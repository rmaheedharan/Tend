// AC-M1-06: a corrupt file (truncated / not JSON), an unknown schema version, or a task that violates a model invariant
// makes the repository throw a typed `HouseholdStoreError`, never return an empty household, and leave the file's
// bytes unchanged. AC-M1-25 (repository part): one case per invariant, loaded through the repository.
// Requirements: FR-B1, FR-B2, UX-3 (a calm, typed failure, never silent data loss); S-M1-02.

import Foundation
import Testing
@testable import TendCore

/// The bytes of a bad household file and the typed error loading it must throw.
struct BadFileCase: Sendable, CustomTestStringConvertible {
    let name: String
    let expected: HouseholdStoreError
    let bytes: @Sendable () throws -> Data

    var testDescription: String { name }
}

@Suite("JSON file repository load errors (AC-M1-06, AC-M1-25)")
struct FileRepositoryLoadErrorTests {

    /// The bytes of a valid saved household file (via the encoder the repository uses), for truncation and edits.
    static func validFileBytes() throws -> Data {
        let household = try HouseholdGenerator.household(seed: 6_006, taskCount: 20)
        return try JSONFileHouseholdRepository.encode(household)
    }

    static func validFileObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try validFileBytes())
        guard let root = object as? [String: Any] else { throw Fixtures.FixtureError.notAnObject }
        return root
    }

    static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    static let corruptCases: [BadFileCase] = [
        BadFileCase(name: "truncated to half", expected: .unreadableFile) {
            let bytes = try validFileBytes()
            return bytes.prefix(bytes.count / 2)
        },
        BadFileCase(name: "truncated by one byte", expected: .unreadableFile) {
            try validFileBytes().dropLast()
        },
        BadFileCase(name: "empty file (0 bytes)", expected: .unreadableFile) { Data() },
        BadFileCase(name: "plain text, not JSON", expected: .unreadableFile) { Data("this is not a household".utf8) },
        BadFileCase(name: "binary noise", expected: .unreadableFile) {
            var rng = SplitMix64(seed: 6_007)
            return Data((0..<512).map { _ in UInt8(truncatingIfNeeded: rng.next()) })
        },
        BadFileCase(name: "JSON array instead of an object", expected: .unreadableFile) { try json([1, 2, 3]) },
        BadFileCase(name: "schemaVersion only, no tasks or rooms", expected: .unreadableFile) {
            try json(["schemaVersion": 1])
        },
        BadFileCase(name: "no schemaVersion", expected: .unreadableFile) {
            var root = try validFileObject()
            root.removeValue(forKey: "schemaVersion")
            return try json(root)
        },
        BadFileCase(name: "schemaVersion is a string", expected: .unreadableFile) {
            var root = try validFileObject()
            root["schemaVersion"] = "1"
            return try json(root)
        },
        BadFileCase(name: "a task field has the wrong type", expected: .unreadableFile) {
            var root = try validFileObject()
            guard var tasks = root["tasks"] as? [[String: Any]], !tasks.isEmpty else {
                throw Fixtures.FixtureError.notAnObject
            }
            tasks[0]["windowStart"] = "tomorrow"
            root["tasks"] = tasks
            return try json(root)
        },
    ]

    static let schemaCases: [BadFileCase] = [2, 0, -1, 99].map { version in
        BadFileCase(name: "schemaVersion \(version)", expected: .unsupportedSchemaVersion(version)) {
            var root = try validFileObject()
            root["schemaVersion"] = version
            return try json(root)
        }
    } + [
        // A future version may change the shape; the version is still reported, not "unreadable".
        BadFileCase(name: "schemaVersion 2 with a different shape", expected: .unsupportedSchemaVersion(2)) {
            try json(["schemaVersion": 2, "members": ["a", "b"]])
        },
    ]

    static let invariantCases: [BadFileCase] = TaskInvariantViolation.allCases.map { violation in
        BadFileCase(name: "task violating \(violation)", expected: .invalidTask(violation)) {
            var root = try validFileObject()
            guard var tasks = root["tasks"] as? [[String: Any]], tasks.count > 7 else {
                throw Fixtures.FixtureError.notAnObject
            }
            tasks[7] = try InvariantTests.violatingJSON(violation)  // one bad task among valid ones
            root["tasks"] = tasks
            return try json(root)
        }
    }

    /// Writes `bad` to a file, then checks every repository operation that reads it: the typed error is thrown, no
    /// household is returned, and the bytes on disk are unchanged afterwards (AC-M1-06).
    func assertRejected(_ bad: BadFileCase) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let bytes = try bad.bytes()
            try bytes.write(to: fileURL)

            let repository = JSONFileHouseholdRepository(fileURL: fileURL)
            var returned: Household?
            await #expect(throws: bad.expected, "\(bad.name): load") {
                returned = try await repository.load()
            }
            #expect(returned == nil, "\(bad.name): a household was returned (possibly empty) instead of an error")
            #expect(try RepositoryHarness.bytes(at: fileURL) == bytes, "\(bad.name): load changed the file")

            // Read-modify-write operations must not overwrite a file they could not read.
            let task = try Fixtures.task()
            await #expect(throws: bad.expected, "\(bad.name): upsertTask") { try await repository.upsertTask(task) }
            await #expect(throws: bad.expected, "\(bad.name): removeTask") {
                try await repository.removeTask(id: task.id)
            }
            await #expect(throws: bad.expected, "\(bad.name): updateRoom") {
                try await repository.updateRoom(Room(id: Fixtures.kitchenID, name: "Kitchen"))
            }
            #expect(try RepositoryHarness.bytes(at: fileURL) == bytes, "\(bad.name): a mutation changed the file")

            // A second, new instance sees the same thing (nothing was cached or repaired).
            await #expect(throws: bad.expected, "\(bad.name): reload") {
                _ = try await JSONFileHouseholdRepository(fileURL: fileURL).load()
            }
            #expect(try RepositoryHarness.entries(in: directory) == ["household.json"])
        }
    }

    @Test("AC-M1-06: a corrupt file (truncated or not JSON) throws unreadableFile and is left byte-for-byte unchanged",
          arguments: corruptCases)
    func corruptFile(bad: BadFileCase) async throws {
        try await assertRejected(bad)
    }

    @Test("AC-M1-06: a file with an unknown schema version throws unsupportedSchemaVersion and is left unchanged",
          arguments: schemaCases)
    func unknownSchemaVersion(bad: BadFileCase) async throws {
        try await assertRejected(bad)
    }

    @Test("AC-M1-25 / AC-M1-06: a file containing a task that violates an invariant throws invalidTask through the repository and is left unchanged",
          arguments: invariantCases)
    func invalidTask(bad: BadFileCase) async throws {
        try await assertRejected(bad)
    }

    @Test("AC-M1-25: the repository cases cover all nine invariants")
    func invariantCoverage() {
        let covered = Set(Self.invariantCases.compactMap { bad -> TaskInvariantViolation? in
            if case .invalidTask(let violation) = bad.expected { return violation }
            return nil
        })
        #expect(covered == Set(TaskInvariantViolation.allCases))
    }

    @Test("AC-M1-06: a path that is a directory, not a file, throws unreadableFile")
    func directoryInsteadOfFile() async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json", isDirectory: true)
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
            await #expect(throws: HouseholdStoreError.unreadableFile) {
                _ = try await JSONFileHouseholdRepository(fileURL: fileURL).load()
            }
        }
    }

    @Test("AC-M1-06: HouseholdStoreError has exactly the design-list cases and carries no user-facing text")
    func errorCases() {
        let all: [HouseholdStoreError] = [
            .unreadableFile, .unsupportedSchemaVersion(2), .invalidTask(.noAllowedDayparts), .writeUnsuccessful,
        ]
        for error in all {
            switch error {
            case .unreadableFile, .unsupportedSchemaVersion, .invalidTask, .writeUnsuccessful:
                break  // exhaustive: a new case would not compile here without updating the design list
            }
        }
        #expect(Set(all).count == 4)
    }
}
