// Test support for WI-M2-09 (routing and consent): a neutral recording mock transport, mock on-device and cloud
// models over it, the stored-state fixtures of the plan's route matrix, and bounded waiting. AC-M2-10, AC-M2-18,
// AC-M2-19. P-1, P-2, P-3.
//
// No real network: the "transport" is a recorder. A mock cloud model records one request when its snapshot stream is
// created (that is when a real adapter starts its request), and records how the stream ended (its termination
// handler), which is the model side of "an in-flight cloud request is cancelled" (IngestionModel adapter contract,
// part 3). WI-M2-14's neutral `CloudTransport` protocol replaces the recorder's role inside the real adapters later.

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Recording mock transport

/// One recorded cloud request (the neutral values a request is built from; the key is recorded only to prove which
/// key was used, never formatted).
struct RecordedRequest: Sendable {
    let provider: CloudProvider
    let key: APIKey
    let input: String
    let roomNames: [String]
}

/// Records every request a mock cloud model starts, and how each one ended. Optionally holds the stream open so a
/// test can turn cloud off while the request is in flight.
final class RecordingTransport: Sendable {
    enum Mode: Sendable {
        /// Answer at once with one complete item, then finish.
        case answerOneItem
        /// Keep the request open; the test drives it with `send(_:)`.
        case hold
    }

    private struct State {
        var requests: [RecordedRequest] = []
        var ends: [String] = []
        var open: [AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation] = []
    }

    let mode: Mode
    private let state = Mutex(State())

    init(mode: Mode = .answerOneItem) { self.mode = mode }

    var requests: [RecordedRequest] { state.withLock { $0.requests } }
    var requestCount: Int { state.withLock { $0.requests.count } }
    /// How each request's stream ended: "cancelled" or "finished".
    var ends: [String] { state.withLock { $0.ends } }

    /// Sends a snapshot on every held request (no effect on ended ones).
    func send(_ items: [ItemSnapshot]) {
        let open = state.withLock { $0.open }
        for continuation in open { continuation.yield(IngestionSnapshot(items: items)) }
    }

    /// Finishes every held request normally.
    func finishHeld() {
        let open = state.withLock { $0.open }
        for continuation in open { continuation.finish() }
    }

    func start(_ request: RecordedRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [self] termination in
                let text = switch termination {
                case .cancelled: "cancelled"
                case .finished: "finished"
                @unknown default: "unknown"
                }
                self.state.withLock { $0.ends.append(text) }
            }
            state.withLock {
                $0.requests.append(request)
                if case .hold = mode { $0.open.append(continuation) }
            }
            if case .answerOneItem = mode {
                continuation.yield(IngestionSnapshot(items: [StreamFixtures.full("Buy dishwasher pods")]))
                continuation.finish()
            }
        }
    }
}

/// A mock cloud model: one per request, built by `RecordingCloudModels` with the provider and key the router read.
struct MockCloudModel: IngestionModel {
    let provider: CloudProvider
    let key: APIKey
    let transport: RecordingTransport

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        transport.start(RecordedRequest(provider: provider, key: key, input: request.input,
                                        roomNames: request.roomNames))
    }
}

/// The cloud model source for the tests: records every provider it was asked for, builds mock cloud models.
final class RecordingCloudModels: CloudModelSource {
    let transport: RecordingTransport
    private let asked = Mutex<[CloudProvider]>([])

    init(transport: RecordingTransport) { self.transport = transport }

    var askedProviders: [CloudProvider] { asked.withLock { $0 } }

    func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
        asked.withLock { $0.append(provider) }
        return MockCloudModel(provider: provider, key: key, transport: transport)
    }
}

/// The on-device source for the tests: a fixed availability and a scripted model.
final class FixedOnDevice: OnDeviceModelSource {
    let current: OnDeviceAvailability
    let scripted: ScriptedModel

    init(_ availability: OnDeviceAvailability,
         steps: [ScriptStep] = [.snapshot([StreamFixtures.full("Buy dishwasher pods")]), .finish]) {
        self.current = availability
        self.scripted = ScriptedModel(steps)
    }

    func availability() -> OnDeviceAvailability { current }
    func model() -> any IngestionModel { scripted }
}

// MARK: - Stored-state fixtures (plan "Route matrix", S0…S8)

/// One stored cloud state: the selection, the consent records and the stored keys.
struct StoredState: Hashable, Sendable, CustomStringConvertible {
    var selected: CloudProvider?
    var consents: Set<CloudProvider>
    var keys: Set<CloudProvider>
    /// Plan row name, for the log.
    var row: String

    var description: String {
        func names(_ set: Set<CloudProvider>) -> String {
            set.map(\.rawValue).sorted().joined(separator: "+")
        }
        return "\(row)[sel=\(selected?.rawValue ?? "-") consent=\(names(consents)) key=\(names(keys))]"
    }

    /// The fixed key text a fixture stores for a provider (synthetic, holds no secret).
    static func fixtureKey(_ provider: CloudProvider) -> APIKey {
        APIKey("fixture-key-\(provider.rawValue)-0123456789")
    }

    func makeStores() -> (InMemoryCloudConsentStore, InMemoryAPIKeyStore) {
        let keyValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.fixtureKey($0)) })
        return (InMemoryCloudConsentStore(selected: selected, consents: consents), InMemoryAPIKeyStore(keys: keyValues))
    }

    /// Whether the plan says cloud is on, and for which provider.
    var expectedCloud: CloudStatus {
        guard let selected, consents.contains(selected), keys.contains(selected) else { return .off }
        return .on(selected)
    }

    /// The keys the plan says remain after a route is chosen (orphan keys, with no consent, are deleted).
    var expectedKeysAfter: Set<CloudProvider> { keys.intersection(consents) }

    /// Every stored state of the plan's matrix: S0, S6 for each Y, S1…S4 for each X, S5, S7, S8 for each X/Y pair.
    static var planRows: [StoredState] {
        let all = CloudProvider.allCases
        var rows: [StoredState] = [StoredState(selected: nil, consents: [], keys: [], row: "S0")]
        for x in all {
            rows.append(StoredState(selected: x, consents: [], keys: [], row: "S1"))
            rows.append(StoredState(selected: x, consents: [x], keys: [], row: "S2"))
            rows.append(StoredState(selected: x, consents: [], keys: [x], row: "S3"))
            rows.append(StoredState(selected: x, consents: [x], keys: [x], row: "S4"))
        }
        for x in all {
            for y in all where y != x {
                rows.append(StoredState(selected: x, consents: [y], keys: [y], row: "S5"))
                rows.append(StoredState(selected: x, consents: [x, y], keys: [x, y], row: "S7"))
                rows.append(StoredState(selected: x, consents: [x], keys: [y], row: "S8"))
            }
        }
        for y in all {
            rows.append(StoredState(selected: nil, consents: [y], keys: [y], row: "S6"))
        }
        return rows
    }

    /// Every combination of selection (none or one of 3), consent subset and key subset: 4 × 8 × 8 = 256 states.
    static var everyState: [StoredState] {
        let all = CloudProvider.allCases
        let subsets: [Set<CloudProvider>] = (0..<8).map { mask in
            Set(all.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        }
        var states: [StoredState] = []
        for selected in [nil] + all.map(Optional.some) {
            for consents in subsets {
                for keys in subsets {
                    states.append(StoredState(selected: selected, consents: consents, keys: keys, row: "any"))
                }
            }
        }
        return states
    }
}

enum RoutingFixtures {
    /// The five availability values of the matrix: available and the four unavailable reasons.
    static let availabilities: [OnDeviceAvailability] =
        [.available] + OnDeviceUnavailableReason.allCases.map { .unavailable($0) }

    /// The route the plan's matrix gives (written out from the plan table, independent of `RouteRules`).
    static func planRoute(_ availability: OnDeviceAvailability, _ preference: RoutePreference,
                          _ cloud: CloudStatus) -> Route {
        switch (cloud, availability, preference) {
        case (.off, .available, _): .onDevice
        case (.off, .unavailable, _): .none
        case (.on, .available, .onDeviceFirst): .onDevice
        case let (.on(x), .available, .alwaysCloud): .cloud(x)
        case let (.on(x), .unavailable, _): .cloud(x)
        }
    }

    static func router(_ state: StoredState, _ availability: OnDeviceAvailability,
                       transport: RecordingTransport = RecordingTransport(),
                       onDeviceSteps: [ScriptStep]? = nil)
        -> (ModelRouter, InMemoryCloudConsentStore, InMemoryAPIKeyStore, RecordingCloudModels, FixedOnDevice) {
        let (consents, keys) = state.makeStores()
        let cloud = RecordingCloudModels(transport: transport)
        let onDevice = onDeviceSteps.map { FixedOnDevice(availability, steps: $0) } ?? FixedOnDevice(availability)
        let router = ModelRouter(onDevice: onDevice, cloudModels: cloud, consents: consents, keys: keys)
        return (router, consents, keys, cloud, onDevice)
    }

    /// The providers whose key is stored now (read through the store protocol).
    static func storedKeys(_ keys: InMemoryAPIKeyStore) async -> Set<CloudProvider> {
        var result: Set<CloudProvider> = []
        for provider in CloudProvider.allCases where await keys.hasKey(for: provider) {
            result.insert(provider)
        }
        return result
    }

    static func storedConsents(_ consents: InMemoryCloudConsentStore) async -> Set<CloudProvider> {
        var result: Set<CloudProvider> = []
        for provider in CloudProvider.allCases where await consents.hasConsent(for: provider) {
            result.insert(provider)
        }
        return result
    }
}

// MARK: - Bounded consumption

/// Reads a routed event sequence with the `BoundedRun` bounds (stops at the first `finished`, asks once more, never
/// reads more than the cap). `onEvent` gets each event as it arrives.
func collectBounded(_ sequence: RoutedDraftEvents, onEvent: @Sendable (Ev) -> Void = { _ in }) async -> BoundedRun {
    var iterator = sequence.makeAsyncIterator()
    var events: [Ev] = []
    while events.count < BoundedRun.cap, let event = await iterator.next() {
        let ev = Ev(event)
        events.append(ev)
        onEvent(ev)
        if case .finished = event {
            let after = await iterator.next()
            return BoundedRun(events: events, afterFinished: after.map(Ev.init), hitCap: false)
        }
    }
    return BoundedRun(events: events, afterFinished: nil, hitCap: events.count >= BoundedRun.cap)
}

/// Waits until `condition` holds, for at most about 5 seconds (5,000 × 1 ms), so a broken rule fails instead of
/// hanging. The logic under test has no clock; this only paces the test's own polling.
func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<5_000 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

/// Events seen so far by a consumer running in another task.
final class SeenEvents: Sendable {
    private let events = Mutex<[Ev]>([])
    func append(_ event: Ev) { events.withLock { $0.append(event) } }
    var all: [Ev] { events.withLock { $0 } }
}

/// Waits (bounded, about 5 seconds) for a consumer running in its own task to see `finished`. If it does not, the
/// consumer is cancelled so the test ends, and `neededCancel` is true, which the caller asserts is false. So a rule
/// that stops a turn-off from ending the capture fails on an assertion instead of hanging.
func awaitConsumer(_ consumer: Task<BoundedRun, Never>, seen: SeenEvents) async -> (run: BoundedRun, neededCancel: Bool) {
    let finished = await eventually { seen.all.contains { if case .finished = $0 { true } else { false } } }
    if !finished { consumer.cancel() }
    return (await consumer.value, !finished)
}
