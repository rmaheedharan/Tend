// `tend-eval-score` (plan "Scoring tool and command"; AC-M2-14, 15, 17, 26; T-26). It reads the files, calls the
// `TendIngestion` scorer with `Data`, writes the scorer log, and returns the exit code:
//   0 = scored and the profile passes, 1 = scored and the profile does not pass,
//   2 = file rejected (not v1, not conforming, not canonical, inconsistent, or the fixtures hash does not match; also
//       unreadable or unusable fixtures and schema; also, for ds1-offline, ds2-offline and ds2-online, input IDs or
//       modes other than the profile's fixed subset, A-F1), 64 = usage error.
// The fixtures hash is the SHA-256 of the `MANIFEST.sha256` bytes, computed by the caller (`sha256sum`) and compared
// with the file's `run.fixturesSHA256`; the manifest itself is checked with `sha256sum -c` first (plan command).

import Foundation
import TendIngestion

public enum EvalScoreCommand {

    public static let usage = """
        usage: tend-eval-score --profile <ds1-gated|ds1-offline|ds2-offline|ds2-online|ds2-gated|info>
                               --fixtures <dir> --expected-fixtures-sha256 <hex> --results <file>
                               [--log <file>] [--schema <file>] [--allowed-key-paths <file>] [--golden-body <file>]
          <dir> holds inputs.json, household.json, golden.json and (unless --schema) results-v1.schema.json.
          --allowed-key-paths: the provider's allowed key-path list (ds2-gated): a JSON array of path strings, or an
          object whose "keyPaths" member is such an array or an array of objects with a "path" member.
          --golden-body: the provider's Fixtures/M2/payload/golden/g1-outcome-empty-<provider>.body.json (ds2-gated):
          every sent body's per-array element counts must equal its counts (D-059).
        fixed subsets (PO ruling F3): ds1-offline takes exactly in01 (text), in02 (voice), in10 (voice);
          ds2-offline and ds2-online take exactly in08 (voice), in16 (voice). Any other input set is rejected.
        exit: 0 profile passes, 1 profile does not pass, 2 file rejected, 64 usage error

        """

    public static let exitPass: Int32 = 0
    public static let exitNotPass: Int32 = 1
    public static let exitRejected: Int32 = 2
    public static let exitUsage: Int32 = 64

    public static func run(_ arguments: [String], io: ToolIO) -> Int32 {
        let parsed: ParsedArguments
        let profile: EvalProfile
        let fixtures: String
        let expected: String
        let resultsPath: String
        do throws(UsageError) {
            parsed = try ParsedArguments(arguments, options: ["profile", "fixtures", "expected-fixtures-sha256",
                                                              "results", "log", "schema", "allowed-key-paths",
                                                              "golden-body"],
                                         flags: ["help"])
            if parsed.flags.contains("help") { io.standardOutput(usage); return exitPass }
            let profileName = try parsed.required("profile")
            guard let known = EvalProfile(rawValue: profileName) else { throw UsageError("unknown profile: \(profileName)") }
            profile = known
            fixtures = try parsed.required("fixtures")
            expected = try parsed.required("expected-fixtures-sha256").lowercased()
            resultsPath = try parsed.required("results")
            if profile == .ds2Gated, parsed.options["allowed-key-paths"] == nil {
                throw UsageError("--allowed-key-paths is required for ds2-gated (AC-M2-26)")
            }
            if profile == .ds2Gated, parsed.options["golden-body"] == nil {
                throw UsageError("--golden-body is required for ds2-gated (AC-M2-26, D-059)")
            }
        } catch {
            io.standardError("tend-eval-score: \(error.message)\n\(usage)")
            return exitUsage
        }

        func reject(_ message: String) -> Int32 {
            io.standardError("tend-eval-score: file rejected: \(message)\n")
            return exitRejected
        }
        let directory = fixtures.hasSuffix("/") ? fixtures : fixtures + "/"
        let schemaPath = parsed.options["schema"] ?? directory + "results-v1.schema.json"
        var files: [String: Data] = [:]
        for (name, path) in [("results", resultsPath), ("schema", schemaPath),
                             ("inputs", directory + "inputs.json"), ("household", directory + "household.json"),
                             ("golden", directory + "golden.json")] {
            guard let data = io.read(path) else { return reject("cannot read \(path)") }
            files[name] = data
        }
        var allowed: Set<String>?
        if let path = parsed.options["allowed-key-paths"] {
            guard let data = io.read(path) else { return reject("cannot read \(path)") }
            guard let list = allowedKeyPaths(data) else { return reject("\(path) is not an allowed key-path list") }
            allowed = list
        }
        var goldenBody: Data?
        if let path = parsed.options["golden-body"] {
            guard let data = io.read(path) else { return reject("cannot read \(path)") }
            goldenBody = data
        }
        let request = EvalScoringRequest(
            results: files["results"] ?? Data(), schema: files["schema"] ?? Data(), inputs: files["inputs"] ?? Data(),
            household: files["household"] ?? Data(), golden: files["golden"] ?? Data(),
            expectedFixturesSHA256: expected, profile: profile, allowedKeyPaths: allowed, goldenBody: goldenBody
        )
        let report: EvalReport
        do throws(EvalScoringError) {
            report = try EvalScorer.run(request)
        } catch {
            return reject(describe(error))
        }
        io.standardOutput(report.log)
        if let logPath = parsed.options["log"], !io.write(logPath, Data(report.log.utf8)) {
            io.standardError("tend-eval-score: cannot write the log to \(logPath)\n")
            return exitRejected
        }
        return report.profileResult.passes ? exitPass : exitNotPass
    }

    /// A JSON array of strings, or `{"keyPaths": [...]}` with strings or `{"path": ...}` objects.
    static func allowedKeyPaths(_ data: Data) -> Set<String>? {
        guard let root = try? EvalJSONReader.parse(data) else { return nil }
        let list: EvalJSON
        if case .array = root { list = root } else if let member = root["keyPaths"] { list = member } else { return nil }
        guard case let .array(entries) = list else { return nil }
        var result: Set<String> = []
        for entry in entries {
            switch entry {
            case let .string(path): result.insert(path)
            case .object:
                guard case let .string(path)? = entry["path"] else { return nil }
                result.insert(path)
            default: return nil
            }
        }
        return result
    }

    static func describe(_ error: EvalScoringError) -> String {
        switch error {
        case let .schemaUnusable(reason): "the schema cannot be used: \(reason)"
        case let .fixturesUnusable(reason): "the fixtures cannot be used: \(reason)"
        case .rejected(.notVersion1): "not a results file v1 (schemaVersion is not 1)"
        case .rejected(.notCanonical): "not canonical JSON (sorted keys, no whitespace, integers only)"
        case let .rejected(.fixturesHashMismatch(expected, found)):
            "the fixtures hash does not match (expected \(expected), file has \(found))"
        case let .rejected(.schemaIssues(issues)):
            "does not conform to results-v1.schema.json:\n  " + issues.prefix(20).map(\.description).joined(separator: "\n  ")
        case let .rejected(.notJSON(reason)): "not JSON: \(reason)"
        case let .rejected(.inconsistent(reason)): "a cross-field rule does not hold: \(reason)"
        case let .subsetMismatch(mismatch): mismatch.reason
        }
    }
}
