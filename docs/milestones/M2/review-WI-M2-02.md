# M2 Code Review — WI-M2-02, PR #17 (`m2/nonfinite-date-invariant`)

- **Owner:** Reviewer (independent, fresh context)  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Reviewed:** `f26ffd7` (code) and `19ef5e2` (plan.md, PO ruling, docs only), diffed against `origin/main` (`dd4d9ad`).
- **Scope:** AC-M2-02 (W2-F3 clause), brief Q9, plan T-21 / R-c, design.md Addendum A; regression against AC-M1-06,
  AC-M1-07, AC-M1-25, AC-M1-04.

## Summary
`TaskInvariantViolation` gains `windowDateNotFinite`. It has no associated value and sits after `noAllowedWeekdays`
and before `windowEndNotAfterStart`, exactly as the Designer's Addendum A says. `HouseholdTask.firstInvariantViolation()`
checks finiteness in that position (`HouseholdTask.swift:84`), before the `end > start` comparison, which NaN would
otherwise fail. Construction and `init(from:)` share this check. `InMemoryHouseholdRepository` now checks every task
against the invariants on `save` and `upsertTask`, and stores nothing on failure (`InMemoryHouseholdRepository.swift:23-24,
30, 42`). The JSON file store has no code change. Its behaviour is pinned by tests: `unreadableFile` on load,
`writeUnsuccessful` on save.

The PO's ruling, recorded in `plan.md` (`19ef5e2`, lines 195-203), accepts both open questions:
- Q1: `unreadableFile` is an acceptable typed AC-M1-06 error for a hand-written non-finite file.
- Q2: the two stores may throw different errors for values set through internal setters. AC-M1-07 is unchanged.

So the code matches the brief AC-M2-02 clause and the plan as amended. No Blocker or Major.

**Evidence (run by the Reviewer):**
- I ran `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` on `f26ffd7` (Linux, `swift:6.2-noble`
  Docker). Result: exit 0, "✔ Test run with 141 tests in 18 suites passed after 127.669 seconds", 0 warnings, 0 `✘`.
- I ran my own mutants on a copy of the package, then reverted them. Each was run with
  `--filter "NonFinite|Invariant|ZeroGuilt|FileRepository"`. The baseline on that filter was 49/49 green. Every mutant
  was killed:

| Mutant | Result |
|---|---|
| M1: finiteness check disabled (`if false`) | red, 92 issues |
| M2: only `windowStart` checked (end unchecked) | red, 42 issues |
| M3: finiteness check moved after the `end > start` check (wrong position) | red, 63 issues |
| M4: in-memory `upsertTask` guard removed | red, 20 issues |
| M5: in-memory `save` stores before checking (non-atomic) | red, 6 issues |

## T-21: every changed M1 test, checked
| Test | Change | Verdict |
|---|---|---|
| `ZeroGuiltModelTests.invariantViolationCases` (`ZeroGuiltModelTests.swift:83`) | The exact ordered list adds `.windowDateNotFinite` in third place. The nine M1 cases keep their order. | Extension. Still an exact `==` on `allCases`. |
| `InvariantTests.casesCoverEveryInvariant` (`InvariantTests.swift:92`) | `count == 9` becomes `== 10`. Set equality is unchanged. 6 new construction rows. | Extension. The new count is exact, so it is not loosened. |
| `InvariantTests.violatingJSON` / `decodeThrows` (`InvariantTests.swift:131`) | New exhaustive-switch arm. Only that row uses the lenient decoder. `Fixtures.decode(using:)` defaults to `JSONDecoder()`, so the nine M1 rows are byte-for-byte as before. | Extension. |
| `FileRepositoryLoadErrorTests.invariantCases` / `invariantCoverage` (`FileRepositoryLoadErrorTests.swift:95, 161`) | The nine M1 rows still expect `invalidTask(v)`. Coverage now asserts `covered == allCases − {windowDateNotFinite}`, `covered.count == 9`, the row count equals `allCases.count`, and the non-finite row expects `.unreadableFile`. | Equivalent for M1 and stricter overall. The PO accepted `unreadableFile` (Q1). |
| `FileRepositoryAtomicSaveTests.encodingFailureKeepsPreviousHousehold` (AC-M1-07, `FileRepositoryAtomicSaveTests.swift:118-136`) | The `-infinity` start / `referenceDate` end task is now made by setting fields through the `@testable` internal setters on a valid task, because the public init now refuses it. The values are the same as before. The assertions (`writeUnsuccessful`, bytes of A unchanged) are untouched. | Same assertion, same meaning: an encode failure part-way through B keeps A. The PO confirmed AC-M1-07 is unchanged (Q2). |

No M1 assertion was removed or weakened. No test is skipped or disabled.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| 1 | Minor | `docs/milestones/M2/plan.md:195-203`; `Packages/TendCore/Sources/TendCore/Persistence/InMemoryHouseholdRepository.swift:23-24,30,42` | The in-memory guard checks **all** invariants, not only finiteness. That is broader than the WI-M2-02 text. The PO's acceptance of the broader guard reached me through an Orchestrator message, but the amended plan text only records `invalidTask(.windowDateNotFinite)` for the in-memory store. I checked the behaviour: it does not break M1, the full suite is green, and no `TendCore` engine path (Rescheduler, Completion) builds an invalid task. It does mean the in-memory store refuses internally built invalid tasks that the file store would save (pre-existing M1 asymmetry, dev-notes follow-up). | The PO or Planner records in `plan.md` (WI-M2-02 bullet or Handoff log) that the all-invariants in-memory guard is accepted. Docs only. Not merge-blocking. | Open |
| 2 | Minor | `docs/milestones/M2/design.md` (whole file, Handoff log row); `docs/milestones/M2/plan.md:798` | The Designer's naming decision is in the repo only as the Developer's word-for-word transcription. `plan.md` has the Planner→Designer "sent" row but no Designer "accepted/returned" row. The content matches what the code does. The gap is provenance. | The Designer, or the Orchestrator on the Designer's behalf, adds a Handoff-log row that confirms Addendum A. Not merge-blocking. | Open |
| 3 | Minor | `docs/milestones/M2/plan.md` (`19ef5e2`) | The PO ruling changed the WI-M2-02 bullet text but added no Handoff-log row (PO → Planner/Developer, date, AC refs), unlike the other PO decisions at `plan.md:794-799`. | Add a Handoff-log row for the 2026-11-21 WI-M2-02 ruling (AC-M2-02, Q9). | Open |
| 4 | Nit | `Packages/TendCore/Tests/TendCoreTests/NonFiniteDateInvariantTests.swift:190`; `Packages/TendCore/Tests/TendCoreTests/Support/Fixtures.swift:83` | `lenientDecoder()` duplicates `Fixtures.nonConformingDecoder()` (same strategy, same strings). | Use `Fixtures.nonConformingDecoder()` in both places. Optional. | Open |
| 5 | Nit | `NonFiniteDateInvariantTests.swift` (`decoderRefusesNonFiniteToken`, `#if os(Linux)` block) | The exact `DecodingError` kinds are asserted only on Linux. Darwin asserts only `is DecodingError`. This is declared in the dev-notes. macOS CI will run the weaker form. | None required. The Tester may note it for macOS CI evidence. | Open |

## Checklist
- [x] Correctness vs ACs: AC-M2-02 W2-F3 clause. The case exists and its name and position match the Designer.
  Construction throws it (6 + 9 parameterised cases). Model decode throws it (task and household). The file store
  rejects a hand-written file with typed `unreadableFile` and leaves the bytes unchanged (22 cases, through the
  AC-M1-06 harness). The in-memory store rejects with `invalidTask(.windowDateNotFinite)` and keeps its contents.
  "The parser never produces one" belongs to WI-M2-05 and is not in this PR.
- [x] Tests are meaningful. Five of my mutants were all killed. Boundary cases (±`greatestFiniteMagnitude`, `nextUp`,
  `1.797…e308` vs `1e309`) pin both sides.
- [x] Swift 6 concurrency is safe. The actor repository uses a synchronous check inside an isolated method, so there
  is no suspension between the check and the store. No `@unchecked Sendable` or `nonisolated(unsafe)`. The new test
  types are `Sendable`. 0 warnings with `-warnings-as-errors`.
- [x] No force unwraps or `try!` in product code.
- [x] Privacy (P-1…P-4): no network, no new import, `TendCore` is still Foundation-only (AC-M1-23 scan green).
- [x] UX-2/UX-3 are enforced in the engine. No overdue state. The banned-word scan of the added lines finds none
  (the only hit is the comment "no overdue state"). The folded `windowdatenotfinite` contains no banned substring.
- [n.a.] Accessibility (no UI).
- [x] Performance: the in-memory save is an O(n) check per save. That is negligible.
- [x] No new dependency, no ADR needed (ADR-0004 format unchanged).

## Open questions (noted; the PO has ruled)
- Q1 (`unreadableFile` vs `invalidTask` for files): the PO accepted `unreadableFile` (`plan.md`, `19ef5e2`).
- Q2 (the stores throw different errors for internally built non-finite tasks): the PO accepted it. AC-M1-07 is unchanged.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | Selection is unchanged. The NowSelector suites are green (AC-M2-13). |
| UX-3 Zero-Guilt | pass | The case name describes data, not conduct. No banned word or substring. No overdue state. Bad input fails calmly with a typed error and is never repaired or emptied. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI path. |
| P-2 No data leaves device (except user iCloud) | pass | No networking. Foundation-only (AC-M1-23 scan green). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Developer (via Orchestrator) | Reviewer | accepted | PR #17, `f26ffd7`, dev-notes WI-M2-02. |
| 2026-11-21 | Orchestrator | Reviewer | accepted | PO ruling on Q1/Q2, verified in `plan.md` at `19ef5e2` (docs only, no code change). |
| 2026-11-21 | Reviewer | Orchestrator → Merge Gatekeeper / Acceptance Tester | accepted | APPROVE. 0 Blocker, 0 Major, 3 Minor (docs provenance), 2 Nit. Full suite 141/141 green, 0 warnings. 5/5 Reviewer mutants killed. |
