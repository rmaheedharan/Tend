// The duplicate shortlist (brief Definitions "Duplicate shortlist (Q12 pre-filter; T-06), deterministic"). FR-A1,
// AC-M2-07, AC-M2-20 (the Q12 = yes payload titles). Plan WI-M2-07.
//
// A pure function of a query text and the household. Two callers use it:
// - the on-device duplicate `Tool` (through `DuplicateLookup`), where the query is the Tool's argument;
// - the cloud payload when Q12 is yes, where the query is the capture text and only the trimmed titles and index
//   numbers are sent (WI-M2-10).

import Foundation
import TendCore

/// One shortlisted task. `index` is its 1-based rank number; `taskID` stays on the phone (it is never sent and never
/// given to a model).
public struct ShortlistEntry: Hashable, Sendable {
    public let index: Int
    public let taskID: HouseholdTask.ID
    /// The title as stored, trimmed at both ends.
    public let title: String
    public let kind: TaskKind
    /// The name of the task's room, or nil when it has none (or its room is not in the household).
    public let roomName: String?

    public init(index: Int, taskID: HouseholdTask.ID, title: String, kind: TaskKind, roomName: String?) {
        self.index = index
        self.taskID = taskID
        self.title = title
        self.kind = kind
        self.roomName = roomName
    }
}

public enum DuplicateShortlist {

    /// At most this many entries (step 6).
    public static let limit = 10

    /// The shortlist for `query`, steps 1–6:
    /// 1. candidates are the tasks whose state is not `completed`;
    /// 2. K(t) = the number of distinct keywords in both the query and t's title;
    /// 3. R(t) = 1 when t has a room and every keyword of that room's name is a keyword of the query (a room name
    ///    with no keywords never matches), else 0;
    /// 4. t is shortlisted when K(t) ≥ 1 or R(t) = 1;
    /// 5. rank by K descending, R descending, the keyword-folded title in ascending UTF-8 byte order, then
    ///    `id.uuidString` in ascending byte order (and, only if two tasks share an ID, household order);
    /// 6. keep the first 10, numbered 1…n.
    /// A task's room is the first household room with its `roomID`; a `roomID` with no such room means no room.
    public static func entries(for query: String, in household: Household) -> [ShortlistEntry] {
        let queryKeywords = Set(Keywords.of(query))
        var roomsByID: [Room.ID: Room] = [:]
        for room in household.rooms where roomsByID[room.id] == nil {
            roomsByID[room.id] = room
        }

        var ranked: [Ranked] = []
        for (offset, task) in household.tasks.enumerated() where task.state != .completed {
            let room = task.roomID.flatMap { roomsByID[$0] }
            let k = Set(Keywords.of(task.title)).intersection(queryKeywords).count
            var r = 0
            if let room {
                let roomKeywords = Set(Keywords.of(room.name))
                if !roomKeywords.isEmpty && roomKeywords.isSubset(of: queryKeywords) { r = 1 }
            }
            guard k >= 1 || r == 1 else { continue }
            ranked.append(Ranked(task: task, room: room, offset: offset, k: k, r: r,
                                 foldedTitle: TextFolding.foldWithoutArticle(task.title)))
        }
        ranked.sort(by: Ranked.precedes)

        return ranked.prefix(limit).enumerated().map { number, item in
            ShortlistEntry(
                index: number + 1,
                taskID: item.task.id,
                title: item.task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: item.task.kind,
                roomName: item.room?.name
            )
        }
    }

    private struct Ranked {
        let task: HouseholdTask
        let room: Room?
        let offset: Int
        let k: Int
        let r: Int
        let foldedTitle: String

        static func precedes(_ a: Ranked, _ b: Ranked) -> Bool {
            if a.k != b.k { return a.k > b.k }
            if a.r != b.r { return a.r > b.r }
            if a.foldedTitle != b.foldedTitle { return TextFolding.utf8Precedes(a.foldedTitle, b.foldedTitle) }
            let ua = a.task.id.uuidString, ub = b.task.id.uuidString
            if ua != ub { return TextFolding.utf8Precedes(ua, ub) }
            return a.offset < b.offset
        }
    }
}
