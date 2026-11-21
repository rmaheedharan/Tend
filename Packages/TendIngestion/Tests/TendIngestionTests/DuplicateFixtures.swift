// Shared builders for the duplicate-rule tests (AC-M2-07, AC-M2-08; brief Definitions "Duplicate shortlist",
// "Local duplicate re-check for cloud drafts", "Duplicate"). FR-A1. Plan WI-M2-07.
//
// Builders only: no rule logic lives here, so the oracles in the property files stay independent of production code.

import Foundation
import TendCore
@testable import TendIngestion

enum DupFixture {

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// `00000000-0000-0000-0000-<suffix>`; `suffix` is 12 hex digits.
    static func id(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? zeroUUID
    }

    /// A UUID made from two generator words (property tests).
    static func uuid(_ high: UInt64, _ low: UInt64) -> UUID {
        func byte(_ word: UInt64, _ index: Int) -> UInt8 { UInt8(truncatingIfNeeded: word >> (56 - 8 * index)) }
        return UUID(uuid: (byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3), byte(high, 4), byte(high, 5),
                           byte(high, 6), byte(high, 7), byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
                           byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)))
    }

    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
    static let end = Date(timeIntervalSinceReferenceDate: 815_604_800)

    /// The states a task can be in, with the flags its invariants need.
    enum StateChoice: CaseIterable, Sendable {
        case active, deferred, maintenance, resurfaced, completed
    }

    /// A valid task. `completed` uses the given kind when it is one-off or restock (M1: a recurring task never stays
    /// completed), and otherwise a one-off.
    static func task(
        _ id: UUID, _ title: String, kind: TaskKind = .oneOff, room: UUID? = nil, state: StateChoice = .active
    ) -> HouseholdTask {
        var kind = kind
        if state == .completed && kind == .recurring { kind = .oneOff }
        let built = try? HouseholdTask(
            id: id,
            title: title,
            kind: kind,
            roomID: room,
            effort: .normal,
            isCritical: state == .resurfaced,
            isDeepClean: state == .maintenance,
            windowStart: start,
            windowEnd: end,
            recurrenceIntervalDays: kind == .recurring ? 7 : nil,
            state: taskState(state),
            completedAt: state == .completed ? start : nil
        )
        // Every argument above satisfies the M1 invariants, so `built` is never nil; the fallback keeps the builder
        // total without a force unwrap.
        return built ?? fallbackTask(id)
    }

    static func taskState(_ choice: StateChoice) -> TaskState {
        switch choice {
        case .active: .active
        case .deferred: .deferred(until: end)
        case .maintenance: .maintenance
        case .resurfaced: .resurfaced
        case .completed: .completed
        }
    }

    private static func fallbackTask(_ id: UUID) -> HouseholdTask {
        // Unreachable in practice; a distinct title makes any use visible in a failing expectation.
        (try? HouseholdTask(id: id, title: "fallback", kind: .oneOff, effort: .normal, windowStart: start,
                            windowEnd: end))
            ?? { preconditionFailure("the M1 initialiser rejected a fixed valid task") }()
    }

    /// A draft as the mapper would emit it (fields that the duplicate rules do not read are fixed).
    static func draft(_ draftID: Int, _ title: String, room: DraftRoom = .none, kind: TaskKind = .oneOff)
        -> IngestionDraft {
        IngestionDraft(
            draftID: draftID, title: title, kind: kind, room: room, effort: .normal, isCritical: false,
            isDeepClean: false, isWeatherDependent: false, allowedDayparts: Daypart.defaultAllowed,
            allowedWeekdays: Set(Weekday.allCases), windowStart: start, windowEnd: end, recurrenceIntervalDays: nil,
            sourcePhrase: nil
        )
    }
}

/// SplitMix64 helpers for the duplicate property generators.
struct DupRandom {
    var g: SplitMix64
    var draws: UInt64 = 0

    init(seed: UInt64) { g = SplitMix64(seed: seed) }

    mutating func next() -> UInt64 {
        draws += 1
        return g.next()
    }
    mutating func chance(_ percent: UInt64) -> Bool { next() % 100 < percent }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func pick<T>(_ values: [T]) -> T { values[Int(next() % UInt64(values.count))] }
    mutating func uuid() -> UUID { DupFixture.uuid(next(), next()) }
}
