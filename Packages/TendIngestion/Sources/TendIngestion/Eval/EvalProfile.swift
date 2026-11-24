// Scoring profiles (plan "Scoring tool and command", "Profiles") and the one entry point the tool calls. FR-A1, UX-3;
// AC-M2-11, 15, 16, 17, 25, 26, 27.
//
// A profile is a list of named checks over the score. Each check cites the AC clause it implements. The scorer
// reports numbers; a profile says whether they meet the AC. The device ACs stay AWAITING-DEVICE until the owner's run
// is recorded (CLAUDE.md §5): a PASS here over a real device file is that AC's scoring evidence, nothing more.

import Foundation
import TendCore

public enum EvalProfile: String, Sendable, Hashable, CaseIterable {
    /// AC-M2-15, 16, 17 (DS-1, on device).
    case ds1Gated = "ds1-gated"
    /// AC-M2-11 (DS-1, airplane mode, 3 inputs).
    case ds1Offline = "ds1-offline"
    /// AC-M2-25, offline part (DS-2, 2 voice inputs).
    case ds2Offline = "ds2-offline"
    /// AC-M2-25, online part (DS-2, the same 2 voice inputs through the cloud).
    case ds2Online = "ds2-online"
    /// AC-M2-26, 27 (DS-2, one provider).
    case ds2Gated = "ds2-gated"
    /// No pass rule (cold start, the iPhone 15 Pro cloud run).
    case info
}

/// One input of a fixed subset: its ID and mode (A-F1; PO rulings F3 and F4 in po-m2-wi16.md).
public struct EvalSubsetInput: Sendable, Hashable, CustomStringConvertible {
    public var inputID: String
    public var mode: EvalInputMode

    public init(_ inputID: String, _ mode: EvalInputMode) {
        self.inputID = inputID
        self.mode = mode
    }

    /// `in01 (text)`: the form the reason and the scorer log use.
    public var description: String { "\(inputID) (\(mode.rawValue))" }

    /// The distinct (input ID, mode) pairs of the file's attempts, sorted by input ID (UTF-8 bytes), then mode. A
    /// retake does not add a pair.
    static func inputs(of file: EvalResultsFileV1) -> [EvalSubsetInput] {
        Set(file.inputs.map { EvalSubsetInput($0.inputID, $0.mode) }).sorted {
            $0.inputID == $1.inputID ? $0.mode.rawValue < $1.mode.rawValue
                : TextFolding.utf8Precedes($0.inputID, $1.inputID)
        }
    }

    static func list(_ inputs: [EvalSubsetInput]) -> String {
        inputs.isEmpty ? "no input" : inputs.map(\.description).joined(separator: ", ")
    }
}

extension EvalProfile {

    /// The fixed input subset of the profile (PO ruling F3), or nil for a profile over the whole fixture set. Pinned
    /// here, not an argument: AC-M2-11 = in01 (text), in02 (voice), in10 (voice); AC-M2-25 = in08 (voice),
    /// in16 (voice). A change needs a DECISIONS.md entry (AC-M2-14 rule). Sorted by input ID.
    public var subset: [EvalSubsetInput]? {
        switch self {
        case .ds1Offline: [EvalSubsetInput("in01", .text), EvalSubsetInput("in02", .voice), EvalSubsetInput("in10", .voice)]
        case .ds2Offline, .ds2Online: [EvalSubsetInput("in08", .voice), EvalSubsetInput("in16", .voice)]
        case .ds1Gated, .ds2Gated, .info: nil
        }
    }

    /// The AC a subset profile scores.
    var subsetAC: String {
        switch self {
        case .ds1Offline: "AC-M2-11"
        case .ds2Offline, .ds2Online: "AC-M2-25"
        case .ds1Gated: "AC-M2-15"
        case .ds2Gated: "AC-M2-26"
        case .info: "no AC"
        }
    }
}

/// A file whose inputs are not exactly the profile's fixed subset (A-F1). The tool exits 2.
public struct EvalSubsetMismatch: Sendable, Hashable {
    public var profile: EvalProfile
    public var required: [EvalSubsetInput]
    public var found: [EvalSubsetInput]

    public init(profile: EvalProfile, required: [EvalSubsetInput], found: [EvalSubsetInput]) {
        self.profile = profile
        self.required = required
        self.found = found
    }

    /// A plain reason that names every input ID and mode on both sides.
    public var reason: String {
        let requiredIDs = Dictionary(required.map { ($0.inputID, $0.mode) }, uniquingKeysWith: { first, _ in first })
        let foundIDs = Set(found.map(\.inputID))
        var notes: [String] = []
        let extra = found.filter { requiredIDs[$0.inputID] == nil }
        if !extra.isEmpty { notes.append("not in the subset: " + EvalSubsetInput.list(extra)) }
        let absent = required.filter { !foundIDs.contains($0.inputID) }
        if !absent.isEmpty { notes.append("not in the file: " + EvalSubsetInput.list(absent)) }
        for input in found {
            if let mode = requiredIDs[input.inputID], mode != input.mode {
                notes.append("\(input.inputID) is \(input.mode.rawValue) in the file, the subset takes it as \(mode.rawValue)")
            }
        }
        return "the inputs are not the fixed \(profile.rawValue) subset (\(profile.subsetAC), PO ruling F3): it takes "
            + "exactly \(EvalSubsetInput.list(required)); the file has \(EvalSubsetInput.list(found))"
            + (notes.isEmpty ? "" : "; " + notes.joined(separator: "; "))
    }
}

/// One named check of a profile.
public struct EvalCheck: Sendable, Hashable {
    public var name: String
    public var holds: Bool
    public var detail: String
}

public struct EvalProfileResult: Sendable, Hashable {
    public var profile: EvalProfile
    public var checks: [EvalCheck]

    /// True when every check holds (always true for `info`).
    public var passes: Bool { checks.allSatisfy(\.holds) }
}

/// The whole result: the file, the score, the profile result and the scorer log.
public struct EvalReport: Sendable, Hashable {
    public var file: EvalResultsFileV1
    public var score: EvalScore
    public var profileResult: EvalProfileResult
    public var log: String
}

/// Everything the scorer needs, as bytes (the tool reads the files; AC-M2-09 Rule 1).
public struct EvalScoringRequest: Sendable, Hashable {
    public var results: Data
    public var schema: Data
    public var inputs: Data
    public var household: Data
    public var golden: Data
    /// The SHA-256 of the `MANIFEST.sha256` bytes, lower-case hex (plan "Fixtures hash").
    public var expectedFixturesSHA256: String
    public var profile: EvalProfile
    /// The provider's allowed key-path list (AC-M2-26), needed by `ds2-gated` only.
    public var allowedKeyPaths: Set<String>?

    public init(
        results: Data, schema: Data, inputs: Data, household: Data, golden: Data, expectedFixturesSHA256: String,
        profile: EvalProfile, allowedKeyPaths: Set<String>? = nil
    ) {
        self.results = results
        self.schema = schema
        self.inputs = inputs
        self.household = household
        self.golden = golden
        self.expectedFixturesSHA256 = expectedFixturesSHA256
        self.profile = profile
        self.allowedKeyPaths = allowedKeyPaths
    }
}

/// Why scoring could not start or the file was refused. The tool exits 2 for every case.
public enum EvalScoringError: Error, Sendable, Hashable {
    case schemaUnusable(EvalSchemaError)
    case fixturesUnusable(EvalFixtureError)
    case rejected(EvalRejection)
    /// A-F1: a subset profile (`ds1-offline`, `ds2-offline`, `ds2-online`) got other input IDs or modes.
    case subsetMismatch(EvalSubsetMismatch)
}

extension EvalScorer {

    /// Reads the fixtures and schema, reads and checks the results file, scores it and applies the profile.
    public static func run(_ request: EvalScoringRequest) throws(EvalScoringError) -> EvalReport {
        let schema: EvalSchemaCheck
        do throws(EvalSchemaError) { schema = try EvalSchemaCheck(schemaData: request.schema) } catch {
            throw .schemaUnusable(error)
        }
        let fixtures: EvalFixtures
        do throws(EvalFixtureError) {
            fixtures = try EvalFixtures(inputs: request.inputs, household: request.household, golden: request.golden)
        } catch {
            throw .fixturesUnusable(error)
        }
        let file: EvalResultsFileV1
        do throws(EvalRejection) {
            file = try EvalResultsFileV1.read(request.results, schema: schema, fixtures: fixtures,
                                             expectedFixturesSHA256: request.expectedFixturesSHA256)
        } catch {
            throw .rejected(error)
        }
        if let required = request.profile.subset {
            let found = EvalSubsetInput.inputs(of: file)
            guard found == required else {
                throw .subsetMismatch(EvalSubsetMismatch(profile: request.profile, required: required, found: found))
            }
        }
        let score = score(file, fixtures: fixtures)
        let result = EvalProfileChecks.evaluate(request.profile, file: file, score: score, fixtures: fixtures,
                                                allowedKeyPaths: request.allowedKeyPaths)
        let log = EvalScoreLog.render(file: file, score: score, result: result)
        return EvalReport(file: file, score: score, profileResult: result, log: log)
    }
}

enum EvalProfileChecks {

    /// Rubric Q3 and the brief's N ≥ 50 (AC-M2-14).
    static let minimumGoldenItems = 50
    /// Rubric Q3: ≤ 2 extra drafts in total.
    static let maximumExtras = 2
    /// AC-M2-17, AC-M2-26: at most 1 false merge in total.
    static let maximumFalseMerges = 1

    static func evaluate(
        _ profile: EvalProfile, file: EvalResultsFileV1, score: EvalScore, fixtures: EvalFixtures,
        allowedKeyPaths: Set<String>?
    ) -> EvalProfileResult {
        var checks: [EvalCheck] = []
        func check(_ name: String, _ holds: Bool, _ detail: String) {
            checks.append(EvalCheck(name: name, holds: holds, detail: detail))
        }
        let totals = score.totals
        let provider = file.run.provider

        func q3Thresholds() {
            check("N >= \(minimumGoldenItems) golden items (AC-M2-14)", totals.goldenItems >= minimumGoldenItems,
                  "N = \(totals.goldenItems)")
            check("every fixture input scored", totals.inputsAbsent.isEmpty,
                  totals.inputsAbsent.isEmpty ? "all \(totals.inputsScored)" : "absent: "
                    + totals.inputsAbsent.joined(separator: ", "))
            for metric in EvalMetric.allCases {
                let required = metric.requiredCount(of: totals.goldenItems)
                let got = totals.correct[metric] ?? 0
                check("\(metric.rawValue) >= \(metric.requiredPercent)% (Q3)", got >= required,
                      "\(got) of \(totals.goldenItems), required \(required)")
            }
            check("extra drafts <= \(maximumExtras) in total (Q3)", totals.extras <= maximumExtras, "\(totals.extras)")
            check("validity 100% (Q3)", totals.validDrafts == totals.drafts, "\(totals.validDrafts) of \(totals.drafts)")
            check("0 introduced banned tokens (Q3, UX-3)", totals.introducedTokens == 0, "\(totals.introducedTokens)")
            check("0 duplicates created (AC-M2-17/26)", totals.duplicatesCreated == 0, "\(totals.duplicatesCreated)")
            check("false merges <= \(maximumFalseMerges) (AC-M2-17/26)", totals.falseMerges <= maximumFalseMerges,
                  "\(totals.falseMerges)")
        }

        func timing(ttfiBelow: Int, totalAtMost: Int, ac: String) {
            let slow = score.inputs.filter { ($0.ttfiMs.map { $0 >= ttfiBelow } ?? true) || $0.totalMs > totalAtMost }
            check("every input TTFI < \(ttfiBelow) ms and total <= \(totalAtMost) ms (\(ac))", slow.isEmpty,
                  slow.isEmpty ? "all \(score.inputs.count)" : "not met: " + slow.map(\.inputID).joined(separator: ", "))
        }

        func routes(_ expected: EvalRoute, ac: String) {
            let other = score.inputs.filter { $0.route != expected }
            check("route \(expected.rawValue) for every scored input (\(ac))", other.isEmpty,
                  other.isEmpty ? "all \(score.inputs.count)" : other.map { "\($0.inputID)=\($0.route.rawValue)" }
                    .joined(separator: ", "))
        }

        /// A-F1, second control: `run` refuses another subset before scoring; this check prints the IDs and modes
        /// in the scorer log and holds the rule if `evaluate` is ever reached another way.
        func inputSet(ac: String) {
            let required = profile.subset ?? []
            let found = EvalSubsetInput.inputs(of: file)
            check("inputs \(EvalSubsetInput.list(required)) (\(ac))", found == required,
                  "file has \(EvalSubsetInput.list(found))")
        }

        /// AC-M2-11 / AC-M2-25 per-input rules: completed, every golden item matched, 0 extras, all valid, 0 duplicates
        /// created (and, for AC-M2-11, 0 introduced banned tokens).
        func perInputParse(ac: String, calmWords: Bool) {
            for input in score.inputs {
                var notes: [String] = []
                if input.outcome != .completed { notes.append("outcome \(input.outcome.rawValue)") }
                if !input.notFound.isEmpty { notes.append("not found " + input.notFound.joined(separator: ",")) }
                if !input.extras.isEmpty { notes.append("\(input.extras.count) extra") }
                if !input.invalidDrafts.isEmpty { notes.append("\(input.invalidDrafts.count) not valid") }
                if input.duplicatesCreated > 0 { notes.append("\(input.duplicatesCreated) duplicates created") }
                if calmWords, !input.introducedTokens.isEmpty {
                    notes.append("\(input.introducedTokens.count) introduced banned tokens")
                }
                check("\(input.inputID): parses cleanly (\(ac))", notes.isEmpty, notes.isEmpty ? "ok" : notes.joined(separator: "; "))
            }
        }

        switch profile {
        case .info:
            break
        case .ds1Gated:
            check("run on device, no provider (AC-M2-15)", provider == nil, provider?.rawValue ?? "none")
            q3Thresholds()
            routes(.onDevice, ac: "AC-M2-15")
            timing(ttfiBelow: 1500, totalAtMost: 5000, ac: "AC-M2-16")
        case .ds1Offline:
            check("run on device, no provider (AC-M2-11)", provider == nil, provider?.rawValue ?? "none")
            inputSet(ac: "AC-M2-11")
            routes(.onDevice, ac: "AC-M2-11")
            perInputParse(ac: "AC-M2-11", calmWords: true)
        case .ds2Offline:
            check("a provider is selected (AC-M2-25)", provider != nil, provider?.rawValue ?? "none")
            inputSet(ac: "AC-M2-25")
            for input in score.inputs {
                let holds = input.outcome == .noModel && input.committedCount == 0 && input.draftCount == 0
                check("\(input.inputID): noModel, no task created (AC-M2-25)", holds,
                      "outcome \(input.outcome.rawValue), \(input.committedCount) committed")
            }
        case .ds2Online:
            check("a provider is selected (AC-M2-25)", provider != nil, provider?.rawValue ?? "none")
            inputSet(ac: "AC-M2-25")
            if let provider { routes(EvalRoute(rawValue: provider.rawValue) ?? .none, ac: "AC-M2-25") }
            perInputParse(ac: "AC-M2-25", calmWords: false)
        case .ds2Gated:
            check("a provider is selected (AC-M2-26)", provider != nil, provider?.rawValue ?? "none")
            q3Thresholds()
            if let provider { routes(EvalRoute(rawValue: provider.rawValue) ?? .none, ac: "AC-M2-26") }
            timing(ttfiBelow: 3000, totalAtMost: 10000, ac: "AC-M2-27")
            if let allowed = allowedKeyPaths {
                var outside: Set<String> = []
                for input in score.inputs {
                    for request in input.cloudRequests { outside.formUnion(request.keyPaths.filter { !allowed.contains($0) }) }
                }
                check("sent key paths are a subset of the allowed list (AC-M2-26)", outside.isEmpty,
                      outside.isEmpty ? "ok" : "outside: " + outside.sorted(by: TextFolding.utf8Precedes)
                        .joined(separator: ", "))
            } else {
                check("sent key paths are a subset of the allowed list (AC-M2-26)", false, "no allowed list given")
            }
        }
        return EvalProfileResult(profile: profile, checks: checks)
    }
}
