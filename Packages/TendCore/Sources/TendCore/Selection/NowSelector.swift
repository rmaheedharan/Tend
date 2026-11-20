import Foundation

/// The Rule-of-Three selector (FR-B1, UX-2; AC-M1-13…16). This is the only public "what to do now" API in `TendCore`,
/// and it returns a `NowSelection`, which can never hold more than three tasks.
///
/// Pure and deterministic: it reads only its inputs, never the clock or the device settings, uses no randomness, never
/// changes a task and never reschedules (brief Q13). Tasks whose window has ended are not valid here; callers run the
/// rescheduler first (WI-M1-04, M3 wiring).
public enum NowSelector {
    /// The first `min(3, n)` of the `n` tasks that are contextually valid in `moment`, ordered by the fixed AC-M1-16 key:
    /// (1) `resurfaced` first; (2) earlier `windowEnd`; (3) critical before non-critical; (4) ascending
    /// `id.uuidString`. If two tasks share an ID, only the better-ranked one can be chosen.
    public static func select(from household: Household, in moment: Moment) -> NowSelection {
        select(from: household.tasks, in: moment)
    }

    /// As `select(from:in:)` for a household, over any list of tasks.
    public static func select(from tasks: [HouseholdTask], in moment: Moment) -> NowSelection {
        let slots = SlotCalendar(calendar: moment.calendar, timeZone: moment.timeZone)
        let slotOfNow = slots.slot(containing: moment.now)

        // Keep the best `capacity` valid tasks in ranked order, in one pass (no full sort of the household).
        var chosen: [HouseholdTask] = []
        chosen.reserveCapacity(NowSelection.capacity + 1)
        for task in tasks where task.isContextuallyValid(in: moment, slotOfNow: slotOfNow) {
            if let index = chosen.firstIndex(where: { $0.id == task.id }) {
                guard ranksBefore(task, chosen[index]) else { continue }
                chosen.remove(at: index)
            }
            let position = chosen.firstIndex(where: { ranksBefore(task, $0) }) ?? chosen.count
            guard position < NowSelection.capacity else { continue }
            chosen.insert(task, at: position)
            if chosen.count > NowSelection.capacity {
                chosen.removeLast()
            }
        }
        return NowSelection(items: chosen) ?? .empty
    }

    /// The fixed AC-M1-16 ordering (brief Q7). No score, priority or weight, and nothing that grows with time (D-3).
    static func ranksBefore(_ lhs: HouseholdTask, _ rhs: HouseholdTask) -> Bool {
        let lhsResurfaced = lhs.state == .resurfaced
        let rhsResurfaced = rhs.state == .resurfaced
        if lhsResurfaced != rhsResurfaced { return lhsResurfaced }
        if lhs.windowEnd != rhs.windowEnd { return lhs.windowEnd < rhs.windowEnd }
        if lhs.isCritical != rhs.isCritical { return lhs.isCritical }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
