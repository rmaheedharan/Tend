# M2 Developer Handoff — WI-M2-02

- **Owner:** Developer  ·  **PR:** not opened yet (branch `m2/nonfinite-date-invariant`)  ·  **ADRs:** ADR-0004 (file
  format, unchanged). No new ADR. No new dependency.

## WI-M2-02 — non-finite window dates become a model invariant (AC-M2-02 W2-F3 clause, Q9, T-21, R-c)

### What changed
- **`TendCore` model.** `TaskInvariantViolation` gains one case, `windowDateNotFinite`, with no associated value. The
  name, doc comment and position come from the iOS Designer ([design.md Addendum A](design.md), 2026-11-21). It sits
  after `noAllowedWeekdays` and before `windowEndNotAfterStart`. `HouseholdTask.firstInvariantViolation()` checks it
  in that position. NaN makes `windowEnd > windowStart` false, so without this order a NaN window would report
  `windowEndNotAfterStart`. Construction and `init(from:)` share the check, so both throw it.
- **`InMemoryHouseholdRepository`.** `save` and `upsertTask` now check every task against the model invariants and
  throw `HouseholdStoreError.invalidTask(firstViolation)`, storing nothing. A public caller cannot build such a task
  any more. The check guards against engine code in `TendCore` that sets a field through an `internal(set)` setter.
  This closes W2-F3: before, the in-memory store accepted a `±.infinity` date.
- **`JSONFileHouseholdRepository`.** No code change. What it does with non-finite dates is now pinned by tests (see
  below).
- **Foundation-only.** No new import. The source scans (AC-M1-02, AC-M1-23) still pass.

### What Foundation does with non-finite dates (Linux, Swift 6.2, pinned)
Probed first with a scratch program, then pinned in `NonFiniteDateInvariantTests`:
- `JSONEncoder` (the repository's settings: `.deferredToDate`, default `.throw` non-conforming float strategy) throws
  `EncodingError.invalidValue` for a NaN, `+inf` or `-inf` date. It writes no bytes.
- `JSONDecoder` with the repository's settings cannot produce a non-finite date from any file:
  - The bare tokens `NaN`, `nan`, `Infinity`, `-Infinity` and `inf` throw `DecodingError.dataCorrupted` ("not valid
    JSON").
  - The overflowing numbers `1e309`, `1e400` and `-1e400` also throw `DecodingError.dataCorrupted`. They do not round
    to infinity.
  - The strings `"NaN"`, `"Infinity"` and `"-Infinity"` throw `DecodingError.typeMismatch`.
  - `1.7976931348623157e308` (the largest finite double) reads back exactly.
- So a hand-written file with a non-finite window date is rejected by the file store with **`unreadableFile`**. That is a
  typed error, as in AC-M1-06. The file is left byte-for-byte unchanged, and every operation that reads it throws.
- A non-finite value reaches the model's own decode check only through a lenient decoder
  (`.convertFromString(...)`). No repository uses one. The tests use one to prove that decode throws
  `windowDateNotFinite` for both a task and a household.

### AC coverage
| AC / item | Test(s) | Result (Linux) |
|---|---|---|
| AC-M2-02 (W2-F3): construction throws | `NonFiniteDateInvariantTests` "constructing a task with a non-finite windowStart or windowEnd throws windowDateNotFinite" (6 cases: NaN, +inf, -inf × start, end); "both window dates non-finite" (9 cases); `InvariantTests` "constructing a task that violates an invariant…" (6 new rows) | PASS |
| AC-M2-02 (Q9 position) | "windowDateNotFinite sits after noAllowedWeekdays and before windowEndNotAfterStart"; "the finiteness check runs before the window-order check and after the weekday check" (6 cases); `ZeroGuiltModelTests` "AC-M1-25 / AC-M2-02 naming…" (exact ordered list) | PASS |
| AC-M2-02 (W2-F3): boundary | "the most extreme finite dates are accepted" (±`greatestFiniteMagnitude`, `distantPast`/`distantFuture`, `nextUp`; round-trips through the ADR-0004 format) | PASS |
| AC-M2-02 (W2-F3): decode throws the typed violation | "a task or household that decodes to a non-finite window date throws windowDateNotFinite" (6 cases); `InvariantTests` "decoding JSON that violates an invariant…" (new row) | PASS |
| AC-M2-02 (W2-F3): JSON file store rejects a hand-written file | "a hand-written file with a non-finite window date is rejected with a typed error and left unchanged" (22 cases: 11 tokens × start, end; AC-M1-06 harness: load, upsert, remove, update room, reopen; bytes unchanged); `FileRepositoryLoadErrorTests` "a file containing a task that violates an invariant…" (new row, `unreadableFile`) | PASS |
| AC-M2-02 (W2-F3): JSON file store refuses to save one | "the file repository refuses to save a task carrying a non-finite date and keeps the stored file" (6 cases; `writeUnsuccessful`, file unchanged) | PASS |
| AC-M2-02 (W2-F3): in-memory store rejects one | "the in-memory repository rejects a task carrying a non-finite date with invalidTask(windowDateNotFinite)…" (6 cases: save, upsert new, upsert replacing; contents unchanged); "…still accepts valid tasks after a rejection" | PASS |
| Pins | "JSONEncoder … refuses a non-finite date" (6); "JSONDecoder cannot read a hand-written non-finite date token" (11); "the largest finite JSON number reads back…"; "the file repository's strict decoder reads a string-spelled non-finite date as unreadableFile" (6) | PASS |
| AC-M1-25, AC-M1-06, AC-M1-07 (unchanged, still green) | All M1 suites | PASS |

**Full suite:** `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` gave
"✔ Test run with 141 tests in 18 suites passed after 129.112 seconds." A rerun on the final tree, after the mutation checks, gave "141 tests in 18 suites passed after 125.803 seconds." There were 0 failures and 0 warnings. Before
this change it was 127 tests in 17 suites. This adds 14 tests and 1 suite, and new rows in existing parameterised
tests.

**Mutation checks (local, then reverted):**
- With the finiteness check returning `windowEndNotAfterStart`, the run was red: "38 tests in 5 suites failed … with
  90 issues".
- With the in-memory guard disabled, the run was red: "14 tests in 1 suite failed … with 26 issues".

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| Full TendCore suite, `-warnings-as-errors` (Swift 6.2, `swift:6.2-noble` Docker) | ✔ 141/141 | — | n.a. | n.a. | macOS CI runs on the PR |
| JSON non-finite pins | ✔ (exact error kinds under `#if os(Linux)`) | — | n.a. | n.a. | Darwin Foundation: only "throws a `DecodingError`" is asserted there. The exact kind is not verified on Darwin. |
| Mutation checks | ✔ | — | n.a. | n.a. | — |

### Things the reviewer should look at closely (T-21: M1 test edits)
I changed these M1 tests. No M1 assertion was removed. Please confirm each change is an extension.
1. `InvariantTests.casesCoverEveryInvariant`: the count went from `== 9` to `== 10`, and the test name now says ten
   (nine M1 cases + one). The set-equality assertion is unchanged. Six construction rows were added.
2. `ZeroGuiltModelTests.invariantViolationCases`: the exact ordered list now has `.windowDateNotFinite` in third
   place. The nine M1 cases keep their relative order. The test name was updated.
3. `InvariantTests.violatingJSON` / `decodeThrows`: a new switch arm (the switch must stay exhaustive). Only that
   row uses a lenient decoder; the nine M1 rows still use the default `JSONDecoder()`. `Fixtures.decode` gained a
   `using:` parameter that defaults to the old behaviour.
4. `FileRepositoryLoadErrorTests.invariantCases` / `invariantCoverage`: the nine M1 cases still expect
   `invalidTask(violation)`. The new row expects `unreadableFile`, because strict JSON cannot carry the value. The
   coverage test still asserts all nine M1 cases as `invalidTask`. It also asserts that the non-finite row exists
   and expects `unreadableFile`.
5. `FileRepositoryAtomicSaveTests.encodingFailureKeepsPreviousHousehold` (AC-M1-07): a public caller can no longer
   build a `-.infinity` task. So the test now builds a valid task and sets `windowStart`/`windowEnd` through the
   `@testable` internal setters, to the same values as before. The assertion (`writeUnsuccessful`, bytes of A
   unchanged, A reloads) is unchanged.

Also check the in-memory write-path guard. It checks **all** invariants, not only finiteness. That is a little more
than the work item asks, and it only matters for values made through internal setters.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The plan wording expects the file store to reject a non-finite file with `invalidTask(…)`. On Linux, strict JSON cannot carry a non-finite number, so the actual typed error is `unreadableFile`. That is still one of AC-M1-06's typed errors, and the brief only says "a typed error, as in AC-M1-06". `invalidTask(.windowDateNotFinite)` can come only from the model decode with a lenient decoder. | Question (PO/Planner) | Open question 1 |
| For a value built through an internal setter, the stores reject with different typed errors: in-memory gives `invalidTask(.windowDateNotFinite)`, the file store gives `writeUnsuccessful` (the encoder refuses; AC-M1-07 pins this). Making the file store check invariants before encoding would change the M1 AC-M1-07 assertion, so I did not do it. | Minor | Open question 2 |
| The file store's save does not check the other invariants for values built through internal setters. This was already true in M1 and is unchanged. | Minor | — |
| Exact Darwin `DecodingError` kinds are not verified. | Nit | macOS CI |

### Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | Selection unchanged. |
| UX-3 Zero-Guilt | pass | The case describes data, not conduct, and has no banned word or substring (Designer check; the AC-M1-02 source scan passes). No overdue state is added. A bad file fails calmly with a typed error and is never repaired or emptied. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI path. |
| P-2 No data leaves device | pass | No networking. TendCore is still Foundation-only (AC-M1-23 scan passes). |
| P-3 Cloud AI only opt-in | n.a. | — |
| P-4 Media not persisted | n.a. | — |

### Open questions
1. **PO / Planner:** is `unreadableFile` accepted as the file store's typed rejection of a hand-written non-finite
   file? Strict JSON cannot carry one. Or should the plan text ("with `HouseholdStoreError.invalidTask(…)`") be read
   as "with a typed `HouseholdStoreError`"?
2. **PO / Reviewer:** for values built through internal setters only, should the file store check invariants before
   encoding, so it reports `invalidTask` like the in-memory store? That needs a PO decision, because it changes the
   expected error in the M1 AC-M1-07 test.

### Handoff log
| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-21 | iOS Designer | Developer | accepted | Case name and position (design.md Addendum A). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent | Branch pushed, no PR opened (as instructed). Two open questions for PO/Planner. |
