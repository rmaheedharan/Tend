# M2 Code Review — A-F1 fix: eval scorer subset profiles take exactly the fixed input IDs and modes (PR #33, `m2/scorer-subset-ids`, head `f6af859`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE (round 2, head `1229ad1`; round 1 APPROVE at `f6af859`)  ·  **Round:** 2
- **Requirements:** AC-M2-11 (DS-1 offline subset), AC-M2-25 (DS-2 subset), AC-M2-14 (scorer log as evidence, the
  "no subset chosen after results" rule), FR-A1, UX-3 (reason wording). Defect A-F1 (Tester, acceptance draft on
  `m2/eval-fixtures-freeze`, AQ-2), severity Minor.
- **Binding inputs checked:** `CLAUDE.md`; brief AC-M2-11, AC-M2-14, AC-M2-25 and the **Eval scoring rules**; PO
  rulings F3 (subsets fixed) and F4 (Developer fixes the tool) in `po-m2-wi16.md` "Follow-up rulings (PR #32 and
  acceptance)"; dev-notes section "A-F1 fix"; the Tester's frozen fixtures
  (`origin/m2/eval-fixtures-freeze:Fixtures/M2/eval/inputs.json`).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed. No protected path is
  touched (diff: `EvalProfile.swift`, `EvalProfileTests.swift`, `Tools/TendTools/Package.swift`,
  `EvalScoreCommand.swift`, `TendToolsTests.swift`, `docs/milestones/M2/dev-notes.md`). `Fixtures/M2/eval/` not touched.
- **Base / head:** `main` `1d1caa3` → `f6af859`. Reviewed in a detached worktree; nothing committed or pushed.

## Summary
The fix does what F4 asks. `EvalProfile.subset` pins `ds1-offline` = in01 (text), in02 (voice), in10 (voice) and
`ds2-offline` / `ds2-online` = in08 (voice), in16 (voice); the whole-set profiles (`ds1-gated`, `ds2-gated`, `info`)
have none. The subset is a property of the profile, not an argument (F4). I checked the pins against the frozen
fixtures: in01 text, in02 voice, in10 voice, in08 voice, in16 voice — all match, and they match the AC wording
(AC-M2-11 "3 eval inputs … 2 voice, 1 text"; AC-M2-25 "2 voice inputs").

`EvalScorer.run` compares the file's distinct (ID, mode) pairs with the subset after the reader accepts the file and
before scoring. Any difference throws `EvalScoringError.subsetMismatch`, and the tool exits 2 with
`file rejected: <reason>`. The reason names the profile, the AC, the required inputs and the file's inputs, then
lists what is not in the subset, what is not in the file, and any mode differences. A voice retake (attempt 2) does
not count as another input. The profile check is a second control and puts the IDs and modes in the scorer log on
every subset run (F4 "the scorer log prints the input IDs and modes"; AC-M2-14 evidence). F4's self-test with the
right count and a wrong ID is there in both suites: 7 cases in `EvalProfileTests` and 3 in `TendToolsTests`.

**Test weakening check (rule: never weaken a test).** I read every changed test hunk:
- `ds1Offline`: still asserts the right file passes. The assertion is stronger now, because it prints the failing
  checks and asserts the new check name. The `extra` and `interrupted` cases keep their exact failing lists, now on
  in02 and in01 of the fixed subset. The old 4-input case asserted an exact failing check. It now asserts a
  `subsetMismatch` with the exact `found` list. That is equivalent or stronger: the file is now refused, which is
  stricter than "scored, does not pass".
- `ds2Offline`: same pass and exact failing list (`in08` / `in16` noModel), moved from in01/in03 to the fixed IDs.
- `ds2Online`: pass and the exact `missing` failure are kept (now in16). The old text-input case asserted the exact
  failing check. It now asserts only the `.subsetMismatch` case (see N1). The exact reason for a mismatched input is
  asserted in the parameterised cases.
- Synthetic fixtures' mode change: `Synthetic.mode` used to make odd inputs voice. It now matches the frozen fixtures
  (voice = 2, 4, 6, 8, 10, 12, 14, 16, 17, 20). That is still 10 voice and 10 text over 20 inputs, so no
  composition-sensitive gated test changes meaning. `Synthetic` is used only in `EvalProfileTests`. No other
  assertion depends on a specific input's mode (grep: the only mode uses are the helper and the A-F1 tests). Nothing
  was removed, skipped or loosened. The `run` → `request`/`run`/`rejection` split is a refactor, and `run` behaves as
  before.

**TendTools `Package.swift`:** the test target now also depends on the `TendIngestion` product. That package is
already declared (`.package(path: "../../Packages/TendIngestion")`) and `TendToolsSupport` already uses it. It is
in-repo, so there is no new package and no ADR is needed (CLAUDE.md §6).

**Wording:** the reason and the usage text use "rejected", "not in the subset" and "not in the file". None of the
banned tokens (overdue, late, missed, failed, behind, penalty) appear, and both suites assert this on every refusal
reason. This is tool output, not app copy.

**Swift 6:** the new types are value types with `Sendable` and `Hashable`. There is no `@unchecked`, no
`nonisolated(unsafe)` and no force unwrap. The build is clean with `-warnings-as-errors`.

### Evidence (Linux, `swift:6.2-noble`, Docker, `-Xswiftc -warnings-as-errors`, own scratch paths)
| Check | Result |
|---|---|
| `swift test --scratch-path /tmp/rev33-ing --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 539 tests in 64 suites passed after 169.644 seconds.` (matches dev-notes) |
| `swift test --scratch-path /tmp/rev33-tools --package-path Tools/TendTools -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 11 tests in 1 suite passed`, 0 `warning:` lines |
| macOS CI / Simulator / device | not run by me (n.a. for a Linux scorer) |

### Mutation check (scratch copy `/tmp/rev33-mut/src`; restore with `cp` + `touch` every `.swift` before each run; M0 baseline green: EvalProfileTests 18/18, TendTools 11/11)
| # | Mutant (in `EvalProfile.swift`) | EvalProfileTests | TendToolsTests | Killed |
|---|---|---|---|---|
| M1 | `run` guard off (`found == required \|\| true`) | 18 issues | 40 issues | yes |
| M2 | subset check only for `ds1-offline` | 10 issues | 24 issues | yes |
| M3 | `run` compares IDs only, not modes | 4 issues | 15 issues | yes |
| M4 | no dedupe of retakes (`Set` removed in `inputs(of:)`) | **passes** | 7 issues | yes (TendTools only) |
| M5 | second control (`inputSet`) always holds | 2 issues | passes | yes |
| M6 | `ds1-offline` pin in10 → in06 | 4 issues | 12 issues | yes |
| M7 | reason drops the mode-difference note | **passes** | 3 issues | yes (TendTools only) |
| M8 | reason drops "not in the file" | **passes** | 3 issues | yes (TendTools only) |
| M9 | reason drops "not in the subset" | **passes** | 4 issues | yes (TendTools only) |
| M10 | `ds2-online` pin in16 → in14 (diverges from `ds2-offline`) | 4 issues | 6 issues | yes |

All 10 mutants are killed. Four of them (M4, M7–M9) are killed only by `TendToolsTests`, which CI does not run (R27-F5,
owner ticket HM-1b, still open). See F1.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Eval/EvalProfile.swift:41` (retake dedupe), `:91` (`reason` notes); tests in `EvalProfileTests.swift` | The retake rule ("a voice retake does not count as another input") and the three reason notes F4 asks for ("a plain reason") are tested only in `TendToolsTests`. CI runs only `swift build` for `Tools/TendTools` (`.github/workflows/ci.yml:82-86`; R27-F5 / HM-1b still open). So mutants M4, M7, M8 and M9 pass every test CI runs. The behaviour is correct today. | In `EvalProfileTests`, add (a) a `ds1-offline` case where in02 has a retake (attempt 2) and the file is scored, not refused, and (b) exact `reason` assertions for each note kind ("not in the subset: …", "not in the file: …", "<id> is <mode> in the file, the subset takes it as <mode>"). This can come in a follow-up PR before DS-1/DS-2 scoring. It does not block. | Open |
| N1 | Nit | `EvalProfileTests.swift:364-368` | The `ds2Online` text-input case now checks only `case .subsetMismatch?`. The old version asserted the exact failing check. The parameterised cases cover the content, so this loses no coverage overall. | Optionally assert `mismatch.found` (`in01 (text), in08 (voice)`), as the `four` case does. | Open |
| N2 | Nit | `EvalProfile.swift` `subsetAC` | `subsetAC` returns `AC-M2-15` / `AC-M2-26` / `no AC` for profiles that have no subset, and those values can never appear in a reason. | Optionally limit it to the subset profiles. | Open |

No Blocker. No Major.

## Checklist
- [x] Correctness vs ACs (AC-M2-11 and AC-M2-25 subset identity; F3 IDs and modes checked against the frozen fixtures;
  AC-M2-14 log evidence)  - [x] Tests meaningful (10/10 mutants killed; F1 notes the CI gap)
- [x] Swift 6 concurrency safe (value types, `Sendable`, no unsafe escape hatches)
- [x] No force unwraps / try! in product code paths  - [x] Privacy (P-1…P-4): Linux tool, no network, no new destination
- [x] UX-2/UX-3 enforced in engine (n.a. for UX-2; UX-3 wording asserted)  - [x] Accessibility (UI): n.a.
- [x] Performance: one `Set` and sort over at most 40 attempts, n.a.  - [x] No new dependency without ADR (in-repo
  package only)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Scorer tool only; no entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No app copy. The refusal reason and the usage text contain no banned token. Both suites assert this on every refusal. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The AC-M2-11 offline subset is now proven by input identity, not just a count. The scorer runs on Linux and does no inference. |
| P-2 No data leaves device (except user iCloud) | pass | No network, no third-party dependency. The new test dependency is an in-repo package. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No request or payload change. |
| P-4 Media not persisted without consent | n.a. | Text files only. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | Review PR #33 (`m2/scorer-subset-ids`, `f6af859`) for A-F1 under PO rulings F3 and F4. |
| 2026-11-24 | Reviewer | Orchestrator | sent (round 1: APPROVE) | 0 Blocker, 0 Major, 1 Minor (F1: retake and reason-note tests only in TendTools, which CI does not run), 2 Nits. Only the Tester closes A-F1; S5/S7 stay as second controls (F4). |

---

## Round 2 — head `1229ad1` (fixes `9bce322`, then a `--no-ff` merge of `main` `368bb9e` with PR #32)

- **Verdict: APPROVE.** No Blocker, no Major. F1, N1 and N2 are closed and verified in the new diff.
- **Requirements:** AC-M2-11, AC-M2-25, AC-M2-14, FR-A1, UX-3 (unchanged from round 1). Milestone lock: M1 `ACCEPTED`,
  M2 `IN-BUILD`, so this work is allowed. No protected path is touched.

### What I checked
- **Fix diff `f6af859..9bce322`** (product code: `EvalProfile.swift`; tests: `EvalProfileTests.swift`; plus the
  round-1 review file committed as `06d3c54`):
  - `subsetAC` is now `String?`. It is nil for `ds1-gated`, `ds2-gated` and `info`. The reason builds `(AC, PO ruling F3)`
    only when there is an AC. Refusals print the same text as before, because only subset profiles can produce one.
  - `Synthetic.request` gains `retakes`. For those inputs it writes a first attempt (noModel, no draft) and then the
    edited attempt as attempt 2, with a retake reason. Every other path builds the same attempts as before.
  - New tests: `retakeIsOneInput` (in02 attempts [1, 2] in the file; `ds1-offline` scored and passes; score uses
    attempt 2; the log line shows the subset; a retake of in04, which is outside the subset, is still refused with the
    exact `found` list). `exactReason` (5 cases): exact full-string reasons for both notes, "not in the subset" only,
    "not in the file" only, and the mode note in both directions. `subsetACs`: pins `subsetAC` across
    `EvalProfile.allCases` in declaration order (ds1-gated, ds1-offline, ds2-offline, ds2-online, ds2-gated, info).
    The `ds2Online` text-input case now asserts `found` and the exact reason (N1).
  - Nothing was removed or loosened. Every round-1 assertion is still present, unchanged.
- **Merge `1229ad1`:** `git diff 368bb9e 1229ad1 --stat` lists only this PR's files (`EvalProfile.swift`,
  `EvalProfileTests.swift`, the 3 TendTools files, `dev-notes.md`, `review-A-F1.md`). `git diff 9bce322 1229ad1`
  outside `docs/` is exactly PR #32's payload changes from `main` (Payload sources and tests, `Fixtures/M2/payload/`).
  Main changed no file under `Eval/` or `Tools/`. Only `dev-notes.md` conflicted, and it holds both the WI-M2-16 and
  the A-F1 round-2 sections. No code is resolved by hand.

### Evidence (Linux, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, merged tree `1229ad1`)
| Check | Result |
|---|---|
| `swift test --scratch-path /tmp/rev33-ing --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 546 tests in 64 suites passed after 156.365 seconds.`, 0 `warning:` lines |
| `swift test --scratch-path /tmp/rev33-tools --package-path Tools/TendTools -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 11 tests in 1 suite passed after 0.217 seconds.`, 0 `warning:` lines |

### Mutants rerun against TendIngestion alone (fresh scratch copy of `1229ad1`; `cp` restore, then `touch` every `.swift` before each run; `--filter EvalProfileTests`)
| # | Mutant (`EvalProfile.swift`) | Round 1 (TendIngestion) | Round 2 (TendIngestion) |
|---|---|---|---|
| M0 | none (baseline) | 18/18 green | `✔ 21 tests passed` |
| M4 | retakes not merged (`Set` removed in `inputs(of:)`) | survived | killed, 1 issue (`retakeIsOneInput`: `found` has in02 twice) |
| M7 | reason drops the mode-difference note | survived | killed, 2 issues |
| M8 | reason drops "not in the file" | survived | killed, 3 issues |
| M9 | reason drops "not in the subset" | survived | killed, 3 issues |
| M11 (new) | reason always omits the AC (`let ac = ""`) | n.a. | killed, 6 issues |

All the round-1 TendIngestion survivors are now killed by the suite CI runs. TendTools tests still do not run in CI
(R27-F5 / HM-1b, owner ticket, `.github/**` protected). That ticket is not a finding on this PR.

### Findings (round 2)
| # | Severity | Finding | Verification | Status |
|---|---|---|---|---|
| F1 | Minor | The retake rule and the reason notes were tested only in TendTools. | `retakeIsOneInput` and `exactReason` (5 cases) in `EvalProfileTests`; M4, M7, M8, M9 killed in TendIngestion alone. | Closed |
| N1 | Nit | The `ds2Online` text-input case checked only the error case. | Now asserts `found` and the exact reason string. | Closed |
| N2 | Nit | `subsetAC` had values for profiles with no subset. | Now `String?`, nil for those profiles; pinned by `subsetACs`; M11 killed. | Closed |

No new findings.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Scorer tool only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Reason text unchanged except for the AC part. The banned-word assertions still run on every refusal. The new exact strings contain no banned token. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | AC-M2-11 subset identity is proven by the tool. No inference in the scorer. |
| P-2 No data leaves device (except user iCloud / P-3 request) | pass | No network, no new dependency. The merge brings in only PR #32, which was reviewed separately. |
| P-3 Cloud AI opt-in, BYOK, minimised, per ADR-0005 | n.a. | This PR changes no request. The merged payload changes come from PR #32 (`review-WI-M2-16-instructions.md`). |
| P-4 Media not persisted without consent | n.a. | Text files only. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | accepted | Round 2: fixes `9bce322`, merge `1229ad1` with `main` `368bb9e`. |
| 2026-11-24 | Reviewer | Orchestrator | sent (round 2: APPROVE) | F1, N1, N2 closed. 546 + 11 green, 0 warnings. M4, M7–M9 (and new M11) killed in TendIngestion alone. Merge clean. Only the Tester closes A-F1. |
