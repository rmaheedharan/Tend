// A hand-written canonical JSON writer that gives identical bytes on Linux and Darwin (plan WI-M2-01, risk R-10,
// ADR-0006). Used for the cloud request bodies (AC-M2-20 golden bytes, P-3) and the eval results file (AC-M2-28).
//
// The canonical form:
// - object keys sorted by their UTF-8 bytes, ascending; a duplicate key (equal UTF-8 bytes) is an error;
// - no insignificant whitespace;
// - strings: `"` and `\` escaped; U+0008, U+0009, U+000A, U+000C, U+000D as `\b` `\t` `\n` `\f` `\r`; every other
//   control character below U+0020 as `\u00XX` with lower-case hex; `/` is not escaped; everything else, including
//   non-ASCII, U+007F and U+2028/U+2029, is written as its UTF-8 bytes, unchanged (no Unicode normalisation);
// - numbers: integers only, in plain decimal (no floating point, no exponent, no `+`, no leading zeros);
// - `true`, `false`, `null`.
// `JSONEncoder` is not used: its `.sortedKeys` order and its escaping are not guaranteed to match across platforms.

import Foundation

/// A JSON value with integers only and ordered object members.
public indirect enum CanonicalJSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case string(String)
    case array([CanonicalJSON])
    /// Members in any order; the writer sorts them. Keys must be distinct by UTF-8 bytes.
    case object([Member])

    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: CanonicalJSON

        public init(_ key: String, _ value: CanonicalJSON) {
            self.key = key
            self.value = value
        }
    }
}

/// Why a value cannot be written canonically.
public enum CanonicalJSONError: Error, Sendable, Equatable {
    /// Two members of one object have the same key (equal UTF-8 bytes).
    case duplicateKey(String)
}

public enum CanonicalJSONWriter {

    /// The canonical bytes of `value`.
    public static func data(_ value: CanonicalJSON) throws(CanonicalJSONError) -> Data {
        var bytes: [UInt8] = []
        try write(value, into: &bytes)
        return Data(bytes)
    }

    /// The canonical text of `value` (the same bytes as `data(_:)`, as UTF-8).
    public static func string(_ value: CanonicalJSON) throws(CanonicalJSONError) -> String {
        var bytes: [UInt8] = []
        try write(value, into: &bytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    static func write(_ value: CanonicalJSON, into bytes: inout [UInt8]) throws(CanonicalJSONError) {
        switch value {
        case .null:
            bytes.append(contentsOf: Array("null".utf8))
        case .bool(let flag):
            bytes.append(contentsOf: Array((flag ? "true" : "false").utf8))
        case .integer(let number):
            bytes.append(contentsOf: Array(String(number).utf8))
        case .string(let text):
            writeString(text, into: &bytes)
        case .array(let elements):
            bytes.append(UInt8(ascii: "["))
            for (index, element) in elements.enumerated() {
                if index > 0 { bytes.append(UInt8(ascii: ",")) }
                try write(element, into: &bytes)
            }
            bytes.append(UInt8(ascii: "]"))
        case .object(let members):
            let sorted = members.sorted { TextFolding.utf8Precedes($0.key, $1.key) }
            bytes.append(UInt8(ascii: "{"))
            for (index, member) in sorted.enumerated() {
                if index > 0 {
                    if Array(sorted[index - 1].key.utf8) == Array(member.key.utf8) {
                        throw .duplicateKey(member.key)
                    }
                    bytes.append(UInt8(ascii: ","))
                }
                writeString(member.key, into: &bytes)
                bytes.append(UInt8(ascii: ":"))
                try write(member.value, into: &bytes)
            }
            bytes.append(UInt8(ascii: "}"))
        }
    }

    static let hexDigits = Array("0123456789abcdef".utf8)

    static func writeString(_ text: String, into bytes: inout [UInt8]) {
        bytes.append(UInt8(ascii: "\""))
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""): bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\"")])
            case UInt8(ascii: "\\"): bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\\")])
            case 0x08: bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "b")])
            case 0x09: bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "t")])
            case 0x0A: bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "n")])
            case 0x0C: bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "f")])
            case 0x0D: bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "r")])
            case 0x00..<0x20:
                bytes.append(contentsOf: Array("\\u00".utf8))
                bytes.append(hexDigits[Int(byte >> 4)])
                bytes.append(hexDigits[Int(byte & 0x0F)])
            default:
                bytes.append(byte)  // UTF-8 bytes of every other scalar, unchanged (multi-byte sequences ≥ 0x80)
            }
        }
        bytes.append(UInt8(ascii: "\""))
    }
}
