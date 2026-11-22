// WI-M2-08: `DraftCommit.commit(confirmed:parsedWith:to:ids:)`, the only write path of the ingestion layer. AC-M2-06, AC-M2-04
// (rooms created only on commit), AC-M2-07 ("commit creates nothing for it"), AC-M2-08 (commit half; the property is
// in `CommitPropertyTests.swift`). FR-A1, Q7, Q10 (W3-F6). Tickets R19-F1, R19-F2 (review-WI-M2-04.md), PO WI-M2-04
// ruling 2, PO WI-M2-07 ruling 2.
//
// Every repository test runs against both M1 repositories (`InMemoryHouseholdRepository` and
// `JSONFileHouseholdRepository` in a temporary directory, AC-M1-04): the contract the brief asks for. Expected values
// are written by hand from the brief's Definitions and the PO rulings.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Test doubles

/// IDs from a fixed script, then `F…01`, `F…02`, … (fresh, never in use). Records how many were drawn.
struct ScriptedIDs: CommitIDGenerator {
    var script: [UUID]
    var draws = 0
    var freshCount = 0

    init(_ script: [UUID] = []) { self.script = script }

    mutating func next() -> UUID {
        draws += 1
        if !script.isEmpty { return script.removeFirst() }
        freshCount += 1
        return CommitFixtures.fresh(freshCount)
    }
}

/// A generator that only ever returns IDs already in use.
struct StuckIDs: CommitIDGenerator {
    let inUse: [UUID]
    var draws = 0
    mutating func next() -> UUID {
        draws += 1
        return inUse[draws % inUse.count]
    }
}

/// A repository that records every call, over an in-memory store. It can refuse the load, or refuse the n-th write.
actor SpyRepository: HouseholdRepository {
    enum Call: Hashable, Sendable {
        case load, save, upsertTask(UUID), removeTask(UUID), updateRoom(UUID)
        var isWrite: Bool { self != .load }
    }

    private let inner: InMemoryHouseholdRepository
    private let loadError: HouseholdStoreError?
    private let refusedWrite: Int?
    private var writes = 0
    private(set) var calls: [Call] = []

    private init(inner: InMemoryHouseholdRepository, loadError: HouseholdStoreError?, refusedWrite: Int?) {
        self.inner = inner
        self.loadError = loadError
        self.refusedWrite = refusedWrite
    }

    static func make(_ household: Household, loadError: HouseholdStoreError? = nil, refusedWrite: Int? = nil)
        async throws -> SpyRepository {
        let inner = InMemoryHouseholdRepository()
        try await inner.save(household)
        return SpyRepository(inner: inner, loadError: loadError, refusedWrite: refusedWrite)
    }

    /// The stored household, read without recording a call.
    func stored() async throws -> Household { try await inner.load() }

    func load() async throws(HouseholdStoreError) -> Household {
        calls.append(.load)
        if let loadError { throw loadError }
        return try await inner.load()
    }

    func save(_ household: Household) async throws(HouseholdStoreError) {
        try write(.save)
        try await inner.save(household)
    }

    func upsertTask(_ task: HouseholdTask) async throws(HouseholdStoreError) {
        try write(.upsertTask(task.id))
        try await inner.upsertTask(task)
    }

    func removeTask(id: HouseholdTask.ID) async throws(HouseholdStoreError) {
        try write(.removeTask(id))
        try await inner.removeTask(id: id)
    }

    func updateRoom(_ room: Room) async throws(HouseholdStoreError) {
        try write(.updateRoom(room.id))
        try await inner.updateRoom(room)
    }

    private func write(_ call: Call) throws(HouseholdStoreError) {
        calls.append(call)
        writes += 1
        if writes == refusedWrite { throw .writeUnsuccessful }
    }
}

/// The two M1 repositories (AC-M1-04), for the contract tests.
enum CommitRepositoryKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory, jsonFile
    var testDescription: String {
        self == .inMemory ? "InMemoryHouseholdRepository" : "JSONFileHouseholdRepository"
    }
}

enum CommitFixtures {
    static let id = DupFixture.id
    static let kitchen = MappingFixtures.kitchen        // …00000000000A
    static let bathroom = MappingFixtures.bathroom      // …00000000000B
    static let pods = DupFixture.task(id("000000000001"), "Buy dish pods", kind: .restock, room: kitchen.id)
    static let counter = DupFixture.task(id("000000000002"), "Wipe kitchen counter", room: kitchen.id)
    static let oven = DupFixture.task(id("000000000003"), "Clean the oven", kind: .recurring)
    static let household = Household(tasks: [pods, counter, oven], rooms: [kitchen, bathroom])

    /// `F0000000-0000-0000-0000-0000000000nn`: never in use in these fixtures.
    static func fresh(_ n: Int) -> UUID {
        let hex = String(n, radix: 16)
        return UUID(uuidString: "F0000000-0000-0000-0000-" + String(repeating: "0", count: 12 - hex.count) + hex)
            ?? DupFixture.zeroUUID
    }

    static func draft(_ draftID: Int, _ title: String, room: DraftRoom = .none, _ duplicate: DraftDuplicate = .none)
        -> IngestionDraft {
        var draft = DupFixture.draft(draftID, title, room: room)
        draft.duplicate = duplicate
        return draft
    }

    /// The task commit should add for `draft` (the M1 initialiser via the draft's own mapping, AC-M2-01).
    static func task(_ draft: IngestionDraft, _ id: UUID, room: UUID?) -> HouseholdTask? {
        try? draft.task(id: id, roomID: room)
    }

    static func withState(_ task: HouseholdTask, _ state: DupFixture.StateChoice) -> HouseholdTask {
        DupFixture.task(task.id, task.title, kind: task.kind, room: task.roomID, state: state)
    }

    /// Runs `body` with a repository of `kind` that holds `household`. File repositories live in a new temporary
    /// directory that is removed afterwards. `reopen` gives a second instance on the same storage (a restart).
    static func withRepository<T>(
        _ kind: CommitRepositoryKind, holding household: Household,
        _ body: (_ repository: any HouseholdRepository, _ reopen: () throws -> any HouseholdRepository) async throws -> T
    ) async throws -> T {
        switch kind {
        case .inMemory:
            let repository = InMemoryHouseholdRepository()
            try await repository.save(household)
            return try await body(repository, { repository })
        case .jsonFile:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TendIngestionCommit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fileURL = directory.appendingPathComponent("household.json")
            let repository = try JSONFileHouseholdRepository(fileURL: fileURL)
            try await repository.save(household)
            return try await body(repository, { try JSONFileHouseholdRepository(fileURL: fileURL) })
        }
    }
}

private typealias C = CommitFixtures

// MARK: - Contract over both M1 repositories

@Suite("AC-M2-06: commit(confirmed:) over both M1 repositories (FR-A1, AC-M2-04, Q7, Q10)")
struct CommitRepositoryContractTests {

    @Test("AC-M2-06: exactly the confirmed drafts that are not duplicates are upserted, with their proposed rooms; nothing else changes", arguments: CommitRepositoryKind.allCases)
    func confirmedNonDuplicatesOnly(kind: CommitRepositoryKind) async throws {
        let d1 = C.draft(1, "Mend the fence", room: .proposed("Porch"))
        let d2 = C.draft(2, "Refill dish pods", .ofExisting(C.pods.id))
        let d3 = C.draft(3, "Call the plumber", room: .existing(C.bathroom.id))
        let d4 = C.draft(4, "mend fence", room: .proposed("Porch"), .ofDraft(1))
        let d5 = C.draft(5, "Sweep the porch", room: .proposed("the  PORCH"))
        let unconfirmed = C.draft(6, "Bake bread", room: .proposed("Pantry"))
        _ = unconfirmed   // parsed but never passed to commit: it must not be saved
        try await C.withRepository(kind, holding: C.household) { repository, reopen in
            var ids = ScriptedIDs()
            let plan = try await DraftCommit.commit(confirmed: [d1, d2, d3, d4, d5], parsedWith: C.household, to: repository, ids: &ids)
            // Draw order: draft 1's new room, then its task; draft 3's task; draft 5's task (its room is draft 1's).
            let porch = Room(id: C.fresh(1), name: "Porch")
            #expect(plan.drafts == [
                CommittedDraft(draftID: 1, decision: .created(C.fresh(2))),
                CommittedDraft(draftID: 2, decision: .alreadyOnList(C.pods.id)),
                CommittedDraft(draftID: 3, decision: .created(C.fresh(3))),
                CommittedDraft(draftID: 4, decision: .sameChoreAsDraft(1)),
                CommittedDraft(draftID: 5, decision: .created(C.fresh(4))),
            ])
            #expect(plan.newRooms == [porch])
            let added = [C.task(d1, C.fresh(2), room: porch.id), C.task(d3, C.fresh(3), room: C.bathroom.id),
                         C.task(d5, C.fresh(4), room: porch.id)].compactMap { $0 }
            #expect(added.count == 3)
            #expect(plan.newTasks == added)
            let expected = Household(tasks: C.household.tasks + added, rooms: C.household.rooms + [porch])
            #expect(try await repository.load() == expected)
            #expect(try await reopen().load() == expected)
            #expect(added.allSatisfy { $0.state == .active && $0.completedAt == nil })
            #expect(ids.draws == 4)
        }
    }

    @Test("AC-M2-06: dismissed drafts and drafts left unconfirmed are not saved (nothing confirmed: nothing read or written)", arguments: CommitRepositoryKind.allCases)
    func nothingConfirmed(kind: CommitRepositoryKind) async throws {
        try await C.withRepository(kind, holding: C.household) { repository, _ in
            var ids = ScriptedIDs()
            let plan = try await DraftCommit.commit(confirmed: [], parsedWith: C.household, to: repository, ids: &ids)
            #expect(plan == CommitPlan(drafts: [], newRooms: [], newTasks: []))
            #expect(try await repository.load() == C.household)
            #expect(ids.draws == 0)
        }
    }

    /// PO WI-M2-07 ruling 2: k confirmed / dismissed / unconfirmed.
    enum DraftKFate: String, CaseIterable, Sendable { case confirmed, dismissed, unconfirmed }

    @Test("PO WI-M2-07 ruling 2 (AC-M2-06): a confirmed ofDraft(k) is never created; if draft k is not committed, that chore is not created", arguments: DraftKFate.allCases, CommitRepositoryKind.allCases)
    func ofDraftNeverCreated(fate: DraftKFate, kind: CommitRepositoryKind) async throws {
        let k = C.draft(1, "Buy bread")
        let repeatOfK = C.draft(2, "Get bread", .ofDraft(1))
        // Dismissed and unconfirmed both mean "not passed to commit"; the review surface keeps them apart (M3).
        let confirmed = fate == .confirmed ? [k, repeatOfK] : [repeatOfK]
        try await C.withRepository(kind, holding: C.household) { repository, _ in
            var ids = ScriptedIDs()
            let plan = try await DraftCommit.commit(confirmed: confirmed, parsedWith: C.household, to: repository, ids: &ids)
            let stored = try await repository.load()
            let breadTasks = stored.tasks.filter { $0.title.lowercased().contains("bread") }
            #expect(plan.drafts.last == CommittedDraft(draftID: 2, decision: .sameChoreAsDraft(1)))
            switch fate {
            case .confirmed:
                #expect(breadTasks.map(\.title) == ["Buy bread"])
                #expect(plan.drafts.first == CommittedDraft(draftID: 1, decision: .created(C.fresh(1))))
            case .dismissed, .unconfirmed:
                #expect(breadTasks.isEmpty)
                #expect(stored == C.household)
                #expect(ids.draws == 0)
            }
        }
    }

    @Test("R19-F2 (AC-M2-06, W3-F6): the generator's in-use task IDs, in-use room IDs and repeats are skipped; commit takes the next one and never overwrites", arguments: CommitRepositoryKind.allCases)
    func collisionSkip(kind: CommitRepositoryKind) async throws {
        let d1 = C.draft(1, "Mend the fence", room: .proposed("Porch"))
        let d2 = C.draft(2, "Call the plumber")
        let d3 = C.draft(3, "Paint the gate")
        try await C.withRepository(kind, holding: C.household) { repository, reopen in
            // Room of draft 1: pods (a task ID in use), kitchen (a room ID in use), then F…01.
            // Task of draft 1: F…01 again (issued in this commit), oven (in use), then F…02.
            // Task of draft 2: bathroom (a room ID in use: no task ever takes a room's ID either), then F…03.
            // Task of draft 3: counter (in use), then F…04.
            var ids = ScriptedIDs([C.pods.id, C.kitchen.id, C.fresh(1), C.fresh(1), C.oven.id, C.fresh(2),
                                   C.bathroom.id, C.fresh(3), C.counter.id])
            ids.freshCount = 3
            let plan = try await DraftCommit.commit(confirmed: [d1, d2, d3], parsedWith: C.household, to: repository, ids: &ids)
            #expect(plan.newRooms == [Room(id: C.fresh(1), name: "Porch")])
            #expect(plan.newTasks.map(\.id) == [C.fresh(2), C.fresh(3), C.fresh(4)])
            #expect(ids.draws == 10)
            for stored in [try await repository.load(), try await reopen().load()] {
                // Never overwrites: every task and room that was there is still there, unchanged.
                #expect(Array(stored.tasks.prefix(3)) == C.household.tasks)
                #expect(Array(stored.rooms.prefix(2)) == C.household.rooms)
                #expect(stored.tasks.count == 6 && stored.rooms.count == 3)
                let all = stored.tasks.map(\.id) + stored.rooms.map(\.id)
                #expect(Set(all).count == all.count, "no two tasks (or rooms) share an ID")
            }
        }
    }

    @Test("R19-F2: a generator that only returns IDs in use ends with idGeneratorExhausted before any write", arguments: CommitRepositoryKind.allCases)
    func stuckGenerator(kind: CommitRepositoryKind) async throws {
        try await C.withRepository(kind, holding: C.household) { repository, _ in
            var ids = StuckIDs(inUse: [C.pods.id, C.kitchen.id])
            do {
                _ = try await DraftCommit.commit(confirmed: [C.draft(1, "Call the plumber")], parsedWith: C.household, to: repository, ids: &ids)
                Issue.record("a generator stuck on IDs in use must end the commit")
            } catch {
                #expect((error as? CommitError) == .idGeneratorExhausted)
            }
            let stored = try await repository.load()
            #expect(stored == C.household)
            // Bounded: in-use count + 1,024 draws for the one ID, then it stops (no hang).
            #expect(ids.draws == 5 + 1_024)
        }
    }

    @Test("AC-M2-06 re-check: an ofExisting target completed or removed by commit time is treated as not a duplicate, and the draft is created", arguments: CommitRepositoryKind.allCases)
    func targetGoneCreates(kind: CommitRepositoryKind) async throws {
        let draft = C.draft(1, "Buy dish pods", room: .existing(C.kitchen.id), .ofExisting(C.pods.id))
        let completed = Household(tasks: [C.withState(C.pods, .completed), C.counter, C.oven], rooms: C.household.rooms)
        let removed = Household(tasks: [C.counter, C.oven], rooms: C.household.rooms)
        for atCommit in [completed, removed] {
            try await C.withRepository(kind, holding: atCommit) { repository, _ in
                var ids = ScriptedIDs()
                let plan = try await DraftCommit.commit(confirmed: [draft], parsedWith: C.household, to: repository, ids: &ids)
                #expect(plan.drafts == [CommittedDraft(draftID: 1, decision: .created(C.fresh(1)))])
                let added = C.task(draft, C.fresh(1), room: C.kitchen.id)
                #expect(try await repository.load() == Household(tasks: atCommit.tasks + [added].compactMap { $0 },
                                                                  rooms: atCommit.rooms))
            }
        }
    }

    @Test("AC-M2-07 / Q7: an ofExisting target that is still not completed creates nothing and is not changed, whatever its other state", arguments: CommitRepositoryKind.allCases)
    func liveTargetUnchanged(kind: CommitRepositoryKind) async throws {
        for state in [DupFixture.StateChoice.active, .deferred, .maintenance, .resurfaced] {
            let target = C.withState(C.pods, state)
            let atCommit = Household(tasks: [target, C.counter, C.oven], rooms: C.household.rooms)
            try await C.withRepository(kind, holding: atCommit) { repository, _ in
                var ids = ScriptedIDs()
                let plan = try await DraftCommit.commit(
                    confirmed: [C.draft(1, "Refill it", room: .proposed("Utility"), .ofExisting(C.pods.id))],
                    parsedWith: C.household, to: repository, ids: &ids)
                #expect(plan == CommitPlan(drafts: [CommittedDraft(draftID: 1, decision: .alreadyOnList(C.pods.id))],
                                           newRooms: [], newTasks: []), "state \(state)")
                #expect(try await repository.load() == atCommit, "a not-created draft's proposed room is not created")
                #expect(ids.draws == 0)
            }
        }
    }

    @Test("Proposed rooms (AC-M2-04, PO WI-M2-04 ruling 2): names that fold equal create one room named by the lowest draftID; a name equal to a room added since the parse uses it; a gone existing room gives no room", arguments: CommitRepositoryKind.allCases)
    func proposedRooms(kind: CommitRepositoryKind) async throws {
        let attic = Room(id: C.id("0000000000AA"), name: "Attic")   // added between parse and commit
        let goneRoom = C.id("0000000000EE")
        let d1 = C.draft(1, "Mend the fence", room: .proposed("The Porch"))
        let d2 = C.draft(2, "Sweep up leaves", room: .proposed("porch"))
        let d3 = C.draft(3, "Store the fan", room: .proposed("my attic"))
        let d4 = C.draft(4, "Fix the shelf", room: .existing(goneRoom))
        let d5 = C.draft(5, "Oil the hinges", room: .proposed("Porch "))
        let atCommit = Household(tasks: C.household.tasks, rooms: C.household.rooms + [attic])
        try await C.withRepository(kind, holding: atCommit) { repository, _ in
            var ids = ScriptedIDs()
            // Passed out of order: commit runs in ascending draftID, so draft 1's text names the room.
            let plan = try await DraftCommit.commit(confirmed: [d5, d2, d4, d1, d3], parsedWith: C.household, to: repository, ids: &ids)
            let porch = Room(id: C.fresh(1), name: "The Porch")
            #expect(plan.newRooms == [porch])
            #expect(plan.newTasks.map(\.roomID) == [porch.id, porch.id, attic.id, nil, porch.id])
            #expect(plan.newTasks.map(\.id) == [C.fresh(2), C.fresh(3), C.fresh(4), C.fresh(5), C.fresh(6)])
            let stored = try await repository.load()
            #expect(stored.rooms == atCommit.rooms + [porch])
            #expect(stored.tasks.map(\.title) == C.household.tasks.map(\.title)
                    + ["Mend the fence", "Sweep up leaves", "Store the fan", "Fix the shelf", "Oil the hinges"])
        }
    }

    @Test("R19-F1 (PO WI-M2-04 ruling 2b): a proposal that folds equal to two existing rooms uses the lowest id.uuidString, in any array order", arguments: CommitRepositoryKind.allCases)
    func proposalTieLowestUUID(kind: CommitRepositoryKind) async throws {
        let low = Room(id: C.id("000000000001"), name: "the  KITCHEN")
        let high = Room(id: C.id("0000000000FF"), name: "Kitchen")
        let middle = Room(id: C.id("000000000080"), name: "Kitchen\u{00A0}")
        for rooms in [[low, high, middle], [high, middle, low], [middle, low, high]] {
            let atCommit = Household(tasks: [], rooms: rooms)
            try await C.withRepository(kind, holding: atCommit) { repository, _ in
                var ids = ScriptedIDs()
                let plan = try await DraftCommit.commit(
                    confirmed: [C.draft(1, "Descale the kettle", room: .proposed("Kitchen"))], parsedWith: atCommit,
                    to: repository, ids: &ids)
                #expect(plan.newRooms.isEmpty)
                #expect(plan.newTasks.map(\.roomID) == [low.id], "rooms \(rooms.map(\.name))")
                #expect(try await repository.load().rooms == rooms)
            }
        }
    }
}

// MARK: - Commit rules (pure plan; the repository contract above covers the writes)

@Suite("AC-M2-06 / AC-M2-08: commit decisions, order and errors (FR-A1)")
struct CommitRuleTests {

    static func plan(_ confirmed: [IngestionDraft], _ household: Household = C.household,
                     parsedWith parsed: Household = C.household) throws -> CommitPlan {
        var ids = ScriptedIDs()
        return try DraftCommit.plan(confirmed: confirmed, parsedWith: parsed, household: household, ids: &ids)
    }

    @Test("R19-F1: RoomLinker.commitPlan picks the lowest id.uuidString among existing rooms that fold equal, in 3 array orders")
    func commitPlanTie() {
        let low = Room(id: C.id("000000000001"), name: "the  KITCHEN")
        let high = Room(id: C.id("0000000000FF"), name: "Kitchen")
        for rooms in [[low, high], [high, low], [high, low, high]] {
            let plan = RoomLinker.commitPlan(for: [.proposed("kitchen")], existing: rooms) { C.fresh(1) }
            #expect(plan == RoomCommitPlan(newRooms: [], roomIDs: [low.id]))
        }
    }

    @Test("AC-M2-06 re-check, target gone: another live task the word-match floor finds is the one already on the list")
    func targetGoneFloorFindsAnother() throws {
        let copy = DupFixture.task(C.id("000000000004"), "buy dish pods", kind: .restock, room: C.kitchen.id)
        let atCommit = Household(tasks: [C.withState(C.pods, .completed), C.counter, C.oven, copy],
                                 rooms: C.household.rooms)
        let plan = try Self.plan([C.draft(1, "Buy dish pods", room: .existing(C.kitchen.id), .ofExisting(C.pods.id))],
                                 atCommit)
        #expect(plan == CommitPlan(drafts: [CommittedDraft(draftID: 1, decision: .alreadyOnList(copy.id))],
                                   newRooms: [], newTasks: []))
    }

    /// How the twin left the household between parse and commit.
    enum Departure: String, CaseIterable, Sendable { case completed, removed }

    @Test("AC-M2-06 re-check, target gone: a live twin of the gone target (same folded title, PO WI-M2-07 D1) is the chore already on the list, even for a synonym draft", arguments: Departure.allCases)
    func goneTargetLiveTwin(departure: Departure) throws {
        // The Tool's title claim resolved to the twin (first match in call order); the twin then left the household.
        let twin = DupFixture.task(C.id("000000000004"), "buy  DISH pods", kind: .restock, room: C.kitchen.id)
        let parsed = Household(tasks: C.household.tasks + [twin], rooms: C.household.rooms)
        let atCommit = Household(tasks: C.household.tasks + (departure == .completed ? [C.withState(twin, .completed)] : []),
                                 rooms: C.household.rooms)
        let plan = try Self.plan([C.draft(1, "Refill it", .ofExisting(twin.id))], atCommit, parsedWith: parsed)
        #expect(plan == CommitPlan(drafts: [CommittedDraft(draftID: 1, decision: .alreadyOnList(C.pods.id))],
                                   newRooms: [], newTasks: []))
        // With no live twin left, the draft is created (the brief's re-check: not a duplicate).
        let neither = Household(tasks: [C.withState(C.pods, .completed), C.counter, C.oven], rooms: C.household.rooms)
        #expect(try Self.plan([C.draft(1, "Refill it", .ofExisting(twin.id))], neither, parsedWith: parsed)
                    .drafts.map(\.decision) == [.created(C.fresh(1))])
    }

    @Test("AC-M2-06 re-check, target gone: a later draft with the same gone target is the same chore as the first one (never a second task)")
    func sameGoneTargetFollowsFirst() throws {
        let atCommit = Household(tasks: [C.withState(C.pods, .completed), C.counter, C.oven], rooms: C.household.rooms)
        let plan = try Self.plan([C.draft(1, "Refill it", .ofExisting(C.pods.id)),
                                  C.draft(2, "dishwasher tablets", .ofExisting(C.pods.id)),
                                  C.draft(3, "the pod thing", .ofExisting(C.pods.id))], atCommit)
        #expect(plan.drafts == [CommittedDraft(draftID: 1, decision: .created(C.fresh(1))),
                                CommittedDraft(draftID: 2, decision: .sameChoreAsDraft(1)),
                                CommittedDraft(draftID: 3, decision: .sameChoreAsDraft(1))])
        #expect(plan.newTasks.map(\.title) == ["Refill it"])
        // When the first one's floor finds a live task, the later ones follow it too.
        let copy = DupFixture.task(C.id("000000000004"), "refill", kind: .restock)
        let withCopy = Household(tasks: atCommit.tasks + [copy], rooms: atCommit.rooms)
        let followed = try Self.plan([C.draft(1, "Refill it", .ofExisting(C.pods.id)),
                                      C.draft(2, "dishwasher tablets", .ofExisting(C.pods.id))], withCopy)
        #expect(followed.drafts.map(\.decision) == [.alreadyOnList(copy.id), .alreadyOnList(copy.id)])
        #expect(followed.newTasks.isEmpty)
    }

    @Test("AC-M2-06 re-check, targets gone: a draft whose gone target's repeat was just created in this commit is the same chore as that draft")
    func goneTargetMatchesTaskCreatedInThisCommit() throws {
        let copy = DupFixture.task(C.id("000000000004"), "buy dish pods", kind: .restock, room: C.kitchen.id)
        let atCommit = Household(tasks: [C.withState(C.pods, .completed), C.counter, C.oven,
                                         C.withState(copy, .completed)], rooms: C.household.rooms)
        let parsed = Household(tasks: C.household.tasks + [copy], rooms: C.household.rooms)
        let plan = try Self.plan([C.draft(1, "Buy dish pods", room: .existing(C.kitchen.id), .ofExisting(C.pods.id)),
                                  C.draft(2, "buy dish pods", room: .existing(C.kitchen.id), .ofExisting(copy.id))],
                                 atCommit, parsedWith: parsed)
        #expect(plan.drafts.map(\.decision) == [.created(C.fresh(1)), .sameChoreAsDraft(1)])
        // A different room is a different chore (word-match rule), so both are created.
        let otherRoom = try Self.plan([
            C.draft(1, "Buy dish pods", room: .existing(C.kitchen.id), .ofExisting(C.pods.id)),
            C.draft(2, "buy dish pods", room: .existing(C.bathroom.id), .ofExisting(copy.id)),
        ], atCommit, parsedWith: parsed)
        #expect(otherRoom.drafts.map(\.decision) == [.created(C.fresh(1)), .created(C.fresh(2))])
    }

    @Test("A none draft is not re-checked at commit (the parse already ran the floor on the same household; PO watch item: missed in-input repeats)")
    func noneDraftNotRechecked() throws {
        let plan = try Self.plan([C.draft(1, "Bake bread"), C.draft(2, "bake bread")])
        #expect(plan.drafts.map(\.decision) == [.created(C.fresh(1)), .created(C.fresh(2))])
    }

    @Test("AC-M2-06: confirmed drafts are committed in ascending draftID whatever order they are passed in (IDs drawn in that order)")
    func ascendingDraftID() throws {
        let drafts = [C.draft(3, "Paint the gate"), C.draft(1, "Mend the fence"), C.draft(2, "Call the plumber")]
        let plan = try Self.plan(drafts)
        #expect(plan.drafts.map(\.draftID) == [1, 2, 3])
        #expect(plan.newTasks.map(\.title) == ["Mend the fence", "Call the plumber", "Paint the gate"])
        #expect(plan.newTasks.map(\.id) == [C.fresh(1), C.fresh(2), C.fresh(3)])
    }

    @Test("The same draft passed twice is committed once; two different drafts with one draftID are refused before any write")
    func repeatedDraftID() async throws {
        let d1 = C.draft(1, "Mend the fence")
        #expect(try Self.plan([d1, d1]).newTasks.count == 1)
        let other = C.draft(1, "Paint the gate")
        #expect(throws: CommitError.draftIDRepeated(1)) { try Self.plan([d1, other]) }
        let spy = try await SpyRepository.make(C.household)
        var ids = ScriptedIDs()
        await #expect(throws: CommitError.draftIDRepeated(1)) {
            try await DraftCommit.commit(confirmed: [other, d1], parsedWith: C.household, to: spy, ids: &ids)
        }
        #expect(await spy.calls == [.load])
    }

    @Test("Writes: every new room first, then each new task in ascending draftID; nothing else is written")
    func writeOrder() async throws {
        let spy = try await SpyRepository.make(C.household)
        var ids = ScriptedIDs()
        _ = try await DraftCommit.commit(confirmed: [
            C.draft(2, "Sweep up leaves", room: .proposed("Porch")),
            C.draft(1, "Store the fan", room: .proposed("Attic")),
            C.draft(3, "Refill it", .ofExisting(C.pods.id)),
        ], parsedWith: C.household, to: spy, ids: &ids)
        // Draft 1: Attic F…01, task F…02. Draft 2: Porch F…03, task F…04.
        #expect(await spy.calls == [.load, .updateRoom(C.fresh(1)), .updateRoom(C.fresh(3)),
                                    .upsertTask(C.fresh(2)), .upsertTask(C.fresh(4))])
    }

    @Test("Errors: an unreadable household and a rejected task are reported before any write; a refused write reports what was written")
    func errors() async throws {
        let unreadable = try await SpyRepository.make(C.household, loadError: .unreadableFile)
        var ids = ScriptedIDs()
        await #expect(throws: CommitError.householdUnreadable(.unreadableFile)) {
            try await DraftCommit.commit(confirmed: [C.draft(1, "Mend the fence")], parsedWith: C.household, to: unreadable, ids: &ids)
        }
        #expect(await unreadable.calls == [.load])

        // A draft the M1 initialiser refuses (unreachable from DraftMapper; a hand-built window that ends at its start).
        let base = C.draft(1, "Mend the fence")
        let invalid = IngestionDraft(
            draftID: 2, title: "Paint the gate", kind: .oneOff, room: .proposed("Porch"), effort: .normal,
            isCritical: false, isDeepClean: false, isWeatherDependent: false, allowedDayparts: base.allowedDayparts,
            allowedWeekdays: base.allowedWeekdays, windowStart: base.windowStart, windowEnd: base.windowStart,
            recurrenceIntervalDays: nil, sourcePhrase: nil)
        let rejecting = try await SpyRepository.make(C.household)
        await #expect(throws: CommitError.taskRejected(draftID: 2, .windowEndNotAfterStart)) {
            try await DraftCommit.commit(confirmed: [base, invalid], parsedWith: C.household, to: rejecting, ids: &ids)
        }
        #expect(await rejecting.calls == [.load])

        let refusing = try await SpyRepository.make(C.household, refusedWrite: 2)
        var fresh = ScriptedIDs()
        let drafts = [C.draft(1, "Mend the fence", room: .proposed("Porch")), C.draft(2, "Call the plumber")]
        var expectedIDs = ScriptedIDs()
        let planned = try DraftCommit.plan(confirmed: drafts, parsedWith: C.household, household: C.household, ids: &expectedIDs)
        await #expect(throws: CommitError.writeStopped(.writeUnsuccessful, planned: planned, roomsWritten: 1,
                                                       tasksWritten: 0)) {
            try await DraftCommit.commit(confirmed: drafts, parsedWith: C.household, to: refusing, ids: &fresh)
        }
        #expect(try await refusing.stored() == Household(tasks: C.household.tasks,
                                                         rooms: C.household.rooms + planned.newRooms))
    }

    @Test("AC-M2-06: a parse writes nothing to the HouseholdRepository; only commit writes")
    func parseWritesNothing() async throws {
        let spy = try await SpyRepository.make(C.household)
        let household = try await spy.load()
        let input = "mend the fence, buy dish pods, and sweep the porch"
        let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: MappingFixtures.newYorkNow,
                                     calendar: MappingFixtures.gregorian,
                                     timeZone: MappingFixtures.zone("America/New_York"),
                                     duplicateCheck: DraftDuplicateRules.onDevice(household: household))
        let model = SnapshotModel([IngestionSnapshot(items: [
            StreamFixtures.full("Mend the fence", room: "Porch", sourcePhrase: "mend the fence"),
            StreamFixtures.full("Buy dish pods", room: "Kitchen", sourcePhrase: "buy dish pods"),
            StreamFixtures.full("Sweep the porch", room: "porch", sourcePhrase: "sweep the porch"),
        ])])
        let run = await collectCapped(pipeline.events(from: .onDevice(model)))
        #expect(!run.capped)
        var summary = DraftStreamSummary()
        for event in run.events { summary.apply(event) }
        #expect(summary.drafts.map(\.duplicate) == [.none, .ofExisting(C.pods.id), .none])
        #expect(await spy.calls == [.load], "the parse made no repository call")
        var ids = ScriptedIDs()
        let plan = try await DraftCommit.commit(confirmed: summary.drafts, parsedWith: C.household, to: spy, ids: &ids)
        #expect(plan.newRooms.map(\.name) == ["Porch"])
        #expect(await spy.calls == [.load, .load, .updateRoom(C.fresh(1)), .upsertTask(C.fresh(2)),
                                    .upsertTask(C.fresh(3))])
    }
}
