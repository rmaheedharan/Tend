// Slot calendar and the next eligible window `E(a, D)` (brief Definitions "Slot" and "Next eligible window", Q11, Q14;
// FR-B1, FR-B2; risk R-3). `E(a, D)` is the shared basis of the rescheduler and recurring completion (WI-M1-04,
// AC-M1-03, AC-M1-17…21), so it is proven here: hand-computed examples, DST days in a named zone, a calendar day that
// does not exist, and a seeded property against the brute-force oracle in `Support/ContextOracle.swift`.

import Foundation
import Testing
@testable import TendCore

@Suite("Slot calendar and next eligible window E(a, D) (WI-M1-03; R-3)")
struct SlotCalendarTests {
    static let berlin = "Europe/Berlin"
    static let newYork = "America/New_York"

    static func window(_ task: HouseholdTask, from anchor: Date, duration: TimeInterval, in zoneID: String) throws
        -> (windowStart: Date, windowEnd: Date)
    {
        let zone = try SelectionFixtures.zone(zoneID)
        return task.nextEligibleWindow(from: anchor, duration: duration,
                                       calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone)
    }

    static func task(_ dayparts: Set<Daypart>, _ weekdays: Set<Weekday> = Set(Weekday.allCases)) throws
        -> HouseholdTask
    {
        try SelectionFixtures.openTask(around: Fixtures.referenceDate, allowedDayparts: dayparts,
                                       allowedWeekdays: weekdays)
    }

    // MARK: Examples (Berlin, week of Monday 16 November 2026)

    struct ExampleCase: Sendable, CustomTestStringConvertible {
        var label: String
        var dayparts: Set<Daypart>
        var weekdays: Set<Weekday>
        /// Anchor: (day of November 2026, hour, minute, second, millisecond), Berlin local.
        var anchor: (Int, Int, Int, Int, Int)
        /// Expected start (day, hour, minute, second, millisecond), or `nil` for "the anchor itself".
        var start: (Int, Int, Int, Int, Int)?
        var testDescription: String { label }
    }

    static let exampleCases: [ExampleCase] = [
        ExampleCase(label: "inside an allowed slot: starts at the anchor", dayparts: [.morning], weekdays: [.wednesday],
                    anchor: (18, 10, 17, 3, 250), start: nil),
        ExampleCase(label: "exactly at an allowed slot's start: starts at the anchor", dayparts: [.evening],
                    weekdays: [.saturday], anchor: (21, 17, 0, 0, 0), start: nil),
        ExampleCase(label: "afternoon, morning-only task: next morning 05:00", dayparts: [.morning],
                    weekdays: Set(Weekday.allCases), anchor: (18, 13, 0, 0, 0), start: (19, 5, 0, 0, 0)),
        ExampleCase(label: "1 ms before an allowed afternoon: that afternoon", dayparts: [.afternoon],
                    weekdays: [.monday], anchor: (16, 11, 59, 59, 999), start: (16, 12, 0, 0, 0)),
        ExampleCase(label: "end of the last allowed slot of the week: same slot next week", dayparts: [.morning],
                    weekdays: [.sunday], anchor: (22, 12, 0, 0, 0), start: (29, 5, 0, 0, 0)),
        ExampleCase(label: "last instant of an allowed slot: starts at the anchor", dayparts: [.morning],
                    weekdays: [.sunday], anchor: (22, 11, 59, 59, 999), start: nil),
        ExampleCase(label: "Sunday 01:00 is in Saturday's night slot", dayparts: [.night], weekdays: [.saturday],
                    anchor: (22, 1, 0, 0, 0), start: nil),
        ExampleCase(label: "Sunday 05:00 is past Saturday night: next Saturday 22:00", dayparts: [.night],
                    weekdays: [.saturday], anchor: (22, 5, 0, 0, 0), start: (28, 22, 0, 0, 0)),
        ExampleCase(label: "Saturday 01:00 is Friday night, not Saturday night: Saturday 22:00", dayparts: [.night],
                    weekdays: [.saturday], anchor: (21, 1, 0, 0, 0), start: (21, 22, 0, 0, 0)),
        ExampleCase(label: "weekend-only from Monday: Saturday 05:00", dayparts: Daypart.defaultAllowed,
                    weekdays: [.saturday, .sunday], anchor: (16, 9, 0, 0, 0), start: (21, 5, 0, 0, 0)),
        ExampleCase(label: "default dayparts at 23:00: next morning", dayparts: Daypart.defaultAllowed,
                    weekdays: Set(Weekday.allCases), anchor: (18, 23, 0, 0, 0), start: (19, 5, 0, 0, 0)),
    ]

    @Test("E(a, D): hand-computed examples, incl. slot starts, the night slot owned by its start day, and a full week ahead",
          arguments: exampleCases)
    func examples(example: ExampleCase) throws {
        let (d, h, m, s, ms) = example.anchor
        let anchor = try SelectionFixtures.local(2026, 11, d, h, m, s, millisecond: ms, in: Self.berlin)
        let expectedStart: Date = if let (d, h, m, s, ms) = example.start {
            try SelectionFixtures.local(2026, 11, d, h, m, s, millisecond: ms, in: Self.berlin)
        } else {
            anchor
        }
        let duration: TimeInterval = 2 * 86_400 + 0.123_456
        let task = try Self.task(example.dayparts, example.weekdays)
        let window = try Self.window(task, from: anchor, duration: duration, in: Self.berlin)
        #expect(window.windowStart == expectedStart, "\(example.label)")
        #expect(window.windowEnd == expectedStart.addingTimeInterval(duration), "windowEnd = s + D exactly")
        let oracle = ContextOracle.nextAllowedStart(
            for: task, from: anchor, calendar: SelectionFixtures.gregorian(in: try SelectionFixtures.zone(Self.berlin)))
        #expect(oracle == expectedStart, "oracle: \(example.label)")
    }

    @Test("E(a, D): the task is not changed and only the requested duration is used")
    func pureAndDurationExact() throws {
        let task = try Self.task([.evening])
        let before = task
        let anchor = try SelectionFixtures.local(2026, 11, 18, 9, in: Self.berlin)
        for duration in [0.001, 1, 3_600.5, 86_400 * 7 + 0.999_999] {
            let window = try Self.window(task, from: anchor, duration: duration, in: Self.berlin)
            #expect(window.windowEnd == window.windowStart.addingTimeInterval(duration))
        }
        #expect(task == before)
    }

    // MARK: DST (R-3, Q11)

    @Test("R-3 / Q11: a nonexistent local time resolves to the next instant, a repeated one to its first occurrence")
    func dstPolicy() throws {
        let zone = try SelectionFixtures.zone(Self.newYork)
        let slots = SlotCalendar(calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone)
        // Sunday 8 March 2026: 02:00 EST jumps to 03:00 EDT. 02:00 does not exist → 03:00 EDT (07:00Z).
        let springNoon = try SelectionFixtures.utc("2026-03-08T16:00:00Z")
        #expect(slots.wallClock(hour: 2, onDayOf: springNoon) == (try SelectionFixtures.utc("2026-03-08T07:00:00Z")))
        // Sunday 1 November 2026: 02:00 EDT falls back to 01:00 EST. 01:00 happens twice → the first (05:00Z).
        let fallNoon = try SelectionFixtures.utc("2026-11-01T17:00:00Z")
        #expect(slots.wallClock(hour: 1, onDayOf: fallNoon) == (try SelectionFixtures.utc("2026-11-01T05:00:00Z")))
        // Day boundaries are unaffected on those days.
        #expect(slots.wallClock(hour: 5, onDayOf: springNoon) == (try SelectionFixtures.utc("2026-03-08T09:00:00Z")))
        #expect(slots.wallClock(hour: 5, onDayOf: fallNoon) == (try SelectionFixtures.utc("2026-11-01T10:00:00Z")))
    }

    @Test("R-3: a night slot across a DST change runs from 22:00 to 05:00 local (6 h in spring, 8 h in autumn) and belongs to Saturday")
    func nightSlotAcrossDST() throws {
        let zone = try SelectionFixtures.zone(Self.newYork)
        let slots = SlotCalendar(calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone)
        let spring = try #require(slots.slot(containing: try SelectionFixtures.utc("2026-03-08T08:30:00Z")))  // 04:30 EDT
        #expect(spring.daypart == .night && spring.weekday == .saturday)
        #expect(spring.start == (try SelectionFixtures.utc("2026-03-08T03:00:00Z")))  // Sat 22:00 EST
        #expect(spring.end == (try SelectionFixtures.utc("2026-03-08T09:00:00Z")))    // Sun 05:00 EDT
        let autumn = try #require(slots.slot(containing: try SelectionFixtures.utc("2026-11-01T06:30:00Z")))  // 2nd 01:30
        #expect(autumn.daypart == .night && autumn.weekday == .saturday)
        #expect(autumn.start == (try SelectionFixtures.utc("2026-11-01T02:00:00Z")))  // Sat 22:00 EDT
        #expect(autumn.end == (try SelectionFixtures.utc("2026-11-01T10:00:00Z")))    // Sun 05:00 EST
        #expect(autumn.end.timeIntervalSince(autumn.start) == 8 * 3_600)
        #expect(spring.end.timeIntervalSince(spring.start) == 6 * 3_600)
    }

    struct DSTCase: Sendable, CustomTestStringConvertible {
        var label: String
        var dayparts: Set<Daypart>
        var weekdays: Set<Weekday>
        var anchorUTC: String
        var startUTC: String
        var testDescription: String { label }
    }

    static let dstCases: [DSTCase] = [
        DSTCase(label: "spring: Saturday 21:00 EST, Saturday-night task → Saturday 22:00 EST", dayparts: [.night],
                weekdays: [.saturday], anchorUTC: "2026-03-08T02:00:00Z", startUTC: "2026-03-08T03:00:00Z"),
        DSTCase(label: "spring: Sunday 04:30 EDT is still Saturday night → anchor", dayparts: [.night],
                weekdays: [.saturday], anchorUTC: "2026-03-08T08:30:00Z", startUTC: "2026-03-08T08:30:00Z"),
        DSTCase(label: "spring: Sunday 05:00 EDT → next Saturday 22:00 EDT", dayparts: [.night],
                weekdays: [.saturday], anchorUTC: "2026-03-08T09:00:00Z", startUTC: "2026-03-15T02:00:00Z"),
        DSTCase(label: "spring: Sunday 01:30 EST, Sunday-morning task → Sunday 05:00 EDT", dayparts: [.morning],
                weekdays: [.sunday], anchorUTC: "2026-03-08T06:30:00Z", startUTC: "2026-03-08T09:00:00Z"),
        DSTCase(label: "autumn: Saturday 23:00 EDT, Sunday-morning task → Sunday 05:00 EST", dayparts: [.morning],
                weekdays: [.sunday], anchorUTC: "2026-11-01T03:00:00Z", startUTC: "2026-11-01T10:00:00Z"),
        DSTCase(label: "autumn: first 01:30 (EDT) is Saturday night → anchor", dayparts: [.night],
                weekdays: [.saturday], anchorUTC: "2026-11-01T05:30:00Z", startUTC: "2026-11-01T05:30:00Z"),
        DSTCase(label: "autumn: second 01:30 (EST) is Saturday night → anchor", dayparts: [.night],
                weekdays: [.saturday], anchorUTC: "2026-11-01T06:30:00Z", startUTC: "2026-11-01T06:30:00Z"),
        DSTCase(label: "autumn: Sunday 06:00 EST, evening task → Sunday 17:00 EST", dayparts: [.evening],
                weekdays: Set(Weekday.allCases), anchorUTC: "2026-11-01T11:00:00Z", startUTC: "2026-11-01T22:00:00Z"),
    ]

    @Test("R-3: E(a, D) on DST days in America/New_York", arguments: dstCases)
    func dstDays(dstCase: DSTCase) throws {
        let anchor = try SelectionFixtures.utc(dstCase.anchorUTC)
        let task = try Self.task(dstCase.dayparts, dstCase.weekdays)
        let duration: TimeInterval = 5_400.5
        let window = try Self.window(task, from: anchor, duration: duration, in: Self.newYork)
        let expected = try SelectionFixtures.utc(dstCase.startUTC)
        #expect(window.windowStart == expected, "\(dstCase.label)")
        #expect(window.windowEnd == expected.addingTimeInterval(duration))
        let oracle = ContextOracle.nextAllowedStart(
            for: task, from: anchor, calendar: SelectionFixtures.gregorian(in: try SelectionFixtures.zone(Self.newYork)))
        #expect(oracle == expected, "oracle: \(dstCase.label)")
    }

    @Test("R-3: a calendar day that does not exist (Samoa skipped Friday 30 December 2011) moves a Friday task to the next Friday")
    func skippedCalendarDay() throws {
        let anchor = try SelectionFixtures.local(2011, 12, 29, 13, in: "Pacific/Apia")  // Thursday afternoon
        let task = try Self.task([.morning], [.friday])
        let window = try Self.window(task, from: anchor, duration: 3_600, in: "Pacific/Apia")
        let expected = try SelectionFixtures.local(2012, 1, 6, 5, in: "Pacific/Apia")
        #expect(window.windowStart == expected)
        let oracle = ContextOracle.nextAllowedStart(
            for: task, from: anchor, calendar: SelectionFixtures.gregorian(in: try SelectionFixtures.zone("Pacific/Apia")))
        #expect(oracle == expected)
    }

    // MARK: Property

    static let propertySeeds: ClosedRange<UInt64> = 300_001...301_000

    @Test("E(a, D): over 1,000 seeded tasks, anchors and time zones the window equals the brute-force oracle's, with windowEnd = s + D")
    func matchesBruteForceOracle() throws {
        var atAnchor = 0, moved = 0, longest: TimeInterval = 0, nearDST = 0
        for seed in Self.propertySeeds {
            let selectionCase = try SelectionCorpus.makeCase(seed: seed, taskCounts: 0...0)
            let anchor = selectionCase.moment.now
            var rng = SplitMix64(seed: seed)
            let task = try HouseholdGenerator.task(using: &rng, rooms: [], now: anchor)
            let duration = task.windowEnd.timeIntervalSince(task.windowStart)
            let window = task.nextEligibleWindow(from: anchor, duration: duration,
                                                 calendar: selectionCase.moment.calendar,
                                                 timeZone: selectionCase.moment.timeZone)
            let expected = ContextOracle.nextAllowedStart(for: task, from: anchor,
                                                          calendar: selectionCase.moment.calendar)
            #expect(window.windowStart == expected, "seed \(seed), \(selectionCase.description)")
            #expect(window.windowEnd == window.windowStart.addingTimeInterval(duration), "seed \(seed)")
            if window.windowStart == anchor { atAnchor += 1 } else { moved += 1 }
            longest = max(longest, window.windowStart.timeIntervalSince(anchor))
            if let change = selectionCase.moment.timeZone.nextDaylightSavingTimeTransition(
                after: anchor.addingTimeInterval(-43_200)), change.timeIntervalSince(anchor) <= 43_200 {
                nearDST += 1
            }
        }
        print("E(a, D) property: seeds \(Self.propertySeeds), \(Self.propertySeeds.count) cases, "
              + "\(atAnchor) start at the anchor, \(moved) move to a later slot, \(nearDST) anchors within 12 h of a "
              + "DST change, longest move \(Int(longest / 3_600)) h")
        #expect(atAnchor > 0 && moved > 0)
        #expect(longest < 8 * 86_400, "an allowed slot always starts within 8 days")
    }
}
