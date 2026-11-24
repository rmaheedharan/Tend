// AC-M2-18 (Linux part): off by default, consent per provider, the restored-state fixtures (i)–(iii) (T-14), orphan-key
// deletion, and the turn-off semantics (a)–(d) through the neutral recording mock transport and the in-memory key
// store. The real Keychain delete (a) is WI-M2-M5 on the owner-run Mac; the in-memory store is not evidence for it.
// P-2, P-3, P-4. Also the in-memory stores and the `APIKey` formatting rule (AC-M2-21 "never in description", which is
// otherwise WI-M2-M5).

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

/// A key store whose every call fails (a locked or broken Keychain).
struct UnavailableKeyStore: APIKeyStore {
    func hasKey(for provider: CloudProvider) async throws(CloudStoreError) -> Bool { throw .storeUnavailable }
    func key(for provider: CloudProvider) async throws(CloudStoreError) -> APIKey? { throw .storeUnavailable }
    func save(_ key: APIKey, for provider: CloudProvider) async throws(CloudStoreError) { throw .storeUnavailable }
    func deleteKey(for provider: CloudProvider) async throws(CloudStoreError) { throw .storeUnavailable }
}

/// A key store that reads and saves, but cannot delete.
actor UndeletableKeyStore: APIKeyStore {
    var keys: [CloudProvider: APIKey]
    init(keys: [CloudProvider: APIKey]) { self.keys = keys }
    func hasKey(for provider: CloudProvider) -> Bool { keys[provider] != nil }
    func key(for provider: CloudProvider) -> APIKey? { keys[provider] }
    func save(_ key: APIKey, for provider: CloudProvider) { keys[provider] = key }
    func deleteKey(for provider: CloudProvider) throws(CloudStoreError) { throw .notAccessibleNow }
}

/// A consent store that reads, but cannot clear (so only the router's in-memory turn-off holds cloud off).
actor UnclearableConsentStore: CloudConsentStore {
    var selected: CloudProvider?
    var consents: Set<CloudProvider>
    init(selected: CloudProvider?, consents: Set<CloudProvider>) {
        self.selected = selected
        self.consents = consents
    }
    func selectedProvider() -> CloudProvider? { selected }
    func select(_ provider: CloudProvider?) { selected = provider }
    func hasConsent(for provider: CloudProvider) -> Bool { consents.contains(provider) }
    func recordConsent(for provider: CloudProvider) { consents.insert(provider) }
    func clearConsent(for provider: CloudProvider) throws(CloudStoreError) { throw .storeUnavailable }
}

/// A consent store whose reads fail.
struct UnreadableConsentStore: CloudConsentStore {
    func selectedProvider() async throws(CloudStoreError) -> CloudProvider? { throw .storeUnavailable }
    func select(_ provider: CloudProvider?) async throws(CloudStoreError) { throw .storeUnavailable }
    func hasConsent(for provider: CloudProvider) async throws(CloudStoreError) -> Bool { throw .storeUnavailable }
    func recordConsent(for provider: CloudProvider) async throws(CloudStoreError) { throw .storeUnavailable }
    func clearConsent(for provider: CloudProvider) async throws(CloudStoreError) { throw .storeUnavailable }
}

/// A key store whose reads can be held until the test releases them. `key(for:)` waits on every call when
/// `holdKeyRead` is true (the request is "being prepared"); the first `hasKey` waits when `holdFirstHasKey` is true (a
/// route choice is reading the stores). `deleteKey` throws when `deleteFails` is true.
final class SuspendingKeyStore: APIKeyStore {
    /// After `release()` the store is open: later reads do not wait, so a rule that reads again cannot hang a test.
    private let waiting = Mutex<(open: Bool, list: [CheckedContinuation<Void, Never>])>((false, []))
    private let keyReads = Mutex(0)
    private let keyReadsReturned = Mutex(0)
    private let heldHasKey = Mutex(0)
    private let armedHasKey: Mutex<Bool>
    let stored: [CloudProvider: APIKey]
    let holdKeyRead: Bool
    let deleteFails: Bool

    init(keys: [CloudProvider: APIKey], holdKeyRead: Bool = true, holdFirstHasKey: Bool = false,
         deleteFails: Bool = false) {
        self.stored = keys
        self.holdKeyRead = holdKeyRead
        self.armedHasKey = Mutex(holdFirstHasKey)
        self.deleteFails = deleteFails
    }

    /// How many `key(for:)` calls are waiting or have waited.
    var keyCalls: Int { keyReads.withLock { $0 } }
    /// How many `key(for:)` calls have returned (review R30-F3: an event to wait on instead of a timer).
    var returnedKeyCalls: Int { keyReadsReturned.withLock { $0 } }
    /// How many `hasKey` calls are waiting or have waited.
    var heldHasKeyCalls: Int { heldHasKey.withLock { $0 } }

    func release() {
        let all = waiting.withLock { state in
            defer { state = (true, []) }
            return state.list
        }
        for continuation in all { continuation.resume() }
    }

    private func hold(counting counter: borrowing Mutex<Int>) async {
        counter.withLock { $0 += 1 }
        StateChanges.shared.changed()
        await withCheckedContinuation { continuation in
            let resumeNow = waiting.withLock { state in
                if state.open { return true }
                state.list.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func hasKey(for provider: CloudProvider) async throws(CloudStoreError) -> Bool {
        let hold = armedHasKey.withLock { armed in defer { armed = false }; return armed }
        if hold { await self.hold(counting: heldHasKey) }
        return stored[provider] != nil
    }
    func key(for provider: CloudProvider) async throws(CloudStoreError) -> APIKey? {
        if holdKeyRead { await hold(counting: keyReads) }
        defer {
            keyReadsReturned.withLock { $0 += 1 }
            StateChanges.shared.changed()
        }
        return stored[provider]
    }
    func save(_ key: APIKey, for provider: CloudProvider) async throws(CloudStoreError) {}
    func deleteKey(for provider: CloudProvider) async throws(CloudStoreError) {
        if deleteFails { throw .notAccessibleNow }
    }
}

/// A consent store with in-memory behaviour whose first `recordConsent` waits until the test releases it.
final class SuspendingConsentStore: CloudConsentStore {
    private struct State {
        var selected: CloudProvider?
        var consents: Set<CloudProvider> = []
        var armed = true
        var waiting: [CheckedContinuation<Void, Never>] = []
        var held = 0
    }
    private let state = Mutex(State())

    var heldCalls: Int { state.withLock { $0.held } }
    var consentsNow: Set<CloudProvider> { state.withLock { $0.consents } }

    func release() {
        let all = state.withLock { s in defer { s.waiting = [] }; return s.waiting }
        for continuation in all { continuation.resume() }
    }

    func selectedProvider() async throws(CloudStoreError) -> CloudProvider? { state.withLock { $0.selected } }
    func select(_ provider: CloudProvider?) async throws(CloudStoreError) { state.withLock { $0.selected = provider } }
    func hasConsent(for provider: CloudProvider) async throws(CloudStoreError) -> Bool {
        state.withLock { $0.consents.contains(provider) }
    }
    func recordConsent(for provider: CloudProvider) async throws(CloudStoreError) {
        let hold = state.withLock { s in defer { s.armed = false }; return s.armed }
        if hold {
            await withCheckedContinuation { continuation in
                state.withLock { $0.waiting.append(continuation); $0.held += 1 }
                StateChanges.shared.changed()
            }
        }
        state.withLock { _ = $0.consents.insert(provider) }
    }
    func clearConsent(for provider: CloudProvider) async throws(CloudStoreError) {
        state.withLock { _ = $0.consents.remove(provider) }
    }
}

@Suite("AC-M2-18 off by default, consent, restored state (P-3)")
struct CloudConsentStateTests {
    typealias R = RoutingFixtures

    /// Submits one capture with each availability and preference; returns the routes seen.
    func submitEverywhere(_ state: StoredState) async -> (routes: Set<Route>, requests: Int, keysAfter: Set<CloudProvider>) {
        var routes: Set<Route> = []
        var requests = 0
        var keysAfter: Set<CloudProvider> = state.keys
        for availability in R.availabilities {
            for preference in RoutePreference.allCases {
                let transport = RecordingTransport()
                let (router, _, keys, _, _) = R.router(state, availability, transport: transport)
                let run = await collectBounded(await router.events(for: StreamFixtures.pipeline(),
                                                                   preference: preference))
                if case let .finished(outcome)? = run.events.last { routes.insert(outcome.route) }
                requests += transport.requestCount
                keysAfter = await R.storedKeys(keys)
            }
        }
        return (routes, requests, keysAfter)
    }

    @Test("AC-M2-18: a fresh install (no selection, no key, no consent) never routes to the cloud and sends nothing")
    func freshInstall() async {
        let consents = InMemoryCloudConsentStore()
        let keys = InMemoryAPIKeyStore()
        #expect(await consents.selectedProvider() == nil)
        #expect(await R.storedConsents(consents).isEmpty)
        #expect(await R.storedKeys(keys).isEmpty)
        let result = await submitEverywhere(StoredState(selected: nil, consents: [], keys: [], row: "S0"))
        #expect(result.routes == [.onDevice, .none])
        #expect(result.requests == 0)
    }

    @Test("AC-M2-18: every stored state with no consent record for the selected provider never routes to the cloud and sends nothing")
    func noConsentForSelected() async {
        var checked = 0
        for state in StoredState.everyState where state.selected.map({ !state.consents.contains($0) }) ?? true {
            let result = await submitEverywhere(state)
            #expect(!result.routes.contains { if case .cloud = $0 { true } else { false } }, "\(state)")
            #expect(result.requests == 0, "\(state)")
            checked += 1
        }
        // Nothing selected: 64 states; X selected without consent for X: 3 × 4 × 8 = 96.
        #expect(checked == 160)
    }

    @Test("AC-M2-18 restored (i): a key for X with no consent record: never cloud, zero requests, and the key is deleted", arguments: CloudProvider.allCases)
    func restoredKeyWithoutConsent(x: CloudProvider) async {
        let state = StoredState(selected: x, consents: [], keys: [x], row: "S3")
        let result = await submitEverywhere(state)
        #expect(result.routes == [.onDevice, .none])
        #expect(result.requests == 0)
        #expect(result.keysAfter.isEmpty)
        // Deleted the first time a route is chosen.
        let (router, _, keys, _, _) = R.router(state, .unavailable(.deviceNotEligible))
        #expect(await R.storedKeys(keys) == [x])
        _ = await router.route(preference: .alwaysCloud)
        #expect(await R.storedKeys(keys).isEmpty)
    }

    @Test("AC-M2-18 restored (ii): a consent record for X and no key: never cloud, zero requests", arguments: CloudProvider.allCases)
    func restoredConsentWithoutKey(x: CloudProvider) async {
        let result = await submitEverywhere(StoredState(selected: x, consents: [x], keys: [], row: "S2"))
        #expect(result.routes == [.onDevice, .none])
        #expect(result.requests == 0)
    }

    @Test("AC-M2-18 restored (iii): a consent record and a key for Y while X is selected: never cloud, zero requests, Y's key is kept")
    func restoredOtherProvider() async {
        for x in CloudProvider.allCases {
            for y in CloudProvider.allCases where y != x {
                let result = await submitEverywhere(StoredState(selected: x, consents: [y], keys: [y], row: "S5"))
                #expect(result.routes == [.onDevice, .none], "\(x) \(y)")
                #expect(result.requests == 0)
                #expect(result.keysAfter == [y])
            }
        }
    }

    @Test("AC-M2-18: given consent and a key for the selected X, the route is only ever cloud(X), never another provider")
    func onlySelectedProvider() async {
        for x in CloudProvider.allCases {
            let others = Set(CloudProvider.allCases).subtracting([x])
            let state = StoredState(selected: x, consents: Set(CloudProvider.allCases),
                                    keys: Set(CloudProvider.allCases), row: "S7+")
            let result = await submitEverywhere(state)
            #expect(result.routes == [.onDevice, .cloud(x)])
            for other in others { #expect(!result.routes.contains(.cloud(other))) }
        }
    }

    @Test("AC-M2-18: a key store that cannot be read keeps cloud off (fail closed) and sends nothing")
    func unreadableKeyStore() async {
        let transport = RecordingTransport()
        let cloud = RecordingCloudModels(transport: transport)
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.modelNotReady)), cloudModels: cloud,
                                 consents: InMemoryCloudConsentStore(selected: .openAI, consents: [.openAI]),
                                 keys: UnavailableKeyStore())
        #expect(await router.cloudStatus() == .off)
        let run = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud))
        #expect(run.events.last.map { if case .finished(.noModel(.none, _, _, _)) = $0 { true } else { false } } == true)
        #expect(transport.requestCount == 0)
        #expect(cloud.askedProviders.isEmpty)
    }

    @Test("AC-M2-18 restored (i), D2: a key with no consent record that cannot be deleted still never turns cloud on", arguments: CloudProvider.allCases)
    func undeletableOrphanKey(x: CloudProvider) async {
        let transport = RecordingTransport()
        let keys = UndeletableKeyStore(keys: [x: StoredState.fixtureKey(x)])
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: transport),
                                 consents: InMemoryCloudConsentStore(selected: x, consents: []), keys: keys)
        #expect(await router.cloudStatus() == .off)
        for preference in RoutePreference.allCases {
            #expect(await router.route(preference: preference) == .none)
            _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: preference))
        }
        #expect(await keys.hasKey(for: x))
        #expect(transport.requestCount == 0)
    }

    @Test("AC-M2-18: a consent store that cannot be read keeps cloud off (fail closed) and sends nothing")
    func unreadableConsentStore() async {
        let transport = RecordingTransport()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: transport),
                                 consents: UnreadableConsentStore(),
                                 keys: InMemoryAPIKeyStore(keys: [.openAI: StoredState.fixtureKey(.openAI)]))
        #expect(await router.cloudStatus() == .off)
        #expect(await router.route(preference: .alwaysCloud) == .none)
        _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud))
        #expect(transport.requestCount == 0)
    }

    @Test("AC-M2-18: turning cloud on records consent, stores the key and selects the provider; only then is the route cloud")
    func turnOn() async throws {
        let consents = InMemoryCloudConsentStore()
        let keys = InMemoryAPIKeyStore()
        let transport = RecordingTransport()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: transport), consents: consents,
                                 keys: keys)
        #expect(await router.route(preference: .onDeviceFirst) == .none)
        let key = APIKey("sk-test-abcdefghijklmnop")
        try await router.turnCloudOn(.anthropic, key: key)
        #expect(await consents.selectedProvider() == .anthropic)
        #expect(await R.storedConsents(consents) == [.anthropic])
        #expect(await keys.key(for: .anthropic) == key)
        #expect(await router.cloudStatus() == .on(.anthropic))
        _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .onDeviceFirst))
        #expect(transport.requests.map(\.provider) == [.anthropic])
        #expect(transport.requests.first?.key == key)
    }
}

@Suite("AC-M2-18 turning cloud off or removing the key (a)–(d) (P-3)")
struct CloudTurnOffTests {
    typealias R = RoutingFixtures

    /// A router with cloud on for `x` (consent and key for every provider) and a transport that holds requests open.
    func onRouter(_ x: CloudProvider, keys keyStore: (any APIKeyStore)? = nil,
                  consents consentStore: (any CloudConsentStore)? = nil)
        -> (ModelRouter, InMemoryCloudConsentStore, InMemoryAPIKeyStore, RecordingTransport) {
        let all = Set(CloudProvider.allCases)
        let state = StoredState(selected: x, consents: all, keys: all, row: "S7+")
        let (consents, keys) = state.makeStores()
        let transport = RecordingTransport(mode: .hold)
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: transport),
                                 consents: consentStore ?? consents, keys: keyStore ?? keys)
        return (router, consents, keys, transport)
    }

    /// Starts a capture in its own task, waits until its request is in flight and one draft was emitted.
    func startInFlight(_ router: ModelRouter, _ transport: RecordingTransport, seen: SeenEvents,
                       expectedRequests: Int = 1) async -> Task<BoundedRun, Never> {
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        let consumer = Task { await collectBounded(events) { seen.append($0) } }
        #expect(await eventually { transport.requestCount == expectedRequests }, "request never started")
        transport.send([StreamFixtures.full("Buy dishwasher pods"), StreamFixtures.titleOnly("Service the")])
        #expect(await eventually { seen.all.count >= 1 }, "no draft emitted while in flight")
        return consumer
    }

    func expectCancelled(_ run: BoundedRun, route: Route, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(run.events.first == .emitted(1, "Buy dishwasher pods"), sourceLocation: sourceLocation)
        #expect(run.events.last == .finished(.cancelled(route: route)), sourceLocation: sourceLocation)
        #expect(run.events.filter { if case .finished = $0 { true } else { false } }.count == 1,
                sourceLocation: sourceLocation)
        #expect(run.afterFinished == nil, sourceLocation: sourceLocation)
        #expect(!run.hitCap, sourceLocation: sourceLocation)
    }

    @Test("AC-M2-18 (a)–(d): turning cloud off deletes every key, clears every consent, cancels the in-flight request with outcome cancelled, writes no task, and no request starts afterwards", .timeLimit(.minutes(1)))
    func turnOffInFlight() async throws {
        for x in CloudProvider.allCases {
            let (router, consents, keys, transport) = onRouter(x)
            let repository = InMemoryHouseholdRepository()
            let household = Household(tasks: [], rooms: MappingFixtures.rooms)
            try await repository.save(household)
            let seen = SeenEvents()
            let consumer = await startInFlight(router, transport, seen: seen)
            let stop: @Sendable () -> Void = { consumer.cancel() }
            try await withTaskCancellationHandler {
                try await router.turnCloudOff()
            } onCancel: { stop() }
            let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
            #expect(!neededCancel, "the capture did not end by itself")
            expectCancelled(run, route: .cloud(x))
            // (a) every key deleted; (b) every consent cleared.
            #expect(await R.storedKeys(keys).isEmpty)
            #expect(await R.storedConsents(consents).isEmpty)
            // (d) the in-flight request is cancelled (its stream ended by cancellation, not by finishing).
            #expect(await eventually { transport.ends == ["cancelled"] }, "\(transport.ends)")
            // Nothing is written.
            #expect(try await repository.load() == household)
            // Data sent after turn-off reaches nobody.
            transport.send([StreamFixtures.full("Mop the kitchen floor")])
            #expect(seen.all.count == run.events.count)
            // (c) no request starts afterwards, whatever the preference or availability says.
            #expect(await router.cloudStatus() == .off)
            for preference in RoutePreference.allCases {
                let after = await collectBounded(await router.events(for: StreamFixtures.pipeline(),
                                                                     preference: preference))
                #expect(after.events.last.map { if case .finished(.noModel(.none, _, _, _)) = $0 { true }
                                                else { false } } == true)
            }
            #expect(transport.requestCount == 1)
        }
    }

    @Test("AC-M2-18 (c): a capture routed to the cloud before turn-off but started after it sends no request and ends cancelled", .timeLimit(.minutes(1)))
    func routedBeforeStartedAfter() async throws {
        let (router, _, _, transport) = onRouter(.openAI)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        #expect(events.route == .cloud(.openAI))
        try await router.turnCloudOff()
        let run = await collectBounded(events)
        #expect(run.events == [.finished(.cancelled(route: .cloud(.openAI)))])
        #expect(run.afterFinished == nil)
        #expect(transport.requestCount == 0)
    }

    @Test("AC-M2-18 (c): consent cleared in the store after the route was chosen (not through the router): the request is refused at start, nothing is sent, and the capture ends cancelled", .timeLimit(.minutes(1)))
    func consentClearedBehindTheRouter() async throws {
        let (router, consents, _, transport) = onRouter(.anthropic)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        #expect(events.route == .cloud(.anthropic))
        await consents.clearConsent(for: .anthropic)
        let run = await collectBounded(events)
        #expect(run.events == [.finished(.cancelled(route: .cloud(.anthropic)))])
        #expect(transport.requestCount == 0)
    }

    @Test("AC-M2-18 (c): the selection changed in the store after the route was chosen (not through the router): the request to the old provider is refused at start, nothing is sent", .timeLimit(.minutes(1)))
    func selectionChangedBehindTheRouter() async throws {
        let (router, consents, keys, transport) = onRouter(.anthropic)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        #expect(events.route == .cloud(.anthropic))
        await consents.select(.gemini)
        let run = await collectBounded(events)
        #expect(run.events == [.finished(.cancelled(route: .cloud(.anthropic)))])
        #expect(transport.requestCount == 0)
        // Consent and key for the old provider are untouched; only the selection moved.
        #expect(await R.storedKeys(keys) == Set(CloudProvider.allCases))
        #expect(await router.cloudStatus() == .on(.gemini))
    }

    @Test("AC-M2-18: a capture the user cancels while its request is being prepared (key being read) sends nothing", .timeLimit(.minutes(1)))
    func cancelWhilePreparing() async {
        let began = ContinuousClock.now
        defer { print("R30-F3 body time, cancelWhilePreparing: \(ContinuousClock.now - began)") }
        let all = Set(CloudProvider.allCases)
        let keyStore = SuspendingKeyStore(keys: Dictionary(uniqueKeysWithValues: all.map {
            ($0, StoredState.fixtureKey($0))
        }))
        let (router, _, _, transport) = onRouter(.openAI, keys: keyStore)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        let seen = SeenEvents()
        let consumer = Task { await collectBounded(events) { seen.append($0) } }
        #expect(await eventually { keyStore.keyCalls == 1 }, "the request was never prepared")
        consumer.cancel()
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel)
        #expect(run.events == [.finished(.cancelled(route: .cloud(.openAI)))])
        keyStore.release()
        // The released preparation returns from the key read (an event), then gets a window to (wrongly) start the
        // request; no polling timer (review R30-F3).
        #expect(await eventually { keyStore.returnedKeyCalls == 1 }, "the key read never returned")
        #expect(await staysFalse { transport.requestCount > 0 }, "a request started after the cancel")
        #expect(transport.requestCount == 0)
        #expect(await router.cloudStatus() == .on(.openAI))
    }

    @Test("AC-M2-18 (a)–(d): removing the key of the provider in use deletes that key, clears that consent, cancels its in-flight request, and no request starts afterwards", .timeLimit(.minutes(1)))
    func removeKeyInFlight() async throws {
        for x in CloudProvider.allCases {
            let (router, consents, keys, transport) = onRouter(x)
            let seen = SeenEvents()
            let consumer = await startInFlight(router, transport, seen: seen)
            let stop: @Sendable () -> Void = { consumer.cancel() }
            try await withTaskCancellationHandler {
                try await router.removeKey(for: x)
            } onCancel: { stop() }
            let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
            #expect(!neededCancel, "the capture did not end by itself")
            expectCancelled(run, route: .cloud(x))
            let others = Set(CloudProvider.allCases).subtracting([x])
            #expect(await R.storedKeys(keys) == others)
            #expect(await R.storedConsents(consents) == others)
            #expect(await eventually { transport.ends == ["cancelled"] })
            // Still selected, but no key: cloud off, no new request (restored (ii) shape).
            #expect(await router.cloudStatus() == .off)
            _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud))
            #expect(transport.requestCount == 1)
        }
    }

    @Test("AC-M2-18: removing the key of a provider that is not in use leaves the in-flight request of the selected one running", .timeLimit(.minutes(1)))
    func removeOtherKey() async throws {
        let (router, consents, keys, transport) = onRouter(.openAI)
        let seen = SeenEvents()
        let consumer = await startInFlight(router, transport, seen: seen)
        try await router.removeKey(for: .gemini)
        #expect(await R.storedKeys(keys) == [.openAI, .anthropic])
        #expect(await R.storedConsents(consents) == [.openAI, .anthropic])
        transport.send([StreamFixtures.full("Buy dishwasher pods"), StreamFixtures.full("Service the AC")])
        transport.finishHeld()
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel, "the capture did not end by itself")
        #expect(run.events.last == .finished(.completed(route: .cloud(.openAI))))
        #expect(run.events.contains(.emitted(2, "Service the AC")))
        #expect(transport.ends == ["finished"])
        #expect(await router.cloudStatus() == .on(.openAI))
    }

    @Test("AC-M2-18 (open question 1, most private reading): selecting another provider cancels the in-flight request of the previous one; the next capture goes only to the new one", .timeLimit(.minutes(1)))
    func switchProviderInFlight() async throws {
        let (router, consents, keys, transport) = onRouter(.openAI)
        let seen = SeenEvents()
        let consumer = await startInFlight(router, transport, seen: seen)
        try await router.select(.anthropic)
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel, "the capture did not end by itself")
        expectCancelled(run, route: .cloud(.openAI))
        #expect(await consents.selectedProvider() == .anthropic)
        // Switching is not turning off: no key or consent is touched.
        #expect(await R.storedKeys(keys) == Set(CloudProvider.allCases))
        #expect(await R.storedConsents(consents) == Set(CloudProvider.allCases))
        #expect(await router.cloudStatus() == .on(.anthropic))
        let next = Task { await collectBounded(await router.events(for: StreamFixtures.pipeline(),
                                                                    preference: .alwaysCloud)) }
        #expect(await eventually { transport.requestCount == 2 })
        transport.finishHeld()
        _ = await next.value
        #expect(transport.requests.map(\.provider) == [.openAI, .anthropic])
    }

    @Test("AC-M2-18: selecting the provider already in use, or turning cloud on again, does not cancel the request in flight", .timeLimit(.minutes(1)))
    func reselectKeepsInFlight() async throws {
        let (router, _, _, transport) = onRouter(.gemini)
        let seen = SeenEvents()
        let consumer = await startInFlight(router, transport, seen: seen)
        try await router.select(.gemini)
        transport.finishHeld()
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel, "the capture did not end by itself")
        #expect(run.events.last == .finished(.completed(route: .cloud(.gemini))))
    }

    @Test("AC-M2-18 (c): when the stores cannot delete or clear, turn-off still cancels the request in flight, reports the store error, and no request starts afterwards in this session", .timeLimit(.minutes(1)))
    func turnOffWithFailingStores() async throws {
        let all = Set(CloudProvider.allCases)
        let keyValues = Dictionary(uniqueKeysWithValues: all.map { ($0, StoredState.fixtureKey($0)) })
        let keys = UndeletableKeyStore(keys: keyValues)
        let consents = UnclearableConsentStore(selected: .openAI, consents: all)
        let (router, _, _, transport) = onRouter(.openAI, keys: keys, consents: consents)
        let seen = SeenEvents()
        let consumer = await startInFlight(router, transport, seen: seen)
        await #expect(throws: CloudStoreError.self) { try await router.turnCloudOff() }
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel, "the capture did not end by itself")
        expectCancelled(run, route: .cloud(.openAI))
        #expect(await router.cloudStatus() == .off)
        for preference in RoutePreference.allCases {
            _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: preference))
        }
        try await router.select(.anthropic)
        #expect(await router.cloudStatus() == .off)
        #expect(transport.requestCount == 1)
        // Turning cloud on again (a new consent and key) is the only way back on.
        try await router.turnCloudOn(.anthropic, key: StoredState.fixtureKey(.anthropic))
        #expect(await router.cloudStatus() == .on(.anthropic))
    }

    @Test("AC-M2-18: removing a key that cannot be deleted still blocks that provider for this session and reports the error")
    func removeKeyWithFailingStore() async {
        let all = Set(CloudProvider.allCases)
        let keyValues = Dictionary(uniqueKeysWithValues: all.map { ($0, StoredState.fixtureKey($0)) })
        let (router, consents, _, _) = onRouter(.openAI, keys: UndeletableKeyStore(keys: keyValues))
        await #expect(throws: CloudStoreError.notAccessibleNow) { try await router.removeKey(for: .openAI) }
        #expect(await R.storedConsents(consents) == [.anthropic, .gemini])
        #expect(await router.cloudStatus() == .off)
    }

    @Test("AC-M2-18: turning cloud off when nothing is stored is calm and leaves everything empty")
    func turnOffWhenOff() async throws {
        let (router, consents, keys, _, _) = R.router(StoredState(selected: nil, consents: [], keys: [], row: "S0"),
                                                      .available)
        try await router.turnCloudOff()
        #expect(await R.storedKeys(keys).isEmpty)
        #expect(await R.storedConsents(consents).isEmpty)
        #expect(await router.cloudStatus() == .off)
    }

    @Test("AC-M2-18: the user cancelling a cloud capture ends it cancelled and ends the request, without touching consent or keys", .timeLimit(.minutes(1)))
    func consumerCancel() async {
        let (router, consents, keys, transport) = onRouter(.anthropic)
        let seen = SeenEvents()
        let consumer = await startInFlight(router, transport, seen: seen)
        consumer.cancel()
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel, "the capture did not end by itself")
        expectCancelled(run, route: .cloud(.anthropic))
        #expect(await eventually { transport.ends == ["cancelled"] })
        #expect(await R.storedKeys(keys) == Set(CloudProvider.allCases))
        #expect(await R.storedConsents(consents) == Set(CloudProvider.allCases))
        #expect(await router.cloudStatus() == .on(.anthropic))
    }

    @Test("AC-M2-18: an on-device capture is not affected by turning cloud off")
    func onDeviceUnaffected() async throws {
        let state = StoredState(selected: .openAI, consents: [.openAI], keys: [.openAI], row: "S4")
        let (router, _, _, _, onDevice) = R.router(state, .available)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .onDeviceFirst)
        try await router.turnCloudOff()
        let run = await collectBounded(events)
        #expect(run.events.last == .finished(.completed(route: .onDevice)))
        #expect(onDevice.scripted.requestCount == 1)
    }
}

@Suite("In-memory consent and key stores; APIKey formatting (AC-M2-18, AC-M2-21 formatting clause; P-3, P-4)")
struct CloudStoreTests {
    @Test("the in-memory key store saves, reads, replaces and deletes; delete is idempotent")
    func keyStore() async throws {
        let store: any APIKeyStore = InMemoryAPIKeyStore()
        #expect(try await store.hasKey(for: .openAI) == false)
        #expect(try await store.key(for: .openAI) == nil)
        try await store.save(APIKey("first-key-123456"), for: .openAI)
        #expect(try await store.key(for: .openAI) == APIKey("first-key-123456"))
        try await store.save(APIKey("second-key-123456"), for: .openAI)
        #expect(try await store.key(for: .openAI) == APIKey("second-key-123456"))
        #expect(try await store.hasKey(for: .gemini) == false)
        try await store.deleteKey(for: .openAI)
        try await store.deleteKey(for: .openAI)
        #expect(try await store.hasKey(for: .openAI) == false)
    }

    @Test("the in-memory consent store records and clears consent per provider and holds at most one selection")
    func consentStore() async throws {
        let store: any CloudConsentStore = InMemoryCloudConsentStore()
        try await store.recordConsent(for: .gemini)
        #expect(try await store.hasConsent(for: .gemini))
        #expect(try await store.hasConsent(for: .openAI) == false)
        try await store.select(.gemini)
        try await store.select(.openAI)
        #expect(try await store.selectedProvider() == .openAI)
        try await store.clearConsent(for: .gemini)
        try await store.clearConsent(for: .gemini)
        #expect(try await store.hasConsent(for: .gemini) == false)
        try await store.select(nil)
        #expect(try await store.selectedProvider() == nil)
    }

    @Test("an APIKey never shows its text in description, debug description, reflection, dump or interpolation")
    func keyFormatting() {
        let secret = "sk-SECRET-a1b2c3d4e5f6"
        let key = APIKey(secret)
        var dumped = ""
        dump(key, to: &dumped)
        var dumpedArray = ""
        dump([key], to: &dumpedArray)
        let forms = [
            key.description, key.debugDescription, String(describing: key), String(reflecting: key), "\(key)",
            dumped, dumpedArray, String(describing: [key]), String(describing: Optional(key)),
            String(describing: RecordedRequest(provider: .openAI, key: key, input: "x", roomNames: [])),
        ]
        for form in forms {
            #expect(!form.contains(secret), "\(form)")
            #expect(!form.contains("a1b2"), "\(form)")
        }
        #expect(Mirror(reflecting: key).children.isEmpty)
        #expect(key.withSecret { $0 } == secret)
        #expect(APIKey(secret) == APIKey(secret))
        #expect(APIKey(secret) != APIKey(secret + "x"))
    }

    @Test("store and route names are calm (no banned token; UX-3)")
    func calmNames() {
        let names = ["\(CloudStoreError.storeUnavailable)", "\(CloudStoreError.notAccessibleNow)",
                     "\(RoutePreference.onDeviceFirst)", "\(RoutePreference.alwaysCloud)",
                     "\(CloudStatus.off)", "\(CloudStatus.on(.gemini))"]
        for name in names {
            let words = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                .lowercased()
            #expect(!BannedTokens.containsBannedToken(words), "\(name)")
        }
        #expect(CloudStoreError.allCases.count == 2)
    }
}
