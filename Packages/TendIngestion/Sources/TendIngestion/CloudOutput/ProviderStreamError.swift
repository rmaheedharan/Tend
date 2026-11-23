// Why a provider stream stopped before a normal finish (plan WI-M2-13; AC-M2-24, AC-M2-23; review R26-F2). FR-A1,
// P-3, UX-3.
//
// `ProviderStreamReader` throws one of these. The cloud adapter (WI-M2-M4/M6) finishes its snapshot stream by
// throwing `stopReason`, so the draft stream gives `noModel` before the first draft and `interrupted` after one
// (brief Definitions, T-25). The cases describe the stream, never the person (AC-M2-23 "none blames the user"), and
// hold no banned token (AC-M2-12). They carry no provider text: no refusal wording, no error message, no output.

import Foundation

/// How the provider said it would not answer. Every signal maps to `ModelStopReason.refusal`.
public enum ProviderDeclineSignal: CaseIterable, Hashable, Sendable {
    /// OpenAI: the model streamed refusal text (`delta.refusal`) instead of the structured output.
    case refusalText
    /// Anthropic: `stop_reason` `refusal`.
    case refusalStop
    /// A provider safety or policy stop: OpenAI `finish_reason` `content_filter`; Gemini `finishReason` `SAFETY`,
    /// `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII` or `IMAGE_SAFETY`.
    case safetyStop
    /// Gemini: the request was blocked before any output (`promptFeedback.blockReason`).
    case promptBlocked
}

/// Why the output stopped before the model finished it. Every cause maps to `ModelStopReason.outputCutShort`.
public enum ProviderCutShortCause: CaseIterable, Hashable, Sendable {
    /// The provider's output-length limit: OpenAI `length`; Anthropic `max_tokens` or `model_context_window_exceeded`;
    /// Gemini `MAX_TOKENS`.
    case lengthLimit
    /// The body ended without the provider's normal end: OpenAI `finish_reason` `stop` and `data: [DONE]`; Anthropic a
    /// normal `stop_reason` and `message_stop`; Gemini `finishReason` `STOP`.
    case noFinish
    /// The body ended inside an event (a line or an event without its blank line, `ServerSentEventEnd.cutShort`).
    case bodyEndedInsideEvent
    /// The provider ended normally, but the output JSON is not finished.
    case outputUnfinished
}

/// Why the stream or its output cannot be read. Every cause maps to `ModelStopReason.unreadableOutput`.
public enum ProviderUnreadableCause: Hashable, Sendable {
    /// An event's data is not one JSON object (OpenAI's `[DONE]` aside).
    case eventNotJSON
    /// An event breaks the dialect: a wrong-typed member, output for a second choice, candidate or tool block, a delta
    /// for a block that never started or has stopped, output after the finish, a second `message_start`.
    case unexpectedStructure
    /// The output text is not valid JSON; the offset counts output bytes (`PartialJSONError.invalid`).
    case outputNotJSON(JSONSyntaxIssue, byteOffset: Int)
    /// The provider ended normally with no output text at all.
    case noOutput
    /// The body passed `ProviderStreamReader.responseByteLimit` (review R26-F2).
    case responseTooLarge
}

/// The typed error of `ProviderStreamReader`; see the file header.
public enum ProviderStreamError: Error, Hashable, Sendable {
    /// The provider would not answer (refusal, safety or policy stop, blocked request).
    case declined(ProviderDeclineSignal)
    /// Gemini `finishReason` `LANGUAGE`: the capture's language is not supported.
    case languageNotSupported
    /// The output stopped before the model finished it.
    case cutShort(ProviderCutShortCause)
    /// The stream or the output cannot be read.
    case unreadable(ProviderUnreadableCause)
    /// The provider sent an error inside the stream; the reason is read from its error type or code.
    case providerError(ModelStopReason)
    /// The provider ended the output with a finish reason that is not a normal finish and has no other mapping.
    case unexpectedFinish

    /// The neutral reason the cloud adapter throws (adapter contract rule 1, `IngestionModel`).
    public var stopReason: ModelStopReason {
        switch self {
        case .declined: .refusal
        case .languageNotSupported: .unsupportedLanguage
        case .cutShort: .outputCutShort
        case .unreadable: .unreadableOutput
        case let .providerError(reason): reason
        case .unexpectedFinish: .otherModelError
        }
    }
}
