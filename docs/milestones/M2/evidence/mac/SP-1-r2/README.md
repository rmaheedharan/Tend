# Owner-run Mac evidence record — SP-1-r2 (MS-2, SP-1 probe round 2)

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
| **Commit tested** | **`b4a4ec4658c2ad52c8f9c77d23112bf5b560bc85`** on `m2/sp1-probe` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff b4a4ec4 HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
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
**SP1-COMMIT = `b4a4ec4658c2ad52c8f9c77d23112bf5b560bc85`.** B0–B6 above and every D5 step below ran at this exact commit, with a clean tree before (`logs/mac-B0-header.log`, `d5/d5-header.log`) and after (`logs/mac-B9-after.log`, `d5/d5-after.log`). [`d5/`](d5/): D5.1 B5 with the default prefix is B5 above (5 tests, `SP1TimingProbe` skipped); `d5-b5-custom-prefix.log`: B5 with `TEND_BUNDLE_PREFIX=org.example.owner` passes too (5 tests, probe skipped; review M-2). D5.2 `d5-probe-full.log` and `d5-probe-lines.txt`: the probe in the iOS 26.5 Simulator with `TEST_RUNNER_TEND_SP1=1 … -only-testing:TendAIHostedTests/SP1TimingProbe`, 28 `SP1|` lines; every capture ends `noModel` because the Simulator has no usable model, which is expected and never an SP-1 result. D5.3 `d5-console.log` / `d5-console-lines.txt`: `xcrun simctl launch --console` of the host with `SIMCTL_CHILD_TEND_SP1_SELFCHECK=1` printed the speech-status line to the Terminal. The Simulator panel could not be tapped (its access prompt was not answered), so [Quick stop test] was not tapped in the Simulator; the early-stop rules it exercises are unit-tested on the speech branch (`EarlyStopTests`).

## File hashes (SHA-256, of the files as committed)
```text
    4917922f73fef9774294351678baed3e951d18a6a5810131081d9b91a10434c5  d5/d5-after.log
    e3254b4026d1c13e50761b0739985bd19488f709dc7561f6849778c75de3bb1b  d5/d5-b5-custom-prefix.log
    2a41b8aa75199dfb8b3c5098630c0df5514880233f6f9b1f3f1055dcb171df40  d5/d5-console-lines.txt
    3dd3bbd440d8ddc2b32cd2dfbd86e1c6f3243247f5554353f480c84f41b6046b  d5/d5-console.log
    eef4cf7c4005c8164fc8e597e8606ce2b359e131a858041d419b6f45a8ecb858  d5/d5-header.log
    cfc4b7b7a68bedc915d21071f516c433ef69d3d78f91c6e7f6f69748a6a2f6cb  d5/d5-probe-full.log
    ff5e8f274142406985ad6ae36df151a8770a335ad4ef975eae4fdaea2b876ea4  d5/d5-probe-lines.txt
    e0f74a8493e8d8d19419b3a1013895f9619077e5841441259b44d4b14eeaa670  logs/mac-B0-header.log
    0745b0b21931e960a9f1aae6475ed506e3d49191ac611f3588bcae69330df19c  logs/mac-B1-tendcore.log
    b54f365aa8ef3ec63403c18e339739399d98ed184d0de303d5229478adfd9077  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    8807efa95c18edb206e2278b8c0107c9c21d664308e2838b81b43de9a9a7726b  logs/mac-B4-tendai-macos.log
    10a093d3c9166305b521b098c437957e1189ec71366471bcde85ce65a5ef39af  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    d3259c08b1aed0c9ada75f0479e330fd9070ba86185b879a87bc05b6be9c7543  logs/mac-B6-archive.log
    d557f674ecd40253364cf996c4537cae67ab8d9d6d2a45fd06fabdbca9931803  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    ab3286e2d6433f8c9735733b2292458cb13ac633fb7390edd51ccfe3625881d1  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    cf71bc90a402ff5b1620232157877d068f7cda207bf1171342e2da01d83f1da5  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    63b81d14f7d030498d7a557e58c0a472c7215b65e4a7878c492e6940a2858420  logs/timings.txt
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
