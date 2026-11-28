// Test support for the WI-M2-10 payload tests (AC-M2-20, the ○ part; WI-M2-11 owns the full sentinel proof). P-3.
//
// - The three golden households (`PayloadGolden`), with fixed version-4 UUIDs (T-29) and one capture each.
// - An obvious fake API key. No real key is used anywhere.
// - The recording mock transport (`PayloadRecordingTransport`), a test double only: it records the `CloudRequest` it
//   is given and answers with an empty stream. The tests assert on the captured request, not on the builder's
//   intermediate values (AC-M2-20, last bullet).
// - The golden request files: `<household>-<provider>.head.txt` (method, host, path and query, then one header per
//   line) and `<household>-<provider>.body.json` (the exact body bytes). Both are written from the captured request.
// - Independent oracles: JSON leaf key paths through `JSONSerialization` (not the production reader), and a reader for
//   the user content that checks its exact shape.
//
// Regenerating the golden files (only under a PO decision, R-15): run the golden test with the environment variable
// `TEND_PAYLOAD_GOLDEN_OUT` set to a directory. The test then also writes the files it builds there (never into the
// repository) and still compares them with the committed ones.

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

enum PayloadFixture {
    /// An obvious fake key (never a real one).
    static let fakeKey = APIKey("FAKE-TEST-KEY-not-a-real-key-0000")
    static let fakeKeyText = "FAKE-TEST-KEY-not-a-real-key-0000"

    static let payloadDirectory = "Fixtures/M2/payload"
    static let goldenDirectory = "Fixtures/M2/payload/golden"
    static let resultsSchemaPath = "Fixtures/M2/eval/results-v1.schema.json"

    static func repositoryFile(_ relative: String) throws -> Data {
        try Data(contentsOf: IngestionSourceScanTests.repositoryRoot().appendingPathComponent(relative))
    }

    /// The fixture file name part for each provider.
    static func name(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        }
    }

    /// The brief's Outcome sentence (brief "Outcome"), used by `tend-payload-dump --outcome-sample` with an empty
    /// household (plan "Real provider recordings").
    static let outcomeSentence = "The AC needs servicing before summer, we're almost out of dishwasher pods, and let's "
        + "deep clean the balcony this weekend if it doesn't rain"

    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
    static let end = Date(timeIntervalSinceReferenceDate: 815_604_800)

    /// A fixed version-4 UUID: `6e5d0a10-0000-4000-8000-<12 hex digits>`.
    static func uuid(_ suffix: String) -> UUID {
        UUID(uuidString: "6E5D0A10-0000-4000-8000-" + suffix) ?? DupFixture.zeroUUID
    }

    /// A valid task (the M1 initialiser accepts every combination used here).
    static func task(_ suffix: String, _ title: String, kind: TaskKind = .oneOff, room: UUID? = nil,
                     state: DupFixture.StateChoice = .active) -> HouseholdTask {
        DupFixture.task(uuid(suffix), title, kind: kind, room: room, state: state)
    }
}

/// One golden household: a capture and the household it is read with.
struct PayloadGoldenCase: Sendable, CustomTestStringConvertible {
    var name: String
    var capture: String
    var household: Household
    var testDescription: String { name }
}

enum PayloadGolden {
    /// G1: the brief's Outcome sentence with an empty household (the `tend-payload-dump --outcome-sample` body).
    static let g1 = PayloadGoldenCase(name: "g1-outcome-empty", capture: PayloadFixture.outcomeSentence,
                                      household: Household(tasks: [], rooms: []))

    // G2: a typical household. Hand-derived shortlist for its capture (brief Definitions, steps 1–6):
    // the capture's keywords are {kitchen, bin, smells, low, dishwasher, pods, balcony, plants, water, saturday,
    // morning} ("again", "we", "re", "on", "the", "and", "need" are stop words).
    //   "Water the balcony plants"   K = 3, R = 1 (Balcony)
    //   "Buy dishwasher pods"        K = 2, R = 1 (Kitchen)   } same K and R: folded title "buy …" < "take …"
    //   "Take out the kitchen bin"   K = 2, R = 1 (Kitchen)   }
    //   "Clean the oven"             K = 0, R = 1 (Kitchen): room only
    //   "Service the AC" and "Buy dish soap" are completed: never candidates. Bathroom and garage tasks share no word.
    static let g2Rooms: [Room] = [
        Room(id: PayloadFixture.uuid("0000000002A1"), name: "Kitchen", lastTendedAt: PayloadFixture.start),
        Room(id: PayloadFixture.uuid("0000000002A2"), name: "Bathroom"),
        Room(id: PayloadFixture.uuid("0000000002A3"), name: "Balcony", lastTendedAt: PayloadFixture.end),
        Room(id: PayloadFixture.uuid("0000000002A4"), name: "Kids\u{2019} room"),
        Room(id: PayloadFixture.uuid("0000000002A5"), name: "Garage"),
    ]
    static let g2 = PayloadGoldenCase(
        name: "g2-typical",
        capture: "The kitchen bin smells again, we're low on dishwasher pods, and the balcony plants need water on "
            + "Saturday morning",
        household: Household(
            tasks: [
                PayloadFixture.task("0000000002B1", "Buy dishwasher pods", kind: .restock, room: g2Rooms[0].id),
                PayloadFixture.task("0000000002B2", "Clean the oven", room: g2Rooms[0].id),
                PayloadFixture.task("0000000002B3", "Water the balcony plants", kind: .recurring, room: g2Rooms[2].id),
                PayloadFixture.task("0000000002B4", "Service the AC", state: .completed),
                PayloadFixture.task("0000000002B5", "Wash the bath mat", kind: .recurring, room: g2Rooms[1].id,
                                    state: .deferred),
                PayloadFixture.task("0000000002B6", "Sort the garage shelves", room: g2Rooms[4].id,
                                    state: .maintenance),
                PayloadFixture.task("0000000002B7", "Take out the kitchen bin", kind: .recurring, room: g2Rooms[0].id),
                PayloadFixture.task("0000000002B8", "Buy dish soap", kind: .restock, room: g2Rooms[0].id,
                                    state: .completed),
            ],
            rooms: g2Rooms
        )
    )
    static let g2ExpectedTitles = ["Water the balcony plants", "Buy dishwasher pods", "Take out the kitchen bin",
                                   "Clean the oven"]

    // G3: escaping and the cap. Room names are sent as written (Q19): spaces, quotes, a slash, a backslash and
    // non-ASCII. 13 live tasks share the keyword "towels", so the shortlist is cut at 10 (step 6); completed towel
    // tasks are never sent. Titles hold a tab, an emoji, quotes and surrounding whitespace (trimmed, D7).
    static let g3Rooms: [Room] = [
        Room(id: PayloadFixture.uuid("0000000003A1"), name: "Caf\u{E9}"),
        Room(id: PayloadFixture.uuid("0000000003A2"), name: "  Hall  "),
        Room(id: PayloadFixture.uuid("0000000003A3"), name: "Laundry \"nook\""),
        Room(id: PayloadFixture.uuid("0000000003A4"), name: "Shed/Yard"),
        Room(id: PayloadFixture.uuid("0000000003A5"), name: "Loft\\attic"),
    ]
    static let g3 = PayloadGoldenCase(
        name: "g3-edge",
        capture: "Wash the towels in the Caf\u{E9}, fold \u{201C}towels\u{201D} \u{1F9FA}, and check the shed/yard\n"
            + "then the loft\\attic \"quickly\"",
        household: Household(
            tasks: [
                PayloadFixture.task("0000000003B1", "Fold towels \u{1F9FA}", room: g3Rooms[2].id),
                PayloadFixture.task("0000000003B2", "Wash\ttowels", kind: .recurring, room: g3Rooms[2].id),
                PayloadFixture.task("0000000003B3", " Hang towels \n", room: g3Rooms[1].id),
                PayloadFixture.task("0000000003B4", "Buy \"soft\" towels", kind: .restock),
                PayloadFixture.task("0000000003B5", "Iron towels/sheets", room: g3Rooms[2].id),
                PayloadFixture.task("0000000003B6", "Sort beach towels", room: g3Rooms[3].id),
                PayloadFixture.task("0000000003B7", "Air the guest towels", room: g3Rooms[4].id),
                PayloadFixture.task("0000000003B8", "Replace kitchen towels", kind: .restock, room: g3Rooms[0].id),
                PayloadFixture.task("0000000003B9", "Stack towels", room: g3Rooms[1].id, state: .resurfaced),
                PayloadFixture.task("0000000003C1", "Mend towels", state: .deferred),
                PayloadFixture.task("0000000003C2", "Count towels", kind: .recurring, state: .maintenance),
                PayloadFixture.task("0000000003C3", "Bleach towels", room: g3Rooms[2].id),
                PayloadFixture.task("0000000003C4", "Dry towels outside", room: g3Rooms[3].id),
                PayloadFixture.task("0000000003C5", "Donate old towels", state: .completed),
                PayloadFixture.task("0000000003C6", "Buy towels", kind: .restock, state: .completed),
                PayloadFixture.task("0000000003C7", "Paint the fence", room: g3Rooms[3].id),
            ],
            rooms: g3Rooms
        )
    )

    static let all: [PayloadGoldenCase] = [g1, g2, g3]

    /// The file name stem of one golden request.
    static func stem(_ golden: PayloadGoldenCase, _ provider: CloudProvider) -> String {
        golden.name + "-" + PayloadFixture.name(provider)
    }
}

/// The recording mock transport (AC-M2-20; a test double only, never linked into a module). It records each request
/// it is given and answers with an empty byte stream. WI-M2-14 defines the real `CloudTransport` protocol; this
/// double has the same shape (a `CloudRequest` in, byte chunks out).
final class PayloadRecordingTransport: Sendable {
    private let recorded = Mutex<[CloudRequest]>([])

    var requests: [CloudRequest] { recorded.withLock { $0 } }

    func send(_ request: CloudRequest) -> AsyncThrowingStream<[UInt8], any Error> {
        recorded.withLock { $0.append(request) }
        return AsyncThrowingStream { $0.finish() }
    }

    /// Sends one request and returns what the transport captured.
    static func capture(_ request: CloudRequest) -> CloudRequest? {
        let transport = PayloadRecordingTransport()
        _ = transport.send(request)
        return transport.requests.first
    }
}

/// A cloud model for the wiring tests: builds the payload with the builder from the request the pipeline gives it, and
/// sends it through the recording transport (the shape WI-M2-M6's adapters will have).
struct PayloadBuildingCloudModel: IngestionModel {
    let provider: CloudProvider
    let key: APIKey
    let transport: PayloadRecordingTransport

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let built = try? CloudPayloadBuilder.request(CloudPayloadInput(request),
                                                     model: CloudModel.defaultModel(for: provider), key: key)
        if let built { _ = transport.send(built) }
        return AsyncThrowingStream { $0.finish() }
    }
}

final class PayloadBuildingCloudModels: CloudModelSource, CloudCaptureReceipt {
    let transport = PayloadRecordingTransport()
    func receive() -> any CloudCaptureReceipt { self }
    func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
        PayloadBuildingCloudModel(provider: provider, key: key, transport: transport)
    }
}

enum PayloadText {
    /// The head file text: `METHOD host path[?query]`, then `Name: value` per header, each line ending in `\n`.
    static func head(_ request: CloudRequest) -> String {
        var line = request.method + " " + request.host + " " + request.path
        if !request.queryItems.isEmpty {
            line += "?" + request.queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&")
        }
        var text = line + "\n"
        for header in request.headers {
            text += header.name + ": " + header.withValue { $0 } + "\n"
        }
        return text
    }

    static func string(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
}

/// Independent oracles (they use `JSONSerialization`, not the production JSON reader or writer).
enum PayloadOracle {
    /// The leaf key paths of a JSON text in the results-file form (`$`, then `.name` or `[]`): the path of every
    /// scalar and of every empty array or object, sorted by UTF-8 bytes and unique.
    static func leafPaths(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var paths: Set<String> = []
        func walk(_ value: Any, _ path: String) {
            if let object = value as? [String: Any] {
                if object.isEmpty { paths.insert(path) }
                for (key, member) in object { walk(member, path + "." + key) }
            } else if let array = value as? [Any] {
                if array.isEmpty { paths.insert(path) }
                for element in array { walk(element, path + "[]") }
            } else {
                paths.insert(path)
            }
        }
        walk(root, "$")
        return paths.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    }

    /// The parsed value at a concrete path such as `$.messages[1].content[0].text`.
    static func value(_ data: Data, at concretePath: String) -> Any? {
        guard var current = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var rest = Substring(concretePath.dropFirst())  // drop "$"
        while !rest.isEmpty {
            if rest.hasPrefix(".") {
                rest = rest.dropFirst()
                let end = rest.firstIndex { $0 == "." || $0 == "[" } ?? rest.endIndex
                guard let object = current as? [String: Any], let member = object[String(rest[..<end])] else {
                    return nil
                }
                current = member
                rest = rest[end...]
            } else if rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]"), let index = Int(rest[rest.index(after: rest.startIndex)..<close]),
                      let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
                rest = rest[rest.index(after: close)...]
            } else {
                return nil
            }
        }
        return current
    }

    /// The three slots of a user content text, read with the exact shape checked: an object with exactly `capture`
    /// (a string), `rooms` (strings) and `existingTasks` (objects with exactly `index` = 1, 2, … and `title`).
    /// Nil if the shape differs in any way.
    static func slots(ofUserContent text: String) -> CloudPayloadInput? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              Set(object.keys) == ["capture", "rooms", "existingTasks"],
              let capture = object["capture"] as? String,
              let rooms = object["rooms"] as? [Any], let tasks = object["existingTasks"] as? [Any] else { return nil }
        var roomNames: [String] = []
        for room in rooms {
            guard let name = room as? String else { return nil }
            roomNames.append(name)
        }
        var titles: [String] = []
        for (offset, entry) in tasks.enumerated() {
            guard let task = entry as? [String: Any], Set(task.keys) == ["index", "title"],
                  let index = task["index"] as? Int, index == offset + 1,  // (on Linux an NSNumber integer also matches `is Bool`; the canonical re-encoding test pins the type)
                  let title = task["title"] as? String else { return nil }
            titles.append(title)
        }
        return CloudPayloadInput(capture: capture, roomNames: roomNames, shortlistTitles: titles)
    }

    /// Where each provider puts the user content (one concrete path) and the fixed instructions.
    static func userContentPath(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "$.messages[1].content[0].text"
        case .anthropic: "$.messages[0].content[0].text"
        case .gemini: "$.contents[0].parts[0].text"
        }
    }

    static func instructionsPath(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "$.messages[0].content[0].text"
        case .anthropic: "$.system"
        case .gemini: "$.systemInstruction.parts[0].text"
        }
    }

    /// Every occurrence of `needle` in `haystack` (bytes).
    static func contains(_ haystack: Data, _ needle: String) -> Bool {
        let n = Array(needle.utf8), h = Array(haystack)
        guard !n.isEmpty, n.count <= h.count else { return false }
        for start in 0...(h.count - n.count) where h[start..<(start + n.count)].elementsEqual(n) { return true }
        return false
    }
}

/// A value expected at a concrete body path.
enum PayloadExpectedValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)

    func matches(_ value: Any?) -> Bool {
        switch self {
        case let .bool(expected): (value as? Bool) == expected && !(value is String)
        case let .int(expected): (value as? Int) == expected && !(value is String)
        case let .string(expected): (value as? String) == expected
        }
    }
}

/// How the expected schema writes a member that may be null.
enum PayloadNullStyle: Sendable {
    case anyOf
    case typeArray
}

/// One curated model's expected request, written by hand from PO WI-M2-10 ruling 7 ("FINAL model list" and "Exact fixed
/// request members per provider"), never read from production (review R28-F7). A model swap changes a row here, the
/// provider table and the regenerated goldens, and nothing else.
struct PayloadExpectedModel: Sendable, CustomTestStringConvertible {
    var model: CloudModel
    var id: String
    var provider: CloudProvider
    var isDefault: Bool
    var host: String
    var path: String
    var query: [CloudQueryItem]
    var headerNames: [String]
    var fixedHeaders: [String: String]
    var schemaPath: String
    var nullStyle: PayloadNullStyle
    /// Members that must hold exactly this value.
    var present: [(String, PayloadExpectedValue)]
    /// Members that must not exist.
    var absent: [String]

    var testDescription: String { id }

    static let all: [PayloadExpectedModel] = [
        PayloadExpectedModel(
            model: .openAIDefault, id: "gpt-6-luna", provider: .openAI, isDefault: true,
            host: "api.openai.com", path: "/v1/chat/completions", query: [],
            headerNames: ["Authorization", "Content-Type", "User-Agent", "Accept-Language"],
            fixedHeaders: ["Content-Type": "application/json", "User-Agent": "Tend", "Accept-Language": "en-US"],
            schemaPath: "$.response_format.json_schema.schema", nullStyle: .anyOf,
            present: [
                ("$.model", .string("gpt-6-luna")), ("$.stream", .bool(true)),
                ("$.stream_options.include_usage", .bool(true)), ("$.reasoning_effort", .string("none")),
                ("$.store", .bool(false)), ("$.max_completion_tokens", .int(4096)),
                ("$.response_format.type", .string("json_schema")),
                ("$.response_format.json_schema.strict", .bool(true)),
                ("$.response_format.json_schema.name", .string("tend_capture")),
            ],
            absent: ["$.temperature", "$.top_p", "$.user", "$.metadata", "$.safety_identifier", "$.tools",
                     "$.prompt_cache_key", "$.max_tokens"]),
        PayloadExpectedModel(
            model: .anthropicDefault, id: "claude-haiku-4-5-20251001", provider: .anthropic, isDefault: true,
            host: "api.anthropic.com", path: "/v1/messages", query: [],
            headerNames: ["x-api-key", "anthropic-version", "Content-Type", "User-Agent", "Accept-Language"],
            fixedHeaders: ["anthropic-version": "2023-06-01", "Content-Type": "application/json", "User-Agent": "Tend",
                           "Accept-Language": "en-US"],
            schemaPath: "$.tools[0].input_schema", nullStyle: .anyOf,
            present: [
                ("$.model", .string("claude-haiku-4-5-20251001")), ("$.stream", .bool(true)),
                ("$.temperature", .int(0)), ("$.max_tokens", .int(4096)),
                ("$.tool_choice.type", .string("tool")), ("$.tool_choice.name", .string("record_items")),
                ("$.tools[0].name", .string("record_items")),
            ],
            absent: ["$.thinking", "$.metadata", "$.top_p", "$.tools[1]"]),
        PayloadExpectedModel(
            model: .geminiDefault, id: "gemini-3.5-flash-lite", provider: .gemini, isDefault: true,
            host: "generativelanguage.googleapis.com",
            path: "/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent",
            query: [CloudQueryItem(name: "alt", value: "sse")],
            headerNames: ["x-goog-api-key", "Content-Type", "User-Agent", "Accept-Language"],
            fixedHeaders: ["Content-Type": "application/json", "User-Agent": "Tend", "Accept-Language": "en-US"],
            schemaPath: "$.generationConfig.responseJsonSchema", nullStyle: .typeArray,
            present: [
                ("$.generationConfig.thinkingConfig.thinkingLevel", .string("minimal")),
                ("$.generationConfig.maxOutputTokens", .int(4096)),
                ("$.generationConfig.responseMimeType", .string("application/json")),
            ],
            absent: ["$.generationConfig.temperature", "$.generationConfig.thinkingConfig.thinkingBudget",
                     "$.generationConfig.responseSchema", "$.model", "$.tools", "$.cachedContent",
                     "$.safetySettings"]),
    ]

    static func row(_ provider: CloudProvider) -> PayloadExpectedModel? {
        all.first { $0.provider == provider && $0.isDefault }
    }
}
