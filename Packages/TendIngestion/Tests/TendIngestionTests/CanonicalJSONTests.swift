// Canonical JSON writer: golden bytes that must be identical on Linux and Darwin (plan WI-M2-01, risk R-10; used by
// AC-M2-20 golden requests and AC-M2-28 results files). The expected bytes are written by hand from the canonical-form
// rules in `CanonicalJSON.swift`, never produced by the writer.

import Foundation
import Testing
@testable import TendIngestion

@Suite("Canonical JSON writer: byte-exact output (R-10; AC-M2-20, AC-M2-28 groundwork)")
struct CanonicalJSONTests {

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    @Test("Scalars and empty containers")
    func scalars() throws {
        #expect(try CanonicalJSONWriter.string(.null) == "null")
        #expect(try CanonicalJSONWriter.string(.bool(true)) == "true")
        #expect(try CanonicalJSONWriter.string(.bool(false)) == "false")
        #expect(try CanonicalJSONWriter.string(.integer(0)) == "0")
        #expect(try CanonicalJSONWriter.string(.integer(-42)) == "-42")
        #expect(try CanonicalJSONWriter.string(.integer(Int.max)) == "9223372036854775807")
        #expect(try CanonicalJSONWriter.string(.integer(Int.min)) == "-9223372036854775808")
        #expect(try CanonicalJSONWriter.string(.array([])) == "[]")
        #expect(try CanonicalJSONWriter.string(.object([])) == "{}")
        #expect(try CanonicalJSONWriter.string(.string("")) == "\"\"")
    }

    @Test("Keys are sorted by UTF-8 bytes, at every level, with no whitespace")
    func keyOrder() throws {
        let value = CanonicalJSON.object([
            .init("z", .integer(1)),
            .init("\u{1F600}", .integer(2)),     // F0 9F 98 80
            .init("a", .object([.init("b", .null), .init("B", .null), .init("aa", .null)])),
            .init("\u{FF5E}", .integer(3)),      // EF BD 9E (before the emoji in UTF-8, after it in UTF-16)
            .init("é", .integer(4)),             // C3 A9
            .init("e\u{0301}", .integer(5)),     // 65 CC 81: a distinct key by bytes, though == as a Swift String
            .init("B", .array([.integer(1), .bool(false), .string("x")])),
        ])
        let expected = "{\"B\":[1,false,\"x\"],\"a\":{\"B\":null,\"aa\":null,\"b\":null},\"e\u{0301}\":5,\"z\":1,"
            + "\"é\":4,\"\u{FF5E}\":3,\"\u{1F600}\":2}"
        let data = try CanonicalJSONWriter.data(value)
        #expect(data == Data(expected.utf8))
        // The same order holds whatever order the members are given in.
        if case .object(let members) = value {
            let reversed = try CanonicalJSONWriter.data(.object(members.reversed()))
            #expect(reversed == data)
        }
    }

    @Test("String escaping: quote, backslash, short escapes, other controls as lower-case \\u00XX; / and non-ASCII raw")
    func escaping() throws {
        let input = "q\" b\\ s/ \u{08}\u{09}\u{0A}\u{0C}\u{0D} \u{00}\u{01}\u{1F} \u{7F} é \u{2028}\u{2029} \u{1F3E0}"
        let data = try CanonicalJSONWriter.data(.string(input))
        // Hand-written bytes: 22 'q' 5c 22 20 'b' 5c 5c 20 's' 2f 20 \b \t \n \f \r 20 \u0000 \u0001 \u001f 20 7f 20
        // c3 a9 20 e2 80 a8 e2 80 a9 20 f0 9f 8f a0 22
        let expected = "22" + "71" + "5c22" + "20" + "62" + "5c5c" + "20" + "73" + "2f" + "20"
            + "5c62" + "5c74" + "5c6e" + "5c66" + "5c72" + "20"
            + "5c7530303030" + "5c7530303031" + "5c7530303166" + "20" + "7f" + "20"
            + "c3a9" + "20" + "e280a8" + "e280a9" + "20" + "f09f8fa0" + "22"
        #expect(Self.hex(data) == expected)
    }

    @Test("A duplicate key (equal UTF-8 bytes) is a typed error, at any depth")
    func duplicateKey() {
        #expect(throws: CanonicalJSONError.duplicateKey("k")) {
            try CanonicalJSONWriter.data(.object([.init("k", .integer(1)), .init("k", .integer(2))]))
        }
        #expect(throws: CanonicalJSONError.duplicateKey("x")) {
            try CanonicalJSONWriter.data(.array([.object([.init("x", .null), .init("y", .null), .init("x", .null)])]))
        }
    }

    @Test("A request-shaped value gives the exact golden bytes, and parses back as valid JSON")
    func goldenRequestShape() throws {
        let value = CanonicalJSON.object([
            .init("model", .string("model-id")),
            .init("stream", .bool(true)),
            .init("store", .bool(false)),
            .init("max_output_tokens", .integer(600)),
            .init("input", .array([
                .object([.init("role", .string("system")), .init("content", .string("Return JSON."))]),
                .object([.init("role", .string("user")),
                         .init("content", .string("We\u{2019}re out of dish pods / \"soon\"\nKitchen"))]),
            ])),
        ])
        let expected = #"{"input":[{"content":"Return JSON.","role":"system"},{"content":"We’re out of dish pods / \"soon\"\nKitchen","role":"user"}],"max_output_tokens":600,"model":"model-id","store":false,"stream":true}"#
        let data = try CanonicalJSONWriter.data(value)
        #expect(String(decoding: data, as: UTF8.self) == expected)
        #expect(data == Data(expected.utf8))
        #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
    }

    @Test("The writer is deterministic over many nested random values (seeded) and always gives valid JSON")
    func deterministicProperty() throws {
        var generator = SplitMix64(seed: 0x0A11_CE5E_ED00_0001)
        let cases = 2_000
        print("CanonicalJSON property: seed 0x0A11CE5EED000001, \(cases) values")
        for index in 0..<cases {
            let value = Self.randomValue(depth: 0, using: &generator)
            let first = try CanonicalJSONWriter.data(value)
            let second = try CanonicalJSONWriter.data(value)
            #expect(first == second, "case \(index)")
            let parsed = try JSONSerialization.jsonObject(with: first, options: [.fragmentsAllowed])
            _ = parsed
            #expect(!first.contains(UInt8(ascii: "\n")), "case \(index): raw newline in output")
        }
    }

    static let alphabet: [String] = ["a", "B", "z", "é", "e\u{0301}", "/", "\"", "\\", "\n", "\u{01}", "\u{1F600}",
                                     "\u{FF5E}", " ", "0", "\u{2028}"]

    static func randomString(using generator: inout SplitMix64) -> String {
        let length = Int.random(in: 0...6, using: &generator)
        return (0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }.joined()
    }

    static func randomValue(depth: Int, using generator: inout SplitMix64) -> CanonicalJSON {
        let pick = Int.random(in: 0..<(depth >= 3 ? 4 : 6), using: &generator)
        switch pick {
        case 0: return .null
        case 1: return .bool(Bool.random(using: &generator))
        case 2: return .integer(Int.random(in: Int.min...Int.max, using: &generator))
        case 3: return .string(randomString(using: &generator))
        case 4:
            let count = Int.random(in: 0...4, using: &generator)
            return .array((0..<count).map { _ in randomValue(depth: depth + 1, using: &generator) })
        default:
            var members: [CanonicalJSON.Member] = []
            var keys: Set<[UInt8]> = []
            for _ in 0..<Int.random(in: 0...4, using: &generator) {
                let key = randomString(using: &generator)
                if keys.insert(Array(key.utf8)).inserted {
                    members.append(.init(key, randomValue(depth: depth + 1, using: &generator)))
                }
            }
            return .object(members)
        }
    }
}

/// SplitMix64, a small seeded generator for property tests (the M1 test support has the same algorithm).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
