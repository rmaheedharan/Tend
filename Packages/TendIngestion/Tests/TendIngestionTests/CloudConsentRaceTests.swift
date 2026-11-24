// WI-M2-09 review round 1 (PR #24): the concurrency windows of `ModelRouter`. AC-M2-18 (c), (d); P-3.
// - R24-F1: a turn-off, remove-key or provider switch while the key is being read for a request.
// - R24-F2: such a turn-off ends the consumer at once, before the key read returns.
// - R24-F3: a turn-off that overlaps a turn-on wins.
// - R24-F4: a turn-off while `cloudStatus` is reading the stores gives `.off`, even when the stores cannot change.
// - R24-F5: the consent rollback in `turnCloudOn`.
// - R24-F6: the router forgets a capture whose events were read to the end.
// Every wait is bounded (`eventually`, `awaitConsumer`, `collectBounded` with a held transport and a time limit), so a
// broken rule fails on an assertion instead of hanging.

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

/// The Settings action that ends cloud access for the routed provider (openAI in these tests).
enum EndingAction: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case turnCloudOff
    case removeKey
    case selectOtherProvider

    var testDescription: String { rawValue }

    func run(on router: ModelRouter) async {
        switch self {
        case .turnCloudOff: try? await router.turnCloudOff()
        case .removeKey: try? await router.removeKey(for: .openAI)
        case .selectOtherProvider: try? await router.select(.anthropic)
        }
    }
}

@Suite("AC-M2-18 (c), (d): Settings actions during the request preparation and overlapping actions (review R24; P-3)")
struct CloudConsentRaceTests {
    typealias R = RoutingFixtures

    static let allKeys = Dictionary(uniqueKeysWithValues: CloudProvider.allCases.map {
        ($0, StoredState.fixtureKey($0))
    })

    /// Cloud on for openAI (consent and key for every provider), a held transport, and the given key store.
    func router(keys: any APIKeyStore, consents: (any CloudConsentStore)? = nil)
        -> (ModelRouter, RecordingTransport) {
        let transport = RecordingTransport(mode: .hold)
        let router = ModelRouter(
            onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
            cloudModels: RecordingCloudModels(transport: transport),
            consents: consents ?? InMemoryCloudConsentStore(selected: .openAI,
                                                            consents: Set(CloudProvider.allCases)),
            keys: keys)
        return (router, transport)
    }

    /// Gives a released key read the chance to (wrongly) start a request: waits for the read to return (an event), then
    /// for a request that must not start (event-driven window, `staysFalse`). No polling timer (review R30-F3).
    func settle(_ transport: RecordingTransport, after keys: SuspendingKeyStore) async {
        #expect(await eventually { keys.returnedKeyCalls == keys.keyCalls }, "the key read never returned")
        _ = await staysFalse { transport.requestCount > 0 }
    }

    @Test("R24-F1, R24-F2: a Settings action while the key is being read for the request ends the capture at once (before the key read returns) with cancelled, and no request is sent", .timeLimit(.minutes(1)), arguments: EndingAction.allCases)
    func actionDuringKeyRead(action: EndingAction) async {
        let began = ContinuousClock.now
        defer { print("R30-F3 body time, actionDuringKeyRead \(action): \(ContinuousClock.now - began)") }
        let keys = SuspendingKeyStore(keys: Self.allKeys)
        let (router, transport) = router(keys: keys)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        #expect(events.route == .cloud(.openAI))
        let seen = SeenEvents()
        let consumer = Task { await collectBounded(events) { seen.append($0) } }
        #expect(await eventually { keys.keyCalls == 1 }, "the request was never prepared")
        await action.run(on: router)
        // R24-F2: the consumer ends while the key read is still held.
        let endedAtOnce = await eventually {
            seen.all.contains { if case .finished = $0 { true } else { false } }
        }
        #expect(endedAtOnce, "the consumer did not end before the key read returned")
        keys.release()
        let (run, neededCancel) = await awaitConsumer(consumer, seen: seen)
        #expect(!neededCancel)
        #expect(run.events == [.finished(.cancelled(route: .cloud(.openAI)))])
        #expect(run.afterFinished == nil)
        await settle(transport, after: keys)
        #expect(transport.requestCount == 0, "a request started after \(action)")
    }

    @Test("R24-F1: beginRequest reads the capture again after the key read: a Settings action during the read refuses the request", .timeLimit(.minutes(1)), arguments: EndingAction.allCases)
    func beginRequestRecheck(action: EndingAction) async throws {
        let keys = SuspendingKeyStore(keys: Self.allKeys)
        let (router, _) = router(keys: keys)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        let watch = try #require(events.watch)
        let (_, continuation) = AsyncThrowingStream<IngestionSnapshot, any Error>.makeStream()
        #expect(await router.attach(watch.captureID, continuation: continuation))
        let begin = Task { await router.beginRequest(watch.captureID) != nil }
        #expect(await eventually { keys.keyCalls == 1 })
        await action.run(on: router)
        keys.release()
        #expect(await begin.value == false, "the request was allowed after \(action)")
        #expect(await router.captureEnded(watch.captureID))
    }

    @Test("R24-F1 control: with no Settings action, the same preparation is allowed exactly once", .timeLimit(.minutes(1)))
    func beginRequestControl() async throws {
        let keys = SuspendingKeyStore(keys: Self.allKeys)
        let (router, _) = router(keys: keys)
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        let watch = try #require(events.watch)
        let (_, continuation) = AsyncThrowingStream<IngestionSnapshot, any Error>.makeStream()
        #expect(await router.attach(watch.captureID, continuation: continuation))
        #expect(await router.attach(watch.captureID, continuation: continuation) == false)
        let begin = Task { await router.beginRequest(watch.captureID) != nil }
        #expect(await eventually { keys.keyCalls == 1 })
        keys.release()
        #expect(await begin.value == true)
        #expect(await router.beginRequest(watch.captureID) == nil, "a second request for one capture")
    }

    @Test("R24-F3: a turn-off that overlaps a turn-on wins: the turn-on returns off, and its consent and key are removed again", .timeLimit(.minutes(1)))
    func turnOffOverlapsTurnOn() async throws {
        let consents = SuspendingConsentStore()
        let keys = InMemoryAPIKeyStore()
        let (router, transport) = router(keys: keys, consents: consents)
        let turnOn = Task { try await router.turnCloudOn(.gemini, key: StoredState.fixtureKey(.gemini)) }
        #expect(await eventually { consents.heldCalls == 1 }, "turn-on never reached the consent store")
        try await router.turnCloudOff()
        consents.release()
        #expect(try await turnOn.value == .off)
        #expect(await router.cloudStatus() == .off)
        #expect(consents.consentsNow.isEmpty)
        #expect(await R.storedKeys(keys).isEmpty)
        _ = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud))
        #expect(transport.requestCount == 0)
    }

    @Test("R24-F3: a remove-key for the same provider that overlaps a turn-on wins; for another provider it does not", .timeLimit(.minutes(1)), arguments: [CloudProvider.gemini, .openAI])
    func removeKeyOverlapsTurnOn(removed: CloudProvider) async throws {
        let consents = SuspendingConsentStore()
        let keys = InMemoryAPIKeyStore()
        let (router, _) = router(keys: keys, consents: consents)
        let turnOn = Task { try await router.turnCloudOn(.gemini, key: StoredState.fixtureKey(.gemini)) }
        #expect(await eventually { consents.heldCalls == 1 })
        try await router.removeKey(for: removed)
        consents.release()
        let expected: CloudStatus = removed == .gemini ? .off : .on(.gemini)
        #expect(try await turnOn.value == expected)
        #expect(await router.cloudStatus() == expected)
    }

    @Test("R24-F3 control: a turn-on that starts after a turn-off has returned turns cloud on")
    func turnOnAfterTurnOff() async throws {
        let (router, _) = router(keys: InMemoryAPIKeyStore(keys: Self.allKeys))
        try await router.turnCloudOff()
        #expect(try await router.turnCloudOn(.anthropic, key: StoredState.fixtureKey(.anthropic)) == .on(.anthropic))
        #expect(await router.cloudStatus() == .on(.anthropic))
    }

    @Test("R24-F4: a turn-off while cloudStatus is reading the stores gives off, even when the stores cannot clear or delete", .timeLimit(.minutes(1)))
    func turnOffDuringStatusRead() async {
        let keys = SuspendingKeyStore(keys: Self.allKeys, holdKeyRead: false, holdFirstHasKey: true,
                                      deleteFails: true)
        let consents = UnclearableConsentStore(selected: .openAI, consents: Set(CloudProvider.allCases))
        let (router, _) = router(keys: keys, consents: consents)
        let status = Task { await router.cloudStatus() }
        #expect(await eventually { keys.heldHasKeyCalls == 1 }, "cloudStatus never read the key store")
        await #expect(throws: CloudStoreError.self) { try await router.turnCloudOff() }
        keys.release()
        #expect(await status.value == .off)
    }

    @Test("R24-F5: when the key cannot be stored, turn-on throws the store error, clears the consent again, and cloud stays off")
    func turnOnRollsBackConsent() async {
        let consents = InMemoryCloudConsentStore()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)),
                                 cloudModels: RecordingCloudModels(transport: RecordingTransport()),
                                 consents: consents, keys: UnavailableKeyStore())
        await #expect(throws: CloudStoreError.storeUnavailable) {
            try await router.turnCloudOn(.openAI, key: StoredState.fixtureKey(.openAI))
        }
        #expect(await R.storedConsents(consents).isEmpty)
        #expect(await consents.selectedProvider() == nil)
        #expect(await router.cloudStatus() == .off)
    }

    @Test("R24-F6: the router tracks a cloud capture while it runs and forgets it once its events were read to the end", .timeLimit(.minutes(1)))
    func captureIsForgotten() async {
        let (router, transport) = router(keys: InMemoryAPIKeyStore(keys: Self.allKeys))
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .alwaysCloud)
        #expect(await router.trackedCaptureCount == 1)
        let consumer = Task { await collectBounded(events) }
        #expect(await eventually { transport.requestCount == 1 })
        transport.finishHeld()
        let run = await consumer.value
        guard case .finished(.completed(route: .cloud(.openAI), _, _))? = run.events.last else {
            Issue.record("expected completed on cloud(openAI): \(run.events)")
            return
        }
        #expect(await router.trackedCaptureCount == 0)
        // An on-device capture is never tracked.
        let state = StoredState(selected: nil, consents: [], keys: [], row: "S0")
        let (onDeviceRouter, _, _, _, _) = R.router(state, .available)
        _ = await collectBounded(await onDeviceRouter.events(for: StreamFixtures.pipeline(),
                                                              preference: .onDeviceFirst))
        #expect(await onDeviceRouter.trackedCaptureCount == 0)
    }
}
