// TendTools commands: argument parsing and exit codes (plan "Scoring tool and command": 0 / 1 / 2; usage 64), run over
// the committed self-test files. Linux CI builds this package; these tests are run locally (dev-notes WI-M2-15).

import Foundation
import Synchronization
import TendIngestion
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

/// A-F1 files built from the committed self-test files (in01 text, in02 voice (2 attempts), in03…in05 text, in06 voice,
/// in07 text, in08 voice): input IDs renamed in the fixtures and the results file alike, and only `keep` left in the
/// results file. The files are given to the tool in memory, under the self-test paths.
enum SubsetFiles {
    static func renamed(_ json: EvalJSON, _ names: [String: String]) -> EvalJSON {
        switch json {
        case let .string(value): .string(names[value] ?? value)
        case let .array(values): .array(values.map { renamed($0, names) })
        case let .object(members): .object(members.map { EvalJSON.Member($0.key, renamed($0.value, names)) })
        default: json
        }
    }

    static func keeping(_ results: EvalJSON, _ keep: Set<String>) -> EvalJSON {
        guard case let .object(members) = results else { return results }
        return .object(members.map { member in
            guard member.key == "inputs", case let .array(inputs) = member.value else { return member }
            return EvalJSON.Member("inputs", .array(inputs.filter {
                guard case let .string(id)? = $0["inputID"] else { return false }
                return keep.contains(id)
            }))
        })
    }

    static let resultsName = "results-subset.canonical.json"

    static func overrides(rename names: [String: String] = [:], keep: Set<String>) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in ["inputs.json", "golden.json"] {
            let path = Repo.path(Repo.selfTest + "/" + name)
            let root = try EvalJSONReader.parse(try #require(FileManager.default.contents(atPath: path)))
            files[path] = try CanonicalJSONWriter.data(renamed(root, names).canonical)
        }
        let results = try EvalJSONReader.parse(try #require(FileManager.default.contents(
            atPath: Repo.path(Repo.selfTest + "/results-selftest-1.canonical.json"))))
        files[Repo.path(Repo.selfTest + "/" + resultsName)] =
            try CanonicalJSONWriter.data(keeping(renamed(results, names), keep).canonical)
        return files
    }
}

/// One A-F1 command case: a profile, the renames, the inputs kept, and the scorer log line or the reason expected.
struct SubsetCommandCase: Sendable, CustomTestStringConvertible {
    var profile: String
    var rename: [String: String] = [:]
    var keep: Set<String>
    var label: String
    var testDescription: String { "\(profile): \(label)" }
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

    @Test("tend-eval-score: usage errors exit 64 (missing option, unknown profile, ds2-gated without a key-path list or golden body)")
    func scoreUsage() {
        let box = Captured()
        #expect(EvalScoreCommand.run([], io: Repo.io(box)) == 64)
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "gated"), io: Repo.io(box)) == 64)
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "ds2-gated"), io: Repo.io(box)) == 64)
        #expect(box.err.contains("--allowed-key-paths is required"))
        let withList = Repo.scoreArguments(profile: "ds2-gated") + ["--allowed-key-paths", "/tmp/list.json"]
        #expect(EvalScoreCommand.run(withList, io: Repo.io(box)) == 64)
        #expect(box.err.contains("--golden-body is required for ds2-gated (AC-M2-26, D-059)"))
        #expect(EvalScoreCommand.run(["--help"], io: Repo.io(box)) == 0)
        #expect(box.out.contains("--golden-body"))
    }

    static let acceptedSubsets: [(SubsetCommandCase, String)] = [
        (SubsetCommandCase(profile: "ds1-offline", rename: ["in06": "in10"], keep: ["in01", "in02", "in10"],
                           label: "in01 (text), in02 (voice, 2 attempts), in10 (voice)"),
         "check PASS: inputs in01 (text), in02 (voice), in10 (voice) (AC-M2-11): file has in01 (text), in02 (voice), "
            + "in10 (voice)\n"),
        (SubsetCommandCase(profile: "ds2-offline", rename: ["in06": "in16"], keep: ["in08", "in16"],
                           label: "in08 (voice), in16 (voice)"),
         "check PASS: inputs in08 (voice), in16 (voice) (AC-M2-25): file has in08 (voice), in16 (voice)\n"),
        (SubsetCommandCase(profile: "ds2-online", rename: ["in06": "in16"], keep: ["in08", "in16"],
                           label: "in08 (voice), in16 (voice)"),
         "check PASS: inputs in08 (voice), in16 (voice) (AC-M2-25): file has in08 (voice), in16 (voice)\n"),
    ]

    @Test("tend-eval-score (A-F1): the fixed subset is scored (exit 0 or 1, not 2); the log prints its IDs and modes",
          arguments: acceptedSubsets)
    func subsetScored(_ c: SubsetCommandCase, line: String) throws {
        let box = Captured()
        let overrides = try SubsetFiles.overrides(rename: c.rename, keep: c.keep)
        let code = EvalScoreCommand.run(Repo.scoreArguments(profile: c.profile, results: SubsetFiles.resultsName),
                                        io: Repo.io(box, overrides: overrides))
        #expect(code == 0 || code == 1, "\(code): \(box.err)")
        #expect(box.out.contains(line), "\(box.out)")
        #expect(box.written["/tmp/x.log"] == Data(box.out.utf8))
    }

    static let refusedSubsets: [(SubsetCommandCase, [String])] = [
        // Right count, wrong ID.
        (SubsetCommandCase(profile: "ds1-offline", keep: ["in01", "in02", "in06"],
                           label: "right count, wrong ID: in06 (voice) for in10"),
         ["exactly in01 (text), in02 (voice), in10 (voice)", "the file has in01 (text), in02 (voice), in06 (voice)",
          "not in the subset: in06 (voice)", "not in the file: in10 (voice)"]),
        (SubsetCommandCase(profile: "ds2-offline", keep: ["in06", "in08"],
                           label: "right count, wrong ID: in06 (voice) for in16"),
         ["exactly in08 (voice), in16 (voice)", "the file has in06 (voice), in08 (voice)",
          "not in the subset: in06 (voice)", "not in the file: in16 (voice)"]),
        (SubsetCommandCase(profile: "ds2-online", keep: ["in02", "in06"],
                           label: "right count, wrong ID: in02 (voice), in06 (voice)"),
         ["exactly in08 (voice), in16 (voice)", "the file has in02 (voice), in06 (voice)",
          "not in the subset: in02 (voice), in06 (voice)", "not in the file: in08 (voice), in16 (voice)"]),
        // Right IDs, wrong mode (the fixtures say text too).
        (SubsetCommandCase(profile: "ds1-offline", rename: ["in03": "in10"], keep: ["in01", "in02", "in10"],
                           label: "wrong mode: in10 (text)"),
         ["the file has in01 (text), in02 (voice), in10 (text)", "in10 is text in the file, the subset takes it as voice"]),
        (SubsetCommandCase(profile: "ds2-offline", rename: ["in03": "in16"], keep: ["in08", "in16"],
                           label: "wrong mode: in16 (text)"),
         ["the file has in08 (voice), in16 (text)", "in16 is text in the file, the subset takes it as voice"]),
        (SubsetCommandCase(profile: "ds2-online", rename: ["in03": "in16"], keep: ["in08", "in16"],
                           label: "wrong mode: in16 (text)"),
         ["the file has in08 (voice), in16 (text)", "in16 is text in the file, the subset takes it as voice"]),
        // The whole self-test file.
        (SubsetCommandCase(profile: "ds1-offline", keep: ["in01", "in02", "in03", "in04", "in05", "in06", "in07", "in08"],
                           label: "every self-test input"),
         ["not in the subset: in03 (text), in04 (text), in05 (text), in06 (voice), in07 (text), in08 (voice)"]),
    ]

    @Test("tend-eval-score (A-F1): any other input set exits 2 with a plain reason naming the IDs and modes",
          arguments: refusedSubsets)
    func subsetRefused(_ c: SubsetCommandCase, parts: [String]) throws {
        let box = Captured()
        let overrides = try SubsetFiles.overrides(rename: c.rename, keep: c.keep)
        let code = EvalScoreCommand.run(Repo.scoreArguments(profile: c.profile, results: SubsetFiles.resultsName),
                                        io: Repo.io(box, overrides: overrides))
        #expect(code == 2, "\(code): \(box.out)")
        #expect(box.out.isEmpty && box.written.isEmpty)
        #expect(box.err.hasPrefix("tend-eval-score: file rejected: the inputs are not the fixed \(c.profile) subset ("))
        for part in parts { #expect(box.err.contains(part), "\(part) in \(box.err)") }
        let words = Set(box.err.lowercased().split { !$0.isLetter }.map(String.init))
        #expect(words.isDisjoint(with: ["overdue", "late", "missed", "failed", "behind", "penalty"]), "\(box.err)")
    }

    @Test("tend-eval-score (A-F1): the whole-set profiles take any input set (info over the 3-input file)")
    func wholeSetProfiles() throws {
        let box = Captured()
        let overrides = try SubsetFiles.overrides(keep: ["in01", "in02", "in06"])
        #expect(EvalScoreCommand.run(Repo.scoreArguments(profile: "info", results: SubsetFiles.resultsName),
                                     io: Repo.io(box, overrides: overrides)) == 0, "\(box.err)")
    }

    @Test("allowed key-path lists: an array of strings, or keyPaths of strings or {path} objects")
    func keyPathLists() {
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"["$.a","$.b"]"#.utf8)) == ["$.a", "$.b"])
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"keyPaths":[{"path":"$.a","role":"fixed"}]}"#.utf8)) == ["$.a"])
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"keyPaths":[1]}"#.utf8)) == nil)
        #expect(EvalScoreCommand.allowedKeyPaths(Data(#"{"paths":[]}"#.utf8)) == nil)
    }

    @Test("tend-payload-dump (WI-M2-10): each provider's body equals the committed G1 golden body byte for byte; no key and no extra output on stdout; the path goes to stderr", arguments: [
        ("openai", "api.openai.com/v1/chat/completions"),
        ("anthropic", "api.anthropic.com/v1/messages"),
        ("gemini", "generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse"),
    ])
    func payloadDump(provider: String, target: String) throws {
        let box = Captured()
        #expect(PayloadDumpCommand.run(["--provider", provider, "--outcome-sample"], io: Repo.io(box)) == 0)
        let golden = try #require(FileManager.default.contents(
            atPath: Repo.path("Fixtures/M2/payload/golden/g1-outcome-empty-\(provider).body.json")))
        #expect(Data(box.out.utf8) == golden)
        #expect(box.out.contains(PayloadDumpCommand.outcomeSentence))
        #expect(box.err.contains("POST " + target))
    }

    @Test("tend-payload-dump: usage errors exit 64 and print no body")
    func payloadDumpUsage() {
        for arguments in [["--provider", "mistral", "--outcome-sample"], ["--provider", "gemini"], ["--outcome-sample"],
                          ["--provider", "openai", "--outcome-sample", "--key", "FAKE"]] {
            let box = Captured()
            #expect(PayloadDumpCommand.run(arguments, io: Repo.io(box)) == 64, "\(arguments)")
            #expect(box.out.isEmpty)
        }
    }
}
