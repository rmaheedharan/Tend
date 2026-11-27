# M2 Code Review — PR #41 (`m2/on-device-adapter`, round 1 @ `2515c7c`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **CHANGES REQUIRED**  ·  **Round:** 1
- **Scope:** WI-M2-M2, the on-device adapter (MS-2): the `@Generable` schema, `PartiallyGenerated` → neutral snapshots,
  the availability / `supportsLocale` / generation-error mapping, the duplicate `Tool`, prewarm, GR-9 guide parity, and
  the `TendIngestion` API change `OnDeviceModelSource.model()` → `model(household:)`. Requirements: ● AC-M2-05,
  ● AC-M2-07, ● AC-M2-10 (Mac halves); GR-9 (eval-composition); R-1, R-4; FR-A1; P-1…P-4; UX-3.
  Diff `41bf8fa..2515c7c`: 39 files, +11,333/−31. Code commit `94d02fe` (16 code/test files); `2515c7c` adds the Mac
  evidence record and the dev-notes section.
- **Inputs read:** `CLAUDE.md`; this skill; `plan.md` WI-M2-M2 row, "Applies to every item", MS-2, R-1/R-4; `brief.md`
  AC-M2-05, AC-M2-07, AC-M2-10; `eval-composition.md` GR-9; the dev-notes section "WI-M2-M2"; every new or changed
  source and test file; the evidence record `evidence/mac/WI-M2-M2/` (README, run script, all logs, probes);
  `review-pr38.md` (precedent for evidence privacy).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. An `m2/` build item is allowed (CLAUDE.md §5).
  No protected path is touched.
- **Merge route:** Mac-only PR, so D-032 (the owner merges with a Mac evidence record for the exact head). An APPROVE
  here accepts no AC; AC evidence is taken at the M2 merge commit (WI-M2-M8).

## Summary

The adapter itself is careful work and I found no Blocker and no code Major. The mapping switches list every known
case, with no plain `default`. The Tool returns exactly the shortlist, reduced to title, kind and room. Snapshots show
only finished values, so a partial title or number never reaches the pipeline (UX-3). The GR-9 refactor leaves the
cloud instruction bytes unchanged, which I proved directly. No golden fixture, no eval file and no existing test
expectation changed. All four Linux packages pass on this head, and the one router mutant I could run on Linux was
killed.

The verdict is CHANGES REQUIRED for one reason, **M1**: both commits on the branch carry the owner's local login name
and the Mac's hostname in their author and committer e-mail fields. That is the same class of leak as review PR #38
M1 (Major), and it would become permanent in `main`'s history on merge. Rewriting the identity fixes it and does not
change the tested tree, so no new Mac run is needed (see M1).

### 1. Verification of the evidence record (task checklist)
| Check | Result |
|---|---|
| Record names the code commit | README "Commit tested" and `mac-B0-header.log:2` both say `94d02fe9b87cbc21b0608cc017c598c74f20eac2`. |
| `2515c7c` is docs-only vs `94d02fe` | `git diff --stat 94d02fe 2515c7c`: 23 files, all under `docs/` (dev-notes plus the 22 evidence files). The tested tree is `41dca2d90267e75b1c9613aa33b4e650f7026be0`. |
| SHA-256 lines | `sha256sum -c` on the 21 lines in the README: **21/21 OK**. The folder holds 22 files, those 21 plus the README. |
| Home path, username, hostname in the **tree** | `grep -rniI -e dharanbro -e /Users/ -e Mac-mini` over the whole worktree, and `git grep -niI` at `2515c7c`, find only `review-pr38.md:154`, which is pre-existing review prose about the grep itself. The logs use `$REPO`/`$HOME` tokens; the only machine string is the model ID `Macmini9,1`, which is not personal (same reading as PR #38). The script needs `REPO` set (`: "${REPO:?…}"`). |
| Same in commit **metadata** | **Fails**: see M1. |
| Clean state | `git status --porcelain` was empty before the run (B0) and after it (`mac-B9-after.log`). |
| Warnings-as-errors | The B4 log shows `-warnings-as-errors -swift-version 6` on the compile lines for TendAI's modules. The only `warning:` lines in B4/B5 come from `appintentsmetadataprocessor` and are not compiler warnings. B1/B2 have 0. |
| Results | B1 141/18 suites, B2 572/67, B4 47/6 suites `TEST SUCCEEDED`, B5 2 tests; 0 `✘`, 0 skipped. The iOS 27 error test ran on the macOS 27.2 host (`mac-B4-tendai-macos.log:1127`). |

### 2. Exhaustive mapping, no plain `default` (AC-M2-10)
- `OnDeviceStopMapping.swift:22-29` switches over `SystemLanguageModel.Availability` with no default at all, so the
  enum is frozen there. `supportsLocale` is folded in, and an unavailable model wins over the locale check.
- `UnavailableReason` (`:31-39`), `GenerationError` (`:59-73`, 9 cases), `LanguageModelError` (`:77-88`, 9 cases),
  `LanguageModelSession.Error` (`:92-98`) and `SystemLanguageModel.Error` (`:102-107`) each list every case and end in
  `@unknown default`. A plain `default` appears nowhere. `@unknown default` is what Swift 6 requires for a non-frozen
  SDK enum, and it still warns when a known case is not listed. The B4 build uses `-warnings-as-errors`, so a missing
  case would have failed it. I read this as meeting AC-M2-10's "exhaustive switch with no `default`" (see i2).
- `GeneratedContent.ParsingError` → `unreadableOutput`. Any other error, including a throwing `Tool` (ours never
  throws), → `otherModelError`. A `ModelStopReason` passes through.
- No mapping re-routes. The router test shows the cloud source is never asked (`NoCloud` records an issue if it is).
  This holds P-1.
- Tests: `OnDeviceStopMappingTests` covers every case of each family, both through the typed overload and through
  `any Error`. On a runtime without iOS 27, the `#available` guard returns early and the test passes. That is honest:
  the family does not exist there. The B4 host is macOS 27, so that test ran its assertions.

### 3. The Tool returns exactly the shortlist (AC-M2-07)
- `DuplicateLookupTool.call` returns `result(await recorder.lookUp(query))` (`DuplicateLookupTool.swift:63-72`), which
  maps each `DuplicateLookupEntry` field for field to `{title, kind, room?}`. `DuplicateLookupRecorder` wraps the
  WI-M2-07 `DuplicateLookupLog` over the capture's own `Household` value. It is an actor, so the Tool is `Sendable`
  with no lock and no `@unchecked`.
- The tests check count, order and every field against `DuplicateLookup.entries` for 8 queries: more than 10 eligible,
  completed tasks left out, room-only, stop-word-only, empty, mixed case. They also check the 10 cap, the field set by
  `Mirror` and by the encoded `GenerationSchema` (`title`, `kind`, `room` only), the argument schema (`query` only),
  and that the result does not change when only the household differs (Q7). The independent oracle for the shortlist
  itself is the Linux suite (WI-M2-07, ≥ 500 seeded households), which passes here (§6). The Mac half rightly checks
  the conformance against the production shortlist.
- The router now hands the capture's household to the source (`ModelRouter.swift:138`), so the Tool reads the same
  value that `DraftDuplicateRules.onDevice(household:)` reads (contract item 4). **Mutant (mine, Linux):** passing an
  empty household at `:138` makes `RouteWiringTests` "WI-M2-M2: the on-device model is asked for with the capture's
  own household" fail. Killed.

### 4. `PartiallyGenerated` snapshots are neutral (AC-M2-05, UX-3, R-4)
- `OnDeviceSnapshotMapping.item` (`:62-88`) shows a property only when one of three things is true: a later property
  of the same item has started, the item is not the last one (rule b), or the stream finished normally (`isFinal`,
  rule c). The last property is a `Bool`, which a snapshot cannot show half-written, so rule (a) can fire only when
  every field is whole. This removes, at the adapter, the J2 hazards the pipeline would otherwise see: the blank first
  title step, and the "Late" prefix of "Later" meeting the calm-words guard.
- The tests build the framework's own `PartiallyGenerated` from JSON prefixes (`GeneratedContent(json:)`). They check
  that "Buy di" and "Late" never appear, that the "1" of "12" never appears, rules a/b/c, and monotonicity over every
  prefix at steps 1, 2, 3 and 7. The end-to-end tests through the real `DraftPipeline` give exactly one `emitted`
  with the whole title "Later: call the plumber", with no skip and no update. The dev-notes list 12 mutants, all
  killed. The schema test pins the generation order and that `isWeatherDependent` is last and boolean. If an SDK ever
  breaks the declaration-order assumption, these tests fail rather than pass.
- One edge case, a framework `CancellationError` while the parse is not cancelled, is mis-classified (m1).

### 5. GR-9: shared sentences, cloud bytes unchanged
- `ItemFieldMeaning` (`CloudOutputSchema.swift:35-57`) holds one sentence per field. `CloudInstructions.text` now
  interpolates it, and every `@Guide` uses the same constant. The exception is `sameAsExisting`, which differs by
  route on purpose (WI-M2-07 D1).
- **Byte check (mine):** I compiled the base `41bf8fa` literal and the head `ItemFieldMeaning` plus interpolated
  literal side by side in `swift:6.2-noble`. Result: `OldI.text == NewI.text`, both 2,030 UTF-8 bytes, equal byte
  arrays. The golden-request suites pass unchanged on Linux and on the Mac (B2, for example "A request-shaped value
  gives the exact golden bytes").
- **Frozen eval:** `git diff 41bf8fa 2515c7c -- Fixtures/` is empty. `Fixtures/M2/eval/MANIFEST.sha256` is identical
  to base (`e85dde40…5e39`), and `sha256sum -c` passes for its 4 files. In `TendIngestionTests` the only changes are
  the new `RouteWiringTests` case and `FixedOnDevice` recording households. No assertion was removed, no expectation
  was edited, nothing is skipped.
- `OnDeviceSchemaTests` reads each `@Guide` description from the encoded schema. It asserts that the description
  equals the shared constant and that `- <field>: <description>` is a line of `CloudInstructions.text`, and it pins
  the ruling 3 `isCritical` sentence literally. That is the string-comparison test that GR-9 asks for.

### 6. `TendIngestion` API change `model()` → `model(household:)`
- This is sound. There is one production conformer (`FoundationModelsOnDeviceSource`) and one test conformer
  (`FixedOnDevice`). The public `events(input:household:…)` passes the household it already receives, so callers
  cannot pass a mismatched one. The test-only overload defaults to an empty household, and only tests with scripted
  pipelines use it. Route `none` builds no model on the reachable path (tested). The unreachable `else` (`:146`)
  still stays on device.

### 7. Swift 6 concurrency
- There is no `@unchecked Sendable` and no `nonisolated(unsafe)` in Sources. The one `LockedBox` is in the test
  target and is documented.
- `PreparedGenerations` is an actor with a one-shot slot. `take` reads and clears with no `await` in between, so it
  has no reentrancy gap.
- Both unstructured `Task`s are cancelled by `onTermination`. The inner generation stream's termination cancels
  `streamResponse`'s task (mutant M3 killed).
- `snapshots(for:)` is nonisolated, so its `Task` does not inherit an actor and model work is never on the main actor.
- `FoundationModelsGeneration` is a `final class` with only `let` stored properties of `Sendable` types. It builds
  under `-swift-version 6 -warnings-as-errors`.

### 8. What I ran (Linux container, worktree detached at `2515c7c`)
| Command | Result |
|---|---|
| `docker run … swift:6.2-noble swift test --scratch-path /tmp/rev41-TendCore --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 141 tests in 18 suites passed`, 0 `warning:`, 0 skipped |
| same, `Packages/TendIngestion` | exit 0, `✔ Test run with 572 tests in 67 suites passed after 117.592 seconds`, 0 `warning:`, 0 `✘`, 0 skipped; AC-M2-09 scan suite (TendIngestion, TendAI, TendEval) and AC-M2-12 calm-vocabulary scan passed |
| same, `Packages/TendSourceScan` | exit 0, `✔ Test run with 63 tests in 4 suites passed` |
| `swift test --package-path Tools/TendTools -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 11 tests in 1 suite passed` |
| `swift build --package-path Packages/TendAI` | does not build on Linux, as expected (`no such module 'FoundationModels'`); plan.md: never built on Linux |
| Cloud-instruction byte comparison (§5) | equal, 2,030 bytes |
| Router mutant (§3) | killed |
| Evidence SHA-256 (§1) | 21/21 OK |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | **Major** | commits `94d02fe`, `2515c7c` (author and committer fields) | Both commits are authored and committed as `<local-login>@<Name>s-Mac-mini.local`. That is the owner's macOS login name and the Mac's hostname, because the Mac session's git identity fell back to the system default. Every earlier commit on `main` uses the owner's public address or `noreply`. The branch is public. On merge, the metadata becomes permanent in `main`'s history and can only be removed by a history rewrite. This is the same class as review PR #38 M1 (a personal identifier in committed evidence, Major), and it is exactly what this record's privacy check exists to prevent. (Skill step 9; CLAUDE.md "treat information about the user as private".) | On the Mac: set `git config user.name` and `user.email` for this repo to the identity the owner uses on `main`. Re-author both commits without changing their trees (for example `git rebase --exec 'git commit --amend --no-edit --reset-author' 41bf8fa`) and force-push `m2/on-device-adapter`. Then `git log --format='%ae %ce' 41bf8fa..HEAD` must show no `.local` address. Code trees are unchanged, so **no Mac rerun is needed**. In the README and the dev-notes, name the new code-commit SHA and state that its tree equals the tested `94d02fe` tree `41dca2d90267e75b1c9613aa33b4e650f7026be0` (`git rev-parse <sha>^{tree}`). Keep `94d02fe` as the SHA in `mac-B0-header.log` (it is what ran; do not edit the logs). Re-check the README SHA-256 lines if any hashed file changes. Owner: old SHAs may stay visible in the GitHub PR timeline; whether to ask GitHub to purge them is your call. | Open |
| m1 | Minor | `OnDeviceIngestionModel.swift:115` | `if Task.isCancelled \|\| error is CancellationError` finishes the stream **normally** when the framework throws `CancellationError` while our parse is not cancelled (for example a system-side cancel). The pipeline then reads a normal finish: the in-progress item is completed and repaired (rule c) and the outcome is `completed`. AC-M2-05 says a stream that stops mid-item is a throw: the item is discarded and the outcome is `interrupted` (or `noModel` before the first draft, AC-M2-10). A real consumer cancel always sets `Task.isCancelled` here, via `onTermination` → `task.cancel()`, so the second clause only matters in the wrong case. | Drop `\|\| error is CancellationError`, so an uncancelled `CancellationError` maps through `OnDeviceStopMapping` (`otherModelError`). Add a scripted test: `.fail(CancellationError())` without cancelling the consumer gives `interrupted` after a draft, and `noModel` before one. | Open |
| n1 | Nit | `OnDeviceOutput.swift:11`, dev-notes "Declaration order … `title` first (R-1)" | "`title` comes first, for time to first item (R-1)". A draft is emitted at item **completion** (rule a: the last property written), so the position of `title` does not change TTFI. Field order matters here only for the finished-values rule and for claims being known at emission. | Reword the comment (and the dev-notes sentence) so it does not suggest a latency gain. | Open |
| n2 | Nit | `OnDeviceSnapshotMappingTests.swift:129-150` (`monotone`) | The "a field never changes once shown" test checks title, sourcePhrase, time, room and sameAsItem, but not kind, effort, sameAsExisting or the three flags. | Optional: compare the whole `ItemSnapshot` field by field (every non-nil field equals the final one). | Open |
| n3 | Nit | `OnDeviceTestSupport.swift:133` | `.hang` spins on `Task.yield()` until cancelled, which busy-waits a core during the test. | Optional: wait on a continuation, or call `Task.sleep` in a loop (cancellation throws). | Open |
| i1 | Info (R-1, for Planner/PO) | `OnDeviceOutput.swift:123`; probes | Warm TTFI on the M1 Mac is about 6.3 s against AC-M2-16's < 1.5 s (iPhone 15 Pro is the gate). The split probe puts about 2 s on the Tool calls: the instruction "call findExistingTasks with the chore's main words" gives one sequential call per chore before the first token (3 calls in the probe). The schema adds about 1 s more. The code does not make this needlessly worse: it prewarms, uses one session per capture, the prompt is minimal, and greedy sampling is used. The levers in the dev-notes are plan or product decisions: one Tool call with all the main words, and shorter shared sentences in both routes. The second changes the AC-M2-20 golden request bytes. The dev-notes say "before the AC-M2-14 freeze", but the eval is already frozen (`MANIFEST.sha256`), so that lever now needs a PO decision. `prewarm(household:)` has no caller yet. WI-M2-M7 (`TendEval`) must call it when capture starts, or DS-1 measures a cold session. | Planner / PO: decide on SP-1 and the levers. Planner: add "TendEval calls `prewarm(household:)` at capture start" to WI-M2-M7's scope notes. | — |
| i2 | Info | `OnDeviceStopMapping.swift` (5 switches) | `@unknown default` appears 5 times, only on non-frozen SDK enums. A new `UnavailableReason` reads as `modelNotReady` (routing treats all reasons alike); a new error case reads as `otherModelError`. I count this as AC-M2-10's "no `default`" being met (none is a plain `default`; known cases are compiler-checked). | Acceptance Tester: record this reading when AC-M2-10 is taken. | — |
| i3 | Info | probes `probe-split.log` | With greedy sampling, the order of Tool queries still varied across runs (run 1 differs from runs 2–3). The answers were identical. | Acceptance Tester: don't assume bit-identical Tool traces across DS-1 repeats. | — |
| i4 | Info | `FoundationModelsOnDeviceSource.swift:19-23` | `locale` defaults to `.current` and is captured when the source is created. iOS relaunches the app on a language change, so this is fine as long as the app builds the source at launch. | None. | — |
| i5 | Info | — | `docs/product/TRACEABILITY.md` has no rows for the new TendAI tests (AC-M2-05/07/10 Mac halves, GR-9). | Documenter: add them when M2 traceability is updated. | — |

## Checklist
- [x] Correctness vs ACs. AC-M2-05: the on-device mapping is finished-values only, tested end to end (m1 is an edge
  case). AC-M2-07: the Tool returns exactly the shortlist's entries and fields. AC-M2-10: every Availability /
  `supportsLocale` / GenerationError case and the iOS 27 family are mapped, with no plain `default`. GR-9: sentences
  shared, cloud bytes unchanged.
- [x] Tests meaningful (would fail if code broke): 12 Developer mutants killed, plus my router mutant. The tests use
  the framework's own `PartiallyGenerated` values.
- [x] No weakening: no golden, fixture, manifest or existing expectation edited; 0 skipped on Linux and on the Mac.
- [x] Swift 6 concurrency safe (§7).
- [x] No force unwraps / `try!` in product code paths (`try?` only in prompt encoding, mapped to `otherModelError`).
- [x] Privacy (P-1…P-4) in **code**: no network, nothing persisted or logged. Evidence/metadata privacy: **M1 open**.
- [x] UX-2/UX-3 enforced in engine: no selection surface. No partial value reaches the pipeline. No new outcome or
  reason name. Guide, instruction and Tool texts pass `BannedTokens` (test).
- [ ] Accessibility (UI): n.a., no UI.
- [x] Performance: model work is off the main actor; prewarm is available; R-1 is information (i1).
- [x] No new dependency without ADR (FoundationModels is an Apple framework; ADR-0005/0006 layout).

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No "what to do now" API; the draft stream is a capture review (Q11). |
| UX-3 Zero-Guilt | pass | Snapshots never show a partial title or number ("Late" of "Later" tested). Every new text passes the banned-token test. Reason names are neutral and blame nobody (`busy`, `otherModelError`, `timedOut`, …). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | `FoundationModels` only. On-device errors and unavailability never route to the cloud (router tests; cloud source never asked). |
| P-2 No data leaves device (except user iCloud) | pass (code) / **concern (repo metadata, M1)** | No networking in TendAI (AC-M2-09 Rule 2 scan, 0 violations). M1 is a personal-data leak into the public repo history, not a runtime data flow. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Cloud instruction bytes are proven identical (2,030 bytes). The Tool is never given to a cloud model. |
| P-4 Media not persisted without consent | pass | The prompt, the answers and the session live in memory for one capture. Nothing is written or logged. A prewarmed session holds only the household value in memory. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Review PR #41 at `2515c7c` (base `41bf8fa`). |
| 2026-11-27 | Reviewer | Developer (owner's Mac), via Orchestrator | returned | CHANGES REQUIRED: M1 (commit identity, no rerun needed). m1 recommended in the same push. n1–n3 optional. i1 to Planner/PO (R-1, prewarm wiring in WI-M2-M7). i2/i3 to Tester, i5 to Documenter. |

---

# Round 2 — PR #43 (`m2/on-device-adapter-v2`, head `d5e7938`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 2
- **Scope:** PR #43 re-creates PR #41 with the same trees and a neutral commit identity. Round-2 changes are
  `git diff ff79f9c d5e7938`: `fad715a` (code and tests: m1, PO R-1 ruling (a), n1, n3) and `d5e7938` (docs only: the
  Mac evidence record `evidence/mac/WI-M2-M2-r2/` and the dev-notes section). Requirements: AC-M2-05, AC-M2-07,
  AC-M2-10 (Mac halves); R-1 / PO ruling 2026-11-27 option (a) (`po-m2-r1-latency.md`); po-m2-wi07 ruling 1 (word-match
  floor); po-m2-wi0607 (re-mark on log growth); FR-A1; P-1…P-4; UX-3.
- **Inputs read:** `CLAUDE.md`; this skill; the round-1 review above; the PO ruling `po-m2-r1-latency.md`; the full
  round-2 code and test diff; the new dev-notes section; the r2 evidence README, run script, B0 header, timings, B4 log
  and the dev-set probes; `OnDeviceIngestionModel.swift` (stream and `PreparedGenerations`), `OnDeviceTestSupport.swift`.
- **Milestone lock:** `STATUS.md` shows M2 `IN-BUILD`; an `m2/` build item is allowed. No protected path is touched.
  Merge route unchanged (D-032: Mac-only PR, owner merges with the evidence record for the exact head).

## Summary
Every round-1 finding that needed action is fixed and verified. The commit identity leak (M1) is gone. An unrequested
framework `CancellationError` is now a model stop (m1), with tests for both outcomes. The PO's one-Tool-call rule is
enforced in code in the recorder actor, not only in the prompt. D1 and the re-mark-on-growth path are unchanged. A test
proves that the word-match floor still marks a repeat that only a refused second call would have found. The frozen eval
is untouched, the evidence hashes match, the docs commit is docs-only, and the four Linux packages pass with warnings
as errors. I have only Nits left. **APPROVE.**

## Verification of round-1 findings
| # | Round-1 severity | Verified how | Status |
|---|---|---|---|
| M1 | Major | `git log --format='%an %ae %cn %ce' 41bf8fa..HEAD`: all five commits read `Claude noreply@anthropic.com` for author and committer. No `.local` address. In `evidence/mac/WI-M2-M2-r2/` and the new dev-notes section, a grep for `/Users/`, `/var/folders`, `*s-Mac*` hostnames, `USER=`/`LOGNAME=`/`HOSTNAME=` and e-mail addresses finds nothing. Paths show only the `$HOME`/`$REPO`/`$SCRATCH` tokens. The `PATH` lines in the B6 logs are generic system paths plus `$HOME/.local/bin`. | **Closed** |
| m1 | Minor | `OnDeviceIngestionModel.swift:114`: the catch now tests only `Task.isCancelled`. Any other error, `CancellationError` included, goes through `OnDeviceStopMapping` (`otherModelError`). `OnDeviceFollowUpTests`: "…after a draft, ends interrupted (AC-M2-05)" expects `.interrupted(.otherModelError, discardedItem: .stoppedBeforeComplete)`. "…before any draft, ends noModel (AC-M2-10)" expects `.stoppedBeforeFirstDraft(.otherModelError)`. A consumer cancel still ends `.cancelled` even when the framework then throws (new `.throwOnCancel` script mode), at the pipeline level and at the stream level. All four tests passed in the Mac B4 log. The Developer's mutant C1 (restore the old clause) kills two of them; I agree from reading, since the old clause turns both into `completed`. | **Closed** |
| n1 | Nit | `OnDeviceOutput.swift:11-13` now says a draft is emitted at item completion and that `title` placement does not change TTFI. Same in dev-notes. | **Closed** |
| n2 | Nit | Not taken (optional). | Open (optional, non-blocking) |
| n3 | Nit | `OnDeviceTestSupport.swift:139`: `.hang` now loops on `Task.sleep(for: .seconds(3_600))`, so it no longer busy-waits. | **Closed** |
| i1–i5 | Info | i1 was answered by the PO ruling (option (a) now, then SP-1). The others stay with the roles named in round 1. | — |

## PO ruling R-1 (a): checked against each Developer duty in the ruling
1. **Enforced in code:** `DuplicateLookupTool.swift:37-53`. `DuplicateLookupRecorder.answeredCallLimit = 1`, guarded by
   `log.queries.count < limit` inside the actor, so the check and the record happen in one step with no `await`
   between them. Concurrent Tool calls cannot both get through. Later calls return `nil`, which the Tool turns into an
   empty result, and they are counted in `refusedCalls` but not recorded. The instruction text and the Tool
   description and `@Guide` also ask for a single call. That wording is checked by a test, but the code rule does not
   depend on it.
2. **D1 and re-mark unchanged:** the rules still replay `recorder.queries`, which now holds only the answered query.
   "snapshots carry only the one answered query…" checks that every snapshot carries `["pods"]` and that a title claim
   the Tool returned still marks `ofExisting(uuid 3)`. The re-mark path in `OnDeviceIngestionModel.swift:95-111` is not
   touched. Recorder lifetime is one per capture: `PreparedGenerations.take` empties the slot, and
   `makeGeneration` builds a fresh recorder, so the cap cannot carry over into the next capture.
3. **Tests:** "the first Tool call is answered…; every later call gets no entries and is not recorded" (second and
   third calls are empty, `queries == ["pods"]`, `refusedCalls == 2`). "a repeat that only a refused second call would
   have found is still marked, by the word-match floor": the answered query `pods` does not shortlist "Water the
   plants", the refused call's result is empty, D1 cannot accept the claim, and the draft is still `ofExisting(uuid 42)`,
   so the floor marked it. Mutants R1 (limit 100) and R2 (refused call still answered) each break that test and
   `secondCallRefused`. I agree from reading: under either mutant, `second.tasks` and the last lookup result are
   non-empty.
4. **Dev-set check (information only, never the frozen eval):** `probes/devset-{before-ff79f9c,after-fad715a}.log`.
   Tool calls drop from 17 to 8. Duplicates created stay at 2 (the same two synonym misses in both runs), false merges
   stay at 0, and median TTFI on the Mac drops from 5.87 s to 5.31 s. Nothing got worse. This is Mac information, not
   AC-M2-16 evidence. AC-M2-16 stays `AWAITING-DEVICE`, and SP-1 is next.
5. **VERIFY (manifest scope)** is answered in dev-notes with file and line. `MANIFEST.sha256` covers four files and the
   freeze test pins three (`EvalFreezeTests.swift:34-38`). Neither covers `payload/golden/` or the instruction text.
   The PO decides what this means for (b).

Changed existing expectations: two tests (`recordsQueries` and the contract-4 snapshot test) now expect `["pods"]`
where they used to expect both queries. That follows from the PO-mandated rule change, and the new assertions are
stricter equalities, so this is not a weakening.

## Evidence checks
- `mac-B0-header.log` names `fad715a3d1f8…`. `git diff --name-only fad715a d5e7938` lists only files under `docs/`.
  `git status` is empty before and after the run.
- All 20 SHA-256 lines in the r2 README match the committed files (`sha256sum -c`: 20 OK, 0 failed). The folder holds
  21 files, the 20 hashed files plus the README.
- Mac results at `fad715a`: B1 141/18, B2 572/67 (AC-M2-09 scan 63 files, 0 violations), B4 55/7 (`TEST SUCCEEDED`,
  all eight new tests listed as passed), B5 2/1, B6 as MS-1 (TendEval archive exit 66 as expected). No compiler
  warnings. 0 skipped.
- Frozen eval untouched: `git diff 41bf8fa HEAD -- Fixtures/M2/eval` is empty (`MANIFEST.sha256` is unchanged).
- Linux (this container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `d5e7938`): TendCore 141 tests in 18
  suites; TendIngestion 572 in 67; TendSourceScan 63 in 4; TendTools (`Tools/TendTools`) 11 in 1. All passed, exit 0,
  0 `warning:` lines. TendAI needs FoundationModels, so it is Mac-only; its evidence is the B4 log above.

## Findings (round 2)
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n4 | Nit | `OnDeviceOutput.swift:13` (160 cols); `OnDeviceIngestionModel.swift:118` (122); `OnDeviceFollowUpTests.swift:55,91` (124, 126) | These lines run past the 120-column width used elsewhere. n1's rewording left line 13 un-reflowed. | Optional: reflow. | Open |
| n5 | Nit | `OnDeviceFollowUpTests.swift:136` | `floorCatchesWhatTheSecondCallMissed` checks that `pods` does not shortlist "Water the plants". It does not check the other half of its premise, that `water plants` would. The R1 and R2 mutants depend on that premise. | Optional: add `#expect(DuplicateLookup.entries(for: "water plants", in: household).contains { $0.title == "Water the plants" })`. | Open |
| n6 | Nit | `probes/devset-Package.swift.txt:1` | The copy puts a comment line before `// swift-tools-version:`, so it does not run as a `Package.swift` verbatim. It is information only. | None needed. Optionally note it in the README. | Open |
| i6 | Info (PO / Planner / Tester) | — | The DECISIONS.md entry the PO ruling asks for ("Tool called at most once per capture…") and the Planner's WI-M2-M2 and SP-1 ordering belong to a human-merged governance PR. They are not part of this PR. Next steps: the Tester scripts SP-1 on this build and the owner runs it. AC-M2-16 stays `AWAITING-DEVICE`. | Planner/PO: land the governance entry. Tester: SP-1 script. | — |
| i7 | Info (Tester) | `DuplicateLookupTool.swift:52` | A refused call returns an empty list, so the model may read "nothing found" for chores it asks about late. The floor still covers word matches. Synonym repeats the single lookup misses are not marked, as in the dev set (the same 2 before and after). AC-M2-07, AC-M2-08 and AC-M2-17 on the frozen eval decide this. | Tester: watch duplicates created per input in DS-1. | — |

No Blocker, no Major, no Minor open.

## Checklist (round 2)
- [x] Correctness vs ACs: AC-M2-05 and AC-M2-10 (m1 outcomes) tested; AC-M2-07 with the one-call rule (D1, floor,
  re-mark) tested; PO R-1 (a) duties 1–4 met.
- [x] Tests meaningful: the C1, R1 and R2 mutants are killed (the Developer ran them on the Mac, and I agree from
  reading). Changed expectations follow the mandated rule and are not weaker.
- [x] Swift 6 concurrency safe: the cap check and the record happen in one actor step with no suspension. The new
  `script` capture in test support is a `final class` in the test target. No new `@unchecked Sendable` in Sources.
- [x] No force unwraps / `try!` in product code paths.
- [x] Privacy (P-1…P-4): code is unchanged in kind. The evidence and commit metadata are now clean (M1 closed).
- [x] UX-2/UX-3: no selection surface. New Tool and instruction text passes `BannedTokens`, which ran in B4.
- [ ] Accessibility (UI): n.a., no UI.
- [x] Performance: fewer Tool round trips before the first token (8 vs 17 on the dev set). R-1 is decided by SP-1.
- [x] No new dependency without ADR.

## Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No "what to do now" surface. |
| UX-3 Zero-Guilt | pass | Duplicate protection is kept (one lookup plus the floor on every path). New texts pass the banned-token test. Outcome names are unchanged and neutral. |
| UX-4 Design craft | n.a. (watch R-1) | No UI. TTFI on the Mac is still far above 1.5 s. SP-1 on iPhone 15 Pro decides. |
| P-1 On-device inference | pass | Only FoundationModels. A framework cancel now ends `interrupted` or `noModel` and never escalates silently to cloud. Routing is unchanged. |
| P-2 No data leaves device (except user iCloud) | pass | No networking in TendAI (AC-M2-09 scan, 0 violations). Repo metadata is clean (M1 closed). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Only the on-device instruction changed. No cloud payload golden or fixture changed. The Tool is never given to a cloud model. |
| P-4 Media not persisted without consent | pass | The recorder, the session and the answers stay in memory for one capture. |

## Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Round 2 of PR #43 at `d5e7938` (round 1 at `ff79f9c`; base `41bf8fa`). |
| 2026-11-27 | Reviewer | Orchestrator → owner (D-032 merge), Tester, Planner/PO | sent | **APPROVE.** M1, m1, n1 and n3 are closed. n2 and n4–n6 are optional. i6: governance entry and SP-1. i7: Tester to watch DS-1. An APPROVE accepts no AC. |
