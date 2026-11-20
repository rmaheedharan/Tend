# M1 Design Spec — Core engine data model and vocabulary review (no UI)

- **Owner:** iOS Designer  ·  **Work items:** all M1 `TendCore` items (the work plan does not exist yet; the Work Planner
  should link this spec from every model, selector, rescheduler and repository item)  ·  **Status:** Ready
- **Inputs:** `docs/milestones/M1/brief.md` (v2, accepted by the Acceptance Tester on 2026-11-20), PRD §2 (UX-1…UX-4), FR-B1, FR-B2, FR-B3.
- **Verdict:** **APPROVED WITH MINOR.** The brief's vocabulary passes UX-3 and UX-2. There is no LAW-STOP. Three Minor
  design rules below (D-1…D-3) are binding on the Developer and the Reviewer.

## Intent
M1 has no screen, so this spec covers the words and shapes that every later screen will inherit. The engine's
vocabulary has to be one a calm person would use about a home. Nothing in the model counts, names or stores lateness
(UX-3), and nothing returns more than three things to do (UX-2). When the M3 UI turns engine output into copy, it
should be translating calm facts ("this moved to Saturday morning"). It should never have to soften a judgement
("this is 3 days late").

## Layout and hierarchy
Not applicable in M1 (no UI). The model shapes that later layouts depend on:
- **UX-2:** `NowSelection` holds at most 3 items, enforced by its type (AC-M1-13). M3 must render it as is. No view
  may concatenate, page or fetch more items. "More" in M3 means a reset or Room Pulse, never a longer list.
- **FR-B3:** `Room.lastTendedAt` is the only room-recency datum. M3 maps it to warmth and tint. The model gives no
  count of untended tasks per room.

## Vocabulary review (brief terms vs UX-3 / UX-2)
| Brief term | Where | Verdict | Note |
|---|---|---|---|
| States `active`, `deferred(until:)`, `maintenance`, `resurfaced`, `completed` | AC-M1-02 | pass | A closed set with no debt state. `resurfaced` reads as "came back gently". |
| "resting" (deferral with `until > now`) | Definitions, Q12 | pass, preferred | Warm, honours the user's choice. Use it in code (see naming list). |
| "lapsed deferral" | Definitions, R1 | Minor (D-1) | "Lapsed" implies a fault (a lapsed membership or a lapsed habit). Code should say the rest **ended**. The meaning is unchanged. |
| "window passed" | Definitions, R2–R4 | pass (Nit) | Neutral and allowed. In code prefer `windowHasEnded(at:)`, which is clearer and cannot be read as "passed or failed". |
| "missed tasks" | PRD gate line only | pass (handled) | The brief already bans it from code (AC-M1-02). It must also never appear in test names or log lines that become acceptance evidence, so use "window ended". |
| Kinds: one-off errand, recurring maintenance, consumable restock | AC-M1-01 | pass | Neutral. |
| Effort Low/Normal/High; Energy Low/Normal/High | Definitions, Q1 | pass | "Low energy" is a valid state, not a deficit. Later copy describes energy, never the person ("low effort" must never be attached to the user). |
| Dayparts morning/afternoon/evening/night, night quiet by default | Q2 | pass | Quiet nights support UX-3 and the "never an alarm" rule. |
| Weather `clear`, `cloudy`, `wet`, `severe`, `unknown` | AC-M1-11 | pass | `severe` describes the weather and is allowed **only** on the weather type, never on a task, state, prompt or error. |
| `critical` flag | Definitions, Q6 | pass (internal only) | Fine as a model flag. The word "critical" (and "urgent") must never reach UI copy; M3 copy states the fact ("due Friday"). |
| `maintenance` | Q5 | pass | Copy in M3 frames it as "a lighter version", never as a "downgrade". |
| Calm, fixed tone marker (AC-M1-18) | AC-M1-18 | pass | One constant value that never changes across passes. See the naming list. |
| Typed errors (AC-M1-06, 07, 25) | AC-M1-06/07/25 | pass with naming rule | `writeFailed` is banned (the brief's note). Use the names below. Errors are developer-facing; M3 maps any user-visible failure to calm copy. |
| Ranking "resurfaced first, then earliest `windowEnd`" | AC-M1-16 | pass | This is ordering only, not a score. No "priority", "urgency" or "score" that rises over time (D-3). |

## Binding naming list (Swift)
These names are binding for `TendCore` public API. Private helpers should follow the same vocabulary. The Developer
may change a type or case name only by recording the reason in the dev handoff note, and only if the new name passes
this table and the forbidden list.

| Concept | Type | Cases / members |
|---|---|---|
| Task | `struct HouseholdTask` (avoids clashing with `_Concurrency.Task`) | `id: UUID`, `title: String`, `kind: TaskKind`, `roomID: UUID?`, `effort: Effort`, `isCritical: Bool`, `isDeepClean: Bool`, `isWeatherDependent: Bool`, `allowedDayparts: Set<Daypart>`, `allowedWeekdays: Set<Weekday>`, `windowStart: Date`, `windowEnd: Date`, `recurrenceIntervalDays: Int?`, `state: TaskState`, `completedAt: Date?` |
| Kind | `enum TaskKind` | `oneOff`, `recurring`, `restock` |
| Lifecycle | `enum TaskState` | `active`, `deferred(until: Date)`, `maintenance`, `resurfaced`, `completed` (exactly these, AC-M1-02) |
| Effective state helper | on `HouseholdTask` | `isResting(at:)`, `isRestOver(at:)` (not "lapsed"), `windowIsOpen(at:)`, `windowHasEnded(at:)` |
| Effort | `enum Effort` | `low`, `normal`, `high` |
| Energy | `enum EnergyLevel` | `low`, `normal`, `high` |
| Daypart | `enum Daypart` | `morning`, `afternoon`, `evening`, `night` |
| Weekday | `enum Weekday` | `sunday` … `saturday` |
| Weather | `enum WeatherCondition` | `clear`, `cloudy`, `wet`, `severe`, `unknown` |
| Room | `struct Room` | `id: UUID`, `name: String`, `lastTendedAt: Date?` |
| Household | `struct Household` | `tasks`, `rooms`, `schemaVersion` |
| Moment / context | `struct Moment` (or `SelectionContext`) | `now`, `calendar`, `timeZone`, `weather`, `energy` |
| Rule-of-Three result | `struct NowSelection` | `items` (≤ 3, type-enforced), `isEmpty`, `static let capacity = 3` |
| Selector | `NowSelector` | `select(from:in:) -> NowSelection` (no other public "what to do now" API, AC-M1-13) |
| Rescheduler | `Rescheduler` (doc wording: "gentle rescheduling") | `reschedule(_:at:calendar:timeZone:) -> Household` |
| Completion | function | `complete(_:at:)` (sets `completedAt`, updates `lastTendedAt`) |
| Next window | function | `nextEligibleWindow(from:duration:)` |
| Tone marker (AC-M1-18) | `enum PromptTone` | **one case only:** `gentle`. It is never stored per pass and never varies. |
| Reschedule reason codes (optional; only if the Developer exposes per-task outcomes) | `enum RescheduleOutcome` | `unchanged`, `restEnded` (R1), `lightened` (R2 → maintenance), `broughtBackGently` (R3 → resurfaced), `movedToNextWindow` (R4) |
| Repository | `protocol HouseholdRepository` | impls `InMemoryHouseholdRepository`, `JSONFileHouseholdRepository` |
| Repository errors | `enum HouseholdStoreError` | `unreadableFile`, `unsupportedSchemaVersion(Int)`, `invalidTask(TaskInvariantViolation)`, `writeUnsuccessful` |
| Invariant errors (AC-M1-25) | `enum TaskInvariantViolation` | `noAllowedDayparts`, `noAllowedWeekdays`, `windowEndNotAfterStart`, `recurringWithoutInterval`, `intervalBelowOneDay`, `intervalOnNonRecurringTask`, `criticalAndDeepClean`, `maintenanceOnNonDeepClean`, `resurfacedOnNonCritical` |

## Forbidden names
**Scanned (AC-M1-02, whole token, identifiers and string literals):** `overdue`, `late`, `lateness`, `missed`,
`failed`, `behind`, `penalty`, `debt`, `streak`.

**Design-forbidden (Reviewer-enforced; not in the scanner; a hit is a Minor finding, or a Blocker if it adds a
lateness or escalation datum):**
- **Escalation and judgement:** `urgent`, `urgency`, `severity` (anywhere except the `WeatherCondition` type, which may
  use the case `severe`), `escalate`/`escalation`, `nag`, `alarm`, `alert`, `warning`, `neglected`, `stale`,
  `abandoned`, `slipped`, `lapsed`, `due`-as-state (`isDue`, `dueState`), `downgrade`, `demote`.
- **Lateness by another name (D-2, binding):** `rescheduleCount`, `deferCount`, `postponeCount`, `skipCount`,
  `attempts`, `timesMoved`, `originalWindowStart`/`originalWindowEnd`, `firstWindow`, `initialDueDate`, and any
  reschedule history array. Storing the original date lets someone compute "X days late" later, even though the size
  stays fixed (this goes beyond AC-M1-20).
- **Rule of Three bypass (UX-2):** no public `allValidTasks`, `candidates`, `nextUp`, `queue`, `backlog` or `todo`
  list API that returns "what to do now" items without the 3-cap. Internal candidate arrays are fine if they stay
  `internal`/`private`.
- **Scores that grow over time (D-3):** no `priority`, `score` or `weight` that increases with time since a window
  ended. Ranking is the fixed AC-M1-16 key.

## States
Not applicable in M1 (no UI). The M3 Now canvas spec will define Empty, Streaming, Normal, Model unavailable, Calm error
and Completed. Engine guarantee for M3: an empty `NowSelection` is a normal, calm result (AC-M1-15), not an error.

## Materials, colour, type
Not applicable in M1 (no UI).

## Motion and haptics
Not applicable in M1 (no UI).

| Event | Animation (spring params) | Reduce Motion fallback | Haptic |
|---|---|---|---|
| n.a. in M1 | — | — | — |

## Copy deck
M1 has **no user-facing strings**. String literals in `TendCore` are limited to coding keys and test fixture titles.
All copy will live in a **String Catalog (`Localizable.xcstrings`) in the app/UI layer from M3**. It will never live in
`TendCore`, which emits codes only.

Engine reason codes that a later UI will turn into copy, and how that copy must read (the keys reserve names; the
final wording is M3):

| Key (reserved for M3) | Engine source | Tone rule (zero-guilt) | Direction (draft, not final) |
|---|---|---|---|
| `now.resurfaced.prompt` | `TaskState.resurfaced` + `PromptTone.gentle` | Specific, factual, an offer; no "critical", "urgent" or "still". | "The electricity bill is due Friday. Want to handle it now?" |
| `now.maintenance.label` | `TaskState.maintenance` | A lighter version counts. Never "downgraded" or "reduced". | "A quick tidy counts this week." |
| `reschedule.moved` | `RescheduleOutcome.movedToNextWindow` | **Silent by default.** Quiet renegotiation means no message. If it is ever shown, it uses the future tense only. | (none; optional "Saved for Saturday morning.") |
| `reschedule.restEnded` | `RescheduleOutcome.restEnded` | **Silent.** The task simply becomes eligible again. | (none) |
| `now.empty` | empty `NowSelection` | Restful, not "all caught up" pressure. | "Nothing needs you right now." |
| `store.error.*` | `HouseholdStoreError` | Calm, about the app, never the user. No error-tone haptic. | "Tend couldn't open your household just now. Your data is safe." |

Also banned in M3 copy: anything that turns `lastTendedAt` into a count of neglect ("14 days since…"). How Room
Pulse shows recency is an M3 design decision.

## Accessibility
Not applicable in M1 (no UI). Note for M3: VoiceOver labels come from the same String Catalog keys and follow the same
tone rules.

## Design review of build
| Check | Result | Evidence (preview/screenshot) |
|---|---|---|
| Public API names match the binding naming list | pending (after build) | Dev handoff note public API listing (AC-M1-13) |
| No forbidden or design-forbidden names; no original-window or counter fields (D-2) | pending (after build) | AC-M1-02 scan log + Reviewer API inspection |
| `PromptTone` has exactly one case | pending (after build) | Source / test |
| Previews and screenshots | n.a. | No UI in M1 |

## Findings
| ID | Severity | Law | Finding | Required action |
|---|---|---|---|---|
| D-1 | Minor | UX-3 | The term "lapsed deferral" implies a fault. | In code use `isRestOver(at:)` / `restEnded`. Product meaning unchanged. The PO may update the brief wording when convenient. |
| D-2 | Minor (Blocker if violated in build) | UX-3 | AC-M1-20 stops growth but would not catch a fixed-size "original window" or a counter, which would allow lateness to be computed. | No original window, counter or history fields (forbidden list). Reviewer checks this. |
| D-3 | Minor (Blocker if violated in build) | UX-3, UX-2 | A future ranking score could add urgency that grows with time. | Ranking stays the AC-M1-16 key. No time-growing score fields. |

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface in M1. The model has no field the user must fill; room, effort, flags and recurrence are set by tests now and by on-device AI in M2 (FR-A1). |
| UX-2 Rule of Three | pass | `NowSelection` has a type-level cap of 3 (AC-M1-13…16). No public unbounded "what to do now" API (forbidden list). |
| UX-3 Zero-Guilt | pass | The state set has no debt state (AC-M1-02). The binding naming list plus D-1…D-3 close the gaps the scanner cannot see: renamed counters, original dates, growing scores. The tone marker is fixed (AC-M1-18). Reschedules are silent by default. |
| UX-4 Design craft | n.a. | No UI in M1 (M3). |
| P-1 On-device inference | n.a. | No AI in M1. The engine is Foundation-only (AC-M1-23). |
| P-2 No data leaves device (except user iCloud) | pass | No networking in `TendCore` (AC-M1-23). Local JSON store only. Weather is injected. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud use. |
| P-4 Media not persisted without consent | n.a. | No media in M1. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | iOS Designer | Orchestrator → Work Planner / Developer | accepted (APPROVED WITH MINOR) | Data-model and vocabulary review of brief v2. No LAW-STOP. Binding naming list and forbidden names issued. D-1 (say "rest ended", not "lapsed"), D-2 (no original-window, counter or history fields) and D-3 (no time-growing score) are binding for build and Reviewer inspection. Copy keys are reserved for the M3 String Catalog. |
