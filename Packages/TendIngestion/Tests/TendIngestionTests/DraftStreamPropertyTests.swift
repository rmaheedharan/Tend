// AC-M2-05 property: seeded random snapshot scripts (fields out of order, items split across snapshots, titles
// growing, values changing after completion, shrinking snapshots, no-title items, normal finishes and throws) give
// exactly the events of an independent oracle, and every structural rule of the brief's "draft stream events" holds.
// FR-A1. Plan WI-M2-06.
//
// Oracle independence: the assembler is incremental (it keeps a completed count and walks forward per snapshot). The
// oracle is a timeline: it first computes each item's completion step from the whole script (rules a, b, c), then
// builds the event list step by step from those completion steps. It shares only `DraftMapper.map` (the Q5 mapping,
// proven by AC-M2-01/02) and the injected duplicate check (a test double). It does not call
// `ItemSnapshot.hasValueForEveryField`; rule (a) is re-written field by field below. The re-mark rule (PO WI-M2-06
// ruling 5) is written as a fresh marking pass from the first changed draft, and the zero-draft `completed` (ruling 1)
// uses its own count of emitted events. Each script is also checked against the ruling 5 invariant.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

enum StreamOracle {
    /// Rule (a), written out independently: the nine schema fields, with a time hint counting once its anchor is set.
    static func everyField(_ item: ItemSnapshot) -> Bool {
        item.title != nil && item.kind != nil && item.roomName != nil && item.effort != nil
            && item.isCritical != nil && item.isDeepClean != nil && item.isWeatherDependent != nil
            && item.time?.anchor != nil && item.sourcePhrase != nil
    }

    enum Ending { case finish, stop(ModelStopReason) }

    static func events(snapshots: [[ItemSnapshot]], ending: Ending, mapper: DraftMapper,
                       check: any DraftDuplicateCheck, route: Route) -> [DraftStreamEvent] {
        let steps = snapshots.count
        // 1. Completion step of each item index (nil = never completes). Step `steps` is the normal finish.
        let maxItems = snapshots.map(\.count).max() ?? 0
        var completion: [Int?] = Array(repeating: nil, count: maxItems)
        for index in 0..<maxItems {
            for step in 0..<steps {
                let items = snapshots[step]
                let previousDone = index == 0 || (completion[index - 1].map { $0 <= step } ?? false)
                guard previousDone else { continue }
                if items.count > index + 1 || (items.count > index && everyField(items[index])) {
                    completion[index] = step
                    break
                }
            }
            if completion[index] == nil, case .finish = ending, let last = snapshots.last, index < last.count,
               index == 0 || completion[index - 1] != nil {
                completion[index] = steps
            }
        }
        // 2. Events, step by step.
        var events: [DraftStreamEvent] = []
        var current: [IngestionDraft] = []           // index = draftID - 1
        var itemOfDraft: [Int] = []                  // item index of each draft
        func complete(_ index: Int, from items: [ItemSnapshot]) {
            switch mapper.map(items[index], draftID: current.count + 1).outcome {
            case var .draft(draft):
                draft.duplicate = check.duplicate(of: draft, earlier: current)
                current.append(draft)
                itemOfDraft.append(index)
                events.append(.emitted(draft))
            case let .skipped(reason):
                events.append(.itemSkipped(reason))
            }
        }
        for step in 0..<steps {
            let items = snapshots[step]
            // Updates (PO WI-M2-06 ruling 5), written as "new contents, then a fresh marking pass from the first
            // changed draft": drafts below it keep their markers; every draft from it onward is marked against the
            // final versions of all lower drafts; each draft that differs in any field gets one `updated`.
            let contents: [IngestionDraft] = current.enumerated().map { k, old in
                let index = itemOfDraft[k]
                guard index < items.count, case var .draft(mapped) = mapper.map(items[index], draftID: k + 1).outcome
                else { return old }
                mapped.duplicate = old.duplicate
                return mapped
            }
            if let first = contents.indices.first(where: { contents[$0] != current[$0] }) {
                var next = Array(contents[..<first])
                for k in first..<contents.count {
                    var draft = contents[k]
                    draft.duplicate = check.duplicate(of: draft, earlier: next)
                    next.append(draft)
                }
                for (old, new) in zip(current, next) where old != new { events.append(.updated(new)) }
                current = next
            }
            for index in 0..<maxItems where completion[index] == step { complete(index, from: items) }
        }
        switch ending {
        case .finish:
            if let last = snapshots.last {
                for index in 0..<maxItems where completion[index] == steps { complete(index, from: last) }
            }
            // PO WI-M2-06 ruling 1, from an independent count of the emitted events.
            let emittedCount = events.filter { if case .emitted = $0 { true } else { false } }.count
            if emittedCount == 0 {
                let note = PlainNote.draft(for: mapper.input, now: mapper.now, resolver: mapper.resolver)
                events.append(.finished(.completed(route: route, input: mapper.input, plainNote: note)))
            } else {
                events.append(.finished(.completed(route: route)))
            }
        case let .stop(reason):
            let lastCount = snapshots.last?.count ?? 0
            let doneCount = completion.prefix(lastCount).filter { $0 != nil }.count
            if current.isEmpty {
                let note = PlainNote.draft(for: mapper.input, now: mapper.now, resolver: mapper.resolver)
                events.append(.finished(.noModel(route: route, reason: .stoppedBeforeFirstDraft(reason),
                                                 input: mapper.input, plainNote: note)))
            } else {
                events.append(.finished(.interrupted(
                    route: route, reason: reason,
                    discardedItem: doneCount < lastCount ? .stoppedBeforeComplete : nil, input: mapper.input)))
            }
        }
        return events
    }
}

/// Builds random scripts that look like a structured stream: items start in order, fields arrive in any order,
/// titles grow by prefixes, and some values change after completion.
struct ScriptGenerator {
    var g: SplitMix64

    static let titles = ["Buy dishwasher pods", "Service the AC", "Mop the kitchen floor", "Late water plants",
                         "Call the plumber", "Buy dishwasher pods", "   ", "Deep clean the balcony"]
    static let rooms = ["Kitchen", "garage", "the bathroom", ""]
    static let phrases = ["dishwasher pods", "mop the kitchen floor", "not in the input"]

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &g) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &g) < p }
    mutating func pick<T>(_ xs: [T]) -> T { xs[int(0...(xs.count - 1))] }

    /// A full item where each field is present with high probability (so rule (a) both fires and does not).
    mutating func finalItem() -> ItemSnapshot {
        ItemSnapshot(
            title: chance(0.9) ? pick(Self.titles) : nil,
            kind: chance(0.9) ? pick([.known(.oneOff), .known(.restock), .known(.recurring), .unrecognized("x")])
                              : nil,
            roomName: chance(0.8) ? pick(Self.rooms) : nil,
            effort: chance(0.9) ? pick([.known(.low), .known(.normal), .known(.high)]) : nil,
            isCritical: chance(0.9) ? chance(0.2) : nil,
            isDeepClean: chance(0.9) ? chance(0.2) : nil,
            isWeatherDependent: chance(0.9) ? chance(0.2) : nil,
            time: chance(0.85) ? TimeHintSnapshot(anchor: chance(0.9) ? .known(.none) : nil,
                                                  daypart: chance(0.3) ? .known(.evening) : nil) : nil,
            sourcePhrase: chance(0.8) ? pick(Self.phrases) : nil
        )
    }

    /// The view of `item` at progress `p` (0…1): each field has its own reveal threshold; the title grows.
    mutating func thresholds() -> [Double] { (0..<10).map { _ in Double.random(in: 0..<1, using: &g) } }

    static func view(_ item: ItemSnapshot, thresholds t: [Double], progress p: Double) -> ItemSnapshot {
        var v = ItemSnapshot()
        if let title = item.title, p >= t[0] {
            let span: Double = max(0.01, 1 - t[0])
            let share: Double = min(1, (p - t[0]) / span + 0.3)
            let length = max(1, Int(Double(title.count) * share))
            v.title = String(title.prefix(length))
        }
        if p >= t[1] { v.kind = item.kind }
        if p >= t[2] { v.roomName = item.roomName }
        if p >= t[3] { v.effort = item.effort }
        if p >= t[4] { v.isCritical = item.isCritical }
        if p >= t[5] { v.isDeepClean = item.isDeepClean }
        if p >= t[6] { v.isWeatherDependent = item.isWeatherDependent }
        if p >= t[7] { v.time = item.time }
        if p >= t[8] { v.sourcePhrase = item.sourcePhrase }
        return v
    }

    mutating func script() -> (snapshots: [[ItemSnapshot]], ending: StreamOracle.Ending) {
        let count = int(0...5)
        var finals = (0..<count).map { _ in finalItem() }
        let marks = (0..<count).map { _ in thresholds() }
        let steps = int(1...10)
        var snapshots: [[ItemSnapshot]] = []
        for step in 0..<steps {
            let progress = Double(step + 1) / Double(steps)
            // Items start in order: item i is visible once progress passes i / count.
            var visible = count == 0 ? 0 : min(count, Int(progress * Double(count)) + (chance(0.5) ? 1 : 0))
            if chance(0.05) { visible = max(0, visible - int(1...2)) }   // a shrinking snapshot
            if chance(0.1), count > 0 { finals[int(0...(count - 1))].title = pick(Self.titles) }  // value changes
            let items = (0..<visible).map { i in
                Self.view(finals[i], thresholds: marks[i], progress: i < visible - 1 ? 1 : progress)
            }
            snapshots.append(items)
        }
        let ending: StreamOracle.Ending = chance(0.6) ? .finish : .stop(pick(ModelStopReason.allCases))
        return (snapshots, ending)
    }
}

@Suite("AC-M2-05 property: random snapshot scripts against the timeline oracle (FR-A1)")
struct DraftStreamPropertyTests {

    @Test("AC-M2-05: 6,000 seeded scripts give exactly the oracle's events, and the event rules hold",
          arguments: [UInt64(0x0A11_C0DE_5EED_0601), 0x0A11_C0DE_5EED_0602, 0x0A11_C0DE_5EED_0603])
    func property(seed: UInt64) {
        var generator = ScriptGenerator(g: SplitMix64(seed: seed))
        let mapper = StreamFixtures.mapper()
        let check = SameTitleCheck()
        var counts: [String: Int] = [:]
        var mismatches = 0
        var invariantMisses = 0
        for run in 0..<2_000 {
            let (snapshots, ending) = generator.script()
            let route: Route = pick(run)
            var assembler = DraftStreamAssembler(mapper: mapper, duplicateCheck: check, route: route)
            var events: [DraftStreamEvent] = []
            for items in snapshots { events += assembler.receive(IngestionSnapshot(items: items)) }
            switch ending {
            case .finish: events += assembler.finishNormally()
            case let .stop(reason): events += assembler.stop(reason)
            }
            let expected = StreamOracle.events(snapshots: snapshots, ending: ending, mapper: mapper, check: check,
                                               route: route)
            if events != expected {
                mismatches += 1
                if mismatches <= 3 {
                    Issue.record("seed \(seed) run \(run): \(events.map(Ev.init)) != \(expected.map(Ev.init))")
                }
            }
            checkRules(events, route: route, seed: seed, run: run, counts: &counts)
            // PO ruling 5 invariant: final markers = one pass of the check over the final drafts.
            var summary = DraftStreamSummary()
            for event in events { summary.apply(event) }
            if summary.drafts.map(\.duplicate) != DraftStreamTests.onePass(summary.drafts, check) {
                invariantMisses += 1
            }
            if events.contains(where: { if case let .updated(d) = $0 { d.duplicate != .none } else { false } }) {
                counts["remarked", default: 0] += 1
            }
        }
        print("AC-M2-05 property seed \(String(seed, radix: 16)): 2000 scripts, \(mismatches) oracle mismatches, "
              + "\(invariantMisses) invariant misses, "
              + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        #expect(mismatches == 0, "seed \(seed)")
        #expect(invariantMisses == 0, "seed \(seed): marker invariant")
        // Coverage: every event and outcome kind occurs on every seed.
        for key in ["emitted", "updated", "itemSkipped", "completed", "completedNoDraft", "interrupted", "noModel",
                    "discarded", "dup", "remarked"] {
            #expect((counts[key] ?? 0) > 0, "seed \(seed): \(key) never occurred")
        }
    }

    func pick(_ run: Int) -> Route {
        [Route.onDevice, .cloud(.openAI), .cloud(.anthropic), .cloud(.gemini), .onDevice][run % 5]
    }

    /// The brief's structural rules, checked on every script.
    func checkRules(_ events: [DraftStreamEvent], route: Route, seed: UInt64, run: Int,
                    counts: inout [String: Int]) {
        var emitted: [Int] = []
        var finishedCount = 0
        for (position, event) in events.enumerated() {
            switch event {
            case let .emitted(draft):
                counts["emitted", default: 0] += 1
                if draft.duplicate != .none { counts["dup", default: 0] += 1 }
                #expect(!emitted.contains(draft.draftID), "seed \(seed) run \(run): emitted twice")
                #expect(draft.draftID == emitted.count + 1, "seed \(seed) run \(run): IDs not 1, 2, 3 …")
                // The input holds no banned token, so no emitted title may hold one (UX-3, AC-M2-12).
                #expect(!BannedTokens.containsBannedToken(draft.title), "seed \(seed) run \(run): \(draft.title)")
                emitted.append(draft.draftID)
            case let .updated(draft):
                counts["updated", default: 0] += 1
                #expect(emitted.contains(draft.draftID), "seed \(seed) run \(run): updated before emitted")
            case .itemSkipped:
                counts["itemSkipped", default: 0] += 1
            case let .finished(outcome):
                finishedCount += 1
                #expect(position == events.count - 1, "seed \(seed) run \(run): finished not last")
                #expect(outcome.route == route)
                switch outcome {
                case let .completed(_, input, note):
                    counts["completed", default: 0] += 1
                    if emitted.isEmpty {
                        counts["completedNoDraft", default: 0] += 1
                        #expect(input == StreamFixtures.input && note != nil, "seed \(seed) run \(run)")
                    } else {
                        #expect(input == nil && note == nil, "seed \(seed) run \(run)")
                    }
                case let .interrupted(_, _, discarded, input):
                    counts["interrupted", default: 0] += 1
                    if discarded != nil { counts["discarded", default: 0] += 1 }
                    #expect(!emitted.isEmpty && input == StreamFixtures.input)
                case let .noModel(_, _, input, note):
                    counts["noModel", default: 0] += 1
                    #expect(emitted.isEmpty && input == StreamFixtures.input && note != nil)
                case .cancelled:
                    Issue.record("cancelled without cancellation")
                }
            }
        }
        #expect(finishedCount == 1, "seed \(seed) run \(run): finished \(finishedCount) times")
    }
}
