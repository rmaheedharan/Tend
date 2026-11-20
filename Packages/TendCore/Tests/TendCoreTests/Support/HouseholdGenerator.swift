// Seeded generator of **valid** households for property tests (WI-M1-02, AC-M1-05; reused by AC-M1-14, AC-M1-21).
//
// Every task it makes satisfies the model invariants (brief "Model invariants", Q15): it goes through the throwing
// initialiser, so an invalid combination would fail the test instead of being silently produced. Across a run of seeds
// it covers every task kind, every critical/deep-clean flag combination the invariants allow, the weather flag, every
// lifecycle state, every daypart and weekday (in random non-empty sets), every window position relative to `now`, and
// dates with sub-second parts. `GeneratorTests` proves that coverage.

import Foundation
import TendCore

enum HouseholdGenerator {
    /// The `now` that window positions are generated around unless a test supplies its own.
    static let defaultNow = Fixtures.referenceDate

    /// Where a task's window sits relative to `now` (brief "Window open" / "Window passed", half-open windows).
    enum WindowPosition: CaseIterable, Sendable {
        /// `windowEnd < now`: the window has ended.
        case endedBeforeNow
        /// `windowEnd == now`: ended, on the boundary (brief Q13).
        case endsExactlyAtNow
        /// `windowStart < now < windowEnd`.
        case openAroundNow
        /// `windowStart == now`: open, on the boundary.
        case startsExactlyAtNow
        /// `windowStart > now`.
        case upcoming
    }

    /// Which flags a task carries. Critical and deep clean together is not allowed (AC-M1-25), so it is not a case.
    enum FlagSet: CaseIterable, Sendable {
        case plain
        case critical
        case deepClean
    }

    static let titles = [
        "Wipe the kitchen counters", "Pay the electricity bill", "Buy dishwasher tablets", "Water the balcony plants",
        "Clean the oven", "Post the parcel", "Change the bed sheets", "Descale the kettle", "Mow the lawn",
        "Café run: oat milk", "Fix the \"wobbly\" chair", "Back\\slash test", "Line one\nline two", "Tab\there",
        "Émile's bike ✨", "観葉植物に水をやる", "🧺 Laundry", "",
    ]

    static let roomNames = ["Kitchen", "Bathroom", "Living room", "Bedroom", "Balcony", "Hall", "Garage", "Garden", "Office"]

    /// A household for `seed`. `taskCount` fixes the number of tasks; otherwise it is drawn from `taskCountRange`.
    static func household(
        seed: UInt64,
        taskCount: Int? = nil,
        taskCountRange: ClosedRange<Int> = 0...500,
        now: Date = defaultNow
    ) throws -> Household {
        var rng = SplitMix64(seed: seed)
        let count = taskCount ?? Int.random(in: taskCountRange, using: &rng)
        let roomCount = Int.random(in: 0...roomNames.count, using: &rng)
        let rooms = (0..<roomCount).map { index in
            Room(
                id: uuid(using: &rng),
                name: roomNames[index],
                lastTendedAt: rng.chance(0.6) ? date(near: now, withinDays: 60, using: &rng) : nil
            )
        }
        let tasks = try (0..<count).map { _ in try task(using: &rng, rooms: rooms, now: now) }
        return Household(tasks: tasks, rooms: rooms)
    }

    /// One valid task. Throws only if the generator itself is wrong (it must never produce an invalid task).
    static func task(using rng: inout SplitMix64, rooms: [Room], now: Date = defaultNow) throws -> HouseholdTask {
        let kind = TaskKind.allCases[Int.random(in: 0..<TaskKind.allCases.count, using: &rng)]
        let flags = FlagSet.allCases[Int.random(in: 0..<FlagSet.allCases.count, using: &rng)]
        let isCritical = flags == .critical
        let isDeepClean = flags == .deepClean

        var states: [TaskState] = [
            .active,
            .deferred(until: date(near: now, withinDays: 10, using: &rng)),
            .completed,
        ]
        if isDeepClean { states.append(.maintenance) }
        if isCritical { states.append(.resurfaced) }
        let state = states[Int.random(in: 0..<states.count, using: &rng)]

        let (windowStart, windowEnd) = window(around: now, using: &rng)
        let completedAt: Date? =
            (state == .completed || rng.chance(0.3)) ? date(near: now, withinDays: 30, using: &rng) : nil

        return try HouseholdTask(
            id: uuid(using: &rng),
            title: titles[Int.random(in: 0..<titles.count, using: &rng)],
            kind: kind,
            roomID: (!rooms.isEmpty && rng.chance(0.8)) ? rooms[Int.random(in: 0..<rooms.count, using: &rng)].id : nil,
            effort: Effort.allCases[Int.random(in: 0..<Effort.allCases.count, using: &rng)],
            isCritical: isCritical,
            isDeepClean: isDeepClean,
            isWeatherDependent: rng.chance(0.3),
            allowedDayparts: nonEmptySubset(of: Daypart.allCases, using: &rng),
            allowedWeekdays: nonEmptySubset(of: Weekday.allCases, using: &rng),
            windowStart: windowStart,
            windowEnd: windowEnd,
            recurrenceIntervalDays: kind == .recurring ? Int.random(in: 1...90, using: &rng) : nil,
            state: state,
            completedAt: completedAt
        )
    }

    /// A window in a random `WindowPosition` relative to `now`, with a positive duration that has a sub-second part.
    static func window(around now: Date, using rng: inout SplitMix64) -> (start: Date, end: Date) {
        let position = WindowPosition.allCases[Int.random(in: 0..<WindowPosition.allCases.count, using: &rng)]
        let duration = positiveDuration(using: &rng)
        switch position {
        case .endedBeforeNow:
            let end = now.addingTimeInterval(-(positiveDuration(using: &rng)))
            return (end.addingTimeInterval(-duration), end)
        case .endsExactlyAtNow:
            return (now.addingTimeInterval(-duration), now)
        case .openAroundNow:
            let before = duration * (0.05 + 0.9 * rng.nextUnitInterval())
            let start = now.addingTimeInterval(-before)
            return (start, start.addingTimeInterval(duration))
        case .startsExactlyAtNow:
            return (now, now.addingTimeInterval(duration))
        case .upcoming:
            let start = now.addingTimeInterval(positiveDuration(using: &rng))
            return (start, start.addingTimeInterval(duration))
        }
    }

    /// A duration from about a millisecond to two weeks, always with a sub-second part, always > 0.
    static func positiveDuration(using rng: inout SplitMix64) -> TimeInterval {
        let wholeSeconds: [ClosedRange<Int>] = [0...0, 1...59, 60...3_600, 3_600...86_400, 86_400...1_209_600]
        let range = wholeSeconds[Int.random(in: 0..<wholeSeconds.count, using: &rng)]
        return Double(Int.random(in: range, using: &rng)) + 0.001 + 0.998 * rng.nextUnitInterval()
    }

    /// A date within `withinDays` days either side of `now`, with a sub-second part.
    static func date(near now: Date, withinDays days: Int, using rng: inout SplitMix64) -> Date {
        let seconds = Int.random(in: -(days * 86_400)...(days * 86_400), using: &rng)
        return now.addingTimeInterval(Double(seconds) + rng.nextUnitInterval())
    }

    static func nonEmptySubset<T: Hashable>(of all: [T], using rng: inout SplitMix64) -> Set<T> {
        let mask = Int.random(in: 1..<(1 << all.count), using: &rng)
        return Set(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
    }

    /// A deterministic UUID from the generator (no `UUID()`: same seed, same identifiers).
    static func uuid(using rng: inout SplitMix64) -> UUID {
        let high = rng.next()
        let low = rng.next()
        func byte(_ word: UInt64, _ index: Int) -> UInt8 { UInt8(truncatingIfNeeded: word >> (8 * index)) }
        return UUID(uuid: (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ))
    }

    /// Every date stored anywhere in a household, in a fixed order, for bit-exact comparison (AC-M1-05, R-7).
    static func allDates(in household: Household) -> [Date] {
        var dates: [Date] = []
        for task in household.tasks {
            dates.append(task.windowStart)
            dates.append(task.windowEnd)
            if case .deferred(let until) = task.state { dates.append(until) }
            if let completedAt = task.completedAt { dates.append(completedAt) }
        }
        for room in household.rooms {
            if let lastTendedAt = room.lastTendedAt { dates.append(lastTendedAt) }
        }
        return dates
    }
}
