# M2 Developer Handoff — WI-M2-01

There is one section per work item, and each section follows the dev-notes template
(`docs/governance/templates/dev-notes.md`).

---

## WI-M2-01 — `TendIngestion` and `TendSourceScan` packages, ADR-0006, text primitives, canonical JSON, the AC-M2-09 scanner

- **Owner:** Developer  ·  **Branch:** `m2/ingestion-foundation`, based on `m2/brief-and-plan` at `81fd80a`  ·
  **PR:** not opened yet (the Orchestrator opens it; the merge needs HM-1 and O-1)  ·
  **ADRs:** [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (Proposed, new). The item also follows
  [ADR-0001](../../architecture/adr/0001-tendcore-module-boundary.md) and
  [ADR-0005](../../architecture/adr/0005-cloud-ai-providers.md).
- **Requirements:**
  - FR-A1 (primitives for room linking, the duplicate shortlist and the scorer); UX-3 (banned-token matcher);
    P-1, P-2, P-3, P-4 (the scan).
  - **Owns AC-M2-09** ([plan.md](plan.md)). Its evidence is taken on the M2 merge commit (WI-M2-M8), when all three
    module roots exist. Every PR re-runs the scan.
  - In scope: N-1 (Rule 3 whole identifiers), T-23 (allowed subset), T-26 (scorer I/O outside Rule 1), T-27 (Rule 5
    exception, off) and T-30 (Rule 4 whole literal).
- **Inputs:**
  - [brief.md](brief.md) Draft v4 (testability ticked at `580d23e`): the Definitions (name folding, keywords, stop
    words, banned tokens) and AC-M2-09 Rules 1–6.
  - [plan.md](plan.md): the WI-M2-01 row and scope notes, "Module and file layout", "Named files" and "Exact commands".
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, so M2 build work is unlocked (CLAUDE.md §5). The `STATUS.md`
  change to M2 `IN-BUILD` (O-1) is waiting for the owner's merge. This PR is not merged before then.

### What changed
- **New package `Packages/TendSourceScan`.** It is Foundation only, test-only, and is never linked into an app target.
  - `SourceScanner.swift` is the M1 lexer and the AC-M1-23 / AC-M1-02 matchers, moved from
    `Packages/TendCore/Tests/TendCoreTests/Support/SourceScanner.swift`. The matching rules are unchanged. The changes:
    - the API is public, with no `import Testing`;
    - `apiHits` takes `allowedImports` and `contentsOfAllowlist`, and the defaults are the M1 values;
    - `networkingHits` takes the name list;
    - `ScanHit` carries a scalar offset;
    - an invalid regex **fails closed**: it returns a synthetic match, so the scan reports a hit instead of passing.
    - The fixed regexes are named constants (`allPatterns`), and a self-test compiles each one.
  - `IngestionSourceRules.swift` is the AC-M2-09 rule engine:
    - the brief's three closed lists, the import sets, the T-23 subset and prefixes, the Rule 4 hosts and regex
      (verbatim), and the T-27 exception forms;
    - `IngestionScanConfiguration`, which holds the plan's named file paths;
    - `violations(in:configuration:)`, which applies Rule 1, 2/3 or 6 according to the file's module and the
      allowlist, plus Rules 4 and 5 in every module.
- **New package `Packages/TendIngestion`.** The library depends on `../TendCore`. The test target depends on
  `TendIngestion` and `../TendSourceScan`. It uses tools 6.2, Swift 6 mode and iOS 26 / macOS 26.
  - `Text/TextFolding.swift` provides:
    - `foldName` (name folding, T-09) and `foldWithoutArticle` (the keyword fold);
    - the closed typographic-quote map and whitespace collapse (Unicode `White_Space`);
    - the letter and decimal-digit classes (general category), and `utf8Precedes`.
  - `Text/Keywords.swift`: `Keywords.of(_:)` and the closed 89-word `stopWords`.
  - `Text/BannedTokens.swift`: the AC-M1-02 list and `BannedTokens.matches(in:)`, which returns the folded token and
    the original range for WI-M2-04.
  - `JSON/CanonicalJSON.swift`: `CanonicalJSON` and `CanonicalJSONWriter` (rules in ADR-0006).
  - The tests:
    - `TextPrimitivesTests`;
    - `CanonicalJSONTests`, including a seeded 2,000-value property test;
    - `ScanScope.swift`, the committed scope table: `TendIngestion` required, `TendAI` and `TendEval` optional until
      WI-M2-M1, T-27 off;
    - `IngestionSourceScanTests`, the real AC-M2-09 scan over the repository paths, with file counts per module.
- **ADR-0006** (M2 module layout, the canonical JSON choice, the scan library, the scoring tool outside Rule 1).
- **Not changed:**
  - `Packages/TendCore`, all of it, including the M1 lexer copy and its tests (R-16);
  - every protected path;
  - every SPM dependency (only local path packages were added; ADR-0006).

### Public API added (for the Reviewer's naming and UX-3 check)
- **`TendIngestion`:**
  - `TextFolding`: `foldName`, `foldWithoutArticle`, `mapTypographicQuotes`, `collapseWhitespace`, `isLetter`,
    `isDecimalDigit`, `utf8Precedes`, `leadingArticles`, `typographicQuotes`;
  - `Keywords`: `of`, `stopWords`;
  - `BannedTokens`: `all`, `matches(in:)`, `containsBannedToken`, `tokens(in:)`, and `BannedTokenMatch`;
  - `CanonicalJSON` (and `.Member`), `CanonicalJSONWriter`: `data`, `string`, and `CanonicalJSONError.duplicateKey`.
- **`TendSourceScan`:** `SourceScanner`, `LexedSource`, `ScanHit`, `ScannedModule`, `ScannedFile`,
  `IngestionScanRule`, `RuleViolation`, `IngestionScanConfiguration`, `IngestionSourceRules`.
- No name contains a banned token, and none uses the M1 design-forbidden list.
- No API returns "what to do now" items (UX-2).

### Decisions the Reviewer should know (technical, reversible; no product meaning changed)
These are my readings of the brief where it leaves the matching method open. Each one is tested. **D1–D3** affect
what AC-M2-09 reports, so I flag them for the Tester as well.

1. **D1: what counts as a "networking pattern" (Rules 1, 2, 3 and 6).** *Corrected in round 2 (review R1-F1).*
   - It covers:
     - the AC-M1-23 networking names and call names, `Host.current` and `URL(string:`;
     - `contentsOf:` URL loading, with exactly the AC-M1-23 / Q23 `append` / `insert` exemption and **no** file
       allowlist;
     - the M2 names, all matched like M1, at camelCase word boundaries;
     - `import Network`, `import CFNetwork` and `import FoundationNetworking`.
   - So `Data(contentsOf:`, `String(contentsOf:` and `.init(contentsOf:` are hits in every `TendAI` file, including
     the three allowlisted files, where they fall outside the T-23 subset. They are also hits in every `TendEval` file,
     including the results writer.
   - One AC-M1-23 entry is **not** a networking pattern here: `http(s)` string literals. Rule 4 governs every literal,
     and it allows `https://<host>` in the allowlisted files, so counting the literals as Rule 3 hits would make Rules 3
     and 4 contradict each other. The Reviewer accepted this half.
   - In round 1 I had also excluded `contentsOf:`, so that `TendEval` could read its bundled fixtures. That narrowed a
     closed list without the PO decision that AC-M1-23 / Q23 require. It is reverted. Whether `TendEval` gets a named
     fixtures-loader exception is a PO question (asked by the Reviewer); until the PO decides, the strict rule stands.
     `Apps/TendEval/Sources` does not exist yet, so nothing breaks.
   - Tests: "(R1-F1) negative: Data(contentsOf:, String(contentsOf:, .init(contentsOf: … are caught in every module
     and file kind" and "(R1-F1) positive: append(contentsOf:) and insert(contentsOf:at:) pass in Rules 1, 2, 3 and 6".
2. **D2: media types and the write/log names match as a substring of an identifier.**
   - The brief gives no matching rule for these M2 lists. A substring match is strictly stronger than the camelCase
     split, so `AVAssetReader`, `AppLogger` and `OSLogType` are hits.
   - The write/log calls match at a left identifier boundary: `Swift.print(` is a hit and `reprint` is not.
3. **D3: where Rule 4 lets the allowed hosts appear.** I read "Where they may appear" strictly:
   - bare hosts appear only in `TendIngestion`, for the provider table;
   - `https://<host>` appears only in the three allowlisted files;
   - so a bare host in `TendAI` or `TendEval` is a hit.

   The plan does not name the provider-table file, so any `TendIngestion` file may hold a bare host. WI-M2-10 could
   name the file so the rule can be narrowed. This is an **open question** for the Planner and Tester.
4. **D4: Rule 1's `Locale(identifier: "en_US_POSIX")` exception** is satisfied because no AC-M1-23 pattern matches it
   (positive test `rule1Positive`). I did **not** add a ban on other `Locale(identifier:)` values, because that would
   extend a closed list without a PO decision.
5. **D5: the T-27 exception forms are exact.**
   - Allowed: `SFSpeechRecognizer.requestAuthorization(` (so the trailing-closure spelling `requestAuthorization { … }`
     is a hit), `SFSpeechRecognizer.authorizationStatus(`, and the identifier `SFSpeechRecognizerAuthorizationStatus`.
   - The exception only applies in `SpeechPermission.swift` and only when `ScanScope.speechPermissionExceptionEnabled`
     is true. It is **off** until WI-M2-M1.
   - Every other `SFSpeech*` use, including `SFSpeechRecognizer(` and `.init(`, is a hit, with the exception off or on.
6. **D6: Rule 6 does not require the results writer to exist** or to contain a write. It only bans write APIs in
   every other `TendEval` file. Rule 6 sets no `TendEval` import list (the brief gives none), but networking imports
   are still caught.
7. **D7: Rule 4 works on decoded literal segments.**
   - The lexer splits a literal at each interpolation, so `"https://\(host)"` gives the segment `https://`, which is
     host-like and not allowed. URLs must therefore be built with `URLComponents`, as T-23 intends.
   - The regex is the brief's, verbatim. In `NSRegularExpression`, `$` also matches before one final newline. That is
     stricter, never looser.
8. **D8: details of name folding.**
   - The order is: quotes to ASCII, then the fold, then trim and collapse, then strip the article. The brief lists the
     collapse first. The result is **not always** the same (review R1-F7): a lone combining mark between spaces is
     removed by the fold, so `"x \u{301} y"` folds to `"x y"` here, where the brief's order would leave two spaces.
     The case is pinned in `TextPrimitivesTests`. **For the PO and Tester:** the implemented order is
     fold-then-collapse, which is the safer one, because it collapses last.
   - An article is stripped only as a whole word followed by more text. So "The" stays "the", and "Theatre room" is
     unchanged.
   - The quote map is a closed list: ‘ ’ ‚ ‛ ′ ʼ become `'`, and “ ” „ ‟ ″ become `"`.
   - Letters are Unicode categories Lu, Ll, Lt, Lm and Lo, and digits are Nd. Both are tested on the first scalar of
     each `Character`, so a decomposed `a` plus a combining accent stays one letter.
9. **D9: canonical JSON members are an ordered list, not a `[String: …]` dictionary.**
   - `"é"` and `"e\u{301}"` are equal as Swift `String`s, but they are different keys by bytes.
   - Duplicate detection uses UTF-8 bytes and throws a typed error.

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-09 (scan) | `TendIngestionTests` › "AC-M2-09: Rules 1–6 hold over every .swift file in the three module Sources (file counts logged per module)" | PASS on Linux. Log: `TendIngestion (required) Packages/TendIngestion/Sources: 4 files scanned`; `TendAI (optional) …: not present`; `TendEval (optional) …: not present`; `4 files in total, 0 violations`. **Partial:** two roots do not exist yet. The evidence for the AC is the WI-M2-M8 run with all three roots required. |
| AC-M2-09 (negative, one planted hit per rule) | `TendSourceScanTests` › "AC-M2-09 negative: every planted hit is caught by its rule" (171 cases over Rules 1–6), "AC-M2-09 coverage: the planted fixtures exercise every entry…", and `TendIngestionTests` › "AC-M2-09 negative (driver): one planted hit per rule…" | PASS |
| AC-M2-09 closed lists pinned to the brief (round 2, R1-F2) | `TendSourceScanTests` › `BriefPinTests`. The pins compare the engine with a literal copy of the brief text for: the networking names and imports, the AC-M1-23 networking names, call names and `contentsOf:` exemptions, the media types, the write and log APIs (and their write/log split), the Rule 1/2/3 imports, the hosts, the host-like regex (string equality) and the T-27 forms. There are hand-written plants per entry for media (Rules 1–3), write (Rules 1–3 and 6), log (Rules 1–3, 6 and the results writer), networking (Rules 1, 2 and 6, and Rule 3 outside the subset), imports and hosts. | PASS |
| AC-M2-09 `contentsOf:` (round 2, R1-F1) | "(R1-F1) negative: …" (6 plants × 8 locations: the three allowlisted files, two `TendAI` adapter files, `TendEval` and its results writer, and `TendIngestion`); "(R1-F1) positive: append(contentsOf:) and insert(contentsOf:at:) …"; `rule6Positive` rewritten so it uses no `contentsOf:` | PASS |
| AC-M2-09 Rule 3 (T-23, N-1) | "Rule 3 (T-23): URLSessionWebSocketTask and URL(string: are caught; a subset-only file passes"; "Rule 3 (N-1): … willPerformHTTPRedirection is not a hit"; "Rule 3: the allowed subset is exactly the brief's closed list" | PASS |
| AC-M2-09 Rule 4 (T-30) | "Rule 4 (T-30): tend.ai.key and com.tend.eval pass; api.example.com and https://api.example.com/v1 are caught" (in every module); "Rule 4: bare hosts pass in TendIngestion; https:// hosts pass only in allowlisted files"; "Rule 4: host-like is decided on the whole literal" (17 cases) | PASS |
| AC-M2-09 Rule 5 (T-27) | "Rule 5 (T-27): SFSpeechRecognizer( in the speech-permission file is caught, with the exception off and on"; "Rule 5 (T-27): the two exception calls … pass only with the exception on, only in the speech-permission file" | PASS |
| AC-M2-09 Rule 6 | "Rule 6: a write API outside EvalResultsWriter.swift and a log API anywhere in TendEval are caught"; "Rule 6 positive …" | PASS |
| AC-M2-09 positives | "Rule 1 positive …", "Rule 2 positive …", "rule hits in comments and plain string text are ignored", "each module is checked by its own rule (dispatch)" | PASS |
| AC-M2-09 Reviewer part | No audio buffers, request bodies, responses or keys are persisted or logged in the three modules. Today only `TendIngestion` exists, and it has no write or log API (the scan above). | For the Reviewer |
| AC-M1-02 / AC-M1-23 (moved lexer, regression) | `TendSourceScanTests` › all M1 self-tests ported (124 planted patterns, near-misses, comments and strings, exemptions) | PASS. The M1 originals also still pass in `TendCoreTests`. |
| Groundwork for AC-M2-04, 07, 08, 12 and 14 (no AC owned) | `TextPrimitivesTests`: name folding (26 cases), keywords (14), the stop-word list is exactly the brief's 89 words, the banned-token list and matcher (16) and its ranges, UTF-8 order | PASS. The owning items (WI-M2-04, 07, 08, 15) add the AC tests. |
| Groundwork for AC-M2-20 and 28 (no AC owned) | `CanonicalJSONTests`: hand-written golden bytes (key order by UTF-8, including U+FF5E against U+1F600 and `é` against `e`+U+0301), escaping in hex, duplicate key, a request-shaped golden, and a 2,000-value seeded determinism and validity property (seed `0x0A11CE5EED000001`) | PASS |

### Test runs (R-18 runtime record)
| Command | Summary line | Tests / cases | Runtime |
|---|---|---|---|
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` (round 2) | `✔ Test run with 48 tests in 3 suites passed after 0.563 seconds.` | 48 tests, 385 cases (round 1: 33 / 365) | ~0.6 s (plus the build) |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` (round 2) | `✔ Test run with 17 tests in 3 suites passed after 0.106 seconds.` The scan log is unchanged: 4 files, 0 violations. | 17 tests, 72 cases (round 1: 17 / 70) | ~0.1 s |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` (round 1; not rerun in round 2, because `Packages/TendCore` is unchanged) | `✔ Test run with 127 tests in 17 suites passed after 113.063 seconds.` | 127 tests | ~113 s |
| `swift build --package-path Packages/TendCore` and `Packages/TendIngestion`, each with `-Xswiftc -warnings-as-errors` | `Build complete!` | — | — |

Every run had 0 warnings, 0 failures and 0 skips. The toolchain was Swift 6.2.4 (swift-6.2.4-RELEASE,
x86_64-unknown-linux-gnu), in the `swift:6.2-noble` image in the container. The XCTest line "Executed 0 tests" is the
empty XCTest bundle; all tests are Swift Testing.

### Mutation check (each key rule broken briefly, then restored)
Every mutant below turned the suite red, except one equivalent mutant:

| Mutant | Result |
|---|---|
| Rule 3 prefix test changed from `hasPrefix` to `contains` (a camelCase-style match, N-1) | killed (N-1 near-miss and subset-only tests) |
| Rule 3 subset widened with `URLSessionWebSocketTask` | killed |
| Rule 4 regex not anchored to the whole literal (T-30) | killed (`tend.ai.key` reported) |
| Rule 4 `https://` hosts allowed outside the allowlist | killed |
| Rule 5 exception applied with the flag off | killed |
| Rule 6 write APIs allowed in every `TendEval` file | killed |
| Rule 1 imports widened with `Security` | killed |
| Rule 2 media check removed, or applied to the speech files too | killed (both) |
| Invalid regex fails open (`return []`) | killed |
| Canonical JSON keys sorted by UTF-16 | killed |
| Canonical JSON duplicate-key check removed | killed |
| Name folding strips an article without the following space | killed |
| Name folding skips the quote map | killed |
| Banned-token split keeps digits inside a token | killed |
| Keywords strip the leading article | **survived: an equivalent mutant.** All five articles (the, a, an, my, our) are stop words, so stripping one cannot change the keywords. |

**Round 2 (review R1-F1, R1-F2).** The Reviewer's mutation run found that deleting a list entry, or widening an import
or host set, left the suite green, because the round 1 plants were generated from the engine's own lists. I reran each
of those mutants one at a time against the round 2 tests, with mtime-safe restores and a clean baseline afterwards
(48 tests green). **All are now killed:**

| Mutant (in `IngestionSourceRules.swift`) | Result | Killed by |
|---|---|---|
| Delete media entry `AVAudioBuffer`, `AVAudioFile`, `CVPixelBuffer`, `CVImageBuffer`, `CIImage`, `UIImage`, `CMSampleBuffer`, or `NSImage` (8 mutants) | killed (each) | media pin + hand-written media plants |
| Delete write entry `OutputStream` or `NSUbiquitousKeyValueStore` (2) | killed (each) | write/log pin + hand-written write plants |
| Delete log entry `debugPrint(`, `dump(` or `os_signpost(` (3) | killed (each) | write/log pin + hand-written log plants |
| Rule 2 imports widened with `AVFoundation` | killed | import pin + import plants |
| Rule 3 imports widened with `Network` | killed | import pin + import plants (exact `import` check) |
| Rule 4 hosts widened with `api.example.org` | killed | host pin + host plants |
| Delete `FoundationNetworking` from the added names (near-equivalent) | killed | networking pin + networking plants |
| Delete `URLSessionConfiguration` from the added names (near-equivalent) | killed | networking pin + networking plants |
| `contentsOf:` no longer a networking pattern (R1-F1 reverted) | killed | R1-F1 negative tests |
| `append` / `insert` exemption dropped | killed | R1-F1 positive test, Rule 1 positive |

The review's prose says 17 survivors, but it lists 16 that are not equivalent (8 media, 2 write, 3 log, 2 import sets,
1 host set). I ran all 16, the 2 near-equivalent ones it names, and 2 new R1-F1 mutants: 20 in total, 20 killed.

One process note: my first batch restored files with an old mtime, so SwiftPM reused mutated objects in a few later
runs. I fixed the helper (it now touches the restored file), reran every affected mutant on its own, and confirmed a
clean green baseline afterwards. The table above is from the clean reruns.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendSourceScan: 48 tests, 385 cases, 0 warnings (round 2) | ✔ container | — | — | — | Linux CI runs it after HM-1 merges. The Gatekeeper should confirm the log shows "48 tests". |
| TendIngestion: 17 tests, 72 cases, 0 warnings, including the AC-M2-09 repository scan (round 2) | ✔ container | — | — | — | Linux CI after HM-1 (confirm "17 tests" and the "4 files scanned" line). |
| TendCore regression: 127 tests | ✔ container | — | — | — | — |
| Folding and canonical JSON on Darwin Foundation (R-10) | — | — | — | — | Not verified. No Mac here. Plan B2 (MS-2) reruns `TendIngestion` on the Mac. The Linux pins (`ß` gives `ss`, fullwidth to ASCII, decomposed accents) must hold there. |
| AC-M2-09 over `TendAI` and `TendEval` | — | — | — | — | The roots do not exist yet. WI-M2-M1 creates them and switches them to `required`. Final evidence is in WI-M2-M8. |

Device ACs: none in this item.

### Things the reviewer should look at closely
- **The rule engine** (`IngestionSourceRules.swift`, risk R-16), especially:
  - D1 (which AC-M1-23 entries count as networking patterns);
  - D3 (where bare hosts may appear);
  - Rule 3's handling of call-form hits: `URL(string:`, `Host(`, `Stream(`, `Host.current` and imports are never
    "in the subset", even though `URL` and `URLSession` are.
- **The fail-closed regex** in `SourceScanner.matches`. The one `.isEmpty` check (the `using:` label in
  `randomCallHits`) would fail open on a bad pattern. It is covered by the "every pattern compiles" test.
- **Two lexer copies.** The M1 test copy is unchanged, and `TendSourceScan` holds the moved one. A fix to either must be
  made in both until the R-16 chore.
- **Linux pins in `TextPrimitivesTests`** that may differ on Darwin (R-10): `ß` and the fullwidth cases. A Mac
  difference is a defect, not a skip.
- **`BannedTokens.all` lives in shipped `Sources`.** This is why there is no AC-M1-02-style vocabulary scan of
  `TendIngestion/Sources`: it would flag the list itself. WI-M2-04 should decide how AC-M2-12's "every outcome and
  reason name contains no banned token" is scanned, for example with a vocabulary scan that exempts exactly the one
  list declaration.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Q-D1, `AVURLAsset` (corrected in round 2, review R1-F4): it is not caught by the `AVAsset` entry, because the substring is not present. (a) Rule 6 bans no media types in `TendEval`, so this is not a gap there: `AVAsset` itself is allowed in `TendEval`. The AC-M2-09 Reviewer clause (no audio persisted) is protected by the Rule 6 write confinement and by the AC-M2-28 results-file type. (b) In Rules 1–3, `AVURLAsset` needs `AVFoundation`, which the import lists ban. `AVFAudio` does not declare `AVAsset` types. No scanner change in this PR. | Nit (optional PO note: add `AVURLAsset`, or a Rule 6 import list, see R1-F5) | Q-D1 (non-blocking) |
| R1-F5: the brief's closed lists have gaps. `write(toFile:`, `fopen(`/`fwrite(` and `import Darwin` in `TendEval` (Rule 6 has no import list), and inferred task types (`uploadTask(`, `webSocketTask(` …) are not caught. The scanner follows the lists as written. | Minor (PO/Tester question) | R1-F5, before WI-M2-M4 and WI-M2-M7 |
| R1-F6: bare allowed hosts may appear in any `TendIngestion` file | Minor | WI-M2-10 names the provider-table file |
| D3: no provider-table file is named, so any `TendIngestion` file may hold a bare allowed host | Minor | Open question Q-D2 (Planner/Tester; WI-M2-10) |
| The AC-M1-02 vocabulary scan is not applied to `TendIngestion/Sources` (the banned list must live there) | Minor | WI-M2-04 |
| The lexer exists twice (M1 test copy and `TendSourceScan`) | Minor | R-16 chore |
| The M1 lexer limits carry over: regex literals are lexed as code; `let d: Date = .init()` is not caught (M1 known limit (f)) | Nit | Inherited (M1) |
| CLAUDE.md §7 does not list the new commands yet. It is a protected path, so the owner adds them (the plan's "Exact commands" has them). | Nit | Owner / Documenter |
| Not verified on Darwin (R-10) | — | Plan B2, MS-2 |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection API. `TendCore` and `NowSelector` are unchanged. |
| UX-3 Zero-Guilt | pass | The banned-token matcher is built and tested as the brief defines it. No identifier or string in the new code uses a banned word, apart from the list itself (by design). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | No inference here. Rule 5 bans `SFSpeech*` (the server-capable recogniser), with the T-27 exception off. |
| P-2 No data leaves device (except user iCloud) | pass | No dependency was added. `TendIngestion` has no networking (Rule 1 scan, 0 violations). Rules 2 and 3 confine networking to the three allowlisted files and to the T-23 subset. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Rule 4 limits hosts to the three ADR-0005 providers: bare hosts only in `TendIngestion`, `https://` only in the allowlisted files. Canonical JSON makes the AC-M2-20 byte checks possible. |
| P-4 Media not persisted without consent | pass | Rules 1–3 ban write and log APIs in `TendIngestion` and `TendAI`, and media types outside the speech files. Rule 6 confines `TendEval` writes to the results writer. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Work Planner | Developer (via Orchestrator) | accepted (H2) | WI-M2-01 Ready (`m2/ingestion-foundation`). M1 `ACCEPTED`. The O-1 `IN-BUILD` change is waiting for the owner's merge, and the PR will not merge before it (or before HM-1). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first. TendSourceScan: 33 tests / 365 cases. TendIngestion: 17 tests / 70 cases. TendCore: 127 tests, unchanged. All green, 0 warnings, on Linux Swift 6.2.4. Mutation-checked (15 mutants killed, 1 equivalent mutant). ADR-0006 Proposed. Open questions: Q-D1 (`AVURLAsset` / Rule 6 imports) and Q-D2 (provider-table file). D1–D3 flagged for the Tester. Not verified on Darwin (B2). Pushed; no PR opened. |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned (round 1: CHANGES REQUIRED) | [review-WI-M2-01.md](review-WI-M2-01.md), copied unchanged into this branch. R1-F1 and R1-F2 Major; R1-F3 and R1-F4 Minor; R1-F5 is a PO/Tester ticket; R1-F6 goes to WI-M2-10; R1-F7 Nit. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 2) | R1-F1 fixed: `contentsOf:` is a networking pattern in Rules 2, 3 and 6 (only `append`/`insert` exempt), with negatives in 8 locations and positives in each rule. `rule6Positive` is rewritten. D1, the header comment and the ADR-0006 P-2 line are corrected. R1-F2 fixed: `BriefPinTests` pins every closed list to literal brief text, with hand-written plants per entry; the reviewer's 16 non-equivalent survivors, its 2 near-equivalent ones and 2 new R1-F1 mutants are all killed. R1-F3 comment and R1-F4 Q-D1 row corrected. R1-F7: the case is pinned (`"x \u{301} y"` → `"x y"`) and D8 softened, and the order is flagged to the PO and Tester. TendSourceScan 48 tests / 385 cases and TendIngestion 17 / 72, green, 0 warnings. TendCore unchanged, so not rerun. |
