// AC-M2-03: the Q6 time resolver (FR-A1; brief Q5 step 5 and 6, Q6, T-08; plan "Q6 time-phrase table" T1–T15,
// R1–R7 and the worked examples E1–E26, with PO Q-T1 and Q-T2 of 2026-11-21). Plan WI-M2-03.
//
// Round 2 (review R1-F1, R1-F2): the tests that pinned the round 1 readings (an invalid hint drops its daypart and
// repeat; R5 needs a weekly repeat) now pin the PO's answers instead. That follows a product decision; it is not a
// weakening.
//
// Every expected value below is written from the plan's table by hand (UTC instants checked against tzdata with
// Python `zoneinfo`), never computed by the code under test. The calendar is Gregorian (en-US, Q2) with an injected time
// zone; `now` is always a fixed instant.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Fixtures

/// A fixed Gregorian calendar in one time zone, with helpers for local and UTC instants.
struct TestClock: Sendable {
    let timeZone: TimeZone
    let calendar: Calendar

    init(_ identifier: String, firstWeekday: Int = 1) {
        // A missing tz identifier would make every expectation below fail loudly, so UTC is a safe stand-in.
        let zone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        self.timeZone = zone
        self.calendar = calendar
    }

    static let newYork = TestClock("America/New_York")
    static let santiago = TestClock("America/Santiago")

    var resolver: TimeResolver { TimeResolver(calendar: calendar, timeZone: timeZone) }

    /// A local wall-clock instant. Every local time used in this file exists and is unambiguous.
    func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> Date {
        let parts = DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s)
        return calendar.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: .nan)
    }
}

/// `"2026-03-08T14:00Z"` or `"2026-03-08T14:00:30Z"` as an instant.
func utc(_ text: String) -> Date {
    var value = text
    if value.count == 17 { value.insert(contentsOf: ":00", at: value.index(value.startIndex, offsetBy: 16)) }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) ?? Date(timeIntervalSinceReferenceDate: .nan)
}

let sevenDays: TimeInterval = 604_800
let weekend: Set<Weekday> = [.saturday, .sunday]

/// One expected resolution.
struct TimeCase: Sendable, CustomTestStringConvertible {
    let id: String
    let hint: TimeHint?
    let now: Date
    let start: Date
    let end: Date
    var dayparts: Set<Daypart> = []
    var weekdays: Set<Weekday> = []
    var interval: Int? = nil
    var clock: TestClock = .newYork

    var testDescription: String { id }
}

func check(_ c: TimeCase, sourceLocation: SourceLocation = #_sourceLocation) {
    let r = c.clock.resolver.resolve(c.hint, now: c.now)
    #expect(r.windowStart == c.start, "\(c.id): start \(r.windowStart) != \(c.start)", sourceLocation: sourceLocation)
    #expect(r.windowEnd == c.end, "\(c.id): end \(r.windowEnd) != \(c.end)", sourceLocation: sourceLocation)
    #expect(r.allowedDayparts == c.dayparts, "\(c.id): dayparts", sourceLocation: sourceLocation)
    #expect(r.allowedWeekdays == c.weekdays, "\(c.id): weekdays", sourceLocation: sourceLocation)
    #expect(r.recurrenceIntervalDays == c.interval, "\(c.id): interval", sourceLocation: sourceLocation)
}

private let ny = TestClock.newYork

// MARK: - Worked examples E1–E21 (America/New_York)

enum WorkedExamples {
    static let all: [TimeCase] = [
        TimeCase(id: "E1 T2 today, 23 h day", hint: TimeHint(anchor: .today),
                 now: ny.local(2026, 3, 8, 10), start: utc("2026-03-08T14:00Z"), end: utc("2026-03-09T04:00Z")),
        TimeCase(id: "E2 T4 tonight, 25 h day", hint: TimeHint(anchor: .tonight),
                 now: ny.local(2026, 11, 1, 19), start: utc("2026-11-02T00:00Z"), end: utc("2026-11-02T10:00Z"),
                 dayparts: [.evening, .night]),
        TimeCase(id: "E3 T9 Sunday at 18:00", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 1, 18), start: utc("2026-11-07T05:00Z"), end: utc("2026-11-09T05:00Z"),
                 weekdays: weekend),
        TimeCase(id: "E4 T9 Sunday before 18:00", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 1, 17, 59), start: utc("2026-11-01T22:59Z"), end: utc("2026-11-02T05:00Z"),
                 weekdays: weekend),
        TimeCase(id: "E5 T9 Saturday, across spring-forward", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 3, 7, 11), start: utc("2026-03-07T16:00Z"), end: utc("2026-03-09T04:00Z"),
                 weekdays: weekend),
        TimeCase(id: "E6 T11 next week, year boundary", hint: TimeHint(anchor: .nextWeek),
                 now: ny.local(2026, 12, 31, 15), start: utc("2027-01-04T05:00Z"), end: utc("2027-01-11T05:00Z")),
        TimeCase(id: "E7 T5 tomorrow, year boundary", hint: TimeHint(anchor: .tomorrow),
                 now: ny.local(2026, 12, 31, 15), start: utc("2027-01-01T05:00Z"), end: utc("2027-01-02T05:00Z")),
        TimeCase(id: "E8 T13 before summer, in summer", hint: TimeHint(anchor: .beforeSeason, season: .summer),
                 now: ny.local(2026, 6, 15, 9), start: utc("2026-06-15T13:00Z"), end: utc("2027-06-01T04:00Z")),
        TimeCase(id: "E9 T13 before winter, in winter (January)", hint: TimeHint(anchor: .beforeSeason, season: .winter),
                 now: ny.local(2027, 1, 10, 9), start: utc("2027-01-10T14:00Z"), end: utc("2027-12-01T05:00Z")),
        TimeCase(id: "E10 T12 before March", hint: TimeHint(anchor: .beforeMonth, month: 3),
                 now: ny.local(2026, 2, 20, 9), start: utc("2026-02-20T14:00Z"), end: utc("2026-03-01T05:00Z")),
        TimeCase(id: "E11 T12 before December, in December", hint: TimeHint(anchor: .beforeMonth, month: 12),
                 now: ny.local(2026, 12, 31, 15), start: utc("2026-12-31T20:00Z"), end: utc("2027-12-01T05:00Z")),
        TimeCase(id: "E12 T6 tomorrow morning, 23 h day", hint: TimeHint(anchor: .tomorrow, daypart: .morning),
                 now: ny.local(2026, 3, 7, 21), start: utc("2026-03-08T09:00Z"), end: utc("2026-03-08T16:00Z"),
                 dayparts: [.morning]),
        TimeCase(id: "E13 T1 no phrase, across spring-forward", hint: TimeHint(anchor: .none),
                 now: ny.local(2026, 3, 7, 11), start: utc("2026-03-07T16:00Z"), end: utc("2026-03-14T16:00Z")),
        TimeCase(id: "E15 T10 this week, Sunday at 18:00", hint: TimeHint(anchor: .thisWeek),
                 now: ny.local(2026, 11, 1, 18), start: utc("2026-11-02T05:00Z"), end: utc("2026-11-09T05:00Z")),
        TimeCase(id: "E16 T10 this week, Sunday before 18:00", hint: TimeHint(anchor: .thisWeek),
                 now: ny.local(2026, 11, 1, 17, 59), start: utc("2026-11-01T22:59Z"), end: utc("2026-11-02T05:00Z")),
        TimeCase(id: "E17 T11 next week, across fall-back", hint: TimeHint(anchor: .nextWeek),
                 now: ny.local(2026, 10, 22, 10), start: utc("2026-10-26T04:00Z"), end: utc("2026-11-02T05:00Z")),
        TimeCase(id: "E18 T11 next week, across spring-forward", hint: TimeHint(anchor: .nextWeek),
                 now: ny.local(2026, 2, 26, 10), start: utc("2026-03-02T05:00Z"), end: utc("2026-03-09T04:00Z")),
        TimeCase(id: "E19 T4 tonight, said after midnight", hint: TimeHint(anchor: .tonight),
                 now: ny.local(2026, 11, 23, 1), start: utc("2026-11-23T06:00Z"), end: utc("2026-11-24T10:00Z"),
                 dayparts: [.evening, .night]),
        TimeCase(id: "E20 T14 in 3 days at night", hint: TimeHint(anchor: .inDays, daypart: .night, count: 3),
                 now: ny.local(2026, 11, 19, 10), start: utc("2026-11-23T03:00Z"), end: utc("2026-11-23T10:00Z"),
                 dayparts: [.night]),
        TimeCase(id: "E21 T9 this weekend in the morning, Sunday 15:00",
                 hint: TimeHint(anchor: .thisWeekend, daypart: .morning),
                 now: ny.local(2026, 11, 1, 15), start: utc("2026-11-07T10:00Z"), end: utc("2026-11-08T17:00Z"),
                 dayparts: [.morning], weekdays: weekend),
        TimeCase(id: "E22 invalid anchor (weekday with no weekday) + 1 week: interval kept (PO Q-T2)",
                 hint: TimeHint(anchor: .weekday, repeatEvery: 1, repeatUnit: .week),
                 now: ny.local(2026, 11, 23, 10), start: utc("2026-11-23T15:00Z"), end: utc("2026-11-30T15:00Z"),
                 interval: 7),
        TimeCase(id: "E23 R5 Thursday + 1 month: weekdays {thursday} (PO Q-T1)",
                 hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .month),
                 now: ny.local(2026, 11, 23, 10), start: utc("2026-11-26T05:00Z"), end: utc("2026-11-27T05:00Z"),
                 weekdays: [.thursday], interval: 30),
        TimeCase(id: "E24 Thursday + 1 day (daily from Thursday): weekdays ∅ (PO Q-T1)",
                 hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .day),
                 now: ny.local(2026, 11, 23, 10), start: utc("2026-11-26T05:00Z"), end: utc("2026-11-27T05:00Z"),
                 interval: 1),
        TimeCase(id: "E25 invalid anchor (inDays 400) + evening: dayparts kept (PO Q-T2)",
                 hint: TimeHint(anchor: .inDays, daypart: .evening, count: 400),
                 now: ny.local(2026, 11, 23, 10), start: utc("2026-11-23T15:00Z"), end: utc("2026-11-30T15:00Z"),
                 dayparts: [.evening]),
    ]
}

// MARK: - Row cases T1–T15 (New York; base Wed 2026-11-18 10:00 EST, no DST change nearby)

enum RowCases {
    static let wed = ny.local(2026, 11, 18, 10)            // 2026-11-18T15:00Z
    static let sat = ny.local(2026, 11, 21, 9)             // 2026-11-21T14:00Z
    static let sun = ny.local(2026, 11, 22, 10)            // 2026-11-22T15:00Z
    static let mon = ny.local(2026, 11, 23, 10)            // 2026-11-23T15:00Z

    static let all: [TimeCase] = [
        // T1
        TimeCase(id: "T1 no phrase", hint: TimeHint(anchor: .none),
                 now: wed, start: wed, end: wed.addingTimeInterval(sevenDays)),
        // T2
        TimeCase(id: "T2 today", hint: TimeHint(anchor: .today),
                 now: wed, start: wed, end: utc("2026-11-19T05:00Z")),
        TimeCase(id: "T2 today at 23:59:59", hint: TimeHint(anchor: .today),
                 now: ny.local(2026, 11, 18, 23, 59, 59), start: utc("2026-11-19T04:59:59Z"),
                 end: utc("2026-11-19T05:00Z")),
        // T3 (P1)
        TimeCase(id: "T3 this morning, inside the slot", hint: TimeHint(anchor: .today, daypart: .morning),
                 now: wed, start: wed, end: utc("2026-11-18T17:00Z"), dayparts: [.morning]),
        TimeCase(id: "T3 this evening, before the slot", hint: TimeHint(anchor: .today, daypart: .evening),
                 now: wed, start: utc("2026-11-18T22:00Z"), end: utc("2026-11-19T03:00Z"), dayparts: [.evening]),
        TimeCase(id: "T3 this morning, slot has ended: tomorrow's", hint: TimeHint(anchor: .today, daypart: .morning),
                 now: ny.local(2026, 11, 18, 13), start: utc("2026-11-19T10:00Z"), end: utc("2026-11-19T17:00Z"),
                 dayparts: [.morning]),
        TimeCase(id: "T3 this afternoon at exactly 17:00 (end <= now): tomorrow's",
                 hint: TimeHint(anchor: .today, daypart: .afternoon),
                 now: ny.local(2026, 11, 18, 17), start: utc("2026-11-19T17:00Z"), end: utc("2026-11-19T22:00Z"),
                 dayparts: [.afternoon]),
        TimeCase(id: "T3 today + night", hint: TimeHint(anchor: .today, daypart: .night),
                 now: wed, start: utc("2026-11-19T03:00Z"), end: utc("2026-11-19T10:00Z"), dayparts: [.night]),
        // T4 (Q6(d)); a daypart is ignored
        TimeCase(id: "T4 tonight", hint: TimeHint(anchor: .tonight),
                 now: wed, start: wed, end: utc("2026-11-19T10:00Z"), dayparts: [.evening, .night]),
        TimeCase(id: "T4 tonight with a daypart (ignored)", hint: TimeHint(anchor: .tonight, daypart: .morning),
                 now: wed, start: wed, end: utc("2026-11-19T10:00Z"), dayparts: [.evening, .night]),
        // T5, T6
        TimeCase(id: "T5 tomorrow", hint: TimeHint(anchor: .tomorrow),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z")),
        TimeCase(id: "T6 tomorrow afternoon", hint: TimeHint(anchor: .tomorrow, daypart: .afternoon),
                 now: wed, start: utc("2026-11-19T17:00Z"), end: utc("2026-11-19T22:00Z"), dayparts: [.afternoon]),
        TimeCase(id: "T6 tomorrow night", hint: TimeHint(anchor: .tomorrow, daypart: .night),
                 now: wed, start: utc("2026-11-20T03:00Z"), end: utc("2026-11-20T10:00Z"), dayparts: [.night]),
        // T7, T8 (P2)
        TimeCase(id: "T7 Thursday said on Wednesday", hint: TimeHint(anchor: .weekday, weekday: .thursday),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z")),
        TimeCase(id: "T7 Wednesday said on Wednesday: next week's", hint: TimeHint(anchor: .weekday, weekday: .wednesday),
                 now: wed, start: utc("2026-11-25T05:00Z"), end: utc("2026-11-26T05:00Z")),
        TimeCase(id: "T7 Tuesday said on Wednesday: 6 days ahead", hint: TimeHint(anchor: .weekday, weekday: .tuesday),
                 now: wed, start: utc("2026-11-24T05:00Z"), end: utc("2026-11-25T05:00Z")),
        TimeCase(id: "T8 Thursday evening", hint: TimeHint(anchor: .weekday, daypart: .evening, weekday: .thursday),
                 now: wed, start: utc("2026-11-19T22:00Z"), end: utc("2026-11-20T03:00Z"), dayparts: [.evening]),
        // T9 (Q6(b))
        TimeCase(id: "T9 this weekend on Wednesday", hint: TimeHint(anchor: .thisWeekend),
                 now: wed, start: utc("2026-11-21T05:00Z"), end: utc("2026-11-23T05:00Z"), weekdays: weekend),
        TimeCase(id: "T9 this weekend on Friday 23:00", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 20, 23), start: utc("2026-11-21T05:00Z"), end: utc("2026-11-23T05:00Z"),
                 weekdays: weekend),
        TimeCase(id: "T9 this weekend on Saturday", hint: TimeHint(anchor: .thisWeekend),
                 now: sat, start: sat, end: utc("2026-11-23T05:00Z"), weekdays: weekend),
        TimeCase(id: "T9 this weekend on Sunday 17:59:59", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 22, 17, 59, 59), start: utc("2026-11-22T22:59:59Z"),
                 end: utc("2026-11-23T05:00Z"), weekdays: weekend),
        TimeCase(id: "T9 this weekend on Sunday 17:59:59.5 (wall clock still before 18:00)",
                 hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 22, 17, 59, 59).addingTimeInterval(0.5),
                 start: utc("2026-11-22T22:59:59Z").addingTimeInterval(0.5), end: utc("2026-11-23T05:00Z"),
                 weekdays: weekend),
        TimeCase(id: "T9 this weekend on Sunday 18:00:00", hint: TimeHint(anchor: .thisWeekend),
                 now: ny.local(2026, 11, 22, 18), start: utc("2026-11-28T05:00Z"), end: utc("2026-11-30T05:00Z"),
                 weekdays: weekend),
        TimeCase(id: "T9 + morning on Wednesday", hint: TimeHint(anchor: .thisWeekend, daypart: .morning),
                 now: wed, start: utc("2026-11-21T10:00Z"), end: utc("2026-11-22T17:00Z"),
                 dayparts: [.morning], weekdays: weekend),
        TimeCase(id: "T9 + morning on Saturday 09:00", hint: TimeHint(anchor: .thisWeekend, daypart: .morning),
                 now: sat, start: sat, end: utc("2026-11-22T17:00Z"), dayparts: [.morning], weekdays: weekend),
        TimeCase(id: "T9 + evening on Saturday 09:00", hint: TimeHint(anchor: .thisWeekend, daypart: .evening),
                 now: sat, start: utc("2026-11-21T22:00Z"), end: utc("2026-11-23T03:00Z"),
                 dayparts: [.evening], weekdays: weekend),
        TimeCase(id: "T9 + night on Saturday 09:00 (ends Monday 05:00)",
                 hint: TimeHint(anchor: .thisWeekend, daypart: .night),
                 now: sat, start: utc("2026-11-22T03:00Z"), end: utc("2026-11-23T10:00Z"),
                 dayparts: [.night], weekdays: weekend),
        TimeCase(id: "T9 + evening on Sunday 17:30", hint: TimeHint(anchor: .thisWeekend, daypart: .evening),
                 now: ny.local(2026, 11, 22, 17, 30), start: utc("2026-11-22T22:30Z"), end: utc("2026-11-23T03:00Z"),
                 dayparts: [.evening], weekdays: weekend),
        TimeCase(id: "T9 + afternoon on Sunday 17:00 (end <= now): coming weekend",
                 hint: TimeHint(anchor: .thisWeekend, daypart: .afternoon),
                 now: ny.local(2026, 11, 22, 17), start: utc("2026-11-28T17:00Z"), end: utc("2026-11-29T22:00Z"),
                 dayparts: [.afternoon], weekdays: weekend),
        TimeCase(id: "T9 + evening on Sunday 18:30: coming weekend", hint: TimeHint(anchor: .thisWeekend, daypart: .evening),
                 now: ny.local(2026, 11, 22, 18, 30), start: utc("2026-11-28T22:00Z"), end: utc("2026-11-30T03:00Z"),
                 dayparts: [.evening], weekdays: weekend),
        // T10 (P3, PO change)
        TimeCase(id: "T10 this week on Wednesday", hint: TimeHint(anchor: .thisWeek),
                 now: wed, start: wed, end: utc("2026-11-23T05:00Z")),
        TimeCase(id: "T10 this week on Monday", hint: TimeHint(anchor: .thisWeek),
                 now: mon, start: mon, end: utc("2026-11-30T05:00Z")),
        TimeCase(id: "T10 this week on Sunday 10:00", hint: TimeHint(anchor: .thisWeek),
                 now: sun, start: sun, end: utc("2026-11-23T05:00Z")),
        TimeCase(id: "T10 this week on Sunday 17:59:59", hint: TimeHint(anchor: .thisWeek),
                 now: ny.local(2026, 11, 22, 17, 59, 59), start: utc("2026-11-22T22:59:59Z"),
                 end: utc("2026-11-23T05:00Z")),
        TimeCase(id: "T10 this week on Sunday 18:00:00: next week", hint: TimeHint(anchor: .thisWeek),
                 now: ny.local(2026, 11, 22, 18), start: utc("2026-11-23T05:00Z"), end: utc("2026-11-30T05:00Z")),
        TimeCase(id: "T10 + afternoon: dayparts only", hint: TimeHint(anchor: .thisWeek, daypart: .afternoon),
                 now: wed, start: wed, end: utc("2026-11-23T05:00Z"), dayparts: [.afternoon]),
        // T11
        TimeCase(id: "T11 next week on Wednesday", hint: TimeHint(anchor: .nextWeek),
                 now: wed, start: utc("2026-11-23T05:00Z"), end: utc("2026-11-30T05:00Z")),
        TimeCase(id: "T11 next week on Monday", hint: TimeHint(anchor: .nextWeek),
                 now: mon, start: utc("2026-11-30T05:00Z"), end: utc("2026-12-07T05:00Z")),
        TimeCase(id: "T11 next week on Sunday", hint: TimeHint(anchor: .nextWeek),
                 now: sun, start: utc("2026-11-23T05:00Z"), end: utc("2026-11-30T05:00Z")),
        TimeCase(id: "T11 + evening: dayparts only", hint: TimeHint(anchor: .nextWeek, daypart: .evening),
                 now: wed, start: utc("2026-11-23T05:00Z"), end: utc("2026-11-30T05:00Z"), dayparts: [.evening]),
        // T12 (Q6(f))
        TimeCase(id: "T12 before March in November", hint: TimeHint(anchor: .beforeMonth, month: 3),
                 now: wed, start: wed, end: utc("2027-03-01T05:00Z")),
        TimeCase(id: "T12 before November, in November", hint: TimeHint(anchor: .beforeMonth, month: 11),
                 now: wed, start: wed, end: utc("2027-11-01T04:00Z")),
        TimeCase(id: "T12 before December, said 30 Nov 23:59", hint: TimeHint(anchor: .beforeMonth, month: 12),
                 now: ny.local(2026, 11, 30, 23, 59), start: utc("2026-12-01T04:59Z"), end: utc("2026-12-01T05:00Z")),
        TimeCase(id: "T12 before December, said 1 Dec 00:00:00 (not later than now): a year ahead",
                 hint: TimeHint(anchor: .beforeMonth, month: 12),
                 now: ny.local(2026, 12, 1, 0), start: utc("2026-12-01T05:00Z"), end: utc("2027-12-01T05:00Z")),
        TimeCase(id: "T12 before March, said 1 Mar 2027 00:00 (exactly 366 days, leap February): kept",
                 hint: TimeHint(anchor: .beforeMonth, month: 3),
                 now: ny.local(2027, 3, 1, 0), start: utc("2027-03-01T05:00Z"), end: utc("2028-03-01T05:00Z")),
        TimeCase(id: "T12 + morning: dayparts only", hint: TimeHint(anchor: .beforeMonth, daypart: .morning, month: 1),
                 now: wed, start: wed, end: utc("2027-01-01T05:00Z"), dayparts: [.morning]),
        // T13 (Q6(c), Q6(f))
        TimeCase(id: "T13 before spring", hint: TimeHint(anchor: .beforeSeason, season: .spring),
                 now: wed, start: wed, end: utc("2027-03-01T05:00Z")),
        TimeCase(id: "T13 before summer", hint: TimeHint(anchor: .beforeSeason, season: .summer),
                 now: wed, start: wed, end: utc("2027-06-01T04:00Z")),
        TimeCase(id: "T13 before autumn, in autumn", hint: TimeHint(anchor: .beforeSeason, season: .autumn),
                 now: wed, start: wed, end: utc("2027-09-01T04:00Z")),
        TimeCase(id: "T13 before winter", hint: TimeHint(anchor: .beforeSeason, season: .winter),
                 now: wed, start: wed, end: utc("2026-12-01T05:00Z")),
        TimeCase(id: "T13 before spring, said 1 Mar 2027 00:00 (exactly 366 days): kept",
                 hint: TimeHint(anchor: .beforeSeason, season: .spring),
                 now: ny.local(2027, 3, 1, 0), start: utc("2027-03-01T05:00Z"), end: utc("2028-03-01T05:00Z")),
        // T14 (P4, PO daypart)
        TimeCase(id: "T14 in 3 days", hint: TimeHint(anchor: .inDays, count: 3),
                 now: wed, start: utc("2026-11-21T05:00Z"), end: utc("2026-11-22T05:00Z")),
        TimeCase(id: "T14 in 1 day (same as tomorrow)", hint: TimeHint(anchor: .inDays, count: 1),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z")),
        TimeCase(id: "T14 in two weeks", hint: TimeHint(anchor: .inWeeks, count: 2),
                 now: wed, start: utc("2026-12-02T05:00Z"), end: utc("2026-12-03T05:00Z")),
        TimeCase(id: "T14 in 52 weeks", hint: TimeHint(anchor: .inWeeks, count: 52),
                 now: wed, start: utc("2027-11-17T05:00Z"), end: utc("2027-11-18T05:00Z")),
        TimeCase(id: "T14 in 366 days (start 366 d minus 10 h ahead): kept", hint: TimeHint(anchor: .inDays, count: 366),
                 now: wed, start: utc("2027-11-19T05:00Z"), end: utc("2027-11-20T05:00Z")),
        TimeCase(id: "T14 in 2 weeks in the afternoon", hint: TimeHint(anchor: .inWeeks, daypart: .afternoon, count: 2),
                 now: wed, start: utc("2026-12-02T17:00Z"), end: utc("2026-12-02T22:00Z"), dayparts: [.afternoon]),
        // T15 (P5)
        TimeCase(id: "T15 in the morning, no day", hint: TimeHint(anchor: .none, daypart: .morning),
                 now: wed, start: wed, end: wed.addingTimeInterval(sevenDays), dayparts: [.morning]),
    ]
}

// MARK: - Repeat rows R1–R7

enum RepeatCases {
    static let wed = RowCases.wed
    static let t1End = wed.addingTimeInterval(sevenDays)

    static let all: [TimeCase] = [
        TimeCase(id: "R1 daily", hint: TimeHint(anchor: .none, repeatEvery: 1, repeatUnit: .day),
                 now: wed, start: wed, end: t1End, interval: 1),
        TimeCase(id: "R1 every other day", hint: TimeHint(anchor: .none, repeatEvery: 2, repeatUnit: .day),
                 now: wed, start: wed, end: t1End, interval: 2),
        TimeCase(id: "R1 every 10 days", hint: TimeHint(anchor: .none, repeatEvery: 10, repeatUnit: .day),
                 now: wed, start: wed, end: t1End, interval: 10),
        TimeCase(id: "R2 weekly", hint: TimeHint(anchor: .none, repeatEvery: 1, repeatUnit: .week),
                 now: wed, start: wed, end: t1End, interval: 7),
        TimeCase(id: "R2 every other week", hint: TimeHint(anchor: .none, repeatEvery: 2, repeatUnit: .week),
                 now: wed, start: wed, end: t1End, interval: 14),
        TimeCase(id: "R3 monthly", hint: TimeHint(anchor: .none, repeatEvery: 1, repeatUnit: .month),
                 now: wed, start: wed, end: t1End, interval: 30),
        TimeCase(id: "R3 quarterly", hint: TimeHint(anchor: .none, repeatEvery: 3, repeatUnit: .month),
                 now: wed, start: wed, end: t1End, interval: 90),
        TimeCase(id: "R3 every 25 months (resolver reports 750; Q5 step 6 decides)",
                 hint: TimeHint(anchor: .none, repeatEvery: 25, repeatUnit: .month),
                 now: wed, start: wed, end: t1End, interval: 750),
        TimeCase(id: "R4 yearly", hint: TimeHint(anchor: .none, repeatEvery: 1, repeatUnit: .year),
                 now: wed, start: wed, end: t1End, interval: 365),
        TimeCase(id: "R4 every two years", hint: TimeHint(anchor: .none, repeatEvery: 2, repeatUnit: .year),
                 now: wed, start: wed, end: t1End, interval: 730),
        TimeCase(id: "R5 every Thursday", hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .week),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z"),
                 weekdays: [.thursday], interval: 7),
        TimeCase(id: "R5 every other Thursday", hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 2, repeatUnit: .week),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z"),
                 weekdays: [.thursday], interval: 14),
        TimeCase(id: "R5 every Thursday evening",
                 hint: TimeHint(anchor: .weekday, daypart: .evening, weekday: .thursday, repeatEvery: 1, repeatUnit: .week),
                 now: wed, start: utc("2026-11-19T22:00Z"), end: utc("2026-11-20T03:00Z"),
                 dayparts: [.evening], weekdays: [.thursday], interval: 7),
        TimeCase(id: "R6 every weekend", hint: TimeHint(anchor: .thisWeekend, repeatEvery: 1, repeatUnit: .week),
                 now: wed, start: utc("2026-11-21T05:00Z"), end: utc("2026-11-23T05:00Z"),
                 weekdays: weekend, interval: 7),
        TimeCase(id: "R7 every morning", hint: TimeHint(anchor: .none, daypart: .morning, repeatEvery: 1, repeatUnit: .day),
                 now: wed, start: wed, end: t1End, dayparts: [.morning], interval: 1),
        TimeCase(id: "R7 every evening", hint: TimeHint(anchor: .none, daypart: .evening, repeatEvery: 1, repeatUnit: .day),
                 now: wed, start: wed, end: t1End, dayparts: [.evening], interval: 1),
        // R5 (PO Q-T1): a week, month or year repeat on a weekday anchor sets {W}; a day repeat keeps ∅.
        TimeCase(id: "R5 monthly on Thursday: {thursday}",
                 hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .month),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z"),
                 weekdays: [.thursday], interval: 30),
        TimeCase(id: "R5 every year on a Thursday: {thursday}",
                 hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .year),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z"),
                 weekdays: [.thursday], interval: 365),
        TimeCase(id: "weekday + every 2 days: weekdays stay empty",
                 hint: TimeHint(anchor: .weekday, weekday: .saturday, repeatEvery: 2, repeatUnit: .day),
                 now: wed, start: utc("2026-11-21T05:00Z"), end: utc("2026-11-22T05:00Z"), interval: 2),
        TimeCase(id: "weekday + repeatEvery 0 week: no repeat, so weekdays stay empty",
                 hint: TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 0, repeatUnit: .week),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z")),
        // A repeat combines with any anchor row; the anchor row keeps its window.
        TimeCase(id: "repeat + tomorrow", hint: TimeHint(anchor: .tomorrow, repeatEvery: 1, repeatUnit: .week),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z"), interval: 7),
        TimeCase(id: "repeat + before March", hint: TimeHint(anchor: .beforeMonth, month: 3, repeatEvery: 1, repeatUnit: .year),
                 now: wed, start: wed, end: utc("2027-03-01T05:00Z"), interval: 365),
        // One-off "on Thursday" (T7) keeps all seven weekdays (∅ here).
        TimeCase(id: "T7 one-off Thursday: weekdays stay empty", hint: TimeHint(anchor: .weekday, weekday: .thursday),
                 now: wed, start: utc("2026-11-19T05:00Z"), end: utc("2026-11-20T05:00Z")),
        // No repeat: repeatEvery < 1, or one of the two fields absent (an unknown unit is dropped to nil, step 2).
        TimeCase(id: "repeatEvery 0: no repeat", hint: TimeHint(anchor: .none, repeatEvery: 0, repeatUnit: .day),
                 now: wed, start: wed, end: t1End),
        TimeCase(id: "repeatEvery -3: no repeat", hint: TimeHint(anchor: .none, repeatEvery: -3, repeatUnit: .week),
                 now: wed, start: wed, end: t1End),
        TimeCase(id: "repeatUnit absent: no repeat", hint: TimeHint(anchor: .none, repeatEvery: 2),
                 now: wed, start: wed, end: t1End),
        TimeCase(id: "repeatEvery absent: no repeat", hint: TimeHint(anchor: .none, repeatUnit: .week),
                 now: wed, start: wed, end: t1End),
        TimeCase(id: "repeatEvery Int.max years: overflow is no repeat (no trap)",
                 hint: TimeHint(anchor: .none, repeatEvery: Int.max, repeatUnit: .year),
                 now: wed, start: wed, end: t1End),
    ]
}

// MARK: - Invalid hints (plan "How the hint meets Q5"): they resolve exactly as no hint

enum InvalidHints {
    /// (label, hint, reason, expected dayparts, expected interval). PO Q-T2: an invalid anchor is no anchor (T1 window,
    /// weekdays ∅); a valid daypart and a valid repeat still count.
    static let all: [(String, TimeHint, TimeResolution.FallbackReason, Set<Daypart>, Int?)] = [
        ("unrecognized anchor + morning + daily",
         TimeHint(anchor: .unrecognized, daypart: .morning, repeatEvery: 1, repeatUnit: .day),
         .unrecognizedAnchor, [.morning], 1),
        ("unrecognized anchor alone", TimeHint(anchor: .unrecognized), .unrecognizedAnchor, [], nil),
        ("weekday with no weekday + weekly", TimeHint(anchor: .weekday, repeatEvery: 1, repeatUnit: .week),
         .requiredFieldAbsent, [], 7),
        ("weekday with no weekday + monthly + evening: no {W}",
         TimeHint(anchor: .weekday, daypart: .evening, repeatEvery: 1, repeatUnit: .month),
         .requiredFieldAbsent, [.evening], 30),
        ("beforeMonth with no month", TimeHint(anchor: .beforeMonth), .requiredFieldAbsent, [], nil),
        ("beforeMonth 0", TimeHint(anchor: .beforeMonth, month: 0), .fieldOutOfRange, [], nil),
        ("beforeMonth 13 + afternoon", TimeHint(anchor: .beforeMonth, daypart: .afternoon, month: 13),
         .fieldOutOfRange, [.afternoon], nil),
        ("beforeMonth -1", TimeHint(anchor: .beforeMonth, month: -1), .fieldOutOfRange, [], nil),
        ("beforeSeason with no (or an unknown) season + yearly",
         TimeHint(anchor: .beforeSeason, repeatEvery: 1, repeatUnit: .year), .requiredFieldAbsent, [], 365),
        ("inDays with no count", TimeHint(anchor: .inDays), .requiredFieldAbsent, [], nil),
        ("inDays 0", TimeHint(anchor: .inDays, count: 0), .fieldOutOfRange, [], nil),
        ("inDays 367", TimeHint(anchor: .inDays, count: 367), .fieldOutOfRange, [], nil),
        ("inDays Int.min", TimeHint(anchor: .inDays, count: Int.min), .fieldOutOfRange, [], nil),
        ("inWeeks with no count", TimeHint(anchor: .inWeeks), .requiredFieldAbsent, [], nil),
        ("inWeeks 0", TimeHint(anchor: .inWeeks, count: 0), .fieldOutOfRange, [], nil),
        ("inWeeks 53 + every 3 weeks", TimeHint(anchor: .inWeeks, count: 53, repeatEvery: 3, repeatUnit: .week),
         .fieldOutOfRange, [], 21),
        ("inDays 366 at night: start is past now + 366 days (daypart kept)",
         TimeHint(anchor: .inDays, daypart: .night, count: 366), .windowOutOfRange, [.night], nil),
    ]
}

@Suite("AC-M2-03: the Q6 time resolver (FR-A1, Q6, T-08)")
struct TimeResolverTests {

    @Test("AC-M2-03: worked examples E1–E13 and E15–E25 equal the plan's table exactly (America/New_York)",
          arguments: WorkedExamples.all)
    func workedExamples(_ c: TimeCase) {
        check(c)
    }

    @Test("AC-M2-03: E14 (R3 / Q5 step 6): every 3 months → interval 90; every 25 months → one-off, no interval")
    func e14() {
        let quarterly = ny.resolver.resolve(TimeHint(anchor: .none, repeatEvery: 3, repeatUnit: .month), now: RowCases.wed)
        let settledQuarterly = RecurrenceSettlement.settle(kind: .recurring, intervalDays: quarterly.recurrenceIntervalDays)
        #expect(settledQuarterly.kind == .recurring)
        #expect(settledQuarterly.intervalDays == 90)

        let long = ny.resolver.resolve(TimeHint(anchor: .none, repeatEvery: 25, repeatUnit: .month), now: RowCases.wed)
        let settledLong = RecurrenceSettlement.settle(kind: .recurring, intervalDays: long.recurrenceIntervalDays)
        #expect(settledLong.kind == .oneOff)
        #expect(settledLong.intervalDays == nil)
    }

    @Test("AC-M2-03: rows T1–T15 at fixed now values equal the table exactly", arguments: RowCases.all)
    func rows(_ c: TimeCase) {
        check(c)
    }

    @Test("AC-M2-03: repeat rows R1–R7 give the table's interval and weekdays", arguments: RepeatCases.all)
    func repeats(_ c: TimeCase) {
        check(c)
    }

    @Test("AC-M2-03 (PO Q-T2): an invalid anchor is no anchor (T1 window, weekdays ∅); a valid daypart and repeat still count",
          arguments: InvalidHints.all)
    func invalidHints(_ label: String, _ hint: TimeHint, _ reason: TimeResolution.FallbackReason,
                      _ dayparts: Set<Daypart>, _ interval: Int?) {
        let r = ny.resolver.resolve(hint, now: RowCases.wed)
        #expect(r.windowStart == RowCases.wed, "\(label)")
        #expect(r.windowEnd == RowCases.wed.addingTimeInterval(sevenDays), "\(label)")
        #expect(r.allowedDayparts == dayparts, "\(label)")
        #expect(r.allowedWeekdays.isEmpty, "\(label)")
        #expect(r.recurrenceIntervalDays == interval, "\(label)")
        #expect(r.basis == .fallback(reason), "\(label)")
        #expect(!r.weekdaysFollowRepeat, "\(label)")
    }

    @Test("AC-M2-03 E26 (PO Q-T1): E23 settled as a one-off drops {thursday} with the interval; weekdays all seven")
    func e26() {
        let e23 = ny.resolver.resolve(TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .month),
                                      now: ny.local(2026, 11, 23, 10))
        #expect(e23.weekdaysFollowRepeat)
        let settled = RecurrenceSettlement.settle(kind: .oneOff, resolution: e23)
        #expect(e23.windowStart == utc("2026-11-26T05:00Z") && e23.windowEnd == utc("2026-11-27T05:00Z"))
        #expect(settled.kind == .oneOff)
        #expect(settled.intervalDays == nil)
        #expect(settled.allowedWeekdays.isEmpty)
        #expect(settled.effectiveWeekdays == Set(Weekday.allCases))
        #expect(settled.allowedDayparts.isEmpty)
        #expect(settled.effectiveDayparts == Daypart.defaultAllowed)
    }

    static let settleCases: [(TimeHint, TaskKind, Set<Weekday>, Int?)] = [
        (TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 1, repeatUnit: .month), TaskKind.recurring,
         Set<Weekday>([.thursday]), Int?.some(30)),
        (TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 25, repeatUnit: .month), .recurring, [], nil),
        (TimeHint(anchor: .weekday, weekday: .thursday, repeatEvery: 2, repeatUnit: .week), .restock, [], nil),
        (TimeHint(anchor: .thisWeekend, repeatEvery: 1, repeatUnit: .week), .oneOff, [.saturday, .sunday], nil),
        (TimeHint(anchor: .thisWeekend, repeatEvery: 1, repeatUnit: .week), .recurring, [.saturday, .sunday], 7),
        (TimeHint(anchor: .weekday, weekday: .friday), .recurring, [], nil),
    ]

    @Test("Q5 step 6 on a resolution: {W} stays with a kept interval, drops with a dropped one; weekend {sat, sun} stays",
          arguments: Self.settleCases)
    func settleResolution(_ hint: TimeHint, _ kind: TaskKind, _ weekdays: Set<Weekday>, _ interval: Int?) {
        let r = ny.resolver.resolve(hint, now: RowCases.wed)
        let s = RecurrenceSettlement.settle(kind: kind, resolution: r)
        #expect(s.allowedWeekdays == weekdays)
        #expect(s.intervalDays == interval)
        #expect(s.allowedDayparts == r.allowedDayparts)
    }

    @Test("AC-M2-03: no hint at all → [now, now + 604,800 s), ∅, ∅, no interval, basis noHint")
    func noHint() {
        let r = ny.resolver.resolve(nil, now: RowCases.wed)
        #expect(r.windowStart == RowCases.wed)
        #expect(r.windowEnd == RowCases.wed.addingTimeInterval(sevenDays))
        #expect(r.allowedDayparts.isEmpty && r.allowedWeekdays.isEmpty)
        #expect(r.recurrenceIntervalDays == nil)
        #expect(r.basis == .noHint)
        #expect(ny.resolver.resolve(TimeHint(anchor: .today), now: RowCases.wed).basis == .hint)
    }

    @Test("AC-M2-03 (R1-F5): a non-finite now never traps and is reported as unresolvable, with or without a hint")
    func nonFiniteNow() {
        let hints: [TimeHint?] = [nil, TimeHint(anchor: .tomorrow),
                                  TimeHint(anchor: .none, daypart: .morning, repeatEvery: 1, repeatUnit: .day)]
        for value in [TimeInterval.nan, .infinity, -.infinity] {
            for hint in hints {
                let r = ny.resolver.resolve(hint, now: Date(timeIntervalSinceReferenceDate: value))
                #expect(r.basis == .fallback(.calendarUnresolved), "\(String(describing: hint)) at \(value)")
                #expect(r.recurrenceIntervalDays == nil && r.allowedDayparts.isEmpty && r.allowedWeekdays.isEmpty)
            }
        }
    }

    // MARK: Q6(a): the week starts on Monday whatever the calendar's firstWeekday

    @Test("AC-M2-03 Q6(a): T7, T9, T10, T11 and T14 do not depend on the calendar's firstWeekday",
          arguments: 1...7)
    func mondayWeekStart(_ firstWeekday: Int) {
        let clock = TestClock("America/New_York", firstWeekday: firstWeekday)
        let cases = (RowCases.all + RepeatCases.all + WorkedExamples.all).map { c in
            TimeCase(id: "\(c.id) [firstWeekday \(firstWeekday)]", hint: c.hint, now: c.now, start: c.start,
                     end: c.end, dayparts: c.dayparts, weekdays: c.weekdays, interval: c.interval, clock: clock)
        }
        for c in cases { check(c) }
    }

    // MARK: Q6(e): DST at local midnight (America/Santiago; tzdata: 2026-09-06 00:00 -04 does not exist, the day
    // starts at 01:00 -03 = 04:00Z; 2027-04-04 00:00 -03 → 2027-04-03 23:00 -04, so Saturday 3 Apr has 25 h)

    static let cl = TestClock.santiago
    static let santiagoCases: [TimeCase] = [
        TimeCase(id: "CL today, Saturday before spring-forward at midnight (23 h day)", hint: TimeHint(anchor: .today),
                 now: cl.local(2026, 9, 5, 10), start: utc("2026-09-05T14:00Z"), end: utc("2026-09-06T04:00Z"),
                 clock: cl),
        TimeCase(id: "CL tomorrow: mid(D+1) moves to 01:00 -03", hint: TimeHint(anchor: .tomorrow),
                 now: cl.local(2026, 9, 5, 10), start: utc("2026-09-06T04:00Z"), end: utc("2026-09-07T03:00Z"),
                 clock: cl),
        TimeCase(id: "CL this weekend on Saturday", hint: TimeHint(anchor: .thisWeekend),
                 now: cl.local(2026, 9, 5, 10), start: utc("2026-09-05T14:00Z"), end: utc("2026-09-07T03:00Z"),
                 weekdays: weekend, clock: cl),
        TimeCase(id: "CL tonight across the gap: 05:00 -03", hint: TimeHint(anchor: .tonight),
                 now: cl.local(2026, 9, 5, 20), start: utc("2026-09-06T00:00Z"), end: utc("2026-09-06T08:00Z"),
                 dayparts: [.evening, .night], clock: cl),
        TimeCase(id: "CL next week across the gap", hint: TimeHint(anchor: .nextWeek),
                 now: cl.local(2026, 9, 2, 10), start: utc("2026-09-07T03:00Z"), end: utc("2026-09-14T03:00Z"),
                 clock: cl),
        TimeCase(id: "CL this week, Sunday 6 Sep 10:00 (the 23 h day)", hint: TimeHint(anchor: .thisWeek),
                 now: cl.local(2026, 9, 6, 10), start: utc("2026-09-06T13:00Z"), end: utc("2026-09-07T03:00Z"),
                 clock: cl),
        TimeCase(id: "CL today, Saturday before fall-back at midnight (25 h day)", hint: TimeHint(anchor: .today),
                 now: cl.local(2027, 4, 3, 10), start: utc("2027-04-03T13:00Z"), end: utc("2027-04-04T04:00Z"),
                 clock: cl),
        TimeCase(id: "CL Saturday night across fall-back: 22:00 -03 to 05:00 -04",
                 hint: TimeHint(anchor: .today, daypart: .night),
                 now: cl.local(2027, 4, 3, 10), start: utc("2027-04-04T01:00Z"), end: utc("2027-04-04T09:00Z"),
                 dayparts: [.night], clock: cl),
    ]

    // America/Havana (tzdata): 2026-03-08 00:00 CST does not exist (the day starts at 01:00 CDT = 05:00Z), and on
    // 2026-11-01 clocks go from 01:00 CDT back to 00:00 CST, so local midnight occurs twice (04:00Z and 05:00Z).
    // Q11: a repeated time takes its first occurrence.
    static let cu = TestClock("America/Havana")
    static let havanaCases: [TimeCase] = [
        TimeCase(id: "CU today before a repeated midnight: its first occurrence", hint: TimeHint(anchor: .today),
                 now: cu.local(2026, 10, 31, 10), start: utc("2026-10-31T14:00Z"), end: utc("2026-11-01T04:00Z"),
                 clock: cu),
        TimeCase(id: "CU tomorrow on the 25 h day", hint: TimeHint(anchor: .tomorrow),
                 now: cu.local(2026, 10, 31, 10), start: utc("2026-11-01T04:00Z"), end: utc("2026-11-02T05:00Z"),
                 clock: cu),
        TimeCase(id: "CU tomorrow on the 23 h day (midnight gap)", hint: TimeHint(anchor: .tomorrow),
                 now: cu.local(2026, 3, 7, 10), start: utc("2026-03-08T05:00Z"), end: utc("2026-03-09T04:00Z"),
                 clock: cu),
    ]

    @Test("AC-M2-03 Q6(e) / Q11: a repeated and a missing local midnight (America/Havana)", arguments: havanaCases)
    func havana(_ c: TimeCase) {
        check(c)
    }

    @Test("AC-M2-03 Q6(e): tzdata sanity for the Havana cases")
    func havanaTzdata() {
        let zone = Self.cu.timeZone
        #expect(zone.secondsFromGMT(for: utc("2026-11-01T04:59Z")) == -4 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2026-11-01T05:00Z")) == -5 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2026-03-08T04:59Z")) == -5 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2026-03-08T05:00Z")) == -4 * 3600)
    }

    @Test("AC-M2-03 Q6(e): a DST change at local midnight (America/Santiago)", arguments: santiagoCases)
    func santiago(_ c: TimeCase) {
        check(c)
    }

    @Test("AC-M2-03 Q6(e): tzdata sanity for the Santiago cases (the gap is where the test assumes)")
    func santiagoTzdata() {
        let zone = Self.cl.timeZone
        #expect(zone.secondsFromGMT(for: utc("2026-09-06T03:59Z")) == -4 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2026-09-06T04:00Z")) == -3 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2027-04-04T02:59Z")) == -3 * 3600)
        #expect(zone.secondsFromGMT(for: utc("2027-04-04T03:00Z")) == -4 * 3600)
        #expect(Self.cl.calendar.startOfDay(for: utc("2026-09-06T12:00Z")) == utc("2026-09-06T04:00Z"))
    }

    // MARK: The out-of-range rule (Q5 step 5), at its exact boundaries

    @Test("AC-M2-03 / Q5 step 5: a window is in range iff now ≤ start ≤ now + 366 d, start < end ≤ start + 366 d")
    func rangeBoundaries() {
        let now = RowCases.wed
        let limit: TimeInterval = 366 * 86_400
        let check = TimeResolver.rangeProblem(start:end:now:)
        #expect(check(now, now.addingTimeInterval(1), now) == nil)
        #expect(check(now.addingTimeInterval(-0.001), now.addingTimeInterval(1), now) == .windowOutOfRange)
        #expect(check(now.addingTimeInterval(limit), now.addingTimeInterval(limit + 1), now) == nil)
        #expect(check(now.addingTimeInterval(limit + 0.001), now.addingTimeInterval(limit + 2), now) == .windowOutOfRange)
        #expect(check(now, now.addingTimeInterval(limit), now) == nil)
        #expect(check(now, now.addingTimeInterval(limit + 0.001), now) == .windowOutOfRange)
        #expect(check(now, now, now) == .emptyWindow)
        #expect(check(now.addingTimeInterval(5), now.addingTimeInterval(4), now) == .emptyWindow)
    }

    @Test("R1-N1: the model is never offered the unrecognized anchor")
    func modelChoices() {
        #expect(TimeHint.Anchor.modelChoices.count == 12)
        #expect(!TimeHint.Anchor.modelChoices.contains(.unrecognized))
    }

    @Test("UX-3: no basis or reason name of the resolver contains a banned token (AC-M1-02 list)")
    func calmNames() {
        let reasons: [TimeResolution.FallbackReason] = [.unrecognizedAnchor, .requiredFieldAbsent, .fieldOutOfRange,
                                                        .emptyWindow, .windowOutOfRange, .calendarUnresolved]
        let names = reasons.map { "\($0)" } + ["\(TimeResolution.Basis.hint)", "\(TimeResolution.Basis.noHint)"]
            + TimeHint.Anchor.allCases.map(\.rawValue)
        for name in names {
            let words = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            #expect(!BannedTokens.containsBannedToken(words), "\(name)")
        }
    }

    // MARK: Q5 step 6 (the resolver never decides the kind)

    @Test("Q5 step 6: settlement of the interval against the final kind", arguments: [
        (TaskKind.recurring, Int?.some(1), TaskKind.recurring, Int?.some(1)),
        (.recurring, 730, .recurring, 730),
        (.recurring, 731, .oneOff, nil),
        (.recurring, 0, .oneOff, nil),
        (.recurring, nil, .oneOff, nil),
        (.oneOff, 7, .oneOff, nil),
        (.restock, 30, .restock, nil),
        (.restock, nil, .restock, nil),
    ])
    func settlement(_ kind: TaskKind, _ interval: Int?, _ expectedKind: TaskKind, _ expectedInterval: Int?) {
        let s = RecurrenceSettlement.settle(kind: kind, intervalDays: interval)
        #expect(s.kind == expectedKind)
        #expect(s.intervalDays == expectedInterval)
    }

    // MARK: Property: invariants and the M1 slot boundaries as an oracle

    static let zones = ["America/New_York", "America/Santiago", "Europe/London", "Australia/Lord_Howe",
                        "Asia/Kolkata", "Pacific/Chatham", "UTC"]

    static func randomHint(using g: inout SplitMix64) -> TimeHint {
        let anchors = TimeHint.Anchor.allCases
        let maybe = { (g: inout SplitMix64) -> Bool in Bool.random(using: &g) }
        return TimeHint(
            anchor: anchors[Int.random(in: 0..<anchors.count, using: &g)],
            daypart: maybe(&g) ? Daypart.allCases.randomElement(using: &g) : nil,
            weekday: maybe(&g) ? Weekday.allCases.randomElement(using: &g) : nil,
            month: maybe(&g) ? Int.random(in: -1...14, using: &g) : nil,
            season: maybe(&g) ? TimeHint.Season.allCases.randomElement(using: &g) : nil,
            count: maybe(&g) ? Int.random(in: -1...400, using: &g) : nil,
            repeatEvery: maybe(&g) ? Int.random(in: -1...40, using: &g) : nil,
            repeatUnit: maybe(&g) ? TimeHint.RepeatUnit.allCases.randomElement(using: &g) : nil
        )
    }

    @Test("AC-M2-03 property: every resolution is a valid Q5 window, and deterministic (seeded)")
    func property() throws {
        let seed: UInt64 = 0x71E5_0A11_CE00_0003
        var g = SplitMix64(seed: seed)
        let cases = 6_000
        var fallbacks = 0
        print("TimeResolver property: seed 0x71E50A11CE000003, \(cases) cases over \(Self.zones.count) zones")
        let base = utc("2026-01-01T00:00Z")
        for index in 0..<cases {
            let clock = TestClock(Self.zones[Int.random(in: 0..<Self.zones.count, using: &g)],
                                  firstWeekday: Int.random(in: 1...7, using: &g))
            let now = base.addingTimeInterval(Double(Int.random(in: 0..<(3 * 366 * 86_400), using: &g))
                                              + Double(Int.random(in: 0..<1000, using: &g)) / 1000)
            let hint = Self.randomHint(using: &g)
            let r = clock.resolver.resolve(hint, now: now)
            let again = clock.resolver.resolve(hint, now: now)
            let label = "case \(index) seed 0x71E50A11CE000003 zone \(clock.timeZone.identifier) now \(now) \(hint)"
            #expect(r == again, "\(label)")
            #expect(r.windowStart >= now, "\(label)")
            #expect(r.windowEnd > r.windowStart, "\(label)")
            #expect(r.windowStart <= now.addingTimeInterval(366 * 86_400), "\(label)")
            #expect(r.windowEnd <= r.windowStart.addingTimeInterval(366 * 86_400), "\(label)")
            // Independent oracle for the fields that do not depend on the anchor (R1–R4, T4, PO Q-T2).
            var expectedInterval: Int? = nil
            if let every = hint.repeatEvery, every >= 1, let unit = hint.repeatUnit {
                let perUnit = [TimeHint.RepeatUnit.day: 1, .week: 7, .month: 30, .year: 365][unit] ?? 0
                let (product, overflow) = every.multipliedReportingOverflow(by: perUnit)
                expectedInterval = overflow ? nil : product
            }
            let expectedDayparts: Set<Daypart> = hint.anchor == .tonight
                ? [.evening, .night] : (hint.daypart.map { [$0] } ?? [])
            #expect(r.recurrenceIntervalDays == expectedInterval, "\(label)")
            #expect(r.allowedDayparts == expectedDayparts, "\(label)")
            if case .fallback = r.basis {
                fallbacks += 1
                #expect(r.windowStart == now && r.windowEnd == now.addingTimeInterval(sevenDays), "\(label)")
                #expect(r.allowedWeekdays.isEmpty && !r.weekdaysFollowRepeat, "\(label)")
            }
            if let interval = r.recurrenceIntervalDays { #expect(interval >= 1, "\(label)") }
            if !r.allowedWeekdays.isEmpty {
                #expect(r.allowedWeekdays == weekend || r.allowedWeekdays.count == 1, "\(label)")
            }
        }
        print("TimeResolver property: \(cases - fallbacks) resolved from the hint, \(fallbacks) fell back to T1")
        #expect(fallbacks > 0 && fallbacks < cases)
    }

    @Test("AC-M2-03 oracle: T6 slot(p, D+1) starts and ends where M1's slot for {p} does (Q6(d) M1 boundaries)")
    func slotOracle() throws {
        var g = SplitMix64(seed: 0x51_07_0A_C1E)
        print("Slot oracle: seed 0x51070AC1E, 1,400 cases over \(Self.zones.count) zones")
        let base = utc("2026-01-01T00:00Z")
        for index in 0..<1_400 {
            let clock = TestClock(Self.zones[index % Self.zones.count])
            let now = base.addingTimeInterval(Double(Int.random(in: 0..<(2 * 366 * 86_400), using: &g)))
            let p = Daypart.allCases[index % 4]
            let r = clock.resolver.resolve(TimeHint(anchor: .tomorrow, daypart: p), now: now)
            let tomorrowStart = clock.resolver.resolve(TimeHint(anchor: .tomorrow), now: now).windowStart
            // M1 oracle: from mid(D+1) (or its local noon for night, since 00:00 lies in the previous night slot).
            let anchor = p == .night ? tomorrowStart.addingTimeInterval(12 * 3600) : tomorrowStart
            let task = try HouseholdTask(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                                         title: "oracle", kind: .oneOff, effort: .normal, allowedDayparts: [p],
                                         windowStart: now, windowEnd: now.addingTimeInterval(60))
            let m1 = task.nextEligibleWindow(from: anchor, duration: 1, calendar: clock.calendar,
                                             timeZone: clock.timeZone)
            #expect(r.windowStart == m1.windowStart,
                    "case \(index) \(clock.timeZone.identifier) \(p) now \(now): \(r.windowStart) vs M1 \(m1.windowStart)")
            // End oracle (R1-F4): the last instant before the end is still in M1's slot; at the end it is not.
            let inside = task.nextEligibleWindow(from: r.windowEnd.addingTimeInterval(-0.001), duration: 1,
                                                 calendar: clock.calendar, timeZone: clock.timeZone)
            let after = task.nextEligibleWindow(from: r.windowEnd, duration: 1, calendar: clock.calendar,
                                                timeZone: clock.timeZone)
            #expect(inside.windowStart == r.windowEnd.addingTimeInterval(-0.001), "case \(index) \(p): end inside")
            #expect(after.windowStart > r.windowEnd, "case \(index) \(p): end is outside M1's slot")
            #expect(clock.calendar.startOfDay(for: tomorrowStart) == tomorrowStart,
                    "case \(index): mid(D+1) is the start of a local day")
        }
    }
}
