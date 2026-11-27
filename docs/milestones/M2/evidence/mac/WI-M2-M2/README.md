# Owner-run Mac evidence record — WI-M2-M2 (MS-2, on-device adapter)

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
| **Commit tested** | **`94d02fe9b87cbc21b0608cc017c598c74f20eac2`** on `m2/on-device-adapter` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff 94d02fe HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
before the run (B0) and after it (`mac-B9-after.log`).

## How it was run
[`run-evidence.sh`](run-evidence.sh) is the MS-1 script with one change: B6's four `xcodebuild` commands also pass
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (review PR #38 n2). It deletes `build/`, `Tend.xcodeproj`, every package
`.build` and the project's DerivedData, then runs B0–B6 in order, each command's output to its own file in
[`logs/`](logs/); [`logs/timings.txt`](logs/timings.txt) has each exit code and wall time. Run as
`REPO=/path/to/Tend zsh run-evidence.sh`. B7 belongs to MS-3.

Personal and machine paths were replaced before hashing, with the MS-1 tokens: `$REPO` (the checkout), `$HOME`,
`$USER`, `$TMPDIR`, `$SCRATCH` (none occurred). Nothing else was edited.

## Results
| Step | Command (plan.md) | Exit | Result |
|---|---|---|---|
| B0 | header | — | [`mac-B0-header.log`](logs/mac-B0-header.log) |
| B1 | `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | 0 | 141 tests in 18 suites passed |
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 572 tests in 67 suites passed. AC-M2-09 scan: TendIngestion 55 files, TendAI 7, TendEval 1; 63 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 47 tests in 6 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 2 tests passed, `TEST SUCCEEDED` (TendAI, with the new adapter, built for the iOS Simulator) |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in every suite. No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## Probes (information only; never evidence for an AC)
[`probes/`](probes/) holds the two throwaway probes of the real on-device session (R-1) and their output:
`probe-pipeline-main.swift` and `probe-pipeline.log` (the public `TendAI` source through the real `DraftPipeline`,
4 runs), `probe-split-main.swift` and `probe-split.log` (a copy of the adapter's schema, with and without the
`Tool`, 3 runs each). Both ran from the session scratchpad against this commit's sources.

## File hashes (SHA-256, of the files as committed)
```text
    aab87ccba299bb9db89375885f6544ffe98dc18d898bbc75ed6055adcf0afe86  logs/mac-B0-header.log
    9db603ccfec5e46a47412756ca2c85879fa47ec6c96f1452bb989af21020d251  logs/mac-B1-tendcore.log
    09a382d915c434f7342b6760c600eee092b347d6a252bab8155fb6e301aeff21  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    5089938fdfb869117c782804f94c3758814cfa57f0c664238467a9ab9eee3bcf  logs/mac-B4-tendai-macos.log
    d2a3843dd146c57b312ab6aefcd8fb1580c253cd54f5cbba1ce7a2915b60baf4  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    79166fee3c27eea2504c728c91cfe405066c54ed2f18b48294bd3d9a6483f475  logs/mac-B6-archive.log
    46840caa6c98a36bc367e615b1394a3ef25ddaf27f144f95ee889151dbed793d  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    da06d8673c2699221790b0bfbb0b1b2433a2e3b445be9ed5882538ed51b2f60f  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    d82a4d403177fa58ebeba4e014cee824e9dde94beac7142f0533623e75cb11d2  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    8043b2381d85ef9a434da274aa78b20ef2d679dd584aa10e2f12596195fffa88  logs/timings.txt
    911580a3571f499e829a74ca469dff19e2753aaac1f6c4624a127de16d22aa72  probes/probe-Package.swift.txt
    9fc38d162a96bdf935f620a366c9b68f63b5e56bd287a160bd5cbd943a2c893d  probes/probe-pipeline-main.swift
    2eea209ccbcfde99531f41ef27eb9fa71af3fdf84e00ef8c4e80720dc5915286  probes/probe-pipeline.log
    20a3664be640e751c92bebda0a0ff77ce419f483c3e7f359350292be3354d939  probes/probe-split-main.swift
    f0ac870998fb1976c7107f49f25aa5fd607acfbed1ba2596734da79d3f9eaaa5  probes/probe-split.log
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```
