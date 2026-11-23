// An incremental JSON parser for growing model output (plan WI-M2-12; AC-M2-24). FR-A1.
//
// A cloud model streams its structured output as JSON text in pieces (WI-M2-13 takes the pieces out of each provider's
// events). This parser reads that text (RFC 8259, UTF-8) one byte at a time and keeps a stack of open containers, so
// each byte is read once. After any chunk, `value` is the JSON read so far:
// - objects, arrays and strings may still be open (`isComplete: false`); an open string holds only whole characters
//   (never half a UTF-8 sequence, half an escape or half a surrogate pair);
// - a number, `true`, `false` or `null` appears only once it is finished (a number ends at the next byte that cannot
//   be part of it, or at `finish()` for a root number);
// - an object member appears once its key is finished and its value has started (or finished, for a scalar).
// Invalid JSON is a typed error with the offset of the first byte that cannot be read, never a crash. A text that ends
// before its root value is finished is `cutShort`. The first error closes the parser: later calls give it again.
//
// Strict where RFC 8259 leaves a choice (dev-notes WI-M2-12, J4): a duplicate object key and a leading BOM are
// errors. Nesting is capped at `maximumDepth`. Pure value type: no I/O, no clock, no logging.

import Foundation

/// A JSON value read so far. Containers and strings carry whether they are finished.
public indirect enum PartialJSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    /// A finished number, as its JSON text (grammar-checked). `ModelNumber.wholeNumber(jsonText:)` reads it.
    case number(String)
    case string(String, isComplete: Bool)
    case array([PartialJSONValue], isComplete: Bool)
    /// Members in text order. Keys are distinct by UTF-8 bytes (a duplicate is an error).
    case object([PartialJSONMember], isComplete: Bool)

    /// True for a scalar and for a finished string or container (and everything inside it).
    public var isComplete: Bool {
        switch self {
        case .null, .bool, .number: true
        case let .string(_, isComplete), let .array(_, isComplete), let .object(_, isComplete): isComplete
        }
    }

    /// The member value for `key` (exact UTF-8 bytes) when this is an object; otherwise nil.
    public subscript(key: String) -> PartialJSONValue? {
        guard case let .object(members, _) = self else { return nil }
        return members.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }
}

/// One object member.
public struct PartialJSONMember: Hashable, Sendable {
    public var key: String
    public var value: PartialJSONValue

    public init(key: String, value: PartialJSONValue) {
        self.key = key
        self.value = value
    }
}

/// Why a JSON text cannot be read.
public enum JSONSyntaxIssue: Error, CaseIterable, Hashable, Sendable {
    /// A byte that cannot start or continue the value at this point.
    case unexpectedByte
    /// A number that does not follow the JSON number grammar (for example `01`, `1.`, `-`, `1e`).
    case invalidNumber
    /// A backslash escape that JSON does not define, or a `\u` with a non-hex digit.
    case invalidEscape
    /// A `\u` escape for half of a surrogate pair without its other half.
    case unpairedSurrogate
    /// A raw control character (below U+0020) inside a string.
    case controlCharacterInString
    /// Bytes that are not valid UTF-8 inside a string.
    case invalidUTF8
    /// An object key that an earlier member of the same object already has.
    case duplicateKey
    /// More than `PartialJSONParser.maximumDepth` open containers.
    case nestingTooDeep
    /// Something other than whitespace after the root value.
    case dataAfterValue
}

/// The typed error of the parser and the structured-output reader.
public enum PartialJSONError: Error, Hashable, Sendable {
    /// The text is not valid JSON; `byteOffset` is the 0-based offset of the first byte that cannot be read.
    case invalid(JSONSyntaxIssue, byteOffset: Int)
    /// The text ended before its root value was finished.
    case cutShort

    /// The neutral reason a cloud adapter ends its snapshot stream with (AC-M2-24: a cut-off text or invalid JSON
    /// after the first draft gives `interrupted`, before any draft `noModel`; brief Definitions, T-25).
    public var stopReason: ModelStopReason {
        switch self {
        case .invalid: .unreadableOutput
        case .cutShort: .outputCutShort
        }
    }
}

/// Reads a growing JSON text; see the file header.
public struct PartialJSONParser: Sendable {
    /// The most containers that may be open at once. The cloud output schema needs 4.
    public static let maximumDepth = 64

    private enum ArrayState: Sendable { case afterOpen, afterComma, inValue, afterValue }

    private enum ObjectState: Sendable {
        case afterOpen, afterComma, inKey, afterKey(String), expectValue(String), inValue(String), afterValue
    }

    private enum Frame: Sendable {
        case array([PartialJSONValue], ArrayState)
        case object([PartialJSONMember], keys: Set<[UInt8]>, ObjectState)
    }

    private enum Scalar: Sendable {
        case none
        case string(StringScanner, isKey: Bool)
        case number([UInt8])
        case literal(expected: [UInt8], matched: Int, value: PartialJSONValue)
    }

    private var frames: [Frame] = []
    private var scalar: Scalar = .none
    private var root: PartialJSONValue?
    private var offset = 0
    private var error: PartialJSONError?

    public init() {}

    /// The value read so far (nil before the root value has started, or while a root scalar is open).
    public var value: PartialJSONValue? {
        if let root { return root }
        var child: PartialJSONValue?
        if case let .string(scanner, isKey) = scalar, !isKey {
            child = .string(scanner.text, isComplete: false)
        }
        for frame in frames.reversed() {
            switch frame {
            case let .array(elements, state):
                if case .inValue = state, let value = child {
                    child = .array(elements + [value], isComplete: false)
                } else {
                    child = .array(elements, isComplete: false)
                }
            case let .object(members, _, state):
                if case let .inValue(key) = state, let value = child {
                    child = .object(members + [PartialJSONMember(key: key, value: value)], isComplete: false)
                } else {
                    child = .object(members, isComplete: false)
                }
            }
        }
        return child
    }

    /// Reads the next chunk. Throws the first error; after one, every call throws it again.
    public mutating func append(_ bytes: some Sequence<UInt8>) throws(PartialJSONError) {
        if let error { throw error }
        for byte in bytes {
            do throws(JSONSyntaxIssue) {
                try consume(byte)
            } catch {
                let failure = PartialJSONError.invalid(error, byteOffset: offset)
                self.error = failure
                throw failure
            }
            offset += 1
        }
    }

    /// Ends the text and returns the finished root value; throws `cutShort` if it is not finished.
    public mutating func finish() throws(PartialJSONError) -> PartialJSONValue {
        if let error { throw error }
        if frames.isEmpty, root == nil, case let .number(bytes) = scalar {
            scalar = .none
            do throws(JSONSyntaxIssue) {
                try completeNumber(bytes)
            } catch {
                let failure = PartialJSONError.invalid(error, byteOffset: offset)
                self.error = failure
                throw failure
            }
        }
        guard let root else {
            self.error = .cutShort
            throw .cutShort
        }
        return root
    }

    // MARK: - Bytes

    private mutating func consume(_ byte: UInt8) throws(JSONSyntaxIssue) {
        switch scalar {
        case .none:
            break
        case .string(var scanner, let isKey):
            scalar = .none  // keeps the scanner's buffer uniquely referenced while it grows
            if try scanner.consume(byte) {
                if isKey { try keyFinished(scanner) } else { valueFinished(.string(scanner.text, isComplete: true)) }
            } else {
                scalar = .string(scanner, isKey: isKey)
            }
            return
        case .number(var bytes):
            if Self.isNumberByte(byte) {
                scalar = .none
                bytes.append(byte)
                scalar = .number(bytes)
                return
            }
            scalar = .none
            try completeNumber(bytes)  // then the byte is read as structure below
        case let .literal(expected, matched, value):
            guard byte == expected[matched] else { throw .unexpectedByte }
            if matched + 1 == expected.count {
                scalar = .none
                valueFinished(value)
            } else {
                scalar = .literal(expected: expected, matched: matched + 1, value: value)
            }
            return
        }
        try structure(byte)
    }

    private mutating func structure(_ byte: UInt8) throws(JSONSyntaxIssue) {
        if Self.isWhitespace(byte) { return }
        if root != nil { throw .dataAfterValue }
        guard let top = frames.popLast() else {
            try startValue(byte)
            return
        }
        switch top {
        case let .array(elements, state):
            switch (state, byte) {
            case (.afterOpen, UInt8(ascii: "]")), (.afterValue, UInt8(ascii: "]")):
                valueFinished(.array(elements, isComplete: true))
            case (.afterValue, UInt8(ascii: ",")):
                frames.append(.array(elements, .afterComma))
            case (.afterOpen, _), (.afterComma, _):
                frames.append(.array(elements, .inValue))
                try startValue(byte)
            default:
                frames.append(top)
                throw .unexpectedByte
            }
        case let .object(members, keys, state):
            switch (state, byte) {
            case (.afterOpen, UInt8(ascii: "}")), (.afterValue, UInt8(ascii: "}")):
                valueFinished(.object(members, isComplete: true))
            case (.afterOpen, UInt8(ascii: "\"")), (.afterComma, UInt8(ascii: "\"")):
                frames.append(.object(members, keys: keys, .inKey))
                scalar = .string(StringScanner(), isKey: true)
            case (.afterValue, UInt8(ascii: ",")):
                frames.append(.object(members, keys: keys, .afterComma))
            case let (.afterKey(key), UInt8(ascii: ":")):
                frames.append(.object(members, keys: keys, .expectValue(key)))
            case let (.expectValue(key), _):
                frames.append(.object(members, keys: keys, .inValue(key)))
                try startValue(byte)
            default:
                frames.append(top)
                throw .unexpectedByte
            }
        }
    }

    private mutating func startValue(_ byte: UInt8) throws(JSONSyntaxIssue) {
        switch byte {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            guard frames.count < Self.maximumDepth else { throw .nestingTooDeep }
            frames.append(byte == UInt8(ascii: "{") ? .object([], keys: [], .afterOpen) : .array([], .afterOpen))
        case UInt8(ascii: "\""):
            scalar = .string(StringScanner(), isKey: false)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            scalar = .number([byte])
        case UInt8(ascii: "t"):
            scalar = .literal(expected: Array("true".utf8), matched: 1, value: .bool(true))
        case UInt8(ascii: "f"):
            scalar = .literal(expected: Array("false".utf8), matched: 1, value: .bool(false))
        case UInt8(ascii: "n"):
            scalar = .literal(expected: Array("null".utf8), matched: 1, value: .null)
        default:
            throw .unexpectedByte
        }
    }

    /// A value finished: it becomes the root, or the next element or member of the open container.
    private mutating func valueFinished(_ value: PartialJSONValue) {
        guard let top = frames.popLast() else {
            root = value
            return
        }
        switch top {
        case var .array(elements, _):
            elements.append(value)
            frames.append(.array(elements, .afterValue))
        case .object(var members, let keys, let state):
            if case let .inValue(key) = state { members.append(PartialJSONMember(key: key, value: value)) }
            frames.append(.object(members, keys: keys, .afterValue))
        }
    }

    private mutating func keyFinished(_ scanner: StringScanner) throws(JSONSyntaxIssue) {
        guard case .object(let members, var keys, _)? = frames.popLast() else { throw .unexpectedByte }
        guard keys.insert(scanner.bytes).inserted else { throw .duplicateKey }
        frames.append(.object(members, keys: keys, .afterKey(scanner.text)))
    }

    private mutating func completeNumber(_ bytes: [UInt8]) throws(JSONSyntaxIssue) {
        guard JSONNumberText(bytes) != nil else { throw .invalidNumber }
        valueFinished(.number(String(decoding: bytes, as: UTF8.self)))
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func isNumberByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."),
             UInt8(ascii: "e"), UInt8(ascii: "E"):
            true
        default:
            false
        }
    }
}

// MARK: - Strings

/// Reads one JSON string body after its opening quote, byte by byte. `bytes` holds only whole, valid UTF-8.
private struct StringScanner: Sendable {
    private enum Escape: Sendable {
        case none
        case backslash
        case unicode(UInt32, digits: Int)
        /// A high surrogate was read; its low half must follow as `\uDC00`…`\uDFFF`.
        case lowBackslash(UInt32)
        case lowU(UInt32)
        case lowUnicode(UInt32, UInt32, digits: Int)
    }

    private(set) var bytes: [UInt8] = []
    private var sequence: [UInt8] = []
    private var continuationsLeft = 0
    private var nextLow: UInt8 = 0x80
    private var nextHigh: UInt8 = 0xBF
    private var escape: Escape = .none

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// Reads one byte; returns true at the closing quote.
    mutating func consume(_ byte: UInt8) throws(JSONSyntaxIssue) -> Bool {
        if continuationsLeft > 0 {
            guard byte >= nextLow, byte <= nextHigh else { throw .invalidUTF8 }
            sequence.append(byte)
            continuationsLeft -= 1
            nextLow = 0x80
            nextHigh = 0xBF
            if continuationsLeft == 0 {
                bytes.append(contentsOf: sequence)
                sequence.removeAll(keepingCapacity: true)
            }
            return false
        }
        switch escape {
        case .none:
            break
        case .backslash:
            let decoded: UInt8
            switch byte {
            case UInt8(ascii: "\""): decoded = 0x22
            case UInt8(ascii: "\\"): decoded = 0x5C
            case UInt8(ascii: "/"): decoded = 0x2F
            case UInt8(ascii: "b"): decoded = 0x08
            case UInt8(ascii: "f"): decoded = 0x0C
            case UInt8(ascii: "n"): decoded = 0x0A
            case UInt8(ascii: "r"): decoded = 0x0D
            case UInt8(ascii: "t"): decoded = 0x09
            case UInt8(ascii: "u"):
                escape = .unicode(0, digits: 0)
                return false
            default: throw .invalidEscape
            }
            bytes.append(decoded)
            escape = .none
            return false
        case let .unicode(value, digits):
            guard let digit = Self.hexValue(byte) else { throw .invalidEscape }
            let unit = value << 4 | digit
            guard digits == 3 else {
                escape = .unicode(unit, digits: digits + 1)
                return false
            }
            switch unit {
            case 0xD800...0xDBFF: escape = .lowBackslash(unit)
            case 0xDC00...0xDFFF: throw .unpairedSurrogate
            default:
                try appendScalar(unit)
                escape = .none
            }
            return false
        case let .lowBackslash(high):
            guard byte == UInt8(ascii: "\\") else { throw .unpairedSurrogate }
            escape = .lowU(high)
            return false
        case let .lowU(high):
            guard byte == UInt8(ascii: "u") else { throw .unpairedSurrogate }
            escape = .lowUnicode(high, 0, digits: 0)
            return false
        case let .lowUnicode(high, value, digits):
            guard let digit = Self.hexValue(byte) else { throw .invalidEscape }
            let unit = value << 4 | digit
            guard digits == 3 else {
                escape = .lowUnicode(high, unit, digits: digits + 1)
                return false
            }
            guard (0xDC00...0xDFFF).contains(unit) else { throw .unpairedSurrogate }
            try appendScalar(0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00))
            escape = .none
            return false
        }
        switch byte {
        case UInt8(ascii: "\""):
            return true
        case UInt8(ascii: "\\"):
            escape = .backslash
        case 0x00..<0x20:
            throw .controlCharacterInString
        case 0x20..<0x80:
            bytes.append(byte)
        case 0xC2...0xDF:
            startSequence(byte, continuations: 1)
        case 0xE0:
            startSequence(byte, continuations: 2, low: 0xA0)
        case 0xED:
            startSequence(byte, continuations: 2, high: 0x9F)
        case 0xE1...0xEF:
            startSequence(byte, continuations: 2)
        case 0xF0:
            startSequence(byte, continuations: 3, low: 0x90)
        case 0xF4:
            startSequence(byte, continuations: 3, high: 0x8F)
        case 0xF1...0xF3:
            startSequence(byte, continuations: 3)
        default:
            throw .invalidUTF8  // 0x80…0xC1 and 0xF5…0xFF never start a sequence
        }
        return false
    }

    private mutating func startSequence(_ lead: UInt8, continuations: Int, low: UInt8 = 0x80, high: UInt8 = 0xBF) {
        sequence = [lead]
        continuationsLeft = continuations
        nextLow = low
        nextHigh = high
    }

    private mutating func appendScalar(_ value: UInt32) throws(JSONSyntaxIssue) {
        guard let scalar = Unicode.Scalar(value) else { throw .unpairedSurrogate }
        bytes.append(contentsOf: Array(String(Character(scalar)).utf8))
    }

    private static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }
}

// MARK: - Numbers

/// A JSON number's text split by the RFC 8259 grammar: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`.
struct JSONNumberText: Sendable {
    var isNegative: Bool
    var integerDigits: ArraySlice<UInt8>
    var fractionDigits: ArraySlice<UInt8>
    var exponentIsNegative: Bool
    var exponentDigits: ArraySlice<UInt8>

    init?(_ bytes: [UInt8]) {
        var index = bytes.startIndex
        func digits() -> ArraySlice<UInt8> {
            let start = index
            while index < bytes.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            return bytes[start..<index]
        }
        isNegative = index < bytes.endIndex && bytes[index] == UInt8(ascii: "-")
        if isNegative { index += 1 }
        integerDigits = digits()
        guard let lead = integerDigits.first, lead != UInt8(ascii: "0") || integerDigits.count == 1 else { return nil }
        fractionDigits = []
        if index < bytes.endIndex, bytes[index] == UInt8(ascii: ".") {
            index += 1
            fractionDigits = digits()
            guard !fractionDigits.isEmpty else { return nil }
        }
        exponentIsNegative = false
        exponentDigits = []
        if index < bytes.endIndex, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.endIndex, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                exponentIsNegative = bytes[index] == UInt8(ascii: "-")
                index += 1
            }
            exponentDigits = digits()
            guard !exponentDigits.isEmpty else { return nil }
        }
        guard index == bytes.endIndex else { return nil }
    }

    /// The exact value as an `Int` when it is a whole number that fits; otherwise nil. No floating point is used.
    var wholeNumber: Int? {
        var significant = Array((integerDigits + fractionDigits).drop { $0 == UInt8(ascii: "0") })
        guard !significant.isEmpty else { return 0 }
        // Exponent magnitude, capped far above any text length so the arithmetic cannot overflow.
        let cap = 1 << 40
        var exponent = 0
        for digit in exponentDigits {
            exponent = min(cap, exponent * 10 + Int(digit - UInt8(ascii: "0")))
        }
        if exponentIsNegative { exponent = -exponent }
        exponent -= fractionDigits.count
        while significant.last == UInt8(ascii: "0") {
            significant.removeLast()
            exponent += 1
        }
        guard exponent >= 0, significant.count + exponent <= 19 else { return nil }
        let text = (isNegative ? "-" : "") + String(decoding: significant, as: UTF8.self)
            + String(repeating: "0", count: exponent)
        return Int(text)
    }
}

extension ModelNumber {
    /// A JSON number's text as an `Int`, read exactly: a finite whole number that fits in `Int` (`2.0`, `0.3e1` and
    /// `1E+2` included), otherwise nil (a fraction, out of range, or not a JSON number). It gives the same result as
    /// `wholeNumber(_: Double)` wherever a `Double` holds the value exactly, and the true answer where it would round
    /// (`9007199254740993`, `1.00000000000000001`) (plan "How the hint meets Q5", Numbers; WI-M2-12).
    public static func wholeNumber(jsonText: String) -> Int? {
        JSONNumberText(Array(jsonText.utf8))?.wholeNumber
    }
}
