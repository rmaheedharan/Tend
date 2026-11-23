// Routing and consent for one household's captures (ADR-0005 Decisions 1, 2 and 5; brief Definitions "Route",
// "Cloud model"; plan "Route matrix"). AC-M2-19, AC-M2-18, AC-M2-10. P-1, P-2, P-3, P-4.
//
// `ModelRouter` is the only place that decides whether a capture may go to the cloud:
// - **Cloud on** means the selected provider has a consent record **and** a stored key, and was not turned off or had
//   its key removed in this session. Anything else is off, which is the default. A failing store reads as off.
// - **Orphan keys** (a key with no consent record for its provider) are deleted every time a route is chosen, so the
//   first route choice after a restore deletes a restored key (T-14 fixture (i)).
// - **One model per capture.** The route is chosen once, before the capture starts, and the pipeline holds exactly one
//   routed model (`RoutedModel`), so an on-device error never reaches the cloud (P-1, AC-M2-10).
// - **Consent is checked again when the request starts.** A cloud capture's model asks the router for permission
//   at the moment its request would start, and gets the key only then.
// - **Turning cloud off or removing the key** cancels every in-flight cloud capture of that provider at once (its
//   outcome becomes `cancelled`, nothing is written), clears the consent record, deletes the key, and blocks the
//   provider for this session even if a store cannot be changed. So no request starts afterwards. A capture's stream
//   is attached as soon as it is created, so this ends the consumer at once, even while the key is being read.
// - **Overlapping Settings actions:** a turn-off or remove-key that starts while a turn-on is running wins; the
//   turn-on then removes what it wrote and returns `.off`.
//
// No clock, timer, dispatch queue, lock or `@unchecked Sendable`: the actor serialises the state. No networking: the
// cloud model comes from an injected `CloudModelSource` (the `TendAI` adapters, WI-M2-M6).

import Foundation
import TendCore

/// The on-device model and its availability (the `TendAI` `FoundationModels` adapter, WI-M2-M2).
public protocol OnDeviceModelSource: Sendable {
    /// The availability for this capture (`SystemLanguageModel.availability` and `supportsLocale`, mapped neutrally).
    func availability() -> OnDeviceAvailability
    func model() -> any IngestionModel
}

/// Builds the cloud model for one provider with the key read for this request (the `TendAI` cloud adapters,
/// WI-M2-M6). A cloud model is never given the duplicate `Tool` (AC-M2-24).
public protocol CloudModelSource: Sendable {
    func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel
}

public actor ModelRouter {
    private let onDevice: any OnDeviceModelSource
    private let cloudModels: any CloudModelSource
    private let consents: any CloudConsentStore
    private let keys: any APIKeyStore

    /// Providers turned off or with their key removed in this session. Only `turnCloudOn` lifts a block.
    private var blocked: Set<CloudProvider> = []

    /// Settings-action order (review R24-F3): every Settings action takes the next number when it starts, and
    /// `lastEnded[p]` is the number of the latest turn-off or remove-key that covered provider `p`. A `turnCloudOn`
    /// that a later turn-off or remove-key overlapped does not turn cloud on: the later action wins.
    private var lastActionNumber: UInt64 = 0
    private var lastEnded: [CloudProvider: UInt64] = [:]

    /// One routed cloud capture, from route choice until its event sequence has ended.
    private struct CloudCapture {
        let provider: CloudProvider
        /// Cloud was turned off (or the key removed, or another provider selected) for this capture.
        var ended = false
        /// The capture's snapshot stream, attached as soon as the stream is created (before the key is read), so a
        /// turn-off ends the consumer at once (review R24-F2).
        var continuation: AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation?
        /// The request was allowed to start (at most once per capture).
        var started = false
    }

    private var captures: [UInt64: CloudCapture] = [:]
    private var lastCaptureID: UInt64 = 0

    public init(onDevice: any OnDeviceModelSource, cloudModels: any CloudModelSource,
                consents: any CloudConsentStore, keys: any APIKeyStore) {
        self.onDevice = onDevice
        self.cloudModels = cloudModels
        self.consents = consents
        self.keys = keys
    }

    // MARK: Route

    /// Whether cloud is on, after deleting every orphan key (a stored key whose provider has no consent record).
    /// Any store error reads as off (fail closed).
    public func cloudStatus() async -> CloudStatus {
        await deleteOrphanKeys()
        do throws(CloudStoreError) {
            guard let selected = try await consents.selectedProvider(),
                  try await consents.hasConsent(for: selected),
                  try await keys.hasKey(for: selected) else { return .off }
            // Read after the awaits: a turn-off that ran meanwhile wins.
            return blocked.contains(selected) ? .off : .on(selected)
        } catch {
            return .off
        }
    }

    /// The route a capture submitted now would take (ADR-0005 Decision 1). Deletes orphan keys.
    public func route(preference: RoutePreference) async -> Route {
        let availability = onDevice.availability()
        return RouteRules.route(availability: availability, preference: preference, cloud: await cloudStatus())
    }

    /// Chooses the route for one capture and returns its draft stream. The route is fixed for the capture and is
    /// reported in `RoutedDraftEvents.route` and in every outcome.
    ///
    /// The pipeline is built here, after the route is chosen, with the duplicate rules of that route (review R23-F2):
    /// `DraftDuplicateRules.onDevice(household:)` on device, and `DraftDuplicateRules.cloud(titleSharing, capture:
    /// input, household:)` on the cloud, with this `input` as the capture. So the rules can never belong to another
    /// route or another capture. The rooms linked and sent are `household.rooms`.
    ///
    /// - Parameter titleSharing: the Q12 answer in force (PO default `.shortlistTitles`).
    public func events(input: String, household: Household, now: Date, calendar: Calendar, timeZone: TimeZone,
                       titleSharing: CloudTitleSharing, preference: RoutePreference) async -> RoutedDraftEvents {
        await events(preference: preference) { route in
            let rules: DraftDuplicateRules = switch route {
            case .cloud: .cloud(titleSharing, capture: input, household: household)
            // Route `none` emits no draft; the on-device rules are given only so the pipeline has a check.
            case .onDevice, .none: .onDevice(household: household)
            }
            return DraftPipeline(input: input, rooms: household.rooms, now: now, calendar: calendar,
                                 timeZone: timeZone, duplicateCheck: rules)
        }
    }

    /// The same, with a pipeline the caller built (tests only: the caller is responsible for matching its rules to
    /// the route, which the public method above makes impossible to get wrong).
    func events(for pipeline: DraftPipeline, preference: RoutePreference) async -> RoutedDraftEvents {
        await events(preference: preference) { _ in pipeline }
    }

    private func events(preference: RoutePreference,
                        makePipeline: (Route) -> DraftPipeline) async -> RoutedDraftEvents {
        let availability = onDevice.availability()
        let route = RouteRules.route(availability: availability, preference: preference, cloud: await cloudStatus())
        let pipeline = makePipeline(route)
        switch route {
        case .onDevice:
            return RoutedDraftEvents(events: pipeline.events(from: .onDevice(onDevice.model())), route: route,
                                     watch: nil)
        case .none:
            // `RouteRules` gives `none` only when the on-device model is unavailable. The `else` branch cannot be
            // reached; it stays on device (never the cloud).
            let routed: RoutedModel = if case let .unavailable(reason) = availability {
                .none(reason)
            } else {
                .onDevice(onDevice.model())
            }
            return RoutedDraftEvents(events: pipeline.events(from: routed), route: routed.route, watch: nil)
        case let .cloud(provider):
            lastCaptureID += 1
            let id = lastCaptureID
            captures[id] = CloudCapture(provider: provider)
            let model = ConsentCheckedCloudModel(router: self, captureID: id)
            return RoutedDraftEvents(events: pipeline.events(from: .cloud(provider, model)), route: route,
                                     watch: RoutedDraftEvents.CaptureWatch(router: self, captureID: id))
        }
    }

    // MARK: Settings actions (M3 Settings calls these; the stores are their backing)

    /// Turns cloud on for `provider` after the consent screen (ADR-0005 Decision 2): records consent, stores the key
    /// and selects the provider. If the key cannot be stored, the consent record is cleared again.
    ///
    /// If a turn-off or a remove-key for `provider` started while this call was running, the later action wins
    /// (review R24-F3): the consent record and key written here are removed again, the provider stays blocked, and the
    /// result is `.off`. Otherwise the result is the cloud status after the call.
    @discardableResult
    public func turnCloudOn(_ provider: CloudProvider, key: APIKey) async throws(CloudStoreError) -> CloudStatus {
        let number = nextActionNumber()
        try await consents.recordConsent(for: provider)
        do throws(CloudStoreError) {
            try await keys.save(key, for: provider)
        } catch {
            try? await consents.clearConsent(for: provider)
            throw error
        }
        try await select(provider)
        // Read after the awaits: a turn-off or remove-key that started meanwhile wins.
        if let ended = lastEnded[provider], ended > number {
            try? await consents.clearConsent(for: provider)
            try? await keys.deleteKey(for: provider)
            return .off
        }
        blocked.remove(provider)
        return await cloudStatus()
    }

    /// Turns cloud off (one switch, ADR-0005 Decision 2): cancels every in-flight cloud capture, then clears every
    /// consent record and deletes every key. Every provider stays blocked for this session even if a store fails;
    /// the first store error is thrown after every step was tried.
    public func turnCloudOff() async throws(CloudStoreError) {
        let number = nextActionNumber()
        for provider in CloudProvider.allCases { lastEnded[provider] = number }
        blocked = Set(CloudProvider.allCases)
        endCaptures { _ in true }
        var firstError: CloudStoreError?
        for provider in CloudProvider.allCases {
            do throws(CloudStoreError) { try await consents.clearConsent(for: provider) } catch {
                firstError = firstError ?? error
            }
        }
        for provider in CloudProvider.allCases {
            do throws(CloudStoreError) { try await keys.deleteKey(for: provider) } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// Removes the key for `provider` ("Remove key", ADR-0005 Decision 5): cancels that provider's in-flight captures,
    /// clears its consent record and deletes its key. Other providers are not touched.
    public func removeKey(for provider: CloudProvider) async throws(CloudStoreError) {
        lastEnded[provider] = nextActionNumber()
        blocked.insert(provider)
        endCaptures { $0 == provider }
        var firstError: CloudStoreError?
        do throws(CloudStoreError) { try await consents.clearConsent(for: provider) } catch { firstError = error }
        do throws(CloudStoreError) { try await keys.deleteKey(for: provider) } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    /// Selects `provider` (nil: none). In-flight captures of any other provider are cancelled (dev-notes WI-M2-09,
    /// open question 1). Consent records and keys are not touched.
    public func select(_ provider: CloudProvider?) async throws(CloudStoreError) {
        endCaptures { $0 != provider }
        try await consents.select(provider)
    }

    // MARK: Captures (used by `ConsentCheckedCloudModel` and `RoutedDraftEvents`)

    /// Attaches the capture's snapshot stream as soon as it is created, so `endCaptures` can end it at once, even
    /// while the request is still being prepared (review R24-F2). False when the capture has already ended.
    func attach(_ captureID: UInt64,
                continuation: AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation) -> Bool {
        guard let capture = captures[captureID], !capture.ended, capture.continuation == nil else { return false }
        captures[captureID]?.continuation = continuation
        return true
    }

    /// Called when a cloud capture's request would start (after `attach`). Returns the provider's model built with
    /// the key read now, or nil (and ends the capture) when cloud is no longer on for that provider. At most one
    /// request per capture.
    func beginRequest(_ captureID: UInt64) async -> (any IngestionModel)? {
        guard let capture = captures[captureID], !capture.ended, !capture.started,
              capture.continuation != nil else { return nil }
        captures[captureID]?.started = true
        let status = await cloudStatus()
        let key: APIKey? = status == .on(capture.provider) ? try? await keys.key(for: capture.provider) : nil
        // Read again after the awaits: a turn-off, remove-key or switch that ran meanwhile wins (review R24-F1).
        guard let key, let current = captures[captureID], !current.ended else {
            endCaptures({ _ in true }, where: captureID)
            return nil
        }
        return cloudModels.model(for: capture.provider, key: key)
    }

    /// Whether the capture was ended by a turn-off (unknown captures count as ended: fail closed).
    func captureEnded(_ captureID: UInt64) -> Bool {
        captures[captureID]?.ended ?? true
    }

    /// Forgets a capture whose event sequence has ended.
    func release(_ captureID: UInt64) {
        captures[captureID] = nil
    }

    /// The number of captures the router still tracks (tests; review R24-F6).
    var trackedCaptureCount: Int { captures.count }

    private func nextActionNumber() -> UInt64 {
        lastActionNumber += 1
        return lastActionNumber
    }

    private func endCaptures(where matches: (CloudProvider) -> Bool) {
        for id in captures.keys {
            endCaptures(matches, where: id)
        }
    }

    /// Ends one capture when it has not ended and its provider matches. Finishing the stream ends the request: its
    /// termination handler cancels the forwarding task, which ends the cloud model's stream (IngestionModel adapter
    /// contract, part 3).
    private func endCaptures(_ matches: (CloudProvider) -> Bool, where captureID: UInt64) {
        guard let capture = captures[captureID], !capture.ended, matches(capture.provider) else { return }
        captures[captureID]?.ended = true
        captures[captureID]?.continuation = nil
        capture.continuation?.finish(throwing: CloudAccessEnded())
    }

    private func deleteOrphanKeys() async {
        for provider in CloudProvider.allCases {
            do throws(CloudStoreError) {
                if try await keys.hasKey(for: provider), !(try await consents.hasConsent(for: provider)) {
                    try await keys.deleteKey(for: provider)
                }
            } catch {
                // Fail closed: `cloudStatus` reads the stores again, and a key with no consent never turns cloud on.
                continue
            }
        }
    }
}

/// Cloud was turned off, the key removed or another provider selected while this capture was routed to the cloud.
/// `RoutedDraftEvents` turns the capture's outcome into `cancelled`.
struct CloudAccessEnded: Error {}

/// The cloud model of one routed capture: it asks the router at the moment the request would start, and forwards the
/// provider model's snapshots. Ending the stream (consumer cancel, turn-off) cancels the forwarding task, which ends
/// the provider model's stream.
struct ConsentCheckedCloudModel: IngestionModel {
    let router: ModelRouter
    let captureID: UInt64

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        AsyncThrowingStream { continuation in
            let forwarding = Task { [router, captureID] in
                guard await router.attach(captureID, continuation: continuation),
                      let model = await router.beginRequest(captureID),
                      !Task.isCancelled else {
                    continuation.finish(throwing: CloudAccessEnded())
                    return
                }
                do {
                    for try await snapshot in model.snapshots(for: request) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }
}
