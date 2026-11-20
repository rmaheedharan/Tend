import Foundation

// Slot calendar (brief "Definitions": Daypart, Slot, `E(a, D)`; Q2, Q11, Q14; FR-B1, FR-B2; risk R-3).
//
// Every wall-clock time is resolved in the **injected** calendar and time zone, never the device's. A local time that
// does not exist (DST spring-forward) resolves to the next existing instant (`.nextTime`); a local time that occurs
// twice (DST fall-back) resolves to its first occurrence (`.first`). Slots are half-open `[start, end)` and tile time
// without gaps: the night slot of day `d` ends exactly where the morning slot of day `d + 1` starts.

extension Daypart {
    /// The local wall-clock hour at which this daypart starts (brief Q2). Each daypart ends where the next one starts;
    /// night ends at 05:00 on the next day.
    var startHour: Int {
        switch self {
        case .morning: 5
        case .afternoon: 12
        case .evening: 17
        case .night: 22
        }
    }
}

/// One daypart on one calendar day, e.g. "Saturday morning" (brief "Slot").
/// The night slot of day `d` runs from 22:00 on `d` to 05:00 on `d + 1` and belongs to day `d`'s weekday (Q11).
struct Slot: Hashable, Sendable {
    let daypart: Daypart
    /// The weekday of the day that owns the slot (for night: the day the night starts on).
    let weekday: Weekday
    let start: Date
    let end: Date

    /// `start <= instant < end` (half-open).
    func contains(_ instant: Date) -> Bool {
        start <= instant && instant < end
    }

    func isAllowed(dayparts: Set<Daypart>, weekdays: Set<Weekday>) -> Bool {
        dayparts.contains(daypart) && weekdays.contains(weekday)
    }
}

/// Slot arithmetic on an injected calendar and time zone. Internal: the public entry points are `NowSelector` and
/// `HouseholdTask.nextEligibleWindow(from:duration:calendar:timeZone:)`.
struct SlotCalendar: Sendable {
    /// The injected calendar with the injected time zone applied (the time zone argument wins over the calendar's own).
    let calendar: Calendar

    /// How many days `nextAllowedStart` looks ahead. Allowed dayparts and weekdays are never empty (AC-M1-25), so an
    /// allowed slot always starts within 8 days; 15 leaves room for calendars that skip a whole day (e.g. Samoa, 2011).
    static let searchHorizonDays = 15

    init(calendar: Calendar, timeZone: TimeZone) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The instant at `hour`:00:00 local on the day of `dayAnchor`, with the brief's DST policy (Q11).
    func wallClock(hour: Int, onDayOf dayAnchor: Date) -> Date? {
        calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: dayAnchor,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
        )
    }

    /// Local noon of the calendar day containing `instant`. Noon exists on every day, so it is a safe anchor for day
    /// arithmetic across DST changes.
    func noon(ofDayContaining instant: Date) -> Date? {
        wallClock(hour: 12, onDayOf: instant)
    }

    /// Local noon `days` calendar days after the day of `noon`.
    func noon(_ days: Int, daysAfter noon: Date) -> Date? {
        guard let shifted = calendar.date(byAdding: .day, value: days, to: noon) else { return nil }
        return self.noon(ofDayContaining: shifted)
    }

    func weekday(ofDayOf instant: Date) -> Weekday? {
        let number = calendar.component(.weekday, from: instant)  // 1 = Sunday … 7 = Saturday
        let all = Weekday.allCases
        guard (1...all.count).contains(number) else { return nil }
        return all[number - 1]
    }

    /// The four slots owned by the day of `dayNoon`, in time order: morning, afternoon, evening, night.
    func slots(ofDayOf dayNoon: Date) -> [Slot] {
        guard
            let weekday = weekday(ofDayOf: dayNoon),
            let nextNoon = noon(1, daysAfter: dayNoon),
            let nextMorning = wallClock(hour: Daypart.morning.startHour, onDayOf: nextNoon)
        else { return [] }
        let dayparts = Daypart.allCases
        var starts: [Date] = []
        for daypart in dayparts {
            guard let start = wallClock(hour: daypart.startHour, onDayOf: dayNoon) else { return [] }
            starts.append(start)
        }
        starts.append(nextMorning)
        return dayparts.indices.map { index in
            Slot(daypart: dayparts[index], weekday: weekday, start: starts[index], end: starts[index + 1])
        }
    }

    /// The slot that contains `instant`: one of its own day's slots, or the previous day's night (before 05:00).
    func slot(containing instant: Date) -> Slot? {
        guard let dayNoon = noon(ofDayContaining: instant) else { return nil }
        if let slot = slots(ofDayOf: dayNoon).first(where: { $0.contains(instant) }) {
            return slot
        }
        guard let previousNoon = noon(-1, daysAfter: dayNoon) else { return nil }
        return slots(ofDayOf: previousNoon).first(where: { $0.contains(instant) })
    }

    /// `s` in the brief's `E(a, D)`: `anchor` itself if it lies in an allowed slot, otherwise the start of the earliest
    /// allowed slot that begins after `anchor`. `nil` only if the calendar cannot resolve a day within the horizon.
    func nextAllowedStart(from anchor: Date, dayparts: Set<Daypart>, weekdays: Set<Weekday>) -> Date? {
        guard let anchorNoon = noon(ofDayContaining: anchor) else { return nil }
        // Start one day early: before 05:00 the anchor sits in the previous day's night slot.
        for offset in -1...Self.searchHorizonDays {
            guard let dayNoon = noon(offset, daysAfter: anchorNoon) else { return nil }
            for slot in slots(ofDayOf: dayNoon) where slot.isAllowed(dayparts: dayparts, weekdays: weekdays) {
                if slot.contains(anchor) { return anchor }
                if slot.start > anchor { return slot.start }
            }
        }
        return nil
    }
}

// MARK: - Next eligible window, `E(a, D)` (public; used by the rescheduler and completion in WI-M1-04)

extension HouseholdTask {
    /// The brief's next eligible window `E(a, D)` for this task's allowed dayparts and weekdays (Q14):
    /// `windowStart = s`, where `s = anchor` if `anchor` lies in an allowed slot, otherwise `s` is the start of the
    /// earliest allowed slot that begins after `anchor`; `windowEnd = s + duration`.
    ///
    /// Slots are resolved in the injected `calendar` and `timeZone` (the time zone wins over the calendar's own), with
    /// nonexistent local times moved to the next instant and repeated ones taken at their first occurrence (Q11).
    /// Pure: the task is not changed; nothing about earlier windows is kept (design D-2).
    ///
    /// Allowed dayparts and weekdays are never empty (AC-M1-25), so an allowed slot always starts within 8 days. If the
    /// calendar cannot resolve a day at all, the window starts at `anchor` (a calm "from now" rather than a crash).
    public func nextEligibleWindow(
        from anchor: Date,
        duration: TimeInterval,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> (windowStart: Date, windowEnd: Date) {
        let slots = SlotCalendar(calendar: calendar, timeZone: timeZone)
        let start = slots.nextAllowedStart(from: anchor, dayparts: allowedDayparts, weekdays: allowedWeekdays) ?? anchor
        return (start, start.addingTimeInterval(duration))
    }
}
