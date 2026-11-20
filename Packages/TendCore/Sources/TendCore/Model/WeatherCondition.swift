import Foundation

/// The injected weather for the moment (AC-M1-11, FR-B1). Tend never fetches weather inside `TendCore` (brief Q8).
/// `severe` describes the weather only; it is never used for a task, state, prompt or error (design.md).
public enum WeatherCondition: String, CaseIterable, Codable, Hashable, Sendable {
    case clear
    case cloudy
    /// Rain or snow.
    case wet
    /// Storm, extreme heat or extreme cold.
    case severe
    /// No weather was supplied. Weather-dependent tasks are not offered on a guess (brief Q3).
    case unknown
}
