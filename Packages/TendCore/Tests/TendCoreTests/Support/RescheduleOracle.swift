// Independent oracle for gentle rescheduling (rules R0–R4) and completion (AC-M1-03, AC-M1-17…21; FR-B2, UX-3;
// risk R-4).
//
// Written straight from the brief ("Rescheduling rules", "Effective state", "Window passed", "Next eligible window",
// AC-M1-03), apart from the production code. It calls no `TendCore` engine function: it reads public stored fields,
// builds expected tasks with the public validating initialiser (the model, not the engine), and uses a different
// method for every step:
// - `E(a, D)`: the brute-force 15-minute scan in `ContextOracle.nextAllowedStart` (production walks slot boundaries).
// - the recurring anchor "now + interval calendar days, same wall-clock time": day arithmetic on a UTC calendar (no
//   DST there), then solving `local = utc + offset` for the zone's offsets around that day with
//   `TimeZone.secondsFromGMT(for:)`; a wall time in a DST gap resolves to the transition instant (the first instant
//   that exists after it, brief Q11). Production uses `Calendar.date(bySettingHour:…, matchingPolicy: .nextTime,
//   repeatedTimePolicy: .first)` on the target day.

import Foundation
import TendCore

enum RescheduleOracle {
    struct OracleGap: Error, CustomStringConvertible {
        var description: String
    }

    /// The task rebuilt through the public initialiser with some fields replaced (everything else copied).
    static func rebuilt(
        _ task: HouseholdTask,
        state: TaskState? = nil,
        window: (start: Date, end: Date)? = nil,
        completedAt: Date?? = nil
    ) throws -> HouseholdTask {
        try HouseholdTask(
            id: task.id, title: task.title, kind: task.kind, roomID: task.roomID, effort: task.effort,
            isCritical: task.isCritical, isDeepClean: task.isDeepClean, isWeatherDependent: task.isWeatherDependent,
            allowedDayparts: task.allowedDayparts, allowedWeekdays: task.allowedWeekdays,
            windowStart: window?.start ?? task.windowStart, windowEnd: window?.end ?? task.windowEnd,
            recurrenceIntervalDays: task.recurrenceIntervalDays, state: state ?? task.state,
            completedAt: completedAt ?? task.completedAt
        )
    }

    /// `E(a, D)` by brute force: `s` from the oracle scan, `windowEnd = s + D`.
    static func nextWindow(for task: HouseholdTask, from anchor: Date, duration: TimeInterval, calendar: Calendar)
        throws -> (start: Date, end: Date)
    {
        guard let start = ContextOracle.nextAllowedStart(for: task, from: anchor, calendar: calendar) else {
            throw OracleGap(description: "no allowed slot within 16 days of \(anchor) for \(task.id)")
        }
        return (start, start.addingTimeInterval(duration))
    }

    /// R0–R4 applied to one task at `now`, in the brief's binding order.
    static func rescheduled(_ task: HouseholdTask, at now: Date, calendar: Calendar) throws -> HouseholdTask {
        var state = task.state
        switch state {
        case .completed:
            return task                                      // R0
        case .deferred(let until) where until > now:
            return task                                      // R0: resting
        case .deferred:
            state = .active                                  // R1: the rest is over
        case .active, .maintenance, .resurfaced:
            break
        }
        guard task.windowEnd <= now else {
            return try rebuilt(task, state: state)           // window open or upcoming: only R1 applies
        }
        let duration = task.windowEnd.timeIntervalSince(task.windowStart)
        let window = try nextWindow(for: task, from: now, duration: duration, calendar: calendar)
        if task.isDeepClean {
            state = .maintenance                             // R2
        } else if task.isCritical {
            state = .resurfaced                              // R3
        }                                                    // R4: state unchanged (active)
        return try rebuilt(task, state: state, window: window)
    }

    // MARK: Completion (AC-M1-03)

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()

    /// `now + days` calendar days at the same local wall-clock time in `calendar.timeZone` (brief Q14, Q11).
    static func sameWallClock(as now: Date, daysLater days: Int, calendar: Calendar) throws -> Date {
        let zone = calendar.timeZone
        let local = now.addingTimeInterval(Double(zone.secondsFromGMT(for: now)))  // local wall clock, read as UTC
        let parts = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: local)
        guard
            let year = parts.year, let month = parts.month, let day = parts.day,
            let hour = parts.hour, let minute = parts.minute, let second = parts.second,
            let midnight = utcCalendar.date(from: DateComponents(year: year, month: month, day: day)),
            let targetMidnight = utcCalendar.date(byAdding: .day, value: days, to: midnight)
        else { throw OracleGap(description: "cannot read the wall clock of \(now)") }
        let t = now.timeIntervalSinceReferenceDate
        let fraction = t - t.rounded(.down)
        let wallAsUTC = targetMidnight.addingTimeInterval(Double(hour * 3_600 + minute * 60 + second))

        // Every offset in force within a day either side; a wall time maps to `wallAsUTC - offset` when that instant
        // really has that offset.
        var offsets = Set<Int>()
        for probe in stride(from: -2 * 86_400, through: 2 * 86_400, by: 1_800) {
            offsets.insert(zone.secondsFromGMT(for: wallAsUTC.addingTimeInterval(Double(probe))))
        }
        let candidates = offsets.compactMap { offset -> Date? in
            let candidate = wallAsUTC.addingTimeInterval(Double(-offset))
            return zone.secondsFromGMT(for: candidate) == offset ? candidate : nil
        }.sorted()
        if let first = candidates.first {
            return first.addingTimeInterval(fraction)        // repeated wall time: its first occurrence
        }
        // A wall time in a DST gap: the first instant after the gap is the transition itself.
        let earliest = wallAsUTC.addingTimeInterval(Double(-(offsets.max() ?? 0)) - 1)
        guard let transition = zone.nextDaylightSavingTimeTransition(after: earliest) else {
            throw OracleGap(description: "wall time \(wallAsUTC) has no instant and no transition in \(zone.identifier)")
        }
        return transition
    }

    /// AC-M1-03 for one task: the expected completed task.
    static func completed(_ task: HouseholdTask, at now: Date, calendar: Calendar) throws -> HouseholdTask {
        switch task.kind {
        case .oneOff, .restock:
            return try rebuilt(task, state: .completed, completedAt: .some(now))
        case .recurring:
            guard let days = task.recurrenceIntervalDays else {
                throw OracleGap(description: "recurring task without interval")
            }
            let anchor = try sameWallClock(as: now, daysLater: days, calendar: calendar)
            let duration = task.windowEnd.timeIntervalSince(task.windowStart)
            let window = try nextWindow(for: task, from: anchor, duration: duration, calendar: calendar)
            return try rebuilt(task, state: .active, window: window, completedAt: .some(now))
        }
    }
}
