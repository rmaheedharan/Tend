// Test support for the WI-M2-15 eval scorer tests (AC-M2-14, AC-M2-28). Reads the committed schema and the hand-built
// self-test files from the repository (tests may read files; only the module Sources are under AC-M2-09 Rule 1).

import Foundation
import Testing
@testable import TendIngestion

enum EvalSelfTest {
    static let schemaPath = "Fixtures/M2/eval/results-v1.schema.json"
    static let selfTestDirectory = "Fixtures/M2/eval-selftest"
    /// The self-test file's `run.fixturesSHA256` (a stand-in; the self-test has no manifest).
    static let selfTestHash = String(repeating: "a", count: 64)

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: IngestionSourceScanTests.repositoryRoot().appendingPathComponent(relative))
    }

    static func selfTest(_ name: String) throws -> Data { try data(selfTestDirectory + "/" + name) }

    static func schema() throws -> EvalSchemaCheck { try EvalSchemaCheck(schemaData: try data(schemaPath)) }

    static func fixtures() throws -> EvalFixtures {
        try EvalFixtures(inputs: try selfTest("inputs.json"), household: try selfTest("household.json"),
                         golden: try selfTest("golden.json"))
    }

    /// The hand-built results file as written (pretty, not canonical).
    static func prettyResults() throws -> Data { try selfTest("results-selftest-1.json") }

    /// The hand-built results file as a parsed value.
    static func resultsRoot() throws -> EvalJSON { try EvalJSONReader.parse(try prettyResults()) }

    static func canonical(_ value: EvalJSON) throws -> Data { try CanonicalJSONWriter.data(value.canonical) }

    static func request(_ results: Data, profile: EvalProfile = .info, expectedHash: String = selfTestHash,
                        allowedKeyPaths: Set<String>? = nil) throws -> EvalScoringRequest {
        EvalScoringRequest(
            results: results, schema: try data(schemaPath), inputs: try selfTest("inputs.json"),
            household: try selfTest("household.json"), golden: try selfTest("golden.json"),
            expectedFixturesSHA256: expectedHash, profile: profile, allowedKeyPaths: allowedKeyPaths
        )
    }

    /// Reads (with every check) and scores the canonical form of `root`.
    static func readAndScore(_ root: EvalJSON) throws -> (EvalResultsFileV1, EvalScore) {
        let file = try EvalResultsFileV1.read(try canonical(root), schema: try schema(), fixtures: try fixtures(),
                                              expectedFixturesSHA256: selfTestHash)
        return (file, EvalScorer.score(file, fixtures: try fixtures()))
    }
}

/// Pointer-style edits of a JSON value, for building wrong files from right ones.
extension EvalJSON {
    /// The value with the member or item at `pointer` (`/inputs/0/mode`) replaced; nil removes it. A missing last
    /// object member is added. An array index equal to the count appends.
    func setting(_ pointer: String, to value: EvalJSON?) -> EvalJSON {
        let segments = pointer.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return setting(segments[...], to: value)
    }

    private func setting(_ segments: ArraySlice<String>, to value: EvalJSON?) -> EvalJSON {
        guard let head = segments.first else { return value ?? .null }
        let rest = segments.dropFirst()
        switch self {
        case var .object(members):
            if let index = members.firstIndex(where: { $0.key == head }) {
                if rest.isEmpty, value == nil { members.remove(at: index) } else {
                    members[index].value = members[index].value.setting(rest, to: value)
                }
            } else if rest.isEmpty, let value {
                members.append(Member(head, value))
            }
            return .object(members)
        case var .array(items):
            guard let index = Int(head) else { return self }
            if index == items.count, rest.isEmpty, let value { items.append(value); return .array(items) }
            guard items.indices.contains(index) else { return self }
            if rest.isEmpty, value == nil { items.remove(at: index) } else {
                items[index] = items[index].setting(rest, to: value)
            }
            return .array(items)
        default:
            return self
        }
    }

    func value(at pointer: String) -> EvalJSON? {
        var current: EvalJSON? = self
        for segment in pointer.split(separator: "/").map(String.init) {
            switch current {
            case let .object(members)?: current = members.first { $0.key == segment }?.value
            case let .array(items)?: current = Int(segment).flatMap { items.indices.contains($0) ? items[$0] : nil }
            default: return nil
            }
        }
        return current
    }
}
