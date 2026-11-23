// The incremental JSON parser under the structured-output reader (plan WI-M2-12; AC-M2-24, Linux part). FR-A1.
//
// It reads a growing JSON text (RFC 8259, UTF-8) byte by byte and can give, after any chunk, the value read so far:
// containers and strings may be open (`isComplete: false`); a number, `true`, `false` or `null` appears only once it
// is finished. Bytes may be cut anywhere: inside a UTF-8 sequence, an escape, a surrogate pair, a number, a key or a
// literal. Invalid JSON is a typed error with the byte offset, never a crash; a text that ends early is `cutShort`.
//
// Oracles: hand-written values for each rule, and Foundation's `JSONDecoder` on the complete text for the property
// (a different parser: it decodes into `OracleJSON` below, written for this test).

import Foundation
import Testing
@testable import TendIngestion

/// An independent JSON value, decoded by Foundation's `JSONDecoder` (the oracle). A number is kept as its whole-number
/// reading, taken from `Decimal` (exact for up to 38 digits) or, when `Decimal` cannot hold it, from `Double`.
///
/// Where `JSONDecoder` and RFC 8259 differ, the tests that compare acceptance allow exactly these, and nothing else
/// (dev-notes WI-M2-12, J4): it accepts a trailing comma before `]` or `}` (RFC: invalid; this parser rejects it); it
/// rejects a number beyond `Double`'s range such as `1e400` (RFC: valid; this parser reads it as a number, and the
/// reader maps it to nil); it reads duplicate names (RFC leaves it open; this parser rejects them); it reads a
/// leading BOM (RFC: a MAY; this parser rejects it).
indirect enum OracleJSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Int?)
    case string(String)
    case array([OracleJSON])
    case object([String: OracleJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let flag = try? container.decode(Bool.self) { self = .bool(flag); return }
        if let text = try? container.decode(String.self) { self = .string(text); return }
        if let decimal = try? container.decode(Decimal.self) { self = .number(Self.whole(decimal)); return }
        if let number = try? container.decode(Double.self) { self = .number(ModelNumber.wholeNumber(number)); return }
        if let elements = try? container.decode([OracleJSON].self) { self = .array(elements); return }
        self = .object(try container.decode([String: OracleJSON].self))
    }

    /// A whole `Decimal` that fits in `Int`, read through its decimal text; otherwise nil.
    static func whole(_ decimal: Decimal) -> Int? {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded == decimal, decimal >= Decimal(Int.min), decimal <= Decimal(Int.max) else { return nil }
        return Int(decimal.description)
    }

    static func decode(_ bytes: [UInt8]) -> OracleJSON? {
        try? JSONDecoder().decode(OracleJSON.self, from: Data(bytes))
    }

    /// True when `bytes` hold an exponent number that `Double` cannot hold (the oracle rejects those).
    static func hasNumberBeyondDouble(_ bytes: [UInt8]) -> Bool {
        let text = String(decoding: bytes, as: UTF8.self)
        guard let pattern = try? NSRegularExpression(pattern: #"-?[0-9]+(\.[0-9]+)?[eE][+-]?[0-9]+"#) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).contains { match in
            guard let span = Range(match.range, in: text), let value = Double(text[span]) else { return true }
            return !value.isFinite
        }
    }

    /// True when the byte at `offset` is `]` or `}` and the last non-whitespace byte before it is `,`.
    static func isTrailingComma(_ bytes: [UInt8], at offset: Int) -> Bool {
        guard offset < bytes.count, bytes[offset] == UInt8(ascii: "]") || bytes[offset] == UInt8(ascii: "}") else {
            return false
        }
        let before = bytes[..<offset].last { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return before == UInt8(ascii: ",")
    }
}

enum JSONFixtures {
    /// Parses `bytes` cut at `cuts`; returns the value after each chunk and the final result.
    static func parse(_ bytes: [UInt8], cuts: [Int] = [])
        -> (steps: [PartialJSONValue?], final: Result<PartialJSONValue, PartialJSONError>) {
        var parser = PartialJSONParser()
        var steps: [PartialJSONValue?] = []
        var start = 0
        for cut in cuts + [bytes.count] where cut >= start {
            do {
                try parser.append(bytes[start..<cut])
            } catch {
                return (steps, .failure(error))
            }
            steps.append(parser.value)
            start = cut
        }
        do {
            return (steps, .success(try parser.finish()))
        } catch {
            return (steps, .failure(error))
        }
    }

    static func parse(_ text: String) -> Result<PartialJSONValue, PartialJSONError> {
        parse(Array(text.utf8)).final
    }

    /// The value after appending `text` without finishing.
    static func partial(_ text: String) -> PartialJSONValue? {
        var parser = PartialJSONParser()
        do { try parser.append(Array(text.utf8)) } catch { return nil }
        return parser.value
    }

    static func string(_ text: String, _ complete: Bool = true) -> PartialJSONValue { .string(text, isComplete: complete) }
    static func object(_ members: [(String, PartialJSONValue)], _ complete: Bool = true) -> PartialJSONValue {
        .object(members.map { PartialJSONMember(key: $0.0, value: $0.1) }, isComplete: complete)
    }
}

@Suite("AC-M2-24 incremental JSON parser: values, partial values, cuts anywhere, typed errors (FR-A1)")
struct PartialJSONParserTests {
    typealias J = JSONFixtures

    @Test("AC-M2-24: complete values of every kind")
    func completeValues() throws {
        let text = #" { "a" : [1, -2.5e3, true, false, null, "x\"\\\/\b\f\n\r\t\u00e9\ud83e\uddfd"], "b": {} , "c":[] } "#
        let value = try J.parse(text).get()
        let expected = J.object([
            ("a", .array([.number("1"), .number("-2.5e3"), .bool(true), .bool(false), .null,
                          J.string("x\"\\/\u{8}\u{C}\n\r\t\u{E9}\u{1F9FD}")], isComplete: true)),
            ("b", J.object([])),
            ("c", .array([], isComplete: true)),
        ])
        #expect(value == expected)
        #expect(value.isComplete)
    }

    @Test("AC-M2-24: a root scalar is a value too; a root number completes at finish")
    func rootScalars() throws {
        #expect(try J.parse("\"x\"").get() == J.string("x"))
        #expect(try J.parse("12").get() == .number("12"))
        #expect(try J.parse(" null ").get() == .null)
        #expect(J.partial("12") == nil)
    }

    @Test("AC-M2-24: open containers and open strings are visible while they grow")
    func partialValues() {
        #expect(J.partial("") == nil)
        #expect(J.partial("  ") == nil)
        #expect(J.partial("{") == J.object([], false))
        #expect(J.partial("{\"ti") == J.object([], false))
        #expect(J.partial("{\"title\"") == J.object([], false))
        #expect(J.partial("{\"title\":") == J.object([], false))
        #expect(J.partial("{\"title\": \"") == J.object([("title", J.string("", false))], false))
        #expect(J.partial("{\"title\": \"Buy di") == J.object([("title", J.string("Buy di", false))], false))
        #expect(J.partial("{\"title\": \"Buy\", \"n\": [1, {\"k\": tr")
                == J.object([("title", J.string("Buy")),
                             ("n", .array([.number("1"), J.object([], false)], isComplete: false))], false))
    }

    @Test("AC-M2-24: a number, true, false and null appear only when finished")
    func scalarsOnlyWhenFinished() {
        #expect(J.partial("[1") == .array([], isComplete: false))
        #expect(J.partial("[12") == .array([], isComplete: false))
        #expect(J.partial("[12,") == .array([.number("12")], isComplete: false))
        #expect(J.partial("[12 ") == .array([.number("12")], isComplete: false))
        #expect(J.partial("[1.5e") == .array([], isComplete: false))
        #expect(J.partial("[tru") == .array([], isComplete: false))
        #expect(J.partial("[true") == .array([.bool(true)], isComplete: false))
        #expect(J.partial("[nul") == .array([], isComplete: false))
        #expect(J.partial("[null") == .array([.null], isComplete: false))
    }

    @Test("AC-M2-24: an open string never shows half a UTF-8 sequence, half an escape or half a surrogate pair")
    func partialStringsAreWhole() {
        let bytes = Array("[\"a\u{E9}\u{1F9FD}\\n\\u00e9\\ud83e\\uddfdz\"]".utf8)
        let expectedPrefixes = ["", "a", "a\u{E9}", "a\u{E9}\u{1F9FD}", "a\u{E9}\u{1F9FD}\n",
                                "a\u{E9}\u{1F9FD}\n\u{E9}", "a\u{E9}\u{1F9FD}\n\u{E9}\u{1F9FD}",
                                "a\u{E9}\u{1F9FD}\n\u{E9}\u{1F9FD}z"]
        var parser = PartialJSONParser()
        var seen: [String] = []
        for byte in bytes {
            #expect(throws: Never.self) { try parser.append([byte]) }
            if case let .array(elements, _)? = parser.value, case let .string(text, _)? = elements.first,
               seen.last != text {
                seen.append(text)
            }
        }
        #expect(seen == expectedPrefixes)
    }

    @Test("AC-M2-24: every cut point (1 and 2 cuts) gives the one-shot value; each step is never ahead of it")
    func everyCut() throws {
        let text = #"{"items":[{"title":"Caf\u00e9 \"pods\" \ud83e\uddfd","n":-12.5E+2,"ok":true,"z":null},"# +
            #"{"title":"洗う e\#u{301}","arr":[0,[],{}]}],"x":false}"#
        let bytes = Array(text.utf8)
        let oneShot = try J.parse(bytes).final.get()
        for first in 0...bytes.count {
            #expect(try J.parse(bytes, cuts: [first]).final.get() == oneShot, "cut \(first)")
        }
        for first in stride(from: 0, through: bytes.count, by: 3) {
            for second in first...bytes.count {
                let result = J.parse(bytes, cuts: [first, second])
                #expect(try result.final.get() == oneShot, "cuts \(first), \(second)")
            }
        }
        let byteByByte = J.parse(bytes, cuts: Array(0...bytes.count))
        #expect(try byteByByte.final.get() == oneShot)
        for (index, step) in byteByByte.steps.enumerated() {
            #expect(step.map { $0.isPrefix(of: oneShot) } ?? true, "step \(index)")
        }
    }

    @Test("AC-M2-24: invalid JSON is a typed error with the byte offset of the first bad byte",
          arguments: [
            ("{]", JSONSyntaxIssue.unexpectedByte, 1),
            ("[1,]", .unexpectedByte, 3),
            ("{\"a\" 1}", .unexpectedByte, 5),
            ("{\"a\":1,}", .unexpectedByte, 7),
            ("{a:1}", .unexpectedByte, 1),
            ("[01]", .invalidNumber, 3),
            ("[1.]", .invalidNumber, 3),
            ("[-]", .invalidNumber, 2),
            ("[1e]", .invalidNumber, 3),
            ("[+1]", .unexpectedByte, 1),
            ("[.5]", .unexpectedByte, 1),
            ("[1-2]", .invalidNumber, 4),
            ("[tru]", .unexpectedByte, 4),
            ("[nulll]", .unexpectedByte, 5),
            ("[True]", .unexpectedByte, 1),
            ("[\"a\\x\"]", .invalidEscape, 4),
            ("[\"a\\u12g4\"]", .invalidEscape, 7),
            ("[\"\\ud83e\"]", .unpairedSurrogate, 8),
            ("[\"\\ud83ex\"]", .unpairedSurrogate, 8),
            ("[\"\\ud83e\\n\"]", .unpairedSurrogate, 9),
            ("[\"\\ud83e\\u0041\"]", .unpairedSurrogate, 13),
            ("[\"\\ud83e\\ue000\"]", .unpairedSurrogate, 13),
            ("[\"\\udc00\"]", .unpairedSurrogate, 7),
            ("[\"a\tb\"]", .controlCharacterInString, 3),
            ("{\"a\":1,\"a\":2}", .duplicateKey, 9),
            ("{} {}", .dataAfterValue, 3),
            ("[] x", .dataAfterValue, 3),
            ("1 2", .dataAfterValue, 2),
            ("\u{FEFF}{}", .unexpectedByte, 0),
          ])
    func invalidJSON(_ text: String, _ issue: JSONSyntaxIssue, _ offset: Int) {
        let bytes = Array(text.utf8)
        for cut in 0...bytes.count {
            let result = J.parse(bytes, cuts: [cut]).final
            #expect(result == .failure(.invalid(issue, byteOffset: offset)), "\(text) cut \(cut)")
        }
        // The oracle rejects it too, except where RFC 8259 leaves the choice to the parser: duplicate names (a SHOULD)
        // and a leading BOM (a MAY). This parser rejects both (dev-notes WI-M2-12, J4).
        if issue != .duplicateKey && bytes.first != 0xEF && !OracleJSON.isTrailingComma(bytes, at: offset) {
            #expect(OracleJSON.decode(bytes) == nil, "the oracle rejects it too: \(text)")
        }
    }

    @Test("AC-M2-24: invalid UTF-8 inside a string is a typed error at the bad byte",
          arguments: [
            ([0xFF], 2), ([0xC0, 0x80], 2), ([0xC1, 0xBF], 2), ([0xE0, 0x80, 0x80], 3), ([0xED, 0xA0, 0x80], 3),
            ([0xF0, 0x80, 0x80, 0x80], 3), ([0xF4, 0x90, 0x80, 0x80], 3), ([0xF5, 0x80], 2), ([0xC3, 0x41], 3),
            ([0x80], 2), ([0xE2, 0x82, 0x41], 4),
          ] as [([UInt8], Int)])
    func invalidUTF8(_ inner: [UInt8], _ offset: Int) {
        let bytes = Array("[\"".utf8) + inner + Array("\"]".utf8)
        for cut in 0...bytes.count {
            #expect(J.parse(bytes, cuts: [cut]).final == .failure(.invalid(.invalidUTF8, byteOffset: offset)),
                    "\(inner) cut \(cut)")
        }
    }

    @Test("AC-M2-24: valid multi-byte UTF-8 at every length and boundary is accepted",
          arguments: ["\u{80}", "\u{7FF}", "\u{800}", "\u{D7FF}", "\u{E000}", "\u{FFFF}", "\u{10000}", "\u{10FFFF}",
                      "\u{7F}"])
    func validUTF8(_ scalar: String) throws {
        #expect(try J.parse("[\"" + scalar + "\"]").get() == .array([J.string(scalar)], isComplete: true))
    }

    @Test("AC-M2-24: every proper prefix of a valid text reads without error and finishes cutShort")
    func truncation() throws {
        let text = #"{"items":[{"title":"a\u00e9\ud83e\uddfd","n":12,"t":true}],"z":null}"#
        let bytes = Array(text.utf8)
        for length in 0..<bytes.count {
            #expect(J.parse(Array(bytes[0..<length])).final == .failure(.cutShort), "length \(length)")
        }
        #expect(try J.parse(bytes).final.get().isComplete)
    }

    @Test("AC-M2-24: nesting deeper than the limit is a typed error, not a deep recursion")
    func nestingLimit() throws {
        let limit = PartialJSONParser.maximumDepth
        let ok = String(repeating: "[", count: limit) + String(repeating: "]", count: limit)
        #expect(try J.parse(ok).get().isComplete)
        let deep = String(repeating: "[", count: 100_000)
        #expect(J.parse(deep) == .failure(.invalid(.nestingTooDeep, byteOffset: limit)))
    }

    @Test("AC-M2-24: after an error or finish the parser is closed and gives the same result again")
    func sticky() {
        var parser = PartialJSONParser()
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try parser.append(Array("[}".utf8)) }
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try parser.append(Array("]".utf8)) }
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try parser.finish() }

        var done = PartialJSONParser()
        #expect(throws: Never.self) { try done.append(Array("[1]".utf8)) }
        #expect(throws: Never.self) { try done.finish() }
        #expect(throws: PartialJSONError.invalid(.dataAfterValue, byteOffset: 3)) { try done.append(Array("x".utf8)) }
    }

    @Test("AC-M2-24: the typed errors map to the neutral stop reasons (invalid → unreadableOutput, cut short → outputCutShort)")
    func stopReasons() {
        #expect(PartialJSONError.cutShort.stopReason == .outputCutShort)
        for issue in JSONSyntaxIssue.allCases {
            #expect(PartialJSONError.invalid(issue, byteOffset: 0).stopReason == .unreadableOutput)
        }
    }

    @Test("AC-M2-24: whole numbers are read exactly from the JSON text; fractions, huge and malformed numbers are nil",
          arguments: [
            ("0", 0), ("-0", 0), ("7", 7), ("-42", -42), ("2.0", 2), ("2.50e1", 25), ("1e2", 100), ("1E+2", 100),
            ("100000e-5", 1), ("0.0", 0), ("0e-999999999999", 0), ("12e0", 12),
            ("9223372036854775807", Int.max), ("-9223372036854775808", Int.min),
            ("9007199254740993", 9_007_199_254_740_993), ("9007199254740993.0", 9_007_199_254_740_993),
            ("1.5", nil), ("-0.5", nil), ("1.00000000000000001", nil), ("1e-1", nil), ("15e-1", nil),
            ("9223372036854775808", nil), ("-9223372036854775809", nil), ("1e19", nil), ("1e400", nil),
            ("1e99999999999999999999999", nil), ("1e-99999999999999999999999", nil),
            ("abc", nil), ("", nil), ("01", nil), ("1.", nil), ("--1", nil), ("1e", nil),
          ] as [(String, Int?)])
    func wholeNumbers(_ text: String, _ expected: Int?) {
        #expect(ModelNumber.wholeNumber(jsonText: text) == expected, "\(text)")
    }

    @Test("AC-M2-24: the exact rule agrees with ModelNumber.wholeNumber(Double) wherever a Double holds the value exactly")
    func agreesWithDoubleRule() {
        var rng = SplitMix64(seed: 0x0A11_C0DE_1205)
        for _ in 0..<5_000 {
            let mantissa = Int.random(in: -999_999...999_999, using: &rng)
            let fraction = Int.random(in: 0...3, using: &rng)
            let exponent = Int.random(in: -6...6, using: &rng)
            var text = String(abs(mantissa))
            if fraction > 0, text.count > fraction {
                text.insert(".", at: text.index(text.endIndex, offsetBy: -fraction))
            }
            text = (mantissa < 0 ? "-" : "") + text + (exponent == 0 ? "" : "e\(exponent)")
            guard let double = Double(text) else { continue }
            #expect(ModelNumber.wholeNumber(jsonText: text) == ModelNumber.wholeNumber(double), "\(text)")
        }
    }
}

extension PartialJSONValue {
    /// True when `self` is a state the parser can show on the way to `final`: every finished scalar equals the one in
    /// `final`, open strings are prefixes, and containers hold a prefix of `final`'s elements or members.
    func isPrefix(of final: PartialJSONValue) -> Bool {
        switch (self, final) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.string(a, aDone), .string(b, _)):
            return aDone ? a == b && final.isComplete : Array(b.utf8).starts(with: Array(a.utf8))
        case let (.array(a, aDone), .array(b, _)):
            guard a.count <= b.count, !aDone || a.count == b.count else { return false }
            return zip(a, b).enumerated().allSatisfy { index, pair in
                index < a.count - 1 || aDone ? pair.0 == pair.1 : pair.0.isPrefix(of: pair.1)
            }
        case let (.object(a, aDone), .object(b, _)):
            guard a.count <= b.count, !aDone || a.count == b.count else { return false }
            return zip(a, b).enumerated().allSatisfy { index, pair in
                pair.0.key == pair.1.key
                    && (index < a.count - 1 || aDone ? pair.0.value == pair.1.value : pair.0.value.isPrefix(of: pair.1.value))
            }
        default: return false
        }
    }
}
