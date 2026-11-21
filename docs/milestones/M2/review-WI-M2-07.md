# M2 Code Review — WI-M2-07, PR #21 (`m2/duplicate-rules`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1 (head `8d463da`)
- **Requirements:** FR-A1, Q7, Q12, T-06, UX-3. ACs: the **Linux half of AC-M2-07** (shortlist, neutral lookup,
  in-input collapse, cloud re-check under Q12 = yes, local word-match under Q12 = no) and the **marking half of
  AC-M2-08** (plan WI-M2-07, both ○). Related: AC-M2-06 (commit re-check, WI-M2-08), AC-M2-20 (Q12 = yes titles,
  WI-M2-10), AC-M2-24 (cloud scope), AC-M2-26 (device duplicate threshold), AC-M2-09 / AC-M2-12 (scans, regression).
- **Commits reviewed:** `e9664ea` (code and tests), `8d463da` (dev notes). Diff `origin/main...HEAD` (base `2f9f86f`).
  It touches only `Packages/TendIngestion/Sources/TendIngestion/Duplicates/**`, four new test files and
  `docs/milestones/M2/dev-notes.md`. No protected path, no dependency, no change to `TendCore` or `TendSourceScan`.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. WI-M2-07 is M2 work. DoR met (WI-M2-01 and
  WI-M2-05 merged at `2f9f86f`).
- **Inputs:** CLAUDE.md; brief.md (Definitions: Name folding, Keywords of a text, Duplicate shortlist, Local duplicate
  re-check for cloud drafts, Duplicate; AC-M2-06, 07, 08, 09, 12, 20, 24, 26; Q7, Q12, T-06); plan.md (WI-M2-07,
  WI-M2-08, WI-M2-M2 rows and the WI-M2-07 note); design.md (no UI in this item); dev-notes.md (WI-M2-07). PO notes:
  `po-q21-q22.md`, `po-m2-wi04.md` (rulings 2b, 2c), `po-m2-wi05.md` (ruling 1, the "proposed room never equals an
  existing room" invariant), `owner-decisions.md` (Q12 open, PO default yes), and **`po-m2-wi07.md` (PO rulings on
  this PR, received during the review)**.

## Summary
The PR adds pure, Foundation + TendCore value types and functions for the duplicate rules: `DuplicateShortlist`
(steps 1–6, cap 10), `DuplicateLookup` + `DuplicateLookupLog` (the neutral function the on-device `Tool` will wrap,
title / kind / room name only, no ID), `LocalWordMatch` (the Q12 = no rule), `DuplicateMarker` (per-draft marking in
output order with the in-input collapse) and `DuplicateRecheck.atCommit`. The code is small, readable and matches the
brief's Definitions line by line. The tests are strong: hand-written cases for every ranking step and every word-match
condition, plus a 600-household oracle property for AC-M2-07 and a 600-household × 3-path marking property for
AC-M2-08. The oracle is genuinely independent (no production call; its own fold, split, stop-word list, byte compare,
selection ranking and brute-force word-match). My own mutants confirm the tests bite: 7 of 8 killed (see below).

The one blocking item is the PO's **ruling 1 on this PR** (`po-m2-wi07.md`): a **word-match floor** is now required
on every path. As built, the on-device and Q12 = yes paths never fall back to the word-match (dev-notes D4), so an
exact repeat that the model did not validly claim (for example, a task ranked 11th or lower on the capture's
shortlist: 56 of 816 exact plants in the developer's own property) is created again. That breaks the PRD gate
"zero duplicate creation" (FR-A1) and the amended AC-M2-07 / AC-M2-08 text. This is R21-F1 (Major).

On the five decisions I was asked to check:
1. **D1, title claims on device:** sound. Only titles a Tool lookup returned in this parse are accepted; unknown
   titles are ignored. The first match in call order then rank order is deterministic; two entries with the same
   folded title are the same chore (PO ruling 3). After R21-F1 an ignored title falls through to the floor.
2. **D2, in-input repeat to the first draft:** literal AC-M2-07 ("collapses into its first draft"). The chain is
   flattened at mark time (one lookup is enough, because every stored `ofDraft` already names a root), and a claim to
   a skipped, own or later position is ignored. Tested by hand and by the property; my mutant C is killed.
3. **D3, valid in-input claim wins over an existing-task claim:** accepted by the PO (ruling 3). It also keeps the
   repeat out if the existing target disappears by commit. Not a defect.
4. **D5, a room ID that matches no room is "no room":** consistent with PO WI-M2-04 ruling 2c and accepted (ruling 3).
   Applied the same way in the shortlist and the word-match, and in the oracle; my mutant A is killed.
5. **Whole-capture shortlist, cap 10, under Q12 = yes:** this **is** the literal brief (Definitions, "Two callers use
   it ... The cloud payload, when Q12 is yes: Q is the capture text"; "Keep at most the first 10"). The developer built
   it literally and raised the risk correctly as open question 1. The PO kept the query and the cap (ADR-0005
   Decision 3, P-2, P-3) and closed the risk with the floor (R21-F1). No change to the shortlist itself.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R21-F1 | **Major** | `Sources/TendIngestion/Duplicates/DuplicateMarker.swift:30-37` (`ExistingTaskCheck` cases carry no household on two paths), `:87-97` (`duplicate(for:)`: no word-match after a missing or invalid model claim on device and under Q12 = yes); `Tests/TendIngestionTests/DuplicateOracle.swift:216-234`; `Tests/TendIngestionTests/DuplicatePropertyTests.swift:381-383`; `docs/milestones/M2/dev-notes.md` D3, D4, the AC-M2-08 marking table, open question 1 | **PO ruling 1 (`po-m2-wi07.md`, FR-A1 "zero duplicate creation", amended AC-M2-07 / AC-M2-08).** A draft with no valid in-input claim and no valid existing-task claim is left `none` on device and under Q12 = yes, even when it is an exact repeat of a live task in a compatible room. Commit then creates the duplicate. The developer's own property shows it: under Q12 = yes, 56 of 816 exact-title plants are outside the capture's 10 and are created again; on device, 3 more. Dev-notes D4 ("the on-device path never falls back to the word-match", mutant M6 "killed") is now the wrong behaviour. | Per the PO ruling, items 1–4: (1) after the in-input claim and the model's existing-task claim, fall back to `LocalWordMatch.target` over the whole local household on the on-device and Q12 = yes paths too (the household must reach those cases, e.g. `.toolLookups(log, household)` / `.sentShortlist(entries, household)`; shape is yours). Precedence: in-input → model existing claim → floor → `none`. Under Q12 = no nothing changes. (2) M6 becomes expected; add and show killed the reverse mutants "no floor on device", "no floor under Q12 = yes" and "floor before the model claim". (3) Give the independent oracle the same precedence. In the AC-M2-08 marking property, **assert** that every planted exact-title duplicate whose room is compatible under the word-match rule is marked on every path, inside or outside the 10; keep counting non-visible synonym plants. Add hand-written cases: an exact repeat ranked 11th under Q12 = yes → marked by the floor; a model index claim and the floor disagree → the model claim wins; an unseen Tool title claim → the floor decides. (4) Update dev-notes D3, D4, the marking table, open question 1 and the mutation table. | Open |
| R21-F2 | Minor | `Sources/TendIngestion/Duplicates/DuplicateShortlist.swift:73` | The entry title is trimmed with `.whitespacesAndNewlines` (D7), but no test has a title with a leading or trailing newline or tab. My mutant G (`.whitespaces` only) **survived** every test. This title is what WI-M2-10 sends under Q12 = yes, so it feeds the AC-M2-20 golden bytes and the shortlist-path values. | Add a hand-written shortlist case with a title such as `"\n\tBuy dish pods \n"` whose expected entry title is `"Buy dish pods"` (and, optionally, let the generator wrap some titles in `\n` / `\t`). Show mutant G killed. | Open (ticket; does not block) |
| R21-F3 | Minor | `Tests/TendIngestionTests/DuplicateOracle.swift:45`, `:12-14` | The oracle splits on `Character.isLetter \|\| Character.isNumber`. The brief says "Unicode letter or decimal digit"; `isNumber` also accepts `½`, `²`, `Ⅷ`, which production splits on. The oracle header states it relies on the restricted generator alphabet, which is true and disclosed, so the property is valid as run. But the oracle is not a faithful transcription of the rule outside that alphabet, and a future generator change would silently make it disagree. | Either make the oracle use the decimal-digit rule (`Character.isWholeNumber` is also too wide; check `unicodeScalars` against `Nd`), or keep it and add one hand-written keyword case with `½` / `²` in a shortlist query so the production split is pinned independently. | Open (ticket; does not block) |
| R21-F4 | Nit | `Sources/TendIngestion/Duplicates/LocalWordMatch.swift:58-64` | D5 treats a dangling task `roomID` as "no room", but a draft `.existing(id)` whose `id` is not a household room is still treated as a room (compatible only with tasks without a room). Unreachable at parse time, because the mapper links only to injected rooms, and commit maps a gone room to `none` (PO WI-M2-04 2c). | Optional: treat the draft side the same way for symmetry, or note it in the doc comment. | Open (optional) |
| R21-F5 | Nit | `Tests/TendIngestionTests/DuplicatePropertyTests.swift:254`, `:286` | `for position in 1...rnd.int(4...14)` binds a variable that is then discarded with `_ = position`. | Optional: `for _ in`. | Open (optional) |

No Blocker. One Major (R21-F1), required by the PO ruling.

### Notes for later items (not findings on this PR)
- **WI-M2-08:** PO ruling 2 — a confirmed `ofDraft(k)` is never created, whatever happened to draft k. `createsTask`
  is already `false` for `ofDraft`; WI-M2-08 must test k confirmed / dismissed / unconfirmed. The commit half of
  AC-M2-08 (no ID repeated, no committed duplicate) is WI-M2-08's.
- **WI-M2-06:** call `mark` once per position in output order, before `emitted`; mutant M2 (`k <= position`) is
  equivalent only under that one-call-per-position contract, so WI-M2-06 should keep it (a second `mark` for one
  position would overwrite `marked[position]`).
- **WI-M2-M2:** the `Tool` keeps the `DuplicateLookupLog` behind its own isolation and hands copies to the marker;
  index-vs-title claims is a technical choice for the Planner / WI-M2-M2 (PO ruling 3).
- **PO watch item (ruling "Open / watch"):** the floor covers existing tasks only; a model that fails to flag an
  in-input repeat at all is not covered. Eval before the AC-M2-14 freeze.

## Tests and evidence
All runs in `swift:6.2-noble` (Swift 6.2), the CI commands from `.github/workflows/ci.yml` with
`-Xswiftc -warnings-as-errors` and `--scratch-path /tmp/rev21-<pkg>`, worktree mounted read-only at `8d463da`:

| Package | Result |
|---|---|
| TendCore | `Build complete!`; `✔ Test run with 141 tests in 18 suites passed after 82.347 seconds.` 0 warnings |
| TendSourceScan | `Build complete!`; `✔ Test run with 63 tests in 4 suites passed after 2.113 seconds.` |
| TendIngestion | `Build complete!`; `✔ Test run with 150 tests in 18 suites passed after 20.093 seconds.` 0 warnings |
| Tools/TendTools | not present at this head (the CI step exits 0) |

Property logs (reproduced): AC-M2-07 seeds `0xD0B1E5EED000701/02/03`, 2,800 queries each (7,474 / 8,732 / 8,105
entries), **0 shortlist mismatches, 0 word-match mismatches**; neighbours decided at K 758/847/794, R 179/226/217,
title 4,355/5,475/5,020, uuid 708/681/638, offset 0; > 10 eligible 214/267/260; room-only, completed-left-out,
stop-word-only and all eight word-match classes present on every seed. AC-M2-08 seeds `…0801/02/03`: 0 oracle
mismatches on all three paths. Under Q12 = yes, exact plants visible / planted were 253/273, 240/256 and 267/287: the
non-visible ones are exactly the gap R21-F1 closes.

**Coverage claims checked.** "Ties at every ranking step" is shown correctly: a neighbour pair decided at R means K
tied, at title means K and R tied, at uuid means K, R and the folded title tied, and each is required > 0 per seed.
The other brief cases (> 10 eligible, completed left out, room-only, stop-word-only with an asserted empty shortlist)
are each required per seed. Sample sizes and seeds are fixed and printed; every failure message carries the seed.

**Oracle independence checked.** `DuplicateOracle.swift` calls no `Keywords`, `TextFolding`, `DuplicateShortlist`,
`LocalWordMatch`, `DuplicateLookup` or `DuplicateMarker` code (grep: no match); it only uses the public value types.
My mutant B (drop "need" from the production stop-word list) is killed by 559 failures, which proves the oracle does
not share the production list.

**My own mutants** (applied one at a time to a copy at `/tmp/rev21-mutsrc`, `--filter "Duplicate|LocalWordMatch"`;
the worktree was never modified, `git status` clean):

| Mutant | Result |
|---|---|
| A word-match: dangling task `roomID` counted as a room | killed (8) |
| B production stop words without "need" | killed (559) |
| C in-input claim must be `< position - 1` | killed (596) |
| D shortlist also drops `maintenance` tasks | killed (2,773) |
| E word-match `shared` = task keyword count | killed (12) |
| F title-claim fold strips the article (`foldName`) | killed (3) |
| G entry title trimmed with `.whitespaces` only | **survived** → R21-F2 |
| H word-match only `active` tasks | killed (359) |

## Checklist
- [ ] Correctness vs ACs — AC-M2-07 / AC-M2-08 as amended by PO ruling 1 not yet met (R21-F1). Everything else
  matches the Definitions.
- [x] Tests meaningful (would fail if code broke) — hand-written cases + independent oracle; 7 of 8 reviewer mutants
  killed; R21-F2 for the survivor.
- [x] Swift 6 concurrency safe — value types only, all `Sendable`; no `@unchecked`, no `nonisolated(unsafe)`, no
  tasks, no globals with mutable state.
- [x] No force unwraps / `try!` in product code paths — none in `Sources`; the test fixture's
  `preconditionFailure` fallback is unreachable and test-only.
- [x] Privacy (P-1…P-4) — no I/O, networking or logging (AC-M2-09 scan: 0 violations); `ShortlistEntry.taskID` never
  reaches `DuplicateLookupEntry` (Mirror test).
- [x] UX-2/UX-3 enforced in engine — no "what to do now" surface; no repeat state, count or copy; case names pass
  the AC-M2-12 vocabulary scan.
- [x] Accessibility (UI) — n.a., no UI.
- [x] Performance — O(tasks) per query or draft, keyword sets built per call; fine for thousands of tasks. The floor
  (R21-F1) adds one O(tasks) pass per unmarked draft, which is fine.
- [x] No new dependency without ADR — none.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Duplicates are found without asking the user anything; a marked draft is simply not created (Q7). |
| UX-2 Rule of Three | pass | The shortlist (≤ 10) goes only to the model or the payload, never to a "what to do now" surface; captured tasks reach Now only through `NowSelector`. |
| UX-3 Zero-Guilt | pass | No overdue/repeat state, count or copy; a completed one-off or restock is never a target (tested on all paths). AC-M2-12 vocabulary scan 0 violations. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Pure local logic; the lookup reads only the injected local household. The floor (R21-F1) is local and deterministic. |
| P-2 No data leaves device (except user iCloud) | pass | No networking, I/O or logging; task IDs never leave `ShortlistEntry`. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Q12 = yes uses only the ≤ 10 trimmed titles (ADR-0005 Decision 3); Q12 = no sends no titles. The PO kept the cap and query, so nothing new is sent. |
| P-4 Media not persisted without consent | pass | Nothing persisted; household unchanged (Q7 test). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Reviewer | accepted | PR #21 at `8d463da`; focus on D1, D2, D3, D5, the whole-capture shortlist, oracle independence and coverage claims. |
| 2026-11-21 | Orchestrator | Reviewer | accepted | PO rulings `po-m2-wi07.md` relayed mid-review; ruling 1 recorded as R21-F1. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: R21-F1 (Major, PO ruling 1 word-match floor). Minors R21-F2, F3 and Nits F4, F5 can be fixed in the same round. Re-review will be a new round in this file. |
