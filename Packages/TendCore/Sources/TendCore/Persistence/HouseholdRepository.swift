import Foundation

/// Where a household is kept (AC-M1-04, S-M1-02, FR-B1, FR-B2, P-2).
///
/// The engine and, later, the UI use only this protocol. M1 ships `InMemoryHouseholdRepository` and the Foundation-only
/// `JSONFileHouseholdRepository`; the app store chosen in ADR-0002 will be a third implementation behind it.
///
/// Contract (one shared test suite runs against every implementation, AC-M1-04):
/// - `load()` returns the stored household exactly. If nothing has ever been saved it returns an empty household at
///   `Household.currentSchemaVersion`. Stored data that cannot be read throws; it is never replaced by an empty
///   household (AC-M1-06).
/// - `save(_:)` replaces the whole stored household. A household whose `schemaVersion` is not
///   `Household.currentSchemaVersion` is rejected with `unsupportedSchemaVersion`, so nothing is stored that this build
///   could not read back.
/// - `upsertTask(_:)` replaces the stored task with the same `id` in place, or appends the task if there is none.
/// - `removeTask(id:)` removes the task with that `id`; removing an unknown `id` changes nothing.
/// - `updateRoom(_:)` replaces the stored room with the same `id` in place, or appends the room if there is none.
/// - Each call is atomic with respect to other calls on the same instance: concurrent calls never lose an update.
/// - A call that throws leaves the stored household as it was (AC-M1-07).
public protocol HouseholdRepository: Sendable {
    func load() async throws(HouseholdStoreError) -> Household
    func save(_ household: Household) async throws(HouseholdStoreError)
    func upsertTask(_ task: HouseholdTask) async throws(HouseholdStoreError)
    func removeTask(id: HouseholdTask.ID) async throws(HouseholdStoreError)
    func updateRoom(_ room: Room) async throws(HouseholdStoreError)
}

// MARK: - Shared edit rules (one definition, so every implementation edits a household the same way)

extension Household {
    /// An empty household at the current schema version: what a repository holds before anything is saved.
    static var empty: Household { Household(tasks: [], rooms: []) }

    /// Throws unless this build can read a household with this schema version back.
    func checkSchemaVersionIsCurrent() throws(HouseholdStoreError) {
        guard schemaVersion == Household.currentSchemaVersion else {
            throw .unsupportedSchemaVersion(schemaVersion)
        }
    }

    mutating func upsertTask(_ task: HouseholdTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    mutating func removeTask(id: HouseholdTask.ID) {
        tasks.removeAll { $0.id == id }
    }

    mutating func updateRoom(_ room: Room) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.append(room)
        }
    }
}
