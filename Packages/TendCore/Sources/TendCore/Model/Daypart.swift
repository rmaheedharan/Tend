import Foundation

/// A part of the day in the injected calendar and time zone (brief Q2):
/// morning [05:00, 12:00), afternoon [12:00, 17:00), evening [17:00, 22:00), night [22:00, 05:00 next day).
/// Slot arithmetic on these boundaries lives with the selector (WI-M1-03).
public enum Daypart: String, CaseIterable, Codable, Hashable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    /// Tasks are quiet at night unless they explicitly allow it (brief Q2, UX-3).
    public static let defaultAllowed: Set<Daypart> = [.morning, .afternoon, .evening]
}
