# M2 Code Review — WI-M2-05, PR #20 (`m2/draft-mapping`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Requirements:** FR-A1, D-016, UX-1, UX-3. ACs: **AC-M2-01** and **AC-M2-02** (owned by this item, plan WI-M2-05).
  The item also touches AC-M2-04 (room linking after the guard, R19-F3), AC-M2-12 (guard in step 7) and AC-M2-03
  (`TimeResolution.init` narrowed, R2-N1). It implements Q5 steps 1–9 and T-07.
- **Commits reviewed:** `d39f434` (code), `4e2991b` (dev notes). Diff `origin/main...HEAD` (base `17c8ab0`). It touches
  only `Packages/TendIngestion/**` and `docs/milestones/M2/dev-notes.md`. No protected path is touched, and no
  dependency is added.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. WI-M2-05 is M2 work, and its DoR is met
  (WI-M2-02, 03 and 04 are merged at `17c8ab0`).
- **Inputs:** CLAUDE.md; brief.md (Definitions: Draft field set, Item completion, Name folding, Banned tokens;
  AC-M2-01, 02, 04, 12; Q5; T-07); plan.md (WI-M2-05 note, Notation ∅ / step 3, "How the hint meets Q5", `basis`);
  design.md; dev-notes.md (WI-M2-05). PO notes: `po-q21-q22.md` (R2-N1 and R19-F3 tickets), `po-m2-wi04.md`
  (ruling 2b), `po-m2-qt1-qt2.md` (Q-T1 E26, Q-T2), and **`po-m2-wi05.md` (PO rulings on this PR, received during
  the review)**.

## Summary
The PR adds the neutral model contract (`ModelChoice`, `ModelNumber`, `TimeHintSnapshot`, `ItemSnapshot`,
`IngestionSnapshot`, `IngestionRequest`, `IngestionModel`), `IngestionDraft` with the brief's field set, and
`DraftMapper`, which runs Q5 in the order `[1, 2, 4, 5, 6, 3, 7, 8, 9]` and logs each repair with its step. It also
makes `TimeResolution.init` internal (R2-N1). All the code is pure, value-typed and `Sendable`, and imports only
Foundation and TendCore.

The engineering is good. AC-M2-01 has hand-written UTC windows in two zones. AC-M2-02 has 6,000 seeded outputs against
a largely independent oracle, which compares the exact repair log, with a coverage check per rule on every seed. 11 of
my own mutants were all killed.

**One Major is open.** PO ruling 1 in `po-m2-wi05.md` reverses decision D1 (R19-F3). A proposed room name that the
guard changes must be re-linked to an existing room by the AC-M2-04 rule. The PR does not re-link, and its test pins
the opposite behaviour. Two Minors and two Nits are listed below. PO rulings 2 (missing anchor = `none`) and 3 (step
order) accept what was built, so neither is a finding.

### AC → code → test
| AC clause | Code | Test(s) |
|---|---|---|
| AC-M2-01: each PRD item type → valid `HouseholdTask` with expected kind, room, effort, flags | `DraftMapper.map` (`DraftMapper.swift:134-224`), `IngestionDraft.task` (`IngestionDraft.swift:68-84`) | `DraftMappingItemTypeTests.itemType` (4 types × NY, London; every draft and task field, hand UTC windows I re-derived: T5, T7/R5, T10, T9 + morning), `criticalBill` (T12) |
| AC-M2-01: dates only from injected `now`, calendar, zone | resolver built from the injected values (`DraftMapper.swift:122-127`) | `datesOnlyFromInjectedInputs` (determinism, `now` + 1 day, `firstWeekday` = Sunday) |
| AC-M2-02: ≥ 1,000 seeded outputs, never crash, never invalid | whole mapper | `DraftMappingPropertyTests.property` (3 fixed seeds × 2,000; `task(...)` never throws; range re-checked; title non-empty) |
| AC-M2-02: degenerate classes listed | generator `OutputGenerator` (`DraftMappingPropertyTests.swift:324-438`) + edge hints | coverage check (`:541-561`): every repair rule and both skip reasons occur on every seed. For end ≤ start, see F3 |
| AC-M2-02: exactly the Q5 rules, in Q5 order, or a typed skip | `repairs` log, `stepOrder` | exact `repairs == expectedRepairs` (`:496`), plus 30+ named step cases in `DraftMappingRepairTests` |
| AC-M2-02: equals an independent oracle of Q5 | — | `Q5Oracle` (`:122-320`); see "Oracle independence" below and F2 |
| AC-M2-02 W2-F3 clause | WI-M2-02 (merged); step 9 net | `initialiserRejects` (NaN, ±∞ `now` → `taskRejected(.windowDateNotFinite)`) |
| AC-M2-04 after the guard (R19-F3) | `DraftMapper.swift:189-194` | `guardCutToExistingRoom` (pins the wrong behaviour; F1) |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | **Major** | `Packages/TendIngestion/Sources/TendIngestion/Draft/DraftMapper.swift:189-194`; `Tests/TendIngestionTests/DraftMappingTests.swift:515-530`; `Tests/TendIngestionTests/DraftMappingPropertyTests.swift:298-307`; `docs/milestones/M2/dev-notes.md` (D1, open question 1) | **R19-F3 / AC-M2-04: no re-link after the guard, against PO ruling 1 (`po-m2-wi05.md`).** Example: "late kitchen", where the user did not say "late", in a household with Kitchen. The draft keeps `proposed("kitchen")`. The PO reads AC-M2-04 as a rule about the draft's final room: `proposed(name)` applies only "if none matches". This draft state also breaks the Definitions invariant "a proposed room never equals an existing room" that WI-M2-07's local word-match relies on. That opens a duplicate-creation path (M2 "zero duplicates" gate) and scores wrong in the eval's Room scoring. The test `guardCutToExistingRoom` and the oracle both encode the reversed choice, so the suite is green on behaviour the PO has ruled out. | Apply ruling 1, items 1–5. (1) In step 7, when the guard changes a `proposed` name to a non-empty name, match the guarded name with the AC-M2-04 rule (name folding, exact, tie → lowest `id.uuidString`), e.g. `RoomLinker.link`. A match gives `existing(id)`. (2) Log it as its own step-7 repair after `roomNameCalmed` (a name that passes the AC-M2-12 scan, e.g. `roomLinkedAfterCalming`), and add it to the coverage list so it occurs on every seed. (3) Flip the R19-F3 test to `existing(kitchen.id)`, keeping the commit plan's no-new-room check. Add a tie case (two rooms folding to "kitchen" in several array orders → lowest `uuidString`) and a no-match case ("late pantry" → `proposed("pantry")`). (4) Give the oracle its own fold-and-compare with `String <` ties (it already has `link`, so reuse that pattern). Kill the reverse mutant "no re-link after the guard" and record it. (5) Update dev notes D1 and open question 1 with the ruling. | Open |
| F2 | Minor | `Tests/TendIngestionTests/DraftMappingPropertyTests.swift:13-16, 253-254`; `docs/milestones/M2/dev-notes.md` (D8) | **The oracle depends on two production functions.** It calls `TimeResolver.resolve` (window, dayparts, weekdays, interval and `basis`, so it also inherits the resolver's Q5 step 5 range fallback) and `TextFolding.foldName`. The AC-M2-02 property alone is therefore blind to defects there. Reviewer mutant `p-no-article-strip` (empty `leadingArticles`) gave **0 oracle mismatches** in the property, and `o-fallback-6d` was not caught by it either. Both were killed elsewhere: by AC-M2-01, AC-M2-04, the AC-M2-03 suite (hand-written UTC tables and E1–E26), `TextPrimitivesTests` and `windowFallback` (literal 604,800 s). I accept this as independent enough for AC-M2-02: Q6 and name folding are Q5's named inputs, not Q5 repairs, and every Q5 repair is re-implemented. But the independence is conditional, and the evidence should say so. | In dev notes D8 (and the Tester's AC-M2-02 evidence), state that the oracle's Q6 and folding parts are verified by AC-M2-03 and `TextPrimitivesTests`, with these two mutants as proof. Optional: have the oracle check the step 5 fallback itself (`basis != .hint` ⇒ window == `[now, now + 604,800 s)`, weekdays ∅). This one line would make the property catch `o-fallback-6d` too. | Open |
| F3 | Minor | `Tests/TendIngestionTests/DraftMappingPropertyTests.swift:361-394`; `docs/milestones/M2/dev-notes.md` (D7, counts table) | **AC-M2-02's "end ≤ start" class is not in the generator.** It cannot be, because the snapshot contract carries no dates (D7). The resolver's `emptyWindow` branch is covered only by `TimeResolverTests.swift:646-647` (WI-M2-03), and "non-finite date" only by the step 9 test with a non-finite `now`. That is correct, but the AC-M2-02 evidence ("counts per repair rule") shows no entry for these two listed classes. A Tester reading the counts table would see a listed class with no count. | Add a line to the AC-M2-02 coverage notes that maps "end ≤ start" → structurally impossible from the contract + `rangeProblem` unit test (`TimeResolverTests.swift:646-647`), and "non-finite" → `ModelNumber` nil (generator `odd` values) + `initialiserRejects`. No code change. | Open |
| F4 | Nit | `Tests/TendIngestionTests/DraftMappingTests.swift:176-215` | The AC-M2-01 cases never assert the draft title against an expected string (only `task.title == draft.title`). | Optional: add an expected `title` per case. | Open (optional) |
| F5 | Nit | `Sources/TendIngestion/Draft/DraftMapper.swift:186` | `CalmWordsGuard.calmed(title, input:)` runs a second time only to label the repair. It is correct (I checked that a fallback title can never equal the original title), but the result is derived twice. | Optional: have the guard return which path it took. | Open (optional) |

**Open: 1 Major (F1), 2 Minor, 2 Nit. No Blocker.**

### The points the Orchestrator asked about
- **Step 3 after 5 and 6 (`[1,2,4,5,6,3,7,8,9]`).** The brief's Q5 order lists 3 before 4. The plan's Notation says
  "WI-M2-05 applies the Q5 step-3 defaults to the resolver's empty sets after step 5". I checked whether moving step 3
  changes any result the brief fixes:
  - Steps 4, 5 and 6 never read dayparts or weekdays, so the move changes no other field.
  - T-07's example (unknown kind → one-off → interval dropped) is unchanged (`orderUnknownKindThenInterval`).
  - E26 (PO Q-T1: "weekdays are all seven") *requires* step 3 after step 6 (`orderE26`; the developer's mutant
    "weekday default before step 6" is killed).
  - Only the order of the diagnostic `repairs` log differs from the brief's numbering.

  **PO ruling 3 (`po-m2-wi05.md`) accepts this order.** The brief Q5 row gets a clarifying sentence in the next
  governance PR. Not a finding.
- **Oracle independence (AC-M2-02).** It is independent enough, with the caveat in F2. The oracle reads the raw
  strings and `Double`s, not the snapshot the code builds. It re-derives step 2 (with its own `whole()` instead of
  `ModelNumber`), steps 3, 4 and 6, the R5 drop from the hint (not from `weekdaysFollowRepeat`; mutant `s-no-R5-flag`
  is killed by the property), the guard over `Character.isLetter` runs, the substring check and the room tie. It never
  calls `DraftMapper`, `RecurrenceSettlement`, `CalmWordsGuard`, `SourcePhrase`, `RoomLinker` or `BannedTokens`
  (verified by reading `:122-320`). The two shared functions are Q5's named inputs (Q6, name folding), and other suites
  with hand-written values pin them.
- **R2-N1.** `TimeResolution.init` is now internal (`TimeResolver.swift:46-48`). The step 5 resolution comes only from
  `resolver.resolve` (`DraftMapper.swift:161`), and step 6 uses `RecurrenceSettlement.settle(kind:resolution:)`, so
  `weekdaysFollowRepeat` always matches how the weekdays were made. No caller outside the module exists yet (`TendAI`
  is not built). The WI-M2-03 tests use `@testable` and are unchanged. Closed.
- **R19-F3.** Reversed by the PO. See F1.
- **Missing anchor = `none` (Q-T2, D3).** A present hint with no anchor resolves as T1/T15: the daypart and repeat
  still count, R5 cannot apply, and `anchorDefaulted` is logged. I compared it with treating it as an invalid anchor.
  The draft fields are identical (T1 window, {p} or ∅, same interval, ∅ weekdays). Only the repair log differs (no
  `windowDefaulted`). **PO ruling 2 confirms it as built.** The reserved `unrecognized` raw value is treated as unknown
  (mutant `x` killed). Not a finding.

### Other points checked and found sound
- **Q5 per step.**
  - (1) `collapseWhitespace`, and a blank title is skipped with no other repairs.
  - (2) Missing equals unknown for kind and effort (D2, from "Q5 repairs fill any missing field"). `roomDefaulted`
    is logged only when room text is present (mutant `a` killed). Unknown elements are dropped.
  - (4) Before (5).
  - (6) `becameOneOff` and `intervalDropped` are exclusive (mutant `d` killed). The range is 1…730 (mutant `m`
    killed).
  - (7) Ruling 1 of `po-m2-wi04.md`: the fallback is checked and calmed.
  - (8) The phrase is kept as given.
  - (9) A probe ID that no invariant reads.
- **Step 9 reachability.** It is reachable only with a non-finite `now`. Over 6,000 cases it gave 0 `taskRejected`,
  which matches "the oracle must show [this] never happens".
- **Contract.** `IngestionDraft.init` is internal, and `duplicate` is `internal(set)`, so only the module makes or
  marks drafts. `ModelChoice.init(raw:)` matches exactly (D4). `ModelNumber.wholeNumber` = `Int(exactly:)`, tested at
  NaN, ±∞, 2.5 and ±9.3e18. `IngestionRequest` holds only text and room names (ADR-0005 Decision 3).
- **`draftID` and commit order (PO WI-M2-04 ruling 2a).** D6 records ascending `draftID` for WI-M2-06/08. That is the
  correct hand-off. WI-M2-06/08 must state and test it.
- **UX-3 names.** `ItemRepair` and `ItemSkipReason` case names hold no banned token (vocabulary scan: 13 files,
  9 exempted, 0 violations).
- **Swift 6.** Value types only, all `Sendable`. No `@unchecked`, no `nonisolated(unsafe)`, no tasks. No force unwrap
  or `try!` in Sources (the `!` in `MappingFixtures.zone` is test-only).
- **Performance.** O(rooms) per item for linking and O(n·m) per phrase. Fine for an utterance.

## Test runs (Reviewer, this run)
Environment: Linux container, `docker run swift:6.2-noble`, **Swift 6.2.4 (swift-6.2.4-RELEASE)**, worktree
`/home/user/wt-rev20` detached at `4e2991b`. These are the CI commands of `.github/workflows/ci.yml`, each with its own
`--scratch-path /tmp/rev20-<pkg>`:

| Command | Result |
|---|---|
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!`, 0 warnings |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 114 tests in 11 suites passed after 6.863 seconds.` AC-M2-02: seed `0xA11C0DE5EED0501` 1,697 drafts / 303 skipped, `…0502` 1,757 / 243, `…0503` 1,717 / 283. Total 5,171 drafts and 829 skipped, **0 oracle mismatches** (matches dev notes) |
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 1.967 seconds.` |
| `swift build` + `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 129.077 seconds.` |

After the mutation run, the clean re-run gave `✔ Test run with 114 tests in 11 suites passed after 6.620 seconds.`, and
`git status` is clean.

### Reviewer mutants (each applied alone by script, full TendIngestion suite, then restored)
| Mutant | Result |
|---|---|
| `d` log `intervalDropped` for a kept recurring interval | killed (property, `recurringKeepsWeekday`) |
| `a` log `roomDefaulted` when there is no room text | killed (property + 6 step tests) |
| `m` interval range 1…729 | killed (property, `recurringKeeps`, settlement suite) |
| `o` T1 fallback 6 days instead of 7 (shared with oracle) | killed by the AC-M2-03 suite and `windowFallback`; **not** by the property (F2) |
| `s` resolver never sets `weekdaysFollowRepeat` | killed (property, E26 tests): the oracle's R5 drop is independent |
| `p` name folding strips no article (shared with oracle) | killed by AC-M2-01, AC-M2-04, `TextPrimitivesTests`; property alone: 0 mismatches (F2) |
| `x` reserved `unrecognized` anchor treated as known | killed (property, `anchors`) |
| `v` guard sees the title as part of the input | killed (property + 2) |
| `y` `roomNameCalmed` never logged | killed (property + 2) |

9 of 9 behaviour mutants are killed by the suite. Two of them (`o`, `p`) are caught only outside the AC-M2-02 property,
which is the caveat in F2.

## Checklist
- [ ] Correctness vs ACs (AC-M2-01 and AC-M2-02 met; AC-M2-04 after the guard is not, per PO ruling 1: F1)
- [x] Tests meaningful (would fail if code broke): 9/9 reviewer mutants killed; caveat F2
- [x] Swift 6 concurrency safe
- [x] No force unwraps / try! in product code paths
- [x] Privacy (P-1…P-4)
- [x] UX-2/UX-3 enforced in engine (UX-3 guard in step 7; UX-2 n.a.)
- [ ] Accessibility (UI): n.a., no UI
- [ ] Performance (main thread, allocations, 120 Hz): n.a. for UI; mapping cost is fine
- [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every draft field is inferred or repaired to a default (AC-M2-01, AC-M2-02). F1's fix makes the draft show the room commit will use, so the user has nothing to correct (PO ruling 1). |
| UX-2 Rule of Three | n.a. | No selection surface. Drafts reach Now only after commit, through `NowSelector`. |
| UX-3 Zero-Guilt | pass | Step 7 runs the guard on every title and proposed room. The property checks that no title holds an unsaid banned token. No overdue state: the window always comes from the resolver, in range. Case names pass the AC-M2-12 vocabulary scan. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. The contract is neutral across adapters. |
| P-2 No data leaves device (except user iCloud) | pass | Pure functions. AC-M2-09 scan: 13 files, 0 violations. `IngestionRequest` holds only text and room names. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path. |
| P-4 Media not persisted without consent | pass | No write or log API. Parsing creates no room or task. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Reviewer | accepted | PR #20 at `4e2991b`. Points: step order, oracle independence, R2-N1, R19-F3, missing anchor. |
| 2026-11-21 | Orchestrator | Reviewer | accepted | PO rulings `po-m2-wi05.md`: ruling 1 reverses R19-F3 (re-link required), rulings 2 and 3 accept as built. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: F1 Major (re-link per PO ruling 1, items 1–5). F2 and F3 Minor (evidence notes), F4 and F5 Nit, all to fix in the same round. Re-review covers the F1 delta and the new mutant. |
