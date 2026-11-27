# Owner-run Mac evidence record — SP-1-r3 (MS-2, SP-1 probe round 3 (quick stop timing))

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
| **Commit tested** | **`ea3d195b1734df73117447756f95c3562671be63`** on `m2/sp1-probe` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff ea3d195 HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
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
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 572 tests in 67 suites passed. AC-M2-09 scan: TendIngestion 55 files, TendAI 11, TendEval 1; 67 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 90 tests in 15 suites passed, `TEST SUCCEEDED` |
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
**SP1-COMMIT = `ea3d195b1734df73117447756f95c3562671be63`.** B0–B6 above and every D5 step below ran at this exact commit with a clean tree before (`logs/mac-B0-header.log`, `d5/d5-header.log`) and after (`logs/mac-B9-after.log`, `d5/d5-after.log`). [`d5/`](d5/): B5 with `TEND_BUNDLE_PREFIX=org.example.owner` (`d5-b5-custom-prefix.log`, 5 tests, probe skipped); the probe in the iOS 26.5 Simulator (`d5-probe-full.log`, `d5-probe-lines.txt`: 28 `SP1|` lines, all `noModel`, expected, never an SP-1 result); the host's console line through `xcrun simctl launch --console` with `SIMCTL_CHILD_TEND_SP1_SELFCHECK=1` (`d5-console*.txt`). The Simulator panel still cannot be tapped (its access prompt is unanswered), so [Quick stop test] was not run in the Simulator.

## File hashes (SHA-256, of the files as committed)
```text
    4917922f73fef9774294351678baed3e951d18a6a5810131081d9b91a10434c5  d5/d5-after.log
    d8ab9a45d03ea9aba56e945115904d75be058cc79c73c90de201fd4457fee7f5  d5/d5-b5-custom-prefix.log
    2a41b8aa75199dfb8b3c5098630c0df5514880233f6f9b1f3f1055dcb171df40  d5/d5-console-lines.txt
    f0210eab31e874e107a1e975dadbeee9b8732c1f74f85d7d58a41e7800bc2142  d5/d5-console.log
    68d2e3a51f8cfef7ee6c5a556a6fcd56d8108fb754787933607abe1e10dbc0d2  d5/d5-header.log
    76b0817c862f70c8ed92842055c0db31ac022f75557b81d7daf40b7034c0eb51  d5/d5-probe-full.log
    097e176beacaf095ccefa03a9f863662242f96b614e86d5f496de5df50ac4de5  d5/d5-probe-lines.txt
    2fceea258dac44c3cf76a1296a4243c51e433882d7b44cb76b7c25f592ad295c  logs/mac-B0-header.log
    cc9823536145d2df7fb5583fd9261a489ec25077d638f8e32331f6813ee3f759  logs/mac-B1-tendcore.log
    cdb0e80142014072339f470d3a295a58dc98f1410fcfc858ded6831d0c2bcf63  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    186f209c8ae65d9073edcbda3e32e49d5b1b21ff903f8bd0a23de5e01d55e3c5  logs/mac-B4-tendai-macos.log
    24f721d83c5b0077d8f7f8ff7d9ccea005852c855ab1e43f6b446e468fc8b785  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    cc5c64107e34b0333454f775b9761784be90e8b3e9740a2ac5ba5fa78b9c9696  logs/mac-B6-archive.log
    f0ca8905faa7a7ad8be3ad8868280e607df340a71a17f9aa34e445f4b0012d9e  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    8368f480462ef909ed857eb43bc5f8d3092516d0a2b78033aee06a3b82d0dc99  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    04542ba7058a590ec31088f088ae04efc532e8b5f5f41e21bfcb8ff092528386  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    cb913c87c011e24c407908472e1a5bc8062c627d22e4d36b81ea14600493b678  logs/timings.txt
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
