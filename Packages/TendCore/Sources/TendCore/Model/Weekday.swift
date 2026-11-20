import Foundation

/// A day of the week, in Gregorian order starting on Sunday (AC-M1-01, AC-M1-10).
public enum Weekday: String, CaseIterable, Codable, Hashable, Sendable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}
