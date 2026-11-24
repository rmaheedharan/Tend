// Test support for WI-M2-14 (cloud deadline and retry): a manual test clock, a scripted neutral transport that moves
// the clock as the body is read, a transport that holds its request open, and a test-only cloud adapter that reads
// the transport's body with `StructuredOutputReader`. AC-M2-22, AC-M2-23. P-3, P-4, UX-3.
//
// Everything here is deterministic: no wall clock, no real sleep, no network. The test clock's `sleep` moves its own
// time forward at once (optionally by a little more, to model a late wake-up), or, in the blocking mode, waits until
// the sleeping task is cancelled. The real transport (`TendAI`, WI-M2-M4) and the real adapters (WI-M2-M6, over
// WI-M2-13's `ProviderStreamReader`) are Mac work; `TransportCloudModel` only stands in for them here.

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Test clock

/// A point on the test clock's timeline: a `Duration` from the test's zero.
struct TestInstant: InstantProtocol, CustomStringConvertible {
    var offset: Duration

    init(offset: Duration) { self.offset = offset }

    static func at(_ seconds: Double) -> TestInstant { TestInstant(offset: .seconds(seconds)) }
    static let zero = TestInstant(offset: .zero)

    func advanced(by duration: Duration) -> TestInstant { TestInstant(offset: offset + duration) }
    func duration(to other: TestInstant) -> Duration { other.offset - offset }
    static func < (lhs: TestInstant, rhs: TestInstant) -> Bool { lhs.offset < rhs.offset }

    var description: String { "t=\(Seconds.of(offset))" }
}

enum Seconds {
    /// A duration as `Double` seconds (test-side conversion, independent of `CloudTiming.seconds`).
    static func of(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// A manual clock. `sleep` records the pause and moves time to the wake-up instant (plus `wakeDelay`) at once. In the
/// blocking mode it instead waits until the sleeping task is cancelled (then throws `CancellationError`).
final class ManualClock: Clock, Sendable {
    typealias Instant = TestInstant

    private struct State {
        var now: TestInstant
        var sleeps: [Duration] = []
        var wakeDelay: Duration
        var blocksSleep: Bool
        var isSleeping = false
        var sleepCancelled = false
        var waiter: CheckedContinuation<Void, any Error>?
    }

    private let state: Mutex<State>

    init(now: TestInstant = .zero, wakeDelay: Duration = .zero, blocksSleep: Bool = false) {
        state = Mutex(State(now: now, wakeDelay: wakeDelay, blocksSleep: blocksSleep))
    }

    var now: TestInstant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    /// Every pause asked for, in order (wake-up instant minus the time when `sleep` was called).
    var sleeps: [Duration] { state.withLock { $0.sleeps } }
    var isSleeping: Bool { state.withLock { $0.isSleeping } }

    func advance(by duration: Duration) {
        state.withLock { $0.now = $0.now.advanced(by: duration) }
    }

    func set(_ instant: TestInstant) {
        state.withLock { $0.now = instant }
    }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let blocks = state.withLock { state -> Bool in
            state.sleeps.append(state.now.duration(to: deadline))
            if state.blocksSleep { return true }
            state.now = max(state.now, deadline).advanced(by: state.wakeDelay)
            return false
        }
        guard blocks else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.sleepCancelled { return true }
                    state.waiter = continuation
                    state.isSleeping = true
                    return false
                }
                if resumeNow { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                state.sleepCancelled = true
                state.isSleeping = false
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(throwing: CancellationError())
        }
    }
}

/// Waits for `condition` by yielding (no wall-clock sleep), up to a fixed number of turns.
func yieldUntil(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<200_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// A counter shared with a task.
final class SharedCount: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func add() { count.withLock { $0 += 1 } }
}

// MARK: - Scripted transport

/// One step of a scripted attempt, run when the reader asks for the next body chunk.
enum TransportStep: Sendable {
    /// The time this step takes on the test clock (the server's or network's time).
    case wait(Duration)
    case chunk([UInt8])
    case fail(CloudTransportFailure)
    case error(any Error & Sendable)
    case finish
}

/// One `send` the transport saw.
struct TransportSend: Sendable {
    let request: CloudRequest
    let timeouts: CloudAttemptTimeouts
    let at: TestInstant
}

/// A neutral transport that replays one script per attempt. Steps run as the body is read (pull-based), so the clock
/// moves exactly when the reader waits. An attempt beyond the scripts answers `unexpectedResponse`.
final class ScriptedTransport: CloudTransport {
    private final class Cursor: Sendable {
        let index = Mutex(0)
        func take(_ steps: [TransportStep]) -> TransportStep? {
            index.withLock { index in
                guard index < steps.count else { return nil }
                defer { index += 1 }
                return steps[index]
            }
        }
    }

    let clock: ManualClock
    let attempts: [[TransportStep]]
    private let recorded = Mutex<[TransportSend]>([])

    init(clock: ManualClock, attempts: [[TransportStep]]) {
        self.clock = clock
        self.attempts = attempts
    }

    var sends: [TransportSend] { recorded.withLock { $0 } }

    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        let index = recorded.withLock { sends -> Int in
            sends.append(TransportSend(request: request, timeouts: timeouts, at: clock.now))
            return sends.count - 1
        }
        let steps = index < attempts.count ? attempts[index] : [.fail(CloudTransportFailure(.unexpectedResponse))]
        let cursor = Cursor()
        let stepClock = self.clock
        return AsyncThrowingStream(unfolding: {
            while let step = cursor.take(steps) {
                switch step {
                case let .wait(duration): stepClock.advance(by: duration)
                case let .chunk(bytes): return bytes
                case let .fail(failure): throw failure
                case let .error(error): throw error
                case .finish: return nil
                }
            }
            return nil
        })
    }
}

/// A transport whose first attempt yields the given chunks and then stays open until its stream is terminated. Records
/// how many sends there were and how many streams ended (the termination handler, adapter contract part 3).
final class HoldingTransport: CloudTransport {
    private struct State {
        var sends = 0
        var terminations = 0
    }

    private final class Box: Sendable {
        let state = Mutex(State())
    }

    let chunks: [[UInt8]]
    private let box = Box()

    init(chunks: [[UInt8]] = []) { self.chunks = chunks }

    var sends: Int { box.state.withLock { $0.sends } }
    var terminations: Int { box.state.withLock { $0.terminations } }

    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        box.state.withLock { $0.sends += 1 }
        let (stream, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        for chunk in chunks { continuation.yield(chunk) }
        continuation.onTermination = { [box] _ in box.state.withLock { $0.terminations += 1 } }
        return stream
    }
}

// MARK: - Fixtures

enum TransportFixture {
    /// A built request (the fake key; the stream fixtures' input and rooms).
    static func request(_ provider: CloudProvider = .openAI) -> CloudRequest {
        let input = CloudPayloadInput(capture: StreamFixtures.input, roomNames: ["Kitchen", "Bathroom"],
                                      shortlistTitles: [])
        do {
            return try CloudPayloadBuilder.request(input, model: CloudModel.defaultModel(for: provider),
                                                   key: PayloadFixture.fakeKey)
        } catch {
            Issue.record("the payload builder refused the fixture request: \(error)")
            preconditionFailure("fixture request")
        }
    }

    static func failure(_ reason: CloudFailureReason, retryAfter: String? = nil) -> CloudTransportFailure {
        CloudTransportFailure(reason, retryAfter: retryAfter)
    }

    /// Reads a whole body: the chunks received, then how it ended (nil: normally).
    static func read<C: Clock>(_ body: CloudResponseBody<C>) async -> (chunks: [[UInt8]], end: (any Error)?) {
        var chunks: [[UInt8]] = []
        do {
            for try await chunk in body { chunks.append(chunk) }
            return (chunks, nil)
        } catch {
            return (chunks, error)
        }
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// One complete item for `StreamFixtures.input` in the cloud output schema (every rule-(a) field finished).
    static func itemJSON(_ title: String) -> String {
        #"{"title":""# + title + #"","kind":"oneOff","room":"Kitchen","effort":"normal","isCritical":false,"#
            + #""isDeepClean":false,"isWeatherDependent":false,"time":{"anchor":"none"},"#
            + #""sourcePhrase":"dishwasher pods"}"#
    }

    /// A whole output with these titles.
    static func outputJSON(_ titles: [String]) -> String {
        #"{"items":["# + titles.map(itemJSON).joined(separator: ",") + "]}"
    }
}

// MARK: - Test-only cloud adapter

/// A stand-in for the `TendAI` cloud adapter (WI-M2-M6): builds the request, reads the body through
/// `CloudResponseBody` (deadline and retry) and turns it into snapshots with `StructuredOutputReader` (the real adapter
/// uses WI-M2-13's `ProviderStreamReader`). It follows the adapter contract: yield, finish normally, or throw a
/// `ModelStopReason`; cancel the work in `onTermination`.
struct TransportCloudModel: IngestionModel {
    let provider: CloudProvider
    let transport: any CloudTransport
    let clock: ManualClock
    let start: TestInstant

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let built: CloudRequest
        do {
            built = try CloudPayloadBuilder.request(CloudPayloadInput(request),
                                                    model: CloudModel.defaultModel(for: provider),
                                                    key: PayloadFixture.fakeKey)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: ModelStopReason.otherModelError) }
        }
        let body = CloudResponseBody(request: built, transport: transport, clock: clock, start: start)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var reader = StructuredOutputReader()
                do {
                    for try await chunk in body {
                        continuation.yield(try reader.append(bytes: chunk))
                    }
                    continuation.yield(try reader.finish())
                    continuation.finish()
                } catch let error as PartialJSONError {
                    let reason: ModelStopReason = error == .cutShort ? .outputCutShort : .unreadableOutput
                    continuation.finish(throwing: reason)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
