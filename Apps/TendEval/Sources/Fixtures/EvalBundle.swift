// The bundled eval, checked against its manifest (AC-M2-28 "the harness shows their SHA-256 manifest hash"; plan
// "Fixtures hash": the SHA-256 of the MANIFEST.sha256 bytes; each bundled file checked against the manifest).

import CryptoKit
import Foundation
import TendIngestion

struct EvalBundle: Sendable {
    let fixtures: EvalFixtures
    /// The SHA-256 of the bundled `MANIFEST.sha256` bytes, lower-case hex: the fixtures hash of the run record.
    let fixturesSHA256: String
    /// File name and whether its bytes match the manifest line, for the three files the harness reads.
    let checks: [(name: String, matches: Bool)]

    var allMatch: Bool { checks.allSatisfy(\.matches) && checks.count == 3 }

    enum LoadError: Error {
        case notLoaded
        case manifestNotText
        case fixtures(EvalFixtureError)
    }

    static func load() throws -> EvalBundle {
        let inputs: Data, household: Data, golden: Data, manifest: Data
        do {
            inputs = try EvalFixturesLoader.inputs()
            household = try EvalFixturesLoader.household()
            golden = try EvalFixturesLoader.golden()
            manifest = try EvalFixturesLoader.manifest()
        } catch {
            throw LoadError.notLoaded
        }
        guard let text = String(data: manifest, encoding: .utf8) else { throw LoadError.manifestNotText }
        let listed = Self.lines(text)
        let checks = [("inputs.json", inputs), ("household.json", household), ("golden.json", golden)].map {
            (name: $0.0, matches: listed[$0.0] == hex(SHA256.hash(data: $0.1)))
        }
        let fixtures: EvalFixtures
        do {
            fixtures = try EvalFixtures(inputs: inputs, household: household, golden: golden)
        } catch {
            throw LoadError.fixtures(error)
        }
        return EvalBundle(fixtures: fixtures, fixturesSHA256: hex(SHA256.hash(data: manifest)), checks: checks)
    }

    /// `sha256sum` lines: `<hex>  <name>`.
    static func lines(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            result[String(parts[1])] = String(parts[0])
        }
        return result
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
