// Source scans over every `.swift` file in `Packages/TendCore/Sources/` (AC-M1-02, AC-M1-23).
// These run on every PR, so later work items (WI-M1-02…04) must keep `Sources/` clean too.

import Foundation
import Testing

@Suite("Source scans of TendCore/Sources (AC-M1-02, AC-M1-23)")
struct SourceScanTests {

    static func loadSources() throws -> [(name: String, text: String)] {
        let directory = SourceScanner.sourcesDirectory()
        let files = SourceScanner.swiftFiles(under: directory)
        return try files.map { url in
            let relative = url.path.replacingOccurrences(of: directory.deletingLastPathComponent().path + "/",
                                                         with: "")
            return (relative, try String(contentsOf: url, encoding: .utf8))
        }
    }

    @Test("AC-M1-02: no banned zero-guilt token in any identifier or string literal of TendCore/Sources")
    func noBannedVocabulary() throws {
        let sources = try Self.loadSources()
        print("AC-M1-02 scan: \(sources.count) files scanned under Packages/TendCore/Sources")
        for source in sources { print("AC-M1-02 scanned: \(source.name)") }
        #expect(sources.count > 0, "no source files found: the scan would pass vacuously")

        let hits = sources.flatMap { SourceScanner.vocabularyHits(in: $0.text, file: $0.name) }
        print("AC-M1-02 scan: \(hits.count) hits")
        for hit in hits { print("AC-M1-02 hit: \(hit)") }
        #expect(hits.isEmpty)
    }

    @Test("AC-M1-23: only `import Foundation`, no ambient time, randomness or networking API in TendCore/Sources")
    func foundationOnlyAndDeterministic() throws {
        let sources = try Self.loadSources()
        print("AC-M1-23 scan: \(sources.count) files scanned under Packages/TendCore/Sources")
        #expect(sources.count > 0, "no source files found: the scan would pass vacuously")

        let importCount = sources.reduce(0) { count, source in
            count + SourceScanner.matches(of: #"(?<![\p{L}\p{N}_.`])import\s+"#,
                                          in: SourceScanner.lex(source.text).code).count
        }
        print("AC-M1-23 scan: \(importCount) import statements found")

        let hits = sources.flatMap { SourceScanner.apiHits(in: $0.text, file: $0.name) }
        print("AC-M1-23 scan: \(hits.count) hits")
        for hit in hits { print("AC-M1-23 hit: \(hit)") }
        #expect(hits.isEmpty)
    }
}
