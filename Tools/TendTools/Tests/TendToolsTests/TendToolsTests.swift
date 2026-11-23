// TendTools commands: argument parsing and exit codes (plan "Scoring tool and command": 0 / 1 / 2; usage 64), run over
// the committed self-test files. Linux CI builds this package; these tests are run locally (dev-notes WI-M2-15).

import Foundation
import Synchronization
import Testing
@testable import TendToolsSupport

/// Captures a command's output. A `Mutex` makes it checked `Sendable` (review R27-N1; no `@unchecked`).
final class Captured: Sendable {
    struct State {
        var out = ""
        var err = ""
        var written: [String: Data] = [:]
    }

    private let state = Mutex(State())

    var out: String { state.withLock { $0.out } }
    var err: String { state.withLock { $0.err } }
    var written: [String: Data] { state.withLock { $0.written } }

    func appendOut(_ text: String) { state.withLock { $0.out += text } }
    func appendErr(_ text: String) { state.withLock { $0.err += text } }
    func record(_ path: String, _ data: Data) { state.withLock { $0.written[path] = data } }
}

enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // TendTools
        .deletingLastPathComponent().deletingLastPathComponent()                               // repository root

    static func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

    static func io(_ box: Captured, overrides: [String: Data] = [:]) -> ToolIO {
        ToolIO(
            read: { overrides[$0] ?? FileManager.default.contents(atPath: $0) },
            write: { box.record($0, $1); return true },
            standardOutput: { box.appendOut($0) },
            standardError: { box.appendErr($0) }
        )
    }

    static let selfTest = "Fixtures/M2/eval-selftest"
    static func scoreArguments(profile: String, results: String = "results-selftest-1.canonical.json",
                               hash: String = String(repeating: "a", count: 64)) -> [String] {
        ["--profile", profile, "--fixtures", path(selfTest), "--schema", path("Fixtures/M2/eval/results-v1.schema.json"),
         "--expected-fixtures-sha256", hash, "--results", path(selfTest + "/" + results), "--log", "/tmp/x.log"]
    }
}

@Suite("TendTools (WI-M2-15)")
struct TendToolsTests {

    @Test("arguments: --name value, --name=value, flags; unknown, repeated and missing values are usage errors")
    func arguments() throws {
        let parsed = try ParsedArguments(["--a", "1", "--b=2", "--f"], options: ["a", "b"], flags: ["f"])
        #expect(parsed.options == ["a": "1", "b": "2"] && parsed.flags == ["f"])
        for bad in [["--c", "1"], ["--a"], ["--a", "--b", "2"], ["--a", "1", "--a", "2"], ["x"], ["--f=1"], ["--f", "--f"]] {
            #expect(throws: UsageError.self) { try ParsedArguments(bad, options: ["a", "b"], flags: ["f"]) }
        }
    }

    @Test("tend-eval-score: info over the canonical self-test file scores it, prints and writes the log, exit 0")
    func scoreInfo() {
        let box = Captured()
        let code = EvalScoreCommand.run(Repo.scoreArguments(profile: "info"), io: Repo.io(box))
        #expect(code == 0, "\(box.err)")
        #expect(box.out.contains("totals: N 18") && box.out.hasSuffix("profile info: INFO (no pass rule)\n"))
        #expect(box.written["/tmp/x.log"] == Data(box.out.utf8))
    }

    @Test("tend-eval-score: a profile that does not pass exits 1 (the self-test file under ds1-gated)")
    func scoreNotPass() {
        let box = Captured()
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "ds1-gated"), io: Repo.io(box)) == 1)
        #expect(box.out.contains("profile ds1-gated: FAIL"))
    }

    @Test("tend-eval-score: rejected files exit 2 — not canonical, fixtures hash mismatch, not v1, unreadable")
    func scoreRejected() {
        let box = Captured()
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "info", results: "results-selftest-1.json"),
                                     io: Repo.io(box)) == 2)
        #expect(box.err.contains("not canonical"))
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "info", hash: String(repeating: "b", count: 64)),
                                     io: Repo.io(box)) == 2)
        #expect(box.err.contains("the fixtures hash does not match"))
        let v2 = Repo.path(Repo.selfTest + "/v2.json")
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "info", results: "v2.json"),
                                     io: Repo.io(box, overrides: [v2: Data(#"{"schemaVersion":2}"#.utf8)])) == 2)
        #expect(box.err.contains("not a results file v1"))
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "info", results: "absent.json"), io: Repo.io(box)) == 2)
        #expect(box.err.contains("cannot read"))
    }

    @Test("tend-eval-score: usage errors exit 64 (missing option, unknown profile, ds2-gated without a key-path list)")
    func scoreUsage() {
        let box = Captured()
        #expect(EvalScoreCommand.run([], io: Repo.io(box)) == 64)
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "gated"), io: Repo.io(box)) == 64)
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "ds2-gated"), io: Repo.io(box)) == 64)
        #expect(box.err.contains("--allowed-key-paths is required"))
        #expect(EvalScoreCommand.run(["--help"], io: Repo.io(box)) == 0)
    }

    @Test("allowed key-path lists: an array of strings, or keyPaths of strings or {path} objects")
    func keyPathLists() {
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"["$.a","$.b"]"#.utf8)) == ["$.a", "$.b"])
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"keyPaths":[{"path":"$.a","role":"fixed"}]}"#.utf8)) == ["$.a"])
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"keyPaths":[1]}"#.utf8)) == nil)
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"paths":[]}"#.utf8)) == nil)
    }

    @Test("tend-payload-dump is a stub until WI-M2-10: valid arguments exit 3 with no body; bad ones exit 64")
    func payloadDumpStub() {
        let box = Captured()
        #expect(PayloadDumpCommand.run(["--provider", "openai", "--outcome-sample"], io: Repo.io(box)) == 3)
        #expect(box.out.isEmpty && box.err.contains("WI-M2-10"))
        #expect(PayloadDumpCommand.run(["--provider", "mistral", "--outcome-sample"], io: Repo.io(box)) == 64)
        #expect(PayloadDumpCommand.run(["--provider", "gemini"], io: Repo.io(box)) == 64)
    }
}
