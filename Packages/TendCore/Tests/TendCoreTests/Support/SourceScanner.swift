// Source-scan guard used by AC-M1-02 (zero-guilt vocabulary, UX-3) and AC-M1-23 (Foundation-only,
// no ambient time/randomness/networking; P-1, P-2, CLAUDE.md §3).
//
// The scanner is a small Swift lexer, not a regex over raw text:
// - Comments (`//`, `///`, `/* */` including nested block comments) are removed. They are out of scope (brief Q16).
// - String literals are recognised before comments, so `"// not a comment"` and `"http://"` stay string content
//   (nit N-2). Single-line, multi-line `"""`, and raw `#"…"#` / `#"""…"""#` strings are supported, including
//   interpolation `\(…)` / `\#(…)`, whose contents are treated as code again (so `"\(Date())"` is still a call).
// - Escapes in literal text are decoded (`\n`, `\t`, `\u{…}`, …) so `"\nlate"` yields the token `late`.
// - API rules are matched on the code text only (string-literal text is not code; interpolations are). Two kinds:
//   * time, ID and randomness patterns at identifier boundaries (nit N-1: `startDate()` is not `Date()`), including
//     `Date.init()` / `UUID.init()` and an implicit-member `.now` with no receiver (review F-2);
//   * networking names at camelCase word boundaries, using the same word split as the AC-M1-02 tokeniser, so
//     `URLSessionWebSocketTask`, `CFSocketCreate` and `InputStream(` are hits (review F-1, brief AC-M1-23).
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

    /// Regex look-arounds for an identifier boundary. `.` before a pattern still matches (`Foundation.Date()` is a
    /// hit) while `startDate()` is not.
    private static let leftBoundary = #"(?<![\p{L}\p{N}_])"#
    private static let rightBoundary = #"(?![\p{L}\p{N}_])"#

    /// AC-M1-23 closed-list patterns matched at **identifier boundaries** (N-1): ambient time, IDs, randomness and
    /// `URL(string:`. `Date()`, `UUID()` and `URL(string:` also match the explicit `.init` spelling (review F-2).
    static let identifierPatterns: [(name: String, regex: String)] = [
        ("Date()", leftBoundary + #"Date\s*(?:\.\s*init\s*)?\(\s*\)"#),
        ("Date.now", leftBoundary + #"Date\s*\.\s*now"# + rightBoundary),
        ("Date(timeIntervalSinceNow",
         leftBoundary + #"Date\s*(?:\.\s*init\s*)?\(\s*timeIntervalSinceNow"# + rightBoundary),
        ("timeIntervalSinceNow", leftBoundary + "timeIntervalSinceNow" + rightBoundary),
        ("Calendar.current", leftBoundary + #"Calendar\s*\.\s*current"# + rightBoundary),
        ("Calendar.autoupdatingCurrent", leftBoundary + #"Calendar\s*\.\s*autoupdatingCurrent"# + rightBoundary),
        ("TimeZone.current", leftBoundary + #"TimeZone\s*\.\s*current"# + rightBoundary),
        ("TimeZone.autoupdatingCurrent", leftBoundary + #"TimeZone\s*\.\s*autoupdatingCurrent"# + rightBoundary),
        ("Locale.current", leftBoundary + #"Locale\s*\.\s*current"# + rightBoundary),
        ("Locale.autoupdatingCurrent", leftBoundary + #"Locale\s*\.\s*autoupdatingCurrent"# + rightBoundary),
        ("ProcessInfo", leftBoundary + "ProcessInfo" + rightBoundary),
        ("UUID()", leftBoundary + #"UUID\s*(?:\.\s*init\s*)?\(\s*\)"#),
        ("SystemRandomNumberGenerator", leftBoundary + "SystemRandomNumberGenerator" + rightBoundary),
        ("URL(string:", leftBoundary + #"URL\s*(?:\.\s*init\s*)?\(\s*string\s*:"#),
        ("arc4random*", leftBoundary + #"arc4random[\p{L}\p{N}_]*"#),
        ("drand48", leftBoundary + "drand48" + rightBoundary),
        ("erand48", leftBoundary + "erand48" + rightBoundary),
        ("lrand48", leftBoundary + "lrand48" + rightBoundary),
        ("srand48", leftBoundary + "srand48" + rightBoundary),
        ("rand(", leftBoundary + #"rand\s*\("#),
        ("random()", leftBoundary + #"random\s*\(\s*\)"#),
    ]

    /// AC-M1-23 networking names matched at **camelCase word boundaries** (review F-1): the name's words must appear
    /// as consecutive words of an identifier, using `subTokens(of:)` (the AC-M1-02 split). So `URLSessionDataTask`,
    /// `URLSessionWebSocketTask`, `CFSocketCreate` and `SocketPort` are hits; `Sockets` and `XURLSession` are not.
    /// Brief Q19 adds `NSURL`, `URLComponents` and `CFURL` (no URL is ever built from a string in `TendCore`); brief Q20
    /// adds the CoreFoundation and POSIX name-resolution and stream families.
    static let networkingNames: [String] = [
        "URLSession", "URLRequest", "URLConnection", "NSURLConnection", "Socket", "NSStream", "getStreamsToHost",
        "NSURL", "URLComponents", "CFURL",                                          // Q19
        "CFHost", "CFReadStream", "CFWriteStream", "CFSocket", "getaddrinfo", "gethostbyname",  // Q20
    ]

    /// AC-M1-23 (brief Q20): ambient clocks, matched like `networkingNames` (whole type and function names at camelCase
    /// / underscore word boundaries). The engine gets time only from the injected `now`.
    static let clockNames: [String] = [
        "DispatchTime", "DispatchWallTime", "ContinuousClock", "SuspendingClock",
        "mach_absolute_time", "clock_gettime", "gettimeofday", "CFAbsoluteTimeGetCurrent",
    ]

    /// AC-M1-23 call names: the name's words must be the **last** words of an identifier that is called, either as
    /// `Name(` or as `Name.init(` (review F-7). Reported as `Stream(`, `InputStream(`, `OutputStream(`, `Host(` and,
    /// for the lower-case POSIX call (brief Q20), `socket(`.
    static let networkingCallNames: [String] = ["Stream", "InputStream", "OutputStream", "Host", "socket"]

    /// AC-M1-23 (brief Q17, PO decision): exactly these two identifiers are exempt from the `Stream(` rule, in both
    /// spellings (`AsyncStream(` and `AsyncStream.init(`). Swift concurrency types; no other exemption without a PO
    /// decision.
    static let streamCallExemptions: Set<String> = ["AsyncStream", "AsyncThrowingStream"]

    /// AC-M1-23 (brief Q18, Q23): any `contentsOf:` is allowed in these source files (matched by file name), the JSON
    /// file repository's. Any change to this list needs a PO decision.
    static let contentsOfAllowlist: Set<String> = ["JSONFileHouseholdRepository.swift"]

    /// AC-M1-23 (brief Q23, review GK-1): every `contentsOf:` argument label is banned, on any type, initialiser or
    /// function, except in an allowlisted file or when the immediately enclosing call is named exactly one of these
    /// (the collection methods `append(contentsOf:)` / `insert(contentsOf:at:)`, with or without a receiver). No other
    /// exception without a PO decision.
    static let contentsOfCallExemptions: Set<String> = ["append", "insert"]
    static let contentsOfRule = "contentsOf:"
    static let contentsOfPattern = leftBoundary + #"contentsOf\s*:"#

    /// Words that may directly precede an implicit-member `.now` (`return .now`, `case .now`); after any other word the
    /// dot has a receiver (`moment.now`).
    static let keywordsBeforeImplicitMember: Set<String> = ["return", "case", "in", "throw", "try", "await", "yield", "then"]

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

        for pattern in identifierPatterns {
            for match in matches(of: pattern.regex, in: code) {
                hits.append(ScanHit(file: file, line: match.line, rule: pattern.name, excerpt: match.text))
            }
        }

        hits.append(contentsOf: implicitNowHits(in: code, file: file))
        hits.append(contentsOf: networkingHits(in: code, file: file))
        hits.append(contentsOf: randomCallHits(in: code, file: file))

        let fileName = (file as NSString).lastPathComponent
        if !contentsOfAllowlist.contains(fileName) {
            let scalars = Array(code.unicodeScalars)
            for match in matches(of: contentsOfPattern, in: code) {
                let call = enclosingCallName(in: scalars, before: match.startOffset)
                if let call, contentsOfCallExemptions.contains(call) { continue }
                hits.append(ScanHit(file: file, line: match.line, rule: contentsOfRule,
                                    excerpt: "\(call ?? "?")(\(match.text)"))
            }
        }

        for literal in lexed.literals {
            let lower = literal.text.lowercased()
            if lower.contains("http://") || lower.contains("https://") {
                hits.append(ScanHit(file: file, line: literal.line, rule: "http(s) literal", excerpt: literal.text))
            }
        }
        return hits
    }

    /// Networking names at camelCase word boundaries (review F-1). See `networkingNames`, `networkingCallNames`.
    static func networkingHits(in code: String, file: String) -> [ScanHit] {
        var hits: [ScanHit] = []
        let scalars = Array(code.unicodeScalars)
        let identifiers = matches(of: #"[\p{L}\p{N}_]+"#, in: code)
        for (position, identifier) in identifiers.enumerated() {
            let identifierWords = subTokens(of: identifier.text)
            for name in networkingNames + clockNames
            where containsWords(subTokens(of: name), in: identifierWords, atEnd: false) {
                hits.append(ScanHit(file: file, line: identifier.line, rule: name, excerpt: identifier.text))
            }
            let next = nextNonWhitespace(in: scalars, from: identifier.endOffset)
            if next.map({ scalars[$0] }) == "(" || isFollowedByInitCall(identifiers, position, scalars: scalars) {
                for name in networkingCallNames
                where containsWords(subTokens(of: name), in: identifierWords, atEnd: true) {
                    if name == "Stream" && streamCallExemptions.contains(identifier.text) { continue }
                    hits.append(ScanHit(file: file, line: identifier.line, rule: "\(name)(",
                                        excerpt: identifier.text + "("))
                }
            }
            // `Host.current`: an identifier ending in the word `Host`, then `.`, then an identifier starting `current`.
            if containsWords(["Host"], in: identifierWords, atEnd: true),
               let dot = next, scalars[dot] == ".",
               position + 1 < identifiers.count,
               let member = nextNonWhitespace(in: scalars, from: dot + 1),
               identifiers[position + 1].startOffset == member,
               subTokens(of: identifiers[position + 1].text).first == "current" {
                hits.append(ScanHit(file: file, line: identifier.line, rule: "Host.current",
                                    excerpt: identifier.text + "." + identifiers[position + 1].text))
            }
        }
        return hits
    }

    /// The identifier at `position` is followed by `.init(` (whitespace allowed), the explicit spelling of a call
    /// (review F-7: `Host.init(name:)` is `Host(name:)`).
    static func isFollowedByInitCall(_ identifiers: [RegexMatch], _ position: Int, scalars: [Unicode.Scalar]) -> Bool {
        guard
            let dot = nextNonWhitespace(in: scalars, from: identifiers[position].endOffset), scalars[dot] == ".",
            position + 1 < identifiers.count,
            let member = nextNonWhitespace(in: scalars, from: dot + 1),
            identifiers[position + 1].startOffset == member, identifiers[position + 1].text == "init",
            let paren = nextNonWhitespace(in: scalars, from: identifiers[position + 1].endOffset)
        else { return false }
        return scalars[paren] == "("
    }

    /// The name of the call whose argument list immediately encloses `offset`: walk back to the nearest unbalanced
    /// `(` (skipping balanced `()`, `[]`, `{}`), then read the identifier right before it (whitespace allowed). `nil`
    /// when the enclosing bracket is not `(` or no identifier precedes it (so the label is not exempt). Code text only:
    /// string-literal text is blanked by the lexer, so brackets inside strings cannot confuse it.
    static func enclosingCallName(in scalars: [Unicode.Scalar], before offset: Int) -> String? {
        var depth = 0
        var index = offset - 1
        while index >= 0 {
            let scalar = scalars[index]
            if scalar == ")" || scalar == "]" || scalar == "}" {
                depth += 1
            } else if scalar == "(" || scalar == "[" || scalar == "{" {
                if depth == 0 {
                    guard scalar == "(" else { return nil }
                    var end = index - 1
                    while end >= 0, scalars[end].properties.isWhitespace { end -= 1 }
                    var start = end
                    while start >= 0, isIdentifierScalar(scalars[start]) { start -= 1 }
                    guard end > start else { return nil }
                    var name = String.UnicodeScalarView()
                    name.append(contentsOf: scalars[(start + 1)...end])
                    return String(name)
                }
                depth -= 1
            }
            index -= 1
        }
        return nil
    }

    /// `needle` occurs as consecutive words of `haystack` (case-sensitive); with `atEnd`, as its last words.
    static func containsWords(_ needle: [String], in haystack: [String], atEnd: Bool) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        if atEnd { return Array(haystack.suffix(needle.count)) == needle }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    /// Implicit-member `.now` with no receiver, which in a `Date` context is `Date.now` (review F-2):
    /// `at now: Date = .now`, `select(at: .now)`, `return .now`, `x ?? .now`. Receiver forms such as `moment.now`,
    /// `self.now`, `f().now`, `xs[0].now`, `x?.now` and a member chain continued on the next line are not hits.
    static func implicitNowHits(in code: String, file: String) -> [ScanHit] {
        var hits: [ScanHit] = []
        let scalars = Array(code.unicodeScalars)
        for match in matches(of: #"\.\s*now"# + rightBoundary, in: code) {
            var index = match.startOffset - 1
            var sawWhitespace = false
            while index >= 0, scalars[index].properties.isWhitespace {
                sawWhitespace = true
                index -= 1
            }
            var hasReceiver = false
            if index >= 0 {
                let previous = scalars[index]
                if isIdentifierScalar(previous) {
                    var wordStart = index
                    while wordStart > 0, isIdentifierScalar(scalars[wordStart - 1]) { wordStart -= 1 }
                    var word = String.UnicodeScalarView()
                    word.append(contentsOf: scalars[wordStart...index])
                    hasReceiver = !keywordsBeforeImplicitMember.contains(String(word))
                } else if previous == ")" || previous == "]" || previous == "}" {
                    hasReceiver = true
                } else if previous == "?" || previous == "!" || previous == ">" {
                    // `x?.now`, `x!.now`, `Box<T>.now` are receivers; `a ?? .now`, `c ? .now : d`, `a > .now` are not.
                    let doubled = previous == "?" && index > 0 && scalars[index - 1] == "?"
                    hasReceiver = !sawWhitespace && !doubled
                }
            }
            if !hasReceiver {
                hits.append(ScanHit(file: file, line: match.line, rule: "Date.now", excerpt: "implicit " + match.text))
            }
        }
        return hits
    }

    static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "_"
    }

    /// Index of the first non-whitespace scalar at or after `start`, if any.
    static func nextNonWhitespace(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var index = start
        while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 }
        return index < scalars.count ? index : nil
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
        /// Offset (in Unicode scalars) of the first scalar of the match.
        var startOffset: Int
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
        // scalarOffset[u] = number of Unicode scalars before UTF-16 offset u.
        var scalarOffset = [Int](repeating: 0, count: nsText.length + 1)
        var utf16Position = 0
        var scalarCount = 0
        for scalar in text.unicodeScalars {
            let width = UTF16.width(scalar)
            for step in 0..<width { scalarOffset[utf16Position + step] = scalarCount }
            utf16Position += width
            scalarCount += 1
        }
        scalarOffset[nsText.length] = scalarCount
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { result in
            var groups: [String] = []
            if result.numberOfRanges > 1 {
                for index in 1..<result.numberOfRanges {
                    let range = result.range(at: index)
                    groups.append(range.location == NSNotFound ? "" : nsText.substring(with: range))
                }
            }
            return RegexMatch(
                text: nsText.substring(with: result.range),
                groups: groups,
                line: line(forUTF16Offset: result.range.location, lineStarts: lineStarts),
                startOffset: scalarOffset[result.range.location],
                endOffset: scalarOffset[result.range.location + result.range.length]
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

