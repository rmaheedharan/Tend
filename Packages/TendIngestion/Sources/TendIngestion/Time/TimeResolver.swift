import Foundation
import TendCore

/// What the Q6 resolver computed for one hint (AC-M2-03). Empty `allowedDayparts` or `allowedWeekdays` mean "∅": the
/// resolver leaves the set empty and Q5 step 3 fills the default (`Daypart.defaultAllowed`, all seven weekdays).
/// `recurrenceIntervalDays` is the raw interval; Q5 step 6 (`RecurrenceSettlement`) decides whether the item keeps it.
public struct TimeResolution: Hashable, Sendable {

    /// Why a window came from the hint or from the T1 fallback (counted per repair rule by AC-M2-02).
    public enum Basis: Hashable, Sendable {
        /// The hint was usable and its row gave the window.
        case hint
        /// There was no hint at all (T1).
        case noHint
        /// The hint was unusable, so it resolves exactly as no hint (plan "Invalid hints are 'no hint'").
        case fallback(FallbackReason)
    }

    /// Why a hint was unusable.
    public enum FallbackReason: Hashable, Sendable {
        /// The anchor was outside the list.
        case unrecognizedAnchor
        /// The anchor's required field (weekday, month, season or count) was absent.
        case requiredFieldAbsent
        /// The required field was outside its range (month 1…12, `inDays` 1…366, `inWeeks` 1…52).
        case fieldOutOfRange
        /// The computed window had end ≤ start.
        case emptyWindow
        /// The computed window started before `now`, more than 366 days after `now`, or lasted more than 366 days.
        case windowOutOfRange
        /// The injected calendar could not resolve a needed day, or `now` was not finite.
        case calendarUnresolved
    }

    public let windowStart: Date
    public let windowEnd: Date
    public let allowedDayparts: Set<Daypart>
    public let allowedWeekdays: Set<Weekday>
    public let recurrenceIntervalDays: Int?
    /// Diagnostic only: which rule gave the window, or the fallback reason (WI-M2-05 counts repairs per rule for
    /// AC-M2-02). It is not part of the AC-M2-03 table check (plan).
    public let basis: Basis
    /// `true` when `allowedWeekdays` is R5's {W}, which Q5 step 6 drops together with the interval (PO Q-T1).
    public let weekdaysFollowRepeat: Bool

    public init(
        windowStart: Date,
        windowEnd: Date,
        allowedDayparts: Set<Daypart>,
        allowedWeekdays: Set<Weekday>,
        recurrenceIntervalDays: Int?,
        basis: Basis,
        weekdaysFollowRepeat: Bool = false
    ) {
        self.weekdaysFollowRepeat = weekdaysFollowRepeat
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.allowedDayparts = allowedDayparts
        self.allowedWeekdays = allowedWeekdays
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.basis = basis
    }
}

/// The deterministic Q6 time resolver (AC-M2-03, FR-A1; brief Q6 and T-08; plan "Q6 time-phrase table" T1–T15 and
/// R1–R7).
///
/// Every local time is resolved in the **injected** calendar and time zone (the time zone wins over the calendar's own).
/// Day arithmetic is anchored at local noon, as in M1, and wall-clock times use the M1 Q11 policy: a time that does not
/// exist moves to the next existing instant (`.nextTime`), a repeated one takes its first occurrence (`.first`). So
/// `mid(d)` is the first instant of day `d`, and a day is 23 h or 25 h long on a DST day (Q6(e)). The week starts on
/// Monday whatever the calendar's `firstWeekday` (Q6(a)): no rule below reads `firstWeekday`.
public struct TimeResolver: Sendable {

    /// `7d` in rows T1 and T15: 604,800 absolute seconds (plan Notation).
    public static let fallbackDuration: TimeInterval = 7 * 86_400
    /// The Q5 step 5 range limit: 366 × 86,400 s.
    public static let rangeLimit: TimeInterval = 366 * 86_400
    /// T9 and T10: on a Sunday at or after this local hour, "this weekend" and "this week" mean the coming ones.
    static let sundayEveningHour = 18
    /// R5 (PO Q-T1): the repeat units with which a weekday anchor sets weekdays to {W}.
    static let weekdayRepeatUnits: Set<TimeHint.RepeatUnit> = [.week, .month, .year]

    let calendar: Calendar

    public init(calendar: Calendar, timeZone: TimeZone) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Resolves `hint` at `now`. `nil` means the model reported no hint (T1).
    ///
    /// An invalid anchor counts as no anchor (PO Q-T2, 2026-11-21): the window is the T1 window and weekdays are ∅, but
    /// a valid daypart still sets {p} (as T15) and a valid repeat still gives its interval (R1–R4). R5's {W} cannot
    /// apply without a valid weekday. `basis` records the fallback reason. A non-finite `now` is checked first, for a
    /// `nil` hint too, and gives the plain T1 fallback with `calendarUnresolved`.
    public func resolve(_ hint: TimeHint?, now: Date) -> TimeResolution {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return Self.fallback(now: now, basis: .fallback(.calendarUnresolved))
        }
        guard let hint else { return Self.fallback(now: now, basis: .noHint) }
        let interval = Self.interval(of: hint)
        let dayparts = Self.dayparts(of: hint)
        let problem: TimeResolution.FallbackReason?
        let window: (start: Date, end: Date)
        switch self.window(for: hint, now: now) {
        case .unusable(let reason):
            problem = reason
            window = (now, now)
        case .window(let start, let end):
            problem = Self.rangeProblem(start: start, end: end, now: now)
            window = (start, end)
        }
        if let problem {  // the anchor is "no anchor"; the rest of the hint still counts
            return TimeResolution(
                windowStart: now,
                windowEnd: now.addingTimeInterval(Self.fallbackDuration),
                allowedDayparts: dayparts,
                allowedWeekdays: [],
                recurrenceIntervalDays: interval,
                basis: .fallback(problem)
            )
        }
        let weekdays = Self.weekdays(of: hint, hasRepeat: interval != nil)
        return TimeResolution(
            windowStart: window.start,
            windowEnd: window.end,
            allowedDayparts: dayparts,
            allowedWeekdays: weekdays,
            recurrenceIntervalDays: interval,
            basis: .hint,
            weekdaysFollowRepeat: hint.anchor == .weekday && !weekdays.isEmpty
        )
    }

    // MARK: - Dayparts, weekdays, interval

    static func dayparts(of hint: TimeHint) -> Set<Daypart> {
        if hint.anchor == .tonight { return [.evening, .night] }  // T4: a daypart is ignored
        guard let daypart = hint.daypart else { return [] }
        return [daypart]
    }

    static func weekdays(of hint: TimeHint, hasRepeat: Bool) -> Set<Weekday> {
        switch hint.anchor {
        case .thisWeekend:
            return [.saturday, .sunday]  // T9, R6
        case .weekday:
            // R5 (PO Q-T1): a weekday anchor sets {W} only with a week, month or year repeat. A one-off "on Thursday"
            // (T7) and a day repeat ("daily from Thursday") keep ∅.
            guard hasRepeat, let unit = hint.repeatUnit, Self.weekdayRepeatUnits.contains(unit),
                  let weekday = hint.weekday
            else { return [] }
            return [weekday]
        default:
            return []
        }
    }

    /// R1–R4: `repeatEvery × unit days`. `nil` when there is no repeat (`repeatEvery` < 1, or either field absent) or
    /// when the product does not fit in `Int` (then Q5 step 6 makes a recurring item a one-off, as for any value above
    /// 730).
    static func interval(of hint: TimeHint) -> Int? {
        guard let every = hint.repeatEvery, every >= 1, let unit = hint.repeatUnit else { return nil }
        let (days, overflow) = every.multipliedReportingOverflow(by: unit.days)
        return overflow ? nil : days
    }

    // MARK: - The Q5 step 5 range rule

    /// `nil` if `[start, end)` is a usable window at `now`; otherwise why not. In range means
    /// `now ≤ start ≤ now + 366 d` and `start < end ≤ start + 366 d` (366 d = 31,622,400 s).
    static func rangeProblem(start: Date, end: Date, now: Date) -> TimeResolution.FallbackReason? {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite else {
            return .calendarUnresolved
        }
        if end <= start { return .emptyWindow }
        if start < now || start > now.addingTimeInterval(rangeLimit) { return .windowOutOfRange }
        if end > start.addingTimeInterval(rangeLimit) { return .windowOutOfRange }
        return nil
    }

    static func fallback(now: Date, basis: TimeResolution.Basis) -> TimeResolution {
        TimeResolution(
            windowStart: now,
            windowEnd: now.addingTimeInterval(fallbackDuration),
            allowedDayparts: [],
            allowedWeekdays: [],
            recurrenceIntervalDays: nil,
            basis: basis
        )
    }

    // MARK: - Rows T1–T15

    enum Computed {
        case window(Date, Date)
        case unusable(TimeResolution.FallbackReason)
    }

    func window(for hint: TimeHint, now: Date) -> Computed {
        guard let today = noon(ofDayContaining: now) else { return .unusable(.calendarUnresolved) }
        let days = Days(resolver: self, today: today)
        let p = hint.daypart
        switch hint.anchor {
        case .unrecognized:
            return .unusable(.unrecognizedAnchor)

        case .none:  // T1, T15
            return .window(now, now.addingTimeInterval(Self.fallbackDuration))

        case .today:
            guard let p else {  // T2
                return days.span(from: now, toMidnightOf: 1)
            }
            // T3 (P1): today's slot from now; if it has ended, tomorrow's.
            guard let slot = days.slot(p, 0) else { return .unusable(.calendarUnresolved) }
            if slot.end <= now { return days.slotWindow(p, 1) }
            return .window(max(now, slot.start), slot.end)

        case .tonight:  // T4
            guard let end = days.at(Daypart.morning.startHour, 1) else { return .unusable(.calendarUnresolved) }
            return .window(now, end)

        case .tomorrow:  // T5, T6
            return days.dayOrSlot(p, 1)

        case .weekday:  // T7, T8 (P2)
            guard let weekday = hint.weekday else { return .unusable(.requiredFieldAbsent) }
            guard let offset = days.firstOffset(after: 0, weekday: weekday) else {
                return .unusable(.calendarUnresolved)
            }
            return days.dayOrSlot(p, offset)

        case .thisWeekend:  // T9
            return thisWeekend(days: days, daypart: p, now: now)

        case .thisWeek:  // T10 (P3, PO change)
            guard let monday = days.firstOffset(after: 0, weekday: .monday) else {
                return .unusable(.calendarUnresolved)
            }
            if isSundayEvening(now, days: days) { return days.span(midnightOf: monday, toMidnightOf: monday + 7) }
            return days.span(from: now, toMidnightOf: monday)

        case .nextWeek:  // T11: 7 calendar days
            guard let monday = days.firstOffset(after: 0, weekday: .monday) else {
                return .unusable(.calendarUnresolved)
            }
            return days.span(midnightOf: monday, toMidnightOf: monday + 7)

        case .beforeMonth:  // T12
            guard let month = hint.month else { return .unusable(.requiredFieldAbsent) }
            guard (1...12).contains(month) else { return .unusable(.fieldOutOfRange) }
            return before(month: month, now: now)

        case .beforeSeason:  // T13
            guard let season = hint.season else { return .unusable(.requiredFieldAbsent) }
            return before(month: season.startMonth, now: now)

        case .inDays, .inWeeks:  // T14 (P4)
            guard let count = hint.count else { return .unusable(.requiredFieldAbsent) }
            let isDays = hint.anchor == .inDays
            guard (1...(isDays ? 366 : 52)).contains(count) else { return .unusable(.fieldOutOfRange) }
            return days.dayOrSlot(p, isDays ? count : 7 * count)
        }
    }

    /// T9 and its daypart rule (Q6(b), PO 2026-11-21).
    func thisWeekend(days: Days, daypart: Daypart?, now: Date) -> Computed {
        guard let weekday = days.weekday(0) else { return .unusable(.calendarUnresolved) }
        let first: Int
        let last: Int
        switch weekday {
        case .saturday:
            (first, last) = (0, 1)
        case .sunday:
            (first, last) = isSundayEvening(now, days: days) ? (6, 7) : (0, 0)
        default:
            guard let saturday = days.firstOffset(after: 0, weekday: .saturday) else {
                return .unusable(.calendarUnresolved)
            }
            (first, last) = (saturday, saturday + 1)
        }
        guard let daypart else {
            guard let start = first == 0 ? now : days.mid(first), let end = days.mid(last + 1) else {
                return .unusable(.calendarUnresolved)
            }
            return .window(start, end)
        }
        guard let firstSlot = days.slot(daypart, first), let lastSlot = days.slot(daypart, last) else {
            return .unusable(.calendarUnresolved)
        }
        if lastSlot.end <= now {  // e.g. "this weekend in the morning" said on Sunday 15:00: the coming weekend
            guard let comingFirst = days.slot(daypart, 6), let comingLast = days.slot(daypart, 7) else {
                return .unusable(.calendarUnresolved)
            }
            return .window(comingFirst.start, comingLast.end)
        }
        return .window(max(now, firstSlot.start), lastSlot.end)
    }

    /// T12, T13: `[now, b)`, where `b` is the earliest local midnight of the 1st of `month` that is later than `now`
    /// (in the current month that is next year's, Q6(f)).
    func before(month: Int, now: Date) -> Computed {
        let year = calendar.component(.year, from: now)
        for candidateYear in [year, year + 1] {
            let parts = DateComponents(year: candidateYear, month: month, day: 1, hour: 12)
            guard
                let firstNoon = calendar.date(from: parts),
                let boundary = wallClock(hour: 0, onDayOf: firstNoon)
            else { return .unusable(.calendarUnresolved) }
            if boundary > now { return .window(now, boundary) }
        }
        return .unusable(.calendarUnresolved)
    }

    /// T9, T10: `now` is on a Sunday at or after 18:00:00 local wall-clock time.
    func isSundayEvening(_ now: Date, days: Days) -> Bool {
        days.weekday(0) == .sunday && calendar.component(.hour, from: now) >= Self.sundayEveningHour
    }

    // MARK: - Calendar primitives (the M1 slot calendar's rules, re-stated here: TendCore keeps them internal)

    /// `hour`:00:00 local on the day of `dayAnchor`, with the M1 Q11 policy.
    func wallClock(hour: Int, onDayOf dayAnchor: Date) -> Date? {
        calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: dayAnchor,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
        )
    }

    /// Local noon of the day containing `instant`. Noon exists on every day, so it anchors day arithmetic across DST.
    func noon(ofDayContaining instant: Date) -> Date? {
        wallClock(hour: 12, onDayOf: instant)
    }

    /// Day arithmetic relative to `D`, the local day that contains `now` (plan Notation). Every day is its local noon.
    struct Days {
        let resolver: TimeResolver
        let today: Date

        /// Local noon of `D + offset`.
        func noon(_ offset: Int) -> Date? {
            guard let shifted = resolver.calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return resolver.noon(ofDayContaining: shifted)
        }

        /// `mid(D + offset)`.
        func mid(_ offset: Int) -> Date? {
            at(0, offset)
        }

        /// `at(h, D + offset)`.
        func at(_ hour: Int, _ offset: Int) -> Date? {
            guard let day = noon(offset) else { return nil }
            return resolver.wallClock(hour: hour, onDayOf: day)
        }

        /// `slot(p, D + offset)`: morning [05, 12), afternoon [12, 17), evening [17, 22), night [22, 05 next day).
        func slot(_ daypart: Daypart, _ offset: Int) -> (start: Date, end: Date)? {
            let start = at(daypart.startHour, offset)
            let end = at(daypart.endHour, daypart == .night ? offset + 1 : offset)  // night ends on the next day
            guard let start, let end else { return nil }
            return (start, end)
        }

        func weekday(_ offset: Int) -> Weekday? {
            guard let day = noon(offset) else { return nil }
            let number = resolver.calendar.component(.weekday, from: day)  // 1 = Sunday … 7 = Saturday
            let all = Weekday.allCases
            guard (1...all.count).contains(number) else { return nil }
            return all[number - 1]
        }

        /// The first offset in `offset + 1 … offset + 7` whose day has `weekday`.
        func firstOffset(after offset: Int, weekday: Weekday) -> Int? {
            (offset + 1...offset + 7).first { self.weekday($0) == weekday }
        }

        /// `[mid(d), mid(d + 1))` with no daypart, `slot(p, d)` with one (T5–T8, T14).
        func dayOrSlot(_ daypart: Daypart?, _ offset: Int) -> Computed {
            guard let daypart else { return span(midnightOf: offset, toMidnightOf: offset + 1) }
            return slotWindow(daypart, offset)
        }

        func slotWindow(_ daypart: Daypart, _ offset: Int) -> Computed {
            guard let slot = slot(daypart, offset) else { return .unusable(.calendarUnresolved) }
            return .window(slot.start, slot.end)
        }

        func span(from start: Date, toMidnightOf endOffset: Int) -> Computed {
            guard let end = mid(endOffset) else { return .unusable(.calendarUnresolved) }
            return .window(start, end)
        }

        func span(midnightOf startOffset: Int, toMidnightOf endOffset: Int) -> Computed {
            guard let start = mid(startOffset), let end = mid(endOffset) else { return .unusable(.calendarUnresolved) }
            return .window(start, end)
        }
    }
}

extension Daypart {
    /// The local hour at which the daypart starts (M1 brief Q2).
    var startHour: Int {
        switch self {
        case .morning: 5
        case .afternoon: 12
        case .evening: 17
        case .night: 22
        }
    }

    /// The local hour at which the daypart ends: the next daypart's start (as in M1, where a slot ends where the next
    /// one starts). For night that is the morning start, on the next day.
    var endHour: Int {
        let all = Daypart.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index + 1) % all.count].startHour
    }
}

/// Q5 step 6: whether an item keeps the resolver's interval (the resolver never decides the kind).
public enum RecurrenceSettlement {
    /// Whole days a recurring item may repeat at (Q5 step 6).
    public static let intervalRange = 1...730

    /// The time fields of an item after Q5 step 6. Empty sets keep the resolver's "∅" meaning; `effective…` applies the
    /// Q5 step 3 defaults (`Daypart.defaultAllowed`, all seven weekdays).
    public struct Settled: Hashable, Sendable {
        public let kind: TaskKind
        public let intervalDays: Int?
        public let allowedDayparts: Set<Daypart>
        public let allowedWeekdays: Set<Weekday>

        public var effectiveDayparts: Set<Daypart> { allowedDayparts.isEmpty ? Daypart.defaultAllowed : allowedDayparts }
        public var effectiveWeekdays: Set<Weekday> {
            allowedWeekdays.isEmpty ? Set(Weekday.allCases) : allowedWeekdays
        }
    }

    /// A recurring item keeps an interval in 1…730; with no interval or one outside the range it becomes a one-off with
    /// no interval. A one-off or restock item never keeps an interval.
    public static func settle(kind: TaskKind, intervalDays: Int?) -> (kind: TaskKind, intervalDays: Int?) {
        guard kind == .recurring else { return (kind, nil) }
        guard let intervalDays, intervalRange.contains(intervalDays) else { return (.oneOff, nil) }
        return (.recurring, intervalDays)
    }

    /// Step 6 on a whole resolution: when the interval is dropped, R5's {W} is dropped with it, so weekdays become ∅
    /// (all seven after Q5 step 3), as for a one-off T7 (PO Q-T1, E26).
    public static func settle(kind: TaskKind, resolution: TimeResolution) -> Settled {
        let settled = settle(kind: kind, intervalDays: resolution.recurrenceIntervalDays)
        let dropsWeekdays = settled.intervalDays == nil && resolution.weekdaysFollowRepeat
        return Settled(
            kind: settled.kind,
            intervalDays: settled.intervalDays,
            allowedDayparts: resolution.allowedDayparts,
            allowedWeekdays: dropsWeekdays ? [] : resolution.allowedWeekdays
        )
    }
}
