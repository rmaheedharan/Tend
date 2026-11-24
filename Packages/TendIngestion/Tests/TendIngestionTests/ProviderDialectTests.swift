// The provider stream dialects, rule by rule (plan WI-M2-13; AC-M2-24, AC-M2-05; R26-F2). FR-A1, P-3, UX-3.
//
// `ProviderStreamReader` = `ServerSentEventFramer` → the provider's dialect → `StructuredOutputReader`. These tests
// pin each dialect rule with small inline bodies; every expected error is also checked byte by byte (the result must
// not depend on how the transport cuts the body). The fixture files are in `ProviderStreamFixtureTests`.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// Small provider bodies built from output pieces.
enum Body {
    static func literal(_ text: String) -> String { DialectWriter.literal(text) }

    static func openAIContent(_ piece: String) -> String {
        "data: " + #"{"id":"c","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"#
            + literal(piece) + #"},"finish_reason":null}]}"# + "\n\n"
    }

    static func openAIFinish(_ reason: String) -> String {
        "data: " + #"{"id":"c","choices":[{"index":0,"delta":{},"finish_reason":"# + literal(reason) + "}]}\n\n"
    }

    static func openAI(_ pieces: [String], finish: String? = "stop", done: Bool = true) -> String {
        var text = "data: " + #"{"id":"c","choices":[{"index":0,"delta":{"role":"assistant","content":"","#
            + #""refusal":null},"finish_reason":null}]}"# + "\n\n"
        text += pieces.map(openAIContent).joined()
        if let finish { text += openAIFinish(finish) }
        if done { text += "data: [DONE]\n\n" }
        return text
    }

    static func anthropicEvent(_ name: String, _ json: String) -> String { "event: \(name)\ndata: \(json)\n\n" }

    static let anthropicStart = anthropicEvent("message_start", #"{"type":"message_start","message":{"id":"m"}}"#)
        + anthropicEvent("content_block_start",
                         #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","input":{}}}"#)

    static func anthropicDelta(_ piece: String, index: Int = 0) -> String {
        anthropicEvent("content_block_delta", #"{"type":"content_block_delta","index":\#(index),"#
                       + #""delta":{"type":"input_json_delta","partial_json":"# + literal(piece) + "}}")
    }

    static func anthropicStop(_ reason: String?) -> String {
        anthropicEvent("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"#
                       + (reason.map(literal) ?? "null") + "}}")
    }

    static let anthropicMessageStop = anthropicEvent("message_stop", #"{"type":"message_stop"}"#)

    static func anthropic(_ pieces: [String], stop: String? = "tool_use", end: Bool = true) -> String {
        var text = anthropicStart + pieces.map { anthropicDelta($0) }.joined()
        if end {
            text += anthropicEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
            text += anthropicStop(stop) + anthropicMessageStop
        }
        return text
    }

    static func geminiChunk(_ parts: [String], finish: String? = nil) -> String {
        let parts = parts.map { #"{"text":"# + literal($0) + "}" }.joined(separator: ",")
        let finish = finish.map { #","finishReason":"# + literal($0) } ?? ""
        return "data: " + #"{"candidates":[{"content":{"parts":["# + parts + #"],"role":"model"},"index":0"# + finish
            + "}]}\r\n\r\n"
    }

    static func gemini(_ pieces: [String], finish: String? = "STOP") -> String {
        guard let last = pieces.last else { return geminiChunk([], finish: finish) }
        return pieces.dropLast().map { geminiChunk([$0]) }.joined() + geminiChunk([last], finish: finish)
    }

    static func body(_ provider: CloudProvider, _ pieces: [String]) -> String {
        switch provider {
        case .openAI: openAI(pieces)
        case .anthropic: anthropic(pieces)
        case .gemini: gemini(pieces)
        }
    }

    /// One whole item (every rule-(a) field) and the root around it.
    static let item = #"{"title":"Mop the floor","kind":"oneOff","room":"Kitchen","effort":"low","isCritical":false,"#
        + #""isDeepClean":false,"isWeatherDependent":false,"time":{"anchor":"none"},"sourcePhrase":"mop"}"#
    static let output = #"{"items":["# + item + "]}"
}

/// Reads `body` one shot and byte by byte and expects the same error from both.
func expectStop(_ body: String, _ provider: CloudProvider, _ error: ProviderStreamError,
                sourceLocation: SourceLocation = #_sourceLocation) {
    let bytes = Array(body.utf8)
    let oneShot = ProviderRead.read(bytes, provider: provider)
    let byByte = ProviderRead.read(bytes, provider: provider, cuts: ProviderRead.everyByte(bytes))
    #expect(oneShot.error == error, sourceLocation: sourceLocation)
    #expect(byByte.error == error, sourceLocation: sourceLocation)
}

/// Reads `body` one shot and byte by byte and expects the same final snapshot.
func expectSnapshot(_ body: String, _ provider: CloudProvider, _ expected: IngestionSnapshot,
                    sourceLocation: SourceLocation = #_sourceLocation) {
    let bytes = Array(body.utf8)
    for cuts in [[], ProviderRead.everyByte(bytes)] {
        let read = ProviderRead.read(bytes, provider: provider, cuts: cuts)
        #expect(read.end == .success(expected), sourceLocation: sourceLocation)
    }
}

@Suite("AC-M2-24 provider stream reader: shared rules (framing, end, sticky errors, the response size cap R26-F2)")
struct ProviderStreamReaderTests {
    typealias B = Body

    @Test("AC-M2-24: each provider's body with the output in pieces gives the one-shot structured-output snapshot",
          arguments: CloudProvider.allCases)
    func happyBody(_ provider: CloudProvider) throws {
        let expected = try StructuredOutputReader.parse(B.output)
        let pieces = stride(from: 0, to: B.output.count, by: 5).map { start in
            String(B.output.dropFirst(start).prefix(5))
        }
        expectSnapshot(B.body(provider, pieces), provider, expected)
        let read = try ProviderStreamReader.read(Array(B.body(provider, pieces).utf8), provider: provider)
        #expect(read == expected)
        #expect(read.lookupQueries.isEmpty)  // a cloud model is never given the duplicate-lookup Tool (AC-M2-24)
    }

    @Test("AC-M2-24: every error maps to exactly one neutral stop reason (the adapter throws it)",
          arguments: [
            (ProviderStreamError.declined(.refusalText), ModelStopReason.refusal),
            (.declined(.refusalStop), .refusal), (.declined(.safetyStop), .refusal), (.declined(.promptBlocked), .refusal),
            (.languageNotSupported, .unsupportedLanguage),
            (.cutShort(.lengthLimit), .outputCutShort), (.cutShort(.noFinish), .outputCutShort),
            (.cutShort(.bodyEndedInsideEvent), .outputCutShort), (.cutShort(.outputUnfinished), .outputCutShort),
            (.unreadable(.eventNotJSON), .unreadableOutput), (.unreadable(.unexpectedStructure), .unreadableOutput),
            (.unreadable(.outputNotJSON(.invalidNumber, byteOffset: 3)), .unreadableOutput),
            (.unreadable(.noOutput), .unreadableOutput), (.unreadable(.responseTooLarge), .unreadableOutput),
            (.providerError(.rateLimited), .rateLimited), (.providerError(.serviceUnavailable), .serviceUnavailable),
            (.providerError(.keyNotAccepted), .keyNotAccepted), (.providerError(.otherModelError), .otherModelError),
            (.unexpectedFinish, .otherModelError),
          ])
    func stopReasons(_ error: ProviderStreamError, _ reason: ModelStopReason) {
        #expect(error.stopReason == reason)
    }

    @Test("AC-M2-24: an empty body, or one that ends with no provider end, is cut short (noFinish)",
          arguments: CloudProvider.allCases)
    func emptyAndUnended(_ provider: CloudProvider) {
        expectStop("", provider, .cutShort(.noFinish))
        let unended = switch provider {
        case .openAI: B.openAI([B.output], finish: nil, done: false)
        case .anthropic: B.anthropic([B.output], end: false)
        case .gemini: B.gemini([B.output], finish: nil)
        }
        expectStop(unended, provider, .cutShort(.noFinish))
    }

    @Test("AC-M2-24: a body that stops inside an event (no blank line) is cut short (bodyEndedInsideEvent)",
          arguments: CloudProvider.allCases)
    func endsInsideEvent(_ provider: CloudProvider) {
        let body = B.body(provider, [B.output])
        let lastEvent = body.dropLast(4).range(of: "data:", options: .backwards)?.upperBound ?? body.endIndex
        expectStop(String(body[..<lastEvent]), provider, .cutShort(.bodyEndedInsideEvent))
        // The last blank line without its final line end (Gemini's is CRLF: a lone trailing CR would still end it).
        expectStop(String(decoding: Array(body.utf8).dropLast(provider == .gemini ? 2 : 1), as: UTF8.self), provider,
                   .cutShort(.bodyEndedInsideEvent))
    }

    @Test("AC-M2-24: a normal provider end with unfinished output JSON is cut short (outputUnfinished)",
          arguments: CloudProvider.allCases)
    func outputUnfinished(_ provider: CloudProvider) {
        expectStop(B.body(provider, [String(B.output.dropLast(2))]), provider, .cutShort(.outputUnfinished))
    }

    @Test("AC-M2-24: a normal provider end with no output text at all is unreadable (noOutput)",
          arguments: CloudProvider.allCases)
    func noOutput(_ provider: CloudProvider) {
        expectStop(B.body(provider, []), provider, .unreadable(.noOutput))
        expectStop(B.body(provider, ["", ""]), provider, .unreadable(.noOutput))
    }

    @Test("AC-M2-24: invalid output JSON is unreadable at the output byte offset of the first bad byte",
          arguments: CloudProvider.allCases)
    func invalidOutput(_ provider: CloudProvider) {
        expectStop(B.body(provider, [#"{"items":[{"#, #""title":tx"#, "ue}]}"]), provider,
                   .unreadable(.outputNotJSON(.unexpectedByte, byteOffset: 20)))
        expectStop(B.body(provider, [#"{"items":[]}"#, " x"]), provider,
                   .unreadable(.outputNotJSON(.dataAfterValue, byteOffset: 13)))
    }

    @Test("AC-M2-24: event data that is not a JSON object is unreadable (eventNotJSON)",
          arguments: CloudProvider.allCases, [#"{"choices":"#, "[1,2]", "\"text\"", "", "{}}", "<html>"])
    func eventNotJSON(_ provider: CloudProvider, _ data: String) {
        expectStop("data: \(data)\n\n" + B.body(provider, [B.output]), provider, .unreadable(.eventNotJSON))
    }

    @Test("AC-M2-05 / AC-M2-24: valid output before a bad byte in the same piece is read, so a draft it completes is emitted and the end is interrupted, not noModel",
          arguments: CloudProvider.allCases)
    func validTextBeforeBadByte(_ provider: CloudProvider) async throws {
        let first = #"{"items":["# + String(B.item.dropLast(3))
        let second = #"p"},{"kind":restock}]}"#
        let body = Array(B.body(provider, [first, second]).utf8)
        let read = ProviderRead.read(body, provider: provider)
        #expect(read.error == .unreadable(.outputNotJSON(.unexpectedByte, byteOffset: first.utf8.count + 12)))
        #expect(read.steps.last?.items.first?.hasValueForEveryField == true)
        let events = await ProviderPipeline.events(body, provider: provider, pipeline: StreamFixtures.pipeline(input: "mop"))
        #expect(ProviderPipeline.emitted(events).map(\.title) == ["Mop the floor"])
        #expect(ProviderPipeline.outcome(events) == .interrupted(route: .cloud(provider), reason: .unreadableOutput,
                                                                discardedItem: .stoppedBeforeComplete, input: "mop"))
    }

    @Test("AC-M2-24: a stop in the same chunk as output that completes a draft is thrown on the next call, after that snapshot (refusal after a draft → interrupted)",
          arguments: CloudProvider.allCases)
    func deferredStop(_ provider: CloudProvider) async throws {
        let body = switch provider {
        case .openAI: B.openAI([B.output], finish: "content_filter")
        case .anthropic: B.anthropic([B.output], stop: "refusal")
        case .gemini: B.gemini([B.output], finish: "SAFETY")
        }
        let bytes = Array(body.utf8)
        var reader = ProviderStreamReader(provider: provider)
        let snapshot = try #require(try reader.append(bytes))
        #expect(snapshot.items.first?.title == "Mop the floor")
        let expected: ProviderStreamError = provider == .anthropic ? .declined(.refusalStop) : .declined(.safetyStop)
        #expect(throws: expected) { try reader.finish() }
        #expect(throws: expected) { try reader.append(Array("data: {}\n\n".utf8)) }
        let events = await ProviderPipeline.events(bytes, provider: provider, pipeline: StreamFixtures.pipeline(input: "mop"))
        #expect(ProviderPipeline.emitted(events).map(\.title) == ["Mop the floor"])
        #expect(ProviderPipeline.outcome(events) == .interrupted(route: .cloud(provider), reason: .refusal,
                                                                discardedItem: nil, input: "mop"))
    }

    @Test("AC-M2-24: errors are sticky; finish is idempotent; a chunk after finish reads nothing",
          arguments: CloudProvider.allCases)
    func stickyAndClosed(_ provider: CloudProvider) throws {
        var broken = ProviderStreamReader(provider: provider)
        #expect(throws: ProviderStreamError.unreadable(.eventNotJSON)) { try broken.append(Array("data: x\n\n".utf8)) }
        #expect(throws: ProviderStreamError.unreadable(.eventNotJSON)) {
            try broken.append(Array(B.body(provider, [B.output]).utf8))
        }
        #expect(throws: ProviderStreamError.unreadable(.eventNotJSON)) { try broken.finish() }

        var reader = ProviderStreamReader(provider: provider)
        _ = try reader.append(Array(B.body(provider, [B.output]).utf8))
        let final = try reader.finish()
        #expect(try reader.finish() == final)
        #expect(try reader.append(Array(B.body(provider, [B.output]).utf8)) == nil)
    }

    @Test("AC-M2-24: events after the provider's end are ignored, including a part-written last line",
          arguments: CloudProvider.allCases)
    func afterTheEnd(_ provider: CloudProvider) throws {
        let expected = try StructuredOutputReader.parse(B.output)
        let body = B.body(provider, [B.output])
        expectSnapshot(body + "data: not json\n\n" + "data: {\"items\"", provider, expected)
    }

    @Test("AC-M2-24: an append that adds no output text returns nil; one that does returns the snapshot so far",
          arguments: CloudProvider.allCases)
    func nilWithoutOutput(_ provider: CloudProvider) throws {
        var reader = ProviderStreamReader(provider: provider)
        #expect(try reader.append(Array(": comment\n\n".utf8)) == nil)
        let body = Array(B.body(provider, [#"{"items":[{"title":"A"}"#, "]}"]).utf8)
        var snapshots: [IngestionSnapshot] = []
        for byte in body { if let snapshot = try reader.append([byte]) { snapshots.append(snapshot) } }
        #expect(snapshots.map(\.items) == [[ItemSnapshot(title: "A")], [ItemSnapshot(title: "A")]])
        #expect(try reader.finish().items == [ItemSnapshot(title: "A")])
    }

    // MARK: R26-F2, the response size cap

    @Test("R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one byte more before the provider's end ends unreadable (responseTooLarge); bytes after the end are not counted; for any chunking",
          arguments: CloudProvider.allCases)
    func sizeCapBoundary(_ provider: CloudProvider) throws {
        let body = Array(B.body(provider, [B.output]).utf8)
        let expected = try StructuredOutputReader.parse(B.output)
        for cuts in [[], ProviderRead.everyByte(body), ProviderRead.eventBoundaries(body)] {
            #expect(ProviderRead.read(body, provider: provider, cuts: cuts, limit: body.count).end == .success(expected))
            // Bytes before the end (a leading comment line) push the end past the limit. (One byte is not enough for
            // Gemini: its body ends with CRLF CRLF, and a lone CR still ends the last event.)
            let over = ProviderRead.read(Array(": padding padding.\n".utf8) + body, provider: provider, cuts: cuts,
                                         limit: body.count)
            #expect(over.end == .failure(.unreadable(.responseTooLarge)))
            // Bytes after the provider's end are dropped and not counted (R29-F1 (b)).
            let tail = Array("data: {\"after\":\"the end\"}\n\n".utf8)
            let after = ProviderRead.read(body + tail + tail, provider: provider, cuts: cuts, limit: body.count)
            #expect(after.end == .success(expected))
        }
        // The chunk that crosses the limit is read up to the limit; the part past it is not counted (R29-F1 (a)).
        var reader = ProviderStreamReader(provider: provider, responseByteLimit: 10)
        _ = try reader.append(Array("0123456789".utf8.prefix(4)))
        #expect(reader.receivedByteCount == 4)
        #expect(throws: ProviderStreamError.unreadable(.responseTooLarge)) { try reader.append(Array("0123456".utf8)) }
        #expect(reader.receivedByteCount == 10)
        // After the end, append reads nothing and counts nothing.
        var ended = ProviderStreamReader(provider: provider, responseByteLimit: body.count)
        _ = try ended.append(body)
        #expect(try ended.append(Array(repeating: 0x61, count: 50)) == nil)
        #expect(ended.receivedByteCount == body.count)
        #expect(try ended.finish() == expected)
    }

    /// Review R29-F1 (a): the cap must not make the result depend on the transport's chunk cuts.
    @Test("R29-F1 / AC-M2-05 / AC-M2-24: a body past the limit whose first item completes under it gives the same drafts and outcome one shot, per event, byte by byte and at 8 random cut sets",
          .serialized, arguments: CloudProvider.allCases)
    func sizeCapChunkIndependence(_ provider: CloudProvider) async throws {
        let longTitle = String(repeating: "a", count: 200)
        let pieces = [#"{"items":["#, B.item, #",{"title":""#] + Array(repeating: longTitle, count: 30)
        let body = Array(B.body(provider, pieces).utf8)
        let limit = 2_048
        #expect(body.count > limit + 1_000)
        var rng = SplitMix64(seed: 0x29F1 &+ UInt64(body.count))
        var cutSets = [[], ProviderRead.eventBoundaries(body), ProviderRead.everyByte(body)]
        for _ in 0..<8 {
            cutSets.append((0..<Int.random(in: 1...30, using: &rng)).map { _ in Int.random(in: 0...body.count, using: &rng) })
        }
        for (index, cuts) in cutSets.enumerated() {
            let read = ProviderRead.read(body, provider: provider, cuts: cuts, limit: limit)
            #expect(read.error == .unreadable(.responseTooLarge), "cut set \(index)")
            let events = await ProviderPipeline.events(body, provider: provider, cuts: cuts, limit: limit,
                                                      pipeline: StreamFixtures.pipeline(input: "mop"))
            #expect(ProviderPipeline.emitted(events).map(\.title) == ["Mop the floor"], "cut set \(index)")
            #expect(ProviderPipeline.outcome(events) == .interrupted(route: .cloud(provider), reason: .unreadableOutput,
                                                                    discardedItem: .stoppedBeforeComplete, input: "mop"),
                    "cut set \(index)")
            await Task.yield()
        }
        // The draft is emitted even when the whole body arrives in one chunk: the hold rule (K3) returns the
        // snapshot of the part under the limit first.
        var reader = ProviderStreamReader(provider: provider, responseByteLimit: limit)
        let snapshot = try #require(try reader.append(body))
        #expect(snapshot.items.first?.hasValueForEveryField == true)
        #expect(reader.receivedByteCount == limit)
        #expect(throws: ProviderStreamError.unreadable(.responseTooLarge)) { try reader.finish() }
    }

    /// PO `po-m2-wi13.md` tickets: the two reader cases of "no provider end" (K2 confirmed).
    @Test("AC-M2-24 / AC-M2-05: finished output with no provider end: a last item that only rule (c) could complete is discarded, the earlier draft kept, interrupted",
          arguments: CloudProvider.allCases)
    func noEndDiscardsTheLastItem(_ provider: CloudProvider) async throws {
        let output = #"{"items":["# + B.item + #",{"title":"Wipe the table","kind":"oneOff"}]}"#
        let body = Array(Self.unended(provider, output).utf8)
        #expect(ProviderRead.read(body, provider: provider).error == .cutShort(.noFinish))
        let events = await ProviderPipeline.events(body, provider: provider,
                                                  pipeline: StreamFixtures.pipeline(input: "mop, wipe the table"))
        #expect(ProviderPipeline.emitted(events).map(\.title) == ["Mop the floor"])
        #expect(ProviderPipeline.outcome(events) == .interrupted(route: .cloud(provider), reason: .outputCutShort,
                                                                discardedItem: .stoppedBeforeComplete,
                                                                input: "mop, wipe the table"))
    }

    @Test("AC-M2-24: finished {\"items\":[]} with no provider end ends noModel with the plain-note offer, never completed",
          arguments: CloudProvider.allCases)
    func noEndEmptyItems(_ provider: CloudProvider) async throws {
        let body = Array(Self.unended(provider, #"{"items":[]}"#).utf8)
        #expect(ProviderRead.read(body, provider: provider).error == .cutShort(.noFinish))
        let events = await ProviderPipeline.events(body, provider: provider,
                                                  pipeline: StreamFixtures.pipeline(input: "mop"))
        guard case let .noModel(route, reason, input, note)? = ProviderPipeline.outcome(events) else {
            Issue.record("expected noModel, got \(events)")
            return
        }
        #expect(events.count == 1)
        #expect(route == .cloud(provider))
        #expect(reason == .stoppedBeforeFirstDraft(.outputCutShort))
        #expect(input == "mop")
        #expect(note?.title == "mop")
    }

    /// A body with the whole output and no provider end, cut cleanly at an event boundary.
    static func unended(_ provider: CloudProvider, _ output: String) -> String {
        switch provider {
        case .openAI: Body.openAI([output], finish: nil, done: false)
        case .anthropic: Body.anthropic([output], end: false)
        case .gemini: Body.gemini([output], finish: nil)
        }
    }

    @Test("R26-F2 / AC-M2-24: a stream with no line end (or one endless output) stops at the limit; before a draft noModel, after one interrupted",
          arguments: CloudProvider.allCases)
    func sizeCapOutcomes(_ provider: CloudProvider) async throws {
        let limit = 4_096
        let endless = [UInt8](repeating: UInt8(ascii: "a"), count: 100)
        var reader = ProviderStreamReader(provider: provider, responseByteLimit: limit)
        var stop: ProviderStreamError?
        for _ in 0..<100 {
            do { _ = try reader.append(endless) } catch { stop = error; break }
        }
        #expect(stop == .unreadable(.responseTooLarge))
        #expect(reader.receivedByteCount <= limit)

        // After a draft: the first item is whole, then an endless title.
        let longTitle = String(repeating: "a", count: 200)
        let pieces = [#"{"items":["# + B.item + #",{"title":""#] + Array(repeating: longTitle, count: 40)
        let body = Array(B.body(provider, pieces).utf8)
        let model = SizeCappedModel(provider: provider, body: body, limit: limit)
        var events: [DraftStreamEvent] = []
        for await event in StreamFixtures.pipeline(input: "mop").events(from: .cloud(provider, model)) {
            events.append(event)
        }
        #expect(ProviderPipeline.emitted(events).map(\.title) == ["Mop the floor"])
        #expect(ProviderPipeline.outcome(events) == .interrupted(route: .cloud(provider), reason: .unreadableOutput,
                                                                discardedItem: .stoppedBeforeComplete, input: "mop"))
        // Before a draft: noModel with the plain-note offer.
        let before = SizeCappedModel(provider: provider, body: Array(repeating: UInt8(ascii: "a"), count: limit + 1),
                                     limit: limit)
        var beforeEvents: [DraftStreamEvent] = []
        for await event in StreamFixtures.pipeline(input: "mop").events(from: .cloud(provider, before)) {
            beforeEvents.append(event)
        }
        guard case let .noModel(_, reason, _, note)? = ProviderPipeline.outcome(beforeEvents) else {
            Issue.record("expected noModel, got \(beforeEvents)")
            return
        }
        #expect(reason == .stoppedBeforeFirstDraft(.unreadableOutput))
        #expect(note != nil)
    }
}

/// A test adapter with a small response limit, fed in 100-byte chunks.
struct SizeCappedModel: IngestionModel {
    let provider: CloudProvider
    let body: [UInt8]
    let limit: Int

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let (provider, body, limit) = (provider, body, limit)
        return AsyncThrowingStream { continuation in
            var reader = ProviderStreamReader(provider: provider, responseByteLimit: limit)
            do throws(ProviderStreamError) {
                var start = 0
                while start < body.count {
                    let end = min(start + 100, body.count)
                    if let snapshot = try reader.append(body[start..<end]) { continuation.yield(snapshot) }
                    start = end
                }
                continuation.yield(try reader.finish())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error.stopReason)
            }
        }
    }
}

@Suite("AC-M2-24 OpenAI dialect (Chat Completions stream: data lines, choices[0].delta, finish_reason, [DONE])")
struct OpenAIDialectTests {
    typealias B = Body
    let provider = CloudProvider.openAI

    @Test("AC-M2-24: finish_reason stop then [DONE] is the only normal end; length, content_filter and others stop the stream",
          arguments: [("length", ProviderStreamError.cutShort(.lengthLimit)), ("content_filter", .declined(.safetyStop)),
                      ("tool_calls", .unexpectedFinish), ("function_call", .unexpectedFinish),
                      ("something_new", .unexpectedFinish)])
    func finishReasons(_ reason: String, _ error: ProviderStreamError) throws {
        expectSnapshot(B.openAI([B.output]), provider, try StructuredOutputReader.parse(B.output))
        expectStop(B.openAI([B.output], finish: reason), provider, error)
    }

    @Test("AC-M2-24: [DONE] without a finish reason, or a stop finish without [DONE], is cut short (noFinish)")
    func bothEndsNeeded() {
        expectStop(B.openAI([B.output], finish: nil, done: true), provider, .cutShort(.noFinish))
        expectStop(B.openAI([B.output], finish: "stop", done: false), provider, .cutShort(.noFinish))
    }

    @Test("AC-M2-24: a refusal piece stops the stream (refusal); a null or empty refusal is not one")
    func refusal() throws {
        expectSnapshot(B.openAI([B.output]), provider, try StructuredOutputReader.parse(B.output))
        let empty = "data: " + #"{"choices":[{"index":0,"delta":{"refusal":""},"finish_reason":null}]}"# + "\n\n"
        expectSnapshot(empty + B.openAI([B.output]), provider, try StructuredOutputReader.parse(B.output))
        let refusal = "data: " + #"{"choices":[{"index":0,"delta":{"refusal":"I can't help with that."}}]}"# + "\n\n"
        expectStop(refusal + B.openAI([B.output]), provider, .declined(.refusalText))
    }

    @Test("AC-M2-24: content after the finish reason, a second choice, or wrong-typed members are unexpected structure",
          arguments: [
            #"{"choices":[{"index":1,"delta":{"content":"x"}}]}"#,
            #"{"choices":{"index":0}}"#,
            #"{"choices":["x"]}"#,
            #"{"choices":[{"index":0,"delta":"x"}]}"#,
            #"{"choices":[{"index":0,"delta":{"content":5}}]}"#,
            #"{"choices":[{"index":0,"delta":{"refusal":true}}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":7}]}"#,
            #"{"choices":[{"index":"0","delta":{}}]}"#,
          ])
    func unexpectedStructure(_ event: String) {
        expectStop("data: \(event)\n\n" + B.openAI([B.output]), provider, .unreadable(.unexpectedStructure))
    }

    @Test("AC-M2-24: output text after finish_reason stop is unexpected structure")
    func contentAfterFinish() {
        let body = B.openAI([B.output], finish: "stop", done: false) + B.openAIContent(" ") + "data: [DONE]\n\n"
        expectStop(body, provider, .unreadable(.unexpectedStructure))
    }

    @Test("AC-M2-24: usage-only chunks, chunks with no choices, null content and comments are ignored")
    func ignored() throws {
        let noise = "data: " + #"{"choices":[],"usage":{"total_tokens":3}}"# + "\n\n" + ": ping\n\n"
            + "data: " + #"{"id":"c","object":"chat.completion.chunk"}"# + "\n\n"
            + "data: " + #"{"choices":[{"index":0,"delta":{"content":null}}]}"# + "\n\n"
            + "data: " + #"{"choices":[{"delta":{"content":""}}]}"# + "\n\n"
        expectSnapshot(noise + B.openAI([B.output]), provider, try StructuredOutputReader.parse(B.output))
    }

    @Test("AC-M2-24: an error object in the stream stops it with a neutral reason",
          arguments: [(#"{"error":{"type":"server_error","code":null}}"#, ModelStopReason.serviceUnavailable),
                      (#"{"error":{"type":"requests","code":"rate_limit_exceeded"}}"#, .rateLimited),
                      (#"{"error":{"type":"invalid_request_error","code":"x"}}"#, .otherModelError),
                      (#"{"error":"boom"}"#, .otherModelError)])
    func errorObject(_ event: String, _ reason: ModelStopReason) {
        expectStop(B.openAI([String(B.output.prefix(9))], finish: nil, done: false) + "data: \(event)\n\n", provider,
                   .providerError(reason))
        expectSnapshot("data: " + #"{"error":null,"choices":[]}"# + "\n\n" + B.openAI([B.output]), provider,
                       (try? StructuredOutputReader.parse(B.output)) ?? IngestionSnapshot(items: []))
    }
}

@Suite("AC-M2-24 Anthropic dialect (Messages stream with one forced tool: input_json_delta, stop_reason, message_stop)")
struct AnthropicDialectTests {
    typealias B = Body
    let provider = CloudProvider.anthropic

    @Test("AC-M2-24: stop reasons tool_use, end_turn and stop_sequence end normally; the rest stop the stream",
          arguments: [("tool_use", nil), ("end_turn", nil), ("stop_sequence", nil),
                      ("max_tokens", ProviderStreamError.cutShort(.lengthLimit)),
                      ("model_context_window_exceeded", .cutShort(.lengthLimit)), ("refusal", .declined(.refusalStop)),
                      ("pause_turn", .unexpectedFinish), ("something_new", .unexpectedFinish)] as [(String, ProviderStreamError?)])
    func stopReasons(_ reason: String, _ error: ProviderStreamError?) throws {
        let body = B.anthropic([B.output], stop: reason)
        if let error {
            expectStop(body, provider, error)
        } else {
            expectSnapshot(body, provider, try StructuredOutputReader.parse(B.output))
        }
    }

    @Test("AC-M2-24: message_stop without a stop reason is cut short (noFinish)")
    func messageStopWithoutReason() {
        expectStop(B.anthropic([B.output], stop: nil), provider, .cutShort(.noFinish))
    }

    /// PO `po-m2-wi13.md` ticket: the Anthropic partial end.
    @Test("AC-M2-24: a normal stop_reason without message_stop is cut short (noFinish), even with finished output")
    func normalStopWithoutMessageStop() {
        for reason in ["tool_use", "end_turn", "stop_sequence"] {
            let body = B.anthropic([B.output], end: false)
                + B.anthropicEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                + B.anthropicStop(reason)
            expectStop(body, provider, .cutShort(.noFinish))
        }
    }

    @Test("AC-M2-24: a text block before the tool block is ignored; pings and unknown event types are ignored; the SSE event name is not trusted over the data type")
    func ignored() throws {
        let body = B.anthropicEvent("message_start", #"{"type":"message_start","message":{}}"#)
            + B.anthropicEvent("content_block_start",
                               #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + B.anthropicEvent("content_block_delta",
                               #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"items\":[5]}"}}"#)
            + B.anthropicEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
            + B.anthropicEvent("ping", #"{"type":"ping"}"#)
            + B.anthropicEvent("content_block_start",
                               #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","input":{}}}"#)
            + B.anthropicEvent("future", #"{"type":"something_new","index":1,"delta":{"partial_json":"x"}}"#)
            + B.anthropicDelta(B.output, index: 1)
            + B.anthropicEvent("ping", #"{"type":"content_block_stop","index":1}"#)
            + B.anthropicStop("tool_use") + B.anthropicMessageStop
        expectSnapshot(body, provider, try StructuredOutputReader.parse(B.output))
    }

    @Test("AC-M2-24: deltas for a block never started or already stopped, a second tool block, a non-JSON tool delta, content before message_start, or an event without a type are unexpected structure",
          arguments: [
            Body.anthropicStart + Body.anthropicDelta("{", index: 3),
            Body.anthropicStart + Body.anthropicEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                + Body.anthropicDelta("{"),
            Body.anthropicStart + Body.anthropicEvent(
                "content_block_start",
                #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","input":{}}}"#),
            Body.anthropicStart + Body.anthropicEvent(
                "content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{"}}"#),
            Body.anthropicStart + Body.anthropicEvent(
                "content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta"}}"#),
            Body.anthropicStart + Body.anthropicEvent(
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text"}}"#),
            Body.anthropicEvent("content_block_start",
                                #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use"}}"#),
            Body.anthropicEvent("message_start", #"{"type":"message_start"}"#)
                + Body.anthropicEvent("message_start", #"{"type":"message_start"}"#),
            Body.anthropicEvent("x", #"{"index":0}"#),
            // Review R29-F3: R3 (message_delta or message_stop before message_start) and R5 (a stopped index restarted).
            Body.anthropicEvent("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#),
            Body.anthropicEvent("message_stop", #"{"type":"message_stop"}"#),
            Body.anthropicStart + Body.anthropicEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                + Body.anthropicEvent(
                    "content_block_start",
                    #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","input":{}}}"#),
            Body.anthropicStart + Body.anthropicEvent("content_block_delta", #"{"type":"content_block_delta","delta":{}}"#),
          ])
    func unexpectedStructure(_ prefix: String) {
        expectStop(prefix + Body.anthropicDelta(Body.output) + Body.anthropicStop("tool_use") + Body.anthropicMessageStop,
                   provider, .unreadable(.unexpectedStructure))
    }

    @Test("AC-M2-24: an error event stops the stream with a neutral reason",
          arguments: [("overloaded_error", ModelStopReason.serviceUnavailable), ("api_error", .serviceUnavailable),
                      ("rate_limit_error", .rateLimited), ("authentication_error", .keyNotAccepted),
                      ("permission_error", .keyNotAccepted), ("invalid_request_error", .otherModelError),
                      ("something_new", .otherModelError)])
    func errorEvent(_ type: String, _ reason: ModelStopReason) {
        let event = Body.anthropicEvent("error", #"{"type":"error","error":{"type":"\#(type)","message":"m"}}"#)
        expectStop(Body.anthropicStart + Body.anthropicDelta(#"{"items":["#) + event, provider, .providerError(reason))
    }
}

@Suite("AC-M2-24 Gemini dialect (streamGenerateContent alt=sse: candidates[0].content.parts[].text, finishReason)")
struct GeminiDialectTests {
    typealias B = Body
    let provider = CloudProvider.gemini

    @Test("AC-M2-24: finishReason STOP ends normally; the others stop the stream",
          arguments: [("MAX_TOKENS", ProviderStreamError.cutShort(.lengthLimit)), ("SAFETY", .declined(.safetyStop)),
                      ("RECITATION", .declined(.safetyStop)), ("BLOCKLIST", .declined(.safetyStop)),
                      ("PROHIBITED_CONTENT", .declined(.safetyStop)), ("SPII", .declined(.safetyStop)),
                      ("IMAGE_SAFETY", .declined(.safetyStop)), ("LANGUAGE", .languageNotSupported),
                      ("OTHER", .unexpectedFinish), ("MALFORMED_FUNCTION_CALL", .unexpectedFinish),
                      ("FINISH_REASON_UNSPECIFIED", .unexpectedFinish), ("SOMETHING_NEW", .unexpectedFinish)])
    func finishReasons(_ reason: String, _ error: ProviderStreamError) throws {
        expectSnapshot(B.gemini([B.output]), provider, try StructuredOutputReader.parse(B.output))
        expectStop(B.gemini([B.output], finish: reason), provider, error)
    }

    @Test("AC-M2-24: a blocked prompt (promptFeedback.blockReason) is a refusal; feedback without a block reason is ignored")
    func promptBlocked() throws {
        let blocked = "data: " + #"{"promptFeedback":{"blockReason":"OTHER"}}"# + "\r\n\r\n"
        expectStop(blocked, provider, .declined(.promptBlocked))
        let rated = "data: " + #"{"promptFeedback":{"blockReason":null,"safetyRatings":[]}}"# + "\r\n\r\n"
        expectSnapshot(rated + B.gemini([B.output]), provider, try StructuredOutputReader.parse(B.output))
    }

    @Test("AC-M2-24: several parts are read in order; thought parts, usage-only chunks and a null content are ignored; text in the STOP chunk is read")
    func parts() throws {
        let mid = B.output.index(B.output.startIndex, offsetBy: 20)
        let body = "data: " + #"{"candidates":[{"content":{"parts":[{"text":"x","thought":true},{"text":"#
            + B.literal(String(B.output[..<mid])) + ",\"thought\":null},{\"text\":\"\",\"thought\":false}]},\"index\":0}]}\r\n\r\n"
            + "data: " + #"{"usageMetadata":{"totalTokenCount":3}}"# + "\r\n\r\n"
            + "data: " + #"{"candidates":[{"content":null,"index":0}]}"# + "\r\n\r\n"
            + "data: " + #"{"candidates":[{"content":{"parts":[{"text":"#
            + B.literal(String(B.output[mid...])) + #"}]},"finishReason":"STOP"}]}"# + "\r\n\r\n"
        expectSnapshot(body, provider, try StructuredOutputReader.parse(B.output))
    }

    @Test("AC-M2-24: a second candidate or wrong-typed members are unexpected structure",
          arguments: [
            #"{"candidates":[{"content":{"parts":[{"text":"x"}]},"index":1}]}"#,
            #"{"candidates":{"index":0}}"#,
            #"{"candidates":[7]}"#,
            #"{"candidates":[{"content":"x","index":0}]}"#,
            #"{"candidates":[{"content":{"parts":"x"},"index":0}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":5}]},"index":0}]}"#,
            #"{"candidates":[{"content":{"parts":["x"]},"index":0}]}"#,
            #"{"candidates":[{"index":0,"finishReason":5}]}"#,
            #"{"candidates":[{"content":{"parts":[{"text":"x","thought":"yes"}]},"index":0}]}"#,  // R29-N1
          ])
    func unexpectedStructure(_ event: String) {
        expectStop("data: \(event)\r\n\r\n" + B.gemini([B.output]), provider, .unreadable(.unexpectedStructure))
    }

    @Test("AC-M2-24: an error object in the stream stops it with a neutral reason",
          arguments: [(429, ModelStopReason.rateLimited), (500, .serviceUnavailable), (503, .serviceUnavailable),
                      (401, .keyNotAccepted), (403, .keyNotAccepted), (400, .otherModelError)])
    func errorObject(_ code: Int, _ reason: ModelStopReason) {
        let event = "data: " + #"{"error":{"code":\#(code),"message":"m","status":"S"}}"# + "\r\n\r\n"
        expectStop(B.geminiChunk([#"{"items":["#]) + event, provider, .providerError(reason))
    }
}

@Suite("AC-M2-24 property: random outputs in each provider's dialect, random pieces, noise and cuts give the one-shot snapshot")
struct ProviderDialectPropertyTests {

    @Test("AC-M2-24: 3 seeds × 200 outputs × 3 providers; one shot and 2 random cut sets equal StructuredOutputReader.parse; snapshots only grow",
          .serialized, arguments: [UInt64(0x0D1A_1EC7_1301), 0x0D1A_1EC7_1302, 0x0D1A_1EC7_1303])
    func randomBodies(seed: UInt64) async throws {
        var corpus = OutputCorpus(rng: SplitMix64(seed: seed))
        var writer = DialectWriter(rng: SplitMix64(seed: seed ^ 0xFFFF))
        var cutsRNG = SplitMix64(seed: seed ^ 0xABCD)
        var counts: [CloudProvider: Int] = [:]
        for index in 0..<200 {
            let output = String(decoding: corpus.output(), as: UTF8.self)
            let expected = try StructuredOutputReader.parse(output)
            for provider in CloudProvider.allCases {
                let body = Array(writer.body(provider, output: output).utf8)
                var cutSets: [[Int]] = [[]]
                for _ in 0..<2 {
                    let count = Int.random(in: 1...30, using: &cutsRNG)
                    cutSets.append((0..<count).map { _ in Int.random(in: 0...body.count, using: &cutsRNG) })
                }
                for cuts in cutSets {
                    let read = ProviderRead.read(body, provider: provider, cuts: cuts)
                    #expect(read.end == .success(expected), "seed \(seed) case \(index) \(provider) cuts \(cuts)")
                    for (step, next) in zip(read.steps, Array(read.steps.dropFirst()) + [expected]) {
                        #expect(step.items.count <= next.items.count, "seed \(seed) case \(index) \(provider)")
                        for (item, later) in zip(step.items, next.items) {
                            #expect(item.isEarlierState(of: later), "seed \(seed) case \(index) \(provider)")
                        }
                    }
                    // One read at a time on a pool thread: the time-limited cancellation tests share the pool.
                    await Task.yield()
                }
                counts[provider, default: 0] += expected.items.count
            }
            await Task.yield()
        }
        let summary = CloudProvider.allCases.map { "\($0.rawValue) \(counts[$0, default: 0])" }.joined(separator: ", ")
        print("AC-M2-24 dialect property seed \(String(seed, radix: 16)): 200 outputs, 600 bodies, 1,800 reads; items: \(summary)")
    }
}
