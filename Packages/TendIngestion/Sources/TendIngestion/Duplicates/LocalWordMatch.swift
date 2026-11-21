// The local word-match for cloud drafts when Q12 is no (brief Definitions "Local duplicate re-check for cloud
// drafts"). FR-A1, AC-M2-07, AC-M2-08, AC-M2-26. Plan WI-M2-07.
//
// It relies on the parse-time invariant "a proposed room never equals an existing room" (PO WI-M2-05 ruling 1:
// the mapper re-links a calmed name), so a proposed room is never compatible with a task that has a room. Commit
// re-checks rooms on its own (PO WI-M2-04 ruling 2b).

import Foundation
import TendCore

public enum LocalWordMatch {

    /// The existing task `draft` repeats under the word-match rule, or nil.
    public static func target(for draft: IngestionDraft, in household: Household) -> HouseholdTask.ID? {
        target(title: draft.title, room: draft.room, in: household)
    }

    /// A task t qualifies when all of these hold:
    /// - t is not `completed`;
    /// - both titles have keywords;
    /// - the keyword sets are equal, or the smaller is a subset of the larger and has ≥ 2 keywords;
    /// - the rooms are compatible: either side has no room, or both are the same existing room.
    /// The qualifying task with the most shared keywords wins, then the lowest `id.uuidString` (UTF-8 byte order).
    /// A task's room is the first household room with its `roomID`; a `roomID` with no such room means no room. The
    /// same holds for the draft: `existing(id)` with no such room counts as no room (review R21-F4; unreachable at parse
    /// time, because the mapper links only to the household's rooms).
    public static func target(title: String, room: DraftRoom, in household: Household) -> HouseholdTask.ID? {
        let draftKeywords = Set(Keywords.of(title))
        guard !draftKeywords.isEmpty else { return nil }
        var roomIDs: Set<Room.ID> = []
        for existing in household.rooms { roomIDs.insert(existing.id) }

        var best: (id: HouseholdTask.ID, shared: Int)?
        for task in household.tasks where task.state != .completed {
            let taskKeywords = Set(Keywords.of(task.title))
            guard !taskKeywords.isEmpty, keywordSetsMatch(draftKeywords, taskKeywords) else { continue }
            let taskRoom = task.roomID.flatMap { roomIDs.contains($0) ? $0 : nil }
            guard roomsCompatible(room, taskRoom, roomIDs: roomIDs) else { continue }
            let shared = draftKeywords.intersection(taskKeywords).count
            if let current = best {
                if shared > current.shared
                    || (shared == current.shared
                        && TextFolding.utf8Precedes(task.id.uuidString, current.id.uuidString)) {
                    best = (task.id, shared)
                }
            } else {
                best = (task.id, shared)
            }
        }
        return best?.id
    }

    /// Equal sets, or the smaller is a subset of the larger and has at least 2 keywords.
    static func keywordSetsMatch(_ a: Set<String>, _ b: Set<String>) -> Bool {
        if a == b { return true }
        let (smaller, larger) = a.count <= b.count ? (a, b) : (b, a)
        return smaller.count >= 2 && smaller.isSubset(of: larger)
    }

    static func roomsCompatible(_ draftRoom: DraftRoom, _ taskRoom: Room.ID?, roomIDs: Set<Room.ID>) -> Bool {
        guard let taskRoom else { return true }
        switch draftRoom {
        case .none: return true
        case .proposed: return false
        case let .existing(id): return id == taskRoom || !roomIDs.contains(id)
        }
    }
}
