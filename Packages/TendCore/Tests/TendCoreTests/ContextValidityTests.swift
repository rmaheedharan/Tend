// Context filter: energy, daypart, weekday, weather, state and window (AC-M1-08…12; FR-B1; brief Definitions,
// Q1, Q2, Q3, Q11, Q12, Q13). Validity is observed through the public API: a one-task selection holds the task exactly
// when it is contextually valid. Each expected value is written out by hand from the brief, and the independent oracle
// (AC-M1-14) is checked against the same table, so the oracle is itself tested.

import Foundation
import Testing
import TendCore

@Suite("Context filter (AC-M1-08…12)")
struct ContextValidityTests {
    static let berlin = "Europe/Berlin"

    /// Wednesday 18 November 2026, 10:00 in Berlin: morning, mid-week.
    static func wednesdayMorning() throws -> Date {
        try SelectionFixtures.local(2026, 11, 18, 10, in: berlin)
    }

    static func check(_ task: HouseholdTask, in moment: Moment, expected: Bool, _ comment: Comment) {
        #expect(SelectionFixtures.isSelected(task, in: moment) == expected, comment)
        #expect(ContextOracle.isValid(task, in: ContextOracle.Context(moment)) == expected, "oracle: \(comment)")
    }

    // MARK: AC-M1-08

    enum EffortProfile: String, CaseIterable, Sendable {
        case low, normal, high, highDeepCleanInMaintenance
    }

    /// Brief Q1, written out: [energy: [low, normal, high, high deep clean in maintenance]].
    static let energyTable: [EnergyLevel: [EffortProfile: Bool]] = [
        .low: [.low: true, .normal: false, .high: false, .highDeepCleanInMaintenance: true],
        .normal: [.low: true, .normal: true, .high: false, .highDeepCleanInMaintenance: true],
        .high: [.low: true, .normal: true, .high: true, .highDeepCleanInMaintenance: true],
    ]

    @Test("AC-M1-08: low energy accepts only low effort (incl. maintenance), normal adds normal, high accepts all",
          arguments: EnergyLevel.allCases, EffortProfile.allCases)
    func energyMatch(energy: EnergyLevel, profile: EffortProfile) throws {
        let now = try Self.wednesdayMorning()
        let task: HouseholdTask = switch profile {
        case .low: try SelectionFixtures.openTask(around: now, effort: .low)
        case .normal: try SelectionFixtures.openTask(around: now, effort: .normal)
        case .high: try SelectionFixtures.openTask(around: now, effort: .high)
        case .highDeepCleanInMaintenance:
            try SelectionFixtures.openTask(around: now, effort: .high, isDeepClean: true, state: .maintenance)
        }
        guard let expected = Self.energyTable[energy]?[profile] else {
            Issue.record("no table entry for \(energy), \(profile)")
            return
        }
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin, energy: energy)
        Self.check(task, in: moment, expected: expected, "energy \(energy), task \(profile)")
        if profile == .highDeepCleanInMaintenance {
            #expect(task.effort == .high, "stored effort is unchanged")
        }
    }

    // MARK: AC-M1-09

    struct BoundaryCase: Sendable, CustomTestStringConvertible {
        var hour: Int, minute: Int, second: Int, millisecond: Int
        var daypart: Daypart
        var testDescription: String {
            func pad(_ value: Int, _ width: Int) -> String {
                let text = String(value)
                return String(repeating: "0", count: max(0, width - text.count)) + text
            }
            return "\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2)).\(pad(millisecond, 3)) → \(daypart.rawValue)"
        }
    }

    static let boundaryCases: [BoundaryCase] = [
        BoundaryCase(hour: 4, minute: 59, second: 0, millisecond: 0, daypart: .night),
        BoundaryCase(hour: 4, minute: 59, second: 59, millisecond: 999, daypart: .night),
        BoundaryCase(hour: 5, minute: 0, second: 0, millisecond: 0, daypart: .morning),
        BoundaryCase(hour: 11, minute: 59, second: 0, millisecond: 0, daypart: .morning),
        BoundaryCase(hour: 11, minute: 59, second: 59, millisecond: 999, daypart: .morning),
        BoundaryCase(hour: 12, minute: 0, second: 0, millisecond: 0, daypart: .afternoon),
        BoundaryCase(hour: 16, minute: 59, second: 0, millisecond: 0, daypart: .afternoon),
        BoundaryCase(hour: 16, minute: 59, second: 59, millisecond: 999, daypart: .afternoon),
        BoundaryCase(hour: 17, minute: 0, second: 0, millisecond: 0, daypart: .evening),
        BoundaryCase(hour: 21, minute: 59, second: 0, millisecond: 0, daypart: .evening),
        BoundaryCase(hour: 21, minute: 59, second: 59, millisecond: 999, daypart: .evening),
        BoundaryCase(hour: 22, minute: 0, second: 0, millisecond: 0, daypart: .night),
    ]

    @Test("AC-M1-09: at each daypart boundary a task is valid exactly when the local daypart is allowed; default dayparts are quiet at night",
          arguments: boundaryCases)
    func daypartBoundaries(boundary: BoundaryCase) throws {
        let now = try SelectionFixtures.local(2026, 11, 18, boundary.hour, boundary.minute, boundary.second,
                                              millisecond: boundary.millisecond, in: Self.berlin)
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        for daypart in Daypart.allCases {
            let task = try SelectionFixtures.openTask(around: now, allowedDayparts: [daypart])
            Self.check(task, in: moment, expected: daypart == boundary.daypart,
                       "\(boundary.testDescription), task allows only \(daypart)")
        }
        // Every non-empty daypart set: valid exactly when it contains the local daypart.
        for dayparts in Fixtures.nonEmptySubsets(of: Daypart.allCases) {
            let task = try SelectionFixtures.openTask(around: now, allowedDayparts: dayparts)
            Self.check(task, in: moment, expected: dayparts.contains(boundary.daypart),
                       "\(boundary.testDescription), task allows \(dayparts.map(\.rawValue).sorted())")
        }
        let quietAtNight = try SelectionFixtures.openTask(around: now, allowedDayparts: Daypart.defaultAllowed)
        Self.check(quietAtNight, in: moment, expected: boundary.daypart != .night,
                   "\(boundary.testDescription), default dayparts")
    }

    @Test("AC-M1-09: one instant in two injected time zones follows each zone's local daypart")
    func daypartFollowsInjectedZone() throws {
        // 2026-11-18T10:00Z is 19:00 (evening) in Tokyo and 02:00 (night) in Los Angeles.
        let instant = try SelectionFixtures.utc("2026-11-18T10:00:00Z")
        let tokyo = try SelectionFixtures.moment(at: instant, in: "Asia/Tokyo")
        let losAngeles = try SelectionFixtures.moment(at: instant, in: "America/Los_Angeles")
        let eveningOnly = try SelectionFixtures.openTask(around: instant, allowedDayparts: [.evening])
        let nightOnly = try SelectionFixtures.openTask(id: 2, around: instant, allowedDayparts: [.night])
        let quiet = try SelectionFixtures.openTask(id: 3, around: instant, allowedDayparts: Daypart.defaultAllowed)
        Self.check(eveningOnly, in: tokyo, expected: true, "evening-only in Tokyo (19:00)")
        Self.check(eveningOnly, in: losAngeles, expected: false, "evening-only in Los Angeles (02:00)")
        Self.check(nightOnly, in: tokyo, expected: false, "night-only in Tokyo (19:00)")
        Self.check(nightOnly, in: losAngeles, expected: true, "night-only in Los Angeles (02:00)")
        Self.check(quiet, in: tokyo, expected: true, "default dayparts in Tokyo (19:00)")
        Self.check(quiet, in: losAngeles, expected: false, "default dayparts in Los Angeles (02:00)")
    }

    @Test("AC-M1-09: the injected time zone wins over the time zone carried by the injected calendar")
    func injectedZoneWinsOverCalendarZone() throws {
        let instant = try SelectionFixtures.utc("2026-11-18T10:00:00Z")
        let tokyoCalendar = SelectionFixtures.gregorian(in: try SelectionFixtures.zone("Asia/Tokyo"))
        let losAngeles = try SelectionFixtures.zone("America/Los_Angeles")
        let moment = Moment(now: instant, calendar: tokyoCalendar, timeZone: losAngeles, weather: .clear, energy: .high)
        #expect(moment.calendar.timeZone == losAngeles)
        let nightOnly = try SelectionFixtures.openTask(around: instant, allowedDayparts: [.night])
        Self.check(nightOnly, in: moment, expected: true, "Los Angeles 02:00 is night, Tokyo 19:00 is not")
    }

    // MARK: AC-M1-10

    struct WeekdayCase: Sendable, CustomTestStringConvertible {
        var label: String
        var day: Int, hour: Int, minute: Int, second: Int, millisecond: Int
        var expected: Bool
        var testDescription: String { "\(label) → \(expected ? "valid" : "not valid")" }
    }

    /// Week of Monday 16 to Sunday 22 November 2026 (Berlin), plus Monday 23. Weekend-only task, all four dayparts.
    static let weekdayCases: [WeekdayCase] = [
        WeekdayCase(label: "Monday 10:00", day: 16, hour: 10, minute: 0, second: 0, millisecond: 0, expected: false),
        WeekdayCase(label: "Tuesday 10:00", day: 17, hour: 10, minute: 0, second: 0, millisecond: 0, expected: false),
        WeekdayCase(label: "Wednesday 10:00", day: 18, hour: 10, minute: 0, second: 0, millisecond: 0, expected: false),
        WeekdayCase(label: "Thursday 10:00", day: 19, hour: 10, minute: 0, second: 0, millisecond: 0, expected: false),
        WeekdayCase(label: "Friday 10:00", day: 20, hour: 10, minute: 0, second: 0, millisecond: 0, expected: false),
        WeekdayCase(label: "Saturday 10:00", day: 21, hour: 10, minute: 0, second: 0, millisecond: 0, expected: true),
        WeekdayCase(label: "Sunday 10:00", day: 22, hour: 10, minute: 0, second: 0, millisecond: 0, expected: true),
        WeekdayCase(label: "Friday 23:00 (Friday night)", day: 20, hour: 23, minute: 0, second: 0, millisecond: 0,
                    expected: false),
        WeekdayCase(label: "Saturday 01:00 (Friday night)", day: 21, hour: 1, minute: 0, second: 0, millisecond: 0,
                    expected: false),
        WeekdayCase(label: "Saturday 04:59:59.999 (Friday night)", day: 21, hour: 4, minute: 59, second: 59,
                    millisecond: 999, expected: false),
        WeekdayCase(label: "Saturday 05:00 (Saturday morning)", day: 21, hour: 5, minute: 0, second: 0, millisecond: 0,
                    expected: true),
        WeekdayCase(label: "Saturday 23:00 (Saturday night)", day: 21, hour: 23, minute: 0, second: 0, millisecond: 0,
                    expected: true),
        WeekdayCase(label: "Monday 01:00 (Sunday night)", day: 23, hour: 1, minute: 0, second: 0, millisecond: 0,
                    expected: true),
        WeekdayCase(label: "Monday 04:59:59.999 (Sunday night)", day: 23, hour: 4, minute: 59, second: 59,
                    millisecond: 999, expected: true),
        WeekdayCase(label: "Monday 05:00 (Monday morning)", day: 23, hour: 5, minute: 0, second: 0, millisecond: 0,
                    expected: false),
    ]

    @Test("AC-M1-10: a weekend-only task is valid on Saturday and Sunday only; the night slot belongs to the day it starts",
          arguments: weekdayCases)
    func weekdays(weekdayCase: WeekdayCase) throws {
        let now = try SelectionFixtures.local(2026, 11, weekdayCase.day, weekdayCase.hour, weekdayCase.minute,
                                              weekdayCase.second, millisecond: weekdayCase.millisecond, in: Self.berlin)
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let weekend = try SelectionFixtures.openTask(
            around: now, allowedDayparts: Set(Daypart.allCases), allowedWeekdays: [.saturday, .sunday])
        Self.check(weekend, in: moment, expected: weekdayCase.expected, "\(weekdayCase.label)")
    }

    @Test("AC-M1-10: an instant that is Sunday 10:00 in one injected zone and Monday in another follows the injected zone")
    func weekdayFollowsInjectedZone() throws {
        // Sunday 22 November 2026, 10:00 in Los Angeles (18:00Z) is Monday 23 November, 07:00 in Auckland.
        let instant = try SelectionFixtures.local(2026, 11, 22, 10, in: "America/Los_Angeles")
        #expect(instant == (try SelectionFixtures.local(2026, 11, 23, 7, in: "Pacific/Auckland")))
        let weekend = try SelectionFixtures.openTask(
            around: instant, allowedDayparts: Set(Daypart.allCases), allowedWeekdays: [.saturday, .sunday])
        Self.check(weekend, in: try SelectionFixtures.moment(at: instant, in: "America/Los_Angeles"), expected: true,
                   "Sunday 10:00 in Los Angeles")
        Self.check(weekend, in: try SelectionFixtures.moment(at: instant, in: "Pacific/Auckland"), expected: false,
                   "Monday 07:00 in Auckland")
    }

    // MARK: AC-M1-11

    /// Brief Q3, written out.
    static let weatherTable: [WeatherCondition: Bool] = [
        .clear: true, .cloudy: true, .wet: false, .severe: false, .unknown: false,
    ]

    @Test("AC-M1-11: a weather-dependent task is valid only in clear or cloudy weather; others ignore the weather",
          arguments: WeatherCondition.allCases)
    func weather(weather: WeatherCondition) throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin, weather: weather)
        let outdoor = try SelectionFixtures.openTask(around: now, isWeatherDependent: true)
        let indoor = try SelectionFixtures.openTask(around: now, isWeatherDependent: false)
        guard let expected = Self.weatherTable[weather] else {
            Issue.record("no table entry for \(weather)")
            return
        }
        Self.check(outdoor, in: moment, expected: expected,
                   "weather-dependent task, weather \(weather)")
        Self.check(indoor, in: moment, expected: true, "task that ignores the weather, weather \(weather)")
    }

    // MARK: AC-M1-12

    struct StateWindowCase: Sendable, CustomTestStringConvertible {
        var label: String
        var expected: Bool
        var testDescription: String { "(\(label)) → \(expected ? "valid" : "not valid")" }
    }

    static let stateWindowCases: [StateWindowCase] = [
        StateWindowCase(label: "a: completed", expected: false),
        StateWindowCase(label: "b: deferred until now + 1 s (resting)", expected: false),
        StateWindowCase(label: "c: deferred until now (rest over)", expected: true),
        StateWindowCase(label: "d: deferred until now - 1 h (rest over)", expected: true),
        StateWindowCase(label: "e: windowStart == now", expected: true),
        StateWindowCase(label: "f: windowStart == now + 1 s", expected: false),
        StateWindowCase(label: "g: windowEnd == now (window ended)", expected: false),
        StateWindowCase(label: "h: windowEnd == now + 1 s", expected: true),
        StateWindowCase(label: "i: windowEnd == now - 1 h (window ended)", expected: false),
    ]

    @Test("AC-M1-12: state and half-open window boundaries decide validity exactly as the brief lists",
          arguments: stateWindowCases)
    func stateAndWindow(stateWindowCase: StateWindowCase) throws {
        let now = try Self.wednesdayMorning().addingTimeInterval(0.25)  // a sub-second `now`
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let day: TimeInterval = 86_400
        let task: HouseholdTask = switch stateWindowCase.label.prefix(1) {
        case "a": try SelectionFixtures.openTask(around: now, state: .completed)
        case "b": try SelectionFixtures.openTask(around: now, state: .deferred(until: now.addingTimeInterval(1)))
        case "c": try SelectionFixtures.openTask(around: now, state: .deferred(until: now))
        case "d": try SelectionFixtures.openTask(around: now, state: .deferred(until: now.addingTimeInterval(-3_600)))
        case "e": try SelectionFixtures.openTask(around: now, windowStart: now)
        case "f": try SelectionFixtures.openTask(around: now, windowStart: now.addingTimeInterval(1))
        case "g": try SelectionFixtures.openTask(around: now, windowStart: now.addingTimeInterval(-day), windowEnd: now)
        case "h": try SelectionFixtures.openTask(around: now, windowEnd: now.addingTimeInterval(1))
        default: try SelectionFixtures.openTask(around: now, windowStart: now.addingTimeInterval(-day),
                                                windowEnd: now.addingTimeInterval(-3_600))
        }
        Self.check(task, in: moment, expected: stateWindowCase.expected, "\(stateWindowCase.label)")
    }

    @Test("AC-M1-12: maintenance and resurfaced tasks with an open window are valid; the selector does not change them")
    func maintenanceAndResurfacedAreOfferable() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin, energy: .low)
        let lighter = try SelectionFixtures.openTask(around: now, effort: .high, isDeepClean: true, state: .maintenance)
        let back = try SelectionFixtures.openTask(id: 2, around: now, isCritical: true, state: .resurfaced)
        Self.check(lighter, in: moment, expected: true, "deep clean in maintenance at low energy")
        Self.check(back, in: moment, expected: true, "critical task brought back gently")
    }
}
