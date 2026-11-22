# M2 Code Review — WI-M2-08 commit confirmed drafts (PR #25, `m2/commit`, head `91a62b6`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** FR-A1; ● AC-M2-06 (commit writes, re-check, `ofDraft` never created, injected IDs, W3-F6 / Q10),
  ● AC-M2-08 (commit half of the property); commit clauses of AC-M2-04 and AC-M2-07; regression AC-M2-09, AC-M2-12.
- **Binding inputs checked:** brief Definitions (Draft, Word-match floor, Local duplicate re-check, Duplicate) and
  AC-M2-04/06/07/08; plan WI-M2-08 row and W3-F6; dev-notes WI-M2-04, WI-M2-07, "WI-M2-06/07 integration", WI-M2-08;
  `review-WI-M2-04.md` (R19-F1, R19-F2), `review-WI-M2-06-07-integration.md` (R23-F1, R23-N2, R23-F2); PO notes
  `po-q21-q22.md` (WI-M2-08 tickets), `po-m2-wi04.md` (ruling 2), `po-m2-wi07.md` (ruling 2), `po-m2-wi0607.md`
  (brief wording), and `po-m2-wi08.md` (2026-11-22, received mid-review: C3.1–C3.4 and C4 ACCEPTED as built).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed.

## Summary
`DraftCommit` is the only write path. It loads the household once and decides every confirmed draft in a pure
`plan(...)`. It then writes the new rooms (`updateRoom`) and the new tasks (`upsertTask`) in ascending `draftID`
through `HouseholdRepository` and nothing else. It makes no network call, does no I/O and does no logging (the
AC-M2-09 scan is green). Verified against the focus list:

- **No overwrite / colliding generator (AC-M2-06, W3-F6, R19-F2):** `CommitIDAllocator` (`DraftCommit.swift:240-260`)
  seeds its `taken` set with every task and room ID of the loaded household and inserts each issued ID. A draw that
  is taken is skipped. The bound is (in use + 1,024) draws, then `idGeneratorExhausted` is thrown before any write.
  Both M1 repositories treat `upsertTask`/`updateRoom` as replace-or-append (`HouseholdRepository.swift:15-17`), so a
  fresh ID is what prevents an overwrite. Tests: `collisionSkip` and `stuckGenerator` (both repositories), plus the
  property with a generator that returns 25 % in-use IDs and 12 % repeats. The ground truth checks that nothing old is
  overwritten and no ID repeats. My mutant R2 (room IDs not taken) is killed with 54 issues.
- **Ascending `draftID`:** `inDraftOrder` (`DraftCommit.swift:224-237`) is a stable sort on (`draftID`, offset). An
  identical repeat is dropped, and a conflicting one throws `draftIDRepeated` before any write. My mutant R6 (input
  order) is killed.
- **R19-F1:** the shared `CommitRoomResolver.peek` uses `RoomLinker.lowestRoom` (`.min` by UTF-8 `uuidString`). It is
  tested in 3 array orders on both repositories and through `commitPlan`. My mutant R4 (`.max`) is killed.
- **R19-F2:** `commitPlan` documents its `makeID` precondition (`RoomLinker.swift:44-46`). `DraftCommit` meets it
  through the allocator. Room IDs and task IDs share one namespace, which is stricter than W3-F6.
- **`ofDraft` never created (PO WI-M2-07 ruling 2):** C1 runs before any room or ID work. It is tested with k
  confirmed, dismissed and unconfirmed on both repositories, and in the property (1,189 / 327 cases, 0 created).
- **Gone/completed `ofExisting` (C3.1–C3.4):** this departs from the brief's literal sentence "treated as not a
  duplicate". It does not contradict the brief's intent, because under the literal reading AC-M2-08 ("no committed
  task is a duplicate of another non-completed task") and the Duplicate definition would fail. The developer raised
  it as a PO question and did not decide it alone. The PO has since ACCEPTED it as built (`po-m2-wi08.md` ruling 1),
  so it is the specified behaviour. My mutants R3 (no C3.1) and R5 (no C3.2, which is not in the developer's list)
  are killed.
- **Write-failure semantics:** each repository call is atomic and leaves the store unchanged on a throw (AC-M1-07),
  and the counters advance only after a call returns. So `writeStopped(roomsWritten, tasksWritten)` describes exactly
  what is stored. I confirmed this with probe P2: a refused second task write gives `(0, 1)` and exactly one stored
  task. There is a partial-commit risk by design (per-item writes rather than one `save`). It is documented, and the
  retry guidance is correct: re-committing the same drafts would duplicate the `none` drafts. It is left to M3. The
  `tasksWritten` counter itself is not pinned by any PR test (F2).
- **Both M1 repositories:** every contract test is parameterised over `InMemoryHouseholdRepository` and
  `JSONFileHouseholdRepository`, with a reopen-as-restart for the file store. The property sends every 10th household
  to the file store (180 commits).
- **Oracle independence:** `CommitOracle` re-implements ordering (by selection), name folding, room peek, word-match
  (`DupOracle.wordMatch`, brute force) and ID skip (a replayed generator copy). It shares only
  `IngestionDraft.task(id:roomID:)` (the M1 mapping, proven by AC-M2-01/02) and `DraftMapper.map` for draft content.
  The ground-truth checks need no rule logic. It mirrors the C3 structure, which is expected for a spec oracle. The
  ground-truth checks are the independent net.
- **Brief edit:** the Word-match floor insertion matches `po-m2-wi0607.md` word for word ("(at any point in the parse;
  when the Tool's results grow, every draft is checked again and a changed marker reaches the user as `updated`, PO
  2026-11-22, WI-M2-06/07 Q1)"), placed after "a title the `Tool` returned in this parse". Only the line wrapping
  changed.
- **R23-F1 / R23-N2:** there is a hand test and the doc wording is applied. The integration open question 1 is
  closed, citing `po-m2-wi0607.md`. **R23-F2** is honestly deferred (PR #24 is not merged) and stays a ticket.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R25-F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Commit/DraftCommit.swift:248-251` | "In use" covers only task and room **IDs**. It does not cover a `roomID` that an existing task still references while the room is gone (a dangling reference, which is legal in M1: D5, `LocalWordMatch` "a roomID with no such room means no room"). Probe P1: a household with the task "Dust the shelf" (roomID `…DD`, no such room) and a generator returning `…DD` makes the new room "Porch" take `…DD`. The old task is then silently linked to "Porch". No task record is overwritten, but an existing task's meaning changes, which goes against the spirit of AC-M2-06 "never overwrites" and the doc "no existing task or room is changed". It is reachable only with a colliding generator (the app uses `UUID()`), so it is not Major. The same gap applies to IDs of tasks or rooms removed since the parse (`parsedWith`), which can be reissued. | Add every task's `roomID` to `taken` (and optionally the `parsedWith` task and room IDs). Add a hand test like P1, and let `CollidingIDs` sometimes return dangling and removed IDs. | Open (non-blocking) |
| R25-F2 | Minor | `Packages/TendIngestion/Tests/TendIngestionTests/CommitTests.swift:535-545` | `writeStopped` is the API's promise of "exactly what was stored", and M3's retry depends on `tasksWritten`. The only refused-write test stops at the first task (`tasksWritten: 0`). My mutant R1 (`tasksWritten += 0`) **survives** the whole Commit/RoomLink filter (40 tests green). The developer's M16 pinned only `roomsWritten`. The current code is correct (probe P2). | Add a case that refuses a later task write (for example, write 2 with no new room, or write 3 after one room), expect `tasksWritten: 1`, and assert the stored household. | Open (non-blocking) |
| R25-F3 | Minor (docs) | `docs/milestones/M2/dev-notes.md` (WI-M2-08 "Open questions", C3 row); `docs/milestones/M2/brief.md:158-159` | `po-m2-wi08.md` answered both open questions after this head was pushed. The developer still has to close Q1/Q2 citing it and change the C3.3 summary to "word-match on t's title and room". The PO also offered a "Commit re-check" Definitions bullet plus edits to the Q12 = yes bullet and to AC-M2-06 that replace the literal "treated as not a duplicate". Until then, the brief text and the code disagree in wording. | Apply the dev-notes edits. Insert the PO's brief text word for word if the PO wants it in this PR, otherwise in the PO's docs PR. The Orchestrator said the developer will add these. | Open (doc follow-up) |
| R25-N1 | Nit | `DraftCommit.swift:87-89` | `commit` runs to completion even if its task is cancelled. There is no cancellation check between writes. That is a good choice, because it avoids a self-inflicted partial write, but it is unstated. | Optionally say in the doc that cancellation does not interrupt a commit. | Open (optional) |
| R25-N2 | Nit (ticket) | — | R23-F2 (build the duplicate rules from the route, or add a wiring test per route) is deferred until PR #24 merges. | Keep it on the WI-M2-08/09 wiring ticket. | Carried |

No Blocker or Major.

## Tests run (reviewer, independent)
Docker `swift:6.2-noble` (Swift 6.2), CI commands from `.github/workflows/ci.yml`, `--scratch-path /tmp/rev25-<pkg>`,
`-Xswiftc -warnings-as-errors`, `swift build` then `swift test`, source mounted read-only:

| Package | Result |
|---|---|
| TendCore | build 0, `✔ Test run with 141 tests in 18 suites passed after 116.839 seconds.` 0 warnings |
| TendSourceScan | build 0, `✔ Test run with 63 tests in 4 suites passed after 3.790 seconds.` 0 warnings |
| TendIngestion | build 0, `✔ Test run with 233 tests in 30 suites passed after 73.420 seconds.` 0 warnings. `WI-M2-08 commit property: seed 0xC0A11CEED080801/…0802/…0803, 200 households × 3 paths, 0 oracle mismatches, 0 ground-truth misses`. AC-M2-09 and AC-M2-12 scans green |

**Reviewer mutants** (on a copy at `/tmp/rev25-mut`, never the worktree; filter `Commit|RoomLink`):

| # | Mutant | Result |
|---|---|---|
| R1 | `tasksWritten` not counted | **survived** (R25-F2) |
| R2 | room IDs not seeded into `taken` | killed (54 issues) |
| R3 | no C3.1 (follow the first draft with the same gone target) | killed (16) |
| R4 | room tie by `.max` uuidString (R19-F1) | killed (13) |
| R5 | no C3.2 (commit-time floor over the household) | killed (32) |
| R6 | commit in input order, not `draftID` | killed (22) |

**Probes** (test file added only in the copy): P1 dangling roomID reuse → new room took `…DD` (R25-F1 confirmed). P2
refused second task write → `writeStopped(…, 0, 1)`, store holds exactly one new task (the current code is correct).

## Checklist
- [x] Correctness vs ACs (AC-M2-06 all bullets, AC-M2-08 commit half, AC-M2-04 commit clauses)
- [x] Tests meaningful (would fail if code broke): 5 of 6 reviewer mutants killed. R1 is a test gap (F2), not a code defect
- [x] Swift 6 concurrency safe: no `@unchecked Sendable` or `nonisolated(unsafe)`; `plan` is synchronous before any
  `await`; the generator is `inout`, not shared; counters are local
- [x] No force unwraps / `try!` in product code paths
- [x] Privacy (P-1…P-4): repository calls only, AC-M2-09 green
- [x] UX-2/UX-3 enforced in engine: no selection surface; new tasks are `active`; names pass the AC-M2-12 scan
- [ ] Accessibility (UI): n.a., no UI
- [x] Performance: O(drafts × tasks) word-match per gone target, fine for a capture. `taken` is a Set
- [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Commit is one act over confirmed drafts. Rooms and IDs are inferred, and nothing is asked. |
| UX-2 Rule of Three | n.a. | No "what to do now" surface. Commit only upserts into the repository `NowSelector` reads (T-21). |
| UX-3 Zero-Guilt | pass | New tasks are `active` with no lateness state. A completed task is never held against the person (`po-m2-wi08` ruling 1). Identifiers pass the AC-M2-12 vocabulary scan. |
| UX-4 Design craft | n.a. | No UI (M3 notes are in `po-m2-wi08.md`). |
| P-1 On-device inference | n.a. | No inference. The re-check is local and deterministic. |
| P-2 No data leaves device (except user iCloud) | pass | Only `HouseholdRepository` calls, with no network, I/O or logging (AC-M2-09: 0 violations). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | Nothing is sent. |
| P-4 Media not persisted without consent | pass | A parse makes no repository call (spy test). Only confirmed drafts are written, and dismissed or unconfirmed ones are never written. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Reviewer | accepted | PR #25 at `91a62b6`, WI-M2-08 (AC-M2-06, AC-M2-08, FR-A1). |
| 2026-11-22 | Orchestrator | Reviewer | accepted | Mid-review: `po-m2-wi08.md`, C3.1–C3.4 and C4 accepted as built; treated as specified behaviour. |
| 2026-11-22 | Reviewer | Orchestrator → Developer, Merge Gatekeeper | sent | **APPROVE.** No Blocker or Major. Three Minors (F1 dangling roomID reuse, F2 `tasksWritten` untested, F3 doc follow-ups from `po-m2-wi08.md`) and two Nits, all non-blocking. They can be fixed in this PR before merge or ticketed for WI-M2-08/09 wiring. |

---

## Round 2 — head `58a1a95` (one commit on `91a62b6`)

- **Verdict:** APPROVE  ·  **Round:** 2
- **Requirements:** FR-A1; AC-M2-06 (W3-F6 / Q10 IDs, Commit re-check), AC-M2-08 (commit property).
- **Binding inputs:** round 1 findings above; PO `po-m2-wi08.md` (rulings 1 and 2, brief text).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. Allowed.

### Summary
Each finding is verified in the new diff (`git diff 91a62b6..58a1a95`). The only product code change is the
`CommitIDAllocator` "in use" set plus two doc comments. The rest is tests and docs. Nothing else in the commit rules
changed.

### Findings (round 1 → round 2)
| # | Severity | File:line | Verification | Status |
|---|---|---|---|---|
| R25-F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Commit/DraftCommit.swift:254-263` | `init(household:parsed:)` puts into `taken` every task ID, every task `roomID` (dangling ones included) and every room ID of **both** the household at commit and `parsedWith`. That covers dangling room references and IDs removed since the parse. New contract test `danglingAndRemovedIDsInUse` (`CommitTests.swift:277`, both repositories, reopen) uses my P1 fixture. The property's `CollidingIDs` now draws dangling and parse-household IDs too (coverage keys `danglingRoomID`, `removedSinceParse` are required on every seed; my run shows a non-zero count for every seed). The ground truth adds "a new room took an ID an existing task points to" and "a new task reused the ID of a task removed since the parse". The oracle skip rule is an independent re-implementation. **My probe P1 now passes** (new room `F…01`, not `…DD`). My mutants R7 (dangling `roomID` not taken) and R8 (`parsed` not taken) are killed (34 and 36 issues). `stuckGenerator`'s exact draw count still holds, because the fixtures' task rooms are existing rooms. | **Closed** |
| R25-F2 | Minor | `Packages/TendIngestion/Tests/TendIngestionTests/CommitTests.swift:573-588` | `refusedLaterTaskWrite`: write 2 of 3 is refused, giving `writeStopped(…, roomsWritten: 0, tasksWritten: 1)`, the exact call list, and the stored household is old + exactly the first planned task. **My mutant R1 (`tasksWritten += 0`) is now killed** by this test (1 issue). | **Closed** |
| R25-F3 | Minor (docs) | `docs/milestones/M2/brief.md:155-158, 173-180, 281-282`; `dev-notes.md` WI-M2-08 | I checked the text against `po-m2-wi08.md` by script, comparing with whitespace normalised. The **Commit re-check** bullet matches word for word, directly after the Word-match floor bullet. The AC-M2-06 edit "(**Commit re-check**, Definitions)" matches. The two Q12 = yes sentences are deleted ("treated as not a duplicate" no longer appears in the brief). A decision-log row has been added; the DECISIONS.md entry is left to the governance PR, as the PO said. Dev-notes open questions 1 and 2 are closed, citing `po-m2-wi08.md`. C3.3 now reads "word-match on t's title and room" in the dev-notes and in the `DraftCommit.plan` doc. | **Closed** |
| R25-N1 | Nit | `DraftCommit.swift:84-85` | The doc now states that cancellation does not interrupt a commit. | **Closed** |
| R25-N2 | Nit (ticket) | — | R23-F2 is still on the WI-M2-08/09 wiring ticket (PR #24 not merged). | Carried |

No new findings. No Blocker or Major.

### Tests run (reviewer, round 2)
Docker `swift:6.2-noble`, CI commands, `--scratch-path /tmp/rev25-<pkg>`, `-Xswiftc -warnings-as-errors`,
`swift build` then `swift test`, source mounted read-only, 0 warnings in every log:

| Package | Result |
|---|---|
| TendCore | build 0, `✔ Test run with 141 tests in 18 suites passed after 116.689 seconds.` |
| TendSourceScan | build 0, `✔ Test run with 63 tests in 4 suites passed after 1.932 seconds.` |
| TendIngestion | build 0, `✔ Test run with 235 tests in 30 suites passed after 54.375 seconds.` (233 + 2). `WI-M2-08 commit property: seed 0xC0A11CEED080801/…0802/…0803, 200 households × 3 paths, 0 oracle mismatches, 0 ground-truth misses` |

**Mutants and probes** (on a fresh copy of `58a1a95` at `/tmp/rev25-mut`, never the worktree; filter `Commit|RoomLink`):

| # | Mutant / probe | Result |
|---|---|---|
| P1 | dangling `roomID` offered first by the generator | pass: new room takes `F…01` |
| P2 | refused second task write | pass: `(0, 1)` |
| R1 | `tasksWritten += 0` | killed (R25-F2 test) |
| R7 | dangling task `roomID` not in use | killed (34 issues) |
| R8 | `parsedWith` IDs not in use | killed (36 issues) |

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Unchanged: commit infers rooms and IDs and asks nothing. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | The brief's Commit re-check says a completed task is never held against the person. No lateness state. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. |
| P-2 No data leaves device (except user iCloud) | pass | Repository calls only. AC-M2-09 scan green. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | Nothing sent. |
| P-4 Media not persisted without consent | pass | Only confirmed drafts are written. A parse writes nothing. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Reviewer | accepted | Round 2 at `58a1a95`: R25-F1, F2, F3, N1 fixes; round 1 report committed. |
| 2026-11-22 | Reviewer | Orchestrator → Merge Gatekeeper | sent | **APPROVE.** R25-F1, F2, F3, N1 closed and verified (P1 passes, R1/R7/R8 killed, brief text word for word). R25-N2 carried on the WI-M2-08/09 wiring ticket. No open Blocker or Major. |
