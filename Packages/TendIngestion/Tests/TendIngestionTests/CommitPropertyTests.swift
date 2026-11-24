// AC-M2-08 (commit half) and AC-M2-06 property: ≥ 500 seeded households, three paths (on device; cloud Q12 = yes;
// cloud Q12 = no), planted duplicates by exact title, by synonym (scripted in the mock) and within one input, drafts
// marked by the real `DraftPipeline` and `DraftDuplicateRules`, then committed with `DraftCommit` to an M1
// repository. FR-A1, Q7, Q10 (W3-F6), PO WI-M2-07 rulings 1 and 2.
//
// Between parse and commit the household changes the way a real one can: some targets are completed or removed, and
// rooms are added. Some drafts are left unconfirmed, the confirmed ones are passed in shuffled order, and the ID
// generator returns IDs already in use (tasks and rooms) and repeats its own earlier IDs.
//
// Two independent checks per parse and path:
// 1. **The oracle** (`CommitOracle`, below) computes the exact commit result from the brief's Definitions and the
//    rules in the dev notes (WI-M2-08 C1–C6). It calls no production code of `TendIngestion`: markers come from
//    `DupOracle` (WI-M2-07, independent), room folding is its own, word-matching is `DupOracle.wordMatch`, and IDs are
//    replayed from a copy of the generator with its own skip rule. Only `IngestionDraft.task(id:roomID:)` (the M1
//    initialiser, proven by AC-M2-01/02) is shared, for the new tasks' field values.
// 2. **Ground truth** from the plants alone, with no rule logic: no committed task repeats a task that is not
//    completed at commit (word-match rule or the mock's scripted claim), no in-input repeat is committed, no ID is
//    repeated, nothing that was in the household is overwritten, and the repository holds exactly the old household
//    plus the new rooms and tasks.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// The property's ID generator: often returns an ID in use (task or room), or one it returned before; otherwise a
/// fresh random one. A value type, so the oracle replays the same sequence from a copy.
struct CollidingIDs: CommitIDGenerator {
    var rnd: DupRandom
    let inUse: [UUID]
    var returned: [UUID] = []

    mutating func next() -> UUID {
        let id: UUID
        let roll = rnd.next() % 100
        if roll < 25, !inUse.isEmpty {
            id = rnd.pick(inUse)
        } else if roll < 37, !returned.isEmpty {
            id = rnd.pick(returned)
        } else {
            id = rnd.uuid()
        }
        returned.append(id)
        return id
    }
}

/// The expected commit result, from the Definitions and the WI-M2-08 rules (C1–C6), with no production rule code.
enum CommitOracle {
    enum Decision: Hashable { case created(UUID), alreadyOnList(UUID), sameChoreAsDraft(Int) }

    struct Result {
        var decisions: [(draftID: Int, decision: Decision)] = []
        var newRooms: [Room] = []
        var newTasks: [HouseholdTask] = []
        var skips: [String: Int] = [:]
        var path: [String: Int] = [:]
    }

    /// Name folding, re-implemented: the oracle's fold, trim and collapse, then one leading article.
    static func nameFold(_ text: String) -> String {
        let folded = DupOracle.fold(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for article in ["the", "a", "an", "my", "our"] where folded.hasPrefix(article + " ") && folded.count > article.count + 1 {
            return String(folded.dropFirst(article.count + 1))
        }
        return folded
    }

    static func expected(confirmed: [IngestionDraft], marks: [Int: DraftDuplicate], parsed: Household,
                         household: Household, ids: inout CollidingIDs) -> Result {
        var result = Result()
        // Ascending draftID by repeated selection (not a sort), one per draftID.
        var pool = confirmed
        var ordered: [IngestionDraft] = []
        while !pool.isEmpty {
            var best = 0
            for i in pool.indices where pool[i].draftID < pool[best].draftID { best = i }
            let next = pool.remove(at: best)
            if !ordered.contains(where: { $0.draftID == next.draftID }) { ordered.append(next) }
        }
        var used = Set(household.tasks.map(\.id))
        for room in household.rooms { used.insert(room.id) }
        let dangling = Set((household.tasks + parsed.tasks).compactMap(\.roomID))
        let parsedIDs = Set(parsed.tasks.map(\.id) + parsed.rooms.map(\.id))
        func draw(_ what: String) -> UUID {
            while true {
                let id = ids.next()
                if household.tasks.contains(where: { $0.id == id }) { result.skips["\(what).taskIDInUse", default: 0] += 1; continue }
                if household.rooms.contains(where: { $0.id == id }) { result.skips["\(what).roomIDInUse", default: 0] += 1; continue }
                if dangling.contains(id) { result.skips["\(what).danglingRoomID", default: 0] += 1; continue }
                if parsedIDs.contains(id) { result.skips["\(what).removedSinceParse", default: 0] += 1; continue }
                if used.contains(id) { result.skips["\(what).issuedAgain", default: 0] += 1; continue }
                used.insert(id)
                return id
            }
        }
        func live(_ id: UUID) -> Bool {
            household.tasks.contains { $0.id == id && $0.state != .completed }
        }
        var createdRooms: [(fold: String, room: Room)] = []
        var createdByDraft: [(draftID: Int, task: HouseholdTask)] = []
        var firstForGoneTarget: [UUID: Decision] = [:]
        /// The room a draft gets: an ID, or nil; `brandNew` when a new room would be made.
        func peek(_ room: DraftRoom) -> (id: UUID?, brandNew: String?) {
            switch room {
            case .none: return (nil, nil)
            case let .existing(id): return (household.rooms.contains { $0.id == id } ? id : nil, nil)
            case let .proposed(name):
                let f = nameFold(name)
                if f.isEmpty { return (nil, nil) }
                var best: Room?
                for r in household.rooms where nameFold(r.name) == f {
                    if best == nil || DupOracle.bytesBefore(r.id.uuidString, best?.id.uuidString ?? "") { best = r }
                }
                if let best { return (best.id, nil) }
                if let made = createdRooms.first(where: { $0.fold == f }) { return (made.room.id, nil) }
                return (nil, name)
            }
        }
        for draft in ordered {
            let (roomID, brandNew) = peek(draft.room)
            let matchRoom: DraftRoom = brandNew != nil ? .proposed(brandNew ?? "") : (roomID.map { .existing($0) } ?? .none)
            let rooms = household.rooms + createdRooms.map(\.room)
            var decision: Decision?
            var goneTarget: UUID?
            switch marks[draft.draftID] ?? .none {
            case let .ofDraft(k):
                decision = .sameChoreAsDraft(k)
            case let .ofExisting(t) where live(t):
                decision = .alreadyOnList(t)
            case let .ofExisting(t):
                goneTarget = t
                if let first = firstForGoneTarget[t] {
                    decision = first
                    result.path["goneTargetFollowsFirst", default: 0] += 1
                } else if let y = DupOracle.wordMatch(draft.title, matchRoom, Household(tasks: household.tasks, rooms: rooms)) {
                    decision = .alreadyOnList(y)
                    result.path["goneTargetFloorAtCommit", default: 0] += 1
                } else if let was = parsed.tasks.first(where: { $0.id == t }),
                          let y = DupOracle.wordMatch(
                              was.title,
                              was.roomID.flatMap { id in parsed.rooms.contains { $0.id == id } ? .existing(id) : nil } ?? .none,
                              Household(tasks: household.tasks, rooms: rooms)) {
                    decision = .alreadyOnList(y)
                    result.path["goneTargetLiveTwin", default: 0] += 1
                } else if let y = DupOracle.wordMatch(draft.title, matchRoom,
                                                      Household(tasks: createdByDraft.map(\.task), rooms: rooms)),
                          let j = createdByDraft.first(where: { $0.task.id == y }) {
                    decision = .sameChoreAsDraft(j.draftID)
                    result.path["goneTargetMatchesThisCommit", default: 0] += 1
                } else {
                    result.path[household.tasks.contains { $0.id == t } ? "targetCompletedCreated" : "targetRemovedCreated",
                                default: 0] += 1
                }
                if let decision { firstForGoneTarget[t] = decision }
            case .none:
                break
            }
            if let decision {
                result.decisions.append((draft.draftID, decision))
                continue
            }
            var finalRoom = roomID
            if let brandNew {
                let room = Room(id: draw("room"), name: brandNew)
                createdRooms.append((nameFold(brandNew), room))
                result.newRooms.append(room)
                finalRoom = room.id
            }
            let id = draw("task")
            guard let task = try? draft.task(id: id, roomID: finalRoom) else { continue }
            if let goneTarget { firstForGoneTarget[goneTarget] = .sameChoreAsDraft(draft.draftID) }
            createdByDraft.append((draft.draftID, task))
            result.newTasks.append(task)
            result.decisions.append((draft.draftID, .created(id)))
        }
        return result
    }
}

@Suite("AC-M2-08 + AC-M2-06 property: ≥ 500 seeded households × 3 paths, parsed by DraftPipeline and committed to an M1 repository (FR-A1)")
struct CommitPropertyTests {

    static let seeds: [UInt64] = [0x0C0A_11CE_ED08_0801, 0x0C0A_11CE_ED08_0802, 0x0C0A_11CE_ED08_0803]
    static let householdsPerSeed = 200

    enum Plant: String, CaseIterable { case fresh, exact, synonym, inInput, completedRepeat, skipped }

    struct Planned {
        var plant: Plant
        var title: String
        var roomText: String?
        var target: HouseholdTask?
        var earlier: Int?
    }

    // Disjoint from the household generator's words, so fresh and synonym items never word-match a task by chance;
    // a number per item keeps them distinct from each other too.
    static let freshWords = ["mend", "fence", "paint", "gate", "call", "plumber", "bake", "oil", "hinge"]
    static let synonymWords = ["refill", "restock", "grab", "pick up", "freshen", "scrub", "tidy"]
    static let proposedRooms = ["Porch", "the porch", "PORCH ", "Attic", "my attic", "Shed", "Lean\u{2019}s den"]
    static let addedRooms = ["porch", "Attic", "the Shed"]

    static func plan(_ household: Household, _ rnd: inout DupRandom) -> [Planned] {
        let live = household.tasks.filter { $0.state != .completed && !DupOracle.keywords($0.title).isEmpty }
        let done = household.tasks.filter { $0.state == .completed && !DupOracle.keywords($0.title).isEmpty }
        var items: [Planned] = []
        for n in 1...rnd.int(3...12) {
            var plant = rnd.pick(Plant.allCases)
            if (plant == .exact || plant == .synonym) && live.isEmpty { plant = .fresh }
            if plant == .completedRepeat && done.isEmpty { plant = .fresh }
            if plant == .inInput && !items.contains(where: { $0.plant != .skipped }) { plant = .fresh }
            func roomText(_ task: HouseholdTask) -> String? {
                guard let id = task.roomID, let room = household.rooms.first(where: { $0.id == id }) else { return nil }
                return rnd.chance(70) ? room.name : nil
            }
            switch plant {
            case .fresh:
                let title = rnd.pick(freshWords) + " " + rnd.pick(freshWords) + " \(100 + n)"
                let room: String? = rnd.chance(45) ? rnd.pick(proposedRooms)
                    : (rnd.chance(45) && !household.rooms.isEmpty ? rnd.pick(household.rooms).name : nil)
                items.append(Planned(plant: .fresh, title: title, roomText: room))
            case .skipped:
                items.append(Planned(plant: .skipped, title: "   "))
            case .exact:
                let t = rnd.pick(live)
                items.append(Planned(plant: .exact, title: t.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                     roomText: roomText(t), target: t))
            case .synonym:
                let t = rnd.pick(live)
                items.append(Planned(plant: .synonym, title: rnd.pick(synonymWords) + " it \(200 + n)",
                                     roomText: rnd.chance(30) ? rnd.pick(proposedRooms) : nil, target: t))
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

    /// The mock's claim on one path (built from the oracle's shortlist only), its Tool queries, and the task the
    /// mock's claim names (nil when the mock scripts no existing-task repeat). On device that can be a twin of the
    /// planted target: another task with the same folded title, maybe in another room (the Tool resolves titles, D1).
    static func claim(_ p: Planned, position: Int, mode: DupOracle.Mode, sent: [ShortlistEntry],
                      household: Household, _ rnd: inout DupRandom) -> (DuplicateClaim, [String], UUID?) {
        var claim = DuplicateClaim()
        var queries: [String] = []
        var scripted: UUID?
        switch p.plant {
        case .exact, .synonym:
            guard let target = p.target else { break }
            switch mode {
            case .onDevice:
                let want = DupOracle.foldedTitle(target.title)
                for query in [p.title, target.title] {
                    queries.append(query)
                    if let entry = DupOracle.shortlist(query, household).first(where: { DupOracle.foldedTitle($0.title) == want }) {
                        claim.sameAsTitle = rnd.chance(50) ? entry.title : entry.title.uppercased()
                        scripted = entry.taskID
                        break
                    }
                }
            case .cloudTitles:
                if let n = sent.firstIndex(where: { $0.taskID == target.id }) {
                    claim.sameAsShortlistIndex = n + 1
                    scripted = sent[n].taskID
                }
            case .cloudNoTitles:
                break
            }
        case .inInput:
            claim.sameAsItem = p.earlier
        case .fresh, .skipped, .completedRepeat:
            break
        }
        return (claim, queries, scripted)
    }

    /// The household at commit: targets and other tasks completed or removed, rooms added.
    static func changed(_ household: Household, _ rnd: inout DupRandom) -> Household {
        var tasks: [HouseholdTask] = []
        for task in household.tasks {
            let roll = rnd.next() % 100
            if roll < 12 { continue }                                            // removed
            if roll < 30, task.state != .completed, task.kind != .recurring {    // completed (M1: not recurring)
                tasks.append(DupFixture.task(task.id, task.title, kind: task.kind, room: task.roomID, state: .completed))
                continue
            }
            tasks.append(task)
        }
        var rooms = household.rooms
        if rnd.chance(35) { rooms.append(Room(id: rnd.uuid(), name: rnd.pick(addedRooms))) }
        return Household(tasks: tasks, rooms: rooms)
    }

    @Test("AC-M2-08 + AC-M2-06: 600 seeded households × 3 paths: the commit equals the oracle; no committed task repeats a live task or an in-input item, no ID repeats, nothing is overwritten", .timeLimit(.minutes(10)), arguments: seeds)
    func property(seed: UInt64) async throws {
        var rnd = DupRandom(seed: seed)
        var gen = DupHouseholdGenerator(rnd: DupRandom(seed: seed ^ 0xC0_FFEE))
        var counts: [String: Int] = [:]
        var mismatches = 0, truthMisses = 0
        for h in 0..<Self.householdsPerSeed {
            await Task.yield()  // do not hold a cooperative-pool thread for the whole loop (review R30-F3)
            let household = gen.household()
            let plan = Self.plan(household, &rnd)
            let input = plan.map(\.title).joined(separator: ", and ")
            let sent = DupOracle.shortlist(input, household)
            let mapper = DraftMapper(input: input, rooms: household.rooms, now: MappingFixtures.newYorkNow,
                                     calendar: MappingFixtures.gregorian,
                                     timeZone: MappingFixtures.zone("America/New_York"))
            for mode in DupOracle.Mode.allCases {
                let label = "seed 0x\(String(seed, radix: 16)) household \(h) \(mode.rawValue)"
                // 1. Parse with the real pipeline and rules.
                var items: [ItemSnapshot] = [], claims: [DuplicateClaim] = [], scripted: [UUID?] = []
                var queries: [String] = []
                for (offset, p) in plan.enumerated() {
                    let (claim, q, s) = Self.claim(p, position: offset + 1, mode: mode, sent: sent, household: household, &rnd)
                    var item = MappingFixtures.item(title: p.title, room: p.roomText,
                                                    time: MappingFixtures.hint(anchor: "none"), sourcePhrase: nil)
                    item.sameAsItem = claim.sameAsItem
                    if let title = claim.sameAsTitle { item.sameAsExisting = .lookupTitle(title) }
                    if let n = claim.sameAsShortlistIndex { item.sameAsExisting = .shortlistIndex(n) }
                    items.append(item)
                    claims.append(claim)
                    scripted.append(s)
                    queries += q
                }
                let model = SnapshotModel([IngestionSnapshot(items: items, lookupQueries: mode == .onDevice ? queries : [])])
                let (rules, routed): (DraftDuplicateRules, RoutedModel) = switch mode {
                case .onDevice: (.onDevice(household: household), .onDevice(model))
                case .cloudTitles: (.cloud(.shortlistTitles, capture: input, household: household), .cloud(.openAI, model))
                case .cloudNoTitles: (.cloud(.noTitles, capture: input, household: household), .cloud(.gemini, model))
                }
                let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: MappingFixtures.newYorkNow,
                                             calendar: MappingFixtures.gregorian,
                                             timeZone: MappingFixtures.zone("America/New_York"), duplicateCheck: rules)
                let run = await collectCapped(pipeline.events(from: routed))
                #expect(!run.capped, "\(label): the stream did not finish within the event cap")
                var summary = DraftStreamSummary()
                for event in run.events { summary.apply(event) }

                // The oracle's own markers (DupOracle) for the same drafts; plant metadata per draftID.
                var oracleItems: [DupOracle.Item] = []
                var planOf: [Int: (plan: Planned, scripted: UUID?)] = [:]
                var next = 1
                for (offset, item) in items.enumerated() {
                    var draft: IngestionDraft?
                    if case let .draft(d) = mapper.map(item, draftID: next).outcome {
                        draft = d
                        planOf[next] = (plan[offset], scripted[offset])
                        next += 1
                    }
                    oracleItems.append(DupOracle.Item(position: offset + 1, draft: draft, claim: claims[offset],
                                                      queriesSoFar: queries))
                }
                let oracleMarks = DupOracle.marks(oracleItems, mode: mode, capture: input, household: household)
                var marks: [Int: DraftDuplicate] = [:]
                for (i, mark) in oracleMarks.enumerated() { marks[i + 1] = mark }
                if summary.drafts.map(\.duplicate) != oracleMarks {
                    mismatches += 1
                    Issue.record("\(label): parse markers \(summary.drafts.map(\.duplicate)) != oracle \(oracleMarks)")
                }

                // 2. Between parse and commit: the household changes; some drafts are left unconfirmed.
                let atCommit = Self.changed(household, &rnd)
                var confirmed = summary.drafts.filter { _ in rnd.chance(80) }
                for i in confirmed.indices.reversed() where i > 0 { confirmed.swapAt(i, rnd.int(0...i)) }
                if !confirmed.isEmpty, rnd.chance(10) { confirmed.append(confirmed[0]) }   // the same draft twice
                // In use (R25-F1): IDs at commit, room IDs tasks still point to (dangling included), and the IDs of
                // the household the parse read (removed since the parse included).
                let inUse = atCommit.tasks.map(\.id) + atCommit.rooms.map(\.id)
                    + (atCommit.tasks + household.tasks).compactMap(\.roomID) + household.tasks.map(\.id)
                var ids = CollidingIDs(rnd: DupRandom(seed: rnd.next()), inUse: inUse)
                var oracleIDs = ids
                let expected = CommitOracle.expected(confirmed: confirmed, marks: marks, parsed: household, household: atCommit,
                                                     ids: &oracleIDs)

                // 3. Commit to an M1 repository (the file store for every 10th household).
                let useFile = h % 10 == 0
                let committed: (plan: CommitPlan, stored: Household)
                if useFile {
                    counts["jsonFileCommits", default: 0] += 1
                    committed = try await CommitFixtures.withRepository(.jsonFile, holding: atCommit) { repository, reopen in
                        let plan = try await DraftCommit.commit(confirmed: confirmed, parsedWith: household, to: repository, ids: &ids)
                        return (plan, try await reopen().load())
                    }
                } else {
                    let repository = InMemoryHouseholdRepository()
                    try await repository.save(atCommit)
                    let plan = try await DraftCommit.commit(confirmed: confirmed, parsedWith: household, to: repository, ids: &ids)
                    committed = (plan, try await repository.load())
                }

                // Check 1: the oracle.
                let actualDecisions: [(Int, CommitOracle.Decision)] = committed.plan.drafts.map {
                    switch $0.decision {
                    case let .created(id): ($0.draftID, .created(id))
                    case let .alreadyOnList(id): ($0.draftID, .alreadyOnList(id))
                    case let .sameChoreAsDraft(k): ($0.draftID, .sameChoreAsDraft(k))
                    }
                }
                let same = actualDecisions.count == expected.decisions.count
                    && zip(actualDecisions, expected.decisions).allSatisfy { $0.0 == $1.draftID && $0.1 == $1.decision }
                if !same || committed.plan.newRooms != expected.newRooms || committed.plan.newTasks != expected.newTasks {
                    mismatches += 1
                    if mismatches <= 3 {
                        Issue.record("\(label): commit \(actualDecisions) rooms \(committed.plan.newRooms) != oracle \(expected.decisions) rooms \(expected.newRooms)")
                    }
                }
                for (key, value) in expected.skips {
                    counts[key, default: 0] += value
                    for kind in ["danglingRoomID", "removedSinceParse"] where key.hasSuffix(kind) { counts[kind, default: 0] += value }
                }
                for (key, value) in expected.path { counts[key, default: 0] += value }

                // Check 2: ground truth, from the plants and the stored household only.
                func miss(_ what: String) {
                    truthMisses += 1
                    if truthMisses <= 5 { Issue.record("\(label): \(what)") }
                }
                let stored = committed.stored
                if stored != Household(tasks: atCommit.tasks + committed.plan.newTasks,
                                       rooms: atCommit.rooms + committed.plan.newRooms) {
                    miss("the repository does not hold exactly the old household plus the new rooms and tasks")
                }
                if Array(stored.tasks.prefix(atCommit.tasks.count)) != atCommit.tasks
                    || Array(stored.rooms.prefix(atCommit.rooms.count)) != atCommit.rooms {
                    miss("an existing task or room was overwritten")
                }
                let pointedTo = Set((atCommit.tasks + household.tasks).compactMap(\.roomID))
                if committed.plan.newRooms.contains(where: { pointedTo.contains($0.id) }) {
                    miss("a new room took an ID an existing task points to")
                }
                let removed = Set(household.tasks.map(\.id)).subtracting(atCommit.tasks.map(\.id))
                if committed.plan.newTasks.contains(where: { removed.contains($0.id) }) {
                    miss("a new task reused the ID of a task removed since the parse")
                }
                let allIDs = stored.tasks.map(\.id) + stored.rooms.map(\.id)
                if Set(allIDs).count != allIDs.count { miss("an ID is repeated") }
                let liveAtCommit = atCommit.tasks.filter { $0.state != .completed }
                var createdFrom: [Int: HouseholdTask] = [:]
                for entry in committed.plan.drafts {
                    if case let .created(id) = entry.decision { createdFrom[entry.draftID] = stored.tasks.first { $0.id == id } }
                }
                for (draftID, task) in createdFrom {
                    guard let (p, scriptedTarget) = planOf[draftID] else { continue }
                    let key = "\(mode.rawValue).\(p.plant.rawValue).created"
                    counts[key, default: 0] += 1
                    let room: DraftRoom = task.roomID.map { .existing($0) } ?? .none
                    if DupOracle.wordMatch(task.title, room, Household(tasks: liveAtCommit, rooms: stored.rooms)) != nil {
                        miss("draft \(draftID) (\(p.plant.rawValue)) was committed as a repeat of a task live at commit")
                    }
                    if p.plant == .inInput { miss("draft \(draftID): an in-input repeat was committed") }
                    if let scriptedTarget, liveAtCommit.contains(where: { $0.id == scriptedTarget }) {
                        miss("draft \(draftID): a scripted repeat of a live task was committed")
                    }
                    if let scriptedTarget, let target = p.target, scriptedTarget != target.id {
                        counts["\(mode.rawValue).claimNamedATwin.created", default: 0] += 1
                    }
                    if p.plant == .synonym && scriptedTarget == nil { counts["\(mode.rawValue).synonymNotScripted.created", default: 0] += 1 }
                }
                // No two tasks committed together repeat each other, unless the later one was not flagged at all at
                // parse time: a missed in-input repeat, which the floor does not cover (PO WI-M2-07 watch item).
                let created = createdFrom.sorted { $0.key < $1.key }
                for (i, a) in created.enumerated() {
                    for b in created[(i + 1)...] {
                        let room: DraftRoom = b.value.roomID.map { .existing($0) } ?? .none
                        guard DupOracle.wordMatch(b.value.title, room, Household(tasks: [a.value], rooms: stored.rooms)) != nil
                        else { continue }
                        if marks[b.key] == DraftDuplicate.none {
                            counts["\(mode.rawValue).unflaggedInInputPairCreated", default: 0] += 1
                        } else {
                            miss("drafts \(a.key) and \(b.key) were both committed as the same chore")
                        }
                    }
                }
                // Confirmed ofDraft(k) never created (PO WI-M2-07 ruling 2), whatever happened to k.
                for draft in confirmed {
                    if case let .ofDraft(k) = marks[draft.draftID] ?? .none {
                        counts[confirmed.contains { $0.draftID == k } ? "ofDraft.kConfirmed" : "ofDraft.kNotConfirmed",
                               default: 0] += 1
                        if createdFrom[draft.draftID] != nil { miss("draft \(draft.draftID): ofDraft(\(k)) was created") }
                    }
                }
                counts["newRooms", default: 0] += committed.plan.newRooms.count
                let proposalsOfCreated = confirmed.filter { createdFrom[$0.draftID] != nil }.compactMap {
                    if case let .proposed(name) = $0.room { CommitOracle.nameFold(name) } else { nil }
                }
                if Set(proposalsOfCreated).count < proposalsOfCreated.count { counts["roomFoldShared", default: 0] += 1 }
                let added = Set(atCommit.rooms.map(\.id)).subtracting(household.rooms.map(\.id))
                if createdFrom.values.contains(where: { $0.roomID.map(added.contains) ?? false }) {
                    counts["roomAddedSinceParseUsed", default: 0] += 1
                }
                if Set(stored.rooms.map { CommitOracle.nameFold($0.name) }).count
                    < Set(atCommit.rooms.map { CommitOracle.nameFold($0.name) }).count + committed.plan.newRooms.count {
                    miss("a new room folds equal to another room")
                }
            }
        }
        print("WI-M2-08 commit property: seed 0x\(String(seed, radix: 16, uppercase: true)), \(Self.householdsPerSeed) households × 3 paths, "
              + "\(mismatches) oracle mismatches, \(truthMisses) ground-truth misses; counts \(counts.sorted { $0.key < $1.key })")
        #expect(mismatches == 0, "seed 0x\(String(seed, radix: 16))")
        #expect(truthMisses == 0, "seed 0x\(String(seed, radix: 16))")
        // Coverage on every seed.
        for key in ["room.taskIDInUse", "room.roomIDInUse", "room.issuedAgain", "task.taskIDInUse", "task.roomIDInUse",
                    "task.issuedAgain", "danglingRoomID", "removedSinceParse", "targetCompletedCreated", "targetRemovedCreated", "goneTargetFloorAtCommit", "goneTargetLiveTwin",
                    "ofDraft.kConfirmed", "ofDraft.kNotConfirmed", "newRooms", "roomFoldShared",
                    "roomAddedSinceParseUsed", "jsonFileCommits"] {
            #expect(counts[key, default: 0] > 0, "seed 0x\(String(seed, radix: 16)): no \(key)")
        }
        for mode in DupOracle.Mode.allCases {
            for plant in [Plant.fresh, .exact, .completedRepeat] {
                #expect(counts["\(mode.rawValue).\(plant.rawValue).created", default: 0] > 0,
                        "seed 0x\(String(seed, radix: 16)): no \(mode.rawValue).\(plant.rawValue).created")
            }
        }
    }
}
