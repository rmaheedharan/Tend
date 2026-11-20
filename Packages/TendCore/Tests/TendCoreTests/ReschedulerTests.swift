// Gentle rescheduling, rule by rule (AC-M1-17, AC-M1-18, AC-M1-19; rules R0–R4; FR-B2, UX-3; design D-1, D-2).
// When a window ends, a deep clean is lightened to maintenance, a critical task is brought back gently, and every
// other task moves to its next eligible window `E(now, D)`. Nothing counts or records the move. Expected windows are
// hand-computed from the brief; the oracle in `Support/RescheduleOracle.swift` is checked against the same examples.
// Test names say "window ended", never the PRD's gate wording (design.md).

import Foundation
import Testing
import TendCore

@Suite("Rescheduler rules R0–R4 (AC-M1-17, AC-M1-18, AC-M1-19)")
struct ReschedulerTests {
    static let berlin = "Europe/Berlin"
    static let newYork = "America/New_York"

    static func reschedule(_ task: HouseholdTask, at now: Date, in zoneID: String) throws
        -> (task: HouseholdTask, outcome: RescheduleOutcome)
    {
        let zone = try SelectionFixtures.zone(zoneID)
        return Rescheduler.reschedule(task, at: now, calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone)
    }

    static func oracle(_ task: HouseholdTask, at now: Date, in zoneID: String) throws -> HouseholdTask {
        try RescheduleOracle.rescheduled(task, at: now,
                                         calendar: SelectionFixtures.gregorian(in: try SelectionFixtures.zone(zoneID)))
    }

    /// One example: when `now` is, which slots the task allows, and where `E(now, D)` must start.
    struct WindowCase: Sendable, CustomTestStringConvertible {
        var label: String
        var zoneID: String
        var now: String                 // UTC ISO-8601
        var nowFraction: TimeInterval
        var dayparts: Set<Daypart>
        var weekdays: Set<Weekday>
        var expectedStart: String?      // UTC ISO-8601; nil = `now` itself
        /// The ended window ends exactly at `now` (brief Q13) rather than an hour before.
        var endsAtNow: Bool
        var testDescription: String { label }
    }

    static let everyWeekday = Set(Weekday.allCases)

    /// Shared by AC-M1-17, 18 and 19. Berlin is UTC+1 in November; New York changes on 8 March and 1 November 2026.
    static let windowCases: [WindowCase] = [
        WindowCase(label: "window ends exactly at now, now inside an allowed slot: E starts at now",
                   zoneID: berlin, now: "2026-11-18T09:17:03Z", nowFraction: 0.25, dayparts: Daypart.defaultAllowed,
                   weekdays: everyWeekday, expectedStart: nil, endsAtNow: true),
        WindowCase(label: "window ended an hour ago, now inside an allowed slot: E starts at now",
                   zoneID: berlin, now: "2026-11-18T09:17:03Z", nowFraction: 0.25, dayparts: [.morning],
                   weekdays: [.wednesday], expectedStart: nil, endsAtNow: false),
        WindowCase(label: "now outside the allowed slots: E starts at the next allowed slot (Saturday 05:00)",
                   zoneID: berlin, now: "2026-11-18T09:17:03Z", nowFraction: 0.25, dayparts: [.morning],
                   weekdays: [.saturday], expectedStart: "2026-11-21T04:00:00Z", endsAtNow: true),
        WindowCase(label: "night slot across midnight: Sunday 01:00 is Saturday night, so E starts at now",
                   zoneID: berlin, now: "2026-11-22T00:00:00Z", nowFraction: 0, dayparts: [.night],
                   weekdays: [.saturday], expectedStart: nil, endsAtNow: true),
        WindowCase(label: "night slot across midnight: Saturday 01:00 is Friday night, so E starts Saturday 22:00",
                   zoneID: berlin, now: "2026-11-21T00:00:00Z", nowFraction: 0, dayparts: [.night],
                   weekdays: [.saturday], expectedStart: "2026-11-21T21:00:00Z", endsAtNow: false),
        WindowCase(label: "DST spring day: morning-only task at 01:30 EST starts at 05:00 EDT",
                   zoneID: newYork, now: "2026-03-08T06:30:00Z", nowFraction: 0.5, dayparts: [.morning],
                   weekdays: everyWeekday, expectedStart: "2026-03-08T09:00:00Z", endsAtNow: true),
        WindowCase(label: "DST autumn day: evening-only task at Saturday 23:00 EDT starts Sunday 17:00 EST",
                   zoneID: newYork, now: "2026-11-01T03:00:00Z", nowFraction: 0, dayparts: [.evening],
                   weekdays: everyWeekday, expectedStart: "2026-11-01T22:00:00Z", endsAtNow: false),
        WindowCase(label: "DST autumn night: the repeated 01:30 (second, EST) is inside Saturday night, so E starts at now",
                   zoneID: newYork, now: "2026-11-01T06:30:00Z", nowFraction: 0, dayparts: [.night],
                   weekdays: [.saturday], expectedStart: nil, endsAtNow: true),
    ]

    struct Expected {
        var now: Date
        var start: Date
        var task: HouseholdTask
    }

    /// Builds a task of the given flags and state whose window ended at (or an hour before) the case's `now`.
    static func endedTask(
        _ example: WindowCase, kind: TaskKind = .oneOff, isCritical: Bool = false, isDeepClean: Bool = false,
        state: (Date) -> TaskState
    ) throws -> Expected {
        let now = try SelectionFixtures.utc(example.now).addingTimeInterval(example.nowFraction)
        let end = example.endsAtNow ? now : now.addingTimeInterval(-3_600.125)
        let duration: TimeInterval = 3 * 86_400 + 0.5
        let task = try Fixtures.task(
            kind: kind, effort: .high, isCritical: isCritical, isDeepClean: isDeepClean, isWeatherDependent: true,
            allowedDayparts: example.dayparts, allowedWeekdays: example.weekdays,
            windowStart: end.addingTimeInterval(-duration), windowEnd: end,
            recurrenceIntervalDays: kind == .recurring ? 14 : nil, state: state(now),
            completedAt: now.addingTimeInterval(-40 * 86_400))
        let start = try example.expectedStart.map(SelectionFixtures.utc) ?? now
        return Expected(now: now, start: start, task: task)
    }

    /// Asserts the window is exactly `E(now, D)` with the hand-computed start, and every non-window, non-state field
    /// is unchanged.
    static func expectMoved(_ result: HouseholdTask, from original: HouseholdTask, to start: Date,
                            state: TaskState, _ label: String) throws {
        let duration = original.windowEnd.timeIntervalSince(original.windowStart)
        #expect(result.windowStart == start, "\(label)")
        #expect(result.windowEnd == start.addingTimeInterval(duration), "windowEnd = s + D exactly: \(label)")
        #expect(result.windowEnd.timeIntervalSince(result.windowStart).bitPattern == duration.bitPattern,
                "D kept bit for bit: \(label)")
        #expect(result == (try RescheduleOracle.rebuilt(original, state: state,
                                                        window: (start, start.addingTimeInterval(duration)))),
                "every other field unchanged: \(label)")
    }

    // MARK: AC-M1-17 deep clean → maintenance

    @Test("AC-M1-17: a deep clean whose window ended moves to maintenance on exactly E(now, D); stored effort unchanged",
          arguments: windowCases, ["active", "maintenance", "rest over"])
    func deepCleanIsLightened(example: WindowCase, startState: String) throws {
        let expected = try Self.endedTask(example, isDeepClean: true) { now in
            switch startState {
            case "active": .active
            case "maintenance": .maintenance
            default: .deferred(until: now.addingTimeInterval(-60))
            }
        }
        let (result, outcome) = try Self.reschedule(expected.task, at: expected.now, in: example.zoneID)
        #expect(result.state == .maintenance)
        #expect(outcome == .lightened)
        #expect(result.effort == .high, "stored effort is kept")
        try Self.expectMoved(result, from: expected.task, to: expected.start, state: .maintenance, example.label)
        #expect(result == (try Self.oracle(expected.task, at: expected.now, in: example.zoneID)), "oracle agrees")
    }

    @Test("AC-M1-17: the lightened deep clean counts as low effort when its new window opens (low energy selects it)")
    func maintenanceCountsAsLowEffort() throws {
        let example = Self.windowCases[0]
        let expected = try Self.endedTask(example, isDeepClean: true) { _ in .active }
        let task = expected.task
        let (result, _) = try Self.reschedule(task, at: expected.now, in: example.zoneID)
        let insideNewWindow = expected.now.addingTimeInterval(60)
        let lowEnergy = try SelectionFixtures.moment(at: insideNewWindow, in: example.zoneID, weather: .clear,
                                                     energy: .low)
        #expect(NowSelector.select(from: [result], in: lowEnergy).items == [result])
        #expect(NowSelector.select(from: [task], in: lowEnergy).isEmpty, "before: ended window, high effort")
    }

    // MARK: AC-M1-18 critical → resurfaced

    @Test("AC-M1-18: a critical task whose window ended is brought back gently (resurfaced) on exactly E(now, D)",
          arguments: windowCases, ["active", "resurfaced", "rest over"])
    func criticalIsBroughtBackGently(example: WindowCase, startState: String) throws {
        let expected = try Self.endedTask(example, kind: .restock, isCritical: true) { now in
            switch startState {
            case "active": .active
            case "resurfaced": .resurfaced
            default: .deferred(until: now)
            }
        }
        let (result, outcome) = try Self.reschedule(expected.task, at: expected.now, in: example.zoneID)
        #expect(result.state == .resurfaced)
        #expect(outcome == .broughtBackGently)
        #expect(result.effort == .high, "stored effort is kept")
        #expect(result.promptTone == .gentle)
        try Self.expectMoved(result, from: expected.task, to: expected.start, state: .resurfaced, example.label)
        #expect(result == (try Self.oracle(expected.task, at: expected.now, in: example.zoneID)), "oracle agrees")
    }

    @Test("AC-M1-18: a resurfaced task carries no escalation field; the only prompt metadata is the fixed gentle tone")
    func noEscalation() throws {
        let example = Self.windowCases[0]
        var task = try Self.endedTask(example, isCritical: true) { _ in .active }.task
        var now = try SelectionFixtures.utc(example.now)
        var tones: Set<PromptTone> = []
        var storedLabels: Set<[String]> = []
        for _ in 1...20 {
            now = task.windowEnd
            task = try Self.reschedule(task, at: now, in: example.zoneID).task
            tones.insert(task.promptTone)
            storedLabels.insert(Mirror(reflecting: task).children.compactMap(\.label))
        }
        #expect(tones == [.gentle], "the tone never changes across passes")
        #expect(PromptTone.allCases == [.gentle])
        let labels = try #require(storedLabels.first)
        #expect(storedLabels.count == 1)
        let designList = ["id", "title", "kind", "roomID", "effort", "isCritical", "isDeepClean", "isWeatherDependent",
                          "allowedDayparts", "allowedWeekdays", "windowStart", "windowEnd", "recurrenceIntervalDays",
                          "state", "completedAt"]
        #expect(labels == designList, "no urgency, severity, tone or counter is stored on the task")
        let json = try Fixtures.jsonObject(task)
        // Optional fields are written only when present: this one-off task has a room and a completion date.
        #expect(Set(json.keys) == Set(designList.filter { $0 != "recurrenceIntervalDays" }))
    }

    // MARK: AC-M1-19 other tasks → next window

    @Test("AC-M1-19: any other task whose window ended stays active on exactly E(now, D), every other field unchanged",
          arguments: [TaskKind.oneOff, .recurring, .restock], windowCases)
    func otherTasksMove(kind: TaskKind, example: WindowCase) throws {
        let expected = try Self.endedTask(example, kind: kind) { _ in .active }
        let (result, outcome) = try Self.reschedule(expected.task, at: expected.now, in: example.zoneID)
        #expect(result.state == .active)
        #expect(outcome == .movedToNextWindow)
        #expect(result.recurrenceIntervalDays == expected.task.recurrenceIntervalDays,
                "the interval applies only on completion")
        try Self.expectMoved(result, from: expected.task, to: expected.start, state: .active, example.label)
        #expect(result == (try Self.oracle(expected.task, at: expected.now, in: example.zoneID)), "oracle agrees")
    }

    @Test("AC-M1-19 / R1: a deferral whose rest is over and whose window ended becomes active on E(now, D)",
          arguments: [TaskKind.oneOff, .recurring, .restock])
    func restOverThenMoved(kind: TaskKind) throws {
        let example = Self.windowCases[2]
        let expected = try Self.endedTask(example, kind: kind) { .deferred(until: $0.addingTimeInterval(-86_400)) }
        let (result, outcome) = try Self.reschedule(expected.task, at: expected.now, in: example.zoneID)
        #expect(outcome == .movedToNextWindow)
        try Self.expectMoved(result, from: expected.task, to: expected.start, state: .active, example.label)
    }

    // MARK: R0, R1 and windows that have not ended

    @Test("R0: completed tasks and resting deferrals are not touched, even with an ended window")
    func completedAndRestingUntouched() throws {
        let example = Self.windowCases[1]
        let completed = try Self.endedTask(example, isDeepClean: true) { _ in .completed }
        let resting = try Self.endedTask(example, isCritical: true) { .deferred(until: $0.addingTimeInterval(0.001)) }
        for expected in [completed, resting] {
            let (result, outcome) = try Self.reschedule(expected.task, at: expected.now, in: example.zoneID)
            #expect(result == expected.task)
            #expect(outcome == .unchanged)
        }
    }

    @Test("R1: a deferral whose rest is over and whose window is still open becomes active and nothing else changes")
    func restEndedOnly() throws {
        let now = try SelectionFixtures.utc("2026-11-18T09:17:03Z")
        for until in [now, now.addingTimeInterval(-3_600)] {
            let task = try Fixtures.task(isCritical: true, windowStart: now.addingTimeInterval(-60),
                                         windowEnd: now.addingTimeInterval(0.001), state: .deferred(until: until))
            let (result, outcome) = try Self.reschedule(task, at: now, in: Self.berlin)
            #expect(outcome == .restEnded)
            #expect(result == (try RescheduleOracle.rebuilt(task, state: .active)))
        }
    }

    @Test("Window open or not yet open: the task is unchanged in every state",
          arguments: [TaskState.active, .maintenance, .resurfaced])
    func openOrUpcomingUnchanged(state: TaskState) throws {
        let now = try SelectionFixtures.utc("2026-11-18T09:17:03Z")
        let windows: [(Date, Date)] = [
            (now, now.addingTimeInterval(1)),                                  // starts at now (open)
            (now.addingTimeInterval(-60), now.addingTimeInterval(0.000_1)),    // open, ends just after now
            (now.addingTimeInterval(0.001), now.addingTimeInterval(60)),       // not yet open
        ]
        for (start, end) in windows {
            let task = try Fixtures.task(isCritical: state == .resurfaced, isDeepClean: state == .maintenance,
                                         windowStart: start, windowEnd: end, state: state)
            let (result, outcome) = try Self.reschedule(task, at: now, in: Self.berlin)
            #expect(result == task)
            #expect(outcome == .unchanged)
        }
    }

    @Test("Rescheduler: the household version keeps task order, rooms and schema version, and matches the per-task rules")
    func householdPass() throws {
        let example = Self.windowCases[2]
        let a = try Self.endedTask(example, isDeepClean: true) { _ in .active }
        let now = a.now
        let tasks = try [
            a.task,
            Fixtures.task(id: Fixtures.id(2), isCritical: true, windowStart: now.addingTimeInterval(-10),
                          windowEnd: now, state: .resurfaced),
            Fixtures.task(id: Fixtures.id(3), state: .completed),
            Fixtures.task(id: Fixtures.id(4), windowStart: now, windowEnd: now.addingTimeInterval(5)),
        ]
        let rooms = [Room(id: Fixtures.kitchenID, name: "Kitchen", lastTendedAt: now)]
        let household = Household(tasks: tasks, rooms: rooms)
        let zone = try SelectionFixtures.zone(example.zoneID)
        let calendar = SelectionFixtures.gregorian(in: zone)
        let result = Rescheduler.reschedule(household, at: now, calendar: calendar, timeZone: zone)
        #expect(result.rooms == rooms && result.schemaVersion == household.schemaVersion)
        #expect(result.tasks.map(\.id) == tasks.map(\.id))
        #expect(result.tasks == tasks.map {
            Rescheduler.reschedule($0, at: now, calendar: calendar, timeZone: zone).task
        })
    }

    @Test("Design list: RescheduleOutcome has exactly the five reason codes")
    func outcomeCodes() {
        #expect(RescheduleOutcome.allCases == [.unchanged, .restEnded, .lightened, .broughtBackGently,
                                               .movedToNextWindow])
    }
}
