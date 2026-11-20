// Seeded property-test corpus for the Rule-of-Three selector (AC-M1-14, AC-M1-15, AC-M1-16; FR-B1, UX-2).
//
// Each case is a valid household from `HouseholdGenerator` (WI-M1-02) plus a random context: `now` (with a sub-second
// part, a quarter of them within ±12 h of a DST change in the chosen zone), a named time zone (whole, half and
// quarter-hour offsets, both hemispheres, with and without DST), weather and energy. The generator places windows
// around that `now`, so every window position occurs (ended, ends exactly at now, open, starts exactly at now,
// upcoming). Same seed, same case, on every platform. Built once per test process and shared by the tests.

import Foundation
import TendCore

struct SelectionCase: Sendable {
    var seed: UInt64
    var moment: Moment
    var household: Household

    var description: String {
        "seed \(seed), \(household.tasks.count) tasks, now \(moment.now.timeIntervalSinceReferenceDate) "
            + "in \(moment.timeZone.identifier), weather \(moment.weather), energy \(moment.energy)"
    }
}

enum SelectionCorpus {
    /// Named zones (tzdata), chosen for offsets and DST rules that stress slot arithmetic.
    static let zoneIdentifiers = [
        "UTC", "Europe/Berlin", "Europe/London", "America/New_York", "America/Los_Angeles", "America/St_Johns",
        "America/Santiago", "Asia/Kolkata", "Asia/Kathmandu", "Asia/Tokyo", "Asia/Tehran", "Australia/Lord_Howe",
        "Pacific/Auckland", "Pacific/Chatham", "Pacific/Kiritimati", "Pacific/Pago_Pago",
    ]

    /// AC-M1-14 gate: ≥ 1,000 households of 50–500 tasks.
    static let gateSeeds: ClosedRange<UInt64> = 1...1_000
    static let gateTaskCounts: ClosedRange<Int> = 50...500

    /// AC-M1-15: households of 0–49 tasks, so selections of 0, 1 and 2 items occur often.
    static let smallSeeds: ClosedRange<UInt64> = 100_001...101_000
    static let smallTaskCounts: ClosedRange<Int> = 0...49

    static let gate: Result<[SelectionCase], any Error> = Result {
        try gateSeeds.map { try makeCase(seed: $0, taskCounts: gateTaskCounts) }
    }

    static let small: Result<[SelectionCase], any Error> = Result {
        try smallSeeds.map { try makeCase(seed: $0, taskCounts: smallTaskCounts) }
    }

    static func makeCase(seed: UInt64, taskCounts: ClosedRange<Int>) throws -> SelectionCase {
        // A separate stream for the context, so the household for a seed is the generator's own household.
        var rng = SplitMix64(seed: seed ^ 0x5EED_C0DE_0000_0000)
        let zoneID = zoneIdentifiers[Int.random(in: 0..<zoneIdentifiers.count, using: &rng)]
        let zone = try SelectionFixtures.zone(zoneID)
        let threeYears = 3 * 365 * 86_400
        var now = HouseholdGenerator.defaultNow.addingTimeInterval(
            Double(Int.random(in: -threeYears...threeYears, using: &rng)) + rng.nextUnitInterval())
        if rng.chance(0.25), let change = zone.nextDaylightSavingTimeTransition(after: now) {
            now = change.addingTimeInterval(Double(Int.random(in: -43_200...43_200, using: &rng)) + rng.nextUnitInterval())
        }
        let weather = WeatherCondition.allCases[Int.random(in: 0..<WeatherCondition.allCases.count, using: &rng)]
        let energy = EnergyLevel.allCases[Int.random(in: 0..<EnergyLevel.allCases.count, using: &rng)]
        let moment = Moment(now: now, calendar: SelectionFixtures.gregorian(in: zone), timeZone: zone,
                            weather: weather, energy: energy)
        let household = try HouseholdGenerator.household(seed: seed, taskCountRange: taskCounts, now: now)
        return SelectionCase(seed: seed, moment: moment, household: household)
    }
}
