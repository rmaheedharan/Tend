# M2 Code Review — WI-M2-04, PR #19 (`m2/calm-words-and-rooms`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** FR-A1 (room linking, `sourcePhrase`), UX-3 (calm-words guard). ACs: **AC-M2-04**, **AC-M2-12**
  (owned by this item, plan WI-M2-04). Touches AC-M2-09 / AC-M1-02 (vocabulary scan exemption, E1). Q5 steps 7 and 8.
- **Commits reviewed:** code at `a402372`. Re-run on the merged head `a4f43b7` (origin/main merged by the
  Orchestrator). Checked: `git diff a402372 a4f43b7` leaves every WI-M2-04 file unchanged (`Guard/`, `Rooms/`, `Text/`,
  the three WI-M2-04 test files). The merge adds only WI-M2-03 (time resolver) files and docs.
- **Milestone lock:** `STATUS.md`: M1 `ACCEPTED`, M2 `IN-BUILD`. WI-M2-04 is M2 work, and its DoR (WI-M2-01 merged,
  `8076d64`) is met. No protected path is touched (`git diff --stat`: only `Packages/TendIngestion/**` and
  `docs/milestones/M2/dev-notes.md`).
- **Inputs:** CLAUDE.md, brief.md (Definitions, AC-M2-04, AC-M2-09, AC-M2-12, Q5), plan.md (WI-M2-04, layout, exact
  commands), design.md, dev-notes.md (WI-M2-04), PO notes `po-q21-q22.md` and **`po-m2-wi04.md` (PO rulings on E4,
  E6, E2/E3: all ACCEPT as built, no code change)**.

## Summary
The item adds four small, pure `TendIngestion` files: `CalmWordsGuard`, `DraftRoom`, `RoomLinker` (link at parse
time, plus a commit plan) and `SourcePhrase.checked`. It also adds a calm-vocabulary scan of the module Sources with one
narrow, fail-closed exemption for the banned list itself. All files import only Foundation (plus TendCore for `Room`).
They have no state, no I/O, no ambient time, locale or randomness, and no concurrency surface.

Every clause of AC-M2-04 and AC-M2-12 maps to a named test whose expected values come from the brief (see the
mapping below). The three open product questions (E2/E3, E4, E6) were ruled on by the PO in `po-m2-wi04.md`, and the
code matches each ruling. My own mutation run (11 mutants) killed 10. The survivor is the commit-time tie rule that
PO Ruling 2b adds (F1, Minor). No Blocker or Major is open.

### AC → code → test
| AC clause | Code | Test(s) |
|---|---|---|
| AC-M2-04 link by name folding, exact | `RoomLinker.link` (`RoomLinker.swift:27-35`) | `linksByNameFolding` (13), `noFuzzyMatch` (8), `noName` (4) |
| AC-M2-04 tie: lowest `id.uuidString` | `lowestRoom` (`RoomLinker.swift:78-82`) | `tieGoesToLowestUUIDString` (3 orders + hex order) |
| AC-M2-04 no match: `proposed(name)` after guard; emptied: `none` | `link` + `CalmWordsGuard.apply` (`CalmWordsGuard.swift:56-60`) | `proposedKeepsText`, `linkThenGuard`, `proposedRoomNameGuarded` |
| AC-M2-04 created only on commit; equal folded proposals: one room | `commitPlan` (`RoomLinker.swift:43-75`) | `oneRoomForEqualProposals`, `distinctProposals`, `nothingConfirmed` |
| AC-M2-04 nothing created or renamed while parsing | pure `link`/`apply` | `parsingCreatesNoRoom` |
| PO Ruling 2b/2c (commit uses existing room; a missing room gives `none`) | `RoomLinker.swift:57-62` | `proposalMatchingExistingRoomAtCommit`, `missingExistingRoom` |
| AC-M2-12 split at non-letters, folded, whole tokens | `BannedTokens.matches` (WI-M2-01) used by `calmed` | `matchingIsFolded`, `wholeTokensOnly`, `everyListedTokenIsRemoved` |
| AC-M2-12 removed only if not in the whole input (Ruling 3, E2: whole-token set) | `CalmWordsGuard.swift:28-31` | `userWordsKept` (7), `inputComparedAsWholeTokens` (3) |
| AC-M2-12 tidy only after a removal; P* trimmed, symbols kept (Ruling 3, E3) | `CalmWordsGuard.swift:31-39, 69-87` | `removesIntroducedTokens` (12), `unchangedWithoutRemoval` |
| AC-M2-12 empty title becomes the `sourcePhrase` (Ruling 1, E4: checked, tidied, calmed) or is skipped with a typed reason | `CalmWordsGuard.swift:48-55` | `emptyTitleBecomesSourcePhrase`, `emptyTitleSkipped` (4), `fallbackTitleIsTidied`, `fallbackTitleIsGuarded` |
| AC-M2-12 user's words kept, incl. room names | as above | `userWordsKept`, `proposedRoomNameUserWordsKept`, `userLabelWithBannedTokenLinks` |
| AC-M2-12 outcome/reason names and instructions hold no banned token | `CalmWordsSkipReason.noTitleWordsLeft`; vocabulary scan | `reasonNamesAreCalm`, `CalmVocabularyScanTests.scanSources` + 7 exemption negative tests |
| Q5 step 8 `sourcePhrase` substring check | `SourcePhrase.checked` | `SourcePhraseCheckTests` (kept 10, dropped 5, empty 4, both sides) |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Rooms/RoomLinker.swift:62`; `Tests/TendIngestionTests/RoomLinkingTests.swift:171` | PO Ruling 2b says that at commit, a proposal that folds to an existing room's name uses "lowest `id.uuidString`, same tie rule as AC-M2-04 linking". The code does this, but no test has two existing rooms folding to the proposal's name. Reviewer mutant `commit-existing-ignores-tie` (replace `lowestRoom` with `rooms.last(where:)`) **survived** (79/79 green). The AC's literal tie clause is tested at link time, so this is not a missing AC test. It is an untested branch of an accepted ruling. | Add a commit-plan test with two or more existing rooms that fold to the proposed name, in several array orders, and expect the lowest `uuidString`. Ticket to the next WI-M2-04 touch or WI-M2-08 (commit). | Open (ticket) |
| F2 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Rooms/RoomLinker.swift:67` | `commitPlan` takes each new room's ID from `makeID()` without checking it against `existingIDs` or IDs already issued in this plan. AC-M2-06 ("If the generator returns an ID already in use, commit takes the next one and never overwrites") applies to rooms as well as tasks. AC-M2-06 belongs to WI-M2-08 and nothing calls `commitPlan` yet, so this is not a defect in this item. But the public API leaves that duty to the caller and does not say so. | Either skip in-use IDs inside `commitPlan` (it already has `existingIDs`), or document the precondition on `makeID`. WI-M2-08 must prove AC-M2-06 for room IDs, including a generator that returns an existing room ID and one that repeats. Ticket to WI-M2-08. | Open (ticket) |
| F3 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Guard/CalmWordsGuard.swift:59` | Linking runs before the guard (E5, correct for user labels). But a proposed name that the guard reduces to an existing room's folded name (for example "late kitchen" → `proposed("kitchen")` while the household has "Kitchen") stays `proposed` in the draft. Commit maps it to the existing room (Ruling 2b), so no duplicate room is created. Still, the draft that M3's review UI shows would say "new room" for a room that exists. | No change needed in WI-M2-04. WI-M2-05 should decide (PO or Designer if it affects UI) whether to re-link the calmed name after step 7, so the draft says `existing`. Note it in WI-M2-05's dev notes. | Open (note for WI-M2-05) |
| F4 | Nit | `Packages/TendIngestion/Tests/TendIngestionTests/CalmWordsGuardTests.swift:208-217` | The property test's oracle (`BannedTokens.tokens`) is the production matcher, not an independent oracle (plan rule "Independent oracles … never by calling production helpers"). The parameterised cases have hand-written expected values, so AC-M2-12 is still proven. The property only shows consistency. The property always passes `sourcePhrase: input`, so the unverified-phrase path is not sampled. The seed prints in decimal (`910077177129600018`), while dev-notes cite hex. | Optional: a small hand-rolled whole-token oracle (lowercased, ASCII-folded) and a share of cases with an unrelated `sourcePhrase`. Print the seed in hex. | Open (optional) |
| F5 | Nit | `docs/milestones/M2/dev-notes.md` (WI-M2-04 "Test runs") | The dev notes record 59 tests at `a402372`. The merged head `a4f43b7` runs 79 (WI-M2-03 added 20). | Optional: add the merged-head count, or let the Documenter note it. | Open (optional) |

No Blocker. No Major.

### Points checked and found sound (no finding)
- **E1 exemption narrowness.** It applies only to the exact path and needs one anchor in lexed code (comments and
  literals are blanked, so an anchor in a comment or string does not count). The span runs from the anchor to the
  first `]`. Only whole-literal hits are exempted, once per token. The real scan also asserts that exactly the nine
  were exempted and that `BannedTokens.all == SourceScanner.bannedTokens`, so a substitution inside the span is caught.
  Negative tests cover the other paths, the rest of the file, repeats, the identifier form, a renamed or doubled
  anchor, and a single-line declaration. On the merged tree the scan now also covers the WI-M2-03 files: 10 files, 9
  exempted, 0 violations.
- **Removal cannot create a new banned token.** Tokens are maximal letter runs, so the text on each side of a removed
  run is a non-letter, and joining them makes no letters. The 2,000-case property confirms it.
- **`sourcePhrase` check.** Both sides are folded as the brief says (the leading article is stripped on both sides,
  T-09). The match is a hand-written `Character` substring (R-10), and an empty fold gives nil. The off-by-one mutant
  is killed.
- **Q5 order.** A blank title never reaches the guard, because Q5 step 1 skips it. `apply`'s fallback on an
  originally blank title can only happen through a direct call, so it is harmless.
- **Names.** `CalmWordsSkipReason.noTitleWordsLeft`, `CalmWordsDecision.keep/skip`, `RoomCommitPlan`, `DraftRoom`:
  none holds a banned token, none uses the M1 design-forbidden list, and none blames the user (T-18).
- **Swift 6.** Value types and caseless enums only, all `Sendable`. No `@unchecked`, no `nonisolated(unsafe)`, no
  tasks. No force unwraps or `try!` in Sources.
- **Performance.** `lowestRoom` folds every room name on each call, O(rooms) per draft, with households of tens of
  rooms. `SourcePhrase` is O(n·m) over one utterance. Both are fine.

## Test runs (Reviewer, this run)
Environment: Linux container, `docker run swift:6.2-noble`, **Swift 6.2.4 (swift-6.2.4-RELEASE)**, worktree at
`a4f43b7`. These are the commands of `.github/workflows/ci.yml` jobs "TendCore swift test (Linux)" and "TendIngestion
swift test (Linux)", plus plan "Exact commands":

| Command | Result |
|---|---|
| `swift build --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `Build complete!` |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 130.425 seconds.` |
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 3.532 seconds.` |
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!` |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 79 tests in 8 suites passed after 6.302 seconds.` Log lines: `AC-M2-12 vocabulary scan: 10 files, 9 exempted (the list), 0 violations`; `AC-M2-09 scan: 10 files in total, 0 violations`; `AC-M2-12 property: seed 910077177129600018, 2000 cases, 1448 titles changed by the guard` |

0 failures, 0 skipped, 0 warnings (no `warning:` line in any log). `Tools/TendTools` does not exist yet, so the CI step
is a no-op. Not verified on Darwin Foundation (R-10, plan B2 / MS-2).

### Reviewer mutation run (each applied alone, run, then restored; `git status` clean afterwards)
| Mutant | Result |
|---|---|
| `trimEnds` without the trailing trim | killed (6 issues) |
| Symbols treated as trimmable punctuation | killed (44 issues) |
| Fallback `sourcePhrase` not collapsed | killed (`fallbackTitleIsTidied`) |
| Proposed-room guard ignores the input | killed (`proposedRoomNameUserWordsKept`, `linkThenGuard`) |
| `sourcePhrase` needle not name-folded (`lowercased()` only) | killed (7 issues) |
| `sourcePhrase` loop off by one (last start position skipped) | killed (`kept`, `bothSidesFolded`) |
| Commit groups by raw name, not folded name | killed (`oneRoomForEqualProposals`) |
| Proposed name not collapsed at link | killed (`proposedKeepsText`) |
| Link tie uses `.first` instead of the lowest `uuidString` | killed (`tieGoesToLowestUUIDString`) |
| Tidy-up also when nothing is removed | killed (`unchangedWithoutRemoval`) |
| Commit match to an existing room ignores the tie rule (`rooms.last(where:)`) | **survived** → F1 |

The Developer's own 22-mutant table (dev-notes) does not overlap with these, apart from the link tie.

## Open product questions (from dev-notes), now ruled
- E4 (fallback title): PO Ruling 1 ACCEPT. The code matches (`CalmWordsGuard.swift:50-54`).
- E6 (commit: first confirmed draft names the room; a proposal equal to an existing room uses it; a missing room gives
  `none`): PO Ruling 2 ACCEPT. The code matches. The commit-order clarification (2a) is for WI-M2-05/06. Tie branch
  untested: F1.
- E2/E3 (whole-token input set; P* punctuation; tidy only after a removal): PO Ruling 3 ACCEPT. The code matches.
- The PO asks for three DECISIONS.md entries in the next human-merged governance PR. That is not a gate on this PR.
- None of the code's choices conflicts with the brief or plan text.

## Checklist
- [x] Correctness vs ACs (AC-M2-04, AC-M2-12; Q5 step 8)  - [x] Tests meaningful (10/11 reviewer mutants killed; F1)
- [x] Swift 6 concurrency safe  - [x] No force unwraps / try! in product code paths  - [x] Privacy (P-1…P-4)
- [x] UX-2/UX-3 enforced in engine (UX-3 guard in `TendIngestion`; no UX-2 surface)  - [ ] Accessibility (UI): n.a., no UI
- [x] Performance (no hot loops of concern)  - [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection or "what to do now" API. The draft stream is a capture review (Q11). |
| UX-3 Zero-Guilt | pass | Every banned token the user did not say is removed from titles, fallback titles and proposed room names (AC-M2-12; parameterised tests + 2,000-case property). The skip reason `noTitleWordsLeft` is calm. The vocabulary scan keeps all module identifiers and literals calm, with one fail-closed exemption. No overdue state, counter or lateness field. |
| UX-4 Design craft | n.a. | No UI. F3 may affect the M3 review copy and is noted for WI-M2-05. |
| P-1 On-device inference | n.a. | No inference. |
| P-2 No data leaves device (except user iCloud) | pass | Pure functions. AC-M2-09 scan: 0 violations over 10 files. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path. |
| P-4 Media not persisted without consent | pass | No write or log API. Parsing creates no room; the commit plan is a value applied by the caller. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Reviewer | accepted | PR #19 at `a402372`. Later update: merged head `a4f43b7` and PO rulings `po-m2-wi04.md`. |
| 2026-11-21 | Reviewer | Orchestrator → Merge Gatekeeper / Developer | sent | APPROVE. 0 Blocker, 0 Major, 3 Minor (F1, F2 → WI-M2-08 ticket; F3 → WI-M2-05 note), 2 Nit. Report not committed (as instructed). |
