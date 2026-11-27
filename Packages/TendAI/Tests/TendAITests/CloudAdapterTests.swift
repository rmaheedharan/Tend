// The three cloud adapters end to end over a mock transport (WI-M2-M6; brief AC-M2-24, with AC-M2-22/23 through the
// transport contract; ADR-0005; Q18). FR-A1, P-2, P-3, P-4.
//
// Every provider stream fixture in `Fixtures/M2/provider-streams` (33 synthetic, 1 recorded) is sent through the real
// cloud model (`CloudIngestionModel` via the provider types and `CloudAdapters`) and the real `DraftPipeline`, with
// the body cut in several ways by the mock transport. Two checks per fixture: the outcome and draft counts the fixture
// README states, and the same event list as the provider stream reader read directly (the Linux oracle path).

import Foundation
import Testing
@testable import TendAI
import TendCore
import TendIngestion

/// A transport that answers every attempt from a script and records what it was asked (test target only).
final class ScriptedCloudTransport: CloudTransport, @unchecked Sendable {
    // @unchecked Sendable: `log` is touched only under `lock`. Test target only.
    enum Reply: Sendable {
        case body([UInt8], chunk: Int)
        case failure(CloudTransportFailure)
        case hang
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var sent: [CloudRequest] = []
    private var terminated = 0

    init(_ replies: [Reply]) { self.replies = replies }

    var requests: [CloudRequest] { lock.withLock { sent } }
    var terminations: Int { lock.withLock { terminated } }

    func send(_ request: CloudRequest, timeouts: CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error> {
        let reply = lock.withLock { () -> Reply in
            sent.append(request)
            return replies.isEmpty ? .failure(CloudTransportFailure(.unexpectedResponse)) : replies.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                switch reply {
                case let .body(bytes, chunk):
                    var start = 0
                    while start < bytes.count {
                        let end = min(bytes.count, start + max(1, chunk))
                        continuation.yield(Array(bytes[start..<end]))
                        start = end
                    }
                    continuation.finish()
                case let .failure(failure):
                    continuation.finish(throwing: failure)
                case .hang:
                    while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
                    continuation.finish()
                }
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.lock.withLock { self?.terminated += 1 }
            }
        }
    }
}

enum CloudFixtures {
    static let outcomeSentence = "The AC needs servicing before summer, we're almost out of dishwasher pods, "
        + "and let's deep clean the balcony this weekend if it doesn't rain"
    static let fakeKey = APIKey("FAKE-TEST-KEY-not-a-real-key-0000")

    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // Tests/TendAITests/<file> → Packages/TendAI → repo
        return url
    }

    static func bytes(_ relative: String) throws -> [UInt8] {
        Array(try Data(contentsOf: repositoryRoot.appendingPathComponent(relative)))
    }

    static let names = ["happy-path", "out-of-order-fields", "truncated-after-first-draft",
                        "length-limit-after-first-draft", "invalid-json-after-first-draft",
                        "invalid-event-before-draft", "schema-violating-fields", "unknown-enum-values",
                        "refusal-before-draft", "provider-error-after-first-draft", "finished-output-no-end"]

    enum Outcome: Hashable { case completed, interrupted(ModelStopReason), noModel(ModelStopReason) }

    /// The fixture README's table: outcome, drafts, skips.
    static func expected(_ name: String) -> (Outcome, drafts: Int, skips: Int) {
        switch name {
        case "happy-path", "out-of-order-fields": (.completed, 3, 0)
        case "truncated-after-first-draft", "length-limit-after-first-draft": (.interrupted(.outputCutShort), 1, 0)
        case "invalid-json-after-first-draft": (.interrupted(.unreadableOutput), 1, 0)
        case "invalid-event-before-draft": (.noModel(.unreadableOutput), 0, 0)
        case "schema-violating-fields": (.completed, 2, 1)
        case "unknown-enum-values": (.completed, 2, 0)
        case "refusal-before-draft": (.noModel(.refusal), 0, 0)
        case "provider-error-after-first-draft": (.interrupted(.serviceUnavailable), 1, 0)
        case "finished-output-no-end": (.interrupted(.outputCutShort), 3, 0)
        default: (.completed, -1, -1)
        }
    }

    static func outcome(_ events: [DraftStreamEvent]) -> Outcome? {
        guard case let .finished(result)? = events.last else { return nil }
        return switch result {
        case .completed: .completed
        case let .interrupted(_, reason, _, _): .interrupted(reason)
        case let .noModel(_, .stoppedBeforeFirstDraft(reason), _, _): .noModel(reason)
        case .noModel, .cancelled: nil
        }
    }

    static func pipeline(_ input: String = outcomeSentence, household: Household = Household(tasks: [], rooms: []))
        -> DraftPipeline {
        DraftPipeline(input: input, rooms: household.rooms, now: Date(timeIntervalSince1970: 1_800_000_000),
                      calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC") ?? .gmt,
                      duplicateCheck: DraftDuplicateRules.cloud(.shortlistTitles, capture: input, household: household))
    }

    static func events(_ model: some IngestionModel, provider: CloudProvider,
                       pipeline: DraftPipeline = pipeline()) async -> [DraftStreamEvent] {
        var all: [DraftStreamEvent] = []
        for await event in pipeline.events(from: .cloud(provider, model)) { all.append(event) }
        return all
    }

    static func adapter(_ provider: CloudProvider, transport: any CloudTransport) -> any IngestionModel {
        CloudAdapters(transport: transport, clock: ContinuousClock()).model(for: provider, key: fakeKey)
    }

    /// The oracle: the provider stream reader over the whole body, as a model (the Linux path).
    struct DirectReaderModel: IngestionModel {
        let provider: CloudProvider
        let bytes: [UInt8]
        func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
            let (provider, bytes) = (provider, bytes)
            return AsyncThrowingStream { continuation in
                var reader = ProviderStreamReader(provider: provider)
                do throws(ProviderStreamError) {
                    if let snapshot = try reader.append(bytes) { continuation.yield(snapshot) }
                    continuation.yield(try reader.finish())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error.stopReason)
                }
            }
        }
    }
}

@Suite("Cloud adapters end to end (WI-M2-M6; AC-M2-24)", .timeLimit(.minutes(2)))
struct CloudAdapterTests {
    typealias F = CloudFixtures

    static let cases: [(CloudProvider, String)] = CloudProvider.allCases.flatMap { p in F.names.map { (p, $0) } }

    static func folder(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        }
    }

    @Test("AC-M2-24: every synthetic fixture through the cloud adapter gives the README's outcome and the reader's events",
          arguments: Array(0..<33))
    func syntheticFixture(index: Int) async throws {
        let (provider, name) = Self.cases[index]
        let body = try F.bytes("Fixtures/M2/provider-streams/synthetic/\(Self.folder(provider))/\(name).sse")
        let oracle = await F.events(F.DirectReaderModel(provider: provider, bytes: body), provider: provider)
        let (outcome, drafts, skips) = F.expected(name)
        for chunk in [body.count, 64, 7, 1] {
            let transport = ScriptedCloudTransport([.body(body, chunk: chunk)])
            let events = await F.events(F.adapter(provider, transport: transport), provider: provider)
            let summary = DraftStreamSummary(events)
            #expect(F.outcome(events) == outcome, "\(provider) \(name) chunk \(chunk)")
            #expect(summary.drafts.count == drafts, "\(provider) \(name) chunk \(chunk)")
            #expect(summary.skipped.count == skips, "\(provider) \(name) chunk \(chunk)")
            #expect(events == oracle, "\(provider) \(name) chunk \(chunk): same events as the reader read directly")
            #expect(transport.requests.count == 1)
        }
    }

    @Test("AC-M2-24: the real Gemini recording (L2a, 2026-11-25) through the adapter gives 3 drafts, completed, no skip")
    func geminiRecording() async throws {
        let body = try F.bytes("Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse")
        for chunk in [body.count, 97, 5] {
            let transport = ScriptedCloudTransport([.body(body, chunk: chunk)])
            let events = await F.events(F.adapter(.gemini, transport: transport), provider: .gemini)
            let summary = DraftStreamSummary(events)
            #expect(F.outcome(events) == .completed)
            #expect(summary.drafts.map(\.title) == ["The AC needs servicing", "dishwasher pods",
                                                    "deep clean the balcony"])
            #expect(summary.skipped.isEmpty)
        }
    }

    @Test("The request the adapter sends for the Outcome sentence is the committed golden request, byte for byte",
          arguments: CloudProvider.allCases)
    func goldenRequest(provider: CloudProvider) async throws {
        let transport = ScriptedCloudTransport([.failure(CloudTransportFailure(.unexpectedResponse))])
        _ = await F.events(F.adapter(provider, transport: transport), provider: provider)
        let request = try #require(transport.requests.first)
        let name = "Fixtures/M2/payload/golden/g1-outcome-empty-\(Self.folder(provider))"
        #expect(Array(request.body) == (try F.bytes(name + ".body.json")))
        let head = String(decoding: try F.bytes(name + ".head.txt"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        var target = request.host + request.path
        if !request.queryItems.isEmpty {
            target += "?" + request.queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&")
        }
        #expect(head.first == "POST " + request.host + " " + target.dropFirst(request.host.count))
        let lines = request.headers.map { header in header.withValue { header.name + ": " + $0 } }
        #expect(Array(head.dropFirst()) == lines)
        #expect(request.model == CloudModel.defaultModel(for: provider))
    }

    @Test("Q12 = yes: the request carries the pipeline's shortlist titles and room names, and nothing else of the household",
          arguments: CloudProvider.allCases)
    func shortlistInRequest(provider: CloudProvider) async throws {
        let kitchen = Room(id: UUID(uuid: (1, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)), name: "Kitchen")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let pods = try HouseholdTask(id: UUID(uuid: (2, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2)),
                                     title: "Buy dishwasher pods", kind: .restock, roomID: kitchen.id, effort: .low,
                                     windowStart: start, windowEnd: start.addingTimeInterval(86_400))
        let mop = try HouseholdTask(id: UUID(uuid: (3, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 3)),
                                    title: "Mop the hallway", kind: .oneOff, effort: .normal,
                                    windowStart: start, windowEnd: start.addingTimeInterval(86_400))
        let household = Household(tasks: [pods, mop], rooms: [kitchen])
        let transport = ScriptedCloudTransport([.failure(CloudTransportFailure(.unexpectedResponse))])
        _ = await F.events(F.adapter(provider, transport: transport), provider: provider,
                           pipeline: F.pipeline(household: household))
        let request = try #require(transport.requests.first)
        let body = String(decoding: request.body, as: UTF8.self)
        #expect(body.contains("Buy dishwasher pods"))     // shortlisted by the capture's words
        #expect(!body.contains("Mop the hallway"))        // not on the shortlist
        #expect(body.contains("Kitchen"))
        #expect(!body.contains(pods.id.uuidString) && !body.contains(kitchen.id.uuidString))
        let expected = try CloudPayloadBuilder.request(
            CloudPayloadInput(capture: F.outcomeSentence, roomNames: ["Kitchen"],
                              shortlistTitles: DuplicateShortlist.entries(for: F.outcomeSentence, in: household)
                                .map(\.title)),
            model: CloudModel.defaultModel(for: provider), key: F.fakeKey)
        #expect(request == expected)
    }

    @Test("Q18: each provider's model is pinned, streams structured output, and fixes sampling and reasoning at the lowest level",
          arguments: CloudProvider.allCases)
    func q18(provider: CloudProvider) async throws {
        let model = CloudModel.defaultModel(for: provider)
        for alias in ["latest", "preview", "exp"] { #expect(!model.rawValue.contains(alias)) }
        let transport = ScriptedCloudTransport([.failure(CloudTransportFailure(.unexpectedResponse))])
        _ = await F.events(F.adapter(provider, transport: transport), provider: provider)
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let profile = model.requestProfile
        switch provider {
        case .openAI:
            #expect(body["stream"] as? Bool == true)
            #expect(body["reasoning_effort"] as? String == "none")
            #expect(body["temperature"] == nil)
            #expect(((body["response_format"] as? [String: Any])?["type"] as? String) == "json_schema")
        case .anthropic:
            #expect(body["stream"] as? Bool == true)
            #expect((body["temperature"] as? NSNumber)?.doubleValue == 0)
            #expect(body["thinking"] == nil)
            #expect((body["tools"] as? [[String: Any]])?.count == 1)
            #expect(body["tool_choice"] != nil)
        case .gemini:
            #expect(request.queryItems.contains { $0.name == "alt" && $0.value == "sse" })
            let config = try #require(body["generationConfig"] as? [String: Any])
            #expect(config["responseMimeType"] as? String == "application/json")
            #expect(config[profile.schemaMember] != nil)
            #expect((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "minimal")
            #expect(config["temperature"] == nil)
        }
        #expect(profile.fits(provider))
    }

    @Test("A cloud model is never given the duplicate Tool: no lookup queries in any snapshot, no Tool in the model")
    func noTool() async throws {
        for provider in CloudProvider.allCases {
            let body = try F.bytes("Fixtures/M2/provider-streams/synthetic/\(Self.folder(provider))/happy-path.sse")
            let model = F.adapter(provider, transport: ScriptedCloudTransport([.body(body, chunk: 33)]))
            var queries: [[String]] = []
            for try await snapshot in model.snapshots(for: IngestionRequest(input: F.outcomeSentence,
                                                                            roomNames: [])) {
                queries.append(snapshot.lookupQueries)
            }
            #expect(!queries.isEmpty)
            let allEmpty = queries.allSatisfy { $0.isEmpty }
            #expect(allEmpty)
            let fields = String(describing: Mirror(reflecting: model).children.map { "\($0.label ?? "")" })
            #expect(!fields.lowercased().contains("tool") && !fields.lowercased().contains("lookup"))
        }
    }

    @Test("AC-M2-23: a key the provider does not accept ends noModel before any draft, with no retry")
    func keyNotAccepted() async {
        let transport = ScriptedCloudTransport([.failure(CloudTransportFailure(.keyNotAccepted))])
        let events = await F.events(F.adapter(.anthropic, transport: transport), provider: .anthropic)
        #expect(F.outcome(events) == .noModel(.keyNotAccepted))
        #expect(transport.requests.count == 1)
    }

    @Test("AC-M2-22/23: a 503 before any body is retried once inside the deadline, then the body is read")
    func retryOnce() async throws {
        let body = try F.bytes("Fixtures/M2/provider-streams/synthetic/openai/happy-path.sse")
        let transport = ScriptedCloudTransport([.failure(CloudTransportFailure(.serviceUnavailable, retryAfter: "0")),
                                                .body(body, chunk: 50)])
        let events = await F.events(F.adapter(.openAI, transport: transport), provider: .openAI)
        #expect(F.outcome(events) == .completed)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0] == transport.requests[1])
    }

    @Test("Contract 3: cancelling the capture ends it cancelled and releases the transport stream")
    func cancellation() async throws {
        let transport = ScriptedCloudTransport([.hang])
        let model = F.adapter(.gemini, transport: transport)
        let pipeline = F.pipeline()
        let task = Task {
            var all: [DraftStreamEvent] = []
            for await event in pipeline.events(from: .cloud(.gemini, model)) { all.append(event) }
            return all
        }
        for _ in 0..<200 where transport.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let events = await task.value
        #expect(events.last == .finished(.cancelled(route: .cloud(.gemini))))
        for _ in 0..<200 where transport.terminations == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(transport.terminations == 1)
    }

    @Test("A stream created inside a cancelled task sends nothing, even while the stream is still held")
    func createdCancelled() async throws {
        let transport = ScriptedCloudTransport([.hang])
        let model = F.adapter(.openAI, transport: transport)
        // Make the stream in a cancelled task and hand it out without reading it, so only the adapter's own check
        // (not the consumer's termination) can keep the request from being sent.
        let made = Task { () -> AsyncThrowingStream<IngestionSnapshot, any Error> in
            withUnsafeCurrentTask { $0?.cancel() }
            return model.snapshots(for: IngestionRequest(input: "x", roomNames: []))
        }
        let stream = await made.value
        try await Task.sleep(for: .milliseconds(200))
        #expect(transport.requests.isEmpty)
        var count = 0
        for try await _ in stream { count += 1 }
        #expect(count == 0)
        #expect(transport.requests.isEmpty)
    }

    @Test("CloudAdapters builds the asked provider's model with its curated model, and nothing else",
          arguments: CloudProvider.allCases)
    func adapterChoice(provider: CloudProvider) {
        let model = F.adapter(provider, transport: ScriptedCloudTransport([]))
        let built: CloudModel? = switch model {
        case let m as OpenAIIngestionModel<ContinuousClock>: m.model
        case let m as AnthropicIngestionModel<ContinuousClock>: m.model
        case let m as GeminiIngestionModel<ContinuousClock>: m.model
        default: nil
        }
        #expect(built == CloudModel.defaultModel(for: provider))
        #expect(built?.provider == provider)
    }

    @Test("Through the router: with Gemini turned on, a capture takes route cloud(gemini) and the recording gives 3 drafts")
    func routerEndToEnd() async throws {
        let body = try F.bytes("Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse")
        let transport = ScriptedCloudTransport([.body(body, chunk: 128)])
        let router = ModelRouter(onDevice: UnavailableOnDeviceSource(),
                                 cloudModels: CloudAdapters(transport: transport, clock: ContinuousClock()),
                                 consents: InMemoryCloudConsentStore(), keys: InMemoryAPIKeyStore())
        _ = try await router.turnCloudOn(.gemini, key: F.fakeKey)
        let routed = await router.events(input: F.outcomeSentence, household: Household(tasks: [], rooms: []),
                                         now: Date(timeIntervalSince1970: 1_800_000_000),
                                         calendar: Calendar(identifier: .gregorian),
                                         timeZone: TimeZone(identifier: "UTC") ?? .gmt,
                                         titleSharing: .shortlistTitles, preference: .onDeviceFirst)
        #expect(routed.route == .cloud(.gemini))
        var events: [DraftStreamEvent] = []
        for await event in routed { events.append(event) }
        #expect(DraftStreamSummary(events).drafts.count == 3)
        #expect(transport.requests.first?.provider == .gemini)
    }
}

struct UnavailableOnDeviceSource: OnDeviceModelSource {
    func availability() -> OnDeviceAvailability { .unavailable(.deviceNotEligible) }
    func model(household: Household) -> any IngestionModel { FailingModel() }
}
