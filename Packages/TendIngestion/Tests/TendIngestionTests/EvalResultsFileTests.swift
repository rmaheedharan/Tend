// Reading, writing and rejecting the results file v1 (AC-M2-28 "Results file (format v1)", "The scorer rejects a file
// that does not conform"; plan "Scoring tool and command": exit 2 = not v1 or fixtures hash mismatch). AC-M2-14.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-15 results file v1: read, write, reject (AC-M2-28, AC-M2-14)")
struct EvalResultsFileTests {

    static func read(_ data: Data, expected: String = EvalSelfTest.selfTestHash) throws -> EvalResultsFileV1 {
        try EvalResultsFileV1.read(data, schema: try EvalSelfTest.schema(), fixtures: try EvalSelfTest.fixtures(),
                                   expectedFixturesSHA256: expected)
    }

    @Test("AC-M2-28: the hand-built self-test file, in canonical form, is read with every field")
    func readsSelfTest() throws {
        let file = try Self.read(try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot()))
        #expect(file.run.operatorName == "self-test (hand-built, WI-M2-15)")
        #expect(file.run.provider == nil && file.run.routePreference == .onDeviceFirst && file.run.prewarm)
        #expect(file.run.network == .init(kind: "offline", downMbps: 0, upMbps: 0, latencyMs: 0))
        #expect(file.coldStart == .init(inputID: "in01", ttfiMs: 2100))
        #expect(file.inputs.count == 8)
        let in01 = file.inputs[0]
        #expect(in01.drafts[0].duplicate == .ofExisting(taskKey: "t-ac"))
        #expect(in01.drafts[0].sourcePhrase == "The AC needs servicing")
        #expect(in01.drafts[1].room == .existing(roomKey: "kitchen"))
        #expect(in01.drafts[2].room == .proposed(name: "the Terrace"))
        #expect(in01.drafts[2].allowedDayparts == Daypart.defaultAllowed)
        #expect(in01.drafts[2].windowStart.text == "2026-11-23T14:00:00.000Z")
        #expect(file.inputs[2].retakeReason == "speaker misread the script")
        #expect(file.inputs[2].transcriber == .speechTranscriber)
        #expect(file.inputs[3].drafts[4].duplicate == .ofDraft(3))
        #expect(file.inputs[7].ttfiMs == nil && file.inputs[7].outcome == .noModel)
    }

    @Test("the committed canonical copy of the self-test file is exactly the canonical form of the pretty file")
    func canonicalCopyMatches() throws {
        let committed = try EvalSelfTest.selfTest("results-selftest-1.canonical.json")
        #expect(committed == (try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot())))
    }

    @Test("AC-M2-28: a file the harness builds through the public API round-trips byte for byte")
    func writerRoundTrip() throws {
        let file = try Self.read(try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot()))
        let bytes = try CanonicalJSONWriter.data(file.canonicalJSON)
        #expect(bytes == (try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot())))
        #expect(try Self.read(bytes) == file)
    }

    @Test("the harness record of a pipeline draft maps IDs to fixture keys and keeps every field")
    func draftRecordFromPipeline() throws {
        let fixtures = try EvalSelfTest.fixtures()
        let kitchen = try #require(fixtures.rooms.first { $0.key == "kitchen" })
        let pods = try #require(fixtures.tasks.first { $0.key == "t-pods" })
        let start = Date(timeIntervalSince1970: 1_795_341_600.25)
        let draft = IngestionDraft(
            draftID: 2, title: "Buy dish pods", kind: .restock, room: .existing(kitchen.id), effort: .low,
            isCritical: false, isDeepClean: false, isWeatherDependent: false, allowedDayparts: [.morning],
            allowedWeekdays: [.monday], windowStart: start, windowEnd: start.addingTimeInterval(3600),
            recurrenceIntervalDays: nil, sourcePhrase: "dish pods", duplicate: .ofExisting(pods.task.id)
        )
        let record = try DraftRecord(draft: draft, roomKeys: fixtures.roomKeys, taskKeys: fixtures.taskKeys)
        #expect(record.room == .existing(roomKey: "kitchen"))
        #expect(record.duplicate == .ofExisting(taskKey: "t-pods"))
        #expect(record.windowStart.text == "2026-11-22T10:00:00.250Z")
        #expect(record.sourcePhrase == "dish pods" && record.allowedWeekdays == [.monday])
        #expect(throws: DraftRecord.RecordError.roomWithoutKey(kitchen.id)) {
            try DraftRecord(draft: draft, roomKeys: [:], taskKeys: fixtures.taskKeys)
        }
        #expect(throws: DraftRecord.RecordError.taskWithoutKey(pods.task.id)) {
            try DraftRecord(draft: draft, roomKeys: fixtures.roomKeys, taskKeys: [:])
        }
    }

    @Test("the outcome and route spellings map from the pipeline's types")
    func spellings() {
        #expect(EvalRoute(.cloud(.openAI)) == .openai)
        #expect(EvalRoute(.cloud(.anthropic)) == .anthropic)
        #expect(EvalRoute(.cloud(.gemini)) == .gemini)
        #expect(EvalRoute(.onDevice) == .onDevice && EvalRoute(.none) == .none)
        #expect(EvalOutcome(.cancelled(route: .onDevice)) == .cancelled)
        #expect(EvalOutcome(.completed(route: .onDevice)) == .completed)
        #expect(EvalProvider.allCases.map(\.rawValue) == ["openai", "anthropic", "gemini"])
    }

    // MARK: - Rejections (exit 2)

    @Test("AC-M2-28 rejection: not JSON, not v1, not conforming, not canonical, fixtures hash mismatch")
    func headlineRejections() throws {
        let root = try EvalSelfTest.resultsRoot()
        #expect(throws: EvalRejection.notJSON(.unexpectedEnd)) { try Self.read(Data("{".utf8)) }
        #expect(throws: EvalRejection.notVersion1) {
            try Self.read(try EvalSelfTest.canonical(root.setting("/schemaVersion", to: .integer(2))))
        }
        #expect(throws: EvalRejection.notVersion1) {
            try Self.read(try EvalSelfTest.canonical(root.setting("/schemaVersion", to: nil)))
        }
        #expect(throws: EvalRejection.schemaIssues([EvalSchemaIssue(path: "/run", keyword: "required",
                                                                    detail: "missing member \"locale\"")])) {
            try Self.read(try EvalSelfTest.canonical(root.setting("/run/locale", to: nil)))
        }
        // The file never holds a body, header value or key: an extra member is refused (additionalProperties).
        let withBody = root.setting("/inputs/0/cloudRequests/0", to: .object([
            .init("attempt", .integer(1)), .init("bytes", .integer(3)), .init("keyPaths", .array([])),
            .init("body", .string("{}")),
        ]))
        do {
            _ = try Self.read(try EvalSelfTest.canonical(withBody))
            Issue.record("a request body was accepted")
        } catch let EvalRejection.schemaIssues(issues) {
            #expect(issues.contains { $0.keyword == "additionalProperties" && $0.path == "/inputs/0/cloudRequests/0/body" })
        }
        #expect(throws: EvalRejection.notCanonical) { try Self.read(try EvalSelfTest.prettyResults()) }
        let canonical = try EvalSelfTest.canonical(root)
        #expect(throws: EvalRejection.notCanonical) { try Self.read(canonical + Data("\n".utf8)) }
        let other = String(repeating: "b", count: 64)
        #expect(throws: EvalRejection.fixturesHashMismatch(expected: other, found: EvalSelfTest.selfTestHash)) {
            try Self.read(canonical, expected: other)
        }
    }

    static let firstAttempt = "/inputs/0"

    /// (name, edits, expected rejection). Each edit breaks exactly one cross-field rule of `EvalInconsistency`.
    static let consistencyCases: [(String, [(String, EvalJSON?)], EvalInconsistency)] = [
        ("unknown input", [("/inputs/0/inputID", .string("in99"))], .unknownInput(inputID: "in99")),
        ("mode differs from the fixture", [("/inputs/0/mode", .string("voice"))],
         .modeDiffersFromFixture(inputID: "in01", attempt: 1)),
        ("attempts not consecutive", [("/inputs/2/attempt", .integer(3))], .attemptsNotConsecutive(inputID: "in02")),
        ("second attempt of a text input", [("/inputs/8", .null)], .tooManyAttempts(inputID: "in01")),
        ("retake without a reason", [("/inputs/2/retakeReason", .null)],
         .retakeReasonMismatch(inputID: "in02", attempt: 2)),
        ("first attempt with a reason", [("/inputs/1/retakeReason", .string("x"))],
         .retakeReasonMismatch(inputID: "in02", attempt: 1)),
        ("transcript on a text input", [("/inputs/0/transcript", .string("x"))],
         .transcriptMismatch(inputID: "in01", attempt: 1)),
        ("voice input without a transcriber", [("/inputs/6/transcriber", .null)],
         .transcriptMismatch(inputID: "in06", attempt: 1)),
        ("draft ID repeated", [("/inputs/4/drafts/1/draftID", .integer(1))],
         .draftIDRepeated(inputID: "in04", attempt: 1, draftID: 1)),
        ("updated before emitted", [("/inputs/4/events/1/type", .string("updated"))],
         .eventsInconsistent(inputID: "in04", attempt: 1)),
        ("finished not last", [("/inputs/4/events/2/type", .string("itemSkipped"))],
         .eventsInconsistent(inputID: "in04", attempt: 1)),
        ("emitted without a draft ID", [("/inputs/4/events/0/draftID", .null)],
         .eventsInconsistent(inputID: "in04", attempt: 1)),
        ("a recorded draft that was never emitted", [("/inputs/4/events/1", nil)],
         .eventsInconsistent(inputID: "in04", attempt: 1)),
        ("ttfiMs is not the first emitted time", [("/inputs/4/ttfiMs", .integer(301))],
         .timingsInconsistent(inputID: "in04", attempt: 1)),
        ("totalMs is not the finished time", [("/inputs/4/totalMs", .integer(1))],
         .timingsInconsistent(inputID: "in04", attempt: 1)),
        ("event times decrease", [("/inputs/4/events/1/tMs", .integer(10))],
         .timingsInconsistent(inputID: "in04", attempt: 1)),
        ("noModel with drafts", [("/inputs/4/outcome", .string("noModel"))],
         .outcomeInconsistent(inputID: "in04", attempt: 1)),
        ("interrupted with no draft", [("/inputs/7/outcome", .string("interrupted"))],
         .outcomeInconsistent(inputID: "in07", attempt: 1)),
        ("unknown room key", [("/inputs/0/drafts/1/room/roomKey", .string("attic"))],
         .unknownReference(inputID: "in01", attempt: 1, draftID: 2)),
        ("unknown task key", [("/inputs/0/drafts/0/duplicate/taskKey", .string("t-none"))],
         .unknownReference(inputID: "in01", attempt: 1, draftID: 1)),
        ("ofDraft names itself", [("/inputs/3/drafts/4/duplicate/draftID", .integer(5))],
         .unknownReference(inputID: "in03", attempt: 1, draftID: 5)),
        ("ofDraft names a later draft", [("/inputs/3/drafts/2/duplicate", .object([
            .init("type", .string("ofDraft")), .init("draftID", .integer(4))])), ("/inputs/3/committed", .array([
            .integer(1), .integer(2), .integer(4)]))],
         .unknownReference(inputID: "in03", attempt: 1, draftID: 3)),
        ("a window date that is not real", [("/inputs/0/drafts/0/windowStart", .string("2026-13-01T00:00:00.000Z"))],
         .invalidDate(inputID: "in01", attempt: 1, draftID: 1)),
        ("a marked draft committed", [("/inputs/0/committed", .array([.integer(1), .integer(3)]))],
         .committedMismatch(inputID: "in01", attempt: 1)),
        ("an unmarked draft not committed", [("/inputs/0/committed", .array([]))],
         .committedMismatch(inputID: "in01", attempt: 1)),
        ("a cancelled capture with commits", [("/inputs/4/outcome", .string("cancelled"))],
         .committedMismatch(inputID: "in04", attempt: 1)),
        ("a cloud request on the on-device route", [("/inputs/0/cloudRequests/0", .object([
            .init("attempt", .integer(1)), .init("bytes", .integer(3)), .init("keyPaths", .array([]))]))],
         .cloudRequestsInconsistent(inputID: "in01", attempt: 1)),
        ("key paths not sorted", [("/inputs/0/route", .string("openai")), ("/inputs/0/cloudRequests/0", .object([
            .init("attempt", .integer(1)), .init("bytes", .integer(3)),
            .init("keyPaths", .array([.string("$.b"), .string("$.a")]))]))],
         .cloudRequestsInconsistent(inputID: "in01", attempt: 1)),
        ("request attempts not numbered 1, 2", [("/inputs/0/route", .string("openai")), ("/inputs/0/cloudRequests/0",
            .object([.init("attempt", .integer(2)), .init("bytes", .integer(3)), .init("keyPaths", .array([]))]))],
         .cloudRequestsInconsistent(inputID: "in01", attempt: 1)),
        ("start time not real", [("/run/startedAtUTC", .string("2026-02-30T00:00:00Z"))], .invalidStartTime),
        ("cold start names an unknown input", [("/coldStart/inputID", .string("in99"))], .unknownColdStartInput),
    ]

    @Test("AC-M2-28 rejection: each cross-field rule (one wrong file per rule)", arguments: consistencyCases.indices)
    func consistency(index: Int) throws {
        let (name, edits, expected) = Self.consistencyCases[index]
        var root = try EvalSelfTest.resultsRoot()
        for (pointer, value) in edits {
            if pointer == "/inputs/8" {
                // Append a second attempt of the text input in01.
                let copy = try #require(root.value(at: "/inputs/0")).setting("/attempt", to: .integer(2))
                    .setting("/retakeReason", to: .string("again"))
                root = root.setting(pointer, to: copy)
            } else {
                root = root.setting(pointer, to: value)
            }
        }
        #expect(throws: EvalRejection.inconsistent(expected), "\(name)") {
            try Self.read(try EvalSelfTest.canonical(root))
        }
    }

    @Test("the unedited self-test file passes every cross-field rule")
    func baselineConsistent() throws {
        _ = try Self.read(try EvalSelfTest.canonical(try EvalSelfTest.resultsRoot()))
    }
}
