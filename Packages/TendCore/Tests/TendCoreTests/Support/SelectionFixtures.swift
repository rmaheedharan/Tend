// Fixtures for the selector and slot-calendar tests (WI-M1-03). Everything is injected: named time zones, a Gregorian
// calendar built here, fixed instants. No `Date()`, no device calendar or time zone (CLAUDE.md §3).

import Foundation
import Testing
import TendCore

enum SelectionFixtures {
    struct UnknownZone: Error, CustomStringConvertible {
        var identifier: String
        var description: String { "time zone \(identifier) is not in tzdata" }
    }

    struct UnresolvableLocalTime: Error {}

    static func zone(_ identifier: String) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else { throw UnknownZone(identifier: identifier) }
        return zone
    }

    static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The instant of a local wall-clock time in `zoneID` (must exist and be unambiguous unless a test says so).
    static func local(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0,
        millisecond: Int = 0, in zoneID: String
    ) throws -> Date {
        let zone = try zone(zoneID)
        var parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        parts.nanosecond = millisecond * 1_000_000
        guard let date = gregorian(in: zone).date(from: parts) else { throw UnresolvableLocalTime() }
        return date
    }

    /// An instant in UTC from an ISO-8601 string with a `Z` suffix.
    static func utc(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = try zone("UTC")
        guard let date = formatter.date(from: text) else { throw UnresolvableLocalTime() }
        return date
    }

    static func moment(
        at now: Date, in zoneID: String, weather: WeatherCondition = .clear, energy: EnergyLevel = .high
    ) throws -> Moment {
        let zone = try zone(zoneID)
        return Moment(now: now, calendar: gregorian(in: zone), timeZone: zone, weather: weather, energy: energy)
    }

    /// A task that is valid at `now` in every respect a test does not override: active, a window open from a day
    /// before to a day after `now`, every daypart and weekday allowed, low effort, not weather-dependent.
    static func openTask(
        id: Int = 1,
        around now: Date,
        effort: Effort = .low,
        isCritical: Bool = false,
        isDeepClean: Bool = false,
        isWeatherDependent: Bool = false,
        allowedDayparts: Set<Daypart> = Set(Daypart.allCases),
        allowedWeekdays: Set<Weekday> = Set(Weekday.allCases),
        windowStart: Date? = nil,
        windowEnd: Date? = nil,
        state: TaskState = .active
    ) throws -> HouseholdTask {
        try Fixtures.task(
            id: Fixtures.id(id), effort: effort, isCritical: isCritical, isDeepClean: isDeepClean,
            isWeatherDependent: isWeatherDependent, allowedDayparts: allowedDayparts, allowedWeekdays: allowedWeekdays,
            windowStart: windowStart ?? now.addingTimeInterval(-86_400),
            windowEnd: windowEnd ?? now.addingTimeInterval(86_400),
            state: state
        )
    }

    /// Validity through the public API only: a one-task selection is non-empty exactly when the task is valid.
    static func isSelected(_ task: HouseholdTask, in moment: Moment) -> Bool {
        let selection = NowSelector.select(from: [task], in: moment)
        return selection.items == [task]
    }
}
