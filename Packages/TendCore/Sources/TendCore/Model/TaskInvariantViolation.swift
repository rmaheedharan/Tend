import Foundation

/// Why a task could not be constructed or decoded (AC-M1-25, brief "Model invariants" and Q15).
/// Degenerate tasks are rejected, never silently repaired. Cases are listed, and checked, in this order.
/// Developer-facing only; a later UI maps any user-visible problem to calm copy (design.md).
public enum TaskInvariantViolation: Error, CaseIterable, Hashable, Sendable {
    /// `allowedDayparts` is empty, so the task could never fit a moment.
    case noAllowedDayparts
    /// `allowedWeekdays` is empty, so the task could never fit a moment.
    case noAllowedWeekdays
    /// `windowEnd` is not strictly after `windowStart` (windows are half-open and non-empty).
    case windowEndNotAfterStart
    /// A recurring task has no `recurrenceIntervalDays`.
    case recurringWithoutInterval
    /// A recurring task's interval is less than one day.
    case intervalBelowOneDay
    /// A one-off or restock task carries a recurrence interval.
    case intervalOnNonRecurringTask
    /// A task is flagged both critical and deep clean.
    case criticalAndDeepClean
    /// State `maintenance` on a task that is not a deep clean.
    case maintenanceOnNonDeepClean
    /// State `resurfaced` on a task that is not critical.
    case resurfacedOnNonCritical
}
