// Test support for the on-device adapter (WI-M2-M2): scripted generations built from JSON prefixes, the way the
// framework's `PartiallyGenerated` values grow. No real model runs in these tests (the iOS Simulator has none, and a
// real model is not deterministic); the real session is exercised by the information-only probe in dev-notes.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

enum OnDeviceJSON {
    /// A `PartiallyGenerated` answer from a (possibly unfinished) JSON text.
    static func partial(_ json: String) throws -> OnDeviceOutput.PartiallyGenerated {
        try OnDeviceOutput.PartiallyGenerated(GeneratedContent(json: json))
    }

    /// One whole item in declaration order, as the model writes it.
    static func item(title: String, sourcePhrase: String = "", kind: String = "oneOff", room: String = "",
                     effort: String = "normal", time: String = #"{"anchor":"none"}"#, sameAsItem: Int? = nil,
                     sameAsExisting: String? = nil, critical: Bool = false, deepClean: Bool = false,
                     weather: Bool = false) -> String {
        var members = [
            #""title":\#(quoted(title))"#,
            #""sourcePhrase":\#(quoted(sourcePhrase))"#,
            #""kind":"\#(kind)""#,
            #""room":\#(quoted(room))"#,
            #""effort":"\#(effort)""#,
            #""time":\#(time)"#,
        ]
        if let sameAsItem { members.append(#""sameAsItem":\#(sameAsItem)"#) }
        if let sameAsExisting { members.append(#""sameAsExisting":\#(quoted(sameAsExisting))"#) }
        members += [#""isCritical":\#(critical)"#, #""isDeepClean":\#(deepClean)"#, #""isWeatherDependent":\#(weather)"#]
        return "{" + members.joined(separator: ",") + "}"
    }

    static func answer(_ items: [String]) -> String {
        #"{"items":["# + items.joined(separator: ",") + "]}"
    }

    static func quoted(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Every prefix of `json` in steps of `step` characters that the framework could show: the ones that parse as a
    /// `PartiallyGenerated` value (the framework never shows half an enum value, which does not parse). The whole text
    /// is always last.
    static func growingPartials(_ json: String, step: Int) -> [OnDeviceOutput.PartiallyGenerated] {
        var result: [OnDeviceOutput.PartiallyGenerated] = []
        var end = json.startIndex
        while end < json.endIndex {
            end = json.index(end, offsetBy: step, limitedBy: json.endIndex) ?? json.endIndex
            if let value = try? partial(String(json[..<end])) { result.append(value) }
        }
        return result
    }
}

/// One step of a scripted generation.
enum GenerationStep: Sendable {
    /// The model shows this answer so far.
    case answer(OnDeviceOutput.PartiallyGenerated)
    /// The model calls the duplicate Tool with this query (through the real Tool type).
    case lookup(String)
    /// The model stops with this error.
    case fail(any Error)
    /// The model waits until the stream is cancelled.
    case hang
}

/// Records what the scripted generations saw, across threads.
final class GenerationLog: Sendable {
    private let state = LockedBox(State())

    struct State {
        var prompts: [String] = []
        var terminated = 0
        var made: [Household] = []
        var prewarmed = 0
        var lookupResults: [OnDeviceLookupResult] = []
    }

    var snapshot: State { state.read { $0 } }
    func update(_ change: (inout State) -> Void) { state.write(change) }
}

/// A small lock-protected box for the test support only (Sources use actors).
final class LockedBox<Value>: @unchecked Sendable {
    // @unchecked Sendable: every access goes through `lock`. Test target only.
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read<T>(_ body: (Value) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(value) }
    func write(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&value) }
}

final class ScriptedGeneration: OnDeviceGeneration {
    let recorder: DuplicateLookupRecorder
    let steps: [GenerationStep]
    let log: GenerationLog
    let tool: DuplicateLookupTool

    init(household: Household, steps: [GenerationStep], log: GenerationLog) {
        let recorder = DuplicateLookupRecorder(household: household)
        self.recorder = recorder
        self.steps = steps
        self.log = log
        self.tool = DuplicateLookupTool(recorder: recorder)
        log.update { $0.made.append(household) }
    }

    func prewarm() { log.update { $0.prewarmed += 1 } }

    func answers(prompt: String) -> AsyncThrowingStream<OnDeviceOutput.PartiallyGenerated, any Error> {
        log.update { $0.prompts.append(prompt) }
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: OnDeviceOutput.PartiallyGenerated.self)
        let steps = steps
        let tool = tool
        let log = log
        let task = Task {
            for step in steps {
                switch step {
                case let .answer(value):
                    continuation.yield(value)
                case let .lookup(query):
                    let result = try await tool.call(arguments: .init(query: query))
                    log.update { $0.lookupResults.append(result) }
                case let .fail(error):
                    continuation.finish(throwing: error)
                    return
                case .hang:
                    while !Task.isCancelled { await Task.yield() }
                    return
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
            log.update { $0.terminated += 1 }
        }
        return stream
    }
}

enum OnDeviceFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    static func room(_ name: String, _ n: UInt8) -> Room {
        Room(id: uuid(n), name: name)
    }

    static func uuid(_ n: UInt8) -> UUID {
        UUID(uuid: (n, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    /// A model over a scripted generation for `household`.
    static func model(household: Household, steps: [GenerationStep],
                      log: GenerationLog = GenerationLog()) -> OnDeviceIngestionModel {
        OnDeviceIngestionModel(household: household, prepared: PreparedGenerations()) { household in
            ScriptedGeneration(household: household, steps: steps, log: log)
        }
    }

    /// Runs a capture through the real pipeline on the on-device route with the on-device duplicate rules.
    static func events(input: String, household: Household, model: some IngestionModel) async -> [DraftStreamEvent] {
        let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: now, calendar: calendar,
                                     timeZone: utc, duplicateCheck: DraftDuplicateRules.onDevice(household: household))
        var events: [DraftStreamEvent] = []
        for await event in pipeline.events(from: .onDevice(model)) { events.append(event) }
        return events
    }

    /// The snapshots a model's stream gives, and how it ended.
    static func snapshots(of model: some IngestionModel, input: String,
                          rooms: [String] = []) async -> (snapshots: [IngestionSnapshot], end: (any Error)?) {
        var result: [IngestionSnapshot] = []
        do {
            for try await snapshot in model.snapshots(for: IngestionRequest(input: input, roomNames: rooms)) {
                result.append(snapshot)
            }
            return (result, nil)
        } catch {
            return (result, error)
        }
    }
}

extension DraftStreamSummary {
    init(_ events: [DraftStreamEvent]) {
        self.init()
        for event in events { apply(event) }
    }
}
