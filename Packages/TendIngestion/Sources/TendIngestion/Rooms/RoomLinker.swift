// Room linking with name folding (AC-M2-04; brief Definitions "Name folding", T-09). FR-A1.
//
// Parse time (`link`): a pure function of the model's room text and the household's rooms. It never creates or renames
// a room. Commit time (`commitPlan`): decides which proposed rooms to create and which room each confirmed draft gets.
// It does not change the household either; the caller applies the plan when it commits.

import Foundation
import TendCore

/// Which room each confirmed draft gets on commit, and the new rooms to add (AC-M2-04).
public struct RoomCommitPlan: Sendable, Equatable {
    /// New rooms to add to the household, in the order of the first confirmed draft that proposed each one.
    public let newRooms: [Room]
    /// One entry per confirmed draft, in the same order: the room's ID, or nil for no room.
    public let roomIDs: [Room.ID?]
}

public enum RoomLinker {

    /// Links a draft's room text to the household (AC-M2-04):
    /// - nil, or a name that folds to empty: `none`;
    /// - an existing room whose name equals it after name folding: `existing`; if several do, the lowest
    ///   `id.uuidString` (ascending UTF-8 byte order);
    /// - otherwise `proposed`, with the model's text trimmed and with whitespace runs collapsed. The calm-words guard
    ///   (`CalmWordsGuard.apply`) then runs on the proposed name.
    /// Matching is exact equality after folding, never fuzzy.
    public static func link(_ modelRoomName: String?, in rooms: [Room]) -> DraftRoom {
        guard let modelRoomName else { return .none }
        let folded = TextFolding.foldName(modelRoomName)
        guard !folded.isEmpty else { return .none }
        if let match = lowestRoom(foldingTo: folded, in: rooms) {
            return .existing(match.id)
        }
        return .proposed(TextFolding.collapseWhitespace(modelRoomName))
    }

    /// The commit plan for the confirmed drafts' rooms, in confirmed order (AC-M2-04):
    /// - `existing(id)`: that room, or nil when it is no longer in `rooms`;
    /// - `proposed(name)`: the existing room that folds to the same name (lowest `id.uuidString`), else the room
    ///   created earlier in this plan for the same folded name, else a new room named `name` with an ID from `makeID`.
    ///   So names that fold the same create one room, and no room duplicates an existing one;
    /// - `none`: nil.
    ///
    /// **Precondition on `makeID` (review R19-F2):** it must return an ID that is not in use (no household task or
    /// room has it) and was not returned before. This function does not check it. `DraftCommit` is the caller that
    /// guarantees it: its ID source skips every ID in use or already issued (AC-M2-06, W3-F6).
    public static func commitPlan<E: Error>(
        for confirmed: [DraftRoom],
        existing rooms: [Room],
        makeID: () throws(E) -> UUID
    ) throws(E) -> RoomCommitPlan {
        var resolver = CommitRoomResolver(existing: rooms)
        var roomIDs: [Room.ID?] = []
        for room in confirmed {
            roomIDs.append(try resolver.resolve(room, makeID: makeID))
        }
        return RoomCommitPlan(newRooms: resolver.newRooms, roomIDs: roomIDs)
    }

    /// The room with the lowest `id.uuidString` among those whose folded name equals `folded`.
    static func lowestRoom(foldingTo folded: String, in rooms: [Room]) -> Room? {
        rooms
            .filter { TextFolding.foldName($0.name) == folded }
            .min { TextFolding.utf8Precedes($0.id.uuidString, $1.id.uuidString) }
    }
}

/// Commit-time room resolution, one confirmed draft at a time (AC-M2-04; PO WI-M2-04 ruling 2). `commitPlan` and
/// `DraftCommit` share it, so both apply the same rules in the same order.
struct CommitRoomResolver {
    /// The household's rooms at commit.
    let existing: [Room]
    private let existingIDs: Set<Room.ID>
    /// Rooms created so far, in creation order.
    private(set) var newRooms: [Room] = []
    /// Folded name → the room created for it.
    private var created: [String: Room.ID] = [:]

    init(existing: [Room]) {
        self.existing = existing
        existingIDs = Set(existing.map(\.id))
    }

    /// The household's rooms followed by the ones created so far.
    var allRooms: [Room] { existing + newRooms }

    /// What `resolve` would give, without creating anything: the room, or `proposed(name)` when a new room would be
    /// made. `existing(id)` of a room that is gone, and a name that folds to empty, give `none`.
    func peek(_ room: DraftRoom) -> DraftRoom {
        switch room {
        case .none:
            return .none
        case let .existing(id):
            return existingIDs.contains(id) ? .existing(id) : .none
        case let .proposed(name):
            let folded = TextFolding.foldName(name)
            if folded.isEmpty { return .none }
            if let match = RoomLinker.lowestRoom(foldingTo: folded, in: existing) { return .existing(match.id) }
            if let id = created[folded] { return .existing(id) }
            return .proposed(name)
        }
    }

    /// The room ID a confirmed draft gets; creates a room (ID from `makeID`) when `peek` says a new one is needed.
    mutating func resolve<E: Error>(_ room: DraftRoom, makeID: () throws(E) -> UUID) throws(E) -> Room.ID? {
        switch peek(room) {
        case .none:
            return nil
        case let .existing(id):
            return id
        case let .proposed(name):
            let newRoom = Room(id: try makeID(), name: name)
            created[TextFolding.foldName(name)] = newRoom.id
            newRooms.append(newRoom)
            return newRoom.id
        }
    }
}
