// The room of an ingestion draft (brief Definitions, "Draft", T-03): an existing household room, a proposed new room
// (created only on commit, AC-M2-04), or no room. FR-A1.

import Foundation
import TendCore

public enum DraftRoom: Sendable, Hashable {
    /// Linked to this existing household room (name folding, AC-M2-04).
    case existing(Room.ID)
    /// A new room the model proposed. The name is the model's text after the calm-words guard (AC-M2-12). It is
    /// created only on commit.
    case proposed(String)
    /// No room.
    case none
}
