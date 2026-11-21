// AC-M2-01: scripted mock model output for each PRD item type maps to a draft that becomes a valid `HouseholdTask`
// with the expected kind, room, effort and flags; dates come only from the injected `now`, calendar and time zone.
// Plus one named test per Q5 repair (brief Q5 steps 1–9, T-07), the R19-F3 decision and the step 9 safety net.
// FR-A1, D-016, UX-3. Plan WI-M2-05.
//
// Expected windows are written out in UTC by hand from the plan's Q6 table (rows T5, T7/R5, T9 + daypart, T10, T12,
// T1), not computed by the code under test.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

enum MappingFixtures {
    static func id(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    static let kitchen = Room(id: id("00000000000A"), name: "Kitchen")
    static let bathroom = Room(id: id("00000000000B"), name: "Bathroom")
    static let rooms = [kitchen, bathroom]

    static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? Date(timeIntervalSinceReferenceDate: .nan)
    }

    static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    static let gregorian = Calendar(identifier: .gregorian)

    /// Mon 2026-11-23 10:00 EST.
    static let newYorkNow = utc("2026-11-23T15:00:00Z")
    /// Mon 2026-11-23 10:00 GMT.
    static let londonNow = utc("2026-11-23T10:00:00Z")

    static func mapper(input: String, now: Date = newYorkNow, zone identifier: String = "America/New_York",
                       rooms: [Room] = rooms) -> DraftMapper {
        DraftMapper(input: input, rooms: rooms, now: now, calendar: gregorian, timeZone: zone(identifier))
    }

    static func item(
        title: String? = "Post the parcel",
        kind: String? = "oneOff",
        room: String? = nil,
        effort: String? = "normal",
        isCritical: Bool? = false,
        isDeepClean: Bool? = false,
        isWeatherDependent: Bool? = false,
        time: TimeHintSnapshot? = nil,
        sourcePhrase: String? = nil
    ) -> ItemSnapshot {
        ItemSnapshot(
            title: title,
            kind: kind.map(ModelChoice<TaskKind>.init(raw:)),
            roomName: room,
            effort: effort.map(ModelChoice<Effort>.init(raw:)),
            isCritical: isCritical,
            isDeepClean: isDeepClean,
            isWeatherDependent: isWeatherDependent,
            time: time,
            sourcePhrase: sourcePhrase
        )
    }

    static func hint(
        anchor: String? = "none", daypart: String? = nil, weekday: String? = nil, month: Int? = nil,
        season: String? = nil, count: Int? = nil, repeatEvery: Int? = nil, repeatUnit: String? = nil
    ) -> TimeHintSnapshot {
        TimeHintSnapshot(
            anchor: anchor.map(ModelChoice<TimeHint.Anchor>.init(raw:)),
            daypart: daypart.map(ModelChoice<Daypart>.init(raw:)),
            weekday: weekday.map(ModelChoice<Weekday>.init(raw:)),
            month: month,
            season: season.map(ModelChoice<TimeHint.Season>.init(raw:)),
            count: count,
            repeatEvery: repeatEvery,
            repeatUnit: repeatUnit.map(ModelChoice<TimeHint.RepeatUnit>.init(raw:))
        )
    }

    static func draft(_ mapping: DraftMapping) -> IngestionDraft? {
        if case let .draft(draft) = mapping.outcome { return draft }
        return nil
    }
}

@Suite("AC-M2-01 draft mapping per PRD item type (FR-A1, D-016)")
struct DraftMappingItemTypeTests {
    typealias F = MappingFixtures

    /// The user's sentence for all four scripted outputs.
    static let input = "Post the parcel tomorrow, clean the bathroom every Saturday, we need dishwasher pods this "
        + "week, and wash the car on the driveway this weekend in the morning if it's dry."

    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var item: ItemSnapshot
        var zone: String
        var now: Date
        // Expected
        var kind: TaskKind
        var room: DraftRoom
        var effort: Effort
        var isCritical: Bool
        var isDeepClean: Bool
        var isWeatherDependent: Bool
        var dayparts: Set<Daypart>
        var weekdays: Set<Weekday>
        var start: Date
        var end: Date
        var interval: Int?
        var sourcePhrase: String?
        var testDescription: String { "\(name) (\(zone))" }
    }

    static let all = Set(Weekday.allCases)

    static func cases(zone: String, now: Date, windows: [(String, String)]) -> [Case] {
        [
            Case(name: "one-off errand", item: F.item(
                    title: "Post the parcel", kind: "oneOff", room: nil, effort: "low",
                    time: F.hint(anchor: "tomorrow"), sourcePhrase: "Post the parcel tomorrow"),
                 zone: zone, now: now, kind: .oneOff, room: .none, effort: .low,
                 isCritical: false, isDeepClean: false, isWeatherDependent: false,
                 dayparts: Daypart.defaultAllowed, weekdays: all,
                 start: F.utc(windows[0].0), end: F.utc(windows[0].1), interval: nil,
                 sourcePhrase: "Post the parcel tomorrow"),
            Case(name: "recurring maintenance", item: F.item(
                    title: "Clean the bathroom", kind: "recurring", room: "the bathroom", effort: "normal",
                    isDeepClean: true,
                    time: F.hint(anchor: "weekday", weekday: "saturday", repeatEvery: 1, repeatUnit: "week"),
                    sourcePhrase: "clean the bathroom every Saturday"),
                 zone: zone, now: now, kind: .recurring, room: .existing(F.bathroom.id), effort: .normal,
                 isCritical: false, isDeepClean: true, isWeatherDependent: false,
                 dayparts: Daypart.defaultAllowed, weekdays: [.saturday],
                 start: F.utc(windows[1].0), end: F.utc(windows[1].1), interval: 7,
                 sourcePhrase: "clean the bathroom every Saturday"),
            Case(name: "consumable restock", item: F.item(
                    title: "Buy dishwasher pods", kind: "restock", room: "KITCHEN", effort: "low",
                    time: F.hint(anchor: "thisWeek"), sourcePhrase: "dishwasher pods"),
                 zone: zone, now: now, kind: .restock, room: .existing(F.kitchen.id), effort: .low,
                 isCritical: false, isDeepClean: false, isWeatherDependent: false,
                 dayparts: Daypart.defaultAllowed, weekdays: all,
                 start: F.utc(windows[2].0), end: F.utc(windows[2].1), interval: nil,
                 sourcePhrase: "dishwasher pods"),
            Case(name: "weather-dependent task", item: F.item(
                    title: "Wash the car", kind: "oneOff", room: "Driveway", effort: "high",
                    isWeatherDependent: true, time: F.hint(anchor: "thisWeekend", daypart: "morning"),
                    sourcePhrase: "wash the car on the driveway"),
                 zone: zone, now: now, kind: .oneOff, room: .proposed("Driveway"), effort: .high,
                 isCritical: false, isDeepClean: false, isWeatherDependent: true,
                 dayparts: [.morning], weekdays: [.saturday, .sunday],
                 start: F.utc(windows[3].0), end: F.utc(windows[3].1), interval: nil,
                 sourcePhrase: "wash the car on the driveway"),
        ]
    }

    /// The same four outputs at the same local time in two zones. The windows differ only through the injected zone.
    static let newYork = cases(zone: "America/New_York", now: F.newYorkNow, windows: [
        ("2026-11-24T05:00:00Z", "2026-11-25T05:00:00Z"),   // T5 tomorrow
        ("2026-11-28T05:00:00Z", "2026-11-29T05:00:00Z"),   // R5 / T7 next Saturday
        ("2026-11-23T15:00:00Z", "2026-11-30T05:00:00Z"),   // T10 this week: [now, mid(next Monday))
        ("2026-11-28T10:00:00Z", "2026-11-29T17:00:00Z"),   // T9 + morning: Sat 05:00 to Sun 12:00
    ])
    static let london = cases(zone: "Europe/London", now: F.londonNow, windows: [
        ("2026-11-24T00:00:00Z", "2026-11-25T00:00:00Z"),
        ("2026-11-28T00:00:00Z", "2026-11-29T00:00:00Z"),
        ("2026-11-23T10:00:00Z", "2026-11-30T00:00:00Z"),
        ("2026-11-28T05:00:00Z", "2026-11-29T12:00:00Z"),
    ])

    @Test("AC-M2-01: each PRD item type maps to a draft that passes the M1 initialiser with the expected fields",
          arguments: newYork + london)
    func itemType(_ c: Case) throws {
        let mapper = F.mapper(input: Self.input, now: c.now, zone: c.zone)
        let mapping = mapper.map(c.item, draftID: 4)
        let draft = try #require(F.draft(mapping), "\(mapping)")
        #expect(draft.draftID == 4)
        #expect(draft.kind == c.kind)
        #expect(draft.room == c.room)
        #expect(draft.effort == c.effort)
        #expect(draft.isCritical == c.isCritical)
        #expect(draft.isDeepClean == c.isDeepClean)
        #expect(draft.isWeatherDependent == c.isWeatherDependent)
        #expect(draft.allowedDayparts == c.dayparts)
        #expect(draft.allowedWeekdays == c.weekdays)
        #expect(draft.windowStart == c.start)
        #expect(draft.windowEnd == c.end)
        #expect(draft.recurrenceIntervalDays == c.interval)
        #expect(draft.sourcePhrase == c.sourcePhrase)
        #expect(draft.duplicate == .none)

        // The M1 initialiser accepts it, field for field.
        let roomID: UUID? = if case let .existing(id) = c.room { id } else { nil }
        let task = try draft.task(id: F.id("0000000000F1"), roomID: roomID)
        #expect(task.id == F.id("0000000000F1"))
        #expect(task.title == draft.title)
        #expect(task.kind == c.kind)
        #expect(task.roomID == roomID)
        #expect(task.effort == c.effort)
        #expect(task.isCritical == c.isCritical)
        #expect(task.isDeepClean == c.isDeepClean)
        #expect(task.isWeatherDependent == c.isWeatherDependent)
        #expect(task.allowedDayparts == c.dayparts)
        #expect(task.allowedWeekdays == c.weekdays)
        #expect(task.windowStart == c.start)
        #expect(task.windowEnd == c.end)
        #expect(task.recurrenceIntervalDays == c.interval)
        #expect(task.state == .active)
        #expect(task.completedAt == nil)
    }

    @Test("AC-M2-01: a critical bill keeps its flag and its window comes from the hint (T12 before December)")
    func criticalBill() throws {
        let item = F.item(title: "Pay the electricity bill", kind: "oneOff", effort: "low", isCritical: true,
                          time: F.hint(anchor: "beforeMonth", month: 12))
        let draft = try #require(F.draft(F.mapper(input: "pay the electricity bill before December")
            .map(item, draftID: 1)))
        #expect(draft.isCritical)
        #expect(!draft.isDeepClean)
        #expect(draft.windowStart == F.newYorkNow)
        #expect(draft.windowEnd == F.utc("2026-12-01T05:00:00Z"))
        _ = try draft.task(id: F.id("0000000000F2"), roomID: nil)
    }

    @Test("AC-M2-01: date fields depend only on the injected now, calendar and time zone (same inputs, same draft)")
    func datesOnlyFromInjectedInputs() throws {
        let item = Self.newYork[0].item
        let first = F.mapper(input: Self.input).map(item, draftID: 1)
        let second = F.mapper(input: Self.input).map(item, draftID: 1)
        #expect(first == second)
        // Moving `now` by one day moves the T5 window by exactly one local day.
        let later = F.mapper(input: Self.input, now: F.newYorkNow.addingTimeInterval(86_400)).map(item, draftID: 1)
        let draft = try #require(F.draft(later))
        #expect(draft.windowStart == F.utc("2026-11-25T05:00:00Z"))
        #expect(draft.windowEnd == F.utc("2026-11-26T05:00:00Z"))
        // A calendar whose firstWeekday is not Monday gives the same windows (Q6(a)).
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.firstWeekday = 1
        let mapper = DraftMapper(input: Self.input, rooms: F.rooms, now: F.newYorkNow, calendar: sundayFirst,
                                 timeZone: F.zone("America/New_York"))
        for c in Self.newYork {
            let d = try #require(F.draft(mapper.map(c.item, draftID: 1)))
            #expect(d.windowStart == c.start && d.windowEnd == c.end, "\(c.name)")
        }
    }
}

@Suite("AC-M2-02 Q5 repairs, one named case per step and the order between steps (FR-A1, D-016, T-07)")
struct DraftMappingRepairTests {
    typealias F = MappingFixtures

    // MARK: (1) Title

    @Test("Q5 (1): the title is trimmed and its whitespace runs collapse to one space",
          arguments: ["  Clean   the\toven \n", "Clean\u{00A0}the oven", "\nClean the\r\noven"])
    func titleTidied(_ raw: String) throws {
        let mapping = F.mapper(input: "clean the oven").map(F.item(title: raw), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.title == "Clean the oven")
        #expect(mapping.repairs.first == .titleTidied)
    }

    @Test("Q5 (1): an untouched title logs no repair")
    func titleUntouched() {
        let mapping = F.mapper(input: "post the parcel").map(F.item(), draftID: 1)
        #expect(!mapping.repairs.contains(.titleTidied))
        #expect(mapping.repairs == [.windowDefaulted(.noHint), .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 (1): a missing or blank title skips the item with a typed reason and nothing else runs",
          arguments: [nil, "", "   ", "\n\t ", "\u{00A0}"] as [String?])
    func titleMissing(_ raw: String?) {
        let mapping = F.mapper(input: "x").map(F.item(title: raw, kind: "chore", effort: "huge"), draftID: 1)
        #expect(mapping.outcome == .skipped(.noTitle))
        #expect(mapping.repairs.isEmpty)
    }

    // MARK: (2) Unknown values

    @Test("Q5 (2): unknown or missing kind → one-off; unknown or missing effort → normal",
          arguments: [("chore", "huge"), (nil, nil), ("OneOff", "Low"), ("", "")] as [(String?, String?)])
    func unknownEnums(_ kind: String?, _ effort: String?) throws {
        let mapping = F.mapper(input: "post the parcel").map(F.item(kind: kind, effort: effort), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .oneOff)
        #expect(draft.effort == .normal)
        #expect(mapping.repairs.prefix(2) == [.kindDefaulted, .effortDefaulted])
    }

    @Test("Q5 (2): a room text that folds to empty → none (room default)", arguments: ["", "   ", "the"] as [String])
    func roomBlank(_ raw: String) throws {
        let mapping = F.mapper(input: "post the parcel").map(F.item(room: raw), draftID: 1)
        let draft = try #require(F.draft(mapping))
        if raw == "the" {
            // "the" alone is not an article followed by more text, so it folds to "the": a proposed room.
            #expect(draft.room == .proposed("the"))
        } else {
            #expect(draft.room == .none)
            #expect(mapping.repairs.contains(.roomDefaulted))
        }
    }

    @Test("Q5 (2): missing flags default to false")
    func flagsDefault() throws {
        let draft = try #require(F.draft(F.mapper(input: "x post").map(
            F.item(isCritical: nil, isDeepClean: nil, isWeatherDependent: nil), draftID: 1)))
        #expect(!draft.isCritical && !draft.isDeepClean && !draft.isWeatherDependent)
    }

    @Test("Q5 (2)+(3): an unknown daypart element is dropped and the empty set becomes Daypart.defaultAllowed")
    func unknownDaypart() throws {
        let mapping = F.mapper(input: "x").map(F.item(time: F.hint(anchor: "tomorrow", daypart: "brunch")),
                                                draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.allowedDayparts == Daypart.defaultAllowed)
        #expect(draft.windowStart == F.utc("2026-11-24T05:00:00Z"))  // T5, not a slot
        #expect(mapping.repairs == [.daypartDropped, .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 (2)+(5): an unknown weekday element is dropped, so a weekday anchor has no weekday → T1 window")
    func unknownWeekday() throws {
        let mapping = F.mapper(input: "x").map(
            F.item(time: F.hint(anchor: "weekday", weekday: "Thursdayish")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.windowStart == F.newYorkNow)
        #expect(draft.windowEnd == F.newYorkNow.addingTimeInterval(7 * 86_400))
        #expect(draft.allowedWeekdays == Set(Weekday.allCases))
        #expect(mapping.repairs == [.weekdayDropped, .windowDefaulted(.fallback(.requiredFieldAbsent)),
                                    .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 (2): an unknown anchor, the reserved 'unrecognized' value, or a missing anchor in a present hint",
          arguments: [("someday", true), ("unrecognized", true), (nil, false)] as [(String?, Bool)])
    func anchors(_ raw: String?, _ unknown: Bool) throws {
        let mapping = F.mapper(input: "x").map(F.item(time: F.hint(anchor: raw, daypart: "evening")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.windowStart == F.newYorkNow)
        #expect(draft.windowEnd == F.newYorkNow.addingTimeInterval(7 * 86_400))
        #expect(draft.allowedDayparts == [.evening])  // the daypart still counts (PO Q-T2, T15)
        if unknown {
            #expect(mapping.repairs == [.anchorUnrecognized, .windowDefaulted(.fallback(.unrecognizedAnchor)),
                                        .weekdaysDefaulted])
        } else {
            #expect(mapping.repairs == [.anchorDefaulted, .weekdaysDefaulted])
        }
    }

    @Test("Q5 (2): unknown season and repeat unit are dropped")
    func unknownSeasonAndUnit() throws {
        let mapping = F.mapper(input: "x").map(F.item(kind: "recurring", time: F.hint(
            anchor: "beforeSeason", season: "monsoon", repeatEvery: 2, repeatUnit: "fortnight")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .oneOff)  // no repeat survives, so step 6 makes it a one-off
        #expect(draft.recurrenceIntervalDays == nil)
        #expect(mapping.repairs == [.seasonDropped, .repeatUnitDropped,
                                    .windowDefaulted(.fallback(.requiredFieldAbsent)), .becameOneOff,
                                    .daypartsDefaulted, .weekdaysDefaulted])
    }

    // MARK: (4) Critical + deep clean

    @Test("Q5 (4): critical + deep clean → critical; deep clean is cleared")
    func criticalWinsOverDeepClean() throws {
        let mapping = F.mapper(input: "x").map(F.item(isCritical: true, isDeepClean: true), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.isCritical)
        #expect(!draft.isDeepClean)
        #expect(mapping.repairs == [.deepCleanCleared, .windowDefaulted(.noHint), .daypartsDefaulted,
                                    .weekdaysDefaulted])
    }

    // MARK: (5) Window

    @Test("Q5 (5): no hint → [now, now + 7 days), and an out-of-range or invalid anchor falls back the same way",
          arguments: [
            (nil, TimeResolution.Basis.noHint),
            (MappingFixtures.hint(anchor: "inDays", count: 400), .fallback(.fieldOutOfRange)),
            (MappingFixtures.hint(anchor: "inDays", daypart: "night", count: 366), .fallback(.windowOutOfRange)),
            (MappingFixtures.hint(anchor: "beforeMonth", month: 13), .fallback(.fieldOutOfRange)),
            (MappingFixtures.hint(anchor: "inWeeks"), .fallback(.requiredFieldAbsent)),
          ] as [(TimeHintSnapshot?, TimeResolution.Basis)])
    func windowFallback(_ hint: TimeHintSnapshot?, _ basis: TimeResolution.Basis) throws {
        let mapping = F.mapper(input: "x").map(F.item(time: hint), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.windowStart == F.newYorkNow)
        #expect(draft.windowEnd == F.newYorkNow.addingTimeInterval(604_800))
        #expect(mapping.repairs.contains(.windowDefaulted(basis)))
    }

    // MARK: (6) Interval

    @Test("Q5 (6): a recurring item with no interval, or one outside 1…730 days, becomes a one-off with no interval",
          arguments: [(nil, nil), (25, "month"), (731, "day"), (3, "year")] as [(Int?, String?)])
    func recurringBecomesOneOff(_ every: Int?, _ unit: String?) throws {
        let mapping = F.mapper(input: "x").map(
            F.item(kind: "recurring", time: F.hint(repeatEvery: every, repeatUnit: unit)), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .oneOff)
        #expect(draft.recurrenceIntervalDays == nil)
        #expect(mapping.repairs.contains(.becameOneOff))
    }

    @Test("Q5 (6): a recurring item keeps an interval at the range ends 1 and 730",
          arguments: [(1, "day", 1), (730, "day", 730), (2, "year", 730), (24, "month", 720)])
    func recurringKeeps(_ every: Int, _ unit: String, _ days: Int) throws {
        let mapping = F.mapper(input: "x").map(
            F.item(kind: "recurring", time: F.hint(repeatEvery: every, repeatUnit: unit)), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .recurring)
        #expect(draft.recurrenceIntervalDays == days)
        #expect(!mapping.repairs.contains(.becameOneOff))
    }

    @Test("Q5 (6): a one-off or restock item with an interval → the interval is dropped", arguments: ["oneOff", "restock"])
    func intervalDropped(_ kind: String) throws {
        let mapping = F.mapper(input: "x").map(
            F.item(kind: kind, time: F.hint(repeatEvery: 1, repeatUnit: "week")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.recurrenceIntervalDays == nil)
        #expect(draft.kind.rawValue == kind)
        #expect(mapping.repairs == [.intervalDropped, .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 order (T-07): an unknown kind becomes a one-off (2), and then its interval is dropped (6)")
    func orderUnknownKindThenInterval() throws {
        let mapping = F.mapper(input: "x").map(
            F.item(kind: "chore", time: F.hint(repeatEvery: 1, repeatUnit: "week")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .oneOff)
        #expect(draft.recurrenceIntervalDays == nil)
        #expect(mapping.repairs == [.kindDefaulted, .intervalDropped, .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 order (E26, PO Q-T1): a one-off 'monthly on Thursday' drops {thursday} with the interval (6), and then weekdays become all seven and dayparts Daypart.defaultAllowed (3)")
    func orderE26() throws {
        let mapping = F.mapper(input: "x").map(F.item(kind: "oneOff", time: F.hint(
            anchor: "weekday", weekday: "thursday", repeatEvery: 1, repeatUnit: "month")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.windowStart == F.utc("2026-11-26T05:00:00Z"))
        #expect(draft.windowEnd == F.utc("2026-11-27T05:00:00Z"))
        #expect(draft.recurrenceIntervalDays == nil)
        #expect(draft.allowedWeekdays == Set(Weekday.allCases))
        #expect(draft.allowedDayparts == Daypart.defaultAllowed)
        #expect(mapping.repairs == [.intervalDropped, .repeatWeekdaysDropped, .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 (6): a recurring 'every 30 months on Thursday' (900 days) becomes a one-off and loses {thursday}")
    func recurringOutOfRangeDropsWeekday() throws {
        let mapping = F.mapper(input: "x").map(F.item(kind: "recurring", time: F.hint(
            anchor: "weekday", weekday: "thursday", repeatEvery: 30, repeatUnit: "month")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.kind == .oneOff)
        #expect(draft.allowedWeekdays == Set(Weekday.allCases))
        #expect(mapping.repairs == [.becameOneOff, .repeatWeekdaysDropped, .daypartsDefaulted, .weekdaysDefaulted])
    }

    @Test("Q5 (6): a recurring 'every Thursday' keeps {thursday} and logs no step 3 weekday default")
    func recurringKeepsWeekday() throws {
        let mapping = F.mapper(input: "x").map(F.item(kind: "recurring", time: F.hint(
            anchor: "weekday", weekday: "thursday", repeatEvery: 1, repeatUnit: "week")), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.allowedWeekdays == [.thursday])
        #expect(draft.recurrenceIntervalDays == 7)
        #expect(mapping.repairs == [.daypartsDefaulted])
    }

    // MARK: (7) Calm-words guard

    @Test("Q5 (7): a banned token the user did not say is removed from the title")
    func titleCalmed() throws {
        let mapping = F.mapper(input: "pay the electricity bill").map(
            F.item(title: "Pay the late electricity bill"), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.title == "Pay the electricity bill")
        #expect(mapping.repairs.contains(.titleCalmed))
    }

    @Test("Q5 (7): a banned token the user said is kept")
    func userWordsKept() throws {
        let mapping = F.mapper(input: "pay the late fee").map(F.item(title: "Pay the late fee"), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.title == "Pay the late fee")
        #expect(!mapping.repairs.contains(.titleCalmed))
    }

    @Test("Q5 (7): a title the guard empties takes the checked sourcePhrase; with none, the item is skipped")
    func titleFallback() throws {
        let input = "sort out the recycling"
        let kept = F.mapper(input: input).map(F.item(title: "Overdue!", sourcePhrase: "sort out the recycling"),
                                              draftID: 1)
        let draft = try #require(F.draft(kept))
        #expect(draft.title == "sort out the recycling")
        #expect(kept.repairs.contains(.titleFromSourcePhrase))

        let skipped = F.mapper(input: input).map(F.item(title: "Overdue!", sourcePhrase: "file the taxes"),
                                                 draftID: 1)
        #expect(skipped.outcome == .skipped(.calmWords(.noTitleWordsLeft)))
    }

    @Test("Q5 (7): a proposed room name is calmed; emptied → none")
    func roomCalmed() throws {
        let calmed = F.mapper(input: "x").map(F.item(room: "Behind shed"), draftID: 1)
        #expect(F.draft(calmed)?.room == .proposed("shed"))
        #expect(calmed.repairs.contains(.roomNameCalmed))
        let cleared = F.mapper(input: "x").map(F.item(room: "late"), draftID: 1)
        #expect(F.draft(cleared)?.room == DraftRoom.none)
        #expect(cleared.repairs.contains(.roomNameCleared))
    }

    @Test("R19-F3: a proposed name the guard cuts to an existing room's name stays proposed at parse time (AC-M2-04 literal), and commit puts it in the existing room without creating one (PO ruling 2b)")
    func guardCutToExistingRoom() throws {
        let mapping = F.mapper(input: "wipe the counters").map(
            F.item(title: "Wipe the counters", room: "late kitchen"), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.room == .proposed("kitchen"))
        #expect(mapping.repairs.contains(.roomNameCalmed))
        var made = 0
        let plan = RoomLinker.commitPlan(for: [draft.room], existing: F.rooms, makeID: {
            made += 1
            return F.id("0000000000C1")
        })
        #expect(plan.newRooms.isEmpty)
        #expect(plan.roomIDs == [F.kitchen.id])
        #expect(made == 0)
    }

    @Test("Q5 (7): an existing room whose user label holds a banned token links and is not guarded (Q19)")
    func userLabelLinks() throws {
        let den = Room(id: F.id("00000000000D"), name: "Late-night den")
        let mapping = F.mapper(input: "x", rooms: [den]).map(F.item(room: "late-night den"), draftID: 1)
        #expect(F.draft(mapping)?.room == .existing(den.id))
    }

    // MARK: (8) sourcePhrase

    @Test("Q5 (8): a sourcePhrase not in the input is dropped; one in the input (after folding) is kept as given",
          arguments: [("the KITCHEN bin", "Empty the kitchen bin", "the KITCHEN bin"),
                      ("buy milk", "Empty the kitchen bin", nil),
                      ("   ", "Empty the kitchen bin", nil)] as [(String, String, String?)])
    func sourcePhrase(_ phrase: String, _ input: String, _ expected: String?) throws {
        let mapping = F.mapper(input: input).map(F.item(title: "Empty bin", sourcePhrase: phrase), draftID: 1)
        let draft = try #require(F.draft(mapping))
        #expect(draft.sourcePhrase == expected)
        #expect(mapping.repairs.contains(.sourcePhraseDropped) == (expected == nil))
    }

    // MARK: (9) M1 initialiser

    @Test("Q5 (9): if the M1 initialiser still rejects the task, the item is skipped with the typed violation (only reachable with a non-finite now, which the pipeline never passes)",
          arguments: [Double.nan, .infinity, -.infinity])
    func initialiserRejects(_ seconds: Double) {
        let mapper = F.mapper(input: "x", now: Date(timeIntervalSinceReferenceDate: seconds))
        let mapping = mapper.map(F.item(), draftID: 1)
        #expect(mapping.outcome == .skipped(.taskRejected(.windowDateNotFinite)))
    }

    // MARK: Numbers from the model

    @Test("Model numbers: only finite whole numbers that fit Int survive (non-finite, fractional, huge → nil)",
          arguments: [(3.0, 3), (-2.0, -2), (0.0, 0), (2.5, nil), (.nan, nil), (.infinity, nil), (-.infinity, nil),
                      (9.3e18, nil), (-9.3e18, nil), (1e15, 1_000_000_000_000_000)] as [(Double, Int?)])
    func wholeNumbers(_ value: Double, _ expected: Int?) {
        #expect(ModelNumber.wholeNumber(value) == expected)
    }

    @Test("ModelChoice: exact raw-value match only; anything else is kept as unrecognized text")
    func modelChoice() {
        #expect(ModelChoice<TaskKind>(raw: "restock") == .known(.restock))
        #expect(ModelChoice<TaskKind>(raw: "Restock") == .unrecognized("Restock"))
        #expect(ModelChoice<TaskKind>(raw: " restock") == .unrecognized(" restock"))
        #expect(ModelChoice<TaskKind>(raw: "restock").value == .restock)
        #expect(ModelChoice<TaskKind>(raw: "x").value == nil)
    }

    // MARK: Draft contract

    @Test("IngestionDraft: draftID is the caller's number, and the duplicate marker starts as none")
    func draftContract() throws {
        let mapper = F.mapper(input: "x")
        let one = try #require(F.draft(mapper.map(F.item(), draftID: 1)))
        let two = try #require(F.draft(mapper.map(F.item(), draftID: 2)))
        #expect(one.draftID == 1 && two.draftID == 2)
        #expect(one.duplicate == .none)
    }

    // UX-3 names: every case name in Sources is covered by the AC-M2-12 vocabulary scan (CalmVocabularyScanTests).

    @Test("Each repair names its Q5 step, and the mapper logs repairs in its documented order of steps")
    func stepNumbers() {
        #expect(ItemRepair.titleTidied.step == 1)
        #expect(ItemRepair.kindDefaulted.step == 2)
        #expect(ItemRepair.weekdaysDefaulted.step == 3)
        #expect(ItemRepair.deepCleanCleared.step == 4)
        #expect(ItemRepair.windowDefaulted(.noHint).step == 5)
        #expect(ItemRepair.repeatWeekdaysDropped.step == 6)
        #expect(ItemRepair.roomNameCleared.step == 7)
        #expect(ItemRepair.sourcePhraseDropped.step == 8)
        #expect(DraftMapper.stepOrder == [1, 2, 4, 5, 6, 3, 7, 8, 9])
    }
}
