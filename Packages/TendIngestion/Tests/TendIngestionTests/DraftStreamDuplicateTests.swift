// WI-M2-06/07 integration: the draft stream marks duplicates with the WI-M2-07 rules (`DraftDuplicateRules`), per PO
// WI-M2-06 ruling 5 (re-mark after updates) and PO WI-M2-07 ruling 1 (word-match floor on every path). AC-M2-05,
// AC-M2-07, AC-M2-08. FR-A1. Review tickets R22-R2-F1, R22-R2-F2, R21-F6.
//
// What the check reads (the purity rule, R22-R2-F2): a draft, its 1-based item position (skipped items included), the
// model's claim from the **latest** version of its item, the same for every lower draft (with their latest markers),
// and the duplicate-lookup queries of the **latest** snapshot. The household and the path are fixed for the parse.
// On device, the Tool's queries grow during a parse; a snapshot whose queries differ from the ones used for the last
// marking re-marks every emitted draft (option (b) of R22-R2-F2). So after `finished`, each marker equals one pass of
// the rules over the final drafts, the final claims and the final queries (the ruling 5 invariant).
//
// Hand-written expected values come from the brief's Definitions. The end-to-end property at the bottom runs seeded
// scripts through `DraftPipeline` on all three paths against `DupOracle` (independent of production) and the shared
// `DraftMapper` (proven by AC-M2-01/02).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// A mock model that replays whole snapshots (items and lookup queries). No clock, no I/O.
final class SnapshotModel: IngestionModel {
    let snapshots: [IngestionSnapshot]
    init(_ snapshots: [IngestionSnapshot]) { self.snapshots = snapshots }

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let snapshots = self.snapshots
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish()
        }
    }
}

/// Reads a draft stream up to its `finished` event, with a hard cap, so a broken rule fails instead of hanging.
func collectCapped(_ sequence: DraftEventSequence, cap: Int = 5_000) async -> (events: [DraftStreamEvent], capped: Bool) {
    var events: [DraftStreamEvent] = []
    var iterator = sequence.makeAsyncIterator()
    while let event = await iterator.next() {
        events.append(event)
        if case .finished = event { return (events, false) }
        if events.count >= cap { return (events, true) }
    }
    return (events, false)
}

private enum S {
    static let kitchen = MappingFixtures.kitchen
    static let pods = DupFixture.task(DupFixture.id("000000000001"), "Buy dish pods", kind: .restock, room: kitchen.id)
    static let counter = DupFixture.task(DupFixture.id("000000000002"), "Wipe kitchen counter", room: kitchen.id)
    static let oven = DupFixture.task(DupFixture.id("000000000003"), "Clean the oven", kind: .recurring)
    static let household = Household(tasks: [pods, counter, oven], rooms: MappingFixtures.rooms)
    static let input = "refill the soap, get oat milk, buy bread, get bread, bread, wipe the counter"

    static func item(_ title: String?, sameAsItem: Int? = nil, existing: ExistingTaskClaim? = nil) -> ItemSnapshot {
        // Every schema field has a value (room "" links to no room), so completion rule (a) fires.
        var item = StreamFixtures.full(title, room: "", sourcePhrase: "")
        item.sameAsItem = sameAsItem
        item.sameAsExisting = existing
        return item
    }

    static func snapshot(_ items: [ItemSnapshot], queries: [String] = []) -> IngestionSnapshot {
        IngestionSnapshot(items: items, lookupQueries: queries)
    }

    static func assemble(_ snapshots: [IngestionSnapshot], check: any DraftDuplicateCheck,
                         route: Route = .onDevice) -> [DraftStreamEvent] {
        var assembler = DraftStreamAssembler(mapper: StreamFixtures.mapper(input: input), duplicateCheck: check,
                                             route: route)
        var events: [DraftStreamEvent] = []
        for snapshot in snapshots { events += assembler.receive(snapshot) }
        return events + assembler.finishNormally()
    }

    static func pipeline(_ snapshots: [IngestionSnapshot], check: any DraftDuplicateCheck,
                         cloud: Bool = false) async -> [DraftStreamEvent] {
        let model = SnapshotModel(snapshots)
        let routed: RoutedModel = cloud ? .cloud(.anthropic, model) : .onDevice(model)
        let run = await collectCapped(StreamFixtures.pipeline(input: input, check: check).events(from: routed))
        #expect(!run.capped)
        return run.events
    }

    /// Both drivers must give `expected`.
    static func expectBoth(_ snapshots: [IngestionSnapshot], check: any DraftDuplicateCheck, cloud: Bool = false,
                           _ expected: [Ev], sourceLocation: SourceLocation = #_sourceLocation) async {
        let route: Route = cloud ? .cloud(.anthropic) : .onDevice
        #expect(assemble(snapshots, check: check, route: route).map(Ev.init) == expected,
                sourceLocation: sourceLocation)
        #expect(await pipeline(snapshots, check: check, cloud: cloud).map(Ev.init) == expected,
                sourceLocation: sourceLocation)
    }
}

@Suite("WI-M2-06/07 integration: the draft stream marks duplicates with the WI-M2-07 rules (AC-M2-05, AC-M2-07, AC-M2-08; FR-A1)")
struct DraftStreamDuplicateTests {

    static let device = DraftDuplicateRules.onDevice(household: S.household)
    static let cloudNo = DraftDuplicateRules.cloud(.noTitles, capture: S.input, household: S.household)
    static let cloudYes = DraftDuplicateRules.cloud(.shortlistTitles, capture: S.input, household: S.household)

    @Test("ItemSnapshot carries the model's two claims as neutral values; they map to DuplicateClaim and are not completion fields")
    func snapshotClaims() {
        var item = S.item("Buy bread", sameAsItem: 2, existing: .lookupTitle("Buy dish pods"))
        #expect(item.duplicateClaim == DuplicateClaim(sameAsItem: 2, sameAsTitle: "Buy dish pods"))
        item.sameAsExisting = .shortlistIndex(3)
        #expect(item.duplicateClaim == DuplicateClaim(sameAsItem: 2, sameAsShortlistIndex: 3))
        #expect(ItemSnapshot().duplicateClaim == DuplicateClaim())
        // Completion rule (a) is the nine schema fields (PO WI-M2-06 ruling 2); the claims are optional and never
        // hold an item back.
        #expect(S.item("Buy bread").hasValueForEveryField)
        #expect(!ItemSnapshot(title: "x", sameAsItem: 1, sameAsExisting: .shortlistIndex(1)).hasValueForEveryField)
        #expect(IngestionSnapshot(items: []).lookupQueries == [])
    }

    @Test("PO ruling 5 / R22-R2-F2: on device, a title claim the Tool had not returned yet is resolved when the lookup queries grow; every draft is re-marked")
    func toolLogGrowth() async {
        let claim = ExistingTaskClaim.lookupTitle("buy DISH pods")
        await S.expectBoth([
            // The claim comes before the Tool call reaches the snapshot: unresolved, and the floor finds nothing.
            S.snapshot([S.item("Refill the soap", existing: claim), S.item("Get oat milk")]),
            S.snapshot([S.item("Refill the soap", existing: claim), S.item("Get oat milk")], queries: ["dish pods"]),
            S.snapshot([S.item("Refill the soap", existing: claim), S.item("Get oat milk")], queries: ["dish pods"]),
        ], check: Self.device, [
            .emitted(1, "Refill the soap"), .emitted(2, "Get oat milk"),
            .updated(1, "Refill the soap", .ofExisting(S.pods.id)),
            .finished(.completed(route: .onDevice)),
        ])
    }

    @Test("PO ruling 5: a claim that arrives after emission re-marks the draft (the claim is read from the latest item)")
    func lateClaim() async {
        await S.expectBoth([
            S.snapshot([S.item("Buy bread"), S.item("Get bread")]),
            S.snapshot([S.item("Buy bread"), S.item("Get bread", sameAsItem: 1)]),
        ], check: Self.cloudNo, cloud: true, [
            .emitted(1, "Buy bread"), .emitted(2, "Get bread"), .updated(2, "Get bread", .ofDraft(1)),
            .finished(.completed(route: .cloud(.anthropic))),
        ])
    }

    @Test("PO ruling 5 / R21-F6: cascade through the stream: draft 2 drops its claim, so draft 3 (content unchanged) collapses into draft 2")
    func cascade() async {
        await S.expectBoth([
            S.snapshot([S.item("Buy bread"), S.item("Get bread", sameAsItem: 1), S.item("Bread", sameAsItem: 2)]),
            S.snapshot([S.item("Buy bread"), S.item("Get bread"), S.item("Bread", sameAsItem: 2)]),
        ], check: Self.device, [
            .emitted(1, "Buy bread"), .emitted(2, "Get bread", .ofDraft(1)), .emitted(3, "Bread", .ofDraft(1)),
            .updated(2, "Get bread"), .updated(3, "Bread", .ofDraft(2)),
            .finished(.completed(route: .onDevice)),
        ])
    }

    @Test("AC-M2-07: positions count skipped items; a claim pointing at a skipped item is ignored")
    func positionsCountSkippedItems() async {
        await S.expectBoth([
            S.snapshot([S.item("   "), S.item("Get bread"), S.item("Bread", sameAsItem: 2), S.item("Buy bread", sameAsItem: 1)]),
        ], check: Self.cloudNo, cloud: true, [
            .skipped(.noTitle), .emitted(1, "Get bread"), .emitted(2, "Bread", .ofDraft(1)), .emitted(3, "Buy bread"),
            .finished(.completed(route: .cloud(.anthropic))),
        ])
    }

    @Test("AC-M2-07: cloud Q12 = yes: an index claim marks the shortlist entry; Tool queries and title claims do not apply on this path")
    func cloudYesIndex() async {
        let sent = DuplicateShortlist.entries(for: S.input, in: S.household)
        let n = (sent.firstIndex { $0.taskID == S.pods.id } ?? 98) + 1
        #expect(n <= sent.count)
        await S.expectBoth([
            S.snapshot([S.item("Refill the soap", existing: .shortlistIndex(n)),
                        S.item("Get oat milk", existing: .lookupTitle("Buy dish pods"))], queries: ["dish pods"]),
        ], check: Self.cloudYes, cloud: true, [
            .emitted(1, "Refill the soap", .ofExisting(S.pods.id)), .emitted(2, "Get oat milk"),
            .finished(.completed(route: .cloud(.anthropic))),
        ])
    }

    @Test("PO WI-M2-07 ruling 1: the word-match floor marks an exact repeat on every path, with no claim")
    func floorOnEveryPath() async {
        for (check, cloud) in [(Self.device, false), (Self.cloudYes, true), (Self.cloudNo, true)] {
            let route: Route = cloud ? .cloud(.anthropic) : .onDevice
            await S.expectBoth([S.snapshot([S.item("wipe the kitchen counter")])], check: check, cloud: cloud, [
                .emitted(1, "wipe the kitchen counter", .ofExisting(S.counter.id)), .finished(.completed(route: route)),
            ])
        }
    }

    @Test("R22-R2-F2: the hook gets the item position, the latest claim and the latest queries; grown queries re-mark every draft, equal queries and a kept claim none")
    func hookInputs() {
        let check = RecordingCheck()
        let a = S.item("Buy bread"), b = S.item("Get bread"), b1 = S.item("Get bread", sameAsItem: 2)
        _ = S.assemble([
            S.snapshot([S.item("  "), a, b]),
            S.snapshot([S.item("  "), a, b], queries: ["bread"]),             // queries grew: re-mark 1 and 2
            S.snapshot([S.item("  "), a, b], queries: ["bread"]),             // nothing changed: no call
            S.snapshot([S.item("  "), a, b1], queries: ["bread"]),            // claim of draft 2 changed: re-mark 2
            S.snapshot([S.item("  "), a, b1], queries: ["bread"]),            // the new claim is kept: no call
        ], check: check)
        let calls = check.fullCalls
        #expect(calls.map(\.entry.position) == [2, 3, 2, 3, 3])
        #expect(check.calls == [Call(draftID: 1, earlier: []), Call(draftID: 2, earlier: [1]),
                                Call(draftID: 1, earlier: []), Call(draftID: 2, earlier: [1]),
                                Call(draftID: 2, earlier: [1])])
        #expect(calls.map(\.lookupQueries) == [[], [], ["bread"], ["bread"], ["bread"]])
        #expect(calls.map(\.entry.claim) == [DuplicateClaim(), DuplicateClaim(), DuplicateClaim(), DuplicateClaim(),
                                             DuplicateClaim(sameAsItem: 2)])
        // Earlier entries carry their latest markers (RecordingCheck marks each draft ofDraft of the one before).
        #expect(calls.last?.earlier.map(\.draft.duplicate) == [.none])
        #expect(calls.last?.earlier.map(\.position) == [2])
    }

    @Test("PO ruling 5 invariant with the real rules: after finished, the markers equal one pass over the final drafts, claims and queries")
    func invariantWithRules() {
        let final = [S.item("Refill the soap", existing: .lookupTitle("Buy dish pods")), S.item("Get bread"),
                     S.item("Bread", sameAsItem: 2), S.item("wipe the counter")]
        let scripts: [[IngestionSnapshot]] = [
            [S.snapshot(Array(final.prefix(2))), S.snapshot(final), S.snapshot(final, queries: ["pods"])],
            [S.snapshot([S.item("Bread"), S.item("Bread", sameAsItem: 1)]), S.snapshot(final, queries: ["pods"])],
            [S.snapshot(final, queries: ["pods"]), S.snapshot(final, queries: ["pods", "oven"])],
        ]
        for snapshots in scripts {
            var summary = DraftStreamSummary()
            for event in S.assemble(snapshots, check: Self.device) { summary.apply(event) }
            let queries = snapshots.last?.lookupQueries ?? []
            let entries = summary.drafts.enumerated().map { offset, draft in
                DuplicateCheckEntry(draft: draft, position: offset + 1, claim: final[offset].duplicateClaim)
            }
            #expect(summary.drafts.map(\.duplicate)
                    == DraftStreamTests.onePass(entries, Self.device, lookupQueries: queries))
            #expect(summary.drafts.first?.duplicate == .ofExisting(S.pods.id))
        }
    }

    @Test("DraftDuplicateRules gives the same markers as DuplicateMarker.mark called once per position with the same evidence")
    func rulesEqualMarker() {
        var log = DuplicateLookupLog(household: S.household)
        _ = log.lookUp("pods")
        _ = log.lookUp("oven")
        let drafts = [DupFixture.draft(1, "Refill soap"), DupFixture.draft(2, "Clean oven"),
                      DupFixture.draft(3, "soap refill"), DupFixture.draft(4, "Wipe kitchen counter")]
        let positions = [1, 3, 4, 5]
        let claims = [DuplicateClaim(sameAsTitle: "BUY dish pods"), DuplicateClaim(sameAsTitle: "Clean the oven"),
                      DuplicateClaim(sameAsItem: 1), DuplicateClaim(sameAsItem: 2, sameAsShortlistIndex: 1)]
        let paths: [(DraftDuplicateRules, ExistingTaskCheck)] = [
            (.onDevice(household: S.household), .toolLookups(log)),
            (.cloud(.shortlistTitles, capture: S.input, household: S.household),
             CloudTitleSharing.shortlistTitles.existingTaskCheck(capture: S.input, household: S.household)),
            (.cloud(.noTitles, capture: S.input, household: S.household), .localWordMatch(S.household)),
        ]
        for (rules, check) in paths {
            var marker = DuplicateMarker()
            let byMarker = drafts.indices.map {
                marker.mark(drafts[$0], position: positions[$0], claim: claims[$0], check: check).duplicate
            }
            let entries = drafts.indices.map {
                DuplicateCheckEntry(draft: drafts[$0], position: positions[$0], claim: claims[$0])
            }
            #expect(DraftStreamTests.onePass(entries, rules, lookupQueries: log.queries) == byMarker)
        }
        // On device the title claims resolve through the replayed queries.
        let device = DraftStreamTests.onePass(
            drafts.indices.map { DuplicateCheckEntry(draft: drafts[$0], position: positions[$0], claim: claims[$0]) },
            DraftDuplicateRules.onDevice(household: S.household), lookupQueries: ["pods", "oven"])
        // Draft 4 claims position 2, which was skipped: ignored, so the floor finds the counter.
        #expect(device == [.ofExisting(S.pods.id), .ofExisting(S.oven.id), .ofDraft(1), .ofExisting(S.counter.id)])
    }

    @Test("D6: confirmed drafts stay in ascending draftID after re-marks (the commit order)")
    func commitOrder() {
        var summary = DraftStreamSummary()
        for event in S.assemble([
            S.snapshot([S.item("Buy bread"), S.item("Get bread"), S.item("Bread")]),
            S.snapshot([S.item("Buy bread"), S.item("Get bread", sameAsItem: 1), S.item("Bread", sameAsItem: 2)],
                       queries: ["bread"]),
        ], check: Self.device) { summary.apply(event) }
        #expect(summary.drafts.map(\.draftID) == [1, 2, 3])
        #expect(summary.drafts.map(\.duplicate) == [.none, .ofDraft(1), .ofDraft(1)])
    }
}

// MARK: - End-to-end property

@Suite("WI-M2-06/07 integration property: seeded scripts through DraftPipeline with the real rules on all three paths (AC-M2-05, AC-M2-08; FR-A1)")
struct DraftStreamDuplicatePropertyTests {

    static let seeds: [UInt64] = [0x0D0B_1E5E_ED06_0701, 0x0D0B_1E5E_ED06_0702, 0x0D0B_1E5E_ED06_0703]
    static let householdsPerSeed = 200

    enum Plant: String, CaseIterable { case fresh, exact, synonym, inInput, completedRepeat, bogusClaim, skipped }

    /// One scripted item, path-independent.
    struct Planned {
        var plant: Plant
        var title: String
        var roomText: String?
        var target: HouseholdTask?
        var earlier: Int?
    }

    /// One item as the mock streams it on one path.
    struct Timed {
        var final: ItemSnapshot
        /// The claim the mock makes (oracle copy, built independently of `ItemSnapshot.duplicateClaim`).
        var claim: DuplicateClaim
        var start: Int
        var reveal: [Int]          // per schema field (9) the step it appears
        var titleDone: Int
        var claimAt: Int
        var queries: [String]
        var queryAt: Int
        var visible: Bool
    }

    static let freshWords = ["mend", "fence", "paint", "gate", "call", "plumber", "bake", "bread", "dust", "kitchen"]
    static let synonymWords = ["refill", "restock", "grab", "pick up", "sort", "freshen", "scrub", "tidy"]

    static func plan(_ household: Household, _ rnd: inout DupRandom) -> [Planned] {
        let live = household.tasks.filter { $0.state != .completed && !DupOracle.keywords($0.title).isEmpty }
        let done = household.tasks.filter { $0.state == .completed && !DupOracle.keywords($0.title).isEmpty }
        var items: [Planned] = []
        for _ in 1...rnd.int(3...12) {
            var plant = rnd.pick(Plant.allCases)
            if (plant == .exact || plant == .synonym) && live.isEmpty { plant = .fresh }
            if plant == .completedRepeat && done.isEmpty { plant = .fresh }
            if plant == .inInput && !items.contains(where: { $0.plant != .skipped }) { plant = .fresh }
            func roomText(_ task: HouseholdTask) -> String? {
                guard let id = task.roomID, let room = household.rooms.first(where: { $0.id == id }) else { return nil }
                return rnd.chance(70) ? room.name : nil
            }
            switch plant {
            case .fresh, .bogusClaim:
                var title = ""
                for _ in 0..<rnd.int(1...3) { title += (title.isEmpty ? "" : " ") + rnd.pick(freshWords) }
                let room: String? = rnd.chance(30) ? "Porch"
                    : (rnd.chance(40) && !household.rooms.isEmpty ? rnd.pick(household.rooms).name : nil)
                items.append(Planned(plant: plant, title: title, roomText: room))
            case .skipped:
                items.append(Planned(plant: .skipped, title: "   "))
            case .exact:
                let t = rnd.pick(live)
                items.append(Planned(plant: .exact, title: t.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                     roomText: roomText(t), target: t))
            case .synonym:
                let t = rnd.pick(live)
                items.append(Planned(plant: .synonym,
                                     title: rnd.pick(synonymWords) + " " + rnd.pick(["it", "that one", "the thing"]),
                                     target: t))
            case .completedRepeat:
                let t = rnd.pick(done)
                items.append(Planned(plant: .completedRepeat,
                                     title: t.title.trimmingCharacters(in: .whitespacesAndNewlines), target: t))
            case .inInput:
                let k = rnd.pick(items.indices.filter { items[$0].plant != .skipped })
                items.append(Planned(plant: .inInput, title: items[k].title, roomText: items[k].roomText,
                                     earlier: k + 1))
            }
        }
        return items
    }

    /// The mock's claims, Tool queries and timing on one path. Visibility uses the oracle's shortlist only.
    static func timed(_ plan: [Planned], mode: DupOracle.Mode, sent: [ShortlistEntry], household: Household,
                      steps: Int, _ rnd: inout DupRandom) -> [Timed] {
        var starts = plan.map { _ in rnd.int(0...(steps - 2)) }
        starts.sort()
        return plan.enumerated().map { offset, p in
            let position = offset + 1
            let start = starts[offset]
            var claim = DuplicateClaim()
            var queries: [String] = []
            var visible = false
            switch p.plant {
            case .exact, .synonym, .completedRepeat:
                guard let target = p.target else { break }
                switch mode {
                case .onDevice:
                    let want = DupOracle.foldedTitle(target.title)
                    for query in [p.title, target.title] {
                        queries.append(query)
                        if let entry = DupOracle.shortlist(query, household).first(where: { DupOracle.foldedTitle($0.title) == want }) {
                            claim.sameAsTitle = rnd.chance(50) ? entry.title : entry.title.uppercased()
                            visible = true
                            break
                        }
                    }
                    if p.plant == .completedRepeat && !visible && rnd.chance(50) { claim.sameAsTitle = target.title }
                case .cloudTitles:
                    if let n = sent.firstIndex(where: { $0.taskID == target.id }) {
                        claim.sameAsShortlistIndex = n + 1
                        visible = true
                    }
                case .cloudNoTitles:
                    break
                }
            case .inInput:
                claim.sameAsItem = p.earlier
                visible = true
            case .bogusClaim:
                switch rnd.int(0...4) {
                case 0: claim.sameAsItem = position
                case 1: claim.sameAsItem = position + rnd.int(1...3)
                case 2: claim.sameAsShortlistIndex = rnd.pick([0, -1, sent.count + 1, 11])
                case 3: claim.sameAsTitle = "no such task title"
                default: claim.sameAsItem = 0
                }
            case .fresh, .skipped:
                break
            }
            var final = MappingFixtures.item(title: p.title, room: p.roomText, time: MappingFixtures.hint(anchor: "none"),
                                             sourcePhrase: rnd.chance(50) ? p.title : nil)
            final.sameAsItem = claim.sameAsItem
            if let title = claim.sameAsTitle { final.sameAsExisting = .lookupTitle(title) }
            if let n = claim.sameAsShortlistIndex { final.sameAsExisting = .shortlistIndex(n) }
            let last = steps - 1
            let reveal = (0..<9).map { field in field == 0 ? start : rnd.int(start...last) }
            return Timed(final: final, claim: claim, start: start, reveal: reveal,
                         titleDone: rnd.int(start...last), claimAt: rnd.int(start...last), queries: queries,
                         queryAt: rnd.int(max(0, start - 1)...last), visible: visible)
        }
    }

    /// The snapshot the mock sends at `step`.
    static func snapshot(_ items: [Timed], step: Int, mode: DupOracle.Mode) -> IngestionSnapshot {
        var shown: [ItemSnapshot] = []
        for item in items where item.start <= step {
            let f = item.final
            var v = ItemSnapshot()
            if let title = f.title {
                if step >= item.titleDone {
                    v.title = title
                } else {
                    let share = Double(step - item.start + 1) / Double(item.titleDone - item.start + 1)
                    v.title = String(title.prefix(max(1, Int(Double(title.count) * share))))
                }
            }
            if step >= item.reveal[1] { v.kind = f.kind }
            if step >= item.reveal[2] { v.roomName = f.roomName }
            if step >= item.reveal[3] { v.effort = f.effort }
            if step >= item.reveal[4] { v.isCritical = f.isCritical }
            if step >= item.reveal[5] { v.isDeepClean = f.isDeepClean }
            if step >= item.reveal[6] { v.isWeatherDependent = f.isWeatherDependent }
            if step >= item.reveal[7] { v.time = f.time }
            if step >= item.reveal[8] { v.sourcePhrase = f.sourcePhrase }
            if step >= item.claimAt {
                v.sameAsItem = f.sameAsItem
                v.sameAsExisting = f.sameAsExisting
            }
            shown.append(v)
        }
        return IngestionSnapshot(items: shown, lookupQueries: mode == .onDevice ? queries(items, upTo: step) : [])
    }

    /// The Tool calls made by `step`, in call order (by step, then item order).
    static func queries(_ items: [Timed], upTo step: Int) -> [String] {
        var calls: [(step: Int, order: Int, query: String)] = []
        for (offset, item) in items.enumerated() where item.queryAt <= step {
            for query in item.queries { calls.append((item.queryAt, offset, query)) }
        }
        // A stable selection by step, without a sort of production values.
        var result: [String] = []
        for s in 0...max(step, 0) { for call in calls where call.step == s { result.append(call.query) } }
        return result
    }

    @Test("AC-M2-05 + AC-M2-08: 600 seeded households × 3 paths through DraftPipeline: final drafts equal the oracle (ruling 5 invariant), and every planted exact-title duplicate in a compatible room is marked", .timeLimit(.minutes(10)), arguments: seeds)
    func property(seed: UInt64) async {
        var rnd = DupRandom(seed: seed)
        var gen = DupHouseholdGenerator(rnd: DupRandom(seed: seed ^ 0xFFFF))
        var counts: [String: Int] = [:]
        var mismatches = 0, invariantMisses = 0
        for h in 0..<Self.householdsPerSeed {
            let household = gen.household()
            let plan = Self.plan(household, &rnd)
            let input = plan.map(\.title).joined(separator: ", and ")
            let sent = DupOracle.shortlist(input, household)
            let mapper = DraftMapper(input: input, rooms: household.rooms, now: MappingFixtures.newYorkNow,
                                     calendar: MappingFixtures.gregorian,
                                     timeZone: MappingFixtures.zone("America/New_York"))
            for mode in DupOracle.Mode.allCases {
                let label = "seed 0x\(String(seed, radix: 16)) household \(h) \(mode.rawValue)"
                let steps = plan.count + 3
                let items = Self.timed(plan, mode: mode, sent: sent, household: household, steps: steps, &rnd)
                let snapshots = (0..<steps).map { Self.snapshot(items, step: $0, mode: mode) }
                let finalQueries = snapshots.last?.lookupQueries ?? []
                let rules: DraftDuplicateRules
                let routed: RoutedModel
                let model = SnapshotModel(snapshots)
                switch mode {
                case .onDevice:
                    rules = .onDevice(household: household)
                    routed = .onDevice(model)
                case .cloudTitles:
                    rules = .cloud(.shortlistTitles, capture: input, household: household)
                    routed = .cloud(.openAI, model)
                case .cloudNoTitles:
                    rules = .cloud(.noTitles, capture: input, household: household)
                    routed = .cloud(.gemini, model)
                }
                let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: MappingFixtures.newYorkNow,
                                             calendar: MappingFixtures.gregorian,
                                             timeZone: MappingFixtures.zone("America/New_York"), duplicateCheck: rules)
                let run = await collectCapped(pipeline.events(from: routed))
                #expect(!run.capped, "\(label): the stream did not finish within the event cap")
                var summary = DraftStreamSummary()
                for event in run.events { summary.apply(event) }

                // The oracle: final contents from the shared mapper, markers from DupOracle over the final claims and
                // the final Tool queries (positions and draftIDs counted here).
                var oracleItems: [DupOracle.Item] = []
                var expectedDrafts: [IngestionDraft] = []
                var positions: [Int] = [], plantOf: [Plant] = [], visible: [Bool] = [], targets: [HouseholdTask?] = []
                for (offset, item) in items.enumerated() {
                    var draft: IngestionDraft?
                    if case let .draft(d) = mapper.map(item.final, draftID: expectedDrafts.count + 1).outcome {
                        draft = d
                        expectedDrafts.append(d)
                        positions.append(offset + 1)
                        plantOf.append(plan[offset].plant)
                        visible.append(item.visible)
                        targets.append(plan[offset].target)
                    }
                    oracleItems.append(DupOracle.Item(position: offset + 1, draft: draft, claim: item.claim,
                                                      queriesSoFar: finalQueries))
                }
                let marks = DupOracle.marks(oracleItems, mode: mode, capture: input, household: household)
                for i in expectedDrafts.indices { expectedDrafts[i].duplicate = marks[i] }
                if summary.drafts != expectedDrafts {
                    mismatches += 1
                    if mismatches <= 3 {
                        Issue.record("\(label): \(summary.drafts.map { ($0.draftID, $0.title, $0.duplicate) }) != \(expectedDrafts.map { ($0.draftID, $0.title, $0.duplicate) })")
                    }
                }
                // The ruling 5 invariant as stated: one pass of the production rules over the final drafts.
                let entries = summary.drafts.enumerated().map { i, draft in
                    DuplicateCheckEntry(draft: draft, position: i < positions.count ? positions[i] : 0,
                                        claim: i < positions.count ? items[positions[i] - 1].final.duplicateClaim
                                            : DuplicateClaim())
                }
                if summary.drafts.map(\.duplicate)
                    != DraftStreamTests.onePass(entries, rules, lookupQueries: finalQueries) {
                    invariantMisses += 1
                }
                // Outcome and event shape.
                let expectedOutcome: DraftStreamOutcome = expectedDrafts.isEmpty
                    ? .completed(route: routed.route, input: input,
                                 plainNote: PlainNote.draft(for: input, now: mapper.now, resolver: mapper.resolver))
                    : .completed(route: routed.route)
                #expect(summary.outcome == expectedOutcome, "\(label)")
                var emitted: [Int: DraftDuplicate] = [:]
                for event in run.events {
                    switch event {
                    case let .emitted(d):
                        #expect(d.draftID == emitted.count + 1, "\(label): draftIDs not 1, 2, 3 …")
                        emitted[d.draftID] = d.duplicate
                    case let .updated(d):
                        #expect(emitted[d.draftID] != nil, "\(label): updated before emitted")
                        counts["\(mode.rawValue).updated", default: 0] += 1
                    default: break
                    }
                }
                #expect(summary.drafts.map(\.draftID) == summary.drafts.indices.map { $0 + 1 }, "\(label): commit order")
                // Planted duplicates.
                for (i, draft) in summary.drafts.enumerated() where i < plantOf.count {
                    let key = "\(mode.rawValue).\(plantOf[i].rawValue)"
                    counts[key, default: 0] += 1
                    if draft.duplicate != .none { counts[key + ".marked", default: 0] += 1 }
                    if emitted[draft.draftID] != draft.duplicate { counts["\(mode.rawValue).remarked", default: 0] += 1 }
                    if visible[i] && [Plant.exact, .synonym, .inInput].contains(plantOf[i]) {
                        #expect(draft.duplicate != .none, "\(label) draft \(draft.draftID): a visible planted duplicate was left unmarked")
                    }
                    if plantOf[i] == .exact, let target = targets[i], DupOracle.roomsCompatible(draft.room, target, household) {
                        counts[key + ".compatible", default: 0] += 1
                        #expect(draft.duplicate != .none,
                                "\(label) draft \(draft.draftID): an exact-title repeat in a compatible room was left unmarked")
                    }
                    if mode == .onDevice, visible[i], items[positions[i] - 1].claimAt < items[positions[i] - 1].queryAt {
                        counts["onDevice.claimBeforeQuery", default: 0] += 1
                    }
                }
            }
        }
        print("WI-M2-06/07 e2e property: seed 0x\(String(seed, radix: 16, uppercase: true)), \(Self.householdsPerSeed) households × 3 paths, "
              + "\(mismatches) oracle mismatches, \(invariantMisses) invariant misses; counts \(counts.sorted { $0.key < $1.key })")
        #expect(mismatches == 0, "seed 0x\(String(seed, radix: 16))")
        #expect(invariantMisses == 0, "seed 0x\(String(seed, radix: 16))")
        for mode in DupOracle.Mode.allCases {
            for key in ["exact.compatible", "exact.marked", "inInput.marked", "updated", "remarked"] {
                #expect(counts["\(mode.rawValue).\(key)", default: 0] > 0, "seed 0x\(String(seed, radix: 16)): no \(mode.rawValue).\(key)")
            }
        }
        #expect(counts["onDevice.claimBeforeQuery", default: 0] > 0, "seed 0x\(String(seed, radix: 16)): Tool log growth never exercised")
        #expect(counts["onDevice.synonym.marked", default: 0] > 0 && counts["cloudTitles.synonym.marked", default: 0] > 0)
    }
}
