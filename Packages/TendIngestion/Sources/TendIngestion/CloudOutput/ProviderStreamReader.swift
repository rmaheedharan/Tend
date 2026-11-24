// One provider's response body to neutral snapshots (plan WI-M2-13; AC-M2-24, AC-M2-05; review R26-F2). FR-A1, P-3.
//
// The cloud adapter (WI-M2-M4/M6, `TendAI`) hands each byte chunk of the response body to `append` and yields every
// snapshot it returns into its `IngestionModel` stream; when the transport ends normally it yields `finish()` and
// finishes. When a call throws, it finishes the stream by throwing the error's `stopReason` (adapter contract rule 1).
// So all three providers reach the draft stream through the same contract as the on-device model (AC-M2-24).
//
// The pipeline: `ServerSentEventFramer` (the bytes to events) → the provider's dialect (each event to output text and,
// optionally, a stop) → `StructuredOutputReader` (the output text to a snapshot, only finished values, J2). The rules:
// - **Order within a chunk.** Events are read in order. An event's output text is read before its stop (for example
//   the text in Gemini's last chunk, then its finish reason).
// - **A stop after new output in the same chunk** is not thrown at once: `append` returns the snapshot with that
//   output, and the next call (`append` or `finish`) throws the stop. So whether a draft is emitted before a stop never
//   depends on how the transport cut the body (a refusal after a completed item is `interrupted`, not `noModel`).
// - **Invalid output JSON** stops at its first bad byte (`outputNotJSON`, output byte offset). The valid text before
//   that byte, in the same piece, is still read, by the same "stop after new output" rule.
// - **After the provider's end** (OpenAI `[DONE]`, Anthropic `message_stop`, Gemini `finishReason` `STOP`), later
//   events and an unfinished last line are ignored.
// - **The end** (`finish`): a body that stops inside an event is `bodyEndedInsideEvent`; one without the provider's
//   normal end is `noFinish` (each dialect's `checkEnd`); a normal end with no output text is `noOutput`; with
//   unfinished output JSON, `outputUnfinished`.
// - **The response size cap (R26-F2, R29-F1).** A body that goes past `responseByteLimit` bytes (default 1 MiB) before
//   the provider's end ends with `unreadable(.responseTooLarge)`. The chunk that crosses the limit is read up to the
//   limit, and the stop follows the same hold rule as any other stop: if that part added output, `append` returns
//   its snapshot and the next call throws. So exactly the first `responseByteLimit` bytes are read, whatever the
//   chunk cuts, and the outcome does not depend on them. Bytes after the provider's end are dropped and not counted.
//   The framer's line and data buffers, the event parser and the output text each stay within the limit, whatever
//   the server sends. The 10.0 s deadline (WI-M2-14) bounds time; this bounds memory. One capture's output is a few
//   kilobytes, and the largest synthetic fixture is under 30 KB.
// - **Sticky.** After an error every call throws it again; after `finish` returns, or after the provider's end,
//   `append` reads nothing, and `finish` returns the same snapshot every time.
// Pure value type: no I/O, no clock, no logging, no network.

import Foundation

/// Reads one cloud provider's streamed response body; see the file header.
public struct ProviderStreamReader: Sendable {
    /// The default response size cap: 1 MiB (review R26-F2).
    public static let defaultResponseByteLimit = 1_048_576

    private enum Dialect: Sendable {
        case openAI(OpenAIStreamDialect)
        case anthropic(AnthropicStreamDialect)
        case gemini(GeminiStreamDialect)
    }

    public let provider: CloudProvider
    /// The most body bytes this reader accepts.
    public let responseByteLimit: Int
    /// The body bytes read so far: at most `responseByteLimit`; bytes past the limit or after the provider's end are not
    /// counted.
    public private(set) var receivedByteCount = 0

    private var framer = ServerSentEventFramer()
    private var dialect: Dialect
    private var output = StructuredOutputReader()
    private var outputByteCount = 0
    private var error: ProviderStreamError?
    private var final: IngestionSnapshot?

    public init(provider: CloudProvider, responseByteLimit: Int = ProviderStreamReader.defaultResponseByteLimit) {
        self.provider = provider
        self.responseByteLimit = max(0, responseByteLimit)
        dialect = switch provider {
        case .openAI: .openAI(OpenAIStreamDialect())
        case .anthropic: .anthropic(AnthropicStreamDialect())
        case .gemini: .gemini(GeminiStreamDialect())
        }
    }

    /// Reads the next body chunk (cut anywhere). Returns the snapshot so far when this chunk added output text, else
    /// nil. Throws the first stop; a stop that follows new output in the same chunk is thrown by the next call.
    public mutating func append(_ bytes: some Collection<UInt8>) throws(ProviderStreamError) -> IngestionSnapshot? {
        if let error { throw error }
        // After the provider's end (or `finish`), later bytes are dropped and not counted (review R29-F1 (b)).
        guard final == nil, !hasEnded else { return nil }
        // Only the part of the chunk that fits under the cap is read (review R29-F1 (a)); the rest is not counted.
        let room = responseByteLimit - receivedByteCount
        let accepted = bytes.prefix(room)
        let overLimit = bytes.count > room
        receivedByteCount += accepted.count
        var changed = false
        for event in framer.append(accepted) where !hasEnded {
            let step: DialectStep
            do throws(ProviderStreamError) {
                step = try read(event)
            } catch {
                return try stop(error, changed: changed)
            }
            if !step.output.isEmpty {
                changed = true
                if let failure = readOutput(step.output) { return try stop(failure, changed: changed) }
            }
            if let failure = step.stop { return try stop(failure, changed: changed) }
        }
        // The body goes past the cap before the provider's end: the same hold rule as any other stop (K3).
        if overLimit, !hasEnded { return try stop(.unreadable(.responseTooLarge), changed: changed) }
        return changed ? output.snapshot : nil
    }

    /// The body ended normally (the transport finished). Returns the final snapshot, or throws why the output is not
    /// finished normally.
    public mutating func finish() throws(ProviderStreamError) -> IngestionSnapshot {
        if let error { throw error }
        if let final { return final }
        let framing = framer.finish()
        if !hasEnded, framing == .cutShort { throw fail(.cutShort(.bodyEndedInsideEvent)) }
        do throws(ProviderStreamError) {
            switch dialect {
            case let .openAI(reader): try reader.checkEnd()
            case let .anthropic(reader): try reader.checkEnd()
            case let .gemini(reader): try reader.checkEnd()
            }
        } catch {
            throw fail(error)
        }
        guard outputByteCount > 0 else { throw fail(.unreadable(.noOutput)) }
        do throws(PartialJSONError) {
            let result = try output.finish()
            final = result
            return result
        } catch {
            switch error {
            case .cutShort: throw fail(.cutShort(.outputUnfinished))
            case let .invalid(issue, offset): throw fail(.unreadable(.outputNotJSON(issue, byteOffset: offset)))
            }
        }
    }

    /// Reads a whole body at once.
    public static func read(_ body: some Collection<UInt8>, provider: CloudProvider) throws(ProviderStreamError)
        -> IngestionSnapshot {
        var reader = ProviderStreamReader(provider: provider)
        _ = try reader.append(body)
        return try reader.finish()
    }

    // MARK: - Steps

    private var hasEnded: Bool {
        switch dialect {
        case let .openAI(reader): reader.hasEnded
        case let .anthropic(reader): reader.hasEnded
        case let .gemini(reader): reader.hasEnded
        }
    }

    private mutating func read(_ event: ServerSentEvent) throws(ProviderStreamError) -> DialectStep {
        switch dialect {
        case var .openAI(reader):
            defer { dialect = .openAI(reader) }
            return try reader.read(event)
        case var .anthropic(reader):
            defer { dialect = .anthropic(reader) }
            return try reader.read(event)
        case var .gemini(reader):
            defer { dialect = .gemini(reader) }
            return try reader.read(event)
        }
    }

    /// Reads output text (no snapshot is built here: `append` builds one per call, not per event, so a chunk with many
    /// events costs one snapshot; review R29-N2). On invalid JSON, the text before the bad byte is read, and the error
    /// is returned.
    private mutating func readOutput(_ text: String) -> ProviderStreamError? {
        let before = output
        do throws(PartialJSONError) {
            try output.read(bytes: text.utf8)
            outputByteCount += text.utf8.count
            return nil
        } catch {
            // `append` reports only `invalid` (`cutShort` comes from `finish`); the other branch keeps the switch total.
            guard case let .invalid(issue, offset) = error else { return .unreadable(.unexpectedStructure) }
            // Read again from the state before this piece, up to the bad byte (the prefix is valid, so this succeeds).
            output = before
            let valid = text.utf8.prefix(max(0, offset - outputByteCount))
            try? output.read(bytes: valid)
            outputByteCount += valid.count
            return .unreadable(.outputNotJSON(issue, byteOffset: offset))
        }
    }

    /// Records a stop. With new output in this chunk, returns its snapshot (the next call throws); otherwise throws.
    private mutating func stop(_ failure: ProviderStreamError, changed: Bool) throws(ProviderStreamError)
        -> IngestionSnapshot? {
        error = failure
        if changed { return output.snapshot }
        throw failure
    }

    private mutating func fail(_ failure: ProviderStreamError) -> ProviderStreamError {
        error = failure
        return failure
    }
}
