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
//   provider for this session even if a store cannot be changed. So no request starts afterwards.
//
// No clock, timer, dispatch queue, lock or `@unchecked Sendable`: the actor serialises the state. No networking: the
// cloud model comes from an injected `CloudModelSource` (the `TendAI` adapters, WI-M2-M6).

import Foundation

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

    /// One routed cloud capture, from route choice until its event sequence has ended.
    private struct CloudCapture {
        let provider: CloudProvider
        /// Cloud was turned off (or the key removed, or another provider selected) for this capture.
        var ended = false
        /// The capture's snapshot stream, once its request has started.
        var continuation: AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation?
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
    public func events(for pipeline: DraftPipeline, preference: RoutePreference) async -> RoutedDraftEvents {
        let availability = onDevice.availability()
        let route = RouteRules.route(availability: availability, preference: preference, cloud: await cloudStatus())
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
    public func turnCloudOn(_ provider: CloudProvider, key: APIKey) async throws(CloudStoreError) {
        try await consents.recordConsent(for: provider)
        do throws(CloudStoreError) {
            try await keys.save(key, for: provider)
        } catch {
            try? await consents.clearConsent(for: provider)
            throw error
        }
        try await select(provider)
        blocked.remove(provider)
    }

    /// Turns cloud off (one switch, ADR-0005 Decision 2): cancels every in-flight cloud capture, then clears every
    /// consent record and deletes every key. Every provider stays blocked for this session even if a store fails;
    /// the first store error is thrown after every step was tried.
    public func turnCloudOff() async throws(CloudStoreError) {
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

    /// Called when a cloud capture's request would start. Returns the provider's model built with the key read now,
    /// or nil (and ends the capture) when cloud is no longer on for that provider. At most one request per capture.
    func beginRequest(_ captureID: UInt64,
                      continuation: AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation) async
        -> (any IngestionModel)? {
        guard let capture = captures[captureID], !capture.ended, capture.continuation == nil else { return nil }
        let status = await cloudStatus()
        let key: APIKey? = status == .on(capture.provider) ? try? await keys.key(for: capture.provider) : nil
        // Read again after the awaits: a turn-off that ran meanwhile wins.
        guard let key, var current = captures[captureID], !current.ended, current.continuation == nil else {
            captures[captureID]?.ended = true
            return nil
        }
        current.continuation = continuation
        captures[captureID] = current
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

    private func endCaptures(where matches: (CloudProvider) -> Bool) {
        for (id, capture) in captures where !capture.ended && matches(capture.provider) {
            captures[id]?.ended = true
            captures[id]?.continuation = nil
            // Ends the request: the stream's termination handler cancels the forwarding task, which ends the cloud
            // model's stream (IngestionModel adapter contract, part 3).
            capture.continuation?.finish(throwing: CloudAccessEnded())
        }
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
                guard let model = await router.beginRequest(captureID, continuation: continuation),
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
