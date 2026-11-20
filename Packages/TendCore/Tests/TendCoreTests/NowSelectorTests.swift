// The Rule of Three (AC-M1-13…16; UX-2, FR-B1; brief Q7, Q13). The gate property (AC-M1-14) runs the selector over
// 1,000 seeded households of 50–500 tasks and checks every item against the independent oracle in
// `Support/ContextOracle.swift`. Failure messages name the seed so a case can be replayed.

import Foundation
import Testing
import TendCore

@Suite("Rule-of-Three selector (AC-M1-13…16)")
struct NowSelectorTests {
    static let berlin = "Europe/Berlin"

    static func wednesdayMorning() throws -> Date {
        try SelectionFixtures.local(2026, 11, 18, 10, in: berlin)
    }

    // MARK: AC-M1-13

    @Test("AC-M1-13: NowSelection holds 0 to 3 items and cannot be constructed with 4 or more")
    func capacityIsEnforcedByTheType() throws {
        #expect(NowSelection.capacity == 3)
        let now = try Self.wednesdayMorning()
        let tasks = try (1...10).map { try SelectionFixtures.openTask(id: $0, around: now) }
        for count in 0...3 {
            let selection = try #require(NowSelection(items: Array(tasks.prefix(count))), "\(count) items")
            #expect(selection.items == Array(tasks.prefix(count)), "order is kept")
            #expect(selection.count == count)
            #expect(selection.isEmpty == (count == 0))
        }
        for count in 4...10 {
            #expect(NowSelection(items: Array(tasks.prefix(count))) == nil, "\(count) items must be rejected")
        }
        #expect(NowSelection.empty.items.isEmpty && NowSelection.empty.isEmpty)
    }

    @Test("AC-M1-13: NowSelection rejects the same task twice")
    func duplicatesAreRejected() throws {
        let now = try Self.wednesdayMorning()
        let task = try SelectionFixtures.openTask(around: now)
        let other = try SelectionFixtures.openTask(id: 2, around: now)
        #expect(NowSelection(items: [task, task]) == nil)
        #expect(NowSelection(items: [task, other, task]) == nil)
    }

    @Test("AC-M1-13: NowSelection stores exactly three optional task slots, so a fourth item has nowhere to go")
    func storageIsThreeSlots() throws {
        let now = try Self.wednesdayMorning()
        let tasks = try (1...3).map { try SelectionFixtures.openTask(id: $0, around: now) }
        let selection = try #require(NowSelection(items: tasks))
        let children = Mirror(reflecting: selection).children
        print("AC-M1-13 NowSelection stored properties: \(children.map { "\($0.label ?? "?"): \(type(of: $0.value))" })")
        #expect(children.count == NowSelection.capacity)
        for child in children {
            #expect(child.value is HouseholdTask?, "\(child.label ?? "?") must be an optional task, not a list")
        }
    }

    @Test("AC-M1-13: the selector returns a NowSelection of 3 even when 100 tasks are valid")
    func selectorReturnsTheCappedType() throws {
        let now = try Self.wednesdayMorning()
        let tasks = try (1...100).map { try SelectionFixtures.openTask(id: $0, around: now) }
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let selection: NowSelection = NowSelector.select(from: Household(tasks: tasks, rooms: []), in: moment)
        #expect(selection.count == 3)
        #expect(NowSelector.select(from: tasks, in: moment) == selection, "both entry points agree")
    }

    @Test("AC-M1-13 / Q13: the selector returns tasks unchanged and does not move a task whose window ended")
    func selectorIsPure() throws {
        let now = try Self.wednesdayMorning()
        let ended = try SelectionFixtures.openTask(around: now, windowStart: now.addingTimeInterval(-7_200),
                                                   windowEnd: now.addingTimeInterval(-3_600))
        let open = try SelectionFixtures.openTask(id: 2, around: now, isCritical: true, state: .resurfaced)
        let household = Household(tasks: [ended, open], rooms: [])
        let before = household
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let selection = NowSelector.select(from: household, in: moment)
        #expect(selection.items == [open], "the returned task is the stored task, field for field")
        #expect(household == before)
        #expect(NowSelector.select(from: Household(tasks: [ended], rooms: []), in: moment).isEmpty,
                "a task whose window ended is not offered and not moved (the rescheduler does that)")
    }

    // MARK: AC-M1-14 (Gate)

    @Test("AC-M1-14 (Gate): over 1,000 seeded households of 50-500 tasks every selection has at most 3 items, no duplicates, and every item passes the independent oracle")
    func gateProperty() throws {
        let cases = try SelectionCorpus.gate.get()
        var sizes = [0, 0, 0, 0]
        var minTasks = Int.max, maxTasks = 0, totalTasks = 0, totalValid = 0, nearDST = 0
        var zones = Set<String>(), weathers = Set<WeatherCondition>(), energies = Set<EnergyLevel>()
        var statesSeen = Set<String>()

        for selectionCase in cases {
            let household = selectionCase.household
            let context = ContextOracle.Context(selectionCase.moment)
            let selection = NowSelector.select(from: household, in: selectionCase.moment)
            let items = selection.items
            minTasks = min(minTasks, household.tasks.count)
            maxTasks = max(maxTasks, household.tasks.count)
            totalTasks += household.tasks.count
            totalValid += ContextOracle.expectedSelection(from: household.tasks, in: context).valid
            zones.insert(selectionCase.moment.timeZone.identifier)
            weathers.insert(selectionCase.moment.weather)
            energies.insert(selectionCase.moment.energy)
            if let change = selectionCase.moment.timeZone.nextDaylightSavingTimeTransition(
                after: selectionCase.moment.now.addingTimeInterval(-43_200)),
               change.timeIntervalSince(selectionCase.moment.now) <= 43_200 {
                nearDST += 1
            }
            for task in household.tasks { statesSeen.insert(Self.stateName(task, at: selectionCase.moment.now)) }

            #expect(items.count <= 3, "more than 3 items: \(selectionCase.description)")
            #expect(Set(items.map(\.id)).count == items.count, "duplicate items: \(selectionCase.description)")
            for item in items {
                #expect(ContextOracle.isValid(item, in: context),
                        "item \(item.id) fails the oracle: \(selectionCase.description)")
                #expect(household.tasks.contains(item), "item not from the household: \(selectionCase.description)")
            }
            sizes[min(items.count, 3)] += 1
        }

        print("AC-M1-14 gate: seeds \(SelectionCorpus.gateSeeds.lowerBound)...\(SelectionCorpus.gateSeeds.upperBound), "
              + "\(cases.count) households, \(totalTasks) tasks (min \(minTasks), max \(maxTasks) per household), "
              + "\(totalValid) contextually valid per the oracle")
        print("AC-M1-14 gate: selection sizes 0/1/2/3 = \(sizes[0])/\(sizes[1])/\(sizes[2])/\(sizes[3]); "
              + "\(zones.count) time zones, \(weathers.count) weather values, \(energies.count) energy levels, "
              + "\(nearDST) moments within 12 h of a DST change; task states seen: \(statesSeen.sorted())")
        #expect(cases.count >= 1_000)
        #expect(minTasks >= 50 && maxTasks <= 500)
        #expect(sizes[3] > 0, "the corpus must exercise the cap")
    }

    /// Labels for the coverage log; "rest over" follows design D-1.
    static func stateName(_ task: HouseholdTask, at now: Date) -> String {
        switch task.state {
        case .active: "active"
        case .deferred(let until): until > now ? "deferred (resting)" : "deferred (rest over)"
        case .maintenance: "maintenance"
        case .resurfaced: "resurfaced"
        case .completed: "completed"
        }
    }

    // MARK: AC-M1-15

    @Test("AC-M1-15: the selection size equals min(3, number of contextually valid tasks) for 50-500 and 0-49 task households")
    func countIsMinOfThreeAndValid() throws {
        let cases = try SelectionCorpus.gate.get() + SelectionCorpus.small.get()
        var sizes = [0, 0, 0, 0]
        var emptyHouseholds = 0
        for selectionCase in cases {
            let context = ContextOracle.Context(selectionCase.moment)
            let valid = selectionCase.household.tasks.filter { ContextOracle.isValid($0, in: context) }.count
            let selection = NowSelector.select(from: selectionCase.household, in: selectionCase.moment)
            #expect(selection.count == min(3, valid), "\(valid) valid: \(selectionCase.description)")
            sizes[min(selection.count, 3)] += 1
            if selectionCase.household.tasks.isEmpty { emptyHouseholds += 1 }
        }
        print("AC-M1-15: seeds \(SelectionCorpus.gateSeeds) (50-500 tasks) and \(SelectionCorpus.smallSeeds) "
              + "(0-49 tasks), \(cases.count) households, \(emptyHouseholds) with no tasks; "
              + "selection sizes 0/1/2/3 = \(sizes[0])/\(sizes[1])/\(sizes[2])/\(sizes[3])")
        #expect(sizes.allSatisfy { $0 > 0 }, "every selection size 0…3 must occur")
    }

    @Test("AC-M1-15: an empty household and a 500-task household with nothing valid give an empty selection without error")
    func emptyAndAllInvalid() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        #expect(NowSelector.select(from: Household(tasks: [], rooms: []), in: moment) == .empty)

        // 500 generated tasks, looked at 100 years later: every window has ended, so nothing is valid.
        let household = try HouseholdGenerator.household(seed: 7, taskCount: 500, now: now)
        let later = try SelectionFixtures.moment(at: now.addingTimeInterval(100 * 365 * 86_400), in: Self.berlin)
        let context = ContextOracle.Context(later)
        #expect(household.tasks.allSatisfy { !ContextOracle.isValid($0, in: context) })
        #expect(NowSelector.select(from: household, in: later) == .empty)
    }

    // MARK: AC-M1-16

    @Test("AC-M1-16: five resurfaced criticals compete; only the three with the earliest windowEnd are returned, ahead of an earlier active task")
    func fiveResurfaced() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let hour: TimeInterval = 3_600
        let resurfaced = try [5, 2, 4, 1, 3].map { order in
            try SelectionFixtures.openTask(id: 10 + order, around: now, isCritical: true,
                                           windowEnd: now.addingTimeInterval(Double(order) * hour), state: .resurfaced)
        }
        let earlierActive = try SelectionFixtures.openTask(id: 1, around: now, isCritical: true,
                                                           windowEnd: now.addingTimeInterval(60))
        let selection = NowSelector.select(from: resurfaced + [earlierActive], in: moment)
        #expect(selection.items.map(\.id) == [11, 12, 13].map(Fixtures.id))
    }

    @Test("AC-M1-16: equal windowEnd ties go to critical tasks first, then ascending ID")
    func equalWindowEndTies() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let end = now.addingTimeInterval(7_200)
        let tasks = try [
            SelectionFixtures.openTask(id: 1, around: now, windowEnd: end),
            SelectionFixtures.openTask(id: 9, around: now, isCritical: true, windowEnd: end),
            SelectionFixtures.openTask(id: 2, around: now, windowEnd: end),
            SelectionFixtures.openTask(id: 5, around: now, isCritical: true, windowEnd: end),
        ]
        #expect(NowSelector.select(from: tasks, in: moment).items.map(\.id) == [5, 9, 1].map(Fixtures.id))
    }

    @Test("AC-M1-16: a non-resurfaced critical ranks after a non-critical with an earlier windowEnd, and before one with the same windowEnd")
    func criticalVersusNonCritical() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let critical = try SelectionFixtures.openTask(id: 1, around: now, isCritical: true,
                                                      windowEnd: now.addingTimeInterval(7_200))
        let earlier = try SelectionFixtures.openTask(id: 2, around: now, windowEnd: now.addingTimeInterval(3_600))
        let sameEnd = try SelectionFixtures.openTask(id: 0, around: now, windowEnd: now.addingTimeInterval(7_200))
        #expect(NowSelector.select(from: [sameEnd, critical, earlier], in: moment).items.map(\.id)
                == [2, 1, 0].map(Fixtures.id))
    }

    @Test("AC-M1-16: the order does not depend on the order of the household's tasks")
    func inputOrderDoesNotMatter() throws {
        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin)
        let tasks = try TieCorpus.tasks(seed: 77, count: 30, now: now)
        let expected = NowSelector.select(from: tasks, in: moment)
        var rng = SplitMix64(seed: 77)
        for round in 0..<50 {
            #expect(NowSelector.select(from: tasks.shuffled(using: &rng), in: moment) == expected, "shuffle \(round)")
        }
        #expect(NowSelector.select(from: tasks.reversed(), in: moment) == expected)
    }

    @Test("AC-M1-16: over the property households and 500 tie-heavy households the items are exactly the oracle's sorted first min(3, n)")
    func rankingMatchesOracle() throws {
        let corpus = try SelectionCorpus.gate.get() + SelectionCorpus.small.get()
        for selectionCase in corpus {
            let expected = ContextOracle.expectedSelection(
                from: selectionCase.household.tasks, in: ContextOracle.Context(selectionCase.moment)).items
            let items = NowSelector.select(from: selectionCase.household, in: selectionCase.moment).items
            #expect(items == expected, "\(selectionCase.description)")
        }

        let now = try Self.wednesdayMorning()
        let moment = try SelectionFixtures.moment(at: now, in: Self.berlin, energy: .low)
        var ties = 0, resurfacedSeen = 0
        for seed in TieCorpus.seeds {
            let tasks = try TieCorpus.tasks(seed: seed, now: now)
            let expected = ContextOracle.expectedSelection(from: tasks, in: ContextOracle.Context(moment))
            #expect(expected.valid == tasks.count, "tie corpus tasks are all valid (seed \(seed))")
            let items = NowSelector.select(from: tasks, in: moment).items
            #expect(items == expected.items, "tie corpus seed \(seed)")
            if Set(items.map(\.windowEnd)).count < items.count { ties += 1 }
            resurfacedSeen += items.filter { $0.state == .resurfaced }.count
        }
        print("AC-M1-16: \(corpus.count) property households (seeds \(SelectionCorpus.gateSeeds), "
              + "\(SelectionCorpus.smallSeeds)) and \(TieCorpus.seeds.count) tie-heavy households "
              + "(seeds \(TieCorpus.seeds)) match the oracle's order; \(ties) tie-heavy selections hold a windowEnd tie, "
              + "\(resurfacedSeen) resurfaced items selected")
        #expect(ties > 0 && resurfacedSeen > 0)
    }
}

/// Households in which every task is valid at `now` (Berlin, Wednesday morning, low energy) and windowEnd takes one of
/// three values, so the later keys of the AC-M1-16 sort (critical, ID) decide often.
enum TieCorpus {
    static let seeds: ClosedRange<UInt64> = 200_001...200_500

    static func tasks(seed: UInt64, count: Int? = nil, now: Date) throws -> [HouseholdTask] {
        var rng = SplitMix64(seed: seed)
        let total = count ?? Int.random(in: 3...40, using: &rng)
        return try (0..<total).map { _ in
            let flag = Int.random(in: 0..<3, using: &rng)  // plain, critical, deep clean
            let isCritical = flag == 1, isDeepClean = flag == 2
            var states: [TaskState] = [.active, .deferred(until: now.addingTimeInterval(-60))]
            if isCritical { states += [.resurfaced, .resurfaced] }
            if isDeepClean { states.append(.maintenance) }
            let state = states[Int.random(in: 0..<states.count, using: &rng)]
            let endHours = Double(Int.random(in: 1...3, using: &rng))
            return try HouseholdTask(
                id: HouseholdGenerator.uuid(using: &rng), title: "Tie", kind: .oneOff,
                effort: state == .maintenance ? .high : .low,
                isCritical: isCritical, isDeepClean: isDeepClean,
                allowedDayparts: Set(Daypart.allCases), allowedWeekdays: Set(Weekday.allCases),
                windowStart: now.addingTimeInterval(-86_400), windowEnd: now.addingTimeInterval(endHours * 3_600),
                state: state)
        }
    }
}
