// The TendEval harness on the iOS Simulator, hosted by the TendEval app (WI-M2-M7; AC-M2-28 "What it does",
// "Results file (format v1)", "Export"; AC-M2-16, AC-M2-17; D-059). No network: cloud runs use a scripted transport
// that answers with the committed synthetic provider streams, and the key is a fake one in an in-memory store.
// The results file each run builds is read back by the scorer's reader (schema, canonical form, cross-field rules).

import CryptoKit
import Foundation
import Testing
@testable import TendEval
import TendAI
import TendCore
import TendIngestion

/// Answers every attempt with one body and records what it was sent (test target only).
final class ScriptedEvalTransport: CloudTransport, @unchecked Sendable {
    // @unchecked Sendable: `sent` is touched only under `lock`. Test target only.
    private let body: [UInt8]
    private let lock = NSLock()
    private var sent: [CloudRequest] = []

    init(body: [UInt8]) { self.body = body }

    var requests: [CloudRequest] { lock.withLock { sent } }

    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        lock.withLock { sent.append(request) }
        let body = body
        return AsyncThrowingStream { continuation in
            var start = 0
            while start < body.count {
                let end = min(body.count, start + 97)
                continuation.yield(Array(body[start..<end]))
                start = end
            }
            continuation.finish()
        }
    }
}

/// An on-device source that is available and whose model records the input and ends with no items.
final class RecordingOnDevice: OnDeviceModelSource, @unchecked Sendable {
    // @unchecked Sendable: `inputs` is touched only under `lock`. Test target only.
    private let lock = NSLock()
    private var seen: [String] = []
    var inputs: [String] { lock.withLock { seen } }

    func availability() -> OnDeviceAvailability { .available }

    func model(household: Household) -> any IngestionModel { Model(owner: self) }

    struct Model: IngestionModel {
        let owner: RecordingOnDevice
        func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
            owner.lock.withLock { owner.seen.append(request.input) }
            return AsyncThrowingStream { $0.finish() }
        }
    }
}

enum Repo {
    static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // Apps/TendEval/Tests/<file> → repo
        return url
    }

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relative))
    }
}

@Suite("TendEval harness (WI-M2-M7; AC-M2-28)", .serialized)
struct EvalHarnessTests {
    static let fakeKey = APIKey("FAKE-TEST-KEY-not-a-real-key-0000")

    static func bundle() throws -> EvalBundle { try EvalBundle.load() }

    static func run(_ attempts: [EvalResultsFileV1.InputAttempt], kind: EvalRunKind, bundle: EvalBundle,
                    coldStart: EvalResultsFileV1.ColdStart? = nil) -> EvalResultsFileV1 {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        return EvalResultsFileV1(
            run: .init(operatorName: "test", startedAtUTC: EvalRunRecord.startedAtUTC(started),
                       deviceModel: EvalRunRecord.deviceModel(), iOSBuild: EvalRunRecord.iOSBuild(),
                       appCommitSHA: String(repeating: "0", count: 40), fixturesSHA256: bundle.fixturesSHA256,
                       locale: "en-US",
                       routePreference: kind.preference == .alwaysCloud ? .alwaysCloud : .onDeviceFirst,
                       provider: kind.provider.map(EvalProvider.init), modelID: kind.modelID,
                       sampling: kind.sampling, prewarm: kind.provider == nil,
                       network: .init(kind: "test", downMbps: 0, upMbps: 0, latencyMs: 0)),
            coldStart: coldStart, inputs: attempts)
    }

    /// The scorer's reader: schema, canonical JSON, the fixtures hash and every cross-field rule.
    static func readBack(_ file: EvalResultsFileV1, bundle: EvalBundle) throws -> EvalResultsFileV1 {
        let data = try CanonicalJSONWriter.data(file.canonicalJSON)
        let schema = try EvalSchemaCheck(schemaData: try Repo.data("Fixtures/M2/eval/results-v1.schema.json"))
        return try EvalResultsFileV1.read(data, schema: schema, fixtures: bundle.fixtures,
                                          expectedFixturesSHA256: bundle.fixturesSHA256)
    }

    @Test("The bundled fixtures load through the loader, match MANIFEST.sha256, and the on-screen hash is the SHA-256 of the manifest bytes")
    func bundleHash() throws {
        let bundle = try Self.bundle()
        #expect(bundle.allMatch)
        #expect(bundle.checks.map(\.name) == ["inputs.json", "household.json", "golden.json"])
        let manifest = try Repo.data("Fixtures/M2/eval/MANIFEST.sha256")
        #expect(bundle.fixturesSHA256 == SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined())
        #expect(bundle.fixtures.inputs.count == 20)
        // The bundled data files are byte for byte the repo's.
        for (name, data) in [("inputs", try EvalFixturesLoader.inputs()), ("household", try EvalFixturesLoader.household()),
                             ("golden", try EvalFixturesLoader.golden())] {
            #expect(data == (try Repo.data("Fixtures/M2/eval/\(name).json")), "\(name)")
        }
    }

    @Test("On device: every text input is fed verbatim; the attempts are read back as a valid v1 file")
    func onDeviceText() async throws {
        let bundle = try Self.bundle()
        let source = RecordingOnDevice()
        let runner = EvalRunner(bundle: bundle, kind: .onDevice, onDevice: source,
                                transport: ScriptedEvalTransport(body: []), keys: InMemoryAPIKeyStore())
        let texts = bundle.fixtures.inputs.filter { $0.mode == .text }
        var attempts: [EvalResultsFileV1.InputAttempt] = []
        for input in texts {
            await runner.prewarm()
            attempts.append(try #require(await runner.run(inputID: input.id, attempt: 1, retakeReason: nil, voice: nil)))
        }
        #expect(source.inputs == texts.map(\.text))
        #expect(attempts.allSatisfy { $0.route == .onDevice && $0.outcome == .completed && $0.cloudRequests.isEmpty })
        #expect(attempts.allSatisfy { $0.totalMs >= 0 && $0.events.last?.type == .finished })
        let read = try Self.readBack(Self.run(attempts, kind: .onDevice, bundle: bundle,
                                              coldStart: .init(inputID: "in01", ttfiMs: nil)), bundle: bundle)
        #expect(read.inputs.count == texts.count)
    }

    @Test("A voice attempt feeds the live transcript to the pipeline and keeps it, the transcriber and retake reason; the clock starts at the final result",
          arguments: [1, 2])
    func voiceAttempt(attempt: Int) async throws {
        let bundle = try Self.bundle()
        let voice = try #require(bundle.fixtures.inputs.first { $0.mode == .voice })
        let source = RecordingOnDevice()
        let runner = EvalRunner(bundle: bundle, kind: .onDevice, onDevice: source,
                                transport: ScriptedEvalTransport(body: []), keys: InMemoryAPIKeyStore())
        let heard = voice.text + " um"
        let finalAt = runner.clock.now.advanced(by: .milliseconds(-300))
        let result = try #require(await runner.run(
            inputID: voice.id, attempt: attempt, retakeReason: attempt == 2 ? "misread" : nil,
            voice: VoiceResult(transcript: heard, transcriber: .speechTranscriber, finalResultAt: finalAt)))
        #expect(result.transcript == heard)
        #expect(source.inputs == [heard], "the pipeline is given the live transcript, not the script")
        #expect(result.transcriber == .speechTranscriber)
        #expect(result.retakeReason == (attempt == 2 ? "misread" : nil))
        #expect(result.totalMs >= 300, "the total runs from the transcriber's final result")
        var attempts = [result]
        if attempt == 2 {
            var first = result
            first.attempt = 1
            first.retakeReason = nil
            attempts.insert(first, at: 0)
        }
        _ = try Self.readBack(Self.run(attempts, kind: .onDevice, bundle: bundle), bundle: bundle)
    }

    @Test("Cloud (each provider, scripted transport): drafts come through the real adapter, the key is stored then removed, and each request records bytes, key paths and the D-059 counts",
          arguments: CloudProvider.allCases)
    func cloudRun(provider: CloudProvider) async throws {
        let bundle = try Self.bundle()
        let folder = switch provider {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        }
        let body = Array(try Repo.data("Fixtures/M2/provider-streams/synthetic/\(folder)/happy-path.sse"))
        let transport = ScriptedEvalTransport(body: body)
        let keys = InMemoryAPIKeyStore()
        let kind = EvalRunKind.cloud(provider, preference: .alwaysCloud)
        let runner = EvalRunner(bundle: bundle, kind: kind, onDevice: RecordingOnDevice(), transport: transport,
                                keys: keys)
        #expect(try await runner.turnCloudOn(key: Self.fakeKey) == .on(provider))
        let input = try #require(bundle.fixtures.inputs.first { $0.mode == .text })
        let attempt = try #require(await runner.run(inputID: input.id, attempt: 1, retakeReason: nil, voice: nil))
        #expect(attempt.route == EvalRoute(.cloud(provider)))
        #expect(attempt.outcome == .completed)
        #expect(attempt.drafts.count == 3)
        #expect(attempt.committed.count == attempt.drafts.filter { !$0.duplicate.isMarked }.count)
        let sent = try #require(transport.requests.first)
        let record = try #require(attempt.cloudRequests.first)
        #expect(attempt.cloudRequests.count == transport.requests.count)
        #expect(record.bytes == sent.body.count)
        #expect(record.keyPaths == CloudRequestKeyPaths.leafPaths(ofBody: sent.body))
        // D-059: the fixed body shape equals the provider's G1 golden body; user content counts the seeded rooms.
        let golden = try Repo.data("Fixtures/M2/payload/golden/g1-outcome-empty-\(folder).body.json")
        #expect(record.arrayCounts == CloudRequestKeyPaths.arrayCounts(ofBody: golden))
        let content = try #require(record.userContentArrayCounts)
        #expect(content.map(\.path) == ["$.existingTasks", "$.rooms"])
        #expect(content.last?.count == bundle.fixtures.rooms.count)
        #expect((content.first?.count ?? 99) <= 10)
        // The file holds no body, header value or key.
        let file = Self.run([attempt], kind: kind, bundle: bundle)
        let text = String(decoding: try CanonicalJSONWriter.data(file.canonicalJSON), as: UTF8.self)
        #expect(!text.contains("FAKE-TEST-KEY"))
        _ = try Self.readBack(file, bundle: bundle)
        try await runner.removeKey()
        #expect(await keys.hasKey(for: provider) == false)
    }

    @Test("The writer puts the canonical file in Documents under the AC-M2-28 name, and nothing else")
    func writer() throws {
        let bundle = try Self.bundle()
        let file = Self.run([], kind: .onDevice, bundle: bundle)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let name = EvalRunRecord.fileName(deviceModel: "iPhone16,1", kind: .cloud(.gemini, preference: .onDeviceFirst),
                                          startedAt: started)
        #expect(name == "m2-eval-iPhone16,1-gemini-20270115T080000Z.json")
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: documents.path))
        let written = try EvalResultsWriter.write(file, name: name)
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: documents.path))
        #expect(after.subtracting(before) == [name] || before.contains(name))
        let url = documents.appendingPathComponent(name)
        #expect(try Data(contentsOf: url) == written)
        #expect(written == (try CanonicalJSONWriter.data(file.canonicalJSON)))
        try FileManager.default.removeItem(at: url)
    }
}
