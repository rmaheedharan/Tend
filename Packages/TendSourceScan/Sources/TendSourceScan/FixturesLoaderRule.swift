// AC-M2-09 Rule 6, PO decision M2 Q23: the fixtures-loader exception. Brief M2 AC-M2-09 ("Fixtures-loader exception
// (M2 Q23)"); plan "Named files" and the WI-M2-01 Developer constraints. P-2, P-4.
//
// Exactly one file, `IngestionScanConfiguration.fixturesLoaderFile` in `TendEval`, may read bundled fixtures with
// `Data(contentsOf: <name>)`. A `contentsOf:` hit in that file is removed from the Rule 6 networking findings only when
// every condition below holds for it. In the same file the extra loader checks always run, whether or not the file
// has a read, so the file can never hold anything the brief's conditions forbid. Everywhere else nothing changes.
//
// How each brief condition is checked (all matching is case-sensitive, on code with comments and string text removed):
// - "The only contentsOf: form is Data(contentsOf: <name>) … one plain identifier and no other arguments" and "The
//   loader returns the bytes as Data and keeps nothing": the read is exactly `return try Data(contentsOf: <name>)`
//   (`Data` not qualified, not backticked, not `.init`), and the next code after its `)` is `}` or `;`, so the bytes
//   are returned as they are, not kept in a local or a property, and not transformed (a `.` on the next line counts as
//   a continuation, so it is rejected too).
// - "bound … by let / guard let / if let <name> = Bundle.main.url(forResource:": the binding starts a statement (after
//   `{`, `}`, `;`, a newline or the file start), so `while let`, `case let`, a second `if` clause, `var`, and stored
//   properties with modifiers are not bindings. The `Bundle.main.url(` call must pass the argument checks, and it must
//   end the binding: `else` follows for `guard`, `{` follows for `if`, and a new statement follows for `let`.
// - "<name> is bound exactly once in the file, in the same function body and before the call": the identifier
//   `<name>` occurs exactly twice in the whole file, once as the bound name and once as the read's argument, and the
//   binding is **in scope** at the read (PR #51 review F2): for `let`, the read comes after the call's `)`; for
//   `guard let`, after the `}` of its `else` block; and walking out from the read's innermost `{` reaches the block
//   that holds the binding through control-flow blocks only (`if`, `guard … else`, `else`, `for`, `while`, `repeat`,
//   `do`, `catch`, `switch`, `defer`). For `if let`, that block is the `{ … }` that directly follows the call. So a
//   read after an empty `if let` block, after a `do` / `for` / `if` block holding the `guard`, in the `else` of an
//   `if let` or in a nested closure is rejected. The binding must also start a statement (`startsStatement`); every
//   current plant that this catches is also caught by `bindingEnds` except a `let` after an attribute, which has its
//   own plant. It is kept as defence in depth.
// - Compiler directives (PR #51 review F1): an inactive `#if` hides code from the compiler, so a binding inside one
//   might not exist in the built program and the read would use a same-named value from another file. Every `#` left
//   in code (comments and raw-string delimiters are gone) is reported, and with any of them no read is allowed.
// - Slashes (PR #51 review round 2, F6): a regex literal can make the lexer read a quote as a string start and hide
//   directive lines or calls. Every `/` left in code is reported, and with any of them no read is allowed. A lexer that
//   understands `/…/` and `#/…/#` would close this for every rule; that is its own ticket.
// - Statements (PR #51 N1 a): the control-flow back-walk stops at a newline that ends a statement, so a closure on the
//   line after `repeat { } while false` is a closure. An Allman-style `{` on its own line is then read as a closure
//   body, which is only stricter.
// - Shadowing (PR #51 review F3): any `typealias`, and any declaration named `Data` or `Bundle`, is reported in the
//   loader file. Shadowing declared in **another** TendEval file cannot be seen by a text scan of this file; the
//   Reviewer confirms it (dev-notes).
// - "No function, initialiser, subscript or closure in the loader file declares a parameter": `func`, `init`
//   (`init?`, `init!`, generic), `subscript` and the accessors `set`, `willSet`, `didSet` must have an empty
//   parameter list. A closure signature (`{ x in`, `{ (x: Int) in`, also `{ [c] in` and `{ () in`) and an implicit
//   closure parameter (`$0`, `$1` …) are reported. This is stricter than the brief for `{ () in` and capture lists.
// - "The whole token URL does not occur": any identifier that is exactly `URL` (backticks removed).
// - "The only use of Bundle is Bundle.main.url(forResource:": every identifier that contains `Bundle` must be the
//   exact token `Bundle` that starts `Bundle.main.url(` with no `.` or backtick before it. Every `forResource`
//   identifier must be the first label of such a call. The brief's named hits each have their own pattern.
// - The `forResource:`, `subdirectory:` and `withExtension:` arguments: the call's top-level arguments are exactly
//   `forResource:`, then optionally `withExtension:`, then optionally `subdirectory:`. Each value is one string literal
//   with no interpolation and no other code (so identifiers, array elements, `nil`, `+` and interpolation are
//   rejected). The decoded literal text must match the brief's pattern over the whole text (`\A…\z`, so a trailing
//   newline does not slip past `$`). Any other label (for example `localization:`) is reported. The interpolation flag
//   is defence in depth: an interpolation holds code, so the blank-code check rejects it first, unless it holds only
//   whitespace (not valid Swift; own plant) or only a literal (rejected by the one-literal count; own plant).
// - "No literal contains ://": every whole literal (segments joined) in the file.
// - "No write or log API occurs": Rule 6 already reports write APIs outside the results writer and log APIs everywhere;
//   the loader file is not the results writer, so nothing extra is needed.
//
// Known limits, for the Reviewer (the brief also asks the Reviewer to confirm that the loader reads only bundle
// resources): the scanner reads text, not types. Control-flow blocks are recognised by their keywords; a trailing
// closure written directly in an `if` condition would be treated as part of that `if`.

import Foundation

extension IngestionSourceRules {

    // MARK: - Closed lists and patterns (brief AC-M2-09, M2 Q23)

    /// The brief's named hits in the loader file, after `Bundle(` (reported by the Bundle-use check). In the brief's
    /// order and spelling. A leading `.` is the brief's way of naming a member; the scan matches the name with or
    /// without a receiver, which is stricter.
    public static let loaderNamedHits: [String] = [
        ".resourceURL", ".bundleURL", ".urls(forResourcesWithExtension:", ".path(forResource:",
        "appendingPathComponent(", "appending(path:", "appending(component:", "deletingLastPathComponent",
    ]

    /// The `forResource:` and `subdirectory:` literal pattern (brief, verbatim).
    public static let loaderResourceNamePattern = "^[A-Za-z0-9_-]+$"
    /// The `withExtension:` literal pattern (brief, verbatim).
    public static let loaderExtensionPattern = "^[A-Za-z0-9]+$"

    /// The brief's `^…$` pattern anchored to the whole text (`\A…\z`): ICU's `$` also matches before a final newline.
    static func wholeTextPattern(_ pattern: String) -> String {
        #"\A"# + String(pattern.dropFirst().dropLast()) + #"\z"#
    }

    public static func isLoaderResourceName(_ text: String) -> Bool {
        wholeTextMatches(wholeTextPattern(loaderResourceNamePattern), text)
    }

    public static func isLoaderExtension(_ text: String) -> Bool {
        wholeTextMatches(wholeTextPattern(loaderExtensionPattern), text)
    }

    /// Fail closed: an invalid pattern accepts nothing (`SourceScanner.matches` returns a synthetic hit, which here
    /// would mean "accepted", so it is not used).
    static func wholeTextMatches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// `Bundle.main.url(`: `Bundle` with no identifier scalar, `.` or backtick before it.
    static let loaderBundleCallPattern = #"(?<![\p{L}\p{N}_.`])Bundle\s*\.\s*main\s*\.\s*url\s*\("#
    /// A binding: `let` / `guard let` / `if let` `<name> = Bundle.main.url(`.
    static let loaderBindingPattern =
        #"(?<![\p{L}\p{N}_.`])(?:(guard|if)\s+)?let\s+([\p{L}_][\p{L}\p{N}_]*)\s*=\s*Bundle\s*\.\s*main\s*\.\s*url\s*\("#
    /// The read: `return try Data(contentsOf: <name>)`.
    static let loaderReadPattern =
        #"(?<![\p{L}\p{N}_.`])return\s+try\s+Data\s*\(\s*contentsOf\s*:\s*([\p{L}_][\p{L}\p{N}_]*)\s*\)"#
    /// `func` with its name; the parameter list is the next `(`.
    static let loaderFuncPattern = #"(?<![\p{L}\p{N}_.`])func\s+"#
    /// Every `#` left in lexed code: compiler directives (`#if`, `#elseif`, `#else`, `#endif`, `#sourceLocation`) and
    /// any other `#name` (PR #51 review F1, fail closed).
    static let loaderDirectivePattern = #"#\s*[\p{L}_]*"#
    /// Implicit closure parameters.
    static let loaderImplicitParameterPattern = #"\$[0-9]"#
    static let loaderLabelPattern = #"\A\s*([\p{L}_][\p{L}\p{N}_]*)\s*:"#

    /// The fixed regexes of the loader rule (the pattern self-test compiles each one).
    static var loaderPatterns: [String] {
        [loaderBundleCallPattern, loaderBindingPattern, loaderReadPattern, loaderFuncPattern, loaderDirectivePattern,
         loaderImplicitParameterPattern, loaderLabelPattern,
         wholeTextPattern(loaderResourceNamePattern), wholeTextPattern(loaderExtensionPattern)]
            + loaderNamedHits.map(loaderNamedHitPattern)
    }

    static func loaderNamedHitPattern(_ hit: String) -> String {
        let name = hit.hasPrefix(".") ? String(hit.dropFirst()) : hit
        return name.contains("(") ? callPattern(name) : wholeTokenPattern(name)
    }
}

/// The result of the loader checks for one file: the `contentsOf:` offsets that are the allowed read, and the loader
/// findings.
struct FixturesLoaderCheck {
    var allowedContentsOfOffsets: Set<Int> = []
    var violations: [RuleViolation] = []
}

/// The M2 Q23 checks over one lexed loader file.
struct FixturesLoaderRule {
    let facts: FileFacts
    let scalars: [Unicode.Scalar]
    /// For each scalar offset, the offset of the innermost enclosing `{` (or -1).
    let enclosingBrace: [Int]
    /// For each `{` offset, the offset of the `{` that encloses it (or -1).
    let parentBrace: [Int: Int]

    static let controlKeywords: Set<String> = ["if", "guard", "while", "for", "switch", "catch"]
    static let controlOpeners: Set<String> = ["else", "do", "repeat", "defer"]
    static let declarationKeywords: Set<String> = [
        "func", "init", "deinit", "subscript", "get", "set", "willSet", "didSet", "struct", "class", "enum",
        "extension", "protocol", "actor",
    ]
    static let accessorKeywords: Set<String> = ["set", "willSet", "didSet"]
    static let shadowKeywords: Set<String> = [
        "typealias", "associatedtype", "struct", "class", "enum", "actor", "protocol", "extension", "let", "var",
        "func", "case",
    ]

    init(facts: FileFacts) {
        self.facts = facts
        let scalars = Array(facts.lexed.code.unicodeScalars)
        self.scalars = scalars
        var enclosing = [Int](repeating: -1, count: scalars.count + 1)
        var parents: [Int: Int] = [:]
        var stack: [Int] = []
        for (index, scalar) in scalars.enumerated() {
            enclosing[index] = stack.last ?? -1
            if scalar == "{" {
                parents[index] = stack.last ?? -1
                stack.append(index)
            } else if scalar == "}" {
                _ = stack.popLast()
            }
        }
        enclosing[scalars.count] = stack.last ?? -1
        enclosingBrace = enclosing
        parentBrace = parents
    }

    func violation(_ check: String, line: Int, excerpt: String) -> RuleViolation {
        RuleViolation(rule: .rule6, check: "fixtures loader: " + check, file: facts.file.path, line: line,
                      excerpt: excerpt)
    }

    func run() -> FixturesLoaderCheck {
        var result = FixturesLoaderCheck()
        let code = facts.lexed.code
        let identifiers = facts.identifiers

        // `Bundle.main.url(` calls and their arguments.
        var validCallOpenParens: Set<Int> = []
        var callStarts: Set<Int> = []
        var firstLabelOffsets: Set<Int> = []
        for match in SourceScanner.matches(of: IngestionSourceRules.loaderBundleCallPattern, in: code) {
            callStarts.insert(match.startOffset)
            let open = match.endOffset - 1
            switch checkArguments(open: open) {
            case .valid(let forResourceOffset):
                validCallOpenParens.insert(open)
                firstLabelOffsets.insert(forResourceOffset)
            case .invalid(let reason, let forResourceOffset):
                if let forResourceOffset { firstLabelOffsets.insert(forResourceOffset) }
                result.violations.append(violation("resource argument: " + reason, line: match.line,
                                                   excerpt: match.text))
            }
        }

        for identifier in identifiers {
            // The whole token `URL`.
            if identifier.text == "URL" {
                result.violations.append(violation("token URL", line: identifier.line, excerpt: identifier.text))
            }
            // The only use of `Bundle` is `Bundle.main.url(forResource:`.
            if identifier.text.contains("Bundle")
                && !(identifier.text == "Bundle" && callStarts.contains(identifier.startOffset)) {
                result.violations.append(violation("Bundle use other than Bundle.main.url(forResource:",
                                                   line: identifier.line, excerpt: identifier.text))
            }
            if identifier.text == "forResource" && !firstLabelOffsets.contains(identifier.startOffset) {
                result.violations.append(violation("forResource outside Bundle.main.url(", line: identifier.line,
                                                   excerpt: identifier.text))
            }
        }

        // The brief's named hits (backticks removed, like every call pattern).
        for hit in IngestionSourceRules.loaderNamedHits {
            for match in SourceScanner.matches(of: IngestionSourceRules.loaderNamedHitPattern(hit), in: facts.callCode) {
                result.violations.append(violation(hit.hasPrefix(".") ? String(hit.dropFirst()) : hit,
                                                   line: match.line, excerpt: match.text))
            }
        }

        // No literal contains `://`.
        for literal in facts.lexed.stringLiterals where literal.text.contains("://") {
            result.violations.append(violation(":// literal", line: literal.line, excerpt: "\"\(literal.text)\""))
        }

        result.violations += parameterViolations()
        result.violations += shadowViolations()

        // Compiler directives (PR #51 review F1): an inactive `#if` hides code from the compiler, so a binding inside
        // one may not exist in the built program. Fail closed: every `#` left in code (comments and raw-string
        // delimiters are already gone) is reported, and with any of them no read is allowed.
        let directives = SourceScanner.matches(of: IngestionSourceRules.loaderDirectivePattern, in: code)
        for match in directives {
            result.violations.append(violation("compiler directive or # name", line: match.line, excerpt: match.text))
        }
        // Slashes (PR #51 review round 2, F6): a regex literal such as `/"""/` makes the lexer read a quote as the start
        // of a string, which can hide directive lines or calls (the lexer's known limit, header of `SourceScanner`).
        // Comments are already removed and the loader needs no division, so every `/` left in code is reported, and
        // with any of them no read is allowed.
        let slashes = SourceScanner.matches(of: "/", in: code)
        for match in slashes {
            result.violations.append(violation("slash in code (regex literal or division)", line: match.line,
                                               excerpt: match.text))
        }
        guard directives.isEmpty, slashes.isEmpty else { return result }

        // The allowed reads.
        let bindings = validBindings(validCallOpenParens: validCallOpenParens)
        let contentsOf = facts.networkingHits.filter { $0.rule == SourceScanner.contentsOfRule }
        let reads = SourceScanner.matches(of: IngestionSourceRules.loaderReadPattern, in: code)
        for hit in contentsOf {
            guard let offset = hit.offset,
                  let read = reads.first(where: { $0.startOffset <= offset && offset < $0.endOffset }),
                  let name = read.groups.first, isAllowedRead(read, name: name, bindings: bindings, in: identifiers)
            else { continue }
            result.allowedContentsOfOffsets.insert(offset)
        }
        return result
    }

    // MARK: - The read and its binding

    struct Binding {
        var name: String
        /// Offset of the bound name.
        var nameOffset: Int
        /// The binding is in scope only after this offset: the call's `)` for `let`, the `}` of the `else` block for
        /// `guard let`, the `{` of the block for `if let`.
        var scopeStart: Int
        /// The `{` whose block the binding is visible in: the enclosing block for `let` and `guard let`, the `if`
        /// block itself for `if let` (-1 at top level).
        var scopeBrace: Int
    }

    func validBindings(validCallOpenParens: Set<Int>) -> [Binding] {
        var result: [Binding] = []
        let code = facts.lexed.code
        for match in SourceScanner.matches(of: IngestionSourceRules.loaderBindingPattern, in: code) {
            let open = match.endOffset - 1
            guard validCallOpenParens.contains(open), startsStatement(match.startOffset),
                  let close = closingParen(from: open),
                  let name = match.groups.dropFirst().first,
                  let nameMatch = facts.identifiers.first(where: {
                      $0.text == name && $0.startOffset >= match.startOffset && $0.endOffset <= match.endOffset
                          && $0.text != "let" && $0.text != "guard" && $0.text != "if"
                  })
            else { continue }
            let keyword = match.groups.first ?? ""
            guard bindingEnds(after: close, keyword: keyword),
                  let scope = bindingScope(keyword: keyword, statementStart: match.startOffset, close: close)
            else { continue }
            result.append(Binding(name: name, nameOffset: nameMatch.startOffset, scopeStart: scope.start,
                                  scopeBrace: scope.brace))
        }
        return result
    }

    func isAllowedRead(_ read: SourceScanner.RegexMatch, name: String, bindings: [Binding],
                       in identifiers: [SourceScanner.RegexMatch]) -> Bool {
        // The bytes are returned as they are: only `}` or `;` may follow the read.
        if let next = SourceScanner.nextNonWhitespace(in: scalars, from: read.endOffset),
           scalars[next] != "}" && scalars[next] != ";" {
            return false
        }
        let occurrences = identifiers.filter { $0.text == name }
        guard occurrences.count == 2,
              let argument = occurrences.first(where: {
                  $0.startOffset >= read.startOffset && $0.endOffset <= read.endOffset
              }),
              let binding = bindings.first(where: { $0.name == name }),
              bindings.filter({ $0.name == name }).count == 1,
              occurrences.contains(where: { $0.startOffset == binding.nameOffset }),
              binding.nameOffset < argument.startOffset
        else { return false }
        return isInScope(binding, at: read.startOffset)
    }

    /// Where a binding becomes visible (PR #51 review F2): see `Binding`. `nil` when the block cannot be found.
    func bindingScope(keyword: String, statementStart: Int, close: Int) -> (start: Int, brace: Int)? {
        let enclosing = enclosingBrace[statementStart]
        switch keyword {
        case "guard":
            guard let elseStart = SourceScanner.nextNonWhitespace(in: scalars, from: close + 1),
                  let open = SourceScanner.nextNonWhitespace(in: scalars, from: elseStart + 4), scalars[open] == "{",
                  let end = matchingClose(from: open)
            else { return nil }
            return (end, enclosing)
        case "if":
            guard let open = SourceScanner.nextNonWhitespace(in: scalars, from: close + 1), scalars[open] == "{"
            else { return nil }
            return (open, open)
        default:
            return (close, enclosing)
        }
    }

    /// The read at `offset` sees the binding: it comes after `scopeStart`, and walking out from the read's innermost
    /// `{` reaches the binding's block through control-flow blocks only (no function, closure or type boundary).
    func isInScope(_ binding: Binding, at offset: Int) -> Bool {
        guard offset > binding.scopeStart else { return false }
        var brace = enclosingBrace[min(offset, enclosingBrace.count - 1)]
        while brace != binding.scopeBrace {
            guard brace >= 0, isControlFlowBlock(brace) else { return false }
            brace = parentBrace[brace] ?? -1
        }
        return true
    }

    /// The binding's `Bundle.main.url(…)` call is the whole value: `else` follows for `guard`, `{` for `if`, and for
    /// `let` the next code is `;`, `}`, the end of the file, or a new statement on a later line that does not start
    /// with `.` (a continuation).
    func bindingEnds(after close: Int, keyword: String) -> Bool {
        guard let next = SourceScanner.nextNonWhitespace(in: scalars, from: close + 1) else {
            return keyword.isEmpty
        }
        switch keyword {
        case "guard":
            return identifier(at: next) == "else"
        case "if":
            return scalars[next] == "{"
        default:
            if scalars[next] == ";" || scalars[next] == "}" { return true }
            let between = scalars[(close + 1)..<next]
            return between.contains("\n") && SourceScanner.isIdentifierScalar(scalars[next])
        }
    }

    /// The text at `offset` starts a statement: only spaces and tabs, then a newline, `{`, `}`, `;` or the file start.
    func startsStatement(_ offset: Int) -> Bool {
        var index = offset - 1
        while index >= 0 {
            let scalar = scalars[index]
            if scalar == "\n" { return true }
            if !scalar.properties.isWhitespace { return scalar == "{" || scalar == "}" || scalar == ";" }
            index -= 1
        }
        return true
    }

    // MARK: - Scopes

    /// Walks back from the `{` at `brace` through its statement (balanced brackets skipped) and reads the keywords.
    func isControlFlowBlock(_ brace: Int) -> Bool {
        var depth = 0
        var index = brace - 1
        var first = true
        while index >= 0 {
            let scalar = scalars[index]
            if scalar == ")" || scalar == "]" || scalar == "}" {
                if scalar == "}" && depth == 0 { return false }
                depth += 1
            } else if scalar == "(" || scalar == "[" || scalar == "{" {
                if depth == 0 { return false }
                depth -= 1
            } else if scalar == ";" && depth == 0 {
                return false
            } else if scalar == "\n" && depth == 0 && endsStatement(beforeNewline: index) {
                // PR #51 N1 (a): a line that ends in a name or a closing bracket ends the statement before this one
                // (`repeat { } while false`, then `let g = {` on the next line).
                return false
            } else if SourceScanner.isIdentifierScalar(scalar) {
                var start = index
                while start > 0, SourceScanner.isIdentifierScalar(scalars[start - 1]) { start -= 1 }
                if depth == 0 {
                    let word = text(start, index + 1)
                    if first && FixturesLoaderRule.controlOpeners.contains(word) { return true }
                    if FixturesLoaderRule.controlKeywords.contains(word) { return true }
                    if FixturesLoaderRule.declarationKeywords.contains(word) { return false }
                    first = false
                }
                index = start
            }
            index -= 1
        }
        return false
    }

    /// The line before the newline at `newline` ends with a name or a closing bracket, so the statement ends there.
    /// A line that ends with an operator, `,`, `(` or `.` continues. This can only make a block look like a closure
    /// (stricter), for example an `if` whose `{` is on its own line.
    func endsStatement(beforeNewline newline: Int) -> Bool {
        var index = newline - 1
        while index >= 0, scalars[index] != "\n", scalars[index].properties.isWhitespace { index -= 1 }
        guard index >= 0, scalars[index] != "\n" else { return false }
        let last = scalars[index]
        return SourceScanner.isIdentifierScalar(last) || last == ")" || last == "]" || last == "}"
    }

    // MARK: - Shadowing (PR #51 review F3)

    /// Any `typealias`, and any declaration named `Data` or `Bundle` (after a declaration keyword, `case`, or `<` of a
    /// generic parameter list). Shadowing from another file cannot be seen by a text scan of this file; the Reviewer
    /// confirms it (dev-notes).
    func shadowViolations() -> [RuleViolation] {
        var result: [RuleViolation] = []
        let identifiers = facts.identifiers
        for (position, identifier) in identifiers.enumerated() {
            if identifier.text == "typealias" {
                result.append(violation("typealias (may shadow Data or Bundle)", line: identifier.line,
                                        excerpt: identifier.text))
                continue
            }
            guard identifier.text == "Data" || identifier.text == "Bundle" else { continue }
            var index = identifier.startOffset - 1
            if index >= 0 && scalars[index] == "`" { index -= 1 }   // a backticked name (PR #51 N1 b)
            while index >= 0, scalars[index].properties.isWhitespace { index -= 1 }
            let declared: Bool
            if index >= 0 && scalars[index] == "<" {
                declared = true
            } else if position > 0, identifiers[position - 1].endOffset == index + 1 {
                declared = FixturesLoaderRule.shadowKeywords.contains(identifiers[position - 1].text)
            } else {
                declared = false
            }
            if declared {
                result.append(violation("declaration shadows \(identifier.text)", line: identifier.line,
                                        excerpt: identifier.text))
            }
        }
        return result
    }

    // MARK: - Parameters

    func parameterViolations() -> [RuleViolation] {
        var result: [RuleViolation] = []
        let code = facts.lexed.code
        // `func name(…)`: the next `(` after the keyword.
        for match in SourceScanner.matches(of: IngestionSourceRules.loaderFuncPattern, in: code) {
            if let open = scalars[match.endOffset...].firstIndex(of: "("), !isEmptyList(open: open) {
                result.append(violation("parameter declared (func)", line: match.line, excerpt: match.text))
            }
        }
        for identifier in facts.identifiers {
            let word = identifier.text
            guard word == "init" || word == "subscript" || FixturesLoaderRule.accessorKeywords.contains(word),
                  !isMemberAccess(identifier.startOffset),
                  var next = SourceScanner.nextNonWhitespace(in: scalars, from: identifier.endOffset)
            else { continue }
            if word == "init", scalars[next] == "?" || scalars[next] == "!",
               let after = SourceScanner.nextNonWhitespace(in: scalars, from: next + 1) {
                next = after
            }
            if word != "subscript" && !FixturesLoaderRule.accessorKeywords.contains(word), scalars[next] == "<",
               let closeAngle = scalars[next...].firstIndex(of: ">"),
               let after = SourceScanner.nextNonWhitespace(in: scalars, from: closeAngle + 1) {
                next = after
            }
            if scalars[next] == "(", !isEmptyList(open: next) {
                result.append(violation("parameter declared (\(word))", line: identifier.line, excerpt: word))
            } else if word == "subscript" {
                result.append(violation("parameter declared (subscript)", line: identifier.line, excerpt: word))
            }
        }
        // Closure signatures: an `in` that is not part of a `for … in` loop.
        for identifier in facts.identifiers where identifier.text == "in" && isClosureSignature(identifier.startOffset) {
            result.append(violation("parameter declared (closure)", line: identifier.line, excerpt: "in"))
        }
        for match in SourceScanner.matches(of: IngestionSourceRules.loaderImplicitParameterPattern, in: code) {
            result.append(violation("parameter declared (closure \(match.text))", line: match.line,
                                    excerpt: match.text))
        }
        return result
    }

    /// Walks back from `in`: a `for` at the same depth means a loop; reaching an unbalanced `{` first means a closure
    /// signature.
    func isClosureSignature(_ offset: Int) -> Bool {
        var depth = 0
        var index = offset - 1
        while index >= 0 {
            let scalar = scalars[index]
            if scalar == ")" || scalar == "]" || scalar == "}" {
                if scalar == "}" && depth == 0 { return false }
                depth += 1
            } else if scalar == "(" || scalar == "[" || scalar == "{" {
                if depth == 0 { return scalar == "{" }
                depth -= 1
            } else if scalar == ";" && depth == 0 {
                return false
            } else if SourceScanner.isIdentifierScalar(scalar) {
                var start = index
                while start > 0, SourceScanner.isIdentifierScalar(scalars[start - 1]) { start -= 1 }
                if depth == 0 && text(start, index + 1) == "for" { return false }
                index = start
            }
            index -= 1
        }
        return false
    }

    /// `(…)` at `open` holds only whitespace (an unclosed list is not empty).
    func isEmptyList(open: Int) -> Bool {
        guard let close = closingParen(from: open) else { return false }
        return scalars[(open + 1)..<close].allSatisfy { $0.properties.isWhitespace }
    }

    /// A `.` (whitespace allowed) directly before `offset`: a member call such as `self.init(` or `x.set(`.
    func isMemberAccess(_ offset: Int) -> Bool {
        var index = offset - 1
        while index >= 0, scalars[index].properties.isWhitespace { index -= 1 }
        return index >= 0 && scalars[index] == "."
    }

    // MARK: - Arguments

    enum ArgumentCheck {
        case valid(forResourceOffset: Int)
        case invalid(String, forResourceOffset: Int?)
    }

    /// The top-level arguments of the call whose `(` is at `open`.
    func checkArguments(open: Int) -> ArgumentCheck {
        guard let close = closingParen(from: open) else { return .invalid("unclosed call", forResourceOffset: nil) }
        var ranges: [Range<Int>] = []
        var depth = 0
        var start = open + 1
        for index in (open + 1)..<close {
            let scalar = scalars[index]
            if scalar == "(" || scalar == "[" || scalar == "{" { depth += 1 }
            if scalar == ")" || scalar == "]" || scalar == "}" { depth -= 1 }
            if scalar == "," && depth == 0 {
                ranges.append(start..<index)
                start = index + 1
            }
        }
        ranges.append(start..<close)

        var labels: [String] = []
        var forResourceOffset: Int?
        for range in ranges {
            let argument = text(range.lowerBound, range.upperBound)
            guard let label = SourceScanner.matches(of: IngestionSourceRules.loaderLabelPattern, in: argument).first,
                  let name = label.groups.first
            else { return .invalid("unlabelled argument", forResourceOffset: forResourceOffset) }
            if labels.isEmpty && name == "forResource" {
                let labelStart = argument.unicodeScalars.firstIndex(where: { !$0.properties.isWhitespace })
                    .map { argument.unicodeScalars.distance(from: argument.unicodeScalars.startIndex, to: $0) } ?? 0
                forResourceOffset = range.lowerBound + labelStart
            }
            labels.append(name)
            let valueRange = (range.lowerBound + label.endOffset)..<range.upperBound
            guard let literal = singleLiteral(in: valueRange) else {
                return .invalid("\(name): not one plain string literal", forResourceOffset: forResourceOffset)
            }
            let ok = name == "withExtension"
                ? IngestionSourceRules.isLoaderExtension(literal) : IngestionSourceRules.isLoaderResourceName(literal)
            if !ok {
                return .invalid("\(name): \"\(literal)\" does not match the brief's pattern",
                                forResourceOffset: forResourceOffset)
            }
        }
        let allowed: [[String]] = [
            ["forResource"], ["forResource", "withExtension"], ["forResource", "subdirectory"],
            ["forResource", "withExtension", "subdirectory"],
        ]
        guard allowed.contains(labels) else {
            return .invalid("labels \(labels) are not forResource:, withExtension:, subdirectory:",
                            forResourceOffset: forResourceOffset)
        }
        guard let forResourceOffset else { return .invalid("no forResource:", forResourceOffset: nil) }
        return .valid(forResourceOffset: forResourceOffset)
    }

    /// The decoded text of the one string literal that is the whole of `range` (only whitespace code around it, no
    /// interpolation), or `nil`.
    func singleLiteral(in range: Range<Int>) -> String? {
        guard scalars[range].allSatisfy({ $0.properties.isWhitespace }) else { return nil }
        let inside = facts.lexed.stringLiterals.filter {
            $0.codeStart >= range.lowerBound && $0.codeEnd <= range.upperBound
        }
        guard inside.count == 1, let literal = inside.first, !literal.hasInterpolation else { return nil }
        return literal.text
    }

    /// The index of the bracket that closes the one at `open` (any kind), or `nil`.
    func matchingClose(from open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "(" || scalar == "[" || scalar == "{" { depth += 1 }
            if scalar == ")" || scalar == "]" || scalar == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    func closingParen(from open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "(" || scalar == "[" || scalar == "{" { depth += 1 }
            if scalar == ")" || scalar == "]" || scalar == "}" {
                depth -= 1
                if depth == 0 { return scalar == ")" ? index : nil }
            }
            index += 1
        }
        return nil
    }

    func identifier(at offset: Int) -> String? {
        guard SourceScanner.isIdentifierScalar(scalars[offset]) else { return nil }
        var end = offset
        while end < scalars.count, SourceScanner.isIdentifierScalar(scalars[end]) { end += 1 }
        return text(offset, end)
    }

    func text(_ start: Int, _ end: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }
}
