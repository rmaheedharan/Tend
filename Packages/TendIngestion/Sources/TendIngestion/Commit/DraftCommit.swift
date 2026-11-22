// Commit: the only write path of the ingestion layer (brief AC-M2-06, AC-M2-04, AC-M2-07, AC-M2-08; Definitions
// "Draft": "A draft is not in the household until it is committed"). FR-A1, Q7, Q10 (W3-F6), UX-1, P-4.
// Plan WI-M2-08. Rulings: PO WI-M2-04 ruling 2 (rooms at commit), PO WI-M2-07 ruling 2 (a confirmed `ofDraft(k)` is
// never created), the D6 commit order (ascending `draftID`). Review tickets R19-F1, R19-F2.
//
// A parse never writes: `DraftPipeline` has no repository. `DraftCommit` reads the household once, decides every
// confirmed draft in a pure plan (`plan(confirmed:household:ids:)`), and then writes the plan through the
// `HouseholdRepository` protocol and nothing else (no other I/O, no network, no logging).

import Foundation
import TendCore

/// The source of the IDs of new tasks and rooms (AC-M2-06, Q10). It is injected so that commit is deterministic in
/// tests and in the eval harness (T-29); the app passes one that returns `UUID()`. It may return an ID that is already
/// in use or one it returned before: commit skips such IDs and takes the next one (W3-F6).
public protocol CommitIDGenerator {
    mutating func next() -> UUID
}

/// What commit did with one confirmed draft.
public enum CommitDecision: Hashable, Sendable {
    /// A new task was added with this ID.
    case created(HouseholdTask.ID)
    /// The chore is already on the list as this task, which is not completed. Nothing is added, and the task is not
    /// changed (Q7).
    case alreadyOnList(HouseholdTask.ID)
    /// The same chore as the draft with this `draftID` in the same capture. Nothing is added for this draft, whatever
    /// happened to that draft (PO WI-M2-07 ruling 2).
    case sameChoreAsDraft(Int)
}

/// One confirmed draft and what commit did with it.
public struct CommittedDraft: Hashable, Sendable {
    public let draftID: Int
    public let decision: CommitDecision
}

/// The whole result of one commit: what happened to each confirmed draft, and exactly what is written.
public struct CommitPlan: Hashable, Sendable {
    /// One entry per distinct confirmed draft, in ascending `draftID`.
    public let drafts: [CommittedDraft]
    /// The proposed rooms that are created, in the order they were first needed (ascending `draftID`).
    public let newRooms: [Room]
    /// The new tasks, in ascending `draftID`. Each is `active`, never completed.
    public let newTasks: [HouseholdTask]
}

/// Why a commit did not complete. Every case except `writeStopped` means nothing was written.
public enum CommitError: Error, Hashable, Sendable {
    /// The repository could not read the household. Nothing was written.
    case householdUnreadable(HouseholdStoreError)
    /// Two different drafts share this `draftID` (drafts from different captures were mixed). Nothing was written.
    case draftIDRepeated(Int)
    /// The M1 initialiser refused the task for this draft (unreachable for a draft from `DraftMapper`, which has passed
    /// it once, Q5 step 9). Nothing was written.
    case taskRejected(draftID: Int, TaskInvariantViolation)
    /// The ID generator kept returning IDs already in use (more than the number in use + 1,024 draws for one ID).
    /// Nothing was written.
    case idGeneratorExhausted
    /// A write was refused. The first `roomsWritten` of `planned.newRooms` and then the first `tasksWritten` of
    /// `planned.newTasks` are stored; nothing after them is. To finish, commit only the drafts whose tasks were not
    /// written: committing the same drafts again would add their chores twice.
    case writeStopped(HouseholdStoreError, planned: CommitPlan, roomsWritten: Int, tasksWritten: Int)
}

public enum DraftCommit {

    /// Commits the drafts the person confirmed (AC-M2-06). Dismissed drafts and drafts left unconfirmed are simply
    /// not passed, and nothing of them is saved.
    ///
    /// - The confirmed drafts are committed in **ascending `draftID`**, whatever order they are passed in (D6; PO
    ///   WI-M2-04 ruling 2a). That order decides which draft's text names a new room, which draft is created first
    ///   when two have the same chore, and the order the generator's IDs are drawn in. The same draft passed twice
    ///   counts once; two different drafts with one `draftID` are refused (`draftIDRepeated`).
    /// - Each draft is decided by `plan(confirmed:parsedWith:household:ids:)` (rules C1–C5 there) on the household as
    ///   `load()` returns it.
    /// - `parsedWith` is the household value the parse's duplicate rules read (the one given to
    ///   `DraftDuplicateRules`). Commit uses it only to know what an `ofExisting` target was when that target has left
    ///   the household since the parse (rule C3).
    /// - Writes: every new room (`updateRoom`), then every new task (`upsertTask`) in ascending `draftID`, so a task is
    ///   never stored before its room. Nothing else is written; no existing task or room is changed.
    /// - If nothing is confirmed, the repository is not called at all.
    ///
    /// Each repository call is atomic (AC-M1-04), but the commit as a whole is not: a refused write stops it, and
    /// `writeStopped` says exactly what was stored. Another writer that adds tasks between this commit's `load()` and
    /// its writes is not seen by the duplicate re-check (the app runs one commit at a time per household; M5 sync
    /// settles concurrent writers).
    public static func commit<G: CommitIDGenerator>(
        confirmed: [IngestionDraft],
        parsedWith parsed: Household,
        to repository: any HouseholdRepository,
        ids: inout G
    ) async throws(CommitError) -> CommitPlan {
        guard !confirmed.isEmpty else { return CommitPlan(drafts: [], newRooms: [], newTasks: []) }
        let household: Household
        do {
            household = try await repository.load()
        } catch {
            throw .householdUnreadable(error)
        }
        let planned = try plan(confirmed: confirmed, parsedWith: parsed, household: household, ids: &ids)
        var roomsWritten = 0
        var tasksWritten = 0
        do {
            for room in planned.newRooms {
                try await repository.updateRoom(room)
                roomsWritten += 1
            }
            for task in planned.newTasks {
                try await repository.upsertTask(task)
                tasksWritten += 1
            }
        } catch {
            throw .writeStopped(error, planned: planned, roomsWritten: roomsWritten, tasksWritten: tasksWritten)
        }
        return planned
    }

    /// The commit decisions for `confirmed` against `household`, with no side effect except drawing IDs from `ids`.
    /// Drafts are taken in ascending `draftID` (see `commit`). For each draft, by its duplicate marker:
    /// - **C1 `ofDraft(k)`:** `sameChoreAsDraft(k)`. Never created, whether draft k is committed, dismissed or left
    ///   unconfirmed (PO WI-M2-07 ruling 2).
    /// - **C2 `ofExisting(t)`, t still not completed:** `alreadyOnList(t)`. Nothing is created and t is not changed (Q7).
    /// - **C3 `ofExisting(t)`, t completed or gone** (the commit re-check, Definitions): the draft is not a duplicate of
    ///   t. It is still never a second copy of one chore:
    ///   1. if an earlier draft in this commit had the same gone target, this draft follows that draft's decision (it
    ///      is the same chore as t, so the same chore as that draft);
    ///   2. else the word-match floor (`LocalWordMatch`, the Definitions rule) over the household's tasks: a match is
    ///      `alreadyOnList`;
    ///   3. else the floor with **t's own title and room** (t as it was in `parsed`) over the household's tasks: a
    ///      live task that repeats t is the same chore as this draft (two tasks with the same folded title are one
    ///      chore, PO WI-M2-07 ruling 3, D1), so it is `alreadyOnList`. This catches a synonym draft whose claim named a
    ///      twin of a task that is still live;
    ///   4. else the floor with the draft's title over the tasks this commit has created so far: a match is
    ///      `sameChoreAsDraft`;
    ///   5. else it is created.
    ///   For the draft's floor, its room is the room commit would give it.
    /// - **C4 `none`:** created. (The parse already ran the floor on this household, Q7.)
    /// - **C5 rooms and IDs:** a created draft's room is resolved as `RoomLinker.commitPlan` does (AC-M2-04: a proposed
    ///   name that folds to an existing room's name uses that room, lowest `id.uuidString`; names that fold equal make
    ///   one room, named by the lowest `draftID`; a gone `existing` room gives no room). A new room's ID is drawn
    ///   first, then the task's. Every ID skips the household's task and room IDs and the IDs already issued in this
    ///   commit (W3-F6), so nothing is ever overwritten and no two tasks share an ID. A draft that is not created
    ///   creates no room.
    public static func plan<G: CommitIDGenerator>(
        confirmed: [IngestionDraft],
        parsedWith parsed: Household,
        household: Household,
        ids: inout G
    ) throws(CommitError) -> CommitPlan {
        let ordered = try inDraftOrder(confirmed)
        var allocator = CommitIDAllocator(household: household)
        var rooms = CommitRoomResolver(existing: household.rooms)
        var decisions: [CommittedDraft] = []
        var newTasks: [HouseholdTask] = []
        var creatorOfTask: [HouseholdTask.ID: Int] = [:]
        var decisionForGoneTarget: [HouseholdTask.ID: CommitDecision] = [:]

        for draft in ordered {
            var decision: CommitDecision?
            var goneTarget: HouseholdTask.ID?
            switch draft.duplicate {
            case .none:
                decision = nil
            case let .ofDraft(k):
                decision = .sameChoreAsDraft(k)
            case let .ofExisting(t):
                if DuplicateRecheck.atCommit(draft.duplicate, in: household) != .none {
                    decision = .alreadyOnList(t)
                } else {
                    goneTarget = t
                    if let earlier = decisionForGoneTarget[t] {
                        decision = earlier
                    } else {
                        let room = rooms.peek(draft.room)
                        let soFar = rooms.allRooms
                        if let match = LocalWordMatch.target(
                            title: draft.title, room: room, in: Household(tasks: household.tasks, rooms: soFar)) {
                            decision = .alreadyOnList(match)
                        } else if let was = parsed.tasks.first(where: { $0.id == t }),
                                  let twin = LocalWordMatch.target(
                                      title: was.title, room: Self.room(of: was, in: parsed),
                                      in: Household(tasks: household.tasks, rooms: soFar)) {
                            decision = .alreadyOnList(twin)
                        } else if let match = LocalWordMatch.target(
                            title: draft.title, room: room, in: Household(tasks: newTasks, rooms: soFar)),
                            let creator = creatorOfTask[match] {
                            decision = .sameChoreAsDraft(creator)
                        }
                        if let decision { decisionForGoneTarget[t] = decision }
                    }
                }
            }
            if let decision {
                decisions.append(CommittedDraft(draftID: draft.draftID, decision: decision))
                continue
            }
            let roomID = try rooms.resolve(draft.room) { () throws(CommitError) -> UUID in
                try allocator.fresh(&ids)
            }
            let id = try allocator.fresh(&ids)
            let task: HouseholdTask
            do {
                task = try draft.task(id: id, roomID: roomID)
            } catch {
                throw .taskRejected(draftID: draft.draftID, error)
            }
            newTasks.append(task)
            creatorOfTask[id] = draft.draftID
            if let goneTarget { decisionForGoneTarget[goneTarget] = .sameChoreAsDraft(draft.draftID) }
            decisions.append(CommittedDraft(draftID: draft.draftID, decision: .created(id)))
        }
        return CommitPlan(drafts: decisions, newRooms: rooms.newRooms, newTasks: newTasks)
    }

    /// A task's room as a draft room for the word-match: its room when the household has it, else none.
    static func room(of task: HouseholdTask, in household: Household) -> DraftRoom {
        guard let id = task.roomID, household.rooms.contains(where: { $0.id == id }) else { return .none }
        return .existing(id)
    }

    /// The drafts in ascending `draftID` (a stable order), each `draftID` once.
    static func inDraftOrder(_ confirmed: [IngestionDraft]) throws(CommitError) -> [IngestionDraft] {
        let sorted = confirmed.enumerated().sorted {
            ($0.element.draftID, $0.offset) < ($1.element.draftID, $1.offset)
        }.map(\.element)
        var result: [IngestionDraft] = []
        for draft in sorted {
            if let last = result.last, last.draftID == draft.draftID {
                guard last == draft else { throw .draftIDRepeated(draft.draftID) }
                continue
            }
            result.append(draft)
        }
        return result
    }
}

/// Draws IDs that are not in use (W3-F6, AC-M2-06): not a task or room of the household, and not issued earlier in
/// the same commit. An ID the generator returns that is taken is skipped, and the next one is drawn.
struct CommitIDAllocator {
    /// The draws allowed for one ID beyond the number of IDs in use. A generator that never repeats a value needs at
    /// most (number in use + 1) draws; the margin lets a generator repeat itself a little.
    static let extraDraws = 1_024

    private var taken: Set<UUID>

    init(household: Household) {
        taken = Set(household.tasks.map(\.id))
        for room in household.rooms { taken.insert(room.id) }
    }

    mutating func fresh<G: CommitIDGenerator>(_ ids: inout G) throws(CommitError) -> UUID {
        for _ in 0..<(taken.count + Self.extraDraws) {
            let id = ids.next()
            if taken.insert(id).inserted { return id }
        }
        throw .idGeneratorExhausted
    }
}
