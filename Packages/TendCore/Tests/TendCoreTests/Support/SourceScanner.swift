// Source-scan guard used by AC-M1-02 (zero-guilt vocabulary, UX-3) and AC-M1-23 (Foundation-only,
// no ambient time/randomness/networking; P-1, P-2, CLAUDE.md §3).
//
// The scanner is a small Swift lexer, not a regex over raw text:
// - Comments (`//`, `///`, `/* */` including nested block comments) are removed. They are out of scope (brief Q16).
// - String literals are recognised before comments, so `"// not a comment"` and `"http://"` stay string content
//   (nit N-2). Single-line, multi-line `"""`, and raw `#"…"#` / `#"""…"""#` strings are supported, including
//   interpolation `\(…)` / `\#(…)`, whose contents are treated as code again (so `"\(Date())"` is still a call).
// - Escapes in literal text are decoded (`\n`, `\t`, `\u{…}`, …) so `"\nlate"` yields the token `late`.
// - API patterns are matched on the code text only, at identifier boundaries (nit N-1: `startDate()` is not `Date()`).
//
// Known limits (documented in dev-notes, risk R-12): regex literals (`/…/`, `#/…/#`) are lexed as code, and
// tokens are whole tokens after the camelCase split, so a split spelling such as `overDue` is a Reviewer check.

import Foundation
import Testing

/// The result of lexing one Swift source text.
struct LexedSource: Sendable {
    /// Code with comments and string-literal text blanked out. Newlines are preserved so line numbers match the input.
    /// Interpolated expressions inside strings are kept as code.
    var code: String
    /// The decoded text of every string-literal segment (segments are split at interpolations), with the 1-based line
    /// on which the segment starts.
    var literals: [(text: String, line: Int)]
}

/// One reported scanner finding.
struct ScanHit: Sendable, Equatable, CustomStringConvertible {
    var file: String
    var line: Int
    var rule: String
    var excerpt: String

    var description: String { "\(file):\(line): [\(rule)] \(excerpt)" }
}

enum SourceScanner {
    // MARK: - Rules

    /// AC-M1-02 banned whole tokens (compared case-insensitively).
    static let bannedTokens: [String] = [
        "overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt", "streak",
    ]

    /// AC-M1-23 closed list of banned API patterns, matched on code at identifier boundaries.
    /// `\b`-style boundaries are written as explicit look-arounds so `.` before a pattern still matches
    /// (`Foundation.Date()` is a hit) while `startDate()` is not.
    static let bannedAPIPatterns: [(name: String, regex: String)] = [
        ("Date()", #"(?<![\p{L}\p{N}_])Date\s*\(\s*\)"#),
        ("Date.now", #"(?<![\p{L}\p{N}_])Date\s*\.\s*now(?![\p{L}\p{N}_])"#),
        ("Date(timeIntervalSinceNow", #"(?<![\p{L}\p{N}_])Date\s*\(\s*timeIntervalSinceNow(?![\p{L}\p{N}_])"#),
        ("timeIntervalSinceNow", #"(?<![\p{L}\p{N}_])timeIntervalSinceNow(?![\p{L}\p{N}_])"#),
        ("Calendar.current", #"(?<![\p{L}\p{N}_])Calendar\s*\.\s*current(?![\p{L}\p{N}_])"#),
        ("Calendar.autoupdatingCurrent", #"(?<![\p{L}\p{N}_])Calendar\s*\.\s*autoupdatingCurrent(?![\p{L}\p{N}_])"#),
        ("TimeZone.current", #"(?<![\p{L}\p{N}_])TimeZone\s*\.\s*current(?![\p{L}\p{N}_])"#),
        ("TimeZone.autoupdatingCurrent", #"(?<![\p{L}\p{N}_])TimeZone\s*\.\s*autoupdatingCurrent(?![\p{L}\p{N}_])"#),
        ("Locale.current", #"(?<![\p{L}\p{N}_])Locale\s*\.\s*current(?![\p{L}\p{N}_])"#),
        ("Locale.autoupdatingCurrent", #"(?<![\p{L}\p{N}_])Locale\s*\.\s*autoupdatingCurrent(?![\p{L}\p{N}_])"#),
        ("ProcessInfo", #"(?<![\p{L}\p{N}_])ProcessInfo(?![\p{L}\p{N}_])"#),
        ("UUID()", #"(?<![\p{L}\p{N}_])UUID\s*\(\s*\)"#),
        ("SystemRandomNumberGenerator", #"(?<![\p{L}\p{N}_])SystemRandomNumberGenerator(?![\p{L}\p{N}_])"#),
        ("URLSession", #"(?<![\p{L}\p{N}_])URLSession(?![\p{L}\p{N}_])"#),
        ("URLRequest", #"(?<![\p{L}\p{N}_])URLRequest(?![\p{L}\p{N}_])"#),
        ("URLConnection", #"(?<![\p{L}\p{N}_])URLConnection(?![\p{L}\p{N}_])"#),
        ("NSURLConnection", #"(?<![\p{L}\p{N}_])NSURLConnection(?![\p{L}\p{N}_])"#),
        ("Socket", #"(?<![\p{L}\p{N}_])Socket(?![\p{L}\p{N}_])"#),
        ("NSStream", #"(?<![\p{L}\p{N}_])NSStream(?![\p{L}\p{N}_])"#),
        ("Stream(", #"(?<![\p{L}\p{N}_])Stream\s*\("#),
        ("Host(", #"(?<![\p{L}\p{N}_])Host\s*\("#),
        ("Host.current", #"(?<![\p{L}\p{N}_])Host\s*\.\s*current(?![\p{L}\p{N}_])"#),
    ]

    /// AC-M1-23: randomness calls that are banned unless their argument list contains `using:`.
    static let randomCallNames: [String] = ["random", "randomElement", "shuffled", "shuffle"]

    /// AC-M1-23: the only allowed import.
    static let allowedImport = "Foundation"

    // MARK: - Scanning

    /// AC-M1-02: banned vocabulary tokens in identifiers and string literals (comments excluded).
    static func vocabularyHits(in source: String, file: String) -> [ScanHit] {
        let lexed = lex(source)
        var hits: [ScanHit] = []
        let banned = Set(bannedTokens)
        for (lineIndex, line) in lexed.code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for word in words(in: String(line)) {
                for token in subTokens(of: word) where banned.contains(token.lowercased()) {
                    hits.append(ScanHit(file: file, line: lineIndex + 1, rule: "token:\(token.lowercased())",
                                        excerpt: word))
                }
            }
        }
        for literal in lexed.literals {
            for word in words(in: literal.text) {
                for token in subTokens(of: word) where banned.contains(token.lowercased()) {
                    hits.append(ScanHit(file: file, line: literal.line, rule: "token:\(token.lowercased())",
                                        excerpt: "\"\(literal.text)\""))
                }
            }
        }
        return hits
    }

    /// AC-M1-23: imports other than `import Foundation`, banned API patterns, `using:`-less randomness, and
    /// `http://` / `https://` string literals.
    static func apiHits(in source: String, file: String) -> [ScanHit] {
        let lexed = lex(source)
        let code = lexed.code
        var hits: [ScanHit] = []

        // Imports: every `import` statement must be exactly `import Foundation` (attributes allowed).
        for match in matches(of: #"(?<![\p{L}\p{N}_.`])import\s+([^;\n]*)"#, in: code) {
            let target = match.groups[0].trimmingCharacters(in: .whitespaces)
            if target != allowedImport {
                hits.append(ScanHit(file: file, line: match.line, rule: "import", excerpt: "import \(target)"))
            }
        }

        for pattern in bannedAPIPatterns {
            for match in matches(of: pattern.regex, in: code) {
                hits.append(ScanHit(file: file, line: match.line, rule: pattern.name, excerpt: match.text))
            }
        }

        hits.append(contentsOf: randomCallHits(in: code, file: file))

        for literal in lexed.literals {
            let lower = literal.text.lowercased()
            if lower.contains("http://") || lower.contains("https://") {
                hits.append(ScanHit(file: file, line: literal.line, rule: "http(s) literal", excerpt: literal.text))
            }
        }
        return hits
    }

    /// Calls to `.random(`, `.randomElement(`, `.shuffled(`, `.shuffle(` whose balanced argument list does not
    /// contain `using:`.
    static func randomCallHits(in code: String, file: String) -> [ScanHit] {
        var hits: [ScanHit] = []
        let scalars = Array(code.unicodeScalars)
        for name in randomCallNames {
            let regex = #"\.\s*"# + name + #"\s*\("#
            for match in matches(of: regex, in: code) {
                // Find the balanced argument list starting at the opening parenthesis.
                var depth = 0
                var index = match.endOffset - 1  // the "(" itself
                var arguments = String.UnicodeScalarView()
                while index < scalars.count {
                    let scalar = scalars[index]
                    if scalar == "(" { depth += 1 }
                    if scalar == ")" { depth -= 1 }
                    arguments.append(scalar)
                    if depth == 0 { break }
                    index += 1
                }
                let argumentText = String(arguments)
                if matches(of: #"(?<![\p{L}\p{N}_])using\s*:"#, in: argumentText).isEmpty {
                    hits.append(ScanHit(file: file, line: match.line, rule: ".\(name)( without using:",
                                        excerpt: match.text + argumentText.dropFirst()))
                }
            }
        }
        return hits
    }

    // MARK: - Tokenising (AC-M1-02)

    /// Maximal runs of letters, digits and `_` (identifier-like words).
    static func words(in text: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "_" {
                current.append(scalar)
            } else if !current.isEmpty {
                result.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    /// Splits a word on `_`, digits, non-letters and camelCase humps.
    /// `isOverdueTask` → `is`, `Overdue`, `Task`; `URLSession` → `URL`, `Session`; `LATE_FEE` → `LATE`, `FEE`.
    static func subTokens(of word: String) -> [String] {
        var tokens: [String] = []
        let scalars = Array(word.unicodeScalars)
        var current = String.UnicodeScalarView()

        func flush() {
            if !current.isEmpty {
                tokens.append(String(current))
                current = String.UnicodeScalarView()
            }
        }

        for (index, scalar) in scalars.enumerated() {
            guard scalar.properties.isAlphabetic else {
                flush()
                continue
            }
            if let previous = current.last {
                let isUpper = scalar.properties.isUppercase
                let previousIsUpper = previous.properties.isUppercase
                let nextIsLower = index + 1 < scalars.count && scalars[index + 1].properties.isLowercase
                if isUpper && !previousIsUpper {
                    flush()  // lower → Upper hump: "isOverdue" splits before "O"
                } else if isUpper && previousIsUpper && nextIsLower {
                    flush()  // acronym end: "URLSession" splits before "S"
                }
            }
            current.append(scalar)
        }
        flush()
        return tokens
    }

    // MARK: - Lexing

    /// Removes comments and separates string-literal text from code. See the file header for the rules.
    static func lex(_ source: String) -> LexedSource {
        var lexer = Lexer(Array(source.unicodeScalars))
        lexer.lexCode(stopAtUnbalancedCloseParen: false)
        return LexedSource(code: String(lexer.code), literals: lexer.literals)
    }

    private struct Lexer {
        let input: [Unicode.Scalar]
        var position = 0
        var line = 1
        var code = String.UnicodeScalarView()
        var literals: [(text: String, line: Int)] = []

        init(_ input: [Unicode.Scalar]) { self.input = input }

        func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            let index = position + offset
            return index < input.count ? input[index] : nil
        }

        func startsWith(_ text: String, at offset: Int = 0) -> Bool {
            var index = position + offset
            for scalar in text.unicodeScalars {
                guard index < input.count, input[index] == scalar else { return false }
                index += 1
            }
            return true
        }

        /// Consumes one scalar, tracking lines. Newlines are always copied to `code` so line numbers survive.
        mutating func advance(emitToCode: Bool) {
            let scalar = input[position]
            position += 1
            if scalar == "\n" {
                line += 1
                code.append("\n")
            } else if emitToCode {
                code.append(scalar)
            }
        }

        /// Lexes code. Inside an interpolation, stops after the `)` that closes it.
        mutating func lexCode(stopAtUnbalancedCloseParen: Bool) {
            var depth = 0
            while position < input.count {
                if startsWith("//") {
                    while let scalar = peek(), scalar != "\n" { advance(emitToCode: false) }
                    code.append(" ")
                } else if startsWith("/*") {
                    skipBlockComment()
                    code.append(" ")
                } else if let hashes = rawStringHashCount() {
                    lexString(hashes: hashes)
                } else if peek() == "\"" {
                    lexString(hashes: 0)
                } else if peek() == "(" {
                    depth += 1
                    advance(emitToCode: true)
                } else if peek() == ")" {
                    if stopAtUnbalancedCloseParen && depth == 0 {
                        position += 1  // the interpolation's closing ")" is not emitted
                        return
                    }
                    depth -= 1
                    advance(emitToCode: true)
                } else {
                    advance(emitToCode: true)
                }
            }
        }

        /// Swift block comments nest.
        mutating func skipBlockComment() {
            var depth = 0
            while position < input.count {
                if startsWith("/*") {
                    depth += 1
                    position += 2
                } else if startsWith("*/") {
                    depth -= 1
                    position += 2
                    if depth == 0 { return }
                } else {
                    advance(emitToCode: false)
                }
            }
        }

        /// If the input at `position` is `#…#"` (one or more `#` then `"`), returns the number of `#`.
        func rawStringHashCount() -> Int? {
            var count = 0
            while peek(count) == "#" { count += 1 }
            guard count > 0, peek(count) == "\"" else { return nil }
            return count
        }

        /// Lexes a string literal starting at `position` (at the first `#` for raw strings, else at `"`).
        mutating func lexString(hashes: Int) {
            position += hashes
            let isMultiline = startsWith("\"\"\"")
            position += isMultiline ? 3 : 1
            code.append(" ")

            let hashSuffix = String(repeating: "#", count: hashes)
            let closing = (isMultiline ? "\"\"\"" : "\"") + hashSuffix
            let escape = "\\" + hashSuffix

            var text = String.UnicodeScalarView()
            var segmentLine = line

            while position < input.count {
                if startsWith(closing) {
                    position += closing.unicodeScalars.count
                    flush(&text, line: segmentLine)
                    code.append(" ")
                    return
                }
                if !isMultiline && peek() == "\n" {
                    // Unterminated single-line string: stop at end of line (keeps the lexer in sync).
                    flush(&text, line: segmentLine)
                    return
                }
                if startsWith(escape) {
                    let after = escape.unicodeScalars.count
                    if peek(after) == "(" {
                        // Interpolation: the expression is code.
                        flush(&text, line: segmentLine)
                        position += after + 1
                        code.append(" ")
                        lexCode(stopAtUnbalancedCloseParen: true)
                        code.append(" ")
                        segmentLine = line
                        continue
                    }
                    position += after
                    decodeEscape(into: &text)
                    continue
                }
                let scalar = input[position]
                if scalar == "\n" { advance(emitToCode: false) } else { position += 1 }
                text.append(scalar)
            }
            flush(&text, line: segmentLine)
        }

        /// Records one finished string-literal segment.
        mutating func flush(_ text: inout String.UnicodeScalarView, line segmentLine: Int) {
            literals.append((text: String(text), line: segmentLine))
            text = String.UnicodeScalarView()
        }

        /// Decodes the escape whose introducer has already been consumed.
        mutating func decodeEscape(into text: inout String.UnicodeScalarView) {
            guard let scalar = peek() else { return }
            switch scalar {
            case "n", "t", "r", "0":
                text.append(" ")
                position += 1
            case "u" where peek(1) == "{":
                var hex = ""
                var index = 2
                while let digit = peek(index), digit != "}" {
                    hex.unicodeScalars.append(digit)
                    index += 1
                }
                if let value = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(value) {
                    text.append(decoded)
                }
                position += index + 1
            case "\n":
                advance(emitToCode: false)  // line continuation in a multi-line string
            default:
                text.append(scalar)  // \\, \", \'
                position += 1
            }
        }
    }

    // MARK: - Regex helper

    struct RegexMatch {
        var text: String
        var groups: [String]
        var line: Int
        /// Offset (in Unicode scalars) just past the match.
        var endOffset: Int
    }

    static func matches(of pattern: String, in text: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Issue.record("Invalid scanner regex: \(pattern)")
            return []
        }
        let nsText = text as NSString
        let lineStarts = lineStartOffsets(in: nsText)
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { result in
            var groups: [String] = []
            if result.numberOfRanges > 1 {
                for index in 1..<result.numberOfRanges {
                    let range = result.range(at: index)
                    groups.append(range.location == NSNotFound ? "" : nsText.substring(with: range))
                }
            }
            let matchEnd = result.range.location + result.range.length
            let prefix = nsText.substring(to: matchEnd)
            return RegexMatch(
                text: nsText.substring(with: result.range),
                groups: groups,
                line: line(forUTF16Offset: result.range.location, lineStarts: lineStarts),
                endOffset: prefix.unicodeScalars.count
            )
        }
    }

    private static func lineStartOffsets(in text: NSString) -> [Int] {
        var starts = [0]
        for index in 0..<text.length where text.character(at: index) == 0x0A {
            starts.append(index + 1)
        }
        return starts
    }

    private static func line(forUTF16Offset offset: Int, lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    // MARK: - Files

    /// `Packages/TendCore/Sources/`, located from this file's path so it works on Linux and macOS.
    /// (`#filePath` is read here, not as a default argument, which would resolve at the caller.)
    static func sourcesDirectory() -> URL {
        let thisFile: String = #filePath
        return URL(fileURLWithPath: thisFile)
            .deletingLastPathComponent()  // Support
            .deletingLastPathComponent()  // TendCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // TendCore (package root)
            .appendingPathComponent("Sources", isDirectory: true)
    }

    /// Every `.swift` file under `directory`, sorted by path for a stable log.
    static func swiftFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }
}

