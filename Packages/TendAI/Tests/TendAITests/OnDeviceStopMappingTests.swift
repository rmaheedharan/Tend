// Availability, locale and generation errors to neutral reasons (WI-M2-M2; AC-M2-10 adapter half). P-1, UX-3.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendIngestion

@Suite("On-device availability and stop mapping (WI-M2-M2; AC-M2-10)")
struct OnDeviceStopMappingTests {

    @Test("AC-M2-10: every SystemLanguageModel.Availability case and supportsLocale map to the neutral availability")
    func availability() {
        typealias A = SystemLanguageModel.Availability
        let cases: [(A, Bool, OnDeviceAvailability)] = [
            (.available, true, .available),
            (.available, false, .unavailable(.unsupportedLocale)),
            (.unavailable(.deviceNotEligible), true, .unavailable(.deviceNotEligible)),
            (.unavailable(.deviceNotEligible), false, .unavailable(.deviceNotEligible)),
            (.unavailable(.appleIntelligenceNotEnabled), true, .unavailable(.appleIntelligenceNotEnabled)),
            (.unavailable(.appleIntelligenceNotEnabled), false, .unavailable(.appleIntelligenceNotEnabled)),
            (.unavailable(.modelNotReady), true, .unavailable(.modelNotReady)),
            (.unavailable(.modelNotReady), false, .unavailable(.modelNotReady)),
        ]
        for (availability, locale, expected) in cases {
            #expect(OnDeviceAvailabilityMapping.neutral(availability, supportsLocale: locale) == expected)
        }
        // Every neutral reason is reachable from the framework.
        let reached = Set(cases.compactMap { if case let .unavailable(r) = $0.2 { r } else { nil } })
        #expect(reached == Set(OnDeviceUnavailableReason.allCases))
    }

    @Test("The source reads the framework's availability and locale support through the mapping")
    func source() {
        let source = FoundationModelsOnDeviceSource(
            readAvailability: { (.available, false) },
            makeGeneration: { FoundationModelsGeneration(household: $0) })
        #expect(source.availability() == .unavailable(.unsupportedLocale))
        let off = FoundationModelsOnDeviceSource(
            readAvailability: { (.unavailable(.appleIntelligenceNotEnabled), true) },
            makeGeneration: { FoundationModelsGeneration(household: $0) })
        #expect(off.availability() == .unavailable(.appleIntelligenceNotEnabled))
    }

    @Test("AC-M2-10: every LanguageModelSession.GenerationError case maps to a neutral stop reason")
    func generationErrors() {
        typealias E = LanguageModelSession.GenerationError
        let context = E.Context(debugDescription: "test")
        let cases: [(E, ModelStopReason)] = [
            (.exceededContextWindowSize(context), .contextTooLong),
            (.assetsUnavailable(context), .assetsUnavailable),
            (.guardrailViolation(context), .guardrail),
            (.unsupportedGuide(context), .otherModelError),
            (.unsupportedLanguageOrLocale(context), .unsupportedLanguage),
            (.decodingFailure(context), .unreadableOutput),
            (.rateLimited(context), .rateLimited),
            (.concurrentRequests(context), .busy),
            (.refusal(E.Refusal(transcriptEntries: []), context), .refusal),
        ]
        for (error, expected) in cases {
            #expect(OnDeviceStopMapping.reason(for: error) == expected)
            #expect(OnDeviceStopMapping.reason(for: error as any Error) == expected)
        }
    }

    @Test("AC-M2-10: every iOS 27 / macOS 27 model error maps to a neutral stop reason")
    func newErrors() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            // The B4 and B5 hosts run macOS 27.2 and iOS 26.5; on iOS 26.5 this family does not exist, and the
            // GenerationError test above covers that runtime. The test is not counted as skipped: it passes there.
            return
        }
        let cases: [(any Error, ModelStopReason)] = [
            (LanguageModelError.contextSizeExceeded(.init(contextSize: 1, tokenCount: 2, debugDescription: "")),
             .contextTooLong),
            (LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")), .rateLimited),
            (LanguageModelError.guardrailViolation(.init(debugDescription: "")), .guardrail),
            (LanguageModelError.refusal(.init(explanation: "", debugDescription: "")), .refusal),
            (LanguageModelError.unsupportedCapability(.init(capability: .toolCalling, debugDescription: "")),
             .otherModelError),
            (LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [], debugDescription: "")),
             .otherModelError),
            (LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "")),
             .otherModelError),
            (LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .english, debugDescription: "")),
             .unsupportedLanguage),
            (LanguageModelError.timeout(.init(debugDescription: "")), .timedOut),
            (LanguageModelSession.Error.concurrentRequests, .busy),
            (LanguageModelSession.Error.transcriptMutationWhileResponding, .otherModelError),
            (SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "")), .assetsUnavailable),
            (GeneratedContent.ParsingError(rawContent: "{", debugDescription: ""), .unreadableOutput),
        ]
        for (error, expected) in cases {
            #expect(OnDeviceStopMapping.reason(for: error) == expected)
        }
    }

    @Test("A ModelStopReason passes through; any other error is otherModelError")
    func passThrough() {
        for reason in ModelStopReason.allCases {
            #expect(OnDeviceStopMapping.reason(for: reason) == reason)
        }
        struct Other: Error {}
        #expect(OnDeviceStopMapping.reason(for: Other()) == .otherModelError)
    }
}
