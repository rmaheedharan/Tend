// Completion (AC-M1-03; FR-B1, FR-B2, FR-B3 data; UX-3). One-off and restock tasks become `completed`; a recurring
// task comes back `active` on its next eligible window `E(now + interval days, D)`; the task's room is tended now.
// Expected values are hand-computed from the brief, and a seeded property checks every kind and state against the
// independent oracle in `Support/RescheduleOracle.swift`.

import Foundation
import Testing
import TendCore

@Suite("Completion (AC-M1-03)")
struct CompletionTests {
    static let berlin = "Europe/Berlin"
    static let newYork = "America/New_York"

    static let kitchen = Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: Fixtures.referenceDate)
    static let hall = Room(id: Fixtures.id(0xA2), name: "Hall", lastTendedAt: nil)

    /// Wednesday 18 November 2026, 10:17:03.250 in Berlin.
    static func now() throws -> Date {
        try SelectionFixtures.local(2026, 11, 18, 10, 17, 3, millisecond: 250, in: berlin)
    }

    static func complete(
        _ task: HouseholdTask, at now: Date, in zoneID: String, rooms: [Room] = [kitchen, hall]
    ) throws -> (household: Household, didComplete: Bool) {
        let zone = try SelectionFixtures.zone(zoneID)
        var household = Household(tasks: [task], rooms: rooms)
        let didComplete = household.complete(task.id, at: now, calendar: SelectionFixtures.gregorian(in: zone),
                                             timeZone: zone)
        return (household, didComplete)
    }

    // MARK: (a) one-off and restock

    struct StartState: Sendable, CustomTestStringConvertible {
        var label: String
        var isCritical: Bool
        var isDeepClean: Bool
        /// The state, relative to `now` (deferrals need `now`).
        var make: @Sendable (Date) -> TaskState
        var testDescription: String { label }
    }

    static let startStates: [StartState] = [
        StartState(label: "active", isCritical: false, isDeepClean: false, make: { _ in .active }),
        StartState(label: "resting deferral", isCritical: false, isDeepClean: false,
                   make: { .deferred(until: $0.addingTimeInterval(3_600)) }),
        StartState(label: "deferral whose rest is over", isCritical: false, isDeepClean: false,
                   make: { .deferred(until: $0.addingTimeInterval(-3_600)) }),
        StartState(label: "maintenance (deep clean)", isCritical: false, isDeepClean: true, make: { _ in .maintenance }),
        StartState(label: "resurfaced (critical)", isCritical: true, isDeepClean: false, make: { _ in .resurfaced }),
    ]

    @Test("AC-M1-03 (a): a one-off or restock task in any non-completed state becomes completed at now, other fields unchanged; its room is tended now",
          arguments: [TaskKind.oneOff, .restock], startStates)
    func oneOffAndRestock(kind: TaskKind, start: StartState) throws {
        let now = try Self.now()
        let task = try Fixtures.task(
            kind: kind, effort: .high, isCritical: start.isCritical, isDeepClean: start.isDeepClean,
            isWeatherDependent: true, allowedDayparts: [.morning, .evening], allowedWeekdays: [.wednesday, .friday],
            windowStart: now.addingTimeInterval(-86_400.5), windowEnd: now.addingTimeInterval(7_200.25),
            state: start.make(now), completedAt: now.addingTimeInterval(-30 * 86_400))
        let (household, didComplete) = try Self.complete(task, at: now, in: Self.berlin)
        #expect(didComplete)
        let done = try #require(household.tasks.first)
        let expected = try RescheduleOracle.rebuilt(task, state: .completed, completedAt: .some(now))
        #expect(done == expected)
        #expect(done.state == .completed && done.completedAt == now)
        #expect(done.windowStart == task.windowStart && done.windowEnd == task.windowEnd, "window unchanged")
        #expect(done.effort == .high, "stored effort unchanged")
        #expect(household.rooms == [Room(id: Self.kitchen.id, name: "Kitchen", lastTendedAt: now), Self.hall],
                "(c) the task's room is tended now; other rooms unchanged")
    }

    // MARK: (b) recurring

    struct RecurringCase: Sendable, CustomTestStringConvertible {
        var label: String
        var zoneID: String
        /// `now` as (year, month, day, hour, minute, second, millisecond) local, or as a UTC ISO string.
        var nowUTC: String?
        var nowLocal: (Int, Int, Int, Int, Int, Int, Int)?
        var interval: Int
        var dayparts: Set<Daypart>
        var weekdays: Set<Weekday>
        /// Expected new `windowStart` as a UTC ISO string, plus a sub-second part.
        var expectedStartUTC: String
        var expectedFraction: TimeInterval
        var testDescription: String { label }
    }

    static let everyDaypart = Set(Daypart.allCases)
    static let everyWeekday = Set(Weekday.allCases)

    static let recurringCases: [RecurringCase] = [
        RecurringCase(label: "weekly, every slot allowed: same wall-clock time 7 days later (Berlin)",
                      zoneID: berlin, nowLocal: (2026, 11, 18, 10, 17, 3, 250), interval: 7,
                      dayparts: everyDaypart, weekdays: everyWeekday,
                      expectedStartUTC: "2026-11-25T09:17:03Z", expectedFraction: 0.25),
        RecurringCase(label: "every 3 days, weekend only: Saturday 10:17:03.250 is allowed, so it starts there",
                      zoneID: berlin, nowLocal: (2026, 11, 18, 10, 17, 3, 250), interval: 3,
                      dayparts: Daypart.defaultAllowed, weekdays: [.saturday, .sunday],
                      expectedStartUTC: "2026-11-21T09:17:03Z", expectedFraction: 0.25),
        RecurringCase(label: "daily, morning only, completed at 13:00: tomorrow 13:00 is not morning, so the next morning 05:00",
                      zoneID: berlin, nowLocal: (2026, 11, 18, 13, 0, 0, 0), interval: 1,
                      dayparts: [.morning], weekdays: everyWeekday,
                      expectedStartUTC: "2026-11-20T04:00:00Z", expectedFraction: 0),
        RecurringCase(label: "every 4 days, Monday only: anchor Sunday 22 Nov, so Monday 23 Nov 05:00",
                      zoneID: berlin, nowLocal: (2026, 11, 18, 10, 17, 3, 250), interval: 4,
                      dayparts: Daypart.defaultAllowed, weekdays: [.monday],
                      expectedStartUTC: "2026-11-23T04:00:00Z", expectedFraction: 0),
        // DST (R-3, Q11). New York: Sunday 8 March 2026 02:00 EST → 03:00 EDT; Sunday 1 November 2026 02:00 EDT →
        // 01:00 EST.
        RecurringCase(label: "DST spring: 2 days across the change keeps 10:00 local (47 h, not 48 h)",
                      zoneID: newYork, nowLocal: (2026, 3, 6, 10, 0, 0, 0), interval: 2,
                      dayparts: everyDaypart, weekdays: everyWeekday,
                      expectedStartUTC: "2026-03-08T14:00:00Z", expectedFraction: 0),
        RecurringCase(label: "DST spring: a wall time that does not exist (02:30:15.250) resolves to the next instant, 03:00 EDT",
                      zoneID: newYork, nowLocal: (2026, 3, 7, 2, 30, 15, 250), interval: 1,
                      dayparts: everyDaypart, weekdays: everyWeekday,
                      expectedStartUTC: "2026-03-08T07:00:00Z", expectedFraction: 0),
        RecurringCase(label: "DST autumn: a repeated wall time (01:30:15.250) resolves to its first occurrence, EDT",
                      zoneID: newYork, nowLocal: (2026, 10, 31, 1, 30, 15, 250), interval: 1,
                      dayparts: everyDaypart, weekdays: everyWeekday,
                      expectedStartUTC: "2026-11-01T05:30:15Z", expectedFraction: 0.25),
        RecurringCase(label: "DST autumn: completed in the second 01:30 (EST), a week later is 01:30 EST",
                      zoneID: newYork, nowUTC: "2026-11-01T06:30:15Z", interval: 7,
                      dayparts: everyDaypart, weekdays: everyWeekday,
                      expectedStartUTC: "2026-11-08T06:30:15Z", expectedFraction: 0),
        RecurringCase(label: "DST autumn: 2 days across the change keeps 18:00 local (49 h), evening slot",
                      zoneID: newYork, nowLocal: (2026, 10, 30, 18, 0, 0, 0), interval: 2,
                      dayparts: [.evening], weekdays: everyWeekday,
                      expectedStartUTC: "2026-11-01T23:00:00Z", expectedFraction: 0),
    ]

    @Test("AC-M1-03 (b): a recurring task becomes active on exactly E(now + interval days, D), keeps effort and flags; incl. DST days",
          arguments: recurringCases, startStates)
    func recurring(example: RecurringCase, start: StartState) throws {
        let now: Date = if let (y, mo, d, h, mi, s, ms) = example.nowLocal {
            try SelectionFixtures.local(y, mo, d, h, mi, s, millisecond: ms, in: example.zoneID)
        } else {
            try SelectionFixtures.utc(try #require(example.nowUTC))
        }
        let duration: TimeInterval = 2 * 86_400 + 0.375
        let task = try Fixtures.task(
            kind: .recurring, effort: .high, isCritical: start.isCritical, isDeepClean: start.isDeepClean,
            isWeatherDependent: true, allowedDayparts: example.dayparts, allowedWeekdays: example.weekdays,
            windowStart: now.addingTimeInterval(-3_600), windowEnd: now.addingTimeInterval(-3_600 + duration),
            recurrenceIntervalDays: example.interval, state: start.make(now))
        let (household, didComplete) = try Self.complete(task, at: now, in: example.zoneID)
        #expect(didComplete)
        let done = try #require(household.tasks.first)

        let expectedStart = try SelectionFixtures.utc(example.expectedStartUTC)
            .addingTimeInterval(example.expectedFraction)
        #expect(done.state == .active, "leaves \(start.label)")
        #expect(done.windowStart == expectedStart, "\(example.label)")
        #expect(done.windowEnd == expectedStart.addingTimeInterval(duration), "D is kept: windowEnd = s + D")
        #expect(done.completedAt == now)
        #expect(done.effort == .high && done.isCritical == start.isCritical && done.isDeepClean == start.isDeepClean
                && done.isWeatherDependent, "stored effort and flags kept")
        #expect(done == (try RescheduleOracle.rebuilt(task, state: .active, window: (expectedStart,
                                                      expectedStart.addingTimeInterval(duration)),
                                                      completedAt: .some(now))),
                "every other field unchanged")
        let zone = try SelectionFixtures.zone(example.zoneID)
        #expect(done == (try RescheduleOracle.completed(task, at: now, calendar: SelectionFixtures.gregorian(in: zone))),
                "the independent oracle agrees")
        #expect(household.rooms.first?.lastTendedAt == now, "(c) the room is tended now")
    }

    // MARK: (c) rooms

    @Test("AC-M1-03 (c): a task with no room, or a room that is not in the household, changes no room")
    func noRoomChangesNoRoom() throws {
        let now = try Self.now()
        let roomless = try Fixtures.task(roomID: nil)
        #expect(try Self.complete(roomless, at: now, in: Self.berlin).household.rooms == [Self.kitchen, Self.hall])
        let elsewhere = try Fixtures.task(roomID: Fixtures.id(0xFF))
        #expect(try Self.complete(elsewhere, at: now, in: Self.berlin).household.rooms == [Self.kitchen, Self.hall])
    }

    @Test("AC-M1-03: only the completed task changes; the other tasks and the schema version are kept")
    func otherTasksUnchanged() throws {
        let now = try Self.now()
        let tasks = try (1...5).map { try Fixtures.task(id: Fixtures.id($0), roomID: $0 == 3 ? Self.hall.id : nil) }
        let zone = try SelectionFixtures.zone(Self.berlin)
        var household = Household(tasks: tasks, rooms: [Self.kitchen, Self.hall])
        let didComplete = household.complete(Fixtures.id(3), at: now,
                                             calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone)
        #expect(didComplete)
        for index in [0, 1, 3, 4] { #expect(household.tasks[index] == tasks[index]) }
        #expect(household.tasks[2].state == .completed)
        #expect(household.rooms == [Self.kitchen, Room(id: Self.hall.id, name: "Hall", lastTendedAt: now)])
        #expect(household.schemaVersion == Household.currentSchemaVersion)
    }

    @Test("AC-M1-03 scope: completing an unknown ID or an already completed task changes nothing and reports false")
    func unknownOrCompletedIsANoOp() throws {
        let now = try Self.now()
        let zone = try SelectionFixtures.zone(Self.berlin)
        let calendar = SelectionFixtures.gregorian(in: zone)
        let done = try Fixtures.task(state: .completed, completedAt: now.addingTimeInterval(-60))
        var household = Household(tasks: [done], rooms: [Self.kitchen])
        let before = household
        let completedAgain = household.complete(done.id, at: now, calendar: calendar, timeZone: zone)
        let unknown = household.complete(Fixtures.id(0x999), at: now, calendar: calendar, timeZone: zone)
        #expect(!completedAgain && !unknown)
        #expect(household == before)
    }

    // MARK: Property against the oracle

    @Test("AC-M1-03: over 300 seeded households every non-completed task completes exactly as the independent oracle says")
    func completionProperty() throws {
        var completedCount = 0
        var recurringCount = 0
        var nearDST = 0
        for seed in UInt64(500_001)...500_300 {
            let testCase = try SelectionCorpus.makeCase(seed: seed, taskCounts: 0...40)
            let moment = testCase.moment
            for task in testCase.household.tasks where task.state != .completed {
                var household = testCase.household
                let didComplete = household.complete(task.id, at: moment.now, calendar: moment.calendar,
                                                     timeZone: moment.timeZone)
                let index = try #require(household.tasks.firstIndex { $0.id == task.id })
                let expected = try RescheduleOracle.completed(task, at: moment.now, calendar: moment.calendar)
                #expect(didComplete, "seed \(seed)")
                #expect(household.tasks[index] == expected, "seed \(seed), task \(task.id): \(testCase.description)")
                if let roomID = task.roomID, let room = household.rooms.first(where: { $0.id == roomID }) {
                    #expect(room.lastTendedAt == moment.now, "seed \(seed): room tended now")
                }
                let otherRooms = household.rooms.filter { $0.id != task.roomID }
                #expect(otherRooms == testCase.household.rooms.filter { $0.id != task.roomID }, "seed \(seed)")
                completedCount += 1
                if task.kind == .recurring { recurringCount += 1 }
            }
            if let change = moment.timeZone.nextDaylightSavingTimeTransition(after: moment.now.addingTimeInterval(-43_200)),
               abs(change.timeIntervalSince(moment.now)) <= 43_200 {
                nearDST += 1
            }
        }
        print("AC-M1-03 property: seeds 500001...500300, \(completedCount) completions, \(recurringCount) recurring, "
              + "\(nearDST) moments within 12 h of a DST change")
        #expect(recurringCount > 100 && nearDST > 10)
    }
}
