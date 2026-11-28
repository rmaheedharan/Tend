# M2 Code Review — PR #54 (`m2/pre-ms3-fixes`, head `ca9badf`, base `main` `19675a3`)

- **Owner:** Reviewer (fresh context; did not write these edits)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** `git diff 19675a3..ca9badf`: 7 files, docs and Tester evidence only. `docs/milestones/M2/acceptance.md`,
  `eval-composition.md`, `plan.md`; `docs/milestones/M2/evidence/tester/independent-rescore.py` (changed),
  `rescore-s6-selftest-build.py`, `rescore-s6-selftest-run.sh`, `rescore-s6-selftest.out` (new). No product code, no
  fixture, no protected path (`CLAUDE.md`, `docs/PRD.md`, `.claude/**`, `.github/**`, `docs/governance/**`,
  `docs/milestones/STATUS.md` untouched).
- **Checked against:** `review-pr53.md` findings F1, F2, F3, i1, i2; PO ruling D-059 (`po-m2-element-counts.md`);
  `Fixtures/M2/eval/results-v1.schema.json`; `Fixtures/M2/payload/golden/g1-outcome-empty-<p>.body.json` and
  `allowed-key-paths-<p>.json`; `project.yml`; `Apps/TendEval/Support/Debug-Info.plist`;
  `Apps/TendEval/Sources/Run/EvalRunner.swift`; `Apps/TendEval/Sources/Screens/EvalSession.swift`;
  `Packages/TendIngestion/Sources/TendIngestion/Eval/EvalProfile.swift` and `EvalResultsReading.swift` (to compare
  verdicts, not as the script's spec).
- **IDs:** AC-M2-13, AC-M2-14, AC-M2-24, AC-M2-26, AC-M2-28, D-050, D-059, Q12, Q20, P-3, P-4, UX-3.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. M2 docs on an `m2/` branch. OK.

## Summary

All five findings from `review-pr53.md` are fixed. The `TEND_COMMIT` steps match how TendEval reads the commit, for
both `xcodebuild` (B7) and Xcode ⌘R (Appendix A). The re-score script's new S6 checks are correct against D-059, the
schema and the golden bodies, and they are written separately from the Swift scorer. I ran the self-test myself
(28/28 as expected, same body as the committed log), added 18 data mutants and 11 script mutants of my own (all
behave as expected; every script mutant is caught by the committed self-test), and confirmed the no-option output is
byte-identical to the old script. No AC is removed or weakened. I found no Blocker and no Major: one Minor (a wrong
count in the evidence text) and four Nits/Info.

### 1. Each finding

| review-pr53 | Fixed? | Evidence |
|---|---|---|
| F1 (stale "valid once merged") | Yes | `acceptance.md:142` and `eval-composition.md:14-16` now say merged in PR #52 (`1b81e7b`). `git merge-base --is-ancestor e014fab 1b81e7b` is true; `sha256sum Fixtures/M2/eval/MANIFEST.sha256` gives `7fdc056e…de22`, same at `1b81e7b`; `(cd Fixtures/M2/eval && sha256sum -c MANIFEST.sha256)` prints 4 x OK. |
| F2 (order that did not happen; Planner confirm) | Yes | `plan.md:329-332` says the PR #52 review used D-059 directly and the plan text came after, in PR #53 (commit `9e35bf7`, merged at `19675a3`). Planner confirmation recorded (`plan.md:332`, handoff row `plan.md:904`). |
| F3 (`TEND_COMMIT` in B7 and Appendix A) | Yes | B7 `plan.md:606-616`; MS-3 row `plan.md:534`; WI-M2-M8 row `plan.md:103`; Appendix A steps 3a, 7a, 9 (`acceptance.md:477-505`). See §2. |
| i1 (re-score does not read `cloudRequests`) | Yes | Script extended; S6 command and self-test described at `acceptance.md:442-452`. See §3. |
| i2 (`sha256sum -c` from repo root) | Yes | `plan.md:663` uses the `cd` form. |

### 2. `TEND_COMMIT` against how TendEval reads it

- `project.yml:99` sets the target build setting `TEND_COMMIT: ""`; `project.yml:107` uses
  `Apps/TendEval/Support/Debug-Info.plist` in Debug only; that plist has `TendCommit = $(TEND_COMMIT)` (build-setting
  expansion at Info.plist processing). `EvalRunner.swift:169-171` reads `TendCommit` from the bundle, empty becomes
  `"unknown"`. `EvalSession.swift:62-63` needs exactly 40 lower-case hex characters, else `setupProblem` returns
  "Build with TEND_COMMIT set to the commit under test (plan WI-M2-M7)." (`EvalSession.swift:131`).
- **B7 (`xcodebuild`)**: a command-line build setting overrides the target setting, so
  `TEND_COMMIT="$(git rev-parse HEAD)"` reaches the plist. Configuration is Debug, so the Debug plist is used.
  `git rev-parse HEAD` prints 40 lower-case hex, which passes `commitIsKnown`. The new `PlistBuddy` check reads the
  built `Debug-iphoneos/TendEval.app/Info.plist` (PlistBuddy reads binary plists). B0 (`plan.md:569`) gives the
  clean-tree check the new comment refers to. Correct.
- **Appendix A (⌘R)**: the TendEval scheme's run action is Debug (`project.yml:175-176`). A custom XcodeGen setting
  shows under **User-Defined** in Build Settings (All); editing the collapsed row sets it for all configurations.
  `/Tend.xcodeproj/` is in `.gitignore`, so step 2's clean check still holds, and regenerating clears the value, as
  step 7a says. The note that a scheme Run environment variable does not help is right (the value is read from the
  Info.plist, not the environment). Step 9's checks (`unknown` or the message) match the code. Correct.

### 3. Re-score script S6 checks

- **SHA**: `sha256sum independent-rescore.py` = `2239f11c…4e14`, as `acceptance.md:54` says; the old version at
  `19675a3` = `30330dbf…4658`, as stated.
- **Against D-059 / plan WI-M2-15 / schema**: exactly five request members; both count members non-null; entry shape
  `{count, path}`, integer ≥ 0 (bools rejected), path pattern equal to the schema's; sorted by UTF-8 bytes and unique;
  `arrayCounts` equal path for path to the script's own walk of the G1 golden body (every array, any depth, empty and
  nested); `userContentArrayCounts` exactly `$.existingTasks` (≤ 10, Q12 = yes, D-050) and `$.rooms` (=
  `len(household.rooms)` = 9); key paths valid, sorted, unique and ⊆ the allowed list; over every request of every
  attempt. This is the same as or stricter than the Swift `ds2-gated` rule (`EvalProfile.swift:349-399`) and the
  reader (`EvalResultsReading.swift:179-195`).
- **Independent**: it walks the golden body itself with a strict JSON parse (no NaN, no duplicate members); it does
  not import or call Swift code. The self-test's oracle is the literal list in the Developer's
  `GoldenArrayCountsTests.swift` (data only), and its extra walk shows all nine G1/G2/G3 bodies equal that list.
- **My run**: in a scratch folder, `rescore-s6-selftest-build.py` then `rescore-s6-selftest-run.sh`: "28 as expected,
  0 not as expected"; the log body (lines 5 onward) is identical to the committed `rescore-s6-selftest.out`. Count:
  3 good, 23 bad, 1 argument case, 1 old-use case (see R54-F1).
- **My data mutants (18)**, all as expected: empty `keyPaths` (1), an `onDevice` first attempt (1), float count (1),
  `$.existingTasks` missing (1), `existingTasks` 0 (0) and 10 (0), `arrayCounts` `{}` (1) and `[]` (1),
  `userContentArrayCounts` `[]` (1), concrete index in a key path (1), duplicate path with a different count (1),
  all routes `none` (1), bad counts only in the scored retake attempt (1), fewer key paths (0), request attempt 0 (1),
  extra request member (1), extra user-content path in sorted order (1); and missing one option (2).
- **My script mutants (11)**, each caught by the committed self-test (1 or more cases WRONG): check only the first
  request; skip non-last attempts; compare seen paths only; `existingTasks` limit 11; no rooms check; no null check; no
  sort check; no provider-argument check; no route check; always exit 0; allow bools as counts. Script restored; hash
  unchanged, tree clean.
- **No-option output**: old and new script give the same stdout and exit code on
  `results-selftest-1.canonical.json` and `results-selftest-1.json` (both fixture dirs) and on a cloud file; output
  SHA-256 is `c15c30ec…a375`, equal to `rescore-selftest-1.out` (`acceptance.md:57`).

### 4. ACs

No AC text removed or changed. The seven device ACs (AC-M2-11, 15, 16, 17, 25, 26, 27) stay `AWAITING-DEVICE`
(those lines are not in the diff). AC-M2-24 text unchanged. The S6 text adds a control.

### 5. Hygiene

Added lines grepped for `/home/`, `/tmp`, `/Users/`, `/mnt/`, e-mail addresses, the owner's name, "Hearth" and the
UX-3 banned words: no hits. The self-test log has repo-relative paths only (the runner strips the sample folder).

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R54-F1 | Minor | `docs/milestones/M2/acceptance.md:448` | Says "24 mutated files exit 1". The build script writes 23 `bad-*.json` files and the log has 23 "expected exit 1" cases (3 + 23 + 1 + 1 = 28, matching "28/28"). Evidence text must match the log (CLAUDE.md §4 rule 2). | Change "24" to "23". | Open (Tester) |
| R54-n1 | Nit | `docs/milestones/M2/acceptance.md:503-505`, `:540` | The Appendix A note and the handoff row say B7's line "stays with the Planner" / "is the Planner's to update", but this same PR already updates B7 (`plan.md:612`). | Say B7 now passes `TEND_COMMIT` (plan B7). | Open (Tester) |
| R54-n2 | Nit | `docs/milestones/M2/acceptance.md:486-489` | Step 7 ends "Change nothing else", then step 7a changes a build setting. A careful owner may hesitate. | e.g. "Change nothing else on this tab." | Open (Tester) |
| R54-i1 | Info | `independent-rescore.py` (route check); `acceptance.md:442-447` | The script's route line is stricter than the Swift scorer: it checks every attempt (Swift `routes` checks scored inputs only) and fails an attempt routed to `<p>` with no request. On iPhone 13 Part C both should hold, so this is a sensible extra control, but S6 only says the verdict must agree with the S4 key-path and counts lines. If the route line alone fails, the Tester must investigate before accepting. | Optional: one sentence in S6 on how a route-line-only FAIL is handled. | Info |
| R54-i2 | Info | `independent-rescore.py` option parsing; `acceptance.md:477` | A repeated option is silently overwritten by the earlier one (options are read from the end). Step 3a compares 40 characters with `APP-COMMIT`; that only works if `APP-COMMIT` is recorded in full. | Optional: refuse repeated options; record `APP-COMMIT` as the full 40-hex SHA. | Info |

## Checklist
- [x] Correctness vs ACs (AC-M2-13 B7, AC-M2-14 re-score, AC-M2-26 S6 checks, AC-M2-28 `TendCommit`) checked against code
- [x] Tests meaningful: self-test re-run; 18 extra data mutants and 11 script mutants, all as expected
- [x] Swift 6 concurrency safe: n.a. (no Swift changed)
- [x] No force unwraps / try! in product code paths: n.a.
- [x] Privacy (P-1…P-4): no change to what is sent or stored; checks read integers and paths only
- [x] UX-2/UX-3 enforced in engine: n.a.; no banned words in added text
- [x] Accessibility (UI): n.a.
- [x] Performance: n.a.
- [x] No new dependency without ADR: none (Python 3 standard library only, Tester evidence tool)
- [x] No AC removed or weakened; device ACs stay AWAITING-DEVICE
- [x] No protected path touched

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug harness install and scoring docs; no product entry path. |
| UX-2 Rule of Three | n.a. | No product surface. |
| UX-3 Zero-Guilt | pass | No banned word in added lines; "FAIL" is team scoring output, not user copy. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Routing unchanged; the route check makes a stray route visible. |
| P-2 No data leaves device (except user iCloud) | pass | No dependency, host or server; scoring runs offline on Linux. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Adds a second, independent proof of minimisation (key paths ⊆ allowed list; counts equal to the G1 golden body, rooms 9, existingTasks ≤ 10) on every request of every attempt (D-059, AC-M2-26). |
| P-4 Media not persisted without consent | pass | Results and logs hold integers and member-name paths only; no body, value, key, personal data or local path. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-28 | Orchestrator | Reviewer | accepted | PR #54, head `ca9badf`, base `main` `19675a3`. Fixes for review-pr53 F1, F2, F3, i1, i2. |
| 2026-11-28 | Reviewer | Orchestrator → Merge Gatekeeper; Acceptance Tester (R54-F1, n1, n2, i1, i2) | sent | **APPROVE**, round 1. No Blocker or Major. review-pr53 F1–F3, i1, i2 verified fixed. `TEND_COMMIT` steps checked against `project.yml`, `Debug-Info.plist`, `EvalRunner`, `EvalSession`. Self-test re-run 28/28; 18 data + 11 script mutants of my own as expected; no-option output byte-identical. Minor R54-F1 (23, not 24, mutated files). Not run: Xcode/device steps (no Mac here; checked by reading). File not committed. |
