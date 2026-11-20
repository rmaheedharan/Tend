// Test support for the repository contract (AC-M1-04) and the file-store tests (AC-M1-05…07, AC-M1-25).
// Every file test runs in its own temporary directory, which is removed afterwards.

import Foundation
import Testing
@testable import TendCore

/// The two `HouseholdRepository` implementations the contract suite runs against (AC-M1-04).
enum RepositoryKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case jsonFile

    var testDescription: String {
        switch self {
        case .inMemory: "InMemoryHouseholdRepository"
        case .jsonFile: "JSONFileHouseholdRepository"
        }
    }
}

/// A repository under test plus a way to open **another** instance on the same storage. For the file store that is a
/// new instance on the same file (a restart); the in-memory store has no storage beyond its instance, so it returns
/// the same instance.
struct RepositoryUnderTest: Sendable {
    let kind: RepositoryKind
    let repository: any HouseholdRepository
    let reopen: @Sendable () -> any HouseholdRepository
}

enum RepositoryHarness {
    /// Runs `body` with a fresh repository of `kind`. File repositories live in a temporary directory that is removed
    /// when `body` returns or throws.
    static func withRepository<T>(
        _ kind: RepositoryKind,
        _ body: (RepositoryUnderTest) async throws -> T
    ) async throws -> T {
        switch kind {
        case .inMemory:
            let repository = InMemoryHouseholdRepository()
            return try await body(RepositoryUnderTest(kind: kind, repository: repository, reopen: { repository }))
        case .jsonFile:
            return try await withTemporaryDirectory { directory in
                let fileURL = directory.appendingPathComponent("household.json")
                return try await body(RepositoryUnderTest(
                    kind: kind,
                    repository: JSONFileHouseholdRepository(fileURL: fileURL),
                    reopen: { JSONFileHouseholdRepository(fileURL: fileURL) }
                ))
            }
        }
    }

    /// Runs `body` with a new, empty temporary directory and removes it afterwards.
    static func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TendCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    /// The names of the entries in `directory` (sorted), used to prove no partial or staging file is left behind.
    static func entries(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    static func bytes(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// A small valid household used by the contract and fault-injection tests.
    static func sampleHousehold(seed: UInt64, taskCount: Int = 12) throws -> Household {
        try HouseholdGenerator.household(seed: seed, taskCount: taskCount)
    }
}

/// An error thrown by injected writers in fault-injection tests (AC-M1-07).
struct InjectedWriteFault: Error, Equatable {}
