# M2 Code Review — PR #52 (`m2/eval-harness`, head `30df4e2`, code commit `070ce05`, base `main` `a5c38f9`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** `git diff origin/main...HEAD`: 45 files (+15395 / -45). Code: `Apps/TendEval/Sources/**` (7 files new or
  changed), `Apps/TendEval/Tests/EvalHarnessTests.swift`, `Apps/TendEval/Support/Debug-Info.plist`, `project.yml`.
  D-059: `Fixtures/M2/eval/results-v1.schema.json`, `MANIFEST.sha256`, TendIngestion `Eval/EvalProfile.swift`,
  `EvalResultsFileV1.swift`, `EvalResultsReading.swift`, `Payload/CloudRequestKeyPaths.swift`, Tools
  `EvalScoreCommand.swift`, plus tests. Docs: `dev-notes.md` (WI-M2-M7 section) and the Mac evidence record
  `docs/milestones/M2/evidence/mac/WI-M2-M7/`.
- **Checked against:** brief AC-M2-28 (all of it: "Never shipped", "Build path", "What it does", "Results file
  (format v1)", "Export", "Reconciliation with AC-M2-09"), AC-M2-16 (prewarm, clock rules, cold start), AC-M2-17
  (commit), AC-M2-26 (key paths and element counts), AC-M2-09 Rule 6 and the M2 Q23 loader rule, brief "Device-run
  rules" (T-20); plan WI-M2-M7 row and note, "Fixtures hash", "Eval harness ID generator", "Scoring tool and command";
  PO ruling D-059 (`po-m2-element-counts.md`); the Tester's D-059 freeze re-check (round 2 PASS at `e014fab`).
- **IDs:** AC-M2-28, AC-M2-26, AC-M2-16, AC-M2-17, AC-M2-09, AC-M2-12, AC-M2-14, AC-M2-21, AC-M2-20, T-20, T-29, D-053,
  D-059, Q23, P-1…P-4, UX-3.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work on an `m2/` branch. No M3+ work.
  OK.

## Summary

The harness does what AC-M2-28 asks, and the D-059 counts are built the way the PO ruled. I found no Blocker and no
Major. There are six Minor findings, three Nits and four Info notes. None of them blocks the merge.

- **Never shipped (AC-M2-28).**
  - `TendEval` has its own bundle ID (`com.tend.eval`). A pre-build guard stops any configuration other than Debug.
  - File sharing comes only from the Debug-only partial `Info.plist`.
  - The `Tend` target has no dependency on it, and the `Tend` scheme builds `Tend` only.
  - The `TendEval` scheme never builds it for archiving.
  - The Mac record shows all four results:
    - a Release build of `TendEval` stops at the guard (exit 65);
    - the `Tend` Release products and the `Tend` archive hold no `TendEval` (`find` prints nothing; `Products/Applications`
      holds only `Tend.app`);
    - the `TendEval` archive action is off (exit 66);
    - the Debug bundle holds the five fixtures byte-for-byte, with `TendCommit` set to `070ce05…`.
  - The Linux scan `ProjectSpecScanTests` passes in my Docker run: 5 targets, 3 schemes, 0 violations, and all 11
    negative plants are caught.
  - TendAI, TendCore and the pipeline gained no code or hook. `git diff --stat` shows no file under `Packages/TendAI`
    or `Packages/TendCore`. The only TendIngestion source changes are D-059 eval-namespace code: the scorer, the
    reader, the writer and the count function.
- **RecordingTransport.**
  - It records at `send(_:timeouts:)` from `request.body`. Those are the exact bytes `CloudHTTPTransport` puts in
    `httpBody` (`CloudHTTPTransport.swift:85`).
  - It then forwards the request unchanged.
  - It calls the one shared count function (`CloudRequestKeyPaths.arrayCounts(ofBody:)` and
    `userContentArrayCounts(ofBody:provider:)`) and `leafPaths(ofBody:)`. There is no second implementation.
- **Results writer.**
  - It emits exactly the five `cloudRequests[]` members that D-059 lists.
  - The arrays are sorted by UTF-8 path, and `null` is written as `null`.
  - The output is canonical JSON. The hosted tests read every built file back through the scorer's own reader:
    schema, canonical form, fixtures hash and cross-field rules.
- **Fixtures hash on screen.**
  - It is the SHA-256 of the bundled `MANIFEST.sha256` bytes, and each data file is checked against its manifest line.
  - The hosted test `bundleHash` compares it with the repo's manifest. My `sha256sum` of the manifest gives
    `7fdc056e…1de22`, the value in the Tester's re-check and the Mac record.
- **TEND_COMMIT.** Without a 40-hex commit, `setupProblem` stops the run and "Start run" is disabled. The scorer's
  schema pattern on `run/appCommitSHA` is a second guard.
- **Q23.**
  - `EvalFixturesLoader` holds four functions that take no parameter. Each one has one literal
    `Bundle.main.url(forResource:withExtension:)` followed by `Data(contentsOf:)`.
  - No `#if`, `typealias` or `extension` appears anywhere in `Apps/TendEval/Sources`.
  - No TendEval file declares or extends `Data`, `Bundle` or `EvalFixturesLoader`. The only other `Bundle` use is
    `Bundle.main.object(forInfoDictionaryKey: "TendCommit")`.
- **Frozen data.**
  - `inputs.json`, `household.json` and `golden.json` are untouched. Only `results-v1.schema.json` and line 4 of
    `MANIFEST.sha256` change.
  - `sha256sum -c` prints four `OK` lines.
  - The schema matches D-059: five required members, `uniqueItems`, the concrete-index path pattern, `minimum: 0`
    and `additionalProperties: false`.
  - I did not redo the Tester's re-check in depth.

**What I ran (Linux, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, worktree at `30df4e2`):**

| Package | Scratch | Result |
|---|---|---|
| `Packages/TendCore` | `/tmp/m7c` | 141 tests in 18 suites passed, 0 warnings, exit 0 |
| `Packages/TendIngestion` | `/tmp/m7i` | 597 tests in 71 suites passed, 0 warnings, exit 0. AC-M2-09 scan: TendIngestion 56, TendAI 20, TendEval 8 files, **84 in total, 0 violations**, Rule 5 T-27 exception OFF. AC-M2-28 `project.yml` scan: 5 targets, 3 schemes, 0 violations, 11 plants caught |
| `Packages/TendSourceScan` | `/tmp/m7s` | 88 tests in 5 suites passed, 0 warnings, exit 0 |
| `Tools/TendTools` | `/tmp/m7t` | 11 tests in 1 suite passed, 0 warnings, exit 0 |

TendAI and TendEval are Mac-only. For those I used the Mac record at `070ce05`: B4 109 tests, B5 36 tests, B5-eval 5
tests (9 cases), all passed, 0 skipped. I verified the record's 19 SHA-256 lines myself: all 19 `OK`.

**My mutants** (each applied alone to a copy of the tree, filtered suite run, restored after). 22 of 24 were killed:

| Id | Mutation | Result |
|---|---|---|
| C1 | count function skips empty arrays | killed (9 tests) |
| C2b | nested index always `[0]` | killed (14) |
| C3 | every `enum` array counted +1 | killed (11) |
| C4 | user-content counts taken from the body root | killed (13) |
| T1 | user-content path always the OpenAI one | killed (10) |
| P1 | `ds2-gated` counts checked on the last attempt only (Tester F1 regression) | killed (6) |
| P2 | `rooms` check off | killed (6) |
| P3 | `existingTasks` cap 11 | killed (3) |
| P4 | an extra user-content path is allowed | killed (3) |
| P5 | an extra body array path is allowed | killed (4) |
| P6 | `arrayCounts: null` is allowed | killed (4) |
| **P7** | `$.existingTasks` absent is allowed | **survived** (see m5) |
| W1 | writer leaves out `userContentArrayCounts` | killed (24) |
| W2 | writer does not sort the count entries | killed (24) |
| R1 | reader's order check on count lists off | killed (5) |
| S1 | scan: archiving rule weakened to `all` only | killed |
| S2 | scan: `Tend` scheme may build anything | killed |
| **S3** | scan: guard check ignores `exit 1` | **survived** (see n2) |
| S4 | scan: dependency rule blind | killed |
| S5b | scan: base-settings file-sharing rule blind | killed |
| S6 | scan: non-Debug configuration rule blind | killed |
| S7 | scan: bundle-ID rule blind | killed |
| S8 | scan: other-target file-sharing rule blind | killed |

C2 and S5, first written as plain deletions, were stopped only by the unused-value error. I rewrote them as C2b and S5b.

**Scan probes** (planted specs fed to `ProjectSpecRules.violations` in a probe test on a separate copy):
- caught: the `Tend` target adds `Apps/TendEval/Sources` to its sources; the `Tend` scheme's test action lists
  `TendEvalTests`; a flow-style `- {target: TendEval}` in the `Tend` target.
- **not caught** (see m1):
  - a new `app-extension` target with `sources: - path: Apps/TendEval/Sources`;
  - a new extension with `dependencies: [{target: TendEval}]`;
  - the `TendEval` scheme's `archive` config set to Release. This one does not matter, because the scheme builds
    nothing for archiving.

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| m1 | Minor | `Packages/TendIngestion/Tests/TendIngestionTests/ProjectSpecScanTests.swift:90-98`, `:130-134` | **The scan only sees dependency and source lines in block form, and only on the `Tend` target.** Two specs pass with 0 violations: (a) a new shipped target, for example an M4 widget extension, that lists `Apps/TendEval/Sources` (or a `Fixtures/M2/eval` file) in its `sources`; (b) a new target with flow-style `dependencies: [{target: TendEval}]`. XcodeGen accepts both. No such target exists in M2, so today's spec is correct and the AC-M2-28 proof holds now (scan plus my inspection). The rule would not stay true by itself once M4 adds extensions. | For every target outside `TendEval`/`TendEvalTests`, report any line that names `TendEval` or `Fixtures/M2/eval`, in any form. A comment does not count. This is the same as the stricter rule the `Tend` target already has. Add the two probes above as plants. Ticket; must land before the first M4 extension target. | Open (ticket) |
| m2 | Minor | `Apps/TendEval/Sources/Run/EvalRunner.swift:125-128` | **Errors are swallowed in the attempt record.** `_ = try? await DraftCommit.commit(...)` drops a commit error such as `taskRejected` or `writeStopped`, and `committed[]` still lists every unmarked draft. `summary.drafts.compactMap { try? DraftRecord(...) }` silently drops a draft that cannot be recorded. Scoring is not misled: the reader defines `committed` as "the unmarked drafts" (`committedMismatch`), and a dropped draft makes the file fail with exit 2 at scoring. But the operator gets no sign of it on the phone during a gate run, so a fault only shows later on the Mac. | Keep the record as it is. If the commit throws or a draft cannot be recorded, show it in `status` (for example "inNN: the commit stopped"), so the operator can record an environment fault (brief "Device-run rules"). Add a hosted test with a repository that fails on write. | Open (ticket) |
| m3 | Minor | `Apps/TendEval/Sources/Screens/EvalSession.swift:129-136`, `:176-189`, `:197-199`; `Apps/TendEval/Tests/EvalHarnessTests.swift` | **The session rules have no automated test.** No test covers: the TEND_COMMIT refusal (`setupProblem`), "a text input runs once", "at most one retake, only with a reason" (`nextAttemptProblem`), or cold-start gating. The dev-notes table credits "Device-run rules" to `voiceAttempt × 2`, but that test calls `EvalRunner.run` directly and skips `nextAttemptProblem`. Fresh household and deterministic IDs (T-29) are credited to `EvalIDGeneratorTests` and `onDeviceText`. `onDeviceText` commits nothing (its model emits no item), so the harness's `EvalIDGenerator(inputNumber:attempt:)` wiring is never exercised. I inspected all of this and it is correct. The scorer enforces the same attempt and retake rules (`attemptsNotConsecutive`, `retakeReasonMismatch`, Linux-tested) and the commit pattern, so a harness bug would be caught at scoring. That is why this is Minor and not Major. | Add hosted tests on `EvalSession`: no TEND_COMMIT gives the refusal text; a text input gets a second-attempt refusal; a voice input gets a retake refusal without a reason and a third-attempt refusal. Add one `cloudRun` assertion that the committed task IDs in the repository are the `EvalIDGenerator` IDs for (input number, attempt). Correct the dev-notes table rows. | Open (ticket) |
| m4 | Minor | `Apps/TendEval/Sources/Screens/EvalSession.swift:146-158`, `:329` | **A stored key can be left with no "Remove key".** `turnCloudOn` saves the key to the Keychain before it returns the status. If the status is not `.on(provider)`, or `select` throws after the save, `startRun` drops the runner. The UI then hides "Remove key" (`canRemoveKey` needs a runner), and the message says "The key was not stored". The same happens if the app is closed in the middle of a run. On iOS, Keychain items can survive deleting the app. P-3 still holds, because it is the owner's key in the owner's Keychain and nothing is sent. But AC-M2-28 "offers 'Remove key' at the end of the run" is not reachable on that path. | On the setup screen, offer "Remove key" for every provider that has a stored key (`APIKeyStore.hasKey`). Or delete the key on any failed start. Make the failure message accurate. | Open (ticket) |
| m5 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Eval/EvalProfile.swift:388-395`; `EvalProfileTests.swift:381` | **Mutant P7 survived.** If `userContentArrayCounts` has no `$.existingTasks` entry, `ds2-gated` fails, as D-059 rule 3 says ("exactly the paths `$.existingTasks` and `$.rooms`"). But no test covers that case. Removing the branch leaves every test green. | Add a plant to the D-059 negative test: user content with `$.rooms` only. It must give exit 1 with "`$.existingTasks` … seen absent". | Open (ticket) |
| m6 | Minor | commit `f81669b` (`docs/milestones/M2/evidence/mac/WI-M2-M7/logs/mac-B6-eval-debug.log`, `mac-B6-eval-release.log`) | **A local folder name is in branch history.** `f81669b` committed two build logs whose `SCRIPT_INPUT_ANCESTOR_3` held the real folder above the checkout. `30df4e2` replaced it with `$REPO_PARENT`, so the tree at HEAD is clean: no `/Users/<name>`, hostname, e-mail or login-like name in any file of the record. The same folder name has been in `main`'s history since `02c1d84` (WI-M2-M1, redacted in `b1f57d3`), so a merge does not add new exposure. The cause is that `run-evidence.sh` does no redaction itself. The tokens are applied by hand after the run. | Make the redaction part of `run-evidence.sh` (or a committed `redact.sh` run before hashing), covering `SCRIPT_INPUT_ANCESTOR_*` and every path above `$REPO`, so the first commit of a record is clean. Rewriting history (squash merge, or rewriting `main`) is the human owner's call. I do not require it, given `02c1d84`. | Open (owner decision; ticket) |
| n1 | Nit | `Apps/TendEval/Sources/Run/EvalRunner.swift:43-45` | `@unchecked Sendable` on `EvalRunner` seems unneeded. Every stored property is a `let` of a Sendable type (`EvalBundle`, `EvalRunKind`, `any OnDeviceModelSource`, the `FoundationModelsOnDeviceSource` struct, `RecordingTransport`, the `ModelRouter` actor and `ContinuousClock`). `RecordingTransport`'s `@unchecked` with `NSLock` is correct as written: `records` is touched only under the lock, and the attempt number is taken inside the lock. | Try plain `Sendable` on the Mac. Keep `@unchecked` only if the compiler requires it, with the reason in the comment. | Open |
| n2 | Nit | `ProjectSpecScanTests.swift:111`, plants at `:205` | Mutant S3 survived. The guard rule's `exit 1` clause has no plant, because the only guard plant changes the condition. | Add a plant that changes `exit 1` to `exit 0`. | Open |
| n3 | Nit | `Apps/TendEval/Sources/Fixtures/EvalBundle.swift:15`; `Run/RecordingTransport.swift:31` | `allMatch`'s `checks.count == 3` is always true. `keyPaths: … ?? []` writes `[]` for a body that is not JSON, while the two count members write `null`. The builder always sends JSON, so this cannot happen today. | Optional: drop the tautology, and comment why `[]` is used. | Open |
| i1 | Info | `docs/milestones/M2/dev-notes.md` (WI-M2-M7 table, first row) | The table cites a "Simulator screenshot" of the fixtures hash on screen. No screenshot is in the evidence folder. The hash value is tested (`bundleHash`), and the view code shows it (`EvalRootView.swift:37-39`). | Commit the screenshot or remove the reference. The Tester's DS-1/DS-2 run record will show the on-screen hash in any case. | Open |
| i2 | Info | plan MS-3; `acceptance.md` DS-1/DS-2 | Two device-run steps are not yet written. The install command must pass `TEND_COMMIT=$(git rev-parse HEAD)`: an Xcode GUI build leaves it empty, and the harness then refuses to start. The DS-2 S4 scorer command must add `--golden-body Fixtures/M2/payload/golden/g1-outcome-empty-<provider>.body.json`, as D-059 says. Neither is written in `docs/` yet. | Tester and Planner: write both into the DS-1/DS-2 scripts and the MS-3 install step. | For Tester/Planner |
| i3 | Info | `EvalRunner.swift:83-86`; `EvalSession.swift:316` | The run header writes `prewarm: true` for a cloud run with "on device first". On an iPhone 13 there is no on-device model to prewarm, so the field means "prewarm was requested", not "a session was prewarmed". Cold start is information only (Q4). Opening an input view before tapping "Cold start" can prewarm the main runner's session, though the cold start uses its own fresh source. | None. Tester: note both in the DS-1/DS-2 scripts (tap "Cold start" before opening any input). | Info |
| i4 | Info | Mac record `README.md` | The Mac ran Xcode 27.2 and the iOS Simulator 26.5 runtime. The brief says "Xcode 26". This is the same toolchain as the earlier MS-1/MS-2 records that were accepted. The deployment target stays iOS 26.0. | None from me. The PO and Tester already accepted this toolchain for MS-1. | Info |

## Requirement walk-through (AC-M2-28 "What it does" and the rest)

| AC-M2-28 point | Code | Test / evidence | Verdict |
|---|---|---|---|
| Fresh copy of the seeded household in the M1 in-memory repository per input | `EvalRunner.run:97-98` (new `InMemoryHouseholdRepository` (TendCore), `save(household)` per attempt) | inspection; `cloudRun` commits into it | met (test gap m3) |
| Deterministic ID generator seeded from input number and attempt, never a fixture UUID (T-29) | `EvalRunner.run:94` `EvalIDGenerator(inputNumber:attempt:)` passed to `DraftCommit.commit(ids:)` | `EvalIDGeneratorTests` (Linux), plan table | met (wiring untested, m3) |
| Shows each input's script | `EvalInputView:129-131` | inspection | met |
| Text verbatim; voice live through the M2 speech adapter; voice uses the transcript | `EvalRunner.run:95` (`voice?.transcript ?? input.text`), `runText` guards `.text`; `startVoice` uses `SpeechCapture().events(from: MicrophoneAudioSource())` (TendAI, on device) | `onDeviceText` (model sees each fixture text exactly), `voiceAttempt` (model sees the transcript; harness mutant E3 killed) | met |
| Prewarm (AC-M2-16) | `show` (`.task` on the input view), `runText`, `startVoice` call `runner.prewarm()` | inspection | met |
| TTFI and total on a monotonic clock | `ContinuousClock`; text start at hand-off, voice at the final transcript; `t` read before `summary.apply` | `voiceAttempt` (`totalMs >= 300`; mutant E4 killed) | met |
| Commit as AC-M2-17 | unmarked drafts in ascending `draftID` | `cloudRun` (mutant E6 killed); scorer `committedMismatch` | met (m2) |
| Device-run rules (retake reason, every attempt kept) | `nextAttemptProblem`, `attempts.append` | scorer reader rules (Linux) | met (m3) |
| Cloud: AC-M2-21 key store, in-memory consent for the selected provider, "Remove key" | `KeychainAPIKeyStore`, `InMemoryCloudConsentStore`, `ModelRouter.turnCloudOn/removeKey`; key field cleared at once | `cloudRun` × 3 (fake key, removed; file holds no key text) | met (m4) |
| Writes nothing except the results file | `EvalResultsWriter` is the only write API (AC-M2-09 Rule 6: 0 violations); Documents, `.atomic`, `.completeFileProtection` | `writer` | met |
| Results file v1, D-059 members, never a body, header value or key | `EvalResultsFileV1.canonicalJSON`; `RecordingTransport` | `cloudRun` (bytes, key paths, counts equal to the G1 golden body, `rooms` = seeded, `existingTasks` ≤ 10), read back by the scorer | met |
| Name `m2-eval-<deviceModel>-<route>-<UTC>.json` | `EvalRunRecord.fileName` | `writer` | met |
| Export via Debug file sharing only; never uploads | `Debug-Info.plist` (Debug config only); no networking type in TendEval apart from the BYOK `CloudHTTPTransport` the router uses | scan rules + plants; AC-M2-09 Rule 6 | met |
| Never shipped; Release/Archive check | `project.yml` | `ProjectSpecScanTests` (Linux, my run), Mac B6 logs | met (m1 for the future) |
| Fixtures bundled; SHA-256 manifest hash shown | `EvalBundle`, `EvalFixturesSection` | `bundleHash`; B6 bundle log | met (i1) |

## Checklist
- [x] Correctness vs ACs (AC-M2-28 all points; AC-M2-26 counts via D-059; AC-M2-16/17 harness side)
- [x] Tests meaningful (22/24 own mutants killed on Linux; developer harness mutants E1–E6 killed on the Mac; P7, S3 noted)
- [x] Swift 6 concurrency safe (`EvalSession` `@MainActor @Observable`; `RecordingTransport` lock-guarded; n1)
- [x] No force unwraps / `try!` in product code paths (none in TendEval; `try?` noted in m2)
- [x] Privacy (P-1…P-4)  - [x] UX-2/UX-3 enforced in engine (n.a. for UX-2; UX-3 vocabulary scan 0 violations)
- [x] Accessibility (UI): n.a. (debug tool, not judged against UX-4, plan WI-M2-M7)
- [x] Performance: no main-thread inference. `for await` on the main actor only receives events.
- [x] No new dependency without ADR (CryptoKit is an Apple framework, named in plan "Fixtures hash"; no SPM package added)
- [x] No test weakened: the changed tests (`EvalSchemaCheckTests` pattern count 6 → 8, `TendToolsTests` usage) are
  stricter. The `ds2-gated` key-path check now covers every attempt, not only the scored one.
- [x] Commits: all 8 by `Claude <noreply@anthropic.com>` (author and committer), each with the attribution trailer.
- [x] Mac evidence record names `070ce05`, 19/19 SHA-256 lines verify, clean tree before (B0) and after (B9), and no
  personal data in the tree at HEAD (m6 covers history).

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug harness, never shipped. Its setup fields are test controls (plan WI-M2-M7). |
| UX-2 Rule of Three | n.a. | No "what should I do" surface. The engine is unchanged. |
| UX-3 Zero-Guilt | pass | No banned word in any TendEval string. The AC-M2-12 vocabulary scan reports 0 violations over TendEval. Status texts are neutral ("Try again", "Nothing was heard"). The only "error" text is the build-time guard message in `project.yml`, which no user sees. |
| UX-4 Design craft | n.a. | Not judged against UX-4 (brief, plan). |
| P-1 On-device inference | pass | The router picks the route (on device first, unless the run is "always use my cloud model"). Speech runs on device through the M2 `SpeechCapture` adapter. Voice attempts feed the transcript, not the script (tested). |
| P-2 No data leaves device (except user iCloud) | pass | No new dependency. TendEval has no networking type (Rule 6, 0 violations). Its only network path is the BYOK `CloudHTTPTransport`, through the neutral protocol. The results file leaves the phone only when the owner copies it through Debug file sharing. Nothing is uploaded. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass (m4) | The key goes into the AC-M2-21 Keychain store and the field is cleared. Consent is in memory for the selected provider only. The recorder writes integers and fixed paths only, never a value, body, header or key (`cloudRun` checks this). D-059 makes the minimisation proof complete on the device. m4 is about removing a leftover key, not about anything being sent. |
| P-4 Media not persisted without consent | pass | Audio is never written: `MicrophoneAudioSource` and `SpeechCapture` work in memory. The only file is the results file in Documents (`.completeFileProtection`), holding scripted eval text, drafts and request metadata, as AC-M2-28 "Reconciliation with AC-M2-09" allows. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-28 | Orchestrator | Reviewer | accepted | PR #52, head `30df4e2`, code `070ce05`, base `a5c38f9`. WI-M2-M7 and D-059. |
| 2026-11-28 | Reviewer | Orchestrator → Merge Gatekeeper; Developer (tickets m1–m5, n1–n3, i1); Tester and Planner (i2, i3); human owner (m6 history decision) | sent | **APPROVE**, round 1. No Blocker or Major. Linux runs: TendCore 141, TendIngestion 597 (scan 84 files, 0 violations), TendSourceScan 88, TendTools 11, all green with `-warnings-as-errors`. 22 of 24 of my mutants killed. File not committed. |
