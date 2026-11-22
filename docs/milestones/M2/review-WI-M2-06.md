# M2 Code Review — WI-M2-06, PR #22 (`m2/draft-stream`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE (round 2, head `d1c0f84`; round 1 at `646c789` was CHANGES
  REQUIRED)  ·  **Round:** 2 (see [Round 2](#round-2--head-d1c0f84) at the end)
- **Requirements:** FR-A1, P-1, P-3, P-4, UX-3. ACs (Linux parts, all ○ in plan WI-M2-06): **AC-M2-05**, **AC-M2-10**,
  **AC-M2-23**. Touches the brief Definitions "Item completion", "Draft stream events", "Route" and "Plain note", plus
  T-03, T-25 and AC-M2-12 (calm names).
- **Commits reviewed:** `c64a184` (code), `646c789` (dev notes). Diff `origin/main...HEAD` (base `2f9f86f`). It touches
  only `Packages/TendIngestion/**` and `docs/milestones/M2/dev-notes.md`. No protected path is touched, no dependency
  is added, and no existing source file is changed.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. WI-M2-06 is M2 work, and its DoR is met
  (WI-M2-05 is merged at `2f9f86f`).
- **Inputs:** CLAUDE.md; brief.md (Definitions; AC-M2-05, 09, 10, 12, 16, 23; T-03, T-25); plan.md (WI-M2-06 and the
  WI-M2-M2, M4, 09, 14 boundaries, R-4); design.md (no stream copy yet); dev-notes.md (WI-M2-06). PO notes:
  `po-q21-q22.md`, `po-m2-wi04.md` (ruling 2a), `po-m2-wi05.md`, `po-m2-wi07.md` (ruling 1, hook contract), and
  **`po-m2-wi06.md` (PO rulings on this PR's open questions 1–5, received during the review)**.

## Summary
The PR adds the neutral route and reason types (`Route`, `CloudProvider`, `OnDeviceUnavailableReason`,
`ModelStopReason`, `NoModelReason`, `RoutedModel`), the event and outcome types, a pure synchronous
`DraftStreamAssembler`, the public `DraftPipeline` / `DraftEventSequence` (`Failure == Never`), and `PlainNote`.

The engineering is very good:
- **Concurrency.** The iterator is a plain value type. The only shared state is `Sendable` (`RoutedModel`, the
  duplicate check). There is no `@unchecked Sendable`, no `nonisolated(unsafe)`, no lock, no `Task {}`, no clock and
  no dispatch queue in the sources. `next(isolation:)` passes the caller's actor to the model iterator. Cancellation
  is checked at one place, at the top of every `next`. It drops buffered events, sets `source = .ended` (which drops
  the last reference to the model's `AsyncThrowingStream` iterator, so its termination handler runs with `.cancelled`
  at once), and returns `finished(.cancelled(route:))`, then `nil`. A cancelled wait returns early from
  `AsyncThrowingStream`, so there is no hang, and whatever it buffers is overridden by the top-of-loop check. The
  tests prove the release while the iterator is still held, and they run the consumer in its own task, so a broken
  rule fails at the time limit instead of hanging.
- **Completion rules (a)/(b)/(c)** are implemented exactly (`DraftStreamAssembler.swift:58-74`). Only the last item
  of a snapshot can be in progress, so items complete in output order. Completion is final.
- **The four outcomes and the route.** Each carries the route. `RoutedModel` holds exactly one model or none, so an
  on-device error cannot re-route to the cloud, retry or queue. This is a type-level property, not a promise (AC-M2-10,
  P-1, P-3). `noModel` before any draft and `interrupted` after one follow T-25 and AC-M2-23.
- **Plain note** follows the Definitions, and PO ruling 3 confirms the trim and guard choices.
- **Duplicate hook** matches the contract as relayed (once per position, in order, before `emitted`, `earlier` = latest
  lower drafts). PO ruling 5 now changes the contract for updates (F2).
- **Tests are real.** 16 hand-written scripted cases run through both the assembler and the pipeline. There is a
  6,000-script seeded property against a timeline oracle, and 9 of my 10 mutants were killed cleanly. The tenth was caught only by a hang (F6).

**Two Majors are open, both from the PO's rulings on this PR's own open questions** (`po-m2-wi06.md`, rulings 1 and
5). Each changes product behaviour that the brief's Definitions now specify (the PO's brief amendment). The Orchestrator
asked for both to be fixed in this PR. There are also four Minors (F3-F6). I found no law violation and no concurrency defect.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | **Major** | `Stream/DraftStreamEvent.swift:31`, `:51-63`; `Stream/DraftStreamAssembler.swift:69-74`; tests `DraftStreamTests.swift:332` (case "no items at all"), `DraftStreamPropertyTests.swift:84` | **PO ruling 1 (`po-m2-wi06.md`, Q1): `completed` with no emitted draft must return the input text and the plain-note offer.** As built, a normal finish with zero items, or with every item skipped by Q5, gives `completed(route)` with no input and no note, so the person's words are lost (brief Outcomes "loses nothing the person said"; UX-3). The PO amended the Definitions `completed` bullet and AC-M2-05 to require this. | Do exactly what ruling 1 says: (1) `completed` gets optional `input` and `plainNote`, filled only when the emitted-draft count is 0 (the note is nil only for a blank input), and the `input` / `plainNote` accessors return them. (2) Tests: empty output; all items skipped (with `itemSkipped` first); one draft then finish (both nil); blank input with empty output (note nil). Add these to the scripted table and to the property oracle, with an independent count of emitted drafts. Update `checkRules` (`DraftStreamPropertyTests.swift:247`). (3) Kill the mutants "no note on completed with 0 drafts" and "note on completed with ≥ 1 draft". (4) Update dev-notes open question 1 and the rules list. | Open |
| F2 | **Major** | `Stream/DraftStreamAssembler.swift:125-141` (line 135 `next.duplicate = last.duplicate`), `:13-18` header; `Stream/DraftStreamEvent.swift:92-98` (protocol doc "not called on an update"); tests `DraftStreamTests.swift:417` (`duplicateMarkerSetAtEmission`), `:436` (`duplicateHookContract`); `DraftStreamPropertyTests.swift:71` | **PO ruling 5 (`po-m2-wi06.md`, Q5): the stream must re-mark duplicates after updates.** As built, an update keeps the marker set at emission. If a draft's title changes, a `none` marker can become a duplicate creation at commit, or a stale duplicate marker can become a false merge. That breaks the M2 gate line "zero duplicate creation" (FR-A1, AC-M2-07/08), and the review screen would not show what commit will do (po-m2-wi05 ruling 1). Commit re-checks only `ofExisting` targets, so it cannot be the backstop. The Definitions `updated` bullet now says a full replacement includes the marker. | Implement ruling 5 in `DraftStreamAssembler`. Emission stays unchanged. On a snapshot that produces updates, after the re-map, run the check again in ascending `draftID` for the lowest updated draft and **every later emitted draft**, each against the latest lower drafts (the `ofDraft` cascade). Each draft whose content or marker changed gets exactly one `updated`. Updates still come before new emissions, and new emissions are checked against the re-marked drafts. Add the invariant test: after `finished`, each marker equals one pass of the check over the final drafts in `draftID` order. Flip the two "set once" tests. Add cases for `none` → duplicate, duplicate → `none`, the cascade (draft 2's content is unchanged but it still gets an `updated`), and "no update → no extra calls". Give the property oracle the same rule, written independently, plus the invariant. Kill these mutants: "marker kept on update" (the current code), "no cascade", and "re-mark after new emissions". Update D7, the follow-up table and open question 5. If the Orchestrator keeps the PR narrow instead, ruling 5 allows this as a binding item for the WI-M2-06/07 integration PR before WI-M2-08 starts. That needs an explicit Orchestrator/PO record. Without one, this stays Major on this PR. | Open |
| F3 | Minor | `Stream/DraftPipeline.swift:27` | The `init` doc says the duplicate check is "called before each `emitted` and `updated`". That contradicts the code and `DraftStreamEvent.swift:92-98` (not called on an update). After F2 it is still inexact, because the re-mark also runs for later drafts that were not updated. | Make the doc state the ruling-5 rule in one place (protocol doc) and point to it from the `init`. | Open |
| F4 | Minor | `Model/IngestionModel.swift:140-147` | The prompt-release-on-cancel guarantee (D4) relies on two things an adapter could break. (i) The adapter must not keep its own reference to the returned `AsyncThrowingStream`. If it does, dropping the pipeline's iterator does not end the stream, and `onTermination` does not fire. The test double `ControlledModel` deliberately drops its slot. (ii) The adapter's `onTermination` must cancel the producer task (the `streamResponse` loop, the `URLSession` bytes task). Otherwise model work and network use go on after the user cancels (P-3 turn-off semantics, WI-M2-09; WI-M2-M2/M4). The protocol doc also still says "the availability and failure reasons ... are added to this contract by WI-M2-06". That is now done, as `RoutedModel` and `ModelStopReason`. | State the adapter contract in the `IngestionModel` doc: end by throwing a `ModelStopReason`; do not keep the returned stream; cancel all work in `onTermination`. Refresh the stale sentence. WI-M2-M2/M4 then test (ii) on the Mac. | Open |
| F5 | Minor | `Stream/DraftStreamAssembler.swift:31-34` (rule (a)); `DraftStreamPropertyTests.swift:107-151` (generator) | Rule (a) can fire while the title is still a prefix, when a model sends fields out of declaration order (possible for cloud JSON, WI-M2-12/13). The draft is then emitted as "Buy", and the duplicate check sees "Buy" (F2 fixes later re-marking). The calm-words guard also runs on a partial token. In that case a prefix such as "Late" of "Latex gloves" is removed from the emitted title and is restored by a later `updated`. This is within the Definitions (PO ruling 2 confirms D1) and is self-correcting through `updated`. No code change is needed for this PR. It is a watch item for WI-M2-13 and the dev-set eval. | None for this PR. Record it under "Known limitations" in dev-notes so that WI-M2-12/13 tests a title that arrives last. | Open (watch) |
| F6 | Minor | `Tests/TendIngestionTests/DraftStreamTests.swift:565-691` (cancellation suite) | The rule that `finished` comes exactly once on the cancellation path depends on one line, `isDone = true` (`DraftPipeline.swift:88`). If that line is removed (my M7), `next()` returns `cancelled` forever with no suspension point. Every `for await` cancellation test then spins without end, the `.timeLimit` traits cannot fire, and the whole `swift test` run hangs: there is no failing test and no diagnostic, only a CI job timeout. The dev-notes claim "no hang" for the developer's mutants, but this one hangs. | Bound the consumption in the cancellation tests: stop collecting after a `finished` event and then call `next()` once more, expecting `nil`, or iterate with a hard event cap (for example 64) and fail if it is reached. M7 must then fail by assertion. Add M7 to the dev-notes mutant table. | Open |

Nits (no action required): the long line at `DraftStreamAssembler.swift:17`. The pull's `.ended` branch
(`DraftPipeline.swift:132-136`) is unreachable and ends calmly, which is fine.

### What I checked and found correct
- **Swift 6 concurrency.** I checked the following and found no defect:
  - `DraftEventSequence: Sendable` holds only `Sendable` values. `Iterator` is deliberately not `Sendable`, because it
    holds an `AsyncThrowingStream.Iterator`.
  - The `case var .running(iterator)` copy shares the stream's storage, and `source` is rewritten after the await.
    There is no state that is assumed unchanged across the suspension: all the mutable state is the iterator's own
    `inout self`.
  - `next()` forwards to `next(isolation: nil)`. Package platforms are iOS/macOS 26, so `AsyncThrowingStream.Iterator.next(isolation:)` is available on Darwin.
  - The build is clean under `-warnings-as-errors`. Darwin behaviour is still to be confirmed in the plan B2 repeat,
    as the dev notes say.
- **Rules (a)/(b)/(c)** and their oracle. A normal finish completes the rest of the items and repairs them through Q5.
  A throw discards the in-progress item (`stoppedBeforeComplete`), or gives nil between items.
- **`noModel` versus `interrupted`.** The test is `drafts.isEmpty`, not "anything completed". My mutant M4 shows that
  skipped-then-throw stays `noModel`.
- **Foreign errors** map to `otherModelError`.
- **Route `none`** gives one event, `finished(noModel(.none, .onDeviceUnavailable, input, note))`, and the model is
  never asked. Cancel before start gives `cancelled` with the route on all three routes.
- **The hook contract as built.** `earlier` = all lower `draftID`s at their latest versions, and skipped items take no
  position (`RecordingCheck`).
- **AC-M2-23 "none blames the user".** I read every case name: `keyNotAccepted`, `serviceUnavailable`, `refusal`,
  `offline`, `timedOut`, `hostNotFound`, `secureConnectionUnavailable`, `rateLimited`, `unreadableOutput`,
  `outputCutShort`, `busy`, `assetsUnavailable`, `guardrail`, `contextTooLong`, `unsupportedLanguage`,
  `otherModelError`, the four unavailable reasons, `stoppedBeforeComplete`, `stoppedBeforeFirstDraft`, `interrupted`,
  `noModel` and `cancelled`. Each one describes the situation or the system, never the person. None holds a banned
  token: the `calmNames` test passes, and the vocabulary scan reports 0 violations.
- **Oracle independence.** The timeline oracle computes completion steps from the whole script first, and the
  assembler walks forward incrementally. They share only `DraftMapper.map` (proven by AC-M2-01/02) and the test-double
  check. Rule (a) is written out again rather than called. The rule-(a) predicate is the same expression on both
  sides, so the oracle proves the incremental algorithm, not the brief's reading of rule (a). The hand-written
  scripted table (the brief's required oracle) and PO ruling 2 cover that reading. This is acceptable.
- **Commit order D6** (ascending `draftID`, `DraftStreamSummary`) matches po-m2-wi04 ruling 2a and po-m2-wi05.

## Tests (reviewer's own run)
Run in `swift:6.2-noble` (Swift 6.2.4), with the CI commands from `.github/workflows/ci.yml` and `-Xswiftc
-warnings-as-errors`, on the worktree at `646c789`:

| Command | Result |
|---|---|
| `swift build --package-path Packages/TendIngestion --scratch-path /tmp/rev22-ing -Xswiftc -warnings-as-errors` | `Build complete!`, 0 warnings |
| `swift test --package-path Packages/TendIngestion --scratch-path /tmp/rev22-ing -Xswiftc -warnings-as-errors` | `✔ Test run with 152 tests in 18 suites passed after 10.071 seconds.` Property: seeds 0601/0602/0603, 2,000 scripts each, **0 oracle mismatches**. The counts are identical to dev-notes (for example 0603: emitted 3541, updated 526, itemSkipped 912, completed 1225, interrupted 513, discarded 331, noModel 262, dup 552). AC-M2-09 scan `18 files in total, 0 violations`. AC-M2-12 vocabulary scan `18 files, 9 exempted (the list), 0 violations`. |
| `swift test --package-path Packages/TendSourceScan --scratch-path /tmp/rev22-scan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 2.560 seconds.` |
| `swift build` / `swift test --package-path Packages/TendCore --scratch-path /tmp/rev22-core -Xswiftc -warnings-as-errors` | `Build complete!`; `✔ Test run with 141 tests in 18 suites passed after 84.414 seconds.` (package unchanged) |

### Reviewer mutants
Each mutant was applied alone to a copy outside the worktree. Each was run with `--filter
"DraftStream|NoModel|CloudOutcome|PlainNote"` and `-warnings-as-errors`, under a 400 s timeout, and then restored.

| # | Mutant (file) | Result |
|---|---|---|
| M0 | rule (a) ignores `isWeatherDependent` (`DraftStreamAssembler.swift:33`) | killed, 12 issues (property + scripted) |
| M1 | rule (b) off by one, `completedCount + 2 < items.count` (`:63`) | killed, 16 issues. One cancellation test failed at its 60 s time limit, not by hanging (the `consumeInOwnTask` design works) |
| M2 | duplicate hook gets `earlier: []` (`:116`) | killed, 18 issues |
| M3 | refresh uses the draft offset as the item index (`:131`) | killed, 12 issues |
| M4 | `noModel` only when nothing completed, so skipped-then-throw becomes `interrupted` (`:80`) | killed, 148 issues |
| M5 | `discardedItem` set whenever the snapshot has items (`:84`) | killed, 18 issues |
| M6 | update does not carry the marker (`:135` removed) | killed, 13 issues |
| M7 | `isDone` not set on the cancellation path (`DraftPipeline.swift:88`) | **detected only as a hang.** The test process stopped producing output and was killed by my 400 s `timeout`. `for await` gets `cancelled` forever with no suspension point, so the cooperative `.timeLimit` cannot fire (see F6) |
| M8 | plain note trims spaces but not newlines (`PlainNote.swift:20`) | killed, 2 issues |
| M9 | after a snapshot the source is set to `.ended` (`DraftPipeline.swift:122`) | killed, 212 issues |

9 of 10 were killed cleanly by failing tests. M7 was caught only by a hang (F6). The worktree was never modified:
the mutants ran on a copy in the scratchpad.

## Checklist
- [ ] Correctness vs ACs: the AC-M2-05 / 10 / 23 Linux parts are met as the brief read at `646c789`, but PO rulings 1
  and 5 amend the Definitions and AC-M2-05 (F1, F2).
- [x] Tests meaningful (would fail if code broke): hand-written oracle table, seeded property, 27 developer mutants and 9 of 10
  reviewer mutants killed by failing tests. M7 was caught only by a hang (F6).
- [x] Swift 6 concurrency safe: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no unstructured `Task` in the
  sources, cooperative cancellation, model stream released on cancel. F4 states the adapter side of the contract.
- [x] No force unwraps / try! in product code paths.
- [x] Privacy (P-1…P-4): one routed model, no network or write API, input returned in memory only.
- [x] UX-2/UX-3 enforced in engine: no "next up" list; calm names and the guard before every event.
- [x] Accessibility (UI): n.a. (no UI).
- [x] Performance: O(drafts) re-maps per snapshot over a handful of items, pure string work, no main-actor work. F2
  adds O(drafts) checks per updating snapshot, which is fine.
- [x] No new dependency without ADR.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every field is inferred. The plain note is one free-text draft with defaults (PO ruling 3). No field is asked of the user. |
| UX-2 Rule of Three | pass | A capture-review stream, not a "what to do now" surface. It has no candidates or next-up list. Drafts reach Now only through commit and `NowSelector`. |
| UX-3 Zero-Guilt | pass (with F1 open) | Names are calm and blame no one, as inspected above. The guard runs before every event, and the user's own banned words are kept in the plain note. F1 (a capture ending with nothing kept) is the PO's UX-3 reading. It is tracked as a Major, not as a law violation in the code as specified at review time. |
| UX-4 Design craft | n.a. | No UI. Copy and motion for these outcomes come in M3. |
| P-1 On-device inference | pass | `RoutedModel` holds exactly one model. An on-device error ends as `noModel` or `interrupted` with route `onDevice`, and it never escalates (AC-M2-10 tests; type-level). |
| P-2 No data leaves device (except user iCloud) | pass | No networking (AC-M2-09 scan, 0 violations). The model request is the capture text and room names only (ADR-0005 Decision 3). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | No retry, no queue and no re-route in the stream. Calm plain-note fallback. F4 asks adapters to stop work on cancel (turn-off semantics). |
| P-4 Media not persisted without consent | pass | No write or log API. The input is in memory only, the plain note is saved only by commit, and cancel writes nothing (repository unchanged in the test). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Reviewer | accepted | PR #22 head `646c789`, WI-M2-06 (AC-M2-05, 10, 23 Linux parts). |
| 2026-11-21 | Orchestrator | Reviewer | accepted | PO rulings `po-m2-wi06.md` relayed mid-review: Q1 and Q5 code changes required in this PR; Q2, Q3, Q4 confirmed. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: F1, F2 Major (PO rulings 1, 5); F3-F6 Minor (F6: one cancellation mutant hangs the suite instead of failing). No law violation, no concurrency defect. Re-review the delta in round 2. |
| 2026-11-22 | Orchestrator | Reviewer | accepted | Round 2, head `d1c0f84` (`e487d5a` code and tests, `d1c0f84` docs and the PO's brief edits). |
| 2026-11-22 | Reviewer | Orchestrator → Merge Gatekeeper | accepted (APPROVE) | F1–F6 closed and verified. Two new Minors, R2-F1 and R2-F2, are non-blocking. The two R2-F2 items should be tracked into the WI-M2-06/07 integration ticket. |

## Round 2 — head `d1c0f84`

- **Verdict: APPROVE.** No Blocker or Major is open.
- **Diff reviewed:** `646c789..d1c0f84`. The code touches only `Packages/TendIngestion/**`. The docs changes are
  `brief.md` (the PO's amendment), `dev-notes.md`, and this file, as committed from round 1. No protected path is
  touched and no dependency is added. `origin/main` is still `2f9f86f`, so the branch is up to date, and WI-M2-07
  (PR #21) is not merged.
- **Milestone lock:** M1 `ACCEPTED`, M2 `IN-BUILD`. Unchanged.

### Round 1 findings, verified in the new diff
| # | Status | Evidence |
|---|---|---|
| F1 Major (PO ruling 1) | **Closed** | The outcome is now `completed(route:input:plainNote:)`, where both payloads default to nil (`DraftStreamEvent.swift:33`). `finishNormally` fills them only when `drafts.isEmpty` (`DraftStreamAssembler.swift:79-81`). The `input` and `plainNote` accessors return them. Tests: scripted cases "no items at all", "every item skipped" (`itemSkipped` comes first) and "one draft then a normal finish" (both nil), through the assembler and the pipeline. Also `blankInputCompleted` (note nil, input returned) and `completedNoDraftEveryRoute` (on device and 3 providers). The property oracle uses its own count of `emitted` events, and `checkRules` asserts both directions. Coverage `completedNoDraft` is 254/255/259 per seed. My mutants R7–R9 are killed (below). |
| F2 Major (PO ruling 5) | **Closed** | `refreshEmitted` (`DraftStreamAssembler.swift:134-156`) works in three steps. (1) It re-maps content and keeps the old marker. (2) It finds `lowest` = the first content change. If there is none, it returns with no call. Otherwise it re-checks `lowest..<count` in ascending order, each draft against `latest[..<offset]`, the latest lower drafts, already re-marked. That covers the `ofDraft` cascade. (3) It gives one `updated` per draft whose content or marker changed. `receive` still runs the refresh before new completions, so new drafts are checked against the re-marked drafts. I checked this against the ruling's rule text point by point; it matches. **Invariant:** by induction, a draft below `lowest` has had no change in itself or in any lower draft since its last check. So with a pure check, the final markers equal one pass over the final drafts. This is tested by `markerInvariant` (hand-written scripts) and by the property on every script: **0 invariant misses** over 6,000 scripts, `remarked` 31/32/39. The "set once" tests are flipped (`duplicateMarkerReMarked`, `duplicateHookContract`). The new `markCases` cover none → duplicate, duplicate → none, the cascade with unchanged content, re-mark before a new emission, and a lower draft unchanged. `noUpdateNoCalls` is added. The oracle's re-mark is written as "new contents, then a fresh pass from the first change". That is structurally close to the code, but the separate invariant check and the hand-written cases make up for it. |
| F3 Minor | **Closed** | The calling rule is stated once, in the `DraftDuplicateCheck` doc (`DraftStreamEvent.swift:99-106`). `DraftPipeline.init` points to it. |
| F4 Minor | **Closed** | The `IngestionModel` doc now states the 3-point adapter contract: end with a `ModelStopReason`, do not keep the stream, cancel all work in `onTermination`. The stale sentence is replaced. Part (3) remains Mac evidence for WI-M2-M2/M4. |
| F5 Minor (watch) | **Closed** (recorded) | It is under dev-notes "Known limitations", for WI-M2-12/13. |
| F6 Minor | **Closed** | `collectBounded` stops at the first `finished`, asks `next()` once more (it must be nil) and caps at 64 events. It is used by every `for await` consumer in the cancellation suite. `cancelBeforeStart` gains `.timeLimit`. **M7 now fails cleanly:** I re-ran it, and 5 tests fail by assertion in 5.2 s, with no hang. |

### Brief edits against `po-m2-wi06.md` (word for word)
I compared each quoted text after collapsing whitespace and line wraps. A script checked that each quote occurs in
both the ruling and the new `brief.md`:

| Ruling text | Where in the brief | Match |
|---|---|---|
| Ruling 5, the new `updated(draft)` bullet | Definitions, Draft stream events | exact |
| Ruling 1, the new **completed** bullet | Definitions, outcome list | exact |
| Ruling 1, the `interrupted` sentence ("No plain note is offered: a stop before any draft is `noModel` (T-25), …") | Definitions, `interrupted` bullet | exact. The old sentence "A plain note is offered only if no draft was emitted." is gone. |
| Ruling 5, the AC-M2-05 `updated` append ("After `finished`, each draft's duplicate marker equals …") | AC-M2-05, second bullet | exact |
| Ruling 1, the new AC-M2-05 bullet ("A stream that finishes normally with no draft emitted …") | AC-M2-05, directly after the "finishes normally" bullet, as the ruling places it | exact |

No AC text was removed and no meaning was weakened: AC-M2-05 only gains bullets. The DECISIONS.md entries stay with
the human-merged governance PR, as the ruling says. Note for the Orchestrator: the ruling planned these edits as "a
docs PR on main". Carrying them in this PR is fine, because `brief.md` is not a protected path.

### New findings (round 2)
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R2-F1 | Minor | `Tests/TendIngestionTests/DraftStreamTests.swift` (`duplicateHookContract`, `markCases`) | My mutant R3b survives. It re-marks from draft 1 whenever any draft changed (`for offset in min(lowest, 0)..<…`). With a pure check this gives the same events and markers, so only the call log can tell it apart. No `RecordingCheck` test has a snapshot where a lower draft is unchanged and a higher one changes. The ruling says the check runs "for the lowest updated draft and every later emitted draft". Over-calling becomes visible once the WI-M2-07 marker reads per-parse state (see R2-F2). | Add a `RecordingCheck` case: three drafts, and only draft 3 is retitled. Expect exactly one re-mark call, `(3, [1, 2])`. This can be done in this PR or at integration. It does not block. | Open (non-blocking) |
| R2-F2 | Minor (watch, integration) | `Stream/DraftStreamEvent.swift:99-106` (`DraftDuplicateCheck` doc) | The invariant ("final markers = one pass over the final drafts") and the "below `lowest` is not re-checked" optimisation are correct only if the check is a **pure function of `(draft, earlier)` plus context fixed for the parse**. WI-M2-07's on-device path reads "a title the `Tool` returned in this parse" (po-m2-wi07 ruling 1). That log grows during the parse. In that case, a draft below `lowest` keeps a marker computed against an older log. Also, `ItemSnapshot` has no model-claim field yet, and ruling 5 says the check must read "the latest item's model claim". | At the WI-M2-06/07 integration, choose one: (a) freeze the Tool log for marking purposes, (b) re-mark all drafts when the log grows, or (c) document why it cannot matter. Then state the purity requirement in the protocol doc, and route the item's model claim through the re-mapped draft. Track this in the integration ticket that is binding before WI-M2-08. | Open (watch) |

### Tests (reviewer's own run, `swift:6.2-noble`, Swift 6.2.4, CI commands, `-Xswiftc -warnings-as-errors`)
| Command | Result |
|---|---|
| `swift build` + `swift test --package-path Packages/TendIngestion --scratch-path /tmp/rev22-ing` | `✔ Test run with 157 tests in 18 suites passed after 10.580 seconds.` 0 warnings. Property, seeds 0601/0602/0603: **0 oracle mismatches, 0 invariant misses**, `completedNoDraft` 255/254/259, `remarked` 31/32/39, `updated` 533/557/545. These numbers match dev-notes. AC-M2-09 scan `18 files in total, 0 violations`. AC-M2-12 vocabulary scan `18 files, 9 exempted (the list), 0 violations`. |
| `swift test --package-path Packages/TendSourceScan --scratch-path /tmp/rev22-scan` | `✔ Test run with 63 tests in 4 suites passed after 2.590 seconds.` |
| `swift build` + `swift test --package-path Packages/TendCore --scratch-path /tmp/rev22-core` | `✔ Test run with 141 tests in 18 suites passed after 91.094 seconds.` |

### Reviewer mutants, round 2
These ran on a scratchpad copy, not the worktree, with `--filter "DraftStream|NoModel|CloudOutcome|PlainNote"`,
`-warnings-as-errors` and a 400 s timeout. After the run, the copy was `diff -r` identical to the worktree sources.

| # | Mutant | Result |
|---|---|---|
| R0 | no cascade: only content-changed drafts are re-marked (`:146` `where latest != drafts`) | killed, 4 tests |
| R1 | re-mark against the pre-update lower drafts (`drafts[..<offset]`) | killed, 4 tests |
| R2 | re-mark checks the old content (`of: drafts[offset]`) | killed, 3 tests |
| R3b | re-mark from draft 1 whenever anything changed | **survived**. Behaviourally equivalent for a pure check; see R2-F1 |
| R4 | re-mark on every snapshot, even with no change | killed, 2 tests (`noUpdateNoCalls`, hook contract) |
| R5 | `updated` only on a title change, so a marker-only change is silent | killed, 4 tests |
| R6 | re-mark only the lowest changed draft | killed, 4 tests |
| R7 | plain note on `completed` even with drafts | killed, 10 tests |
| R8 | `completed` with 0 drafts has no plain note | killed, 4 tests |
| R9 | `completed` with 0 drafts has no input | killed, 5 tests |
| R10 | round 1 M7: `isDone` not set on the cancellation path | **killed by assertion**, 5 tests in 5.2 s, no hang (F6 fixed) |

10 of 11 were killed. The survivor, R3b, is equivalent under a pure check and is recorded as R2-F1.

### Concurrency (round 2 delta)
The delta changes no concurrency code. `refreshEmitted` stays synchronous and pure, inside the value-type assembler.
The new test helper `collectBounded` runs in the consumer's own task. Round 1's conclusions still hold.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | The plain note on an empty `completed` is still one free-text draft with defaults, offered and not emitted. |
| UX-2 Rule of Three | pass | No selection surface is added. |
| UX-3 Zero-Guilt | pass | A capture never ends with nothing kept (ruling 1). The case names are unchanged and pass the calm-names test and the vocabulary scan. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | No change to routing. An on-device error never escalates. |
| P-2 No data leaves device (except user iCloud) | pass | Re-marking is local. The AC-M2-09 scan reports 0 violations. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | No retry, queue or re-route. The adapter contract now asks adapters to stop all work on cancel (F4). |
| P-4 Media not persisted without consent | pass | The input is returned in memory only. The plain note is saved only by commit. |
