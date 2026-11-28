// The only TendEval file that reads files: the frozen eval fixtures bundled at build time (AC-M2-28 "Build path";
// AC-M2-09 Rule 6, fixtures-loader exception, M2 Q23). Each file is loaded by its own literal resource name; nothing
// else is read, nothing is kept, and every function takes no parameter. `results-v1.schema.json` is bundled too (B6
// checks its bytes) but the harness does not need it: the scorer checks the results file on the Mac.

import Foundation

enum EvalFixturesLoader {
    enum LoaderError: Error {
        case missing
    }

    static func inputs() throws -> Data {
        guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else {
            throw LoaderError.missing
        }
        return try Data(contentsOf: inputsFile)
    }

    static func household() throws -> Data {
        guard let householdFile = Bundle.main.url(forResource: "household", withExtension: "json") else {
            throw LoaderError.missing
        }
        return try Data(contentsOf: householdFile)
    }

    static func golden() throws -> Data {
        guard let goldenFile = Bundle.main.url(forResource: "golden", withExtension: "json") else {
            throw LoaderError.missing
        }
        return try Data(contentsOf: goldenFile)
    }

    static func manifest() throws -> Data {
        guard let manifestFile = Bundle.main.url(forResource: "MANIFEST", withExtension: "sha256") else {
            throw LoaderError.missing
        }
        return try Data(contentsOf: manifestFile)
    }
}
