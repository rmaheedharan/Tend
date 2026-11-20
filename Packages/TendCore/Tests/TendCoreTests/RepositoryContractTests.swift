// AC-M1-04: one shared contract suite (save, load, upsert task, remove task, update room) runs against both
// `HouseholdRepository` implementations, and both pass every case.
// Requirements: FR-B1, FR-B2, P-2 (local storage only); S-M1-02.

import Foundation
import Testing
@testable import TendCore

@Suite("HouseholdRepository contract (AC-M1-04)")
struct RepositoryContractTests {

    @Test("AC-M1-04 contract: a repository with nothing saved loads an empty household at the current schema version",
          arguments: RepositoryKind.allCases)
    func freshRepositoryIsEmpty(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let loaded = try await store.repository.load()
            #expect(loaded == Household(tasks: [], rooms: []))
            #expect(loaded.schemaVersion == Household.currentSchemaVersion)
        }
    }

    @Test("AC-M1-04 contract: save then load returns the household exactly, also from a reopened instance",
          arguments: RepositoryKind.allCases)
    func saveThenLoad(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_001)
            try await store.repository.save(household)
            #expect(try await store.repository.load() == household)
            #expect(try await store.reopen().load() == household)
        }
    }

    @Test("AC-M1-04 contract: save replaces the whole household (nothing from the earlier save survives)",
          arguments: RepositoryKind.allCases)
    func saveReplacesEverything(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            try await store.repository.save(try RepositoryHarness.sampleHousehold(seed: 4_002))
            let second = try RepositoryHarness.sampleHousehold(seed: 4_003, taskCount: 3)
            try await store.repository.save(second)
            #expect(try await store.reopen().load() == second)

            let empty = Household(tasks: [], rooms: [])
            try await store.repository.save(empty)
            #expect(try await store.reopen().load() == empty)
        }
    }

    @Test("AC-M1-04 contract: upsert adds a task with a new ID at the end", arguments: RepositoryKind.allCases)
    func upsertInserts(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_004)
            try await store.repository.save(household)
            let newTask = try Fixtures.task(id: Fixtures.id(0xBEEF), title: "Buy dishwasher tablets", kind: .restock)

            try await store.repository.upsertTask(newTask)

            let loaded = try await store.reopen().load()
            #expect(loaded.tasks == household.tasks + [newTask])
            #expect(loaded.rooms == household.rooms)
        }
    }

    @Test("AC-M1-04 contract: upsert replaces the task with the same ID in place, keeping the order of the others",
          arguments: RepositoryKind.allCases)
    func upsertReplacesInPlace(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_005)
            try await store.repository.save(household)
            let index = 5
            let original = household.tasks[index]
            let replacement = try Fixtures.task(
                id: original.id, title: "Descale the kettle", kind: .recurring, effort: .low,
                recurrenceIntervalDays: 30
            )

            try await store.repository.upsertTask(replacement)

            var expected = household
            expected.tasks[index] = replacement
            let loaded = try await store.reopen().load()
            #expect(loaded == expected)
            #expect(loaded.tasks.count == household.tasks.count)
        }
    }

    @Test("AC-M1-04 contract: upsert into a repository with nothing saved creates a household with that task",
          arguments: RepositoryKind.allCases)
    func upsertIntoEmpty(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let task = try Fixtures.task()
            try await store.repository.upsertTask(task)
            #expect(try await store.reopen().load() == Household(tasks: [task], rooms: []))
        }
    }

    @Test("AC-M1-04 contract: remove deletes only the task with that ID", arguments: RepositoryKind.allCases)
    func removeTask(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_006)
            try await store.repository.save(household)
            let removed = household.tasks[3]

            try await store.repository.removeTask(id: removed.id)

            var expected = household
            expected.tasks.remove(at: 3)
            #expect(try await store.reopen().load() == expected)
        }
    }

    @Test("AC-M1-04 contract: removing an ID that is not stored changes nothing and does not throw",
          arguments: RepositoryKind.allCases)
    func removeUnknownTask(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_007)
            try await store.repository.save(household)
            try await store.repository.removeTask(id: Fixtures.id(0xD00D))
            #expect(try await store.reopen().load() == household)
        }
    }

    @Test("AC-M1-04 contract: update room replaces the room with the same ID in place, including lastTendedAt (FR-B3)",
          arguments: RepositoryKind.allCases)
    func updateRoomReplaces(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let rooms = [
                Room(id: Fixtures.id(0xA1), name: "Kitchen"),
                Room(id: Fixtures.id(0xA2), name: "Bathroom", lastTendedAt: Fixtures.referenceDate),
                Room(id: Fixtures.id(0xA3), name: "Hall"),
            ]
            let household = Household(tasks: [try Fixtures.task()], rooms: rooms)
            try await store.repository.save(household)
            let tended = Room(id: Fixtures.id(0xA2), name: "Bathroom",
                              lastTendedAt: Fixtures.referenceDate.addingTimeInterval(86_400.25))

            try await store.repository.updateRoom(tended)

            var expected = household
            expected.rooms[1] = tended
            #expect(try await store.reopen().load() == expected)
        }
    }

    @Test("AC-M1-04 contract: update room with a new ID adds the room at the end", arguments: RepositoryKind.allCases)
    func updateRoomInserts(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = Household(tasks: [], rooms: [Room(id: Fixtures.id(0xA1), name: "Kitchen")])
            try await store.repository.save(household)
            let balcony = Room(id: Fixtures.id(0xA9), name: "Balcony")

            try await store.repository.updateRoom(balcony)

            #expect(try await store.reopen().load().rooms == household.rooms + [balcony])
        }
    }

    @Test("AC-M1-04 contract: saving a household with a schema version this build cannot read is rejected and stores nothing",
          arguments: RepositoryKind.allCases)
    func saveRejectsUnknownSchemaVersion(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let household = try RepositoryHarness.sampleHousehold(seed: 4_008)
            try await store.repository.save(household)
            var future = household
            future.schemaVersion = Household.currentSchemaVersion + 1

            await #expect(throws: HouseholdStoreError.unsupportedSchemaVersion(Household.currentSchemaVersion + 1)) {
                try await store.repository.save(future)
            }
            #expect(try await store.reopen().load() == household)
        }
    }

    @Test("AC-M1-04 contract: concurrent upserts from many tasks are all kept (no lost update; Swift 6 isolation)",
          arguments: RepositoryKind.allCases)
    func concurrentUpsertsAreSerialised(kind: RepositoryKind) async throws {
        try await RepositoryHarness.withRepository(kind) { store in
            let tasks = try (1...64).map { n in try Fixtures.task(id: Fixtures.id(0x1000 + n), title: "Task \(n)") }
            let repository = store.repository
            try await withThrowingTaskGroup(of: Void.self) { group in
                for task in tasks {
                    group.addTask { try await repository.upsertTask(task) }
                }
                try await group.waitForAll()
            }
            let loaded = try await store.reopen().load()
            #expect(Set(loaded.tasks.map(\.id)) == Set(tasks.map(\.id)))
            #expect(loaded.tasks.count == tasks.count)
        }
    }

    @Test("AC-M1-04 contract: a sequence of save, upsert, remove and update room gives the same household on both implementations")
    func implementationsAgree() async throws {
        func run(_ kind: RepositoryKind) async throws -> Household {
            try await RepositoryHarness.withRepository(kind) { store in
                let household = try RepositoryHarness.sampleHousehold(seed: 4_009, taskCount: 40)
                try await store.repository.save(household)
                var rng = SplitMix64(seed: 4_010)
                for step in 0..<60 {
                    switch step % 3 {
                    case 0:
                        try await store.repository.upsertTask(
                            try HouseholdGenerator.task(using: &rng, rooms: household.rooms))
                    case 1:
                        let current = try await store.repository.load()
                        if let victim = current.tasks.first { try await store.repository.removeTask(id: victim.id) }
                    default:
                        try await store.repository.updateRoom(Room(
                            id: HouseholdGenerator.uuid(using: &rng), name: "Room \(step)",
                            lastTendedAt: HouseholdGenerator.date(near: Fixtures.referenceDate, withinDays: 5,
                                                                  using: &rng)))
                    }
                }
                return try await store.reopen().load()
            }
        }
        let inMemory = try await run(.inMemory)
        let jsonFile = try await run(.jsonFile)
        #expect(inMemory == jsonFile)
        #expect(inMemory.tasks.count == 40 + 20 - 20)
    }
}
