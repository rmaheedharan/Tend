# Owner-run Mac evidence record — WI-M2-M7 (MS-2, TendEval harness)

This is the record that plan.md ("Owner-run Mac evidence record") and D-032 ask for. A Mac record is never evidence for
a device AC.

| Field | Value |
|---|---|
| Who ran it | The Developer agent (Claude), driving the owner's Mac over Remote Control, 2026-11-28 (UTC; the log timestamps are in the Mac's local time) |
| Mac | M1 Mac mini (`Macmini9,1`, Apple M1, 16 GB) |
| macOS | 27.2.1 (26B131) |
| Xcode | 27.2 (27B52), iOS 27.2 SDK, macOS 27.2 SDK; Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| Simulator runtime | iOS 26.5 (23F77), device "iPhone 17 Pro" |
| XcodeGen | 2.46.0, binary SHA-256 `8774da74…f99db` (ADR-0003) |
| tz database | 2026f |
| **Commit tested** | **`070ce0598868fece8986126c40e10eb93ef25108`** on `m2/eval-harness` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff 070ce05 HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
before the run (B0) and after it (`mac-B9-after.log`).

## How it was run
[`run-evidence.sh`](run-evidence.sh) is the MS-1 script with B6's `xcodebuild` commands also passing
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (review PR #38 n2), plus, for WI-M2-M7: B5-eval (the TendEval hosted tests),
B6-eval-release (a Release build of TendEval, which must stop at the Debug-only guard), and `TEND_COMMIT=$(git rev-parse
HEAD)` on the TendEval Debug build. It deletes `build/`, `Tend.xcodeproj`, every package
`.build` and the project's DerivedData, then runs B0–B6 in order, each command's output to its own file in
[`logs/`](logs/); [`logs/timings.txt`](logs/timings.txt) has each exit code and wall time. Run as
`REPO=/path/to/Tend zsh run-evidence.sh`. B7 belongs to MS-3.

Personal and machine paths were replaced before hashing, with the MS-1 tokens: `$REPO` (the checkout), `$HOME`,
`$USER`, `$TMPDIR`, `$SCRATCH`, and `$REPO_PARENT` for every folder between `$HOME` and `$REPO` (applied to the two
TendEval B6 build logs after the first commit of this record, where an `SCRIPT_INPUT_ANCESTOR_3` value showed the
folder above the checkout). Nothing else was edited.

## Results
| Step | Command (plan.md) | Exit | Result |
|---|---|---|---|
| B0 | header | — | [`mac-B0-header.log`](logs/mac-B0-header.log) |
| B1 | `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | 0 | 141 tests in 18 suites passed |
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 597 tests in 71 suites passed. AC-M2-09 scan: TendIngestion 56 files, TendAI 20, TendEval 8; 84 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 109 tests in 18 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 36 tests in 5 suites passed, `TEST SUCCEEDED` |
| B5-eval | `xcodebuild test -project Tend.xcodeproj -scheme TendEval -destination 'platform=iOS Simulator,name=iPhone 17 Pro' …` | 0 | 5 tests in 1 suite passed (9 cases), `TEST SUCCEEDED` ([`mac-B5-eval-hosted.log`](logs/mac-B5-eval-hosted.log)) |
| B6 | Release build of `TendEval` | 65 (expected) | stops at the pre-build guard: "TendEval is built only in the Debug configuration (AC-M2-28), not Release." ([`mac-B6-eval-release.log`](logs/mac-B6-eval-release.log)) |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in every suite. No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## WI-M2-M7 specifics
- **Fixtures hash** (SHA-256 of `MANIFEST.sha256`, as the harness shows it): `7fdc056e92e419a4b416ea14493a7cc2ab9188bb559c796bd79ed45d2141de22`.
  The bundle log shows all five bundled files byte-equal to the repo, and the Debug Info.plist carries
  `TendCommit` = the tested commit, `UIFileSharingEnabled`, and the microphone usage text.
- **AC-M2-09 scan** with the Q23 loader exception from `main` (PR #51): 84 files, 0 violations, `EvalFixturesLoader`
  included (B2).
- **AC-M2-28 `project.yml` scan** (`ProjectSpecScanTests`, Linux-runnable, in B2): the committed spec passes; 11 negative
  plants each caught.
- **Harness mutants** ([`mutants-harness.txt`](mutants-harness.txt)), TendEval hosted tests, one at a time, restored
  after: E1–E6 killed (E3 first survived and was killed after `voiceAttempt` was made to check the model's input).

## File hashes (SHA-256, of the files as committed)
```text
    9cd280d3be25b6384c106321045cf3d0a45d34ec9f3a360500a6ac620e82dfae  logs/mac-B0-header.log
    4f1ad4f58cd770c0674bac769b71517fc9d4da29fa521eeccd821a7d18e5f819  logs/mac-B1-tendcore.log
    5b78bb93ede4b5cc503df7537c6b851f671cc53db5bcab17dd8f26ea472915d8  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    40030015703bb28d0c9e9ebaf82fdefb4c317a0152b4f632f1718ec543a00d26  logs/mac-B4-tendai-macos.log
    c844560d2dd66abd80bf1eed3620e72a32ece7104e6582be34244ed8b9b951e2  logs/mac-B5-eval-hosted.log
    6063e5a627f60e0ed5f037d9fafb3071d83b11542c13ff72f9550fbc0302e3c7  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    67454b7558c550c0e0e058d558e11f0dd680fb7bc8a8f40f2b0655cd0f9214b0  logs/mac-B6-archive.log
    b56d93425d47ac7ad786437d62017f70d146bd536f0c7f9a555f8a95c2a9f4e1  logs/mac-B6-eval-archive.log
    39264c4d9830a1aba5e60de27a67b99ebe6b1a6255768a0d63bec0fa3cd816e3  logs/mac-B6-eval-bundle.log
    6ac8039e85c1af26015232f27da6f7fbf2da089d1d3bed0510a41f1dc40e449d  logs/mac-B6-eval-debug.log
    c42c410fc01de1c695ec04315be72c62068a275e52e2b91fc3b5976af4302d11  logs/mac-B6-eval-release.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    979efef98c64df4db399fec3b074ec0d0f995a89f71ac1bd1bddf9151f76eaac  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    49e819d19fde597b649ec65983348d80f1d4bfefd174bf3cf7f8b86bafc3f78b  logs/timings.txt
    099613bbddd70fd9097e0947db965f7b7accd3e5eb99e2e1e3b47d08157e1a8f  mutants-harness.txt
    e63ab403bcca4d645038123d2d9d14831478475d8928afb5e6012a6597f8e0f1  run-evidence.sh
```
