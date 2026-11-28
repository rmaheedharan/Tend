// The eval results file, format v1 (AC-M2-28 "Results file (format v1)"; plan "Named files": `EvalResultsFileV1`,
// "the results-file type, defined in `TendIngestion` next to the scorer"). FR-A1, P-4, AC-M2-14, 15, 16, 17, 26, 27.
//
// The JSON shape is `Fixtures/M2/eval/results-v1.schema.json`. The harness (`TendEval`, WI-M2-M7) builds this value
// through the public API and writes `CanonicalJSONWriter.data(file.canonicalJSON)`; the scorer reads it with
// `EvalResultsFileV1.read(_:schema:)`. The file never holds audio, a request or response body, header values or a key
// (AC-M2-28): there is no field for any of them, and `additionalProperties: false` refuses one if it is added.
//
// Field choices that the brief leaves to the Developer (dev-notes WI-M2-15, decisions E1–E6):
// - all numbers are integers (the canonical writer has no floating point): times in whole milliseconds, network speeds
//   in whole Mbit/s;
// - window dates are `EvalInstant` text (UTC, milliseconds);
// - room and task IDs are written as the fixture keys (AC-M2-28); `room` and `duplicate` are tagged objects.

import Foundation
import TendCore

public struct EvalResultsFileV1: Sendable, Hashable {

    public static let schemaVersion = 1

    public var run: Run
    /// The cold-start TTFI of input 1 (AC-M2-16, information only). Nil for a run that has none (the cloud runs).
    public var coldStart: ColdStart?
    /// One entry per attempt, in the order they were run.
    public var inputs: [InputAttempt]

    public init(run: Run, coldStart: ColdStart?, inputs: [InputAttempt]) {
        self.run = run
        self.coldStart = coldStart
        self.inputs = inputs
    }

    public struct Run: Sendable, Hashable {
        public var operatorName: String
        /// `yyyy-MM-ddTHH:mm:ssZ`.
        public var startedAtUTC: String
        public var deviceModel: String
        public var iOSBuild: String
        public var appCommitSHA: String
        public var fixturesSHA256: String
        public var locale: String
        public var routePreference: EvalRoutePreference
        public var provider: EvalProvider?
        public var modelID: String
        public var sampling: String
        public var prewarm: Bool
        public var network: Network

        public init(
            operatorName: String, startedAtUTC: String, deviceModel: String, iOSBuild: String, appCommitSHA: String,
            fixturesSHA256: String, locale: String, routePreference: EvalRoutePreference, provider: EvalProvider?,
            modelID: String, sampling: String, prewarm: Bool, network: Network
        ) {
            self.operatorName = operatorName
            self.startedAtUTC = startedAtUTC
            self.deviceModel = deviceModel
            self.iOSBuild = iOSBuild
            self.appCommitSHA = appCommitSHA
            self.fixturesSHA256 = fixturesSHA256
            self.locale = locale
            self.routePreference = routePreference
            self.provider = provider
            self.modelID = modelID
            self.sampling = sampling
            self.prewarm = prewarm
            self.network = network
        }
    }

    /// Entered by the owner (AC-M2-28; Q15 speed test).
    public struct Network: Sendable, Hashable {
        public var kind: String
        public var downMbps: Int
        public var upMbps: Int
        public var latencyMs: Int

        public init(kind: String, downMbps: Int, upMbps: Int, latencyMs: Int) {
            self.kind = kind
            self.downMbps = downMbps
            self.upMbps = upMbps
            self.latencyMs = latencyMs
        }
    }

    public struct ColdStart: Sendable, Hashable {
        public var inputID: String
        public var ttfiMs: Int?

        public init(inputID: String, ttfiMs: Int?) {
            self.inputID = inputID
            self.ttfiMs = ttfiMs
        }
    }

    public struct InputAttempt: Sendable, Hashable {
        public var inputID: String
        public var mode: EvalInputMode
        public var attempt: Int
        public var retakeReason: String?
        /// Voice only: the transcript of the scripted eval utterance.
        public var transcript: String?
        public var transcriber: EvalTranscriber?
        public var route: EvalRoute
        public var outcome: EvalOutcome
        /// Nil when no draft was emitted.
        public var ttfiMs: Int?
        public var totalMs: Int
        public var events: [Event]
        /// The final state of every emitted draft.
        public var drafts: [DraftRecord]
        /// The draft IDs handed to commit: every draft the pipeline did not mark as a duplicate (AC-M2-17).
        public var committed: [Int]
        public var cloudRequests: [CloudRequestRecord]

        public init(
            inputID: String, mode: EvalInputMode, attempt: Int, retakeReason: String?, transcript: String?,
            transcriber: EvalTranscriber?, route: EvalRoute, outcome: EvalOutcome, ttfiMs: Int?, totalMs: Int,
            events: [Event], drafts: [DraftRecord], committed: [Int], cloudRequests: [CloudRequestRecord]
        ) {
            self.inputID = inputID
            self.mode = mode
            self.attempt = attempt
            self.retakeReason = retakeReason
            self.transcript = transcript
            self.transcriber = transcriber
            self.route = route
            self.outcome = outcome
            self.ttfiMs = ttfiMs
            self.totalMs = totalMs
            self.events = events
            self.drafts = drafts
            self.committed = committed
            self.cloudRequests = cloudRequests
        }
    }

    public struct Event: Sendable, Hashable {
        public var type: EvalEventType
        public var draftID: Int?
        public var tMs: Int

        public init(type: EvalEventType, draftID: Int?, tMs: Int) {
            self.type = type
            self.draftID = draftID
            self.tMs = tMs
        }
    }

    /// Per cloud request attempt: the byte count, the JSON key paths and the per-array element counts, never a value
    /// (AC-M2-26, AC-M2-28; PO ruling on per-array element counts, 2026-11-27, D-059).
    public struct CloudRequestRecord: Sendable, Hashable {
        public var attempt: Int
        public var bytes: Int
        /// Sorted by UTF-8 bytes and unique. Array indices are written as `[]`.
        public var keyPaths: [String]
        /// Every array in the sent body with its element count (`CloudRequestKeyPaths.arrayCounts(ofBody:)`); nil only
        /// when the body is not strict JSON.
        public var arrayCounts: [ArrayCount]?
        /// Every array in the parsed user content, paths from its root (`$.rooms`, `$.existingTasks`); nil only when
        /// the body is not strict JSON, the user-content path is missing, or its string is not a strict JSON object.
        public var userContentArrayCounts: [ArrayCount]?

        public init(attempt: Int, bytes: Int, keyPaths: [String], arrayCounts: [ArrayCount]?,
                    userContentArrayCounts: [ArrayCount]?) {
            self.attempt = attempt
            self.bytes = bytes
            self.keyPaths = keyPaths
            self.arrayCounts = arrayCounts
            self.userContentArrayCounts = userContentArrayCounts
        }
    }
}

// MARK: - Enumerations (JSON spellings)

public enum EvalRoutePreference: String, Sendable, Hashable, CaseIterable {
    case onDeviceFirst
    case alwaysCloud
}

/// The provider names as the results file and its file name write them (AC-M2-28).
public enum EvalProvider: String, Sendable, Hashable, CaseIterable {
    case openai
    case anthropic
    case gemini

    public init(_ provider: CloudProvider) {
        switch provider {
        case .openAI: self = .openai
        case .anthropic: self = .anthropic
        case .gemini: self = .gemini
        }
    }
}

public enum EvalInputMode: String, Sendable, Hashable, CaseIterable {
    case text
    case voice
}

public enum EvalTranscriber: String, Sendable, Hashable, CaseIterable {
    case speechTranscriber = "SpeechTranscriber"
    case dictationTranscriber = "DictationTranscriber"
}

/// The route (brief Definitions, "Route"), with the provider written by name.
public enum EvalRoute: String, Sendable, Hashable, CaseIterable {
    case onDevice
    case openai
    case anthropic
    case gemini
    case none

    public init(_ route: Route) {
        switch route {
        case .onDevice: self = .onDevice
        case let .cloud(provider): self = EvalRoute(rawValue: EvalProvider(provider).rawValue) ?? .none
        case .none: self = .none
        }
    }

    public var provider: EvalProvider? { EvalProvider(rawValue: rawValue) }
}

/// The four outcomes (brief Definitions, "Draft stream events").
public enum EvalOutcome: String, Sendable, Hashable, CaseIterable {
    case completed
    case interrupted
    case noModel
    case cancelled

    public init(_ outcome: DraftStreamOutcome) {
        switch outcome {
        case .completed: self = .completed
        case .interrupted: self = .interrupted
        case .noModel: self = .noModel
        case .cancelled: self = .cancelled
        }
    }
}

public enum EvalEventType: String, Sendable, Hashable, CaseIterable {
    case emitted
    case updated
    case itemSkipped
    case finished
}

// MARK: - Draft record

/// A draft's final state, every field of the draft field set (brief Definitions, "Draft"), with IDs as fixture keys.
public struct DraftRecord: Sendable, Hashable {
    public enum RoomRecord: Sendable, Hashable {
        case existing(roomKey: String)
        case proposed(name: String)
        case none
    }

    public enum DuplicateRecord: Sendable, Hashable {
        case none
        case ofExisting(taskKey: String)
        case ofDraft(Int)

        public var isMarked: Bool { self != .none }
    }

    public var draftID: Int
    public var title: String
    public var kind: TaskKind
    public var room: RoomRecord
    public var effort: Effort
    public var isCritical: Bool
    public var isDeepClean: Bool
    public var isWeatherDependent: Bool
    public var allowedDayparts: Set<Daypart>
    public var allowedWeekdays: Set<Weekday>
    public var windowStart: EvalInstant
    public var windowEnd: EvalInstant
    public var recurrenceIntervalDays: Int?
    public var sourcePhrase: String?
    public var duplicate: DuplicateRecord

    public init(
        draftID: Int, title: String, kind: TaskKind, room: RoomRecord, effort: Effort, isCritical: Bool,
        isDeepClean: Bool, isWeatherDependent: Bool, allowedDayparts: Set<Daypart>, allowedWeekdays: Set<Weekday>,
        windowStart: EvalInstant, windowEnd: EvalInstant, recurrenceIntervalDays: Int?, sourcePhrase: String?,
        duplicate: DuplicateRecord
    ) {
        self.draftID = draftID
        self.title = title
        self.kind = kind
        self.room = room
        self.effort = effort
        self.isCritical = isCritical
        self.isDeepClean = isDeepClean
        self.isWeatherDependent = isWeatherDependent
        self.allowedDayparts = allowedDayparts
        self.allowedWeekdays = allowedWeekdays
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.sourcePhrase = sourcePhrase
        self.duplicate = duplicate
    }

    /// Why a pipeline draft cannot be recorded with fixture keys.
    public enum RecordError: Error, Sendable, Hashable {
        case roomWithoutKey(UUID)
        case taskWithoutKey(UUID)
        case windowDateNotRecordable
    }

    /// The record of a pipeline draft, for the harness. `roomKeys` and `taskKeys` map the seeded fixture IDs to their
    /// keys; a draft from a fresh copy of the seeded household names only those (AC-M2-28).
    public init(
        draft: IngestionDraft, roomKeys: [UUID: String], taskKeys: [UUID: String]
    ) throws(RecordError) {
        let room: RoomRecord
        switch draft.room {
        case let .existing(id):
            guard let key = roomKeys[id] else { throw .roomWithoutKey(id) }
            room = .existing(roomKey: key)
        case let .proposed(name): room = .proposed(name: name)
        case .none: room = .none
        }
        let duplicate: DuplicateRecord
        switch draft.duplicate {
        case .none: duplicate = .none
        case let .ofExisting(id):
            guard let key = taskKeys[id] else { throw .taskWithoutKey(id) }
            duplicate = .ofExisting(taskKey: key)
        case let .ofDraft(k): duplicate = .ofDraft(k)
        }
        guard let start = EvalInstant(draft.windowStart), let end = EvalInstant(draft.windowEnd) else {
            throw .windowDateNotRecordable
        }
        self.init(
            draftID: draft.draftID, title: draft.title, kind: draft.kind, room: room, effort: draft.effort,
            isCritical: draft.isCritical, isDeepClean: draft.isDeepClean, isWeatherDependent: draft.isWeatherDependent,
            allowedDayparts: draft.allowedDayparts, allowedWeekdays: draft.allowedWeekdays, windowStart: start,
            windowEnd: end, recurrenceIntervalDays: draft.recurrenceIntervalDays, sourcePhrase: draft.sourcePhrase,
            duplicate: duplicate
        )
    }

    /// The first M1 invariant this draft breaks, or nil when it passes (brief "Validity": the M1 invariants,
    /// AC-M1-25). The check is the M1 initialiser itself, with a placeholder ID and no room (neither is an invariant).
    public var invariantViolation: TaskInvariantViolation? {
        do throws(TaskInvariantViolation) {
            _ = try HouseholdTask(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), title: title, kind: kind, roomID: nil,
                effort: effort, isCritical: isCritical, isDeepClean: isDeepClean, isWeatherDependent: isWeatherDependent,
                allowedDayparts: allowedDayparts, allowedWeekdays: allowedWeekdays, windowStart: windowStart.date,
                windowEnd: windowEnd.date, recurrenceIntervalDays: recurrenceIntervalDays
            )
            return nil
        } catch {
            return error
        }
    }
}

// MARK: - Writing (canonical JSON)

extension EvalResultsFileV1 {

    /// The file as canonical JSON. The harness writes `CanonicalJSONWriter.data(file.canonicalJSON)`.
    public var canonicalJSON: CanonicalJSON {
        .object([
            .init("schemaVersion", .integer(Self.schemaVersion)),
            .init("run", run.canonicalJSON),
            .init("coldStart", coldStart.map { .object([
                .init("inputID", .string($0.inputID)), .init("ttfiMs", Self.optional($0.ttfiMs)),
            ]) } ?? .null),
            .init("inputs", .array(inputs.map(\.canonicalJSON))),
        ])
    }

    /// `[{count, path}]` sorted by the UTF-8 bytes of the path, or `null`.
    static func counts(_ counts: [ArrayCount]?) -> CanonicalJSON {
        guard let counts else { return .null }
        return .array(counts.sorted { TextFolding.utf8Precedes($0.path, $1.path) }.map { entry in
            .object([.init("count", .integer(entry.count)), .init("path", .string(entry.path))])
        })
    }

    static func optional(_ value: Int?) -> CanonicalJSON { value.map { .integer($0) } ?? .null }
    static func optional(_ value: String?) -> CanonicalJSON { value.map { .string($0) } ?? .null }
}

extension EvalResultsFileV1.Run {
    var canonicalJSON: CanonicalJSON {
        .object([
            .init("operator", .string(operatorName)), .init("startedAtUTC", .string(startedAtUTC)),
            .init("deviceModel", .string(deviceModel)), .init("iOSBuild", .string(iOSBuild)),
            .init("appCommitSHA", .string(appCommitSHA)), .init("fixturesSHA256", .string(fixturesSHA256)),
            .init("locale", .string(locale)), .init("routePreference", .string(routePreference.rawValue)),
            .init("provider", EvalResultsFileV1.optional(provider?.rawValue)), .init("modelID", .string(modelID)),
            .init("sampling", .string(sampling)), .init("prewarm", .bool(prewarm)),
            .init("network", .object([
                .init("kind", .string(network.kind)), .init("downMbps", .integer(network.downMbps)),
                .init("upMbps", .integer(network.upMbps)), .init("latencyMs", .integer(network.latencyMs)),
            ])),
        ])
    }
}

extension EvalResultsFileV1.InputAttempt {
    var canonicalJSON: CanonicalJSON {
        .object([
            .init("inputID", .string(inputID)), .init("mode", .string(mode.rawValue)),
            .init("attempt", .integer(attempt)), .init("retakeReason", EvalResultsFileV1.optional(retakeReason)),
            .init("transcript", EvalResultsFileV1.optional(transcript)),
            .init("transcriber", EvalResultsFileV1.optional(transcriber?.rawValue)),
            .init("route", .string(route.rawValue)), .init("outcome", .string(outcome.rawValue)),
            .init("ttfiMs", EvalResultsFileV1.optional(ttfiMs)), .init("totalMs", .integer(totalMs)),
            .init("events", .array(events.map { event in
                .object([
                    .init("type", .string(event.type.rawValue)),
                    .init("draftID", EvalResultsFileV1.optional(event.draftID)), .init("tMs", .integer(event.tMs)),
                ])
            })),
            .init("drafts", .array(drafts.map(\.canonicalJSON))),
            .init("committed", .array(committed.map { .integer($0) })),
            .init("cloudRequests", .array(cloudRequests.map { request in
                .object([
                    .init("attempt", .integer(request.attempt)), .init("bytes", .integer(request.bytes)),
                    .init("keyPaths", .array(request.keyPaths.sorted(by: TextFolding.utf8Precedes).map { .string($0) })),
                    .init("arrayCounts", EvalResultsFileV1.counts(request.arrayCounts)),
                    .init("userContentArrayCounts", EvalResultsFileV1.counts(request.userContentArrayCounts)),
                ])
            })),
        ])
    }
}

extension DraftRecord {
    var canonicalJSON: CanonicalJSON {
        let roomJSON: CanonicalJSON
        switch room {
        case let .existing(key): roomJSON = .object([.init("type", .string("existing")), .init("roomKey", .string(key))])
        case let .proposed(name): roomJSON = .object([.init("type", .string("proposed")), .init("name", .string(name))])
        case .none: roomJSON = .object([.init("type", .string("none"))])
        }
        let duplicateJSON: CanonicalJSON
        switch duplicate {
        case .none: duplicateJSON = .object([.init("type", .string("none"))])
        case let .ofExisting(key):
            duplicateJSON = .object([.init("type", .string("ofExisting")), .init("taskKey", .string(key))])
        case let .ofDraft(k):
            duplicateJSON = .object([.init("type", .string("ofDraft")), .init("draftID", .integer(k))])
        }
        return .object([
            .init("draftID", .integer(draftID)), .init("title", .string(title)), .init("kind", .string(kind.rawValue)),
            .init("room", roomJSON), .init("effort", .string(effort.rawValue)),
            .init("isCritical", .bool(isCritical)), .init("isDeepClean", .bool(isDeepClean)),
            .init("isWeatherDependent", .bool(isWeatherDependent)),
            // Sets are written in case order, so the same draft always gives the same bytes.
            .init("allowedDayparts", .array(Daypart.allCases.filter(allowedDayparts.contains).map { .string($0.rawValue) })),
            .init("allowedWeekdays", .array(Weekday.allCases.filter(allowedWeekdays.contains).map { .string($0.rawValue) })),
            .init("windowStart", .string(windowStart.text)), .init("windowEnd", .string(windowEnd.text)),
            .init("recurrenceIntervalDays", EvalResultsFileV1.optional(recurrenceIntervalDays)),
            .init("sourcePhrase", EvalResultsFileV1.optional(sourcePhrase)),
            .init("duplicate", duplicateJSON),
        ])
    }
}
