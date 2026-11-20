import Foundation

/// Gentle rescheduling (FR-B2, UX-3; brief "Rescheduling rules" R0–R4, Q4, Q5, Q12–Q14; AC-M1-17…21).
///
/// One pass at an injected `now` renegotiates every task whose window has ended, quietly and without keeping score:
/// - **R0** a completed task, or a resting deferral (`until > now`), is left exactly as it is, even if its window ended.
/// - **R1** a deferral whose rest is over (`until <= now`) becomes `active`; R2–R4 then apply if its window ended.
/// - **R2** a deep clean whose window ended steps down to `maintenance` (counted as low effort; its stored effort is
///   kept) on the next eligible window `E(now, D)`.
/// - **R3** a critical task whose window ended is `resurfaced` (brought back gently, ranked first by the selector) on
///   `E(now, D)`.
/// - **R4** any other task whose window ended stays `active` and moves to `E(now, D)`.
///
/// `D` is the task's own window length, so nothing shrinks or grows. In R2–R4 only the state and the window change;
/// every other field is kept. Nothing records that, how often or how far a task moved (design D-2), and nothing ranks
/// by time since a window ended (D-3). Pure and deterministic: it reads only its inputs (no clock, no device calendar,
/// no randomness), and a second pass at the same `now` changes nothing.
public enum Rescheduler {
    /// R0–R4 applied to every task of `household` at `now`. Task order, rooms and schema version are kept.
    public static func reschedule(
        _ household: Household, at now: Date, calendar: Calendar, timeZone: TimeZone
    ) -> Household {
        let slots = SlotCalendar(calendar: calendar, timeZone: timeZone)
        var result = household
        result.tasks = household.tasks.map { reschedule($0, at: now, slots: slots).task }
        return result
    }

    /// R0–R4 applied to one task at `now`, with the reason code for what happened.
    public static func reschedule(
        _ task: HouseholdTask, at now: Date, calendar: Calendar, timeZone: TimeZone
    ) -> (task: HouseholdTask, outcome: RescheduleOutcome) {
        reschedule(task, at: now, slots: SlotCalendar(calendar: calendar, timeZone: timeZone))
    }

    /// R0–R4 in the brief's binding order, on a slot calendar built once per pass.
    static func reschedule(
        _ task: HouseholdTask, at now: Date, slots: SlotCalendar
    ) -> (task: HouseholdTask, outcome: RescheduleOutcome) {
        // R0: completed, or resting (`until > now`): untouched, even with an ended window (brief Q12).
        if task.state == .completed || task.isResting(at: now) {
            return (task, .unchanged)
        }
        var result = task
        // R1: the rest is over, so the task is simply active again (design D-1: "rest ended", never "lapsed").
        let restEnded = task.isRestOver(at: now)
        if restEnded {
            result.state = .active
        }
        guard result.windowHasEnded(at: now) else {
            return (result, restEnded ? .restEnded : .unchanged)
        }
        // R2–R4: the next eligible window from `now`, keeping the task's own duration `D`.
        let window = result.nextEligibleWindow(
            from: now, duration: result.windowEnd.timeIntervalSince(result.windowStart), slots: slots)
        result.windowStart = window.windowStart
        result.windowEnd = window.windowEnd
        let outcome: RescheduleOutcome
        if result.isDeepClean {
            result.state = .maintenance                 // R2
            outcome = .lightened
        } else if result.isCritical {
            result.state = .resurfaced                  // R3
            outcome = .broughtBackGently
        } else {
            outcome = .movedToNextWindow                // R4: state stays active
        }
        return (result, outcome)
    }
}

extension HouseholdTask {
    /// The tone of any prompt about this task (AC-M1-18, design.md): always `gentle`. A fixed marker, computed rather
    /// than stored, so it can never rise or vary between passes.
    public var promptTone: PromptTone { .gentle }
}
