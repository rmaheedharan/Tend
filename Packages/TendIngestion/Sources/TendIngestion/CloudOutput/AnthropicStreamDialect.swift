// The Anthropic stream dialect: Messages with `stream: true` and structured output by one forced tool (plan WI-M2-10
// endpoint; WI-M2-13; AC-M2-24). FR-A1, P-3.
//
// The request (WI-M2-10, PO WI-M2-10 ruling 7): model `claude-haiku-4-5-20251001`, `anthropic-version: 2023-06-01`,
// the forced tool, no `thinking` member. The served `message.model` and the usage in `message_start` and
// `message_delta` are ignored for drafts (the drift check reads them, WI-M2-M6).
// The documented format, as read here (synthetic fixtures; real recordings are WI-M2-M6):
// - named events whose data carries the same `type`; the data's `type` is what counts (the event name is not used);
// - `message_start`, then content blocks: `content_block_start` (`index`, `content_block.type`),
//   `content_block_delta` (`index`, `delta`), `content_block_stop` (`index`); then `message_delta` with
//   `delta.stop_reason`, then `message_stop`. `ping` and unknown event types are ignored (the provider may add types);
// - the output text is the forced tool's input JSON: the `partial_json` of each `input_json_delta` for the one
//   `tool_use` block (the empty `input` object of `content_block_start` is not output). Other blocks (for example a
//   text block) are not output and are ignored;
// - `stop_reason`: `tool_use`, `end_turn` and `stop_sequence` are normal; `max_tokens` and
//   `model_context_window_exceeded` cut the output; `refusal` is a refusal; anything else (`pause_turn`, a new one) is
//   an unexpected finish. `null` is "not yet";
// - an `error` event stops the stream: `overloaded_error` and `api_error` → `serviceUnavailable`, `rate_limit_error`
//   → `rateLimited`, `authentication_error` and `permission_error` → `keyNotAccepted`, anything else →
//   `otherModelError`.
// Strict rules (`unexpectedStructure`): content or `message_delta` before `message_start`, a second `message_start`, a
// block index started twice, a delta or stop for a block that is not open, a second `tool_use` block, a tool delta that
// is not `input_json_delta` with a string `partial_json`, an event without a string `type`. The normal end needs a
// normal `stop_reason` and `message_stop`. Pure value type: no I/O, no clock, no logging.

import Foundation

struct AnthropicStreamDialect: Sendable {
    /// `message_stop` arrived: later events are ignored.
    private(set) var hasEnded = false
    private var started = false
    private var openBlocks: Set<Int> = []
    private var stoppedBlocks: Set<Int> = []
    private var toolBlock: Int?
    private var finishedNormally = false

    mutating func read(_ event: ServerSentEvent) throws(ProviderStreamError) -> DialectStep {
        let root = try ProviderEventJSON.object(event.data)
        guard let type = try root.string("type") else { throw .unreadable(.unexpectedStructure) }
        switch type {
        case "message_start":
            guard !started else { throw .unreadable(.unexpectedStructure) }
            started = true
        case "content_block_start":
            let index = try blockIndex(root, open: false)
            guard let block = try root.object("content_block"), let blockType = try block.string("type") else {
                throw .unreadable(.unexpectedStructure)
            }
            openBlocks.insert(index)
            if blockType == "tool_use" {
                guard toolBlock == nil else { throw .unreadable(.unexpectedStructure) }
                toolBlock = index
            }
        case "content_block_delta":
            let index = try blockIndex(root, open: true)
            guard index == toolBlock else { return DialectStep() }
            guard let delta = try root.object("delta"), try delta.string("type") == "input_json_delta",
                  let piece = try delta.string("partial_json") else {
                throw .unreadable(.unexpectedStructure)
            }
            return DialectStep(output: piece)
        case "content_block_stop":
            let index = try blockIndex(root, open: true)
            openBlocks.remove(index)
            stoppedBlocks.insert(index)
        case "message_delta":
            guard started else { throw .unreadable(.unexpectedStructure) }
            guard let reason = try root.object("delta")?.string("stop_reason") else { return DialectStep() }
            switch reason {
            case "tool_use", "end_turn", "stop_sequence": finishedNormally = true
            case "max_tokens", "model_context_window_exceeded": return DialectStep(stop: .cutShort(.lengthLimit))
            case "refusal": return DialectStep(stop: .declined(.refusalStop))
            default: return DialectStep(stop: .unexpectedFinish)
            }
        case "message_stop":
            guard started else { throw .unreadable(.unexpectedStructure) }
            hasEnded = true
        case "error":
            throw .providerError(Self.reason(forErrorType: root["error"]?["type"]))
        default:
            break  // `ping` and event types this dialect does not know.
        }
        return DialectStep()
    }

    /// The body ended: the normal end needs a normal `stop_reason` and `message_stop`.
    func checkEnd() throws(ProviderStreamError) {
        guard hasEnded, finishedNormally else { throw .cutShort(.noFinish) }
    }

    /// The event's block index. `open`: the block must be open now; otherwise it must never have been started.
    private func blockIndex(_ root: PartialJSONValue, open: Bool) throws(ProviderStreamError) -> Int {
        guard started, let index = try root.wholeNumber("index") else { throw .unreadable(.unexpectedStructure) }
        let isNew = !openBlocks.contains(index) && !stoppedBlocks.contains(index)
        guard open ? openBlocks.contains(index) : isNew else { throw .unreadable(.unexpectedStructure) }
        return index
    }

    private static func reason(forErrorType type: PartialJSONValue?) -> ModelStopReason {
        guard case let .string(type, true)? = type else { return .otherModelError }
        switch type {
        case "overloaded_error", "api_error": return .serviceUnavailable
        case "rate_limit_error": return .rateLimited
        case "authentication_error", "permission_error": return .keyNotAccepted
        default: return .otherModelError
        }
    }
}
