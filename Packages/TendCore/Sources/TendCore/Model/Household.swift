import Foundation

/// Everything Tend knows about one household (AC-M1-01; persistence in WI-M1-02).
/// Decoding validates every task (AC-M1-25). Schema-version policy is enforced by the repository (AC-M1-06).
public struct Household: Hashable, Codable, Sendable {
    /// The schema version written by this build of `TendCore`.
    public static let currentSchemaVersion = 1

    public var tasks: [HouseholdTask]
    public var rooms: [Room]
    public var schemaVersion: Int

    public init(tasks: [HouseholdTask], rooms: [Room], schemaVersion: Int = Household.currentSchemaVersion) {
        self.tasks = tasks
        self.rooms = rooms
        self.schemaVersion = schemaVersion
    }
}
