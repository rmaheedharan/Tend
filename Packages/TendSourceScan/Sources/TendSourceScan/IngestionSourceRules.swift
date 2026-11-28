// The AC-M2-09 rule engine: Rules 1–6 over the `Sources` of `TendIngestion`, `TendAI` and `TendEval`, with comments
// removed (the AC-M1-23 approach, through `SourceScanner.lex`). Brief M2 AC-M2-09 (v4 plus PO decision
// M2 Q24); plan WI-M2-01; ADR-0006.
// P-1, P-2, P-3, P-4.
//
// The closed lists below are copied from the brief. Changing one needs a PO decision that updates AC-M2-09.
//
// How each list is matched (the brief fixes the lists, the matching follows the M1 precedent):
// - Networking patterns: the AC-M1-23 networking patterns as M1 matches them (names at camelCase word boundaries, the
//   call names `Stream(` `InputStream(` `OutputStream(` `Host(` `socket(` and `Host.current`, `URL(string:`, and
//   `contentsOf:` URL loading with exactly the AC-M1-23 / Q23 `append` / `insert` exemption and **no** file allowlist),
//   plus the M2 names (camelCase word boundaries), plus `import Network`, `import CFNetwork` and
//   `import FoundationNetworking`. One AC-M1-23 entry is not a networking pattern here: `http(s)` string literals,
//   because Rule 4 governs every literal and allows `https://<host>` in the allowlisted files (review R1-F1).
// - Media types and the write and log names: the name occurs **anywhere inside** an identifier (case-sensitive
//   substring). This is stricter than the camelCase split, so `AVAssetReader`, `AppLogger` and `OSLogType` are hits.
//   (`AVURLAsset` does not contain `AVAsset` and is not a hit; it needs `AVFoundation`, which Rules 1–3 do not allow.)
//   Every camelCase word-boundary hit is also a substring hit, so this relaxes none of the type-name patterns that
//   M2 Q24 keeps on the AC-M1-23 camelCase rule (`Logger`, `FileManager`, `OSLog`, `AppStorage` and the rest).
// - Call patterns (M2 Q24, "How call patterns match"): every write, log and session-method call. A call matches only
//   when the character before the name is not a letter, digit or `_` (a `.` receiver is fine). Matching is
//   case-sensitive. Whitespace and newlines are ignored between the name and `(`, and between `(` and the first label.
//   Backticks are removed first. So `Swift.print(` and `x.write(to:` are hits, and `reprint(`, `inputs(` (not
//   `puts(`), `snprintf(` (not `printf(`), `metadata(for:` (not `data(for:`) and `data(forKey:` are not.
// - Method references (M2 Q24): `dataTask`, `uploadTask`, `downloadTask`, `streamTask` and `webSocketTask` are also
//   hits as whole tokens without `(`, so `let f = s.dataTask` is caught.
// - Rule 3 session methods (M2 Q24): the only allowed session-method call is `bytes(for:` whose balanced argument list
//   contains the label `delegate:` (checked like AC-M1-23's `using:` rule).
// - Rule 6 imports (M2 Q24): the module is the first path component after `import` and any kind keyword
//   (`import struct Darwin.C` is `Darwin`). Attributes are ignored, so `@_exported` and `@_implementationOnly` imports
//   count. Rules 1–3 keep the stricter M1 form: the whole import target must be a listed module.
// - The M2 Q23 fixtures-loader exception (scanner follow-up `m2/scanner-loader-exception`; WI-M2-01 stayed strict): in
//   the one named loader file only, a `contentsOf:` hit that is exactly the brief's allowed read is removed from the
//   Rule 6 findings, and the loader's own checks always run in that file. See `FixturesLoaderRule.swift`. Everywhere
//   else `Data(contentsOf:` is still a hit in every TendEval file.
// - Rule 3 prefix rule (N-1): an identifier token is the **whole** Swift identifier, never split at camelCase, so
//   `willPerformHTTPRedirection` is not a hit and `HTTPCookieStorage` is.
// - Rule 4 (T-30): host-like is tested on the **whole** decoded literal segment (the lexer splits a literal at each
//   interpolation, so `"https://\(host)"` gives the segment `https://`, which is host-like and not allowed).

import Foundation

/// The three scanned modules (brief Definitions, binding names).
public enum ScannedModule: String, Sendable, CaseIterable, Comparable {
    case tendIngestion = "TendIngestion"
    case tendAI = "TendAI"
    case tendEval = "TendEval"

    public static func < (lhs: ScannedModule, rhs: ScannedModule) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}

/// One source file to scan. `path` is repository-relative with `/` separators; the configuration's file lists use
/// the same form.
public struct ScannedFile: Sendable, Equatable {
    public var module: ScannedModule
    public var path: String
    public var text: String

    public init(module: ScannedModule, path: String, text: String) {
        self.module = module
        self.path = path
        self.text = text
    }
}

/// The six rules of AC-M2-09.
public enum IngestionScanRule: Int, Sendable, CaseIterable, CustomStringConvertible {
    case rule1 = 1, rule2, rule3, rule4, rule5, rule6

    public var description: String { "Rule \(rawValue)" }
}

/// One AC-M2-09 finding: which rule, which check inside it, where, and the matched text.
public struct RuleViolation: Sendable, Equatable, CustomStringConvertible {
    public var rule: IngestionScanRule
    public var check: String
    public var file: String
    public var line: Int
    public var excerpt: String

    public init(rule: IngestionScanRule, check: String, file: String, line: Int, excerpt: String) {
        self.rule = rule
        self.check = check
        self.file = file
        self.line = line
        self.excerpt = excerpt
    }

    public var description: String { "\(file):\(line): [\(rule) \(check)] \(excerpt)" }
}

/// The file paths the rules name (plan "Named files"). Moving one needs a plan update and the Tester's note.
public struct IngestionScanConfiguration: Sendable, Equatable {
    /// Rule 3: the cloud-adapter allowlist (closed list of file paths in the plan).
    public var cloudAdapterAllowlist: Set<String>
    /// Rule 2: the only `TendAI` files where media types may appear.
    public var speechAdapterFiles: Set<String>
    /// Rule 5: the one file where the T-27 exception may apply.
    public var speechPermissionFile: String
    /// Rule 5: `true` only after the T-27 check on the owner-run Mac confirms that iOS 26 needs the two calls
    /// (WI-M2-M1). Until then there is no exception.
    public var speechPermissionExceptionEnabled: Bool
    /// Rule 6: the only `TendEval` file where write APIs may appear.
    public var resultsWriterFile: String
    /// Rule 4: the payload builder's provider table in `TendIngestion`, the only file where the bare hosts may appear
    /// (brief AC-M2-09 Rule 4 "Where they may appear"; review R1-F6, named in the plan by WI-M2-10).
    public var providerTableFile: String
    /// Rule 6 (M2 Q23): the fixtures loader, the only `TendEval` file that may read bundled fixtures with
    /// `Data(contentsOf: <name>)`, under the brief's conditions.
    public var fixturesLoaderFile: String

    public init(
        cloudAdapterAllowlist: Set<String>,
        speechAdapterFiles: Set<String>,
        speechPermissionFile: String,
        speechPermissionExceptionEnabled: Bool,
        resultsWriterFile: String,
        providerTableFile: String,
        fixturesLoaderFile: String
    ) {
        self.cloudAdapterAllowlist = cloudAdapterAllowlist
        self.speechAdapterFiles = speechAdapterFiles
        self.speechPermissionFile = speechPermissionFile
        self.speechPermissionExceptionEnabled = speechPermissionExceptionEnabled
        self.resultsWriterFile = resultsWriterFile
        self.providerTableFile = providerTableFile
        self.fixturesLoaderFile = fixturesLoaderFile
    }
}

public enum IngestionSourceRules {

    // MARK: - Closed lists (brief AC-M2-09, T-11, T-23, T-27, T-30)

    /// Networking patterns: the M2 names added to the AC-M1-23 networking names (`SourceScanner.networkingNames`).
    /// Matched at camelCase word boundaries like the M1 names. (`URLSession`, `URLRequest` and `URLComponents` are
    /// already in the M1 list; they are repeated here because the brief names them.)
    public static let addedNetworkingNames: [String] = [
        "FoundationNetworking", "URLSession", "URLRequest", "URLProtocol", "URLSessionConfiguration",
        "URLComponents", "NWConnection", "SFSpeech",
    ]

    /// Networking patterns, M2 Q24: the session-method calls (call-pattern rule).
    public static let sessionMethodCalls: [String] = [
        "dataTask(", "uploadTask(", "downloadTask(", "streamTask(", "webSocketTask(", "data(for:", "data(from:",
        "bytes(for:", "bytes(from:", "upload(for:", "upload(from:", "download(for:", "download(from:",
        "download(resumeFrom:",
    ]

    /// Networking patterns, M2 Q24: the task-creating names that also match as whole tokens without `(`.
    public static let methodReferenceNames: [String] = [
        "dataTask", "uploadTask", "downloadTask", "streamTask", "webSocketTask",
    ]

    /// Rule 3 (M2 Q24): the one allowed session-method call, when its argument list contains `delegate:`.
    public static let streamingReadCall = "bytes(for:"
    public static let delegateLabelPattern = SourceScanner.leftBoundary + #"delegate\s*:"#

    /// Networking imports: `import Network`, `import CFNetwork`, and `FoundationNetworking` (banned everywhere).
    public static let networkingImports: Set<String> = ["Network", "CFNetwork", "FoundationNetworking"]

    /// The full name list used for networking-pattern hits.
    public static var networkingNames: [String] {
        var names = SourceScanner.networkingNames
        for name in addedNetworkingNames where !names.contains(name) { names.append(name) }
        return names
    }

    /// Media types (closed).
    public static let mediaTypes: [String] = [
        "AVAudioBuffer", "AVAudioPCMBuffer", "AVAudioFile", "AVAsset", "CMSampleBuffer",
        "CVPixelBuffer", "CVImageBuffer", "CGImage", "CIImage", "UIImage", "NSImage",
    ]

    /// Write APIs (closed; M2 Q24): type names, then call patterns.
    public static let writeNames: [String] = [
        "FileManager", "FileHandle", "OutputStream", "UserDefaults", "NSUbiquitousKeyValueStore", "AppStorage",
        "SceneStorage",
    ]
    public static let writeCalls: [String] = [
        "write(to:", "write(toFile:", "createFile(", "archiveRootObject(", "fopen(", "freopen(", "fdopen(", "fwrite(",
        "fputs(", "fputc(", "mkstemp(", "tmpfile(", "creat(",
    ]

    /// Log APIs (closed; M2 Q24): type names, then call patterns.
    public static let logNames: [String] = ["Logger", "OSLog"]
    public static let logCalls: [String] = [
        "print(", "debugPrint(", "dump(", "NSLog(", "os_log(", "os_signpost(", "printf(", "fprintf(", "vprintf(",
        "vfprintf(", "dprintf(", "puts(", "putc(", "putchar(", "perror(", "syslog(",
    ]

    /// Imports allowed per rule.
    public static let rule1Imports: Set<String> = ["Foundation", "TendCore"]
    public static let rule2Imports: Set<String> = [
        "Foundation", "FoundationModels", "Speech", "AVFAudio", "TendCore", "TendIngestion",
    ]
    public static let rule3Imports: Set<String> = rule2Imports.union(["Security"])
    /// Rule 6 (M2 Q24): the closed `TendEval` import list, compared with the module name (`importedModule(of:)`).
    public static let rule6Imports: Set<String> = [
        "Foundation", "SwiftUI", "CryptoKit", "TendCore", "TendIngestion", "TendAI",
    ]
    /// Import kind keywords skipped before the module path (`import struct Darwin.C` is `Darwin`).
    public static let importKindKeywords: Set<String> = [
        "typealias", "struct", "class", "enum", "protocol", "let", "var", "func",
    ]

    /// Rule 3: the allowed networking subset (closed; T-23). `URLSession.AsyncBytes` is the identifier `URLSession`
    /// followed by `AsyncBytes` (which has no networking prefix); `bytes(for:delegate:)` has no networking identifier.
    public static let allowedNetworkingSubset: Set<String> = [
        "URLSession", "URLSessionConfiguration", "URLSessionTask", "URLSessionTaskDelegate",
        "URLRequest", "URL", "URLComponents", "URLResponse", "HTTPURLResponse", "URLError",
    ]

    /// Rule 3: identifier prefixes that must be in the subset (case-sensitive, whole identifier; N-1).
    public static let networkingPrefixes: [String] = ["URL", "NSURL", "HTTP", "NW", "CFHost", "CFStream", "CFNetwork"]

    /// Rule 4: the only host-like literals (bare host, or `https://` followed by one of them).
    public static let allowedHosts: [String] = [
        "api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com",
    ]

    /// Rule 4: a literal is host-like when it contains `://` or the whole literal matches this (brief, verbatim).
    public static let hostLikePattern =
        #"(?i)^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|net|org|io|ai|dev|app|co|cloud)(:\d+)?(/\S*)?$"#

    /// Rule 5 (T-27): the exact exception forms, valid only in the speech-permission file and only when enabled.
    public static let speechExceptionCallPattern =
        SourceScanner.leftBoundary + #"SFSpeechRecognizer\s*\.\s*(?:requestAuthorization|authorizationStatus)\s*\("#
    public static let speechExceptionType = "SFSpeechRecognizerAuthorizationStatus"

    // MARK: - Fixed regexes

    static func callPattern(_ call: String) -> String {
        // `write(to:` → `write\s*\(\s*to\s*:`; `print(` → `print\s*\(`.
        var name = call
        var label: String?
        if let open = call.firstIndex(of: "(") {
            name = String(call[..<open])
            let rest = call[call.index(after: open)...]
            if rest.hasSuffix(":") { label = String(rest.dropLast()) }
        }
        var pattern = SourceScanner.leftBoundary + NSRegularExpression.escapedPattern(for: name) + #"\s*\("#
        if let label { pattern += #"\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:"# }
        return pattern
    }

    /// Every fixed regex the rules use (a self-test compiles each one).
    public static var allPatterns: [String] {
        [hostLikePattern, speechExceptionCallPattern, delegateLabelPattern]
            + (writeCalls + logCalls + sessionMethodCalls).map(callPattern)
            + methodReferenceNames.map(wholeTokenPattern) + loaderPatterns + SourceScanner.allPatterns
    }

    /// A whole identifier token: not preceded or followed by a letter, digit or `_`.
    static func wholeTokenPattern(_ name: String) -> String {
        SourceScanner.leftBoundary + NSRegularExpression.escapedPattern(for: name) + SourceScanner.rightBoundary
    }

    /// The module an import statement imports: the first path component after any kind keyword (M2 Q24).
    public static func importedModule(of importTarget: String) -> String {
        let words = importTarget.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = words.first else { return importTarget }
        let path = importKindKeywords.contains(first) && words.count > 1 ? words[1] : first
        return path.split(separator: ".").first.map(String.init) ?? path
    }

    // MARK: - Scan

    /// Runs Rules 1–6 over `files`. Each file is checked by the rules of its module; Rules 4 and 5 apply to all three.
    public static func violations(in files: [ScannedFile], configuration: IngestionScanConfiguration)
        -> [RuleViolation] {
        files.flatMap { violations(in: $0, configuration: configuration) }
    }

    public static func violations(in file: ScannedFile, configuration: IngestionScanConfiguration)
        -> [RuleViolation] {
        let lexed = SourceScanner.lex(file.text)
        let facts = FileFacts(file: file, lexed: lexed, configuration: configuration)
        var result: [RuleViolation] = []
        switch file.module {
        case .tendIngestion:
            result += rule1(facts)
        case .tendAI:
            if configuration.cloudAdapterAllowlist.contains(file.path) {
                result += rule3(facts)
            } else {
                result += rule2(facts)
            }
        case .tendEval:
            result += rule6(facts)
        }
        result += rule4(facts)
        result += rule5(facts)
        return result
    }

    // MARK: - Rules

    /// Rule 1, `TendIngestion`: imports `Foundation` and `TendCore` only; none of the full AC-M1-23 closed list (no
    /// `contentsOf:` allowlist here); no networking pattern, media type, write or log API.
    /// `Locale(identifier: "en_US_POSIX")` is allowed: no AC-M1-23 pattern matches it (a positive test proves it).
    static func rule1(_ facts: FileFacts) -> [RuleViolation] {
        var result = SourceScanner.apiHits(in: facts.file.text, file: facts.file.path,
                                           allowedImports: rule1Imports, contentsOfAllowlist: [])
            .map { facts.violation(.rule1, check: "AC-M1-23 " + $0.rule, hit: $0) }
        result += facts.networkingViolations(.rule1)
        result += facts.mediaViolations(.rule1)
        result += facts.writeViolations(.rule1)
        result += facts.logViolations(.rule1)
        return result
    }

    /// Rule 2, `TendAI` outside the allowlist: closed imports; no networking pattern, no write or log API; media types
    /// only in the speech adapter files.
    static func rule2(_ facts: FileFacts) -> [RuleViolation] {
        var result = facts.importViolations(.rule2, allowed: rule2Imports)
        result += facts.networkingViolations(.rule2)
        result += facts.writeViolations(.rule2)
        result += facts.logViolations(.rule2)
        if !facts.configuration.speechAdapterFiles.contains(facts.file.path) {
            result += facts.mediaViolations(.rule2)
        }
        return result
    }

    /// Rule 3, `TendAI` allowlisted cloud-adapter files: Rule 2 imports plus `Security`; every networking-pattern hit
    /// and every identifier with a networking prefix is in the allowed subset; no media type, write or log API.
    static func rule3(_ facts: FileFacts) -> [RuleViolation] {
        var result = facts.importViolations(.rule3, allowed: rule3Imports)
        // Networking-pattern hits: a name hit is allowed only when the whole identifier is in the subset. Every other
        // hit (`URL(string:`, `contentsOf:`, `Host(`, `Stream(`, `Host.current`, networking imports) is never in it.
        // M2 Q24: the only session-method call allowed is `bytes(for:` with `delegate:` in its argument list.
        let names = Set(networkingNames)
        for hit in facts.networkingHits where !facts.isStreamingReadWithDelegate(hit) {
            let isSubsetIdentifier = names.contains(hit.rule) && allowedNetworkingSubset.contains(hit.excerpt)
            if !isSubsetIdentifier {
                result.append(facts.violation(.rule3, check: "networking outside subset: " + hit.rule, hit: hit))
            }
        }
        for identifier in facts.identifiers
        where networkingPrefixes.contains(where: { identifier.text.hasPrefix($0) })
            && !allowedNetworkingSubset.contains(identifier.text) {
            result.append(RuleViolation(rule: .rule3, check: "networking prefix outside subset",
                                        file: facts.file.path, line: identifier.line, excerpt: identifier.text))
        }
        result += facts.mediaViolations(.rule3)
        result += facts.writeViolations(.rule3)
        result += facts.logViolations(.rule3)
        return result
    }

    /// Rule 4, all three modules: every host-like literal is an allowed host (bare) or `https://` + an allowed host.
    /// Bare hosts may appear only in the payload builder's provider table, one named `TendIngestion` file (review
    /// R1-F6); `https://` hosts only in the allowlisted cloud-adapter files.
    static func rule4(_ facts: FileFacts) -> [RuleViolation] {
        var result: [RuleViolation] = []
        for literal in facts.lexed.literals where isHostLike(literal.text) {
            let text = literal.text
            let check: String?
            if allowedHosts.contains(text) {
                if facts.file.module != .tendIngestion {
                    check = "bare host outside TendIngestion"
                } else {
                    check = facts.file.path == facts.configuration.providerTableFile
                        ? nil : "bare host outside the provider table"
                }
            } else if allowedHosts.contains(where: { "https://" + $0 == text }) {
                check = facts.isAllowlisted ? nil : "https:// host outside the cloud-adapter allowlist"
            } else {
                check = "host-like literal not allowed"
            }
            if let check {
                result.append(RuleViolation(rule: .rule4, check: check, file: facts.file.path, line: literal.line,
                                            excerpt: "\"\(text)\""))
            }
        }
        return result
    }

    /// Rule 5, all three modules: no `SFSpeech*` API, except (T-27, only when enabled, only in the speech-permission
    /// file) exactly `SFSpeechRecognizer.requestAuthorization(`, `SFSpeechRecognizer.authorizationStatus(` and the
    /// `SFSpeechRecognizerAuthorizationStatus` type.
    static func rule5(_ facts: FileFacts) -> [RuleViolation] {
        facts.networkingHits
            .filter { $0.rule == "SFSpeech" && !facts.isSpeechException($0) }
            .map { facts.violation(.rule5, check: "SFSpeech* API", hit: $0) }
    }

    /// Rule 6, `TendEval`: the closed import list (M2 Q24); no networking pattern, including `contentsOf:`, except the
    /// M2 Q23 read in the fixtures loader; in the loader file, the Q23 checks; write APIs only in the results writer;
    /// no log API.
    static func rule6(_ facts: FileFacts) -> [RuleViolation] {
        var result = SourceScanner.imports(inCode: facts.lexed.code)
            .filter { !rule6Imports.contains(importedModule(of: $0.target)) }
            .map { RuleViolation(rule: .rule6, check: "import", file: facts.file.path, line: $0.line,
                                 excerpt: "import \($0.target)") }
        var allowedReads: Set<Int> = []
        if facts.file.path == facts.configuration.fixturesLoaderFile {
            let loader = FixturesLoaderRule(facts: facts).run()
            allowedReads = loader.allowedContentsOfOffsets
            result += loader.violations
        }
        result += facts.networkingViolations(.rule6, allowedContentsOfOffsets: allowedReads)
        if facts.file.path != facts.configuration.resultsWriterFile {
            result += facts.writeViolations(.rule6)
        }
        result += facts.logViolations(.rule6)
        return result
    }

    /// Rule 4 host-like test (T-30): contains `://`, or the whole literal matches `hostLikePattern`.
    public static func isHostLike(_ literal: String) -> Bool {
        literal.contains("://") || !SourceScanner.matches(of: hostLikePattern, in: literal).isEmpty
    }
}

/// Facts about one lexed file, computed once and shared by the rules.
struct FileFacts {
    let file: ScannedFile
    let lexed: LexedSource
    let configuration: IngestionScanConfiguration
    let identifiers: [SourceScanner.RegexMatch]
    /// Networking-pattern hits (names, call names, `Host.current`, `URL(string:`, `contentsOf:`, networking imports),
    /// before any exception. The Rule 5 exception is removed from these in `networkingViolations`.
    let networkingHits: [ScanHit]
    let speechExceptionOffsets: Set<Int>
    /// Code with backticks removed, for the call-pattern rule (M2 Q24). Offsets of call hits refer to this text.
    let callCode: String
    /// Offsets (in `callCode`) of `bytes(for:` calls whose argument list contains `delegate:` (Rule 3, M2 Q24).
    let streamingReadOffsets: Set<Int>

    init(file: ScannedFile, lexed: LexedSource, configuration: IngestionScanConfiguration) {
        self.file = file
        self.lexed = lexed
        self.configuration = configuration
        let code = lexed.code
        identifiers = SourceScanner.identifiers(inCode: code)

        var hits = SourceScanner.networkingHits(in: code, file: file.path,
                                                names: IngestionSourceRules.networkingNames)
        for pattern in SourceScanner.identifierPatterns where pattern.name == "URL(string:" {
            for match in SourceScanner.matches(of: pattern.regex, in: code) {
                hits.append(ScanHit(file: file.path, line: match.line, rule: pattern.name, excerpt: match.text,
                                    offset: match.startOffset))
            }
        }
        // `contentsOf:` URL loading (AC-M1-23, Q23): every label, except directly inside `append(` / `insert(`.
        let scalars = Array(code.unicodeScalars)
        for match in SourceScanner.matches(of: SourceScanner.contentsOfPattern, in: code) {
            let call = SourceScanner.enclosingCallName(in: scalars, before: match.startOffset)
            if let call, SourceScanner.contentsOfCallExemptions.contains(call) { continue }
            hits.append(ScanHit(file: file.path, line: match.line, rule: SourceScanner.contentsOfRule,
                                excerpt: "\(call ?? "?")(\(match.text)", offset: match.startOffset))
        }
        // M2 Q24: session-method calls (call-pattern rule) and task-creating method references (whole tokens).
        callCode = code.replacingOccurrences(of: "`", with: "")
        let callScalars = Array(callCode.unicodeScalars)
        var streaming: Set<Int> = []
        for call in IngestionSourceRules.sessionMethodCalls {
            for match in SourceScanner.matches(of: IngestionSourceRules.callPattern(call), in: callCode) {
                hits.append(ScanHit(file: file.path, line: match.line, rule: call, excerpt: match.text,
                                    offset: match.startOffset))
                if call == IngestionSourceRules.streamingReadCall,
                   let arguments = Self.argumentList(in: callScalars, from: match.startOffset),
                   !SourceScanner.matches(of: IngestionSourceRules.delegateLabelPattern, in: arguments).isEmpty {
                    streaming.insert(match.startOffset)
                }
            }
        }
        streamingReadOffsets = streaming
        for name in IngestionSourceRules.methodReferenceNames {
            for match in SourceScanner.matches(of: IngestionSourceRules.wholeTokenPattern(name), in: callCode) {
                hits.append(ScanHit(file: file.path, line: match.line, rule: name, excerpt: match.text,
                                    offset: match.startOffset))
            }
        }
        for statement in SourceScanner.imports(inCode: code)
        where IngestionSourceRules.networkingImports
            .contains(IngestionSourceRules.importedModule(of: statement.target)) {
            hits.append(ScanHit(file: file.path, line: statement.line, rule: "import",
                                excerpt: "import \(statement.target)", offset: statement.offset))
        }
        networkingHits = hits

        var offsets: Set<Int> = []
        if configuration.speechPermissionExceptionEnabled && file.path == configuration.speechPermissionFile {
            for match in SourceScanner.matches(of: IngestionSourceRules.speechExceptionCallPattern, in: code) {
                offsets.insert(match.startOffset)
            }
            for identifier in identifiers where identifier.text == IngestionSourceRules.speechExceptionType {
                offsets.insert(identifier.startOffset)
            }
        }
        speechExceptionOffsets = offsets
    }

    /// The top level of the balanced argument list of the call whose name starts at `start`: the text between its
    /// `(` and the matching `)`, with every nested bracketed part blanked, so `bytes(for: make(delegate: d))` does not
    /// count as passing `delegate:`. `nil` when there is no `(`.
    static func argumentList(in scalars: [Unicode.Scalar], from start: Int) -> String? {
        guard var index = scalars[start...].firstIndex(of: "(") else { return nil }
        var depth = 0
        var text = String.UnicodeScalarView()
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "(" || scalar == "[" || scalar == "{" { depth += 1 }
            text.append(depth == 1 ? scalar : " ")
            if scalar == ")" || scalar == "]" || scalar == "}" { depth -= 1 }
            if depth == 0 { break }
            index += 1
        }
        return String(text)
    }

    /// Rule 3 (M2 Q24): this hit is the allowed `bytes(for:` call with `delegate:`.
    func isStreamingReadWithDelegate(_ hit: ScanHit) -> Bool {
        guard hit.rule == IngestionSourceRules.streamingReadCall, let offset = hit.offset else { return false }
        return streamingReadOffsets.contains(offset)
    }

    var isAllowlisted: Bool {
        file.module == .tendAI && configuration.cloudAdapterAllowlist.contains(file.path)
    }

    func isSpeechException(_ hit: ScanHit) -> Bool {
        guard let offset = hit.offset else { return false }
        return speechExceptionOffsets.contains(offset)
    }

    func violation(_ rule: IngestionScanRule, check: String, hit: ScanHit) -> RuleViolation {
        RuleViolation(rule: rule, check: check, file: file.path, line: hit.line, excerpt: hit.excerpt)
    }

    func importViolations(_ rule: IngestionScanRule, allowed: Set<String>) -> [RuleViolation] {
        SourceScanner.imports(inCode: lexed.code)
            .filter { !allowed.contains($0.target) }
            .map { RuleViolation(rule: rule, check: "import", file: file.path, line: $0.line,
                                 excerpt: "import \($0.target)") }
    }

    /// `allowedContentsOfOffsets`: the M2 Q23 loader reads (Rule 6, the loader file only); empty everywhere else.
    func networkingViolations(_ rule: IngestionScanRule, allowedContentsOfOffsets: Set<Int> = [])
        -> [RuleViolation] {
        networkingHits
            .filter { !isSpeechException($0) }
            .filter { hit in
                !(hit.rule == SourceScanner.contentsOfRule
                  && hit.offset.map { allowedContentsOfOffsets.contains($0) } == true)
            }
            .map { violation(rule, check: "networking " + $0.rule, hit: $0) }
    }

    func nameViolations(_ rule: IngestionScanRule, kind: String, names: [String]) -> [RuleViolation] {
        var result: [RuleViolation] = []
        for identifier in identifiers {
            for name in names where identifier.text.contains(name) {
                result.append(RuleViolation(rule: rule, check: "\(kind) \(name)", file: file.path,
                                            line: identifier.line, excerpt: identifier.text))
            }
        }
        return result
    }

    func callViolations(_ rule: IngestionScanRule, kind: String, calls: [String]) -> [RuleViolation] {
        var result: [RuleViolation] = []
        for call in calls {
            for match in SourceScanner.matches(of: IngestionSourceRules.callPattern(call), in: callCode) {
                result.append(RuleViolation(rule: rule, check: "\(kind) \(call)", file: file.path, line: match.line,
                                            excerpt: match.text))
            }
        }
        return result
    }

    func mediaViolations(_ rule: IngestionScanRule) -> [RuleViolation] {
        nameViolations(rule, kind: "media type", names: IngestionSourceRules.mediaTypes)
    }

    func writeViolations(_ rule: IngestionScanRule) -> [RuleViolation] {
        nameViolations(rule, kind: "write API", names: IngestionSourceRules.writeNames)
            + callViolations(rule, kind: "write API", calls: IngestionSourceRules.writeCalls)
    }

    func logViolations(_ rule: IngestionScanRule) -> [RuleViolation] {
        nameViolations(rule, kind: "log API", names: IngestionSourceRules.logNames)
            + callViolations(rule, kind: "log API", calls: IngestionSourceRules.logCalls)
    }
}
