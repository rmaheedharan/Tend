# Traceability Matrix

Owned by the Product Documenter; verified by the Acceptance Tester at every gate.
Every PRD requirement must reach a test and a doc. Empty cells in a milestone being gated are a gate blocker.

## Overview by milestone

| Req | Milestone | Story | Acceptance criterion | Test(s) / evidence | User doc | Status |
|---|---|---|---|---|---|---|
| FR-B1, FR-B2, FR-B3 (data), UX-2, UX-3, P-1, P-2 | M1 | S-M1-01…06 | AC-M1-01…25 | See "M1 detail" below | See "M1 detail" below | **PASS** (25/25, acceptance.md at `0a9eb87`); PO gate pending |
| FR-A1 | M2 | — | — | — | — | not started |
| FR-B1, FR-B3, FR-C1, FR-C2, FR-C3, UX-1, UX-4 | M3 | — | — | — | — | not started |
| FR-A2, FR-A3, FR-D1, FR-D2, FR-D3 | M4 | — | — | — | — | not started |
| FR-E1, FR-E2 | M5 | — | — | — | — | not started |

## M1 detail — Core Engine & Cognitive Shielding

Sources: [brief](../milestones/M1/brief.md) (stories, ACs), [plan](../milestones/M1/plan.md) (work items),
[acceptance](../milestones/M1/acceptance.md) (evidence). All tests are Swift Testing tests in
`Packages/TendCore/Tests/TendCoreTests/`, cited as `File: "display name"` (long names are shortened with "…").
**Evidence for every row:** RUN-CI, the push run on merge commit `6fff92c`
([run 44824227807](https://github.com/rmaheedharan/Tend/actions/runs/44824227807/job/136592581524)): 127 tests in
17 suites passed, 0 warnings; repeated in RUN-L (Linux container). Verified on Linux only; no device AC in M1.

Doc keys: **OV** = [TendCore architecture overview](../architecture/overview.md) (section named in brackets);
**R3** = [Why Tend shows you at most three things](explanation/rule-of-three.md);
**CR** = [Why nothing in Tend ever counts against you](explanation/compassionate-rescheduling.md);
ADRs are in [`docs/architecture/adr/`](../architecture/adr/).

| Req | Story | AC | WI | Test(s) | Doc | Status |
|---|---|---|---|---|---|---|
| FR-B1, FR-B2, FR-B3, UX-3 | S-M1-01 | AC-M1-01 | WI-M1-01 | `ModelTests`: "AC-M1-01: one task of each kind … is representable, Equatable and Codable"; "…every field combination allowed by the model invariants … round-trips through Codable"; "…every non-empty set of allowed dayparts and weekdays …"; "…Equatable distinguishes every stored field of HouseholdTask"; "AC-M1-01 / FR-B3: a Room carries an optional lastTendedAt …"; plus TaskState, Household, default dayparts and enum-case tests | OV [Model]; ADR-0001 | PASS |
| UX-3, FR-B2 | S-M1-01 | AC-M1-02 | WI-M1-01 | `SourceScanTests`: "AC-M1-02: no banned zero-guilt token in any identifier or string literal of TendCore/Sources"; `SourceScannerSelfTests`: "AC-M1-02 negative: …planted in an identifier…", "…planted in a string literal…", "…whole-token match ignores near-misses…", "…banned tokens inside comments are ignored…", "N-2: comment markers inside string literals…"; `ZeroGuiltModelTests`: "AC-M1-02: the lifecycle state is the closed set …", "AC-M1-02 / D-2: HouseholdTask stores exactly the fields …", "…the encoded HouseholdTask has exactly the naming-list keys", "…Room and Household store no counters or history" | OV [How UX-3 is enforced]; CR | PASS |
| FR-B1, FR-B2, FR-B3, UX-3 | S-M1-01 | AC-M1-03 | WI-M1-04 | `CompletionTests`: "AC-M1-03 (a): a one-off or restock task …", "AC-M1-03 (b): a recurring task becomes active on exactly E(now + interval days, D) …; incl. DST days", "AC-M1-03 (c): a task with no room … changes no room", "AC-M1-03: only the completed task changes …", "AC-M1-03 scope: …", "AC-M1-03: over 300 seeded households … independent oracle" | OV [Rescheduling]; CR ("When you finish a task") | PASS |
| FR-B1, FR-B2, P-2 | S-M1-02 | AC-M1-04 | WI-M1-02 | `RepositoryContractTests`: 12 "AC-M1-04 contract: …" tests × 2 implementations (in-memory, JSON file), plus "AC-M1-04 contract: a sequence of save, upsert, remove and update room gives the same household on both implementations" | OV [Persistence]; ADR-0004 | PASS |
| FR-B1, FR-B2 | S-M1-02 | AC-M1-05 | WI-M1-02 | `FileRepositoryRoundTripTests`: "AC-M1-05: 200 seeded households (0-500 tasks) round-trip through a new file repository instance exactly", "R-7 / AC-M1-05: awkward sub-second dates …"; `GeneratorTests`: "Generator: over the AC-M1-05 seeds every kind, flag, state … occurs, and every task is valid" | OV [Persistence]; ADR-0004 | PASS |
| FR-B1, FR-B2 | S-M1-02 | AC-M1-06 | WI-M1-02 | `FileRepositoryLoadErrorTests`: "AC-M1-06: a corrupt file … throws unreadableFile and is left byte-for-byte unchanged", "AC-M1-06: a file with an unknown schema version …", "AC-M1-25 / AC-M1-06: a file containing a task that violates an invariant …", "AC-M1-06: a path that is a directory …" | OV [Persistence]; ADR-0004 | PASS |
| FR-B1, FR-B2 | S-M1-02 | AC-M1-07 | WI-M1-02 | `FileRepositoryAtomicSaveTests`: "AC-M1-07: when a later save of B fails mid-way, loading returns A intact …", "…a failed upsert, remove or room update leaves A intact", "…when the very first save fails …", "…after a failed save, the next successful save …", "…a save whose encoding fails part-way …", "R-8 / AC-M1-07: the standard writer replaces the file by rename …", "…the write primitive is given the whole encoded household in one call …" | OV [Persistence]; ADR-0004 | PASS |
| FR-B1 | S-M1-03 | AC-M1-08 | WI-M1-03 | `ContextValidityTests`: "AC-M1-08: low energy accepts only low effort (incl. maintenance), normal adds normal, high accepts all"; `ReschedulerTests`: "AC-M1-17: the lightened deep clean counts as low effort …" | OV [Selection]; R3 ("What fits right now means") | PASS |
| FR-B1 | S-M1-03 | AC-M1-09 | WI-M1-03 | `ContextValidityTests`: "AC-M1-09: at each daypart boundary …; default dayparts are quiet at night", "AC-M1-09: one instant in two injected time zones …", "AC-M1-09: the injected time zone wins …"; `SlotCalendarTests` (R-3 / Q11 DST cases) | OV [Selection]; R3 | PASS |
| FR-B1 | S-M1-03 | AC-M1-10 | WI-M1-03 | `ContextValidityTests`: "AC-M1-10: a weekend-only task is valid on Saturday and Sunday only; the night slot belongs to the day it starts", "AC-M1-10: an instant that is Sunday 10:00 in one injected zone and Monday in another …" | OV [Selection]; R3 | PASS |
| FR-B1 | S-M1-03 | AC-M1-11 | WI-M1-03 | `ContextValidityTests`: "AC-M1-11: a weather-dependent task is valid only in clear or cloudy weather; others ignore the weather" | OV [Selection], [Injected inputs]; R3 | PASS |
| FR-B1, FR-B2 | S-M1-03 | AC-M1-12 | WI-M1-03 | `ContextValidityTests`: "AC-M1-12: state and half-open window boundaries decide validity exactly as the brief lists", "AC-M1-12: maintenance and resurfaced tasks with an open window are valid …"; `ZeroGuiltModelTests`: "D-1: isResting and isRestOver …", "Window helpers are half-open …" | OV [Model], [Selection]; R3 | PASS |
| UX-2, FR-B1 | S-M1-04 | AC-M1-13 | WI-M1-03 | `NowSelectorTests`: "AC-M1-13: NowSelection holds 0 to 3 items and cannot be constructed with 4 or more", "…rejects the same task twice", "…stores exactly three optional task slots …", "…the selector returns a NowSelection of 3 even when 100 tasks are valid", "AC-M1-13 / Q13: the selector returns tasks unchanged …"; API listing in dev-notes.md | OV [How UX-2 is enforced]; R3 | PASS |
| UX-2, FR-B1 | S-M1-04 | AC-M1-14 (Gate) | WI-M1-03 | `NowSelectorTests`: "AC-M1-14 (Gate): over 1,000 seeded households of 50-500 tasks every selection has at most 3 items, no duplicates, and every item passes the independent oracle" | OV [How UX-2 is enforced]; R3 | PASS |
| UX-2, FR-B1 | S-M1-04 | AC-M1-15 | WI-M1-03 | `NowSelectorTests`: "AC-M1-15: the selection size equals min(3, number of contextually valid tasks) …", "AC-M1-15: an empty household and a 500-task household with nothing valid give an empty selection without error" | OV [How UX-2 is enforced]; R3 | PASS |
| UX-2, FR-B1 | S-M1-04 | AC-M1-16 | WI-M1-03 | `NowSelectorTests`: "AC-M1-16: five resurfaced criticals compete …", "…equal windowEnd ties …", "…a non-resurfaced critical ranks after …", "…the order does not depend on the order of the household's tasks", "…over the property households and 500 tie-heavy households …" | OV [Selection]; R3 ("How Tend picks the three") | PASS |
| FR-B2, UX-3 | S-M1-05 | AC-M1-17 | WI-M1-04 | `ReschedulerTests`: "AC-M1-17: a deep clean whose window ended moves to maintenance on exactly E(now, D); stored effort unchanged", "AC-M1-17: the lightened deep clean counts as low effort …"; `SlotCalendarTests` (E(a, D) examples, DST) | OV [Rescheduling]; CR | PASS |
| FR-B2, UX-3 | S-M1-05 | AC-M1-18 | WI-M1-04 | `ReschedulerTests`: "AC-M1-18: a critical task whose window ended is brought back gently (resurfaced) on exactly E(now, D)", "AC-M1-18: a resurfaced task carries no escalation field …"; `ZeroGuiltModelTests`: "Design review: PromptTone has exactly one case, gentle" | OV [Rescheduling], [How UX-3 is enforced]; CR | PASS |
| FR-B2, UX-3 | S-M1-05 | AC-M1-19 | WI-M1-04 | `ReschedulerTests`: "AC-M1-19: any other task whose window ended stays active on exactly E(now, D) …", "AC-M1-19 / R1: …", "R0: …", "R1: …", "Window open or not yet open: …", "Rescheduler: the household version …", "Design list: RescheduleOutcome has exactly the five reason codes" | OV [Rescheduling]; CR | PASS |
| FR-B2, UX-3 | S-M1-05 | AC-M1-20 (Gate) | WI-M1-04 | `ReschedulerPropertyTests`: "AC-M1-20 (Gate): after N = 1…60 consecutive ended windows the decoded structure equals the structure after 1 pass; only the window moves"; "W3-F2 / Q21 measurement: across 2035-01-10 13:37:04Z (2^30 s) an odd-step duration changes exactly once by one 2^-23 s step …" | OV [How UX-3 is enforced]; CR | PASS |
| FR-B2, UX-3, UX-2 | S-M1-05 | AC-M1-21 (Gate) | WI-M1-04 | `ReschedulerPropertyTests`: "AC-M1-21 (Gate): over 500 seeded households of 50-500 tasks (at least half with ended windows) one pass equals the oracle, leaves no ended window, and is idempotent" | OV [Rescheduling]; CR | PASS |
| FR-B1, FR-B2, P-1, P-2 | S-M1-06 | AC-M1-22 | WI-M1-04 | `ReschedulerPropertyTests`: "AC-M1-22: identical inputs give identical selection and rescheduling outputs over 100 runs, and two RNG seeds give the same outputs" | OV [Injected inputs]; ADR-0001 | PASS |
| P-1, P-2 | S-M1-06 | AC-M1-23 | WI-M1-01 (scanner); every later WI keeps it green | `SourceScanTests`: "AC-M1-23: only `import Foundation`, no ambient time, randomness or networking API in TendCore/Sources"; `SourceScannerSelfTests`: "AC-M1-23 negative: imports other than Foundation are detected", "AC-M1-23 negative: every banned pattern planted in code is detected", "AC-M1-23 coverage: …every pattern in the closed list", "N-1: near-misses …", "AC-M1-23 negative: banned patterns in comments and plain string text are ignored", "Review F-2: `.now` with a receiver is not reported …", "AC-M1-23 positive: AsyncStream( … append/insert(contentsOf:) (Q23) are not reported" | OV [Injected inputs]; ADR-0001 | PASS |
| FR-B1, FR-B2 (gate line 1) | S-M1-06 | AC-M1-24 (Gate) | WI-M1-04 | RUN-CI on `6fff92c`: 127 tests / 17 suites, 0 failures, 0 skipped, 0 warnings; AC → test table in acceptance.md (every other AC maps to a named test, this table agrees) | OV [What was verified where]; [release notes M1](release-notes/M1.md) | PASS |
| FR-B1, FR-B2, UX-3 | S-M1-01 | AC-M1-25 | WI-M1-01 (+ WI-M1-02 decode path) | `InvariantTests`: "AC-M1-25: constructing a task that violates an invariant throws the typed violation", "…the cases cover all nine invariants …", "…values just inside each invariant are accepted (boundary)", "…when several invariants are broken …", "…decoding JSON that violates an invariant …", "…decoding a household whose file contains one invalid task …", "AC-M1-25 / AC-M1-02: an unknown lifecycle state in JSON is rejected …"; `FileRepositoryLoadErrorTests`: "AC-M1-25 / AC-M1-06: …", "AC-M1-25: the repository cases cover all nine invariants"; `ZeroGuiltModelTests`: "AC-M1-25 naming: TaskInvariantViolation has exactly the nine design-list cases" | OV [Model] | PASS |

### M1 laws

| Law | Stories | ACs that prove it | Extra evidence | Doc | Status |
|---|---|---|---|---|---|
| **UX-2** Rule of Three | S-M1-04 | AC-M1-13, 14, 15, 16 (and AC-M1-21 (f) after rescheduling) | Acceptance charter C-1: 697,500 tasks, up to 2,994 per household, 5-UUID adversary; no 4th item | OV [How UX-2 is enforced]; R3 | PASS |
| **UX-3** Zero-Guilt | S-M1-01, S-M1-05 | AC-M1-02, 03, 17, 18, 19, 20, 21, 25 | Design rules D-1…D-3 (Reviewer-checked by hand in every WI review); charters C-2 and C-3 | OV [How UX-3 is enforced]; CR | PASS |
| **P-1** On-device inference | S-M1-06 | AC-M1-23 (Foundation-only), AC-M1-22 | No AI in M1; charter C-5. P-1 is n.a. by scope; the engine has no inference and no network | OV [What TendCore is]; ADR-0001 | PASS (n.a. by scope; boundary proven) |
| **P-2** No data leaves the device | S-M1-02, S-M1-06 | AC-M1-23, AC-M1-04…07 | `FileRepositoryLoadErrorTests`: "W2-F1 / P-2: a repository refuses a URL that is not a local file URL before any read or write", "W2-F1: a file URL from a path is accepted"; charter C-4 (offline run, compiled-symbol check); weather injected only (Q22) | OV [Persistence], [Injected inputs]; ADR-0001; ADR-0004 | PASS |

### M1 code → AC (no orphan code)

| Source (`Packages/TendCore/Sources/TendCore/`) | ACs |
|---|---|
| `Model/HouseholdTask.swift`, `TaskState.swift`, `TaskKind.swift`, `Effort.swift`, `Daypart.swift`, `Weekday.swift`, `WeatherCondition.swift`, `Room.swift`, `Household.swift` | AC-M1-01, 02, 12, 25 |
| `Model/TaskInvariantViolation.swift` | AC-M1-25 |
| `Model/PromptTone.swift` | AC-M1-18 |
| `Persistence/HouseholdRepository.swift`, `InMemoryHouseholdRepository.swift`, `HouseholdStoreError.swift` | AC-M1-04, 06, 07 |
| `Persistence/JSONFileHouseholdRepository.swift` | AC-M1-04…07, 25; P-2 (W2-F1) |
| `Selection/Moment.swift`, `ContextValidity.swift` | AC-M1-08…12 |
| `Selection/SlotCalendar.swift` | AC-M1-09, 10, 03, 17…21 (`E(a, D)`) |
| `Selection/NowSelection.swift`, `NowSelector.swift` | AC-M1-13…16 |
| `Rescheduling/Rescheduler.swift`, `RescheduleOutcome.swift` | AC-M1-17…22 |
| `Rescheduling/Completion.swift` | AC-M1-03 |

**Check (Documenter, 2026-11-20):** 25 of 25 M1 ACs have at least one named test and a doc. No orphan AC. No
untested criterion. Every source file maps to an AC. I reran the suite on `0a9eb87` (Linux, Swift 6.2, `-warnings-as-errors`): `✔ Test run with 127 tests in 17 suites passed after 111.042 seconds.`, 0 warnings, 0 `✘`, and every AC-M1-01…23 and AC-M1-25 has at least one passing test whose name carries its ID. AC-M1-24 is the run itself.
