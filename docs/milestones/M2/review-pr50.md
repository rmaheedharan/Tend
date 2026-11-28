# M2 Code Review — PR #50 (`m2/cloud-adapters`, head `e039a4d`, code commit `035378e`, base `main` `65c06cd`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **CHANGES REQUIRED**  ·  **Round:** 1
- **Work item:** WI-M2-M6 "Cloud adapters end to end" (plan row WI-M2-M6, MS-2; plan "Real provider recordings").
- **IDs:** AC-M2-24 (main), AC-M2-22 "Timeouts" and AC-M2-23 (through the transport), AC-M2-27 (total ≤ 10.0 s
  depends on the deadline), Q12, Q18, Q22, T-17, T-19; ADR-0005; FR-A1; P-1, P-2, P-3, P-4; UX-3.
- **Scope:** `git diff 65c06cd e039a4d`. It holds 24 files. Five are new `TendAI/Cloud` sources (`CloudIngestionModel`,
  `OpenAIIngestionModel`, `AnthropicIngestionModel`, `GeminiIngestionModel`, `CloudAdapters`), one is the new test
  file `CloudAdapterTests.swift` (12 tests, 50 cases), and the rest are the `dev-notes.md` section and the Mac evidence
  record `evidence/mac/WI-M2-M6/`. Nothing changes in `TendCore`, `TendIngestion`, `TendSourceScan`, `Fixtures/`,
  `project.yml` or any protected path.
- **Milestone lock:** M1 is ACCEPTED and M2 is IN-BUILD (`STATUS.md`), so this M2 work item is allowed.

## Summary

The adapters are small and clean. They match the adapter contract in `IngestionModel.swift`. Each one sends exactly
the golden request, with the key only in the auth header. Each reads `CloudResponseBody` into `ProviderStreamReader`,
ends with a neutral `ModelStopReason`, has no Tool, sends nothing when created in a cancelled task, and releases the
transport on termination. The tests are real: I rebuilt the five sources and the test file on Linux, and my mutants
were killed (see the mutation table). The evidence record checks out. All 16 SHA-256 lines verify. It names `035378e`,
the tree was clean before and after, there is no personal data, and both commits are by `Claude <noreply@anthropic.com>`.
The Gemini recording is valid for AC-M2-24: all 14 events report `modelVersion` `gemini-3.5-flash-lite`, which is the
pinned ID.

Two Majors block the merge:

- **R50-F1.** The 10.0 s deadline starts too late. The adapter reads `clock.now` only inside its own
  `snapshots(for:)`. The router calls that only after the consent check and the Keychain read. The brief (AC-M2-22,
  Q22) and `CloudResponseBody`'s own contract say the deadline runs from "the moment the pipeline receives the input".
  This exact point was handed to WI-M2-M6 as a ticket (review WI-M2-14 open question 1; dev-notes WI-M2-14 hand-off
  table: "adapter passes the deadline start (D3) read at receipt, with a test"). It was neither built nor mentioned,
  and no test checks it: a mutant that moves `start` 30 s later survives.
- **R50-F2.** The owner-pending recording commands can put the owner's API key on screen and into the shell history
  file. On macOS the default shell is zsh, and an interactive zsh does not treat `#` as a comment unless
  `INTERACTIVE_COMMENTS` is set. The line `read -rs TEND_KEY   # OpenAI key, then Return (nothing is shown)` fails
  with `zsh: unknown sort specifier`, so `read` never runs. The key the owner then types goes to an ordinary prompt,
  where it is echoed, run as a command and saved to `~/.zsh_history`. I reproduced this with zsh 5.9.

## AC and rule check

| Item | Code | Test (Mac B4; re-run by me on Linux where marked) | Result |
|---|---|---|---|
| AC-M2-24: drafts flow through the same `IngestionModel` contract and draft stream events as on device | `CloudIngestionModel.swift:40-79` yields `ProviderStreamReader` snapshots, then `finish()`. A `ProviderStreamError` ends with its `stopReason`, a `ModelStopReason` passes through, a cancel finishes quietly, and anything else is `otherModelError` (contract 1) | `syntheticFixture` (33 cases × 4 cuts: whole, 64, 7, 1 byte) checks the README outcome, draft and skip counts, and event-for-event equality with the reader read directly. `geminiRecording` uses 3 cuts. Both pass on Mac B4 and in my Linux harness | pass |
| AC-M2-24: at least one real recording per provider (T-19) | Gemini only (`gemini/recorded-outcome-sample.sse`). OpenAI and Anthropic are owner-pending | Gemini: the served model equals the pinned ID in 14/14 events, no `thoughtsTokenCount`, and no header or key text (`grep -i 'sk-\|x-api-key\|x-goog-api-key\|authorization\|AIza\|bearer'`: 0) | **open**: AC-M2-24 cannot be PASS yet (R50-F4) |
| AC-M2-24: a cloud model is never given the duplicate Tool | No Tool anywhere in the five types. `lookupQueries` stays empty | `noTool` (the `Mirror` half is weak, R50-N2) | pass |
| ADR-0005 Decision 3 / Q12: only the capture, room names and shortlist titles | `CloudPayloadBuilder.request(CloudPayloadInput(request), …)` (`:51`) | `goldenRequest` (body and every header line byte for byte, × 3 providers). `shortlistInRequest`: the shortlisted title and room name are present, the title that is not shortlisted is absent, no UUIDs, and the request equals the builder's | pass |
| Key only in the auth header; never in the URL or a log | The key goes only to the builder. `CloudRequest`'s description lists header *names* only (seen in a failure message from my mutant m1: `headers: Authorization, Content-Type, …, body: 4205 bytes`). No logging in the new files. Gemini has `alt=sse` only in the query | `goldenRequest` head lines | pass |
| Q18: pinned model, structured streaming, fixed sampling, least reasoning | `CloudModel.defaultModel(for:)` | `q18` × 3 matches D-049 (OpenAI no `temperature`, `reasoning_effort: none`; Anthropic `temperature: 0`, no `thinking`; Gemini `thinkingLevel: minimal`, no `temperature`). Condition 1 (current) is shown live only for Gemini, which is disclosed | pass for code. Conditions 1 and 5 for OpenAI and Anthropic wait on the recordings |
| AC-M2-22 deadline from receipt (Q22, T-17) | `let start = clock.now` inside `snapshots(for:)` (`:48`). This runs after `ModelRouter.beginRequest`'s `cloudStatus()` and Keychain read (`ModelRouter.swift:249-259`) | none. Mutant m10 (`start` + 30 s) **survives** | **fail (R50-F1)** |
| AC-M2-22/23 via the transport | `CloudResponseBody` (WI-M2-14, unchanged) | `keyNotAccepted` (no retry), `retryOnce` (503, then the body; same request twice) | pass |
| Contract 3: cancel releases the transport, and a stream made in a cancelled task sends nothing | `:44-47` guard; `:78` `onTermination` cancels the reading task | `cancellation` (`terminations == 1`), `createdCancelled` (the stream is held, not read) | pass |
| Routing (P-1) | `CloudAdapters.model(for:key:)` builds only the provider it was asked for | `adapterChoice` × 3; `routerEndToEnd` (on device unavailable, Gemini on, route `cloud(gemini)`, 3 drafts) | pass |
| Frozen eval files | — | `git diff 65c06cd e039a4d -- Fixtures` is empty. `sha256sum -c MANIFEST.sha256` in `Fixtures/M2/eval`: 4/4 OK | pass |
| No existing test weakened | — | The diff adds one test file and changes no other test | pass |

## Runs (this review)

| Run | Where | Result |
|---|---|---|
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` at `e039a4d`, scratch `/tmp/m6c` | Docker `swift:6.2-noble` | 141 tests in 18 suites passed, exit 0, 0 warnings |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` at `e039a4d`, scratch `/tmp/m6i` | Docker `swift:6.2-noble` | 580 tests in 68 suites passed, exit 0, 0 warnings. AC-M2-09 scan: 77 files, 0 violations. AC-M2-12: 77 files, 9 exempted, 0 violations |
| Linux harness: the five new sources (minus the `CloudAdapters()` initialiser that needs the Mac-only `CloudHTTPTransport`), `CloudAdapterTests.swift` unchanged, plus two test-only helpers from `OnDeviceTestSupport`/`OnDeviceModelTests` | Docker `swift:6.2-noble`, `-warnings-as-errors` | 12 tests in 1 suite passed, 0 warnings. This means the Foundation-only adapter code also builds clean under Swift 6.2 strict concurrency |
| Mac record `evidence/mac/WI-M2-M6/` | read only | 16/16 SHA-256 lines verify. B0 names `035378e843c2…` and B0/B9 `git status --porcelain` are empty. `git diff --name-only 035378e e039a4d` is all under `docs/`. B4 shows 108 tests in 18 suites, 0 `✘`, with the 12 new tests and `syntheticFixture` "with 33 test cases". The logs hold only `$HOME`/`$REPO`/`$USER`/`$TMPDIR` tokens, `FAKETEAMID` and "Sign to Run Locally": no personal data |

### Mutation table (my mutants, Linux harness, one at a time on a scratch copy)

| # | Mutant | Result |
|---|---|---|
| m1 | Remove the "created in a cancelled task" guard | killed (`createdCancelled`) |
| m2 | `onTermination` does not cancel the task | killed (`cancellation`, `terminations == 0`) |
| m3 | Drop room names from the payload input | killed (`shortlistInRequest` × 3) |
| m4 | Call `reader.finish()` but do not yield its snapshot | **survived** (R50-I1) |
| m5 | `ProviderStreamError` flattened to `otherModelError` | killed (`syntheticFixture`) |
| m6 | Gemini adapter builds the OpenAI model | killed (`syntheticFixture` index 22, `noTool`) |
| m7 | `ModelStopReason` flattened to `otherModelError` | killed (`keyNotAccepted`) |
| m8 | `start` 9 s earlier | killed (`retryOnce`; the test crashes on `requests[1]`, R50-N1) |
| m9 | A cancel ends with `otherModelError` instead of a quiet finish | survived. This is equivalent: the consumer has already gone, and the pipeline reports `cancelled` either way |
| m10 | `start` 30 s later (deadline 40 s) | **survived** (R50-F1) |

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R50-F1 | **Major** | `Packages/TendAI/Sources/TendAI/Cloud/CloudIngestionModel.swift:48` (and the header, `:9-10`) | **The deadline starts after the consent check and the Keychain read, not at receipt (AC-M2-22 "Timeouts", Q22, T-17; AC-M2-27).** The brief (`brief.md:845-846`) and `CloudResponseBody.swift:5-6` define the 10.0 s deadline "from the moment the pipeline receives the input". The adapter reads `clock.now` inside its own `snapshots(for:)`. `ConsentCheckedCloudModel` calls that only after `ModelRouter.beginRequest`, which awaits `cloudStatus()` (two store reads) and `keys.key(for:)` (the Keychain). So the time spent on routing and the Keychain is outside the deadline. A body can then legally run until receipt + 10 s + that time, which breaks the AC-M2-27 total (≤ 10.0 s from receipt) that the deadline exists to protect. The file header changes the definition to "from the moment the capture reached this model" without a ruling. This exact point was ticketed to this work item (review-WI-M2-14 open question 1; dev-notes WI-M2-14 hand-off table row WI-M2-M6: "`start` must be read before the Keychain read … An adapter that reads a fresh clock in its own `snapshots(for:)` … starts the deadline late"). It is not addressed or listed in the WI-M2-M6 dev-notes. No test pins it: my mutant m10 (`start` + 30 s) survives every test. | Read the deadline start no later than when the routed capture is created, before the cloud-status and Keychain reads (the WI-M2-14 dev-notes D3 point: `ModelRouter.events(input:…)`), and pass it to the adapter. For example, carry an instant through `CloudModelSource.model(for:key:…)` or the routed capture. The router stays clock-free if the instant comes from the adapters' injected clock, for example via a `CloudModelSource` "receipt mark" taken at route time. That design choice is the Developer's (or the Planner's) and needs no product decision. Add a test on a manual clock where the consent or key store takes simulated time before `beginRequest` returns, and assert that the first attempt's `CloudAttemptTimeouts.resource` equals 10.0 s minus that time (and that m10 is killed). Correct the header at `:9-10`. If the team instead wants "from the model call" as the meaning, that needs a PO ruling recorded in `DECISIONS.md` and a brief amendment, not a silent reinterpretation. | Open |
| R50-F2 | **Major** | `docs/milestones/M2/dev-notes.md:6352-6365` | **The owner's recording commands can echo the API key and store it in shell history (P-3 key hygiene; plan "Real provider recordings": "the key is typed, never echoed, never in shell history").** The commands are meant to be pasted into the Mac's shell, and the macOS default shell is zsh. Interactive zsh treats `#` as a comment only when `INTERACTIVE_COMMENTS` is set, and it is off by default. Probe (zsh 5.9, `zsh -f -i`, commands on stdin): `read -rs TEND_KEY   # OpenAI key, then Return (nothing is shown)` prints `zsh: unknown sort specifier` and `read` does not run. The next typed line (the key) prints `zsh: command not found: <key>`, so it is echoed on screen and written to `~/.zsh_history`. The Anthropic line prints `not an identifier: #` with exit 1. Pasted as a block, the first `curl` also runs with an empty bearer token. Two lesser points: (a) `-H "Authorization: Bearer $TEND_KEY"` puts the key in `curl`'s argv while it runs, where other local processes can see it with `ps`; (b) the post-check greps for key shapes, not for the key itself. | Make the block safe in default interactive zsh and in bash. Remove every inline `#` comment from the code block (put the instructions in prose above it). Use a prompt that works in both shells, for example `printf 'OpenAI key: '; read -rs TEND_KEY; echo`, and stop if it is empty (`[ -n "$TEND_KEY" ] \|\| { echo "no key read"; return 1 2>/dev/null \|\| exit 1; }`). Better still, ship it as a small script run with `zsh script.sh` or `bash script.sh`, where comments are honoured and nothing enters interactive history. Pass the header from stdin rather than argv (`printf 'Authorization: Bearer %s\n' "$TEND_KEY" \| curl -H @- …`, and likewise `x-api-key`). Re-run the probe in zsh and in bash and note the result in dev-notes. | Open |
| R50-F3 | Minor | `docs/milestones/M2/dev-notes.md:6354, 6360, 6368-6369` | `-D ~/tend-rec-out/<p>.status` saves the response headers to disk. For OpenAI and Anthropic these include account or organisation identifiers. T-19 and the plan say "Only the response stream is saved". The note "never the `.status` file when it holds account identifiers" leaves the file on disk anyway. | Drop `-D` and print only the status code (`-w '%{http_code}\n'`, or `-o file -w`), or delete the `.status` files in the same block after reading. Write out the Gemini command too, as the plan asks for all three ("WI-M2-M6 writes the three commands into `dev-notes.md`"), even though it is not needed again. | Open |
| R50-F4 | Minor | `docs/milestones/M2/dev-notes.md:6348-6350`; plan row WI-M2-M6 | The owner's choice "Gemini now, others later" leaves AC-M2-24's "at least one real recording per provider" (T-19) and Q18 conditions 1 and 5 for OpenAI and Anthropic open. The choice is not recorded in `DECISIONS.md` or the plan. Merging this PR must not be read as closing WI-M2-M6 or AC-M2-24. | Record the owner's choice and the follow-up (owner-run recordings, plus adding them to `CloudAdapterTests` and `ProviderStreamRecordingTests`) in `DECISIONS.md` or the plan's WI-M2-M6 row (PO or Planner). The Tester keeps AC-M2-24 not PASS until both recordings are in. | Open |
| R50-N1 | Nit | `Packages/TendAI/Tests/TendAITests/CloudAdapterTests.swift:314` | `transport.requests[0] == transport.requests[1]` traps (index out of range) when only one request was sent, which kills the whole test process (seen with m8). | `try #require(transport.requests.count == 2)` before indexing. | Open |
| R50-N2 | Nit | `CloudAdapterTests.swift:293-294` | The `Mirror` check looks only at the top-level labels of the provider wrapper (`cloud`), so it cannot see a Tool held in `CloudIngestionModel`. The "no Tool" guarantee comes from the types, so this half proves little. | Reflect into the `cloud` child as well, or drop the `Mirror` half and say the guarantee is by type. | Open |
| R50-N3 | Nit | `evidence/mac/WI-M2-M6/README.md:8`; `dev-notes.md:6392-6393` | The README says the run was on 2026-11-27, but the log timestamps (Mac local time) and the hand-off log say 2026-11-28. | State the time zone, or use one date. | Open |
| R50-N4 | Nit | `CloudIngestionModel.swift:57-78` | `onTermination` is set after the reading `Task` starts. This is safe today, because the stream is not handed out until the build closure returns, and a handler set after an early finish has nothing left to cancel. Setting the handler first is the usual pattern and reads more obviously correct. | Optional: create the task, then set `onTermination` before anything can yield (or comment why the order is safe). | Open |
| R50-I1 | Info | `CloudIngestionModel.swift:64`; `dev-notes.md:6331` | My mutant m4 (call `finish()` but drop its snapshot) survives: with complete JSON, `finish()`'s snapshot equals the last appended one, so the pipeline's events do not change. The dev-notes A1 "no `finish()` snapshot" was killed, so A1 must have removed more, for example the `finish()` call and its end checks. That mutant is not the same as m4. Not a defect. | Optional: say exactly what A1 changed. | — |
| R50-I2 | Info | `CloudAdapterTests.swift:239-240` | `ScriptedCloudTransport` is `@unchecked Sendable` with an `NSLock`. It is test-only and correct (every access is under the lock). No `@unchecked Sendable` or `nonisolated(unsafe)` in product code. | None. | — |

## Checklist
- [ ] Correctness vs ACs: AC-M2-22 deadline start (R50-F1). AC-M2-24 is otherwise met in code; its recordings are open (R50-F4)
- [x] Tests meaningful (would fail if code broke): 8 of 10 reviewer mutants killed; m9 is equivalent and m10 is R50-F1
- [x] Swift 6 concurrency safe (Linux `-warnings-as-errors` clean; no unchecked escapes in product code; cancellation releases the transport)
- [x] No force unwraps / `try!` in product code paths
- [ ] Privacy (P-1…P-4): code passes; the owner key-handling instructions fail (R50-F2)
- [x] UX-2/UX-3 enforced in engine (UX-2 n.a.; UX-3 neutral reasons only, AC-M2-12 scan 0)
- [x] Accessibility (UI): n.a., no UI
- [x] Performance: no main-actor work; O(1) per chunk; the body is capped by the reader
- [x] No new dependency without ADR (none added; networking stays in the allowlisted files, AC-M2-09 scan 0)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No UI. |
| UX-2 Rule of Three | n.a. | No surface. |
| UX-3 Zero-Guilt | pass | Only the neutral `ModelStopReason` cases. No new user-facing string. AC-M2-12 vocabulary scan: 0 violations. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The cloud model is built only through `CloudModelSource` on route `cloud` (`routerEndToEnd`). The router is unchanged, so an on-device error never re-routes. |
| P-2 No data leaves device (except user iCloud) | pass | The adapters use only the neutral `CloudTransport`. No networking type in the new files. AC-M2-09 scan: 77 files, 0 violations. No new dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | **concern** | Code: the request is the golden request byte for byte, with only the capture, room names and shortlist titles, no IDs, the key only in the auth header and never in the URL, and `store: false` for OpenAI unchanged. Concern: the owner recording commands can echo and store the key (R50-F2). The deadline start (R50-F1) is a P-3/AC-M2-27 timing issue, not a data-minimisation one. |
| P-4 Media not persisted without consent | pass | Bodies live in memory for one capture. Nothing is written or logged. The Gemini recording holds only the response stream (no header or key text). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | PR #50 at `e039a4d` (code `035378e`), base `65c06cd`. |
| 2026-11-27 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: R50-F1 Major (deadline start at receipt, with a test), R50-F2 Major (zsh-safe, history-safe recording commands). R50-F3, F4 Minor; N1-N4 Nit. R50-F4 needs the PO or Planner to record the owner's "Gemini now, others later" choice. Re-review checks F1 with a killing test for m10 and F2 with a zsh and bash probe. |

---

# Round 2 — PR #50 (`m2/cloud-adapters`, head `33e1997`, code commit `990fffc`, evidence commit `33e1997`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 2
- **Scope:** `git diff 463572d 33e1997` (39 files). Code: `CloudModelSource.receive()` and the new
  `CloudCaptureReceipt` (`ModelRouter.swift`), the receipt in `CloudAdapters.swift`, `start:` on
  `CloudIngestionModel` and the three provider types, the test-double conformances, `CloudAdapterTests`
  (`deadlineFromReceipt` × 3, N1, N2), the new `CloudReceiptTests.swift` (TendIngestion), and the new script
  `Tools/Recording/record-provider-stream.sh`. Docs: the dev-notes section and the Mac record
  `evidence/mac/WI-M2-M6-round1/`. No change in `Fixtures/` (frozen eval files untouched), `TendCore`, `project.yml`
  or any protected path. `git diff --name-only 990fffc 33e1997` is all under `docs/`.
- **IDs:** AC-M2-22 "Timeouts", Q22, T-17, AC-M2-27, AC-M2-24, T-19, Q18; ADR-0005; P-1, P-2, P-3, P-4; UX-3.
- **Milestone lock:** M1 ACCEPTED, M2 IN-BUILD (`STATUS.md`). This M2 work item is allowed.
- **Commits:** `990fffc` and `33e1997` are both by `Claude <noreply@anthropic.com>`.

## Summary
Both Majors are closed. The deadline start is now read once, when the pipeline receives the input. This happens before
the route choice and before any consent or Keychain read, on the adapters' injected clock (AC-M2-22, Q22). Tests now
pin it: all my round-1 and round-2 deadline mutants are killed. The recording commands are replaced by a script that
works in zsh and bash. In my own pty probe it did not echo the key, kept it out of the history and out of `curl`'s
argv, saved only the stream, and deleted a stream that contained the key (P-3).

One new Minor finding (R50-F5): the leak check passes the key to `grep` as an argument. So the key is in one process's
argv for a moment, and the script and dev-notes claim it never is. R50-F4 stays open for the PO or Planner. It is
Minor and does not block this PR, but it keeps AC-M2-24 not PASS.

## Runs (this review)
| Run | Where | Result |
|---|---|---|
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` at `33e1997`, scratch `/tmp/m6r2c` | Docker `swift:6.2-noble` | 141 tests in 18 suites passed, exit 0, 0 `warning:` lines |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` at `33e1997`, scratch `/tmp/m6r2i` | Docker `swift:6.2-noble` | 582 tests in 69 suites passed, exit 0, 0 warnings. Both `CloudReceiptTests` pass. AC-M2-09 scan: 77 files, 0 violations. AC-M2-12: 77 files, 9 exempted, 0 violations |
| Linux harness: the `TendAI/Cloud` adapter sources at `33e1997` (`CloudIngestionModel`, the three provider types, `CloudAdapters` without the Mac-only `init()`), `CloudAdapterTests.swift` unchanged, plus `FailingModel` and the `DraftStreamSummary(_:)` helper copied from the TendAI test target | Docker `swift:6.2-noble`, `-warnings-as-errors` | 13 tests in 1 suite passed (incl. `deadlineFromReceipt` × 3), 0 warnings. Swift 6 strict concurrency is clean for the changed product code |
| Mac record `evidence/mac/WI-M2-M6-round1/` | read only | 23/23 SHA-256 lines verify (16 B0–B9 files and 7 extras). B0 names `990fffc34da4…`. The B0 and B9 `git status --porcelain` output is empty. B1 141, B2 582/69, B4 109/18 (incl. `deadlineFromReceipt` × 3), B5 36/5, all passed. The logs hold only `$HOME`/`$REPO`/`$USER`/`$TMPDIR` tokens and toolchain paths: no personal data. `mutants-r50-f1.txt` matches what I found myself |

### Mutation table, round 2 (one at a time, each on a scratch copy; the worktree was never edited)
| # | Mutant | Result |
|---|---|---|
| m10 | Receipt start 30 s later (`CloudAdapters.receive()`) | killed (`deadlineFromReceipt` × 3) |
| m11 | Start read at the model call (`snapshots(for:)` uses `clock.now`, the round-1 behaviour) | killed (`deadlineFromReceipt`) |
| m12 | Start read when the model is built (`Receipt.model(for:key:)` uses `clock.now`) | killed (`deadlineFromReceipt`) |
| m13 | Router takes the receipt after the `cloudStatus()` read | killed (`CloudReceiptTests.receiptFirst`, `onDeviceReceipt`) |
| m14 | Gemini only: start 1 s later | killed (`deadlineFromReceipt` gemini case) |
| m15 | Start 1 s earlier | killed (`deadlineFromReceipt`: exact equality, resource 7.5 s) |
| m16 | `beginRequest` builds the model from a fresh `cloudModels.receive()`, not the capture's receipt | killed (`CloudReceiptTests.receiptFirst`) |

### Recording-script probe (this container: zsh 5.9, bash 5.2; fake keys; local HTTP server on 127.0.0.1 and `invalid.invalid` via `TEND_REC_BASE`; no real provider host or key)
| Check | zsh (`zsh -i`, history on, INC_APPEND_HISTORY) | bash (`bash -i`, history on, `history -a`) |
|---|---|---|
| Run as `<shell> Tools/Recording/record-provider-stream.sh <p> <out>` from a real pty; key typed at the prompt | openai, gemini: prompt shown, key not in the pty transcript | anthropic, openai: same |
| History file | holds the command lines only, never the key | same |
| Request at the server | auth header exact (`Authorization: Bearer …` / `x-api-key` / `x-goog-api-key`), other golden headers, body 4343 / 4294 bytes | same |
| Key in `/proc/*/cmdline` or `environ` (polled every 20 ms while `curl` waited 3 s) | 0 hits (the key variable is not exported) | 0 hits |
| argv of `curl` and `grep` (PATH shims logging argv) | `curl`: `-H @-` only, no key. **`grep`: `-F -q -e <key> -- <stream>`, so the key is in argv** (R50-F5) | same code path |
| Saved files | only `<provider>.sse`. No headers (the server's `X-Org-Id` header was not saved) | same |
| Response that echoes the key | stream deleted, "the response contained the key, so … was deleted", exit 1 | same |
| Empty key | "no key read; nothing was sent", exit 1, server request count unchanged, no output folder | — |
| Invalid host | `curl: (6) Could not resolve host`, status 000, exit 6, the out folder is empty | — |

## Findings, round 2
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R50-F1 | Major | `ModelRouter.swift:148`, `CloudAdapters.swift:21-22`, `CloudIngestionModel.swift:45` | Fixed. `events(preference:household:makePipeline:)` calls `cloudModels.receive()` first, before `onDevice.availability()` and before any await, so before the cloud-status and Keychain reads. The receipt reads `clock.now` once, on the adapters' injected clock. `beginRequest` builds the model from `capture.receipt` (`:275`), and `CloudIngestionModel` never reads its own start. The router stays clock-free. The headers at `CloudIngestionModel.swift:11-14` now state the brief's definition. Tests: `deadlineFromReceipt` (manual `StepClock`, Keychain read 2.5 s, first attempt `resource 7.5 / request 4.0`) and `CloudReceiptTests` (order, one receipt per capture, model from its own receipt after the key read). m10–m16 are all killed. | — | **Closed** |
| R50-F2 | Major | `Tools/Recording/record-provider-stream.sh`; `dev-notes.md` owner-pending section | Fixed. The steps are now a script run as `zsh <script>` / `bash <script>`, with no inline comments in the commands the owner copies. It has a hidden `stty -echo` prompt on a tty, stops on an empty key, sends the auth header on `curl`'s stdin (`printf` is a builtin in both shells), uses a non-exported variable that is cleared at the end, and has a trap that restores echo. My zsh and bash pty probes: no echo, no history entry, nothing in `curl`'s argv or any process environment. The `grep` argv point is a separate Minor (R50-F5). | — | **Closed** |
| R50-F3 | Minor | same | Fixed. There is no `-D`, the status is printed with `-w '%{http_code}'`, and only `<provider>.sse` is saved (probe: the server's headers did not reach disk). The Gemini command is written out. | — | **Closed** |
| R50-F4 | Minor | `dev-notes.md` owner-pending section; plan row WI-M2-M6 | Still open, correctly routed. The Developer marked it "for the PO or Planner". `DECISIONS.md` and `plan.md` still do not record the owner's "Gemini now, others later" choice. | PO or Planner records it. The Tester keeps AC-M2-24 not PASS until the OpenAI and Anthropic recordings are in. | Open (not a merge block) |
| R50-F5 | Minor | `Tools/Recording/record-provider-stream.sh` (leak check, `grep -F -q -e "$key" -- "$stream"`); script header ("never in any command's arguments"); `dev-notes.md` owner-pending prose and the round-1 table; `evidence/.../probe/probe.sh:13,26` | **The leak check puts the key in `grep`'s argv** while `grep` runs, where `ps` can see it. The window is milliseconds, on the owner's own Mac. The developer's probe sampled `ps` only while `curl` ran, so it missed this, and the script and dev-notes claim the opposite. Plan "Real provider recordings" and P-3 key hygiene: the claim the owner relies on must be true. | Check without argv, for example in pure shell: `content=$(cat -- "$stream"); case $content in *"$key"*) leak=yes ;; esac`. That works in zsh and bash; `$key` is quoted, so it is matched literally. Or use `printf '%s\n' "$key" \| grep -F -q -f - -- "$stream"`, after checking that BSD `grep` accepts `-f -` on macOS. Extend the probe with a `grep` argv shim or a `ps` sample during the check. Fix it in this PR or before the owner's first OpenAI or Anthropic run, whichever comes first. | Open |
| R50-N1 | Nit | `CloudAdapterTests.swift:330` | `try #require(transport.requests.count == 2)` before indexing. | — | Closed |
| R50-N2 | Nit | `CloudAdapterTests.swift:297-313` | The stored-member walk goes 4 levels deep and asserts that it reaches `cloud.model` and `cloud.transport`. The comment says the guarantee is by type. | — | Closed |
| R50-N3 | Nit | `evidence/mac/WI-M2-M6/README.md:8` | The README states UTC and that the logs use the Mac's local time. | — | Closed |
| R50-N4 | Nit | `CloudIngestionModel.swift:61-63` | A comment explains why the order is safe. | — | Closed |
| R50-I1 | Info | — | Unchanged. | — | — |
| R50-I3 | Info | `CloudAdapterTests.swift` `StepClock`, `SlowKeyStore` | They are `@unchecked Sendable` with an `NSLock`, test-only, and every access is under the lock. There is no `@unchecked Sendable` or `nonisolated(unsafe)` in the changed product code. | None. | — |

## Checks asked for in round 2
- **P-1, no silent escalation:** the receipt is taken for every capture, but it only reads a clock. `onDevice.model`
  is still chosen for `.onDevice` and `.none`, and the route rules are unchanged. `CloudReceiptTests.onDeviceReceipt`
  shows that an on-device capture builds no cloud model. `OnDeviceModelTests.NoCloud` (`Issue.record` if asked) still
  passes in Mac B4. An on-device error still never re-routes.
- **No test weakened:** the round-2 test edits make tests stronger (N1 `#require`, N2 deeper walk) or add tests. The
  test doubles gain `receive() -> self` with no change in behaviour. The frozen eval files are unchanged (no
  `Fixtures/` diff).
- **Script vs P-3 / ADR-0005:** the script sends only the committed golden request (a synthetic capture, no household
  data) to the provider host in the golden head line, with the owner's own key. It saves no headers. It is a
  developer tool and not shipped in the app (not in `project.yml` targets). No dependency is added.

## Checklist
- [x] Correctness vs ACs: AC-M2-22 deadline from receipt (R50-F1 closed). AC-M2-24 recordings still open (R50-F4, not a code defect)
- [x] Tests meaningful: 7 of 7 deadline/receipt mutants killed
- [x] Swift 6 concurrency safe (Linux `-warnings-as-errors` clean; the router actor reads the receipt before its first await)
- [x] No force unwraps / `try!` in product code paths
- [x] Privacy (P-1…P-4): pass. One Minor hygiene point in the owner script (R50-F5)
- [x] UX-2/UX-3 enforced in engine (UX-2 n.a.; UX-3 neutral, AC-M2-12 scan 0)
- [x] Accessibility (UI): n.a.
- [x] Performance: one clock read per capture
- [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No UI. |
| UX-2 Rule of Three | n.a. | No surface. |
| UX-3 Zero-Guilt | pass | No new user-facing string. The script's messages are neutral. AC-M2-12 scan: 0 violations. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The route rules are unchanged. On device, the receipt builds no cloud model (`onDeviceReceipt`), and there is no silent escalation. |
| P-2 No data leaves device (except user iCloud) | pass | No networking type added to Swift. AC-M2-09 scan: 77 files, 0 violations. The script talks only to the golden provider host (or a test base URL). No dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The deadline holds from receipt (AC-M2-22, AC-M2-27). The request is unchanged (golden). Owner key hygiene: hidden prompt, no history, not in `curl` argv or the environment, not saved. Minor: the key is briefly in `grep` argv (R50-F5). |
| P-4 Media not persisted without consent | pass | Only the response stream is saved by the owner tool. No headers. The app path persists nothing. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Round 2 at `33e1997` (code `990fffc`), diff from `463572d`. |
| 2026-11-28 | Reviewer | Orchestrator → Merge Gatekeeper; Developer; PO/Planner | sent | APPROVE. R50-F1, F2, F3, N1–N4 closed. Open Minors: R50-F5 (Developer: argv-free leak check, fix the claim, extend the probe; before the owner's next recording) and R50-F4 (PO or Planner: record the "Gemini now, others later" choice). AC-M2-24 stays not PASS for the Tester. |
