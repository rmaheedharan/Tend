import Foundation

/// The lifecycle of a task (AC-M1-02, FR-B2, UX-3).
///
/// This is a closed set on purpose. There is no debt state: a window that ends is renegotiated by the rescheduler
/// (WI-M1-04) into `maintenance`, `resurfaced` or a new window, never into a state that counts or names lateness.
public enum TaskState: Hashable, Sendable {
    /// Eligible whenever its window, slot, energy and weather fit.
    case active
    /// The person asked for rest until `until`. While `until > now` the task is resting: never shown, never moved.
    /// Once `until <= now` the rest is over and the task behaves exactly as `active` (brief Q12).
    case deferred(until: Date)
    /// A deep clean stepped down to a light-touch version; counts as low effort, stored effort is kept (brief Q5).
    case maintenance
    /// A critical task brought back gently, ranked first by the selector (AC-M1-16, AC-M1-18).
    case resurfaced
    /// Done. Only one-off and restock tasks stay here; recurring tasks return to `active` on completion (AC-M1-03).
    case completed
}

extension TaskState: Codable {
    /// Encoded as `{"name": "<case>"}`, plus `"until"` for `deferred`. Unknown names are rejected, never defaulted.
    private enum CodingKeys: String, CodingKey {
        case name
        case until
    }

    private enum Name: String, Codable {
        case active
        case deferred
        case maintenance
        case resurfaced
        case completed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Name.self, forKey: .name) {
        case .active: self = .active
        case .deferred: self = .deferred(until: try container.decode(Date.self, forKey: .until))
        case .maintenance: self = .maintenance
        case .resurfaced: self = .resurfaced
        case .completed: self = .completed
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .active:
            try container.encode(Name.active, forKey: .name)
        case .deferred(let until):
            try container.encode(Name.deferred, forKey: .name)
            try container.encode(until, forKey: .until)
        case .maintenance:
            try container.encode(Name.maintenance, forKey: .name)
        case .resurfaced:
            try container.encode(Name.resurfaced, forKey: .name)
        case .completed:
            try container.encode(Name.completed, forKey: .name)
        }
    }
}
