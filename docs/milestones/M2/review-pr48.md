# M2 Code Review — PR #48 (`m2/sp1-device-script`, round 1 @ `b5492a6`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this change)  ·  **Verdict:** **CHANGES REQUIRED**  ·  **Round:** 1
- **Scope:** Docs only. `git diff origin/main...HEAD` covers 2 files: new `docs/milestones/M2/device-scripts/SP-1.md`
  (+392), the owner-run iPhone 15 Pro spike for R-1 (PO ruling 2026-11-27 option (d)); and
  `docs/milestones/M2/acceptance.md` (+25/−1): a link to SP-1 and DS-1 Part C (quick stop, stop then start again;
  AC-M2-11 voice path, P-4, review PR #42 M1 / M1-r2). No code, no fixture, no protected path is touched.
- **Inputs read:** `CLAUDE.md`; this skill; the PO ruling `/mnt/project-files/notes/po-m2-r1-latency.md`; `brief.md`
  AC-M2-16 (`:595`), Q4 (`:1005`), T-27 (`:1157`, `:1443`); `acceptance.md` (DS-1, AQ-1); `project.yml`; `.gitignore`;
  `Fixtures/M2/eval/inputs.json`; `devset-main.swift` on `origin/m2/on-device-adapter-v2` (the PR #43 evidence);
  `Packages/TendAI/HostedTests/TendAIHostedScaffoldTests.swift`; the review template.
- **Milestone lock:** `STATUS.md` shows M2 `IN-BUILD`. An `m2/` device-script change is allowed (CLAUDE.md §5).

## Summary

The script is careful and mostly right. SP-1 is clearly information only and AC-M2-16 stays `AWAITING-DEVICE`. The
decision rules match the PO ruling. The frozen eval is never used, and the privacy split (short `SP1|` files sent, full
logs kept on the Mac) is sound. One owner step is not exact on the most likely path: the `xcodebuild` commands reuse a
fixed `-resultBundlePath`, so the retry that A1 tells the owner to do (after "Untrusted Developer", which is near
certain on a first install with a free account) fails, and a re-run of an invalid Run 1 or 2 overwrites the log that
must be kept. That is a Major (M1). The rest are Minor, Nit or Info.

### 1. Nothing in `acceptance.md` removed or weakened
- `git diff origin/main...HEAD | grep '^-'` shows exactly one removed content line: the DS-1 run-record row
  `| Screenshots | ds1-p7-start.png, ds1-b6-airplane.png, export confirmation |`. It comes back unchanged with
  `` `ds1-c14-restart.png` `` added (`acceptance.md:279`). Confirmed.
- Every other change is an addition: the SP-1 link (`:125`), Part C steps 11-14 (`:247-262`), one new run-record row
  (`:278`), and a Part C pass rule (`:302-304`). The rule says it "adds to the AC pass rules above and changes none of
  them", and the diff shows no AC result row, gate rule or scoring step (S1-S5) changed. This makes the check stricter,
  not weaker.
- No banned UX-3 word in the added text (`grep -w` for overdue, late, missed, failed, behind, penalty: 0 hits).

### 2. SP-1 is information only; AC-M2-16 stays AWAITING-DEVICE
`SP-1.md:11-13` ("not evidence for any AC ... AC-M2-16 stays AWAITING-DEVICE until DS-1 Part A"), `:337-338` (result
goes in as an information note under R-1, "not in the AC Results table ... whatever SP-1 shows"), and the
`acceptance.md:125` link all say this. The AC results table in `acceptance.md` is unchanged. Pass.

### 3. Decision rules against the PO ruling
| PO ruling (d) | SP-1 | Match |
|---|---|---|
| Cold and warm TTFI, plus total, on 3 or more dev-set inputs, never the frozen 20 | 8 dev inputs; cold once per run, 24 warm per run, total recorded (`:57-66`) | yes |
| Under 1.5 s: close R-1; (b) and (c) closed | "Every warm `ttfi_ms` < 1500" → R-1 closed, (b) and (c) closed (`:351`) | yes, and uses brief Q4 "each input, not an average", which is stricter |
| Miss: numbers to PO, then (b); still missing after (b): human owner; only the owner changes AC-M2-16 | `:352` | yes |
| Built with (a) in place | D1 requires PR #43 `fad715a`; T1 checks ancestry (`:31`, `:139`) | yes |
| (b) on HOLD; no AC change | D6 (`:132-133`) | yes, but see m3 |
| (a) cap: second call refused or capped | `tool_answered` ≤ 1 per capture, refused counted (`:356-359`) | yes |
Cold start is information only (`:353`). That matches brief Q4 ("cold start is reported but does not gate").

### 4. Frozen eval never used
D3.2 forbids reading, bundling or copying `Fixtures/M2/eval`; T2 greps the probe paths. I checked the claim at
`41bf8fa`: the two spoken sentences ("Kettle needs descaling, also wipe the oven door", "Water the plants and wash the
car") are `devset-main.swift:25` and `:31` on `origin/m2/on-device-adapter-v2`. Neither equals or is contained in any
`text` in `Fixtures/M2/eval/inputs.json` (closest: in07 "wash the car this Saturday if the sun's out"; in10 "water the
garden plants every morning"). Pass.

### 5. Commands on Xcode 27.2
| Command | My view |
|---|---|
| `xcodebuild -showdestinations -project … -scheme TendAIHostedTests` and `{ platform:iOS, arch:arm64e, id:00008130-…` | Plausible. `00008130` is the A17 Pro UDID prefix. The "Any iOS Device" line also matches the grep; the script warns about it. |
| `-only-testing:TendAIHostedTests/SP1TimingProbe` | Right **if** `SP1TimingProbe` is a type (`@Suite struct` or `XCTestCase`). A bare `@Test func SP1TimingProbe()` would need `…/SP1TimingProbe()`. See m4. |
| `TEST_RUNNER_TEND_SP1=1 xcodebuild test …` | Right. `xcodebuild` strips the prefix and sets `TEND_SP1` in the test process, which for a hosted bundle is the host app. |
| `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` | Right; both exist, and registration needs updates on. `project.yml:33` has `CODE_SIGN_STYLE: Automatic`, so `DEVELOPMENT_TEAM=` on the command line works. |
| `TEND_BUNDLE_PREFIX="$PREFIX"` as a build-setting override | Right once D2 lands. |
| `-resultBundlePath build/results/SP1-run0.xcresult` | **Wrong on retry.** `xcodebuild` stops with "Existing file at -resultBundlePath" when the bundle is already there, and a failed run still writes one. See M1. |
| `xcrun devicectl device process launch --console --terminate-existing --device "$DEV" "$PREFIX.aitesthost"` | Plausible. `--device` takes a UDID; `--console` and `--terminate-existing` exist. D4.3 asks for unbuffered stdout, which `--console` needs. |
| `security find-certificate -c "Apple Development" -p \| openssl x509 -noout -subject` | Works for a Personal Team (OU is the team ID), but prints only the first match. See n1. |
| `xcodegen generate`, then `git status --porcelain` in S10 | Clean: `/Tend.xcodeproj/` and `/build/` are in `.gitignore`. |
D5.4 asks the Developer to check every one of these on the owner's Mac. That is the right control; M1 still needs a
script fix, because a Simulator dry run never does the retry.

### 6. Owner safety, simple English, personal data
Steps are short and in plain words. Nothing is destructive except deleting the old test app (S3, intended), and
Auto-Lock is set back (R1). `PREFIX` and `TEAM` stay in shell variables, never in a committed file (`:158-160`). Only the
`SP1|` lines leave the Mac (`:170-172`, `:306-310`); D3.7 bans bundle ID, device name, UDID, team and user name in those
lines; the Tester checks each file before commit (`:332-333`). The `text=` field holds only the fixed invented sentences,
and the owner is told to report any other speech (`:300-301`). Pass.

### 7. Developer prerequisites D1-D6 are testable
D1 → T1 (`merge-base --is-ancestor`). D2 → T3 (grep `project.yml`) and B5. D3 → T4 (B5 skipped, line format in the dry
run) and the line shapes are exact. D4 → D5.3 (`simctl launch --console`). D5 → recorded in `dev-notes.md`, T4. D6 → by
diff review of `m2/sp1-probe`. All testable. Small gaps in m4 and n2.

### 8. Law check present
`SP-1.md:372-383` covers UX-1…UX-4 and P-1…P-4. The statuses are reasonable.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | Major | `SP-1.md:230-244`, `:247-255`, `:344-345` | Every `xcodebuild test` uses a fixed `-resultBundlePath build/results/SP1-runN.xcresult`. A1 tells the owner to "paste the same command again" after "Untrusted Developer" (near certain on the first install with a free account) or a bundle-ID error. The first try has already written `SP1-run0.xcresult`, so the retry stops at once with "Existing file at -resultBundlePath" and the owner is stuck. The same happens with the "runs it again" rule for an invalid Run 1 or 2. In that case `tee` also overwrites `full-run1.log`, which breaks "every file is kept" (brief Device-run rules 4). The owner steps are not exact on the expected path. | Give every attempt its own name and keep every file. For example, A1 retry: use `run0b` (then `run0c`) in both names. Rule at `:344-345`: re-run as `run1b`/`run2b`, keep the first files, and have A5 and the Tester read the valid attempt. Or, at the very least, add `rm -rf build/results/SP1-run0.xcresult` before a retry of Run 0 only, and never reuse a name for Run 1 or 2. Update A5's `for r in …` list to match. | Open |
| m1 | Minor | `acceptance.md:249-250` vs `:255-256` | "Do not speak in steps 11 and 12" contradicts step 12, which asks the owner to say "Water the plants and wash the car" in its second capture. | Say: "Do not speak during a quick stop (step 11, and the first capture in step 12)." | Open |
| m2 | Minor | `SP-1.md:342-345` | A run with an outcome that is not `completed` is "not valid", but a re-run is only described for environment reasons. There is no rule for a non-`completed` outcome on a clean phone (for example a model error). It could be re-run until it looks good, or dropped. | Add: a non-`completed` outcome with no environment reason is not re-run. It is reported to the Developer and the PO with the numbers, and R-1 is "not met" until they rule. | Open |
| m3 | Minor | `SP-1.md:132-133` | D6 forbids changing "any `@Guide` text or instruction". The PO ruling allows the Developer to try one technical alternative in SP-1 (meanings stated once in the on-device session instructions or a prewarmed prefix, with the parity test unchanged, and the cloud bytes unchanged). D6 is stricter than the ruling and does not say so. | Either allow it as a separate, labelled variant run after the baseline Run 1 and Run 2 (the baseline still decides R-1), or note in the Handoff Log that the Tester asks the PO to keep that alternative out of SP-1. | Open |
| m4 | Minor | `SP-1.md:50`, `:233` | `-only-testing:TendAIHostedTests/SP1TimingProbe` is right only if `SP1TimingProbe` is a type. D3 says "a hosted test", which also allows a bare `@Test func`, whose ID is `…/SP1TimingProbe()`. | In D3, say "a `@Suite struct SP1TimingProbe` (Swift Testing, as in `TendAIHostedScaffoldTests`)". | Open |
| n1 | Nit | `SP-1.md:189-194` | `security find-certificate -c "Apple Development"` without `-a` prints only the first match. A Mac with an old or second team certificate could give the wrong `TEAM`. | Optional: add "If you have more than one Apple ID in Xcode, use the Team ID shown under your Personal Team in Xcode → Settings → Accounts." | Open |
| n2 | Nit | `TendAIHostedScaffoldTests.swift:14` (base) vs D2.1 | The scaffold test expects `Bundle.main.bundleIdentifier == "com.tend.aitesthost"`. With the owner's `PREFIX` it would fail if the whole bundle ran. SP-1 is not affected (`-only-testing`). | Optional for D2: compare against the prefix setting, or note that the test assumes the default prefix. | Open |
| i1 | Info | `SP-1.md:256-261` | D5.2 proves that `SP1|` lines reach the `xcodebuild` log on the Simulator only. On a device, test stdout normally reaches the log too, and if it does not, the lines are still in the kept `.xcresult`. | Tester: if A5 gives 0 lines, take the lines from the result bundle (`xcrun xcresulttool get log --type console --path …` or the Xcode 27.2 equivalent, checked in D5.4) rather than asking for a re-run. | — |
| i2 | Info | `acceptance.md` "Read this first" | DS-1 still says "Xcode 26" while SP-1 and the owner's Mac use Xcode 27.2. This was already there before the PR. | Tester: line it up when DS-1 is next edited. | — |

## Checklist
- [x] Correctness vs ACs: SP-1 is information only; AC-M2-16 stays AWAITING-DEVICE; Part C adds to AC-M2-11 and changes no rule.
- [x] Tests meaningful: n.a. (no code). The decision rules are concrete, per capture, and match PO ruling (d) and brief Q4.
- [x] No weakening: the one removed line is the Screenshots row, re-added with `ds1-c14-restart.png`.
- [ ] Owner steps exact: M1 (result-bundle retry) and m1 (contradiction) are open.
- [x] Swift 6 concurrency safe: n.a.
- [x] No force unwraps / try! in product code paths: n.a.
- [x] Privacy (P-1…P-4): only `SP1|` lines are sent; full logs stay on the Mac; no frozen-eval data; no cloud route.
- [x] UX-2/UX-3 enforced in engine: n.a.; no banned word in the added text.
- [x] Accessibility (UI): n.a. (never-shipped test host).
- [x] Performance: n.a.
- [x] No new dependency without ADR: none added.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Debug buttons in a never-shipped host; no entry form. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No banned word in the added text or the required usage sentence; a slow result is "not met". |
| UX-4 Design craft | concern (watch) | Same as the PO ruling: a slow TTFI hurts felt craft. AC-M2-16 is held, not relaxed. |
| P-1 On-device inference | pass | The probe uses only the on-device source; speech is `SpeechAnalyzer` on device. |
| P-2 No data leaves device (except user iCloud) | pass | Only invented dev-set text; the short files go to the owner's Mac by cable and are checked before commit. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path. |
| P-4 Media not persisted without consent | pass | No audio stored; the quick-stop checks (SP-1 B4/B5, DS-1 Part C) test that the microphone really stops. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Review PR #48 at `b5492a6` against `41bf8fa`. |
| 2026-11-27 | Reviewer | Orchestrator → Acceptance Tester | returned | CHANGES REQUIRED: M1 (unique result-bundle and log names per attempt, keep every file). m1-m4 should be fixed in the same round. n1, n2, i1, i2 optional. Re-review the same file as round 2. |

---

## Round 2 (@ `475cc27`, diff `git diff fed0998 475cc27`)

- **Owner:** Reviewer (fresh context)  ·  **Verdict:** **APPROVE**  ·  **Round:** 2
- **Scope:** `SP-1.md` (+95/−30 across both files, v2) and `acceptance.md` (2 wording lines). Docs only, no protected
  path. Across the whole PR (`origin/main...475cc27`), only two lines are removed: the Screenshots row (re-added with
  `ds1-c14-restart.png`, as in round 1) and the DS-1 "Xcode 26" line (now "Xcode 26 or later … the Mac mini has Xcode
  27.2"; i2). Neither weakens a rule. The AC results table is still unchanged, and AC-M2-16 stays AWAITING-DEVICE.

### Round-1 findings, checked in the new diff
| # | Round-1 finding | What changed | Verified | Status |
|---|---|---|---|---|
| M1 | Fixed `-resultBundlePath` broke the A1 retry and the Run 1/2 re-run, and `tee` overwrote kept logs | S9 defines `sp1run <name>`. It refuses a name whose `full-<name>.log` or `SP1-<name>.xcresult` already exists, and builds both paths from the name. A1, A3, A4 and V3 use it. Retries are `run0b`/`run0c`/`run1b`/`run2b`. A5 and B9 loop over every `full-run*.log` / `full-speech*.log`. R2 sends every `sp1-*.txt`. The run record lists every name. Tester step 5: the first valid try counts, earlier tries are kept with their reason, and no try is made after a valid one. | I ran the function and the A5 loop in bash with an `xcodebuild` stub (scratchpad). `sp1run run0` twice: the second refused with "The name run0 is already used… run0b", rc=1, and the first files were untouched. `run0b` and `runv1` each made their own log, and the loop made `sp1-run0.txt`, `sp1-run0b.txt` and `sp1-runv1.txt`. A failed `xcodebuild` still leaves the `tee` log, so the guard fires even when no bundle was written. The syntax (`name() {}`, `[ -e ]`, `${n#full-}`, globs that always match here) is also valid in zsh, the macOS default shell. zsh itself is not installed in this container, so that part is read, not run. | Closed |
| m1 | DS-1 Part C "Do not speak in steps 11 and 12" contradicted step 12 | `acceptance.md:249-250` now reads "Do not speak during a quick stop (step 11, and the first capture in step 12)." | Read in the diff | Closed |
| m2 | No rule for a non-`completed` outcome on a clean phone | New paragraph under "Run valid?": it is not re-run, it is kept and reported to the Developer and PO with all numbers, and R-1 is **not met** until they rule. Also: "A run is never repeated to get better numbers." Environment re-runs use new names. | Read in the diff. It matches the PO ruling (a miss goes to the PO) and closes the cherry-picking route. | Closed |
| m3 | D6 was stricter than the PO's technical alternative and did not say so | New D7, Part V and T4b (details below). | See "Variant run" below | Closed |
| m4 | `-only-testing` ID depended on the probe being a type | D3 now says `@Suite struct SP1TimingProbe` and explains why. | Read in the diff | Closed |
| n1 | The certificate lookup prints only the first match | S5.3 adds: with more than one Apple ID or team, use the Personal Team's Team ID from Xcode → Settings → Accounts. | Read in the diff | Closed |
| n2 | The scaffold test hard-codes `com.tend.aitesthost` | D2.1 requires the scaffold test to compare against the prefix setting (for example an `Info.plist` value). | Read in the diff | Closed |
| i1 | Device stdout might not reach the `xcodebuild` log | A5: with 0 lines, do not re-run; tell the Orchestrator. Tester step 4: take the `SP1|` lines from the kept bundle (`xcrun xcresulttool get log --type console …`, or the form checked in D5.4). | Read in the diff | Closed |
| i2 | DS-1 said "Xcode 26" | Now "Xcode 26 or later … Xcode 27.2". | Read in the diff | Closed |

### Variant run (D7, Part V, T4b): information only, baseline is the shipping setup
- **The baseline is the shipping setup.** D6 now says "`SP1-COMMIT` is the baseline: the shipping setup with option
  (a), nothing else." "Run valid?" still requires the build to be `SP1-COMMIT`, so a variant try can never be a valid
  Run 1 or Run 2.
- **The variant is kept apart.** It is a separate unmerged commit `SP1-VARIANT-COMMIT` on top of `SP1-COMMIT`. Its
  header carries `variant=…` (D7.1). Part V runs last, after Part B, "never before Run 1 and Run 2", with its own names
  (`runv1`, `runv2`) and its own header file. Tester step 5 says variant tries are "reported in their own block and
  never mixed with the baseline". V5 switches back to the baseline.
- **It never closes R-1.** D7.4 says it "never decides R-1, and it is not merged because of SP-1 without a PO ruling".
  The decision table adds: variant runs are "information only … They never close R-1. If the baseline is not met and
  the variant meets the rule, the PO decides". This matches PO ruling (b): the technical alternative is allowed in
  SP-1 if the parity test still compares the same sentences and the cloud bytes are unchanged.
- **The PO's conditions are checked.** D7.2 and T4b: no path under `Fixtures/` changes (`git diff --stat`), B2
  (AC-M2-20 golden bytes) and the parity test pass, and the meaning sentences are word for word the same (D7.3, T4b).
  Option (b) stays on HOLD (no new wording).

### New findings (round 2)
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n3 | Nit | `SP-1.md` T4b | D7.2 says the one-call rule is unchanged in the variant, but T4b does not check it. A variant that loosened the cap would look faster. It cannot close R-1, but the PO might be misled when comparing. | Optional: add to T4b that `git diff SP1-COMMIT SP1-VARIANT-COMMIT` does not touch the duplicate-lookup cap code, and that the variant lines show `tool_answered` ≤ 1. | Open |
| n4 | Nit | `SP-1.md` "How the Tester reads the results" step 2 | The header check names only `sp1-mac-header.txt`. The new `sp1-mac-header-variant.txt` should show `SP1-VARIANT-COMMIT` and a clean status. | Optional: extend step 2 to the variant header. | Open |

No Blocker, Major or Minor is open. The Nits do not block.

### Checklist (round 2)
- [x] Owner steps exact: M1 and m1 closed. Every try has its own name, and no file is overwritten (checked by running the steps with a stub).
- [x] No weakening: the two removed lines are a re-added row and a wording widening. No AC, gate or scoring rule changed.
- [x] SP-1 information only; AC-M2-16 AWAITING-DEVICE; the variant never closes R-1; the baseline is the shipping setup with option (a).
- [x] Decision rules still match PO ruling (d), with brief Q4 per-capture strictness. No re-run to improve numbers (m2).
- [x] Frozen eval unused (baseline D3.2, T2; variant D7.2, T4b).
- [x] Privacy: unchanged; R2 sends only the short `sp1-*.txt` files; full logs and bundles stay on the Mac.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No banned word in the added text (the refusal message is calm: "Use a new name"). |
| UX-4 Design craft | concern (watch) | As in round 1; AC-M2-16 held, not relaxed. |
| P-1 On-device inference | pass | The baseline and the variant are both on-device only. |
| P-2 No data leaves device (except user iCloud) | pass | Only `SP1|` lines are sent; the Tester checks for personal data before commit. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path; the variant must leave the cloud bytes unchanged (B2). |
| P-4 Media not persisted without consent | pass | Unchanged; no audio stored. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Round 2 at `475cc27` (`git diff fed0998 475cc27`). |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper | accepted | APPROVE. M1, m1-m4, n1, n2, i1, i2 closed. n3 and n4 optional. Next: Merge Gatekeeper. Then the Developer builds D1-D6 (and optionally D7) on `m2/sp1-probe`. |
