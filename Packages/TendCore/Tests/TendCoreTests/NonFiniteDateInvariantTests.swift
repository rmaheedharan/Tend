// AC-M2-02 clause (W2-F3, brief Q9, plan T-21; WI-M2-02): a task whose `windowStart` or `windowEnd` is not a finite
// point in time (NaN, +infinity, -infinity) breaks a model invariant, `TaskInvariantViolation.windowDateNotFinite`
// (named by the iOS Designer, M2 design.md addendum 2026-11-21). Construction throws it, and both M1 repositories
// reject such a task or file with a typed error, as in AC-M1-06.
// It also pins what Foundation's JSONEncoder / JSONDecoder do with non-finite dates on this platform.
// Requirements: FR-B1, FR-B2, UX-3 (a calm, typed failure; no overdue state); AC-M1-25 is extended, not edited.

import Foundation
import Testing
@testable import TendCore

/// Which window date is made non-finite.
enum WindowDateField: String, CaseIterable, Sendable {
    case windowStart
    case windowEnd
}

/// One non-finite value, as a `Double` and (for hand-written files) as the JSON text that tries to say it.
struct NonFiniteValue: Sendable, CustomTestStringConvertible {
    let name: String
    let value: Double

    var testDescription: String { name }

    static let all: [NonFiniteValue] = [
        NonFiniteValue(name: "NaN", value: .nan),
        NonFiniteValue(name: "+infinity", value: .infinity),
        NonFiniteValue(name: "-infinity", value: -.infinity),
    ]
}

/// One (field, value) pair: 2 x 3 = 6 cases.
struct NonFiniteDateCase: Sendable, CustomTestStringConvertible {
    let field: WindowDateField
    let value: NonFiniteValue

    var testDescription: String { "\(field.rawValue) = \(value.name)" }

    static let all: [NonFiniteDateCase] = WindowDateField.allCases.flatMap { field in
        NonFiniteValue.all.map { NonFiniteDateCase(field: field, value: $0) }
    }

    var date: Date { Date(timeIntervalSinceReferenceDate: value.value) }

    /// Builds the task through the public throwing initialiser, with only this field non-finite.
    func build() throws(TaskInvariantViolation) -> HouseholdTask {
        switch field {
        case .windowStart:
            try Fixtures.task(windowStart: date)
        case .windowEnd:
            try Fixtures.task(windowEnd: date)
        }
    }

    /// A valid task whose field is then set to the non-finite date through the module-internal setter. No public
    /// caller can do this; it stands in for a defect in engine code inside `TendCore` (defence in depth).
    func corruptedTask(id: UUID) throws -> HouseholdTask {
        var task = try Fixtures.task(id: id)
        switch field {
        case .windowStart: task.windowStart = date
        case .windowEnd: task.windowEnd = date
        }
        #expect(task.firstInvariantViolation() == .windowDateNotFinite)
        return task
    }
}

/// A hand-written JSON token that tries to put a non-finite number in a date field.
struct HandWrittenToken: Sendable, CustomTestStringConvertible {
    let text: String
    /// `true` if the token is a JSON string (the decoder sees a string, not a number).
    let isString: Bool

    var testDescription: String { text }

    static let all: [HandWrittenToken] = [
        // Bare tokens: not JSON numbers (JSON has no NaN or infinity literal).
        HandWrittenToken(text: "NaN", isString: false),
        HandWrittenToken(text: "nan", isString: false),
        HandWrittenToken(text: "Infinity", isString: false),
        HandWrittenToken(text: "-Infinity", isString: false),
        HandWrittenToken(text: "inf", isString: false),
        // Valid JSON numbers that overflow a Double (they would round to +/-infinity).
        HandWrittenToken(text: "1e309", isString: false),
        HandWrittenToken(text: "1e400", isString: false),
        HandWrittenToken(text: "-1e400", isString: false),
        // Strings: only a decoder with a `.convertFromString` non-conforming float strategy would read these.
        HandWrittenToken(text: "\"NaN\"", isString: true),
        HandWrittenToken(text: "\"Infinity\"", isString: true),
        HandWrittenToken(text: "\"-Infinity\"", isString: true),
    ]
}

struct HandWrittenFileCase: Sendable, CustomTestStringConvertible {
    let field: WindowDateField
    let token: HandWrittenToken

    var testDescription: String { "\(field.rawValue): \(token.text)" }

    static let all: [HandWrittenFileCase] = WindowDateField.allCases.flatMap { field in
        HandWrittenToken.all.map { HandWrittenFileCase(field: field, token: $0) }
    }
}

@Suite("Non-finite window dates (AC-M2-02 W2-F3 clause, Q9, T-21)")
struct NonFiniteDateInvariantTests {
    static let start = Fixtures.referenceDate
    static let placeholder = "__TEND_NONFINITE_PLACEHOLDER__"

    // MARK: Model (construction)

    @Test("AC-M2-02 (W2-F3): constructing a task with a non-finite windowStart or windowEnd throws windowDateNotFinite",
          arguments: NonFiniteDateCase.all)
    func constructionThrows(nonFinite: NonFiniteDateCase) {
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            try nonFinite.build()
        }
    }

    @Test("AC-M2-02 (W2-F3): both window dates non-finite throws windowDateNotFinite",
          arguments: NonFiniteValue.all, NonFiniteValue.all)
    func bothNonFinite(start: NonFiniteValue, end: NonFiniteValue) {
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            try Fixtures.task(windowStart: Date(timeIntervalSinceReferenceDate: start.value),
                              windowEnd: Date(timeIntervalSinceReferenceDate: end.value))
        }
    }

    @Test("AC-M2-02 (Q9 position): windowDateNotFinite sits after noAllowedWeekdays and before windowEndNotAfterStart")
    func casePosition() throws {
        let all = TaskInvariantViolation.allCases
        let index = try #require(all.firstIndex(of: .windowDateNotFinite))
        #expect(index == 2)
        #expect(all[index - 1] == .noAllowedWeekdays)
        #expect(all[index + 1] == .windowEndNotAfterStart)
    }

    @Test("AC-M2-02 (Q9 position): the finiteness check runs before the window-order check and after the weekday check",
          arguments: NonFiniteDateCase.all)
    func checkOrder(nonFinite: NonFiniteDateCase) {
        let date = nonFinite.date
        let start = nonFinite.field == .windowStart ? date : Self.start
        let end = nonFinite.field == .windowEnd ? date : Self.start
        // NaN makes `end > start` false, and -infinity end / +infinity start make it false too: without the earlier
        // check these would all report windowEndNotAfterStart.
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            try Fixtures.task(windowStart: start, windowEnd: end)
        }
        // Later invariants are reported only after the window is finite.
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            try Fixtures.task(kind: .oneOff, isCritical: true, isDeepClean: true, windowStart: start, windowEnd: end,
                              recurrenceIntervalDays: 3, state: .maintenance)
        }
        // Earlier invariants still come first.
        #expect(throws: TaskInvariantViolation.noAllowedDayparts) {
            try Fixtures.task(allowedDayparts: [], windowStart: start, windowEnd: end)
        }
        #expect(throws: TaskInvariantViolation.noAllowedWeekdays) {
            try Fixtures.task(allowedWeekdays: [], windowStart: start, windowEnd: end)
        }
    }

    @Test("AC-M2-02 (W2-F3 boundary): the most extreme finite dates are accepted")
    func extremeFiniteDatesAccepted() throws {
        let lowest = Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)
        let highest = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        let task = try Fixtures.task(windowStart: lowest, windowEnd: highest)
        #expect(task.windowStart == lowest && task.windowEnd == highest)
        _ = try Fixtures.task(windowStart: .distantPast, windowEnd: .distantFuture)
        _ = try Fixtures.task(windowStart: Self.start,
                              windowEnd: Date(timeIntervalSinceReferenceDate: Self.start.timeIntervalSinceReferenceDate
                                                  .nextUp))
        // A finite file round-trips through the repository's format (ADR-0004), extreme values included.
        let household = Household(tasks: [task], rooms: [])
        let decoded = try JSONFileHouseholdRepository.decode(try JSONFileHouseholdRepository.encode(household))
        #expect(decoded == household)
    }

    // MARK: Model (decode path)

    /// The JSON object of a valid task with `field` replaced by a string `text` (read only by a lenient decoder).
    static func taskObject(field: WindowDateField, string text: String) throws -> [String: Any] {
        var object = try Fixtures.jsonObject(try Fixtures.task())
        object[field.rawValue] = text
        return object
    }

    /// A decoder that maps the strings "+inf", "-inf" and "nan" to non-finite doubles. The repository never uses one;
    /// this reaches the model's own decode validation with a value strict JSON cannot carry.
    static func lenientDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    static func lenientString(_ value: NonFiniteValue) -> String {
        if value.value.isNaN { return "nan" }
        return value.value > 0 ? "+inf" : "-inf"
    }

    @Test("AC-M2-02 (W2-F3): a task or household that decodes to a non-finite window date throws windowDateNotFinite",
          arguments: NonFiniteDateCase.all)
    func decodeThrows(nonFinite: NonFiniteDateCase) throws {
        let object = try Self.taskObject(field: nonFinite.field, string: Self.lenientString(nonFinite.value))
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            _ = try Self.lenientDecoder().decode(HouseholdTask.self, from: data)
        }
        // The same through a whole household: the only way bytes become a `Household` for either repository.
        var household = try Fixtures.jsonObject(Household(tasks: [try Fixtures.task()], rooms: []))
        household["tasks"] = [object]
        let householdData = try JSONSerialization.data(withJSONObject: household)
        #expect(throws: TaskInvariantViolation.windowDateNotFinite) {
            _ = try Self.lenientDecoder().decode(Household.self, from: householdData)
        }
    }

    // MARK: Foundation JSON behaviour, pinned (Linux, Swift 6.2; ADR-0004 format)

    @Test("AC-M2-02 (W2-F3) pin: JSONEncoder with the repository's settings refuses a non-finite date (EncodingError.invalidValue)",
          arguments: NonFiniteDateCase.all)
    func encoderRefusesNonFiniteDate(nonFinite: NonFiniteDateCase) throws {
        let task = try nonFinite.corruptedTask(id: Fixtures.id(1))
        var caught: (any Error)?
        do {
            _ = try JSONFileHouseholdRepository.encode(Household(tasks: [task], rooms: []))
        } catch {
            caught = error
        }
        let error = try #require(caught, "the encoder wrote a non-finite date")
        guard case EncodingError.invalidValue(let value, _) = error else {
            Issue.record("expected EncodingError.invalidValue, got \(error)")
            return
        }
        let double = try #require(value as? Double)
        #expect(!double.isFinite)
    }

    @Test("AC-M2-02 (W2-F3) pin: JSONDecoder cannot read a hand-written non-finite date token (DecodingError)",
          arguments: HandWrittenToken.all)
    func decoderRefusesNonFiniteToken(token: HandWrittenToken) throws {
        struct DateBox: Decodable { var date: Date }
        let data = Data("{\"date\":\(token.text)}".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate  // as the repository decodes (ADR-0004)
        var caught: (any Error)?
        do {
            let box = try decoder.decode(DateBox.self, from: data)
            Issue.record("decoded \(token.text) to \(box.date.timeIntervalSinceReferenceDate)")
        } catch {
            caught = error
        }
        let error = try #require(caught)
        #expect(error is DecodingError, "\(token.text): \(error)")
        #if os(Linux)
        // Exact kinds observed on Linux (Swift 6.2.4, swift-corelibs/swift-foundation JSONDecoder).
        switch (error as? DecodingError, token.isString) {
        case (.dataCorrupted?, false), (.typeMismatch?, true):
            break
        default:
            Issue.record("\(token.text): unexpected error kind \(error)")
        }
        #endif
    }

    @Test("AC-M2-02 (W2-F3) pin: the largest finite JSON number reads back as a finite date; one step past it does not")
    func overflowBoundary() throws {
        struct DateBox: Decodable { var date: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let largest = try decoder.decode(DateBox.self, from: Data("{\"date\":1.7976931348623157e308}".utf8))
        #expect(largest.date.timeIntervalSinceReferenceDate == .greatestFiniteMagnitude)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DateBox.self, from: Data("{\"date\":1e309}".utf8))
        }
    }

    // MARK: JSON file repository

    /// The bytes of a valid saved household file with task 7's `field` replaced by the raw `token` text.
    static func handWrittenFile(_ bad: HandWrittenFileCase) throws -> Data {
        var root = try FileRepositoryLoadErrorTests.validFileObject()
        guard var tasks = root["tasks"] as? [[String: Any]], tasks.count > 7 else {
            throw Fixtures.FixtureError.notAnObject
        }
        tasks[7][bad.field.rawValue] = placeholder
        root["tasks"] = tasks
        let text = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        let quoted = "\"\(placeholder)\""
        #expect(text.components(separatedBy: quoted).count == 2, "placeholder must appear exactly once")
        return Data(text.replacingOccurrences(of: quoted, with: bad.token.text).utf8)
    }

    @Test("AC-M2-02 (W2-F3) / AC-M1-06: a hand-written file with a non-finite window date is rejected with a typed error and left unchanged",
          arguments: HandWrittenFileCase.all)
    func fileRepositoryRejectsHandWrittenFile(bad: HandWrittenFileCase) async throws {
        // Strict JSON cannot carry a non-finite number, so the file is not a readable household (pinned above). The
        // typed error is `unreadableFile`; nothing is returned, repaired or overwritten (AC-M1-06 harness).
        let bytes = try Self.handWrittenFile(bad)
        try await FileRepositoryLoadErrorTests().assertRejected(
            BadFileCase(name: "hand-written \(bad.testDescription)", expected: .unreadableFile) { bytes })
    }

    @Test("AC-M2-02 (W2-F3) pin: the file repository's strict decoder reads a string-spelled non-finite date as unreadableFile, never as a task",
          arguments: NonFiniteDateCase.all)
    func fileRepositoryStrictDecode(nonFinite: NonFiniteDateCase) throws {
        // The repository's decoder keeps the default `.throw` non-conforming float strategy (ADR-0004), so the
        // strings a lenient decoder would turn into NaN or infinity are a type mismatch here, not a task.
        #expect(throws: HouseholdStoreError.unreadableFile) {
            let object = try Self.taskObject(field: nonFinite.field, string: Self.lenientString(nonFinite.value))
            var root = try FileRepositoryLoadErrorTests.validFileObject()
            root["tasks"] = [object]
            _ = try JSONFileHouseholdRepository.decode(try JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test("AC-M2-02 (W2-F3) / AC-M1-07: the file repository refuses to save a task carrying a non-finite date and keeps the stored file",
          arguments: NonFiniteDateCase.all)
    func fileRepositoryRefusesToSave(nonFinite: NonFiniteDateCase) async throws {
        try await RepositoryHarness.withTemporaryDirectory { directory in
            let fileURL = directory.appendingPathComponent("household.json")
            let repository = try JSONFileHouseholdRepository(fileURL: fileURL)
            let householdA = try HouseholdGenerator.household(seed: 9_201, taskCount: 12)
            try await repository.save(householdA)
            let bytesA = try RepositoryHarness.bytes(at: fileURL)

            let corrupted = try nonFinite.corruptedTask(id: Fixtures.id(0x9201))
            var householdB = householdA
            householdB.tasks.append(corrupted)
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) { try await repository.save(householdB) }
            await #expect(throws: HouseholdStoreError.writeUnsuccessful) { try await repository.upsertTask(corrupted) }

            #expect(try RepositoryHarness.bytes(at: fileURL) == bytesA)
            #expect(try RepositoryHarness.entries(in: directory) == ["household.json"])
            #expect(try await JSONFileHouseholdRepository(fileURL: fileURL).load() == householdA)
        }
    }

    // MARK: In-memory repository

    @Test("AC-M2-02 (W2-F3): the in-memory repository rejects a task carrying a non-finite date with invalidTask(windowDateNotFinite) and keeps what it holds",
          arguments: NonFiniteDateCase.all)
    func inMemoryRepositoryRejects(nonFinite: NonFiniteDateCase) async throws {
        let repository = InMemoryHouseholdRepository()
        let householdA = try HouseholdGenerator.household(seed: 9_202, taskCount: 12)
        try await repository.save(householdA)

        let corrupted = try nonFinite.corruptedTask(id: Fixtures.id(0x9202))
        var householdB = householdA
        householdB.tasks.append(corrupted)
        await #expect(throws: HouseholdStoreError.invalidTask(.windowDateNotFinite)) {
            try await repository.save(householdB)
        }
        await #expect(throws: HouseholdStoreError.invalidTask(.windowDateNotFinite)) {
            try await repository.upsertTask(corrupted)
        }
        // Replacing an existing task in place with a corrupted copy is refused too.
        let existing = try #require(householdA.tasks.first)
        var corruptedExisting = try nonFinite.corruptedTask(id: existing.id)
        corruptedExisting.title = existing.title
        await #expect(throws: HouseholdStoreError.invalidTask(.windowDateNotFinite)) {
            try await repository.upsertTask(corruptedExisting)
        }
        #expect(try await repository.load() == householdA)
    }

    @Test("AC-M2-02 (W2-F3): the in-memory repository still accepts valid tasks after a rejection")
    func inMemoryRepositoryAcceptsValidAfterRejection() async throws {
        let repository = InMemoryHouseholdRepository()
        let corrupted = try NonFiniteDateCase(field: .windowEnd, value: NonFiniteValue.all[0])
            .corruptedTask(id: Fixtures.id(0x9203))
        await #expect(throws: HouseholdStoreError.invalidTask(.windowDateNotFinite)) {
            try await repository.upsertTask(corrupted)
        }
        #expect(try await repository.load() == Household(tasks: [], rooms: []))
        let valid = try Fixtures.task(id: Fixtures.id(0x9203))
        try await repository.upsertTask(valid)
        #expect(try await repository.load().tasks == [valid])
    }
}
