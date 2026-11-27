# M2 Code Review — PR #49 (`m2/sp1-script-r3`, head `6d3d868`, docs only: `device-scripts/SP-1.md` v3)

- **Owner:** Reviewer (fresh context; did not write this script or the probe)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** `git diff origin/main...HEAD` = one file, `docs/milestones/M2/device-scripts/SP-1.md` (+45 / -10).
- **Checked against:** probe build `SP1-COMMIT` `c07e12a9647c7612b720a4d598d9f535870ca1b6` on `origin/m2/sp1-probe`
  (`Apps/TendAITestHost/Sources/SP1SpeechScreen.swift`, `Packages/TendAI/HostedTests/SP1TimingProbe.swift`, read with
  `git show`); PO R-1 ruling 2026-11-27 (`po-m2-r1-latency.md`, read only); `review-sp1-probe.md` round 3, items 1-7.
- **IDs:** FR-A1, R-1, SP-1, T-27, Q20; AC-M2-07, AC-M2-11, AC-M2-16, AC-M2-25 (all three stay AWAITING-DEVICE);
  UX-3, P-1, P-4.

## Summary

The v3 script matches the final probe build exactly. Every printed shape and field the owner or the Tester is told to
read is the one the code prints. The B4/B5 decision rule is the round 3 item 3 text word for word. Nothing in it is
weaker than v2 or the PO R-1 ruling: it only adds new ways to find a Major (`restops` >= 1, `finished=none`). I re-ran
Part T T1-T5 myself and got the same results. There are no banned words and no personal data. There is no Blocker and
no Major. Two Nits and two Info notes do not block the merge.

## Printed format check (code at `c07e12a`)

| Script text (SP-1.md) | Code | Match |
|---|---|---|
| D4.6 full shape `SP1\|seq=<n>\|quickstop\|try=<1-10>\|when=<beforeChosen\|atChosen>\|firststop=<planned\|timer>\|finished=<outcome>\|ms_stop_to_finished=<ms\|none>\|restops=<0-3>` (`:121`) | `SP1SpeechScreen.swift:225-227`; `emit` (`:33-38`) adds `SP1\|seq=<n>\|`; `when` from `attempt > 5` (`:165`); `firstStop` default `"planned"`, `"timer"` at `:204`; `outcome` default `"none"` (`:248`); `ms` is `none` unless both `stoppedAt` and `finishedAt` are set (`:221-224`); `restops` 0...3 (`:212-216`) | yes |
| D4.6 example `...try=1\|when=beforeChosen\|firststop=planned\|finished=nothingHeard\|ms_stop_to_finished=40\|restops=0` (`:116`) | Same field order as `:225-227` | yes |
| `SP1\|seq=<n>\|quickstop\|try=<n>\|stop_tapped`, only when [Stop] is tapped during the test (`:119`, `:122`) | `:138-142` (only while `busy` and `quickStopTry` is set) | yes |
| `SP1\|seq=<n>\|quickstop\|done` (`:117`, `:122`) | `:231` | yes |
| `finished=` values `transcribed`, `nothingHeard`, `unavailable(<r>)`, `stopped(<r>)`, `cancelled`, `none` (`:122-123`) | `name(_ outcome:)` `:55-63`, default `"none"` `:248` | yes |
| D4.7 limit: re-stop after 5 s with no `finished` after the latest stop, up to 3, then cancel (`:130-132`) | `:195-219` (`lastStopAt` reset at `:217`, cancel at `restops == 3` `:212-214`) | yes |
| D4.7 timer: tries 6-10, no `transcriberChosen` within 5 s of the start, then `firststop=timer` (`:132-133`) | `:200-208` (`tryStart` `:167`, check `:202`) | yes |
| D4.7 time is from the first stop to `finished` (`:133-134`) | `stoppedAt` is set once (`:172`, `:180-183` only if nil, `:203`); re-stops do not move it | yes |
| "at most about 25 s" per try (`:134-135`) | Timer path: 5 s + timer stop + 3 re-stops x 5 s + 5 s, then cancel = 25 s; tries 1-5: 20 s | yes |
| B5: "about 15 seconds" when stops work; "up to about 4-5 minutes" otherwise (`:347-348`) | 10 tries + 1 s pause each (`:228`) is about 10-15 s; worst case 5 x 21 s + 5 x 26 s + 10 s countdown is about 4 min | yes |
| B5: "[Stop] does nothing during the countdown" (`:353`) | `quickStopTry = nil` at `:230` before the countdown; `stop()` then reaches `guard current != nil` (`:144`) and returns | yes (round 3 m-5) |
| B4 by hand uses `capture\|n=` lines (unchanged, item 7) | `:104-147`; after B3 `askedMicrophone` is true, so `start()` sets `current` with no suspension and a fast [Stop] is seen | yes |

The quick stop test cannot be tapped in the Simulator, so this check comes from reading the code, as in round 3.

## Round 3 items 1-7 (`review-sp1-probe.md`) and the PO ruling

| Item | Where in v3 | Status |
|---|---|---|
| 1 D4.6 example and optional `stop_tapped` | `:116`, `:119-123` | Done |
| 2 D4.7 per-try limit, `firststop=timer`, first-stop timing | `:130-135` | Done |
| 3 B4/B5 rule: `firststop=planned`, `restops=0`, not `none`, <= 2000 ms; `restops` >= 1 / `none` is Major; `timer` is information; a try after `stop_tapped` is information; delete the m-4 caveat | `:461`. I checked the caveat: `git show origin/main:.../SP-1.md` has no "artefact" or `restops` text, so the Handoff Log is right that there was nothing to delete. | Done |
| 4 B5 owner step: duration, do not tap [Stop], wait for the countdown, "dot stayed", close from the app switcher | `:346-354` | Done (Nit n-1) |
| 5 Values `SP1-COMMIT` = `c07e12a…` with the record `SP-1-r4` | `:203`; variant "none", so Part V is skipped (`:204`, `:375`) | Done |
| 6 Part T at `c07e12a`, including the PR #44 round 5 APPROVE | `:182-195` | Done; re-checked below |
| 7 B4 by hand unchanged | `:342-345` unchanged | Done |

PO R-1 ruling: the R-1 rule (`:442-450`, every warm TTFI < 1500 ms; a miss goes to the PO, then (b), then the owner;
only the owner can change AC-M2-16), the one-call rule (`:452-455`) and "information only / AC-M2-16 stays
AWAITING-DEVICE" (`:13-15`, `:426-427`) are unchanged from v2 and match the ruling. No rule or AC is weakened.
AC-M2-11, AC-M2-16 and AC-M2-25 stay AWAITING-DEVICE in `acceptance.md` (not touched by this PR). SP-1 stays
information only (`:8`, `:185`).

## Part T re-check (this review, Linux container, after `git fetch origin`)

- **T1:** `git merge-base --is-ancestor fad715a c07e12a` exit 0; `... 8c324a6 c07e12a` exit 0. Same.
- **T2:** the `git grep` at `c07e12a` prints nothing (exit 1). I took the 8 dev texts from `SP1TimingProbe.swift` at
  `c07e12a` and the 20 `text` values from `Fixtures/M2/eval/inputs.json` at `c07e12a` and compared them with a small
  script, case-insensitive, "equal or contained" both ways: 0 overlaps. `git diff --stat origin/main c07e12a --
  Fixtures` is empty. Same.
- **T3:** `project.yml:109` has the microphone sentence (no banned word); `TEND_BUNDLE_PREFIX: com.tend` at `:106` and
  `:128`; `git grep -c NSSpeechRecognitionUsageDescription c07e12a -- ':!docs'` has no hits. Same.
- **T4:** `SP-1-r4` README: 23 of 23 SHA-256 lines OK. The D5 and B0 headers name `c07e12a…`, and both "after" files
  hold only their markers (an empty porcelain). B5 and the custom-prefix B5 show "37 tests in 6 suites passed" and
  `** TEST SUCCEEDED **`, with the SP-1 test skipped. `d5-probe-lines.txt` has 28 `SP1|` lines. Same.
- **T5:** `review-pr42.md` on `origin/m2/speech-adapter-v2` (`910c11a`) has the heading "Round 5 — PR #44 at `8c324a6`"
  with "**Verdict: APPROVE.** No open Blocker or Major." Same.
- `git diff --stat c07e12a origin/m2/sp1-probe` (now at `e3507f4`) lists only `docs/` paths, so the later commits
  (including the M-3 fix) do not change the build under test.

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n-1 | Nit | `SP-1.md:352-354` | The "dot stayed" path says "open the app again with B1 (new file name `full-speech-b.log`)". The B1 command has `full-speech.log` written in, so the owner must edit the pasted text. If the first `devicectl --console` is still attached, the owner may also need Control-C first. The owner can follow it as written (B1 `:333` gives the same hint, and B9 `:365` picks up `full-speech*.log`), but it is not paste-ready. | Optional: give the full B1 command with `full-speech-b.log`, and say "if Terminal is still waiting, press Control-C first". | Open (non-blocking) |
| n-2 | Nit | `SP-1.md:461` | The "Expected" cell lists `firststop=planned`, but the "If not" cell says `firststop=timer` is information, not a defect. It also does not say how to read a `finished=unavailable(<r>)` or `stopped(<r>)` try. This is the round 3 item 3 wording, and the Tester can read it, but a future reader could take `timer` as a fail. | Optional: add "(`timer` is information, see the next cell)" and say that a non-`none` outcome other than `transcribed`/`nothingHeard`/`cancelled` goes to the Developer as information. | Open (non-blocking) |
| i-1 | Info | `SP-1.md:184` | Part T was recorded when `origin/m2/sp1-probe` was at `2b2daed`. The branch is now at `e3507f4`, but only docs changed after `c07e12a` (checked above), so the record still holds. | None. | Info |
| i-2 | Info | `SP-1.md:203`, `:255` | The owner fetches `c07e12a` by SHA through `git fetch origin`. This works while `m2/sp1-probe` exists or is merged with a merge commit (the repo's normal style). A squash merge followed by deleting the branch would leave the commit unreachable. | Merge Gatekeeper/Orchestrator: merge `m2/sp1-probe` with a merge commit, or keep the branch until SP-1 has run. | Info |

## Other checks

- **UX-3 words:** the added lines contain no match for `\b(overdue|late|missed|failed|behind|penalty)\b`
  (case-insensitive). "latest" (`:130`) is not the word "late".
- **Personal data:** the added lines have no `@`, `/home`, `/Users` or `~/` path, no name, no user name, no host name,
  no UDID or team ID. `com.tend` and `PREFIX`/`TEAM` are placeholders. The commit author is `Claude
  <noreply@anthropic.com>`.
- **Owner English and commands:** B5 uses short, plain sentences. The app-switcher gesture is correct for an iPhone 15
  Pro. The Part A and Part B commands are unchanged from v2 (round 3 item 5: the probe still runs with
  `-only-testing:TendAIHostedTests/SP1TimingProbe`).
- **Milestone lock:** `STATUS.md` shows M1 ACCEPTED and M2 IN-BUILD; branch `m2/...`. Allowed. No protected file is
  touched.

## Checklist
- [x] Correctness vs ACs: script matches the code at `c07e12a`; round 3 items 1-7 done; PO R-1 rules unchanged
- [x] Tests meaningful: n.a. (docs); no AC or rule weakened; the new B5 rule only adds Major triggers
- [x] Swift 6 concurrency safe: n.a. (no code); the probe's timing rules I relied on were re-read in code
- [x] No force unwraps / try!: n.a.
- [x] Privacy (P-1…P-4): no personal data; the B5 closing step covers m-5
- [x] UX-2/UX-3: n.a. / no banned word
- [x] Accessibility (UI): n.a.
- [x] Performance: n.a.
- [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Device script; the test host has debug buttons only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No banned word in the added text; a slow result is "not met", reported calmly. |
| UX-4 Design craft | n.a. | Test host, not product UI. AC-M2-16 is held, not relaxed (PO ruling). |
| P-1 On-device inference | pass | The probe uses on-device `FoundationModels` and `SpeechAnalyzer` only; unchanged. |
| P-2 No data leaves device (except user iCloud) | pass | Only invented sentences; only short `sp1-*` files are sent, and they are checked first; no personal data in the diff. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path in SP-1. |
| P-4 Media not persisted without consent | pass | No audio kept. B5 now treats any unanswered stop (`restops` >= 1, `finished=none`) as a Major, and the "dot stayed" step closes the app, since [Stop] is a no-op in the countdown (m-5). Device proof stays AWAITING-DEVICE. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | PR #49 `m2/sp1-script-r3` at `6d3d868`, SP-1.md v3 for `SP1-COMMIT` `c07e12a`. |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper | sent | **APPROVE.** No Blocker/Major. Nits n-1, n-2 are optional; i-2: keep `c07e12a` reachable (merge `m2/sp1-probe` with a merge commit or keep the branch). |
| 2026-11-27 | Reviewer | Orchestrator → human owner | sent (info) | SP-1 may be run once PR #49 is merged; information only; AC-M2-11, AC-M2-16 and AC-M2-25 stay AWAITING-DEVICE. |
