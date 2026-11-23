// AC-M2-14: "The scorer (`TendIngestion`) passes self-tests against hand-built results files with known right and
// wrong answers. They cover every rule below, including a false merge, a duplicate created, a proposed-room match and a
// tie in matching." Brief "Eval scoring rules" (T-04). FR-A1, UX-3.
//
// The hand-built file is `Fixtures/M2/eval-selftest/results-selftest-1.json` with its own small household, inputs and
// golden set (not the eval; the eval fixtures are WI-M2-16). Every expected number below was worked out by hand from
// the brief's rules, before the scorer ran, and the derivation is written next to it. No expected value is computed by
// calling production code. The rule each test covers is named in the test.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("AC-M2-14 scorer self-tests over hand-built results files (eval scoring rules, T-04)")
struct EvalScorerSelfTests {

    static func scored() throws -> EvalScore {
        try EvalSelfTest.readAndScore(try EvalSelfTest.resultsRoot()).1
    }

    static func input(_ id: String) throws -> EvalInputScore {
        try #require(try scored().inputs.first { $0.inputID == id })
    }

    // MARK: - in01: everything right; existing-task items; proposed-room match through an alternate

    @Test("AC-M2-14 (in01): all three items found and correct; a proposed room matches a new room's alternate after name folding")
    func in01() throws {
        let s = try Self.input("in01")
        // Draft text (title keywords, then new sourcePhrase keywords): d1 "Service the AC" + "The AC needs servicing"
        // → [service, ac, servicing]; overlap with g01-ac's groups = 3.
        #expect(s.draftText[1] == ["service", "ac", "servicing"])
        #expect(s.pairings == [
            EvalPairing(draftID: 1, goldenKey: "g01-ac", overlap: 3),
            EvalPairing(draftID: 2, goldenKey: "g01-pods", overlap: 2),
            EvalPairing(draftID: 3, goldenKey: "g01-balcony", overlap: 2),
        ])
        #expect(s.notFound.isEmpty && s.extras.isEmpty)
        // Room scoring: g01-balcony expects new("Balcony", [terrace, deck]); the draft is proposed("the Terrace"), which
        // name-folds to "terrace" = an alternate → correct.
        #expect(s.items.allSatisfy { $0.found && $0.kindCorrect && $0.roomCorrect && $0.effortCorrect
            && $0.criticalCorrect && $0.deepCleanCorrect && $0.weatherCorrect })
        // Best targets: d1 → seeded t-ac (3), d2 → seeded t-pods (2), d3 → golden g01-balcony (2). Committed [3], so
        // c(g01-balcony) = 1 and nothing is a duplicate.
        #expect(s.bestTargets.map(\.target) == [.seeded("t-ac"), .seeded("t-pods"), .golden("g01-balcony")])
        #expect(s.committedCounts == [.golden("g01-balcony"): 1])
        #expect(s.duplicatesCreated == 0 && s.falseMerges.isEmpty)
    }

    // MARK: - in02: a false merge; a not-found item; last attempt scored

    @Test("AC-M2-14 (in02): a false merge — a create item whose only draft was marked as a duplicate and nothing was committed")
    func in02FalseMerge() throws {
        let s = try Self.input("in02")
        // Device-run rules: the last attempt is scored (attempt 2; attempt 1's "Clean the over" is ignored).
        #expect(s.attempt == 2 && s.attemptsInFile == 2)
        #expect(s.draftText[1] == ["clean", "oven"])
        // d1 is marked ofExisting(t-mop) and so is still primary; it pairs with g02-oven (overlap 2).
        #expect(s.pairings == [EvalPairing(draftID: 1, goldenKey: "g02-oven", overlap: 2)])
        // g02-mirror has no draft: not found, and wrong in every field.
        #expect(s.notFound == ["g02-mirror"])
        let mirror = try #require(s.items.first { $0.goldenKey == "g02-mirror" })
        #expect(!mirror.kindCorrect && !mirror.roomCorrect && !mirror.effortCorrect && !mirror.criticalCorrect
            && !mirror.deepCleanCorrect && !mirror.weatherCorrect)
        // Best target of d1 is golden g02-oven (t-mop needs "mop", so it is not satisfied). d1 is marked and c(g02-oven)
        // = 0 → g02-oven is a false merge.
        #expect(s.bestTargets.map(\.target) == [.golden("g02-oven")])
        #expect(s.falseMerges == ["g02-oven"])
        #expect(s.duplicatesCreated == 0 && s.committedCount == 0)
    }

    // MARK: - in03: duplicates created; extras; ofDraft drafts are not primary

    @Test("AC-M2-14 (in03): duplicates created — two commits of one seeded chore and two of one create item; extras; an ofDraft draft is not primary")
    func in03DuplicatesCreated() throws {
        let s = try Self.input("in03")
        // All four primary pairs have overlap 2. Order: golden order (g03-pods before g03-towels), then draftID:
        // (1,pods) (2,pods) (3,towels) (4,towels). Greedy → d1–g03-pods, d3–g03-towels; d2 and d4 are extra.
        // d5 is ofDraft(3), so it is not primary: neither paired nor extra.
        #expect(s.pairings == [
            EvalPairing(draftID: 1, goldenKey: "g03-pods", overlap: 2),
            EvalPairing(draftID: 3, goldenKey: "g03-towels", overlap: 2),
        ])
        #expect(s.extras == [2, 4])
        // Best targets: d1, d2 → seeded t-pods; d3, d4, d5 → golden g03-towels. Committed [1, 2, 3, 4]:
        // c(t-pods) = 2, c(g03-towels) = 2. Duplicates created = max(0, 2 − 1) + 2 = 3.
        #expect(s.bestTargets.map(\.target) == [.seeded("t-pods"), .seeded("t-pods"), .golden("g03-towels"),
                                                .golden("g03-towels"), .golden("g03-towels")])
        #expect(s.committedCounts == [.seeded("t-pods"): 2, .golden("g03-towels"): 2])
        #expect(s.duplicatesCreated == 3)
        // d5 is marked and its best target is g03-towels, but c(g03-towels) = 2 > 0 → not a false merge.
        #expect(s.falseMerges.isEmpty)
    }

    // MARK: - in04: a tie in matching

    @Test("AC-M2-14 (in04): a tie in matching — equal overlap goes to golden order, then the lower draftID")
    func in04TieInMatching() throws {
        let s = try Self.input("in04")
        // Both drafts satisfy both items with overlap 2. Sorted by golden order then draftID:
        // (1,kitchen) (2,kitchen) (1,bathroom) (2,bathroom). Greedy → d1–g04-kitchen, d2–g04-bathroom.
        #expect(s.pairings == [
            EvalPairing(draftID: 1, goldenKey: "g04-kitchen", overlap: 2),
            EvalPairing(draftID: 2, goldenKey: "g04-bathroom", overlap: 2),
        ])
        // d1 is linked to the bathroom and d2 to the kitchen, so both rooms are wrong under this pairing (a scorer that
        // broke the tie by the higher draftID would pair them the other way and score both rooms right).
        #expect(s.items.map(\.roomCorrect) == [false, false])
        #expect(s.items.map(\.kindCorrect) == [true, true])
        // Best target tie (equal overlap, both golden) → the lower key, "g04-bathroom" < "g04-kitchen", for both
        // drafts. Both committed → c(g04-bathroom) = 2 → 1 duplicate created; g04-kitchen has c = 0 but no marked
        // draft, so it is not a false merge. (Open question WI-M2-15 Q1 for the Tester: two items with identical
        // match groups in one input are always counted this way.)
        #expect(s.bestTargets.map(\.target) == [.golden("g04-bathroom"), .golden("g04-bathroom")])
        #expect(s.duplicatesCreated == 1 && s.falseMerges.isEmpty)
    }

    // MARK: - in05: overlap order, best-target ties, sourcePhrase, validity

    @Test("AC-M2-14 (in05): higher overlap wins the pairing; best-target ties go golden-first, then the lower seeded key")
    func in05Ties() throws {
        let s = try Self.input("in05")
        // d4 "Mop the hallway floors, mop the floor" → [mop, hallway, floors, floor], overlap 3 with g05-mop; it is
        // taken before d1 "Mop the floor" (overlap 2), even though d1 has the lower draftID. d1 is extra.
        // d3 "Sort it" + phrase "sort it out, the garage shelves" → [sort, garage, shelves], overlap 3 with g05-garage
        // (the item is satisfied only through the sourcePhrase).
        #expect(s.draftText[3] == ["sort", "garage", "shelves"])
        #expect(s.pairings == [
            EvalPairing(draftID: 4, goldenKey: "g05-mop", overlap: 3),
            EvalPairing(draftID: 3, goldenKey: "g05-garage", overlap: 3),
            EvalPairing(draftID: 2, goldenKey: "g05-plants", overlap: 2),
        ])
        #expect(s.extras == [1])
        // Best targets: d1 and d4 tie between golden g05-mop and seeded t-mop → golden. d2 ties between seeded
        // t-plants-a and t-plants-b → the lower key t-plants-a. d3 → g05-garage.
        #expect(s.bestTargets.map(\.target) == [.golden("g05-mop"), .seeded("t-plants-a"), .golden("g05-garage"),
                                                .golden("g05-mop")])
        // c(g05-mop) = 2, c(t-plants-a) = 1, c(g05-garage) = 1 → duplicates = (2 − 1) + 1 = 2.
        #expect(s.duplicatesCreated == 2)
        // Validity: d3's window is empty (end = start) → windowEndNotAfterStart; the others pass.
        #expect(s.invalidDrafts == [3: .windowEndNotAfterStart])
        #expect(s.items.allSatisfy { $0.found && $0.roomCorrect && $0.kindCorrect && $0.effortCorrect })
    }

    // MARK: - in06: calm words; wrong fields; fresh household

    @Test("AC-M2-14 (in06): introduced banned tokens in a title and a proposed room name; a word the user said is kept; wrong fields")
    func in06CalmWordsAndFields() throws {
        let s = try Self.input("in06")
        // The transcript says "late", so "late" in d1's title is not introduced. "overdue" (d2 title) and "missed"
        // (d3 proposed room name) are not in the transcript → 2 introduced.
        #expect(s.introducedTokens == [
            EvalIntroducedToken(draftID: 2, field: .title, token: "overdue"),
            EvalIntroducedToken(draftID: 3, field: .proposedRoomName, token: "missed"),
        ])
        let byKey = Dictionary(uniqueKeysWithValues: s.items.map { ($0.goldenKey, $0) })
        // g06-bill (d1): weather-dependent set but not expected → only weather wrong.
        let bill = try #require(byKey["g06-bill"])
        #expect(bill.kindCorrect && bill.roomCorrect && bill.effortCorrect && bill.criticalCorrect && bill.deepCleanCorrect
            && !bill.weatherCorrect)
        // g06-oven (d2): kind restock (expected oneOff), effort high (normal), critical true (false) → three wrong.
        let oven = try #require(byKey["g06-oven"])
        #expect(!oven.kindCorrect && oven.roomCorrect && !oven.effortCorrect && !oven.criticalCorrect
            && oven.deepCleanCorrect && oven.weatherCorrect)
        // g06-tiles (d3): expected existing(bathroom) but the draft proposes a new room → room wrong; deep clean not set.
        let tiles = try #require(byKey["g06-tiles"])
        #expect(tiles.kindCorrect && !tiles.roomCorrect && tiles.effortCorrect && !tiles.deepCleanCorrect)
        // Household state: every input starts fresh. in02 also had an oven item; here g06-oven is committed once →
        // c = 1, no duplicate (nothing from in02 carries over).
        #expect(s.duplicatesCreated == 0)
        #expect(s.committedCounts[.golden("g06-oven")] == 1)
    }

    @Test("AC-M2-14 (in07): noModel with no draft — the item is not found and counts as wrong in every field")
    func in07NoModel() throws {
        let s = try Self.input("in07")
        #expect(s.outcome == .noModel && s.ttfiMs == nil && s.draftCount == 0)
        #expect(s.notFound == ["g07-sweep"] && s.items.map(\.found) == [false])
    }

    // MARK: - Totals ("Denominators")

    @Test("AC-M2-14: totals over all inputs — denominators over golden items, not-found items wrong in every field")
    func totals() throws {
        let t = try Self.scored().totals
        // N = 3 + 2 + 2 + 2 + 3 + 3 + 1 = 16. Found = 3 + 1 + 2 + 2 + 3 + 3 + 0 = 14.
        #expect(t.goldenItems == 16 && t.inputsScored == 7 && t.inputsAbsent.isEmpty)
        #expect(t.correct[.segmentation] == 14)
        // kind: 14 found − g06-oven = 13. room: 14 − in04 (2) − g06-tiles = 11. effort: 14 − g06-oven = 13.
        // critical: 14 − g06-oven = 13. deepClean: 14 − g06-tiles = 13. weather: 14 − g06-bill = 13.
        #expect(t.correct[.kind] == 13 && t.correct[.room] == 11 && t.correct[.effort] == 13)
        #expect(t.correct[.critical] == 13 && t.correct[.deepClean] == 13 && t.correct[.weatherDependent] == 13)
        // Extras: in03 (2) + in05 (1) = 3. Drafts: 3 + 1 + 5 + 2 + 4 + 3 + 0 = 18, one not valid.
        #expect(t.extras == 3 && t.drafts == 18 && t.validDrafts == 17)
        // Introduced banned tokens 2; duplicates created 0 + 0 + 3 + 1 + 2 + 0 + 0 = 6; false merges 1 (g02-oven).
        #expect(t.introducedTokens == 2 && t.duplicatesCreated == 6 && t.falseMerges == 1)
    }

    // MARK: - Rule units (each rule on its own, hand-built values)

    static func draft(_ id: Int, _ title: String, phrase: String? = nil, room: DraftRecord.RoomRecord = .none,
                      duplicate: DraftRecord.DuplicateRecord = .none) -> DraftRecord {
        DraftRecord(draftID: id, title: title, kind: .oneOff, room: room, effort: .normal, isCritical: false,
                    isDeepClean: false, isWeatherDependent: false, allowedDayparts: Daypart.defaultAllowed,
                    allowedWeekdays: Set(Weekday.allCases), windowStart: EvalInstant(millisecondsSince1970: 0),
                    windowEnd: EvalInstant(millisecondsSince1970: 1000), recurrenceIntervalDays: nil,
                    sourcePhrase: phrase, duplicate: duplicate)
    }

    @Test("Draft text: keywords of the title joined with the sourcePhrase's, distinct, stop words dropped, folded")
    func draftTextRule() {
        #expect(EvalScorer.draftText(of: Self.draft(1, "We're out of DISH pods", phrase: "dish pods, the dishwasher"))
            == ["dish", "pods", "dishwasher"])
        #expect(EvalScorer.draftText(of: Self.draft(1, "Café’s AC")) == ["cafe", "ac"])
    }

    @Test("Satisfies: at least one token from each match group; overlap counts draft tokens in any group")
    func satisfiesRule() {
        let groups: [Set<String>] = [["ac", "aircon"], ["service", "servicing"]]
        #expect(EvalScorer.satisfies(["service", "ac", "servicing"], groups: groups))
        #expect(!EvalScorer.satisfies(["service", "servicing"], groups: groups))
        #expect(EvalScorer.overlap(["service", "ac", "servicing", "summer"], groups: groups) == 3)
        #expect(EvalScorer.overlap(["summer"], groups: groups) == 0)
    }

    @Test("Room scoring, every case", arguments: [
        (DraftRecord.RoomRecord.existing(roomKey: "kitchen"), EvalGoldenItem.ExpectedRoom.existing(roomKey: "kitchen"), true),
        (.existing(roomKey: "bathroom"), .existing(roomKey: "kitchen"), false),
        (.proposed(name: "kitchen"), .existing(roomKey: "kitchen"), false),
        (.none, .existing(roomKey: "kitchen"), false),
        (.proposed(name: "  The  BALCONY "), .new(name: "Balcony", alternates: []), true),
        (.proposed(name: "my Terrace"), .new(name: "Balcony", alternates: ["terrace"]), true),
        (.proposed(name: "Balconies"), .new(name: "Balcony", alternates: []), false),
        (.existing(roomKey: "balcony"), .new(name: "Balcony", alternates: []), false),
        (.none, .new(name: "Balcony", alternates: []), false),
        (.none, .none, true),
        (.proposed(name: "Garage"), .none, false),
        (.existing(roomKey: "kitchen"), .none, false),
    ])
    func roomRule(room: DraftRecord.RoomRecord, expected: EvalGoldenItem.ExpectedRoom, correct: Bool) {
        #expect(EvalScorer.roomIsCorrect(room, expected: expected) == correct)
    }

    @Test("⌈p × N⌉: N = 50 gives 48, 45, 43 (the brief's examples); fractions round up")
    func requiredCounts() {
        #expect(EvalMetric.segmentation.requiredCount(of: 50) == 48)
        #expect(EvalMetric.room.requiredCount(of: 50) == 45)
        #expect(EvalMetric.effort.requiredCount(of: 50) == 43)
        #expect(EvalMetric.kind.requiredCount(of: 51) == 49)     // 48.45 → 49
        #expect(EvalMetric.room.requiredCount(of: 60) == 54)     // exact
        #expect(EvalMetric.effort.requiredCount(of: 61) == 52)   // 51.85 → 52
        #expect(EvalMetric.allCases.map(\.requiredPercent) == [95, 95, 90, 85, 95, 95, 95])
    }

    @Test("Best target: no satisfied target gives none; higher overlap beats golden-first")
    func bestTargetRule() {
        let targets: [(EvalTarget, [Set<String>])] = [
            (.golden("g-b"), [["oven"]]),
            (.seeded("t-a"), [["oven"], ["clean"]]),
        ]
        let higher = EvalScorer.bestTarget(for: Self.draft(1, "clean oven"), text: ["clean", "oven"], targets: targets)
        #expect(higher.target == .seeded("t-a") && higher.overlap == 2)
        let none = EvalScorer.bestTarget(for: Self.draft(2, "mop"), text: ["mop"], targets: targets)
        #expect(none.target == nil)
        #expect(EvalScorer.precedes(.golden("z"), .seeded("a")) && !EvalScorer.precedes(.seeded("a"), .golden("z")))
        #expect(EvalScorer.precedes(.seeded("t-plants-a"), .seeded("t-plants-b")))
    }

    @Test("Best target counts completed seeded tasks out (they are not targets)")
    func completedNotTarget() throws {
        // t-bins is completed in the self-test household; a committed draft for it is not a duplicate.
        var root = try EvalSelfTest.resultsRoot()
        root = root.setting("/inputs/7", to: try #require(root.value(at: "/inputs/7"))
            .setting("/outcome", to: .string("completed"))
            .setting("/drafts/0", to: try EvalSelfTest.draftJSON(id: 1, title: "Take out the bins"))
            .setting("/committed", to: .array([.integer(1)]))
            .setting("/ttfiMs", to: .integer(300))
            .setting("/events", to: .array([
                .object([.init("type", .string("emitted")), .init("draftID", .integer(1)), .init("tMs", .integer(300))]),
                .object([.init("type", .string("finished")), .init("draftID", .null), .init("tMs", .integer(500))]),
            ]))
            .setting("/totalMs", to: .integer(500)))
        let s = try #require(try EvalSelfTest.readAndScore(root).1.inputs.first { $0.inputID == "in07" })
        #expect(s.bestTargets.map(\.target) == [nil])
        #expect(s.duplicatesCreated == 0 && s.extras == [1])
    }

    @Test("Absent inputs are reported and not scored")
    func absentInputs() throws {
        var root = try EvalSelfTest.resultsRoot()
        root = root.setting("/inputs/7", to: nil)
        let totals = try EvalSelfTest.readAndScore(root).1.totals
        #expect(totals.inputsAbsent == ["in07"] && totals.inputsScored == 6 && totals.goldenItems == 15)
    }

    // MARK: - Log ("Output")

    @Test("Output: the scorer log has per-input and total counts for every metric, each pairing and each best target")
    func log() throws {
        let report = try EvalScorer.run(try EvalSelfTest.request(
            try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot())))
        let log = report.log
        #expect(log.contains("pairing: draft 4 <-> g05-mop (overlap 3)"))
        #expect(log.contains("best target: draft 2 -> seeded t-plants-a (overlap 2)"))
        #expect(log.contains("best target: draft 1 -> golden g02-oven (overlap 2)"))
        #expect(log.contains("duplicates created: 3; false merges: 0"))
        #expect(log.contains("false merges: 1 (g02-oven)"))
        #expect(log.contains("item g02-mirror: not found"))
        #expect(log.contains("introduced banned tokens: 2 (draft 2 title overdue, draft 3 proposedRoomName missed)"))
        for metric in EvalMetric.allCases { #expect(log.contains("totals: \(metric.rawValue) ")) }
        #expect(log.contains("totals: room 11 of 16 (required 15 at 90%)"))
        #expect(log.hasSuffix("profile info: INFO (no pass rule)\n"))
        // Deterministic: the same file gives the same bytes.
        let again = try EvalScorer.run(try EvalSelfTest.request(
            try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot())))
        #expect(again.log == log)
        // The committed scorer log of the self-test file (the Tester's re-score compares with it, AC-M2-14).
        #expect(log == String(decoding: try EvalSelfTest.selfTest("results-selftest-1.score.log"), as: UTF8.self))
        print(log)
    }
}

extension EvalSelfTest {
    /// A plain valid draft as JSON (oneOff, no room, not marked).
    static func draftJSON(id: Int, title: String) throws -> EvalJSON {
        let record = DraftRecord(draftID: id, title: title, kind: .oneOff, room: .none, effort: .normal,
                                 isCritical: false, isDeepClean: false, isWeatherDependent: false,
                                 allowedDayparts: Daypart.defaultAllowed, allowedWeekdays: Set(Weekday.allCases),
                                 windowStart: EvalInstant(millisecondsSince1970: 0),
                                 windowEnd: EvalInstant(millisecondsSince1970: 86_400_000), recurrenceIntervalDays: nil,
                                 sourcePhrase: nil, duplicate: .none)
        return try EvalJSONReader.parse(try CanonicalJSONWriter.data(record.canonicalJSON))
    }
}
