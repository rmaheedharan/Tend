// AC-M2-09, PO decision M2 Q24: the stricter lists, the exact call-pattern rule, method references, Rule 3 session
// methods, and the closed Rule 6 import list. Every plant and positive test the brief names for Q24 is here, written by
// hand from the brief text. M2 Q23 (the fixtures-loader exception) was not built in WI-M2-01 (plan WI-M2-01); it is
// built in the scanner follow-up `m2/scanner-loader-exception` and tested in `Q23LoaderTests`. P-2, P-3, P-4.

import Testing
import TendSourceScan

extension PlanPaths {
    /// Plan "Named files" (M2 Q23): the only file with the fixtures-loader exception.
    static let fixturesLoader = "Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift"
}

@Suite("AC-M2-09 M2 Q24: stricter lists, call patterns, session methods, Rule 6 imports")
struct Q24RulesTests {

    /// Brief: "One plant for each pattern added by M2 Q24 is caught on its own, in TendIngestion, as a parameterised
    /// test": every session-method call; `write(toFile:`, `AppStorage`, `SceneStorage`, `archiveRootObject(`; each C
    /// call on the write and log lists. (code, expected check)
    static let q24Plants: [(String, String)] = [
        ("let t = s.dataTask(with: r)", "networking dataTask("),
        ("let t = s.uploadTask(with: r, from: d)", "networking uploadTask("),
        ("let t = s.downloadTask(with: r)", "networking downloadTask("),
        ("let t = s.streamTask(withHostName: h, port: 1)", "networking streamTask("),
        ("let t = s.webSocketTask(with: r)", "networking webSocketTask("),
        ("let x = try await s.data(for: q)", "networking data(for:"),
        ("let x = try await s.data(from: u)", "networking data(from:"),
        ("let x = try await s.bytes(for: q)", "networking bytes(for:"),
        ("let x = try await s.bytes(from: u)", "networking bytes(from:"),
        ("let x = try await s.upload(for: q, from: b)", "networking upload(for:"),
        ("let x = try await s.upload(from: b)", "networking upload(from:"),
        ("let x = try await s.download(for: q)", "networking download(for:"),
        ("let x = try await s.download(from: u)", "networking download(from:"),
        ("let x = try await s.download(resumeFrom: d)", "networking download(resumeFrom:"),
        ("try s.write(toFile: p, atomically: true, encoding: .utf8)", "write API write(toFile:"),
        ("@AppStorage(\"k\") var key = \"\"", "write API AppStorage"),
        ("@SceneStorage(\"k\") var tab = 0", "write API SceneStorage"),
        ("NSKeyedArchiver.archiveRootObject(x, toFile: p)", "write API archiveRootObject("),
        ("let f = fopen(p, m)", "write API fopen("),
        ("let f = freopen(p, m, stdout)", "write API freopen("),
        ("let f = fdopen(fd, m)", "write API fdopen("),
        ("fwrite(b, 1, n, f)", "write API fwrite("),
        ("fputs(s, f)", "write API fputs("),
        ("fputc(c, f)", "write API fputc("),
        ("let fd = mkstemp(&t)", "write API mkstemp("),
        ("let f = tmpfile()", "write API tmpfile("),
        ("let fd = creat(p, 0o600)", "write API creat("),
        ("printf(f, s)", "log API printf("),
        ("fprintf(h, f, s)", "log API fprintf("),
        ("vprintf(f, a)", "log API vprintf("),
        ("vfprintf(h, f, a)", "log API vfprintf("),
        ("dprintf(2, f, s)", "log API dprintf("),
        ("puts(s)", "log API puts("),
        ("putc(c, h)", "log API putc("),
        ("putchar(c)", "log API putchar("),
        ("perror(s)", "log API perror("),
        ("syslog(p, f, s)", "log API syslog("),
    ]

    @Test("AC-M2-09 M2 Q24 list plants: each pattern added by Q24 is caught on its own in TendIngestion",
          arguments: q24Plants.indices)
    func q24PlantCaughtInIngestion(index: Int) {
        let (code, check) = Self.q24Plants[index]
        let found = scan(.tendIngestion, PlanPaths.ingestionFile, code)
        #expect(found.contains { $0.rule == .rule1 && $0.check == check }, "`\(code)`: \(found)")
    }

    @Test("AC-M2-09 M2 Q24 coverage: the plants cover every Q24 session call, write and log addition")
    func q24PlantsCoverAdditions() {
        let checks = Set(Self.q24Plants.map(\.1))
        let added = ["write(toFile:", "AppStorage", "SceneStorage", "archiveRootObject(", "fopen(", "freopen(",
                     "fdopen(", "fwrite(", "fputs(", "fputc(", "mkstemp(", "tmpfile(", "creat("].map { "write API " + $0 }
            + ["printf(", "fprintf(", "vprintf(", "vfprintf(", "dprintf(", "puts(", "putc(", "putchar(", "perror(",
               "syslog("].map { "log API " + $0 }
            + IngestionSourceRules.sessionMethodCalls.map { "networking " + $0 }
        #expect(Set(added) == checks)
    }

    // MARK: "Also caught" (brief AC-M2-09, M2 Q24)

    @Test("AC-M2-09 M2 Q24: import Darwin and fwrite( in TendEval are each caught on their own")
    func darwinAndFwriteInEval() {
        #expect(scan(.tendEval, PlanPaths.evalFile, "import Darwin").contains { $0.rule == .rule6 && $0.check == "import" })
        #expect(scan(.tendEval, PlanPaths.evalFile, "fwrite(b, 1, n, f)")
            .contains { $0.rule == .rule6 && $0.check == "write API fwrite(" })
    }

    @Test("AC-M2-09 M2 Q24: @AppStorage(\"k\") var key = \"\" in TendEval is caught")
    func appStorageInEval() {
        #expect(scan(.tendEval, PlanPaths.evalFile, "@AppStorage(\"k\") var key = \"\"")
            .contains { $0.rule == .rule6 && $0.check == "write API AppStorage" })
    }

    @Test("AC-M2-09 M2 Q24 Rule 3: inferred task types, bytes(for: without delegate:, and a method reference are caught in an allowlisted file",
          arguments: [
            "let t = s.uploadTask(with: r, from: d)",
            "let w = s.webSocketTask(with: r)",
            "session.bytes(for: request)",
            "let f = s.dataTask",
            "let (b, r) = try await session.bytes(for: request, delegatee: x)",   // not the `delegate:` label
            "let (b, r) = try await session.bytes(for: make(delegate: d))",        // `delegate:` of an inner call
          ])
    func rule3SessionMethodsCaught(code: String) {
        for path in [PlanPaths.transport, PlanPaths.failureMapping, PlanPaths.keychain] {
            #expect(scan(.tendAI, path, code).contains { $0.rule == .rule3 }, "`\(code)` in \(path)")
        }
    }

    @Test("AC-M2-09 M2 Q24 Rule 3 positive: exactly the brief's streaming read with delegate: passes in an allowlisted file")
    func rule3StreamingReadPasses() {
        let code = "let (stream, response) = try await session.bytes(for: request, delegate: redirectRefuser)"
        #expect(scan(.tendAI, PlanPaths.transport, code).isEmpty)
        // The same call is still a networking hit everywhere else (Rules 1, 2 and 6 allow no networking pattern).
        #expect(scan(.tendAI, PlanPaths.aiFile, code).contains { $0.rule == .rule2 })
        #expect(scan(.tendIngestion, PlanPaths.ingestionFile, code).contains { $0.rule == .rule1 })
        #expect(scan(.tendEval, PlanPaths.evalFile, code).contains { $0.rule == .rule6 })
    }

    @Test("AC-M2-09 M2 Q24: Data(contentsOf: u) is caught outside the allowlist, in an allowlisted file and in TendEval")
    func contentsOfCaught() {
        let code = "let d = try Data(contentsOf: u)"
        #expect(scan(.tendAI, PlanPaths.aiFile, code).contains { $0.rule == .rule2 && $0.check.contains("contentsOf:") })
        #expect(scan(.tendAI, PlanPaths.transport, code).contains { $0.rule == .rule3 && $0.check.contains("contentsOf:") })
        #expect(scan(.tendEval, PlanPaths.evalFile, code).contains { $0.rule == .rule6 && $0.check.contains("contentsOf:") })
    }

    @Test("AC-M2-09 M2 Q23 (replaces the WI-M2-01 strict-until-Q23 test): the brief's Q23 positive form passes only in the fixtures-loader file; String(contentsOf: is still caught there")
    func loaderFileExceptionIsNarrow() {
        let q23Positive = """
            guard let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") else { throw LoaderError.missing }; return try Data(contentsOf: u)
            """
        #expect(scan(.tendEval, PlanPaths.fixturesLoader, q23Positive).isEmpty)
        #expect(scan(.tendEval, PlanPaths.evalFile, q23Positive)
            .contains { $0.rule == .rule6 && $0.check.contains("contentsOf:") })
        #expect(scan(.tendEval, PlanPaths.fixturesLoader, "let s = try String(contentsOf: u)")
            .contains { $0.rule == .rule6 })
    }

    // MARK: Rule 6 imports (M2 Q24)

    @Test("AC-M2-09 M2 Q24 Rule 6: every import outside the closed list is caught, in every import form", arguments: [
        "import Darwin", "import Glibc", "import FoundationNetworking", "import Network", "import CFNetwork",
        "import os", "import AVFAudio", "import UniformTypeIdentifiers", "import Alamofire", "import Combine",
        "import struct Darwin.C", "import func Darwin.fwrite", "import os.log", "@_exported import Darwin",
        "@_implementationOnly import os", "@preconcurrency import Glibc", "import Foundation; import Darwin",
    ])
    func rule6ImportCaught(code: String) {
        #expect(scan(.tendEval, PlanPaths.evalFile, code).contains { $0.rule == .rule6 && $0.check == "import" },
                "\(code)")
    }

    @Test("AC-M2-09 M2 Q24 Rule 6 positive: the six listed modules pass, also with a kind keyword or an attribute")
    func rule6ImportsPass() {
        let code = """
            import Foundation
            import SwiftUI
            import CryptoKit
            import TendCore
            import TendIngestion
            import TendAI
            @preconcurrency import Foundation
            import struct Foundation.Date
            @_exported import TendCore
            """
        #expect(scan(.tendEval, PlanPaths.evalFile, code).isEmpty)
    }

    @Test("Import module parsing: the first path component after any kind keyword (M2 Q24)", arguments: [
        ("Darwin", "Darwin"), ("struct Darwin.C", "Darwin"), ("func Darwin.fwrite", "Darwin"), ("os.log", "os"),
        ("class  Foundation.NSObject", "Foundation"), ("Foundation", "Foundation"),
    ])
    func importedModuleParsing(target: String, expected: String) {
        #expect(IngestionSourceRules.importedModule(of: target) == expected)
    }

    // MARK: How call patterns match (M2 Q24)

    @Test("Call-pattern rule: a . receiver, whitespace and newlines before ( and before the label, and backticks still match",
          arguments: [
            ("Swift.print(x)", "log API print("),
            ("print (x)", "log API print("),
            ("print\n(x)", "log API print("),
            ("`print`(x)", "log API print("),
            ("try d.write(\n    to: u)", "write API write(to:"),
            ("try d.write( toFile : p, atomically: true)", "write API write(toFile:"),
            ("let x = try await s.`data`(for: q)", "networking data(for:"),
            ("let x = try await s.data(\n  for: q)", "networking data(for:"),
            ("let f = s.`dataTask`", "networking dataTask"),
          ])
    func callPatternMatches(code: String, check: String) {
        #expect(scan(.tendIngestion, PlanPaths.ingestionFile, code).contains { $0.rule == .rule1 && $0.check == check },
                "`\(code)`")
    }

    @Test("Call-pattern rule: identifier boundary on the left, case-sensitive, exact first label, whole method-reference tokens")
    func callPatternNearMisses() {
        let code = """
            let a = inputs(x)
            let b = snprintf(&buf, 8, f)
            let c = metadata(for: k)
            let d = reprint(x)
            let e = defaults.data(forKey: k)
            let f = Print(x) + PUTS(y) + Fopen(z)
            let g = create(x)
            let h = s.data(with: q)
            let i = dataTaskCount + uploadTasks + myStreamTask
            let j = DataTask.self
            let k = my_puts(x) + x2printf(y)
            """
        for (module, path) in [(ScannedModule.tendIngestion, PlanPaths.ingestionFile),
                               (.tendAI, PlanPaths.aiFile), (.tendAI, PlanPaths.transport), (.tendEval, PlanPaths.evalFile)] {
            let found = scan(module, path, code)
            #expect(found.isEmpty, "\(path): \(found)")
        }
        // Their own patterns: fprintf( and fputs( are hits.
        #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "fprintf(h, f)").contains { $0.check == "log API fprintf(" })
        #expect(!scan(.tendIngestion, PlanPaths.ingestionFile, "fprintf(h, f)").contains { $0.check == "log API printf(" })
        #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "fputs(s, f)").contains { $0.check == "write API fputs(" })
        #expect(!scan(.tendIngestion, PlanPaths.ingestionFile, "fputs(s, f)").contains { $0.check == "log API puts(" })
    }
}
