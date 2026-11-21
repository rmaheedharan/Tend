// AC-M1-07: household A was saved; a later save of household B fails mid-way (injected write failure); loading returns
// A intact, with no partial or empty file. Risk R-8 (atomic replace on Linux); ADR-0004.
// Requirements: FR-B1, FR-B2 ("never lose a reminder for a bill", S-M1-02).

import Foundation
import Testing
@testable import TendCore

/// Where an injected write failure happens (AC-M1-07).
enum InjectedFailure: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// The write primitive throws before it writes anything.
    case beforeAnyBytes
    /// The write primitive stages half of B's bytes next to the file (as an atomic write does) and then throws,
    /// like a crash or a full disk mid-way through the write.
    case halfwayThroughStaging
    /// The write primitive stages all of B's bytes and throws just before the final replace.
    case justBeforeReplace

    var testDescription: String { rawValue }

    /// A writer that fails at this point. It never touches the destination file itself: that is the primitive's
    /// contract (replace atomically or not at all), which the standard writer meets with Foundation's `.atomic` write.
    var writer: HouseholdFileWriter {
        let failure = self
        return HouseholdFileWriter { data, destination in
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).injected-staging")
            switch failure {
            case .beforeAnyBytes:
                break
            case .halfwayThroughStaging:
                try data.prefix(data.count / 2).write(to: staging)
            case .justBeforeReplace:
                try data.write(to: staging)
            }
            throw InjectedWriteFault()
        }
    }
}

@Suite("JSON file repository atomic save (AC-M1-07, R-8)")
struct FileRepositoryAtomicSaveTests {

    @Test("AC-M1-07: when a later save of B fails mid-way, loading returns A intact (no partial or empty file)",
          arguments: InjectedFailure.allCases)
    func failedSaveKeepsPreviousHousehold(failure: InjectedFailure) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let householdA = try HouseholdGenerator.household(seed: 7_001, taskCount: 120)
            let householdB = try HouseholdGenerator.household(seed: 7_002, taskCount: 300)
            try await JSONFileHouseholdRepository(fileURL: fileURL).save(householdA)
            let bytesA = try RepositoryHarness.bytes(at: fileURL)

            let failing = try JSONFileHouseholdRepository(fileURL: fileURL, writer: failure.writer)
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) { try await failing.save(householdB) }

            #expect(try RepositoryHarness.bytes(at: fileURL) == bytesA, "\(failure): the household file changed")
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == householdA)
            #expect(try await failing.load() == householdA, "\(failure): the failing instance must not cache B")
        }
    }

    @Test("AC-M1-07: a failed upsert, remove or room update leaves A intact", arguments: InjectedFailure.allCases)
    func failedMutationKeepsPreviousHousehold(failure: InjectedFailure) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let householdA = try HouseholdGenerator.household(seed: 7_003, taskCount: 40)
            try await JSONFileHouseholdRepository(fileURL: fileURL).save(householdA)
            let bytesA = try RepositoryHarness.bytes(at: fileURL)
            let failing = try JSONFileHouseholdRepository(fileURL: fileURL, writer: failure.writer)

            await #expect(throws: HouseholdStoreError.writeUnsuccessful) {
                try await failing.upsertTask(try Fixtures.task(id: Fixtures.id(0x7777)))
            }
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) {
                try await failing.removeTask(id: householdA.tasks[0].id)
            }
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) {
                try await failing.updateRoom(Room(id: Fixtures.id(0x8888), name: "Garage"))
            }

            #expect(try RepositoryHarness.bytes(at: fileURL) == bytesA)
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == householdA)
        }
    }

    @Test("AC-M1-07: when the very first save fails, no household file is created and nothing was saved",
          arguments: InjectedFailure.allCases)
    func failedFirstSaveCreatesNoFile(failure: InjectedFailure) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let failing = try JSONFileHouseholdRepository(fileURL: fileURL, writer: failure.writer)
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) {
                try await failing.save(try HouseholdGenerator.household(seed: 7_004, taskCount: 10))
            }
            #expect(!RepositoryHarness.fileExists(fileURL))
        }
    }

    @Test("AC-M1-07: after a failed save, the next successful save of B is stored and loads exactly")
    func recoveryAfterFailure() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let householdA = try HouseholdGenerator.household(seed: 7_005, taskCount: 30)
            let householdB = try HouseholdGenerator.household(seed: 7_006, taskCount: 30)
            try await JSONFileHouseholdRepository(fileURL: fileURL).save(householdA)
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) {
                try await JSONFileHouseholdRepository(fileURL: fileURL,
                                                      writer: InjectedFailure.halfwayThroughStaging.writer)
                    .save(householdB)
            }
            try await JSONFileHouseholdRepository(fileURL: fileURL).save(householdB)
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == householdB)
        }
    }

    @Test("AC-M1-07: a save whose encoding fails part-way (a non-finite date) writes nothing and leaves A intact")
    func encodingFailureKeepsPreviousHousehold() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let householdA = try HouseholdGenerator.household(seed: 7_007, taskCount: 25)
            let repository = try JSONFileHouseholdRepository(fileURL: fileURL)
            try await repository.save(householdA)
            let bytesA = try RepositoryHarness.bytes(at: fileURL)

            // JSON cannot hold an infinite number, so the encoder stops part-way through household B. Since AC-M2-02
            // (W2-F3) a public caller can no longer build such a task (windowDateNotFinite), so the date is set
            // through the module-internal setter, standing in for an engine defect. The assertion is unchanged.
            var householdB = householdA
            var nonFiniteTask = try Fixtures.task(id: Fixtures.id(0x9999))
            nonFiniteTask.windowStart = Date(timeIntervalSinceReferenceDate: -.infinity)
            nonFiniteTask.windowEnd = Fixtures.referenceDate
            householdB.tasks.append(nonFiniteTask)
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) { try await repository.save(householdB) }

            #expect(try RepositoryHarness.bytes(at: fileURL) == bytesA)
            #expect(try RepositoryHarness.entries(in: directory) == ["household.json"])
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == householdA)
        }
    }

    @Test("R-8 / AC-M1-07: the standard writer replaces the file by rename (new file identity), never rewrites it in place, and leaves no staging file")
    func standardWriterReplacesByRename() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let repository = try JSONFileHouseholdRepository(fileURL: fileURL)
            func fileNumber() throws -> Int? {
                try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))[.systemFileNumber]
                    as? Int
            }
            try await repository.save(try HouseholdGenerator.household(seed: 7_008, taskCount: 10))
            let before = try #require(try fileNumber())
            try await repository.save(try HouseholdGenerator.household(seed: 7_009, taskCount: 10))
            let after = try #require(try fileNumber())

            #expect(before != after, "the file kept its identity: it was rewritten in place, which is not atomic")
            #expect(try RepositoryHarness.entries(in: directory) == ["household.json"])
        }
    }

    @Test("AC-M1-07: the write primitive is given the whole encoded household in one call, after encoding has finished")
    func writerReceivesCompleteBytes() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let household = try HouseholdGenerator.household(seed: 7_010, taskCount: 60)
            let expected = try JSONFileHouseholdRepository.encode(household)
            let capturing = HouseholdFileWriter { data, destination in
                #expect(destination == fileURL)
                #expect(data == expected)
                try HouseholdFileWriter.standard.write(data, destination)
            }
            try await JSONFileHouseholdRepository(fileURL: fileURL, writer: capturing).save(household)
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == household)
        }
    }
}
