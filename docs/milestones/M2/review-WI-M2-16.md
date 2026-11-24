# M2 Code Review — WI-M2-16: eval fixtures, Tester docs and the Linux composition check (PR #34, `m2/eval-fixtures-freeze`, head `1184436`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** AC-M2-14 (fixtures meet rubric Q3 and the eval scoring rules; composition check on Linux; SHA-256
  manifest and freeze; Tester re-score), FR-A1, FR-B2, UX-3, P-3 (N-3); feeds AC-M2-11, 15, 16, 17, 25, 26, 27, 28.
- **Binding inputs checked:** `CLAUDE.md`; brief AC-M2-14, rubric Q3, "Eval scoring rules", "Device-run rules"; plan
  WI-M2-16 row, "Eval harness ID generator" (version-4 fixture UUIDs); `po-m2-wi16.md` rulings 1–10 and follow-ups
  F1–F4; `eval-composition.md` (v3); `acceptance.md` (v2); dev-notes "WI-M2-16 (Developer part 2)".
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. WI-M2-16 is M2 work. Allowed. No protected path is
  touched: the PR diff against `origin/main` (`368bb9e`) has only `Fixtures/M2/eval/{inputs,household,golden}.json`,
  three test files under `Packages/TendIngestion/Tests/TendIngestionTests/`, and `docs/milestones/M2/` files.
- **Commits under review:** Tester commits up to `45940a8` (fixtures, `eval-composition.md`, `acceptance.md`, re-score
  evidence); `8c0913b` merge of `origin/main` (PR #32); `1184436` Developer tests + dev-notes.
- **Not in scope / not claimed:** AC-M2-14 is **not** met by this PR. There is no `MANIFEST.sha256`, and the freeze
  waits for L2a (GR-4) and the PO's go. The PR says so honestly (see 3 below). An APPROVE here is a merge decision on
  the code and data. It does not accept AC-M2-14 or any device AC.

## Summary

**1. Builds and tests (my own runs, Linux, Docker `swift:6.2-noble`, Swift 6.2.4, `-warnings-as-errors`, my scratch paths).**
- `swift test --scratch-path /tmp/rev34-ing --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors`:
  exit 0, `Test run with 556 tests in 66 suites passed`, 0 `warning:` lines, 0 `✘`. There is exactly one skip:
  `➜ Test "AC-M2-14: MANIFEST.sha256 verifies against every file in Fixtures/M2/eval" skipped: "not frozen yet: no
  MANIFEST.sha256 (waits for L2a, PO ruling 1)"`. This matches the dev notes (556, 1 skipped by design).
- `swift test --scratch-path /tmp/rev34-tools --package-path Tools/TendTools -Xswiftc -warnings-as-errors`: exit 0,
  `Test run with 8 tests in 1 suite passed`.
- No dependency. No `Package.swift` and no `Sources/` file changed (`git diff origin/main HEAD -- '**/Package.swift'
  Packages/TendIngestion/Sources` is empty). The SHA-256 is test-only code, so `TendIngestion` stays Foundation-only.

**2. The composition check uses the project's own code on the real fixtures.** `EvalCompositionCheck.violations`
reads the three committed files through the WI-M2-15 reader (`EvalFixtures`). It calls the real
`DuplicateShortlist.entries`, `LocalWordMatch.target(title:room:in:)`, `EvalScorer.targets` / `bestTarget` /
`draftText` / `satisfies`, `Keywords`, `BannedTokens` and `TextFolding`. It does not re-implement any of them.
`EvalScorer.targets` drops completed seeded tasks and `bestTarget` breaks ties golden-first, as the brief says. So F5
("distinguishable targets") is the brief's rule exactly. Each Q3 line (C1–C12) is checked twice: against the Q3
threshold (`.rule`) and against the value the Tester tabled for PO approval (`.pin`). Composition tags are checked
against the data (`.tag`). F1–F9 cover fixed IDs (version 4 + RFC variant), N-3, banned tokens, keyword-folded match
groups, reference phrases, shortlist reachability and the word-match floor, existing-item field equality, named rooms
(ruling 2), and effort/weather/deep-clean words (rulings 5, 9).
- **Negative controls are meaningful.** There are 63 controls, each an in-memory mutation re-written canonically.
  Most also match a `detail` substring, so a control cannot pass on an unrelated violation of the same rule. An
  identity round trip passes, which proves the mutation writer adds no violation of its own. "Every rule has a
  control" is asserted. The digit-run and whole-token readings have their own tests.
- **My own mutants** (on a scratch copy of the worktree, never on the worktree; filtered run of `EvalCompositionTests`
  and `EvalFreezeTests`, 18 tests):

  | Mutant | Caught by the composition check? | Also by the PO hash pin? |
  |---|---|---|
  | `g16-carservice.isWeatherDependent` false → true (golden flag) | yes: C5 pin, C6 pin, F9 | yes |
  | `g08-card.isCritical` false → true | yes: C7 pin | yes |
  | `t-kettle` ID `…-4000-…` → `…-5000-…` (version nibble) | yes: F1 `not a version-4 RFC UUID` | yes |
  | `g12-door` room garage → hallway (not named in in12) | yes: F8 `room Hallway is not named in in12` | yes |
  | `g05-oven` room kitchen → bathroom (bathroom named in in05) | yes: F7 `golden fields differ from t-oven` | yes |
  | `g18-counters` room kitchen → none | **no** (see N1) | yes |
  | `g16-carservice` effort normal → low | **no** (not machine-checked, the dev notes say so) | yes |

  Every mutant fails the suite. Five are caught by a named composition rule. Two are caught only by the PO-approved
  hash pins (`approvedHashes`: household.json and golden.json both failed). The pins are a real backstop: any byte
  change fails and goes back to the PO (ruling 1).

**3. The skipped manifest test is honest.** `committedManifestVerifies` is gated by `.enabled(if: manifestExists)` and
is reported as skipped with its reason, never as a pass. Separately, `freezeStateAgrees` **runs and passes now**. It
asserts that `MANIFEST.sha256` exists exactly when `EvalFreeze.declaredFrozen` is true, and that the Tester's
`eval-composition.md` Status bullet says "Not frozen" exactly when the eval is not frozen. So:
- adding a manifest without flipping the flag fails;
- flipping the flag without a manifest fails;
- a Status bullet that disagrees fails.

The verifier itself is tested now on in-memory renders: 7 broken-manifest controls plus a changed-file control. The
documented command is executed (`sha256sum`, stdout only) and compared byte for byte with the render. Nothing is
hidden.

**4. The hand-written SHA-256 is correct.** I checked the four FIPS 180-4 vectors in `sha256Vectors` against the
standard: empty `e3b0c442…b855`, "abc" `ba7816bf…15ad`, 448-bit `248d6a61…06c1`, and 10⁶ × "a" `cdc76e5c…2cd0`
(multi-block). As an independent cross-check, `sha256sum` on the committed files gives `b32e45af…ebcec` (inputs),
`089a22bd…17f66` (household) and `882c2906…80d4dc` (golden). These equal the PO ruling 1 approvals and the test's
pins, and the Swift helper agrees with them (`approvedHashes` passes). The padding, the big-endian length and the
round function read correctly.

**5. Fixtures.** I checked them with my own Python (`-I`), not the project code:
- 0 banned tokens (overdue, late, missed, failed, behind, penalty, debt, streak, lateness) as whole tokens in any file;
- 0 digit runs holding 600…729 (N-3);
- all 28 room/task IDs are version 4 with the RFC variant, and all are unique;
- every `referencePhrase` is a substring of its input;
- N = 58.

The capitalised words in the inputs are only weekdays and sentence starts. There are no names, addresses or real
personal data ("the kids" and "our bedroom" are generic).

Spot check of 18 golden items against PO rulings 2, 3, 5, 7, 8 and 9:
- **Critical** (ruling 3): `g02-electric`, `g08-water`, `g18-tax` are bills or tax; `g05-chicken`, `g11-yogurt`,
  `g18-soup` are food that will expire; `g08-insurance` is a dated renewal (equal to the seeded `t-insurance`);
  `g11-smoke` is a home safety check. `g02-dentist`, `g16-carservice`, `g10-heater` and `g20-chimney` are not
  critical. Correct.
- **Room** (ruling 2): `g02-sink`, `g05-chicken`, `g12-door`, `g16-radiators`, `g17-toys`, `g19-floor` each name
  their room. Restocks, bills and bookings are `none`. `g13-clothes` is `none`, since no room is named. The new rooms
  Balcony, Patio, Shed and Porch are named and not in the household. Correct. See N3 on `g15-shower`.
- **Effort** (ruling 5): deep cleans are `high`; `g07-shed` (big sort-out) and `g14-fence` (paint/stain) are `high`;
  errands are `low`. See F2 on `g16-carservice`.
- **Weather** (ruling 9): all 12 weather items are tied by the person's own words ("dry", "rain", "sunny", "sun's
  out"). No outdoor chore is inferred.
- **Existing vs create**:
  - `g03-milk` and `g03-bulb` are `create`, because `t-milk` and `t-bulb` are completed (said again means new).
  - `g08-insurance` targets the `resurfaced` task, `g14-fence` the `deferred` one, and `g05-oven` the `maintenance`
    one.
  - `g01-pods`, `g06-pods` and `g17-pods` all target `t-pods`. Ruling 7 is respected: "dishwasher tablets" shares a
    keyword.
  - Repeats inside one input are one item (ruling 8: in03 milk, in06 toilet paper, in12 trash, in18 tax).
- **False-merge traps** are real under the scorer's rule:
  - `g04-trashbags` vs `t-bins`: both satisfied; the golden item wins on overlap 2 vs 1.
  - `g16-carservice` vs `t-car`: the wash group is not satisfied.
  - `g10-heater` vs `t-plants`: only "water" is shared.
  - `g15-plants` vs `t-plants`: the garden group is not satisfied ("sameChoreOtherRoom").
  - `g08-water` vs `t-plants`: only "water" is shared.

  F6 proves that the real word-match floor merges none of them.

**6. Tester scripts DS-1 / DS-2 (acceptance.md).** All seven device ACs (AC-M2-11, 15, 16, 17, 25, 26, 27) are
`AWAITING-DEVICE`, and AC-M2-14 is `OPEN (not frozen)`. No device criterion is marked PASS. The scripts are clear and
numbered, with exact settings paths, word-for-word voice tables that match `inputs.json`, the retake rule, the
no-rerun rule, the PO F3 subsets (in01/in02/in10; in08/in16), the A-F1 manual controls S5/S7, and pass rules with
exact thresholds (56/56/53/50/56/56/56 of 58 = ⌈p × 58⌉). I ran two of the commands:
- DS-2 Part A `swift run … tend-payload-dump … > body.json`: build progress goes to stderr, and stdout is the JSON
  body only. Fine.
- DS-1 S1 `sha256sum -c Fixtures/M2/eval/MANIFEST.sha256` from the repo root fails. See F1.

**7. The merge of main (`8c0913b`) adds nothing.** `git merge-tree --write-tree 45940a8 368bb9e` gives tree `044111a…`,
which is identical to `8c0913b^{tree}`. It is a clean automatic merge with no hand edits. `git diff 368bb9e 8c0913b`
contains only the branch's own Tester files. `origin/main` is still `368bb9e`.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | Minor | `docs/milestones/M2/acceptance.md:239` (DS-1 S1; DS-2 S1 at :370 says "As DS-1 S1") | `sha256sum -c Fixtures/M2/eval/MANIFEST.sha256` run "from the repo root" cannot work. The manifest lists bare names (`golden.json …`, `EvalManifest.command` runs inside the directory), so `sha256sum -c` looks in the current directory and fails. I reproduced it on a scratch copy: from the parent directory `FAILED open or read` ×4, exit 1; from `Fixtures/M2/eval`, 4 × `OK`, exit 0. It fails safe (no false PASS), hence Minor. It would still stop the Tester's scoring step. | Tester: change S1 to `(cd Fixtures/M2/eval && sha256sum -c MANIFEST.sha256)`, keeping `H=$(sha256sum Fixtures/M2/eval/MANIFEST.sha256 \| cut -d' ' -f1)` as is (that line is correct from the root). Doc-only; the Tester may fix it with the freeze commit. | OPEN |
| F2 | Minor (question for Tester/PO, before the freeze) | `Fixtures/M2/eval/golden.json` item `g16-carservice` (`effort: normal`) | The Tester's rule 9 (`eval-composition.md:120`, ruling 5) names "book" as `low`. The sibling bookings `g02-dentist`, `g14-cleaner` and `g20-chimney` are `low`, but "book the car in for a service" is `normal`. One reading is defensible: the item is the service, not the booking, as with `g01-ac` and `g10-heater` at `normal`. But the labels are not consistent with the rule as written. It is 1 of 58 against an 85% effort gate, so the gate stays passable. It is still a label a correct model could lose on, and the composition check cannot see effort on create items (my mutant). | Tester: confirm the reading, or relabel `low` and take it back to the PO under ruling 1 **before** the freeze (afterwards it needs a DECISIONS.md entry). If kept, add one sentence to rule 9 saying that "book X for a service" is scored on the service. No code change. | OPEN |
| N1 | Nit | `EvalCompositionSupport.swift:480-503` (F8) | F8 checks one direction only. `existing(room)` must be named, but a create item whose `referencePhrase` names a household room can be labelled `none` and still pass (mutant `g18-counters` → none passed every composition rule; only the hash pin caught it). This matches the Tester's rule 8 as written, so it is not a defect. | Optional: add the converse for `create` items (room named **in the item's own `referencePhrase`** ⇒ expected `existing(that room)`). It holds today for every item I checked. | OPEN (optional) |
| N2 | Nit | `EvalCompositionSupport.swift:619-624` | `listedNames` says "every regular file" but filters only dot-files and the manifest, so a sub-directory would be listed and `Data(contentsOf:)` would throw. No sub-directory exists today. | Optional: filter to regular files, or fix the comment. | OPEN (optional) |
| N3 | Nit | `golden.json` `g15-shower` (room `existing(bathroom)`) | "Bathroom" is named in in15 for the other two chores, not in the shower clause. It meets rule 8 (input-level) and ruling 2 ("clearly sits in"), so I am not asking for a change. It is the one golden room that relies on inference within the input. | None. The Tester may note it next to the M3 unnamed-room dev-set watch item. | OPEN (info) |
| N4 | Nit | `acceptance.md:175` (DS-1 P10) | "[Operator]: type your name or initials". The results files are committed to the repository. | Tester: say "initials" only. | OPEN |

No Blocker. No Major.

## Checklist
- [x] Correctness vs ACs: AC-M2-14 composition clause and the Linux check are implemented and pass on the real files.
      The manifest and freeze are honestly not done yet (L2a). The re-score clause has evidence (`acceptance.md`
      "independent re-score").
- [x] Tests meaningful (would fail if code broke): 63 controls, an identity round trip, 7 of my own mutants all fail
      the suite, FIPS vectors, and the hash pins cross-checked with `sha256sum`.
- [x] Swift 6 concurrency safe: test-only code; `@Sendable` mutation closures; no `@unchecked`, no
      `nonisolated(unsafe)`.
- [x] No force unwraps / try! in product code paths: no product code changed.
- [x] Privacy (P-1…P-4): invented fixtures, no personal data, N-3 clean; `Process` runs local `sha256sum` only, in tests.
- [x] UX-2/UX-3 enforced in engine: UX-2 n.a.; UX-3 F3 refuses any banned whole token in the fixtures.
- [x] Accessibility (UI): n.a.
- [x] Performance: n.a. (the suite adds ~4 s on Linux).
- [x] No new dependency without ADR: none added.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Inputs are free brain-dumps (FR-A1), spoken or handed over verbatim; TendEval controls are a debug harness (AC-M2-28). |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | 0 banned tokens in the fixtures (F3, and my own regex); the critical labels mean "waiting has a real cost" (ruling 3), with no alarm copy; the script copy uses no banned word. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | DS-1 runs with cloud off and AC-M2-11 in airplane mode; DS-2 proves an on-device transcript offline (AC-M2-25). |
| P-2 No data leaves device (except user iCloud) | pass | No dependency; invented data; the tests run only local `sha256sum`; results move by AirDrop to the owner's Mac. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | N-3 holds on every fixture byte (F2); every shortlist ≤ 6 titles (F6); the DS-2 key handling is a hidden prompt, the key is removed after each provider, and Part A sends only the fixed sample. L2a (GR-4) is still required before the freeze. |
| P-4 Media not persisted without consent | n.a. | Text only; no audio stored (device-run rules). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | PR #34 `m2/eval-fixtures-freeze` @ `1184436`; worktree `/home/user/wt-rev34`. |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper, Acceptance Tester, PO | sent (round 1: APPROVE) | 0 Blocker, 0 Major. F1 (Tester, DS-1 S1 command), F2 (Tester/PO, `g16-carservice` effort, before the freeze), N1–N4 optional. AC-M2-14 stays OPEN until L2a, the manifest and the freeze. Not committed or pushed by the Reviewer. |
