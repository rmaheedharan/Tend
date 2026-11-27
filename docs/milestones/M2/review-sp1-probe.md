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
