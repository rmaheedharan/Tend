// AC-M2-09: the source scan over the `Sources` of `TendIngestion`, `TendAI` and `TendEval`, run from the
// `TendIngestion` test target over the repository paths (brief Environment: Linux). Rules 1–6, comments removed.
// P-1, P-2, P-3, P-4. The planted-hit and near-miss tests for the rule engine are in
// `Packages/TendSourceScan/Tests/TendSourceScanTests/IngestionSourceRulesTests.swift`; this file proves the real scan
// ran (file counts per module > 0 for every required root) and found nothing.

import Foundation
import Testing
import TendSourceScan

@Suite("AC-M2-09 source scan of TendIngestion, TendAI and TendEval Sources")
struct IngestionSourceScanTests {

    /// The repository root, located from this file's path (works on Linux and macOS).
    static func repositoryRoot() -> URL {
        let thisFile: String = #filePath
        return URL(fileURLWithPath: thisFile)
            .deletingLastPathComponent()  // TendIngestionTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // TendIngestion
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
    }

    struct LoadedRoot {
        var root: ScanScope.Root
        var exists: Bool
        var files: [ScannedFile]
    }

    static func load() throws -> [LoadedRoot] {
        let repository = repositoryRoot()
        return try ScanScope.roots.map { root in
            let directory = repository.appendingPathComponent(root.path, isDirectory: true)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
            let urls = exists ? SourceScanner.swiftFiles(under: directory) : []
            let files = try urls.map { url in
                let relative = String(url.standardizedFileURL.path.dropFirst(repository.standardizedFileURL.path.count + 1))
                return ScannedFile(module: root.module, path: relative, text: try String(contentsOf: url, encoding: .utf8))
            }
            return LoadedRoot(root: root, exists: exists, files: files)
        }
    }

    @Test("AC-M2-09: Rules 1–6 hold over every .swift file in the three module Sources (file counts logged per module)")
    func scanRepository() throws {
        let loaded = try Self.load()
        print("AC-M2-09 scan: repository root \(Self.repositoryRoot().path)")
        print("AC-M2-09 scan: Rule 5 T-27 exception \(ScanScope.speechPermissionExceptionEnabled ? "ON" : "OFF")")
        for entry in loaded {
            let status = entry.exists ? "\(entry.files.count) files scanned" : "not present"
            print("AC-M2-09 scan: \(entry.root.module.rawValue) (\(entry.root.state.rawValue)) \(entry.root.path): \(status)")
            for file in entry.files { print("AC-M2-09 scanned: \(file.path)") }
            if entry.root.state == .required {
                #expect(entry.files.count > 0,
                        "required root \(entry.root.path) has 0 files: the scan would pass vacuously")
            }
        }

        let files = loaded.flatMap(\.files)
        let violations = IngestionSourceRules.violations(in: files, configuration: ScanScope.configuration)
        print("AC-M2-09 scan: \(files.count) files in total, \(violations.count) violations")
        for violation in violations { print("AC-M2-09 violation: \(violation)") }
        #expect(violations.isEmpty)
    }

    @Test("AC-M2-09: the scope table names the three modules, and TendIngestion is required")
    func scopeTable() {
        #expect(ScanScope.roots.map(\.module) == ScannedModule.allCases)
        #expect(ScanScope.roots.first { $0.module == .tendIngestion }?.state == .required)
        #expect(ScanScope.configuration.cloudAdapterAllowlist.count == 3)
        #expect(ScanScope.configuration.speechPermissionExceptionEnabled == false)  // until WI-M2-M1 (T-27)
    }

    @Test("AC-M2-09 negative (driver): one planted hit per rule, run through the same configuration, is caught")
    func plantedThroughDriverConfiguration() {
        let planted: [(ScannedFile, IngestionScanRule)] = [
            (ScannedFile(module: .tendIngestion, path: "Packages/TendIngestion/Sources/TendIngestion/X.swift",
                         text: "import Network"), .rule1),
            (ScannedFile(module: .tendAI, path: "Packages/TendAI/Sources/TendAI/X.swift",
                         text: "let s = URLSession.shared"), .rule2),
            (ScannedFile(module: .tendAI, path: "Packages/TendAI/Sources/TendAI/Cloud/CloudHTTPTransport.swift",
                         text: "let t: URLSessionWebSocketTask? = nil"), .rule3),
            (ScannedFile(module: .tendIngestion, path: "Packages/TendIngestion/Sources/TendIngestion/X.swift",
                         text: "let h = \"api.example.com\""), .rule4),
            (ScannedFile(module: .tendAI, path: "Packages/TendAI/Sources/TendAI/Speech/SpeechPermission.swift",
                         text: "let r = SFSpeechRecognizer(locale: l)"), .rule5),
            (ScannedFile(module: .tendEval, path: "Apps/TendEval/Sources/Run/X.swift",
                         text: "print(x)"), .rule6),
        ]
        for (file, rule) in planted {
            let found = IngestionSourceRules.violations(in: [file], configuration: ScanScope.configuration)
            #expect(found.contains { $0.rule == rule }, "\(rule) not caught in \(file.path): \(found)")
        }
    }
}
