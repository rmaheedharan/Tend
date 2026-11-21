import Foundation

/// A `HouseholdRepository` that keeps the household in memory (AC-M1-04).
///
/// For tests, previews and fakes. It follows the same contract as the file store; nothing survives the instance.
///
/// Writes check every task against the model invariants and throw `invalidTask` for the first broken one, storing
/// nothing (AC-M2-02, W2-F3). A public caller cannot build such a task; the check guards against engine code inside
/// `TendCore` that sets a field through its internal setter. The file store refuses the same values: a non-finite
/// date cannot be encoded as JSON, so its save throws `writeUnsuccessful` (AC-M1-07).
/// An actor, so concurrent calls are serialised and every edit is a single read-modify-write (Swift 6 isolation).
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var household: Household = .empty

    public init() {}

    public func load() throws(HouseholdStoreError) -> Household {
        household
    }

    public func save(_ household: Household) throws(HouseholdStoreError) {
        try household.checkSchemaVersionIsCurrent()
        for task in household.tasks {
            try Self.checkInvariants(task)
        }
        self.household = household
    }

    public func upsertTask(_ task: HouseholdTask) throws(HouseholdStoreError) {
        try Self.checkInvariants(task)
        household.upsertTask(task)
    }

    public func removeTask(id: HouseholdTask.ID) throws(HouseholdStoreError) {
        household.removeTask(id: id)
    }

    public func updateRoom(_ room: Room) throws(HouseholdStoreError) {
        household.updateRoom(room)
    }

    private static func checkInvariants(_ task: HouseholdTask) throws(HouseholdStoreError) {
        if let violation = task.firstInvariantViolation() {
            throw .invalidTask(violation)
        }
    }
}
