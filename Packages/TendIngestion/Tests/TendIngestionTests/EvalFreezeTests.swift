// WI-M2-16 freeze state and MANIFEST.sha256 (AC-M2-14: "committed, with a SHA-256 manifest, and frozen"; plan "Fixtures
// hash"; PO `po-m2-wi16.md` ruling 1: approval holds for the files with the hashes b32e45af…, 089a22bd…, 882c2906…).
//
// The freeze waits for the owner's live check L2a (GR-4) and the other ruling 1 conditions, so this branch writes no
// manifest. What is tested now:
// - the three Tester files still have the PO-approved hashes (any byte change fails here first);
// - the freeze state is declared in one place (`EvalFreeze.declaredFrozen`) and must agree with the repository: the
//   manifest exists exactly when the eval is declared frozen, and the Tester's composition status says "Not frozen"
//   exactly when it is not. Writing the manifest without flipping the flag (or the reverse) fails;
// - the manifest verifier, on manifests rendered in memory from the real files, with negative controls;
// - the documented command (`EvalManifest.command`) writes the same bytes as the in-memory render, where `sha256sum`
//   exists (Linux; recorded as skipped elsewhere);
// - when the manifest exists, it verifies against every file in `Fixtures/M2/eval` (skipped, with the reason, until
//   then).
// To freeze: run `EvalManifest.command`, set `declaredFrozen = true`, and update the composition status, in one commit.

import Foundation
import Testing
@testable import TendIngestion

enum EvalFreeze {
    /// The declared freeze state of `Fixtures/M2/eval`. Not frozen: L2a (GR-4) and the composition-check condition (e)
    /// of PO ruling 1 are still open at this commit.
    static let declaredFrozen = false

    /// PO ruling 1 (approved at `95491ed`); recorded in `eval-composition.md` "PO approval".
    static let approvedSHA256: [String: String] = [
        "inputs.json": "b32e45afeb25a6d8972ce9f3b78a6dd051686d4ac6b7d87564769bf92c7ebcec",
        "household.json": "089a22bd5a0b3da9ef6b057b186f61b459963f02bbee322c30a47b2af8e17f66",
        "golden.json": "882c2906a15704b9b8376cfdd62aa3b909239b4b6f7ca9ce4d370fa69580d4dc",
    ]

    static var directory: URL {
        IngestionSourceScanTests.repositoryRoot().appendingPathComponent(EvalFixtureFiles.directory, isDirectory: true)
    }

    static var manifestURL: URL { directory.appendingPathComponent(EvalManifest.name) }

    static var manifestExists: Bool { FileManager.default.fileExists(atPath: manifestURL.path) }

    static let sha256sum = "/usr/bin/sha256sum"

    /// Every file a manifest must list, with its bytes.
    static func listedFiles() throws -> [(name: String, data: Data)] {
        try EvalManifest.listedNames(in: directory).map { ($0, try EvalFixtureFiles.data($0)) }
    }
}

@Suite("WI-M2-16 eval freeze and MANIFEST.sha256 (AC-M2-14)")
struct EvalFreezeTests {

    @Test("SHA-256 helper matches the FIPS 180-4 vectors (empty, \"abc\", 448-bit, 1 000 000 × a)")
    func sha256Vectors() {
        #expect(SHA256Hex.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256Hex.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256Hex.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(SHA256Hex.hex(Data(repeating: 0x61, count: 1_000_000))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("PO ruling 1: inputs.json, household.json and golden.json have the PO-approved SHA-256 (any change goes back to the PO)",
          arguments: EvalFixtureFiles.approvedNames)
    func approvedHashes(_ name: String) throws {
        #expect(SHA256Hex.hex(try EvalFixtureFiles.data(name)) == EvalFreeze.approvedSHA256[name])
    }

    @Test("PO ruling 1, negative control: one changed byte changes the hash")
    func approvedHashNegative() throws {
        var data = try EvalFixtureFiles.data("golden.json")
        data[data.startIndex + 40] ^= 0x01
        #expect(SHA256Hex.hex(data) != EvalFreeze.approvedSHA256["golden.json"])
    }

    @Test("AC-M2-14 freeze state: NOT frozen yet — no MANIFEST.sha256, and the Tester's composition status says \"Not frozen\" (flip EvalFreeze.declaredFrozen when freezing)")
    func freezeStateAgrees() throws {
        #expect(EvalFreeze.manifestExists == EvalFreeze.declaredFrozen,
                "MANIFEST.sha256 exists: \(EvalFreeze.manifestExists), declared frozen: \(EvalFreeze.declaredFrozen)")
        let status = try EvalManifest.compositionStatus()
        #expect(!status.isEmpty, "no \"- **Status:**\" bullet in \(EvalFixtureFiles.compositionDoc)")
        #expect(status.contains("Not frozen") == !EvalFreeze.declaredFrozen, "status: \(status)")
    }

    @Test("AC-M2-14: a manifest rendered from the real files verifies; the listed files are exactly the eval directory's")
    func renderedManifestVerifies() throws {
        let files = try EvalFreeze.listedFiles()
        #expect(files.map(\.name) == ["golden.json", "household.json", "inputs.json", "results-v1.schema.json"])
        let manifest = EvalManifest.render(files)
        #expect(EvalManifest.problems(manifest, files: files).isEmpty)
        #expect(manifest.split(separator: "\n").count == 4)
    }

    static let manifestControls: [(name: String, edit: @Sendable (String) -> String, problem: String)] = [
        ("a wrong hash (first line, golden.json)", { ($0.hasPrefix("0") ? "1" : "0") + $0.dropFirst() },
         "hash of golden.json"),
        ("a file left out", { String($0.split(separator: "\n").dropFirst().joined(separator: "\n") + "\n") },
         "does not list golden.json"),
        ("an unknown file listed", { $0 + String(repeating: "0", count: 64) + "  notes.txt\n" }, "not a fixture file"),
        ("names out of order", { String($0.split(separator: "\n").reversed().joined(separator: "\n") + "\n") },
         "byte order"),
        ("one space instead of two", { $0.replacingOccurrences(of: "  inputs.json", with: " inputs.json") },
         "malformed line"),
        ("upper-case hex", { $0.uppercased().replacingOccurrences(of: ".JSON", with: ".json") }, "malformed line"),
        ("no final newline", { String($0.dropLast()) }, "newline"),
    ]

    @Test("AC-M2-14 manifest verifier, negative controls: each broken manifest is refused",
          arguments: manifestControls.indices)
    func manifestNegative(_ index: Int) throws {
        let control = Self.manifestControls[index]
        let files = try EvalFreeze.listedFiles()
        let broken = control.edit(EvalManifest.render(files))
        let problems = EvalManifest.problems(broken, files: files)
        #expect(problems.contains { $0.contains(control.problem) }, "\(control.name): \(problems)")
    }

    @Test("AC-M2-14 manifest verifier, negative control: a fixture changed after the manifest was written is refused")
    func manifestRefusesChangedFile() throws {
        var files = try EvalFreeze.listedFiles()
        let manifest = EvalManifest.render(files)
        let index = try #require(files.firstIndex { $0.name == "inputs.json" })
        files[index].data.append(0x0A)
        #expect(EvalManifest.problems(manifest, files: files) == ["hash of inputs.json does not match"])
    }

    @Test("AC-M2-14: the documented manifest command writes exactly the in-memory render (stdout only; nothing written)",
          .enabled(if: FileManager.default.isExecutableFile(atPath: EvalFreeze.sha256sum),
                   "sha256sum is not installed here (Linux has it)"))
    func documentedCommandMatchesRender() throws {
        // The command is `cd <dir> && LC_ALL=C sha256sum <names> > MANIFEST.sha256`; run it without the redirection.
        #expect(EvalManifest.command.hasPrefix("cd " + EvalFixtureFiles.directory + " && LC_ALL=C sha256sum "))
        #expect(EvalManifest.command.hasSuffix(" > " + EvalManifest.name))
        let names = EvalManifest.command
            .dropFirst(("cd " + EvalFixtureFiles.directory + " && LC_ALL=C sha256sum ").count)
            .dropLast((" > " + EvalManifest.name).count)
            .split(separator: " ").map(String.init)
        #expect(names == (try EvalManifest.listedNames(in: EvalFreeze.directory)))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: EvalFreeze.sha256sum)
        process.arguments = names
        process.currentDirectoryURL = EvalFreeze.directory
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: output, as: UTF8.self) == EvalManifest.render(try EvalFreeze.listedFiles()))
    }

    @Test("AC-M2-14: MANIFEST.sha256 verifies against every file in Fixtures/M2/eval",
          .enabled(if: EvalFreeze.manifestExists, "not frozen yet: no MANIFEST.sha256 (waits for L2a, PO ruling 1)"))
    func committedManifestVerifies() throws {
        let manifest = try String(contentsOf: EvalFreeze.manifestURL, encoding: .utf8)
        let problems = EvalManifest.problems(manifest, files: try EvalFreeze.listedFiles())
        #expect(problems.isEmpty, "\(problems)")
    }
}
