// WI-M2-14: the cloud deadline and the single retry, over the neutral `CloudTransport` (N-2). AC-M2-22 (Linux
// arithmetic: timeouts and retry rule, T-17, T-28, Q22) and AC-M2-23 (Linux: the outcome, plain note and retry decisions
// over a neutral failure reason, T-18). FR-A1, P-3, P-4, UX-3.
//
// The rule under test (brief AC-M2-22, Q22):
// - Deadline 10.0 s from the moment the pipeline receives the input, on an injected clock.
// - Each attempt: resource timeout = time left; request (idle) timeout = min(time left, 4.0 s).
// - One retry, only for 429/5xx, after a pause p = max(0.5 s, `Retry-After` delta-seconds; missing or unreadable = 0),
//   and only if ≥ 3.0 s are left before the deadline after the pause.
// - Nothing is queued or retried in the background (AC-M2-23, ADR-0005 Decision 7).
// All tests use the manual `ManualClock`: no wall clock, no real sleep.

import Foundation
import Synchronization
import Testing
import TendCore
import TendSourceScan
@testable import TendIngestion

private typealias T = TransportFixture

// MARK: - The numbers and the pure rules

@Suite("AC-M2-22 deadline arithmetic (T-17, Q22): the numbers and the per-attempt timeouts")
struct CloudTimingTests {

    @Test("AC-M2-22 / Q22: the deadline is 10.0 s, the idle cap 4.0 s, the shortest pause 0.5 s, the retry floor 3.0 s")
    func numbers() {
        #expect(CloudTiming.captureDeadline == .seconds(10))
        #expect(CloudTiming.requestIdleLimit == .seconds(4))
        #expect(CloudTiming.minimumRetryPause == .milliseconds(500))
        #expect(CloudTiming.minimumTimeLeftForRetry == .seconds(3))
        #expect(CloudTiming.maximumAttempts == 2)
    }

    struct TimeoutCase: Sendable, CustomTestStringConvertible {
        let timeLeft: Duration
        let resource: Double
        let request: Double
        var testDescription: String { "left \(Seconds.of(timeLeft)) s" }
    }

    static let timeoutCases: [TimeoutCase] = [
        TimeoutCase(timeLeft: .seconds(10), resource: 10, request: 4),
        TimeoutCase(timeLeft: .milliseconds(7_500), resource: 7.5, request: 4),
        TimeoutCase(timeLeft: .milliseconds(4_001), resource: 4.001, request: 4),
        TimeoutCase(timeLeft: .seconds(4), resource: 4, request: 4),
        TimeoutCase(timeLeft: .milliseconds(3_999), resource: 3.999, request: 3.999),
        TimeoutCase(timeLeft: .seconds(3), resource: 3, request: 3),
        TimeoutCase(timeLeft: .milliseconds(250), resource: 0.25, request: 0.25),
        TimeoutCase(timeLeft: .nanoseconds(1), resource: 1e-9, request: 1e-9),
    ]

    @Test("AC-M2-22: resource timeout = time left; request timeout = min(time left, 4.0 s)", arguments: timeoutCases)
    func timeouts(_ cell: TimeoutCase) {
        let timeouts = CloudTiming.timeouts(timeLeft: cell.timeLeft)
        #expect(timeouts == CloudAttemptTimeouts(resource: cell.resource, request: cell.request))
        #expect(timeouts.request <= timeouts.resource)
        #expect(timeouts.request <= 4.0)
    }

    @Test("AC-M2-22: seconds conversion is exact for the rule's values and keeps sub-second parts")
    func secondsConversion() {
        #expect(CloudTiming.seconds(.seconds(10)) == 10)
        #expect(CloudTiming.seconds(.milliseconds(500)) == 0.5)
        #expect(CloudTiming.seconds(.milliseconds(3_250)) == 3.25)
        #expect(CloudTiming.seconds(.zero) == 0)
        #expect(CloudTiming.seconds(.seconds(-2)) == -2)
    }
}

@Suite("AC-M2-22 Retry-After (T-28): delta-seconds only; missing or unreadable counts as 0")
struct RetryAfterFieldTests {

    static let cases: [(String?, Int)] = [
        (nil, 0), ("", 0), ("0", 0), ("1", 1), ("2", 2), ("7", 7), ("120", 120), ("007", 7),
        (" 5", 5), ("5 ", 5), ("\t3\t", 3), ("  12  ", 12),
        // Not delta-seconds: read as 0.
        ("1.5", 0), ("-1", 0), ("+3", 0), ("1e2", 0), ("0x10", 0), ("5s", 0), ("5, 6", 0), ("5 6", 0), ("abc", 0),
        ("Wed, 21 Oct 2015 07:28:00 GMT", 0), ("\u{0663}", 0), ("\u{FF11}", 0), (" ", 0), ("\n5", 0), ("5\n", 0),
        ("inf", 0), ("nan", 0), ("\u{00A0}5", 0),
        // Very large values are readable; they are capped (any value above the deadline means no retry).
        ("999999999", 999_999_999), ("1000000000", 999_999_999), ("99999999999999999999999999", 999_999_999),
        ("0000000000000000000004", 4),
    ]

    @Test("AC-M2-22 / T-28: Retry-After field values", arguments: cases)
    func delaySeconds(_ value: String?, _ expected: Int) {
        #expect(RetryAfterField.delaySeconds(value) == expected, "\(String(describing: value))")
    }
}

@Suite("AC-M2-22 / AC-M2-23 the retry rule (T-28, Q22): one retry, 429/5xx only, inside the deadline")
struct CloudRetryRuleTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let label: String
        let failure: CloudTransportFailure
        let attempt: Int
        let bodyStarted: Bool
        let timeLeft: Duration
        let pause: Duration?
        var testDescription: String { label }
    }

    static func c(_ label: String, _ reason: CloudFailureReason, retryAfter: String? = nil, attempt: Int = 1,
                  bodyStarted: Bool = false, left: Duration, pause: Duration?) -> Case {
        Case(label: label, failure: T.failure(reason, retryAfter: retryAfter), attempt: attempt,
             bodyStarted: bodyStarted, timeLeft: left, pause: pause)
    }

    static let cases: [Case] = [
        c("429, no Retry-After, 10 s left: 0.5 s", .rateLimited, left: .seconds(10), pause: .milliseconds(500)),
        c("5xx, no Retry-After, 10 s left: 0.5 s", .serviceUnavailable, left: .seconds(10), pause: .milliseconds(500)),
        c("429, Retry-After 0: 0.5 s", .rateLimited, retryAfter: "0", left: .seconds(10), pause: .milliseconds(500)),
        c("429, Retry-After 1: 1 s", .rateLimited, retryAfter: "1", left: .seconds(10), pause: .seconds(1)),
        c("5xx, Retry-After 2: 2 s", .serviceUnavailable, retryAfter: "2", left: .seconds(10), pause: .seconds(2)),
        c("429, unreadable Retry-After: 0.5 s", .rateLimited, retryAfter: "soon", left: .seconds(10),
          pause: .milliseconds(500)),
        c("429, HTTP-date Retry-After: 0.5 s", .rateLimited, retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT",
          left: .seconds(10), pause: .milliseconds(500)),
        c("Retry-After 7 with 10 s left: exactly 3.0 s after, retry", .rateLimited, retryAfter: "7",
          left: .seconds(10), pause: .seconds(7)),
        c("Retry-After 8 with 10 s left: 2.0 s after, no retry", .rateLimited, retryAfter: "8", left: .seconds(10),
          pause: nil),
        c("3.5 s left: exactly 3.0 s after the 0.5 s pause, retry", .serviceUnavailable, left: .milliseconds(3_500),
          pause: .milliseconds(500)),
        c("3.499 s left: under 3.0 s after the pause, no retry", .serviceUnavailable, left: .milliseconds(3_499),
          pause: nil),
        c("3.0 s left: 2.5 s after the pause, no retry", .rateLimited, left: .seconds(3), pause: nil),
        c("no time left: no retry", .rateLimited, left: .zero, pause: nil),
        c("time already past: no retry", .rateLimited, left: .seconds(-1), pause: nil),
        c("huge Retry-After: no retry", .rateLimited, retryAfter: "99999999999999999999", left: .seconds(10),
          pause: nil),
        c("second attempt: never again", .rateLimited, attempt: 2, left: .seconds(9), pause: nil),
        c("third attempt: never", .serviceUnavailable, attempt: 3, left: .seconds(9), pause: nil),
        c("after body bytes: no retry", .rateLimited, bodyStarted: true, left: .seconds(9), pause: nil),
        c("offline: no retry", .offline, left: .seconds(10), pause: nil),
        c("timeout: no retry", .timedOut, left: .seconds(10), pause: nil),
        c("DNS: no retry", .hostNotFound, left: .seconds(10), pause: nil),
        c("TLS: no retry", .secureConnectionUnavailable, left: .seconds(10), pause: nil),
        c("401/403: no retry", .keyNotAccepted, retryAfter: "1", left: .seconds(10), pause: nil),
        c("refused before sending: no retry", .requestNotSent, left: .seconds(10), pause: nil),
        c("other status: no retry", .unexpectedResponse, retryAfter: "1", left: .seconds(10), pause: nil),
    ]

    @Test("AC-M2-22 / AC-M2-23: the pause before the one retry, or no retry", arguments: cases)
    func pause(_ cell: Case) {
        let pause = CloudRetryRule.pause(after: cell.failure, attempt: cell.attempt, bodyStarted: cell.bodyStarted,
                                         timeLeft: cell.timeLeft)
        #expect(pause == cell.pause, "\(cell.label)")
    }

    @Test("AC-M2-23: only 429 (rateLimited) and 5xx (serviceUnavailable) allow the retry")
    func retryableReasons() {
        #expect(Set(CloudFailureReason.allCases.filter(\.allowsRetry)) == [.rateLimited, .serviceUnavailable])
    }
}

@Suite("AC-M2-23 neutral failure reasons to outcomes (T-18): the mapping and calm names")
struct CloudFailureReasonTests {

    static let mapping: [(CloudFailureReason, ModelStopReason)] = [
        (.offline, .offline), (.timedOut, .timedOut), (.hostNotFound, .hostNotFound),
        (.secureConnectionUnavailable, .secureConnectionUnavailable), (.keyNotAccepted, .keyNotAccepted),
        (.rateLimited, .rateLimited), (.serviceUnavailable, .serviceUnavailable),
        (.requestNotSent, .otherModelError), (.unexpectedResponse, .otherModelError),
    ]

    @Test("AC-M2-23: each transport failure maps to one neutral stop reason (the brief's case table)",
          arguments: mapping)
    func stopReason(_ reason: CloudFailureReason, _ expected: ModelStopReason) {
        #expect(reason.stopReason == expected)
        #expect(CloudTransportFailure(reason, retryAfter: "3").stopReason == expected)
    }

    @Test("AC-M2-23: the mapping table covers every reason")
    func complete() {
        #expect(Set(Self.mapping.map(\.0)) == Set(CloudFailureReason.allCases))
        #expect(CloudFailureReason.allCases.count == 9)
    }

    @Test("AC-M2-23 / AC-M2-12: no failure reason or transport type name contains a banned token (none blames the user, T-18)")
    func calmNames() {
        let banned = Set(BannedTokens.all)
        var names = CloudFailureReason.allCases.map { "\($0)" }
        names += ["CloudTransport", "CloudTransportFailure", "CloudFailureReason", "CloudAttemptTimeouts",
                  "CloudTiming", "CloudRetryRule", "RetryAfterField", "CloudResponseBody", "captureDeadline",
                  "requestIdleLimit", "minimumRetryPause", "minimumTimeLeftForRetry", "maximumAttempts"]
        names.append("\(CloudTransportFailure(.rateLimited, retryAfter: "2"))")
        for name in names {
            let words = name.split { !$0.isLetter }.flatMap { SourceScanner.subTokens(of: String($0)) }
            let hits = words.map { $0.lowercased() }.filter(banned.contains)
            #expect(hits.isEmpty, "\(name): \(hits)")
        }
    }
}

// MARK: - The attempts over the transport

@Suite("AC-M2-22 / AC-M2-23 CloudResponseBody: attempts, timeouts and the single retry on the injected clock")
struct CloudResponseBodyTests {

    private static func body(_ transport: any CloudTransport, _ clock: ManualClock,
                             start: TestInstant = .zero) -> CloudResponseBody<ManualClock> {
        CloudResponseBody(request: T.request(), transport: transport, clock: clock, start: start)
    }

    @Test("AC-M2-22: a first attempt that answers is passed through, once, with (10, 4) when it starts at receipt")
    func success() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[
            .wait(.milliseconds(300)), .chunk(T.bytes("ab")), .wait(.milliseconds(200)), .chunk(T.bytes("cd")),
            .finish,
        ]])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end == nil)
        #expect(result.chunks == [T.bytes("ab"), T.bytes("cd")])
        #expect(transport.sends.count == 1)
        #expect(transport.sends.first?.timeouts == CloudAttemptTimeouts(resource: 10, request: 4))
        #expect(transport.sends.first?.request == T.request())
        #expect(clock.sleeps.isEmpty)
    }

    @Test("AC-M2-22: the deadline runs from receipt of the input, not from the send (2.5 s gone: 7.5 s left)")
    func deadlineFromReceipt() async {
        let clock = ManualClock(now: .at(102.5))
        let transport = ScriptedTransport(clock: clock, attempts: [[.finish]])
        let body = Self.body(transport, clock, start: .at(100))
        #expect(body.deadline == .at(110))
        _ = await T.read(body)
        #expect(transport.sends.map(\.timeouts) == [CloudAttemptTimeouts(resource: 7.5, request: 4)])
    }

    @Test("AC-M2-22: with no time left at the start nothing is sent; the body ends timedOut",
          arguments: [10.0, 10.5, 30.0])
    func noTimeLeft(_ elapsed: Double) async {
        let clock = ManualClock(now: .at(elapsed))
        let transport = ScriptedTransport(clock: clock, attempts: [[.finish]])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end as? ModelStopReason == .timedOut)
        #expect(transport.sends.isEmpty)
    }

    @Test("AC-M2-22 / AC-M2-23: 429 at 1.0 s, no Retry-After: pause 0.5 s, retry at 1.5 s with (8.5, 4); its body is read")
    func retryAfterRateLimit() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.seconds(1)), .fail(T.failure(.rateLimited))],
            [.wait(.milliseconds(400)), .chunk(T.bytes("ok")), .finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end == nil)
        #expect(result.chunks == [T.bytes("ok")])
        #expect(clock.sleeps == [.milliseconds(500)])
        #expect(transport.sends.map(\.at) == [.at(0), .at(1.5)])
        #expect(transport.sends.map(\.timeouts) == [CloudAttemptTimeouts(resource: 10, request: 4),
                                                    CloudAttemptTimeouts(resource: 8.5, request: 4)])
        #expect(transport.sends.allSatisfy { $0.request == T.request() })
    }

    @Test("AC-M2-22: 503 at 1.0 s with Retry-After 2: pause 2 s, retry at 3.0 s with (7, 4)")
    func retryAfterServiceUnavailable() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.seconds(1)), .fail(T.failure(.serviceUnavailable, retryAfter: "2"))],
            [.chunk(T.bytes("x")), .finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end == nil)
        #expect(clock.sleeps == [.seconds(2)])
        #expect(transport.sends.map(\.at) == [.at(0), .at(3)])
        #expect(transport.sends.last?.timeouts == CloudAttemptTimeouts(resource: 7, request: 4))
    }

    @Test("AC-M2-23: a second 429/5xx ends the body with its reason; exactly 2 sends, 1 pause (never a third)",
          arguments: [(CloudFailureReason.rateLimited, CloudFailureReason.rateLimited),
                      (.rateLimited, .serviceUnavailable), (.serviceUnavailable, .rateLimited),
                      (.serviceUnavailable, .offline)])
    func secondFailure(_ first: CloudFailureReason, _ second: CloudFailureReason) async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.fail(T.failure(first))], [.fail(T.failure(second, retryAfter: "0"))], [.chunk(T.bytes("never"))],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end as? ModelStopReason == second.stopReason)
        #expect(result.chunks.isEmpty)
        #expect(transport.sends.count == 2)
        #expect(clock.sleeps.count == 1)
    }

    @Test("AC-M2-22 boundary: 429 at 6.5 s leaves exactly 3.0 s after the pause: retry with (3, 3)")
    func boundaryRetry() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.milliseconds(6_500)), .fail(T.failure(.rateLimited))], [.finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end == nil)
        #expect(transport.sends.map(\.at) == [.at(0), .at(7)])
        #expect(transport.sends.last?.timeouts == CloudAttemptTimeouts(resource: 3, request: 3))
    }

    @Test("AC-M2-22 boundary: 429 at 6.501 s leaves under 3.0 s after the pause: no pause, no retry, rateLimited")
    func boundaryNoRetry() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.milliseconds(6_501)), .fail(T.failure(.rateLimited))], [.finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end as? ModelStopReason == .rateLimited)
        #expect(transport.sends.count == 1)
        #expect(clock.sleeps.isEmpty)   // no needless wait when the retry cannot happen
    }

    @Test("AC-M2-22: Retry-After 7 at 0 s leaves exactly 3.0 s: retry; Retry-After 8 leaves 2.0 s: no retry",
          arguments: [("7", true), ("8", false), ("6", true), ("9", false)])
    func retryAfterHonoured(_ value: String, _ retries: Bool) async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.fail(T.failure(.serviceUnavailable, retryAfter: value))], [.finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(transport.sends.count == (retries ? 2 : 1))
        #expect(clock.sleeps == (retries ? [.seconds(Int(value) ?? 0)] : []))
        if retries {
            #expect(result.end == nil)
        } else {
            #expect(result.end as? ModelStopReason == .serviceUnavailable)
        }
    }

    @Test("AC-M2-22: the 3.0 s rule is checked again after the pause (a late wake-up leaves under 3.0 s: no retry)")
    func recheckAfterPause() async {
        let clock = ManualClock(wakeDelay: .milliseconds(1))
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.milliseconds(6_500)), .fail(T.failure(.rateLimited))], [.finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(clock.sleeps == [.milliseconds(500)])
        #expect(result.end as? ModelStopReason == .rateLimited)
        #expect(transport.sends.count == 1)
    }

    @Test("AC-M2-23: every other transport failure ends the body at once with its neutral reason; one send, no pause",
          arguments: [CloudFailureReason.offline, .timedOut, .hostNotFound, .secureConnectionUnavailable,
                      .keyNotAccepted, .requestNotSent, .unexpectedResponse])
    func noRetryFailures(_ reason: CloudFailureReason) async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.wait(.milliseconds(100)), .fail(T.failure(reason, retryAfter: "0"))], [.finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end as? ModelStopReason == reason.stopReason)
        #expect(transport.sends.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test("AC-M2-23: a 429/5xx after body bytes is not retried (the reader already has them); the bytes stay")
    func noRetryAfterBody() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [
            [.chunk(T.bytes("part")), .fail(T.failure(.serviceUnavailable))], [.chunk(T.bytes("again")), .finish],
        ])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.chunks == [T.bytes("part")])
        #expect(result.end as? ModelStopReason == .serviceUnavailable)
        #expect(transport.sends.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test("AC-M2-22: a chunk that arrives at or after the deadline is not read; the body ends timedOut",
          arguments: [10.0, 10.25])
    func chunkAfterDeadline(_ arrival: Double) async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[
            .wait(.seconds(2)), .chunk(T.bytes("early")), .wait(.seconds(arrival - 2)), .chunk(T.bytes("tardy")),
            .finish,
        ]])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.chunks == [T.bytes("early")])
        #expect(result.end as? ModelStopReason == .timedOut)
    }

    @Test("AC-M2-22: a normal end at or after the deadline is timedOut; just before it, it is a normal end",
          arguments: [(9.999, false), (10.0, true)])
    func endAtDeadline(_ arrival: Double, _ timedOut: Bool) async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[
            .chunk(T.bytes("a")), .wait(.milliseconds(Int64((arrival * 1000).rounded()))), .finish,
        ]])
        let result = await T.read(Self.body(transport, clock))
        if timedOut {
            #expect(result.end as? ModelStopReason == .timedOut)
        } else {
            #expect(result.end == nil)
        }
    }

    @Test("AC-M2-23 adapter contract rule 1: a foreign error is otherModelError; a ModelStopReason is not trusted from the transport")
    func foreignErrors() async {
        for error in [CocoaError(.fileNoSuchFile) as any Error & Sendable, ModelStopReason.guardrail] {
            let clock = ManualClock()
            let transport = ScriptedTransport(clock: clock, attempts: [[.error(error)], [.finish]])
            let result = await T.read(Self.body(transport, clock))
            #expect(result.end as? ModelStopReason == .otherModelError)
            #expect(transport.sends.count == 1)
        }
    }

    @Test("AC-M2-23: a CancellationError from the transport is passed on as cancellation, never retried")
    func cancellationFromTransport() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[.error(CancellationError())], [.finish]])
        let result = await T.read(Self.body(transport, clock))
        #expect(result.end is CancellationError)
        #expect(transport.sends.count == 1)
    }

    @Test("IngestionModel contract rule 3 (R24-F7): read inside an already cancelled task, nothing is sent")
    func cancelledBeforeSend() async {
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[.finish]])
        let body = Self.body(transport, clock)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await T.read(body)
        }
        let result = await task.value
        #expect(result.end is CancellationError)
        #expect(transport.sends.isEmpty)
    }

    @Test("AC-M2-23: cancelling during the pause ends at once with cancellation; the retry is never sent")
    func cancelDuringPause() async {
        let clock = ManualClock(blocksSleep: true)
        let transport = ScriptedTransport(clock: clock, attempts: [[.fail(T.failure(.rateLimited))], [.finish]])
        let body = Self.body(transport, clock)
        let task = Task { await T.read(body) }
        let sleeping = await yieldUntil { clock.isSleeping }
        #expect(sleeping)
        task.cancel()
        let result = await task.value
        #expect(result.end is CancellationError)
        #expect(transport.sends.count == 1)
    }

    @Test("AC-M2-23 (no background queue): after the body ends nothing more is sent, and a stopped read releases the transport stream")
    func nothingAfterward() async {
        // 1. After a final failure, asking again gives nil and sends nothing.
        let clock = ManualClock()
        let transport = ScriptedTransport(clock: clock, attempts: [[.fail(T.failure(.offline))], [.finish]])
        var iterator = Self.body(transport, clock).makeAsyncIterator()
        var ends: [String] = []
        for step in 0..<3 {
            if step == 2 { clock.advance(by: .seconds(60)) }
            do {
                ends.append(try await iterator.next().map { "chunk \($0)" } ?? "nil")
            } catch {
                ends.append("\(error)")
            }
        }
        #expect(ends == ["offline", "nil", "nil"])

        // 1b. After a normal end, asking again gives nil and sends nothing.
        let doneClock = ManualClock()
        let done = ScriptedTransport(clock: doneClock, attempts: [[.chunk(T.bytes("a")), .finish], [.finish]])
        var doneIterator = Self.body(done, doneClock).makeAsyncIterator()
        var doneSteps: [String] = []
        for _ in 0..<4 {
            doneSteps.append((try? await doneIterator.next()).flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
                             ?? "nil")
        }
        #expect(doneSteps == ["a", "nil", "nil", "nil"])
        #expect(done.sends.count == 1)
        #expect(transport.sends.count == 1)

        // 2. A consumer cancelled mid-body (after its first chunk, while the transport is still open) ends with
        //    `CancellationError`, never a normal end (review R30-F1), and the transport's stream is ended (its
        //    termination handler).
        let holding = HoldingTransport(chunks: [T.bytes("first")])
        let heldBody = Self.body(holding, ManualClock())
        let received = SharedCount()
        let consumer = Task { () -> (count: Int, end: String) in
            do {
                for try await _ in heldBody { received.add() }
                return (received.value, "normal end")
            } catch {
                return (received.value, error is CancellationError ? "CancellationError" : "\(error)")
            }
        }
        let readFirst = await yieldUntil { received.value == 1 }
        #expect(readFirst)
        consumer.cancel()
        let outcome = await consumer.value
        #expect(outcome.count == 1)
        #expect(outcome.end == "CancellationError")
        let ended = await yieldUntil { holding.terminations == 1 }
        #expect(ended)
        #expect(holding.sends == 1)
    }

    // MARK: Property test

    @Test("AC-M2-22 / AC-M2-23 property: 4,000 seeded scripts keep the rule (≤ 2 sends, retry iff the rule says so, every timeout from the deadline)")
    func property() async {
        let seed: UInt64 = 0x7E9D_0014_0022_0023
        var generator = SplitMix64(seed: seed)
        let reasons = CloudFailureReason.allCases
        for index in 0..<4_000 {
            await Task.yield()  // do not hold a cooperative-pool thread for the whole loop (review R30-F3)
            let startAt = Int64.random(in: 0...5_000, using: &generator)                       // ms on the clock
            let lead = Int64.random(in: 0...12_000, using: &generator)                         // ms from receipt to the read
            let firstTime = Int64.random(in: 0...11_000, using: &generator)                    // ms to the answer
            let firstReason = reasons.randomElement(using: &generator) ?? .rateLimited
            let retryAfter: String? = switch Int.random(in: 0..<5, using: &generator) {
            case 0: nil
            case 1: "soon"
            case 2: String(Int.random(in: 0...12, using: &generator))
            case 3: " \(Int.random(in: 0...4, using: &generator)) "
            default: "1.5"
            }
            let bodyFirst = Bool.random(using: &generator) && Bool.random(using: &generator)
            let wake = Int64.random(in: 0...2, using: &generator) == 0 ? Int64.random(in: 1...800, using: &generator) : 0
            let clock = ManualClock(now: TestInstant(offset: .milliseconds(startAt + lead)),
                                  wakeDelay: .milliseconds(wake))
            let start = TestInstant(offset: .milliseconds(startAt))
            var first: [TransportStep] = [.wait(.milliseconds(firstTime))]
            if bodyFirst { first.append(.chunk(T.bytes("b"))) }
            first.append(.fail(T.failure(firstReason, retryAfter: retryAfter)))
            let transport = ScriptedTransport(clock: clock, attempts: [first, [.chunk(T.bytes("ok")), .finish]])
            let result = await T.read(Self.body(transport, clock, start: start))

            // Independent oracle (milliseconds, integers).
            let deadline = startAt + 10_000
            let sendsFirst = startAt + lead < deadline
            var expectedSends = sendsFirst ? 1 : 0
            var expectedPause: Int64?
            let failAt = startAt + lead + firstTime
            if sendsFirst, !bodyFirst,
               firstReason == .rateLimited || firstReason == .serviceUnavailable {
                let delta = Self.oracleDelta(retryAfter)
                let pause = max(500, delta * 1_000)
                if deadline - (failAt + pause) >= 3_000 {
                    expectedPause = pause
                    if deadline - (failAt + pause + wake) >= 3_000 { expectedSends = 2 }
                }
            }
            let context = "seed \(seed) case \(index): start \(startAt) lead \(lead) first \(firstTime) " +
                "\(firstReason) RA \(String(describing: retryAfter)) body \(bodyFirst) wake \(wake)"
            // A first chunk at or after the deadline ends the body timedOut before the failure is seen.
            if sendsFirst && bodyFirst && failAt >= deadline {
                #expect(transport.sends.count == 1, "\(context)")
                #expect(result.end as? ModelStopReason == .timedOut, "\(context)")
                continue
            }
            #expect(transport.sends.count == expectedSends, "\(context)")
            #expect(clock.sleeps == (expectedPause.map { [Duration.milliseconds($0)] } ?? []), "\(context)")
            for send in transport.sends {
                let left = Seconds.of(send.at.duration(to: TestInstant(offset: .milliseconds(deadline))))
                #expect(send.timeouts.resource == left, "\(context)")
                #expect(send.timeouts.request == min(left, 4.0), "\(context)")
                #expect(left > 0, "\(context)")
            }
            if transport.sends.count == 2 {
                let left = Seconds.of(transport.sends[1].at.duration(to: TestInstant(offset: .milliseconds(deadline))))
                #expect(left >= 3.0, "\(context)")
                #expect(result.end == nil, "\(context)")
            } else if expectedSends == 0 {
                #expect(result.end as? ModelStopReason == .timedOut, "\(context)")
            } else {
                #expect(result.end as? ModelStopReason == firstReason.stopReason, "\(context)")
            }
        }
    }

    /// Independent Retry-After reading for the property test (the generator only makes these shapes).
    private static func oracleDelta(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard !trimmed.isEmpty, trimmed.allSatisfy({ ("0"..."9").contains($0) }) else { return 0 }
        return Int64(trimmed) ?? 0
    }
}

// MARK: - Through the pipeline

@Suite("AC-M2-23 cloud failures through the pipeline over the transport: calm outcomes, input, plain note, the single retry")
struct CloudTransportOutcomeTests {
    typealias F = StreamFixtures
    typealias O = OutcomeFixtures

    struct Cell: Sendable, CustomTestStringConvertible {
        let provider: CloudProvider
        let reason: CloudFailureReason
        var testDescription: String { "\(provider) \(reason)" }
    }

    /// The brief's transport failures (offline, timeout, DNS, TLS, 401/403, 429, 5xx) plus the two "other" reasons.
    static let cells: [Cell] = CloudProvider.allCases.flatMap { provider in
        CloudFailureReason.allCases.map { Cell(provider: provider, reason: $0) }
    }

    private static func run(_ provider: CloudProvider, _ attempts: [[TransportStep]],
                            clock: ManualClock = ManualClock()) async -> (DraftStreamSummary, [DraftStreamEvent], Int) {
        let transport = ScriptedTransport(clock: clock, attempts: attempts)
        let model = TransportCloudModel(provider: provider, transport: transport, clock: clock, start: clock.now)
        var summary = DraftStreamSummary()
        var events: [DraftStreamEvent] = []
        for await event in F.pipeline().events(from: .cloud(provider, model)) {
            summary.apply(event)
            events.append(event)
        }
        return (summary, events, transport.sends.count)
    }

    @Test("AC-M2-23: each transport failure before any draft (and again on the retry for 429/5xx): noModel with the route, the input and the plain note; no draft",
          arguments: cells)
    func beforeAnyDraft(_ cell: Cell) async {
        let failure = T.failure(cell.reason)
        let (summary, events, sends) = await Self.run(cell.provider, [[.fail(failure)], [.fail(failure)]])
        #expect(summary.outcome == .noModel(route: .cloud(cell.provider),
                                            reason: .stoppedBeforeFirstDraft(cell.reason.stopReason),
                                            input: F.input, plainNote: O.plainNote(F.input)))
        #expect(summary.drafts.isEmpty)
        #expect(!events.contains { if case .emitted = $0 { true } else { false } })
        #expect(sends == (cell.reason.allowsRetry ? 2 : 1))
    }

    @Test("AC-M2-23: each transport failure after a draft: interrupted with the route and the input; no plain note; the draft stays; no retry",
          arguments: cells)
    func afterADraft(_ cell: Cell) async {
        let partial = #"{"items":["# + T.itemJSON("Buy dishwasher pods") + #",{"title":"Serv"#
        let (summary, _, sends) = await Self.run(cell.provider, [
            [.chunk(T.bytes(partial)), .fail(T.failure(cell.reason))], [.finish],
        ])
        #expect(summary.outcome == F.interrupted(cell.reason.stopReason, discarded: .stoppedBeforeComplete,
                                                 route: .cloud(cell.provider)))
        #expect(summary.outcome?.plainNote == nil)
        #expect(summary.outcome?.input == F.input)
        #expect(summary.drafts.map(\.title) == ["Buy dishwasher pods"])
        #expect(sends == 1)
    }

    @Test("AC-M2-23: 429 then a good answer: completed with the drafts, no plain note; 2 sends, one 0.5 s pause",
          arguments: CloudProvider.allCases)
    func retryThenAnswer(_ provider: CloudProvider) async {
        let clock = ManualClock()
        let output = T.outputJSON(["Buy dishwasher pods", "Service the AC"])
        let (summary, _, sends) = await Self.run(provider, [
            [.wait(.milliseconds(800)), .fail(T.failure(.rateLimited))],
            [.chunk(T.bytes(String(output.prefix(40)))), .chunk(T.bytes(String(output.dropFirst(40)))), .finish],
        ], clock: clock)
        #expect(summary.outcome == .completed(route: .cloud(provider)))
        #expect(summary.drafts.map(\.title) == ["Buy dishwasher pods", "Service the AC"])
        #expect(summary.outcome?.plainNote == nil)
        #expect(sends == 2)
        #expect(clock.sleeps == [.milliseconds(500)])
    }

    @Test("AC-M2-23: a malformed body (from the reader) is noModel(unreadableOutput) with the plain note; not retried")
    func malformedBody() async {
        let (summary, _, sends) = await Self.run(.anthropic, [[.chunk(T.bytes("{\"items\": [tru")), .finish]])
        // A finished-but-broken JSON prefix: the reader reports it once the bad byte arrives or at the end.
        #expect(summary.outcome?.plainNote == O.plainNote(F.input))
        if case let .noModel(_, reason, input, _)? = summary.outcome {
            #expect(reason == .stoppedBeforeFirstDraft(.unreadableOutput)
                    || reason == .stoppedBeforeFirstDraft(.outputCutShort))
            #expect(input == F.input)
        } else {
            Issue.record("expected noModel, got \(String(describing: summary.outcome))")
        }
        let (bad, _, badSends) = await Self.run(.openAI, [[.chunk(T.bytes("{\"items\": [}")), .finish]])
        #expect(bad.outcome == .noModel(route: .cloud(.openAI), reason: .stoppedBeforeFirstDraft(.unreadableOutput),
                                        input: F.input, plainNote: O.plainNote(F.input)))
        #expect(sends == 1 && badSends == 1)
    }

    @Test("AC-M2-22 / AC-M2-23: an answer cut by the deadline after a draft is interrupted(timedOut); before one, noModel(timedOut) with the plain note")
    func deadlineThroughPipeline() async {
        let output = T.outputJSON(["Buy dishwasher pods", "Service the AC"])
        let cut = output.index(output.startIndex, offsetBy: output.count - 30)
        let (after, _, _) = await Self.run(.gemini, [[
            .wait(.seconds(2)), .chunk(T.bytes(String(output[..<cut]))), .wait(.seconds(9)),
            .chunk(T.bytes(String(output[cut...]))), .finish,
        ]])
        #expect(after.outcome == F.interrupted(.timedOut, discarded: .stoppedBeforeComplete, route: .cloud(.gemini)))
        #expect(after.drafts.map(\.title) == ["Buy dishwasher pods"])

        let (before, _, _) = await Self.run(.gemini, [[.wait(.seconds(11)), .chunk(T.bytes(output)), .finish]])
        #expect(before.outcome == .noModel(route: .cloud(.gemini), reason: .stoppedBeforeFirstDraft(.timedOut),
                                           input: F.input, plainNote: O.plainNote(F.input)))
    }
}
