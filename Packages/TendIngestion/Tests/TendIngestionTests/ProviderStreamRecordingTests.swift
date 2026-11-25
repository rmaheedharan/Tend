// The first real provider recording: Gemini, live check L2a (plan "Real provider recordings", GR-4; WI-M2-16 DoR;
// AC-M2-24 "Fixtures (T-19)", AC-M2-05). FR-A1, P-3.
//
// On 2026-11-25 the owner sent the committed golden body `Fixtures/M2/payload/golden/g1-outcome-empty-gemini.body.json`
// (the brief's Outcome sentence, empty household) with the golden headers to `streamGenerateContent?alt=sse`. The
// reply was HTTP 200, `text/event-stream`; the response body only is saved at
// `Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse` (no request, no header, no key).
//
// These tests read that real body through the production path (`ProviderStreamReader` with the Gemini dialect, then
// `DraftPipeline` on the Gemini cloud route via the test adapter `ChunkedProviderModel`) one shot, one event per
// chunk, byte by byte and at 40 seeded random cut sets, and pin the exact result: `completed` (finishReason `STOP`
// is present, K2), 3 drafts with their fields, no skip. They also record what the body shows about the request
// profile (PO WI-M2-10 ruling 7): the served model, no `thoughtsTokenCount` (0 thinking tokens reported), and the
// trailing part with empty `text` and a `thoughtSignature`, which carries the finish and must add nothing.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

enum GeminiRecording {
    static let url = IngestionSourceScanTests.repositoryRoot()
        .appendingPathComponent("Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse")

    static func load() throws -> [UInt8] { Array(try Data(contentsOf: url)) }

    /// The output text the recording carries, typed again here from the file (the model's own wording).
    static let output = #"{"items":["#
        + #"{"effort":"normal","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"kind":"oneOff","#
        + #""room":"","sameAsExisting":null,"sameAsItem":null,"sourcePhrase":"The AC needs servicing before summer","#
        + #""time":{"anchor":"beforeSeason","count":null,"daypart":null,"month":null,"repeatEvery":null,"#
        + #""repeatUnit":null,"season":"summer","weekday":null},"title":"The AC needs servicing"},"#
        + #"{"effort":"low","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"kind":"restock","#
        + #""room":"","sameAsExisting":null,"sameAsItem":null,"sourcePhrase":"we're almost out of dishwasher pods","#
        + #""time":{"anchor":"none","count":null,"daypart":null,"month":null,"repeatEvery":null,"repeatUnit":null,"#
        + #""season":null,"weekday":null},"title":"dishwasher pods"},"#
        + #"{"effort":"high","isCritical":false,"isDeepClean":true,"isWeatherDependent":true,"kind":"oneOff","#
        + #""room":"balcony","sameAsExisting":null,"sameAsItem":null,"#
        + #""sourcePhrase":"deep clean the balcony this weekend if it doesn't rain","#
        + #""time":{"anchor":"thisWeekend","count":null,"daypart":null,"month":null,"repeatEvery":null,"#
        + #""repeatUnit":null,"season":null,"weekday":null},"title":"deep clean the balcony"}"#
        + "]}"

    static let titles = ["The AC needs servicing", "dishwasher pods", "deep clean the balcony"]

    /// The `data:` payloads of the body, parsed with Foundation (independently of the reader under test).
    static func events(_ bytes: [UInt8]) throws -> [[String: Any]] {
        try String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r\n")
            .filter { $0.hasPrefix("data: ") }
            .map { try #require(try JSONSerialization.jsonObject(with: Data($0.dropFirst(6).utf8)) as? [String: Any]) }
    }

    static func parts(_ event: [String: Any]) -> [[String: Any]] {
        let candidates = event["candidates"] as? [[String: Any]] ?? []
        return candidates.flatMap { (($0["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? [] }
    }
}

@Suite("AC-M2-24 provider stream recording (real): Gemini L2a, GR-4, through the same draft stream (FR-A1)")
struct ProviderStreamRecordingTests {
    typealias R = GeminiRecording

    @Test("AC-M2-24 / GR-4: the Gemini recording holds the response body only: no request, no header, no key")
    func responseOnly() throws {
        let text = String(decoding: try R.load(), as: UTF8.self)
        for banned in ["x-goog-api-key", "AIza", "Authorization", "Bearer", "FAKE-TEST-KEY", "HTTP/", "POST ",
                       "Content-Type", "systemInstruction", "generationConfig", "\"contents\""] {
            #expect(!text.contains(banned), "\(banned)")
        }
        // Every non-empty line is a `data:` line (CRLF framing, no event name, no comment).
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.allSatisfy { $0.hasPrefix("data: {") })
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(try R.load().count * 16 < ProviderStreamReader.defaultResponseByteLimit)
    }

    @Test("AC-M2-24 / GR-4: what the recording shows about the request profile: served model gemini-3.5-flash-lite, no thoughtsTokenCount, no thought part, a trailing empty-text part with thoughtSignature and STOP")
    func requestProfile() throws {
        let bytes = try R.load()
        let events = try R.events(bytes)
        #expect(events.count == 14)
        // One response, one served model in every event.
        #expect(events.allSatisfy { $0["modelVersion"] as? String == "gemini-3.5-flash-lite" })
        #expect(Set(events.compactMap { $0["responseId"] as? String }).count == 1)
        // No thinking reported: usageMetadata never carries thoughtsTokenCount, and the totals add up without it.
        for event in events {
            let usage = try #require(event["usageMetadata"] as? [String: Any])
            #expect(usage["thoughtsTokenCount"] == nil)
            let prompt = try #require(usage["promptTokenCount"] as? Int)
            let candidates = try #require(usage["candidatesTokenCount"] as? Int)
            #expect(usage["totalTokenCount"] as? Int == prompt + candidates)
        }
        let lastUsage = try #require(events.last?["usageMetadata"] as? [String: Any])
        #expect(lastUsage["promptTokenCount"] as? Int == 549)
        #expect(lastUsage["candidatesTokenCount"] as? Int == 297)
        #expect(lastUsage["totalTokenCount"] as? Int == 846)
        print("GR-4 L2a Gemini recording: modelVersion gemini-3.5-flash-lite; usage prompt 549, candidates 297, "
              + "total 846; thoughtsTokenCount absent (0 thinking tokens reported)")
        // No part is a thought; only the last event's part carries a thoughtSignature, with empty text.
        let allParts = events.flatMap(R.parts)
        #expect(allParts.allSatisfy { $0["thought"] == nil })
        #expect(events.dropLast().flatMap(R.parts).allSatisfy { $0["thoughtSignature"] == nil })
        let lastParts = R.parts(try #require(events.last))
        try #require(lastParts.count == 1)
        #expect(lastParts[0]["text"] as? String == "")
        #expect((lastParts[0]["thoughtSignature"] as? String)?.isEmpty == false)
        // The finish reason arrives only in that last event.
        let finishes = events.map { (($0["candidates"] as? [[String: Any]])?.first?["finishReason"] as? String) }
        #expect(finishes.dropLast().allSatisfy { $0 == nil })
        #expect(finishes.last == "STOP")
        // The joined output is exactly the typed text, and it is schema-shaped for the reader.
        #expect(try ProviderFixtures.geminiOutputText(bytes) == R.output)
    }

    @Test("AC-M2-24 / GR-4: the trailing empty-text part with thoughtSignature adds no output and gives the normal end (STOP)")
    func trailingSignaturePart() throws {
        let bytes = try R.load()
        let text = String(decoding: bytes, as: UTF8.self)
        let lastEvent = try #require(text.components(separatedBy: "\r\n\r\n").filter { !$0.isEmpty }.last)
        var dialect = GeminiStreamDialect()
        let step = try dialect.read(ServerSentEvent(type: "message", data: String(lastEvent.dropFirst(6)), lastEventID: ""))
        #expect(step.output == "")
        #expect(step.stop == nil)
        #expect(dialect.hasEnded)
        #expect(throws: Never.self) { try dialect.checkEnd() }
        // Without that last event the body has no normal end: truncated (K2), with all 3 items read.
        let withoutLast = Array(bytes.prefix(bytes.count - lastEvent.utf8.count - 4))
        #expect(withoutLast.count + lastEvent.utf8.count + 4 == bytes.count)
        let cut = ProviderRead.read(withoutLast, provider: .gemini)
        #expect(cut.error == .cutShort(.noFinish))
        #expect(cut.steps.last == (try StructuredOutputReader.parse(R.output)))
    }

    @Test("AC-M2-24 / AC-M2-05 / GR-4: the Gemini recording gives completed, the 3 titles in order and no skip through DraftPipeline on the Gemini cloud route")
    func outcome() async throws {
        let bytes = try R.load()
        let read = ProviderRead.read(bytes, provider: .gemini)
        #expect(read.error == nil)
        #expect(try read.end.get() == StructuredOutputReader.parse(R.output))
        #expect(try read.end.get().items.map(\.title) == R.titles)

        let events = await ProviderPipeline.events(bytes, provider: .gemini)
        #expect(ProviderPipeline.emitted(events).map(\.title) == R.titles)
        #expect(ProviderPipeline.finalDrafts(events).map(\.title) == R.titles)
        #expect(ProviderPipeline.skippedCount(events) == 0)
        #expect(!events.contains { if case .updated = $0 { true } else { false } })
        #expect(events.filter { if case .finished = $0 { true } else { false } }.count == 1)
        #expect(ProviderPipeline.outcome(events) == .completed(route: .cloud(.gemini)))
    }

    @Test("AC-M2-24 / AC-M2-04 / GR-4: the recording's drafts: no room, no room, a proposed room; kinds, efforts, flags and source phrases as sent")
    func drafts() async throws {
        let events = await ProviderPipeline.events(try R.load(), provider: .gemini)
        let drafts = ProviderPipeline.finalDrafts(events)
        try #require(drafts.count == 3)
        #expect(drafts.map(\.draftID) == [1, 2, 3])
        #expect(drafts.map(\.room) == [.none, .none, .proposed("balcony")])
        #expect(drafts.map(\.kind) == [.oneOff, .restock, .oneOff])
        #expect(drafts.map(\.effort) == [.normal, .low, .high])
        #expect(drafts.map(\.isCritical) == [false, false, false])
        #expect(drafts.map(\.isDeepClean) == [false, false, true])
        #expect(drafts.map(\.isWeatherDependent) == [false, false, true])
        #expect(drafts.map(\.recurrenceIntervalDays) == [nil, nil, nil])
        #expect(drafts.map(\.sourcePhrase) == ["The AC needs servicing before summer",
                                               "we're almost out of dishwasher pods",
                                               "deep clean the balcony this weekend if it doesn't rain"])
        #expect(drafts.map(\.duplicate) == [.none, .none, .none])
    }

    @Test("AC-M2-24 / GR-4: the recording gives the same result one shot, one event per chunk, byte by byte and at 40 seeded random cut sets (reader and pipeline: all 42)")
    func splitChunks() async throws {
        let bytes = try R.load()
        let oneShot = ProviderRead.read(bytes, provider: .gemini)
        let oneShotEvents = await ProviderPipeline.events(bytes, provider: .gemini)
        let seed = 0x6E3A11A2A ^ UInt64(bytes.count)
        var rng = SplitMix64(seed: seed)
        let boundaries = ProviderRead.eventBoundaries(bytes)
        // A cut after each of the 14 events (the last cut is the body's end).
        #expect(boundaries.count == 14)
        #expect(boundaries.last == bytes.count)
        var cutSets = [boundaries, ProviderRead.everyByte(bytes)]
        for _ in 0..<40 {
            let count = Int.random(in: 1...40, using: &rng)
            cutSets.append((0..<count).map { _ in Int.random(in: 0...bytes.count, using: &rng) })
        }
        let finished = Set(R.titles)
        for (index, cuts) in cutSets.enumerated() {
            let read = ProviderRead.read(bytes, provider: .gemini, cuts: cuts)
            #expect(read.end == oneShot.end, "cut set \(index), seed \(seed)")
            #expect(read.steps.last == oneShot.steps.last, "cut set \(index), seed \(seed)")
            // No step ever shows part of a title.
            for step in read.steps {
                for item in step.items {
                    if let title = item.title { #expect(finished.contains(title), "part title \(title), cut set \(index)") }
                }
            }
            let events = await ProviderPipeline.events(bytes, provider: .gemini, cuts: cuts)
            #expect(ProviderPipeline.emitted(events).map(\.title) == R.titles, "cut set \(index), seed \(seed)")
            #expect(ProviderPipeline.finalDrafts(events) == ProviderPipeline.finalDrafts(oneShotEvents),
                    "cut set \(index), seed \(seed)")
            #expect(ProviderPipeline.skippedCount(events) == 0, "cut set \(index), seed \(seed)")
            #expect(ProviderPipeline.outcome(events) == .completed(route: .cloud(.gemini)), "cut set \(index), seed \(seed)")
            await Task.yield()
        }
    }
}
