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
- **No personal data:** `grep -rniE 'dharanbro|Mac-mini|/Users/'` over the evidence folder and the new dev-notes
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
