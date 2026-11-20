// AC-M1-05: ≥ 200 seeded random households of valid tasks (0–500 tasks each) saved by the file repository and loaded by
// a new instance on the same file are equal field for field, with dates exactly equal. Risk R-7 (date precision);
// file format per ADR-0004. Requirements: FR-B1, FR-B2, P-2; S-M1-02.

import Foundation
import Testing
@testable import TendCore

@Suite("JSON file repository round trip (AC-M1-05, R-7)")
struct FileRepositoryRoundTripTests {
    /// Fixed seeds: 200 households. Seed 1 has 0 tasks and seed 2 has 500, so both ends of the range are always run.
    static let seeds: ClosedRange<UInt64> = 1...200

    static func taskCount(for seed: UInt64) -> Int? {
        switch seed {
        case 1: 0
        case 2: 500
        default: nil  // drawn from 0...500 by the seeded generator
        }
    }

    @Test("AC-M1-05: 200 seeded households (0-500 tasks) round-trip through a new file repository instance exactly")
    func seededHouseholdsRoundTrip() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            var totalTasks = 0
            var totalDates = 0
            var subSecondDates = 0
            var minTasks = Int.max
            var maxTasks = 0
            for seed in Self.seeds {
                let household = try HouseholdGenerator.household(seed: seed, taskCount: Self.taskCount(for: seed))
                let fileURL = directory.appendingPathComponent("household-\(seed).json")

                try await JSONFileHouseholdRepository(fileURL: fileURL).save(household)
                let loaded = try await JSONFileHouseholdRepository(fileURL: fileURL).load()

                #expect(loaded == household, "seed \(seed): loaded household differs from the saved one")
                let saved = HouseholdGenerator.allDates(in: household)
                let read = HouseholdGenerator.allDates(in: loaded)
                #expect(saved.map(\.timeIntervalSinceReferenceDate.bitPattern)
                        == read.map(\.timeIntervalSinceReferenceDate.bitPattern),
                        "seed \(seed): a date is not bit-exact after the round trip")

                totalTasks += household.tasks.count
                totalDates += saved.count
                subSecondDates += saved.filter { $0.timeIntervalSinceReferenceDate.rounded() != $0.timeIntervalSinceReferenceDate }.count
                minTasks = min(minTasks, household.tasks.count)
                maxTasks = max(maxTasks, household.tasks.count)
                try FileManager.default.removeItem(at: fileURL)
            }
            print("AC-M1-05: seeds \(Self.seeds.lowerBound)...\(Self.seeds.upperBound), \(Self.seeds.count) households, "
                  + "\(totalTasks) tasks (min \(minTasks), max \(maxTasks) per household), "
                  + "\(totalDates) dates compared bit-exact, \(subSecondDates) with a sub-second part")
            #expect(Self.seeds.count >= 200)
            #expect(minTasks == 0)
            #expect(maxTasks == 500)
            #expect(subSecondDates > 0)
        }
    }

    /// Dates chosen to break lossy encodings: ISO-8601 with milliseconds, `%.15g`, or `Float` would change these.
    static let awkwardIntervals: [TimeInterval] = [
        784_102_400.123_456,
        0.1 + 0.2,
        1e-7,
        -1e-9,
        0,
        -978_307_200.000_001,  // 1970-01-01T00:00:00.000001Z, before the reference date
        4_102_444_800.000_5,  // the year 2131, a sub-millisecond part near the limit of Double precision
        784_102_400.0.nextUp,
        784_102_400.0.nextDown,
        1.0 / 3.0,
        123_456_789.987_654_321,
    ]

    @Test("R-7 / AC-M1-05: awkward sub-second dates are written and read back bit-exact",
          arguments: awkwardIntervals)
    func awkwardDatesAreExact(interval: TimeInterval) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let start = Date(timeIntervalSinceReferenceDate: interval)
            let end = Date(timeIntervalSinceReferenceDate: interval.nextUp)  // the smallest possible window
            let task = try Fixtures.task(windowStart: start, windowEnd: end, state: .deferred(until: start),
                                         completedAt: end)
            let household = Household(tasks: [task], rooms: [Room(id: Fixtures.kitchenID, name: "Kitchen",
                                                                  lastTendedAt: start)])
            let fileURL = directory.appendingPathComponent("household.json")

            try await JSONFileHouseholdRepository(fileURL: fileURL).save(household)
            let loaded = try await JSONFileHouseholdRepository(fileURL: fileURL).load()

            #expect(loaded == household)
            #expect(HouseholdGenerator.allDates(in: loaded).map(\.timeIntervalSinceReferenceDate.bitPattern)
                    == HouseholdGenerator.allDates(in: household).map(\.timeIntervalSinceReferenceDate.bitPattern))
        }
    }

    @Test("ADR-0004: the file is JSON with schemaVersion 1 and dates as seconds since the reference date")
    func fileFormat() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let task = try Fixtures.task()
            try await JSONFileHouseholdRepository(fileURL: fileURL).save(Household(tasks: [task], rooms: []))

            let object = try JSONSerialization.jsonObject(with: try RepositoryHarness.bytes(at: fileURL))
            let root = try #require(object as? [String: Any])
            #expect(root["schemaVersion"] as? Int == 1)
            let tasks = try #require(root["tasks"] as? [[String: Any]])
            let windowStart = try #require(tasks.first?["windowStart"] as? Double)
            #expect(windowStart == task.windowStart.timeIntervalSinceReferenceDate)
        }
    }

    @Test("ADR-0004: saving the same household twice writes identical bytes (stable key order)")
    func deterministicBytes() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let household = try HouseholdGenerator.household(seed: 77, taskCount: 50)
            let first = directory.appendingPathComponent("first.json")
            let second = directory.appendingPathComponent("second.json")
            try await JSONFileHouseholdRepository(fileURL: first).save(household)
            try await JSONFileHouseholdRepository(fileURL: second).save(household)
            #expect(try RepositoryHarness.bytes(at: first) == RepositoryHarness.bytes(at: second))
        }
    }
}
