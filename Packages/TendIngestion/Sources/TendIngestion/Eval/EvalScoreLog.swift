// The scorer log (brief "Eval scoring rules", "Output": "The scorer writes per-input and total counts for every metric,
// each pairing, and each best target. This is the scorer log used as evidence."). AC-M2-14, 15, 17, 26.
//
// A pure function from the score to text; `tend-eval-score` prints it and writes it to the `--log` file. The text is
// deterministic (fixed orders everywhere), so two runs over the same file give the same bytes.

import Foundation
import TendCore

public enum EvalScoreLog {

    public static func render(file: EvalResultsFileV1, score: EvalScore, result: EvalProfileResult) -> String {
        var lines: [String] = []
        let run = file.run
        lines.append("Tend M2 eval scorer log (results file v1; brief Eval scoring rules)")
        lines.append("profile: \(result.profile.rawValue)")
        lines.append("run: device \(run.deviceModel), iOS \(run.iOSBuild), provider \(run.provider?.rawValue ?? "none"), "
                     + "model \(run.modelID), sampling \(run.sampling), started \(run.startedAtUTC)")
        lines.append("run: app \(run.appCommitSHA), fixtures \(run.fixturesSHA256)")
        if let cold = file.coldStart {
            lines.append("cold start (information only): \(cold.inputID) ttfiMs \(cold.ttfiMs.map(String.init) ?? "none")")
        }
        for input in score.inputs {
            lines.append("")
            lines.append("input \(input.inputID): \(input.mode.rawValue), attempt \(input.attempt) scored "
                         + "(\(input.attemptsInFile) in file), route \(input.route.rawValue), outcome "
                         + "\(input.outcome.rawValue), ttfiMs \(input.ttfiMs.map(String.init) ?? "none"), totalMs \(input.totalMs)")
            for id in input.draftText.keys.sorted() {
                lines.append("  draft \(id) text [\((input.draftText[id] ?? []).joined(separator: " "))]")
            }
            for pairing in input.pairings {
                lines.append("  pairing: draft \(pairing.draftID) <-> \(pairing.goldenKey) (overlap \(pairing.overlap))")
            }
            for item in input.items {
                if let id = item.draftID {
                    lines.append("  item \(item.goldenKey): found (draft \(id)); kind \(mark(item.kindCorrect)), room "
                                 + "\(mark(item.roomCorrect)), effort \(mark(item.effortCorrect)), critical "
                                 + "\(mark(item.criticalCorrect)), deepClean \(mark(item.deepCleanCorrect)), weather "
                                 + "\(mark(item.weatherCorrect))")
                } else {
                    lines.append("  item \(item.goldenKey): not found")
                }
            }
            lines.append("  extra drafts: \(list(input.extras.map(String.init)))")
            for best in input.bestTargets {
                let target = best.target.map { "\($0) (overlap \(best.overlap))" } ?? "none"
                lines.append("  best target: draft \(best.draftID) -> \(target)")
            }
            let counts = input.committedCounts.sorted { EvalScorer.precedes($0.key, $1.key) }
                .map { "\($0.key)=\($0.value)" }
            lines.append("  committed: \(input.committedCount); c(x): \(list(counts))")
            let merges = input.falseMerges.isEmpty ? "" : " (" + input.falseMerges.joined(separator: ", ") + ")"
            lines.append("  duplicates created: \(input.duplicatesCreated); false merges: \(input.falseMerges.count)"
                         + merges)
            let invalid = input.invalidDrafts.keys.sorted().map { "draft \($0) \(input.invalidDrafts[$0].map { "\($0)" } ?? "")" }
            lines.append("  validity: \(input.draftCount - input.invalidDrafts.count) of \(input.draftCount) valid"
                         + (invalid.isEmpty ? "" : " (" + invalid.joined(separator: ", ") + ")"))
            let tokens = input.introducedTokens.map { "draft \($0.draftID) \($0.field.rawValue) \($0.token)" }
            lines.append("  introduced banned tokens: \(input.introducedTokens.count)"
                         + (tokens.isEmpty ? "" : " (" + tokens.joined(separator: ", ") + ")"))
            lines.append("  golden \(input.goldenCount), found \(input.goldenCount - input.notFound.count), extras "
                         + "\(input.extras.count)")
        }
        let totals = score.totals
        lines.append("")
        lines.append("totals: inputs scored \(totals.inputsScored), absent \(list(totals.inputsAbsent))")
        lines.append("totals: N \(totals.goldenItems), extras \(totals.extras), drafts \(totals.drafts), valid "
                     + "\(totals.validDrafts), introduced banned tokens \(totals.introducedTokens), duplicates created "
                     + "\(totals.duplicatesCreated), false merges \(totals.falseMerges)")
        for metric in EvalMetric.allCases {
            lines.append("totals: \(metric.rawValue) \(totals.correct[metric] ?? 0) of \(totals.goldenItems) "
                         + "(required \(metric.requiredCount(of: totals.goldenItems)) at \(metric.requiredPercent)%)")
        }
        lines.append("")
        for check in result.checks {
            lines.append("check \(check.holds ? "PASS" : "FAIL"): \(check.name): \(check.detail)")
        }
        let verdict = result.profile == .info ? "INFO (no pass rule)" : (result.passes ? "PASS" : "FAIL")
        lines.append("profile \(result.profile.rawValue): \(verdict)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func mark(_ correct: Bool) -> String { correct ? "ok" : "wrong" }
    static func list(_ items: [String]) -> String { items.isEmpty ? "none" : items.joined(separator: ", ") }
}
