# Owner-run Mac evidence record — WI-M2-M6-round1 (MS-2, cloud adapters, PR #50 review round 1)

This is the record that plan.md ("Owner-run Mac evidence record") and D-032 ask for. A Mac record is never evidence for
a device AC.

| Field | Value |
|---|---|
| Who ran it | The Developer agent (Claude), driving the owner's Mac over Remote Control, 2026-11-27 (UTC; the log timestamps are in the Mac's local time) |
| Mac | M1 Mac mini (`Macmini9,1`, Apple M1, 16 GB) |
| macOS | 27.2.1 (26B131) |
| Xcode | 27.2 (27B52), iOS 27.2 SDK, macOS 27.2 SDK; Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| Simulator runtime | iOS 26.5 (23F77), device "iPhone 17 Pro" |
| XcodeGen | 2.46.0, binary SHA-256 `8774da74…f99db` (ADR-0003) |
| tz database | 2026f |
| **Commit tested** | **`990fffc34da40fd884f1bd98e390b2667cb79af5`** on `m2/cloud-adapters` |

**Commit and tree:** the record is committed in the next commit, which adds only this folder and the `dev-notes.md`
section (docs only; `git diff 990fffc HEAD --stat` shows no file outside `docs/`). `git status --porcelain` was empty
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
| B2 | `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | 0 | 582 tests in 69 suites passed. AC-M2-09 scan: TendIngestion 56 files, TendAI 20, TendEval 1; 77 in total, 0 violations; Rule 5 T-27 exception OFF |
| B3 | `xcodegen generate --spec project.yml` | 0 | project generated |
| B4 | `(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)` | 0 | 109 tests in 18 suites passed, `TEST SUCCEEDED` |
| B5 | `xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath build/results/B5-hosted.xcresult SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | 0 | 36 tests in 5 suites passed, `TEST SUCCEEDED` |
| B6 | Release build of `Tend`, then `find … -iname '*TendEval*'` | 0 | `BUILD SUCCEEDED`; `find` printed nothing |
| B6 | Archive of `Tend`, then `find … -iname '*TendEval*'` | 0 | `ARCHIVE SUCCEEDED`; `find` printed nothing; `Products/Applications` holds only `Tend.app` |
| B6 | Debug build of `TendEval` | 0 | `BUILD SUCCEEDED`; the 5 fixtures in the bundle match the repo ([`mac-B6-eval-bundle.log`](logs/mac-B6-eval-bundle.log)) |
| B6 | Archive of `TendEval` | 66 (expected) | "Scheme TendEval is not currently configured for the archive action." |

0 tests skipped in every suite. No compiler warning in any log. Two non-compiler `warning:` lines appear, as in MS-1:
`appintentsmetadataprocessor`'s "Metadata extraction skipped" notice, and the build-validation "All interface
orientations must be supported …" for `Tend` and `TendEval` (B6 only; ticket m1(a), waiting on the Designer's iPad
orientation set).

## File hashes (SHA-256, of the files as committed)
```text
    e34909aa18f926b3f1beac6f51920807e7a74f3ad88e6a6e2c00cabd5d7b5916  logs/mac-B0-header.log
    352944da8bd421bbfded80bcfe2895996f06ba236667cbdf86ae6f4576b8fd1e  logs/mac-B1-tendcore.log
    cf80efe960a57184e817c7901a5644e7936e967f5c0af34da47dbe322f2f60e1  logs/mac-B2-tendingestion.log
    67ba535348bf43d70dbb47b82f3c373e169bc5f063b0864118ff6c8d47d9a0f9  logs/mac-B3-xcodegen.log
    6de32c74b521da7253d4d919c50fb5dab9cf10fc1b8d8db9653e7870b3d1579c  logs/mac-B4-tendai-macos.log
    cb639dc4278a80947d3d02ec6cd3df282c92a50bf335be63871ef699aef5a348  logs/mac-B5-hosted.log
    2320f2e0356bce30e4dff0e6cef7aefbb2b60324eb9bd6772a1e4bd92a7e0f49  logs/mac-B6-archive-find.log
    20a800c8698e66a650e0271db6163787e942bbea7baa2ca9cbdf984347af75f6  logs/mac-B6-archive.log
    9574fa7d62ef73ab4f6cb60047fb637b103601ca9de3ad58566d505539ba42a2  logs/mac-B6-eval-archive.log
    2a5c0830412a704d12842587e56031fa914d4934242e29607eb2a7824d10cbde  logs/mac-B6-eval-bundle.log
    87164385216c6a6200921b2e124a5b47bbf0de5253d3fbde34358d2a18517d47  logs/mac-B6-eval-debug.log
    65ca1525bd711f65d07aab1eae27bea50064478b1094df16b05a47f2f4ab2f1a  logs/mac-B6-release-find.log
    1a5d13cd34c6ba05aed106239dd70db352be3ef853e4fb4052898c519d9dfc31  logs/mac-B6-release.log
    80e7817e404a7089e796d4e1dc1d4143dc05024999e1195079403b29b3cc29b5  logs/mac-B9-after.log
    c3e76a67cfe56f3ae2e6c76a43f905ef5d10e6aab92a5263cdc7b114043ce7df  logs/timings.txt
    9ccbc3e5a3e09837d465ee46d567bc49b7b1f571b4f5442eda779723d52cd0ef  run-evidence.sh
```

## Review round 1 extras (not part of B0–B6)
- **R50-F1 mutants** ([`mutants-r50-f1.txt`](mutants-r50-f1.txt)), one at a time on the working copy, each restored
  after: m10 (deadline start 30 s later, in `CloudAdapters.receive()`), m11 (start read at the model call, the round-1
  code), m12 (start read when the model is built) are killed by `CloudAdapterTests.deadlineFromReceipt` (TendAI
  `swift test`); m13 (the router takes the receipt after the cloud-status read) is killed by both `CloudReceiptTests`
  (TendIngestion, Linux-runnable).
- **R50-F2 probe** ([`probe/`](probe/)): `probe.sh` runs `Tools/Recording/record-provider-stream.sh` in zsh 5.9 and
  bash with a fake key (`FAKE-TEST-KEY-not-a-real-key-0000`) against a local test server (`server.py`, 127.0.0.1)
  through `TEND_REC_BASE`, and against an invalid endpoint (127.0.0.1:1). No real key and no network call. Checks per
  shell and provider: exit 0, status 200 printed, one request, the auth header exact, every other golden header sent,
  the golden body byte for byte, path and query, curl running when `ps` was sampled and the key in no process's
  arguments, the key not on screen, only `<provider>.sse` saved, the key in no saved file; then an empty key, no input,
  the invalid endpoint (curl exit 7, nothing on screen), an unknown provider (64), and a response that echoes the key
  (the stream is deleted). Result: [`probe.log`](probe/probe.log), 90 passed, 0 not passed.
- `tty-probe.sh` does the same on a real pseudo-terminal (`script(1)`) from an interactive `zsh -f -i` and
  `bash --norc -i` with history on: the prompt shows, the typed key is not echoed, the request carries it, echo is
  restored, and the key is not in the history file. Result: [`tty-probe.log`](probe/tty-probe.log), 14 passed.
- Control ([`control-old-command.log`](probe/control-old-command.log)): the round-1 line
  `read -rs TEND_KEY   # …` in the same interactive zsh prints "unknown sort specifier", and the key typed next is
  echoed and saved to history, as the review found. So the probe would have caught it.

```text
    4f926c92ca6c2f48effd0724e14432f6d7b07c6b6ef5574bd2cec93d6be95325  mutants-r50-f1.txt
    d1784dcd7030848fe366d11ddcab52954b914f90069d5dfb94b0cf751a242951  probe/control-old-command.log
    32d177443569f5be23a605552cda4c977affc9b9021f70cff2e90cfb2b747c12  probe/probe.log
    d19ff8d26a247a3c153cb08702cf38ebf8783660699cb1198d8977209234a026  probe/probe.sh
    4bd2eb8d7e90a207af35db0535f8f561d9c8eefba986fcb19db24c4e3fefc589  probe/server.py
    0084ac625fb8aa490efa500778aab41930e67e8a60eb1632909a1230c1cf00fb  probe/tty-probe.log
    162abc0644bae348ed69db3f7332c90f4f2762318a71dca5d13f2ad7087aa767  probe/tty-probe.sh
```
