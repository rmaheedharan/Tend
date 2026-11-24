// The Gemini stream dialect: `streamGenerateContent?alt=sse` with `responseMimeType: application/json` and the output
// schema in `responseJsonSchema` (plan WI-M2-10 endpoint; WI-M2-13; AC-M2-24). FR-A1, P-3.
//
// The request (WI-M2-10, PO WI-M2-10 ruling 7): model `gemini-3.5-flash-lite`, the output schema in the JSON-Schema
// member `responseJsonSchema` (`type` arrays with `"null"`; members in sorted key order), and
// `thinkingConfig.thinkingLevel: "minimal"`, the lowest documented level, which is not documented as zero thinking.
// The documented format, as read here (synthetic fixtures; real recordings are WI-M2-M6):
// - every event is `data: <GenerateContentResponse JSON>` with no event name and no end sentinel;
// - the output text is the `text` of each part of `candidates[0].content.parts`, in order. A part with
//   `"thought": true` is not output (none is expected without `includeThoughts`, but minimal thinking is not zero). A
//   `thought` that is not a Boolean is `unexpectedStructure`. Other part members (`thoughtSignature`) and
//   `usageMetadata` (`thoughtsTokenCount`) are ignored for drafts;
// - `candidates[0].finishReason`: `STOP` is the normal finish; `MAX_TOKENS` cuts the output; `SAFETY`,
//   `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII` and `IMAGE_SAFETY` are safety stops; `LANGUAGE` is an
//   unsupported language; anything else (`OTHER`, `MALFORMED_FUNCTION_CALL`, `FINISH_REASON_UNSPECIFIED`, a new one) is
//   an unexpected finish. The text of the chunk that carries the finish reason is read first;
// - `promptFeedback.blockReason` (any value) means the request was blocked: a refusal;
// - a chunk with no `candidates` (usage only) adds nothing;
// - an `error` object inside the stream stops it: `code` 429 → `rateLimited`, 500…599 → `serviceUnavailable`, 401 or
//   403 → `keyNotAccepted`, anything else → `otherModelError`.
// Strict rules (`unexpectedStructure`): only candidate index 0 (a missing index counts as 0); wrong-typed members.
// The normal end is `finishReason` `STOP`; events after it are ignored. Pure value type: no I/O, no clock, no logging.

import Foundation

struct GeminiStreamDialect: Sendable {
    static let safetyStops: Set<String> = ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII",
                                           "IMAGE_SAFETY"]

    /// `finishReason` `STOP` arrived: later events are ignored.
    private(set) var hasEnded = false

    mutating func read(_ event: ServerSentEvent) throws(ProviderStreamError) -> DialectStep {
        let root = try ProviderEventJSON.object(event.data)
        if let error = root.present("error") { throw .providerError(Self.reason(forError: error)) }
        if try root.object("promptFeedback")?.present("blockReason") != nil {
            return DialectStep(stop: .declined(.promptBlocked))
        }
        var step = DialectStep()
        for candidate in try root.array("candidates") ?? [] {
            let candidate = try candidate.requireObject()
            guard (try candidate.wholeNumber("index") ?? 0) == 0 else { throw .unreadable(.unexpectedStructure) }
            for part in try candidate.object("content")?.array("parts") ?? [] {
                let part = try part.requireObject()
                if try part.bool("thought") == true { continue }
                if let text = try part.string("text") { step.output += text }
            }
            if let reason = try candidate.string("finishReason") {
                switch reason {
                case "STOP": hasEnded = true
                case "MAX_TOKENS": step.stop = .cutShort(.lengthLimit)
                case "LANGUAGE": step.stop = .languageNotSupported
                case _ where Self.safetyStops.contains(reason): step.stop = .declined(.safetyStop)
                default: step.stop = .unexpectedFinish
                }
            }
        }
        return step
    }

    /// The body ended: the normal end is `finishReason` `STOP`.
    func checkEnd() throws(ProviderStreamError) {
        guard hasEnded else { throw .cutShort(.noFinish) }
    }

    private static func reason(forError error: PartialJSONValue) -> ModelStopReason {
        guard case let .number(text)? = error["code"], let code = ModelNumber.wholeNumber(jsonText: text) else {
            return .otherModelError
        }
        switch code {
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        case 401, 403: return .keyNotAccepted
        default: return .otherModelError
        }
    }
}
