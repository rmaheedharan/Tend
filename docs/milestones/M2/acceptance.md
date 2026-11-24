# M2 Acceptance Report

- **Owner:** Acceptance Tester  ·  **Build / commit:** not yet (M2 is IN-BUILD; base of this text `95491ed`, branch
  `m2/eval-fixtures-freeze`; v2 adds the PO follow-up rulings F3/F4 and the PR #32 `02f944e` golden-request
  verification)  ·  **Date:** 2026-11-24
- **Overall:** NOT YET ASSESSED. M2 is `IN-BUILD` (`docs/milestones/STATUS.md`). This first version holds only:
  1. the AC-M2-14 independent re-score of the scorer self-test file (WI-M2-16);
  2. the device scripts **DS-1** (WI-M2-D1: AC-M2-11, 15, 16, 17) and **DS-2** (WI-M2-D2: AC-M2-25, 26, 27), drafted
     before the build so the owner can prepare. The seven device ACs stay **AWAITING-DEVICE** (CLAUDE.md §5).
  The full verification of every AC follows after the Reviewer's APPROVE on the M2 merge commit (skill "After review").
- **Requirement IDs:** FR-A1, FR-B2, UX-1, UX-3, P-1, P-2, P-3, P-4; AC-M2-11, 14, 15, 16, 17, 25, 26, 27, 28; brief
  rubric Q3, Q4, Q15, Q16, Q20; brief "Eval scoring rules" and "Device-run rules"; plan WI-M2-16, WI-M2-D1, WI-M2-D2,
  "Scoring tool and command", B7.

## Results
| AC | Status (PASS / FAIL / AWAITING-DEVICE) | Evidence | Environment | Notes |
|---|---|---|---|---|
| AC-M2-01…10, 12, 13, 18…24, 28 | not yet assessed | — | Linux / owner-run Mac | Verified after the Reviewer's APPROVE on the M2 merge commit. |
| AC-M2-11 | **AWAITING-DEVICE** | DS-1 Part B (below) | Device, iPhone 15 Pro | Subset fixed: **in01 (text), in02 (voice), in10 (voice)** (PO F3, 2026-11-24; a change needs a DECISIONS.md entry). |
| AC-M2-14 | OPEN (not frozen) | Re-score: "AC-M2-14 independent re-score" below (agrees with the scorer log). Composition approved by the PO at `95491ed` (`eval-composition.md`, "PO approval"). | Linux + Tester review | GR-1, GR-2, GR-3, GR-5 verified and CLOSED at PR #32 head `02f944e` (`eval-composition.md`, "Verification of the regenerated golden requests", V1–V8); they hold if PR #32 merges with those golden files. Still open: PR #32 merge, L2a (GR-4) on those bodies, the Developer's composition check, `MANIFEST.sha256`, the freeze. |
| AC-M2-15 | **AWAITING-DEVICE** | DS-1 Part A | Device, iPhone 15 Pro; scoring on Linux | |
| AC-M2-16 | **AWAITING-DEVICE** | DS-1 Part A | Device, iPhone 15 Pro | |
| AC-M2-17 | **AWAITING-DEVICE** | DS-1 Part A | Device, iPhone 15 Pro; scoring on Linux | |
| AC-M2-25 | **AWAITING-DEVICE** | DS-2 Part B | Device, iPhone 13 | Subset fixed: **in08 (voice), in16 (voice)** (PO F3, 2026-11-24; a change needs a DECISIONS.md entry). |
| AC-M2-26 | **AWAITING-DEVICE** | DS-2 Part C | Device, iPhone 13; scoring on Linux | Q16 (owner, 2026-11-24): all three providers. |
| AC-M2-27 | **AWAITING-DEVICE** | DS-2 Part C (gate) and Part D (information only) | Device, iPhone 13 (+ iPhone 15 Pro, info) | |

## PRD §4 gate lines
| Gate line | Met? | Evidence |
|---|---|---|
| Automated mock tests pass 100% | not yet | AC-M2-13 after the merge commit. |
| 20 messy voice/text inputs parse accurately (iPhone 15 Pro, on device) | AWAITING-DEVICE | DS-1 Part A (AC-M2-15), fixtures AC-M2-14. |
| Latency under 1.5 s (on device) | AWAITING-DEVICE | DS-1 Part A (AC-M2-16). |
| Zero duplicate creation | AWAITING-DEVICE | DS-1 Part A (AC-M2-17), DS-2 Part C (AC-M2-26). |
| Same eval on iPhone 13, cloud path | AWAITING-DEVICE | DS-2 Part C (AC-M2-26, 27). |

## AC-M2-14 independent re-score (WI-M2-16)

AC-M2-14: "The Tester re-scores one self-test file independently and gets the same scores." Also asked by PO
`po-m2-wi15.md` ruling 3: confirm readings S1 and S4.

- **File:** `Fixtures/M2/eval-selftest/results-selftest-1.canonical.json` (SHA-256
  `2d0a7f4cb5cc69886d501f817e8d9a86191910f1c018987722ccb6cfb72e9ade`) against the self-test fixtures in the same folder
  (`inputs.json` `f6807180…`, `household.json` `a3287114…`, `golden.json` `63328f77…`). The pretty-printed twin
  `results-selftest-1.json` (`8ab4f3b8…`) holds the same data; my script gives byte-identical output on both. The
  committed tool refuses the pretty-printed one (`file rejected: not canonical JSON`, exit 2), as AC-M2-28 requires, so
  the committed log was made from the canonical file.
- **Method:** my own Python script, written only from the brief (Definitions "Name folding", "Keywords of a text" with
  the closed stop-word list, "Banned tokens"; "Eval scoring rules"), the M1 invariants (`TaskInvariantViolation` case
  list) and PO readings S1 and S4. It does not read or call the `TendIngestion` scorer.
  - Script: `docs/milestones/M2/evidence/tester/independent-rescore.py` (SHA-256
    `30330dbf6f9bf29a0dac1ea4fec170492be14ff74e9e38a29fcdfdecea824658`).
  - Output: `docs/milestones/M2/evidence/tester/rescore-selftest-1.out` (SHA-256
    `c15c30ecfe2cddc72e1e9b4bb6c9b234d29885c028fb249ce512692081d5a375`).
  - Command (Linux, repo root, Python 3, isolated mode):
    `python3 -I docs/milestones/M2/evidence/tester/independent-rescore.py Fixtures/M2/eval-selftest Fixtures/M2/eval-selftest/results-selftest-1.canonical.json`
- **Compared with:** `Fixtures/M2/eval-selftest/results-selftest-1.score.log` (SHA-256
  `e2479197d93b669e7d7d036b60996b78ac2bef110f7f2a11144ef4d4bd6d5ada`). I also re-ran the committed tool at `95491ed`
  (Linux container, Swift 6.2.4) and its new log is byte-identical to the committed one:
  `swift run --package-path Tools/TendTools tend-eval-score --profile info --fixtures Fixtures/M2/eval-selftest --schema Fixtures/M2/eval/results-v1.schema.json --expected-fixtures-sha256 aaaa…aaaa (64 × a) --results Fixtures/M2/eval-selftest/results-selftest-1.canonical.json --log <scratch>/rerun.log`
  → exit 0, `profile info: INFO (no pass rule)`, `diff` empty.

| Quantity | Scorer log | My re-score | Same? |
|---|---|---|---|
| Scored attempt per input | in02 attempt 2, all others attempt 1 | same | yes |
| Pairings (all 8 inputs) | e.g. in05 d4↔g05-mop, d3↔g05-garage, d2↔g05-plants; in02 g02-mirror not found; in07 g07-sweep not found | identical for every input | yes |
| Best targets (all drafts) | e.g. in03 d1, d2 → t-pods; d3, d4, d5 → g03-towels; in04 d1, d2 → g04-bathroom; in05 d5 → none | identical for every draft | yes |
| N / extras | 18 / 4 (in03 d2, d4; in05 d1, d5) | 18 / 4 (same drafts) | yes |
| Drafts / valid | 21 / 20 (in05 d3 `windowEndNotAfterStart`) | 21 / 20 (same draft, same invariant) | yes |
| Introduced banned tokens | 4: in06 d2 title "overdue", in06 d3 room "missed", in08 d2 title "late" × 2 | 4, same occurrences | yes |
| Duplicates created | 6 (in03 3, in04 1, in05 2) | 6 (same per input) | yes |
| False merges | 1 (in02 g02-oven) | 1 (same item) | yes |
| Segmentation / kind / room / effort | 16 / 15 / 13 / 15 of 18 | 16 / 15 / 13 / 15 | yes |
| Critical / deepClean / weatherDependent | 15 / 15 / 15 of 18 | 15 / 15 / 15 | yes |
| Required counts (⌈p × N⌉) | 18, 18, 17, 16, 18, 18, 18 | same | yes |

- **S1 confirmed:** draft text is the distinct keywords of title ∪ sourcePhrase (in01 d1 "Service the AC" + "The AC
  needs servicing" gives `[service ac servicing]`, overlap 3, not 4; in05 d4 overlap 3).
- **S4 confirmed:** each introduced occurrence counts (in08 d2 "late late" = 2, because the scored transcript has no
  "late"); a token the user said counts zero times (in06 transcript says "late", so d1 "Pay the late gas bill" counts 0).
- **Result: the re-score agrees with the scorer on every number. AC-M2-14's re-score clause is met** (the AC stays
  OPEN until the freeze).
- **Limit of my script (stated, not a finding):** banned-token splitting uses Latin letters only (en-US, Q2); keyword
  splitting uses Unicode word characters minus `_`. Both are enough for the en-US fixtures. I will run the same script
  over every device results file as the AC-M2-15 / 26 re-score.

## Exploratory testing
Charter (30 min, Linux, `95491ed`): *"Can a device results file pass an AC-M2-11 or AC-M2-25 profile while not being
the named subset?"* Read the profile rules in the tool's usage and ran the scorer on the self-test file.
- Finding A-F1: the `ds1-offline`, `ds2-offline` and `ds2-online` profiles check the **count** of inputs and of voice
  inputs, not their **IDs**. Any 3 inputs with 2 voice would pass `ds1-offline`. Mitigation in the scripts below: I
  check the input IDs by hand (step S5 of each scoring part) before I record a PASS. A tool check would be better
  (Minor, below).

## Defects
| ID | Severity | AC | Steps | Expected | Actual | Owner |
|---|---|---|---|---|---|---|
| A-F1 | Minor | AC-M2-11, AC-M2-25 | Score any 3-input file (2 voice) that is not in01, in02, in10 with `--profile ds1-offline`. | The profile refuses inputs other than the subset named in this file (or the tool takes the subset as an argument). | Only the counts are checked. | Developer, **OPEN (Minor)**. PO F4: the Developer pins the IDs in the profiles (`ds1-offline` = in01 text, in02 voice, in10 voice; `ds2-offline`/`ds2-online` = in08 voice, in16 voice), anything else exits 2 with a plain reason, the log prints input IDs and modes, plus a right-count wrong-ID self-test; due before DS-1/DS-2 scoring. DS-1 S5 and DS-2 S7 stay as a second control, recorded with the file's IDs. If the fix is not in before scoring, S5/S7 alone are accepted for that scoring and A-F1 stays open. Only I close A-F1. |

## Device test scripts (for the human owner)

### Read this first (both scripts)

**What you need.** The Mac with Xcode 26 (MacBook Air M4 or Mac mini M1), a free Apple Developer account (your Apple
ID), the iPhone 15 Pro and the iPhone 13, both on iOS 26, both with a Lightning or USB-C cable. A quiet room for the
voice inputs. About 2 hours for DS-1 and 3 hours for DS-2.

**Values you will check on screen.** Fill these in before the run (the Tester gives them to you through the
Orchestrator once the eval is frozen and the M2 merge commit exists):

| Name | Value |
|---|---|
| `APP-COMMIT` (the M2 merge commit TendEval was built from, WI-M2-M8) | *to be filled in* |
| `FIXTURE-HASH` (SHA-256 of `Fixtures/M2/eval/MANIFEST.sha256`, shown by TendEval) | *to be filled in at the freeze* |

**About the app.** `TendEval` is a test app, not Tend. Its screens are plain test controls (AC-M2-28). In the steps,
names in **[square brackets]** are the controls AC-M2-28 and plan WI-M2-M7 require (input list, script text, start,
retake reason, network fields, key field, export, "Remove key"). The Developer has not built the harness yet, so the
Tester will check every bracketed name against the real WI-M2-M7 build and update this script before your run. If a
button on screen has a different name, do not guess: stop and tell the Orchestrator.

**Rules for every run (brief "Device-run rules").**
1. Text inputs: you do **not** type them. TendEval hands the fixture text to Tend word for word.
2. Voice inputs: read the printed words aloud **exactly**, including "um", "uh" and the self-corrections ("no wait,
   Thursday"). Speak at a normal pace, about 20 cm from the phone. Nothing you say is stored as audio.
3. Retake: **at most one** per voice input, and **only if you misread the words** (skipped a word, said a wrong word,
   coughed). Type the reason in **[Retake reason]** (for example "said Wednesday instead of Thursday"). Never retake
   because Tend's result looks wrong.
4. Never re-run a whole run to get a better result. Repeat a whole run only for an environment fault (the app crashed,
   the wrong build, the wrong network). Write the reason in the run record and keep every file.
5. Keep every results file TendEval writes, including repeated ones and ones that do not pass.

**Getting the results files to the Mac (every part).** On the iPhone open **Files** → **Browse** → **On My iPhone** →
**TendEval**. Long-press the newest file named `m2-eval-<device>-<route>-<date>.json` → **Share** → **AirDrop** →
your Mac. On the Mac it lands in **Downloads**. Move it (Finder) into the Tend repository folder
`docs/milestones/M2/evidence/device/`. Put screenshots and screen recordings in the same folder. Then tell the
Orchestrator "DS-1 files are in" (or DS-2). You do not need to commit; the agent commits them and the Tester scores
them.

**Before each script: is TendEval installed and in date?** TendEval is installed by the Developer in Mac session MS-3
(plan B7). A free account's install works for **7 days**. If the app icon is missing, or the app says it "is no longer
available", or it shows "Untrusted Developer", do Appendix A first.

---

### DS-1: iPhone 15 Pro, on-device model (WI-M2-D1; AC-M2-15, 16, 17, then AC-M2-11)

**Device:** iPhone 15 Pro. **iOS:** 26.x (record the build). **App:** TendEval, Debug, built at `APP-COMMIT`.
**Fixtures:** frozen, `FIXTURE-HASH`. **Model:** Apple on-device model, greedy sampling. **Cloud:** off.

#### Preconditions (about 15 minutes; check each box)
- [ ] P1. iOS build: **Settings → General → About → iOS Version**. Tap the number once to show the build (for example
  `23A341`). Write it in the run record.
- [ ] P2. Language and region: **Settings → General → Language & Region**: iPhone Language **English (US)**, Region
  **United States**.
- [ ] P3. Apple Intelligence: **Settings → Apple Intelligence & Siri** → **Apple Intelligence** on. Wait until the page
  no longer says it is downloading (on Wi-Fi and power this can take a while). Siri language: **English (United
  States)**.
- [ ] P4. Power: battery at least 50%, **Low Power Mode off** (**Settings → Battery**), phone not hot. Unplug the cable
  during the run.
- [ ] P5. Quiet phone: turn on **Do Not Disturb** (Control Centre → Focus). Close all other apps (swipe up from the bottom
  and hold, then flick each app away).
- [ ] P6. Wi-Fi on for Part A (cloud is off, so nothing is sent; Wi-Fi lets the speech assets download).
- [ ] P7. Open **TendEval**. Check on its first screen:
  - the fixtures hash equals `FIXTURE-HASH` (compare the first 8 and last 8 characters at least);
  - **[Route preference]** is on-device first and **no provider / cloud off** is shown, and no key is stored;
  - the on-device model status reads **available** (if it says "not ready", wait for P3 to finish; if "not eligible",
    stop and tell the Orchestrator);
  - the speech status reads **ready / installed**. If it offers **[Download]**, tap it and wait.
  Take a **screenshot** of this screen (press side button + volume up). File it as `ds1-p7-start.png`.
- [ ] P8. The first time you use the microphone, iOS asks for permission. Tap **Allow**. Note in the run record
  whether a speech-recognition permission prompt appeared, and its exact words (plan WI-M2-M1, T-27 device check).
- [ ] P9. Speed test (for the record only): open Safari, go to `fast.com`, tap **Show more info**, write down Download,
  Upload and Latency (Unloaded). Enter them in TendEval's **[Network]** fields with kind `home Wi-Fi`.
- [ ] P10. **[Operator]**: type your name or initials.

#### Part A: the gated run, all 20 inputs (AC-M2-15, 16, 17), about 60 minutes
1. **Fresh launch for the cold start.** Swipe TendEval away (app switcher), then open it again. Do not tap anything
   else first.
2. Tap **[Start gated run]**. TendEval first runs **in01** once with no prewarm and records the cold-start time
   (information only, AC-M2-16). It is a text input, so you just wait.
3. TendEval then shows the inputs **in fixture order, in01 to in20**. For each one:
   - **text** (in01, 03, 05, 07, 09, 11, 13, 15, 18, 19): tap **[Run]** and wait until it says finished.
   - **voice** (in02, 04, 06, 08, 10, 12, 14, 16, 17, 20): read the words below (they are also on screen). Tap
     **[Record]**, read the words, then tap **[Stop]** (or wait if TendEval stops by itself). Wait until it says
     finished. If you misread, use your one retake (rule 3).
4. When in20 is finished, tap **[Export]**. TendEval writes
   `m2-eval-iPhone16,1-onDevice-<date>.json` (the device code for iPhone 15 Pro is `iPhone16,1`).
5. **Do not** look for a better result or run again. Copy the file to the Mac (see "Getting the results files").

The 10 voice inputs, word for word (from `Fixtures/M2/eval/inputs.json`):

| Input | Read aloud exactly |
|---|---|
| in02 | Um, okay, so I need to pay the electric bill by Friday, no wait, Thursday, and, uh, book the dentist for the kids, and the bathroom sink is draining really slowly |
| in04 | So, uh, the gutters are full of leaves again, clear those once it's dry, and mow the back garden every week from now on, but only when it's not raining, and grab more trash bags |
| in06 | Okay, uh, we're nearly out of dishwasher tablets, and toilet paper, we need toilet paper, and um the washing machine in the laundry room smells funny so run a hot cleaning cycle |
| in08 | Right, the water bill, pay that by the twentieth, um, no, by the fifteenth, and renew the car insurance this week, and, uh, pick up a birthday card |
| in10 | Um, so water the garden plants every morning, and, uh, the windows, wash the outside windows when there's no rain forecast, and get the water heater serviced every year |
| in12 | Take the trash out tonight, it's trash day every Tuesday, um, fix the squeaky garage door this weekend, and, uh, yeah, the trash, don't forget the trash |
| in14 | Okay so, um, paint the garden fence when it's dry, no, actually, just stain it, sometime next week, and deep clean the kitchen fridge, it smells, and, uh, book the window cleaner |
| in16 | Uh, book the car in for a service on Monday, no wait, Tuesday, and, um, the gutters, clear the gutters before the rain comes, and bleed the radiators in the bedroom |
| in17 | We're low on cat food, the kibble, so order more, and the dishwasher tablets, yeah, those too, and, um, sort through the kids room toy box in three days |
| in20 | Um, okay, the bedroom windows, no, the living room windows, wash them this afternoon if it's sunny, and dust the bookshelves in the hallway, and, um, book the chimney sweep every year before winter |

#### Part B: airplane mode, 3 inputs (AC-M2-11), about 10 minutes
**The AC-M2-11 subset (fixed before any device run): in01 (text), in02 (voice), in10 (voice).**
Why these three: together they hold all four item types (one-off, recurring, restock, weather-dependent), both modes,
a self-correction ("no wait, Thursday"), a critical bill, a new room (Balcony), the PRD FR-A1 sentence (in01), and
three existing-task mentions (`t-pods`, `t-dentist`, `t-plants`) that the on-device duplicate `Tool` must find with no
network. None has a repeat inside the input; that case is gated on all 20 inputs in Part A.

6. Open **Control Centre** and turn **Airplane Mode on**. Then make sure **Wi-Fi is off** and **Bluetooth is off**
   (tap their icons until they are grey; airplane mode can leave them on). Take a **screenshot of Control Centre**:
   `ds1-b6-airplane.png`.
7. In TendEval, set **[Network]** kind to `airplane mode` and the numbers to 0.
8. Tap **[Run subset]** and choose **in01, in02, in10** (in that order). Run each as in step 3 (one retake rule
   applies).
9. Tap **[Export]**. This is a second file (it holds only the 3 inputs). Take a screenshot of the export confirmation.
10. Turn Airplane Mode off. Copy the file to the Mac.

#### What to record (DS-1 run record, filled in by you; the Tester completes the scoring rows)
| Field | Value |
|---|---|
| Who ran it; date and start time (local and UTC) | |
| Device model; iOS build (P1) | iPhone 15 Pro; |
| `APP-COMMIT` as shown by TendEval | |
| Fixtures hash as shown by TendEval (must equal `FIXTURE-HASH`) | |
| Model / sampling | Apple on-device model / greedy |
| Network and speed test (P9) | home Wi-Fi, down / up Mbps, latency ms |
| Speech permission prompt seen? Exact words (P8) | |
| Retakes (input, reason) | |
| Environment faults and repeated runs (reason) | none / … |
| Part A results file name and SHA-256 | (Tester fills in SHA-256) |
| Part B results file name and SHA-256 | (Tester fills in SHA-256) |
| Screenshots | `ds1-p7-start.png`, `ds1-b6-airplane.png`, export confirmation |

#### Scoring (Acceptance Tester, Linux, repo root, after the files are committed)
- S1. `sha256sum -c Fixtures/M2/eval/MANIFEST.sha256` → every line `OK`. `H=$(sha256sum Fixtures/M2/eval/MANIFEST.sha256 | cut -d' ' -f1)`; `H` must equal `FIXTURE-HASH` and the file's `run.fixturesSHA256`.
- S2. Part A:
  `swift run --package-path Tools/TendTools -c release tend-eval-score --profile ds1-gated --fixtures Fixtures/M2/eval --expected-fixtures-sha256 "$H" --results docs/milestones/M2/evidence/device/<part-A-file>.json --log docs/milestones/M2/evidence/device/<part-A-file>.score.log`
- S3. Part B: the same with `--profile ds1-offline` and the Part B file.
- S4. My independent re-score of both files:
  `python3 -I docs/milestones/M2/evidence/tester/independent-rescore.py Fixtures/M2/eval <file>.json > <file>.rescore.out`.
  Every total must equal the scorer log (AC-M2-15 "The Tester's re-score must agree").
- S5. By hand: the Part B file holds exactly in01 (text), in02 (voice), in10 (voice) (A-F1); `run.provider` is null;
  `run.routePreference` is `onDeviceFirst`; `run.network.kind` says airplane mode; the screenshot shows airplane mode
  on, Wi-Fi and Bluetooth off; each voice attempt has a non-empty `transcript`. Part A holds all 20 inputs, last
  attempt scored, at most one retake per voice input, each with a reason; `coldStart.inputID` is `in01`.

#### Pass rules (all must hold; the AC is FAIL otherwise)
| AC | Pass rule | Read from |
|---|---|---|
| AC-M2-15 | In the S2 log: N = 58; segmentation ≥ 56 found and extras ≤ 2; kind ≥ 56; room ≥ 53; effort ≥ 50; critical, deepClean, weatherDependent ≥ 56 each; validity 100%; 0 introduced banned tokens; route `onDevice` for every input; no provider. S4 agrees on every number. | S2 checks "… (Q3)", "validity", "0 introduced …", "route onDevice", "run on device"; S4 |
| AC-M2-16 | Every one of the 20 scored inputs: TTFI < 1500 ms and total ≤ 5000 ms. Cold start reported, not scored. | S2 check "every input TTFI < 1500 ms and total <= 5000 ms (AC-M2-16)" |
| AC-M2-17 | 0 duplicates created, false merges ≤ 1, over all 20 inputs. | S2 checks "0 duplicates created", "false merges <= 1"; S4 |
| AC-M2-11 | S3 exits 0 (each of the 3: outcome `completed`, route `onDevice`, every golden item found, 0 extras, all drafts valid, 0 introduced banned tokens, 0 duplicates created), **and** S5 holds. | S3 log, S5 |

Note: `ds1-gated` covers AC-M2-15, 16 and 17 in one exit code. I record each AC from its own check lines, so one AC can
PASS while another FAILs.

---

### DS-2: iPhone 13, cloud model (WI-M2-D2; AC-M2-25, then AC-M2-26 and 27)

**Device:** iPhone 13 (no on-device model; ADR-0005). **iOS:** 26.x (record the build). **App:** TendEval, Debug, at
`APP-COMMIT`. **Fixtures:** `FIXTURE-HASH`. **Providers (Q16, owner 2026-11-24):** all three, each with its curated
model: OpenAI `gpt-6-luna`, Anthropic `claude-haiku-4-5-20251001`, Gemini `gemini-3.5-flash-lite` (brief Q18).
**Keys:** your own, one per provider. You pay the API cost (about 3 × 20 short requests, plus 4 for Part B and 1 Mac
check before and after each provider). **Network:** home Wi-Fi (Q15).

**Your keys stay safe.** You paste a key only into TendEval's **[Key]** field (it goes to the iPhone Keychain, this
device only) and, for the served-model check, at a hidden Terminal prompt on the Mac. Never paste a key into a chat,
a file or this document. At the end of each provider, tap **[Remove key]**.

#### Preconditions (check each box)
- [ ] P1–P5 and P8–P10 as in DS-1, on the iPhone 13 (skip P3: the iPhone 13 has no Apple Intelligence).
- [ ] P6. Wi-Fi on.
- [ ] P7. Open TendEval. Check: the fixtures hash equals `FIXTURE-HASH`; the on-device model status reads **not
  eligible** (this is expected on iPhone 13); the speech status reads **ready / installed** (tap **[Download]** if
  offered and wait; this must happen **before** airplane mode, plan R-7). Screenshot: `ds2-p7-start.png`.

#### Part A: the served-model check on the Mac (before each provider's run; brief Q18, plan condition 2)
Do this on the Mac, in **Terminal**, from the Tend repository folder, at `APP-COMMIT`, right before that provider's
Part C run, and again right after it. It sends one fixed sample sentence with no household data (plan "Real provider
recordings").
```bash
swift run --package-path Tools/TendTools tend-payload-dump --provider openai --outcome-sample > "$TMPDIR/body.json"
read -rs TEND_KEY      # paste the key and press Return; nothing is shown
curl -sS -N https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $TEND_KEY" -H 'Content-Type: application/json' \
  -H 'User-Agent: Tend' -H 'Accept-Language: en-US' \
  --data-binary @"$TMPDIR/body.json" | grep -o '"model":"[^"]*"' | sort -u
unset TEND_KEY; rm "$TMPDIR/body.json"
```
- Anthropic: `--provider anthropic`; URL `https://api.anthropic.com/v1/messages`; headers
  `-H "x-api-key: $TEND_KEY" -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json'
  -H 'User-Agent: Tend' -H 'Accept-Language: en-US'`; same `grep`.
- Gemini: `--provider gemini`; URL
  `'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse'`;
  headers `-H "x-goog-api-key: $TEND_KEY" -H 'Content-Type: application/json' -H 'User-Agent: Tend'
  -H 'Accept-Language: en-US'`; and `grep -o '"modelVersion":"[^"]*"'`.
- Write the printed model name in the run record, before and after. **If the before and after names differ, or differ
  from the curated model, that provider's run is void until a PO ruling** (plan condition 2): record it and tell the
  Orchestrator.

#### Part B: AC-M2-25, offline then online, 2 voice inputs, about 15 minutes
**The AC-M2-25 subset (fixed before any device run): in08 (voice) and in16 (voice).**
Why these two: both are spoken with a self-correction; together they hold critical bills, a weather condition, a room
named by the person (Bedroom), two existing tasks the cloud must recognise from the shortlist (`t-insurance`, which is
`resurfaced`, and `t-gutters`), and a false-merge trap ("car … service" against `t-car` "Wash the car"). They are
different from the AC-M2-11 voice inputs, so the two device phones speak four different voice inputs between them.

Use **one** provider for Part B: the first one you run in Part C (default **OpenAI**). Write which one in the record.
1. Do Part A (served-model check) for this provider.
2. In TendEval: **[Provider]** → the provider; paste your key in **[Key]**; read the consent text and tap **[Agree]**.
   **[Route preference]**: on-device first (the iPhone 13 has no on-device model, so the route is the cloud).
3. **Offline.** Control Centre → **Airplane Mode on**, then make sure **Wi-Fi and Bluetooth are off**. Screenshot:
   `ds2-b3-airplane.png`. Set **[Network]** kind to `airplane mode`, numbers 0.
4. Tap **[Run subset]**, choose **in08, in16**. For each, tap **[Record]**, read the words below, **[Stop]**.
   Each should end calmly with no tasks and an offer to keep your words as a plain note. Take a **screenshot of that
   screen for each input**: `ds2-b4-in08-offline.png`, `ds2-b4-in16-offline.png`. Do **not** accept the plain note.
5. Tap **[Export]** (the offline file).
6. **Online.** Airplane Mode off, Wi-Fi on. Wait until Wi-Fi is connected. Set **[Network]** to `home Wi-Fi` with the
   P9 numbers.
7. Tap **[Run subset]**, choose **in08, in16** again, speak them again, then **[Export]** (the online file).
8. Keep the key in for Part C if this provider is next; otherwise tap **[Remove key]**.

| Input | Read aloud exactly |
|---|---|
| in08 | Right, the water bill, pay that by the twentieth, um, no, by the fifteenth, and renew the car insurance this week, and, uh, pick up a birthday card |
| in16 | Uh, book the car in for a service on Monday, no wait, Tuesday, and, um, the gutters, clear the gutters before the rain comes, and bleed the radiators in the bedroom |

#### Part C: AC-M2-26 and 27, all 20 inputs, once per provider, about 45 minutes each
Do this three times: **OpenAI, then Anthropic, then Gemini**.
1. Part A (served-model check, **before**).
2. In TendEval: **[Provider]** → this provider; paste its key; **[Agree]** to the consent. For Gemini, the consent
   screen shows a warning recommending a paid-tier key (Q17): read it and note in the record which tier your key is.
3. Check **[Network]** is `home Wi-Fi` with today's speed test (repeat P9 if more than an hour has passed).
4. **Fresh launch:** swipe TendEval away and open it again (re-enter the provider and consent if TendEval asks; consent
   is kept only in memory). Tap **[Start gated run]** and run in01 to in20 exactly as in DS-1 Part A step 3 (same voice
   table, same retake rule).
5. **[Export]**. The file is named `m2-eval-iPhone14,5-<openai|anthropic|gemini>-<date>.json` (the device code for
   iPhone 13 is `iPhone14,5`).
6. Tap **[Remove key]**. Screenshot that the key is removed.
7. Part A (served-model check, **after**).

#### Part D: information only (AC-M2-27), iPhone 15 Pro with "always use my cloud model", about 45 minutes
On the **iPhone 15 Pro**, one provider (your choice; default OpenAI): **[Route preference]** → **always use my cloud
model**, provider, key, **[Agree]**, then the 20 inputs as in Part C steps 3–6. This run is not a gate; it shows how the
cloud compares on the faster phone. It never replaces AC-M2-16.

#### What to record (DS-2 run record; one block per provider plus Part B and Part D)
| Field | Value |
|---|---|
| Who ran it; date and start time (local and UTC) | |
| Device model; iOS build | iPhone 13; |
| `APP-COMMIT` and fixtures hash as shown by TendEval | |
| Provider; curated model; served model **before** and **after** (Part A) | |
| Gemini key tier (paid / free) | |
| Sampling (as recorded in the file) | |
| Network and speed test (down / up Mbps, latency ms) | |
| Transcriber used (TendEval shows it; also in the file) | `SpeechTranscriber` / `DictationTranscriber` |
| Speech permission prompt seen? Exact words | |
| Retakes (input, reason); environment faults (reason) | |
| Results file names (Part B offline, Part B online, Part C × 3, Part D) | (Tester fills in SHA-256) |
| Screenshots | `ds2-p7-start.png`, `ds2-b3-airplane.png`, two offline outcome screens, three "key removed" screens |

#### Scoring (Acceptance Tester, Linux, repo root)
- S1. As DS-1 S1.
- S2. Part B offline: `tend-eval-score --profile ds2-offline …` (same arguments as DS-1 S2).
- S3. Part B online: `--profile ds2-online`.
- S4. Part C, per provider `<p>`: `--profile ds2-gated --allowed-key-paths Fixtures/M2/payload/allowed-key-paths-<p>.json`.
- S5. Part D: `--profile info`.
- S6. My independent re-score of every file (as DS-1 S4); totals must agree.
- S7. By hand: Part B files hold exactly in08 and in16, both voice (A-F1); both Part B files name the same provider;
  in the offline file each attempt has a non-empty `transcript` and a non-null `transcriber`, `cloudRequests` is empty
  and nothing is committed; the two offline screenshots show the calm outcome with the plain-note offer; served models
  before and after match the curated ID for every provider; each "key removed" screenshot is present.

#### Pass rules
| AC | Pass rule | Read from |
|---|---|---|
| AC-M2-25 | S2 exits 0 (provider selected, 2 voice inputs, each `noModel` with no draft and nothing committed) **and** S3 exits 0 (each: route `cloud(<provider>)`, `completed`, every golden item found, 0 extras, all drafts valid, 0 duplicates created) **and** S7 holds (on-device transcript and transcriber recorded while offline; plain-note offer seen). | S2, S3, S7 |
| AC-M2-26 | For **each** of the three providers, the S4 log shows: the Q3 thresholds as in DS-1 AC-M2-15 (N = 58; 56 / 56 / 53 / 50 / 56 / 56 / 56; extras ≤ 2; validity 100%; 0 introduced banned tokens); route = that provider for every input; 0 duplicates created; false merges ≤ 1; "sent key paths are a subset of the allowed list" holds. S6 agrees. S7 served-model check holds. | S4 check lines (except the timing line), S6, S7 |
| AC-M2-27 | For each provider, the S4 check "every input TTFI < 3000 ms and total <= 10000 ms (AC-M2-27)" holds. Part D figures are reported in this file for information only. | S4 timing line; S5 |

If the owner narrows Q16 to fewer providers, that needs a PO decision first; a provider left out is hidden in the app
until it passes (brief Q16). It is never "skipped" in this script without that decision.

---

### Appendix A: reinstall TendEval on an iPhone (free Apple Developer account; about 10 minutes per phone)
Only if TendEval is missing or expired (7-day limit). It installs the same `APP-COMMIT`; nothing else changes.
1. On the Mac, open **Terminal** and go to the Tend repository folder (`cd` + drag the folder into the window +
   Return).
2. Run `git checkout <APP-COMMIT>` and then `git status --porcelain`. The second command must print **nothing**. If it
   prints anything, stop and tell the Orchestrator.
3. Run `xcodegen generate --spec project.yml`, then `open Tend.xcodeproj`.
4. In Xcode: **Xcode → Settings → Accounts**. If your Apple ID is not listed, click **+** → **Apple ID** and sign in.
5. Connect the iPhone with the cable. Unlock it. If it asks "Trust This Computer?", tap **Trust** and enter the
   passcode.
6. In Xcode's top bar, pick the scheme **TendEval** and, next to it, your iPhone.
7. In the left column click the blue **Tend** project icon → under Targets click **TendEval** → tab **Signing &
   Capabilities** → **Team**: choose **<your name> (Personal Team)**. Change nothing else. If Xcode shows a red error
   about the bundle identifier or the number of apps, take a screenshot and stop: tell the Orchestrator.
8. Press **⌘R** (Product → Run). The first time on a phone:
   - If Xcode says Developer Mode is needed: on the iPhone, **Settings → Privacy & Security → Developer Mode** → on →
     **Restart**, then confirm **Turn On** after the restart. Press ⌘R again.
   - If the iPhone says "Untrusted Developer": **Settings → General → VPN & Device Management** → under **Developer
     App** tap your Apple ID → **Trust**. Press ⌘R again.
9. TendEval opens on the phone. Check that it shows `APP-COMMIT` and `FIXTURE-HASH`. Unplug the cable.
(The Developer's Terminal route for the same install is plan "B7"; either is fine.)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every input is one free brain-dump: spoken live or handed over as text. TendEval's controls are debug test controls (AC-M2-28), not a capture form. |
| UX-2 Rule of Three | n.a. | No "what to do now" surface in M2 (brief T-21). |
| UX-3 Zero-Guilt | pass | Calm words are gated at 0 introduced banned tokens (AC-M2-15, 11). Script copy for the owner uses no banned word; the offline outcome is checked to be calm (AC-M2-25). |
| UX-4 Design craft | n.a. | No product UI; TendEval is not judged against UX-4 (plan WI-M2-M7). |
| P-1 On device first | pass | DS-1 runs with cloud off; AC-M2-11 runs in airplane mode with Wi-Fi and Bluetooth off; DS-2 proves the transcript is made on device while offline (AC-M2-25). |
| P-2 No data leaves the device | pass | Only invented fixture data is used. Results files move by AirDrop to the owner's own Mac; TendEval never uploads (AC-M2-28). The fast.com speed test sends no household data. |
| P-3 Cloud AI opt-in, minimised | pass | Cloud only after the owner pastes their own key and agrees to the consent; "Remove key" after each provider; sent key paths checked against the allowed lists (AC-M2-26). The Mac served-model check sends the fixed Outcome sample with an empty household. Keys never go into files or chat. GR-1, 2, 3, 5 closed at PR #32 `02f944e`; GR-4 (L2a) must close before the freeze. |
| P-4 Media not persisted | pass | No audio is stored (brief device-run rules); TendEval writes only the results file (AC-M2-28); screenshots show no household data beyond the invented fixtures. |

## Open questions and needs (route through the Orchestrator)
| ID | For | Question / need | Needed by |
|---|---|---|---|
| AQ-1 | Developer (WI-M2-M7) | The scripts need: a subset run of named inputs that exports its own results file (`ds1-offline`, `ds2-offline`, `ds2-online` require 3 or 2 inputs per file); on-screen model availability, speech-asset status with a download while online, the route preference, the selected provider and whether a key is stored; the device's `APP-COMMIT`. Please confirm these exist, and give the exact control labels so I can replace the bracketed names. | Before WI-M2-M7 review |
| AQ-2 | Developer | A-F1 (Minor): let the subset profiles check input IDs (for example a `--inputs in01,in02,in10` option), or confirm the manual check S5/S7 is the accepted control. **ANSWERED (PO F4, `po-m2-wi16.md` follow-up, 2026-11-24):** the Developer fixes the tool (IDs pinned in the profiles, not a free argument; exit 2 otherwise; IDs and modes in the log; self-test), due before DS-1/DS-2 scoring; S5/S7 stay as manual controls with the file's IDs recorded. A-F1 stays open until I verify the fix. | Before DS-1 |
| AQ-3 | Human owner (Q20, plan O-3) | Confirm the signing team: your free personal team is assumed in Appendix A. | Before MS-3 |
| AQ-4 | PO | Confirm the AC-M2-11 subset (in01, in02, in10) and the AC-M2-25 subset (in08, in16). They are fixed now, before any device output exists. **ANSWERED (PO F3, 2026-11-24):** confirmed and fixed: AC-M2-11 = in01 (text), in02 (voice), in10 (voice); AC-M2-25 = in08 (voice), in16 (voice). Any change after the freeze or a device run needs a DECISIONS.md entry; choosing a subset after seeing results is not allowed (governance PR records it). | Before the freeze |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Acceptance Tester | accepted | WI-M2-16 remaining Tester items: independent re-score of `results-selftest-1`; DS-1 and DS-2 (WI-M2-D1, D2) with the AC-M2-11 and AC-M2-25 subsets. |
| 2026-11-24 | Acceptance Tester | Orchestrator → PO, Developer, owner | sent | Re-score agrees with the scorer log on every number (S1, S4 confirmed). DS-1 and DS-2 drafted; all seven device ACs AWAITING-DEVICE. AQ-1…AQ-4 open. AC-M2-14 stays OPEN until GR-1/GR-2 verification and the freeze. |
| 2026-11-24 | PO (via Orchestrator) | Acceptance Tester | answered | `po-m2-wi16.md` follow-up rulings: F3 fixes both subsets (AQ-4 answered); F4: Developer fixes A-F1 in the tool, S5/S7 stay (AQ-2 answered, A-F1 open). |
| 2026-11-24 | Acceptance Tester | Orchestrator → PO, Developer, owner | sent | AQ-2, AQ-4 answered. GR-1, GR-2, GR-3, GR-5 verified and closed at PR #32 head `02f944e` (`eval-composition.md` v3). DS-2 Part A `curl` lines now send `User-Agent: Tend` and `Accept-Language: en-US` (GR-10). AC-M2-14 stays OPEN (PR #32 merge, L2a, composition check, manifest, freeze). AQ-1, AQ-3 open. |
