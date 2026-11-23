// Server-sent-event framing (plan WI-M2-12; AC-M2-24, Linux part). FR-A1.
//
// The three provider streams (OpenAI, Anthropic, Gemini with `alt=sse`) are `text/event-stream` bodies. The framer
// turns the byte chunks the transport hands over (split anywhere, including inside a UTF-8 sequence or between the CR
// and LF of a CRLF) into whole events, following the WHATWG HTML "Server-sent events" parsing rules: CRLF, LF and CR
// line ends; `:` comments; `event`, `data`, `id` fields; one leading space after the colon removed; data lines joined
// with LF; a blank line dispatches; a leading BOM is dropped; an event that never got its blank line is not
// dispatched. The provider dialects on top (WI-M2-13) read `type` and `data`.
//
// Oracles: hand-written expected events for each rule, and for the property the events the generator meant to
// encode (it builds the event list first, then writes it out with random line ends, comments and spacing).

import Foundation
import Testing
@testable import TendIngestion

enum SSEFixtures {
    /// Feeds `bytes` in chunks cut at `cuts` (sorted offsets) and returns the events and the end.
    static func frame(_ bytes: [UInt8], cuts: [Int]) -> (events: [ServerSentEvent], end: ServerSentEventEnd) {
        var framer = ServerSentEventFramer()
        var events: [ServerSentEvent] = []
        var start = 0
        for cut in cuts + [bytes.count] where cut >= start {
            events += framer.append(bytes[start..<cut])
            start = cut
        }
        return (events, framer.finish())
    }

    static func frame(_ text: String) -> (events: [ServerSentEvent], end: ServerSentEventEnd) {
        frame(Array(text.utf8), cuts: [])
    }

    static func event(_ data: String, type: String = "message", id: String = "") -> ServerSentEvent {
        ServerSentEvent(type: type, data: data, lastEventID: id)
    }
}

@Suite("AC-M2-24 SSE framing: the event-stream rules (WHATWG), byte chunks split anywhere (FR-A1)")
struct ServerSentEventFramerTests {
    typealias S = SSEFixtures

    @Test("AC-M2-24: a data line and a blank line give one message event")
    func basic() {
        let result = S.frame("data: {\"a\":1}\n\n")
        #expect(result.events == [S.event("{\"a\":1}")])
        #expect(result.end == .complete)
    }

    @Test("AC-M2-24: the event field names the type; it resets after each dispatch")
    func eventType() {
        let result = S.frame("event: content_block_delta\ndata: x\n\ndata: y\n\n")
        #expect(result.events == [S.event("x", type: "content_block_delta"), S.event("y")])
    }

    @Test("AC-M2-24: several data lines are joined with LF; one trailing LF is removed")
    func multiLineData() {
        let result = S.frame("data: first\ndata:second\ndata\ndata:  spaced\n\n")
        #expect(result.events == [S.event("first\nsecond\n\n spaced")])
    }

    @Test("AC-M2-24: CRLF, CR and LF all end a line, in any mix")
    func lineEnds() {
        let result = S.frame("data: a\r\n\r\ndata: b\r\rdata: c\n\nevent: e\rdata: d\r\n\n")
        #expect(result.events == [S.event("a"), S.event("b"), S.event("c"), S.event("d", type: "e")])
        #expect(result.end == .complete)
    }

    @Test("AC-M2-24: a CR at the end of a chunk and its LF in the next chunk are one line end, not two")
    func splitCRLF() {
        let bytes = Array("data: a\r\ndata: b\r\n\r\n".utf8)
        let crOffsets = bytes.indices.filter { bytes[$0] == 0x0D }.map { $0 + 1 }
        for cut in crOffsets {
            #expect(S.frame(bytes, cuts: [cut]).events == [S.event("a\nb")], "cut after CR at \(cut)")
        }
    }

    @Test("AC-M2-24: comments and unknown fields are ignored; retry is ignored (no reconnection here)")
    func commentsAndUnknownFields() {
        let result = S.frame(": keep-alive\n:\nfoo: bar\nretry: 3000\ndata: x\nDATA: y\nEvent: z\n\n")
        #expect(result.events == [S.event("x")])
    }

    @Test("AC-M2-24: a field with no colon has an empty value; only one leading space is removed")
    func fieldWithoutColon() {
        #expect(S.frame("data\n\n").events == [S.event("")])
        #expect(S.frame("data:\n\n").events == [S.event("")])
        #expect(S.frame("data:   three\n\n").events == [S.event("  three")])
        #expect(S.frame("data: a: b\n\n").events == [S.event("a: b")])
    }

    @Test("AC-M2-24: a blank line with no data dispatches nothing and clears the event type")
    func blankWithoutData() {
        let result = S.frame("\n\nevent: ping\n\ndata: x\n\n")
        #expect(result.events == [S.event("x")])
    }

    @Test("AC-M2-24: the id field persists across events; an id holding NUL is ignored")
    func lastEventID() {
        let result = S.frame("id: 7\ndata: a\n\ndata: b\n\nid: x\u{0}y\ndata: c\n\nid\ndata: d\n\n")
        #expect(result.events == [S.event("a", id: "7"), S.event("b", id: "7"), S.event("c", id: "7"),
                                  S.event("d", id: "")])
    }

    @Test("AC-M2-24: one leading BOM is dropped, only at the very start of the stream, even when split")
    func byteOrderMark() {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("data: a\n\n".utf8) + [0xEF, 0xBB, 0xBF]
            + Array("data: b\n\n".utf8)
        for cut in 0...bytes.count {
            let result = S.frame(bytes, cuts: [cut])
            // The second BOM starts a line whose field name is "\u{FEFF}data", which is not a known field.
            #expect(result.events == [S.event("a")], "cut at \(cut)")
        }
    }

    @Test("AC-M2-24: a chunk split inside a UTF-8 sequence gives the same text (every cut point)")
    func splitUTF8() {
        let text = "event: d\ndata: {\"t\":\"caf\u{E9} \u{1F9FD} \u{6D17}\u{3046} e\u{301}\"}\n\n"
        let bytes = Array(text.utf8)
        let expected = [S.event("{\"t\":\"caf\u{E9} \u{1F9FD} \u{6D17}\u{3046} e\u{301}\"}", type: "d")]
        for cut in 0...bytes.count {
            #expect(S.frame(bytes, cuts: [cut]).events == expected, "cut at \(cut)")
        }
        for first in 0...bytes.count {
            for second in first...min(bytes.count, first + 6) {
                #expect(S.frame(bytes, cuts: [first, second]).events == expected, "cuts \(first), \(second)")
            }
        }
    }

    @Test("AC-M2-24: invalid UTF-8 becomes U+FFFD (the event-stream decoding rule), never a crash")
    func invalidUTF8() {
        let bytes: [UInt8] = Array("data: a".utf8) + [0xFF, 0xE2, 0x82] + Array("\n\n".utf8)
        let result = S.frame(bytes, cuts: [8])
        #expect(result.events == [S.event("a\u{FFFD}\u{FFFD}")])
    }

    @Test("AC-M2-24: a stream that ends before the blank line does not dispatch its last event and ends cut short")
    func truncation() {
        #expect(S.frame("data: a\n\ndata: b\n").events == [S.event("a")])
        #expect(S.frame("data: a\n\ndata: b\n").end == .cutShort)
        #expect(S.frame("data: a\n\ndata: b").end == .cutShort)
        #expect(S.frame("data: a\n\nevent: x\n").end == .cutShort)
        #expect(S.frame("data: a\n\n: comment\n").end == .complete)
        #expect(S.frame("data: a\n\n: unfinished comment").end == .cutShort)
        #expect(S.frame("").end == .complete)
        #expect(S.frame([0xEF, 0xBB, 0xBF], cuts: [1]) == ([], .complete))
        #expect(S.frame([0xEF, 0xBB], cuts: []).end == .cutShort)
        #expect(S.frame("data: a\n\n\u{FEFF}").end == .cutShort)
        #expect(S.frame("data: a\r").events == [])
        #expect(S.frame("data: a\r").end == .cutShort)
        #expect(S.frame("data: a\r\r").events == [S.event("a")])
        #expect(S.frame("data: a\r\r").end == .complete)
    }

    @Test("AC-M2-24: after finish the framer is closed; more bytes give no events")
    func closedAfterFinish() {
        var framer = ServerSentEventFramer()
        #expect(framer.append(Array("data: a\n".utf8)) == [])
        #expect(framer.finish() == .cutShort)
        #expect(framer.append(Array("\ndata: b\n\n".utf8)) == [])
        #expect(framer.finish() == .complete)
    }

    @Test("AC-M2-24: events come out at the chunk that completes them, not later")
    func eventsAtTheirChunk() {
        var framer = ServerSentEventFramer()
        #expect(framer.append(Array("data: a\n".utf8)) == [])
        #expect(framer.append(Array("\nda".utf8)) == [S.event("a")])
        #expect(framer.append(Array("ta: b\n\ndata: c\n\n".utf8)) == [S.event("b"), S.event("c")])
        #expect(framer.finish() == .complete)
    }
}

@Suite("AC-M2-24 SSE framing property: random event lists, random spellings and random cuts give the events meant")
struct ServerSentEventFramerPropertyTests {
    typealias S = SSEFixtures

    static let pieces = ["a", "b", "{", "}", "\"", ":", " ", "x y", "caf\u{E9}", "\u{1F9FD}", "\u{6D17}", "e\u{301}",
                         "\u{FEFF}", "\\n", "0", "data", "[DONE]"]

    /// A random event list and one random way of writing it as an event stream.
    static func randomStream(_ rng: inout SplitMix64) -> (bytes: [UInt8], events: [ServerSentEvent]) {
        var text = ""
        var events: [ServerSentEvent] = []
        var lastID = ""
        func word(_ rng: inout SplitMix64) -> String {
            (0..<Int.random(in: 0...4, using: &rng)).map { _ in pieces.randomElement(using: &rng) ?? "a" }.joined()
        }
        func end(_ rng: inout SplitMix64) -> String { ["\n", "\r\n", "\r"].randomElement(using: &rng) ?? "\n" }
        func field(_ name: String, _ value: String, _ rng: inout SplitMix64) -> String {
            if value.isEmpty, Bool.random(using: &rng) { return name + end(&rng) }
            let separator = value.hasPrefix(" ") || Bool.random(using: &rng) ? ": " : ":"
            return name + separator + value + end(&rng)
        }
        for _ in 0..<Int.random(in: 0...6, using: &rng) {
            if Int.random(in: 0...3, using: &rng) == 0 { text += ":" + word(&rng) + end(&rng) }
            let type = Bool.random(using: &rng) ? "" : ["content_block_delta", "response.output_text.delta", "ping",
                                                       "message_stop"].randomElement(using: &rng) ?? ""
            if !type.isEmpty { text += field("event", type, &rng) }
            if Int.random(in: 0...4, using: &rng) == 0 {
                lastID = String(Int.random(in: 0...999, using: &rng))
                text += field("id", lastID, &rng)
            }
            let lines = (0..<Int.random(in: 1...3, using: &rng)).map { _ in word(&rng) }
            for line in lines { text += field("data", line, &rng) }
            if Int.random(in: 0...5, using: &rng) == 0 { text += field("retry", "100", &rng) }
            // A blank line right after a CR line end: an LF there would join the CR into one CRLF line end.
            let blank = end(&rng)
            text += text.unicodeScalars.last == "\r" && blank == "\n" ? "\r\n" : blank
            events.append(ServerSentEvent(type: type.isEmpty ? "message" : type, data: lines.joined(separator: "\n"),
                                          lastEventID: lastID))
        }
        var bytes = Array(text.utf8)
        if Bool.random(using: &rng) { bytes = [0xEF, 0xBB, 0xBF] + bytes }
        return (bytes, events)
    }

    @Test("AC-M2-24: 3 seeds × 600 streams, each framed one-shot, byte by byte and at 3 random cut sets",
          arguments: [UInt64(0x55E1_2001), 0x55E1_2002, 0x55E1_2003])
    func randomCuts(seed: UInt64) async {
        var rng = SplitMix64(seed: seed)
        var eventCount = 0
        var mismatches = 0
        for streamIndex in 0..<600 {
            await Task.yield()  // do not hold a cooperative-pool thread for the whole loop
            let (bytes, expected) = Self.randomStream(&rng)
            var cutSets: [[Int]] = [[], Array(0...bytes.count)]
            for _ in 0..<3 {
                cutSets.append((0..<Int.random(in: 1...8, using: &rng))
                    .map { _ in Int.random(in: 0...bytes.count, using: &rng) }.sorted())
            }
            for cuts in cutSets {
                let result = S.frame(bytes, cuts: cuts)
                if result.events != expected || result.end != .complete {
                    mismatches += 1
                    Issue.record("seed \(seed) stream \(streamIndex) cuts \(cuts): \(result) != \(expected)")
                }
            }
            eventCount += expected.count
        }
        print("AC-M2-24 SSE property: seed \(String(seed, radix: 16)), 600 streams, \(eventCount) events, 5 cut sets each")
        #expect(mismatches == 0)
        #expect(eventCount > 1_000, "coverage: \(eventCount) events")
    }
}
