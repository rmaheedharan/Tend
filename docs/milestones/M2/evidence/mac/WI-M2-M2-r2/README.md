# Owner-run Mac evidence record — WI-M2-M2-r2 (MS-2, on-device adapter, round 2)

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
| **Commit tested** | **`fad715a3d1f81cadd17a9403b96dca12c3ba231d`** on `m2/on-device-adapter-v2` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff fad715a HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
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
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 572 tests in 67 suites passed. AC-M2-09 scan: TendIngestion 55 files, TendAI 7, TendEval 1; 63 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 55 tests in 7 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 2 tests in 1 suites passed, `TEST SUCCEEDED` |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in every suite. No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## Probes (information only; never evidence for an AC)
[`probes/`](probes/): the Developer dev-set probe (`devset-main.swift`, 8 captures of my own, never the frozen eval) and its output before (`ff79f9c`) and after (`fad715a`) the one-call rule. Information only (R-1).

## File hashes (SHA-256, of the files as committed)
```text
    a9b8f1932177dfc65997dd629c0d60c162bebb53c9587e2726bb0fe3405ba962  logs/mac-B0-header.log
    be5f9cf981d07f15cd19a861c592ddc9c5fb0490b4b0ff8d105627e3103c37aa  logs/mac-B1-tendcore.log
    b903ba9afb6338928e09b965396c0e4eea0f1c37a9709bbaa90ae93c6d94b4e7  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    eade0c29e7cdf846c62bd3d3a233e790d534f0432a73fe2c772ba9a3373279cc  logs/mac-B4-tendai-macos.log
    2e1117d7b52c7023a318408543e1e532f2eb6ab9cfcc60411230f99c45ff9445  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    1c8bb60314cde63161c9d995a68c239e3cc38879ae7d82e8f99c35468307e0ca  logs/mac-B6-archive.log
    3914bd293e3b6331ff6a02da4d8ee00eb9423a242c30d7432d2c4d922e9fd05b  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    84f7cf2a31e6abec46c9d3a28c8f0dd81c5f0e493a1cd459c694ab6d3978a68e  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    126a9c917eac8f7439873714f956c10535cb4b616654c31979d491fc77e016c8  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    7fd90c1c6a32f4cc333ff3ac35f02b1b72e3ceab8092b520531cb26902bd2c66  logs/timings.txt
    4171b132e6f9eb0d7dbd1a3e07cea4be103879694ed5fe46f42b9d7e63c005cf  probes/devset-Package.swift.txt
    21f22344f1994337d90edbceea49865bd69339f611eef0879e5337e771cd64ce  probes/devset-after-fad715a.log
    ef0f22762d617446465842e45e96f47fc4420a9ee694be1b151e5e339d33ff63  probes/devset-before-ff79f9c.log
    0215740182a7335669daa6e9d33905d1530ad54804bd05556ddb198eb8e10ce9  probes/devset-main.swift
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
