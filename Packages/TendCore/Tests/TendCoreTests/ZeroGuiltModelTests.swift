// AC-M1-02 (structural part) and design D-1, D-2: the lifecycle is a closed set with no debt state, and no model
// type stores a counter, an original window or a history that would let anyone compute lateness later.
// Also the design-review check that `PromptTone` has exactly one case (AC-M1-18 groundwork, design.md).
// Requirements: UX-3, FR-B2.

import Foundation
import Testing
import TendCore

@Suite("Zero-guilt model structure (AC-M1-02, D-1, D-2)")
struct ZeroGuiltModelTests {

    /// The design naming list, exactly. Adding any stored field (a counter, an original window, a history) fails.
    static let householdTaskStoredFields: [String] = [
        "id", "title", "kind", "roomID", "effort", "isCritical", "isDeepClean", "isWeatherDependent",
        "allowedDayparts", "allowedWeekdays", "windowStart", "windowEnd", "recurrenceIntervalDays", "state",
        "completedAt",
    ]

    /// Exhaustive switch with no `default`: adding a lifecycle case breaks compilation of this test.
    static func caseName(of state: TaskState) -> String {
        switch state {
        case .active: "active"
        case .deferred: "deferred"
        case .maintenance: "maintenance"
        case .resurfaced: "resurfaced"
        case .completed: "completed"
        }
    }

    @Test("AC-M1-02: the lifecycle state is the closed set active, deferred(until:), maintenance, resurfaced, completed")
    func lifecycleIsClosedSet() throws {
        let until = Fixtures.referenceDate
        let all: [TaskState] = [.active, .deferred(until: until), .maintenance, .resurfaced, .completed]
        #expect(all.map(Self.caseName(of:)) == ["active", "deferred", "maintenance", "resurfaced", "completed"])

        // The only associated value is the deferral date (no reason, no count, no original date).
        let deferred = Mirror(reflecting: TaskState.deferred(until: until))
        let payload = try #require(deferred.children.first)
        #expect(payload.label == "deferred")
        let payloadFields = Mirror(reflecting: payload.value).children.map(\.label)
        #expect(payloadFields == ["until"])
        for state in [TaskState.active, .maintenance, .resurfaced, .completed] {
            #expect(Mirror(reflecting: state).children.isEmpty, "\(state) must carry no data")
        }
    }

    @Test("AC-M1-02 / D-2: HouseholdTask stores exactly the fields in the design naming list (no counter, original window or history)")
    func householdTaskStoredFieldsAreExact() throws {
        let task = try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7)
        let labels = Mirror(reflecting: task).children.compactMap(\.label)
        print("D-2: HouseholdTask stored fields: \(labels.joined(separator: ", "))")
        #expect(labels == Self.householdTaskStoredFields)
    }

    @Test("AC-M1-02 / D-2: the encoded HouseholdTask has exactly the naming-list keys")
    func householdTaskEncodedKeysAreExact() throws {
        // A task with every optional present, so no key is omitted.
        let task = try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7,
                                     state: .deferred(until: Fixtures.referenceDate),
                                     completedAt: Fixtures.referenceDate)
        let object = try Fixtures.jsonObject(task)
        #expect(Set(object.keys) == Set(Self.householdTaskStoredFields))
        let state = try #require(object["state"] as? [String: Any])
        #expect(Set(state.keys) == ["name", "until"])
    }

    @Test("AC-M1-02 / D-2: Room and Household store no counters or history")
    func roomAndHouseholdFieldsAreExact() throws {
        let room = Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: Fixtures.referenceDate)
        #expect(Mirror(reflecting: room).children.compactMap(\.label) == ["id", "name", "lastTendedAt"])
        let household = Household(tasks: [], rooms: [room])
        #expect(Mirror(reflecting: household).children.compactMap(\.label) == ["tasks", "rooms", "schemaVersion"])
    }

    @Test("Design review: PromptTone has exactly one case, gentle (AC-M1-18 groundwork)")
    func promptToneHasOneCase() throws {
        #expect(PromptTone.allCases == [.gentle])
        #expect(try Fixtures.roundTrip([PromptTone.gentle]) == [.gentle])
    }

    @Test("AC-M1-25 naming: TaskInvariantViolation has exactly the nine design-list cases")
    func invariantViolationCases() {
        #expect(TaskInvariantViolation.allCases == [
            .noAllowedDayparts, .noAllowedWeekdays, .windowEndNotAfterStart, .recurringWithoutInterval,
            .intervalBelowOneDay, .intervalOnNonRecurringTask, .criticalAndDeepClean, .maintenanceOnNonDeepClean,
            .resurfacedOnNonCritical,
        ])
    }
}

@Suite("Effective-state helpers (D-1; brief definitions, Q12, Q13)")
struct EffectiveStateTests {
    static let now = Fixtures.referenceDate

    @Test("D-1: isResting and isRestOver split a deferral at now (until > now rests; until <= now rest is over)",
          arguments: [
            (-3600.0, false, true),
            (-0.001, false, true),
            (0.0, false, true),
            (0.001, true, false),
            (1.0, true, false),
          ])
    func restingAndRestOver(offset: TimeInterval, resting: Bool, restOver: Bool) throws {
        let task = try Fixtures.task(state: .deferred(until: Self.now.addingTimeInterval(offset)))
        #expect(task.isResting(at: Self.now) == resting)
        #expect(task.isRestOver(at: Self.now) == restOver)
    }

    @Test("D-1: a task that is not deferred is neither resting nor at the end of a rest",
          arguments: [TaskState.active, .completed])
    func notDeferred(state: TaskState) throws {
        let task = try Fixtures.task(state: state)
        #expect(!task.isResting(at: Self.now))
        #expect(!task.isRestOver(at: Self.now))
    }

    @Test("Window helpers are half-open: windowStart <= now < windowEnd is open; windowEnd <= now has ended",
          arguments: [
            // (start offset, end offset, open, ended)
            (0.0, 1.0, true, false),         // windowStart == now
            (0.001, 1.0, false, false),      // not yet open
            (-1.0, 0.0, false, true),        // windowEnd == now: ended
            (-1.0, 0.001, true, false),      // windowEnd just after now
            (-7200.0, -3600.0, false, true), // ended an hour ago
          ])
    func windowHelpers(startOffset: TimeInterval, endOffset: TimeInterval, open: Bool, ended: Bool) throws {
        let task = try Fixtures.task(windowStart: Self.now.addingTimeInterval(startOffset),
                                     windowEnd: Self.now.addingTimeInterval(endOffset))
        #expect(task.windowIsOpen(at: Self.now) == open)
        #expect(task.windowHasEnded(at: Self.now) == ended)
    }
}
