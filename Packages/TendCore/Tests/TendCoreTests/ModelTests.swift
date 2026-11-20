// AC-M1-01: the household model can represent every task the invariants allow, and is Equatable and Codable.
// Requirements: FR-B1, FR-B2, FR-B3 (data only: Room.lastTendedAt), UX-3.

import Foundation
import Testing
import TendCore

@Suite("Household model (AC-M1-01)")
struct ModelTests {

    @Test("AC-M1-01: one task of each kind (one-off errand, recurring maintenance, consumable restock) is representable, Equatable and Codable",
          arguments: TaskKind.allCases)
    func oneTaskOfEachKind(kind: TaskKind) throws {
        let task = try Fixtures.task(
            kind: kind,
            recurrenceIntervalDays: kind == .recurring ? 7 : nil
        )
        #expect(task.kind == kind)
        #expect(task == task)
        let decoded = try Fixtures.roundTrip(task)
        #expect(decoded == task)
        #expect(decoded.windowStart == task.windowStart)  // fractional seconds survive exactly
        #expect(decoded.windowEnd == task.windowEnd)
    }

    /// Every combination of kind, effort, critical/deep-clean flags, weather flag, lifecycle state, optional room and
    /// optional completion date. Combinations that break an invariant must be rejected (AC-M1-25); every other one
    /// must construct, compare equal to itself and round-trip through JSON unchanged.
    @Test("AC-M1-01: every field combination allowed by the model invariants is representable and round-trips through Codable")
    func everyAllowedCombinationRoundTrips() throws {
        let start = Fixtures.referenceDate
        let states: [TaskState] = [
            .active, .deferred(until: start.addingTimeInterval(3600.25)), .maintenance, .resurfaced, .completed,
        ]
        let flagCombinations: [(critical: Bool, deepClean: Bool)] = [
            (false, false), (true, false), (false, true), (true, true),
        ]
        var representable = 0
        var rejected = 0
        var index = 0
        for kind in TaskKind.allCases {
            for effort in Effort.allCases {
                for flags in flagCombinations {
                    for isWeatherDependent in [false, true] {
                        for state in states {
                            for roomID in [nil, Fixtures.kitchenID] {
                                for completedAt in [nil, start.addingTimeInterval(42.75)] {
                                    index += 1
                                    let expectedViolation = Self.expectedViolation(
                                        critical: flags.critical, deepClean: flags.deepClean, state: state)
                                    let result = Result { () throws(TaskInvariantViolation) in
                                        try HouseholdTask(
                                            id: Fixtures.id(index), title: "Task \(index)", kind: kind,
                                            roomID: roomID, effort: effort, isCritical: flags.critical,
                                            isDeepClean: flags.deepClean, isWeatherDependent: isWeatherDependent,
                                            allowedDayparts: Daypart.defaultAllowed,
                                            allowedWeekdays: Set(Weekday.allCases),
                                            windowStart: start, windowEnd: start.addingTimeInterval(86_400.5),
                                            recurrenceIntervalDays: kind == .recurring ? 14 : nil,
                                            state: state, completedAt: completedAt)
                                    }
                                    switch result {
                                    case .success(let task):
                                        #expect(expectedViolation == nil, "combination \(index) should be rejected")
                                        #expect(task.state == state)
                                        #expect(task.effort == effort)
                                        #expect(task.roomID == roomID)
                                        #expect(task.completedAt == completedAt)
                                        #expect(try Fixtures.roundTrip(task) == task)
                                        representable += 1
                                    case .failure(let violation):
                                        #expect(violation == expectedViolation, "combination \(index)")
                                        rejected += 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        print("AC-M1-01: \(index) combinations checked, \(representable) representable, \(rejected) rejected by invariants")
        #expect(representable > 0)
        #expect(representable + rejected == index)
    }

    @Test("AC-M1-01: every non-empty set of allowed dayparts and weekdays is representable and round-trips")
    func everyDaypartAndWeekdaySetRoundTrips() throws {
        let daypartSets = Fixtures.nonEmptySubsets(of: Daypart.allCases)
        let weekdaySets = Fixtures.nonEmptySubsets(of: Weekday.allCases)
        #expect(daypartSets.count == 15)
        #expect(weekdaySets.count == 127)
        var checked = 0
        for dayparts in daypartSets {
            for weekdays in weekdaySets {
                let task = try Fixtures.task(allowedDayparts: dayparts, allowedWeekdays: weekdays)
                let decoded = try Fixtures.roundTrip(task)
                #expect(decoded == task)
                #expect(decoded.allowedDayparts == dayparts)
                #expect(decoded.allowedWeekdays == weekdays)
                checked += 1
            }
        }
        print("AC-M1-01: \(checked) daypart × weekday sets round-tripped")
    }

    @Test("AC-M1-01: Equatable distinguishes every stored field of HouseholdTask")
    func equatableCoversEveryField() throws {
        let base = try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7)
        let start = base.windowStart
        let variants: [(field: String, task: HouseholdTask)] = [
            ("id", try Fixtures.task(id: Fixtures.id(999), kind: .recurring, recurrenceIntervalDays: 7)),
            ("title", try Fixtures.task(title: "Water the plants", kind: .recurring, recurrenceIntervalDays: 7)),
            ("kind", try Fixtures.task(kind: .oneOff)),
            ("roomID", try Fixtures.task(kind: .recurring, roomID: nil, recurrenceIntervalDays: 7)),
            ("effort", try Fixtures.task(kind: .recurring, effort: .high, recurrenceIntervalDays: 7)),
            ("isCritical", try Fixtures.task(kind: .recurring, isCritical: true, recurrenceIntervalDays: 7)),
            ("isDeepClean", try Fixtures.task(kind: .recurring, isDeepClean: true, recurrenceIntervalDays: 7)),
            ("isWeatherDependent",
             try Fixtures.task(kind: .recurring, isWeatherDependent: true, recurrenceIntervalDays: 7)),
            ("allowedDayparts",
             try Fixtures.task(kind: .recurring, allowedDayparts: [.night], recurrenceIntervalDays: 7)),
            ("allowedWeekdays",
             try Fixtures.task(kind: .recurring, allowedWeekdays: [.saturday], recurrenceIntervalDays: 7)),
            ("windowStart",
             try Fixtures.task(kind: .recurring, windowStart: start.addingTimeInterval(0.001),
                               recurrenceIntervalDays: 7)),
            ("windowEnd",
             try Fixtures.task(kind: .recurring, windowEnd: base.windowEnd.addingTimeInterval(0.001),
                               recurrenceIntervalDays: 7)),
            ("recurrenceIntervalDays", try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 8)),
            ("state",
             try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7, state: .deferred(until: start))),
            ("completedAt", try Fixtures.task(kind: .recurring, recurrenceIntervalDays: 7, completedAt: start)),
        ]
        #expect(variants.count == ZeroGuiltModelTests.householdTaskStoredFields.count)
        for variant in variants {
            #expect(variant.task != base, "changing \(variant.field) must make the tasks unequal")
        }
    }

    @Test("AC-M1-01: TaskState values are Equatable and Codable, including the deferral date (FR-B2)")
    func taskStateRoundTrips() throws {
        let until = Fixtures.referenceDate.addingTimeInterval(0.25)
        let states: [TaskState] = [.active, .deferred(until: until), .maintenance, .resurfaced, .completed]
        for state in states {
            #expect(try Fixtures.roundTrip(StateBox(state: state)).state == state)
        }
        #expect(TaskState.deferred(until: until) != .deferred(until: until.addingTimeInterval(0.001)))
        #expect(TaskState.active != .resurfaced)
    }

    @Test("AC-M1-01 / FR-B3: a Room carries an optional lastTendedAt and round-trips through Codable")
    func roomCarriesLastTendedAt() throws {
        let untended = Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: nil)
        let tended = Room(id: Fixtures.kitchenID, name: "Kitchen",
                          lastTendedAt: Fixtures.referenceDate.addingTimeInterval(0.5))
        #expect(untended.lastTendedAt == nil)
        #expect(untended != tended)
        #expect(try Fixtures.roundTrip(untended) == untended)
        #expect(try Fixtures.roundTrip(tended) == tended)
        #expect(try Fixtures.roundTrip(tended).lastTendedAt == tended.lastTendedAt)
    }

    @Test("AC-M1-01: a Household holds tasks, rooms and a schema version and round-trips through Codable")
    func householdRoundTrips() throws {
        let rooms = [
            Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: Fixtures.referenceDate),
            Room(id: Fixtures.id(0xA2), name: "Balcony", lastTendedAt: nil),
        ]
        let tasks = [
            try Fixtures.task(id: Fixtures.id(1), kind: .oneOff),
            try Fixtures.task(id: Fixtures.id(2), kind: .recurring, isDeepClean: true,
                              recurrenceIntervalDays: 30, state: .maintenance),
            try Fixtures.task(id: Fixtures.id(3), kind: .restock, roomID: nil, isCritical: true,
                              state: .resurfaced),
        ]
        let household = Household(tasks: tasks, rooms: rooms)
        #expect(household.schemaVersion == Household.currentSchemaVersion)
        #expect(Household.currentSchemaVersion == 1)
        #expect(try Fixtures.roundTrip(household) == household)
        #expect(Household(tasks: [], rooms: []).tasks.isEmpty)
    }

    @Test("AC-M1-01: the default allowed dayparts are morning, afternoon and evening; night is quiet (Q2)")
    func defaultDayparts() throws {
        #expect(Daypart.defaultAllowed == [.morning, .afternoon, .evening])
        let task = try HouseholdTask(
            id: Fixtures.id(7), title: "Take out the recycling", kind: .oneOff, effort: .low,
            windowStart: Fixtures.referenceDate, windowEnd: Fixtures.referenceDate.addingTimeInterval(3600))
        #expect(task.allowedDayparts == [.morning, .afternoon, .evening])
        #expect(task.allowedWeekdays == Set(Weekday.allCases))
        #expect(task.state == .active)
        #expect(task.roomID == nil)
        #expect(!task.isCritical && !task.isDeepClean && !task.isWeatherDependent)
    }

    @Test("AC-M1-01: the value enums hold exactly the cases in the design naming list")
    func enumCases() {
        #expect(TaskKind.allCases == [.oneOff, .recurring, .restock])
        #expect(Effort.allCases == [.low, .normal, .high])
        #expect(EnergyLevel.allCases == [.low, .normal, .high])
        #expect(Daypart.allCases == [.morning, .afternoon, .evening, .night])
        #expect(Weekday.allCases == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        #expect(WeatherCondition.allCases == [.clear, .cloudy, .wet, .severe, .unknown])
    }

    /// Mirrors the brief's "Model invariants" to predict the outcome of a combination. The order matches the order in
    /// which `HouseholdTask` checks them (documented in dev-notes).
    static func expectedViolation(critical: Bool, deepClean: Bool, state: TaskState)
        -> TaskInvariantViolation?
    {
        if critical && deepClean { return .criticalAndDeepClean }
        if state == .maintenance && !deepClean { return .maintenanceOnNonDeepClean }
        if state == .resurfaced && !critical { return .resurfacedOnNonCritical }
        return nil
    }
}

/// Wraps a `TaskState` so it can be encoded as a top-level JSON object.
struct StateBox: Codable, Equatable {
    var state: TaskState
}
