# Owner-run Mac evidence record — SP-1-dry-run (MS-2, SP-1 probe build and dry run)

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
| **Commit tested** | **`e2cdab04cd820432fd9af83e76706bbe418c1049`** on `m2/sp1-probe` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff e2cdab0 HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
before the run (B0) and after it (`mac-B9-after.log`).

## How it was run
[`run-evidence.sh`](run-evidence.sh) is the MS-1 script with one change: B6's four `xcodebuild` commands also pass
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (review PR #38 n2). It deletes `build/`, `Tend.xcodeproj`, every package
`.build` and the project's DerivedData, then runs B0–B6 in order, each command's output to its own file in
[`logs/`](logs/); [`logs/timings.txt`](logs/timings.txt) has each exit code and wall time. Run as
`REPO=/path/to/Tend zsh run-evidence.sh`. B7 belongs to MS-3.

Personal and machine paths were replaced before hashing, with the MS-1 tokens: `$REPO` (the checkout), `$HOME`,
`$USER`, `$TMPDIR`, `$SCRATCH`, and the Simulator's device and app-container IDs (`$SIM_DEVICE`, `$APP_CONTAINER`). Nothing else was edited.

## Results
| Step | Command (plan.md) | Exit | Result |
|---|---|---|---|
| B0 | header | — | [`mac-B0-header.log`](logs/mac-B0-header.log) |
| B1 | `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | 0 | 141 tests in 18 suites passed |
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 572 tests in 67 suites passed. AC-M2-09 scan: TendIngestion 55 files, TendAI 11, TendEval 1; 67 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 86 tests in 14 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 5 tests in 3 suites passed, `TEST SUCCEEDED` |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in B1, B2 and B4. In B5 exactly one test is skipped, by design: `SP1TimingProbe` runs only with `TEND_SP1=1` (SP-1 D2.4, D3.1). No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## Probes (information only; never evidence for an AC)
[`dry-run/`](dry-run/): D5.2 the probe in the iOS 26.5 Simulator at the same tree (`TEST_RUNNER_TEND_SP1=1 … -only-testing:TendAIHostedTests/SP1TimingProbe`; full log and the `grep -o 'SP1|.*'` extract: 28 lines, header, cold, 24 warm, summary, footer; every capture ends `noModel` because the Simulator has no usable model, which is expected and is never an SP-1 result); D5.3 `xcrun simctl launch --console` of the host with `SIMCTL_CHILD_TEND_SP1_SELFCHECK=1`: the speech-status line reached the Terminal. The dry runs were made from the working tree just before commit e2cdab0, whose tree they match except that the probe's watchdog and device-code fixes were already in.

## File hashes (SHA-256, of the files as committed)
```text
    2a41b8aa75199dfb8b3c5098630c0df5514880233f6f9b1f3f1055dcb171df40  dry-run/sp1-sim-console-lines.txt
    9c15b2f84e314a645fa29f24d1fedce1b76e0eea3168433dbc1870af9cd0d609  dry-run/sp1-sim-probe-full.log
    a0c22f290bb7eec774dee86ec00f5d77bd3fb5edb007ecb48999569aefea665b  dry-run/sp1-sim-probe-lines.txt
    3d7ec6946e7c4eb63a5e0c92291b8a65883b1f7930ecef094170455fd33d1220  logs/mac-B0-header.log
    bb78a465c0ff2137412437d44509c34c041b77c9a092d2feeb5a6c6eac7096ea  logs/mac-B1-tendcore.log
    8c8d7d4cc6b0b24365b0e09d64678b93dfb23daba8e34d3e2b7549eaf60dbdd1  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    7a3ce60551e1c6dff40cda22b6ec0a1e310f23063086cc9781bc29697feb5920  logs/mac-B4-tendai-macos.log
    30dca942af856d1df0c4beea27ba633697d4658bbe3df271dbd4609fb57ec045  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    7827cb1902c77b62035acb71669ffd025bfd159b8f816cd3d24217f3eb17ddef  logs/mac-B6-archive.log
    c44cf4c375bb88e0e765e0327075ed3f0cf3893e313bc45c120ccf6ea6c2215f  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    21d9e78c770aac8d26ca388493039f2890ec0e756d7458950653c6d43a4c6eb5  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    d8116d747785692da280a85524c173ad6c034e2eafbe9abfea22f4683db0b53d  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    8bcdb7ada464a72e072726ea2304c395127957ba21ccdec25e67bbc631adc37d  logs/timings.txt
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
