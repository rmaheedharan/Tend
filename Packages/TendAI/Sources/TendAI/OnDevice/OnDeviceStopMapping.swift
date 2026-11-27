// `SystemLanguageModel.Availability`, `supportsLocale` and the generation errors to the neutral reasons (WI-M2-M2;
// brief AC-M2-10; ADR-0005 Decision 1(a)). P-1, P-3, UX-3.
//
// Every switch here is exhaustive with no `default`. A `@unknown default` appears only where the framework's enum is
// not frozen, which the compiler requires; it still warns (an error with warnings as errors) when a known case is not
// listed, so a new case in a later SDK must be mapped by hand.
//
// The SDK on the owner's Mac is Xcode 27.2 (iOS 27.2 / macOS 27.2 SDK) with an iOS 26.0 deployment target. On an
// iOS 26 runtime the model throws `LanguageModelSession.GenerationError`. iOS 27 / macOS 27 deprecate it in favour of
// `LanguageModelError`, `LanguageModelSession.Error`, `SystemLanguageModel.Error` and `GeneratedContent.ParsingError`,
// so both families are mapped (the second behind `#available`).
//
// No outcome here can re-route to the cloud: the adapter only reports why the model stopped (P-1, AC-M2-10).

import Foundation
import FoundationModels
import TendIngestion

enum OnDeviceAvailabilityMapping {
    /// The neutral availability. An unavailable model wins over the locale check.
    static func neutral(_ availability: SystemLanguageModel.Availability,
                        supportsLocale: Bool) -> OnDeviceAvailability {
        switch availability {
        case .available:
            supportsLocale ? .available : .unavailable(.unsupportedLocale)
        case let .unavailable(reason):
            .unavailable(neutral(reason))
        }
    }

    static func neutral(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> OnDeviceUnavailableReason {
        switch reason {
        case .deviceNotEligible: .deviceNotEligible
        case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
        case .modelNotReady: .modelNotReady
        // A reason a later OS adds: the calmest reading, "not ready yet". Routing treats every reason alike.
        @unknown default: .modelNotReady
        }
    }
}

enum OnDeviceStopMapping {
    /// Why the on-device model stopped. A `ModelStopReason` passes through; an error this table does not know is
    /// `otherModelError`.
    static func reason(for error: any Error) -> ModelStopReason {
        if let reason = error as? ModelStopReason { return reason }
        if let error = error as? LanguageModelSession.GenerationError { return reason(for: error) }
        if #available(iOS 27.0, macOS 27.0, *) {
            if let error = error as? LanguageModelError { return reason(for: error) }
            if let error = error as? LanguageModelSession.Error { return reason(for: error) }
            if let error = error as? SystemLanguageModel.Error { return reason(for: error) }
            if error is GeneratedContent.ParsingError { return .unreadableOutput }
        }
        // A throwing `Tool` (ours never throws) and every other error.
        return .otherModelError
    }

    /// The iOS 26 generation errors.
    static func reason(for error: LanguageModelSession.GenerationError) -> ModelStopReason {
        switch error {
        case .exceededContextWindowSize: .contextTooLong
        case .assetsUnavailable: .assetsUnavailable
        case .guardrailViolation: .guardrail
        // The schema asked for a guide the model cannot follow: a defect on our side, not the person's.
        case .unsupportedGuide: .otherModelError
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .decodingFailure: .unreadableOutput
        case .rateLimited: .rateLimited
        case .concurrentRequests: .busy
        case .refusal: .refusal
        @unknown default: .otherModelError
        }
    }

    /// The iOS 27 language-model errors.
    @available(iOS 27.0, macOS 27.0, *)
    static func reason(for error: LanguageModelError) -> ModelStopReason {
        switch error {
        case .contextSizeExceeded: .contextTooLong
        case .rateLimited: .rateLimited
        case .guardrailViolation: .guardrail
        case .refusal: .refusal
        case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: .otherModelError
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .timeout: .timedOut
        @unknown default: .otherModelError
        }
    }

    /// The iOS 27 session errors.
    @available(iOS 27.0, macOS 27.0, *)
    static func reason(for error: LanguageModelSession.Error) -> ModelStopReason {
        switch error {
        case .concurrentRequests: .busy
        case .transcriptMutationWhileResponding: .otherModelError
        @unknown default: .otherModelError
        }
    }

    /// The iOS 27 system-model errors.
    @available(iOS 27.0, macOS 27.0, *)
    static func reason(for error: SystemLanguageModel.Error) -> ModelStopReason {
        switch error {
        case .assetsUnavailable: .assetsUnavailable
        @unknown default: .otherModelError
        }
    }
}
