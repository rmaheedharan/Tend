# M2 Code Review — WI-M2-M1: XcodeGen project, `TendAI` scaffold, T-27 check (PR #38, `m2/xcodegen-project`, head `02c1d84`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE (round 2, head `b1f57d3`; round 1 was CHANGES REQUIRED)  ·
  **Round:** 1 (head `02c1d84`, base `origin/main` `20c40ea`); 2 (head `b1f57d3`), see "Round 2" below
- **Requirements:** ○ AC-M2-09 (Rule 5 / T-27 decision; `TendAI` and `TendEval` scan roots to `required`),
  ○ AC-M2-13 (the Mac lane exists: B4, B5), ○ AC-M2-28 (the target and scheme structure its `project.yml` scan will
  check; owner WI-M2-M7), T-27, R-1, R-8; P-1, P-2, P-4; CLAUDE.md §3 (project generation, "no warnings"), §6 (no
  dependency without an ADR).
- **Binding inputs checked:** `CLAUDE.md`; plan.md WI-M2-M1 row, scope note and "Exact commands"; brief.md AC-M2-09
  Rules 5 and 6, AC-M2-13, AC-M2-28, T-27; ADR-0003 (diff); DECISIONS.md D-032; dev-notes.md "WI-M2-M1"; the Mac
  evidence record `docs/milestones/M2/evidence/mac/MS-1/` (README, 15 logs, probes, `run-evidence.sh`).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. WI-M2-M1 is M2 work. Allowed.
- **Protected paths:** none touched (`git diff --name-only 20c40ea..02c1d84` has no `CLAUDE.md`, `docs/PRD.md`,
  `.claude/**`, `.github/**`, `docs/governance/**`, `docs/milestones/STATUS.md`). No `.pbxproj` or `.xcodeproj` in the
  tree.
- **Merge route:** Mac-only PR, so D-032 applies (owner merges; Gatekeeper APPROVE on every rule except G3).
- **Not claimed here:** an APPROVE would not accept AC-M2-09, 13 or 28. Those are taken at the M2 merge commit.

## Summary

**1. Evidence covers `0065664`; `02c1d84` is docs-only.** `mac-B0-header.log` prints
`0065664278099efc737c4c7065f2dafec57ed524`. `git diff --name-only 0065664 02c1d84` lists only files under `docs/`
(the evidence folder, `dev-notes.md` timings and probe numbers, and the R-1 row of `plan.md`). `git status --porcelain`
before (B0) and after (`mac-B9-after.log`) shows only the untracked evidence folder. I recomputed the SHA-256 of all 22
files listed in the README: every one matches. `timings.txt` exit codes match the README table.

**2. Test-file changes are what dev-notes says.**
- `ProviderDialectTests.swift:596`: the only change is `])` → `] as [String])` plus a comment. No row, expectation,
  test name or body changed (one-line diff). The test still runs **13 cases** on Linux (my run) and on the Mac
  (`mac-B2-tendingestion.log`).
- `IngestionSourceScanTests.swift:74`: comment only; the assertion `speechPermissionExceptionEnabled == false` is
  unchanged.
- `ScanScope.swift`: `TendAI` and `TendEval` roots `optional` → `required` (the plan's rule; a required root with 0
  files now fails), Rule 5 exception stays `false`. This tightens the scan; nothing is weakened.

**3. My Linux runs (Docker `swift:6.2-noble`, `-warnings-as-errors`, scratch `/tmp/rev38-<pkg>`), all exit 0, 0
`warning:` lines, 0 `✘`, 0 `➜` skips:**

| Package | Result |
|---|---|
| TendCore | 141 tests in 18 suites passed |
| TendIngestion | 570 tests in 67 suites passed. AC-M2-09 scan: TendIngestion 55, TendAI 1, TendEval 1, 57 files, 0 violations. Both Havana tests pass here (older tzdata). |
| TendSourceScan | 63 tests in 4 suites passed |
| Tools/TendTools | 11 tests in 1 suite passed |
| TendAI | builds on Linux today (scaffold imports `Foundation` only); 1 test passed. It will stop building on Linux once the adapters land; the plan already says it is never built on Linux. |

**4. Havana (B2 on the Mac).** Two `TimeResolverTests` cases fail on macOS with tzdata 2026f (`TimeResolverTests.swift`
606, 613). This branch does not touch `TimeResolverTests.swift` or the resolver. It is not this PR's defect. It still
blocks AC-M2-13(b) until WI-M2-03's owner and the PO fix the fixture (dev-notes records it, unchanged tests: correct).

**5. AC-M2-28 structure in `project.yml` (Release/Archive exclusion).** Sound for what this item owns:
- `TendEval` has its own bundle ID (`com.tend.eval`), and no other target lists it as a dependency (`Tend` has no
  dependencies at all; `TendAIHostedTests` depends on `TendAITestHost` and the `TendAI` package only).
- `Tend` scheme builds only `Tend` (`Tend: all`); archive uses Release. B6: Release build and archive succeed and
  `find … -iname '*TendEval*'` prints nothing in both; `Products/Applications` holds only `Tend.app`.
- `TendEval` scheme: build targets `[running, testing, profiling, analyzing]` (no `archiving`), every action Debug.
  `xcodebuild archive -scheme TendEval` is refused with exit 66 (`mac-B6-eval-archive.log`).
- File sharing is in Debug only: `INFOPLIST_FILE` is set only under `configs: Debug`. B6 bundle log shows
  `UIFileSharingEnabled = true` in Debug and the 5 fixture SHA-256 equal to the repo's (they also equal the frozen
  values in review-WI-M2-16-freeze).
- The target itself still has a Release configuration (XcodeGen makes both). See m2.

**6. No new SPM dependency (P-2, CLAUDE.md §6).** `Packages/TendAI/Package.swift` has two local `path:` dependencies
(`../TendCore`, `../TendIngestion`); no `url:` in any `Package.swift`; no `Package.resolved`. `project.yml` lists three
local packages. XcodeGen is a developer tool, not linked into any product, and is recorded in ADR-0003 with an exact
version and checksum. I confirm ADR-0003's decision (it lists the Reviewer as confirming decider), subject to m3.

**7. Strict concurrency.** `project.yml` base: `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`,
`SWIFT_TREAT_WARNINGS_AS_ERRORS YES`. `TendAI` package: `swiftLanguageModes: [.v6]`. B4 and B5 pass
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the command line, so it also reaches the package targets. No
`@unchecked Sendable`, `nonisolated(unsafe)` or `Task {}` in the new code.

**8. T-27.** The probe source (`probes/Probe.swift`) never calls `requestAuthorization`. On macOS `SpeechTranscriber`
and `DictationTranscriber` transcribed the sentence while `SFSpeechRecognizer.authorizationStatus()` stayed
`notDetermined`; on the iOS 26.5 Simulator neither transcriber could run (no model; no authorization error either).
Keeping the Rule 5 exception **off** is the stricter, privacy-safe default and matches the brief ("If the Developer
finds they are not needed, there is no exception"). The evidence for iOS is documentation only. See m4.

**9. Evidence hygiene (the reason for the verdict).** The README says home and temporary paths were replaced. The user
name was, but the repository folder in the owner's home directory was not: the segment `<handle>-projects` (a
personal handle) appears **2,248 times on 1,498 lines** in 8 logs and in `run-evidence.sh:3`. See M1.

**10. Warnings.** The README says "The only `warning:` lines are `appintentsmetadataprocessor`'s". That is not true:
`mac-B6-release.log:356`, `mac-B6-archive.log:246` and `mac-B6-eval-debug.log:1114` carry the build-validation warning
"All interface orientations must be supported unless the app requires full screen." for `Tend` and `TendEval`. It is
not in the AC-M2-13(b) commands (B1, B2, B4, B5 are clean), but it comes from this PR's `project.yml` and conflicts with
CLAUDE.md §3 "no warnings". See m1.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | **Major** | `docs/milestones/M2/evidence/mac/MS-1/logs/*.log` (8 files: B2, B3, B4, B5, B6-release, B6-archive, B6-eval-debug, B6-eval-archive), `run-evidence.sh:3` | A personal identifier from the owner's home directory (`$HOME/<handle>-projects/Tend`) is committed 2,248 times, in a public repository. The README (line 31) says home paths were redacted, so the record also misstates what was done. Once merged, it stays in `main`'s history and can only be removed by a history rewrite. (Security/privacy hygiene, skill step 9; CLAUDE.md "treat information about the user as private".) | Replace the repository path everywhere in the evidence folder with a neutral token (for example `$REPO` for `$HOME/<handle>-projects/Tend`), the same way `$HOME` was done; make `run-evidence.sh` `cd` to a neutral variable (`cd "$REPO"`). Say in the README which tokens were substituted. Recompute and update the 22 SHA-256 lines. Then `grep -rn <handle> docs/` must print nothing. This is a text substitution of the committed logs; it needs no new Mac run (see Q1). | Open |
| m1 | Minor | `project.yml:43-56` (`Tend`), `:58-89` (`TendEval`); `evidence/mac/MS-1/README.md:56-57` | (a) With `TARGETED_DEVICE_FAMILY "1,2"` and no orientation keys, the `Tend` and `TendEval` builds emit "All interface orientations must be supported unless the app requires full screen." (CLAUDE.md §3 "no warnings"; it also becomes an App Store validation issue for `Tend` in M3+.) (b) The README states that no other `warning:` line exists. | (b) now, with M1 (docs only): correct the README sentence to name this warning and its three log lines. (a) Ticket: add `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` with all four orientations (and an explicit iPhone list) for `Tend` and `TendEval` in the next Mac session (MS-2), where B6 is re-run anyway. The iPad orientation choice is the Designer's (CLAUDE.md §9 Q1). | Open |
| m2 | Minor | `project.yml:58-89` (`TendEval`) | AC-M2-28 says `TendEval` "is built only in the Debug configuration". Today this holds only through the schemes; `xcodebuild -target TendEval -configuration Release` would still build it (dev-notes "Things the reviewer should look at" asks about this). | Ticket for WI-M2-M7 (● AC-M2-28): add a hard guard in the `TendEval` Release configuration (for example a Release-only setting that fails the build, or excluding all sources in Release), and have the WI-M2-M7 `project.yml` scan test assert it. Not needed for this PR. | Open (ticket) |
| m3 | Minor | `evidence/mac/MS-1/README.md:13` vs `docs/architecture/adr/0003-project-generation.md:51` | The README abbreviates the XcodeGen zip SHA-256 as `4d9e34b6…dff892`; ADR-0003 records `4d9e34b6…f0196806`. The tails differ. The binary hash (`8774da74…f99db`) matches the B0 log and the ADR. The zip pin is the dependency record (CLAUDE.md §6), so the two must agree. | With M1: re-check the zip digest against the GitHub release asset and make the README and ADR show the same value (full 64 hex digits in the README is simplest). | Open |
| m4 | Minor | `dev-notes.md` "T-27"; `plan.md` speech-permission row; R-8 | T-27 rests on Apple's documentation and a macOS command-line probe. On macOS a command-line tool's privacy permissions can be attributed to the launching terminal, so the macOS run is weaker evidence for an iOS app than it looks. If iOS does require speech authorization, it is found only in DS-1, at the device gate. | Ticket for the Planner / Tester: add a T-27 check (first capture shows the microphone prompt only, and transcribes) to SP-1 in MS-2 on the iPhone 15 Pro, so the answer arrives before the gate. The decision itself (exception off) stands. | Open (ticket) |
| n1 | Nit | `dev-notes.md` WI-M2-M1 header ("PR: not opened") and Handoff log ("no PR") | PR #38 is open. | Update to "PR #38" when the M1 fix is pushed. | Open |
| n2 | Nit | `plan.md` B6 `TendEval` Debug build command | B6 builds the packages inside the project without `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (B4 and B5 pass it). B1/B2 already cover the packages, so this is consistency only. | Optional: add the flag to the B6 commands. | Open |

**Questions (not findings):**
- **Q1 (PO / human owner, D-032 (2)).** D-032 says the record must be for the PR's exact head commit and "a new push needs
  a new record". A record can never be for the commit that adds it, so `02c1d84` (and the M1 fix) can only be docs-only
  commits on top of the tested `0065664`. I treated a docs-only delta (verified with `git diff --name-only`) as covered.
  Please confirm that reading, or say that a new Mac run is needed.
- **Q2 (PO).** AC-M2-13(b) and AC-M2-28 say "Xcode 26". The Mac has Xcode 27.2 (iOS 27.2 SDK) with an iOS 26.0
  deployment target and the iOS 26.5 Simulator. Whether that meets "Xcode 26" is product meaning for the gate, not for
  this PR. The PO should rule before MS-3.
- **Q3 (Documenter).** CLAUDE.md §7 still has the Xcode command commented out; it is protected, so the Documenter
  proposes the change for a human merge.

## Checklist
- [x] Correctness vs ACs (the ○ parts of AC-M2-09, 13, 28 that this item owns; ● owners are WI-M2-01, M8, M7)
- [x] Tests meaningful (scan roots now `required`, so a 0-file root fails; the hosted test checks the host bundle ID)
- [x] Swift 6 concurrency safe (Swift 6 mode, `complete`, warnings as errors; no unsafe escapes)
- [x] No force unwraps / `try!` in product code paths (none in the new code)
- [ ] Privacy (P-1…P-4): laws pass; evidence hygiene fails (M1)
- [x] UX-2/UX-3 enforced in engine (no engine change; M1 suites green on Linux and Mac)
- [x] Accessibility (UI): n.a., no product UI (`Color.clear` skeletons; `TendEval` placeholder text)
- [x] Performance: n.a. for a scaffold
- [x] No new dependency without ADR (XcodeGen in ADR-0003; no SPM dependency)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface; the M1 `NowSelector` suites stay green (Linux, B1). |
| UX-3 Zero-Guilt | pass | Only strings: `"TendAI"`, `"TendEval"`, `Tend`. No banned token (AC-M2-12 vocabulary scan passes over the new `TendAI` root). |
| UX-4 Design craft | n.a. | No product UI in M2. The iPad orientation question (m1) goes to the Designer for M3. |
| P-1 On-device inference | pass | No inference code yet. T-27 keeps speech on `SpeechAnalyzer` with no `SFSpeech*` exception (AC-M2-09 Rule 5). |
| P-2 No data leaves device (except user iCloud) | pass | No SPM/SDK dependency, no networking code; AC-M2-09 scan 0 violations over 57 files. XcodeGen is a dev tool pinned by checksum (ADR-0003). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud code; no key used. |
| P-4 Media not persisted without consent | pass | The probe audio was synthetic `say` output and is not committed. `TendEval` file sharing is Debug only. Privacy Manifest ships with the app in M3 (brief P-4 row). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Developer (via Orchestrator) | Reviewer | accepted | PR #38, head `02c1d84`, evidence for `0065664`. |
| 2026-11-25 | Reviewer | Developer | returned | CHANGES REQUIRED: M1 (personal path in committed evidence). With it, docs-only: m1(b) README warning sentence, m3 zip hash, n1. Tickets: m1(a) orientations (MS-2), m2 Release guard (WI-M2-M7), m4 T-27 in SP-1 (Planner/Tester). Questions Q1 (PO/owner, D-032), Q2 (PO, Xcode 27.2), Q3 (Documenter). Re-review: I check `grep -rn <handle> docs/` is empty, the 22 hashes, and that the fix commit touches only `docs/`. |

## Round 2 (head `b1f57d3`, fix commit on top of `02c1d84`)

- **Verdict:** **APPROVE**. No open Blocker or Major. M1 is closed; the docs-only parts of m1(b), m3 and n1 are closed;
  m1(a), m2, m4 and n2 are tracked as tickets. Requirements unchanged from round 1: ○ AC-M2-09, ○ AC-M2-13,
  ○ AC-M2-28, T-27; P-1, P-2, P-4. An APPROVE still accepts no AC (they are taken at the M2 merge commit).
- **Merge route:** unchanged, D-032 (owner merges a Mac-only PR). Q1 below still decides whether the docs-only delta on
  top of `0065664` stays covered by the MS-1 record.

### What I checked (Linux container, worktree detached at `b1f57d3`)
1. **Scope.** `git diff --name-only 02c1d84 b1f57d3` lists 13 files, all under `docs/`: ADR-0003, `dev-notes.md`, the
   MS-1 README, 8 logs, `run-evidence.sh`, and this review file (round 1, first committed here). No product code, no
   test, no `project.yml`, no protected path. The Mac record therefore still covers `0065664` on the same reading as
   round 1 (Q1).
2. **M1, handle gone.** I took the handle from `git show 02c1d84:…/run-evidence.sh` line 3 and ran
   `git grep -i -c <handle> b1f57d3 -- .` over the whole tree: no match (exit 1). `git grep` for `/Users/`,
   `/var/folders`, `-projects` and `$HOME/<lowercase>` finds only this review file's placeholder text `<handle>`.
   No hostname, `.local` name or user name appears; the only machine string is the model ID `Macmini9,1`
   (README:9, `mac-B0-header.log:20`), which is not personal.
3. **M1, logs are a pure substitution.** For each of the 8 changed logs I took the `02c1d84` version, replaced the
   bytes `$HOME/<handle>-projects/Tend` with `$REPO` (binary-safe, so the `\r\n` and U+2028 test parameters in B2
   stay intact), and compared with `b1f57d3` using `cmp`: **all 8 byte-identical**. Counts agree with the README:
   2,247 occurrences in the logs plus 1 in `run-evidence.sh` = 2,248; `$REPO` lines 1,497 + 1 = 1,498.
4. **`run-evidence.sh`.** The hard-coded `cd` is now `: "${REPO:?…}"` then `cd "$REPO" || exit 1`, with a usage
   comment. The rest of the script is unchanged. The README says the run itself used the literal path (true; the
   logs were substituted afterwards).
5. **SHA-256.** `sha256sum -c` on the 22 lines in README:86-107: **22/22 OK**. The folder holds exactly those 22
   files plus the README; none is unlisted.
6. **m1(b).** The README "Warnings" paragraph now names the orientation warning and its three lines. I checked them:
   `mac-B6-release.log:356` (`Tend`), `mac-B6-archive.log:246` (`Tend`), `mac-B6-eval-debug.log:1114` (`TendEval`).
   Across all logs the only `warning:` lines are those 3 and 6 `appintentsmetadataprocessor` notices, as written.
7. **m3 and the ADR-0003 size change.** README:13 and :48 now give the full zip digest
   `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`, equal to ADR-0003:51 and the ADR's install
   command (:60). I downloaded the exact URL in ADR-0003:50
   (`https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip`) into an empty scratch directory:
   **4,278,764 bytes, SHA-256 `4d9e34b6…f0196806`**. So the old size (5,738,697) was wrong and the new size is right.
   `xcodegen/bin/xcodegen` inside the zip hashes to `8774da746668bc18fe74e54cbaf10f2631a1fb05947cd374179aa912f14f99db`,
   equal to ADR-0003:52 and B0. (The GitHub API for the asset's published digest was not reachable from this session,
   so I did not re-check the ADR's "matches the digest GitHub publishes" clause; the download itself agrees.)
   The pin (version, URL, digests) is unchanged in substance; only the size note was corrected. CLAUDE.md §6 is met.
8. **n1 and tickets.** `dev-notes.md` WI-M2-M1 header now says "PR: #38". A "Tickets (from review round 1)" table
   carries m1(a) → MS-2 (orientation keys; iPad set is the Designer's, CLAUDE.md §9 Q1), m2 → WI-M2-M7 (Release
   guard asserted by the AC-M2-28 scan test), m4 → MS-2 SP-1 on the iPhone 15 Pro (Planner / Tester), n2 → next Mac
   run. Each matches the round 1 required change. Two Handoff-log rows were added.
9. **Nothing else.** No other line in the five non-log files changed in substance.

### Round 2 findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | Major | evidence logs, `run-evidence.sh:3-5` | Fixed as asked (checks 2-5). | — | **Closed** (verified in `b1f57d3`) |
| m1 | Minor | `evidence/mac/MS-1/README.md` "Warnings"; `project.yml` | (b) fixed (check 6). (a) ticketed for MS-2 in dev-notes. | (a) as round 1, in MS-2. | (b) **Closed**; (a) Open (ticket, MS-2) |
| m2 | Minor | `project.yml` `TendEval` | Ticketed for WI-M2-M7 in dev-notes. | As round 1. | Open (ticket, WI-M2-M7) |
| m3 | Minor | README:13, :48; ADR-0003:50-51 | Fixed; digest and new size verified by download (check 7). | — | **Closed** |
| m4 | Minor | T-27 | Ticketed for MS-2 SP-1 in dev-notes. | As round 1. | Open (ticket, Planner / Tester) |
| n1 | Nit | `dev-notes.md` WI-M2-M1 header | Fixed ("PR: #38"). | — | **Closed** |
| n2 | Nit | `plan.md` B6 | Ticketed for the next Mac run. | Optional. | Open (ticket) |
| n3 | Nit | `dev-notes.md` last Handoff-log row | Says "Not pushed", but `b1f57d3` is the PR head under review, so it has been pushed. | Optional: say "pushed as `b1f57d3`" the next time dev-notes is edited. Not a merge condition. | Open |

**Questions carried from round 1:** Q1 (PO / human owner, D-032: docs-only delta on top of `0065664` counts as
covered) is still open and is the owner's call at merge; this review treats it as covered, as in round 1. Q2 (PO,
Xcode 27.2 vs "Xcode 26") and Q3 (Documenter, CLAUDE.md §7) are unchanged and do not block this PR.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Docs-only delta. |
| UX-2 Rule of Three | n.a. | Docs-only delta; no engine change. |
| UX-3 Zero-Guilt | pass | No UI copy changed; no banned token added. |
| UX-4 Design craft | n.a. | No product UI. Orientation question stays with the Designer (m1(a)). |
| P-1 On device first | pass | No code change; T-27 decision (no `SFSpeech*` exception) unchanged. |
| P-2 No data leaves device except allowed routes | pass | No dependency added; XcodeGen pin re-verified (check 7). The personal path is removed from the public record (M1). |
| P-3 Cloud AI per ADR-0005 | n.a. | No cloud code. |
| P-4 Media not persisted without consent | pass | No change; no audio or media committed. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Developer (via Orchestrator) | Reviewer | accepted | Fix commit `b1f57d3` on `02c1d84`, docs only. |
| 2026-11-25 | Reviewer | Orchestrator → owner merge under D-032 (Merge Gatekeeper review), Acceptance Tester | sent | APPROVE. M1, m1(b), m3, n1 closed and verified; m1(a), m2, m4, n2 tickets; n3 optional nit. Q1 for the PO / owner at merge. |
