// AC-M2-12, last clause: "model instructions (on-device and cloud) and every outcome and reason name contain no banned
// token". UX-3. Plan WI-M2-04 (closes the WI-M2-01 follow-up "the AC-M1-02 vocabulary scan is not applied to
// `TendIngestion/Sources`").
//
// The scan is the AC-M1-02 vocabulary scan (`SourceScanner.vocabularyHits`: identifiers split at camelCase, digits and
// `_`, and every string literal; comments removed), run over every `.swift` file of the three AC-M2-09 module roots
// (`ScanScope.roots`). That is stricter than the clause: it covers every identifier and literal, so every outcome and
// reason case name and every instruction string written in these modules is covered as it is added.
//
// One named exemption, `BannedTokenListExemption`, and nothing else: the string literals of the single declaration
// `public static let all: [String] = [ … ]` in `Text/BannedTokens.swift`, because the guard needs the list. See the type
// for the exact conditions. It is fail-closed: if the anchor is missing or appears twice, nothing is exempted.

import Foundation
import Testing
import TendSourceScan
@testable import TendIngestion

/// The one exemption from the calm-vocabulary scan (dev-notes WI-M2-04, decision E1).
///
/// A hit is exempted only when **all** of these hold:
/// 1. the file path is exactly `file`;
/// 2. the lexed code of that file contains `anchor` exactly once (otherwise nothing is exempted);
/// 3. the hit's line lies between the anchor's line and the first line after it whose code holds the closing `]`;
/// 4. the hit comes from a string literal whose **whole** text is the banned token (`"late"`, not `"late fee"`);
/// 5. each banned token is exempted at most once (a repeated entry is a hit).
/// Identifier hits on those lines, any other literal in the file, and the same declaration in any other file are hits.
enum BannedTokenListExemption {
    static let file = "Packages/TendIngestion/Sources/TendIngestion/Text/BannedTokens.swift"
    static let anchor = "public static let all: [String] = ["

    struct Result {
        var kept: [ScanHit]
        var exempted: [ScanHit]
    }

    static func apply(to hits: [ScanHit], path: String, source: String) -> Result {
        guard path == file, let span = declarationLines(in: source) else {
            return Result(kept: hits, exempted: [])
        }
        var used: Set<String> = []
        var result = Result(kept: [], exempted: [])
        for hit in hits {
            let token = String(hit.rule.dropFirst("token:".count))
            if hit.rule.hasPrefix("token:"), span.contains(hit.line), hit.excerpt == "\"\(token)\"",
               !used.contains(token) {
                used.insert(token)
                result.exempted.append(hit)
            } else {
                result.kept.append(hit)
            }
        }
        return result
    }

    /// The 1-based line span of the declaration, or nil when the anchor is not found exactly once (fail-closed).
    static func declarationLines(in source: String) -> ClosedRange<Int>? {
        let lines = SourceScanner.lex(source).code.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let anchorLines = lines.indices.filter { lines[$0].contains(anchor) }
        guard anchorLines.count == 1, let start = anchorLines.first else { return nil }
        let afterOpening = lines[start].components(separatedBy: anchor).dropFirst().joined()
        if afterOpening.contains("]") { return (start + 1)...(start + 1) }
        guard let end = lines.indices.first(where: { $0 > start && lines[$0].contains("]") }) else { return nil }
        return (start + 1)...(end + 1)
    }
}

@Suite("AC-M2-12 calm vocabulary scan of the module Sources (UX-3)")
struct CalmVocabularyScanTests {

    @Test("AC-M2-12: no banned token in any identifier or string literal of the module Sources, except the one list")
    func scanSources() throws {
        let loaded = try IngestionSourceScanTests.load()
        var kept: [ScanHit] = []
        var exempted: [ScanHit] = []
        var fileCount = 0
        for entry in loaded {
            print("AC-M2-12 vocabulary scan: \(entry.root.module.rawValue) \(entry.root.path): "
                  + (entry.exists ? "\(entry.files.count) files" : "not present"))
            for file in entry.files {
                fileCount += 1
                let hits = SourceScanner.vocabularyHits(in: file.text, file: file.path)
                let result = BannedTokenListExemption.apply(to: hits, path: file.path, source: file.text)
                kept += result.kept
                exempted += result.exempted
            }
        }
        print("AC-M2-12 vocabulary scan: \(fileCount) files, \(exempted.count) exempted (the list), "
              + "\(kept.count) violations")
        for hit in kept { print("AC-M2-12 violation: \(hit)") }
        #expect(fileCount > 0)
        #expect(kept.isEmpty)
        // The exemption covers exactly the nine list entries, once each, and they are the brief's list.
        #expect(exempted.map { String($0.rule.dropFirst("token:".count)) }.sorted() == BannedTokens.all.sorted())
        #expect(BannedTokens.all == SourceScanner.bannedTokens)
    }

    // MARK: Negative tests: the exemption is narrow

    static let declaration = """
        public enum BannedTokens {
            public static let all: [String] = [
                "overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt", "streak",
            ]
        }
        """

    static func kept(_ source: String, path: String = BannedTokenListExemption.file) -> [ScanHit] {
        let hits = SourceScanner.vocabularyHits(in: source, file: path)
        return BannedTokenListExemption.apply(to: hits, path: path, source: source).kept
    }

    @Test("AC-M2-12 exemption: the declaration alone gives 0 hits, and 9 are exempted")
    func declarationExempted() {
        let hits = SourceScanner.vocabularyHits(in: Self.declaration, file: BannedTokenListExemption.file)
        let result = BannedTokenListExemption.apply(to: hits, path: BannedTokenListExemption.file,
                                                    source: Self.declaration)
        #expect(hits.count == 9)
        #expect(result.exempted.count == 9)
        #expect(result.kept.isEmpty)
    }

    @Test("AC-M2-12 exemption: the same declaration in any other file is flagged", arguments: [
        "Packages/TendIngestion/Sources/TendIngestion/Text/Other.swift",
        "Packages/TendIngestion/Sources/TendIngestion/BannedTokens.swift",
        "Packages/TendAI/Sources/TendAI/Text/BannedTokens.swift",
        "Apps/TendEval/Sources/BannedTokens.swift",
    ])
    func otherFileFlagged(path: String) {
        #expect(Self.kept(Self.declaration, path: path).count == 9)
    }

    @Test("AC-M2-12 exemption: anything else in the list file is flagged", arguments: [
        // (planted source, expected hits kept)
        (CalmVocabularyScanTests.declaration + "\nlet note = \"late\"", 1),                                   // a literal outside the span
        (CalmVocabularyScanTests.declaration + "\nfunc isLate() -> Bool { false }", 1),                       // an identifier outside
        (CalmVocabularyScanTests.declaration + "\nenum Reason { case missedWindow }", 1),                     // an outcome-style case name
        (CalmVocabularyScanTests.declaration + "\nlet instructions = \"Never say overdue.\"", 1),             // an instruction string
        (CalmVocabularyScanTests.declaration.replacingOccurrences(of: "public static let all: [String] = [",
                                          with: "public static let all: [String] = [ \"late fee\","), 1),
        (CalmVocabularyScanTests.declaration.replacingOccurrences(of: "\"streak\",", with: "\"streak\", \"late\","), 1),   // repeated entry
        (CalmVocabularyScanTests.declaration.replacingOccurrences(of: "public static let all: [String] = [",
                                          with: "public static let all: [String] = [ lateCount,"), 1),  // identifier
    ])
    func restOfFileFlagged(source: String, expected: Int) {
        #expect(Self.kept(source).count == expected, "\(Self.kept(source))")
    }

    @Test("AC-M2-12 exemption: the hit that is kept is the planted one, not a list entry")
    func keptHitIsThePlantedOne() {
        // A longer literal inside the span, placed before the real "late" entry: only "late fee" is kept.
        let longer = Self.declaration.replacingOccurrences(of: "public static let all: [String] = [",
                                                           with: "public static let all: [String] = [ \"late fee\",")
        #expect(Self.kept(longer).map(\.excerpt) == ["\"late fee\""])
        // A token missing from the list, written outside the span, is never exempted.
        let outside = Self.declaration.replacingOccurrences(of: " \"late\",", with: "")
            + "\nlet note = \"late\""
        #expect(Self.kept(outside).map(\.line) == [6])
        // A literal before the declaration is not exempted either, even if the list holds the same token.
        let before = "let first = \"debt\"\n" + Self.declaration
        #expect(Self.kept(before).map(\.line) == [1])
    }

    @Test("AC-M2-12 exemption: fail-closed when the anchor is missing or appears twice")
    func failClosed() {
        let renamed = Self.declaration.replacingOccurrences(of: "static let all:", with: "static let words:")
        #expect(Self.kept(renamed).count == 9)
        let twice = Self.declaration + "\n" + Self.declaration.replacingOccurrences(of: "enum BannedTokens",
                                                                                   with: "enum Copy")
        #expect(Self.kept(twice).count == 18)
        // An anchor that appears only inside a comment is not code, so nothing is exempted either.
        let commented = "// public static let all: [String] = [\nlet x = [\"late\"]"
        #expect(Self.kept(commented).count == 1)
    }

    @Test("AC-M2-12 exemption: a single-line declaration is spanned to its own line only")
    func singleLineDeclaration() {
        let source = "public static let all: [String] = [\"late\"]\nlet y = \"late\""
        #expect(Self.kept(source).count == 1)
    }
}
