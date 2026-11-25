# Owner-run Mac evidence record — MS-1 (WI-M2-M1)

This is the record that plan.md ("Owner-run Mac evidence record") and D-032 ask for. A Mac record is never evidence for
a device AC.

| Field | Value |
|---|---|
| Who ran it | The Developer agent (Claude), driving the owner's Mac over Remote Control, 2026-11-25 |
| Mac | M1 Mac mini (`Macmini9,1`, Apple M1, 16 GB) |
| macOS | 27.2.1 (26B131) |
| Xcode | 27.2 (27B52), iOS 27.2 SDK, macOS 27.2 SDK; Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| Simulator runtime | iOS 26.5 (23F77), device "iPhone 17 Pro" |
| XcodeGen | 2.46.0. Release zip SHA-256 `4d9e34b6…dff892`; binary SHA-256 `8774da74…f99db` (ADR-0003) |
| tz database | 2026f |
| **Commit tested** | **`0065664278099efc737c4c7065f2dafec57ed524`** on `m2/xcodegen-project` |

**Commit and tree:**
- The record itself is committed in the next commit. That commit adds only this folder and updates the numbers in
  `dev-notes.md` and `plan.md` (docs only). `git diff 0065664 HEAD --stat` shows that no file outside `docs/`
  changed.
- `git status --porcelain` (B0 and after the run) shows one untracked entry, this folder
  (`docs/milestones/M2/evidence/mac/`). The probe files had already been copied into it. No tracked file was
  modified, and nothing in it is built.

## How it was run
[`run-evidence.sh`](run-evidence.sh) runs the plan's commands B0–B6 in order, with the same flags. Before it starts,
it deletes `build/`, `Tend.xcodeproj`, every `Packages/*/.build` and the project's DerivedData. Each command's
output goes to its own file in [`logs/`](logs/). [`logs/timings.txt`](logs/timings.txt) has each command's exit
code and wall time. B7 (install on an iPhone) belongs to MS-3 and was not run.

Home and temporary paths in the logs were replaced with `$HOME`, `$USER`, `$TMPDIR` and `$SCRATCH` before
hashing, because the repository is public. Nothing else was edited.

## Results
| Step | Command (plan.md) | Exit | Result |
|---|---|---|---|
| B0 | header | — | [`mac-B0-header.log`](logs/mac-B0-header.log) |
| B1 | `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | 0 | 141 tests in 18 suites passed, 0 warnings |
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | **1** | 570 tests in 67 suites, **2 failures**: the America/Havana tzdata cases of AC-M2-03 (Q6(e)). The cause is tzdata 2026f (dev-notes "WI-M2-M1"). AC-M2-09 scan: TendIngestion 55 files, TendAI 1, TendEval 1; 57 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 1 test passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 2 tests passed, `TEST SUCCEEDED` |
| B6 | `xcodebuild build … -scheme Tend -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/dd-release CODE_SIGNING_ALLOWED=NO` | 0 | `BUILD SUCCEEDED`; `find build/dd-release/Build/Products -iname '*TendEval*'` printed nothing |
| B6 | `xcodebuild archive … -scheme Tend -destination 'generic/platform=iOS' -archivePath build/Tend.xcarchive CODE_SIGNING_ALLOWED=NO` | 0 | `ARCHIVE SUCCEEDED`; `find build/Tend.xcarchive -iname '*TendEval*'` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | `xcodebuild build … -scheme TendEval -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/dd-eval CODE_SIGNING_ALLOWED=NO` | 0 | `BUILD SUCCEEDED`. The bundle holds the 5 eval fixtures, each SHA-256 equal to the repo's. Info.plist: `com.tend.eval`, `UIFileSharingEnabled = true`, `LSSupportsOpeningDocumentsInPlace = true` |
| B6 (new) | `xcodebuild archive … -scheme TendEval …` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

Warnings: no compiler warning appears in any log. The only "warning:" lines are `appintentsmetadataprocessor`'s
"Metadata extraction skipped, no AppIntents.framework dependency found", a tool notice, not a compiler warning.

## Probes (information only; never evidence for an AC)
- [`probes/`](probes/) holds the T-27 and R-1 probe sources: `Probe.swift` and the two entry files, and the XcodeGen
  spec of the throwaway project in the session scratchpad.
- `mac-probe-final.log` is the macOS run of that exact source.
- `ios-sim-probe-run2.log` is the iOS 26.5 Simulator run of that exact source (the `[probe]` lines; the error
  dumps are trimmed to their first line).
- The audio input was a `say`-generated 16 kHz WAV (SHA-256 `5dd4ff4c…cdd03f`). It is not committed.

## File hashes (SHA-256, of the files as committed)
```text
    13a067f0946d5320e691231de857c767a383c35a448fc630867c3708968212c1  logs/mac-B0-header.log
    fe684c28ec5b7f85ba297ebd626208b1d8f59ff08c464c2e27e276a3b89ec942  logs/mac-B1-tendcore.log
    b0b1f41113433b5e1200ef921e9b84271ca9ce3fbb34a4db9315ea04e3503e93  logs/mac-B2-tendingestion.log
    97b4deb576dc6550bc03d5ecca0a2101a115162d7d850d7075e3ed36a2796385  logs/mac-B3-xcodegen.log
    4324a0a95300aeaacb21f45afcac1f91a66f431834c33ae88ad0e3e4df0f5509  logs/mac-B4-tendai-macos.log
    f3312dbc354bfd72bbd0e617cb80f4be2bf605a321bb22b6f9906880f53127f7  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    4276bc4194411fa681976385eb27a19dc8deb308e936ea13ce54891252c8d0d7  logs/mac-B6-archive.log
    189d26808f22922b0078fe82db24a80ffa07e2e82dd416f7d32afa61f89f8df1  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    c1b0a8a801c6433d019071231ff948aecdb15b54ca91e8cf9a10ee3e18b33700  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    40a17c34bbebec60d5a1a5ab8251d9aba74d74a12f848ca27364f7674f8a0384  logs/mac-B6-release.log
    726afc407c638fcc582ff1abfb0973f3baff25aceea213d8ee7a6835c9251115  logs/mac-B9-after.log
    8b004f58485682d279fbbc0d486dba73c8bac16e1885a79b2415abd43632d8d1  logs/timings.txt
    766c8c7c54bb87c191f0d7ac1becf824633c759c8544b71a11ad0b044878fb53  probes/IOSProbe-ProbeApp.swift
    b64b60f74999951f96565727b4fac70a088b39e84dff5a254d710d6c5d9b4742  probes/MacProbe-main.swift
    a5f541fe09e9b091d8575dd497a771e76196b29be64e2696a1e826d73e0e57ba  probes/Probe.swift
    5354fc5d6f03ca96256e45e27c45ce99076e71f37b471c1118e9d846604dd585  probes/ios-sim-probe-run2.log
    e4b090f21480895327d0bcf00fd262106220553f9b080c925b42f2b9f38af3af  probes/mac-probe-final.log
    8770a95cda4e9465080590003328e7332dc10f9e2d72dab0ea2e003a968421ed  probes/probe-project.yml
    cef6bb1a62ce5784e3ef93a574bd2ceb1fa38ced5ccf17f7cc26459dc2481111  run-evidence.sh
```
