import Foundation

/// A room in the household (AC-M1-01, FR-B3 data only).
/// `lastTendedAt` is the only room-recency datum; the model keeps no count of untended tasks per room (design.md).
public struct Room: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// When a task in this room was last completed, if ever. Set by completion (WI-M1-04).
    public var lastTendedAt: Date?

    public init(id: UUID, name: String, lastTendedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.lastTendedAt = lastTendedAt
    }
}
