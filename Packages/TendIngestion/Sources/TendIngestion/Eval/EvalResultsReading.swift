// Reading and rejecting a results file (AC-M2-28: "The scorer rejects a file that does not conform"; plan "Scoring
// tool and command": exit 2 = "file rejected (not v1, or the fixtures hash does not match)"). FR-A1, AC-M2-14.
//
// Order of checks (the first one that does not hold is the rejection):
// 1. the bytes are JSON (`EvalJSONReader`: integers only, no duplicate keys);
// 2. `schemaVersion` is 1 (so a later format is named as such, not as a list of schema issues);
// 3. the value conforms to `results-v1.schema.json` (`EvalSchemaCheck`);
// 4. the bytes are canonical JSON (AC-M2-28 "in canonical JSON (sorted keys)"): writing the parsed value with
//    `CanonicalJSONWriter` gives the same bytes;
// 5. `run.fixturesSHA256` equals the expected hash (the SHA-256 of the `MANIFEST.sha256` bytes);
// 6. the cross-field rules (`EvalInconsistency`), which a JSON Schema of this subset cannot say. Each one is a rule of
//    AC-M2-28, the device-run rules or the brief's Definitions; dev-notes WI-M2-15 lists them with their sources.

import Foundation
import TendCore

/// Why a results file is rejected (not scored).
public enum EvalRejection: Error, Sendable, Hashable {
    case notJSON(EvalJSONError)
    case notVersion1
    case schemaIssues([EvalSchemaIssue])
    case notCanonical
    case fixturesHashMismatch(expected: String, found: String)
    case inconsistent(EvalInconsistency)
}

/// A cross-field rule the file breaks. `inputID` and `attempt` say where.
public enum EvalInconsistency: Sendable, Hashable {
    /// `inputID` is not in `inputs.json`.
    case unknownInput(inputID: String)
    /// `mode` differs from the fixture's mode.
    case modeDiffersFromFixture(inputID: String, attempt: Int)
    /// The attempts of one input are not numbered 1, 2, … in file order.
    case attemptsNotConsecutive(inputID: String)
    /// Device-run rules: a text input has one attempt; a voice input has at most one retake.
    case tooManyAttempts(inputID: String)
    /// Device-run rules: a retake has a reason, and a first attempt has none.
    case retakeReasonMismatch(inputID: String, attempt: Int)
    /// AC-M2-28: `transcript` and `transcriber` are present exactly for voice inputs.
    case transcriptMismatch(inputID: String, attempt: Int)
    /// Draft IDs repeat within one attempt.
    case draftIDRepeated(inputID: String, attempt: Int, draftID: Int)
    /// Brief "Draft stream events": `emitted` exactly once per draft, `updated` only after it, `itemSkipped` and
    /// `finished` without a draft, `finished` exactly once and last; the recorded drafts are exactly the emitted ones.
    case eventsInconsistent(inputID: String, attempt: Int)
    /// Event times decrease, `ttfiMs` is not the first `emitted` time, or `totalMs` is not the `finished` time.
    case timingsInconsistent(inputID: String, attempt: Int)
    /// Brief outcome rules: `noModel` emits no draft; `interrupted` has at least one draft.
    case outcomeInconsistent(inputID: String, attempt: Int)
    /// A room key, task key or `ofDraft` target that does not exist (an `ofDraft(k)` needs an earlier draft k).
    case unknownReference(inputID: String, attempt: Int, draftID: Int)
    /// A window date that is not a real UTC instant.
    case invalidDate(inputID: String, attempt: Int, draftID: Int)
    /// AC-M2-17: `committed` is exactly the drafts not marked as duplicates.
    case committedMismatch(inputID: String, attempt: Int)
    /// AC-M2-28: key paths sorted by UTF-8 bytes; request attempts numbered 1, 2, …; no cloud request off the cloud.
    case cloudRequestsInconsistent(inputID: String, attempt: Int)
    /// `run.startedAtUTC` is not a real UTC instant.
    case invalidStartTime
    /// `coldStart.inputID` is not in `inputs.json`.
    case unknownColdStartInput
}

extension EvalResultsFileV1 {

    /// Reads, checks and rejects. Pure: bytes and fixtures in, a value or a typed rejection out (AC-M2-09 Rule 1).
    public static func read(
        _ data: Data, schema: EvalSchemaCheck, fixtures: EvalFixtures, expectedFixturesSHA256: String
    ) throws(EvalRejection) -> EvalResultsFileV1 {
        let root: EvalJSON
        do throws(EvalJSONError) { root = try EvalJSONReader.parse(data) } catch { throw .notJSON(error) }
        guard root["schemaVersion"] == .integer(schemaVersion) else { throw .notVersion1 }
        let issues = schema.issues(in: root)
        guard issues.isEmpty else { throw .schemaIssues(issues) }
        guard let canonical = try? CanonicalJSONWriter.data(root.canonical), canonical == data else {
            throw .notCanonical
        }
        let file = try ValueReader().file(root)
        guard file.run.fixturesSHA256 == expectedFixturesSHA256 else {
            throw .fixturesHashMismatch(expected: expectedFixturesSHA256, found: file.run.fixturesSHA256)
        }
        try file.checkConsistency(fixtures: fixtures)
        return file
    }

    /// The cross-field rules (see the type comment of `EvalInconsistency`).
    func checkConsistency(fixtures: EvalFixtures) throws(EvalRejection) {
        func fail(_ reason: EvalInconsistency) -> EvalRejection { .inconsistent(reason) }
        guard EvalInstant(text: run.startedAtUTC, milliseconds: false) != nil else { throw fail(.invalidStartTime) }
        if let coldStart, fixtures.input(coldStart.inputID) == nil { throw fail(.unknownColdStartInput) }
        let roomKeys = Set(fixtures.rooms.map(\.key))
        let taskKeys = Set(fixtures.tasks.map(\.key))
        var attemptsSeen: [String: Int] = [:]
        for entry in inputs {
            let id = entry.inputID
            let n = entry.attempt
            guard let fixture = fixtures.input(id) else { throw fail(.unknownInput(inputID: id)) }
            guard entry.mode == fixture.mode else { throw fail(.modeDiffersFromFixture(inputID: id, attempt: n)) }
            guard n == (attemptsSeen[id] ?? 0) + 1 else { throw fail(.attemptsNotConsecutive(inputID: id)) }
            attemptsSeen[id] = n
            guard n <= (entry.mode == .voice ? 2 : 1) else { throw fail(.tooManyAttempts(inputID: id)) }
            guard (n >= 2) == (entry.retakeReason != nil) else {
                throw fail(.retakeReasonMismatch(inputID: id, attempt: n))
            }
            let isVoice = entry.mode == .voice
            guard (entry.transcript != nil) == isVoice, (entry.transcriber != nil) == isVoice else {
                throw fail(.transcriptMismatch(inputID: id, attempt: n))
            }

            // Drafts: unique IDs, known references, real dates.
            var draftIDs: Set<Int> = []
            for draft in entry.drafts {
                guard draftIDs.insert(draft.draftID).inserted else {
                    throw fail(.draftIDRepeated(inputID: id, attempt: n, draftID: draft.draftID))
                }
            }
            for draft in entry.drafts {
                guard draft.windowStart != .invalidMarker, draft.windowEnd != .invalidMarker else {
                    throw fail(.invalidDate(inputID: id, attempt: n, draftID: draft.draftID))
                }
                if case let .existing(key) = draft.room, !roomKeys.contains(key) {
                    throw fail(.unknownReference(inputID: id, attempt: n, draftID: draft.draftID))
                }
                switch draft.duplicate {
                case let .ofExisting(key) where !taskKeys.contains(key):
                    throw fail(.unknownReference(inputID: id, attempt: n, draftID: draft.draftID))
                case let .ofDraft(k) where !(draftIDs.contains(k) && k < draft.draftID):
                    throw fail(.unknownReference(inputID: id, attempt: n, draftID: draft.draftID))
                default: break
                }
            }

            // Events (brief "Draft stream events").
            var emitted: [Int] = []
            var lastTime = 0
            for (index, event) in entry.events.enumerated() {
                let isLast = index == entry.events.count - 1
                switch event.type {
                case .emitted:
                    guard let d = event.draftID, !emitted.contains(d), !isLast else {
                        throw fail(.eventsInconsistent(inputID: id, attempt: n))
                    }
                    emitted.append(d)
                case .updated:
                    guard let d = event.draftID, emitted.contains(d), !isLast else {
                        throw fail(.eventsInconsistent(inputID: id, attempt: n))
                    }
                case .itemSkipped:
                    guard event.draftID == nil, !isLast else { throw fail(.eventsInconsistent(inputID: id, attempt: n)) }
                case .finished:
                    guard event.draftID == nil, isLast else { throw fail(.eventsInconsistent(inputID: id, attempt: n)) }
                }
                guard event.tMs >= lastTime else { throw fail(.timingsInconsistent(inputID: id, attempt: n)) }
                lastTime = event.tMs
            }
            guard Set(emitted) == draftIDs else { throw fail(.eventsInconsistent(inputID: id, attempt: n)) }
            let firstEmitted = entry.events.first { $0.type == .emitted }?.tMs
            guard entry.ttfiMs == firstEmitted, entry.totalMs == entry.events.last?.tMs else {
                throw fail(.timingsInconsistent(inputID: id, attempt: n))
            }

            // Outcomes.
            switch entry.outcome {
            case .noModel: guard entry.drafts.isEmpty else { throw fail(.outcomeInconsistent(inputID: id, attempt: n)) }
            case .interrupted:
                guard !entry.drafts.isEmpty else { throw fail(.outcomeInconsistent(inputID: id, attempt: n)) }
            case .completed, .cancelled: break
            }

            // Committed (AC-M2-17): every draft the pipeline did not mark, and nothing else. A cancelled capture
            // writes nothing (brief "cancelled: nothing is written").
            let unmarked = Set(entry.drafts.filter { !$0.duplicate.isMarked }.map(\.draftID))
            let expectedCommitted = entry.outcome == .cancelled ? [] : unmarked
            guard Set(entry.committed) == expectedCommitted else {
                throw fail(.committedMismatch(inputID: id, attempt: n))
            }

            // Cloud requests.
            if entry.route.provider == nil, !entry.cloudRequests.isEmpty {
                throw fail(.cloudRequestsInconsistent(inputID: id, attempt: n))
            }
            for (index, request) in entry.cloudRequests.enumerated() {
                let sorted = zip(request.keyPaths, request.keyPaths.dropFirst()).allSatisfy {
                    TextFolding.utf8Precedes($0, $1)
                }
                guard request.attempt == index + 1, sorted else {
                    throw fail(.cloudRequestsInconsistent(inputID: id, attempt: n))
                }
            }
        }
    }
}

/// Builds the model from a value that already conforms to the schema. A type it does not expect still gives a typed
/// rejection (never a crash), named as a schema issue at that path.
struct ValueReader {
    struct Unexpected: Error {}

    func file(_ root: EvalJSON) throws(EvalRejection) -> EvalResultsFileV1 {
        do throws(Unexpected) {
            let run = try object(root["run"])
            let network = try object(run["network"])
            let coldStart: EvalResultsFileV1.ColdStart?
            if let cold = root["coldStart"], cold != .null {
                coldStart = .init(inputID: try string(cold["inputID"]), ttfiMs: try optionalInt(cold["ttfiMs"]))
            } else {
                coldStart = nil
            }
            return EvalResultsFileV1(
                run: .init(
                    operatorName: try string(run["operator"]), startedAtUTC: try string(run["startedAtUTC"]),
                    deviceModel: try string(run["deviceModel"]), iOSBuild: try string(run["iOSBuild"]),
                    appCommitSHA: try string(run["appCommitSHA"]), fixturesSHA256: try string(run["fixturesSHA256"]),
                    locale: try string(run["locale"]), routePreference: try enumValue(run["routePreference"]),
                    provider: try optionalEnum(run["provider"]), modelID: try string(run["modelID"]),
                    sampling: try string(run["sampling"]), prewarm: try bool(run["prewarm"]),
                    network: .init(
                        kind: try string(network["kind"]), downMbps: try int(network["downMbps"]),
                        upMbps: try int(network["upMbps"]), latencyMs: try int(network["latencyMs"])
                    )
                ),
                coldStart: coldStart,
                inputs: try array(root["inputs"]).map { (entry: EvalJSON) throws(Unexpected) in try attempt(entry) }
            )
        } catch {
            throw .schemaIssues([EvalSchemaIssue(path: "", keyword: "type", detail: "value not readable as v1")])
        }
    }

    func attempt(_ entry: EvalJSON) throws(Unexpected) -> EvalResultsFileV1.InputAttempt {
        var events: [EvalResultsFileV1.Event] = []
        for event in try array(entry["events"]) {
            events.append(.init(type: try enumValue(event["type"]), draftID: try optionalInt(event["draftID"]),
                                tMs: try int(event["tMs"])))
        }
        var drafts: [DraftRecord] = []
        for draft in try array(entry["drafts"]) { drafts.append(try self.draft(draft)) }
        var committed: [Int] = []
        for value in try array(entry["committed"]) { committed.append(try int(value)) }
        var requests: [EvalResultsFileV1.CloudRequestRecord] = []
        for request in try array(entry["cloudRequests"]) {
            var paths: [String] = []
            for path in try array(request["keyPaths"]) { paths.append(try string(path)) }
            requests.append(.init(attempt: try int(request["attempt"]), bytes: try int(request["bytes"]), keyPaths: paths))
        }
        return .init(
            inputID: try string(entry["inputID"]), mode: try enumValue(entry["mode"]), attempt: try int(entry["attempt"]),
            retakeReason: try optionalString(entry["retakeReason"]), transcript: try optionalString(entry["transcript"]),
            transcriber: try optionalEnum(entry["transcriber"]), route: try enumValue(entry["route"]),
            outcome: try enumValue(entry["outcome"]), ttfiMs: try optionalInt(entry["ttfiMs"]),
            totalMs: try int(entry["totalMs"]), events: events, drafts: drafts, committed: committed,
            cloudRequests: requests
        )
    }

    func draft(_ value: EvalJSON) throws(Unexpected) -> DraftRecord {
        let roomJSON = try object(value["room"])
        let room: DraftRecord.RoomRecord
        switch try string(roomJSON["type"]) {
        case "existing": room = .existing(roomKey: try string(roomJSON["roomKey"]))
        case "proposed": room = .proposed(name: try string(roomJSON["name"]))
        case "none": room = .none
        default: throw Unexpected()
        }
        let duplicateJSON = try object(value["duplicate"])
        let duplicate: DraftRecord.DuplicateRecord
        switch try string(duplicateJSON["type"]) {
        case "none": duplicate = .none
        case "ofExisting": duplicate = .ofExisting(taskKey: try string(duplicateJSON["taskKey"]))
        case "ofDraft": duplicate = .ofDraft(try int(duplicateJSON["draftID"]))
        default: throw Unexpected()
        }
        var dayparts: [Daypart] = []
        for part in try array(value["allowedDayparts"]) { dayparts.append(try enumValue(part)) }
        var weekdays: [Weekday] = []
        for day in try array(value["allowedWeekdays"]) { weekdays.append(try enumValue(day)) }
        // A pattern-conforming date that is not a real instant (month 13) is reported by the consistency check.
        let start = EvalInstant(text: try string(value["windowStart"])) ?? EvalInstant.invalidMarker
        let end = EvalInstant(text: try string(value["windowEnd"])) ?? EvalInstant.invalidMarker
        return DraftRecord(
            draftID: try int(value["draftID"]), title: try string(value["title"]), kind: try enumValue(value["kind"]),
            room: room, effort: try enumValue(value["effort"]), isCritical: try bool(value["isCritical"]),
            isDeepClean: try bool(value["isDeepClean"]), isWeatherDependent: try bool(value["isWeatherDependent"]),
            allowedDayparts: Set(dayparts), allowedWeekdays: Set(weekdays), windowStart: start, windowEnd: end,
            recurrenceIntervalDays: try optionalInt(value["recurrenceIntervalDays"]),
            sourcePhrase: try optionalString(value["sourcePhrase"]), duplicate: duplicate
        )
    }

    func object(_ value: EvalJSON?) throws(Unexpected) -> EvalJSON {
        guard case .object? = value, let value else { throw Unexpected() }
        return value
    }
    func array(_ value: EvalJSON?) throws(Unexpected) -> [EvalJSON] {
        guard case let .array(values)? = value else { throw Unexpected() }
        return values
    }
    func string(_ value: EvalJSON?) throws(Unexpected) -> String {
        guard case let .string(text)? = value else { throw Unexpected() }
        return text
    }
    func optionalString(_ value: EvalJSON?) throws(Unexpected) -> String? {
        if value == .null { return nil }
        return try string(value)
    }
    func int(_ value: EvalJSON?) throws(Unexpected) -> Int {
        guard case let .integer(number)? = value else { throw Unexpected() }
        return number
    }
    func optionalInt(_ value: EvalJSON?) throws(Unexpected) -> Int? {
        if value == .null { return nil }
        return try int(value)
    }
    func bool(_ value: EvalJSON?) throws(Unexpected) -> Bool {
        guard case let .bool(flag)? = value else { throw Unexpected() }
        return flag
    }
    func enumValue<E: RawRepresentable>(_ value: EvalJSON?) throws(Unexpected) -> E where E.RawValue == String {
        guard let parsed = E(rawValue: try string(value)) else { throw Unexpected() }
        return parsed
    }
    func optionalEnum<E: RawRepresentable>(_ value: EvalJSON?) throws(Unexpected) -> E? where E.RawValue == String {
        if value == .null { return nil }
        return try enumValue(value) as E
    }
}

extension EvalInstant {
    /// Stands for a window date that matched the pattern but is not a real instant; the consistency check rejects any
    /// draft that holds it (`EvalInconsistency.invalidDate`).
    static let invalidMarker = EvalInstant(millisecondsSince1970: Int64.min)
}
