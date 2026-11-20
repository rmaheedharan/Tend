import Foundation

// Completion (AC-M1-03; FR-B1, FR-B2, FR-B3 data only; UX-3).

extension Household {
    /// Completes the task with `taskID` at `now`, in any state except `completed` (AC-M1-03):
    /// - a one-off or restock task becomes `completed` with `completedAt == now`; nothing else about it changes;
    /// - a recurring task becomes `active` (leaving `maintenance`, `resurfaced` or a deferral) on its next eligible
    ///   window `E(now + interval days, D)`, where "now + interval days" keeps the local wall-clock time in the injected
    ///   calendar and time zone (brief Q11, Q14); its stored effort and flags are kept and `completedAt == now`;
    /// - the task's room, if it is in this household, is tended now (`lastTendedAt == now`, FR-B3).
    ///
    /// `completedAt` is the latest completion only, never a history (design D-2). Returns `false`, and changes
    /// nothing, when no task has `taskID` or that task is already `completed` (the brief defines completion for
    /// non-completed tasks only). Pure: reads only its inputs, never the clock or the device calendar.
    @discardableResult
    public mutating func complete(
        _ taskID: HouseholdTask.ID, at now: Date, calendar: Calendar, timeZone: TimeZone
    ) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), tasks[index].state != .completed else {
            return false
        }
        let task = tasks[index]
        tasks[index] = task.completed(at: now, slots: SlotCalendar(calendar: calendar, timeZone: timeZone))
        if let roomID = task.roomID, let roomIndex = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[roomIndex].lastTendedAt = now
        }
        return true
    }
}

extension HouseholdTask {
    /// The task after completion at `now` (AC-M1-03 (a), (b)); rooms are the household's concern.
    func completed(at now: Date, slots: SlotCalendar) -> HouseholdTask {
        var result = self
        result.completedAt = now
        switch kind {
        case .oneOff, .restock:
            result.state = .completed
        case .recurring:
            // A recurring task always has an interval of at least one day (AC-M1-25); 1 is never used in practice.
            let days = recurrenceIntervalDays ?? 1
            let anchor = slots.sameWallClockTime(as: now, daysLater: days)
                ?? now.addingTimeInterval(Double(days) * 86_400)  // only if the calendar cannot resolve the day
            let window = nextEligibleWindow(
                from: anchor, duration: windowEnd.timeIntervalSince(windowStart), slots: slots)
            result.windowStart = window.windowStart
            result.windowEnd = window.windowEnd
            result.state = .active
        }
        return result
    }
}
