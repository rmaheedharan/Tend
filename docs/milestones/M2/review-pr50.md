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
