// The OpenAI stream dialect: Chat Completions with `stream: true` and a strict JSON-schema `response_format` (plan
// WI-M2-10 endpoint; WI-M2-13; AC-M2-24). FR-A1, P-3.
//
// The documented format, as read here (synthetic fixtures; real recordings are WI-M2-M6):
// - every event is `data: <chat.completion.chunk JSON>` with no event name; the body ends with `data: [DONE]`;
// - the output text is `choices[0].delta.content`, in pieces; a `null` or empty piece adds nothing;
// - a refusal streams as `choices[0].delta.refusal` text instead of content; a non-empty piece is a refusal (`null`
//   and `""` are not);
// - `choices[0].finish_reason`: `stop` is the normal finish; `length` cuts the output; `content_filter` is a safety
//   stop; any other value (`tool_calls`, `function_call`, a new one) is an unexpected finish;
// - a chunk with no `choices`, or an empty array (the `include_usage` chunk), adds nothing;
// - an `error` object inside the stream stops it: `type` `server_error` → `serviceUnavailable`, `code`
//   `rate_limit_exceeded` → `rateLimited`, anything else → `otherModelError`.
// Strict rules: only choice index 0 (a missing index counts as 0); output after the finish reason, wrong-typed members
// and a second choice are `unexpectedStructure`. The normal end needs both `finish_reason` `stop` and `[DONE]`.
// Pure value type: no I/O, no clock, no logging.

import Foundation

struct OpenAIStreamDialect: Sendable {
    static let doneMarker = "[DONE]"

    /// `[DONE]` arrived: later events are ignored.
    private(set) var hasEnded = false
    /// `finish_reason` `stop` arrived.
    private var finishedNormally = false

    mutating func read(_ event: ServerSentEvent) throws(ProviderStreamError) -> DialectStep {
        if event.data == Self.doneMarker {
            hasEnded = true
            return DialectStep()
        }
        let root = try ProviderEventJSON.object(event.data)
        if let error = root.present("error") { throw .providerError(Self.reason(forError: error)) }
        var step = DialectStep()
        for choice in try root.array("choices") ?? [] {
            let choice = try choice.requireObject()
            guard (try choice.wholeNumber("index") ?? 0) == 0 else { throw .unreadable(.unexpectedStructure) }
            if let delta = try choice.object("delta") {
                if let refusal = try delta.string("refusal"), !refusal.isEmpty {
                    step.stop = .declined(.refusalText)
                    return step
                }
                if let content = try delta.string("content"), !content.isEmpty {
                    guard !finishedNormally else { throw .unreadable(.unexpectedStructure) }
                    step.output += content
                }
            }
            if let reason = try choice.string("finish_reason") {
                switch reason {
                case "stop": finishedNormally = true
                case "length": step.stop = .cutShort(.lengthLimit)
                case "content_filter": step.stop = .declined(.safetyStop)
                default: step.stop = .unexpectedFinish
                }
                if step.stop != nil { return step }
            }
        }
        return step
    }

    /// The body ended: the normal end needs `finish_reason` `stop` and `[DONE]`.
    func checkEnd() throws(ProviderStreamError) {
        guard hasEnded, finishedNormally else { throw .cutShort(.noFinish) }
    }

    private static func reason(forError error: PartialJSONValue) -> ModelStopReason {
        if case let .string(type, true)? = error["type"], type == "server_error" { return .serviceUnavailable }
        if case let .string(code, true)? = error["code"], code == "rate_limit_exceeded" { return .rateLimited }
        return .otherModelError
    }
}
