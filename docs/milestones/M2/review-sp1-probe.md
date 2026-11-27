# M2 Code Review — SP-1 probe, branch `m2/sp1-probe` (head `a964296`; diff `130721c..a964296`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Scope:** only `git diff 130721c a964296`: `e2cdab0` (code: `project.yml`, `Apps/TendAITestHost/Sources/*`,
  `Packages/TendAI/HostedTests/SP1TimingProbe.swift`) and `a964296` (docs only: `dev-notes.md` SP-1 section, Mac
  evidence record `evidence/mac/SP-1-dry-run/`). Base `130721c` = PR #43 head `ad8f755` merged with PR #44 head
  `774db72`. The PR #43/#44 code itself is out of scope (see I-1 for one thing found while reading it).
- **Spec:** `docs/milestones/M2/device-scripts/SP-1.md` v2 (on `origin/main`, `475cc27`, written before `e2cdab0`),
  Part D (D1-D6); PO ruling 2026-11-27 R-1 (`po-m2-r1-latency.md`, options (a)/(d), (b) on HOLD).
- **IDs:** FR-A1, R-1, SP-1, AC-M2-07, AC-M2-11, AC-M2-16 (stays AWAITING-DEVICE), T-27, Q20, plan B5/B6, MS-2,
  review PR #42 M1/M1-r2, review PR #48 n2; P-1…P-4, UX-3.

## Summary

The timing probe (D3) is close to the spec and its numbers would be honest: skipped unless `TEND_SP1=1`, dev set only
(8 texts, same household, same per-chore check as `devset-main.swift`, fixed UUIDs, no overlap with the 20 frozen
`inputs.json` texts, checked), cold `dev1` with no prewarm, 3 warm rounds with prewarm + 1.0 s, `ContinuousClock`,
TTFI at the first `emitted`, 30 s watchdog, Tool answered/refused from the capture's own `DuplicateLookupRecorder`, no
timing `#expect`, `.timeLimit(.minutes(15))`, line shape as D3.7. The `FoundationModelsOnDeviceSource` it builds is
the same as the public `init(locale: en_US)` except that it keeps each generation for the count (no new public API).
No frozen eval file, `@Guide` text, instruction or one-call rule is touched (D6). The evidence record checks out.

Two things block:
1. **M-1, the [Quick stop test] (D4.7) will stall at try 1 with the microphone open**, by code reading. Tries 1-5 call
   `source.stop()` before the capture has called `source.audio(in:)`; `MicrophoneCaptureState.stop()` in `idle`
   returns `.nothing`, so the stop is dropped, the microphone starts after `transcriberChosen` and nothing ever stops
   it: the loop waits forever, no `quickstop|try=1` line is printed, tries 6-10 (the M1-r2 window SP-1 exists to
   check) never run, and the screen's [Stop] is inert during the test (`current == nil`). The owner would have to kill
   the app. The probe must stay bounded and report what it saw.
2. **M-2, D2.1 is not done:** `TendAIHostedScaffoldTests` still compares against the literal `"com.tend.aitesthost"`,
   so the full hosted bundle fails with the owner's prefix (review PR #48 n2; spec says "must").

On the link change (`BUNDLE_LOADER: ""`), see "Link change assessment": no state crosses the two copies today, so
hosted tests and the probe are not made wrong by it; a separate SP-1 app target is **not required** for SP-1, but the
change should be undone or isolated before the Keychain/`URLProtocol` hosted tests land (m-1).

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M-1 | Major | `Apps/TendAITestHost/Sources/SP1SpeechScreen.swift:137-179` (`quickStopTest`), `:128-133` (`stop`); cause in `Packages/TendAI/Sources/TendAI/Speech/MicrophoneCaptureState.swift:52` and `SpeechTranscriptionAdapter.swift:215-216` | D4.7 tries 1-5: `capture.events(from: source)` only starts the capture task; `source.audio(in:)` is called later, after the awaited transcriber choice and `emit(.transcriberChosen)`. The immediate `source.stop()` (line 153) finds the source `idle` and is dropped (`case .idle … return .nothing`). The microphone then starts and the `for await` at line 155 never ends. Result: no line for try 1, tries 2-10 never run, no `quickstop|done`, no countdown, the microphone stays on, and [Stop] does nothing because `stop()` returns at `guard current != nil` during the test. Tries 6-10 have the same (small) race: the `transcriberChosen` event is yielded before `audio(in:)` calls `begin()`, so a main-actor `stop()` can still land in `idle`. Wrong behaviour in the real device scenario (OPERATING_MODEL §6 Major); it also loses the D4.7 output the SP-1 decision rules read (B5: "every try has a `finished=` line"). | Keep D4.7's timing (tries 1-5 stop right after start; 6-10 at `transcriberChosen`) and make every try bounded and reported: if no `finished` arrives within a fixed bound after the stop (for example 3 s), call `source.stop()` again (and keep calling it on each later `transcriberChosen`/until `finished`), then print the try line with an extra field such as `restops=<n>` and `ms_stop_to_finished` still measured from the **first** stop, so a dropped stop is visible, never hidden. Let [Stop] call `source.stop()` whenever a capture or the quick stop test is running. Give the Tester the new field so the "How the Tester reads" / Decision rules text can name it. Re-run D5 at the new commit (see m-3). | Open |
| M-2 | Major | `Packages/TendAI/HostedTests/TendAIHostedScaffoldTests.swift:14`; `project.yml:105-125` | SP-1 D2.1 (v2, review PR #48 n2): the scaffold test that checks `Bundle.main.bundleIdentifier == "com.tend.aitesthost"` "must compare against the prefix setting instead … so the whole bundle still passes with the owner's prefix". It is unchanged, so `xcodebuild test -scheme TendAIHostedTests … TEND_BUNDLE_PREFIX=<owner prefix>` (any later whole-bundle run on the owner's phone, e.g. DS-1) fails on this test. `dev-notes.md` D2 does not mention it. SP-1 Part A itself uses `-only-testing:…/SP1TimingProbe`, so the timing run is not affected, but the deliverable is unmet. | Set an `Info.plist` key on `TendAITestHost` from the setting (e.g. `INFOPLIST_KEY_…` or a custom key `TendBundlePrefix: $(TEND_BUNDLE_PREFIX)`) and compare `Bundle.main.bundleIdentifier` with `"\(prefix).aitesthost"`; keep a check that the prefix is non-empty so the test still fails if the host is wrong. Show B5 passing once with the default and once with `TEND_BUNDLE_PREFIX=org.example.owner` (Simulator is fine) in the evidence record. | Open |
| m-1 | Minor | `project.yml:96-100, 127-129` | The host now links `TendCore`/`TendIngestion`/`TendAI` and the hosted bundle links its own copies (`BUNDLE_LOADER: ""`); 11 "Class … is implemented in both" warnings in `mac-B5-hosted.log`. Safe today (see assessment below), but it changes the host from "blank" (plan WI-M2-M1/B5 purpose: Keychain and `URLProtocol` tests) to one that holds a second copy of every package type, and the warning noise can hide a real duplicate later. Not recorded as a decision. | Ticket it: after SP-1 (and before WI-M2-M4/M5 hosted Keychain/`URLProtocol` tests land), either move the speech screen to its own never-shipped target (e.g. `TendSP1Host`, own bundle ID from the same prefix) and restore the blank host with `BUNDLE_LOADER: "$(TEST_HOST)"`, or keep it and record the link model in a short ADR-0003 addendum / DECISIONS entry with the rule "no host code runs during hosted tests and no type is looked up by name". No change is required for SP-1 itself. | Open |
| m-2 | Minor | `Apps/TendAITestHost/Sources/SP1SpeechScreen.swift:93-100` | `start()` checks only `current == nil`, then suspends on `requestMicrophone()` before `current` is set. A second [Start] in that window (before the alert shows), or any [Start] during [Quick stop test] (`current` stays nil there; `busy` is not checked), starts a second capture on the same source: one gets `audioNotStarted`, `current` is overwritten, and when the first task ends it sets `current = nil` while the other still runs, so [Stop] is ignored with the microphone on. The owner is told not to touch the phone in B5, so this is unlikely, hence Minor. | Guard `start()` with `!busy` and a `starting` flag set before the first `await`; only clear `current` from the task that owns it (compare a capture number). |
| m-3 | Minor | `docs/milestones/M2/evidence/mac/SP-1-dry-run/README.md:51` | "The dry runs were made from the working tree just before commit e2cdab0, whose tree they match except that the probe's watchdog and device-code fixes were already in" is ambiguous: D5.2 and D5.3 are not tied to a commit as clearly as B0-B6 (which are at `e2cdab0`, clean before and after). The D5.3 check also used `TEND_SP1_SELFCHECK=1` instead of a tap (allowed by D5.3's wording; stated honestly). | When M-1/M-2 are fixed, re-run B0-B6 and D5.2/D5.3 at the new committed head with a clean tree and name that commit as the new `SP1-COMMIT`; state plainly "same tree as `<sha>`". If the Simulator panel can be tapped then, tap [Quick stop test] once there too (information only). | Open |
| n-1 | Nit | `Packages/TendAI/HostedTests/SP1TimingProbe.swift:175-176` | If the 30 s watchdog fires in the instant after `work` finished but before `watchdog.cancel()`, a completed capture is labelled `timeout`. Practically never. | Optional: set a flag inside `work` when the stream ended and label `timeout` only if it did not. | Open |
| n-2 | Nit | `Packages/TendAI/HostedTests/SP1TimingProbe.swift:231` | `median` takes the upper middle of 24 values (13th). Fine for information; the Tester computes the 48-capture rule from the raw lines anyway. | Optional: name it `ttfi_p50_upper_ms` or note it in dev-notes. | Open |
| n-3 | Nit | `Apps/TendAITestHost/Sources/SP1SpeechScreen.swift:204` | D4.3 asks for "big text"; lines use `.body.monospaced()`. Readable and scales with Dynamic Type; the owner also has the Terminal copy. Not product UI (no UX-4 review). | Optional: `.title3.monospaced()` or let the owner raise text size. | Open |
| I-1 | Info (escalate) | `Packages/TendAI/Sources/TendAI/Speech/MicrophoneCaptureState.swift:50-53` (PR #44 code, outside this diff) | Same root cause as M-1, seen from the product side: a stop that comes after the person tapped Start but before the adapter has called `audio(in:)` (the transcriber choice is awaited first) is dropped, and the microphone then starts and keeps running. SP-1 B4 ("tap [Start] and then [Stop] at once") will very likely show "dot stayed", which the SP-1 decision rules map to a Major defect against WI-M2-M3 (P-4 consent: the microphone keeps running after the person stopped). I do not rule on it here (not in this diff, and whether M3's capture screen will stop by cancelling the event stream instead is a design question). | Orchestrator: route to the Developer and the PR #44 Reviewer before the owner's device run, so the owner's time is not spent confirming a defect visible in code. If it is fixed in the adapter, the M-1 re-stop in the probe stays as a safety net and should then show `restops=0`. | Open |
| I-2 | Info | `dry-run/sp1-sim-probe-lines.txt` | In the Simulator the header says `model=available` but every capture ends `noModel`. Harmless there (MS-1), and the SP-1 "Run valid?" rule already needs every capture `completed`, so a device run with this mismatch is invalid and reported, not counted. | None. Tester: note it when reading device files. | Open |
| I-3 | Info | `project.yml` | D2.1's optional part (same prefix for `Tend` and `TendEval`, MS-3) is not done; allowed ("SP-1 needs only these two"). `commit=unknown` in the header is allowed (D3.7; S10 records the commit). | None for SP-1; MS-3 will need it. | Open |

### Link change assessment (task item 1)

What changed: before `e2cdab0` the host had no package dependencies; the package code lived only in the hosted test
bundle, and `BUNDLE_LOADER: $(TEST_HOST)` resolved nothing of note. Now the host (its Debug code in
`TendAITestHost.debug.dylib`) links all three packages for the speech screen, and the bundle keeps its own copies
(`BUNDLE_LOADER: ""`), still injected into the host (`TEST_HOST` unchanged, so Keychain access groups and the app
sandbox are the host's, as before). Checked:
- **Which copy the tests use.** Static linking binds the bundle's references to the bundle's own copies (two-level
  namespace), so every type, conformance and generic the tests touch is the bundle's copy, exactly as before this
  change. Swift Testing discovers tests from test-content records, which exist only in the bundle.
- **State in the host's copy.** At launch the host makes one `SP1SpeechModel`: `SpeechCapture(locale:)` (a struct
  around a stateless `SpeechAnalyzerEngine`) and `MicrophoneAudioSource()` (empty `init`). Nothing else runs unless a
  button is tapped or `TEND_SP1_SELFCHECK=1` is set (not set by `xcodebuild` or by the owner's commands). So nothing in
  the host's copy is live during B5 or the probe.
- **Singletons and name lookups.** `git grep` over the three packages' `Sources`: no `static let shared`, no mutable
  statics, no `nonisolated(unsafe)`, no `NSClassFromString`/`NSStringFromClass`/`NSKeyedArchiver`/`@objc`/
  `URLProtocol.registerClass`. The 11 duplicated classes are plain Swift classes used by direct reference, so the ObjC
  runtime's "which one is used is undefined" never applies. No package has resources (`Bundle.module` not involved).
- **Process-wide shared things** (Keychain items, `AVAudioSession.sharedInstance()`, the `FoundationModels` and
  `Speech` frameworks) exist once per process anyway; only one side uses each at a time (the host is idle in tests;
  the probe never touches audio).
- **Conclusion.** No type, singleton, Keychain or actor state crosses between the copies today, so neither hosted
  tests nor the probe are made wrong by it, and a separate SP-1 app target is not needed for SP-1. The risk is future:
  a later hosted test that registers a class by name, or host code that runs at launch, would meet the duplicate. That
  is ticketed as m-1.

### Other checks (task items 2-4)
- **`TEND_SP1_SELFCHECK=1`** (`SP1SpeechScreen.swift:214-219`, `.task`): presses [Speech status] once; that path calls
  only `capture.readiness()` (installed/supported locales, no download, no permission request, no microphone) and
  `SpeechPermission.microphone()` (read only). Without the variable nothing runs at launch (D4.1). Pass.
- **D6 / frozen eval.** No path under `Fixtures/` or any `MANIFEST.sha256` in the diff; T2 `git grep` for
  `Fixtures/M2/eval`, `inputs.json`, `golden.json` in `Packages/TendAI/HostedTests` and `Apps/TendAITestHost` at
  `a964296` prints nothing; the 8 dev-set texts are neither equal to nor contained in (nor contain) any of the 20
  frozen texts (scripted check). No timing `#expect`. Pass.
- **D1.** `fad715a`, `ad8f755` and `774db72` are ancestors of `a964296`; dev-notes names both unmerged heads. Pass.
- **D2.2/D2.3.** One calm usage sentence ("TendAITestHost uses the microphone to test voice capture. Nothing is
  saved."), no banned word; no `NSSpeechRecognitionUsageDescription` anywhere outside `docs/`. Pass.
- **Evidence record.** All 19 SHA-256 lines in `README.md` verify (`sha256sum -c`: 19 OK); it names
  `e2cdab04cd820432fd9af83e76706bbe418c1049`; B0 shows that commit with a clean tree; B9 clean after; `a964296` adds
  only `docs/` files. Personal-data scan of the whole diff: no `/Users/` path, no user name, host name, e-mail (other
  than `noreply@anthropic.com`), team ID, UDID or signing identity other than "Sign to Run Locally"; paths use the
  MS-1 tokens (`$HOME`, `$REPO`, `$SIM_DEVICE`, `$APP_CONTAINER`). Both commits authored and committed by
  `Claude <noreply@anthropic.com>`. Pass.
- **Linux runs (this review, Docker `swift:6.2-noble`, `-warnings-as-errors`, at `a964296`):** TendCore "141 tests in
  18 suites passed", exit 0; TendIngestion "572 tests in 67 suites passed", exit 0; 0 warnings in both logs. Same
  counts as the Mac B1/B2 logs. TendAI and the hosted bundle are Mac-only: taken from the committed Mac logs (B4 86
  tests; B5 5 tests in 3 suites, `SP1TimingProbe` skipped), not re-run here.
- **Swift 6 concurrency.** `SP1SpeechModel` is `@MainActor @Observable`; its capture task inherits the main actor.
  `SP1Lines` and `SP1Generations` are `@unchecked Sendable` with every stored field under an `NSLock`: correct, test
  target only, sign-off given. The probe's `work`/`watchdog` tasks are bounded. Hosted build has
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and no compiler warning. Reentrancy issue noted as m-2.

## Checklist
- [ ] Correctness vs ACs (spec D1-D6): D3, D5, D6 met; **D2.1 not met (M-2); D4.7 not reliably met (M-1)**
- [x] Tests meaningful: the probe asserts no timing by design (D3.6); it fails only on an unavailable model or a broken probe; B5 unchanged otherwise
- [x] Swift 6 concurrency safe (one Minor reentrancy, m-2)
- [x] No force unwraps / `try!` in product code paths (no product code changed)
- [ ] Privacy (P-1…P-4): pass for the new code, but M-1 leaves the microphone open with no in-app stop; I-1 escalated
- [x] UX-2/UX-3 enforced in engine (n.a.; no engine change; no banned word in the new copy)
- [x] Accessibility (UI): not product UI; buttons 56 pt high, Dynamic Type text (n-3)
- [x] Performance: n.a. for a debug host; probe work off the main actor
- [x] No new dependency without ADR (packages already in the project; link change ticketed m-1)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug buttons in a never-shipped test host; no entry form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | New strings ("Speech status", "Get speech model", "Start", "Stop", "Quick stop test", "Look at the top of the screen now", the usage sentence) use no banned word; result lines use `stopped`/`none`, no shaming copy. |
| UX-4 Design craft | n.a. | Test host, not product UI (SP-1 Part D). |
| P-1 On-device inference | pass | Probe uses only `FoundationModelsOnDeviceSource`; speech via `SpeechAnalyzer` on device; no cloud route in either. |
| P-2 No data leaves device (except user iCloud) | pass | No network code added; the only download is Apple's en-US speech asset via `AssetInventory`, only on [Get speech model] (allowed by SP-1 P-2 note). Output lines hold no bundle ID, device name, UDID or team. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path used. |
| P-4 Media not persisted without consent | concern | Nothing is stored and no audio is kept; transcripts go only to the screen and standard output of the fixed invented sentences (as SP-1 allows). Concern: by code reading the [Quick stop test] leaves the microphone running with no way to stop it from the screen (M-1), and the adapter drops an early stop (I-1, outside this diff). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Review `m2/sp1-probe` `130721c..a964296` against SP-1 Part D and the PO R-1 ruling. |
| 2026-11-27 | Reviewer | Orchestrator → Developer | returned | CHANGES REQUIRED: M-1 (bounded, reported quick-stop tries; working [Stop]), M-2 (scaffold test against the prefix). Minors m-1…m-3 to ticket or fold in; re-run D5 at the new commit and name it as `SP1-COMMIT`. |
| 2026-11-27 | Reviewer | Orchestrator → Developer + PR #44 Reviewer | sent (info) | I-1: early stop dropped in `MicrophoneCaptureState` (P-4 concern), visible in code before the device run. |
| 2026-11-27 | Reviewer | Orchestrator → Acceptance Tester | sent (info) | After the fix: new `SP1-COMMIT`, the new quick-stop field (M-1) for the reading rules, I-2 note. Not ready for the owner yet. |

---

# Round 2 — branch `m2/sp1-probe`, head `ccfebb3`; diff `8a7ff1f..ccfebb3`

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2
- **Scope:** `git diff 8a7ff1f ccfebb3`: `b4a4ec4` (code: `SP1SpeechScreen.swift`, new
  `Apps/TendAITestHost/Support/Info.plist`, `project.yml`, `SP1TimingProbe.swift`, `TendAIHostedScaffoldTests.swift`;
  plus a `dev-notes.md` section) and `ccfebb3` (docs only: `dev-notes.md`, Mac record `evidence/mac/SP-1-r2/`).
  `5869f59..8a7ff1f` checked only to confirm it is the merge: `8a7ff1f` has parents `5869f59` (round-1 head) and
  `430f700` (`m2/speech-adapter-v2`); `git merge-tree` of those two gives a conflict only in `dev-notes.md`, and the
  committed tree differs from the automatic result only there (3 lines, the conflict markers); no code was edited in
  the merge. The early-stop fix `e100496` is reviewed under PR #44 round 4; here only how the probe uses it.
- **Spec:** `docs/milestones/M2/device-scripts/SP-1.md` v2 (`origin/main` `475cc27`; not on this branch) Part D;
  round-1 findings above.
- **IDs:** FR-A1, R-1, SP-1, AC-M2-07, AC-M2-11, AC-M2-16 (stays AWAITING-DEVICE), AC-M2-25, T-27, Q20, plan B5/B6,
  MS-2, review PR #48 n2; P-1…P-4, UX-3.

## Summary

Both Majors are closed in code and evidence. M-1: every quick-stop try is now bounded (worst case about 25 s), the
time is taken at the `finished` event from the first stop, dropped stops show as `restops=<n>` and, after 3 re-stops,
the try is cancelled and printed as `finished=none`; [Stop] works during the test. With the adapter fix merged
(`captureWillStart()` is called synchronously in `SpeechCapture.events(from:)`, before anything is awaited), the stop
right after `events(from:)` in tries 1-5 and the stop at `transcriberChosen` in tries 6-10 both land in the `armed`
state and are kept, so the expected device result is `restops=0` on every try. M-2: the host has
`TendBundlePrefix = $(TEND_BUNDLE_PREFIX)` in a partial Info.plist and the scaffold test compares against
`"<prefix>.aitesthost"`, with a `#require` and a non-empty check; B5 passes with the default prefix and with
`org.example.owner`. m-2, m-3, n-1, n-2, n-3 closed; m-1 is ticketed in dev-notes as asked.

One new Minor (m-4): in tries 6-10 the 5 s limit is counted from the start of the try, not from the stop, so a slow
transcriber choice can produce a `restops=1` that does not mean a dropped stop. It does not affect the time field and
does not hide a defect (it can only over-report), so it does not block. One Nit (n-4).

## Round-1 findings, re-checked

| # | Round-1 severity | Evidence in `8a7ff1f..ccfebb3` | Status |
|---|---|---|---|
| M-1 | Major | `SP1SpeechScreen.swift:154-212`. Per try: a `@MainActor` consumer task reads the events and records `stoppedAt` (tries 6-10 at `transcriberChosen`), `finishedAt` and the outcome at the `finished` event (`:164-180`); the main loop polls every 50 ms (`:183-203`): with no `finished` 5 s after the (first) stop it calls `source.stop()` again, up to 3 times (`restops`), then `consumer.cancel()` (the stream's `onTermination` cancels the adapter task, whose source stream's `onTermination` tears the microphone down); if `transcriberChosen` never comes within 5 s it stops anyway. The line (`:209-210`) prints `ms_stop_to_finished` from the **first** stop to the `finished` event (`none` if there was none) and `restops=<n>`. Worst case per try: 5 s + 4 × 5 s = 25 s, so the test always reaches `quickstop|done`. `stop()` (`:135-140`) now runs when `busy` (quick stop test) as well as with a capture. Root cause fixed in the adapter (I-1, `e100496`, merged): `events(from:)` calls `source.captureWillStart()` before its first await (`SpeechTranscriptionAdapter.swift:194-195`), so both D4.7 stop points are kept. Caveat: m-4 below. | **Closed** |
| M-2 | Major | `Apps/TendAITestHost/Support/Info.plist` (key `TendBundlePrefix`, value `$(TEND_BUNDLE_PREFIX)`); `project.yml:110-113` (`GENERATE_INFOPLIST_FILE: YES` + `INFOPLIST_FILE`, merged with the generated keys; the file is outside `Sources`, so it is not copied as a resource); `TendAIHostedScaffoldTests.swift:13-18` (`try #require` the key, `#expect(!prefix.isEmpty)`, `#expect(bundleIdentifier == "\(prefix).aitesthost")`). The test fails if the key is missing (wrong host), unexpanded, or does not match. `logs/mac-B5-hosted.log`: 5 tests in 3 suites passed, bundle ID `com.tend.aitesthost`; `d5/d5-b5-custom-prefix.log`: command line has `TEND_BUNDLE_PREFIX=org.example.owner`, bundle ID `org.example.owner.aitesthost`, "The tests run inside the TendAITestHost app" passed, 5 tests in 3 suites, `TEST SUCCEEDED`. | **Closed** |
| m-1 | Minor | `dev-notes.md` "Link change kept": must be undone or isolated before the Keychain / `URLProtocol` hosted tests (WI-M2-M4, WI-M2-M5) share the host; two options named (own SP-1 target with `BUNDLE_LOADER: "$(TEST_HOST)"` restored, or a DECISIONS entry); "Ticket: Planner, before the M4/M5 branches are merged with this one". This is what round 1 asked. | **Closed** (ticketed; Planner owns it) |
| m-2 | Minor | `start()` `:97-99`: refused when `current != nil`, `starting` or `busy`; `starting` is set before the first `await` (`requestMicrophone`) and cleared by `defer` after `current` is set. `quickStopTest()` `:147-149` also refuses while `starting`, and sets `busy` before its first `await`. The capture task clears `current` only if `captureNumber == n` (`:130`). | **Closed** |
| m-3 | Minor | README names `SP1-COMMIT = b4a4ec4658c2ad52c8f9c77d23112bf5b560bc85`; `logs/mac-B0-header.log` and `d5/d5-header.log` print that SHA with an empty `git status --porcelain`; `logs/mac-B9-after.log` and `d5/d5-after.log` empty after. `ccfebb3` adds only `docs/` files (`git diff --stat b4a4ec4 ccfebb3`). The Simulator panel still could not be tapped, stated plainly; [Quick stop test] was not run there (allowed, information only). | **Closed** |
| n-1 | Nit | `SP1TimingProbe.swift:137-163`: `timeout` only when `work.isCancelled` and the summary's outcome is `cancelled`/`nil` (or `finished` was not seen). A capture that finished by itself just before the watchdog fired keeps its real outcome. | **Closed** |
| n-2 | Nit | `SP1TimingProbe.swift:241`: comment "upper middle value for an even count (the 13th of 24)"; name kept because the script uses it (reasonable). | **Closed** |
| n-3 | Nit | `SP1SpeechScreen.swift:253`: `.title3.monospaced()`. | **Closed** |
| I-1 | Info | Fixed on `m2/speech-adapter-v2` (`e100496`), merged at `8a7ff1f`; reviewed separately (PR #44 round 4). The probe's re-stop stays as the safety net, as round 1 suggested. | **Closed** here |
| I-2, I-3 | Info | Unchanged: D5.2 again shows `model=available` with every capture `noModel` in the Simulator (25 of 25). | Info (no action) |

## New findings (round 2)

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| m-4 | Minor | `Apps/TendAITestHost/Sources/SP1SpeechScreen.swift:182-194` | For tries 6-10 (`atChosen`) `waited` starts counting when the try starts and is not reset when the consumer sets `stoppedAt` at `transcriberChosen`. So the first re-stop comes 5 s after the **start**, not 5 s after the stop: if the transcriber choice takes, say, 4.5 s and the stop-to-finished 1 s, the line reads `restops=1` with `ms_stop_to_finished≈1000` although the stop was not dropped. The doc comment (`:143-145`) and dev-notes say "within 5 s of the stop". It can only over-report (never hides a dropped stop) and the time field stays honest, and on a warm phone the choice is far below 5 s, so not Major. Also, the "transcriber never chosen within 5 s: stop now" path (`:187-192`) is not marked on the line, so a try 6-10 stopped by the timer looks like one stopped at `transcriberChosen`. | Measure the limit from the stop: e.g. compare `clock.now` with `attemptState.stoppedAt + .seconds(5)` (and the last re-stop), instead of the shared `waited`; optionally print `stop=timer` (or similar) when the timer made the first stop. If fixed before the owner's run, re-run B5 and D5 and name the new `SP1-COMMIT`; if not, the Acceptance Tester reads it as below. | Open (non-blocking) |
| n-4 | Nit | `SP1SpeechScreen.swift:135-139` | [Stop] during the quick stop test (or during [Get speech model], where `busy` is also true) prints `capture|n=<last manual capture number>|stop_tapped`, which names a capture that is not running (or `n=0`). Harmless; could confuse a reader of the file. | Optional: print `quickstop|stop_tapped` while `busy`. | Open |
| I-4 | Info | `evidence/mac/SP-1-r2/logs/mac-B4-tendai-macos.log` (and every earlier `mac-B4` log on `main`) | The `xcodebuild` destination list prints the Mac's hardware identifier (`id:` of "My Mac"). Not personal data under the MS-1 token list and pre-existing in every record, so out of scope here; no name, e-mail, user path, team ID or device UDID of the phone appears. | None for SP-1. PO/Documenter may decide whether MS-1 should also replace that `id:` with a token in future records. | Info |

## SP-1 script vs the printed lines (for the Acceptance Tester)

The `quickstop` line is now
`SP1|seq=..|quickstop|try=<n>|when=<beforeChosen or atChosen>|finished=<outcome or none>|ms_stop_to_finished=<ms or none>|restops=<0-3>`.
All other line shapes (header, cold, warm, summary, footer, speech-status, capture) are unchanged. `SP-1.md` v2 does not
yet match. The Tester must update it (on `main`; protected-file rules do not apply, it is under `docs/milestones/`):
1. **D4.6 example:** add `|restops=0` to the `quickstop` example line.
2. **"How the Tester reads" / Decision rules, row "B4, B5 quick stop":** add "every `quickstop` line has `restops=0`
   and a real `finished=` outcome". `restops` ≥ 1 together with `ms_stop_to_finished` ≥ 5000 (or `none`), or
   `finished=none` (try cancelled after 3 re-stops), means a stop was dropped: same Major against WI-M2-M3 (P-4). While
   m-4 is open: on a `when=atChosen` line, `restops=1` with `ms_stop_to_finished` < 5000 is a timing artefact of the
   probe (slow transcriber choice), not a dropped stop; record it as information.
3. **B5 owner step:** "about 15 seconds" holds when every stop works; if stops are dropped the test can take up to about
   4-5 minutes (10 × 25 s). Tell the owner to wait for `quickstop|done` and not to close the app; if the orange dot is
   still on after the countdown, tap **[Stop]** (it now works during and after the test) and write that down.
4. **Run identity:** the build to use is `SP1-COMMIT = b4a4ec4658c2ad52c8f9c77d23112bf5b560bc85` (record
   `evidence/mac/SP-1-r2/`); the owner's commands (Part A/B) are unchanged (D5.4, round 1).
5. **B4 by hand:** a second quick [Start] while one is being set up is now silently refused (m-2); the script needs no
   change, but the Tester should not expect two `capture|n=` starts from a double tap.

## Other checks (round 2)
- **Evidence record.** All 23 SHA-256 lines in `evidence/mac/SP-1-r2/README.md` verify (`sha256sum -c`: 23 OK).
  B1 141 tests / 18 suites; B2 572 / 67, scan 67 files, 0 violations; B4 90 / 15 (includes "Early stop (SP-1 review
  I-1; P-4)"); B5 5 / 3 with `SP1TimingProbe` skipped by design; B6 as MS-1 (eval archive exit 66 expected).
  `timings.txt` exit codes match. Only non-compiler `warning:` lines (AppIntents metadata notice, orientation notice for
  B6). D5.2: 28 `SP1|` lines (header, cold, 24 warm, summary, footer), all 25 captures `noModel` (Simulator, MS-1).
  D5.3: the `speech-status` line reached the Terminal (self-check variable).
- **Personal data.** Scan of the whole diff (10 620 lines): no user home path (paths use `$HOME`/`$REPO`), no e-mail
  other than `noreply@anthropic.com`, no person's name or user name, team shown only as `FAKETEAMID`, no phone UDID,
  no signing identity. See I-4 for the Mac's destination `id:`.
- **Authorship.** `8a7ff1f`, `b4a4ec4`, `ccfebb3`: author and committer `Claude <noreply@anthropic.com>`.
- **Frozen eval (D6).** No path under `Fixtures/`, no `MANIFEST.sha256`, `inputs.json` or `golden.json` in the diff;
  `git grep` for `Fixtures/M2/eval|inputs.json|golden.json` in `Apps/TendAITestHost` and `Packages/TendAI/HostedTests`
  at `ccfebb3` prints nothing. No `@Guide`, instruction or eval code touched. Pass.
- **Linux runs (this review, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `ccfebb3`, read-only mount,
  scratch paths `/tmp/sp1r2c` and `/tmp/sp1r2i` inside the container):** TendCore "141 tests in 18 suites passed", exit
  0; TendIngestion "572 tests in 67 suites passed", exit 0; 0 `warning:` lines in either log. Same counts as Mac B1/B2.
  TendAI and the hosted bundle are Mac-only: taken from the committed Mac logs, not re-run here.
- **Swift 6 concurrency.** `SP1SpeechModel` and the new `QuickStopAttempt` are `@MainActor`; the consumer task is
  `Task { @MainActor in … }`, so the poll loop and the consumer never race on the attempt state (they interleave only at
  awaits, and every read after an await re-checks the state). The shared `MicrophoneAudioSource` is captured as a
  `let` and its state is under its own lock. `consumer` is always awaited before the next try, so no try outlives its
  line. Hosted build has `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and compiles clean in B5. No new `@unchecked Sendable` or
  `nonisolated(unsafe)`; the two existing `@unchecked Sendable` test helpers are unchanged (signed off in round 1).
- **No network, no new dependency.** No `URLSession`/`URLRequest` in the host or probe; the only URL is the plist DTD.
  No new package.

## Checklist (round 2)
- [x] Correctness vs ACs (spec D1-D6): D2.1 met (M-2 closed); D4.7 bounded and reported (M-1 closed; m-4 is a reading caveat)
- [x] Tests meaningful: the scaffold test fails on a missing, empty or mismatched prefix; shown passing with two prefixes
- [x] Swift 6 concurrency safe
- [x] No force unwraps / `try!` in product code paths (no product code changed in this diff)
- [x] Privacy (P-1…P-4): microphone always stops or the try is cancelled; [Stop] works during the test
- [x] UX-2/UX-3 enforced in engine (n.a.; no engine change; no banned word in new strings)
- [x] Accessibility (UI): not product UI; larger monospaced text (n-3)
- [x] Performance: 50 ms main-actor poll in a debug host only; n.a. otherwise
- [x] No new dependency without ADR (link model ticketed, m-1)

## Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug buttons in a never-shipped test host. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | New output strings (`restops=`, `finished=none`) and comments use no banned word (scanned: overdue, late, missed, failed, behind, penalty). |
| UX-4 Design craft | n.a. | Test host, not product UI (SP-1 Part D). |
| P-1 On-device inference | pass | Unchanged: `FoundationModelsOnDeviceSource` and `SpeechAnalyzer` on device only. |
| P-2 No data leaves device (except user iCloud) | pass | No network code; the bundle prefix goes only into the host's own Info.plist. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path. |
| P-4 Media not persisted without consent | pass | Round-1 concern resolved: each quick-stop try re-stops and finally cancels (which tears the microphone down), [Stop] works during the test, and the adapter now keeps an early stop (I-1). Nothing is stored; no audio is kept. Device confirmation stays with SP-1 B4/B5 (AWAITING-DEVICE). |

## Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Round 2 of `m2/sp1-probe`, `8a7ff1f..ccfebb3`, merge `8a7ff1f` checked. |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper | APPROVE | M-1, M-2, m-2, m-3, n-1…n-3 closed with evidence; m-1 ticketed (Planner). No open Blocker/Major. Open: m-4 (Minor), n-4 (Nit), I-4 (Info). |
| 2026-11-27 | Reviewer | Orchestrator → Acceptance Tester | sent | Update SP-1.md: `restops` field (D4.6 and the B4/B5 rule), the m-4 reading caveat, B5 duration and [Stop] note, `SP1-COMMIT = b4a4ec4`. |
| 2026-11-27 | Reviewer | Orchestrator → Developer | sent (optional) | m-4: count the 5 s limit from the stop; if done before the owner's run, re-run B5/D5 and name the new `SP1-COMMIT`. |
| 2026-11-27 | Reviewer | Orchestrator → Planner | sent | m-1 ticket: undo or isolate the host link change before WI-M2-M4/M5 hosted tests share the host. |

---

# Round 3 — branch `m2/sp1-probe`, head `849d6db`; code diffs `e20ba9f..ea3d195` and `88921e8..c07e12a`

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 3
- **Scope:** `ea3d195` (code: `SP1SpeechScreen.swift`, round-2 m-4 and n-4), `eca2327` (docs: Mac record
  `evidence/mac/SP-1-r3/`, dev-notes), merge `88921e8` (`eca2327` + `origin/m2/speech-adapter-v2` at `8c324a6`, which
  holds `main` up to `9e50012`), `c07e12a` (build fix in `KeychainAPIKeyStoreHostedTests.swift`), `849d6db` (docs: Mac
  record `evidence/mac/SP-1-r4/`, dev-notes). The speech adapter at `8c324a6` is reviewed under PR #44; here only that
  the merge carries it unchanged.
- **Final SP1-COMMIT named by the Developer:** `c07e12a9647c7612b720a4d598d9f535870ca1b6`.
- **Spec:** `docs/milestones/M2/device-scripts/SP-1.md` v2 (read from `origin/main`) Part D and Part T; round-2 findings.
- **IDs:** FR-A1, R-1, SP-1, AC-M2-11, AC-M2-16 (stays AWAITING-DEVICE), AC-M2-18, AC-M2-21, AC-M2-22, AC-M2-23,
  AC-M2-25, T-27, Q20, plan B5/B6, MS-2; P-1…P-4, UX-3.

## Summary

The code is good. m-4 and n-4 are closed: the re-stop limit now counts from the latest stop, a timer-made first stop
is marked `firststop=timer`, and [Stop] during a try prints `quickstop|try=<n>|stop_tapped` and stops that try. The
three printed shapes match the format given to the Tester exactly. The merge `88921e8` carries every code file
unchanged (its tree differs from the automatic `git merge-tree` result only in `dev-notes.md`, and every speech
adapter file equals `8c324a6`). `c07e12a` is the same one-line helper fix already on `m2/on-device-adapter-v2`. Both
evidence records verify (23 of 23 SHA-256 lines each, every file covered) and name the right commits with a clean tree
before and after. B5 passes with the default prefix and with `org.example.owner` (37 tests in 6 suites). TendCore and
TendIngestion pass here in Docker with warnings as errors.

One **Major** stops the merge: the dev-notes rebuild in `88921e8` **lost 61 lines of WI-M2-M2 text**, including
WI-M2-M2's **Law check** and **Handoff log**, and left one stray table row (M-3). The dev-notes text says "no section
twice", which is true, but sections were dropped. It is a docs-only fix; the build under test (`c07e12a`) does not
change and nothing has to be re-run.

The `BUNDLE_LOADER: ""` link change now also covers the Keychain and `URLProtocol` hosted tests from `main` (13 "Class
… is implemented in both" runtime messages). My judgement: **it does not block merging this branch to `main`**; it
should be a tracked ticket (m-6). One new Minor (m-5: [Stop] after the last try is a silent no-op) and one Nit (n-5).

## Round-2 findings, re-checked

| # | Round-2 severity | Evidence at `849d6db` | Status |
|---|---|---|---|
| m-4 | Minor | `SP1SpeechScreen.swift:196-218`. `lastStopAt` starts as the planned stop (tries 1-5) and otherwise picks up `attemptState.stoppedAt` as soon as the consumer sets it at `transcriberChosen` (`:200`, `lastStopAt ?? attemptState.stoppedAt`). The 5 s check is `since.duration(to: clock.now) >= .seconds(5)` (`:211`), and every re-stop resets `lastStopAt = clock.now` (`:217`). So `restops` goes above 0 only when a stop really got no `finished` for 5 s. The no-`transcriberChosen` path (`:200-208`) counts 5 s from `tryStart` (`:202`), sets `firstStop = "timer"` and the stop time, and from then on the normal re-stop rule applies. The consumer and the poll loop are both `@MainActor`, and the consumer only stops when `stoppedAt == nil`, so there is never a double first stop. Worst case per try is still 5 s + 4 × 5 s = 25 s; the time field is still first stop → `finished`. | **Closed** |
| n-4 | Nit | `SP1SpeechScreen.swift:137-148`: with `busy` and a running try (`quickStopTry`, set at `:169`), [Stop] prints `quickstop|try=<n>|stop_tapped` and calls `source.stop()`. The old `capture|n=<old>|stop_tapped` line is gone. See m-5 for the time after try 10. | **Closed** |
| m-1 | Minor (ticketed) | Its condition has now been reached: `main`'s Keychain and transport hosted tests share the host (see m-6). | Superseded by m-6 |
| I-4 | Info | Unchanged: `mac-B4` logs in `SP-1-r3`/`SP-1-r4` again print the Mac's destination `id:`. | Info |

## Merge `88921e8`: is it faithful?

- **Parents:** `eca2327` (this branch) and `8c324a6` (= `origin/m2/speech-adapter-v2`). `git merge-tree --write-tree
  eca2327 8c324a6` conflicts only in `dev-notes.md` (`ModelRouter.swift` merges cleanly). The committed tree differs
  from the automatic result **only** in `dev-notes.md`, so no code was edited in the merge.
- **Speech adapter:** `git diff 8c324a6 88921e8 -- Packages/TendAI/Sources/TendAI/Speech` and the speech tests
  (`SpeechCaptureTests`, `SpeechPermissionTests`, `SpeechRealEngineTests`, `EarlyStopTests`,
  `MicrophoneCaptureStateTests`, `RoundFiveStopTests`, `HostedTests/SpeechHostedTests.swift`) are empty. `c07e12a` and
  `849d6db` do not touch them. **Equal to `8c324a6`.**
- **dev-notes.md:** **not faithful** (M-3). Lines 1-6052 of the merged file are byte-for-byte `8c324a6`'s file
  (good). The rest is this branch's own sections, but only the parts that sat under their own `##` headings in
  `eca2327`. In `eca2327` the earlier merge had left part of WI-M2-M2 *inside* the WI-M2-M3 sections (WI-M2-M2's
  "Known limitations / follow-ups", "Law check" and "Handoff log" under WI-M2-M3, and WI-M2-M2 round 2's "AC → test
  (B4)", "Developer dev set", "Eval manifest" and "Test runs" under WI-M2-M3 round 3). Taking WI-M2-M3 from the speech
  branch dropped those parts. A line-level three-way count (base `430f700`, both parents, result) shows 34 distinct
  non-blank lines added by this branch that are missing from `88921e8` (and from `849d6db`), and 0 lines from the
  speech branch lost. Compared with the clean WI-M2-M2 text on `origin/m2/on-device-adapter-v2` (`d4d1a95`, lines
  5807-6023), the merged lines 6053-6209 are short by 61 lines and have 1 extra line. All 34 lost lines are on
  `origin/m2/on-device-adapter-v2`.

## New findings (round 3)

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M-3 | **Major** | `docs/milestones/M2/dev-notes.md:6181-6209` (at `88921e8` and `849d6db`) | The dev-notes rebuild in merge `88921e8` dropped 61 lines of WI-M2-M2 text. After line 6181 these WI-M2-M2 subsections are missing: "Known limitations / follow-ups" (R-1 TTFI 6.3 s risk row for AC-M2-16, B6 orientation row, DS-1 row), **"Law check"** and **"Handoff log"**. In WI-M2-M2 round 2 these are missing: "AC → test (B4)" (m1 and R-1 (a) test names, mutants), "Developer dev set" (the before/after table), "Eval manifest" (4 files listed, 3 pinned in `EvalFreezeTests.swift:34-38`) and "Test runs" (`fad715a` counts). Line 6208 is a stray WI-M2-M3 handoff row ("Reviewer sign-off asked for the one `@unchecked Sendable`") left at the end of WI-M2-M2 round 2's "What changed"; it is already in WI-M2-M3's handoff log at line 5916. Why Major: CLAUDE.md §4 rules 3 and 4 (every artifact keeps its Law Check; traceability FR → AC → test), and the lost text is the only place on this branch that records WI-M2-M2's AC → test mapping and R-1 follow-ups. When this branch merges into `main` after PR #43, git can apply the deletion with no conflict, so `main` could silently lose WI-M2-M2's Law Check. The round-4 dev-notes line "rebuilt by section … with no section twice" says nothing was lost, which is not true. | Docs-only commit: replace merged lines 6053-6209 (`## WI-M2-M2 …` through the end of `## WI-M2-M2 round 2` "What changed", stray row included) with lines 5807-6023 of `docs/milestones/M2/dev-notes.md` from `origin/m2/on-device-adapter-v2` (`d4d1a95`). Stop just before its `### WI-M2-M2: brought up to date with main` part, which belongs to that branch. Then check that `git diff origin/m2/on-device-adapter-v2 <new> -- docs/milestones/M2/dev-notes.md` shows no deletion inside the two WI-M2-M2 sections. Fix the round-4 sentence ("rebuilt by section"). `SP1-COMMIT` stays `c07e12a`; no Mac re-run needed. | **Open** |
| m-5 | Minor | `Apps/TendAITestHost/Sources/SP1SpeechScreen.swift:137-145, 230-236` | `quickStopTry` is cleared at `:230`, before the 10 s "Look at the top of the screen now" countdown, while `busy` stays true. In that window [Stop] reaches `guard current != nil` and returns without calling `source.stop()` or printing anything. In round 2 it called `source.stop()` there. Round 2 told the Tester that [Stop] "works during and after the test", and SP-1 B5 is exactly when the owner looks for the orange dot. Each try now ends `finished` or is cancelled (and cancel tears the microphone down), so the lever matters only if that teardown itself goes wrong, and a dot that stays is already a Major under the B4/B5 rule. Not blocking. Also, between tries (the 1 s pause) [Stop] prints `try=<n>` for the try that has just ended; harmless. | Optional (any new code commit means a new `SP1-COMMIT` and a re-run of B5/D5): clear `quickStopTry` after the countdown (then [Stop] prints `quickstop|try=10|stop_tapped`, which is still the given format). Otherwise the Tester's B5 step must say: if the dot stays after the countdown, write "dot stayed" and close the app from the app switcher; do not rely on [Stop] there. | Open (non-blocking) |
| m-6 | Minor | `project.yml:131-133` (`TendAIHostedTests`: `BUNDLE_LOADER: ""`); `docs/milestones/M2/dev-notes.md` round 4, "The link change now matters" | With `main` merged, the Keychain (`KeychainAPIKeyStoreHostedTests`, AC-M2-18, AC-M2-21) and transport (`CloudHTTPTransportHostedTests`, AC-M2-22, AC-M2-23) hosted tests run in a host that has its own copies of the packages. B5 prints 13 "Class … is implemented in both" runtime messages (TendAI, TendIngestion and TendCore classes). **Judgement: not a merge blocker; make it a ticket.** Why: (1) Swift code in each image binds to its own copy at link time, so every test exercises one self-consistent copy (the package code under test). (2) The only runtime lookup by class is `configuration.protocolClasses = [StubProtocol.self]` (`CloudHTTPTransportHostedTests.swift:121`), and `StubProtocol` lives only in the test bundle. No hosted test or `TendAI` source uses `NSClassFromString`, keyed archiving or `Bundle(for:)` (grep at `849d6db`). (3) The Keychain entitlement and access group come from the host process either way. (4) B5 passes 37/37 with both prefixes, and the product targets `Tend`/`TendEval` are not affected. (5) These are runtime messages, not compiler warnings (CLAUDE.md §3 "no warnings" is met: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` builds clean). The risk is for later: any hosted test that comes to depend on host code, host statics or ObjC lookup by name would see undefined class choice. The dev-notes text contradicts this, though: "must be undone or isolated before this branch's `project.yml` reaches `main`". | Developer, in the M-3 docs commit: reword that sentence to a ticket. Planner: ticket with owner and a due point, **before the M2 gate or before any hosted test uses host-side code or state, whichever comes first**. Fix is option (a) from round 2 (move the speech screen to its own never-shipped target and restore `BUNDLE_LOADER: "$(TEST_HOST)"` for the blank host) or option (b) (a DECISIONS entry; human merge, since `docs/governance/**` is protected). | Open (ticket) |
| n-5 | Nit | `SP1SpeechScreen.swift:138-143` | A person's [Stop] during tries 6-10 before `transcriberChosen` does not set `stoppedAt`, so that try prints `firststop=planned` … `ms_stop_to_finished=none` with a real `finished=` outcome. The `stop_tapped` line just before it makes this readable. | None needed; the Tester reads a try right after a `quickstop|try=<n>|stop_tapped` line as information only (below). | Open |
| I-5 | Info | `evidence/mac/SP-1-r3/`, `SP-1-r4/` logs | System log lines carry the Mac's local UTC offset, as every earlier Mac record on `main` does. Not on the MS-1 token list. Same handling as I-4 (PO/Documenter may decide for future records). | None for SP-1. | Info |

## Printed format check (task item)

At `c07e12a` the code prints exactly:
- `SP1|seq=<n>|quickstop|try=<1-10>|when=<beforeChosen|atChosen>|firststop=<planned|timer>|finished=<outcome>|ms_stop_to_finished=<ms|none>|restops=<0-3>`
  (`:225-227`; `emit` adds `SP1|seq=<n>|`; `finished` is `none` when no `finished` event came, i.e. the try was
  cancelled after 3 re-stops; otherwise `transcribed`, `nothingHeard`, `unavailable(<r>)`, `stopped(<r>)` or
  `cancelled`);
- `SP1|seq=<n>|quickstop|done` (`:231`);
- `SP1|seq=<n>|quickstop|try=<n>|stop_tapped` (`:140`), only while a try is set (see m-5 for after try 10).
Match: yes. The quick stop test was not run in the Simulator (the panel cannot be tapped there; information only, as in
round 2), so this is checked by reading the code, not from a log.

## What the Acceptance Tester must change in `SP-1.md` (v2 on `origin/main`)

1. **D4.6 example block (line 115):** replace the quickstop example with
   `SP1|seq=..|quickstop|try=1|when=beforeChosen|firststop=planned|finished=nothingHeard|ms_stop_to_finished=40|restops=0`
   and add, as optional, `SP1|seq=..|quickstop|try=<n>|stop_tapped` (only when [Stop] is tapped during the test).
2. **D4.7 (lines 120-123):** add the per-try limit. If no `finished` comes within 5 s of the latest stop, the source is
   stopped again, up to 3 times (`restops`), and then the try is cancelled (`finished=none`). If tries 6-10 see no
   `transcriberChosen` within 5 s of their start, the timer makes the first stop (`firststop=timer`).
   `ms_stop_to_finished` is always from the first stop to `finished`.
3. **Decision rules, row "B4, B5 quick stop" (line 428).** For B5, every `quickstop|try=` line must have
   `firststop=planned`, `restops=0`, a real `finished=` outcome (not `none`) and `ms_stop_to_finished` ≤ 2000. Then:
   - `restops` ≥ 1, or `finished=none`, means a stop went unanswered for 5 s: same Major, owner Developer (WI-M2-M3;
     P-4).
   - `firststop=timer` on a try 6-10 means the transcriber was not chosen within 5 s, so that try did not test the
     `transcriberChosen` window. Report it to the Developer as information, and judge the try's
     `ms_stop_to_finished` the same way.
   - A try that comes right after a `quickstop|try=<n>|stop_tapped` line is information only (n-5).
   - **Delete the round-2 m-4 caveat** ("on a `when=atChosen` line, `restops=1` with `ms_stop_to_finished` < 5000 is a
     probe artefact"). It no longer applies: from `ea3d195` on, any `restops` ≥ 1 is a real unanswered stop.
4. **B5 owner step (lines 319-321).** "About 15 seconds" holds only when every stop works. If stops are dropped, the test
   can take up to about 4-5 minutes (10 × 25 s). Tell the owner: wait for "Look at the top of the screen now", do not
   close the app before then, and do not tap [Stop] during the test. If the dot is still there after the countdown,
   write "dot stayed" and close the app from the app switcher. [Stop] does nothing in the countdown (m-5), unless the
   Developer ships the m-5 fix and a new `SP1-COMMIT`.
5. **Values table (line 176):** `SP1-COMMIT` = `c07e12a9647c7612b720a4d598d9f535870ca1b6` (record
   `docs/milestones/M2/evidence/mac/SP-1-r4/`). The M-3 fix is docs-only and does not change it; only a new code commit
   (for example for m-5) would. The owner's Part A/B commands are unchanged (the probe still runs with
   `-only-testing:TendAIHostedTests/SP1TimingProbe`, so `main`'s Keychain/transport hosted tests do not run on the phone).
6. **Part T at `c07e12a`.** I checked T1-T3 here, but the Tester must re-run them and record them:
   - T1: `git merge-base --is-ancestor fad715a c07e12a` and `… 8c324a6 c07e12a` both succeed. The Tester must also
     confirm that the PR #44 review of `8c324a6` (round 5) is APPROVE, since D1 needs "a round the Reviewer has
     approved".
   - T2: the `git grep` prints nothing.
   - T3: `NSMicrophoneUsageDescription` is present and there is no `NSSpeechRecognitionUsageDescription`.
   - T4: B5 at `SP-1-r4` is **37 tests in 6 suites** with the probe skipped (no longer 5 tests); D5.2 has 28 `SP1|`
     lines.
7. **B4 by hand:** no change (it uses `capture|n=` lines, unchanged; a second fast [Start] is refused, as in round 2).

## Other checks (round 3)

- **Evidence records.** `SP-1-r3`: `sha256sum -c` 23 of 23 OK, every file except README covered. B0 and D5 headers
  print `ea3d195b1734df73117447756f95c3562671be63` with an empty porcelain, and both "after" files are empty. `SP-1-r4`:
  23 of 23 OK, all files covered, headers print `c07e12a9647c7612b720a4d598d9f535870ca1b6`, clean before and after.
  `timings.txt` in both: B1-B6 exit 0, eval archive exit 66 (expected, MS-1). `SP-1-r4` counts: B1 141/18, B2 580/68,
  B4 96/17, B5 37/6 (`com.tend.aitesthost`), `d5-b5-custom-prefix.log` 37/6 with `TEND_BUNDLE_PREFIX =
  org.example.owner` and bundle `org.example.owner.aitesthost`, `TEST SUCCEEDED`. No `✘` lines. The only `warning:`
  lines are the AppIntents metadata notice.
- **`c07e12a`.** Adds `import TendCore` and the `model(household: Household)` signature to the test-only
  `UnavailableOnDevice`. Identical to the same helper on `origin/m2/on-device-adapter-v2` (empty diff). Test helper
  only, no product code.
- **Linux runs (this review, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `849d6db`, read-only mount,
  scratch `/tmp/sp1r3c` and `/tmp/sp1r3i` inside the container).** TendCore: "141 tests in 18 suites passed", exit 0,
  0 `warning:` lines. TendIngestion: "580 tests in 68 suites passed", exit 0, 0 `warning:` lines. Same counts as Mac
  B1/B2 in `SP-1-r4`. TendAI and the hosted bundle are Mac-only and are taken from the committed logs.
- **Personal data.** I scanned the added lines of `e20ba9f..eca2327` and `eca2327..849d6db` (code, dev-notes, both
  records; about 23 900 lines). No user home path (`$HOME`, `$SIM_DEVICE`, `$APP_CONTAINER` tokens). The only e-mail
  is `noreply@anthropic.com`; `user@api.openai.com` is a test URL argument in main's transport test. No person's name
  or user name, no team ID, no phone UDID, no signing identity. The UUIDs are URLSession task IDs and test fixtures.
  I-4 and I-5 are as noted.
- **Authorship.** `ea3d195`, `eca2327`, `88921e8`, `c07e12a`, `849d6db`: author and committer `Claude
  <noreply@anthropic.com>`. The other commits in the range come in from `main`/PR #44 and were reviewed there.
- **Frozen eval (D6).** No path under `Fixtures/` and no `MANIFEST.sha256`, `inputs.json`, `golden.json`,
  `household.json` or `results-v1` in `git diff --name-only e20ba9f 849d6db`. `Fixtures/` is identical to
  `origin/main`. The Part T2 `git grep` at `c07e12a` prints nothing. Pass.
- **Swift 6.** The new state (`quickStopTry`, `firstStop`, `lastStopAt`) is main-actor only (`SP1SpeechModel`,
  `QuickStopAttempt` are `@MainActor`; `lastStopAt`/`tryStart` are locals). The consumer task is `@MainActor`. Every
  read after `Task.sleep` re-checks `attemptState.ended`. No new `@unchecked Sendable` or `nonisolated(unsafe)`. The
  hosted build compiles with warnings as errors (B5).
- **UX-3 words.** The new strings and identifiers (`firststop`, `timer`, `planned`, `stop_tapped`) contain no banned
  word. "latest" appears only in code comments (not UI copy) and is not the word "late".
- **No network, no new dependency.** No `URLSession`/`URLRequest` in `Apps/TendAITestHost`. No new package.

## Checklist (round 3)
- [x] Correctness vs ACs (SP-1 Part D): m-4/n-4 closed; printed format matches; D1 commit contents present (T1)
- [x] Tests meaningful: scaffold test passes with two prefixes; no test changed or weakened in this range (only the `c07e12a` helper signature)
- [x] Swift 6 concurrency safe
- [x] No force unwraps / `try!` added
- [x] Privacy (P-1…P-4): each try bounded and cancelled at worst; m-5 is a reduced fallback only
- [x] UX-2/UX-3 (n.a. / no banned word)
- [x] Accessibility (UI): not product UI
- [x] Performance: n.a. (debug host)
- [x] No new dependency without ADR (link model: m-6 ticket)
- [ ] **Merge faithful and docs complete: no** (M-3, dev-notes lost WI-M2-M2 Law check, Handoff log and AC → test)

## Law check (round 3)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug buttons in a never-shipped test host. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | New output fields and comments use no banned word (scanned: overdue, late, missed, failed, behind, penalty; "latest" in comments only). |
| UX-4 Design craft | n.a. | Test host, not product UI (SP-1 Part D). |
| P-1 On-device inference | pass | Unchanged; the speech adapter equals `8c324a6` (on-device `SpeechAnalyzer`); `FoundationModels` on device. |
| P-2 No data leaves device (except user iCloud) | pass | No network code in the host. Main's transport hosted tests use `StubProtocol` only (timeouts in B5 are stubbed, no real request). No personal data in the records. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path in the probe; main's cloud code is unchanged by this branch. |
| P-4 Media not persisted without consent | pass (with m-5 note) | Each quick-stop try is bounded and at worst cancelled, which tears the microphone down; nothing is stored. m-5: [Stop] is a no-op during the closing countdown, so the fallback there is closing the app. Device proof stays with SP-1 B4/B5 (AWAITING-DEVICE). |

## Handoff log (round 3)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Round 3 of `m2/sp1-probe` at `849d6db`: `e20ba9f..ea3d195`, merge `88921e8`, `88921e8..c07e12a`, records SP-1-r3/r4. |
| 2026-11-27 | Reviewer | Orchestrator → Developer | returned | CHANGES REQUIRED: M-3 (restore the 61 lost WI-M2-M2 dev-notes lines from `origin/m2/on-device-adapter-v2` 5807-6023, drop the stray row, fix the "rebuilt by section" sentence, reword the link-change sentence per m-6). Docs only; `SP1-COMMIT` stays `c07e12a`. Optional m-5 (needs a new `SP1-COMMIT` and B5/D5 re-run). |
| 2026-11-27 | Reviewer | Orchestrator → Planner | sent | m-6 ticket: undo or isolate `BUNDLE_LOADER: ""` before the M2 gate or before any hosted test uses host code/state; not a merge blocker. |
| 2026-11-27 | Reviewer | Orchestrator → Acceptance Tester | sent | SP-1.md changes 1-7 above (format, D4.7, B4/B5 rule without the m-4 caveat, B5 duration and closing step, `SP1-COMMIT = c07e12a`, Part T incl. PR #44 round-5 approval, B5 37 tests). M-3 blocks the merge only, not the device run (the build `c07e12a` is unchanged by its fix); ready for the owner once these edits are in and the PR #44 round-5 review is APPROVE. |
