# M2 Code Review — PR #15 (WI-M2-01, `m2/ingestion-foundation`; round 1 @ `6143908`, round 2 @ `7bc22b9`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** APPROVE (round 2, head `7bc22b9`; round 1 was CHANGES REQUIRED)  ·  **Round:** 2
- **Scope:** WI-M2-01: `TendIngestion` and `TendSourceScan` packages, ADR-0006, text primitives, canonical JSON, and
  the AC-M2-09 scanner. This item owns AC-M2-09 and lays groundwork for AC-M2-04, 07, 08, 12, 14, 20 and 28.
- **Inputs read:** `CLAUDE.md`; `docs/milestones/M2/brief.md` (v4; AC-M2-09 Rules 1–6, Definitions) and `plan.md`
  (WI-M2-01 row, "Module and file layout", "Named files") on `origin/main`; `docs/milestones/M1/brief.md` AC-M1-23
  and Q17/Q19/Q20/Q23; the PR diff (16 files); `dev-notes.md` (WI-M2-01, D1–D9, Q-D1, Q-D2); ADR-0006.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, so M2 build work is allowed (CLAUDE.md §5). M2 is still shown
  as `PLANNING`. The `IN-BUILD` change (O-1) and the CI job (HM-1) are owner merges. The plan (R-11) already says
  this PR cannot merge before them.

## Summary
Most of the work is strong. The lexer move is faithful: apart from the API changes the dev-notes list, the diff
against the M1 copy shows the same matching rules. Canonical JSON is correct. Folding, keywords, stop words and
banned tokens match the brief's Definitions. There is no concurrency hazard, and no product code touches the network,
the disk or a log. Rules 3, 4 and 5 are implemented carefully, and I tried hard to get past them and could not.

Two Major findings block the merge:

1. **R1-F1 (D1).** D1 takes `contentsOf:` (URL loading, an AC-M1-23 networking-family pattern) out of Rules 2, 3
   and 6. So `Data(contentsOf: url)` passes in every `TendAI` file, including the three cloud-adapter files, and in
   every `TendEval` file. That makes a rule weaker than the brief's AC-M2-09. It also adds a `contentsOf:` exception
   without the PO decision that AC-M1-23 / Q23 require. In the allowlisted files it opens a network read that skips
   the AC-M2-22 transport controls (ephemeral session, host check, redirect refusal).
2. **R1-F2.** The tests do not pin the closed lists to the brief. The planted hits and the "coverage" test are
   generated from the engine's own lists. When I deleted one list entry or widened one import or host set at a time,
   17 of 37 changes left the suite green.

My judgement on **Q-D1** (`AVURLAsset`): no scanner change is needed in this PR, but the false code comment must be
fixed (R1-F3, R1-F4). **Q-D2** can wait for WI-M2-10 (R1-F6).

### What I ran (Linux container, Swift 6.2 via `swift:6.2-noble`, fresh worktree at `6143908`)
| Command | Result |
|---|---|
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 33 tests in 2 suites passed after 0.314 seconds.` 0 warnings. |
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete! (6.01s)`, 0 warnings. |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 17 tests in 3 suites passed after 0.094 seconds.` Scan log: `TendIngestion (required) Packages/TendIngestion/Sources: 4 files scanned`, `TendAI (optional) … not present`, `TendEval (optional) … not present`, `4 files in total, 0 violations`. |
| TendCore regression | Not run. It is optional, and `Packages/TendCore` is unchanged in the diff. GitHub check "TendCore swift test (Linux)" on `6143908` is `success`. |
| GitHub checks on `6143908` | Only TendCore runs in CI. The two new packages are not run in CI until HM-1 merges. This is known (plan R-11) and is not a code finding, but the Gatekeeper must not merge without it (G3). |

### My planted violations (a temp copy of `TendSourceScan` plus one extra test file; nothing committed)
Configuration: the plan's file names, with the T-27 exception **on**, so the strictest exception path is the one
tested.

| # | Plant | Module / file | Result |
|---|---|---|---|
| P01 | `let d = try Data(contentsOf: c.url!)` | TendAI `Cloud/CloudHTTPTransport.swift` (allowlisted) | **NOT CAUGHT** (R1-F1) |
| P02 | `let d = try Data(contentsOf: u)` | TendAI `Cloud/OpenAIIngestionModel.swift` | **NOT CAUGHT** (R1-F1) |
| P03 | `let d = try Data(contentsOf: u)` | TendEval `Run/X.swift` | **NOT CAUGHT** (R1-F1) |
| P04 | `let d = try Data(contentsOf: u)` | TendIngestion | caught (Rule 1, AC-M1-23 `contentsOf:`) |
| P05 | `AVURLAsset(url: u)`, no import | TendAI | not caught (R1-F3, R1-F4) |
| P06 | `import AVFoundation` | TendAI | caught (Rule 2 import) |
| P07 | `import Glibc` | TendIngestion | caught (Rule 1 import) |
| P08 | `s.write(toFile: p, atomically: true, encoding: .utf8)` | TendEval | not caught (brief list gap, R1-F5) |
| P09 | `"https://api.openai.com"` | TendAI, not allowlisted | caught (Rule 4) |
| P10 | `Swift.print(x)` | TendIngestion | caught (Rule 1 log) |
| P11 | `URLCache.shared` | allowlisted | caught (Rule 3 prefix) |
| P12 | `SFSpeechRecognizer.requestAuthorization { _ in }`, exception on | `SpeechPermission.swift` | caught (Rules 2 and 5) |
| P13 | `"HTTPS://API.OPENAI.COM"` | allowlisted | caught (Rule 4) |
| P14 | `import Darwin` + `fwrite(…)` | TendEval | not caught (brief gap: Rule 6 has no import list, R1-F5) |
| P15 | `d.write(toFile: p, atomically: true)` | TendAI | not caught (brief list gap, R1-F5) |
| P16 | `"api.openai.com"` | TendEval | caught (Rule 4, D3) |
| P17 | `s.uploadTask(with: r, from: d)` | allowlisted | not caught (the type is inferred; R1-F5) |
| P18 | `"https://\(host)/v1"` | allowlisted | caught (Rule 4, D7) |
| P19 | `os.Logger(subsystem:category:)` | TendEval | caught (Rule 6 log) |
| P20 | `#"Data(contentsOf: u)"#` (string text) | TendIngestion | not caught, which is correct (string text is not code) |
| P21 | `(s as NSString).write(to: u, …)` | TendIngestion | caught (Rule 1 write) |
| P22 | `CMSampleBufferRef` | TendIngestion | caught (Rule 1 media, D2 substring) |
| P23 | `import FoundationNetworking` | allowlisted | caught (Rule 3) |
| P24 | `URLSessionStreamTask?` | allowlisted | caught (Rule 3) |
| P25 | `"http://api.openai.com"` | allowlisted | caught (Rule 4) |

### My mutation run (one change at a time to `IngestionSourceRules.swift`, full `TendSourceScan` suite each time)
- **Killed (20):** AVAudioPCMBuffer, CGImage, AVAsset, FileManager, FileHandle, UserDefaults, Logger, OSLog,
  URLProtocol, NWConnection, SFSpeech, `createFile(`, `write(to:`, `print(`, `NSLog(`, `os_log(`, dropping the
  `NW` or `CFStream` prefix, and dropping `Network` from the networking imports.
- **Survived and not equivalent (17):**
  - media entries: AVAudioBuffer, AVAudioFile, CVPixelBuffer, CVImageBuffer, CIImage, UIImage, CMSampleBuffer,
    NSImage;
  - write entries: OutputStream, NSUbiquitousKeyValueStore;
  - log entries: `debugPrint(`, `dump(`, `os_signpost(`;
  - Rule 2 imports widened with `AVFoundation`; Rule 3 imports widened with `Network`; the Rule 4 hosts widened with
    `api.example.org`.
  - Also survived, but these are close to equivalent: removing `FoundationNetworking` from the added names (the
    import set still bans it), and removing `URLSessionConfiguration` (`URLSession` still matches it at a camelCase
    boundary).

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R1-F1 | **Major** | `Packages/TendSourceScan/Sources/TendSourceScan/IngestionSourceRules.swift:11-12` (D1 comment), `:340-360` (`FileFacts.init` builds `networkingHits` with no `contentsOf:` pattern), used by `rule2` `:244-253`, `rule3` `:257-279` and `rule6` `:314-321`; `Packages/TendSourceScan/Tests/TendSourceScanTests/IngestionSourceRulesTests.swift:529-538` (`rule6Positive` asserts the weaker behaviour); `docs/architecture/adr/0006-m2-module-layout.md` Law check P-2 ("Networking can appear only in the three allowlisted `TendAI` files"), which is false today | **D1 makes Rules 2, 3 and 6 weaker than AC-M2-09.** The brief's networking patterns are "the AC-M1-23 networking patterns, plus …". AC-M1-23 lists `contentsOf:` as **URL loading** and says "No other `contentsOf:` exception may be added without a PO decision (Q23)". D1 drops it with no PO decision. Plants P01–P03 pass. The worst case is P01: in `CloudHTTPTransport.swift`, `Data(contentsOf: components.url!)` is a network read outside the T-23 subset (`bytes(for:delegate:)`). It skips the AC-M2-22 ephemeral session, host check and redirect refusal. In P02, a provider adapter could fetch a URL it was handed, outside the transport. This weakens a P-2/P-3 guard. The `http(s)`-literal half of D1 is fine: Rule 4 is strictly stronger for every literal that contains `://` (P13, P18, P25), and Rule 4 explicitly allows `https://<host>` in the allowlisted files. The stated reason for D1 (the harness must read its fixtures) is a product-scope question for the PO. The Developer may not settle it by narrowing a closed list. | (1) Treat `contentsOf:` as a networking pattern in Rules 2, 3 and 6. Keep exactly the AC-M1-23 `append`/`insert` exemption and no file allowlist. Keep the `http(s)`-literal exclusion. (2) Add negative tests for P01, P02 and P03, at least `Data(contentsOf:`, `String(contentsOf:` and `.init(contentsOf:`, and positive tests for `append(contentsOf:)` in each of the three rules. (3) Rewrite `rule6Positive` so it no longer depends on `contentsOf:`. (4) If `TendEval` needs to read its bundled fixtures, raise a PO question now. For example: allow `contentsOf:` in one named fixtures-loader file in the plan, for bundle URLs only. Until the PO decides, the stricter rule stands. `Apps/TendEval/Sources` does not exist yet, so nothing breaks. (5) Correct D1 in `dev-notes.md`, the header comment and the ADR-0006 P-2 line. | Open |
| R1-F2 | **Major** | `Packages/TendSourceScan/Tests/TendSourceScanTests/IngestionSourceRulesTests.swift:90-130` (the Rule 1 plants are generated from `IngestionSourceRules.networkingNames` / `mediaTypes` / `writeNames` / `logNames` / `logCalls`) and `:273-295` (the "coverage" test compares those lists with plants built from the same lists) | **The closed lists are not pinned to the brief, so the tests would not fail if a list were wrong.** These lists are the whole point of AC-M2-09 (T-11 "closed"). Only `allowedNetworkingSubset` and `networkingPrefixes` (`:369-377`) and the stop-word and banned-token lists are compared with a literal copy of the brief. My mutation run left 17 changes green that are not equivalent: 8 media entries, 2 write entries, 3 log entries, the Rule 2 and Rule 3 import sets widened, and the Rule 4 host list widened. "Are the tests real? Would they fail if the code were wrong?" Here the answer is no, for most of AC-M2-09's closed lists. The Developer's own mutation table did not try deleting a list entry. | Add pin tests, like `rule3SubsetIsClosed`, that compare each of these with a **literal copy of the brief text**: `mediaTypes`; `writeNames` + `writeCalls`; `logNames` + `logCalls`; `addedNetworkingNames` + `networkingImports` (and `contentsOf:` after R1-F1); `rule1Imports`, `rule2Imports`, `rule3Imports`; `allowedHosts`; `hostLikePattern` (string equality with the brief's regex); and the T-27 forms. Better still, hand-write at least one plant per entry from the brief text rather than from the engine list. Rerun the 17 surviving mutants and record that they are now killed. | Open |
| R1-F3 | Minor | `Packages/TendSourceScan/Sources/TendSourceScan/IngestionSourceRules.swift:14` | The comment says "`AVURLAsset`, `AppLogger` and `OSLogType` are hits". `AVURLAsset` is not a hit: it does not contain the substring `AVAsset` (P05, and the dev-notes say so too). A false claim in a privacy guard's header will mislead later reviewers. | Remove `AVURLAsset` from the comment, or give a true example such as `AVAssetReader`. | Open |
| R1-F4 | Minor | `docs/milestones/M2/dev-notes.md`, Known limitations row Q-D1 | **Q-D1 judgement: no scanner change in this PR.** (a) The brief's Rule 6 bans no media types in `TendEval`, so "in `TendEval` it would not be caught" is not a gap: `AVAsset` itself is allowed there. The AC-M2-09 Reviewer clause (no audio persisted) is protected by the Rule 6 write confinement and by AC-M2-28's results-file type. (b) In Rules 1–3 `AVURLAsset` needs `AVFoundation`, which the import lists ban (P06, P07). `AVFAudio` does not declare `AVAsset` types. | Correct the Q-D1 row with (a) and (b). It can stay as an optional PO note (adding `AVURLAsset`, or a Rule 6 import list, see R1-F5), and it does not block WI-M2-01. | Open |
| R1-F5 | Minor (question for PO and Tester; gaps in the brief, not Developer defects) | Brief AC-M2-09 lists, as implemented at `IngestionSourceRules.swift:134-155` | My plants found three gaps in the brief's closed lists. The scanner follows those lists faithfully. (a) `write(toFile:` on `NSString`/`NSData` persists data and is not on the write list (P08, P15). (b) Rule 6 has no import list, so `import Darwin` plus `fwrite`/`fopen` passes in `TendEval` (P14). (c) The T-23 subset works on identifiers, so `session.uploadTask(with:)` and `session.webSocketTask(with:)` pass, because the banned task type is inferred (P17). | PO and Tester: decide before WI-M2-M4 and WI-M2-M7 whether to add `write(toFile:`, `fopen(`/`fwrite(`, a Rule 6 import list, and the task-creating method names (`uploadTask(`, `downloadTask(`, `streamTask(`, `webSocketTask(`) to AC-M2-09. Until then, the WI-M2-M4 and M7 reviewers check these by hand. | Open (ticket) |
| R1-F6 | Minor | `IngestionSourceRules.swift:289-290` (D3, Q-D2) | Bare allowed hosts may appear in any `TendIngestion` file, not only in the payload builder's provider table, because the plan names no table file. This follows the brief as written, and it is the stricter reading of "where they may appear" across modules. | WI-M2-10 names the provider-table file in the plan and narrows the rule to it. This needs no change in this PR. | Open (ticket, WI-M2-10) |
| R1-F7 | Nit | `docs/milestones/M2/dev-notes.md` D8; `Packages/TendIngestion/Sources/TendIngestion/Text/TextFolding.swift:39-41` | D8 says that running the fold before the whitespace collapse gives "the same result" as the brief's order. That may not hold for unusual input, for example a lone combining mark between spaces (`"a \u{301} b"`): the fold can remove the mark after the collapse has already run in the brief's order. I did not run this on the toolchain. The Developer's order is the safer one, because it collapses last. | Either soften the claim in D8, or pin such a case in `TextPrimitivesTests` and tell the PO and Tester that the order is fold-then-collapse. | Open |

There are no Blockers. Two Majors are open, so the verdict is **CHANGES REQUIRED** (OPERATING_MODEL §6).

### Decisions D1–D9: do they weaken a law?
| Decision | Verdict |
|---|---|
| D1 | **Weakens P-2/P-3** (the `contentsOf:` half). See R1-F1. The `http(s)`-literal half is accepted. |
| D2 | Accepted. Substring matching is stronger than the brief. Left-boundary calls work: `Swift.print(` is caught (P10). |
| D3 | Accepted. It is the stricter cross-module reading (P16). Narrow it in WI-M2-10 (R1-F6). |
| D4 | Accepted. AC-M1-23 bans no `Locale(identifier:)` form, so the exception is a no-op. Adding a ban would extend a closed list. |
| D5 | Accepted. The trailing-closure form is caught (P12). The exception is off, and it is pinned in `ScanScope.swift` and tested. |
| D6 | Accepted. Rule 6 restricts where writes may happen. It does not require the results writer to exist. |
| D7 | Accepted. Splitting at interpolation makes `"https://\(host)"` a hit (P18). That is stricter. |
| D8 | Accepted, with a Nit on the claim (R1-F7). |
| D9 | Accepted, and correct: members are compared by UTF-8 bytes and duplicates throw, so canonically equal keys are not merged. |
| UX-3 | No overdue/lateness state, field or string in the new code. `BannedTokens.all` is the list itself. Its follow-up (an AC-M2-12 vocabulary scan that exempts that one declaration) belongs to WI-M2-04 and is ticketed. |

### Canonical JSON check
- Keys are sorted by UTF-8 bytes (`lexicographicallyPrecedes` on `.utf8`).
- After sorting, a duplicate key (equal bytes) is always next to its twin, so the check that compares neighbours is
  complete.
- Escaping is exactly as ADR-0006 says: only `"` and `\` are escaped, `\b \t \n \f \r` use short escapes, the other
  C0 controls use lower-case `\u00xx`, `/` is not escaped, and everything else is raw UTF-8.
- Integers are written with `String(Int)`, so there is no leading zero and no `+`. Swift strings cannot hold lone
  surrogates.
- The golden bytes, the UTF-8 versus UTF-16 key-order cases and the seeded 2,000-value validity property are real
  tests.
- Note for WI-M2-10: `Int` values above 2^53 are not portable to JavaScript readers. This is not an issue for the
  current payloads.

## Checklist
- [ ] Correctness vs ACs: AC-M2-09 Rules 2, 3 and 6 are weaker than the brief (R1-F1). Rules 1, 4 and 5 are correct.
- [ ] Tests meaningful (would fail if code broke): not for the closed lists (R1-F2). They are meaningful elsewhere:
  Rules 3, 4 and 5, canonical JSON and folding are well tested.
- [x] Swift 6 concurrency safe: language mode v6. No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `Task {}`,
  and no shared mutable state (static `let`s only). 0 warnings with `-warnings-as-errors`.
- [x] No force unwraps / `try!` in product code paths (`TendIngestion/Sources`).
- [ ] Privacy (P-1…P-4): P-2/P-3 concern from R1-F1. No product code sends, writes or logs anything.
- [x] UX-2/UX-3 enforced in engine: UX-2 does not apply. The UX-3 matcher follows the brief.
- [x] Accessibility (UI): does not apply (no UI).
- [x] Performance: the scan runs in tests only. The folding and JSON writers are linear.
- [x] No new dependency without ADR: only local path packages, recorded in ADR-0006.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection API. `TendCore` is unchanged. |
| UX-3 Zero-Guilt | pass | The banned-token matcher follows the brief Definitions (whole tokens, split at non-letters, then name-folded) and is tested against the literal AC-M1-02 list. No new identifier or string uses a banned word, apart from the list itself. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | No inference here. Rule 5 bans `SFSpeech*`, with the T-27 exception off (P12 is caught even with it on). |
| P-2 No data leaves device (except user iCloud) | **concern** | Rules 2, 3 and 6 let `contentsOf:` URL loading through (R1-F1, P01–P03). No product code does this today, but the guard that AC-M2-09 promises is weaker than specified. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | **concern** | In the allowlisted files, `Data(contentsOf:)` would skip the AC-M2-22 transport controls (R1-F1). Rule 4's host limits hold (P09, P13, P16, P18, P25). |
| P-4 Media not persisted without consent | pass | `TendIngestion` has no write, log or media API (the scan finds 0 violations and P10, P21 and P22 are caught). R1-F2 means some list entries are not protected by tests yet, and R1-F5(a) is a gap in the brief, not in the code. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Developer (via Orchestrator) | Reviewer | accepted for review | PR #15, head `6143908`. Fresh worktree. All three commands rerun on Linux Swift 6.2: 33 tests and 17 tests green, 0 warnings, AC-M2-09 scan log as in dev-notes. 25 planted violations and 37 single-change mutants run. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned (CHANGES REQUIRED) | Fix R1-F1 and R1-F2 (Major). Fix R1-F3 and R1-F4 in the same round (both are small). R1-F6 is ticketed to WI-M2-10. R1-F7 is optional. |
| 2026-11-21 | Reviewer | Product Owner + Acceptance Tester (via Orchestrator) | question | R1-F1(4): does `TendEval` need a named `contentsOf:` fixtures-loader exception? R1-F5: add `write(toFile:`, `fopen(`/`fwrite(`, a Rule 6 import list and the `URLSession` task-creating methods to AC-M2-09? Q-D1: no change needed (R1-F4). |

---

## Round 2 — head `7bc22b9` (2026-11-21)

- **Verdict:** APPROVE. No Blocker or Major is open. Two new Minors (R2-F1, R2-F2) are ticketed and do not block.
- **What changed since round 1:**
  - `ed3dbcc`: the R1-F1 to R1-F4 and R1-F7 fixes.
  - `a94e37c`: main merged, including PR #16 (the PO decisions M2 Q23 and Q24 in the brief and the plan).
  - `7bc22b9`: M2 Q24 built in full. M2 Q23 is deliberately not built, so this item stays strict.
  - New Developer decision D10: `delegate:` counts only at the top level of the `bytes(for:` call's arguments.
- **Inputs re-read:** AC-M2-09 on `origin/main` (Q24 lists, call-pattern rule, Rule 3 session methods, Rule 6 imports,
  the Q23 fixtures-loader exception, and the new plants and positives); plan lines 10, 58, 174-186 and 442-443 (the
  timing of Q23 and Q24); dev-notes D1, D2, D8, D10 and the round 2 and round 3 handoff rows; the diff
  `6143908..7bc22b9`.

### What I ran (Linux, Swift 6.2 `swift:6.2-noble`, worktree detached at `7bc22b9`)
| Command | Result |
|---|---|
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 1.972 seconds.` 0 warnings. |
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!`, 0 warnings. |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 17 tests in 3 suites passed after 0.147 seconds.` Scan log: `TendIngestion (required) …: 4 files scanned`, `TendAI` and `TendEval` `not present`, `4 files in total, 0 violations`. |

### Re-planted round 1 misses, plus my own Q24 plants
I used a temp copy with one extra test file. The configuration has the plan's file names and the T-27 exception **on**.

| # | Plant | Where | Result |
|---|---|---|---|
| P01 / P02 / P03 | `Data(contentsOf: …)` | allowlisted file / TendAI adapter / TendEval | caught (Rules 3 / 2 / 6, `contentsOf:`) |
| P03b | the brief's Q23 positive form, exactly | `Fixtures/EvalFixturesLoader.swift` | caught (Rule 6). Strict, as the plan requires before Q23. |
| P05 | `AVURLAsset(url:)`, no import | TendAI | not caught, as expected (R1-F4: needs `AVFoundation`, which the import lists ban) |
| P08 / P15 | `write(toFile:` | TendEval / TendAI | caught (Q24 write list) |
| P14a / P14b | `import Darwin` / `fwrite(` | TendEval | each caught on its own (Q24) |
| P17, Q01 | `s.uploadTask(with:from:)` / `s.webSocketTask(with:)` | allowlisted | caught (session-method call and method reference) |
| Q02 | `s.bytes(for: r)` | allowlisted | caught (no `delegate:`) |
| Q03 / Q04 | `bytes(for: r, delegate: nil)`; `bytes(\nfor:r,delegate:d)` | allowlisted | pass. The brief asks only that `delegate:` is in the argument list. |
| Q05 | `` s.`bytes`(for: r) `` | allowlisted | caught (backticks removed) |
| Q06 / Q07 | `delegate:` only inside a comment / only inside a string | allowlisted | caught (comments and string text are removed before D10 looks) |
| Q08 | an allowed `bytes(for:…delegate:)` followed by `data(for:` | allowlisted | caught (`data(for:`) |
| Q09 / Q10 | `let f = s.dataTask` / `let f = s.data` | allowlisted | caught / pass. `data` is not on the brief's method-reference list. |
| Q11 / Q12 | `bytes(from: u, delegate: d)`; `download(resumeFrom:` | allowlisted | caught |
| Q13 to Q16 | `@_exported import os`; `@preconcurrency import Darwin`; `import func Glibc.fwrite`; `import Foundation; import UniformTypeIdentifiers` | TendEval | caught (Rule 6 import) |
| Q17 | `import struct SwiftUI.Text` | TendEval | pass (module `SwiftUI`) |
| Q18 to Q22, Q26, Q31 | `fputs(`, `putchar(`, `archiveRootObject(`, `@SceneStorage`, `printf (`, `creat(`, `mkstemp(` | across the modules | caught |
| Q23 / Q24 | `` `print`(x) ``; `Swift.print\n(x)` | TendIngestion | caught |
| Q25 | the brief's positives: `inputs(`, `snprintf(`, `metadata(for:`, `reprint(`, `data(forKey:`, `append(contentsOf:)`, `insert(contentsOf:at:)` | TendIngestion | pass |
| Q27 / Q28 | `tmpfile()` / `puts(x)` | the results writer | pass (write allowed there) / caught (log never allowed) |
| Q29 | `xs.append(Data(contentsOf: u))` | TendAI | caught. The exemption applies only to the call that directly encloses the label. |
| Q32 | `URLSession.shared.data(for: r)` | TendEval | caught |
| **Q30** | `` `…` (44 backticks) SFSpeechRecognizer.authorizationStatus(); x.data(for: r) `` | `SpeechPermission.swift`, T-27 exception **on** | **not caught**. See R2-F1. With the exception off, as it is today, the hit is reported. |

### Mutant sample (one change at a time to `IngestionSourceRules.swift`, full TendSourceScan suite each time)
All 17 were **killed**.
- **Six of the round 1 survivors**, deleted or widened again: AVAudioBuffer, OutputStream, `debugPrint(` and
  `os_signpost(` deleted; Rule 2 imports widened with `AVFoundation`; Rule 4 hosts widened with `api.example.org`.
- **Q24 entries deleted:** `fputs(`, `creat(`, `puts(`, `bytes(from:`, `data(for:`, `SceneStorage`, and the `dataTask`
  method reference.
- **Rule 6 imports widened** with `os`.
- **D10 broken:** `delegate:` counted at any depth.
- **The `func` import kind keyword dropped.**
- **`contentsOf:` exempted everywhere.**

R1-F2 is fixed in substance: `BriefPinTests.swift` compares each list with the brief text, and every entry has a
hand-written plant.

### Q24 coverage check (brief AC-M2-09 on main → code and test)
| Brief item | Code | Test | OK |
|---|---|---|---|
| Session-method calls (14) and method references (5) | `IngestionSourceRules.swift:133-143`, FileFacts `:425-455` | `Q24RulesTests` "list plants" (parameterised, TendIngestion) and "coverage"; `BriefPinTests` networking pin | yes |
| Write list (20) and log list (18), with their split | `:165-180` | `BriefPinTests` write/log pin; hand-written plants | yes |
| Call-pattern rule: left boundary, case-sensitive, whitespace and newlines, backticks, exact first label | `callPattern`, `callCode` (`:434`) | `Q24RulesTests:177-220` | yes |
| Type names keep the AC-M1-23 camelCase rule | D2: substring match. Every camelCase hit is also a substring hit, so this is stricter and relaxes nothing (the brief says "relaxes none of them"). | pins and plants | accepted |
| Rule 3: only `bytes(for:` with `delegate:` (D10: top level, after comments and strings are removed) | `:320-330`, `argumentList` `:478-492` | `Q24RulesTests:94-117` (includes `delegatee:` and a nested `delegate:`) | yes. D10 is the strict reading of "checked like AC-M1-23's `using:` rule". |
| `contentsOf:` in Rules 2, 3 and 6, with only `append`/`insert` exempt | FileFacts `:425-431` | `Q24RulesTests:119-125`, R1-F1 tests in 8 locations | yes |
| Rule 6 closed imports: first path component after a kind keyword; `@_exported` and `@_implementationOnly` count | `rule6Imports`, `importedModule(of:)`, `rule6` | `Q24RulesTests:140-175`; `BriefPinTests:144` | yes |
| "Also caught" items: `import Darwin`, `fwrite(`, `@AppStorage`, `uploadTask`, `webSocketTask`, `bytes(for:` without `delegate:`, `s.dataTask`, `Data(contentsOf:` in 3 places | — | `Q24RulesTests:81-125` | yes |
| Positives: the Rule 3 streaming read exactly, and the "anywhere" list | — | `Q24RulesTests:109`, `BriefPinTests:153` | yes |
| Q23 loader exception, its "caught in the loader file" plants, and its loader positive | **not built** (header `:31-32`) | `Q24RulesTests:127` shows that the loader file is strict | correct for now. See R2-F2. |

**Leaving Q23 out is correct.**
- The plan requires it: line 10, lines 177 and 442-443 ("WI-M2-01 round 2 stays strict"), with Q23 in a follow-up
  scanner PR that merges before WI-M2-M7 opens for review.
- It is the stricter state. With no exception, every `contentsOf:` in TendEval is a hit, including the loader's
  allowed form.
- `Apps/TendEval/Sources` does not exist yet, so no real code is blocked.
- The brief's Q23 loader positive cannot pass until the follow-up. That is a planned gap, not a defect in this item.

### Round 1 findings, re-verified
| # | Round 1 severity | Status in round 2 | Evidence |
|---|---|---|---|
| R1-F1 | Major | **Closed** | P01–P03 caught; `contentsOf-exempt-all` mutant killed; `rule6Positive` no longer uses `contentsOf:`; D1, the header comment and the ADR-0006 P-2 line are corrected. |
| R1-F2 | Major | **Closed** | `BriefPinTests.swift` pins every closed list to the literal brief text and has hand-written plants. All 6 round 1 survivors I re-ran are killed, and so are the 11 Q24 and D10 mutants. |
| R1-F3 | Minor | **Closed** | The header now says `AVAssetReader` is a hit and `AVURLAsset` is not (`IngestionSourceRules.swift:16-17`). |
| R1-F4 | Minor | **Closed** | The dev-notes Q-D1 row is corrected (dev-notes line 303). Rule 6 now also bans `AVFoundation` through its import list. |
| R1-F5 | Minor (PO/Tester) | **Closed** | M2 Q24 added `write(toFile:`, the C write and log calls, a Rule 6 import list and the session methods (P08, P14, P15, P17 caught). |
| R1-F6 | Minor | Open (ticket, WI-M2-10) | Unchanged. Bare hosts may still appear in any TendIngestion file until the provider-table file is named. |
| R1-F7 | Nit | **Closed** | D8 is softened, and the case is pinned in `TextPrimitivesTests.swift:42-45` (`"x \u{301} y"` → `"x y"`). |

### Round 2 findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R2-F1 | Minor | `Packages/TendSourceScan/Sources/TendSourceScan/IngestionSourceRules.swift:434` (call hits use offsets in `callCode`, where backticks are removed), `:465-472` (the T-27 offsets are taken in `code`), `:503-506` (`isSpeechException` compares the two), `:519` (`networkingViolations`) | **Two offset spaces are mixed.** Session-method call hits and method-reference hits carry offsets in the text with backticks removed. The Rule 5 exception offsets are positions in the original code. When the T-27 exception is on, a session call whose `callCode` offset equals an exception offset in the speech-permission file is wrongly exempt. Plant Q30 shows this: 44 backticks before the exception call hide a later `data(for:`. Today the exception is off, so the case cannot happen, and it needs very unusual code. But WI-M2-M1 may turn T-27 on, and the Q23 follow-up will add more offset-based exemptions on top of this. | Keep one coordinate space. Either make `isSpeechException` match only hits whose rule is `SFSpeech`, or record which text each offset came from. Add Q30 as a negative test with the exception on. Do this in the Q23 follow-up scanner PR, or in WI-M2-M1 before `speechPermissionExceptionEnabled` becomes `true`, whichever comes first. | Open (ticket) |
| R2-F2 | Minor | Brief AC-M2-09 "Caught in the fixtures-loader file" and the loader positive; `Q24RulesTests.swift:127-138` | Without Q23, the loader-file plants are only partly tested. The `contentsOf:`, `String(contentsOf:` and `NSURL` forms are caught today. `Bundle.main.resourceURL!.appendingPathComponent(`, `url(forResource: "../x"`, `URL(fileURLWithPath:` and the parameter-bound `Data(contentsOf: u)` with a separate binding have no test yet: they only become meaningful once the exception exists. The loader positive cannot pass until then. | The Q23 follow-up PR must add every "Caught in the fixtures-loader file" plant and the exact loader positive. Its reviewer must also confirm that the loader reads only bundle resources (AC-M2-09 Reviewer clause). Track this in `TRACEABILITY.md` and the plan, as AC-M2-09 part "Q23 follow-up". | Open (ticket, Q23 follow-up) |

There are no Blockers or Majors, so the verdict is **APPROVE** (OPERATING_MODEL §6).

**Merge conditions are outside this review.** The Merge Gatekeeper still needs these before merging:
- HM-1, so that CI runs TendSourceScan and TendIngestion (plan R-11; G3);
- the owner's O-1 change (M2 `IN-BUILD` in `STATUS.md`);
- green checks on `7bc22b9`.

### Round 2 checklist
- [x] Correctness vs ACs: every Q24 rule, plant and positive is implemented and tested. Q23 is deferred, as the plan
  says (R2-F2).
- [x] Tests meaningful: the pins and hand-written plants are in place, and all 17 sampled mutants are killed.
- [x] Swift 6 concurrency safe: no new shared state. `callCode` and `streamingReadOffsets` are `let`s, computed once
  per file. 0 warnings.
- [x] No force unwraps / `try!` in product code paths. TendIngestion `Sources` is unchanged since round 1.
- [x] Privacy (P-1…P-4): the guard is now at least as strict as the brief, with one Minor gap that cannot happen today
  (R2-F1).
- [x] UX-2/UX-3 enforced in engine: UX-2 does not apply. UX-3 is unchanged.
- [x] Accessibility (UI): does not apply (no UI).
- [x] Performance: the extra regex passes run in tests only, linear per file.
- [x] No new dependency without ADR.

### Round 2 law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection API. `TendCore` is unchanged. |
| UX-3 Zero-Guilt | pass | Unchanged since round 1. No new identifier or string uses a banned token. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Rule 5 is unchanged and P12 is still caught. The R2-F1 gap applies only with T-27 on, and it is ticketed before that. |
| P-2 No data leaves device (except user iCloud) | pass | `contentsOf:` and every Q24 session method are hits outside the Rule 3 subset. Rule 6 has a closed import list. The R1-F1 concern is closed. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | In the allowlisted files the only network read allowed is `bytes(for:` with a top-level `delegate:` (D10), so AC-M2-22's transport controls cannot be skipped through `data(for:`, `contentsOf:` or the task methods. Rule 4 is unchanged. |
| P-4 Media not persisted without consent | pass | The write and log lists now include `write(toFile:`, `AppStorage`, `SceneStorage`, `archiveRootObject(` and the C calls. TendIngestion has 0 violations. The results writer may write but never log (Q27, Q28). |

### Round 2 handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Developer (via Orchestrator) | Reviewer | accepted for review | Head `7bc22b9`. Reran 3 commands: 63 and 17 tests green, 0 warnings. 42 plants and 17 mutants run. |
| 2026-11-21 | Reviewer | Merge Gatekeeper (via Orchestrator) | accepted (APPROVE) | No open Blocker or Major. Merge still needs HM-1, O-1 and green checks. ADR-0006 may move to Accepted. |
| 2026-11-21 | Reviewer | Developer / Work Planner (via Orchestrator) | tickets | R2-F1 (one offset space; before T-27 is turned on or in the Q23 follow-up). R2-F2 (Q23 follow-up: every loader plant and the loader positive). R1-F6 (WI-M2-10). |
