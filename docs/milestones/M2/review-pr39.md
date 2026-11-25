# M2 Code Review — PR #39 (`m2/havana-tz-fixtures`, round 1 @ `2374aad`, base `origin/main` `20c40ea`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** A change to test fixtures only, under **AC-M2-03** (FR-A1, Q6(e), Q11). The three America/Havana
  `TimeResolverTests.havana` cases and the `havanaTzdata` sanity test move from the 2026 Cuba transitions to the 2025
  ones. The PR adds a stale-fixture guard. Diff: `git diff origin/main...HEAD` covers 2 files,
  `Packages/TendIngestion/Tests/TendIngestionTests/TimeResolverTests.swift` (+39/−10) and `docs/milestones/M2/dev-notes.md`
  (+87). No file under `Sources/`, `Package.swift` or `Fixtures/` changed, and no protected path is touched.
- **Inputs read:** `CLAUDE.md`; the PO ruling "PO Havana tz fixtures, 2026-11-25" (`/mnt/project-files/notes/po-m2-havana.md`,
  option C); the PR diff; the dev-notes section for this change; `TimeResolverTests.swift` helpers (`TestClock`, `utc`,
  `check`); my earlier `review-WI-M2-03.md` (the original Havana cases).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. An `m2/` test fix is allowed (CLAUDE.md §5).

## Summary

The change does what the PO ruling (option C) asks. It keeps America/Havana, so the test still covers a DST change at
local midnight. It moves each case to a settled 2025 transition, with the same weekday and hour for `now` relative to
the transition. Expected values stay as literal UTC instants. It adds a guard that fails with a "stale fixture" message
if the tz data ever rewrites those transitions. No assertion was removed, loosened, skipped or made conditional. The
number of cases is the same: 3 parameterised Havana cases plus 1 sanity test, and the file still has 20 `@Test` on
both base and head. The sanity test gains checks (the guard and `startOfDay`) and loses none. I found no Blocker and no
Major.

### 1. The hand-computed instants are correct (independent of Foundation)
Cuba rules in tzdata **2026f** (fetched `northamerica` at tag `2026f` from the `eggert/tz` mirror): `Rule Cuba 2012 2025
Nov Sun>=1 0:00s`, `Rule Cuba 2013 2026 Mar Sun>=8 0:00s`, `Rule Cuba 2027 max Nov Sun>=1`, `Zone America/Havana … -5:00
Cuba C%sT`. 2026f NEWS lists the Cuba change only under "Changes to future timestamps". I worked the dates out by hand.
1 Mar 2025 is a Saturday, so Sun>=8 is **9 Mar**. 1 Nov 2025 is a Saturday, so Sun>=1 is **2 Nov**. `0:00s` means
00:00 standard time (−05), which is 05:00Z.

| Case | Hand derivation | Test literal | Python `zoneinfo` (host tzdata) | `zic`+`zdump -v` on 2026f |
|---|---|---|---|---|
| Spring 2025-03-09 | 00:00 CST = 05:00Z becomes 01:00 CDT. The day starts at 05:00Z, and mid(03-10) = 00:00 CDT = 04:00Z. 23 h | `2025-03-09T05:00Z` to `2025-03-10T04:00Z` | 05:00Z → 01:00−04; 03-10T04:00Z → 00:00−04 | `Sun Mar 9 04:59:59 2025 UT = 23:59:59 CST`, `05:00:00 UT = 01:00:00 CDT` |
| Fall 2025-11-02 | At 05:00Z, 01:00 CDT becomes 00:00 CST. Local midnight happens at 04:00Z (CDT) and again at 05:00Z (CST). Q11 takes the first occurrence, **04:00Z**. mid(11-03) = 00:00 CST = 05:00Z. 25 h | today ends `2025-11-02T04:00Z`; tomorrow `2025-11-02T04:00Z` to `2025-11-03T05:00Z` | fold=0 → 04:00Z, fold=1 → 05:00Z; 11-03 00:00 → 05:00Z | `Sun Nov 2 04:59:59 2025 UT = 00:59:59 CDT`, `05:00:00 UT = 00:00:00 CST` |
| `now` Sat 2025-11-01 10:00 CDT | 10:00 − (−4) = 14:00Z = today's start | `2025-11-01T14:00Z` | 14:00Z | — |
| `now` Sat 2025-03-08 10:00 CST | 15:00Z (input only) | — | 15:00Z | — |
| 2026 fall-back (why the old fixture broke) | — | — | host: still falls back on 2026-11-01 | 2026f: no 2026 fall-back; next one `Sun Nov 7 05:00:00 2027 UT` |

All of them match. The guard table (`:610-613`) matches the `zdump` lines exactly: offset −18000 → −14400 at
2025-03-09T05:00:00Z, and −14400 → −18000 at 2025-11-02T05:00:00Z.

### 2. The tests are real, and the guard means something
- The expected values are `utc("…")` string literals. None comes from `nextDaylightSavingTimeTransition` or any other
  Foundation lookup, so option B was not used by the back door. `now` is built with `cu.local(...)` (Foundation), but it
  is an input. For the "today" case the literal start `14:00Z` pins it, and the guard covers the other two.
- The guard (`expectHavanaFixture`, `:615-628`) runs at the start of every parameterised case (`:631`) and of the sanity
  test (`:637`). It checks the zone identifier. That check matters: `TestClock` falls back to GMT when the identifier
  is missing (`:25`), so without it a missing zone would only show up as unexplained window mismatches. It also checks
  the offset 1 s before and at each transition. It does not short-circuit `check(c)`, so a stale fixture shows both the
  "stale fixture" message and the window mismatch. It never passes silently.
- **Mutants (my run, a copy of the tree in a scratch directory, filter `havana`):** (a) Q11 second occurrence: the
  25 h case start changed to `05:00Z` → `✘ … start 2025-11-02 04:00:00 +0000 != 2025-11-02 05:00:00 +0000`. (b) Guard
  spring "after" offset set to −5 h → `✘ … stale fixture: Havana tzdata changed (offset from 2025-03-09T05:00:00Z is not
  -18000 s)` on all 3 cases and on the sanity test. Run result: `✘ Test run with 2 tests in 1 suite failed … with 5
  issues`. 2/2 killed. The Developer's own break check (dev-notes) kills a third mutant.

### 3. What I ran
| Command | Result |
|---|---|
| `docker run --rm -v /home/user/wt-rev39:/w -w /w swift:6.2-noble swift test --scratch-path /tmp/rev39 --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 570 tests in 67 suites passed after 117.575 seconds.`, 0 `warning:`. Havana: `✔ … (America/Havana)" with 3 test cases passed`, `✔ … tzdata sanity for the Havana cases (stale fixture if this fails)" passed`. |
| Mutant run (above) | 2/2 killed |
| Can Foundation be made to use 2026f on Linux? I bind-mounted the 2026f `America/Havana` over `/usr/share/zoneinfo/America/Havana` and ran base `20c40ea` and head | Both passed, and so did a run with `Etc/UTC` mounted in its place. So Foundation in `swift:6.2-noble` does **not** read system zoneinfo for this zone (it uses ICU's bundled data). Linux cannot reproduce the owner's 2026f failure. The 2026f proof here is the `zic`/`zdump` table above, and the Mac rerun is still needed (see i1). |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n1 | Nit | `docs/milestones/M2/dev-notes.md:5238`, `:5266`, `:5287` | The note says Linux CI "(tzdata 2026e) still passes, but would fail when it updates", and it ties the Linux run to the `tzdata 2026e` apt package. My mount test shows Foundation in this image ignores `/usr/share/zoneinfo` (an `Etc/UTC` file mounted as Havana changes nothing). Linux results follow the toolchain's bundled ICU tz data, not apt `tzdata`. The conclusion still holds, because the 2025 fixtures are stable under either source. Only the stated reason is wrong. | Optional: say that Linux Foundation uses the toolchain's ICU tz data, so a Swift toolchain update (not an apt `tzdata` update) would surface 2026f on Linux. | Open |
| n2 | Nit | `docs/milestones/M2/dev-notes.md:5232` | "**PR:** none yet (local commit only)". The PR is now #39. | Optional: update to PR #39. | Open |
| n3 | Nit | `TimeResolverTests.swift:620-626` | The guard checks offsets only at the two transition instants. If a future rewrite added a transition somewhere else inside a window, the cases would still fail through `check(c)`, but without the "stale fixture" hint. | None required. The test cannot pass wrongly. Optional: add one guard row for an instant in the middle of each window. | Open |
| i1 | Info | dev-notes "Verification environment" | The owner's Mac run on tzdata 2026f, where the failure was seen, has not happened yet. That is a Tester/owner confirmation step under the PO ruling, not a code defect. The `zdump` evidence on 2026f supports the expected result. | The Acceptance Tester records the owner's Mac rerun (570 pass) before treating AC-M2-03 as fixed on 2026f. | — |
| i2 | Info | — | The DECISIONS.md entry "PO Havana tz fixtures, 2026-11-25" is pending, as the PO ruling's Bookkeeping section says. It belongs in a human-merged governance PR. | PO / Documenter. | — |

## Checklist
- [x] Correctness vs ACs: AC-M2-03 Q6(e)/Q11. The skipped midnight (23 h, starts at the first instant that exists) and the repeated midnight (25 h, first occurrence 04:00Z) are still proven with exact UTC instants, which I recomputed three ways.
- [x] Tests meaningful (would fail if code broke): 2/2 mutants killed, and the guard fails loudly with a "stale fixture" message.
- [x] No weakening: no assertion removed or loosened, no skip, no tolerance, no conditional pass. Case count unchanged (3 + 1; 20 `@Test` before and after).
- [x] Swift 6 concurrency safe: test code only. `-warnings-as-errors` clean.
- [x] No force unwraps / try! in product code paths: no product code changed.
- [x] Privacy (P-1…P-4): not applicable (tests only).
- [x] UX-2/UX-3 enforced in engine: not applicable (no engine change).
- [x] Accessibility (UI): not applicable.
- [x] Performance: not applicable.
- [x] No new dependency without ADR: none added.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Correct day bounds across a midnight DST change keep items on the right local day (FR-A1). No copy added, and no banned token in the diff. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference path changed. |
| P-2 No data leaves device (except user iCloud) | n.a. | Tests only. Zone data is local. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No change. |
| P-4 Media not persisted without consent | n.a. | No media. |

## Verdict
**APPROVE.** No open Blocker or Major. n1–n3 are optional Nits. This is a merge decision on PR #39 only. It does not
accept AC-M2-03 on tzdata 2026f, which still needs the owner's Mac rerun (i1), recorded by the Acceptance Tester.

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Reviewer | accepted | Review PR #39 at `2374aad` against PO ruling option C (AC-M2-03 Q6(e), Q11). |
| 2026-11-25 | Reviewer | Orchestrator → Merge Gatekeeper, Acceptance Tester | sent | APPROVE. UTC instants verified by hand, by Python `zoneinfo` and by `zdump` on 2026f. 570 passed, 0 warnings. 2/2 mutants killed. No weakening. Tester: confirm the AC-M2-03 cases and record the owner's Mac rerun (i1). |
