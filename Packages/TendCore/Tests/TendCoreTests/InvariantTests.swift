// AC-M1-25: each model invariant is enforced at construction (typed throw) and on JSON decode.
// The repository wrapping of the decode error (`HouseholdStoreError.invalidTask`) is WI-M1-02.
// Requirements: FR-B1, FR-B2, UX-3; brief Q15 (degenerate inputs are rejected, never silently repaired).

import Foundation
import Testing
import TendCore

/// One invariant case: a builder that violates it, the expected typed error, and the JSON fields that, transplanted
/// into an otherwise valid encoded task, produce the same violation on decode.
struct InvariantCase: Sendable, CustomTestStringConvertible {
    let violation: TaskInvariantViolation
    let build: @Sendable () throws(TaskInvariantViolation) -> HouseholdTask

    var testDescription: String { "\(violation)" }
}

@Suite("Model invariants (AC-M1-25)")
struct InvariantTests {
    static let start = Fixtures.referenceDate

    static let cases: [InvariantCase] = [
        InvariantCase(violation: .noAllowedDayparts) { () throws(TaskInvariantViolation) in
            try Fixtures.task(allowedDayparts: [])
        },
        InvariantCase(violation: .noAllowedWeekdays) { () throws(TaskInvariantViolation) in
            try Fixtures.task(allowedWeekdays: [])
        },
        InvariantCase(violation: .windowEndNotAfterStart) { () throws(TaskInvariantViolation) in
            try Fixtures.task(windowStart: InvariantTests.start, windowEnd: InvariantTests.start)  // equal: empty window
        },
        InvariantCase(violation: .windowEndNotAfterStart) { () throws(TaskInvariantViolation) in
            try Fixtures.task(windowStart: InvariantTests.start, windowEnd: InvariantTests.start.addingTimeInterval(-0.001))  // reversed
        },
        InvariantCase(violation: .recurringWithoutInterval) { () throws(TaskInvariantViolation) in
            try Fixtures.task(kind: .recurring, recurrenceIntervalDays: nil)
        },
        InvariantCase(violation: .intervalBelowOneDay) { () throws(TaskInvariantViolation) in
            try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 0)
        },
        InvariantCase(violation: .intervalBelowOneDay) { () throws(TaskInvariantViolation) in
            try Fixtures.task(kind: .recurring, recurrenceIntervalDays: -3)
        },
        InvariantCase(violation: .intervalOnNonRecurringTask) { () throws(TaskInvariantViolation) in
            try Fixtures.task(kind: .oneOff, recurrenceIntervalDays: 7)
        },
        InvariantCase(violation: .intervalOnNonRecurringTask) { () throws(TaskInvariantViolation) in
            try Fixtures.task(kind: .restock, recurrenceIntervalDays: 1)
        },
        InvariantCase(violation: .criticalAndDeepClean) { () throws(TaskInvariantViolation) in
            try Fixtures.task(isCritical: true, isDeepClean: true)
        },
        InvariantCase(violation: .maintenanceOnNonDeepClean) { () throws(TaskInvariantViolation) in
            try Fixtures.task(isDeepClean: false, state: .maintenance)
        },
        InvariantCase(violation: .resurfacedOnNonCritical) { () throws(TaskInvariantViolation) in
            try Fixtures.task(isCritical: false, state: .resurfaced)
        },
    ]

    @Test("AC-M1-25: constructing a task that violates an invariant throws the typed violation",
          arguments: cases)
    func constructionThrows(invariant: InvariantCase) {
        #expect(throws: invariant.violation) {
            try invariant.build()
        }
    }

    @Test("AC-M1-25: the cases cover all nine invariants in the design naming list")
    func casesCoverEveryInvariant() {
        #expect(Set(Self.cases.map(\.violation)) == Set(TaskInvariantViolation.allCases))
        #expect(TaskInvariantViolation.allCases.count == 9)
    }

    @Test("AC-M1-25: values just inside each invariant are accepted (boundary)")
    func boundariesAccepted() throws {
        _ = try Fixtures.task(allowedDayparts: [.night])
        _ = try Fixtures.task(allowedWeekdays: [.sunday])
        _ = try Fixtures.task(windowStart: Self.start, windowEnd: Self.start.addingTimeInterval(0.001))
        _ = try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 1)
        _ = try Fixtures.task(isCritical: true, state: .resurfaced)
        _ = try Fixtures.task(isDeepClean: true, state: .maintenance)
    }

    @Test("AC-M1-25: when several invariants are broken, the first in the documented order is reported")
    func violationOrderIsDeterministic() {
        #expect(throws: TaskInvariantViolation.noAllowedDayparts) {
            try Fixtures.task(isCritical: true, isDeepClean: true, allowedDayparts: [], allowedWeekdays: [])
        }
        #expect(throws: TaskInvariantViolation.windowEndNotAfterStart) {
            try Fixtures.task(kind: .oneOff, windowStart: Self.start, windowEnd: Self.start,
                              recurrenceIntervalDays: 3)
        }
    }

    // MARK: Decode path

    /// Builds the JSON of a task that violates `violation` by encoding a *valid* task and transplanting the offending
    /// field values from other valid encodings (or literal JSON scalars). This keeps the test independent of how
    /// each field is encoded.
    static func violatingJSON(_ violation: TaskInvariantViolation) throws -> [String: Any] {
        switch violation {
        case .noAllowedDayparts:
            var object = try Fixtures.jsonObject(try Fixtures.task())
            object["allowedDayparts"] = [Any]()
            return object
        case .noAllowedWeekdays:
            var object = try Fixtures.jsonObject(try Fixtures.task())
            object["allowedWeekdays"] = [Any]()
            return object
        case .windowEndNotAfterStart:
            var object = try Fixtures.jsonObject(try Fixtures.task())
            object["windowEnd"] = object["windowStart"]
            return object
        case .recurringWithoutInterval:
            var object = try Fixtures.jsonObject(try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7))
            object.removeValue(forKey: "recurrenceIntervalDays")
            return object
        case .intervalBelowOneDay:
            var object = try Fixtures.jsonObject(try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7))
            object["recurrenceIntervalDays"] = 0
            return object
        case .intervalOnNonRecurringTask:
            var object = try Fixtures.jsonObject(try Fixtures.task(kind: .oneOff))
            object["recurrenceIntervalDays"] = 7
            return object
        case .criticalAndDeepClean:
            var object = try Fixtures.jsonObject(try Fixtures.task(isCritical: true))
            object["isDeepClean"] = true
            return object
        case .maintenanceOnNonDeepClean:
            var object = try Fixtures.jsonObject(try Fixtures.task())
            object["state"] = try Fixtures.jsonObject(try Fixtures.task(isDeepClean: true, state: .maintenance))["state"]
            return object
        case .resurfacedOnNonCritical:
            var object = try Fixtures.jsonObject(try Fixtures.task())
            object["state"] = try Fixtures.jsonObject(try Fixtures.task(isCritical: true, state: .resurfaced))["state"]
            return object
        }
    }

    @Test("AC-M1-25: decoding JSON that violates an invariant throws the typed violation",
          arguments: TaskInvariantViolation.allCases)
    func decodeThrows(violation: TaskInvariantViolation) throws {
        let object = try Self.violatingJSON(violation)
        #expect(throws: violation) {
            _ = try Fixtures.decode(HouseholdTask.self, fromJSONObject: object)
        }
    }

    @Test("AC-M1-25: decoding a household whose file contains one invalid task throws the typed violation")
    func householdDecodeThrows() throws {
        var household = try Fixtures.jsonObject(Household(tasks: [try Fixtures.task()], rooms: []))
        household["tasks"] = [try Self.violatingJSON(.criticalAndDeepClean)]
        #expect(throws: TaskInvariantViolation.criticalAndDeepClean) {
            _ = try Fixtures.decode(Household.self, fromJSONObject: household)
        }
    }

    @Test("AC-M1-25 / AC-M1-02: an unknown lifecycle state in JSON is rejected, not mapped to a default")
    func unknownStateRejected() throws {
        for unknownName in ["overdue", "late", "missed", "failed", "Active", ""] {
            var object = try Fixtures.jsonObject(try Fixtures.task())
            guard var state = object["state"] as? [String: Any] else {
                Issue.record("state is not encoded as an object")
                return
            }
            state["name"] = unknownName
            object["state"] = state
            #expect(throws: DecodingError.self, "state name \(unknownName) must be rejected") {
                _ = try Fixtures.decode(HouseholdTask.self, fromJSONObject: object)
            }
        }
    }
}
