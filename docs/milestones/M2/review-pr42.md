# M2 Code Review — PR #42 (`m2/speech-adapter`, WI-M2-M3, round 1 @ `d5d9c97`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **CHANGES REQUIRED**  ·  **Round:** 1
- **Scope:** WI-M2-M3, the speech adapter (MS-2): **AC-M2-09** (Rule 2 media types only in the two speech files;
  Rule 5 with the T-27 exception off), the Mac halves of **AC-M2-11** and **AC-M2-25** (the transcriber used is
  reported; the brain-dump input is the final transcript), **T-27** (microphone permission only), FR-A1, P-1, P-4,
  UX-3. Two commits: `1c19f68` (code and tests, 7 new files under `Packages/TendAI`) and `d5d9c97` (docs only: the
  dev-notes section and the Mac evidence record). `git diff --numstat 41bf8fa..d5d9c97` shows 0 deleted lines in any
  file. Only `dev-notes.md` is modified (append only); every other file is new. No protected path is touched.
- **Inputs read:** `CLAUDE.md`; the `code-reviewer` skill; `plan.md` WI-M2-M3 row (`:98`), "Named files" (`:55-56`),
  the WI-M2-01 Developer constraints (`:180-186`), R-7 (`:725`); `brief.md` AC-M2-09 Rules 2 and 5 (`:463-470`),
  AC-M2-11 (`:528`), AC-M2-25 (`:882`), T-27 (`:1157`, `:1443`); the full PR diff; the new dev-notes section; the
  evidence record `evidence/mac/WI-M2-M3/`; the AC-M2-09 scan configuration in `TendSourceScan`.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. An `m2/` work item is allowed (CLAUDE.md §5).

## Summary

The adapter is well shaped. The transcriber choice is a pure function with the right order (SpeechTranscriber, then
DictationTranscriber, then a neutral `unavailable` reason). The transcriber used is reported first and again in the
`FinalTranscript` (AC-M2-25). Volatile text is for display only. There is no `SFSpeech*` API, no speech-recognition
authorization (T-27; the Rule 5 exception stays off), no networking, no write or log API, and no asset download call.
The fake-engine tests are real: they check exact event sequences, and the cancellation test checks that both the
audio and the transcriber are stopped. The real-engine tests on the Mac transcribe a synthesised sentence with both
transcribers. The evidence record is complete, names `1c19f68`, its hashes all verify, and it holds no personal data.

I found **one Major** in `MicrophoneAudioSource`, the one `@unchecked Sendable` type that needs my sign-off. A
`stop()` that arrives before `start()` has stored its state is lost, so the microphone keeps running after the
person has stopped (finding M1). The data-race analysis of the type passes (every mutable stored field is
lock-guarded, and the tap block captures no `self`), but I cannot sign off a type whose stop contract fails under a
realistic interleaving. There are also 5 Minors, 2 Nits and 4 Info items.

### 1. Sign-off on the one `@unchecked Sendable` (`MicrophoneAudioSource.swift:25`) — **NOT SIGNED OFF in round 1**

What I checked, field by field:

| State | Kind | Access | Verdict |
|---|---|---|---|
| `lock` (`:28`) | `let NSLock` | — | Immutable; `NSLock` is thread-safe. OK. |
| `engine` (`:29`) | `var AVAudioEngine?` | Written at `:94` and `:104`; read at `:103`. All three are inside `lock.withLock`. | Field is guarded. OK. |
| `continuation` (`:30`) | `var …Continuation?` | Written at `:49`, `:95`, `:105`; read at `:48`. All inside `lock.withLock`. | Field is guarded. OK. |

The tap block (`:70-92`):
- It captures no `self`. It captures `continuation` (the parameter, an `AsyncThrowingStream.Continuation`, which is
  `Sendable` and safe to `yield`/`finish` from any thread), `format` (not mutated), `ratio` (a `Double`) and
  `converter`.
- `converter` is a non-`Sendable` `AVAudioConverter`. It is created before `installTap` (so creation happens before
  the first callback), it is never stored on `self`, and it is used only inside the tap block. AVAudioEngine calls a
  tap serially on one thread, so the converter is confined to that thread. OK.
- `given` and `error` are locals of each callback. The converter's input block is called synchronously within
  `convert(to:error:withInputFrom:)`. OK.
- A `yield` after `finish` (a buffer in flight while `stop()` runs) is a no-op. Repeated `finish` calls are no-ops. OK.

So there is **no data race on the stored fields**. Two things still stop the sign-off:
- **M1 (Major):** the check-then-act gap between `start()` and `stop()` described below.
- **m3 (Minor):** the justification comment at `:26-27` claims "`engine` … touched only under `lock`". The *field* is,
  but the engine *object's* methods are called outside the lock: `prepare()`/`start()` at `:97-98` and
  `removeTap`/`stop()` at `:109-110`. `AVAudioEngine` does not document that these may run concurrently. After the
  M1 fix the comment must state exactly what the lock protects and why the unlocked calls cannot overlap.

I will sign off in round 2 when M1 is fixed and the comment is accurate. The `nonisolated(unsafe) var given` in the
test-only `FileAudioSource` (`SpeechRealEngineTests.swift:30`) is a local flag used only inside a synchronous
converter callback in a test. **I sign that one off.** No other `@unchecked Sendable` or `nonisolated(unsafe)` exists
in `Packages/TendAI` (`grep -rn` over `Sources` and `Tests`).

### 2. ACs and the requested checks
- **Fallback order (plan `:98`, R-7).** `TranscriberChoice.choose` (`SpeechTranscriptionAdapter.swift:112-119`)
  returns SpeechTranscriber when it is available, supports the locale and has its assets; else DictationTranscriber
  under the same conditions; else `unavailable(assetsNotInstalled)` if either supports the language, else
  `unavailable(languageNotSupported)`. Correct. All 64 combinations are tested, plus three explicit preference cases
  (`SpeechCaptureTests.swift:259-267`). One gap: a nil audio format for the chosen transcriber ends the capture without
  trying the other one (m4).
- **The transcriber used is reported (AC-M2-25 Mac half).** `.transcriberChosen(kind)` is emitted before any audio
  (`:197`) and the kind is carried in `FinalTranscript` and `nothingHeard`. Tested for both kinds (`:134-141`) and by
  the real engine on the Mac (`SpeechRealEngineTests.swift:77-85`). AC-M2-11 and AC-M2-25 themselves stay
  **AWAITING-DEVICE** (DS-1, DS-2), which the dev notes say correctly (○).
- **Final transcript only (brief Definitions "Brain-dump input").** Finals are trimmed and joined; volatile text is
  only in `.textSoFar` (`:201-216`). The test at `:115-132` checks the exact sequence and would fail if volatile text
  reached the final transcript (the dev notes' mutant S2 confirms).
- **Never starts an asset download.** No `downloadAndInstall`, `reserve(` or similar call exists in `Sources`
  (`grep`). The engine calls `AssetInventory.assetInstallationRequest(supporting:)` (`:300`) only to learn whether a
  download would be needed; a non-nil request ends the capture as `stopped(transcriptionStopped)` without starting it.
  This meets the requirement. The `try?` there fails open, and neither branch is tested (m5).
- **T-27, microphone only.** `SpeechPermission.swift` uses only `AVAudioApplication.recordPermission` and
  `requestRecordPermission()`; there is no `SFSpeech*` token anywhere in `Packages/TendAI`. The scan configuration
  keeps `speechPermissionExceptionEnabled` false, and the B2 scan reports "Rule 5 T-27 exception OFF", 0 violations,
  TendAI 4 files. I reproduced the scan on Linux (below). The "microphone prompt only" check is a device step (DS-1,
  DS-2), which is right.
- **P-4, in memory only.** Buffers go from the tap to the converter to `AnalyzerInput` to the stream; nothing is kept
  on `self`, written or logged. No `FileManager`, `write(`, `print(`, `Logger` or `UserDefaults` in `Sources`.
  `AVAudioFile` appears only in the test target, which the scan does not cover (as Rule 2 intends). The test's
  synthesised `.wav` is deleted by a `defer` after each real-engine test (`SpeechRealEngineTests.swift:75`, `:94`);
  there is one leak path on failure (n2).
- **UX-3, neutral names.** `nothingHeard`, `audioInterrupted`, `transcriptionStopped`, `languageNotSupported`,
  `assetsNotInstalled`, `audioFormatUnavailable`, `cancelled`: none blames the person, and `SpeechNamesTests` checks
  them against `BannedTokens`. The only banned-word hit in `Sources` is "behind" in a `// MARK:` comment
  ("behind a protocol", `:122`), which is not UI copy.
- **No tests weakened.** No existing test file is modified; the PR adds 17 TendAI tests and 2 hosted tests.
- **Developer constraints (plan `:180-186`).** No method shares a name and first label with an AC-M2-09 session call
  (`audio(in:`, `transcribe(_:locale:input:)`, `events(from:)`, `choice(for:)`, `audioFormat(for:locale:)`). The
  imports (`AVFAudio`, `Foundation`, `Speech`) are in TendAI's closed list; Rule 6's list applies to `TendEval` only.
- **Swift 6 concurrency (rest of the adapter).** `SpeechCapture`, `SpeechAnalyzerEngine`, `AudioEndWatch` and all
  public value types are genuinely `Sendable` (`AudioEndWatch` holds only a `let` stream and an actor). Every
  unstructured `Task` is cancelled from an `onTermination` handler. `AudioEndState.markThrown()` is awaited before
  `finish(throwing:)` (`:240-241`), so `didThrow` is already true when `run` reads it after the transcriber ends.
  Cancellation runs through `withTaskCancellationHandler` to `cancelAndFinishNow()`. The package is in Swift 6 mode
  and B4/B5 ran with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` with no compiler warning.

### 3. Evidence record (`evidence/mac/WI-M2-M3/`)
- **Commit named:** `README.md` and `mac-B0-header.log` both give `1c19f688d665a6b1c6c0046e69c3b190f3af7a14`, and
  `git rev-parse d5d9c97^` is that commit.
- **`d5d9c97` is docs only:** `git diff --numstat 1c19f68..d5d9c97` lists only paths under `docs/` (18 files: the
  dev-notes section and the evidence folder).
- **SHA-256:** the README lists 16 files (every file in the folder except the README itself). `sha256sum -c` on the
  listed lines: **16/16 OK**.
- **No personal data:** `grep -rniE '<owner login>|Mac-mini|/Users/'` over the evidence folder and the new dev-notes
  section: **0 hits**. Also 0 hits for `maheed`, `/var/folders`, or `.local` host names. Paths are the `$REPO`,
  `$HOME`, `$TMPDIR` tokens. The README names the machine model ("M1 Mac mini, `Macmini9,1`"), which is hardware,
  not a hostname.
- **Logs agree with the claims:** B4 lists 18 tests in 6 suites passed, including both real-engine tests (1.86 s and
  1.73 s); B5 4 tests in 2 suites; `git status --porcelain` empty before and after. The only `warning:` lines are the
  non-compiler `appintentsmetadataprocessor` notices noted in MS-1.

### 4. What I ran (Linux container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `d5d9c97`)
| Package | Result |
|---|---|
| `Packages/TendCore` | exit 0, `✔ Test run with 141 tests in 18 suites passed`; 0 `warning:`, 0 `✘`, 0 skipped results |
| `Packages/TendIngestion` | exit 0, `✔ Test run with 571 tests in 67 suites passed`; 0 `warning:`, 0 `✘`, 0 skipped results. Scan lines: "Rule 5 T-27 exception OFF"; "TendAI (required) Packages/TendAI/Sources: 4 files scanned"; TendIngestion 55, TendEval 1; no violation reported (matches B2). |
| `Packages/TendSourceScan` | exit 0, `✔ Test run with 63 tests in 4 suites passed`; 0 `warning:`, 0 `✘` |
| `Tools/TendTools` | exit 0, `✔ Test run with 11 tests in 1 suite passed`; 0 `warning:`, 0 `✘` |
| `Packages/TendAI` | Not run: Apple-only (`AVFAudio`, `Speech`); its `Package.swift` says it is never built on Linux. B4/B5 on the owner's Mac are the evidence. |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | **Major** | `MicrophoneAudioSource.swift:46-54`, `:56-98`; `SpeechTranscriptionAdapter.swift:197-198` | **A `stop()` that comes before `start()` has stored its state is lost, and the microphone keeps running.** `start()` sets up the audio session (`:58-62`, slow on iOS), creates the engine, reads `inputNode` and installs the tap. Only then does it store `engine` and `continuation` under the lock (`:93-96`) and start the engine (`:98`). `stop()` reads `continuation` and `engine` under the lock, finds both nil, and does nothing. `start()` then stores them and starts the microphone. The window is real: `run` emits `.transcriberChosen` (`:197`) *before* it calls `source.audio(in:)` (`:198`), so a UI that shows "listening" on that event, or a hold-to-talk release (Action Button, FR-A1), can call `stop()` inside it. Then the capture keeps recording after the person stopped. Audio spoken after "stop" reaches the transcriber and the transcript, and the microphone indicator stays on. This is wrong behaviour in a real scenario and a concurrency hazard (OPERATING_MODEL §6 Major), and it touches the person's consent to record (P-4 spirit). | Make `stop()` sticky. Keep a lock-guarded state (`idle` → `starting` → `running` → `stopped`). `stop()` always moves it to `stopped`. `start()` checks the state under the same lock before it activates the session and again when it stores the engine. If the state is `stopped`, it finishes the continuation normally, does not start the engine, and deactivates the session. Put this state in a small internal type with no AVFoundation in it, so it can be unit-tested: stop before start, stop during start, stop twice, termination before start. Add a DS-1 step for the Tester (stop within 0.5 s of "listening"; the capture ends and the microphone indicator goes off). | Open |
| m1 | Minor | `MicrophoneAudioSource.swift:34-43`, `:101-107` | **Reusing one source for a second capture is unsafe.** `tearDown()` stops whatever engine is in `self.engine`, not the engine of the stream being terminated. If `audio(in:)` is called again while a capture runs, the first engine is overwritten (and orphaned with its tap still on), and the first stream's `onTermination` then stops the second capture. The public API does not say "one capture at a time". | Either refuse a second `audio(in:)` while one is active (finish it with `audioNotStarted`), or tie each stream's teardown to its own engine (compare identity). Document the rule in the type's doc comment. | Open |
| m2 | Minor | `MicrophoneAudioSource.swift:58-68`, `:73`, `:88`, `:109-113` | **Cleanup on the error paths.** (a) On iOS the session is set active at `:61`; if the converter cannot be made (`:66-68`), `start()` throws before the engine is stored, so `tearDown()` never deactivates the session. Other apps' audio stays ducked or stopped. (b) A conversion error calls `continuation.finish(throwing:)` from inside the tap block. That runs `onTermination` → `tearDown()` → `removeTap(onBus:)` and `engine.stop()` on the tap thread, inside the tap callback. Apple does not document this as safe. | (a) Deactivate the session on every early exit from `start()`. (b) Do the teardown off the tap thread, or add a DS-1 note that checks this path. Both paths are error-only, so this does not block. | Open |
| m3 | Minor | `MicrophoneAudioSource.swift:26-27` | The `@unchecked Sendable` justification overclaims (see §1): the engine's methods run outside the lock at `:97-98` and `:109-110`. | Rewrite the comment to say exactly what the lock guards (the two stored fields and, after M1, the state) and why the unlocked engine calls cannot overlap. | Open |
| m4 | Minor | `SpeechTranscriptionAdapter.swift:194-196` | **No fallback when the chosen transcriber has no audio format.** If SpeechTranscriber is chosen but `bestAvailableAudioFormat` returns nil, the capture ends `unavailable(audioFormatUnavailable)` without trying DictationTranscriber, which may be usable. The plan's order (`plan.md:98`) is "SpeechTranscriber, falling back to DictationTranscriber". This is unlikely on a device that reports SpeechTranscriber available, so it does not block. | Try the other transcriber when the chosen one has no format (and report the one used), or record in dev-notes why a nil format is terminal. Add a fake-engine test either way. | Open |
| m5 | Minor | `SpeechTranscriptionAdapter.swift:300` | `(try? await AssetInventory.assetInstallationRequest(…)) ?? nil` treats a **throw** as "installed" and goes on to analysis. That is safe for P-2 (analysis does not download), but it fails open on an unknown asset state, and it differs from the non-nil branch. Neither branch is tested; the dev notes' own risk (a device that lists a locale as installed while analysis still needs a download) depends on it. | Treat a throw like a pending request (`assetsMissing` → `stopped(transcriptionStopped)`), or say in a comment why going on is right. Ask the Tester to record the outcome of DS-2's airplane-mode run, which exercises this call offline. | Open |
| n1 | Nit | `SpeechCaptureTests.swift:243-249` | The "independent table" in `everyCombination` repeats the implementation's boolean expressions, so it is not independent. The explicit `preference` cases and mutant S1 do cover the order. | Optional: use a literal expected table, or drop "independent" from the test name. | Open |
| n2 | Nit | `SpeechRealEngineTests.swift:52-61`, `:74-75` | If `say` creates the file and then exits non-zero, `#require` throws inside `make()` before the caller's `defer` is set, so the temporary file is left behind. The content is a synthetic sentence, not household audio. | Optional: delete the file inside `make()` on failure. | Open |
| i1 | Info | `SpeechTranscriptionAdapter.swift:167` | `SpeechCapture` does not check the microphone permission. On iOS a denied permission gives silent buffers, so the capture would end `nothingHeard`. | M3 / Designer: call `SpeechPermission` before a capture and show the calm Settings path for `notAllowed`. | — |
| i2 | Info | dev-notes "Known limitations" | `NSMicrophoneUsageDescription` is needed in the app and `TendEval` targets before DS-1/DS-2. | Designer (string) + WI-M2-M7 `project.yml`, as the dev notes ticket says. | — |
| i3 | Info | — | AC-M2-11 and AC-M2-25 stay AWAITING-DEVICE. | Acceptance Tester: DS-1/DS-2 record the transcriber used, that only the microphone prompt appears (T-27), the airplane-mode outcome, and the M1 quick-stop step. | — |
| i4 | Info | — | `docs/product/TRACEABILITY.md` has no rows yet for the WI-M2-M3 tests. | Documenter: add AC-M2-09 / 11 / 25 → test rows. | — |

## Checklist
- [x] Correctness vs ACs: transcriber choice and order, transcriber reported, final transcript only, T-27, Rule 2 and
  Rule 5 scan. The gap is in the live microphone source (M1), which no headless test can run.
- [x] Tests meaningful (would fail if code broke): exact event sequences; cancellation checks that both audio and
  transcriber stop; real-engine transcription on the Mac; 6 mutants killed per the dev notes. Oracle duplication n1.
- [ ] Swift 6 concurrency safe: no data race, and the build has no warnings, but the stop/start ordering in the one
  `@unchecked Sendable` type is unsafe (M1); `@unchecked Sendable` not signed off in this round.
- [x] No force unwraps / `try!` in product code paths (`grep`; the only `try?` is m5 and the session deactivate).
- [x] Privacy (P-1…P-4): on-device modules only, no `SFSpeech*`, no networking, no download, nothing written or
  logged. M1 is a consent concern, not a persistence one.
- [x] UX-2/UX-3 enforced in engine: UX-2 n.a.; UX-3 names tested against `BannedTokens`.
- [ ] Accessibility (UI): n.a. (no UI).
- [x] Performance: per-buffer allocation of one converted `AVAudioPCMBuffer` (needed, since buffers are passed on);
  no main-actor work in the adapter.
- [x] No new dependency without ADR: Apple frameworks only, in TendAI's closed import list.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Voice capture is a primary entry; no form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Outcome and reason names are neutral and tested against `BannedTokens`; none blames the person. |
| UX-4 Design craft | n.a. | No UI in this PR. |
| P-1 On-device inference | pass | `SpeechAnalyzer` with `SpeechTranscriber` / `DictationTranscriber` only; no `SFSpeech*`; T-27 exception off (scan). |
| P-2 No data leaves device (except user iCloud) | pass | No networking API; no asset download started (`assetInstallationRequest` only reads whether one is needed; m5). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud step here. |
| P-4 Media not persisted without consent | concern | Nothing is persisted or logged (pass). Concern: M1 lets the microphone keep recording after the person pressed stop, so audio they did not mean to give reaches the transcript. Fix M1. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Developer | Reviewer (via Orchestrator) | accepted for review | PR #42 at `d5d9c97`; sign-off asked for the one `@unchecked Sendable`. |
| 2026-11-27 | Reviewer | Developer (via Orchestrator) | returned | Round 1: CHANGES REQUIRED (M1). `@unchecked Sendable` not signed off until M1 and m3 are fixed. Minors m1–m5 to be fixed or ticketed; Nits optional. Tester: add the M1 quick-stop step to DS-1. |

---

## Round 2 — PR #44 (`m2/speech-adapter-v2`, head `7479152`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **CHANGES REQUIRED**  ·  **Round:** 2
- **Scope:** `git diff 895f5c1 7479152`: `118fcbe` (code and tests, `Packages/TendAI` only: 6 files, one new source
  `MicrophoneCaptureState.swift`, one new test file) and `7479152` (docs only: the dev-notes round-2 section and the
  Mac evidence record `evidence/mac/WI-M2-M3-r2/`). Same requirements as round 1: AC-M2-09 (Rules 2 and 5, T-27
  exception off), the Mac halves of AC-M2-11 and AC-M2-25, T-27, FR-A1, P-1, P-4, UX-3.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`; an `m2/` work item is allowed (CLAUDE.md §5).
  No protected path is touched (`git diff --name-only 895f5c1 7479152` lists only `Packages/TendAI/**` and
  `docs/milestones/M2/**`).

### Summary
Most of round 1 is fixed well. The new `MicrophoneCaptureState` is a clean, AVFoundation-free state machine with
real unit tests for stop-before-start, stop-during-start, stop-twice, one-at-a-time and per-token teardown. m1, m2,
m4, m5, n1 and n2 are closed. But the **M1 fix is not complete**: the source marks the capture `running` and
publishes the engine *before* it calls `engine.prepare()` / `engine.start()`. A `stop()` (or the stream's
termination) in that window takes the engine and tears it down on its own thread while the start path is still
calling `prepare()`/`start()` on the same engine on another thread. That is the same check-then-act class as round-1
M1, moved later in `start()`, and it makes the new `@unchecked Sendable` justification ("no two threads ever call one
engine at the same time") false. I therefore keep M1 open (narrowed, below as **M1-r2**) and **do not sign off the
`@unchecked Sendable` in round 2**.

### Round-1 findings, verified in the new diff
| # | Round-1 ask | What I found at `118fcbe` | Status |
|---|---|---|---|
| M1 | Sticky stop via a lock-guarded lifecycle, checked before session activation and when the engine is stored; unit-tested without AVFoundation; stop-during-start tested | `MicrophoneCaptureState` (`MicrophoneCaptureState.swift:216-295`) has `idle/starting/running/stopRequested`; `stop()` while starting is remembered (`:249-251`); `mayActivate` (`:260-268`) is asked before the iOS session (`MicrophoneAudioSource.swift:76`) and `markRunning` (`:272-282`) when the engine is stored (`:122-126`). Unit tests: `MicrophoneCaptureStateTests.swift:10-36` (stop before activation, stop after activation before store), `:38-54` (stop while running, stop twice), `:99-106` (idle stop). Termination-before-start is covered by `end(token)` and the per-token tests (`:76-97`). **But** `markRunning` runs *before* `engine.prepare()`/`engine.start()` (`MicrophoneAudioSource.swift:122-135`), so a stop in that window is not sticky — see M1-r2. | **Open (narrowed → M1-r2)** |
| m1 | Refuse a second capture, or tie teardown to its own engine | Both done. `begin()` returns nil unless `idle` (`MicrophoneCaptureState.swift:239-244`); the source finishes the second stream with `audioNotStarted` without touching the first (`MicrophoneAudioSource.swift:47-50`). Engine and continuation are stored with their token; `takeEngine(token)` (`:182-188`), `end(token)` (`:156-163`) and `finishStart` (`:145-153`) only touch their own capture. Rule documented in the type comment (`:8-9`). Tested: `oneAtATime`, `endIsPerToken`. | **Closed** |
| m2 | (a) session inactive on every early exit; (b) conversion-stop teardown off the tap thread | (a) `finishStart(…, sessionActive: true)` on the session-activation failure (`:87`), the converter failure (`:95`), and the stopped-before-store path (`:130`); `tearDown` deactivates after an engine-start failure (`:137-139`). (b) `conversionStopped` (`:166-179`) does the state change, teardown and `finish(throwing:)` in a `Task`, not in the tap. Untestable headless; B5 builds the iOS paths. | **Closed** |
| m3 | Comment says exactly what the lock guards and why unlocked engine calls cannot overlap | The comment (`:31-37`) now names the three guarded fields correctly. Its second claim — only the token owner calls engine methods, "the start path until `markRunning` succeeds, then whoever takes the engine out" — is **not what the code does**: the start path keeps calling `prepare()`/`start()` (`:134-135`) *after* `markRunning` has published the engine for `stop()`/`end()` to take. The comment will be true once M1-r2 is fixed. (Also: the tap now captures `[weak self]` (`:99`), so "the tap block only reads the converter … and calls the continuation" should mention it.) | **Open (folds into M1-r2)** |
| m4 | Try the next transcriber when the chosen one has no audio format | `run` loops with an `excluded` set (`SpeechTranscriptionAdapter.swift:198-214`); `TranscriberChoice.choose(…excluding:)` (`:113-119`) marks excluded kinds unusable, so the loop ends in at most three passes. The kind actually used is emitted and carried in the final transcript. Tests: `SpeechRoundTwoTests.formatFallback` checks `.transcriberChosen(.dictationTranscriber)` first and the final `FinalTranscript(…, transcriber: .dictationTranscriber)`; `noFormatAnywhere` checks no audio was ever requested; `noFallback`; `exclusion`. | **Closed** |
| m5 | Thrown asset request = not installed; both branches tested | `AssetCheck.installed` (`SpeechTranscriptionAdapter.swift:386-394`) returns true only for a nil request; a non-nil request and a throw both return false, which leads to `assetsMissing` → `stopped(transcriptionStopped)` (`:318-323`). Tested for nil, non-nil and throw (`SpeechCaptureTests.swift` `assetCheck`). No download call added (`grep` for `downloadAndInstall`/`reserve(` in `Sources`: 0). | **Closed** |
| n1 | Oracle not independent | "independent table" dropped from the test name. | **Closed** |
| n2 | `say` temp file leak on failure | `make()` deletes the file on any thrown error (`SpeechRealEngineTests.swift:57-65`). | **Closed** |

### No tests weakened
`git diff 895f5c1 118fcbe -- Packages/TendAI/Tests | grep '^-'` shows only: the two `ScriptedEngine` methods replaced
for the new `choice(for:excluding:)` signature (behaviour for `excluding: []` unchanged), the n1 rename, and the n2
`say` lines moved into a `do/catch` (same `#require`). No assertion removed; no test skipped or disabled.

### `@unchecked Sendable` decision (`MicrophoneAudioSource.swift:30`) — **NOT SIGNED OFF in round 2**
Field by field: `lock` is a `let NSLock`; `state`, `engine`, `continuation` are read and written only inside
`lock.withLock` (`:47`, `:51`, `:60-67`, `:76`, `:122-126`, `:137`, `:147-150`, `:157-161`, `:169-174`, `:183-187`).
No stored-field race. The tap block captures `[weak self]`, the `Sendable` continuation, `format`, `ratio`, the
token and the tap-confined `converter`; that part is fine. What fails is the one non-field claim the type rests on:
exclusive ownership of the `AVAudioEngine` object. The interleaving (stop from the main actor while `audio(in:)` runs
inside `SpeechCapture.run` on the cooperative pool):

1. Start thread: `markRunning(token)` → `running`, `self.engine = (token, engine)` (`:122-126`), lock released.
2. Main thread: `stop()` → `state.stop()` returns `.wasRunning(token)` (`:62`), takes the continuation, then
   `tearDown(takeEngine(token))` → `removeTap(onBus:)`, `engine.stop()`, session set inactive (`:190-195`), then
   `continuation.finish()`.
3. Start thread, concurrently with 2: `engine.prepare()`; `try engine.start()` (`:134-135`).

Steps 2 and 3 call `removeTap`/`stop` and `prepare`/`start` on one engine from two threads, which `AVAudioEngine`
does not document as safe. If step 3 wins after step 2, the engine starts *after* the person stopped (on iOS it can
re-activate the session the stop just released), with no tap and no owner, until it is released at the end of
`start()`. The same applies to the stream's termination (`end(token)`, `:156-163`) in that window. `prepare()` and
`start()` are the slowest calls in the path (hardware I/O set-up), so the window is not negligible, and it is exactly
the "stop during start" case round-1 M1 asked to make sticky.

I sign off when M1-r2 is fixed and the comment matches. The test-only `nonisolated(unsafe) var given` stays signed
off from round 1; no other `@unchecked Sendable` or `nonisolated(unsafe)` exists in `Packages/TendAI`
(`grep -rn` over `Sources` and `Tests`).

### Evidence record (`evidence/mac/WI-M2-M3-r2/`)
- **Commit named:** `README.md` and `logs/mac-B0-header.log` both give `118fcbee2b6049c72eb9cfabb638600341701939`,
  which is `7479152^`.
- **`7479152` is docs only:** `git diff --numstat 118fcbe 7479152` lists only paths under `docs/` (the dev-notes
  section and the 20 evidence files).
- **SHA-256:** the README lists 16 files; `sha256sum -c` on those lines: **16/16 OK**.
- **No personal data:** `grep -rniE '<owner login>|<owner name>|Mac-mini|/Users/|/var/folders'` over the folder: 0 hits. The
  only `.local` hits are the `$HOME/.local/...` token path for XcodeGen and in the build `PATH`, not a hostname.
  Paths use the MS-1 tokens.
- **Commit identities neutral:** `git log --format='%an <%ae> | %cn <%ce>' 41bf8fa..7479152`: every commit is
  `Claude <noreply@anthropic.com>` for author and committer.
- **Logs agree with the claims:** B4 `✔ Test run with 29 tests in 8 suites passed`, including the suites "Microphone
  capture state (WI-M2-M3; review PR #42 M1, m1)" and "Speech round 2 (WI-M2-M3; review PR #42 m4, m5)" and both
  real-engine tests; B5 4 tests in 2 suites; `timings.txt` exits match the README (B6-eval-archive 66 as expected).
  The only `warning:` lines are the non-compiler `appintentsmetadataprocessor` and interface-orientation notices
  already ticketed in MS-1.

### What I ran (Linux container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `7479152`)
| Package | Result |
|---|---|
| `Packages/TendCore` | exit 0, `✔ Test run with 141 tests in 18 suites passed`; 0 `warning:`, 0 `✘`; the "skipped" text hits are test output, not skipped tests |
| `Packages/TendIngestion` | exit 0, `✔ Test run with 571 tests in 67 suites passed`; 0 `warning:`, 0 `✘`. Scan: "Rule 5 T-27 exception OFF"; "TendAI (required) Packages/TendAI/Sources: 5 files scanned" (incl. `MicrophoneCaptureState.swift`); TendIngestion 55, TendEval 1; "61 files in total, 0 violations" (matches B2) |
| `Packages/TendSourceScan` | exit 0, `✔ Test run with 63 tests in 4 suites passed`; 0 `warning:`, 0 `✘` |
| `Packages/TendAI` | Not run: Apple-only (`AVFAudio`, `Speech`). B4/B5 in the Mac record are the evidence. |

### Round 2 findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1-r2 | **Major** | `MicrophoneAudioSource.swift:122-140`, `:31-37` | **Stop during engine start is still not sticky, and two threads can call one `AVAudioEngine`.** `markRunning` moves the state to `running` and publishes the engine before `engine.prepare()`/`engine.start()`. A `stop()` or stream termination in that window tears the engine down on its own thread while the start path calls `prepare()`/`start()` on it; if `start()` lands last, the microphone starts after the person stopped (FR-A1 hold-to-talk, P-4 consent). The `@unchecked Sendable` comment claims this overlap cannot happen. | Keep the phase `starting` until the engine has started: install the tap, `prepare()`, `try start()`, and only then call `markRunning(token)` and store the engine under the lock. If `markRunning` answers false (a stop or termination arrived meanwhile), the start path itself removes the tap, stops its own engine, sets the session inactive and finishes the stream normally. Then only the start path ever touches the engine before `markRunning` succeeds, and the comment is true (also mention the tap's `[weak self]`). Update the `MicrophoneCaptureState` doc comment (`:208-210`, "`markRunning` when it stores the engine") to "after the engine has started". The existing `stopDuringStart` state test already covers the state rule; add a line in dev-notes naming the new order, and keep the DS-1 quick-stop step. | Open |
| m6 | Minor | `MicrophoneAudioSource.swift:62-70`, `:156-163`; `MicrophoneCaptureState.swift:252-254`, `:263-265`, `:278-279`, `:288-289` | The state goes back to `idle` *before* the old capture's teardown has run, so a new `audio(in:)` can begin while the previous `tearDown`/`finishStart` is still about to call `deactivateSession()`. On iOS, deactivating the shared session with running I/O stops the new capture's engine (it would then end "nothing heard"). Needs a very fast re-press, so it does not block. | Either hold a `stopping(token)` phase that `begin()` refuses until the teardown is done (then `idle`), or record in dev-notes why the window is acceptable and add a DS-1 note (stop, then start again at once). | Open |
| i5 | Info | `MicrophoneAudioSource.swift:99-119` | After a conversion failure each later buffer also schedules a `conversionStopped` task until the teardown runs; only the first acts (the others find the state ended). Harmless; noted for the Tester's DS-1 error path. | — | — |

Round-1 Info items i1–i4 stand unchanged (permission check before capture and `NSMicrophoneUsageDescription` for
M3 / WI-M2-M7; AC-M2-11 and AC-M2-25 stay **AWAITING-DEVICE**; TRACEABILITY rows for the WI-M2-M3 tests).

### Checklist (round 2)
- [x] Correctness vs ACs: transcriber order with format fallback (m4), transcriber reported, final transcript only,
  T-27, AC-M2-09 scan (61 files, 0 violations, T-27 exception off).
- [x] Tests meaningful: the state tests would fail on a lost sticky stop or a shared teardown (the dev notes' mutants
  agree); m4/m5 tests check exact events and every branch. No test weakened.
- [ ] Swift 6 concurrency safe: no stored-field race, no compiler warning, but the engine-ownership claim fails
  (M1-r2); `@unchecked Sendable` not signed off.
- [x] No force unwraps / `try!` in product code (`grep`).
- [x] Privacy (P-1…P-4): on-device only, no `SFSpeech*`, no networking, no download, nothing written or logged;
  M1-r2 is a consent concern.
- [x] UX-2/UX-3: UX-2 n.a.; UX-3 names unchanged and tested against `BannedTokens`.
- [ ] Accessibility (UI): n.a. (no UI).
- [x] Performance: unchanged; the per-buffer allocation is needed.
- [x] No new dependency without ADR.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Voice capture, no form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No new outcome or reason name; existing names checked against `BannedTokens`. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | `SpeechAnalyzer` with `SpeechTranscriber`/`DictationTranscriber` only; scan Rule 5 exception off. |
| P-2 No data leaves device | pass | No networking; a thrown or pending asset request now ends the capture, never a download (m5). |
| P-3 Cloud escalation per ADR | n.a. | No cloud step. |
| P-4 Media not persisted without consent | concern | Nothing persisted or logged (pass). Concern: M1-r2 can still start the microphone after the person stopped. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Developer | Reviewer (via Orchestrator) | accepted for review | PR #44 at `7479152` (code `118fcbe`); round-1 fixes; `@unchecked Sendable` sign-off asked again. |
| 2026-11-27 | Reviewer | Developer (via Orchestrator) | returned | Round 2: **CHANGES REQUIRED** (M1-r2 Major: mark running only after `engine.start()`). m1, m2, m4, m5, n1, n2 closed; m3 folds into M1-r2; new Minor m6. `@unchecked Sendable` not signed off. Tester: keep the DS-1 quick-stop step and add stop-then-start-at-once (m6). |

---

## Round 3 — PR #44 (`m2/speech-adapter-v2`, head `774db72`, round-2 head `99a4841`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 3
- **Scope:** `git diff 99a4841 774db72`: `33bab80` (code and tests, 3 files, all in `Packages/TendAI`:
  `MicrophoneAudioSource.swift`, `MicrophoneCaptureState.swift`, `MicrophoneCaptureStateTests.swift`) and `774db72`
  (docs only: dev-notes round-3 section and the Mac evidence record `evidence/mac/WI-M2-M3-r3/`). Requirements as in
  rounds 1–2: FR-A1 (hold-to-talk capture), the Mac halves of AC-M2-11 and AC-M2-25, AC-M2-09 (scan, T-27 exception
  off), T-27, P-1, P-4, UX-3.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`; an `m2/` work item is allowed (CLAUDE.md §5).
  No protected path is touched (`git diff --name-only 99a4841 774db72` lists only `Packages/TendAI/**` and
  `docs/milestones/M2/**`).

### Summary
M1-r2 is fixed the way round 2 asked, and m6 is fixed with a real `stopping` phase. The start path now owns the
`AVAudioEngine` alone from creation until `engine.start()` has returned; only then is it published under the lock.
A stop or termination in that window only changes the state, and the start path tears down its own engine. I traced
every interleaving of `start`, `stop()`, `end(token)` (termination) and `conversionStopped` against the new state
machine and found no path where two parties call one engine, no path where the microphone keeps running after a stop,
and no path where an old teardown's session deactivation can overlap a new capture. **I sign off the
`@unchecked Sendable` on `MicrophoneAudioSource` in this round.** No Blocker or Major is open; two Nits and three Info
items are new and do not block.

### Round-2 findings, verified in the new diff
| # | Round-2 ask | What I found at `33bab80` | Status |
|---|---|---|---|
| M1-r2 | Engine created, tap installed, `prepare()` and `start()` called, and only then `markRunning` + publish; a stop/termination during start only sets `stopRequested`; the start path stops its own engine, deactivates the session, finishes the stream normally; comments match | `MicrophoneAudioSource.swift:91-128`: engine made (`:91`), converter made (`:94`), tap installed (`:99`), `prepare()` (`:123`), `try start()` (`:124`); only then `markRunning(token)` and `self.engine = (token, engine)` in one `lock.withLock` (`:130-134`). If `markRunning` is false (`MicrophoneCaptureState.swift:82-84`: `stopRequested` → `stopping`), the start path takes its continuation, calls `tearDown(engine, …)` on **its local engine** (tap removed, `stop()`, session inactive, `finishTeardown`) and `continuation.finish()` normally (`:135-141`). `stop()` on a starting capture returns `.wasStarting` and touches nothing (`MicrophoneCaptureState.swift:53-55`, `MicrophoneAudioSource.swift:66-67`); `end(token)` on a starting capture sets `stopRequested`, returns false, so `takeEngine` is never called (`MicrophoneCaptureState.swift:106-108`, `MicrophoneAudioSource.swift:156-158`; and there is nothing published to take). A conversion stop from the tap before `markRunning` also only sets `stopRequested` (`:165`). An engine-start failure goes through `giveUp` → `startGaveUp` → `stopping` → teardown by the start path (`:125-127`, `:145-151`). Comments: the type header (`:6-10`), the `@unchecked Sendable` justification (`:35-43`) and the state doc (`MicrophoneCaptureState.swift:9-12`, `:74-76`) now describe exactly this order. Tests: `stopDuringEngineStart`, `terminationDuringEngineStart`, `stopBeforeActivation`. | **Closed** |
| m3 | Comment matches the code | Folded into M1-r2; the engine-ownership claim is now true. The `[weak self]` mention round 2 asked for is still missing (new Nit n3). | **Closed** |
| m6 | `stopping(token)` phase that `begin()` refuses until teardown (incl. session deactivation) is done; tested | New `Phase.stopping` (`MicrophoneCaptureState.swift:25-26`). Every path to a teardown enters it: running `stop` (`:56-58`), running `end` (`:103-105`), `markRunning` after a stop (`:82-84`), `startGaveUp` (`:91-95`). `begin` gives a token only in `idle` (`:43-44`). `finishTeardown(token)` (`:115-117`) is the only way out of `stopping`, and it is called as the **last** step of `tearDown`, after `removeTap`, `engine.stop()` and `deactivateSession()` (`MicrophoneAudioSource.swift:190-197`). The one non-teardown exit, `mayActivate` after a stop (`:67-69`), goes straight to `idle`, which is correct: nothing was activated. Tests: `stopWhileRunning`, `noOverlapAfterTermination`, `startGaveUp`, plus `begin() == nil` during `stopping` in `stopDuringEngineStart`. | **Closed** |
| i5 | (Info) repeated `conversionStopped` tasks | Unchanged and still harmless: only the first finds `running`; the rest find `stopping`/`idle` and return (`:165`). | — |

### Interleavings traced (`MicrophoneAudioSource.swift` at `33bab80`)
1. **Stop during `prepare()`/`start()`.** `stop()` → `.wasStarting`, returns. Start path: `markRunning` false →
   local teardown → `finishTeardown` → `idle` → `finish()` → `onTermination` → `end(token)` finds `idle`, false. One
   party touched the engine. PASS.
2. **Termination during start.** `end(token)` → `stopRequested`, takes the stored continuation (the start path keeps
   its own parameter copy), does not tear down. Start path ends as in 1. PASS.
3. **Stop while running, racing a termination or a conversion stop.** Under the lock exactly one of `stop()` /
   `end(token)` / the conversion task moves `running` → `stopping` and gets the engine; the others see `stopping`
   and return. PASS.
4. **Re-press during teardown (m6).** `begin()` is nil while `stopping`; the second `audio(in:)` finishes with
   `audioNotStarted` and never touches the first. Idle only after the session was deactivated. PASS.
5. **Stale token after teardown.** `stop()` path calls `finishTeardown` before `continuation.finish()`, so a new
   `begin()` can get `token+1` before the old `onTermination` runs; the old `end(token)` matches neither
   `.running(token+1)` nor `.starting(token+1)` and is a no-op. Tested by `perToken`. PASS.
6. **Lock discipline.** Every read/write of `state`, `engine`, `continuation` is inside `lock.withLock` (`:53`, `:57`,
   `:66`, `:75`, `:130-134`, `:147`, `:156`, `:165`, `:173-177`, `:182-186`, `:196`). No `continuation.finish()` or
   engine call is made while the lock is held, so the synchronous `onTermination` → `end` cannot deadlock.

### `@unchecked Sendable` decision (`MicrophoneAudioSource.swift:34`) — **SIGNED OFF in round 3**
Stored fields: `lock` is a `let NSLock`; `state`, `engine`, `continuation` are only touched under it (item 6 above).
Engine ownership: exclusive to the start path until it is published after `start()` (`:130-134`), then taken out
exactly once under the lock (`takeEngine`, `:181-187`) by the single caller that moved the state to `stopping`. The
tap block captures the `Sendable` continuation, `format`, `ratio`, the token, the tap-confined `converter` (made
before `installTap`, never changed) and `[weak self]`, through which it only calls `conversionStopped` (one lock
acquisition plus a `Task`). The justification comment (`:35-43`) is accurate apart from the missing `[weak self]`
mention (Nit n3, not load-bearing). The test-only `nonisolated(unsafe) var given`
(`SpeechRealEngineTests.swift:30`) stays signed off from round 1; `grep -rn '@unchecked Sendable\|nonisolated(unsafe)'
Packages/TendAI` finds no others.

### Tests: real, and none weakened
- `git diff 99a4841 774db72 -- Packages/TendAI/Tests | grep '^-'`: the old tests were rewritten for the new phase,
  not dropped. Every removed assertion has a counterpart or no longer applies: `stopBeforeActivation` no longer checks
  `markRunning` after a refused `mayActivate` (the start path returns there and never calls it; the mutant below
  that makes `mayActivate` answer true after a stop is still killed); "allowed after it ends" moved to
  `noOverlapAfterTermination` and `stopWhileRunning`, which now also require the `finishTeardown` step;
  `phase == .running` is still asserted in `perToken`. No test skipped or disabled; no `.disabled`, `withKnownIssue`
  or `#if false` added.
- **Mutants, run by me** (Linux Docker `swift:6.2-noble`, `MicrophoneCaptureState.swift` and
  `MicrophoneCaptureStateTests.swift` copied unchanged into a scratch package; both are Foundation-only). Unmutated:
  all pass. Killed: running `stop` → `idle` (m6); `markRunning` after a stop → `running`/true (M1-r2); termination
  during start not recorded; `begin` allowed while `stopping`; `startGaveUp` → `idle`; `mayActivate` true after a
  stop; running `end` → `idle`; stop while starting ignored; `finishTeardown` unconditional. **10 of 11 killed.**
  The survivor, `finishTeardown` ignoring the token while in `stopping` of another token, is an equivalent mutant in
  practice: with `begin` refused during `stopping`, only the owner of the current `stopping(token)` can call
  `finishTeardown` (Info i8). This agrees with the dev notes' killed list.
- The `MicrophoneAudioSource` paths themselves need audio hardware; they are built in B4/B5 and stay for DS-1/DS-2
  (AC-M2-11, AC-M2-25 remain **AWAITING-DEVICE**).

### Evidence record (`evidence/mac/WI-M2-M3-r3/`)
- **Commit named:** `README.md` and `logs/mac-B0-header.log` give `33bab8051a427ae88c46de60b840b5c6a67b328c`, which is
  `774db72^` (`git rev-parse`).
- **`774db72` is docs only:** `git diff --name-only 33bab80 774db72` lists only `docs/` paths (dev-notes and the 17
  files of the record).
- **SHA-256:** the README lists 16 files; `sha256sum -c` on those lines: **16/16 OK**.
- **No personal data:** `grep -rniE` for the owner's names, `Mac-mini`, `/Users/`, `/var/folders`, `/home/`, e-mail
  addresses, `.lan`/`.home`: 0 hits. Paths use the MS-1 tokens (`$HOME`, `$REPO`, …). `Macmini9,1` is the hardware
  model identifier, not a hostname (as in rounds 1–2).
- **Commit identities neutral:** `git log --format='%an <%ae> | %cn <%ce>' 99a4841..774db72`: both commits are
  `Claude <noreply@anthropic.com>` for author and committer.
- **Logs agree with the claims:** B4 `✔ Test run with 32 tests in 8 suites passed` including the suite "Microphone
  capture state (WI-M2-M3; review PR #42 M1, m1, M1-r2, m6)"; `timings.txt` exits match the README (B6-eval-archive
  66 as expected). The only `warning:` lines are the `appintentsmetadataprocessor` and interface-orientation notices
  already ticketed in MS-1; no compiler warning.

### What I ran (Linux container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `774db72`)
| Package | Result |
|---|---|
| `Packages/TendCore` | exit 0, `✔ Test run with 141 tests in 18 suites passed`; 0 `warning:`, 0 `✘`, 0 `error:` |
| `Packages/TendIngestion` | exit 0, `✔ Test run with 571 tests in 67 suites passed`; 0 `warning:`, 0 `✘`, 0 `error:`. Scan: "Rule 5 T-27 exception OFF"; TendIngestion 55, TendAI 5, TendEval 1; "61 files in total, 0 violations" (matches B2) |
| `MicrophoneCaptureState` mutants | scratch package, see above: 10/11 killed, survivor equivalent |
| `Packages/TendAI` | Not run: Apple-only (`AVFAudio`, `Speech`). B4/B5 in the Mac record are the evidence. |

### Round 3 findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n3 | Nit | `MicrophoneAudioSource.swift:40-42` | The justification says "the tap block only reads the converter … and calls the continuation"; it also calls `self?.conversionStopped(token)` through `[weak self]` (round 2 asked for the mention). Not load-bearing: that call only takes the lock and schedules a `Task`. | Optional: add "and, through `[weak self]`, `conversionStopped`". | Open (optional) |
| n4 | Nit | `MicrophoneAudioSource.swift:190`, `:195` | `tearDown`'s `sessionActive` parameter defaults to `true` and every caller passes `true` or nothing, so `engine != nil \|\| sessionActive` is always true; the parameter is dead. | Optional: drop it and always deactivate, or pass `false` where the session was never activated. | Open (optional) |
| i6 | Info | `MicrophoneAudioSource.swift:162-169`, `:130-141` | A conversion failure in the microseconds between `engine.start()` and `markRunning` is recorded as a stop, so the stream ends normally rather than with `conversionStopped`. The microphone still stops; only the reason differs. | — | — |
| i7 | Info | `MicrophoneAudioSource.swift:125-127` | If the person stopped during start and `engine.start()` then throws, the stream ends with `audioNotStarted` rather than an empty utterance. Correct teardown; for the Tester's DS-1 error-path wording only. | — | — |
| i8 | Info | `MicrophoneCaptureState.swift:115-117` | The token check in `finishTeardown` is not killed by a test (equivalent mutant under the one-at-a-time rule). No test needed. | — | — |

Round-1/2 Info items i1–i5 stand (permission check and `NSMicrophoneUsageDescription` for M3 / WI-M2-M7; AC-M2-11
and AC-M2-25 stay **AWAITING-DEVICE**; TRACEABILITY rows for the WI-M2-M3 tests are the Documenter's).

### Checklist (round 3)
- [x] Correctness vs ACs: FR-A1 capture start/stop order, T-27, AC-M2-09 scan (61 files, 0 violations, T-27
  exception off); the Mac halves of AC-M2-11/AC-M2-25 built and tested in B4/B5.
- [x] Tests meaningful: state tests kill 10/11 mutants (my run); no test weakened.
- [x] Swift 6 concurrency safe: no stored-field race, exclusive engine ownership, no lock held across `finish()`;
  `@unchecked Sendable` signed off.
- [x] No force unwraps / `try!` in the changed product files (`grep`).
- [x] Privacy (P-1…P-4): on-device only; no networking; nothing written or logged; the microphone cannot keep
  running after a stop.
- [x] UX-2/UX-3: UX-2 n.a.; UX-3 no new user-facing name.
- [ ] Accessibility (UI): n.a. (no UI).
- [x] Performance: unchanged.
- [x] No new dependency without ADR.

### Law check (round 3)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Voice capture (FR-A1), no form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No new outcome, reason or copy; `MicrophoneAudioStop` names unchanged. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | `SpeechAnalyzer` path unchanged; AC-M2-09 scan Rule 5 exception off, 0 violations. |
| P-2 No data leaves device | pass | No networking, no download added. |
| P-3 Cloud escalation per ADR | n.a. | No cloud step. |
| P-4 Media not persisted without consent | pass | Buffers passed on in memory, nothing written or logged; the round-2 concern (microphone starting after a stop, M1-r2) is closed. |

### Handoff log (round 3)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Developer | Reviewer (via Orchestrator) | accepted for review | PR #44 at `774db72` (code `33bab80`); M1-r2 and m6 fixes; `@unchecked Sendable` sign-off asked again. |
| 2026-11-27 | Reviewer | Merge Gatekeeper / Acceptance Tester (via Orchestrator) | accepted | Round 3: **APPROVE**. M1-r2, m3, m6 closed; `@unchecked Sendable` signed off. New Nits n3, n4 optional; Info i6–i8. Tester: DS-1 keeps the quick-stop step and the stop-then-start-at-once step (m6); AC-M2-11 and AC-M2-25 stay AWAITING-DEVICE. |
