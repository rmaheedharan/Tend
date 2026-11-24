# M2 Code Review — WI-M2-14 cloud deadline and single 429/5xx retry over a neutral transport (PR #30, `m2/cloud-deadline-retry`, head `2d626a2`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE (round 2, head `1c15b90`; round 1 was APPROVE at `2d626a2`)  ·  **Round:** 2
- **Requirements:** FR-A1, P-2, P-3, P-4, UX-3. This PR delivers the Linux parts (○) of **AC-M2-22** (the "Timeouts"
  bullet: deadline, per-attempt timeouts, retry rule; T-17, T-28, Q22) and **AC-M2-23** (outcome, plain note and retry
  decisions over a neutral failure reason; T-18). WI-M2-M4 owns both (●) on the owner-run Mac. Regression: AC-M2-09
  (Rule 1 scan over the new `Transport/` files) and AC-M2-12 (vocabulary).
- **Binding inputs checked:** `CLAUDE.md`. Brief: AC-M2-22, AC-M2-23, Definitions (draft stream events, plain note),
  Outcomes, Q15, Q22, T-17, T-18, T-25, T-28. Plan: WI-M2-14 row, the "**WI-M2-14 — `m2/cloud-deadline-retry`**"
  section, N-2, WI-M2-M4/M6/M7 rows. ADR-0005 (no background queue or retry, P-4 line 157) and ADR-0006 (module
  layout). Dev-notes WI-M2-14 section (D1–D10, open questions 1–3). PO notes `po-m2-wi06.md` (rulings 1, 4),
  `po-m2-wi09.md` (ruling 3), `po-m2-wi10.md`. Received mid-review: `po-m2-wi14.md` (PO rulings on open questions 2
  and 3, note on 1).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. WI-M2-14 is M2 work; its dependencies
  (WI-M2-06, 09, 10) are merged on `main` `f1b6458`. Allowed. No protected path is touched
  (`git diff --stat f1b6458...2d626a2`: three new files under `TendIngestion/Sources/TendIngestion/Transport/`, a
  comment-only change in `Stream/DraftPipeline.swift`, two new test files, `docs/milestones/M2/dev-notes.md`).
- **Limits of this review:** Linux only. Whether `URLSession` really applies the timeouts, the redirect/host refusal and
  the `URLError`/status mapping are WI-M2-M4 (Mac) and are not judged here.

## Summary
The design is small and right. The transport protocol carries only plain values (N-2). `CloudTiming` holds the Q22
numbers as `Duration`. `CloudRetryRule` is a pure function. `CloudResponseBody<C: Clock>` runs the attempts as a
three-state iterator (`beforeAttempt` → `reading` → `ended`) on an injected clock. It spawns no task, has no queue,
and does no I/O or logging. Every throw ends the iterator. The retry cannot be sent a third time:
`attempt < maximumAttempts` guards it, and dev mutant M6 plus my mutant J prove it. I checked the Q22 arithmetic line
by line against the brief and found it exact at every boundary (table below). The tests are real: I ran 5 more
mutants of my own and the suites killed all 5. One probe found a small gap. When the reading task is cancelled in the
middle of a body, the body reports a normal end, not `CancellationError` as the file header says (R30-F1). Nothing is
sent and no outcome changes, because whoever cancels throws the output away. So it is Minor. No Blocker or Major.

| Focus | What I checked | Result |
|---|---|---|
| Deadline 10.0 s from receipt (AC-M2-22, Q22) | `deadline = start + captureDeadline`, where `start` is an input. Test `deadlineFromReceipt` starts at 100 and reads at 102.5, giving a deadline of 110 and timeouts (7.5, 4). Before each attempt `left > .zero`; test `noTimeLeft` at 10.0 / 10.5 / 30.0 sends nothing and ends `timedOut`. My mutant B (`>=`) is killed at exactly 10.0. | pass |
| Per-attempt timeouts (resource = time left; request = min(left, 4.0 s)) | `CloudTiming.timeouts` reads the clock just before `send`, so the retry's timeouts come from the time after the pause (test `retryAfterRateLimit`: (10, 4) then (8.5, 4); dev M19). Boundaries 4.001 → (4.001, 4), 4.0 → (4, 4), 3.999 → (3.999, 3.999), 1 ns. The `Double` conversion is exact for every Q22 value and every whole-second `Retry-After`. | pass |
| Pause p = max(0.5 s, `Retry-After`) (T-28) | `max(minimumRetryPause, .seconds(delaySeconds))`. Test cells cover missing, `0`, `1`, `2`, unreadable, HTTP-date, 7 and 8. Dev M8, M20 and M23 kill the variants. | pass |
| `Retry-After` delta-seconds only | RFC 9110 `1*DIGIT` after SP/HTAB trimming (OWS). Everything else counts as 0: sign, fraction, `1e2`, hex, non-ASCII digits (U+0663, U+FF11), NBSP, newline, inner space, list `5, 6`. Digits accumulate with a cap at 999,999,999 checked after each digit, so the largest intermediate value is about 1e10 and cannot overflow `Int`. `timeLeft - pause` in `Duration` cannot overflow either. | pass |
| 3.0 s rule before and after the pause | Before: `timeLeft - pause >= 3.0 s`, so there is no needless wait (test `boundaryNoRetry` at 6.501 s: no sleep). After: `timeLeft >= 3.0 s` read again from the clock after `sleep` (test `recheckAfterPause` with a 1 ms late wake: no retry, the original reason kept). Exactly 3.0 s retries: 6.5 s gives a send at 7.0 with (3, 3); `Retry-After 7` at 0 s retries. My mutant A (`>` after the pause) and mutant D (pre-check ignores the pause) are killed. | pass |
| Only 429/5xx, at most once, never after body bytes | `allowsRetry` is true only for `rateLimited` and `serviceUnavailable` (set-equality test). `attempt < 2`. `bodyStarted` is set when the first chunk is returned (test `noRetryAfterBody`; dev M7). A second 429/5xx ends with its own reason after exactly 2 sends and 1 pause (4 cells; my mutant J, an extra sleep before the retry, is killed). | pass |
| Nothing sent after cancel or deadline | Before each attempt: `Task.checkCancellation()`, then the time check. Cancelling during the pause makes the clock's sleep throw (test `cancelDuringPause`, blocking `ManualClock`). After `ended` the iterator gives nil and sends nothing, even 60 s later (test `nothingAfterward`). Mid-body cancellation: nothing more is sent, but see R30-F1 for the end type. | pass (R30-F1) |
| No background queue (AC-M2-23, ADR-0005) | `Sources/.../Transport/*`: no `Task {`, no `Task.detached`, no `DispatchQueue`, no stored buffer, no file or log. When the iterator is released, the transport stream is released (test with `HoldingTransport.terminations == 1`). | pass |
| Failure → outcome mapping (AC-M2-23, UX-3) | 9 reasons map to `ModelStopReason`, and the table equals `allCases`. Through the real `DraftPipeline`, 3 providers × 9 reasons: `noModel(stoppedBeforeFirstDraft(r))` with the input and the plain note before a draft, and `interrupted(r)` with the input, the draft kept and no plain note after one. A malformed body gives `unreadableOutput`; a deadline cut gives `interrupted(timedOut)` or `noModel(timedOut)` with the plain note. Refusal and the `none` route are covered by existing WI-M2-06/13 tests. Every brief failure case has a calm typed end. | pass |
| D7: a failure that arrives after the deadline keeps its own reason | My mutant I (turns it into `timedOut`) is killed by the property test. | pass |
| The oracle is independent | Property test: 4,000 seeded scripts, seed printed in every message. The decision oracle is integer milliseconds and written separately from `CloudRetryRule`/`CloudTiming`. Its `Retry-After` reader uses `trimmingCharacters` plus a digit check, a different method from the code under test. Only the `Double` seconds check reuses the same formula (`Seconds.of`); see R30-F4. | pass (Nit) |
| Clock injection under Swift 6 | `CloudResponseBody<C: Clock>` with `C.Duration == Duration` is `Sendable` through `Clock: Sendable`. The iterator is non-`Sendable`, as it should be. `next(isolation:)` passes the isolation to the inner stream iterator. The static `retry` touches only the `Sendable` body. No `@unchecked`, no `nonisolated(unsafe)`. The test clock uses a `Mutex` and a cancellation handler that resumes the continuation exactly once. Built with `-warnings-as-errors`: 0 warnings. | pass |
| No real time / sleep / I/O / logging in Sources (AC-M2-09) | grep of `Transport/*.swift`: no `Date`, `ContinuousClock`, `SuspendingClock`, `Task.sleep`, `print`, `Logger` or `URL` identifier (comments only). The AC-M2-09 scan in the `TendSourceScan`/`TendIngestion` runs passes with `CloudResponseBody.swift` scanned. | pass |
| AC-M2-12 vocabulary; T-18 "none blames the user" | I inspected the case names: `offline`, `timedOut`, `hostNotFound`, `secureConnectionUnavailable`, `keyNotAccepted` (says the provider did not accept, not "your key is wrong"), `rateLimited`, `serviceUnavailable`, `requestNotSent`, `unexpectedResponse`. None names the person or contains a banned token. Test `calmNames` plus the AC-M2-12 scan: 0 violations. | pass |

## Test runs (this review, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, worktree at `2d626a2`)
| Package | Result |
|---|---|
| `Packages/TendIngestion` (scratch `/tmp/rev30-ing`) | "Test run with 475 tests in 57 suites passed after 109.624 seconds", 0 warnings. The 6 new suites (34 tests) pass; the property test took 49.1 s in the full parallel run and 2.5 s alone. |
| `Packages/TendCore` (scratch `/tmp/rev30-TendCore`) | "141 tests in 18 suites passed" |
| `Packages/TendSourceScan` (scratch `/tmp/rev30-TendSourceScan`) | "63 tests in 4 suites passed" |

## Probes and mutants (scratch copy `/tmp/claude-0/rev30mut` from `git archive HEAD`; one change at a time, restored after each; `diff -r Packages` against the worktree is equal afterwards; the worktree was never edited)
| # | Change | Result |
|---|---|---|
| Probe P1 | Cancel the consumer of a `CloudResponseBody` over `HoldingTransport` after its first chunk | Prints `normal end after 1`, not `CancellationError` (R30-F1) |
| A | After-pause re-check `>=` → `>` | killed (`boundaryRetry`, `retryAfterHonoured` "7") |
| B | Before-attempt `left > .zero` → `>= .zero` | killed (`noTimeLeft` at 10.0) |
| D | Pre-pause rule ignores the pause (`timeLeft >= 3`) | killed (rule table, `boundaryNoRetry`, `retryAfterHonoured` "8"/"9") |
| I | A failure after the deadline reports `timedOut` (against D7) | killed (property test) |
| J | Extra 1 ms clock sleep before the retry send | killed (`retryThenAnswer`, `secondFailure`) |

With the developer's 23 mutants (all killed), the rule is pinned at every boundary I could think of.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R30-F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Transport/CloudResponseBody.swift:101-117` | When the reading task is cancelled in the middle of a body, `AsyncThrowingStream.Iterator.next` returns `nil`. The iterator treats that as a **normal end** of the body (`state = .ended; return nil`). The file header (line 16) says "`CancellationError` passes through". Probe P1 shows `normal end after 1`. An adapter would then call its reader's `finish()` on a partial body. Today this changes no outcome and sends nothing: the canceller (the pipeline after a consumer cancel, or the router via `onTermination`) discards the output, and the iterator ends. But it is an untrue end, against the honesty of `po-m2-wi06` ruling 1, and the test that covers this path (`nothingAfterward` part 2) swallows the end type (`catch {}`). | After the transport iterator returns `nil` (and before the deadline check), call `try Task.checkCancellation()`, so a cancelled read ends with `CancellationError`. Assert the end type in `nothingAfterward` part 2 (or in a new test). Can be done in this PR or ticketed to the next touch of the file (WI-M2-M6 at the latest). | Open (Minor) |
| R30-F2 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Transport/CloudTransport.swift:90-98` (contract points 3–4) | The transport contract does not say what a cancelled attempt ends with. Point 3 says every non-2xx ending is a `CloudTransportFailure`, while `CloudResponseBody` passes `CancellationError` through (D8). On the Mac, `URLSession` reports a cancelled task as `URLError.cancelled`. If WI-M2-M4 maps that to `unexpectedResponse` by point 3, a cancelled capture's body ends `otherModelError` instead of cancellation. That is harmless today for the same reason as F1, but it is a trap for the Mac work. | Add to the contract: "When the task is cancelled (`onTermination`), finish without a failure or throw `CancellationError`; never map `URLError.cancelled` to a `CloudFailureReason`." Ticket for WI-M2-M4: a `URLProtocol` test for it. | Open (Minor, ticket) |
| R30-F3 | Minor (not in this diff; flake risk) | `Packages/TendIngestion/Tests/TendIngestionTests/CloudConsentTests.swift:424` (WI-M2-09), helpers `RoutingSupport.swift:273-295` | The watch item in the dev-notes is a **real flake risk**. In my full run on 4 cores, this test reported "passed after 94.452 seconds" under `.timeLimit(.minutes(1))`. It passed only because the limit counts from when the test body starts, not from the reported start. The cause: `eventually`, `awaitConsumer` and the 200-step loop pace themselves with `Task.sleep(1 ms)` steps on the cooperative pool. They have to wait for free pool threads while the CPU-heavy property suites run in parallel (WI-M2-06/07 integration, AC-M2-24 readers, and now this PR's 4,000-case property test at 49 s). Under extra load from other containers the dev saw it hit 60 s once. The product logic is not at fault (alone: 0.26 s). This PR adds load but does not cause the problem. | Ticket to the WI-M2-09 owner, not a blocker for PR #30: take the wall-clock pacing out of the liveness waits (yield-based or event-driven waits, as `yieldUntil` here), or run the heavy property suites `.serialized`, so the 1-minute bound means something under load. Do not weaken any assertion. Optional here: cut the property test's CPU (for example, fewer cases with the same seeded coverage). | Open (ticket) |
| R30-F4 | Nit | `Packages/TendIngestion/Tests/TendIngestionTests/CloudDeadlineRetryTests.swift:528-531`, `TransportTestSupport.swift:36-40` | The property test checks `send.timeouts.resource == left` with `Seconds.of`, which repeats the formula of `CloudTiming.seconds`. That `Double` check is not independent (the decision oracle is). The table test `timeouts` with literal values covers it, so the risk is low. | Optional: compare timeouts in integer milliseconds (`Int64((x * 1000).rounded())`) against the oracle's ms values. | Open (Nit) |
| R30-F5 | Nit | `CloudResponseBody.swift:98-113` | While an attempt is silent (no chunk, no end), the 10.0 s deadline relies wholly on the transport's resource timeout. `CloudResponseBody` checks the deadline only when something arrives, which is the right choice: no race and no extra task. But AC-M2-27 (total ≤ 10.0 s) then depends on WI-M2-M4 really applying `timeoutIntervalForResource` per attempt. | Ticket to WI-M2-M4 (Planner): one `URLProtocol` test where the stub never answers and the attempt ends `timedOut` at the resource timeout. | Open (ticket) |

**Open questions in the dev-notes:**
1. **D3, where the deadline starts.** This is technical, for the Planner (`po-m2-wi14.md` note on Q1). The review adds
   one fact. `ConsentCheckedCloudModel.snapshots(for:)` (`Routing/ModelRouter.swift`) calls the provider model's
   `snapshots(for:)` only after `beginRequest`, which comes after the cloud-status and Keychain reads. So an adapter
   that reads `start` inside its own `snapshots(for:)` starts the deadline late. `start` has to be read no later than
   the routed capture is created and handed through `model(for:key:)` or the request. Planner: WI-M2-M6 DoD line
   "adapter passes the deadline start (D3) read at receipt, with a test" (as the PO note says).
2. **D6, deadline on the body.** Closed: **confirmed as built** by `po-m2-wi14.md` ruling Q2, including the "at or after"
   boundary. Brief amendment 1 is pending, applied by the developer or PO afterwards, and is not counted as missing.
3. **D9, `requestNotSent` and `unexpectedResponse` → `otherModelError`.** Closed: **confirmed** by `po-m2-wi14.md`
   ruling Q3. One outcome reason is enough, and the transport keeps the two cases apart (binding). The code already
   does this (`CloudFailureReason` has both, and the test `complete` pins 9 cases). Brief amendment 2 is pending.
   WI-M2-M4 refusal tests must assert `requestNotSent` and zero requests reaching the stub (Planner ticket).

## Checklist
- [x] Correctness vs ACs (Linux parts of AC-M2-22 "Timeouts" and AC-M2-23; Mac parts are WI-M2-M4)  - [x] Tests meaningful (would fail if code broke: 23 dev + 5 reviewer mutants killed)  - [x] Swift 6 concurrency safe (0 warnings, no unchecked escapes; R30-F1 is a semantic end-type gap, not a race)
- [x] No force unwraps / try! in product code paths  - [x] Privacy (P-1…P-4)  - [x] UX-2/UX-3 enforced in engine (UX-3: every failure has a calm typed outcome; UX-2 n.a.)
- [x] Accessibility (UI) n.a.  - [x] Performance (no main-thread work; O(1) per chunk)  - [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Every brief failure case (AC-M2-23) ends in a calm typed outcome: `noModel` with the input and the plain note before a draft, `interrupted` with drafts and the input after one. Tested for 3 providers × 9 reasons. The case names blame nobody (T-18 inspection above), and the AC-M2-12 scan finds 0. There is no overdue-like state. |
| UX-4 Design craft | n.a. | No UI; the M3 copy for `timedOut`/`otherModelError` belongs to the Designer (`po-m2-wi14.md`). |
| P-1 On-device inference | pass | Routing is unchanged. The retry stays on the same cloud route, and a cloud failure never moves to another route. |
| P-2 No data leaves device (except user iCloud) | pass | No networking in `TendIngestion` (AC-M2-09 Rule 1 scan, `Transport/` included). The protocol is neutral, and the real transport is WI-M2-M4's allowlisted file. No dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | At most two sends of the same built request per capture, both inside 10.0 s. No new request content. Nothing is sent after cancellation (turn-off) or after the deadline. `requestNotSent` stays separately provable (PO Q3). |
| P-4 Media not persisted without consent | pass | No queue, no store, no file, no log. The bytes are passed on and not kept. Nothing is retried in the background (ADR-0005). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | PR #30 at `2d626a2` (base `f1b6458`), fresh context. Mid-review FYI: `po-m2-wi14.md` (Q2, Q3 confirmed; Q1 to the Planner). |
| 2026-11-24 | Reviewer | Orchestrator → Developer (F1, F2 optional now), Planner (F2, F5, D3, Q3 tickets), WI-M2-09 owner (F3), Merge Gatekeeper | accepted (round 1: **APPROVE**) | 0 Blocker, 0 Major, 3 Minor (F1 cancel reported as a normal end; F2 transport contract silent on cancellation; F3 WI-M2-09 wall-clock flake risk, pre-existing), 2 Nit. TendIngestion 475 / TendCore 141 / TendSourceScan 63 green, 0 warnings, Linux. Reviewer mutants 5/5 killed, 1 probe. Open questions 2 and 3 closed by `po-m2-wi14.md`; 1 to the Planner (WI-M2-M6). Linux only: no Mac or device claim. |

## Round 2 — head `1c15b90` (`main` still `f1b6458`, no merge)

- **Verdict: APPROVE.** No Blocker or Major. R30-F1, F2 and F3 are closed and verified. F4 (Nit) stays open as
  optional. F5 is ticketed to WI-M2-M4. Two new Minors (F6, F7) concern WI-M2-09 code and the new test helper; they are
  tickets and do not block PR #30.
- **Scope of the round** (`git diff --stat 2d626a2 1c15b90`): `CloudResponseBody.swift` (+1 code line, comments),
  `CloudTransport.swift` (contract text), WI-M2-09 test support and tests (`RoutingSupport.swift`,
  `CloudConsentTests.swift`, `CloudConsentRaceTests.swift`), one `await Task.yield()` per outer loop in four property
  tests, `brief.md` (2 PO amendments), `dev-notes.md`, and this file (round 1, committed unchanged; I checked it equal
  to my round 1 text). No protected path is touched, and the milestone lock is unchanged (M2 `IN-BUILD`).

### Test runs (round 2, this review; `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, worktree at `1c15b90`, scratch `/tmp/rev30r2-ing`)
| Run | Result | WI-M2-09 body times (the test prints them; the time limit counts from the body start) |
|---|---|---|
| Full 1 (incl. build; my mutant and probe builds ran in parallel on the same 4 cores) | "Test run with 475 tests in 57 suites passed after 180.376 seconds", 0 warnings, exit 0 | `cancelWhilePreparing` 1.88 s; `actionDuringKeyRead` 1.82 / 1.85 / 1.85 s |
| Full 2 | "Test run with 475 tests in 57 suites passed after 137.680 seconds", 0 warnings, exit 0 | `cancelWhilePreparing` 2.95 s; `actionDuringKeyRead` 2.95 / 2.95 / 2.95 s |

In round 1 the same test reported "passed after 94.452 seconds". Now the body takes under 3 s against the 60 s limit,
even with extra load from my builds.

### Verification of the round 1 findings
| # | Check | Result |
|---|---|---|
| R30-F1 | `CloudResponseBody.swift:115`: `if chunk == nil { try Task.checkCancellation() }`. It runs before the deadline check, so a cancelled read never becomes a normal end or `timedOut`. A read that has not been cancelled is unchanged. `nothingAfterward` part 2 now waits on an event (the first chunk received), cancels, and asserts `count == 1` and the end `CancellationError`. My mutant R2-M1 (the line removed, scratch copy, `touch`ed after restore) is **killed** at `CloudDeadlineRetryTests.swift:497`. The file header is updated. | **Closed** |
| R30-F2 | `CloudTransport.swift` contract point 5: a cancelled attempt is not a failure. The transport finishes without an error or throws `CancellationError`, and must never map `URLError.cancelled` or any other cancellation to a `CloudFailureReason`. Point 3 points to the exception. This matches what `CloudResponseBody` does (D8 plus F1). WI-M2-M4 ticket with a `URLProtocol` test is recorded in the dev-notes. | **Closed** |
| R30-F3 | The waits are event-driven. `StateChanges` (a generation counter, so a change between check and wait is not lost) is signalled by every double the waits read. `eventually` checks again on each change, with a 10 s wall-clock bound (was 5,000 × ≥ 1 ms). `staysFalse` keeps the 200 ms "must not start" window, now **after** an event-driven wait that the released key read has returned (`returnedKeyCalls`). That is stricter: it proves the released step ran. **Nothing weakened:** removed `-` lines are only the polling loops, the old `settle` and the old `eventually`. `.timeLimit` count 25 → 25; `#expect` count 1,611 → 1,616 (new assertions: `readFirst`, the end type, `returnedKeyCalls` twice, `staysFalse`). Seeds, `householdsPerSeed` and every iteration count are unchanged (I diffed every seed and `0..<n` line: only the three polling loops are gone). The new yields in four property loops change no input or assertion. The full-run evidence is above. | **Closed** (see F7 for one race in the new helper) |
| R30-F4 | Kept as is, as optional. | Open (Nit, optional) |
| R30-F5 | WI-M2-M4 ticket recorded in the dev-notes (silent stub ends `timedOut` at the resource timeout). | Ticketed |

### R2-M3: is it truly equivalent? **No.**
The developer's mutant R2-M3 removes `!Task.isCancelled` from the guard in `ConsentCheckedCloudModel.snapshots(for:)`
(`Routing/ModelRouter.swift:317-320`, WI-M2-09 code, not in this diff). It survives the suite, so the developer
called it "likely equivalent". I tested that claim with a probe on the scratch copy
(`ReviewerProbeR2Tests.swift`, deleted afterwards). A `CloudModelSource` double cancels the consumer task from
inside `model(for:key:)`, which is after `beginRequest`'s last re-read of the capture. The probe ran 300 captures per
arm and counted the requests `MockCloudModel` recorded:

| Build | Consumer cancel during the model build | Turn-off started during the model build |
|---|---|---|
| HEAD `1c15b90` (guard present) | **8 / 300** requests started | 300 / 300 (the turn-off reaches the router actor only after the request has started; it is then cancelled as in-flight, which AC-M2-18 allows) |
| R2-M3 (guard removed) | **298 / 300** requests started | 298 / 300 |

So the guard does real work. In 97 % of these interleavings it is the only thing that stops a request after a cancel
that landed while the request was being prepared. R2-M3 is a **surviving, non-equivalent mutant**, which means the
WI-M2-09 tests have a gap. The probe also shows that HEAD itself still starts a request in about 3 % of these runs:
the consumer's cancellation reaches the forwarding task only when the pipeline's stream ends, which can be after the
guard. The transport stream is then cancelled at once. → R30-F6.

### Brief amendments vs `po-m2-wi14.md` (word for word)
I extracted the quoted text of "Brief amendment 1" and "Brief amendment 2" from the PO note and the brief at
`1c15b90`, normalised only the whitespace (line wrapping), and compared them as strings. **Both match exactly** (434 and
454 characters). Both are in the right places: amendment 1 directly after "…from the moment the pipeline receives
the input." in AC-M2-22 "Timeouts", and amendment 2 as a new bullet directly after "No outcome or reason name contains
a banned token." in AC-M2-23. The only removed brief line is the re-wrapped "moment the pipeline receives the input.".
No AC text is deleted or weakened.

### Findings, round 2
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R30-F6 | Minor (WI-M2-09 code, not in this diff; ticket) | `Packages/TendIngestion/Sources/TendIngestion/Routing/ModelRouter.swift:317-320`; tests `CloudConsentTests.swift`, `CloudConsentRaceTests.swift` | R2-M3 is not equivalent (probe above: 8/300 → 298/300). No test kills it, so a later change could drop the `!Task.isCancelled` guard unnoticed. That would break AC-M2-18 "a capture the user cancels while its request is being prepared sends nothing" in the common interleaving. Separately, HEAD still starts a request (then cancels it at once) in about 3 % of cancels that land during the model build. That is the residual window between the consumer's cancel and the forwarding task seeing it. | WI-M2-09 owner (via the Planner): (1) add a test that kills R2-M3, for example a `CloudModelSource` double that cancels the consumer inside `model(for:key:)`, or a seam that makes the cancellation visible to the forwarding task deterministically; (2) decide whether the ~3 % residual window must close for AC-M2-18 (for example, the forwarding task re-checks after the model is built and before `snapshots(for:)`, or the adapter honours IngestionModel contract rule 3 in WI-M2-M6) and record it. Ask the PO only if the reading of AC-M2-18 for a cancel at the very moment the request starts is unclear. Do not mark R2-M3 equivalent. | Open (ticket) |
| R30-F7 | Minor (test helper; liveness only, never a false pass) | `Packages/TendIngestion/Tests/TendIngestionTests/RoutingSupport.swift:302-322` (`StateChanges.wait`) | A timeout can be lost. The `bound` task may fire `resume(id)` before the waiter has registered its continuation (for example, when the limit passes between `eventually`'s `now >= limit` check and the registration). `resume` then finds nothing, and the waiter waits for the next `changed()` from any test. If none comes, the test hangs to its 60 s limit and fails. The window is microseconds, but it is the same class of flake that F3 removed. | Record an "expired" flag per id in `resume` when no waiter is registered yet, and resume at once on registration if it is set (as `ManualClock` does with `sleepCancelled`). Next touch of the file; not blocking. | Open (ticket) |

### Checklist (round 2)
- [x] Correctness vs ACs (F1 end type; contract point 5; brief amendments match the PO note word for word)  - [x] Tests meaningful (R2-M1 killed; no assertion, seed, count or time limit weakened)  - [x] Swift 6 concurrency safe (0 warnings; F7 is a test-helper liveness race)
- [x] No force unwraps / try! in product code paths  - [x] Privacy (P-1…P-4; F6 ticketed for WI-M2-09)  - [x] UX-2/UX-3 enforced in engine
- [x] Accessibility (UI) n.a.  - [x] Performance (WI-M2-09 bodies < 3 s under full parallel load)  - [x] No new dependency without ADR

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | A cancelled read now ends as cancellation, never as a finished body (F1), so no outcome claims what did not happen. Brief amendment 1 makes the deadline end calm, with the words kept. Case names are unchanged; AC-M2-12 scan 0. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No networking in `TendIngestion`; no dependency. |
| P-3 Cloud AI opt-in, minimised | pass (watch F6) | This PR's code sends nothing after cancel or deadline, and the cancellation contract is now explicit (F2). F6: in WI-M2-09's forwarding path, a cancel that lands during the model build can still start a request that is cancelled at once (~3 % in the probe), and the guard that prevents most of these has no killing test. Ticketed, not this PR's code. |
| P-4 Media not persisted without consent | pass | Nothing queued or stored. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | Round 2 at `1c15b90` (`main` `f1b6458`): verify F1, F2, F3, R2-M3 equivalence, brief amendments; two full runs. |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper; Planner (F6, F7, F5 and round 1 tickets); WI-M2-09 owner (F6) | accepted (round 2: **APPROVE**) | F1, F2, F3 closed with evidence. Two full TendIngestion runs: 475/475, 0 warnings; WI-M2-09 bodies 1.8–2.9 s. R2-M1 killed. R2-M3 **not equivalent** (probe 8/300 vs 298/300) → F6 ticket. F7 helper race ticket. Brief amendments 1–2 match `po-m2-wi14.md` word for word. Linux only. |
