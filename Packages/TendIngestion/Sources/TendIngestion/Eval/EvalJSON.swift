// A strict JSON reader for the eval results file and fixtures (AC-M2-14, AC-M2-28; plan WI-M2-15). FR-A1 (the eval
// that proves capture), P-4 (it reads only the bytes it is handed).
//
// Why not `JSONSerialization` or `JSONDecoder`: the results file must be the canonical JSON that `CanonicalJSONWriter`
// writes (ADR-0006), so the reader must see duplicate keys (both Foundation readers silently keep one), keep the
// difference between a Boolean and a number (Linux `NSNumber` bridging blurs it), and behave identically on Linux and
// the Mac. The grammar is RFC 8259, with two restrictions that match the canonical writer: numbers are integers only
// (no fraction, no exponent), and object keys must be distinct by UTF-8 bytes. The reader takes `Data` and returns a
// value: no file access (AC-M2-09 Rule 1, T-26).

import Foundation

/// A parsed JSON value. Object members keep their order (the canonical check compares bytes).
public indirect enum EvalJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int)
    case string(String)
    case array([EvalJSON])
    case object([Member])

    public struct Member: Sendable, Hashable {
        public var key: String
        public var value: EvalJSON

        public init(_ key: String, _ value: EvalJSON) {
            self.key = key
            self.value = value
        }
    }

    /// The JSON Schema type name of this value ("integer" for every number, because only integers are read).
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .integer: "integer"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// The member value for `key`, or nil when this is not an object or has no such member.
    public subscript(key: String) -> EvalJSON? {
        guard case let .object(members) = self else { return nil }
        return members.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }

    /// JSON equality: strings and keys compare by Unicode scalars (not Swift's canonical equivalence), object members
    /// compare irrespective of order. Used by `uniqueItems`, `enum` and `const`.
    public static func jsonEqual(_ lhs: EvalJSON, _ rhs: EvalJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.integer(a), .integer(b)): return a == b
        case let (.string(a), .string(b)): return a.unicodeScalars.elementsEqual(b.unicodeScalars)
        case let (.array(a), .array(b)):
            return a.count == b.count && zip(a, b).allSatisfy { jsonEqual($0, $1) }
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            return a.allSatisfy { member in
                b.contains { $0.key.unicodeScalars.elementsEqual(member.key.unicodeScalars) && jsonEqual($0.value, member.value) }
            }
        default: return false
        }
    }

    /// The same value as `CanonicalJSON`, for the canonical-bytes check and for writing.
    public var canonical: CanonicalJSON {
        switch self {
        case .null: .null
        case let .bool(value): .bool(value)
        case let .integer(value): .integer(value)
        case let .string(value): .string(value)
        case let .array(values): .array(values.map(\.canonical))
        case let .object(members): .object(members.map { CanonicalJSON.Member($0.key, $0.value.canonical) })
        }
    }
}

/// Why bytes are not readable JSON (the byte offset is into the input).
public enum EvalJSONError: Error, Sendable, Hashable {
    case notUTF8
    case unexpectedEnd
    case unexpectedByte(offset: Int)
    case numberNotInteger(offset: Int)
    case numberOutOfRange(offset: Int)
    case invalidEscape(offset: Int)
    case controlCharacterInString(offset: Int)
    case duplicateKey(String, offset: Int)
    case nestedTooDeep(offset: Int)
    case trailingContent(offset: Int)
}

public enum EvalJSONReader {

    /// The deepest nesting accepted. The results file needs 6 levels; the limit keeps recursion bounded.
    public static let maximumDepth = 64

    public static func parse(_ data: Data) throws(EvalJSONError) -> EvalJSON {
        let bytes = [UInt8](data)
        guard String(validating: bytes, as: UTF8.self) != nil else { throw .notUTF8 }
        var reader = Reader(bytes: bytes)
        reader.skipWhitespace()
        let value = try reader.value(depth: 0)
        reader.skipWhitespace()
        guard reader.index == bytes.count else { throw .trailingContent(offset: reader.index) }
        return value
    }

    struct Reader {
        let bytes: [UInt8]
        var index = 0

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func peek() throws(EvalJSONError) -> UInt8 {
            guard index < bytes.count else { throw .unexpectedEnd }
            return bytes[index]
        }

        mutating func expect(_ literal: String) throws(EvalJSONError) {
            for byte in literal.utf8 {
                guard index < bytes.count else { throw .unexpectedEnd }
                guard bytes[index] == byte else { throw .unexpectedByte(offset: index) }
                index += 1
            }
        }

        mutating func value(depth: Int) throws(EvalJSONError) -> EvalJSON {
            guard depth < EvalJSONReader.maximumDepth else { throw .nestedTooDeep(offset: index) }
            switch try peek() {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .integer(try integer())
            default: throw .unexpectedByte(offset: index)
            }
        }

        mutating func object(depth: Int) throws(EvalJSONError) -> EvalJSON {
            index += 1
            var members: [EvalJSON.Member] = []
            var keys: Set<[UInt8]> = []
            skipWhitespace()
            if try peek() == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                let keyOffset = index
                guard try peek() == UInt8(ascii: "\"") else { throw .unexpectedByte(offset: index) }
                let key = try string()
                guard keys.insert(Array(key.utf8)).inserted else { throw .duplicateKey(key, offset: keyOffset) }
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                members.append(EvalJSON.Member(key, try value(depth: depth + 1)))
                skipWhitespace()
                let next = try peek()
                index += 1
                if next == UInt8(ascii: "}") { return .object(members) }
                guard next == UInt8(ascii: ",") else { throw .unexpectedByte(offset: index - 1) }
            }
        }

        mutating func array(depth: Int) throws(EvalJSONError) -> EvalJSON {
            index += 1
            var values: [EvalJSON] = []
            skipWhitespace()
            if try peek() == UInt8(ascii: "]") { index += 1; return .array(values) }
            while true {
                skipWhitespace()
                values.append(try value(depth: depth + 1))
                skipWhitespace()
                let next = try peek()
                index += 1
                if next == UInt8(ascii: "]") { return .array(values) }
                guard next == UInt8(ascii: ",") else { throw .unexpectedByte(offset: index - 1) }
            }
        }

        mutating func integer() throws(EvalJSONError) -> Int {
            let start = index
            var negative = false
            if bytes[index] == UInt8(ascii: "-") { negative = true; index += 1 }
            let digitsStart = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            let digits = bytes[digitsStart..<index]
            guard !digits.isEmpty else { throw .unexpectedByte(offset: index) }
            if digits.count > 1, digits.first == UInt8(ascii: "0") { throw .unexpectedByte(offset: digitsStart + 1) }
            if index < bytes.count, [UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")].contains(bytes[index]) {
                throw .numberNotInteger(offset: start)
            }
            var magnitude: Int = 0
            for digit in digits {
                let (times10, o1) = magnitude.multipliedReportingOverflow(by: 10)
                let (sum, o2) = negative
                    ? times10.subtractingReportingOverflow(Int(digit - UInt8(ascii: "0")))
                    : times10.addingReportingOverflow(Int(digit - UInt8(ascii: "0")))
                guard !o1, !o2 else { throw .numberOutOfRange(offset: start) }
                magnitude = sum
            }
            return magnitude
        }

        mutating func string() throws(EvalJSONError) -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var pendingBytes: [UInt8] = []
            func flush() {
                if !pendingBytes.isEmpty {
                    scalars.append(contentsOf: String(decoding: pendingBytes, as: UTF8.self).unicodeScalars)
                    pendingBytes.removeAll()
                }
            }
            while true {
                guard index < bytes.count else { throw .unexpectedEnd }
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    flush()
                    return String(scalars)
                }
                if byte < 0x20 { throw .controlCharacterInString(offset: index) }
                if byte != UInt8(ascii: "\\") {
                    pendingBytes.append(byte)
                    index += 1
                    continue
                }
                flush()
                let escapeOffset = index
                index += 1
                guard index < bytes.count else { throw .unexpectedEnd }
                let code = bytes[index]
                index += 1
                switch code {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    let first = try hex4(escapeOffset: escapeOffset)
                    if (0xD800...0xDBFF).contains(first) {
                        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                              bytes[index + 1] == UInt8(ascii: "u") else { throw .invalidEscape(offset: escapeOffset) }
                        index += 2
                        let second = try hex4(escapeOffset: escapeOffset)
                        guard (0xDC00...0xDFFF).contains(second),
                              let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
                        else { throw .invalidEscape(offset: escapeOffset) }
                        scalars.append(scalar)
                    } else {
                        guard let scalar = Unicode.Scalar(first) else { throw .invalidEscape(offset: escapeOffset) }
                        scalars.append(scalar)
                    }
                default: throw .invalidEscape(offset: escapeOffset)
                }
            }
        }

        mutating func hex4(escapeOffset: Int) throws(EvalJSONError) -> UInt32 {
            guard index + 4 <= bytes.count else { throw .unexpectedEnd }
            var value: UInt32 = 0
            for byte in bytes[index..<(index + 4)] {
                let digit: UInt8
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
                default: throw .invalidEscape(offset: escapeOffset)
                }
                value = value * 16 + UInt32(digit)
            }
            index += 4
            return value
        }
    }
}
