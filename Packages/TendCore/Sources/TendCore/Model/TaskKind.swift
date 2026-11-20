import Foundation

/// What sort of household task this is (AC-M1-01, FR-B1).
public enum TaskKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// A one-off errand, for example "post the parcel".
    case oneOff
    /// Recurring maintenance, for example "clean the bathroom" every 7 days. Requires `recurrenceIntervalDays`.
    case recurring
    /// A consumable restock, for example "buy dishwasher tablets".
    case restock
}
