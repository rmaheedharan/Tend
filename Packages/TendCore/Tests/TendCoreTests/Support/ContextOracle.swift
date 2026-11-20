// Independent oracle for "contextually valid at now", the AC-M1-16 ranking and `E(a, D)` (AC-M1-14, AC-M1-15,
// AC-M1-16; risk R-4).
//
// Written straight from the brief's Definitions, apart from the production code: it calls no `TendCore` function or
// internal helper (only public stored properties of `HouseholdTask`), and it uses a *different* method for every step:
// - daypart and owning weekday come from the local hour and weekday components (`Calendar.dateComponents`), with
//   "before 05:00 belongs to the previous weekday" done by modular arithmetic. Production builds slot intervals from
//   resolved wall-clock boundaries (`date(bySettingHour:…)`) and checks containment.
// - effective state, window, energy and weather are written as explicit tables here.
// - ranking is a full sort on a tuple key, then a prefix. Production keeps a running top three.
// - `E(a, D)` is a brute-force forward scan over 15-minute instants. Production walks slot boundaries.

import Foundation
import TendCore

enum ContextOracle {
    /// Inputs of one moment, as plain values (the oracle does not use `Moment` beyond reading its fields).
    struct Context {
        var now: Date
        var calendar: Calendar  // its timeZone is set to `timeZone`
        var timeZone: TimeZone
        var weather: WeatherCondition
        var energy: EnergyLevel

        init(now: Date, calendar: Calendar, timeZone: TimeZone, weather: WeatherCondition, energy: EnergyLevel) {
            var calendar = calendar
            calendar.timeZone = timeZone
            self.now = now
            self.calendar = calendar
            self.timeZone = timeZone
            self.weather = weather
            self.energy = energy
        }

        init(_ moment: Moment) {
            self.init(now: moment.now, calendar: moment.calendar, timeZone: moment.timeZone,
                      weather: moment.weather, energy: moment.energy)
        }
    }

    // MARK: Slot membership (brief "Daypart", "Slot", Q2, Q11)

    /// Daypart names by local hour 0…23, written out as a table (brief Q2).
    static let daypartByHour: [Daypart] =
        Array(repeating: .night, count: 5)          // 00–04
        + Array(repeating: .morning, count: 7)      // 05–11
        + Array(repeating: .afternoon, count: 5)    // 12–16
        + Array(repeating: .evening, count: 5)      // 17–21
        + Array(repeating: .night, count: 2)        // 22–23

    /// Gregorian weekday numbers (1 = Sunday) to names, written out.
    static let weekdayByNumber: [Int: Weekday] = [
        1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday, 5: .thursday, 6: .friday, 7: .saturday,
    ]

    /// The daypart of `instant` and the weekday of the day that owns its slot (night before 05:00 → previous day).
    static func slotLabel(of instant: Date, calendar: Calendar) -> (daypart: Daypart, weekday: Weekday)? {
        let parts = calendar.dateComponents([.hour, .weekday], from: instant)
        guard let hour = parts.hour, let weekdayNumber = parts.weekday, (0...23).contains(hour) else { return nil }
        let daypart = daypartByHour[hour]
        let owningNumber = hour < 5 ? ((weekdayNumber + 5) % 7) + 1 : weekdayNumber  // previous day for 00–04
        guard let weekday = weekdayByNumber[owningNumber] else { return nil }
        return (daypart, weekday)
    }

    static func liesInAllowedSlot(_ task: HouseholdTask, at instant: Date, calendar: Calendar) -> Bool {
        guard let label = slotLabel(of: instant, calendar: calendar) else { return false }
        return task.allowedDayparts.contains(label.daypart) && task.allowedWeekdays.contains(label.weekday)
    }

    // MARK: Validity (brief "Contextually valid at now", Q1, Q3, Q12, Q13)

    /// Energy → accepted efforts (brief Q1), as a table.
    static let acceptedEfforts: [EnergyLevel: Set<Effort>] = [
        .low: [.low],
        .normal: [.low, .normal],
        .high: [.low, .normal, .high],
    ]

    /// Weather values under which a weather-dependent task may be offered (brief Q3).
    static let safeWeather: Set<WeatherCondition> = [.clear, .cloudy]

    static func isValid(_ task: HouseholdTask, in context: Context) -> Bool {
        let now = context.now
        let stateQualifies: Bool
        switch task.state {
        case .active, .maintenance, .resurfaced: stateQualifies = true
        case .deferred(let until): stateQualifies = until <= now  // rest over → treated as active
        case .completed: stateQualifies = false
        }
        guard stateQualifies else { return false }
        guard task.windowStart <= now, now < task.windowEnd else { return false }
        guard liesInAllowedSlot(task, at: now, calendar: context.calendar) else { return false }
        let effort: Effort = task.state == .maintenance ? .low : task.effort
        guard acceptedEfforts[context.energy, default: []].contains(effort) else { return false }
        if task.isWeatherDependent && !safeWeather.contains(context.weather) { return false }
        return true
    }

    // MARK: Ranking (AC-M1-16, Q7)

    /// The AC-M1-16 key as a comparable tuple: (resurfaced ? 0 : 1, windowEnd, critical ? 0 : 1, uuidString).
    static func rankKey(_ task: HouseholdTask) -> (Int, Date, Int, String) {
        (task.state == .resurfaced ? 0 : 1, task.windowEnd, task.isCritical ? 0 : 1, task.id.uuidString)
    }

    static func ranked(_ tasks: [HouseholdTask]) -> [HouseholdTask] {
        tasks.sorted { rankKey($0) < rankKey($1) }
    }

    /// The oracle's Now selection: every valid task, fully sorted by the AC-M1-16 key, first `min(3, n)`.
    static func expectedSelection(from tasks: [HouseholdTask], in context: Context) -> (valid: Int, items: [HouseholdTask]) {
        let valid = tasks.filter { isValid($0, in: context) }
        return (valid.count, Array(ranked(valid).prefix(3)))
    }

    // MARK: `E(a, D)` by brute force (brief "Next eligible window", Q14)

    /// Every allowed slot starts at a local hh:00:00. All zones used in tests have offsets in whole quarter hours (and
    /// DST changes on quarter hours), so every slot start is a multiple of 15 minutes since the reference date.
    static let step: TimeInterval = 900

    /// `s`: `anchor` if it is in an allowed slot, else the first 15-minute instant after `anchor` that is.
    static func nextAllowedStart(for task: HouseholdTask, from anchor: Date, calendar: Calendar) -> Date? {
        if liesInAllowedSlot(task, at: anchor, calendar: calendar) { return anchor }
        let base = anchor.timeIntervalSinceReferenceDate
        var tick = (base / step).rounded(.down) * step
        if tick <= base { tick += step }
        for _ in 0..<(16 * 96) {
            let instant = Date(timeIntervalSinceReferenceDate: tick)
            if liesInAllowedSlot(task, at: instant, calendar: calendar) { return instant }
            tick += step
        }
        return nil
    }
}
