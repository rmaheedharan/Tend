# M2 Code Review — WI-M2-09, PR #24 (`m2/routing-and-consent`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1 (head `40ac5b4`)
- **Requirements:** FR-A1, P-1, P-2, P-3, P-4, UX-3. ACs: ● **AC-M2-19** (full), ○ **AC-M2-18** (Linux part: consent,
  route, cancel, in-memory key store), ○ **AC-M2-10** (route level) (plan WI-M2-09; plan "Route matrix").
  Related: AC-M2-21 (`APIKey` formatting clause only; the rest is WI-M2-M5), AC-M2-22/23 (WI-M2-14, not here),
  AC-M2-09 / AC-M2-12 (scans, regression).
- **Commit reviewed:** `40ac5b4`, diff `origin/main...HEAD` (base `00928fc`). Four new source files under
  `Packages/TendIngestion/Sources/TendIngestion/Routing/`, three new test files, `dev-notes.md`. No existing source
  file changed, no protected path, no dependency, Foundation only (ADR-0006).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. WI-M2-09 is M2 work; DoR met (WI-M2-06 merged).
- **Inputs:** CLAUDE.md; PRD privacy laws (via CLAUDE.md §2); brief.md (Definitions "Cloud model", "Route", "Draft
  stream events", "Plain note"; AC-M2-10, 18, 19, 22, 23); plan.md (WI-M2-09, WI-M2-14, WI-M2-M4 rows, "Route matrix"
  S0–S8); ADR-0005 Decisions 1, 2, 5; ADR-0006; dev-notes.md WI-M2-09. Project notes: `po-q21-q22.md`,
  `owner-decisions.md`, and **`po-m2-wi09.md`** (PO rulings on this PR's three open questions, received during the
  review: all three accepted as built, no code change; brief amendments to follow as a doc-only change).

## Summary
The routing layer is small, readable and correct on the main paths. `RouteRules.route` is ADR-0005 Decision 1 exactly
(available → on device unless "always cloud" with cloud on; unavailable → `cloud(X)` if cloud on, else `none`; "always
cloud" with cloud off ignored). `ModelRouter.cloudStatus` implements the Definitions rule (selected provider with
consent **and** key, not blocked this session), deletes orphan keys first and fails closed on every store error. One
`RoutedModel` per capture means an on-device error can never reach the cloud (P-1, AC-M2-10). Turn-off and remove-key
block first, end in-flight captures synchronously on the actor, then clear the stores and report the first store
error. `APIKey` hides its text in every formatting path I tried.

The tests are strong: 340 plan cells and 2,560 exhaustive cells against two oracles that do not call production
code (`planRoute` written from the plan table; the 2,560-cell oracle written from the Definitions), plus the
restored fixtures (i)–(iii), failing stores, consumer cancel, and turn-off while in flight. All waits are bounded.

One rule the developer names as the key reentrancy guard is **untested**: the re-check in `beginRequest` after the key
read (`ModelRouter.swift:182`). If it is removed, a turn-off that runs while the key is being read lets the request
start afterwards, which breaks AC-M2-18 (c). No test catches that (my mutant A survived). This is a missing test for
an AC clause on a concurrency path, so it is **Major** (OPERATING_MODEL §6). The code is right today; the fix is one
test. The other findings are Minor or Nit.

PO open questions 1–3 (D5 switch provider cancels, selection kept on turn-off, `cancelled` for a not-yet-started
request): accepted as built by the PO (`po-m2-wi09.md`). The code and tests match those rulings. Closing the
dev-notes questions and making the brief amendments is a doc-only follow-up, not a merge condition here.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R24-F1 | **Major** | `Packages/TendIngestion/Sources/TendIngestion/Routing/ModelRouter.swift:182` (test gap: `Tests/TendIngestionTests/CloudConsentTests.swift`) | The re-check after the awaits in `beginRequest` (`!current.ended, current.continuation == nil`) is what stops a request when cloud is turned off **while the key is being read** (AC-M2-18 (c), (d); P-3). No test turns cloud off during that window. Mutant A (guard reduced to `guard let key, var current = captures[captureID]`) passes all 40 routing tests. `cancelWhilePreparing` (line 348) covers the user cancelling, but there `release` removes the capture, so the `captures[captureID]` lookup fails anyway and the `ended` check is never reached. The dev notes say "every check that matters is read again after its last await"; this one is only kept by code, not by tests. | Add a test: cloud on for X, the `SuspendingKeyStore` holds `key(for:)`, a capture is routed and its preparation is waiting, `turnCloudOff()` (and separately `removeKey(for: X)` and `select(Y)`) runs, then the key read is released. Expect `finished(.cancelled(route: .cloud(X)))` only, `afterFinished == nil`, and `transport.requestCount == 0`. Use the bounded helpers (`awaitConsumer`, `eventually`) so it fails on an assertion, not a hang, and show in dev-notes that it kills mutant A. My probe of this shape passes on the PR head (0 requests, `cancelled`); on mutant A it hangs, because the request does start after the turn-off. | Open |
| R24-F2 | Minor | `ModelRouter.swift:201-209`, `:175-189` | A turn-off while the key read is pending does not end the consumer "at once" (ADR-0005 Decision 2): `endCaptures` can only finish a continuation that `beginRequest` has already stored, so the consumer waits until the key store returns. Probe REV2: after `turnCloudOff()` returned, the consumer had no `finished` for 1 s while the key read was held; it ended `cancelled` with 0 requests when the read was released. With a Keychain this is normally milliseconds, so the outcome is right and only the timing differs. | Ticket (this PR or WI-M2-M5): register the snapshot continuation with the capture when the stream is created (before `beginRequest` awaits), so `endCaptures` ends it at once. Otherwise state the bound in dev-notes. |  Open (ticket) |
| R24-F3 | Minor | `ModelRouter.swift:119-129` | `turnCloudOn` lifts the block (`blocked.remove`) after its awaits without checking whether a `turnCloudOff` / `removeKey` ran meanwhile. Probe REV: with a consent store whose `recordConsent` is slow, `turnCloudOn(X)` started, `turnCloudOff()` started and **returned without error**, then `turnCloudOn` finished: `cloudStatus() == .on(X)`. This is a legal ordering (the turn-on finished last), and the in-memory actors keep FIFO order, so it does not break an AC today. A real non-actor store (Keychain, durable consent store) can reorder writes, and "off returned, then cloud is on" is not what a user who tapped off expects. | Ticket for M3 / WI-M2-M5: either the router serialises Settings actions (an epoch counter: `turnCloudOn` rolls back and throws if a turn-off or remove-key for X started after it began), or M3 Settings must never send overlapping actions and says so in its brief. Record the choice. | Open (ticket) |
| R24-F4 | Minor | `ModelRouter.swift:75` | The `blocked` re-read after the awaits in `cloudStatus` is not tested on its own. Mutant D (block read before the awaits) survives, because `beginRequest`'s second `cloudStatus` and the cleared stores hide it. This is defence in depth, so it is Minor. | Add a test with stores that cannot clear or delete (as in `turnOffWithFailingStores`) where the turn-off runs while `cloudStatus` waits on a store read, and expect `.off`. Or note it as covered only by R24-F1's test. | Open |
| R24-F5 | Minor | `ModelRouter.swift:121-126` | The rollback in `turnCloudOn` (clear the consent again if the key cannot be saved) is untested. Mutant K (rollback removed) survives. The behaviour fails closed anyway (consent without a key is cloud off, restored (ii)), but it is a documented rule. | Add a test with a key store whose `save` throws: `turnCloudOn` throws that error, the consent record is cleared, `cloudStatus() == .off`. | Open |
| R24-F6 | Nit | `ModelRouter.swift:192-199`, `RoutedDraftEvents.swift:318` | `release` and "unknown counts as ended" have no test (mutants H and I survive). H can only be reached after `isDone`, so it is equivalent. I is only a leak (D10). | Optional: a test reading a capture to `finished` and checking the router holds no entry (an internal count). | Open (optional) |
| R24-F7 | Nit | `ConsentCheckedCloudModel`, `ModelRouter.swift:239-245` | A turn-off that runs between the `!Task.isCancelled` check and `model.snapshots(for:)` lets the provider stream start inside an already cancelled task. That is the linearisation point of "in flight" and is acceptable, but it puts a duty on the adapters. | WI-M2-M6 adapter contract: a provider stream started in a cancelled task cancels its transport at once and sends nothing (add to the existing IngestionModel adapter contract, part 3). | Open (WI-M2-M6) |

Not findings (checked and fine):
- Route rule vs ADR-0005 Decision 1 and the plan matrix: exact. `none` only for unavailable + cloud off; `cloud(Y)` never
  for an unselected Y (S5, S6, S8 cells; 2,560-cell oracle).
- Orphan-key deletion (T-14): every provider, not only the selected one (mutant C killed, 1,188 issues); a key with
  consent for an unselected provider is kept (S5, S7).
- Store errors fail closed: read errors give `.off`; an orphan key that cannot be deleted never turns cloud on (D2).
- Turn-off order: block and `endCaptures` before any await (mutant F, moving `endCaptures` after the stores, is killed).
- Request start re-reads cloud status and reads the key only for the routed provider (mutant J killed, D6).
- Forwarding `Task` is cancelled from `onTermination` (mutant E killed). No `@unchecked Sendable`, no
  `nonisolated(unsafe)`, no lock, clock or dispatch queue in product code. Test helpers use `Mutex` (Synchronization).
- `RoutedDraftEvents`: `Failure == Never`, `finished` exactly once and last, one actor hop per cloud event only.
  Replacing an inner `noModel`/`interrupted` with `cancelled` after a cloud-access end matches PO ruling 3
  (`po-m2-wi09.md`) and the amended AC-M2-18 (d).
- `APIKey`: `description`, `debugDescription`, `customMirror` with no children; not `Hashable`, not `Codable`;
  `CloudStoreError` has no payload. Beyond the developer's 10 forms, I checked an enum payload, `String(reflecting:)`
  of that enum, a tuple interpolation, a dictionary value and `dump` of an enum: none showed the text (probe REV3).
- UX-3: `notAccessibleNow`, `storeUnavailable`, `onDeviceFirst`, `alwaysCloud`, `off`, `on`, `CloudAccessEnded` are
  calm; AC-M2-12 vocabulary scan 0 violations.
- `none` branch with the model available (`ModelRouter.swift:99-103`) is unreachable and stays on device, never cloud.

## Mutation check (Reviewer's own, on a scratch copy; never the worktree)
Run with `--filter "Route|Consent|CloudTurnOff|CloudStore|RouterNoModel|Reviewer"`, `-warnings-as-errors`, in
`swift:6.2-noble`, with a 600 s timeout per mutant. Baseline: 40 tests passed (38 PR tests + 2 reviewer probes).

| # | Mutant | Result |
|---|---|---|
| A | `beginRequest` drops the re-check after the key read | **survived** (R24-F1). My probe REV2 (the R24-F1 shape) detects it, but only as a hang: the request starts after the turn-off on the holding transport and the probe's unbounded `consumer.value` never returned (killed by hand after 20 min). The required test must use the bounded `awaitConsumer` / `eventually` helpers and assert `requestCount == 0`, so the mutant fails on an assertion |
| B | `RoutedDraftEvents` checks before the inner `next` | invalid (compile error), not counted |
| C | orphan deletion only for the first provider | killed (1,188 issues) |
| D | `cloudStatus` reads `blocked` before the awaits | **survived** (R24-F4) |
| E | no `onTermination` cancel of the forwarding task | killed (transport ends not `cancelled`) |
| F | turn-off ends captures after the store awaits | killed (turn-off in flight, failing stores) |
| G | unavailable + cloud on + on device first gives `none` | killed (536 issues) |
| H | unknown capture counts as not ended | survived, equivalent (R24-F6) |
| I | no `release` on `finished` | survived, leak only (R24-F6) |
| J | key read without the cloud-status check | killed (selection changed behind the router) |
| K | `turnCloudOn` without consent rollback | **survived** (R24-F5) |

## Tests run (Reviewer, PR head `40ac5b4`, Linux, `swift:6.2-noble`, Swift 6.2, `-Xswiftc -warnings-as-errors`)
| Command | Result |
|---|---|
| `swift test --package-path Packages/TendIngestion --scratch-path /tmp/rev24-ing` | `✔ Test run with 232 tests in 30 suites passed after 31.105 seconds.` 0 warnings |
| `swift build --package-path Packages/TendIngestion --scratch-path /tmp/rev24-ing` | `Build complete!` |
| `swift test --package-path Packages/TendSourceScan --scratch-path /tmp/rev24-scan` | `✔ Test run with 63 tests in 4 suites passed after 3.157 seconds.` |
| `swift test --package-path Packages/TendCore --scratch-path /tmp/rev24-core` | `✔ Test run with 141 tests in 18 suites passed after 137.627 seconds.` |
| `Tools/TendTools` build | not present on this branch (CI step exits 0 when `Package.swift` is missing) |
| Reviewer probes (scratch copy): REV (on overlapping off), REV2 (turn-off during key read), REV3 (`APIKey` nested forms) | 3 passed. REV: `on(openAI)` after off returned (R24-F3). REV2: no `finished` within 1 s before the key read was released (R24-F2), then `cancelled`, 0 requests |

Not verified: Darwin actor scheduling and `AsyncThrowingStream` termination (plan B2, owner-run Mac); the real
Keychain (WI-M2-M5).

## Checklist
- [x] Correctness vs ACs (AC-M2-19 full; AC-M2-18 and AC-M2-10 Linux parts) — except the test gap in R24-F1
- [ ] Tests meaningful (would fail if code broke) — R24-F1 (Major), R24-F4, R24-F5
- [x] Swift 6 concurrency safe (no data race; reentrancy notes R24-F2, F3, F7)
- [x] No force unwraps / try! in product code paths
- [x] Privacy (P-1…P-4)
- [x] UX-2/UX-3 enforced in engine (UX-2 n.a.; UX-3 calm names)
- [x] Accessibility (UI) — n.a., no UI
- [x] Performance (main thread, allocations, 120 Hz) — one actor hop per cloud event; no main-actor work
- [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; turning cloud on is a Settings action (M3). |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Case names describe the store or setting, never the person; turn-off gives `cancelled`, not a failure; scan 0 violations. PO ruling 3: M3 keeps the words when the user did not cancel. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | ADR-0005 Decision 1 exact (340 + 2,560 cells); an on-device stop never asks the cloud (16 reasons × 3 states, 0 requests); one model per capture. |
| P-2 No data leaves device (except user iCloud) | pass | No networking in `TendIngestion` (AC-M2-09 scan 0 violations); the transport is a test recorder only. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | concern | Rules are correct (off by default, consent **and** key, orphan deletion, fail closed, turn-off blocks and cancels). Concern only because the turn-off-during-key-read guard is untested (R24-F1) and overlapping turn-on/turn-off can end "on" (R24-F3, ticket). |
| P-4 Media not persisted without consent | pass | Nothing written; a cancelled capture leaves the repository unchanged; `APIKey` cannot reach a log through formatting. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Reviewer | accepted (H4) | PR #24 head `40ac5b4`, worktree `/home/user/wt-rev24`. |
| 2026-11-22 | Product Owner (via Orchestrator) | Reviewer | noted | `po-m2-wi09.md`: Q1–Q3 accepted as built, no code change; brief amendments and dev-notes closure as doc-only follow-up. Checked: code matches the rulings. |
| 2026-11-22 | Reviewer | Developer (via Orchestrator) | returned (round 1) | CHANGES REQUIRED: R24-F1 Major (test for the turn-off-during-key-read re-check; must kill mutant A). Minor R24-F2…F5 to fix or ticket; Nits F6, F7 optional / WI-M2-M6. Tests green on Linux: TendIngestion 232, TendSourceScan 63, TendCore 141. |
