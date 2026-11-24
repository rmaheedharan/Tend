// Test support for the three provider stream dialects (plan WI-M2-13; AC-M2-24, AC-M2-05). FR-A1, P-3.
//
// - `ProviderFixtures`: the synthetic fixture files under `Fixtures/M2/provider-streams/synthetic/<provider>/` and the
//   output texts they were written from (the same texts, typed again here, so a test can check that a fixture's
//   pieces join up to exactly the intended output).
// - `ProviderRead`: feeds a body to `ProviderStreamReader` cut at given offsets and records what an adapter would
//   yield: one snapshot per `append` that returned one, then the final snapshot or the error.
// - `ChunkedProviderModel`: a test-only cloud adapter over a fixed list of byte chunks (the transport is WI-M2-14 and
//   the real adapters are WI-M2-M4/M6 on the Mac). It follows the `IngestionModel` adapter contract: yield each
//   snapshot, finish normally, or throw the error's `ModelStopReason`.
// - `DialectWriter`: an independent writer of provider bodies for the property test (Swift, not the fixture
//   generator).
// Tests may read files; the module Sources may not (AC-M2-09 Rule 1).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

enum ProviderFixtures {
    /// The folder name of each provider's fixtures.
    static func folder(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        }
    }

    static func directory(_ provider: CloudProvider) -> URL {
        IngestionSourceScanTests.repositoryRoot()
            .appendingPathComponent("Fixtures/M2/provider-streams/synthetic", isDirectory: true)
            .appendingPathComponent(folder(provider), isDirectory: true)
    }

    static func load(_ provider: CloudProvider, _ name: String) throws -> [UInt8] {
        let url = directory(provider).appendingPathComponent(name + ".sse")
        return Array(try Data(contentsOf: url))
    }

    /// The fixture names on disk for a provider (without `.sse`), sorted.
    static func names(on provider: CloudProvider) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory(provider).path)
            .filter { $0.hasSuffix(".sse") }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    /// The brief's Outcome sample sentence: the input every fixture was written for (no household data).
    static let input = "The AC needs servicing before summer, we're almost out of dishwasher pods, and let's deep "
        + "clean the balcony this weekend if it doesn't rain"

    // The output texts (the generator's, without its piece markers).
    /// No room: `room` is `""`, a finished value, so the item meets rule (a) before the next item starts.
    static let item1 = #"{"title":"Service the AC","kind":"oneOff","room":"","effort":"normal","isCritical":false,"#
        + #""isDeepClean":false,"isWeatherDependent":false,"time":{"anchor":"beforeSeason","season":"summer"},"#
        + #""sourcePhrase":"The AC needs servicing before summer"}"#
    static let item2 = #"{"title":"Buy dishwasher pods","kind":"restock","room":"Kitchen","effort":"low","#
        + #""isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"time":{"anchor":"none"},"#
        + #""sourcePhrase":"almost out of dishwasher pods"}"#
    /// The title arrives last (PO WI-M2-12 ticket).
    static let item3 = #"{"kind":"oneOff","room":"Balcony","effort":"high","isCritical":false,"isDeepClean":true,"#
        + #""isWeatherDependent":true,"time":{"anchor":"thisWeekend"},"#
        + #""sourcePhrase":"deep clean the balcony this weekend","title":"Deep clean the balcony"}"#
    static let happyOutput = #"{"items":["# + item1 + "," + item2 + "," + item3 + "]}"
    static let happyTitles = ["Service the AC", "Buy dishwasher pods", "Deep clean the balcony"]

    /// Gemini's happy-path output in the `responseJsonSchema` dialect (PO WI-M2-10 ruling 7): every member, in sorted
    /// key order (so `title` is last in every item), `null` for the nullable hint members and claims.
    static let geminiHappyOutput = #"{"items":["#
        + #"{"effort":"normal","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"kind":"oneOff","#
        + #""room":"","sameAsExisting":null,"sameAsItem":null,"sourcePhrase":"The AC needs servicing before summer","#
        + #""time":{"anchor":"beforeSeason","count":null,"daypart":null,"month":null,"repeatEvery":null,"#
        + #""repeatUnit":null,"season":"summer","weekday":null},"title":"Service the AC"},"#
        + #"{"effort":"low","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"kind":"restock","#
        + #""room":"Kitchen","sameAsExisting":null,"sameAsItem":null,"sourcePhrase":"almost out of dishwasher pods","#
        + #""time":{"anchor":"none","count":null,"daypart":null,"month":null,"repeatEvery":null,"repeatUnit":null,"#
        + #""season":null,"weekday":null},"title":"Buy dishwasher pods"},"#
        + #"{"effort":"high","isCritical":false,"isDeepClean":true,"isWeatherDependent":true,"kind":"oneOff","#
        + #""room":"Balcony","sameAsExisting":null,"sameAsItem":null,"#
        + #""sourcePhrase":"deep clean the balcony this weekend","#
        + #""time":{"anchor":"thisWeekend","count":null,"daypart":null,"month":null,"repeatEvery":null,"#
        + #""repeatUnit":null,"season":null,"weekday":null},"title":"Deep clean the balcony"}"#
        + "]}"

    /// The output text a Gemini body carries: the non-thought part texts joined in order (read with Foundation's
    /// `JSONSerialization`, independently of the reader under test).
    static func geminiOutputText(_ bytes: [UInt8]) throws -> String {
        var text = ""
        for line in String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r\n") where line.hasPrefix("data: ") {
            let object = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any]
            let candidates = object?["candidates"] as? [[String: Any]] ?? []
            for candidate in candidates {
                let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                for part in parts where part["thought"] as? Bool != true { text += part["text"] as? String ?? "" }
            }
        }
        return text
    }
    /// The text of the invalid-JSON fixtures up to the bad byte (`r` of the bare word `restock`).
    static let invalidPrefix = #"{"items":["# + item1 + #",{"title":"Buy dishwasher pods","kind":"#

    /// The pipeline for the fixtures' input (rooms Kitchen and Bathroom).
    static func pipeline() -> DraftPipeline {
        StreamFixtures.pipeline(input: input)
    }
}

/// What an adapter yields for one body cut at `cuts`.
struct ProviderRead {
    var steps: [IngestionSnapshot]
    var end: Result<IngestionSnapshot, ProviderStreamError>

    /// The adapter's script: each yielded snapshot, then the final snapshot and a normal finish, or the stop reason.
    var script: [ScriptStep] {
        var script = steps.map { ScriptStep.snapshot($0.items) }
        switch end {
        case let .success(final): script += [.snapshot(final.items), .finish]
        case let .failure(error): script.append(.stop(error.stopReason))
        }
        return script
    }

    var error: ProviderStreamError? {
        if case let .failure(error) = end { return error }
        return nil
    }

    static func read(_ bytes: [UInt8], provider: CloudProvider, cuts: [Int] = [],
                     limit: Int = ProviderStreamReader.defaultResponseByteLimit) -> ProviderRead {
        var reader = ProviderStreamReader(provider: provider, responseByteLimit: limit)
        var steps: [IngestionSnapshot] = []
        var start = 0
        for cut in cuts.sorted() + [bytes.count] where cut >= start {
            do {
                if let snapshot = try reader.append(bytes[start..<cut]) { steps.append(snapshot) }
            } catch {
                return ProviderRead(steps: steps, end: .failure(error))
            }
            start = cut
        }
        do {
            return ProviderRead(steps: steps, end: .success(try reader.finish()))
        } catch {
            return ProviderRead(steps: steps, end: .failure(error))
        }
    }

    static func read(_ text: String, provider: CloudProvider, cuts: [Int] = []) -> ProviderRead {
        read(Array(text.utf8), provider: provider, cuts: cuts)
    }

    /// Cut offsets: every byte (byte by byte).
    static func everyByte(_ bytes: [UInt8]) -> [Int] { Array(1..<max(bytes.count, 1)) }

    /// Cut offsets right after each blank line (one event per chunk).
    static func eventBoundaries(_ bytes: [UInt8]) -> [Int] {
        var cuts: [Int] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                cuts.append(index + 2)
            } else if bytes[index] == 0x0A, index + 2 < bytes.count, bytes[index + 1] == 0x0D,
                      bytes[index + 2] == 0x0A {
                cuts.append(index + 3)
            }
            index += 1
        }
        return cuts
    }
}

/// A test-only cloud adapter over fixed byte chunks (the `IngestionModel` adapter contract, rule 1).
struct ChunkedProviderModel: IngestionModel {
    let provider: CloudProvider
    let chunks: [[UInt8]]
    let limit: Int

    init(provider: CloudProvider, bytes: [UInt8], cuts: [Int],
         limit: Int = ProviderStreamReader.defaultResponseByteLimit) {
        self.provider = provider
        self.limit = limit
        var chunks: [[UInt8]] = []
        var start = 0
        for cut in cuts.sorted() + [bytes.count] where cut >= start {
            chunks.append(Array(bytes[start..<cut]))
            start = cut
        }
        self.chunks = chunks
    }

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let (provider, chunks, limit) = (provider, chunks, limit)
        return AsyncThrowingStream { continuation in
            // A producer task that yields every 256 chunks, so a byte-by-byte body does not hold a cooperative-pool
            // thread for long (the time-limited cancellation tests share the pool; WI-M2-12 J9).
            let producer = Task {
                var reader = ProviderStreamReader(provider: provider, responseByteLimit: limit)
                do throws(ProviderStreamError) {
                    for (index, chunk) in chunks.enumerated() {
                        // After a cancel (the consumer stopped), stop reading (review R29-R2-N1).
                        if Task.isCancelled { return }
                        if let snapshot = try reader.append(chunk) { continuation.yield(snapshot) }
                        if index % 256 == 255 { await Task.yield() }
                    }
                    continuation.yield(try reader.finish())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error.stopReason)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

enum ProviderPipeline {
    /// The draft stream events for a body on the provider's cloud route, through the public pipeline.
    static func events(_ bytes: [UInt8], provider: CloudProvider, cuts: [Int] = [],
                       limit: Int = ProviderStreamReader.defaultResponseByteLimit,
                       pipeline: DraftPipeline = ProviderFixtures.pipeline()) async -> [DraftStreamEvent] {
        let model = ChunkedProviderModel(provider: provider, bytes: bytes, cuts: cuts, limit: limit)
        var events: [DraftStreamEvent] = []
        for await event in pipeline.events(from: .cloud(provider, model)) { events.append(event) }
        return events
    }

    static func emitted(_ events: [DraftStreamEvent]) -> [IngestionDraft] {
        events.compactMap { if case let .emitted(draft) = $0 { draft } else { nil } }
    }

    /// The last version of each draft, in `draftID` order.
    static func finalDrafts(_ events: [DraftStreamEvent]) -> [IngestionDraft] {
        var drafts: [Int: IngestionDraft] = [:]
        for event in events {
            switch event {
            case let .emitted(draft), let .updated(draft): drafts[draft.draftID] = draft
            default: break
            }
        }
        return drafts.keys.sorted().compactMap { drafts[$0] }
    }

    static func skippedCount(_ events: [DraftStreamEvent]) -> Int {
        events.filter { if case .itemSkipped = $0 { true } else { false } }.count
    }

    static func outcome(_ events: [DraftStreamEvent]) -> DraftStreamOutcome? {
        if case let .finished(outcome)? = events.last { return outcome }
        return nil
    }
}

/// Writes provider bodies from output pieces, independently of the fixture generator (for the property test).
struct DialectWriter {
    var rng: SplitMix64

    mutating func chance(_ percent: Int) -> Bool { Int.random(in: 0..<100, using: &rng) < percent }

    /// A JSON string literal for `text` (Foundation's encoder; it may write `\/`).
    static func literal(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Splits `text` into 1…12-scalar pieces (a piece never ends inside a scalar).
    mutating func pieces(of text: String) -> [String] {
        var pieces: [String] = []
        var scalars = Array(text.unicodeScalars)[...]
        while !scalars.isEmpty {
            let count = min(scalars.count, Int.random(in: 1...12, using: &rng))
            var piece = String.UnicodeScalarView()
            piece.append(contentsOf: scalars.prefix(count))
            pieces.append(String(piece))
            scalars = scalars.dropFirst(count)
        }
        return pieces
    }

    mutating func lineEnd() -> String { chance(30) ? "\r\n" : (chance(10) ? "\r" : "\n") }

    mutating func event(_ data: String, name: String? = nil) -> String {
        let end = lineEnd()
        var text = ""
        if chance(5) { text += ": comment" + end }
        if let name { text += "event: " + name + end }
        text += (chance(20) ? "data:" : "data: ") + data + end + end
        return text
    }

    mutating func body(_ provider: CloudProvider, output: String) -> String {
        let pieces = pieces(of: output)
        switch provider {
        case .openAI:
            var text = event(#"{"id":"c","object":"chat.completion.chunk","choices":[{"index":0,"delta":"#
                             + #"{"role":"assistant","content":"","refusal":null},"finish_reason":null}]}"#)
            for piece in pieces {
                if chance(10) { text += event(#"{"choices":[{"index":0,"delta":{"content":null}}]}"#) }
                text += event(#"{"choices":[{"index":0,"delta":{"content":"# + Self.literal(piece)
                              + #"},"finish_reason":null}]}"#)
            }
            text += event(#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#)
            if chance(50) { text += event(#"{"choices":[],"usage":{"total_tokens":9}}"#) }
            return text + event("[DONE]")
        case .anthropic:
            var text = event(#"{"type":"message_start","message":{"id":"m","content":[]}}"#, name: "message_start")
            text += event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","input":{}}}"#,
                          name: "content_block_start")
            for piece in pieces {
                if chance(10) { text += event(#"{"type":"ping"}"#, name: "ping") }
                text += event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","#
                              + #""partial_json":"# + Self.literal(piece) + "}}", name: "content_block_delta")
            }
            text += event(#"{"type":"content_block_stop","index":0}"#, name: "content_block_stop")
            text += event(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#, name: "message_delta")
            return text + event(#"{"type":"message_stop"}"#, name: "message_stop")
        case .gemini:
            var text = ""
            for (index, piece) in pieces.enumerated() {
                let finish = index == pieces.count - 1 ? #","finishReason":"STOP""# : ""
                var parts = #"{"text":"# + Self.literal(piece) + "}"
                if chance(10) { parts = #"{"text":"thinking","thought":true},"# + parts }
                text += event(#"{"candidates":[{"content":{"parts":["# + parts + #"],"role":"model"},"index":0"#
                              + finish + "}]}")
            }
            if pieces.isEmpty { text += event(#"{"candidates":[{"index":0,"finishReason":"STOP"}]}"#) }
            return text
        }
    }
}
