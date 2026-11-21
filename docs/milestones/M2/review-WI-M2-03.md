# M2 Code Review — PR #18 (WI-M2-03, `m2/time-resolver`; round 1 @ `09346cf`, PR head `65e3665`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Scope:** WI-M2-03: `TimeHint`, the Q6 time resolver and `RecurrenceSettlement` in `TendIngestion`. This item owns
  **AC-M2-03** (FR-A1). It also supplies Q5 step 5 (the window and the 366-day range rule) and step 6 (interval
  settlement) for WI-M2-05 (AC-M2-02). Code diff reviewed: `ce3ad5a..09346cf` (4 files: `Time/TimeHint.swift`,
  `Time/TimeResolver.swift`, `TimeResolverTests.swift`, `dev-notes.md`).
- **Inputs read:** `CLAUDE.md`; `docs/milestones/M2/brief.md` (AC-M2-03, Q5, Q6 with (a)–(f), T-08); `plan.md` (the
  WI-M2-03 row and the full "Q6 time-phrase table": hint, notation, T1–T15, R1–R7, "How the hint meets Q5",
  E1–E21) at `09346cf`, **and the plan as changed on the same branch at `65e3665`** (PO Q-T1/Q-T2, E22–E26);
  `dev-notes.md` WI-M2-03 (DT1–DT10, Q-T1, Q-T2); M1 `SlotCalendar.swift` (for the slot rules that are copied).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, so M2 build work is allowed (CLAUDE.md §5). M2 is still shown
  as `PLANNING`; the `IN-BUILD` change is an owner merge, as for WI-M2-01. Not a code finding.

## Summary

**Important change since the brief for this review.** I was told that Q-T1 and Q-T2 are open and to judge the code as
built. When I checked the PR on GitHub, its head was no longer `09346cf` but `65e3665`. Two commits after `09346cf`
(`815fd33`, `65e3665`, plan only) record the **PO's answers to Q-T1 and Q-T2 (2026-11-21)**. They change the R5 row,
the note under the repeat table and the invalid-hint bullet, and they add E22–E26. The Tester approved those rows. The
plan now says the WI-M2-03 test scope is E1–E26 and "Developer reworks PR #18". **The PO picked the other reading in
both cases.** So the code at `09346cf` no longer meets the table that AC-M2-03 ("equal the table exactly") points to:

- Q-T1: a weekday anchor with a `month` or `year` repeat must set weekdays to {W}. The code sets {W} only with `week`
  (DT2). **E23 fails.**
- Q-T2: an invalid anchor falls back to the T1 window, but a valid daypart and a valid repeat still count. The code
  ignores the whole hint (DT1). **E22 and E25 fail.**
- E22–E26 have no tests. E26 (weekdays drop when step 6 drops the interval) cannot be expressed with the
  `RecurrenceSettlement` API, which does not see weekdays.

I checked all of this by running the resolver at `09346cf` on the E22–E25 hints (table below). These are R1-F1…F3,
all Major. Since AC-M2-03 is defined by the table as it is now, the PR cannot merge as it is.

**Against the table as it was at `09346cf`, the work is very good.** Every row T1–T15 and R1–R7 matches the text. I
recomputed 26 UTC values with Python `zoneinfo` and all of them match, including E1, E2, E10–E13, E15–E21, three
Santiago cases and three Havana cases. The 366-day rule is right at both ends. There are no banned UX-3 tokens, no
Foundation I/O, no clock or device reads, and no concurrency hazard. The tests are real: I planted 17 mutants and the
suite killed all 17. The duplicated slot rules have a working drift oracle, and I confirmed it by moving M1's evening
start. The rework should be small. The rest of the code can stay as it is.

### What I ran (Linux container, Swift 6.2.4 via `swift:6.2-noble`, fresh worktree `/home/user/wt-rev18` at `09346cf`)
| Command | Result |
|---|---|
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete! (6.68s)`, 0 warnings. (A plain `swift build` at the repo root does not apply: there is no root `Package.swift`.) |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 34 tests in 4 suites passed after 3.654 seconds.` 0 warnings (`grep -c warning:` = 0). Parameterised counts: E 20, rows 58, repeats 25, invalid 15, firstWeekday 7, Santiago 8, Havana 3, settlement 8. Logs: `TimeResolver property: seed 0x71E50A11CE000003, 6000 cases over 7 zones` → `4116 resolved from the hint, 1884 fell back to T1`; `Slot oracle: seed 0x51070AC1E, 1,400 cases over 7 zones`. |
| AC-M2-09 regression (inside the run above) | `AC-M2-09 scan: TendIngestion (required) Packages/TendIngestion/Sources: 6 files scanned`, `AC-M2-09 scan: 6 files in total, 0 violations`. |
| Code diff `09346cf..65e3665` | `Packages/` unchanged (plan.md only), so the run above also holds for the PR head. |
| GitHub checks on `09346cf` | `TendCore swift test (Linux)`: success; `gatekeeper`: skipped. `TendIngestion` is not yet in CI (HM-1, as for PR #15). |

### Independent recomputation (Python 3 `zoneinfo`; M1 Q11 policy re-implemented: gap → next existing instant, repeated → `fold=0`)
| Case | Expected (mine) | Test / plan | Match |
|---|---|---|---|
| E1 T2, 23 h day | `[2026-03-08T14:00Z, 2026-03-09T04:00Z)` 14 h | same | ✔ |
| E2 T4, 25 h day | `[2026-11-02T00:00Z, 2026-11-02T10:00Z)` | same | ✔ |
| E3 T9 Sun 18:00 | `[2026-11-07T05:00Z, 2026-11-09T05:00Z)` | same | ✔ |
| E10 T12 before March | `[2026-02-20T14:00Z, 2026-03-01T05:00Z)` | same | ✔ |
| E11 T12 Dec in Dec | `[2026-12-31T20:00Z, 2027-12-01T05:00Z)` | same | ✔ |
| E12 T6, 23 h day | `[2026-03-08T09:00Z, 2026-03-08T16:00Z)` | same | ✔ |
| E13 T1 | `[2026-03-07T16:00Z, 2026-03-14T16:00Z)` 168 h absolute | same | ✔ |
| E15 / E16 T10 | `[11-02T05:00Z, 11-09T05:00Z)` / `[11-01T22:59Z, 11-02T05:00Z)` | same | ✔ |
| E17 / E18 T11 | 169 h `[10-26T04:00Z, 11-02T05:00Z)` / 167 h `[03-02T05:00Z, 03-09T04:00Z)` | same | ✔ |
| E19 T4 after midnight | `[2026-11-23T06:00Z, 2026-11-24T10:00Z)` 28 h | same | ✔ |
| E20 T14 night | `[2026-11-23T03:00Z, 2026-11-23T10:00Z)` | same | ✔ |
| E21 T9 + morning Sun 15:00 | Sun morning ended (assert), coming weekend `[11-07T10:00Z, 11-08T17:00Z)` | same | ✔ |
| CL tomorrow (gap at midnight) | `[2026-09-06T04:00Z, 2026-09-07T03:00Z)` 23 h | same | ✔ |
| CL tonight across the gap | `[2026-09-06T00:00Z, 2026-09-06T08:00Z)` | same | ✔ |
| CL next week across the gap / CL Sat night across fall-back | `[09-07T03:00Z, 09-14T03:00Z)` / `[2027-04-04T01:00Z, 04-04T09:00Z)` | same | ✔ |
| CU today (repeated midnight, first) | `[2026-10-31T14:00Z, 2026-11-01T04:00Z)` | same | ✔ |
| CU tomorrow 25 h / 23 h (gap) | `[11-01T04:00Z, 11-02T05:00Z)` / `[03-08T05:00Z, 03-09T04:00Z)` | same | ✔ |
| T12 "before March" at 1 Mar 2027 00:00 | exactly 366.0 days → kept | kept | ✔ |
| E22 / E25 windows (new plan) | `[2026-11-23T15:00Z, 2026-11-30T15:00Z)` | resolver: same window | ✔ window; ✘ interval / dayparts (R1-F1) |
| E23 / E24 windows (new plan) | `[2026-11-26T05:00Z, 2026-11-27T05:00Z)` | resolver: same window | ✔ window; ✘ E23 weekdays (R1-F2) |

### The resolver at `09346cf` on the new rows E22–E25 (probe test in a scratch copy; not committed)
| # | Hint | Resolver output | Plan at `65e3665` | Result |
|---|---|---|---|---|
| E22 | `weekday`, no weekday, + 1 `week` | T1 window, dayparts ∅, weekdays ∅, **interval nil**, basis `fallback(requiredFieldAbsent)` | interval **7** | ✘ |
| E23 | `weekday` Thu + 1 `month` | T7 window, **weekdays ∅**, interval 30 | weekdays **{thursday}** | ✘ |
| E24 | `weekday` Thu + 1 `day` | T7 window, weekdays ∅, interval 1 | same | ✔ |
| E25 | `inDays` 400 + `evening` | T1 window, **dayparts ∅**, no interval, basis `fallback(fieldOutOfRange)` | dayparts **{evening}** | ✘ |
| E26 | E23 settled as one-off | `RecurrenceSettlement.settle` returns `(kind, intervalDays)` only; weekdays cannot be dropped | weekdays all seven, no interval | not expressible (R1-F3) |

### Row-by-row check against the table at `09346cf`
- **T1/T15** `[now, now + 604,800 s)`, daypart → {p} (`TimeResolver.swift:182-183`, `114-118`). ✔
- **T2** `[now, mid(D+1))` (`:186-188`). ✔ **T3** `[max(now, slot.start), slot.end)`, and if `slot.end ≤ now`,
  `slot(p, D+1)`. `≤` is right; the 17:00 "afternoon" case tests the boundary (`:190-192`). ✔ DT6 (today + night at
  01:00 gives tonight's slot) is the literal table.
- **T4** `[now, at(05, D+1))`, {evening, night}, daypart ignored (`:194-196`, `:115`). ✔
- **T5–T8** `firstOffset(after: 0…)` scans 1…7, so said on the same weekday it means next week (`:349-351`). ✔ Samoa
  probe (2011-12-29, Apia): Friday → 6 Jan 2012, weekend and next week land on real days. ✔
- **T9 / Sunday 18:00:** Mon–Fri `[mid(Sat), mid(Sat+2))`, Saturday `[now, mid(D+2))`, Sunday < 18 `[now, mid(D+1))`,
  Sunday ≥ 18 `[mid(D+6), mid(D+8))` (`:242-261`). Daypart `[max(now, slot(first).start), slot(last).end)` with
  the "end ≤ now → `[slot(D+6).start, slot(D+7).end)`" branch (`:263-272`). ✔ The 18:00 cut-off reads the local
  hour of `now` (`:291-293`), so 17:59:59.5 is "before" (tested). ✔
- **T10** `[now, mid(nextMon))`, Sunday ≥ 18 → T11 window (`:211-216`). ✔ **T11** 7 calendar days, `mid(nextMon+7)`
  (`:218-222`), E17/E18 169 h/167 h. ✔
- **T12/T13** earliest `mid(1 M y)` later than `now`, years `[y, y+1]` in the local year (`:277-288`); strict `>`
  (1 Dec 00:00:00 → a year ahead, tested); meteorological northern seasons (`TimeHint.swift:47-54`). ✔
- **T14** `d = D + N` or `D + 7N`, 1…366 / 1…52, slot with a daypart (`:233-237`). ✔
- **Daypart with T10–T13:** sets {p}, window unchanged. ✔
- **R1–R4** `N × {1, 7, 30, 365}`, overflow → nil (`:136-140`). ✔ **R6** {sat, sun} (`:122-123`). ✔ **R7** ✔.
  **R5**: correct against the old note; wrong against PO Q-T1 (R1-F2).
- **366-day rule** (`:146-154`): `start < now`, `start > now + 31,622,400 s`, `end > start + 31,622,400 s` fall back;
  equality is kept; `end ≤ start` is `emptyWindow`. The ±1 ms boundary tests are present (test `:554-566`). ✔
- **Q6(a)** no rule reads `firstWeekday`; every case reruns with `firstWeekday` 1…7. ✔
- **Non-finite `now`** never traps (NaN, ±∞ tested; I probed finite extremes 1e12…`greatestFiniteMagnitude`: no trap;
  all fall back calmly). One small gap (R1-F5).

### My planted mutants (scratch copy `/tmp/claude-0/rev18/w`, each applied alone, then restored; nothing committed)
| # | Mutant | Result |
|---|---|---|
| M1 | T9 start always `mid(first)` (drops `now` on Sat/Sun) | killed (86) |
| M2 | T9 daypart start `firstSlot.start` (drops `max(now, …)`) | killed (50) |
| M3 | Day anchor noon → 02:00 (`noon(ofDayContaining:)`) | killed (5, the DST cases) |
| M4 | T12 candidate years `[y+1, y]` | killed (35) |
| M5 | Saturday window `(0, 0)` instead of `(0, 1)` | killed (45) |
| M6 | Night end = `at(05, d) + 86,400 s` instead of `at(05, d+1)` | killed (2, Santiago fall-back) |
| M7 | Sunday cut-off `>` 18 instead of `>=` | killed (83) |
| M8 | Range rule `start < now − 1 s` | killed (2) |
| M9 | Tonight's dayparts also include the hint's daypart | killed |
| M10 | T9 weekdays {sat, sun} only with a repeat | killed (67) |
| M11 | T9 coming-weekend first day `D+7` instead of `D+6` | killed (19) |
| M12 | `inWeeks` range 1…53 | killed (2) |
| M13 | Non-finite `now` guard removed | killed (2) |
| M14 | Winter starts in November | killed (19) |
| M15 | T3 "slot has ended" → `slot(p, D)` instead of `D+1` | killed (50) |
| M16 | Range limit `start > now + 367 d` | killed (7) |
| M17 (drift) | **TendCore** `Daypart.evening.startHour` 17 → 18, TendIngestion unchanged | killed **only** by "AC-M2-03 oracle: T6 slot(p, D+1) equals M1's …", which proves the drift oracle works for slot starts |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R1-F1 | **Major** | `Packages/TendIngestion/Sources/TendIngestion/Time/TimeResolver.swift:86-100`, `:156-165`; tests `TimeResolverTests.swift:375-396`, `:431-439`, `:640-645` | **PO Q-T2 is not built (AC-M2-03, plan "How the hint meets Q5" at `65e3665`, E22, E25).** Every `.unusable` or out-of-range result goes to `Self.fallback`, which hard-codes dayparts ∅ and interval `nil`. Under Q-T2, an invalid anchor gives the T1 window and ∅ weekdays, but a valid daypart still gives {p} and a valid repeat still gives its interval. Probe: E22 gives interval `nil` (expected 7), and E25 gives dayparts ∅ (expected {evening}). So a recurring "every week" item whose weekday was lost becomes a one-off in step 6, which the PO has ruled out. The tests pin the old behaviour: the invalid-hint test expects ∅ / `nil`, the first `InvalidHints` row sends `morning` + daily, and the property test expects ∅ / `nil` on every fallback. | On an invalid anchor (any `FallbackReason` except a non-finite `now`), return the T1 window and weekdays ∅, dayparts `dayparts(of:)` (that is {p} if the daypart is valid; a broken `tonight` cannot happen), and interval `interval(of:)`. Keep `basis = .fallback(reason)`. Update the invalid-hint test, its `InvalidHints` rows and the property-test fallback assertion to the new rule. Add E22 and E25 as exact cases. Update DT1 in dev-notes. Changing these tests follows a PO product decision. It is not a weakening, but say so in the dev-notes. | Open |
| R1-F2 | **Major** | `TimeResolver.swift:124-127`; test `TimeResolverTests.swift:346-350` | **PO Q-T1 is not built (R5 row at `65e3665`, E23).** `guard hasRepeat, hint.repeatUnit == .week` sets {W} only for weekly repeats. The PO's R5 covers `week`, `month` and `year`, and only a `day` repeat keeps ∅ (E24). Probe: E23 gives weekdays ∅, but {thursday} is expected. The test "weekday + monthly repeat: weekdays stay empty" pins the rejected reading. | Set {W} when the anchor is `weekday`, the weekday is present, the interval is non-nil, and `repeatUnit ∈ {week, month, year}`. Replace the pinned test with E23 and E24, and add a yearly case. Update DT2. | Open |
| R1-F3 | **Major** | `TimeResolverTests.swift:400` (worked examples E1–E21 only); `TimeResolver.swift:398-410` (`RecurrenceSettlement`) | **No tests for E22–E26.** The plan's WI-M2-03 scope is now E1–E26 (plan WI-M2-03 paragraph at `65e3665`), so these AC-M2-03 rows have no tests. That alone is Major. E26 also needs Q5 step 6 to drop R5's {W} together with the interval. `settle(kind:intervalDays:)` cannot do that, because it does not see weekdays, and no test shows that the drop happens anywhere. | Add E22–E25 to the worked examples as exact resolver-output cases. For E26, either (a) extend `RecurrenceSettlement` to settle the weekdays too (for example `settle(kind:resolution:)` returning kind, interval and weekdays, where a dropped interval clears an R5 {W}) and test E26 here, or (b) get the Planner to record that E26 is tested in WI-M2-05 (AC-M2-02) and say which API carries it. Option (a) is preferred because the plan places E26 in WI-M2-03's scope. | Open |
| R1-F4 | Minor | `TimeResolver.swift:387-395` (`endHour`); test `TimeResolverTests.swift:656-679` | **The drift oracle covers slot starts only.** M17 shows the oracle catches a change to an M1 start hour. But in M1 a slot's end is defined as the next slot's start (`SlotCalendar.swift:98-100`), while `TendIngestion` keeps a second, separate `endHour` table. If M1 moved a start hour, a fix to `startHour` alone would leave a stale `endHour`, and no test would compare it with M1. The oracle's zones also have no DST gap at a slot hour, so a change to M1's Q11 policy at a slot hour would not be seen. | Derive `endHour` from the next daypart's `startHour` (night → `morning.startHour` on `d+1`, as now), or add an end oracle using M1's public API: `nextEligibleWindow(from: end − 1 ms)` returns the anchor itself, and `from: end` returns a later start. Ticket; does not block. | Open |
| R1-F5 | Minor | `TimeResolver.swift:87-90`; test `TimeResolverTests.swift:453-459` | **A non-finite `now` with a `nil` hint is reported as `.noHint`, not `.fallback(.calendarUnresolved)`.** The `nil` guard runs before the finite check, so DT9's claim ("the result is the T1 fallback with reason `calendarUnresolved`") is true only for a non-nil hint. Probe: `resolve(nil, now: .nan)` gives `basis noHint`, with non-finite dates. The test covers only `TimeHint(anchor: .tomorrow)`. WI-M2-05's per-rule counts (AC-M2-02) would count this as "no hint". | Run the finite check first, add the `nil` case to `nonFiniteNow`, and keep DT9 accurate. Note for WI-M2-05: both paths return a non-finite window, which the Q9 invariant (AC-M2-02) rejects with a typed skip. | Open |
| R1-F6 | Minor | `docs/milestones/M2/dev-notes.md` (WI-M2-03: DT1, DT2, Q-T1/Q-T2 rows, "E1–E21", AC coverage) | The handoff note is out of date at the PR head. It lists Q-T1 and Q-T2 as open and gives E1–E21 as the scope. | Update it with the rework: the PO answers, E22–E26, the new test names and counts, and a new run log. | Open |
| R1-N1 | Nit | `TimeHint.swift:16`, `:35-36` | `Anchor.unrecognized` is in `CaseIterable` and has a raw value. The schema mirrors (on-device `@Generable`, cloud schemas, WI-M2-10/12) must not offer it to the model as a valid choice. | Add a doc note, or a `static let modelChoices` that excludes it, for the schema work. | Open |
| R1-N2 | Nit | `TimeResolver.swift:151` with `:233-237` | Observation, not a code defect. "In 366 days" said at local midnight falls back to T1 when D+366 is on the other side of a DST change. Probe: `inDays` 366 at 2026-03-09 00:00 EDT gives `windowOutOfRange`, because `mid(D+366)` = now + 366 d + 1 h. This is the table read literally (count 1…366 against an absolute 366 × 86,400 s limit). | For Tester/PO awareness only. No change needed unless the PO wants it. | Open |

## Checklist
- [ ] Correctness vs ACs: matches the table at `09346cf`, but **not** the current table (PO Q-T1/Q-T2, E22–E26): R1-F1…F3
- [ ] Tests meaningful (would fail if code broke): yes, 17/17 of my mutants killed, plus a working drift oracle (M17). Missing E22–E26 (R1-F3)
- [x] Swift 6 concurrency safe: value types only, all `Sendable`; no `Task`, actor, `@unchecked Sendable` or `nonisolated(unsafe)`; builds with `-warnings-as-errors`
- [x] No force unwraps / `try!` in product code paths (grep on `Time/*.swift`: none)
- [x] Privacy (P-1…P-4): no I/O, no network, no logging, no clock or device calendar/zone/locale read; AC-M2-09 6 files, 0 violations
- [x] UX-2/UX-3 enforced in engine: UX-2 n.a.; UX-3: no overdue state, field or helper; start ≥ `now` always; names checked against the banned list (test), and my grep of the added lines for *overdue, late, missed, failed, behind, penalty, past-due* found nothing
- [x] Accessibility (UI): n.a., no UI
- [x] Performance: O(1) per hint (at most 7 + 2 calendar look-ups); property suite 6,000 cases in ~3 s on Linux debug
- [x] No new dependency without ADR: Foundation + TendCore only (ADR-0006); `TendCore` and protected paths untouched

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Times are inferred from the model's structured hint. Nothing asks the user for a field (FR-A1). |
| UX-2 Rule of Three | n.a. | No selection surface or API in this item. |
| UX-3 Zero-Guilt | pass | No overdue or lateness state, field or helper. Every window starts at or after `now` (range rule; property test). A broken hint falls back calmly to `[now, now + 7 d)`. Case names are checked against the AC-M1-02 list, and my grep of the diff found no banned token. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | Pure deterministic computation. No inference. |
| P-2 No data leaves device (except user iCloud) | pass | No network or I/O API. AC-M2-09 scan: `6 files in total, 0 violations`. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No request is built here. The schema mirrors come in WI-M2-10/12 (see R1-N1). |
| P-4 Media not persisted without consent | pass | No write, log or media API. |

## Open questions
- **Q-T1, Q-T2:** answered by the PO on 2026-11-21 (plan `815fd33`/`65e3665`), so they are no longer open. The code
  must follow the answers (R1-F1, R1-F2). The `DECISIONS.md` entry belongs to the human-merged governance PR (plan
  handoff log).
- **R-10 / Darwin:** not verified here (no Mac). The Santiago and Havana midnight cases rely on Linux Foundation's
  `date(bySettingHour:…, .nextTime, .first)`. The Mac rerun (plan B2, MS-2) must treat any Darwin difference as a
  defect, as the dev-notes say.

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Developer (via Orchestrator) | Reviewer | accepted for review | PR #18, WI-M2-03, code at `09346cf`, stacked on PR #15 (`ce3ad5a`). AC-M2-03. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned (CHANGES REQUIRED, round 1) | The code matches the table as it was at `09346cf`: 26 values recomputed with `zoneinfo`, 17/17 mutants killed, drift oracle proven, 0 warnings, AC-M2-09 0 violations. But the PR head `65e3665` carries PO Q-T1/Q-T2 and E22–E26, which the code does not build. 3 Major findings: R1-F1 (Q-T2), R1-F2 (Q-T1), R1-F3 (no E22–E26 tests, E26 settlement). 3 Minor: R1-F4 (end-hour drift), R1-F5 (non-finite `now` + `nil`), R1-F6 (dev-notes). 2 Nits. Next: Developer rework; Reviewer round 2 on the new head. |
