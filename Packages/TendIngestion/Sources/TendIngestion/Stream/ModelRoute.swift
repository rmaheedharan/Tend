// The route a capture takes and the neutral reasons a model can be unusable or stop (brief Definitions "Route",
// "Draft stream events"; AC-M2-10, AC-M2-19, AC-M2-23; ADR-0005 Decision 1). FR-A1, P-1, P-3, UX-3.
//
// These are neutral values: the adapters in `TendAI` map `SystemLanguageModel.Availability`,
// `LanguageModelSession.GenerationError`, `URLError` and HTTP statuses onto them (WI-M2-M2, WI-M2-M4, on the owner-run
// Mac). Routing (WI-M2-09) picks the route; stream assembly only reports it. Case names describe the situation, never
// the person (AC-M2-23 "none blames the user") and hold no banned token (AC-M2-10, AC-M2-12).

import Foundation

/// The three cloud providers ADR-0005 allows (bring your own key).
public enum CloudProvider: String, CaseIterable, Hashable, Sendable {
    case openAI
    case anthropic
    case gemini
}

/// Which model handles a capture (brief Definitions "Route").
public enum Route: Hashable, Sendable {
    /// The on-device language model.
    case onDevice
    /// The user's chosen cloud provider (cloud on, ADR-0005).
    case cloud(CloudProvider)
    /// No usable model: the on-device model is unavailable and cloud is off.
    case none
}

/// Why the on-device model cannot be used for this capture (brief AC-M2-10; plan route matrix, input A).
public enum OnDeviceUnavailableReason: CaseIterable, Hashable, Sendable {
    /// This device cannot run the on-device model.
    case deviceNotEligible
    /// Apple Intelligence is turned off on this device.
    case appleIntelligenceNotEnabled
    /// The model is still downloading or preparing.
    case modelNotReady
    /// The model does not support the current language or locale (T-12, Q2).
    case unsupportedLocale
}

/// Why a model stopped producing output (on-device generation errors, cloud transport and provider outcomes, and a
/// cut-off stream). An adapter finishes its snapshot stream by throwing one of these. Any other error type is treated
/// as `otherModelError`.
public enum ModelStopReason: Error, CaseIterable, Hashable, Sendable {
    // On-device generation (`LanguageModelSession.GenerationError`, mapped in WI-M2-M2).
    /// The model's safety guardrail stopped the response.
    case guardrail
    /// The capture is longer than the model's context window.
    case contextTooLong
    /// The model does not support the capture's language.
    case unsupportedLanguage
    /// The model's assets are not available right now.
    case assetsUnavailable
    /// The model is handling another request.
    case busy
    // Shared by on-device and cloud.
    /// Too many requests in a short time (on-device rate limit, or HTTP 429).
    case rateLimited
    /// The output could not be read as the expected structure (decoding, or a malformed cloud body).
    case unreadableOutput
    /// The model or provider declined to answer.
    case refusal
    // Cloud transport and provider (mapped in WI-M2-M4).
    /// The device has no network connection.
    case offline
    /// The cloud deadline or a request timeout passed (AC-M2-22).
    case timedOut
    /// The provider's host name could not be resolved.
    case hostNotFound
    /// A secure (TLS) connection could not be set up.
    case secureConnectionUnavailable
    /// The provider did not accept the stored key (HTTP 401 or 403).
    case keyNotAccepted
    /// The provider's service is unavailable (HTTP 5xx).
    case serviceUnavailable
    // The stream itself.
    /// The output stream ended before the structured output was complete (truncation, AC-M2-24).
    case outputCutShort
    /// Any other error.
    case otherModelError
}

/// Why `noModel` was the outcome (brief Definitions "noModel").
public enum NoModelReason: Hashable, Sendable {
    /// Route `none`: the on-device model is unavailable and cloud is off.
    case onDeviceUnavailable(OnDeviceUnavailableReason)
    /// The routed model stopped (an error, a refusal or a guardrail) before the first draft was emitted (T-25).
    case stoppedBeforeFirstDraft(ModelStopReason)
}

/// The routed model for one capture: exactly one model, or none. The pipeline holds no other model, so an on-device
/// error can never re-route to the cloud (AC-M2-10, AC-M2-19, P-3).
public enum RoutedModel: Sendable {
    case onDevice(any IngestionModel)
    case cloud(CloudProvider, any IngestionModel)
    /// Route `none`, with the on-device reason (cloud is off).
    case none(OnDeviceUnavailableReason)

    public var route: Route {
        switch self {
        case .onDevice: .onDevice
        case let .cloud(provider, _): .cloud(provider)
        case .none: .none
        }
    }
}
