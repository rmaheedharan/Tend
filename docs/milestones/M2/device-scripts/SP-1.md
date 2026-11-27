# SP-1: device spike on the iPhone 15 Pro (information only)

- **Owner:** Acceptance Tester  ·  **Run by:** the human owner  ·  **Date written:** 2026-11-27  ·  **Base:** `origin/main`
  `41bf8fa`, branch `m2/sp1-device-script`
- **Status:** READY FOR THE DEVELOPER (Part D below). The owner runs it only after the Tester has filled in the
  "Values" table and done the pre-run checks (Part T).
- **What it is:** a short spike that answers R-1: "is the on-device time to first item (TTFI) under 1.5 s on the real
  gate phone, with one duplicate-lookup `Tool` call per capture?" (PO ruling 2026-11-27, `po-m2-r1-latency.md`,
  option (d)). It also checks three speech things on the real phone: the T-27 permission prompt, a quick stop, and stop
  then start again (review PR #42 M1 / M1-r2, review i3).
- **What it is not:** it is **not evidence for any AC**. AC-M2-16 stays **AWAITING-DEVICE** until DS-1 Part A (the
  frozen eval, 20 inputs, in `TendEval`) is run and recorded (CLAUDE.md §5). SP-1 never uses the frozen eval
  (`Fixtures/M2/eval`); it uses the Developer's own dev set (plan R-2, R-19).
- **Requirement IDs:** FR-A1, P-1, P-4, UX-3; AC-M2-07 (one `Tool` call, word-match floor), AC-M2-11 (voice path on
  device), AC-M2-16 (the number SP-1 looks at, not proven here), AC-M2-25 (same speech adapter on the iPhone 13, not run
  here); plan SP-1, R-1, R-3, MS-2, B5, B6, Q20; brief Q4, T-27, Definitions "Time to first item"; PO R-1 ruling
  (a)-(d); review PR #42 M1, M1-r2, i2, i3.
- **Devices:** the iPhone 15 Pro only (on-device model). The iPhone 13 is not used (it has no on-device model; cloud
  only, DS-2). The Mac is the owner's Mac mini (M1) with Xcode 27.2.

---

## Part D: what the Developer must provide before the run

The `TendEval` harness (WI-M2-M7) does not exist yet, so SP-1 runs from the existing never-shipped `TendAITestHost`
app and its `TendAIHostedTests` bundle (plan WI-M2-M1, `project.yml`). Deliver D1-D6 in one small PR, branch
`m2/sp1-probe`, reviewed as usual. Nothing here is product UI or product code; it is test code in a host app that is
never shipped and never archived.

**D1. The build under test.** The SP-1 commit (`SP1-COMMIT`) must contain:
- the one-call `Tool` rule from PR #43 (`fad715a`, "one answered duplicate-Tool call per capture"), and
- the speech adapter from PR #44 **with review M1-r2 fixed** (the sticky stop also covers `engine.prepare()` /
  `engine.start()`), at a round the Reviewer has approved.
Best: both PRs merged to `main`, and `m2/sp1-probe` branched from that `main`. If you must combine unmerged heads,
say so in the PR and name both heads.

**D2. `project.yml` (no hand-edited `.pbxproj`; ADR-0003).**
1. A build setting `TEND_BUNDLE_PREFIX` (default `com.tend`). The bundle IDs of `TendAITestHost` and
   `TendAIHostedTests` become `$(TEND_BUNDLE_PREFIX).aitesthost` and `$(TEND_BUNDLE_PREFIX).aihostedtests`. A free
   Apple account needs bundle IDs that nobody else has used, so the owner passes his own prefix on the command line
   (Q20). Using the same setting for `Tend` and `TendEval` is recommended (MS-3 needs it too), but SP-1 needs only these
   two.
2. `TendAITestHost` gets `INFOPLIST_KEY_NSMicrophoneUsageDescription` with one short calm sentence (for example
   "TendAITestHost uses the microphone to test voice capture. Nothing is saved."). No banned word (UX-3).
3. **No** `NSSpeechRecognitionUsageDescription` in any target. Reason: T-27 says the speech-recognition permission is
   not needed. If the phone does need it, the app will stop at the first capture or show a second prompt, and SP-1 sees
   it. Do not add the key "to be safe".
4. B5 and B6 still pass unchanged (the probe is skipped in B5; `Tend` Release and Archive still hold no `TendEval`).

**D3. The timing probe: a hosted test `SP1TimingProbe`** (file `Packages/TendAI/HostedTests/SP1TimingProbe.swift`).
1. **Off by default.** It runs only when the environment variable `TEND_SP1` is `1` (set by the owner with
   `TEST_RUNNER_TEND_SP1=1`, which `xcodebuild` passes to the test process). In B5 it reports as skipped.
2. **Inputs: the Developer dev set only.** The 8 captures and the household (8 tasks, 3 rooms) of
   `docs/milestones/M2/evidence/mac/WI-M2-M2-r2/probes/devset-main.swift` (on the PR #43 branch), with the same
   expectations per chore, IDs `dev1` ... `dev8` in that order, and fixed UUIDs. It must not read, bundle or copy
   anything from `Fixtures/M2/eval`, and no input may equal a frozen input.
3. **Order of work in one test process:**
   - **Header:** device model code (`utsname.machine`, for example `iPhone16,1`), `operatingSystemVersionString`,
     `thermalState`, `isLowPowerModeEnabled`, and the on-device model availability (`FoundationModelsOnDeviceSource`
     `availability()`). If the model is not available, print the reason, record a test issue and stop.
   - **Cold:** `dev1` once, as the first model use in the process, with **no** `prewarm`.
   - **Warm:** 3 rounds over `dev1` ... `dev8` (24 captures). For each: `prewarm(household:)`, wait 1.0 s (the person
     taps before speaking, Q4), then run it.
4. **Clock (brief Definitions, AC-M2-16 clock rules for text):** `ContinuousClock`. Start when the text is handed to
   the pipeline (`DraftPipeline` events from the on-device model). **TTFI** ends at the first `emitted` event.
   **Total** ends when the event stream finishes. Limit each capture to 30 s; if it is reached, print `timeout` and go
   on.
5. **Per capture, also print:** the number of `Tool` calls that were answered and the number that were refused (the
   one-call cap; `DuplicateLookupRecorder.refusedCalls` or an equal count; `@testable import` is fine, no new public
   API just for this), the outcome, the number of drafts, and the dev-set check (duplicates created, false merges) as
   in `devset-main.swift`.
6. **No timing `#expect`.** The numbers are information only, so the test passes whatever the times are. It fails
   only if the model is not available or the probe itself breaks. Use `.timeLimit(.minutes(15))`.
7. **Output lines, exactly this shape**, one per line, written to standard output with no buffering (flush after each
   line), each with a running number `seq`. Times in whole milliseconds. No bundle ID, no device name, no UDID, no team,
   no user name in any line.
   ```text
   SP1|seq=1|header|device=iPhone16,1|os=Version 26.x (Build 23xxx)|thermal=nominal|lowPower=false|model=available|commit=<git sha if available, else unknown>
   SP1|seq=2|cold|input=dev1|ttfi_ms=2345|total_ms=6789|tool_answered=1|tool_refused=0|outcome=completed|drafts=2|dup_created=0|false_merges=0
   SP1|seq=3|warm|round=1|input=dev1|ttfi_ms=...|total_ms=...|tool_answered=1|tool_refused=0|outcome=completed|drafts=2|dup_created=0|false_merges=0
   ...
   SP1|seq=27|summary|warm_n=24|ttfi_min_ms=...|ttfi_median_ms=...|ttfi_max_ms=...|ttfi_under_1500=x/24|total_median_ms=...|total_max_ms=...|total_le_5000=x/24|tool_answered_max=1|tool_refused_sum=...
   SP1|seq=28|footer|thermal=nominal|lowPower=false
   ```
   The `commit` field is optional (for example from an `Info.plist` value set at build time); the Mac header file in
   step A2 records the commit anyway.

**D4. The speech screen in `TendAITestHost`** (the app's root view; never shipped).
1. It does **nothing** at launch: no permission request, no speech or asset call, no microphone, until a button is
   tapped. So the hosted tests (B5, D3) are not changed by it.
2. Buttons with exactly these labels, large enough to tap quickly:
   **[Speech status]**, **[Get speech model]**, **[Start]**, **[Stop]**, **[Quick stop test]**.
3. Below them, a list of the same `SP1|...` lines it prints (big text, newest at the bottom), so the owner can also take
   a screenshot. The lines also go to standard output with no buffering (the owner's Terminal saves them).
4. It uses the product path, nothing hand-made: `SpeechPermission.requestMicrophone()` on the first **[Start]**, then
   `SpeechCapture(locale: en_US).events(from:)` with **one** `MicrophoneAudioSource` kept for the whole session (so a
   second capture reuses it). **[Stop]** calls that source's `stop()`.
5. **[Speech status]** prints `SpeechCapture.readiness()` and `SpeechPermission.microphone()`. It must not start a
   download. **[Get speech model]** downloads the en-US speech assets (`AssetInventory`), only when tapped (online).
   Where the download code lives (the adapter's planned `prepareAssets()`, or the probe) is your choice.
6. Lines to print (one capture is number `n`):
   ```text
   SP1|seq=..|speech-status|readiness=ready(speechTranscriber)|mic=notAsked
   SP1|seq=..|capture|n=1|start|mic_before=notAsked
   SP1|seq=..|capture|n=1|mic_after=allowed
   SP1|seq=..|capture|n=1|transcriber=speechTranscriber
   SP1|seq=..|capture|n=1|stop_tapped
   SP1|seq=..|capture|n=1|finished=transcribed|ms_stop_to_finished=180|words=7|text=Water the plants and wash the car
   SP1|seq=..|quickstop|try=1|when=beforeChosen|finished=nothingHeard|ms_stop_to_finished=40
   SP1|seq=..|quickstop|done
   ```
   The transcript text is printed only because the owner reads a fixed invented sentence (P-4: nothing is stored by the
   app; no audio is kept).
7. **[Quick stop test]** runs 10 tries by itself, 1 s apart, with the same source: tries 1-5 call `stop()` right after
   the capture is started (before `transcriberChosen`); tries 6-10 call `stop()` at the `transcriberChosen` event (the
   M1-r2 window). Each try prints its line. After try 10 it prints `quickstop|done` and shows "Look at the top of the
   screen now" with a 10-second countdown.

**D5. Dry run and command check (owner's Mac, through Remote Control).**
1. Run B5 with the probe present: it passes, and `SP1TimingProbe` shows as skipped.
2. Run the probe on the iOS 26.5 Simulator with `TEST_RUNNER_TEND_SP1=1` and `-only-testing:TendAIHostedTests/SP1TimingProbe`.
   The model may be unavailable there; that is fine. Show that `SP1|...` lines appear in the `xcodebuild` log and that
   `grep -o 'SP1|.*'` extracts them.
3. Launch `TendAITestHost` on the Simulator with `xcrun simctl launch --console` and show that the speech-screen lines
   reach the Terminal.
4. Check, on Xcode 27.2, every owner command in Part A and Part B (the `-only-testing` name, the `TEST_RUNNER_`
   variable, `-allowProvisioningUpdates`, `-allowProvisioningDeviceRegistration`, `TEND_BUNDLE_PREFIX`, and
   `xcrun devicectl device process launch --console`). If any option or name differs, tell the Tester; the Tester
   corrects this script. No Simulator timing is ever reported as an SP-1 result.
5. Record D5 in `dev-notes.md` (information only) and give the Tester `SP1-COMMIT`.

**D6. Do not change** the frozen eval, any `@Guide` text or instruction (option (b) is on HOLD, PO ruling), or the
one-call rule, to make SP-1 look better.

---

## Part T: Tester checks before the owner is asked to run (Acceptance Tester)

- T1. `git merge-base --is-ancestor fad715a SP1-COMMIT` succeeds, and the PR #44 round with M1-r2 fixed is an ancestor.
- T2. The probe uses no frozen-eval file: `git grep -n -e 'Fixtures/M2/eval' -e 'inputs.json' -e 'golden.json' SP1-COMMIT -- Packages/TendAI/HostedTests Apps/TendAITestHost`
  prints nothing. The 8 dev-set texts are not equal to, or contained in, any `text` in `Fixtures/M2/eval/inputs.json`
  (checked at `41bf8fa`: no overlap; re-check at `SP1-COMMIT`).
- T3. `project.yml` at `SP1-COMMIT` has `NSMicrophoneUsageDescription` for `TendAITestHost` and no
  `NSSpeechRecognitionUsageDescription` anywhere.
- T4. D5 is recorded: B5 passes with the probe skipped; the line format above appears in the dry-run log.
- T5. Fill in the "Values" table and correct any command the Developer reported in D5.4. Then tell the Orchestrator
  "SP-1 ready for the owner".

---

## Values (filled in by the Tester before the run)

| Name | Value |
|---|---|
| `SP1-COMMIT` (the commit to build) | *to be filled in* |
| Dev-set source | `devset-main.swift` (PR #43 evidence), 8 inputs `dev1`-`dev8` |

The owner picks two more values on the day (they are **not** written into this file or into any committed file):
- `PREFIX`: your own bundle ID prefix (Q20), see step S4.
- `TEAM`: your Personal Team ID, see step S5.

---

## Owner steps (about 45 minutes; simple steps)

**Before you start.** You need: the Mac mini, the iPhone 15 Pro, its USB-C cable, and your Apple ID (a free Apple
Developer account is enough). The iPhone 13 is not needed. If the Developer agent is working on your Mac through Remote
Control, it can type the Mac commands for you; you still do the iPhone steps.

**Privacy.** The tests use only made-up sentences. The full Terminal logs may show your name (from your signing
certificate) and your phone's name. Keep the full logs on your Mac. You only send the short `sp1-*.txt` files, which
hold only the `SP1|` lines.

### Setup (one time, about 20 minutes)

- [ ] S1. **The iPhone.** Settings → General → Language & Region: **English (US)**, region **United States**. Settings →
  Apple Intelligence & Siri: **Apple Intelligence on**, and the page no longer says it is downloading. Battery at least
  50%. **Low Power Mode off** (Settings → Battery). Turn on **Do Not Disturb**. Close all other apps.
- [ ] S2. **Keep the screen on.** Settings → Display & Brightness → **Auto-Lock → Never**. (Set it back after SP-1.)
- [ ] S3. **Remove the old test app.** If you see an app called **TendAITestHost** on the iPhone, press and hold its
  icon → **Remove App** → **Delete App**. (This makes sure the iPhone asks for the microphone again in Part B.)
- [ ] S4. **Pick your bundle ID prefix (Q20).** A free account needs a name nobody else has used. Make one up, in the
  form `com.<word>.tend`, for example `com.bluekettle42.tend`. Use only small letters and numbers in the word. Do not use
  your name or email. Keep the same prefix later for `TendEval`. Tell the Orchestrator which one you chose.
- [ ] S5. **Your Apple ID in Xcode, and your Team ID.**
  1. Open Xcode → **Xcode → Settings → Accounts**. If your Apple ID is not there, click **+** → **Apple ID** and sign in.
  2. Click your Apple ID → your **Personal Team** → **Manage Certificates…**. If there is no **Apple Development**
     certificate, click **+** → **Apple Development**. Click **Done**.
  3. In Terminal, run:
     ```bash
     security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
     ```
     It prints a line with `OU=` and 10 letters and numbers, for example `OU=AB12CD34EF`. Those 10 characters are your
     `TEAM`. Do not paste the line anywhere else.
- [ ] S6. **Connect the iPhone.** Plug it into the Mac with the cable. Unlock it. If it asks **"Trust This
  Computer?"**, tap **Trust** and type your passcode. In Xcode, open **Window → Devices and Simulators** and wait until
  the iPhone is shown as ready (the first time this can take some minutes).
- [ ] S7. **Developer Mode.** On the iPhone: Settings → Privacy & Security → **Developer Mode** → on → **Restart**.
  After the restart, unlock the iPhone and tap **Turn On**, then type your passcode. (If you do not see Developer Mode,
  do S6 again and wait, then look again.)
- [ ] S8. **Get the code.** In Terminal, go to your Tend folder (type `cd `, drag the Tend folder into the window,
  press Return). Then paste this, with `SP1-COMMIT` from the Values table:
  ```bash
  git fetch origin && git switch --detach SP1-COMMIT && git status --porcelain
  ```
  The last command must print **nothing**. If it prints anything, stop and tell the Orchestrator.
- [ ] S9. **Set the values for this Terminal window** (put in your own values; nothing is saved):
  ```bash
  PREFIX=com.yourword.tend
  TEAM=AB12CD34EF
  mkdir -p ~/tend-sp1-out
  xcodegen generate --spec project.yml
  xcodebuild -showdestinations -project Tend.xcodeproj -scheme TendAIHostedTests | grep 'platform:iOS,'
  ```
  The last command lists your iPhone like `{ platform:iOS, arch:arm64e, id:00008130-…, name:… }`. Copy the text after
  `id:` up to the comma, and set it:
  ```bash
  DEV=00008130-paste-your-id-here
  ```
  (Do not use a line that says "Any iOS Device" or "Simulator".)
- [ ] S10. **Mac header** (for the record):
  ```bash
  { git rev-parse HEAD; git status --porcelain; sw_vers; xcodebuild -version; } > ~/tend-sp1-out/sp1-mac-header.txt
  ```

### Part A: timing (about 15 minutes; you only wait)

The phone stays plugged in and unlocked for all of Part A. Do not use it while a run is going.

- [ ] A1. **Run 0 (install and trust).** Paste:
  ```bash
  TEST_RUNNER_TEND_SP1=1 xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests \
    -destination "platform=iOS,id=$DEV" -only-testing:TendAIHostedTests/SP1TimingProbe \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" TEND_BUNDLE_PREFIX="$PREFIX" \
    -resultBundlePath build/results/SP1-run0.xcresult 2>&1 | tee ~/tend-sp1-out/full-run0.log
  ```
  - If it stops and says the developer is **not trusted**, or the iPhone says **"Untrusted Developer"**: on the iPhone
    go to Settings → General → **VPN & Device Management** → under **Developer App** tap your Apple ID → **Trust**.
    Then paste the same command again.
  - If it shows a red error about the bundle identifier ("not available" or "cannot be registered"), pick another word
    in S4, set `PREFIX` again, and paste the command again.
  - If it ends with `** TEST SUCCEEDED **`, Run 0 is done. Any other ending: copy the last 30 lines into a text file
    and tell the Orchestrator.
- [ ] A2. **Restart the iPhone** (hold the side button and a volume button → slide to power off → turn it on again).
  Unlock it. Wait **2 minutes** with the screen on. (This makes Run 1 a true cold start.)
- [ ] A3. **Run 1.** Paste the same command with `run1` in both names:
  ```bash
  TEST_RUNNER_TEND_SP1=1 xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests \
    -destination "platform=iOS,id=$DEV" -only-testing:TendAIHostedTests/SP1TimingProbe \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" TEND_BUNDLE_PREFIX="$PREFIX" \
    -resultBundlePath build/results/SP1-run1.xcresult 2>&1 | tee ~/tend-sp1-out/full-run1.log
  ```
- [ ] A4. **Run 2**, right after Run 1 (no restart): the same command with `run2` in both names.
- [ ] A5. **Make the short files** (only the `SP1|` lines):
  ```bash
  for r in run0 run1 run2; do grep -o 'SP1|.*' ~/tend-sp1-out/full-$r.log > ~/tend-sp1-out/sp1-$r.txt; done
  wc -l ~/tend-sp1-out/sp1-run*.txt
  ```
  Each of `sp1-run1.txt` and `sp1-run2.txt` should have about 28 lines. If one has 0 lines, tell the Orchestrator.

### Part B: speech (about 10 minutes; you tap and speak)

- [ ] B1. **Open the app from Terminal** (so its lines are saved). Paste:
  ```bash
  xcrun devicectl device process launch --console --terminate-existing --device "$DEV" "$PREFIX.aitesthost" \
    2>&1 | tee ~/tend-sp1-out/full-speech.log
  ```
  The **TendAITestHost** app opens on the iPhone with the buttons. Leave the Terminal window open.
- [ ] B2. Tap **[Speech status]**. If the line says `assetsNotInstalled`, tap **[Get speech model]**, wait until it says
  done, then tap **[Speech status]** again. It should say `ready(...)`.
- [ ] B3. **First capture: the permission prompt (T-27).** Tap **[Start]**. Watch the screen carefully.
  - You should see **one** message: *"TendAITestHost" Would Like to Access the Microphone*. Tap **Allow**.
  - Write down **every** message that appears, with its exact words. In particular: did any message say **"Speech
    Recognition"**? Did the app close by itself?
  - Then say, at a normal pace: **"Water the plants and wash the car"**. Tap **[Stop]**.
  - A `finished=transcribed` line should appear with your words.
- [ ] B4. **Quick stop by hand (3 times).** Tap **[Start]** and then **[Stop]** at once, as fast as you can. Do not
  speak. Look at the top of the screen: the small **orange dot** (or the microphone sign in the Dynamic Island) must go
  away within **3 seconds** and stay away for **10 seconds**. Do this 3 times. Write down, for each time, "dot gone" or
  "dot stayed".
- [ ] B5. **Quick stop test (automatic).** Tap **[Quick stop test]** and do not touch the phone. It starts and stops
  the microphone 10 times by itself (about 15 seconds). When it says **"Look at the top of the screen now"**, watch for
  10 seconds: the orange dot must be gone. Write down "dot gone" or "dot stayed".
- [ ] B6. **Stop, then start again.** Tap **[Start]**, say **"Kettle needs descaling, also wipe the oven door"**, tap
  **[Stop]**. Right away tap **[Start]** again, say **"Water the plants and wash the car"**, tap **[Stop]**. Both
  should show a `finished=transcribed` line with the words you said. Then check the orange dot is gone.
- [ ] B7. Then **quick stop, then start again**: tap **[Start]** and **[Stop]** at once; right away tap **[Start]**,
  say **"Water the plants and wash the car"**, tap **[Stop]**. The last capture should show `finished=transcribed` with
  your words. Check the dot is gone.
- [ ] B8. Take a **screenshot** of the app's line list (side button + volume up). Then in Terminal press
  **Control-C** to end.
- [ ] B9. Make the short file:
  ```bash
  grep -o 'SP1|.*' ~/tend-sp1-out/full-speech.log > ~/tend-sp1-out/sp1-speech.txt; wc -l ~/tend-sp1-out/sp1-speech.txt
  ```
  If it has 0 lines, keep the screenshot; it is enough for Part B.

Say only the printed sentences while recording. If you said anything else, tell the Orchestrator before you send the
files.

### Send the results

- [ ] R1. Set **Auto-Lock** back to what you had. You can unplug the iPhone.
- [ ] R2. Send these to the Orchestrator (for example: copy them into the Tend folder
  `docs/milestones/M2/evidence/device/SP-1/` and say "SP-1 files are in"; you do not need to commit):
  `sp1-mac-header.txt`, `sp1-run0.txt`, `sp1-run1.txt`, `sp1-run2.txt`, `sp1-speech.txt`, the screenshot, and your
  notes (the run record below). **Do not send** the `full-*.log` files unless the Tester asks; they may hold your name.
  The Tester checks every file for personal data before the agent commits it.

### Run record (filled in by you)

| Field | Value |
|---|---|
| Who ran it (initials only); date; start time (local) | |
| iPhone model (should be iPhone 15 Pro, `iPhone16,1` in the header line) | |
| Bundle prefix chosen (S4) | |
| Run 0: ended with `TEST SUCCEEDED`? Any trust or bundle steps needed? | |
| Run 1 and Run 2: ended with `TEST SUCCEEDED`? | |
| B3: every message seen at the first **[Start]**, exact words. Any "Speech Recognition" message? Did the app close? | |
| B4: dot gone / dot stayed (3 times) | |
| B5: dot gone / dot stayed | |
| B6: both captures showed your words? Dot gone? | |
| B7: last capture showed your words? Dot gone? | |
| Anything odd (phone got hot, a crash, a run repeated and why) | |

---

## How the Tester reads the results

1. Personal-data check on every file before commit (no name, email, device name, UDID, team ID, bundle prefix in the
   `sp1-*` files; the header file holds only the commit, `sw_vers` and Xcode version). Remove nothing else.
2. `sp1-mac-header.txt`: the commit is `SP1-COMMIT` and `git status --porcelain` printed nothing.
3. Each run file: the header says `device=iPhone16,1` and `model=available`; drop any line repeated with the same `seq`
   (an `xcodebuild` echo), and nothing else.
4. Write the SP-1 result into `acceptance.md` as an **information-only** note under R-1 (not in the AC Results table),
   with who, when, device, iOS build and `SP1-COMMIT`. AC-M2-16 stays AWAITING-DEVICE whatever SP-1 shows.

## Decision rules (from the PO R-1 ruling 2026-11-27; brief Q4)

**Run valid?** Run 1 and Run 2 each count only if: the header shows `iPhone16,1`, `model=available`, `lowPower=false`;
the header and footer `thermal` are `nominal` or `fair`; every capture's outcome is `completed`; and the build is
`SP1-COMMIT`. If a run is not valid for an environment reason (hot phone, Low Power Mode, wrong build), the owner waits
10 minutes and runs it again; every file is kept (brief "Device-run rules" 4). Run 0 is information only.

**R-1 (timing).** Measured over the **48 warm captures** of Run 1 and Run 2 together (24 each). Each capture counts on
its own, not an average (brief Q4).
| Result | What happens |
|---|---|
| **Every** warm `ttfi_ms` < 1500 | R-1 is **closed**; options (b) and (c) are closed (PO ruling (d)). |
| **Any** warm `ttfi_ms` ≥ 1500, or any `timeout` | Not met. The Tester sends all numbers to the **PO**. Next step is option (b) (shorter guide sentences, PO approves the exact text). If it still is not met after (b), it goes to the **human owner**. Only the owner can change AC-M2-16. |
| Cold `ttfi_ms` (Run 0, 1, 2) | Information only (as AC-M2-16's cold start). Reported, never decides R-1. |
| Any warm `total_ms` > 5000 | Reported to the PO as a separate finding: AC-M2-16 also needs total ≤ 5.0 s. It does not change the R-1 rule above; the PO rules on it. |

**One-call rule (AC-M2-07, PR #43).** Every capture must show `tool_answered` ≤ 1. A capture with 2 or more is a defect
(Major, owner: Developer) against the cap, reported with the run; the timing numbers are still reported. `tool_refused`
> 0 is allowed (the model tried again and was refused) and is reported, because each refused call costs time.
`dup_created` and `false_merges` are information only (the Developer's dev-set check is on the Mac, PO ruling (a)4).

**Speech (T-27, review PR #42 M1 / M1-r2, AC-M2-11 voice path).**
| Check | Expected | If not |
|---|---|---|
| B3 permission (T-27) | Exactly one prompt, the microphone one. No "Speech Recognition" prompt. The app does not close. A `finished=transcribed` line. | T-27 finding to the Developer and the PO: the WI-M2-M1 T-27 result does not hold on device, so the AC-M2-09 Rule 5 exception must be decided again (brief T-27). |
| B4, B5 quick stop | Every try has a `finished=` line with `ms_stop_to_finished` ≤ 2000. The orange dot is gone within 3 s and stays gone 10 s, every time. | Defect, **Major**, owner Developer (WI-M2-M3; the microphone keeps running after the person stopped; P-4 consent). |
| B6, B7 stop then start again | Every second capture ends `finished=transcribed` with the spoken words (the key words "kettle", "oven", "plants", "car" are in the text). No `audioNotStarted`. The dot is gone at the end. | Defect, **Major**, owner Developer (WI-M2-M3, one capture at a time, review m1). |

These speech checks are spikes too. DS-1 (TendEval) repeats them on the gate build (DS-1 P8 and Part C).

---

## Law Check

| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The test app buttons are debug controls, not a capture form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Owner steps and the required usage sentence use no banned word. A slow result is "not met", reported calmly. |
| UX-4 Design craft | concern (watch) | A slow first item hurts felt quality; that is why R-1 is checked on the real phone. AC-M2-16 is held, not relaxed. The test host is not judged against UX-4. |
| P-1 On-device inference | pass | The timing probe uses only `FoundationModelsOnDeviceSource`; no cloud route exists in the probe. Speech is on device (`SpeechAnalyzer`). |
| P-2 No data leaves device | pass | Only invented dev-set sentences and an invented household. The short files hold no personal data and move to the owner's own Mac by cable; the Tester checks them before commit. The asset download in B2 is Apple's speech model, only when tapped. |
| P-3 Cloud AI only opt-in | n.a. | No cloud path is used. No key is needed. |
| P-4 Media not persisted | pass | No audio is stored. The only text kept is the transcript of the fixed invented sentences. The quick-stop checks test that the microphone really stops when the person stops. |

## Handoff Log

| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-27 | PO (via Orchestrator) | Acceptance Tester | accepted | R-1 ruling (d): script SP-1 on the build with option (a). |
| 2026-11-27 | Acceptance Tester | Orchestrator → Developer | sent | Part D (D1-D6): `m2/sp1-probe` with the timing probe, the speech screen, `TEND_BUNDLE_PREFIX`, the microphone usage sentence, and the D5 dry run. |
| 2026-11-27 | Acceptance Tester | Orchestrator → human owner | pending | Q20: pick the bundle prefix (S4) and use the Personal Team. Run SP-1 after the Tester says "SP-1 ready for the owner". |
| 2026-11-27 | Acceptance Tester | Orchestrator → PO | sent (info) | SP-1 uses the brief Q4 rule "each input, not an average" for R-1 (every warm TTFI < 1500 ms). A total > 5000 ms is reported to the PO separately. |
