// The seeded valid-household generator is deterministic and covers what AC-M1-05 (and later AC-M1-14, AC-M1-21)
// require: every task kind, flag, state, non-empty daypart/weekday set, window position and sub-second dates.

import Foundation
import Testing
import TendCore

@Suite("Seeded household generator (AC-M1-05 support)")
struct GeneratorTests {

    @Test("SplitMix64 produces the published reference sequence for seed 0, so seeds replay on every platform")
    func splitMixReference() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test("Generator: the same seed gives the same household; different seeds give different ones")
    func deterministic() throws {
        for seed: UInt64 in [1, 2, 42, 9_999] {
            #expect(try HouseholdGenerator.household(seed: seed) == HouseholdGenerator.household(seed: seed),
                    "seed \(seed)")
        }
        #expect(try HouseholdGenerator.household(seed: 3) != HouseholdGenerator.household(seed: 4))
    }

    @Test("Generator: over the AC-M1-05 seeds every kind, flag, state, daypart, weekday and window position occurs, and every task is valid")
    func coverage() throws {
        let now = HouseholdGenerator.defaultNow
        var kinds = Set<TaskKind>()
        var efforts = Set<Effort>()
        var flagSets = Set<String>()
        var weatherFlags = Set<Bool>()
        var states = Set<String>()
        var dayparts = Set<Daypart>()
        var weekdays = Set<Weekday>()
        var daypartSets = Set<Set<Daypart>>()
        var positions = Set<String>()
        var deferralSides = Set<String>()
        var withRoom = 0, withoutRoom = 0, subSecond = 0, dates = 0, households = 0, tasks = 0

        for seed in FileRepositoryRoundTripTests.seeds {
            let household = try HouseholdGenerator.household(
                seed: seed, taskCount: FileRepositoryRoundTripTests.taskCount(for: seed))
            households += 1
            for task in household.tasks {
                tasks += 1
                kinds.insert(task.kind)
                efforts.insert(task.effort)
                flagSets.insert("critical=\(task.isCritical) deepClean=\(task.isDeepClean)")
                weatherFlags.insert(task.isWeatherDependent)
                dayparts.formUnion(task.allowedDayparts)
                weekdays.formUnion(task.allowedWeekdays)
                daypartSets.insert(task.allowedDayparts)
                if task.roomID == nil { withoutRoom += 1 } else { withRoom += 1 }
                switch task.state {
                case .active: states.insert("active")
                case .deferred(let until):
                    states.insert("deferred")
                    deferralSides.insert(until > now ? "resting" : "restOver")
                case .maintenance: states.insert("maintenance")
                case .resurfaced: states.insert("resurfaced")
                case .completed: states.insert("completed")
                }
                if task.windowEnd < now { positions.insert("endedBeforeNow") }
                if task.windowEnd == now { positions.insert("endsExactlyAtNow") }
                if task.windowStart < now && now < task.windowEnd { positions.insert("openAroundNow") }
                if task.windowStart == now { positions.insert("startsExactlyAtNow") }
                if task.windowStart > now { positions.insert("upcoming") }
                // Valid by construction; checked again here so a generator change cannot slip an invalid task in.
                #expect(throws: Never.self, "seed \(seed)") { _ = try Fixtures.decode(
                    HouseholdTask.self, fromJSONObject: try Fixtures.jsonObject(task)) }
            }
            for date in HouseholdGenerator.allDates(in: household) {
                dates += 1
                if date.timeIntervalSinceReferenceDate.rounded() != date.timeIntervalSinceReferenceDate { subSecond += 1 }
            }
        }
        print("Generator coverage: \(households) households, \(tasks) tasks, \(daypartSets.count) of 15 daypart sets, "
              + "\(subSecond) of \(dates) dates with a sub-second part")

        #expect(kinds == Set(TaskKind.allCases))
        #expect(efforts == Set(Effort.allCases))
        #expect(flagSets == ["critical=false deepClean=false", "critical=true deepClean=false",
                             "critical=false deepClean=true"])
        #expect(weatherFlags == [true, false])
        #expect(states == ["active", "deferred", "maintenance", "resurfaced", "completed"])
        #expect(deferralSides == ["resting", "restOver"])
        #expect(dayparts == Set(Daypart.allCases))
        #expect(weekdays == Set(Weekday.allCases))
        #expect(daypartSets.count == 15)
        #expect(positions == ["endedBeforeNow", "endsExactlyAtNow", "openAroundNow", "startsExactlyAtNow", "upcoming"])
        #expect(withRoom > 0 && withoutRoom > 0)
        #expect(subSecond > dates / 2)
    }
}
