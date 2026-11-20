import Foundation

/// A `HouseholdRepository` that keeps the household in memory (AC-M1-04).
///
/// For tests, previews and fakes. It follows the same contract as the file store; nothing survives the instance.
/// An actor, so concurrent calls are serialised and every edit is a single read-modify-write (Swift 6 isolation).
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var household: Household = .empty

    public init() {}

    public func load() throws(HouseholdStoreError) -> Household {
        household
    }

    public func save(_ household: Household) throws(HouseholdStoreError) {
        try household.checkSchemaVersionIsCurrent()
        self.household = household
    }

    public func upsertTask(_ task: HouseholdTask) throws(HouseholdStoreError) {
        household.upsertTask(task)
    }

    public func removeTask(id: HouseholdTask.ID) throws(HouseholdStoreError) {
        household.removeTask(id: id)
    }

    public func updateRoom(_ room: Room) throws(HouseholdStoreError) {
        household.updateRoom(room)
    }
}
