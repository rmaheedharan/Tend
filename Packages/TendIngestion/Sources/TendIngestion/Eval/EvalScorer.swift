// The eval scorer (brief "Eval scoring rules", binding for AC-M2-11, 14, 15, 17, 25, 26; T-04; rubric Q3). FR-A1,
// UX-3 (calm words), plan WI-M2-15.
//
// Pure: a checked results file and the fixtures in, a score value out (AC-M2-09 Rule 1, T-26). `tend-eval-score`
// (Tools/TendTools) reads the files and prints. Each rule below is quoted by its brief heading in the code that does
// it, and each has a hand-built self-test (`EvalScorerSelfTests`). Readings where the brief leaves a choice are
// dev-notes WI-M2-15 S1–S6; the rules themselves are not changed.

import Foundation
import TendCore

// MARK: - Score values

/// A scoring target (brief "Best target"): a golden item of the input, or a seeded task.
public enum EvalTarget: Sendable, Hashable, CustomStringConvertible {
    case golden(String)
    case seeded(String)

    public var key: String {
        switch self {
        case let .golden(key), let .seeded(key): key
        }
    }

    public var description: String {
        switch self {
        case let .golden(key): "golden \(key)"
        case let .seeded(key): "seeded \(key)"
        }
    }
}

/// One (primary draft, golden item) pair taken by the one-to-one matching.
public struct EvalPairing: Sendable, Hashable {
    public var draftID: Int
    public var goldenKey: String
    public var overlap: Int
}

/// The best target of one draft (many-to-one).
public struct EvalBestTarget: Sendable, Hashable {
    public var draftID: Int
    public var target: EvalTarget?
    public var overlap: Int
}

/// The field results of one golden item. Not-found items count as wrong in every field (brief "Denominators").
public struct EvalItemResult: Sendable, Hashable {
    public var goldenKey: String
    public var draftID: Int?
    public var kindCorrect: Bool
    public var roomCorrect: Bool
    public var effortCorrect: Bool
    public var criticalCorrect: Bool
    public var deepCleanCorrect: Bool
    public var weatherCorrect: Bool

    public var found: Bool { draftID != nil }
}

/// A banned token in a title or proposed room name that does not occur in the input (brief "Calm words"; AC-M2-12).
public struct EvalIntroducedToken: Sendable, Hashable {
    public enum Field: String, Sendable, Hashable {
        case title
        case proposedRoomName
    }

    public var draftID: Int
    public var field: Field
    public var token: String
}

/// The score of the scored (last) attempt of one input.
public struct EvalInputScore: Sendable, Hashable {
    public var inputID: String
    public var mode: EvalInputMode
    public var attempt: Int
    public var attemptsInFile: Int
    public var route: EvalRoute
    public var outcome: EvalOutcome
    public var ttfiMs: Int?
    public var totalMs: Int
    /// The draft text of each draft (brief "Draft text"), by draft ID.
    public var draftText: [Int: [String]]
    public var pairings: [EvalPairing]
    /// Golden items in golden order.
    public var items: [EvalItemResult]
    public var notFound: [String]
    public var extras: [Int]
    public var bestTargets: [EvalBestTarget]
    /// c(x) for every target with c(x) > 0.
    public var committedCounts: [EvalTarget: Int]
    public var duplicatesCreated: Int
    public var falseMerges: [String]
    public var draftCount: Int
    public var invalidDrafts: [Int: TaskInvariantViolation]
    public var introducedTokens: [EvalIntroducedToken]
    public var committedCount: Int
    public var cloudRequests: [EvalResultsFileV1.CloudRequestRecord]

    public var goldenCount: Int { items.count }
}

/// The fields scored per found item (brief "Denominators"; rubric Q3 percentages).
public enum EvalMetric: String, Sendable, Hashable, CaseIterable {
    case segmentation
    case kind
    case room
    case effort
    case critical
    case deepClean
    case weatherDependent

    /// Rubric Q3: segmentation ≥ 95%, kind ≥ 95%, room ≥ 90%, effort ≥ 85%, each flag ≥ 95%.
    public var requiredPercent: Int {
        switch self {
        case .room: 90
        case .effort: 85
        case .segmentation, .kind, .critical, .deepClean, .weatherDependent: 95
        }
    }

    /// ⌈p × N⌉ in integers (brief "Denominators": with N = 50, 95% → 48, 90% → 45, 85% → 43).
    public func requiredCount(of total: Int) -> Int {
        (requiredPercent * total + 99) / 100
    }

    func isCorrect(_ item: EvalItemResult) -> Bool {
        switch self {
        case .segmentation: item.found
        case .kind: item.kindCorrect
        case .room: item.roomCorrect
        case .effort: item.effortCorrect
        case .critical: item.criticalCorrect
        case .deepClean: item.deepCleanCorrect
        case .weatherDependent: item.weatherCorrect
        }
    }
}

/// Totals over every scored input.
public struct EvalTotals: Sendable, Hashable {
    /// N: golden items over the scored inputs.
    public var goldenItems: Int
    public var correct: [EvalMetric: Int]
    public var extras: Int
    public var drafts: Int
    public var validDrafts: Int
    public var introducedTokens: Int
    public var duplicatesCreated: Int
    public var falseMerges: Int
    public var inputsScored: Int
    /// Fixture inputs with no attempt in the file.
    public var inputsAbsent: [String]
}

public struct EvalScore: Sendable, Hashable {
    public var inputs: [EvalInputScore]
    public var totals: EvalTotals
}

// MARK: - Scoring

public enum EvalScorer {

    /// Scores every fixture input that has an attempt in the file, in `inputs.json` order.
    public static func score(_ file: EvalResultsFileV1, fixtures: EvalFixtures) -> EvalScore {
        var scores: [EvalInputScore] = []
        var absent: [String] = []
        for input in fixtures.inputs {
            let attempts = file.inputs.filter { $0.inputID == input.id }
            // Device-run rules: "Every attempt is kept in the results file, and the last attempt is the one scored."
            guard let last = attempts.max(by: { $0.attempt < $1.attempt }) else {
                absent.append(input.id)
                continue
            }
            scores.append(scoreInput(last, attemptsInFile: attempts.count, input: input, fixtures: fixtures))
        }
        var correct: [EvalMetric: Int] = [:]
        for metric in EvalMetric.allCases {
            correct[metric] = scores.reduce(0) { $0 + $1.items.filter(metric.isCorrect).count }
        }
        let totals = EvalTotals(
            goldenItems: scores.reduce(0) { $0 + $1.goldenCount },
            correct: correct,
            extras: scores.reduce(0) { $0 + $1.extras.count },
            drafts: scores.reduce(0) { $0 + $1.draftCount },
            validDrafts: scores.reduce(0) { $0 + $1.draftCount - $1.invalidDrafts.count },
            introducedTokens: scores.reduce(0) { $0 + $1.introducedTokens.count },
            duplicatesCreated: scores.reduce(0) { $0 + $1.duplicatesCreated },
            falseMerges: scores.reduce(0) { $0 + $1.falseMerges.count },
            inputsScored: scores.count,
            inputsAbsent: absent
        )
        return EvalScore(inputs: scores, totals: totals)
    }

    static func scoreInput(
        _ entry: EvalResultsFileV1.InputAttempt, attemptsInFile: Int, input: EvalFixtureInput, fixtures: EvalFixtures
    ) -> EvalInputScore {
        // "Household state": every input starts from a fresh copy of the seeded household, so only this input's golden
        // items and the seeded tasks are used; nothing carries over from another input.
        let golden = fixtures.golden.filter { $0.inputID == input.id }
        let drafts = entry.drafts.sorted { $0.draftID < $1.draftID }
        let text = Dictionary(uniqueKeysWithValues: drafts.map { ($0.draftID, draftText(of: $0)) })

        // "Segmentation matching (one-to-one)".
        let pairings = segmentationPairs(drafts: drafts, golden: golden, text: text)
        let pairedDraft = Dictionary(uniqueKeysWithValues: pairings.map { ($0.goldenKey, $0.draftID) })
        let paired = Set(pairings.map(\.draftID))
        let primary = drafts.filter(isPrimary)
        let extras = primary.map(\.draftID).filter { !paired.contains($0) }
        let byID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.draftID, $0) })
        let items = golden.map { item -> EvalItemResult in
            guard let id = pairedDraft[item.key], let draft = byID[id] else {
                return EvalItemResult(goldenKey: item.key, draftID: nil, kindCorrect: false, roomCorrect: false,
                                      effortCorrect: false, criticalCorrect: false, deepCleanCorrect: false,
                                      weatherCorrect: false)
            }
            return EvalItemResult(
                goldenKey: item.key, draftID: id, kindCorrect: draft.kind == item.kind,
                roomCorrect: roomIsCorrect(draft.room, expected: item.room), effortCorrect: draft.effort == item.effort,
                criticalCorrect: draft.isCritical == item.isCritical, deepCleanCorrect: draft.isDeepClean == item.isDeepClean,
                weatherCorrect: draft.isWeatherDependent == item.isWeatherDependent
            )
        }

        // "Best target (many-to-one, for duplicates)".
        let targets = targets(golden: golden, tasks: fixtures.tasks)
        let best = drafts.map { bestTarget(for: $0, text: text[$0.draftID] ?? [], targets: targets) }
        let bestByDraft = Dictionary(uniqueKeysWithValues: best.map { ($0.draftID, $0.target) })

        // "Duplicates created": c(x) counts committed drafts whose best target is x.
        var counts: [EvalTarget: Int] = [:]
        for id in Set(entry.committed) {
            if let target = bestByDraft[id] ?? nil { counts[target, default: 0] += 1 }
        }
        let createKeys = golden.filter { $0.expect == .create }.map(\.key)
        var duplicatesCreated = 0
        for key in createKeys { duplicatesCreated += max(0, (counts[.golden(key)] ?? 0) - 1) }
        for task in fixtures.tasks where !task.isCompleted { duplicatesCreated += counts[.seeded(task.key)] ?? 0 }

        // "False merges": a create item g with a marked draft whose best target is g, and c(g) = 0. Each g once.
        let falseMerges = createKeys.filter { key in
            (counts[.golden(key)] ?? 0) == 0
                && drafts.contains { $0.duplicate.isMarked && bestByDraft[$0.draftID] == .golden(key) }
        }

        // "Validity" counts all emitted drafts (the M1 invariants).
        var invalid: [Int: TaskInvariantViolation] = [:]
        for draft in drafts { if let violation = draft.invariantViolation { invalid[draft.draftID] = violation } }

        // "Calm words" counts all titles and proposed room names (0 introduced banned tokens). Introduced means the
        // token does not occur anywhere in the whole input (AC-M2-12): the typed text, or the final transcript.
        let inputText = entry.mode == .voice ? (entry.transcript ?? "") : input.text
        let said = BannedTokens.tokens(in: inputText)
        var introduced: [EvalIntroducedToken] = []
        for draft in drafts {
            for match in BannedTokens.matches(in: draft.title) where !said.contains(match.token) {
                introduced.append(EvalIntroducedToken(draftID: draft.draftID, field: .title, token: match.token))
            }
            if case let .proposed(name) = draft.room {
                for match in BannedTokens.matches(in: name) where !said.contains(match.token) {
                    introduced.append(EvalIntroducedToken(draftID: draft.draftID, field: .proposedRoomName,
                                                          token: match.token))
                }
            }
        }

        return EvalInputScore(
            inputID: input.id, mode: entry.mode, attempt: entry.attempt, attemptsInFile: attemptsInFile,
            route: entry.route, outcome: entry.outcome, ttfiMs: entry.ttfiMs, totalMs: entry.totalMs, draftText: text,
            pairings: pairings, items: items, notFound: items.filter { !$0.found }.map(\.goldenKey), extras: extras,
            bestTargets: best, committedCounts: counts, duplicatesCreated: duplicatesCreated, falseMerges: falseMerges,
            draftCount: drafts.count, invalidDrafts: invalid, introducedTokens: introduced,
            committedCount: Set(entry.committed).count, cloudRequests: entry.cloudRequests
        )
    }

    // MARK: Rules

    /// "Draft text": the keywords of the final `title`, joined with the keywords of its `sourcePhrase`. Read as the
    /// distinct tokens of both (S1): title keywords first, then phrase keywords not already present.
    public static func draftText(of draft: DraftRecord) -> [String] {
        var tokens = Keywords.of(draft.title)
        for token in Keywords.of(draft.sourcePhrase ?? "") where !tokens.contains(token) { tokens.append(token) }
        return tokens
    }

    /// "A draft satisfies a target when the draft text holds at least one token from each of the target's match
    /// groups."
    public static func satisfies(_ text: [String], groups: [Set<String>]) -> Bool {
        groups.allSatisfy { group in text.contains(where: group.contains) }
    }

    /// "Overlap(d, g) is the number of draft-text tokens that appear in any of g's groups."
    public static func overlap(_ text: [String], groups: [Set<String>]) -> Int {
        text.filter { token in groups.contains { $0.contains(token) } }.count
    }

    /// "A draft is primary when it is not marked `ofDraft`."
    static func isPrimary(_ draft: DraftRecord) -> Bool {
        if case .ofDraft = draft.duplicate { return false }
        return true
    }

    /// "Form every (primary draft, golden item) pair where the draft satisfies the item. Sort the pairs by overlap
    /// descending, then golden order ascending, then `draftID` ascending. Take pairs greedily, skipping any pair whose
    /// draft or item is already taken."
    static func segmentationPairs(
        drafts: [DraftRecord], golden: [EvalGoldenItem], text: [Int: [String]]
    ) -> [EvalPairing] {
        var candidates: [(pair: EvalPairing, goldenOrder: Int)] = []
        for draft in drafts where isPrimary(draft) {
            let tokens = text[draft.draftID] ?? []
            for (order, item) in golden.enumerated() where satisfies(tokens, groups: item.matchGroups) {
                candidates.append((EvalPairing(draftID: draft.draftID, goldenKey: item.key,
                                               overlap: overlap(tokens, groups: item.matchGroups)), order))
            }
        }
        candidates.sort { a, b in
            if a.pair.overlap != b.pair.overlap { return a.pair.overlap > b.pair.overlap }
            if a.goldenOrder != b.goldenOrder { return a.goldenOrder < b.goldenOrder }
            return a.pair.draftID < b.pair.draftID
        }
        var takenDrafts: Set<Int> = []
        var takenItems: Set<String> = []
        var result: [EvalPairing] = []
        for candidate in candidates
        where !takenDrafts.contains(candidate.pair.draftID) && !takenItems.contains(candidate.pair.goldenKey) {
            takenDrafts.insert(candidate.pair.draftID)
            takenItems.insert(candidate.pair.goldenKey)
            result.append(candidate.pair)
        }
        return result
    }

    /// "Room scoring": `existing(roomKey)` only when linked to that room; `new(name, alternates)` only when the draft is
    /// `proposed(x)` and the name-folded x equals the name-folded name or an alternate (linking it to an existing room
    /// is wrong); `none` only when the draft room is `none`.
    public static func roomIsCorrect(_ room: DraftRecord.RoomRecord, expected: EvalGoldenItem.ExpectedRoom) -> Bool {
        switch (expected, room) {
        case let (.existing(expectedKey), .existing(key)): return key == expectedKey
        case let (.new(name, alternates), .proposed(x)):
            let folded = TextFolding.foldName(x)
            return ([name] + alternates).contains { TextFolding.foldName($0) == folded }
        case (.none, .none): return true
        default: return false
        }
    }

    /// "The targets of an input are its `create` golden items plus the seeded tasks that are not `completed`."
    static func targets(golden: [EvalGoldenItem], tasks: [EvalSeededTask]) -> [(EvalTarget, [Set<String>])] {
        golden.filter { $0.expect == .create }.map { (.golden($0.key), $0.matchGroups) }
            + tasks.filter { !$0.isCompleted }.map { (.seeded($0.key), $0.matchGroups) }
    }

    /// "For each draft, its best target is the target it satisfies with the highest overlap. Ties go to golden items
    /// before seeded tasks, then to the lower key. A draft that satisfies no target has no best target." Lower key is
    /// ascending UTF-8 byte order (S3).
    static func bestTarget(
        for draft: DraftRecord, text: [String], targets: [(EvalTarget, [Set<String>])]
    ) -> EvalBestTarget {
        var best: EvalBestTarget = EvalBestTarget(draftID: draft.draftID, target: nil, overlap: 0)
        for (target, groups) in targets where satisfies(text, groups: groups) {
            let value = overlap(text, groups: groups)
            guard let current = best.target else {
                best = EvalBestTarget(draftID: draft.draftID, target: target, overlap: value)
                continue
            }
            if value > best.overlap || (value == best.overlap && precedes(target, current)) {
                best = EvalBestTarget(draftID: draft.draftID, target: target, overlap: value)
            }
        }
        return best
    }

    /// Golden before seeded, then the lower key.
    static func precedes(_ a: EvalTarget, _ b: EvalTarget) -> Bool {
        switch (a, b) {
        case (.golden, .seeded): return true
        case (.seeded, .golden): return false
        default: return TextFolding.utf8Precedes(a.key, b.key)
        }
    }
}
