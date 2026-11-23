// The strict JSON reader and the eval instant text form (AC-M2-28 results file v1; plan WI-M2-15). FR-A1.

import Foundation
import Testing
@testable import TendIngestion

@Suite("WI-M2-15 eval JSON reader and instants (AC-M2-28)")
struct EvalJSONTests {

    @Test("reads every JSON form, keeps member order, and decodes escapes and surrogate pairs")
    func readsForms() throws {
        let text = #"{"b":[true,false,null,-12,0,"x\"\\\/\b\f\n\r\t\u00e9\ud83d\ude00"],"a":{}}"#
        let value = try EvalJSONReader.parse(Data(text.utf8))
        #expect(value == .object([
            .init("b", .array([.bool(true), .bool(false), .null, .integer(-12), .integer(0),
                               .string("x\"\\/\u{08}\u{0C}\n\r\té😀")])),
            .init("a", .object([])),
        ]))
    }

    @Test("a value written by CanonicalJSONWriter reads back to the same value and bytes")
    func roundTrip() throws {
        let value = EvalJSON.object([.init("z", .string("é\u{1}\u{7f}")), .init("a", .array([.integer(Int.min)]))])
        let bytes = try CanonicalJSONWriter.data(value.canonical)
        let back = try EvalJSONReader.parse(bytes)
        #expect(try CanonicalJSONWriter.data(back.canonical) == bytes)
    }

    @Test("rejects", arguments: [
        ("", EvalJSONError.unexpectedEnd),
        ("{\"a\":1,\"a\":2}", .duplicateKey("a", offset: 7)),
        ("1.5", .numberNotInteger(offset: 0)),
        ("1e3", .numberNotInteger(offset: 0)),
        ("01", .unexpectedByte(offset: 1)),
        ("99999999999999999999", .numberOutOfRange(offset: 0)),
        ("\"a\u{1}\"", .controlCharacterInString(offset: 2)),
        ("\"\\x\"", .invalidEscape(offset: 1)),
        ("\"\\ud800\"", .invalidEscape(offset: 1)),
        ("[1,]", .unexpectedByte(offset: 3)),
        ("{} x", .trailingContent(offset: 3)),
        ("tru", .unexpectedEnd),
    ])
    func rejects(text: String, error: EvalJSONError) {
        #expect(throws: error) { try EvalJSONReader.parse(Data(text.utf8)) }
    }

    @Test("rejects bytes that are not UTF-8, and nesting deeper than the limit")
    func rejectsBytesAndDepth() {
        #expect(throws: EvalJSONError.notUTF8) { try EvalJSONReader.parse(Data([0x22, 0xFF, 0x22])) }
        let deep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)
        #expect(throws: EvalJSONError.nestedTooDeep(offset: 64)) { try EvalJSONReader.parse(Data(deep.utf8)) }
    }

    @Test("JSON equality compares strings by Unicode scalars and objects without order")
    func jsonEquality() {
        #expect(!EvalJSON.jsonEqual(.string("é"), .string("e\u{301}")))
        #expect(EvalJSON.jsonEqual(.object([.init("a", .integer(1)), .init("b", .null)]),
                                   .object([.init("b", .null), .init("a", .integer(1))])))
        #expect(!EvalJSON.jsonEqual(.integer(1), .bool(true)))
    }

    @Test("instants: text form, millisecond rounding down, and range checks", arguments: [
        ("1970-01-01T00:00:00.000Z", Int64(0)),
        ("2026-11-22T10:15:30.123Z", Int64(1_795_342_530_123)),
        ("1969-12-31T23:59:59.999Z", Int64(-1)),
        ("2024-02-29T00:00:00.000Z", Int64(1_709_164_800_000)),
        ("0001-01-01T00:00:00.000Z", Int64(-62_135_596_800_000)),
    ])
    func instants(text: String, milliseconds: Int64) throws {
        let instant = try #require(EvalInstant(text: text))
        #expect(instant.millisecondsSince1970 == milliseconds)
        #expect(instant.text == text)
        #expect(EvalInstant(instant.date) == instant)
    }

    @Test("instants: a Date is rounded down to the millisecond; non-finite dates are refused")
    func instantFromDate() {
        #expect(EvalInstant(Date(timeIntervalSince1970: 1.0009))?.millisecondsSince1970 == 1000)
        #expect(EvalInstant(Date(timeIntervalSince1970: -0.0001))?.millisecondsSince1970 == -1)
        #expect(EvalInstant(Date(timeIntervalSinceReferenceDate: .nan)) == nil)
        #expect(EvalInstant(Date(timeIntervalSinceReferenceDate: .infinity)) == nil)
    }

    @Test("instants: every millisecond of a seeded sample round-trips through Date exactly (floor correction)")
    func instantRoundTripProperty() {
        var state: UInt64 = 0x15_EED_0001
        var count = 0
        for _ in 0..<20_000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let m = Int64(bitPattern: state >> 20) % 253_402_300_799_999
            let instant = EvalInstant(millisecondsSince1970: m)
            #expect(EvalInstant(instant.date) == instant, "seed 0x15EED0001, m \(m)")
            #expect(EvalInstant(text: instant.text) == instant, "m \(m)")
            count += 1
        }
        print("EvalInstant round trip: \(count) samples, seed 0x15EED0001")
    }

    @Test("instants: impossible or malformed text is refused", arguments: [
        "2026-13-01T00:00:00.000Z", "2026-02-29T00:00:00.000Z", "2026-04-31T00:00:00.000Z", "2026-01-01T24:00:00.000Z",
        "2026-01-01T00:60:00.000Z", "2026-01-01T00:00:60.000Z", "0000-01-01T00:00:00.000Z", "2026-01-01 00:00:00.000Z",
        "2026-01-01T00:00:00.000", "2026-01-01T00:00:00Z", "2026-1-01T00:00:00.000Z",
    ])
    func instantRefused(text: String) {
        #expect(EvalInstant(text: text) == nil)
    }

    @Test("instants: the second-only form is read only when asked")
    func secondForm() {
        #expect(EvalInstant(text: "2026-11-22T10:00:00Z", milliseconds: false)?.millisecondsSince1970 == 1_795_341_600_000)
        #expect(EvalInstant(text: "2026-11-22T10:00:00.000Z", milliseconds: false) == nil)
    }
}
