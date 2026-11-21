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
    public static func commitPlan(
        for confirmed: [DraftRoom],
        existing rooms: [Room],
        makeID: () -> UUID
    ) -> RoomCommitPlan {
        let existingIDs = Set(rooms.map(\.id))
        var created: [String: Room.ID] = [:]
        var newRooms: [Room] = []
        var roomIDs: [Room.ID?] = []
        for room in confirmed {
            switch room {
            case let .existing(id):
                roomIDs.append(existingIDs.contains(id) ? id : nil)
            case .none:
                roomIDs.append(nil)
            case let .proposed(name):
                let folded = TextFolding.foldName(name)
                if folded.isEmpty {
                    roomIDs.append(nil)
                } else if let match = lowestRoom(foldingTo: folded, in: rooms) {
                    roomIDs.append(match.id)
                } else if let id = created[folded] {
                    roomIDs.append(id)
                } else {
                    let newRoom = Room(id: makeID(), name: name)
                    created[folded] = newRoom.id
                    newRooms.append(newRoom)
                    roomIDs.append(newRoom.id)
                }
            }
        }
        return RoomCommitPlan(newRooms: newRooms, roomIDs: roomIDs)
    }

    /// The room with the lowest `id.uuidString` among those whose folded name equals `folded`.
    static func lowestRoom(foldingTo folded: String, in rooms: [Room]) -> Room? {
        rooms
            .filter { TextFolding.foldName($0.name) == folded }
            .min { TextFolding.utf8Precedes($0.id.uuidString, $1.id.uuidString) }
    }
}
