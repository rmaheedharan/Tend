# M2 Design Spec — addenda

- **Owner:** iOS Designer  ·  **Work items:** WI-M2-02  ·  **Status:** Ready (naming addendum only)

M2 has no user-facing surface of its own (plan "Design need"). This file holds the Designer's short addenda. A full
spec is not needed for WI-M2-02. The Developer recorded the decision below word for word, from the Designer's note.

## Addendum A — WI-M2-02 invariant case name (iOS Designer, 2026-11-21)

> # iOS Designer naming decision, WI-M2-02 (AC-M2-02 W2-F3, Q9, plan R-c), 2026-11-21
>
> Swift case (no associated value):
> ```swift
> /// `windowStart` or `windowEnd` is not a finite point in time (NaN or infinite interval), so the window cannot be placed.
> case windowDateNotFinite
> ```
> Position: directly after `noAllowedWeekdays` and before `windowEndNotAfterStart`. `firstInvariantViolation()` checks cases in order; a NaN window makes `end > start` false, so finiteness must be checked first to give the true reason. Both M1 stores agree.
> Associated value: none (all existing cases have none; enum is CaseIterable). Field detail, if ever needed, goes in `HouseholdStoreError.invalidTask(…)`.
> Reason: follows the `window…` + plain-state style; describes data, not conduct; calm if surfaced.
> Law Check: UX-3 pass (folded `windowdatenotfinite` has no banned word or substring; no overdue state). UX-1/2/4, P-1..P-4 n.a.

## Law Check (this file)

| Law | Status | Note |
|---|---|---|
| UX-1 | n.a. | No entry surface. |
| UX-2 | n.a. | No selection surface. |
| UX-3 | pass | The case name has no banned word or substring and adds no overdue state (Designer's check above). |
| UX-4 | n.a. | No UI. |
| P-1…P-4 | n.a. | A model invariant only. |

## Handoff log

| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-21 | iOS Designer | Developer | accepted | Name and position for WI-M2-02 (R-c), recorded word for word by the Developer. |
