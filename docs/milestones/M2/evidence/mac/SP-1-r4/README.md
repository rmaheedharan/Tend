# Owner-run Mac evidence record — SP-1-r4 (MS-2, SP-1 probe with the final speech branch)

This is the record that plan.md ("Owner-run Mac evidence record") and D-032 ask for. A Mac record is never evidence for
a device AC.

| Field | Value |
|---|---|
| Who ran it | The Developer agent (Claude), driving the owner's Mac over Remote Control, 2026-11-27 |
| Mac | M1 Mac mini (`Macmini9,1`, Apple M1, 16 GB) |
| macOS | 27.2.1 (26B131) |
| Xcode | 27.2 (27B52), iOS 27.2 SDK, macOS 27.2 SDK; Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| Simulator runtime | iOS 26.5 (23F77), device "iPhone 17 Pro" |
| XcodeGen | 2.46.0, binary SHA-256 `8774da74…f99db` (ADR-0003) |
| tz database | 2026f |
| **Commit tested** | **`c07e12a9647c7612b720a4d598d9f535870ca1b6`** on `m2/sp1-probe` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff c07e12a HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
before the run (B0) and after it (`mac-B9-after.log`).

## How it was run
[`run-evidence.sh`](run-evidence.sh) is the MS-1 script with one change: B6's four `xcodebuild` commands also pass
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (review PR #38 n2). It deletes `build/`, `Tend.xcodeproj`, every package
`.build` and the project's DerivedData, then runs B0–B6 in order, each command's output to its own file in
[`logs/`](logs/); [`logs/timings.txt`](logs/timings.txt) has each exit code and wall time. Run as
`REPO=/path/to/Tend zsh run-evidence.sh`. B7 belongs to MS-3.

Personal and machine paths were replaced before hashing, with the MS-1 tokens: `$REPO` (the checkout), `$HOME`,
`$USER`, `$TMPDIR`, `$SCRATCH`. Nothing else was edited.

## Results
| Step | Command (plan.md) | Exit | Result |
|---|---|---|---|
| B0 | header | — | [`mac-B0-header.log`](logs/mac-B0-header.log) |
| B1 | `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | 0 | 141 tests in 18 suites passed |
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 580 tests in 68 suites passed. AC-M2-09 scan: TendIngestion 56 files, TendAI 15, TendEval 1; 72 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 96 tests in 17 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 37 tests in 6 suites passed, `TEST SUCCEEDED` |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in B1, B2 and B4. In B5 exactly one test is skipped, by design: `SP1TimingProbe` runs only with `TEND_SP1=1` (SP-1 D2.4, D3.1). No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## Probes (information only; never evidence for an AC)
**SP1-COMMIT = `c07e12a9647c7612b720a4d598d9f535870ca1b6`.** It contains the on-device adapter (PR #43) with the one-call Tool rule, the speech adapter at PR #44 round 5 (`8c324a6`: early stop kept, arming independent of an earlier capture, no audio after a cancel) and main up to `9e50012` (PRs #45, #46, #47). B0–B6 above and every D5 step below ran at this exact commit with a clean tree before (`logs/mac-B0-header.log`, `d5/d5-header.log`) and after (`logs/mac-B9-after.log`, `d5/d5-after.log`). [`d5/`](d5/): B5 with `TEND_BUNDLE_PREFIX=org.example.owner` (`d5-b5-custom-prefix.log`); the probe in the iOS 26.5 Simulator (`d5-probe-*`: 28 `SP1|` lines, all `noModel`, expected, never an SP-1 result); the host's console line via `xcrun simctl launch --console` with `SIMCTL_CHILD_TEND_SP1_SELFCHECK=1` (`d5-console*`). The Simulator panel still cannot be tapped, so [Quick stop test] was not run in the Simulator.

## File hashes (SHA-256, of the files as committed)
```text
    4917922f73fef9774294351678baed3e951d18a6a5810131081d9b91a10434c5  d5/d5-after.log
    5e4be3cb052de2ca18474713c63a56658d07c1ef2ddbb37a980fb93ff5cc9ccd  d5/d5-b5-custom-prefix.log
    2a41b8aa75199dfb8b3c5098630c0df5514880233f6f9b1f3f1055dcb171df40  d5/d5-console-lines.txt
    6ea9eec39fd54b2538a7c0387174abf1eaee0ad41a3bf9ddbc402df8f61e9423  d5/d5-console.log
    5e3540e62449426fd095258177a6e63ccbf373c9da73c02243ce367d4f21e611  d5/d5-header.log
    e916bbb6fd39c4eef088109f525c42af304d884be2d167edf4c712fe3895e0f6  d5/d5-probe-full.log
    5b1e50dbb014788758bf0acdaad629417afdd8fbcdbdc632c66adffdc7a54c8b  d5/d5-probe-lines.txt
    5535e34af398973658a2871669500676d3642a33aac45794c45740d2477657a9  logs/mac-B0-header.log
    80f230f71e09f613aaf237cc444d4e9516f1854e0373bec8da2e3d63c59cd913  logs/mac-B1-tendcore.log
    ab513bc772d34e276863110c53abf61356b6dd45f553d64caaccbe518bfc23c0  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    64d62fed745f0485c0699c36e7c5afbef174a7237f69c5ab98f9db8f8450cf17  logs/mac-B4-tendai-macos.log
    e9a00ac4593664c68efae90b8ba0321175013ca84a1c81cb319ffa47f3266c05  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    9d0da2115f4c659da614c65c1047d2305916a1d9acb5971d8da026db6c253af5  logs/mac-B6-archive.log
    af34c6e141002f114233609114823f2ae0e3023a040667131176b0457cd7137c  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    5a53fa0b94118de4d62b7dbf3b435dcb1cb8cd8ae8b1e12f303c6d06822cbe8d  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    9a15846c02300194ee8e92e7d55a32105cf65e14fccb8ba145ecb82bd9c7114e  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    254439e8f35860eedb9d8b68ee9feaed51f6fcb4569aacfbcfc63e24375d2e33  logs/timings.txt
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
