# M2 Developer Handoff — WI-M2-01, WI-M2-02, WI-M2-03

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
     closed list without the PO decision that AC-M1-23 / Q23 require. It is reverted.
   - **Round 3: the PO has answered both review questions (PR #16, merged into main and then into this branch).**
     - **M2 Q24** (the Reviewer's R1-F5 gaps): stricter lists, built in this round. The session-method calls, the
       method references and the `bytes(for:` + `delegate:` rule are now networking patterns. `write(toFile:`,
       `AppStorage`, `SceneStorage`, `archiveRootObject(` and the C calls are on the write and log lists. The exact
       call-pattern rule applies, `contentsOf:` is banned in Rules 2, 3 and 6 by the brief's own words, and Rule 6
       has a closed import list.
     - **M2 Q23** (R1-F1(4)): one named fixtures-loader file
       (`Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift`) may use `Data(contentsOf:` under the brief's
       conditions. Per the plan, **WI-M2-01 stays strict** and the exception comes in a scanner follow-up that merges
       before WI-M2-M7 is reviewed. Until then `Data(contentsOf:` is a hit in every `TendEval` file, including the
       loader file (test "the fixtures-loader file has no exception …"). The brief's "Caught in the fixtures-loader
       file" plants and its loader positive are left for that follow-up, because they only make sense with the
       exception's own rules (the whole token `URL`, the `Bundle` uses, the literal-argument checks).
     - `Apps/TendEval/Sources` does not exist yet, so nothing breaks.
   - Tests: "(R1-F1) negative: Data(contentsOf:, String(contentsOf:, .init(contentsOf: … are caught in every module
     and file kind" and "(R1-F1) positive: append(contentsOf:) and insert(contentsOf:at:) pass in Rules 1, 2, 3 and 6".
2. **D2: media types and the write/log type names match as a substring of an identifier.**
   - A substring match is strictly stronger than the camelCase split, so `AVAssetReader`, `AppLogger` and `OSLogType`
     are hits.
   - Round 3: M2 Q24 says the type-name patterns "keep the AC-M1-23 camelCase word-boundary rule" and that it
     "relaxes none of them". Every camelCase word-boundary hit is also a substring hit, because consecutive camelCase
     words are a contiguous substring. So the substring match keeps that rule and adds to it; it relaxes nothing. For
     the Reviewer: if the PO wants the exact camelCase rule rather than the superset, that is a one-line change.
   - Calls follow the M2 Q24 call-pattern rule (D10).
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
   every other `TendEval` file. (Round 3: Rule 6 now also has the closed M2 Q24 import list; see D10.)
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
10. **D10: the M2 Q24 call-pattern rule** (round 3), applied to every write, log and session-method call:
    - The regex is `(?<![\p{L}\p{N}_])name\s*\(` plus `\s*label\s*:` when the pattern has a first label. It runs
      on the lexed code with comments and string text blanked and backticks removed. `\s` includes newlines, and it
      is case-sensitive.
    - So `Swift.print(`, `` `print`(x) ``, `print\n(x)` and `d.write(\n to: u)` are hits. `inputs(`, `snprintf(`,
      `metadata(for:`, `reprint(` and `data(forKey:` are not.
    - I also allow whitespace between the label and `:`. That is stricter, not looser.
    - Method references: `dataTask`, `uploadTask`, `downloadTask`, `streamTask` and `webSocketTask` are hits as whole
      identifier tokens (`let f = s.dataTask`). `dataTaskCount` and `DataTask` are not.
    - **Rule 3 streaming read.** The only allowed session-method call is `bytes(for:` when the label `delegate:`
      appears at the **top level** of its own argument list. Brackets nested inside the argument list are blanked
      before the check, so `bytes(for: make(delegate: d))` is a hit. I read "checked like AC-M1-23's `using:` rule" as
      the call's own arguments. This is stricter than a check over the whole text, and it is tested. `delegatee:` is
      not `delegate:`.
    - **Rule 6 imports.** `IngestionSourceRules.importedModule(of:)` skips one kind keyword (`typealias`, `struct`,
      `class`, `enum`, `protocol`, `let`, `var`, `func`), then takes the first path component (`import struct
      Darwin.C` → `Darwin`, `import os.log` → `os`). Attributes come before `import`, so they are ignored, and
      `@_exported` / `@_implementationOnly` imports count. Rules 1–3 keep the stricter M1 form, where the whole target
      must be a listed module (`import struct Foundation.Date` is a hit there).

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-09 (scan) | `TendIngestionTests` › "AC-M2-09: Rules 1–6 hold over every .swift file in the three module Sources (file counts logged per module)" | PASS on Linux. Log: `TendIngestion (required) Packages/TendIngestion/Sources: 4 files scanned`; `TendAI (optional) …: not present`; `TendEval (optional) …: not present`; `4 files in total, 0 violations`. **Partial:** two roots do not exist yet. The evidence for the AC is the WI-M2-M8 run with all three roots required. |
| AC-M2-09 (negative, one planted hit per rule) | `TendSourceScanTests` › "AC-M2-09 negative: every planted hit is caught by its rule" (171 cases over Rules 1–6), "AC-M2-09 coverage: the planted fixtures exercise every entry…", and `TendIngestionTests` › "AC-M2-09 negative (driver): one planted hit per rule…" | PASS |
| AC-M2-09 closed lists pinned to the brief (round 2, R1-F2) | `TendSourceScanTests` › `BriefPinTests`. The pins compare the engine with a literal copy of the brief text for: the networking names and imports, the AC-M1-23 networking names, call names and `contentsOf:` exemptions, the media types, the write and log APIs (and their write/log split), the Rule 1/2/3 imports, the hosts, the host-like regex (string equality) and the T-27 forms. There are hand-written plants per entry for media (Rules 1–3), write (Rules 1–3 and 6), log (Rules 1–3, 6 and the results writer), networking (Rules 1, 2 and 6, and Rule 3 outside the subset), imports and hosts. | PASS |
| AC-M2-09 M2 Q24 (round 3) | `TendSourceScanTests` › `Q24RulesTests`. It covers: the M2 Q24 list plants, each caught on its own in TendIngestion (37 parameterised cases, every session-method call, `write(toFile:`, `AppStorage`, `SceneStorage`, `archiveRootObject(` and each C call), plus a coverage check; `import Darwin` and `fwrite(` in TendEval; `@AppStorage` in TendEval; Rule 3 `uploadTask(`, `webSocketTask(`, `bytes(for:` without `delegate:`, `s.dataTask`, a misspelled `delegatee:` and a nested `delegate:`, in all 3 allowlisted files; the exact Rule 3 positive; `Data(contentsOf: u)` in TendAI outside the allowlist, in an allowlisted file and in TendEval; the loader file strict until Q23; the Rule 6 imports (17 forms caught, 6 listed modules pass); import parsing; the call-pattern matches and near-misses. `BriefPinTests` now also pins the session-method calls, the method references, the separate Write and Log lists, the Rule 6 imports and the brief's positives, and adds hand-written plants for every new entry. | PASS |
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
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` (round 3, M2 Q24) | `✔ Test run with 63 tests in 4 suites passed after 2.269 seconds.` | 63 tests, 529 cases (round 2: 48 / 385; round 1: 33 / 365) | ~2 s (plus the build) |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` (round 3) | `✔ Test run with 17 tests in 3 suites passed after 0.155 seconds.` The scan log is unchanged: 4 files, 0 violations. | 17 tests, 72 cases (unchanged since round 2) | ~0.2 s |
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

**Round 3 (M2 Q24).** Each mutant was applied alone and restored with a touch; the clean baseline afterwards was 63 tests
green. **All 17 are killed:**

| Mutant | Killed by |
|---|---|
| Delete session call `download(resumeFrom:`; delete `data(for:` | Q24 list plants, Q24 coverage, pin |
| Rule 3 allows `bytes(for:` without `delegate:` (compiling variant; my first variant failed to build, so it proved nothing and was rerun) | Rule 3 session-method plants, networking plants |
| `delegate:` counted at any depth | the nested-`delegate:` plant |
| Backticks not removed before call matching | call-pattern match test |
| Method references off | Rule 3 `s.dataTask` plant, call-pattern test |
| Call pattern left boundary dropped | brief positives, near-miss test |
| Label matched as a prefix (`data(for` matches `data(forKey:`) | brief positives, near-miss test |
| Rule 6 imports widened with `Darwin`; the Rule 6 import check removed | Rule 6 import tests, `import Darwin` test |
| `importedModule` ignores the kind keyword | Rule 6 positive, import parsing |
| Delete `creat(`, `AppStorage`, `write(toFile:`, `syslog(` | Q24 plants, pins, hand-written plants |
| A loader-file `contentsOf:` exception leaks in early (M2 Q23 not approved for this item) | the loader-file strictness test |

One process note: my first batch restored files with an old mtime, so SwiftPM reused mutated objects in a few later
runs. I fixed the helper (it now touches the restored file), reran every affected mutant on its own, and confirmed a
clean green baseline afterwards. The table above is from the clean reruns.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendSourceScan: 63 tests, 529 cases, 0 warnings (round 3) | ✔ container | — | — | — | Linux CI runs it after HM-1 merges. The Gatekeeper should confirm the log shows "63 tests". |
| TendIngestion: 17 tests, 72 cases, 0 warnings, including the AC-M2-09 repository scan (round 3) | ✔ container | — | — | — | Linux CI after HM-1 (confirm "17 tests" and the "4 files scanned" line). |
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
| Q-D1, `AVURLAsset` (corrected in round 2, review R1-F4; round 3: Rule 6 now has a closed import list (M2 Q24), so `AVFoundation` is a hit in `TendEval` too): it is not caught by the `AVAsset` entry, because the substring is not present. (a) Rule 6 bans no media types in `TendEval`, so this is not a gap there: `AVAsset` itself is allowed in `TendEval`. The AC-M2-09 Reviewer clause (no audio persisted) is protected by the Rule 6 write confinement and by the AC-M2-28 results-file type. (b) In Rules 1–3, `AVURLAsset` needs `AVFoundation`, which the import lists ban. `AVFAudio` does not declare `AVAsset` types. No scanner change in this PR. | Nit (optional PO note: add `AVURLAsset`, or a Rule 6 import list, see R1-F5) | Q-D1 (non-blocking) |
| R1-F5: the brief's closed lists had gaps. **Closed in round 3 by M2 Q24**, built and tested here. | — | Done (M2 Q24) |
| M2 Q23, the fixtures-loader exception: not built in WI-M2-01. The brief's loader-file plants and the loader positive come with it. | Planned | Scanner follow-up, merged before WI-M2-M7 is reviewed (plan) |
| Developer constraint (plan, M2 Q24): no source method in the three modules may share a name and first label with a session-method call (`data(for:` …). `CanonicalJSONWriter.data(_:)` has the first label `_`, so it does not collide. | — | Every later item |
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
| 2026-11-21 | Orchestrator | Developer | accepted | PR #16 merged into main (PO decisions M2 Q23 and Q24, stricter only). Build Q24 in WI-M2-01; leave Q23 out. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 3) | `origin/main` merged into the branch (no rebase). M2 Q24 built in full: session-method calls and method references, the `bytes(for:` + top-level `delegate:` rule in Rule 3, the Write and Log lists, the exact call-pattern rule (backticks, whitespace, left boundary, case), `contentsOf:` in Rules 2, 3 and 6, and the closed Rule 6 import list with import parsing. Every brief Q24 plant and positive is tested, the pins extend to the new lists, and 17 Q24 mutants are killed. M2 Q23 is not built (plan); the loader file stays strict and is tested. D1 updated, D2 clarified, D10 added. TendSourceScan 63 tests / 529 cases and TendIngestion 17 / 72, green, 0 warnings. |

---

## WI-M2-02 — non-finite window dates become a model invariant (AC-M2-02 W2-F3 clause, Q9, T-21, R-c)

### What changed
- **`TendCore` model.** `TaskInvariantViolation` gains one case, `windowDateNotFinite`, with no associated value. The
  name, doc comment and position come from the iOS Designer ([design.md Addendum A](design.md), 2026-11-21). It sits
  after `noAllowedWeekdays` and before `windowEndNotAfterStart`. `HouseholdTask.firstInvariantViolation()` checks it
  in that position. NaN makes `windowEnd > windowStart` false, so without this order a NaN window would report
  `windowEndNotAfterStart`. Construction and `init(from:)` share the check, so both throw it.
- **`InMemoryHouseholdRepository`.** `save` and `upsertTask` now check every task against the model invariants and
  throw `HouseholdStoreError.invalidTask(firstViolation)`, storing nothing. A public caller cannot build such a task
  any more. The check guards against engine code in `TendCore` that sets a field through an `internal(set)` setter.
  This closes W2-F3: before, the in-memory store accepted a `±.infinity` date.
- **`JSONFileHouseholdRepository`.** No code change. What it does with non-finite dates is now pinned by tests (see
  below).
- **Foundation-only.** No new import. The source scans (AC-M1-02, AC-M1-23) still pass.

### What Foundation does with non-finite dates (Linux, Swift 6.2, pinned)
Probed first with a scratch program, then pinned in `NonFiniteDateInvariantTests`:
- `JSONEncoder` (the repository's settings: `.deferredToDate`, default `.throw` non-conforming float strategy) throws
  `EncodingError.invalidValue` for a NaN, `+inf` or `-inf` date. It writes no bytes.
- `JSONDecoder` with the repository's settings cannot produce a non-finite date from any file:
  - The bare tokens `NaN`, `nan`, `Infinity`, `-Infinity` and `inf` throw `DecodingError.dataCorrupted` ("not valid
    JSON").
  - The overflowing numbers `1e309`, `1e400` and `-1e400` also throw `DecodingError.dataCorrupted`. They do not round
    to infinity.
  - The strings `"NaN"`, `"Infinity"` and `"-Infinity"` throw `DecodingError.typeMismatch`.
  - `1.7976931348623157e308` (the largest finite double) reads back exactly.
- So a hand-written file with a non-finite window date is rejected by the file store with **`unreadableFile`**. That is a
  typed error, as in AC-M1-06. The file is left byte-for-byte unchanged, and every operation that reads it throws.
- A non-finite value reaches the model's own decode check only through a lenient decoder
  (`.convertFromString(...)`). No repository uses one. The tests use one to prove that decode throws
  `windowDateNotFinite` for both a task and a household.

### AC coverage
| AC / item | Test(s) | Result (Linux) |
|---|---|---|
| AC-M2-02 (W2-F3): construction throws | `NonFiniteDateInvariantTests` "constructing a task with a non-finite windowStart or windowEnd throws windowDateNotFinite" (6 cases: NaN, +inf, -inf × start, end); "both window dates non-finite" (9 cases); `InvariantTests` "constructing a task that violates an invariant…" (6 new rows) | PASS |
| AC-M2-02 (Q9 position) | "windowDateNotFinite sits after noAllowedWeekdays and before windowEndNotAfterStart"; "the finiteness check runs before the window-order check and after the weekday check" (6 cases); `ZeroGuiltModelTests` "AC-M1-25 / AC-M2-02 naming…" (exact ordered list) | PASS |
| AC-M2-02 (W2-F3): boundary | "the most extreme finite dates are accepted" (±`greatestFiniteMagnitude`, `distantPast`/`distantFuture`, `nextUp`; round-trips through the ADR-0004 format) | PASS |
| AC-M2-02 (W2-F3): decode throws the typed violation | "a task or household that decodes to a non-finite window date throws windowDateNotFinite" (6 cases); `InvariantTests` "decoding JSON that violates an invariant…" (new row) | PASS |
| AC-M2-02 (W2-F3): JSON file store rejects a hand-written file | "a hand-written file with a non-finite window date is rejected with a typed error and left unchanged" (22 cases: 11 tokens × start, end; AC-M1-06 harness: load, upsert, remove, update room, reopen; bytes unchanged); `FileRepositoryLoadErrorTests` "a file containing a task that violates an invariant…" (new row, `unreadableFile`) | PASS |
| AC-M2-02 (W2-F3): JSON file store refuses to save one | "the file repository refuses to save a task carrying a non-finite date and keeps the stored file" (6 cases; `writeUnsuccessful`, file unchanged) | PASS |
| AC-M2-02 (W2-F3): in-memory store rejects one | "the in-memory repository rejects a task carrying a non-finite date with invalidTask(windowDateNotFinite)…" (6 cases: save, upsert new, upsert replacing; contents unchanged); "…still accepts valid tasks after a rejection" | PASS |
| Pins | "JSONEncoder … refuses a non-finite date" (6); "JSONDecoder cannot read a hand-written non-finite date token" (11); "the largest finite JSON number reads back…"; "the file repository's strict decoder reads a string-spelled non-finite date as unreadableFile" (6) | PASS |
| AC-M1-25, AC-M1-06, AC-M1-07 (unchanged, still green) | All M1 suites | PASS |

**Full suite:** `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` gave
"✔ Test run with 141 tests in 18 suites passed after 129.112 seconds." A rerun on the final tree, after the mutation checks, gave "141 tests in 18 suites passed after 125.803 seconds." There were 0 failures and 0 warnings. Before
this change it was 127 tests in 17 suites. This adds 14 tests and 1 suite, and new rows in existing parameterised
tests.

**Mutation checks (local, then reverted):**
- With the finiteness check returning `windowEndNotAfterStart`, the run was red: "38 tests in 5 suites failed … with
  90 issues".
- With the in-memory guard disabled, the run was red: "14 tests in 1 suite failed … with 26 issues".

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| Full TendCore suite, `-warnings-as-errors` (Swift 6.2, `swift:6.2-noble` Docker) | ✔ 141/141 | — | n.a. | n.a. | macOS CI runs on the PR |
| JSON non-finite pins | ✔ (exact error kinds under `#if os(Linux)`) | — | n.a. | n.a. | Darwin Foundation: only "throws a `DecodingError`" is asserted there. The exact kind is not verified on Darwin. |
| Mutation checks | ✔ | — | n.a. | n.a. | — |

### Things the reviewer should look at closely (T-21: M1 test edits)
I changed these M1 tests. No M1 assertion was removed. Please confirm each change is an extension.
1. `InvariantTests.casesCoverEveryInvariant`: the count went from `== 9` to `== 10`, and the test name now says ten
   (nine M1 cases + one). The set-equality assertion is unchanged. Six construction rows were added.
2. `ZeroGuiltModelTests.invariantViolationCases`: the exact ordered list now has `.windowDateNotFinite` in third
   place. The nine M1 cases keep their relative order. The test name was updated.
3. `InvariantTests.violatingJSON` / `decodeThrows`: a new switch arm (the switch must stay exhaustive). Only that
   row uses a lenient decoder; the nine M1 rows still use the default `JSONDecoder()`. `Fixtures.decode` gained a
   `using:` parameter that defaults to the old behaviour.
4. `FileRepositoryLoadErrorTests.invariantCases` / `invariantCoverage`: the nine M1 cases still expect
   `invalidTask(violation)`. The new row expects `unreadableFile`, because strict JSON cannot carry the value. The
   coverage test still asserts all nine M1 cases as `invalidTask`. It also asserts that the non-finite row exists
   and expects `unreadableFile`.
5. `FileRepositoryAtomicSaveTests.encodingFailureKeepsPreviousHousehold` (AC-M1-07): a public caller can no longer
   build a `-.infinity` task. So the test now builds a valid task and sets `windowStart`/`windowEnd` through the
   `@testable` internal setters, to the same values as before. The assertion (`writeUnsuccessful`, bytes of A
   unchanged, A reloads) is unchanged.

Also check the in-memory write-path guard. It checks **all** invariants, not only finiteness. That is a little more
than the work item asks, and it only matters for values made through internal setters.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The plan wording expects the file store to reject a non-finite file with `invalidTask(…)`. On Linux, strict JSON cannot carry a non-finite number, so the actual typed error is `unreadableFile`. That is still one of AC-M1-06's typed errors, and the brief only says "a typed error, as in AC-M1-06". `invalidTask(.windowDateNotFinite)` can come only from the model decode with a lenient decoder. | Question (PO/Planner) | Open question 1 |
| For a value built through an internal setter, the stores reject with different typed errors: in-memory gives `invalidTask(.windowDateNotFinite)`, the file store gives `writeUnsuccessful` (the encoder refuses; AC-M1-07 pins this). Making the file store check invariants before encoding would change the M1 AC-M1-07 assertion, so I did not do it. | Minor | Open question 2 |
| The file store's save does not check the other invariants for values built through internal setters. This was already true in M1 and is unchanged. | Minor | — |
| Exact Darwin `DecodingError` kinds are not verified. | Nit | macOS CI |

### Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | Selection unchanged. |
| UX-3 Zero-Guilt | pass | The case describes data, not conduct, and has no banned word or substring (Designer check; the AC-M1-02 source scan passes). No overdue state is added. A bad file fails calmly with a typed error and is never repaired or emptied. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI path. |
| P-2 No data leaves device | pass | No networking. TendCore is still Foundation-only (AC-M1-23 scan passes). |
| P-3 Cloud AI only opt-in | n.a. | — |
| P-4 Media not persisted | n.a. | — |

### Open questions
1. **PO / Planner:** is `unreadableFile` accepted as the file store's typed rejection of a hand-written non-finite
   file? Strict JSON cannot carry one. Or should the plan text ("with `HouseholdStoreError.invalidTask(…)`") be read
   as "with a typed `HouseholdStoreError`"?
2. **PO / Reviewer:** for values built through internal setters only, should the file store check invariants before
   encoding, so it reports `invalidTask` like the in-memory store? That needs a PO decision, because it changes the
   expected error in the M1 AC-M1-07 test.

### Handoff log
| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-21 | iOS Designer | Developer | accepted | Case name and position (design.md Addendum A). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent | Branch pushed, no PR opened (as instructed). Two open questions for PO/Planner. |

---

## WI-M2-03 — `TimeHint` and the Q6 time resolver

- **Owner:** Developer  ·  **Branch:** `m2/time-resolver`, stacked on `m2/ingestion-foundation` at `ce3ad5a` (PR #15,
  WI-M2-01). Round 2: `origin/m2/ingestion-foundation` (with PR #13, the CI job) merged in  ·  **PR:** #18  ·
  **Review:** [review-WI-M2-03.md](review-WI-M2-03.md) (round 1 CHANGES REQUIRED, copied unchanged from `656d740`)  ·  **ADRs:** none new. The item follows [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (it adds
  files under `Packages/TendIngestion/Sources/TendIngestion/` only).
- **Requirements:** FR-A1 (time fields of a draft). **Owns AC-M2-03.** It also provides Q5 step 5 (the time-hint
  window and the out-of-range rule) and step 6 (interval settlement) for WI-M2-05, which owns AC-M2-02. UX-3 (no
  overdue-style helper, calm case names).
- **Inputs:**
  - [brief.md](brief.md): AC-M2-03, Q5 (steps 5 and 6), Q6 with the settled points (a)–(f), T-08.
  - [plan.md](plan.md): the WI-M2-03 row (DoR ticked: Tester review of the Q6 table APPROVED 2026-11-21; PO
    acknowledged P1–P7 with the P3 change) and the "Q6 time-phrase table": the hint, the notation, T1–T15, R1–R7,
    "How the hint meets Q5" and E1–E21. Round 2: the plan at `65e3665`, with the PO answers to Q-T1 and Q-T2
    (2026-11-21): the R5 row, the note under the repeat table, the "invalid anchor is no anchor" bullet, E22–E26.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, so M2 build work is unlocked (CLAUDE.md §5). As for WI-M2-01,
  the O-1 change of M2 to `IN-BUILD` waits for the owner's merge.

### What changed
- `Packages/TendIngestion/Sources/TendIngestion/Time/TimeHint.swift` (new): the neutral `TimeHint` (anchor,
  daypart, weekday, month, season, count, repeatEvery, repeatUnit), with `Anchor` (the plan's 12 values plus
  `unrecognized`), `Season` (`startMonth`: Mar, Jun, Sep, Dec; Q6(c)) and `RepeatUnit` (`days`: 1, 7, 30, 365; Q6, P6).
- `Packages/TendIngestion/Sources/TendIngestion/Time/TimeResolver.swift` (new):
  - `TimeResolver(calendar:timeZone:)` and `resolve(_ hint: TimeHint?, now:) -> TimeResolution`. The time zone
    argument wins over the calendar's own, as in M1. `now`, the calendar and the time zone are all injected. The code
    never reads the clock or the device's calendar, time zone or locale.
  - `TimeResolution`: window start and end, dayparts and weekdays (empty means ∅, filled by Q5 step 3), the raw
    interval, and a `basis` (`hint`, `noHint` or `fallback(reason)`) so that WI-M2-05 can count repairs per rule
    (AC-M2-02 evidence).
  - `RecurrenceSettlement.settle(kind:intervalDays:)`: Q5 step 6 (recurring keeps 1…730, otherwise it becomes a
    one-off with no interval; one-off and restock never keep an interval). It is here so that E14 can be tested in
    this item. WI-M2-05 calls it.
  - Round 2: `RecurrenceSettlement.settle(kind:resolution:)` returns `Settled` (kind, interval, dayparts, weekdays,
    plus `effectiveDayparts` / `effectiveWeekdays` with the Q5 step 3 defaults), so E26 is tested here.
    `TimeResolution.weekdaysFollowRepeat` is new. `TimeHint.Anchor.modelChoices` lists the 12 values a model may send
    (without `unrecognized`) for the schema work in WI-M2-10/12 (review R1-N1).
- `Packages/TendIngestion/Tests/TendIngestionTests/TimeResolverTests.swift` (new, written before the code; the first
  build failed with "cannot find type 'TimeResolver' in scope").
- Not changed: `Packages/TendCore`, `Packages/TendSourceScan`, every protected path and every dependency.

### Decisions the Reviewer and Tester should know (technical readings; flagged where they touch product meaning)
1. **DT1 (round 2, PO Q-T2): an invalid anchor counts as no anchor; the rest of the hint still counts.** The window
   is the T1 window and weekdays are ∅, but a valid daypart still gives {p} (as T15) and a valid repeat still gives
   its interval (R1–R4). R5's {W} cannot apply without a valid weekday. `basis` still records the reason. So a
   recurring "every week" item whose weekday was lost stays recurring (E22). Round 1 dropped the whole hint; the PO
   chose the other reading (review R1-F1).
2. **DT2 (round 2, PO Q-T1): R5 sets weekdays {W} with a week, month or year repeat.** A day repeat ("daily from
   Thursday") keeps ∅ (E24), and so does a one-off T7. `TimeResolution.weekdaysFollowRepeat` marks R5's {W}, and
   `RecurrenceSettlement.settle(kind:resolution:)` drops it together with the interval when Q5 step 6 drops the
   interval, so weekdays become ∅, which is all seven after Q5 step 3 (E26). T9's {saturday, sunday} is not tied to
   the repeat and stays. Round 1 set {W} only for a week repeat (review R1-F2, R1-F3).
3. **DT3: interval overflow.** `repeatEvery × unit days` is computed with an overflow check. A product that does not
   fit in `Int` gives no interval, so step 6 makes a recurring item a one-off, the same result as any value above 730.
   The resolver never traps.
4. **DT4: unknown values.** An unknown anchor is the case `Anchor.unrecognized`, which keeps the anchor non-optional
   and avoids an `Optional.none` / `Anchor.none` ambiguity. Unknown daypart, weekday, season and repeat unit values,
   and non-integer numbers, are `nil` in the neutral type. The provider parsers (WI-M2-12) and the on-device mapping
   do that mapping (plan). An unknown season therefore reads as "season absent" (`requiredFieldAbsent`).
5. **DT5: the M1 slot rules are re-stated in `TendIngestion`.** `SlotCalendar` and `Daypart.startHour` are internal
   to `TendCore`, and this item does not change `TendCore`. The resolver uses the same method: local-noon day
   arithmetic, `date(bySettingHour:…, matchingPolicy: .nextTime, repeatedTimePolicy: .first)`, and the same hours. The
   test "AC-M2-03 oracle: T6 slot(p, D+1) starts and ends where M1's slot for {p} does" checks 1,400 cases over 7
   zones against M1's public `HouseholdTask.nextEligibleWindow`. So a drift between the two copies turns the suite red.
   Round 2 (review R1-F4): `endHour` is derived from the next daypart's `startHour` (night: the morning start on the
   next day), as M1 does, and the oracle now checks slot ends too: from `end − 1 ms` M1 returns the anchor itself, and
   from `end` it returns a later start.
6. **DT6: T3 is applied literally.** "Today" + a daypart uses the slots of `D`, the calendar day of `now`. So "today"
   + night said at 01:00 gives tonight's slot `[22:00, 05:00 next day)`, not the night already in progress. This is
   the table as written. I note it for the Tester; it is not a question.
7. **DT7: the Sunday 18:00 rule reads the local hour of `now`.** `hour >= 18` on a Sunday (the weekday of `D`). So
   17:59:59.5 is "before 18:00" (tested), and 18:00:00 is "at or after". No instant comparison is used, so a zone
   where 18:00 does not exist still behaves like a wall clock.
8. **DT8: the range rule.** `now ≤ start ≤ now + 366 d` and `start < end ≤ start + 366 d`, with 366 d = 31,622,400 s.
   Exactly 366 days is kept (tests at the boundary ±1 ms, and T12/T13 "before March" said at 00:00 on 1 Mar 2027,
   whose window is exactly 366 days because of the leap February). A start later than `now + 366 d` falls back
   (`inDays` 366 at night). An empty window is `emptyWindow`. Both fall back to T1.
9. **DT9: a non-finite `now`** never traps. It is checked first, before the `nil`-hint check (round 2, review R1-F5),
   so with or without a hint the result is the plain T1 fallback (∅, ∅, no interval) with reason
   `calendarUnresolved`, and its dates are non-finite too. The Q9 invariant (AC-M2-02) rejects such a window with a
   typed skip. WI-M2-05 must not pass a non-finite `now`; the pipeline's clock is injected and finite.
10. **DT10: names.** No type, case or member name contains a banned token (test "UX-3: no basis or reason name …"),
    and there is no overdue-style or "past-due" helper (plan law check watch item).

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-03 worked examples | "AC-M2-03: worked examples E1–E13 and E15–E25 equal the plan's table exactly (America/New_York)" (24 cases: window start and end, dayparts, weekdays and interval each compared exactly; E22–E25 are the PO Q-T1/Q-T2 rows) | PASS (Linux) |
| AC-M2-03 E26 | "AC-M2-03 E26 (PO Q-T1): E23 settled as a one-off drops {thursday} with the interval; weekdays all seven" and "Q5 step 6 on a resolution: …" (6 cases) | PASS |
| AC-M2-03 E14 | "AC-M2-03: E14 (R3 / Q5 step 6): every 3 months → interval 90; every 25 months → one-off, no interval" | PASS |
| AC-M2-03 rows T1–T15 | "AC-M2-03: rows T1–T15 at fixed now values equal the table exactly" (58 cases: every row and every daypart branch, T3 at the slot end, T7 on the same weekday, T9 on Wed/Fri/Sat/Sun 17:59:59, 17:59:59.5 and 18:00:00 with and without dayparts, T10 on Mon/Wed/Sun before and at 18:00, T12/T13 in the current month or season, at 1 Dec 00:00:00 and at exactly 366 days, T14 at 1, 3, 366 days and 2, 52 weeks) | PASS |
| AC-M2-03 repeat rows R1–R7 | "AC-M2-03: repeat rows R1–R7 give the table's interval and weekdays" (28 cases, including R5 with month and year repeats, a day repeat on a weekday anchor, repeats on other anchors, `repeatEvery` 0 and −3, one field absent, and `Int.max` years) | PASS |
| AC-M2-03 invalid anchors (PO Q-T2) | "AC-M2-03 (PO Q-T2): an invalid anchor is no anchor (T1 window, weekdays ∅); a valid daypart and repeat still count" (17 cases, each with its typed reason, dayparts and interval) and "no hint at all …" | PASS |
| Non-finite `now` (R1-F5) | "AC-M2-03 (R1-F5): a non-finite now never traps … with or without a hint" (NaN, ±∞ × nil and two hints) | PASS |
| AC-M2-03 Q6(a) Monday week start | "AC-M2-03 Q6(a): … do not depend on the calendar's firstWeekday" (all 110 row, repeat and example cases rerun with `firstWeekday` 1…7) | PASS |
| AC-M2-03 Q6(e) DST and year boundary | E1, E2, E5, E12, E13, E17, E18 (New York), E6, E7, E11 (year boundary), plus "a DST change at local midnight (America/Santiago)" (8 cases, `mid(d)` at 01:00 −03 on 2026-09-06; a 25 h Saturday on 2027-04-03) and "a repeated and a missing local midnight (America/Havana)" (3 cases: on 2026-11-01 midnight occurs twice and the first occurrence is used, Q11). Each zone has a tzdata sanity test. | PASS |
| Q5 step 5 range rule | "AC-M2-03 / Q5 step 5: a window is in range iff …" (boundaries ±1 ms) | PASS |
| Q5 step 6 (for WI-M2-05) | "Q5 step 6: settlement of the interval against the final kind" (8 cases) | PASS |
| Invariants | "AC-M2-03 property: every resolution is a valid Q5 window, and deterministic (seeded)": seed `0x71E50A11CE000003`, 6,000 random hints over 7 zones (New York, Santiago, London, Lord Howe, Kolkata, Chatham, UTC), random `firstWeekday`, `now` over 2026–2028 with fractional seconds; 4,116 resolved from the hint, 1,884 fell back; on every case the interval and dayparts equal an independent oracle (R1–R4, T4, PO Q-T2), and on a fallback weekdays are ∅. "AC-M2-03 oracle: T6 slot(p, D+1) starts and ends where M1's slot for {p} does": seed `0x51070AC1E`, 1,400 cases. | PASS |
| UX-3 names | "UX-3: no basis or reason name of the resolver contains a banned token (AC-M1-02 list)" | PASS |
| R1-N1 | "R1-N1: the model is never offered the unrecognized anchor" | PASS |
| AC-M2-09 (regression) | "AC-M2-09: Rules 1–6 hold …": `TendIngestion (required) Packages/TendIngestion/Sources: 6 files scanned`, `6 files in total, 0 violations` | PASS |

The Tester's planned independent cases are covered by the design: Santiago with DST at midnight (the resolver's
`mid(d)` is the day's first instant, cross-checked with `startOfDay`), Sunday 17:59:59 and 18:00:00 for T9 and T10
(hour-based, DT7), and T12/T13 near the 366-day limit (exactly 366 days is kept; DT8).

### Test runs
| Command | Summary line | Tests / cases | Runtime |
|---|---|---|---|
| `swift build --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `Build complete!` | — | — |
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!` | — | — |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` (round 1) | `✔ Test run with 34 tests in 4 suites passed after 3.734 seconds.` | 34 tests (WI-M2-01: 17) | ~4 s |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` (round 2, after merging `origin/m2/ingestion-foundation`) | `✔ Test run with 37 tests in 4 suites passed after 6.009 seconds.` (0 warnings; AC-M2-09 scan 6 files, 0 violations) | 37 tests (WI-M2-01: 17); the 20 resolver tests have 159 parameterised cases plus the two seeded properties | ~6 s |

0 warnings, 0 failures, 0 skips. Swift 6.2.4 in the `swift:6.2-noble` image (the container's docker wrapper).
`TendSourceScan` and `TendCore` are unchanged, so their suites were not rerun (WI-M2-01 numbers stand: 63 and 127).

### Mutation check (each mutant applied alone, file touched so SwiftPM rebuilt it, then restored; clean baseline green)
| Mutant | Result |
|---|---|
| Sunday cut-off `>= 18` made `>= 19` | killed (84 failing) |
| T3 `slot.end <= now` made `<` | killed |
| T7 "first day after D" includes D | killed |
| R5 sets {W} with any repeat | killed |
| Range: `end > start + 366 d` made `>=` | killed |
| Range: the `start > now + 366 d` check removed | killed |
| T12 `boundary > now` made `>=` | killed |
| Gap policy `.nextTime` made `.strict` | killed |
| Repeated-time policy `.first` made `.last` | killed (by the Havana cases; it survived before they were added, which is why they exist) |
| Tonight's {evening, night} override removed | killed |
| T9 coming weekend offsets 6, 7 made 7, 8 | killed |
| T9 daypart "end ≤ now → coming weekend" branch removed | killed |
| T10 Sunday-evening rule removed | killed |
| T4 end 05:00 made 06:00 | killed |
| T14 week = 6 days | killed |
| `inDays` range 1…367 | killed |
| Night slot ends on its own day | killed |
| T1 fallback 7 d + 1 h | killed |
| Q5 step 6 range 1…731 | killed |
| `repeatEvery >= 0` counts as a repeat | killed |
| Absent season reported as out of range | killed |
| `TimeHint`: month = 31 days; year = 366 days; winter starts in November | killed (each) |
| Gap policy `.nextTime` made `.previousTimePreservingSmallerComponents` | **survived: equivalent here.** A probe on Linux Foundation shows that every non-strict policy gives the same instant for a missing local midnight (Santiago 2026-09-06 and Havana 2026-03-08 both give the day's first instant), and no tested zone has a gap at a slot hour (05, 12, 17, 22). `.strict` is killed. |

**Round 2 mutants** (the new behaviour; same method, clean baseline green afterwards). All 9 killed: R5 units back
to week only; R5 with a day repeat too; an invalid anchor drops its daypart; an invalid anchor drops its repeat;
settlement keeps {W} after dropping the interval; settlement drops the weekend's {sat, sun} too; the `nil` hint checked
before the finite `now`; `endHour` off by one daypart; afternoon ending at 18:00.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| AC-M2-03: 37 tests (round 2), 0 warnings, including the AC-M2-09 scan (6 files, 0 violations) | ✔ container | — | — | — | Linux CI runs it once PR #15 and the owner's CI PR are merged. |
| The same results on Darwin Foundation (R-10: DST policies and `date(bySettingHour:)` at a missing or repeated midnight) | — | — | — | — | Not verified: no Mac here. Plan B2 (MS-2) reruns `TendIngestion` on the Mac. A Darwin difference in the Santiago or Havana cases is a defect, not a skip. |

Device ACs: none in this item.

### Things the reviewer should look at closely
- `TimeResolver.thisWeekend` (T9 with a daypart and the "end ≤ now" coming-weekend rule).
- The two copies of the slot rules (DT5) and the oracle test that ties them together.
- DT1 and DT2, rebuilt in round 2 to the PO's answers, and `RecurrenceSettlement.settle(kind:resolution:)`.
- `Days.firstOffset(after:weekday:)` scans 1…7 calendar days by noon arithmetic, so a zone that skips a whole day
  (Samoa 2011) still finds the weekday within 7 steps.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Q-T1 and Q-T2: **closed**, answered by the PO on 2026-11-21 (plan `815fd33`, `65e3665`) and built in round 2 (DT1, DT2). The `DECISIONS.md` entry is in the human-merged governance PR. | — | Done |
| The slot rules exist in TendCore (internal) and here; the start and end oracle guards drift. Making `SlotCalendar` public would need a TendCore change. | Nit | Later chore (with R-16) |
| R1-N2: "in 366 days" said at local midnight falls back to T1 when D+366 is across a DST change (the table read literally). No change. | Nit (PO/Tester awareness) | — |
| One equivalent mutant (gap policy, see above). | Nit | — |
| Not verified on Darwin (R-10). | — | Plan B2, MS-2 |
| WI-M2-05 wiring: steps 5 and 6 call `resolve` and `RecurrenceSettlement.settle`; `basis` feeds the per-rule counts. | Planned | WI-M2-05 |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Times are inferred from the model's hint; no field is asked for. |
| UX-2 Rule of Three | n.a. | No selection API. |
| UX-3 Zero-Guilt | pass | No overdue state or helper. A window in the past is never produced (start ≥ now); a broken hint falls back calmly to "this week". Case names are checked against the banned list. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | Pure computation; no inference here. |
| P-2 No data leaves device (except user iCloud) | pass | Foundation and TendCore only; AC-M2-09 scan 0 violations. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | The hint type adds no request field; the cloud schemas mirror it in WI-M2-10/12 under ADR-0005. |
| P-4 Media not persisted without consent | pass | No write, log or media API. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Work Planner | Developer (via Orchestrator) | accepted (H2) | WI-M2-03 Ready: Tester's Q6 table review APPROVED, PO acknowledged P1–P7 with the P3 change. Branch `m2/time-resolver`, stacked on PR #15. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first. TendIngestion 34 tests, green, 0 warnings, Linux Swift 6.2.4. Every row, R1–R7 and E1–E21 tested exactly; Santiago and Havana DST at midnight; 24 mutants killed, 1 equivalent. Open questions Q-T1, Q-T2 (PO). Not verified on Darwin (B2). Pushed; no PR opened. |
| 2026-11-21 | Product Owner | Developer (via plan) | answered | Q-T1 and Q-T2 (plan `815fd33`, `65e3665`; E22–E26). |
| 2026-11-21 | Reviewer | Developer (via Orchestrator) | returned (round 1: CHANGES REQUIRED) | [review-WI-M2-03.md](review-WI-M2-03.md), copied unchanged. R1-F1…F3 Major (PO Q-T2, Q-T1, E22–E26); R1-F4…F6 Minor; R1-N1, N2 Nits. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 2) | R1-F1 (Q-T2) and R1-F2 (Q-T1) built; R1-F3: E22–E25 exact, E26 through `settle(kind:resolution:)`; R1-F4: `endHour` derived and an end oracle; R1-F5: finite check first, tested with a `nil` hint; R1-F6: this section; R1-N1: `modelChoices`. The round 1 tests that pinned the replaced readings now pin the PO's answers (a product decision, not a weakening). 9 new mutants killed. `origin/m2/ingestion-foundation` merged in. TendIngestion: `✔ Test run with 37 tests in 4 suites passed after 6.009 seconds.` (0 warnings; AC-M2-09 scan 6 files, 0 violations) |

## WI-M2-04 — calm-words guard (AC-M2-12), room linking with name folding (AC-M2-04), `sourcePhrase` check

- **Owner:** Developer  ·  **Branch:** `m2/calm-words-and-rooms`, based on `origin/main` at `8076d64` (WI-M2-01
  merged)  ·  **PR:** not opened (as instructed; the Orchestrator opens it)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (files sit in `TendIngestion/Sources`, Foundation +
  TendCore only).
- **Requirements:** FR-A1 (room linking, `sourcePhrase`), UX-3 (calm-words guard). **Owns AC-M2-04 and AC-M2-12**
  ([plan.md](plan.md) WI-M2-04). Brief inputs: Definitions ("Draft", "Name folding", "Banned tokens"), AC-M2-04,
  AC-M2-12, T-09, T-10, Q5 steps 7 and 8, Q19 (room names are user labels).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. The DoR condition "WI-M2-01 merged" is met
  (PR #15, `8076d64`).

### What changed
- **`TendIngestion` (new files, all Foundation + TendCore):**
  - `Rooms/DraftRoom.swift`: `DraftRoom` = `existing(Room.ID)` / `proposed(String)` / `none` (brief T-03 field set).
    WI-M2-05 uses it in `IngestionDraft`.
  - `Rooms/RoomLinker.swift`: `RoomLinker.link(_:in:)` (parse time, pure, never creates or renames a room) and
    `RoomLinker.commitPlan(for:existing:makeID:)` with `RoomCommitPlan` (`newRooms`, `roomIDs`). The commit plan is pure
    too: the caller (WI-M2-05/06 `commit(confirmed:)`) appends `newRooms`. IDs come from the injected `makeID`.
  - `Guard/CalmWordsGuard.swift`: `CalmWordsGuard.calmed(_:input:)`, `CalmWordsGuard.apply(title:room:sourcePhrase:input:)`
    → `CalmWordsDecision` (`keep(title:room:)` / `skip(CalmWordsSkipReason)`), `CalmWordsSkipReason.noTitleWordsLeft`.
  - `Text/SourcePhrase.swift`: `SourcePhrase.checked(_:input:)`.
  - `Text/BannedTokens.swift`: header comment only (it now points at the exemption, see E1).
- **Tests (`TendIngestionTests`):** `CalmWordsGuardTests` (AC-M2-12), `RoomLinkingTests` (AC-M2-04),
  `SourcePhraseCheckTests`, `CalmVocabularyScanTests` (AC-M2-12 vocabulary clause, with the exemption and its
  negative tests). The calm-guard cases use the brief's Outcome sentence as the input; room cases use the brief's
  examples ("the kitchen", "Sam's room", the five articles, the AC-M1-02 list).
- **Not changed:** `TendCore`, `TendSourceScan`, every protected path, every dependency.

### How the pieces fit (for WI-M2-05, Q5 steps 7 and 8)
1. Before step 7: `RoomLinker.link(modelRoomText, in: household.rooms)`. Linking uses the **model's raw room text**,
   so a household room the user named "Late-night den" still links (the label is the user's own word, Q19).
2. Step 7: `CalmWordsGuard.apply(title:room:sourcePhrase:input:)`. Only a `proposed` name is guarded.
3. Step 8: `SourcePhrase.checked(sourcePhrase, input:)` for the draft's stored `sourcePhrase`.
4. Commit: `RoomLinker.commitPlan(for: confirmedRooms, existing: household.rooms, makeID:)`.

### Decisions the Reviewer should know (technical or literal readings; each is tested)
- **E1: the banned-list vocabulary exemption (WI-M2-01 review follow-up).** AC-M2-12's "every outcome and reason name
  and the model instructions contain no banned token" is checked by the **AC-M1-02 vocabulary scan** (identifiers
  split at camelCase, digits and `_`, plus every string literal; comments removed) over every `.swift` file of the
  three AC-M2-09 roots (`ScanScope.roots`: TendIngestion required; TendAI and TendEval scanned as soon as they exist).
  This is stricter than the clause, because it covers every identifier and literal, so future outcome/reason names and
  instruction strings are covered as they are written. There is **one named exemption, `BannedTokenListExemption`**
  (in `CalmVocabularyScanTests.swift`), and no file-level exemption. A hit is exempted only when all hold:
  1. the path is exactly `Packages/TendIngestion/Sources/TendIngestion/Text/BannedTokens.swift`;
  2. the anchor `public static let all: [String] = [` occurs **exactly once in the lexed code** (not in a comment);
  3. the hit's line is in the declaration's span (anchor line to the first `]` after it);
  4. the hit is a string literal whose **whole text** is the token (`"late"`, not `"late fee"`);
  5. each token is exempted **at most once**.
  If the anchor is missing or repeated, nothing is exempted (fail-closed: all nine are reported). The real scan also
  asserts that exactly the nine list tokens were exempted and that `BannedTokens.all == SourceScanner.bannedTokens`.
  Negative tests: the declaration in four other paths (9 hits each), a literal, an identifier, an outcome-style case
  name and an instruction string outside the span, `"late fee"` and an identifier inside the span, a repeated entry,
  a renamed anchor, a doubled anchor, an anchor in a comment, and a single-line declaration. A further test checks
  *which* hit is kept (by excerpt and line), so the once-only rule cannot hide a span or whole-text mutant.
  *Why in the test target, not `TendSourceScan`:* it is one fact about one file of this module, and keeping it next
  to the scan keeps `TendSourceScan` unchanged. Moving it is a reversible refactor.
- **E2: "whole input" is compared as whole tokens.** A banned token is kept only when the same folded whole token is
  in the input ("lateness" in the input does not allow "late" in the title). This is the brief's token rule applied to
  both sides; it removes more, so it is the stricter reading.
- **E3: "punctuation" is Unicode general category P\*** (Pc, Pd, Ps, Pe, Pi, Pf, Po), on the first scalar of each
  character. Symbols (`$`, `+`, `€`) are not trimmed. The tidy-up (collapse and trim) runs **only after a removal**,
  as the brief says ("After a removal, …"); otherwise the text is returned unchanged.
- **E4: a fallback title is a verified, calm `sourcePhrase`.** When the guard empties a title, the stand-in is the
  `sourcePhrase` only if it passes the step 8 substring check, trimmed and collapsed, and itself calmed. Otherwise
  the item is skipped (`noTitleWordsLeft`). Reason: Q5 runs the guard (7) before the `sourcePhrase` check (8), so an
  unchecked phrase is model text, not the user's words, and could carry an introduced token. See open question 1.
- **E5: link first, then guard.** Linking uses the model's raw text; the guard applies only to a `proposed` name
  (AC-M2-04: "If none matches, it carries `proposed(name)`, … after the calm-words guard"). A proposed name is stored
  trimmed and collapsed. A name that folds to empty is `none` at link time; a proposed name the guard empties is `none`.
- **E6: commit.** Proposals are grouped by folded name; the first confirmed draft's text names the new room. A proposal
  whose folded name equals an **existing** room's name at commit uses that room (lowest `id.uuidString`) and creates
  nothing. This covers a name the guard reduced to an existing name ("late kitchen" → "kitchen") and a room added
  between parse and commit. An `existing(id)` whose room is gone gives no room. See open question 2.
- **E7: `sourcePhrase` match is a plain `Character` substring** of the folded input, implemented by hand (no
  Foundation `range(of:)`, so no platform option differences, R-10). A phrase that folds to empty is nil. A phrase
  that passes is returned exactly as given (not folded or tidied). "alcon" in "balcony" passes: the brief says
  substring, not whole words.
- **E8: tie order** is ascending UTF-8 bytes of `id.uuidString` (`TextFolding.utf8Precedes`), the same as the
  shortlist tie-break.

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-04 | `RoomLinkingTests` (AC-M2-04 suite): folded linking (13 cases: trim/collapse, articles the/my/our, ASCII vs typographic apostrophe, diacritics incl. decomposed, width, folding of the stored name); exact-not-fuzzy (8 cases: plural, prefix, digits, spacing, double article, punctuation, apostrophe); nil/empty → `none` (4); proposed text kept (3); tie → lowest `uuidString` in 3 array orders; empty household; no room created or renamed during parsing; link-then-guard (4); user label with a banned token links; commit: equal folded proposals create one room, distinct proposals in order, proposal equal to an existing room, missing existing room, nothing confirmed | PASS (Linux) |
| AC-M2-12 | `CalmWordsGuardTests` (AC-M2-12 suite): removal and tidy-up (12); each of the 9 tokens (9); folded matching (5); whole tokens only (7); no tidy without removal (3); user's words kept (7); input compared as whole tokens (3); empty title → `sourcePhrase` (and tidied); skip with typed reason for nil/empty/blank/unverified phrase (4); fallback guarded; proposed room guarded, emptied → `none` (5); user-said room name kept; existing/none untouched; title kept ignores phrase; 2,000-case seeded property (seed `0x0CA13E5EED000412`, printed; 1,448 titles changed): no kept title or proposed name holds a token absent from the input, never empty; reason case names calm. `CalmVocabularyScanTests`: the module-Sources vocabulary scan (8 files, 9 exempted, 0 violations) and the exemption's negative tests | PASS (Linux) |
| (Q5 step 8, no AC owned) | `SourcePhraseCheckTests`: kept (10, from the brief's Outcome sentence), dropped (5), nil/empty (4), both sides folded (4 checks) | PASS (Linux) |

AC-M2-12's instruction clause has no instruction strings to check yet: the on-device and cloud instructions are written
in later items (WI-M2-05/10/11). The vocabulary scan covers them automatically when they land in any of the three roots.
If instructions are ever kept outside `.swift` files (for example a resource file), that item must extend the scan.

### Test runs
| Command | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 59 tests in 7 suites passed after 0.409 seconds.` Scan lines: `AC-M2-09 scan: 8 files in total, 0 violations`; `AC-M2-12 vocabulary scan: 8 files, 9 exempted (the list), 0 violations`. |
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!` |

0 warnings, 0 failures, 0 skips. Swift 6.2.4 in the `swift:6.2-noble` image (container). TendSourceScan and TendCore
are unchanged, so they were not rerun.

### Mutation check
Each mutant was applied alone, run with `-warnings-as-errors`, and restored with a touch (mtime-safe). The clean
baseline afterwards was 59 tests green. **All 22 are killed.**

| Mutant | Killed by |
|---|---|
| Guard ignores the input (removes every banned token) | user's words kept, input as whole tokens (4 tests) |
| Input compared as a substring, not whole tokens (compiling variant; the first variant left `said` unused and failed the build, so it was rerun) | input compared as whole tokens (3 tests) |
| No punctuation trim (compiling variant, as above) | removal and tidy-up, folded matching (6 tests) |
| No whitespace collapse | removal and tidy-up, user's words (3 tests) |
| Tidy-up without a removal | no tidy without removal |
| Fallback skips the `sourcePhrase` check | skip with typed reason (unverified phrase) |
| Fallback not calmed | fallback guarded |
| Emptied proposed room kept as `proposed("")` | proposed room guarded (3 tests) |
| Proposed room not guarded | proposed room guarded (3 tests) |
| Tie picks the highest `uuidString` | tie test |
| Linking without the article strip | folded linking |
| Stored room names not folded | tie test, folded linking |
| Commit: no grouping of equal proposals | one room for equal proposals |
| Commit: proposal not checked against existing rooms | proposal equal to an existing room |
| Commit: a missing existing room kept (compiling variant, as above) | missing existing room |
| `sourcePhrase`: input side not folded | kept cases, both sides folded |
| `sourcePhrase`: empty needle allowed | nil/empty |
| Exemption: no path check | other-file plants |
| Exemption: a literal may hold more text (`contains`) | kept hit is the planted one (**survived the first run**: the count-only test let the once-only rule hide it; the excerpt check was added) |
| Exemption: span ignored | kept hit is the planted one (**survived the first run** for the same reason; line checks added) |
| Exemption: repeated entries allowed | rest-of-file plants (repeated entry) |
| Exemption: anchor count not checked | fail-closed (doubled anchor) |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion: 59 tests, AC-M2-04, AC-M2-12, sourcePhrase, AC-M2-09 scan, vocabulary scan | ✔ container | — | — | — | Linux CI on the PR. |
| Folding-based behaviour on Darwin Foundation (R-10) | — | — | — | — | Not verified (no Mac). Plan B2 (MS-2). The guard and linker use `TextFolding`, so the WI-M2-01 pins cover them. |

Device ACs: none in this item.

### Things the reviewer should look at closely
- **E1, the exemption**: whether the five conditions are narrow enough, and the fail-closed paths.
- **E4 and E6** (open questions below): both are the stricter reading, but they are product meaning.
- `CalmWordsGuard.calmed` removes by original ranges from `BannedTokens.matches`, so a decomposed accent inside a
  token is removed with it (`Late\u{301}` case).

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Instruction strings do not exist yet; the vocabulary scan covers them once written in `.swift` files of the three roots | Nit | WI-M2-05/10/11 |
| The exemption is anchored on the declaration's first line; reformatting it fails closed (red, not silently green) | Nit | — |
| Not verified on Darwin (R-10) | — | Plan B2, MS-2 |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection API. |
| UX-3 Zero-Guilt | pass | The guard removes every banned token the user did not say from titles and proposed room names (AC-M2-12, property test). The skip reason `noTitleWordsLeft` is calm. The vocabulary scan keeps every identifier and literal in the module Sources free of banned tokens, except the one list. No overdue state or counter. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. |
| P-2 No data leaves device (except user iCloud) | pass | Pure functions; no networking (AC-M2-09 scan: 0 violations). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | — |
| P-4 Media not persisted without consent | pass | No write or log API; nothing is stored. Parsing never creates a room. |

### Open questions
1. **PO (AC-M2-12, E4):** when the guard empties a title, should the stand-in be the raw `sourcePhrase` (literal "it
   becomes the draft's `sourcePhrase`") or only a phrase that passes the step 8 check and is itself calm (built)? The
   built reading never shows model words the user did not say. It differs from the literal one only when the phrase is
   not in the input, or holds a banned token that is a substring but not a whole token of the input.
2. **PO (AC-M2-04, E6):** at commit, a proposed name that folds to an existing room's name uses that room instead of
   creating a second room with the same folded name (built). And when two drafts' proposals fold the same, the first
   confirmed draft's text names the room (built). Please confirm both.
3. **PO / Tester (AC-M2-12, E2, E3):** confirm that "occurs anywhere in the input" is a whole-token comparison, that
   "punctuation" is Unicode P\* (symbols kept), and that text is tidied only after a removal.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Developer | accepted (H2) | WI-M2-04 Ready: WI-M2-01 merged (`8076d64`). Includes the WI-M2-01 review follow-up (vocabulary scan exemption). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed before the code). 22 mutants killed (2 after adding a test). TendIngestion 59 tests green, 0 warnings, Linux. Mutation-checked. Three open questions for the PO. Pushed; no PR opened. |

---

## WI-M2-05 — neutral model contract, `IngestionDraft`, Q5 repairs in order, mapping to `HouseholdTask`

- **Owner:** Developer  ·  **Branch:** `m2/draft-mapping`, from `origin/main` at `17c8ab0` (WI-M2-02, 03 and 04
  merged)  ·  **PR:** #20  ·  **Review:** [review-WI-M2-05.md](review-WI-M2-05.md) (round 1 CHANGES REQUIRED; reworked in round 2,
  see "Round 2" below)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (new files under `TendIngestion/Sources`, Foundation +
  TendCore only).
- **Requirements:** FR-A1, D-016, UX-1 (every field inferred), UX-3. **Owns AC-M2-01 and AC-M2-02**
  ([plan.md](plan.md) WI-M2-05). Brief inputs: Definitions ("Draft", "Item completion", "Draft stream events"), Q5
  steps 1–9, T-07, Q6 via the plan table, Q9. Plan inputs: the WI-M2-05 note, "Notation" (∅ sets and step 3), "How the
  hint meets Q5", the `basis` bullet, E26. Tickets: R2-N1, R19-F3, PO WI-M2-04 ruling 2 (commit order).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. DoR "deps merged" is met (WI-M2-02, 03, 04 on
  `main`).

### What changed
- `Sources/TendIngestion/Model/IngestionModel.swift` (new): the neutral contract.
  - `ModelChoice<Value>` (`known(Value)` / `unrecognized(String)`, `init(raw:)` exact raw-value match). An unknown
    enum value is kept as a value (brief T-03 (a)) until Q5 step 2 repairs it.
  - `ModelNumber.wholeNumber(_:)`: `Int(exactly:)`, so fractional, NaN, ±∞ and out-of-`Int` numbers are nil (plan
    "Numbers"; WI-M2-12 and the on-device mapping use it).
  - `TimeHintSnapshot` (mirrors `TimeHint`, fields as sent), `ItemSnapshot` (title, kind, roomName, effort, three
    flags, time, sourcePhrase; all optional), `IngestionSnapshot` (all items so far, in output order; each replaces the
    last), `IngestionRequest` (input text and room names, ADR-0005 Decision 3).
  - `protocol IngestionModel: Sendable { func snapshots(for:) -> AsyncThrowingStream<IngestionSnapshot, any Error> }`.
    It is deliberately minimal. WI-M2-06 adds the availability and failure reasons for `noModel` (AC-M2-10).
- `Sources/TendIngestion/Draft/IngestionDraft.swift` (new): `IngestionDraft` with the brief's field set (`draftID`,
  title, kind, room `DraftRoom`, effort, flags, dayparts, weekdays, window, interval, `sourcePhrase`, `duplicate`) and
  `DraftDuplicate` (`none` / `ofExisting(id)` / `ofDraft(draftID)`). The initialiser is **internal**, so only the mapper
  (and WI-M2-06's plain note, in the module) makes drafts. `task(id:roomID:) throws(TaskInvariantViolation)` builds the
  `HouseholdTask` for commit: `active`, never completed.
- `Sources/TendIngestion/Draft/DraftMapper.swift` (new): `DraftMapper(input:rooms:now:calendar:timeZone:)` and
  `map(_:draftID:) -> DraftMapping` (`outcome` = `.draft` / `.skipped(ItemSkipReason)`, plus `repairs: [ItemRepair]` in
  the order they ran). `ItemRepair` has 22 cases, each with its Q5 `step`. `ItemSkipReason` = `noTitle` (1),
  `calmWords(CalmWordsSkipReason)` (7), `taskRejected(TaskInvariantViolation)` (9).
- `Sources/TendIngestion/Time/TimeResolver.swift`: **`TimeResolution.init` is now internal (R2-N1).** Outside the module
  a resolution can only come from `TimeResolver.resolve`, so `weekdaysFollowRepeat` always matches how the weekdays were
  made. Nothing outside the module constructed one. The WI-M2-03 tests use `@testable` and are unchanged.
- Tests (new, written first; the first build failed with "cannot find type 'DraftMapper' in scope"):
  `DraftMappingTests.swift` (AC-M2-01 suite and the Q5 step suite), `DraftMappingPropertyTests.swift` (AC-M2-02
  property, generator and oracle).
- Not changed: `TendCore`, `TendSourceScan`, every protected path, every dependency.

### The Q5 steps as built (brief Q5; plan WI-M2-05)
| Step | What the mapper does | Calls |
|---|---|---|
| 1 | `title` nil, or empty after trim and collapse (`TextFolding.collapseWhitespace`) → `skipped(.noTitle)`. Otherwise the tidy title. | — |
| 2 | Kind unknown or missing → `oneOff`; effort → `normal`; flags missing → false. Room: `RoomLinker.link` on the model's raw text (WI-M2-04 order); text that folds to empty → `none`. Time hint: missing anchor → `.none`; unknown anchor (or the reserved `unrecognized` value) → `.unrecognized`; unknown daypart, weekday, season or repeat-unit element → dropped. | `RoomLinker.link` |
| 4 | Critical + deep clean → critical, deep clean cleared. | — |
| 5 | `resolver.resolve(hint, now:)`, the only source of a `TimeResolution` (R2-N1). A `basis` other than `hint` is logged as `windowDefaulted(basis)` (plan: `basis` is diagnostic, used for these counts). | `TimeResolver.resolve` |
| 6 | `RecurrenceSettlement.settle(kind:resolution:)`: recurring outside 1…730 or with no interval → one-off; an interval on a non-recurring item → dropped; R5's {W} drops with the interval (E26). | `RecurrenceSettlement` |
| 3 | Empty dayparts → `Daypart.defaultAllowed`; empty weekdays → all seven (`Settled.effective…`). | — |
| 7 | `CalmWordsGuard.apply` on the title and a proposed room (PO WI-M2-04 ruling 1: the fallback is the checked, calmed `sourcePhrase`). **Round 2 (PO WI-M2-05 ruling 1):** if the guard changed a proposed name and left it non-empty, the calmed name is matched again with the AC-M2-04 rule, and a match gives `existing(id)` (`roomLinkedAfterCalming`, logged after `roomNameCalmed`). | `CalmWordsGuard`, `RoomLinker.link` |
| 8 | `SourcePhrase.checked`; a phrase that fails → nil. | `SourcePhrase` |
| 9 | `draft.task(id: probeID, roomID: nil)`; a rejection → `skipped(.taskRejected(violation))`. | M1 initialiser |

**Why step 3 runs after 5 and 6 (`DraftMapper.stepOrder == [1, 2, 4, 5, 6, 3, 7, 8, 9]`).** The dayparts and weekdays
only exist once the resolver (step 5) has made them. The plan says the resolver returns ∅ and "WI-M2-05 applies the Q5
step-3 defaults to the resolver's empty sets after step 5". Step 6 can empty the weekdays again (E26: R5's {thursday}
drops with the interval), so step 3 must also come after 6. Otherwise an E26 item would reach the initialiser with no
weekdays. The mutant "step 3 before step 6" is killed (see below). All other steps run in the brief's order. This is
the plan's wording, made exact. It is not a new product reading.

### Decisions the Reviewer should know
- **D1, R19-F3 (guard cuts a proposed name to an existing room's name): re-link after the guard (round 2, PO
  ruling 1 in `po-m2-wi05.md`, which reverses the round 1 default).** Take "late kitchen" in a household with Kitchen,
  where the user did not say "late". Step 7 calms the name to "kitchen". Because the guard changed the name, the calmed
  name is matched again with the AC-M2-04 rule (name folding, exact match, tie → lowest `id.uuidString`, via
  `RoomLinker.link`), so the draft is `existing(kitchenID)`. The repair is logged as `roomLinkedAfterCalming`, after
  `roomNameCalmed`.
  - A calmed name that matches no room stays `proposed(calmedName)` ("late pantry" → `proposed("pantry")`).
  - An emptied name is `none`.
  - An unchanged proposed name is not matched again, because it already failed the step 2 match.
  - Commit keeps its own re-check (PO WI-M2-04 ruling 2b).

  As a result, a draft never proposes a room that equals an existing one, which is the invariant WI-M2-07's local
  word-match relies on. Tests: "R19-F3 (PO ruling 1): …" (flipped), the tie case (3 array orders) and the no-match
  case. The reverse mutant ("no re-link") is killed.
- **D2, a missing kind or effort is repaired like an unknown one.** "On completion, the Q5 repairs fill any missing
  field" (Definitions). Both cases log `kindDefaulted` / `effortDefaulted`. Missing flags become false and are not
  logged (they are not enums).
- **D3, a time hint with no anchor means anchor `none`.** Its daypart and repeat still count (T15, R7). It is logged
  `anchorDefaulted`. A hint whose anchor is the reserved value `unrecognized` is treated as unknown (`anchorUnrecognized`),
  because the model is never offered it (`Anchor.modelChoices`).
- **D4, `ModelChoice.init(raw:)` matches exactly** (no case or space folding): "Restock" is unknown and becomes a
  one-off. The schemas (WI-M2-10, WI-M2-M2) offer exactly the raw values. Tested, and the case-insensitive mutant is
  killed.
- **D5, `draftID` comes from the caller.** A skipped item uses none, so stream assembly (WI-M2-06) advances its counter
  only on `.draft`. That keeps IDs as 1, 2, 3 … in emission order.
- **D6, commit order (PO WI-M2-04 ruling 2).** This item does not commit. The only order its API implies is `draftID`
  ascending = emission order = model-output order (Definitions). **WI-M2-06/08 should pass confirmed drafts to
  `RoomLinker.commitPlan` and the upsert in ascending `draftID`, and state it.** That makes the first proposer of a
  folded room name the draft with the lowest `draftID`.
- **D7, step 9 is reachable only with a non-finite `now`.** Over 6,000 outputs the oracle shows no rejection with a
  finite `now` (0 `taskRejected`). The step 9 test drives it with NaN and ±∞ `now` and gets
  `taskRejected(.windowDateNotFinite)`.
  **Where the AC-M2-02 classes "end ≤ start" and "non-finite" are covered (review F3).** Neither has a row in the
  counts table, because no model output can produce them:
  - **End ≤ start** is impossible by construction: the snapshot contract carries no dates, and every window comes from
    the resolver. The resolver's own empty-window branch is covered by `rangeProblem`'s unit test in
    `TimeResolverTests.swift` (the Q5 step 5 range rule at ±1 ms, which includes end = start). The property re-checks
    `start < end` and the 366-day range on every draft.
  - **Non-finite numbers in a time hint:** `ModelNumber.wholeNumber` turns them into nil. The generator's `odd` values
    include NaN, ±∞, 2.5, 1e30 and 9.3e18, and the test "Model numbers: …" covers them. They then count as a missing
    or out-of-range field (`requiredFieldAbsent` / `fieldOutOfRange` rows).
  - **Non-finite dates** are reachable only through a non-finite `now`: "Q5 (9): …" (NaN, ±∞) and the WI-M2-02
    invariant tests.
- **D8, the oracle's independence** (written at the top of `DraftMappingPropertyTests.swift`). The oracle reads the
  **raw** output (strings and `Double`s) and re-implements steps 1–8 itself: Character-based tidy, enum defaults, step 3,
  step 4, the basis check, step 6 and the R5 drop derived from the hint (not `weekdaysFollowRepeat`), a calm guard over
  `Character.isLetter` runs, `String.contains` for the phrase, and `String <` for room ties. It calls only
  `TimeResolver.resolve` (Q6, verified against the plan table by AC-M2-03) and `TextFolding.foldName` (the brief's
  primitive). It never calls `DraftMapper`, `RecurrenceSettlement`, `CalmWordsGuard`, `SourcePhrase`, `RoomLinker` or
  `BannedTokens`. The generator alphabet is restricted so that the `Character` classes match the production scalar
  classes.
  **Round 2 (review F2):**
  - The oracle now computes the step 5 fallback itself: when `basis != .hint`, it expects `[now, now + 604,800 s)` and
    weekdays ∅.
  - It also re-links after the guard with its own fold-and-compare, using `String <` for ties.
  - **The independence is conditional.** A defect in the two shared functions is invisible to this property.
    - Reviewer mutant `p` (name folding strips no article) gives 0 mismatches here. It is killed by AC-M2-01, AC-M2-04
      and `TextPrimitivesTests`.
    - Q6 rows are pinned by the AC-M2-03 suite (hand-written UTC tables, E1–E26).
    - The fallback-duration mutant (`o`, 6 days) is now also killed by the property itself (mutation table).
  - The AC-M2-02 evidence should cite those suites next to the property.

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-01 | "AC-M2-01: each PRD item type maps to a draft that passes the M1 initialiser with the expected fields". 8 cases: one-off errand (T5), recurring maintenance (R5 "every Saturday", deep clean, existing room via "the bathroom"), consumable restock (T10, "KITCHEN" links), weather-dependent (T9 + morning, proposed "Driveway"), each in America/New_York and Europe/London. Every draft field and every `HouseholdTask` field is compared with hand-written UTC windows. Also "a critical bill …" (T12) and "date fields depend only on the injected now, calendar and time zone" (same inputs give the same draft; `now` + 1 day moves T5 by one local day; `firstWeekday` = Sunday gives the same windows) | PASS (Linux) |
| AC-M2-02 property | "AC-M2-02: 6,000 seeded outputs map without a crash or an invalid task; each equals the Q5 oracle, repairs and order included; counts per repair rule are logged". Seeds `0x0A11C0DE5EED0501`, `…0502`, `…0503`, 2,000 outputs each, 6 zones, random `firstWeekday`, `now` over 2026–2028 with milliseconds. Per output: deterministic; `repairs` equal the oracle's list exactly, in the `stepOrder`; outcome and every field equal the oracle; `task(id:roomID:)` never throws; the window is inside the Q5 range; no unsaid banned token in a title; every repair rule and both skip reasons occur on every seed; no `taskRejected` | PASS (Linux): 6,000 outputs, 5,171 drafts, 829 skipped, **0 oracle mismatches** |
| AC-M2-02 per-step cases | `DraftMappingRepairTests` (the Q5 step suite): (1) tidy (3 inputs), untouched, nil/blank → `noTitle` with nothing else run (5); (2) unknown/missing kind and effort (4), blank room (3), flags, unknown daypart, unknown weekday → T1, unknown/reserved/missing anchor (3), unknown season and unit; (4); (5) no hint and 4 fallback reasons; (6) becomes one-off (4), keeps at 1/730/2 years/24 months (4), interval dropped (2), **T-07 order** (unknown kind, then interval dropped), **E26 order** (6 before 3), out-of-range R5, kept R5; (7) title calmed, user's words kept, fallback/skip, room calmed/cleared, **R19-F3**, user label links; (8) kept/dropped (3); (9) non-finite `now` (3); `ModelNumber` (10); `ModelChoice`; draft contract; step numbers and `stepOrder` | PASS (Linux) |
| AC-M2-02 W2-F3 clause | Delivered by WI-M2-02 (merged). Here it is the step 9 net: `taskRejected(.windowDateNotFinite)` | PASS (Linux) |
| AC-M2-09, AC-M2-12 (regression) | "AC-M2-09: Rules 1–6 hold …": `13 files in total, 0 violations`. "AC-M2-12 vocabulary scan": `13 files, 9 exempted (the list), 0 violations`. The new case names (`ItemRepair`, `ItemSkipReason`) are covered by that scan | PASS (Linux) |

**Counts per repair rule** (sum over the three seeds, 6,000 outputs; per-seed lines are in the log):

| Step | Rule | Count |
|---|---|---|
| 1 | `titleTidied` | 4,269 |
| 1 | skip `noTitle` | 604 |
| 2 | `kindDefaulted` / `effortDefaulted` / `roomDefaulted` | 1,445 / 1,473 / 281 |
| 2 | `anchorDefaulted` / `anchorUnrecognized` | 299 / 406 |
| 2 | `daypartDropped` / `weekdayDropped` / `seasonDropped` / `repeatUnitDropped` | 317 / 264 / 194 / 293 |
| 4 | `deepCleanCleared` | 443 |
| 5 | `windowDefaulted`: `noHint` / `unrecognizedAnchor` / `requiredFieldAbsent` / `fieldOutOfRange` / `windowOutOfRange` | 1,104 / 406 / 876 / 103 / 119 |
| 6 | `becameOneOff` / `intervalDropped` / `repeatWeekdaysDropped` | 1,177 / 654 / 186 |
| 3 | `daypartsDefaulted` / `weekdaysDefaulted` | 3,550 / 5,119 |
| 7 | `titleCalmed` / `titleFromSourcePhrase` / `roomNameCalmed` / `roomNameCleared` | 2,470 / 137 / 542 / 396 |
| 7 | `roomLinkedAfterCalming` (round 2; the round 2 counts are in "Round 2" below) | — |
| 7 | skip `calmWords(noTitleWordsLeft)` | 225 |
| 8 | `sourcePhraseDropped` | 1,673 |
| 9 | skip `taskRejected` | **0** |

`emptyWindow` and `calendarUnresolved` never occur with a finite `now` and the Gregorian calendar. No hint reaches
them, and they are not required by the coverage check. The generator puts 15 % of hints on a fixed list of edge hints
(`inDays` 366 at night or in the evening, `inWeeks` 52 at night, R5 repeats out of range and in range, a daily repeat
on a weekday). Without that list, `windowOutOfRange` did not occur on one seed, and the coverage check caught it.

### Test runs
| Command (in `swift:6.2-noble`, Swift 6.2.x) | Summary line |
|---|---|
| `swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `Build complete!` (0 warnings) |
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 114 tests in 11 suites passed after 6.809 seconds.` (79 before this item + 35 new) |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 136.931 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 3.907 seconds.` (unchanged package) |

### Mutation check
Each mutant was applied alone by a script, run with `--filter DraftMapping` and `-warnings-as-errors`, and then
restored, with the mtime touched. **25 of 25 are killed.** The final clean run is the 114-test line above.

| Mutant | Killed by (number of failing tests) |
|---|---|
| (1) no trim/collapse | property, tidy, blank (3) |
| (1) blank title not skipped | property, blank (2) |
| (2) kind default `restock` | property, unknown enums, T-07 order (3) |
| (2) effort default `low` | property, unknown enums (2) |
| (2) `kindDefaulted` not logged | property, unknown enums, T-07 order (3) |
| (2) `anchorUnrecognized` not logged | property, anchors (2) |
| (2) dropped element not logged | property, daypart, weekday, season/unit (4) |
| (2) missing anchor → `unrecognized` | property, anchors (2) |
| (2) weather flag defaults to true | property, flags (2) |
| (4) deep clean kept | property, step 4 (2) |
| (5) only `noHint` logged | property + 4 step tests (5) |
| (6) kind not settled | property + 3 (4) |
| (6) interval not settled | property + 5 (6) |
| (6) R5 drop not logged | property, out-of-range R5, E26 (3) |
| (3) weekday default before step 6 | property, out-of-range R5, E26 (3) |
| (3) no daypart default | 29 tests |
| (3) logged before (6) (order only) | property + 5 (6) |
| (7) title not guarded | property + 2 (3) |
| (7) room not guarded | property, room calmed, R19-F3 (3) |
| (7) re-link after the guard (the R19-F3 alternative) | property, R19-F3 (2) |
| (7) `titleCalmed` / `titleFromSourcePhrase` swapped | property + 2 (3) |
| (8) phrase not checked | property, step 8 (2) |
| (9) initialiser not run | step 9 (1) |
| `ModelNumber` rounds fractions | property, model numbers (2) |
| `ModelChoice` folds case | property, `ModelChoice`, unknown enums (3) |

Two mutants of the first `ModelNumber` version survived ("round before converting", "drop the whole-number guard").
Both were **equivalent**, because `Int(exactly:)` already returns nil for every case the guard checked. The function was
reduced to `Int(exactly: value)`. The rounding mutant of the new version is killed (above).

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 114 tests: AC-M2-01, AC-M2-02, AC-M2-09 scan, AC-M2-12 vocabulary scan | ✔ container | — | — | — | Linux CI runs on the PR. |
| TendCore 141 tests, TendSourceScan 63 tests (unchanged) | ✔ container | — | — | — | — |
| Folding and `Calendar` behaviour on Darwin (R-10, W3-F1) | — | — | — | — | Not verified (no Mac). Plan B2 on the owner-run Mac. |

Device ACs: none in this item.

### Things the reviewer should look at closely
- The oracle's independence (D8): whether calling `TimeResolver.resolve` and `TextFolding.foldName` is acceptable.
  Both are inputs Q5 names (Q6 and name folding), not Q5 repairs.
- Step 3's placement (the table above) and `DraftMapper.stepOrder`.
- `TimeResolution.init` made internal (R2-N1). It is an API narrowing in a WI-M2-03 file.
- The `IngestionModel` protocol is minimal on purpose. WI-M2-06 extends it for AC-M2-10.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| `IngestionModel` has no availability or failure-reason contract yet | — | WI-M2-06 (AC-M2-10) |
| `ItemSnapshot` has no "every field present" helper for completion rule (a); WI-M2-06 defines which schema fields count | — | WI-M2-06 |
| Commit must pass confirmed drafts in ascending `draftID` (D6) | — | WI-M2-06/08 |
| Not verified on Darwin (R-10) | — | Plan B2, MS-2 |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every draft field is inferred or repaired to a default. No field is ever asked of the user (AC-M2-01, AC-M2-02). |
| UX-2 Rule of Three | n.a. | No selection surface. Drafts reach Now only after commit, through `NowSelector`. |
| UX-3 Zero-Guilt | pass | Step 7 runs the calm-words guard on every title and proposed room. The property test checks that no draft title holds an unsaid banned token. A missed window is never a state: the window always comes from the resolver, in range. Repair and skip names pass the AC-M2-12 vocabulary scan. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. The contract is the same for the on-device and cloud adapters. |
| P-2 No data leaves device | pass | Pure functions, no networking (AC-M2-09 scan: 0 violations). `IngestionRequest` holds only the capture text and room names (ADR-0005 Decision 3). |
| P-3 Cloud AI opt-in, BYOK, minimised | n.a. | — |
| P-4 Media not persisted | pass | No write or log API. Nothing is stored. Mapping creates no room or task. |

### Open questions
1. ~~**PO / Designer (R19-F3, AC-M2-04):** should the draft be re-linked after the guard?~~ **Closed: PO ruling 1
   (`po-m2-wi05.md`): re-link.** Built in round 2 (D1).
2. ~~**PO (D3, small):** is a time hint with no anchor anchor `none`?~~ **Closed: PO ruling 2 confirms it as built.**
   PO ruling 3 also accepts the step order `[1, 2, 4, 5, 6, 3, 7, 8, 9]`.

### Round 2 (review round 1: CHANGES REQUIRED; PO rulings `po-m2-wi05.md`)
| Finding | Change |
|---|---|
| **F1 Major** (PO ruling 1, items 1–5) | `DraftMapper` step 7: after the guard changes a proposed name to a non-empty name, the mapper calls `RoomLinker.link(calmedName, in: rooms)`. A match gives `existing(id)`, logged as the new case `ItemRepair.roomLinkedAfterCalming` (step 7, after `roomNameCalmed`). The R19-F3 test is flipped to `existing(kitchenID)`, and the commit plan still creates no room. New tests: the tie case (`"the  KITCHEN"` …0001 and `"Kitchen"` …00FF in 3 array orders → …0001), the no-match case ("late pantry" with no Pantry → `proposed("pantry")`), and "only when changed" (an unchanged name, and an emptied one). The oracle re-links with its own fold and `String <` tie. The generator adds calmed-to-existing room texts ("late kitchen", "Overdue Garage", "late Sam’s room", "behind the bathroom", "late pantry"). The coverage check now requires `roomLinkedAfterCalming` on every seed. D1 and open question 1 are updated. |
| **F2 Minor** | D8 states the conditional independence and cites the suites that cover the shared functions. The oracle now computes the step 5 fallback window and its ∅ weekdays itself, so the fallback-duration mutant is killed by the property (below). |
| **F3 Minor** | D7 maps "end ≤ start" and "non-finite" to the tests that cover them. No code change. |
| **F4 Nit** | The AC-M2-01 cases assert the draft title against a hand-written string. |
| **F5 Nit** | Not changed. Labelling the title repair calls `CalmWordsGuard.calmed` a second time. Removing that call would change `CalmWordsDecision`, a WI-M2-04 type, and its tests. The Reviewer confirmed the result is correct. |
| Found while mutating | Under the step 9 mutant, the test "Q5 (9)" crashed instead of failing: describing a NaN `Date` traps in Foundation on Linux. The test now compares to a Bool first, so the mutant gives a clean failure. |

**Round 2 test runs** (`swift:6.2-noble`, `-warnings-as-errors`, 0 warnings, `swift build` first for each package):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 117 tests in 11 suites passed after 6.517 seconds.` (114 + 3 new: tie, no-match, only-when-changed). AC-M2-09 `13 files in total, 0 violations`; AC-M2-12 vocabulary `13 files, 9 exempted (the list), 0 violations` |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 2.171 seconds.` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 118.442 seconds.` |

**Round 2 AC-M2-02 property:** same seeds (`0x0A11C0DE5EED0501`, `…0502`, `…0503`). 6,000 outputs gave 5,167 drafts and
833 skipped, with **0 oracle mismatches** and 0 `taskRejected`. Counts per rule (sum of the three seeds):

| Step | Rule | Count |
|---|---|---|
| 1 | `titleTidied` / skip `noTitle` | 4,307 / 600 |
| 2 | `kindDefaulted` / `effortDefaulted` / `roomDefaulted` | 1,454 / 1,455 / 266 |
| 2 | `anchorDefaulted` / `anchorUnrecognized` | 273 / 408 |
| 2 | `daypartDropped` / `weekdayDropped` / `seasonDropped` / `repeatUnitDropped` | 281 / 275 / 178 / 325 |
| 4 | `deepCleanCleared` | 396 |
| 5 | `windowDefaulted`: `noHint` / `unrecognizedAnchor` / `requiredFieldAbsent` / `fieldOutOfRange` / `windowOutOfRange` | 1,093 / 408 / 872 / 107 / 126 |
| 6 | `becameOneOff` / `intervalDropped` / `repeatWeekdaysDropped` | 1,197 / 639 / 198 |
| 3 | `daypartsDefaulted` / `weekdaysDefaulted` | 3,561 / 5,148 |
| 7 | `titleCalmed` / `titleFromSourcePhrase` / `roomNameCalmed` / `roomNameCleared` / **`roomLinkedAfterCalming`** | 2,498 / 128 / 722 / 388 / **402** (per seed 125 / 138 / 139) |
| 7 | skip `calmWords(noTitleWordsLeft)` | 233 |
| 8 | `sourcePhraseDropped` | 1,684 |
| 9 | skip `taskRejected` | **0** |

"End ≤ start" and "non-finite": see D7. Neither can come from a model output.

**Round 2 mutation check: 29 of 29 killed.** All earlier mutants were re-run on the new code. The round 1 mutant
"re-link after the guard" is now the built behaviour, so it was replaced by its reverse. New mutants:
| Mutant | Killed by |
|---|---|
| **No re-link after the guard** (the reverse of PO ruling 1) | property, R19-F3, tie (3) |
| Re-link not logged | property, R19-F3, tie (3) |
| Re-link takes the first matching room, not the lowest `uuidString` | property, tie (2) |
| `roomLinkedAfterCalming` logged before `roomNameCalmed` | property, R19-F3 (2) |
| Resolver T1 fallback 6 days instead of 7 (run with the property suite only) | property (1): the F2 fallback check |

The other 24 (steps 1–9, `ModelNumber`, `ModelChoice`) are all still killed. "Room not guarded" is now also killed by
the no-match test. Under the step 9 mutant the run first crashed (see the last F row); after the test fix it fails
cleanly in "Q5 (9)".

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Developer | accepted (H2) | WI-M2-05 Ready: WI-M2-02, 03, 04 merged (`17c8ab0`). Tickets R2-N1, R19-F3, PO ruling 2 (commit order). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 114 tests green, 0 warnings, Linux; AC-M2-02 property 6,000 outputs, 0 oracle mismatches. 25/25 mutants killed (2 equivalent ones removed by simplifying). Two open questions (R19-F3 re-link, missing anchor). Pushed; no PR opened. |
| 2026-11-21 | Reviewer (via Orchestrator) | Developer | returned (round 1) | CHANGES REQUIRED: F1 Major (re-link per PO ruling 1), F2 and F3 Minor, F4 and F5 Nit. PO rulings `po-m2-wi05.md`: 1 re-link; 2 and 3 accepted as built. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1 fixed (re-link plus tests and oracle, reverse mutant killed); F2, F3 documented and the oracle's own fallback check added; F4 fixed; F5 not changed (reason given). TendIngestion 117, TendSourceScan 63, TendCore 141 green, 0 warnings. 29/29 mutants killed. Review file committed with the fix. |

---

## WI-M2-06 — draft stream assembly over neutral snapshots, the four outcomes with route, `noModel` reasons, the plain note

- **Owner:** Developer  ·  **Branch:** `m2/draft-stream`, from `origin/main` at `2f9f86f` (WI-M2-05 merged, PR #20)
  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): new files under `TendIngestion/Sources`, Foundation and
  TendCore only.
- **Requirements:** FR-A1, P-1, P-3, P-4, UX-3. This item delivers the **Linux parts** of AC-M2-05, AC-M2-10 and
  AC-M2-23 ([plan.md](plan.md) WI-M2-06, all ○). The Mac parts stay with WI-M2-M2 (`PartiallyGenerated` →
  neutral snapshots, `Availability` / `GenerationError` → neutral reasons) and WI-M2-M4 (`URLError` / HTTP status →
  neutral reasons). The retry and deadline decisions of AC-M2-23 are WI-M2-14.
- **Brief inputs:** Definitions ("Draft", "Item completion", "Draft stream events", "Route", "Plain note"), T-03, T-12,
  T-25. **Rulings:** PO WI-M2-04 ruling 2 and WI-M2-05 D6 (commit order), WI-M2-05 D5 (the caller's `draftID`).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. DoR "deps merged" is met (WI-M2-05 is on
  `main`).
- **Parallel work:** WI-M2-07 (duplicate rules) is being built at the same time. This item contains no duplicate
  logic. It only calls an injected `DraftDuplicateCheck` (see D7).

### What changed
All new files are in `Packages/TendIngestion`. No existing source file was changed.
- `Sources/TendIngestion/Stream/ModelRoute.swift`:
  - `CloudProvider` (`openAI`, `anthropic`, `gemini`) and `Route` (`onDevice`, `cloud(provider)`, `none`).
  - `OnDeviceUnavailableReason`: the plan's four reasons, `deviceNotEligible`, `appleIntelligenceNotEnabled`,
    `modelNotReady` and `unsupportedLocale`.
  - `ModelStopReason: Error` (16 cases): the neutral on-device, cloud and stream reasons. An adapter ends its snapshot
    stream by throwing one of them.
  - `NoModelReason` (`onDeviceUnavailable(_)`, `stoppedBeforeFirstDraft(_)`).
  - `RoutedModel` (`onDevice(model)`, `cloud(provider, model)`, `none(reason)`, plus `route`).
- `Sources/TendIngestion/Stream/DraftStreamEvent.swift`:
  - `DraftStreamEvent` (`emitted`, `updated`, `itemSkipped`, `finished`).
  - `DraftStreamOutcome` (`completed`, `interrupted`, `noModel`, `cancelled`), each carrying `route`, with the
    accessors `route`, `input` and `plainNote`.
  - `DiscardedItemReason.stoppedBeforeComplete`.
  - `DraftStreamSummary`, which folds events into the latest drafts in ascending `draftID`.
  - The `DraftDuplicateCheck` protocol and `NoDuplicateCheck`.
- `Sources/TendIngestion/Stream/DraftStreamAssembler.swift`:
  - `ItemSnapshot.hasValueForEveryField` (completion rule (a)).
  - The internal, pure, synchronous `DraftStreamAssembler`. It takes snapshots in and gives events out.
- `Sources/TendIngestion/Stream/DraftPipeline.swift`:
  - The public `DraftPipeline(input:rooms:now:calendar:timeZone:duplicateCheck:)` and
    `events(from: RoutedModel) -> DraftEventSequence`.
  - `DraftEventSequence` is an `AsyncSequence` with `Failure == Never`. Its iterator implements both `next()` and
    `next(isolation:)`.
- `Sources/TendIngestion/Draft/PlainNote.swift`: `PlainNote.draft(for:now:calendar:timeZone:) -> IngestionDraft?`.
- Tests (new, written first; the first build failed with "cannot find type 'ModelStopReason' in scope"):
  - `DraftStreamTests.swift`: the AC-M2-05 oracle table, the event shape tests and the cancellation suite.
  - `DraftStreamOutcomeTests.swift`: AC-M2-10, AC-M2-23, the plain note, calm names and D6.
  - `DraftStreamPropertyTests.swift`: the AC-M2-05 property and its timeline oracle.
- Not changed: `TendCore`, `TendSourceScan`, every protected path and every dependency. `IngestionModel` keeps its
  WI-M2-05 shape. Availability is not a method on the model: the route (WI-M2-09) decides, and `RoutedModel.none`
  carries the reason (D2).

### The rules as built (brief Definitions; each one is tested)
- **Completion (T-03).** An item is complete at the first of three moments:
  - (a) `hasValueForEveryField`;
  - (b) the snapshot holds a later item;
  - (c) the stream finishes normally.

  Only the last item of a snapshot can still be in progress, so items complete in model-output order. On completion,
  `DraftMapper.map` runs the Q5 repairs. A draft gets the next `draftID`, and the counter advances only for a draft
  (D5). A Q5 skip gives `itemSkipped(reason)`.
- **`emitted`.** It comes once per `draftID`, at completion, with the duplicate marker already set.
- **`updated`.**
  - On every snapshot, each emitted draft whose item is still present is mapped again with its own `draftID`.
  - **Round 2 (PO WI-M2-06 ruling 5):** if any draft's content changed, the duplicate check runs again in ascending
    `draftID` for the lowest changed draft and every later emitted draft, each against the latest lower drafts. If no
    content changed, the check is not called (D7).
  - Each draft whose content or marker changed gets exactly one `updated`, which is a full replacement.
  - Within one snapshot, the updates (in ascending `draftID`) come before any new emissions, so a new draft is checked
    against the re-marked drafts.
  - A draft is never withdrawn. If Q5 would now skip the item, or a shorter snapshot no longer holds it, there is no
    event and the last version stays.
- **End.**
  - A normal finish completes the rest of the items, then gives `completed(route)`. **Round 2 (PO WI-M2-06
    ruling 1):** if no draft was emitted (no items, or every item skipped), `completed` also carries the input and the
    plain-note offer (nil only for a blank input). With at least one draft, both are nil.
  - A stop with no draft emitted gives `noModel(route, .stoppedBeforeFirstDraft(reason), input, plainNote)` (T-25,
    AC-M2-23: "`noModel` before any draft").
  - A stop after a draft gives `interrupted(route, reason, discardedItem, input)`. `discardedItem` is
    `stoppedBeforeComplete` when an item was in progress, and nil between items.
  - A thrown error that is not a `ModelStopReason` counts as `otherModelError`.
  - Nothing is accepted after `finished`.
- **Route `none`.** The only event is `finished(noModel(.none, .onDeviceUnavailable(reason), input, plainNote))`. No
  model exists to ask.
- **Order of drafts (binding, PO WI-M2-04 ruling 2 and WI-M2-05 D6).** `draftID`s are 1, 2, 3 … in emission order,
  which is the model's output order. **Confirmed drafts go to commit in ascending `draftID`.** The API docs of
  `DraftStreamEvent.swift` say this, and `DraftStreamSummary.drafts` is already in that order (test "D6 …").

### Decisions the Reviewer should know
- **D1, completion rule (a): the field set (WI-M2-05 follow-up).**
  - The schema fields are the nine fields of `ItemSnapshot`: title, kind, roomName, effort, the three flags, time and
    sourcePhrase.
  - An unknown enum value counts as a value (T-03).
  - `time` counts once its `anchor` is set. The other hint fields depend on the anchor and are absent for most
    anchors, so requiring them would mean rule (a) almost never fires. Later hint fields arrive as `updated`.
  - An item whose model leaves `roomName` or `sourcePhrase` out never meets (a). It completes by (b) or (c), which is
    only later, never wrong.
  - This sets a technical moment, not a product meaning. It affects TTFI (AC-M2-16), so it is listed under the open
    questions for the PO to confirm.
- **D2, where availability lives.** `IngestionModel` is unchanged. Routing (WI-M2-09) reads the on-device
  availability and the cloud state and gives a `RoutedModel`. The pipeline holds **exactly one** model, or none. It
  therefore has no way to re-route an on-device error to the cloud (AC-M2-10, AC-M2-19, P-3), and no way to retry or
  queue (AC-M2-23). This is a type-level proof, not a promise. WI-M2-09 may add a protocol for reading availability.
  The neutral reasons it needs are already here.
- **D3, the neutral reason names (AC-M2-23 "none blames the user"; Reviewer inspection).** The mapping comment table
  at the top of `DraftStreamOutcomeTests.swift` maps each brief case to its reason. For example, 401/403 is
  `keyNotAccepted` (the provider did not accept the stored key), and 5xx is `serviceUnavailable`. No name refers to
  the person. `calmNames` splits every outcome, reason and event description at camelCase and checks it against the
  banned list. The AC-M2-12 vocabulary scan also covers the source (0 violations).
- **D4, cancellation is cooperative (Swift structured concurrency).**
  - At the top of every `next()`, a cancelled task gets `finished(.cancelled(route))` next. Any buffered events are
    dropped (cancellation wins over an outcome that has not been delivered yet). The iterator then lets go of the
    model's `AsyncThrowingStream`, which ends the model's work through its termination handler. After that, `next()`
    returns `nil`. The model stream is released when `cancelled` is returned, not later when the consumer drops the
    iterator (test "the cancelled event already releases the model stream …", which holds the iterator).
  - If the task is cancelled while it waits for the model, `AsyncThrowingStream` returns early with a nil or a throw.
    The pull buffers whatever that gives, but the top-of-loop check runs before any event is returned, so it is read
    as cancellation, never as `completed` (tests "cancel while waiting" and "… finishing after cancellation …").
    There is one cancellation check, at one place. An earlier second check inside the pull was redundant (an
    equivalent mutant) and was removed.
  - The cancellation tests run the consumer in its own task and pass the test's own cancellation on to it
    (`consumeInOwnTask`). So a broken rule makes a test fail at its time limit instead of hanging. A first mutation
    pass showed that hang, and it was fixed before the final run.
  - There is no clock, timer, `DispatchQueue`, lock or `@unchecked Sendable` in the sources. The iterator is a plain
    value type and runs in the caller's isolation through `next(isolation:)`.
  - "No task is written" holds by construction: neither the pipeline nor the assembler has a repository. The
    cancellation test also loads an in-memory repository before and after.
- **D5, the plain note (brief Definitions).**
  - The title is the whole input, **trimmed at both ends only**, so inner spacing and newlines are the user's. That is
    the literal "(trimmed)" of the brief. Q5 step 1 also collapses whitespace, but that step is for model titles.
  - The calm-words guard is not run, because every word is the user's own and AC-M2-12 keeps a user's words (test:
    "I'm late paying the gas bill" is kept).
  - The fields are the Q5 defaults (the T1 window from the resolver, default dayparts, all weekdays, one-off, normal,
    no room, flags false, no interval). `sourcePhrase` is nil, `duplicate` is `none` and `draftID` is 1.
  - The plain note is nil for a blank input, or when the M1 initialiser rejects it (only with a non-finite `now`).
  - It is an **offer** inside `noModel`, never an `emitted` event. Only `commit(confirmed:)` (WI-M2-08) saves it.
- **D6, `interrupted` never carries a plain note** (confirmed by PO WI-M2-06; the brief sentence is replaced). By the
  AC-M2-23 / T-25 rule, a stop before any draft is `noModel`, so an `interrupted` outcome always
  has at least one draft. Its case therefore has no `plainNote` field, and `plainNote` returns nil.
- **D7, duplicate marking is injected, and the hook point fits WI-M2-07 (stays out of WI-M2-07).**
  - **Hook point:** `DraftStreamAssembler.completeNext()`, the one place a draft is created. It calls
    `DraftDuplicateCheck.duplicate(of:earlier:)` **exactly once per draft position, in output order, before that
    draft's `emitted`**. `earlier` holds every draft with a lower `draftID` (latest versions, ascending). Skipped items
    take no position.
  - This matches the contract the Orchestrator relayed for WI-M2-07 (PR #21, not merged):
    `DuplicateMarker.mark(_:position:claim:check:)`, "once per draft position, in output order, before `emitted`".
    This branch does not depend on that file. Integration after both merge is a small conformance of the WI-M2-07
    marker to `DraftDuplicateCheck`, or a rename of this one call.
  - **Round 2 (PO WI-M2-06 ruling 5; review F2): the stream re-marks after updates.**
    - A snapshot that changes any emitted draft's content re-runs the check, in ascending `draftID`, from the lowest
      changed draft through every later emitted draft, each against the latest lower drafts. This covers `ofDraft`
      cascades: a later draft whose content is unchanged still gets an `updated` if its marker changes.
    - No content change means no call. Emission is unchanged.
    - Invariant (tested): after `finished`, each marker equals one pass of the check over the final drafts in
      `draftID` order.
    - The round 1 trade-off (a stale marker after an update) is closed. The calling rule is stated once, in the
      `DraftDuplicateCheck` doc (review F3).
  - **For WI-M2-07 integration:** the relayed contract "once per draft position, before `emitted`" still holds at
    emission. The WI-M2-07 marker must also accept being called again for a position after an update (ruling 5). Its
    claim must come from the latest item (`DraftMapper` re-maps the latest snapshot).
  - `DraftPipeline.init` requires the check. No default is given, so that M3 cannot forget the WI-M2-07 rules.
- **D8, a skipped item stays skipped.** Completion is final. If a later snapshot gives a skipped item a title, there
  is no late emission, because the brief says "at the moment of completion" (test "a skipped item stays skipped …").
- **D9, the scan rules shaped the names.** The AC-M1-23 `Stream(` rule bans calling any identifier that ends in the
  word "Stream", apart from `AsyncStream` and `AsyncThrowingStream`. So the public type is `DraftPipeline` and the
  sequence is `DraftEventSequence`. `AsyncThrowingStream.makeStream` is used only in tests, which are out of scan
  scope.

### AC coverage
| AC (Linux part) | Test(s) | Result |
|---|---|---|
| AC-M2-05 oracle | "AC-M2-05: the scripted snapshots give exactly the expected event list" (pure assembler, and `DraftPipeline` with a mock model): **16 scripted cases × 2**. They cover fields out of order, an item split across snapshots, rule (b), a no-title item (no `draftID` used), a normal finish mid-item (emitted, and skipped without a title), a throw mid-item (discarded, `interrupted`), a throw between items, a foreign error, model-output order versus `sourcePhrase` order, several completions in one snapshot, never withdrawn (blank re-map, shrinking snapshot), updates before emissions, a skipped item staying skipped, an empty output, and a calmed title | PASS (Linux) |
| AC-M2-05 rules | "an item still in progress at a normal finish is completed and repaired by Q5" (whole draft, M1 initialiser); "emitted and updated drafts are whole replacements …; finished comes once, last"; "nothing follows finished"; "the duplicate marker is set once, before emitted, and an update keeps it"; "the duplicate hook is called exactly once per draft position, in output order, before emitted" (D7); "the model is asked once, with the capture text and the room names"; "lazy and repeatable"; "after finished, the iterator returns nil"; "every outcome carries the route" (on device and 3 providers); "the sequence never throws" is shown at compile time (`for await` with no `try`; `Failure == Never`) | PASS (Linux) |
| AC-M2-05 property | "AC-M2-05: 6,000 seeded scripts give exactly the oracle's events, and the event rules hold". Seeds `0x0A11C0DE5EED0601…0603`, 2,000 scripts each, against an independent **timeline oracle** (completion steps first, then events; rule (a) written out again). It also checks the structural rules on every script. Coverage requires every event kind, every outcome, `discarded` and a duplicate marker on every seed | PASS (Linux): **0 oracle mismatches**. Per seed (0601 / 0602 / 0603): emitted 3,508 / 3,444 / 3,541; updated 519 / 547 / 526; itemSkipped 891 / 877 / 912; completed 1,185 / 1,199 / 1,225; interrupted 553 / 534 / 513 (discarded 356 / 359 / 331); noModel 262 / 267 / 262; marked duplicates 553 / 528 / 552 |
| AC-M2-05 cancellation | Cancel while waiting for the model (earlier events stay, then `cancelled`; model stream ended `.cancelled`; repository unchanged); a consumer that cancels itself mid-buffer (the buffered events are dropped); the model stream already ended while the consumer still holds the iterator, and `next()` is nil after `finished`; cancelled before start (on device, cloud, none: only `cancelled`, model never asked); a late model finish after cancellation still gives `cancelled`; the assembler's `cancel` | PASS (Linux) |
| AC-M2-10 | "cloud off and on-device unavailable (each reason)": 4 cases, route `none`, the input and a plain note returned, only the `finished` event. "on-device generation throws before the first draft (each reason, cloud on or off)": 9 reasons × 4 scripts (at once, after an empty snapshot, after a skipped item, with an item in progress); route `onDevice`; asked once. "a throw after the first draft is interrupted" (T-25): 9 cases. A foreign error gives `otherModelError` | PASS (Linux) |
| AC-M2-23 (outcome, plain note) | "each cloud failure before any draft": 3 providers × 10 reasons × 4 scripts, `noModel` with route, input and plain note; asked once (no retry here, nothing queued). "each cloud failure after a draft": 30 cases, `interrupted`, no plain note, the input returned, the draft stays. "the same plain-note offer exists when the route is none" | PASS (Linux). The retry and deadline decisions are WI-M2-14 |
| Plain note | 6 tests: the user's words trimmed at both ends only (3 inputs, compared to a hand-written draft); the user's banned word kept; blank gives nil (3); passes the M1 initialiser and becomes an `active` task; non-finite `now` gives nil (compared to a Bool first, because describing a NaN `Date` in a failure message traps on Linux, as in WI-M2-05 round 2); a blank input gives `noModel` with no note and the input still returned | PASS (Linux) |
| AC-M2-10 / AC-M2-23 names (UX-3) | "no outcome, reason or event name contains a banned token" (camelCase split); "the neutral reason lists are complete". AC-M2-12 vocabulary scan: `18 files, 9 exempted (the list), 0 violations` | PASS (Linux) + Reviewer inspection (D3) |
| AC-M2-09 (regression) | "AC-M2-09: Rules 1–6 hold …": `18 files in total, 0 violations` | PASS (Linux) |

### Test runs
| Command (in `swift:6.2-noble`, Swift 6.2.x, `-Xswiftc -warnings-as-errors`) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 152 tests in 18 suites passed after 9.156 seconds.` (117 before this item + 35 new) |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 89.574 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 4.754 seconds.` (unchanged package) |

### Mutation check
Each mutant was applied alone by a script, run with `--filter "DraftStream|NoModel|CloudOutcome|PlainNote"` and
`-warnings-as-errors` inside a 420 s timeout, and then restored. After the run, the sources were compared with a
pristine copy (`diff -r`: identical). **27 of 27 are killed on the final code, with no hang and no crash.** The final
clean run is the 152-test line above.

| # | Mutant | Killed by (number of failing tests) |
|---|---|---|
| 0 | completion rule (a) off | property, scripted ×2, whole replacements, routes, nothing after finished, marker (7) |
| 1 | rule (b) off | property, scripted ×2, self-cancel mid-buffer, release at once (5) |
| 2 | rule (c) off (normal finish does not complete the rest) | property, scripted ×2, Q5 at finish, hook contract, lazy, iterator end, D6 summary (8) |
| 3 | `draftID` counter advances on a skip | property, scripted ×2, hook contract (4) |
| 4 | no `updated` events | property, scripted ×2, whole replacements, hook contract, marker, D6 summary (7) |
| 5 | new emissions before updates in one snapshot | property (1) |
| 6 | a blank re-map withdraws / emits the old draft again | property, scripted ×2 (3) |
| 7 | marker not set at emission | property, hook contract, marker (3) |
| 8 | marker checked again on update (the hook is called twice) | property, hook contract, marker (3) |
| 9 | `noModel` even after a draft | property, scripted ×2, routes, T-25, AC-M2-23 after a draft (6) |
| 10 | `interrupted` even before a draft | property, AC-M2-10 ×2, AC-M2-23 before any draft (4) |
| 11 | discarded item never reported | property, scripted ×2, T-25, AC-M2-23 after a draft (5) |
| 12 | a foreign error read as `refusal` | scripted ×2, AC-M2-10 foreign error (3) |
| 13 | `noModel` without the plain note | property, AC-M2-10 ×2, AC-M2-23 (4) |
| 14 | input not returned with `interrupted` | property, scripted ×2, routes, T-25, AC-M2-23 (6) |
| 15 | events accepted after `finished` | nothing after finished (1) |
| 16 | rule (a) ignores `sourcePhrase` | property (1) |
| 17 | rule (a) counts a time hint with no anchor | property (1) |
| 18 | no cancellation check in `next` | self-cancel, before start, while waiting, release at once, late finish (5) |
| 19 | buffered events delivered before `cancelled` | self-cancel, while waiting (2) |
| 20 | cancellation keeps the model stream until the iterator is dropped | release at once (1) |
| 21 | cloud route reported as `onDevice` | before start, routes, AC-M2-23 ×2 (4) |
| 22 | no room names in the model request | model asked once (1) |
| 23 | plain note collapses inner whitespace | plain note user words (1) |
| 24 | plain note not trimmed | plain note ×3 (3) |
| 25 | plain note returned when the M1 initialiser rejects it | non-finite `now` (1) |
| 26 | plain note `sourcePhrase` = title | AC-M2-10 ×3, AC-M2-23 ×2, plain note (6) |

**What the earlier passes found (and what changed because of them):**
- **Hang.** In the first pass, the "rule (b) off" and "no cancellation check" mutants **hung** instead of failing:
  - the self-cancel test awaited an unstructured `Task.value`, which does not pass on the time-limit cancellation;
  - and a cancelled wait looped on a finished iterator.

  Fixes: the tests run the consumer in `consumeInOwnTask`, and the pull no longer has its own cancellation branch.
- **Survivor.** The "keeps the model stream" mutant survived until the test "the cancelled event already releases the
  model stream …" was added.
- **Equivalent mutant.** A second cancellation check inside the pull was redundant with the top-of-loop check, so it
  was removed.
- **Crash.** The non-finite-`now` plain-note test crashed instead of failing under its mutant, because a NaN `Date`
  in a failure message traps on Linux. It now compares to a Bool first.
- **Spelling.** Three mutants needed spellings that compile under `-warnings-as-errors`.
- **Hook change.** After the WI-M2-07 hook note, mutant 8 was turned into its reverse, and everything was run again
  on the final code.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 152 tests: AC-M2-05, 10, 23 (Linux parts), plain note, AC-M2-09 and AC-M2-12 scans | ✔ container | — | — | — | Linux CI runs on the PR. |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| `next(isolation:)` and `AsyncThrowingStream` cancellation on Darwin | — | — | — | — | Not verified (no Mac). The plan B2 repeat of the `TendIngestion` suite on the owner-run Mac covers it. |
| Adapter mappings (`PartiallyGenerated`, `Availability`, `GenerationError`, `URLError`/HTTP) to these neutral values | — | — | — | — | Not in this item: WI-M2-M2 and WI-M2-M4 on the owner-run Mac. |

Device ACs: none in this item.

### Things the reviewer should look at closely
- The iterator in `DraftPipeline.swift`: the cancellation order (D4), `next(isolation:)` passing the caller's actor
  to the model iterator, and the unreachable `.ended` branch, which ends calmly instead of trapping.
- The update rule (re-map every emitted draft on each snapshot, keeping its emission marker). It costs
  O(drafts) mappings per snapshot. Brain-dumps hold a handful of items, so this is fine. The cost of `DraftMapper.map`
  is pure string work.
- D1 (the rule (a) field set) and D5 (the plain note trimmed only, no guard).
- The oracle's independence: the timeline oracle shares `DraftMapper.map` (AC-M2-01/02) and the test double for
  duplicates. It computes completion and update moments itself, and it does not call `hasValueForEveryField`.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Conform the WI-M2-07 marker (`DuplicateMarker.mark`, PR #21) to `DraftDuplicateCheck` after both merge. It is called at emission and again by the ruling 5 re-mark (D7) | — | Integration after WI-M2-06 and WI-M2-07 merge; before WI-M2-08 |
| Rule (a) can fire while a title is still a prefix, when a model sends fields out of declaration order (cloud JSON). The draft is emitted as "Buy" and corrected by `updated`, with a re-mark. The calm-words guard can remove a partial token (for example "Late" of "Latex gloves"), which a later update restores. Within the Definitions (PO ruling 2) and self-correcting (review F5, watch) | watch | WI-M2-12/13: test a title that arrives last; dev-set eval |
| Adapter contract (end with a `ModelStopReason`; do not keep the returned stream; cancel all work in `onTermination`) is now in the `IngestionModel` doc (review F4). Part (3) is tested on the Mac | — | WI-M2-M2, WI-M2-M4, WI-M2-09 |
| Routing produces `RoutedModel`, and its matrix uses `OnDeviceUnavailableReason` and `CloudProvider` from here | — | WI-M2-09 |
| Adapters throw `ModelStopReason`; the mapping table is in `DraftStreamOutcomeTests.swift` | — | WI-M2-M2, WI-M2-M4, WI-M2-13 |
| Commit takes confirmed drafts in ascending `draftID` (D6) and saves a plain note only on confirm | — | WI-M2-08 |
| Not verified on Darwin | — | Plan B2, MS-2 |

### Open questions (PO; built to the most literal reading, work continues)
1. ~~**`completed` with no draft.**~~ **Closed: PO WI-M2-06 ruling 1.** Offer the input and the plain note. Built in
   round 2.
2. ~~**Rule (a) field set (D1).**~~ **Closed: ruling 2 confirms it as built.** Watch: a single item whose model leaves
   out `roomName` or `sourcePhrase` completes only at (c).
3. ~~**Plain note title (D5).**~~ **Closed: ruling 3 confirms it as built.**
4. ~~**`cancelled` returns no input.**~~ **Closed: ruling 4 confirms it as built.** For M3: an app-initiated cancel
   keeps the input itself.
5. ~~**A marker after an update (D7).**~~ **Closed: ruling 5.** The stream re-marks. Built in round 2 (D7).

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every draft field is still inferred (Q5). The plain note is one free-text draft with defaults. Nothing asks the user for a field. |
| UX-2 Rule of Three | pass | The stream is a capture review API, not a "what to do now" surface. It exposes no candidates or next-up list. Drafts reach Now only after commit, through `NowSelector`. |
| UX-3 Zero-Guilt | pass | Every title passes the calm-words guard before any event (scripted case and property). Outcome and reason names are calm and do not blame the user (D3; test plus the vocabulary scan, 0 violations). There is no failure or late state, and an error before a draft is a calm `noModel` with the user's words kept. |
| UX-4 Design craft | n.a. | No UI. Copy and motion for these outcomes are M3. |
| P-1 On-device inference | pass | The pipeline holds one routed model and never re-routes an on-device error to the cloud (D2; route stays `onDevice` in the AC-M2-10 tests). |
| P-2 No data leaves device (except user iCloud) | pass | There is no networking (AC-M2-09 scan, 0 violations). The model request holds only the capture text and room names (ADR-0005 Decision 3). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | No consent or routing logic here (WI-M2-09). The neutral cloud reasons map to calm outcomes. There is no retry or queue in the stream. |
| P-4 Media not persisted without consent | pass | No write or log API. The input text is returned only in memory, and the plain note is saved only by commit. Cancel writes nothing. |

### Round 2 (review round 1: CHANGES REQUIRED; PO rulings `po-m2-wi06.md`)
The review is committed with this fix: [review-WI-M2-06.md](review-WI-M2-06.md). The numbers in this section replace
the round 1 test and mutant numbers above.

| Finding | Change |
|---|---|
| **F1 Major** (PO ruling 1) | `completed(route:input:plainNote:)`. The two new payloads default to nil. They are filled only when no draft was emitted, and the note is nil only for a blank input. The `input` and `plainNote` accessors return them. Tests: scripted cases "no items at all" (flipped), "every item skipped" (three `itemSkipped`, then `completed` with input and note) and "one draft then a normal finish" (both nil); a blank input with an empty output (input "  ", note nil); zero-draft `completed` on all 4 routes; accessors. The property oracle builds the outcome from its own count of `emitted` events, and `checkRules` checks both branches (`completedNoDraft` about 255 per seed). The two ruling 1 mutants are killed (12, 13). |
| **F2 Major** (PO ruling 5) | `DraftStreamAssembler.refreshEmitted` works in three steps: (1) re-map the content of every emitted draft whose item is present; (2) if any content changed, run the check in ascending `draftID` from the lowest changed draft through every later draft, each against the latest lower drafts; (3) give one `updated` per draft whose content or marker changed. With no change there is no call. Updates still come before new emissions. Tests: "markers are re-checked after an update" (the flipped "set once" test); 5 re-mark cases (none to duplicate, duplicate to none, cascade with content unchanged, re-mark before a new emission, only the higher draft re-marked), each through both the assembler and the pipeline; the hook call log (flipped: (1, []), (1, []), (2, [1]), (3, [1, 2])); "a repeated identical snapshot calls the hook no more"; the invariant test (final markers = one pass over the final drafts). The property oracle writes the rule as a fresh marking pass from the first changed draft and checks the invariant on every script (0 misses). Mutants killed: "marker kept on update" (the round 1 code), "no cascade", "re-mark after new emissions", plus "re-mark even when nothing changed" and "re-mark against stale lower drafts". D7, the follow-ups and open question 5 are updated. |
| **F3 Minor** | The calling rule is stated once, in the `DraftDuplicateCheck` doc. `DraftPipeline.init` points to it. |
| **F4 Minor** | The `IngestionModel` doc now states the adapter contract: (1) end with a `ModelStopReason`; (2) do not keep the returned stream; (3) cancel all work in `onTermination`. The stale "added by WI-M2-06" sentence is replaced. Part (3) is for WI-M2-M2/M4 on the Mac (follow-up table). |
| **F5 Minor (watch)** | Recorded under "Known limitations". No code change. |
| **F6 Minor** | The cancellation tests read through `collectBounded`: it stops at the first `finished`, calls `next()` once more (which must be nil) and caps at 64 events. `cancelBeforeStart` gains a time limit. Reviewer mutant **M7** ("`isDone` not set on the cancellation path") is now killed by 5 assertion failures, with no hang. |
| Brief | The PO's amendments, applied word for word to `brief.md`: the Definitions `updated` and `completed` bullets, the replaced `interrupted` sentence, the AC-M2-05 `updated` bullet sentence and the new AC-M2-05 bullet. No protected path is touched. |
| Nit | The long header line in `DraftStreamAssembler.swift` is wrapped. |

**Round 2 test runs** (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 157 tests in 18 suites passed after 9.546 seconds.` (152 + 5 new: re-mark cases, no update no calls, invariant, blank input `completed`, zero-draft `completed` per route; others extended). AC-M2-09 `18 files in total, 0 violations`; AC-M2-12 vocabulary `18 files, 9 exempted (the list), 0 violations` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 89.956 seconds.` (unchanged) |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 3.710 seconds.` (unchanged) |

**Round 2 AC-M2-05 property:** seeds `0x0A11C0DE5EED0601…0603`, 2,000 scripts each, **0 oracle mismatches, 0 invariant
misses**. Per seed (0601 / 0602 / 0603):

| Count | 0601 | 0602 | 0603 |
|---|---|---|---|
| emitted | 3,508 | 3,444 | 3,541 |
| updated | 533 | 557 | 545 |
| scripts with a re-marked update | 31 | 32 | 39 |
| completed (of which with no draft) | 1,185 (255) | 1,199 (254) | 1,225 (259) |
| interrupted | 553 | 534 | 513 |
| noModel | 262 | 267 | 262 |

The coverage check now also requires `completedNoDraft` and `remarked` on every seed.

**Round 2 mutation check: 33 of 33 killed on the final code**, with no hang and no crash. The sources were identical
to the pristine copy afterwards. Each mutant was run with `--filter "DraftStream|NoModel|CloudOutcome|PlainNote"`
under a 420 s timeout.

| # | Mutant | Failing tests |
|---|---|---|
| 0 | rule (a) off | 9 |
| 1 | rule (b) off | 5 |
| 2 | rule (c) off | 10 |
| 3 | `draftID` counter advances on a skip | 4 |
| 4 | no `updated` events | 8 |
| 5 | re-mark after new emissions (emissions before updates) | 4 |
| 6 | `updated` for unchanged drafts too | 2 |
| 7 | marker not set at emission | 6 |
| 8 | **marker kept on update** (the round 1 behaviour, reverse of ruling 5) | 5 |
| 9 | **no cascade to later drafts** | 4 |
| 10 | re-mark even when nothing changed | 2 |
| 11 | re-mark against stale lower drafts | 4 |
| 12 | **no plain note on `completed` with 0 drafts** | 5 |
| 13 | **plain note on `completed` with ≥ 1 draft** | 10 |
| 14 | `noModel` even after a draft | 6 |
| 15 | `interrupted` even before a draft | 4 |
| 16 | discarded item never reported | 5 |
| 17 | a foreign error read as `refusal` | 3 |
| 18 | `noModel` without the plain note | 4 |
| 19 | input not returned with `interrupted` | 6 |
| 20 | events accepted after `finished` | 1 |
| 21 | rule (a) ignores `sourcePhrase` | 1 |
| 22 | rule (a) counts a time hint with no anchor | 1 |
| 23 | no cancellation check | 5 |
| 24 | buffered events before `cancelled` | 2 |
| 25 | cancellation keeps the model stream | 1 |
| 26 | **M7: `isDone` not set on the cancellation path** (reviewer) | 5 (assertions, no hang) |
| 27 | cloud route reported as `onDevice` | 5 |
| 28 | no room names in the model request | 1 |
| 29 | plain note collapses inner whitespace | 1 |
| 30 | plain note not trimmed | 4 |
| 31 | plain note returned when the M1 initialiser rejects it | 1 |
| 32 | plain note `sourcePhrase` = title | 9 |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Developer | accepted (H2) | WI-M2-06 Ready: WI-M2-05 merged (`2f9f86f`). Binding: D6 commit order; Linux parts only; no cloud transport. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 152 green, TendCore 141, TendSourceScan 63, 0 warnings, Linux. AC-M2-05 property 6,000 scripts, 0 oracle mismatches. 27/27 mutants killed (no hang, no crash). 5 PO open questions; D7 duplicate hook point fits the WI-M2-07 contract. Pushed; no PR opened. |
| 2026-11-21 | Reviewer (via Orchestrator) | Developer | returned (round 1) | CHANGES REQUIRED: F1, F2 Major (PO rulings 1, 5 in `po-m2-wi06.md`); F3–F6 Minor (F6: M7 hangs the suite). |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1 and F2 built with tests, oracle and reverse mutants; F3, F4, F6 fixed; F5 recorded. Brief amended as the PO wrote. TendIngestion 157, TendCore 141, TendSourceScan 63 green, 0 warnings. 33/33 mutants killed, M7 by assertion. Review file committed with the fix. |

## WI-M2-07 — duplicate rules: shortlist, the neutral lookup the `Tool` wraps, in-input collapse, cloud re-check (Q12 yes) and local word-match (Q12 no)

- **Owner:** Developer  ·  **Branch:** `m2/duplicate-rules`, from `origin/main` at `2f9f86f` (WI-M2-01 and 05
  merged)  ·  **PR:** #21  ·  **Review:** [review-WI-M2-07.md](review-WI-M2-07.md) (round 1 CHANGES REQUIRED; reworked
  in round 2, see "Round 2" below)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): new files under `TendIngestion/Sources`, Foundation and
  TendCore only, no I/O, no logging.
- **Requirements:** FR-A1, Q7, Q12, T-06, UX-3. **Linux half of AC-M2-07 (○) and the marking half of AC-M2-08 (○)**
  ([plan.md](plan.md) WI-M2-07). WI-M2-M2 owns the `Tool` conformance (owner-run Mac). WI-M2-08 owns commit and closes
  AC-M2-08 (●). Brief inputs: Definitions ("Keywords of a text", "Duplicate shortlist", "Local duplicate re-check for
  cloud drafts", "Duplicate", "Draft stream events"), Q7, Q12. Binding inputs: PO WI-M2-05 ruling 1 (the word-match may
  rely on "a proposed room never equals an existing room"; commit still re-checks) and the confirmed-draft order (ascending
  `draftID`, D6).
- **Q12:** still open with the owner (`owner-decisions.md`: PO default yes). **Both paths are built behind a parameter,
  `CloudTitleSharing`** (`.shortlistTitles` = yes, `.noTitles` = no), as the plan says.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. DoR "deps merged" is met.
- **Parallel work:** WI-M2-06 (stream assembly) is being built in another worktree. This item does not touch
  `IngestionModel.swift`, `ItemSnapshot` or anything in stream assembly (see "Integration points").

### What changed
New directory `Sources/TendIngestion/Duplicates/`. Everything in it is a pure function or value type.
- `DuplicateShortlist.swift`: `ShortlistEntry` (index 1…n, `taskID`, title as stored and trimmed, kind, room name) and
  `DuplicateShortlist.entries(for:in:)`, which applies steps 1–6 exactly, with `limit = 10`.
- `DuplicateLookup.swift`:
  - `DuplicateLookupEntry` holds title, kind and room name, and **no ID**.
  - `DuplicateLookup.entries(for:in:)` is the neutral function the `Tool` wraps. It is exactly the shortlist, reduced
    to those three fields.
  - `DuplicateLookupLog` is a value type. It records each Tool call (query and shortlist) so that a model's title claim
    can be turned back into a task ID on the phone (`taskID(forTitle:)`).
- `LocalWordMatch.swift`: `LocalWordMatch.target(title:room:in:)` and `target(for:in:)`, the Q12 = no rule exactly.
- `DuplicateMarker.swift`:
  - `DuplicateClaim` is what the model said about an item: `sameAsItem` (an earlier 1-based position),
    `sameAsShortlistIndex` (cloud, Q12 = yes) or `sameAsTitle` (on device, a title the Tool returned).
  - `ExistingTaskCheck` is the evidence per path: `.toolLookups(log)`, `.sentShortlist(entries)` or
    `.localWordMatch(household)`.
  - `CloudTitleSharing` is the Q12 parameter. `existingTaskCheck(capture:household:)` gives the payload's own
    shortlist under yes and the word-match under no.
  - `DuplicateMarker.mark(_:position:claim:check:)` is called once per draft, in output order, before `emitted`.
  - `DuplicateRecheck.atCommit(_:in:)` is the commit-time re-check of `ofExisting`.
  - `DraftDuplicate.createsTask` is true only for `none`.
- Tests (written first; the first build failed with "cannot find type 'ShortlistEntry' in scope"):
  - `DuplicateRulesTests.swift`: hand-written AC-M2-07 cases (5 suites).
  - `DuplicateOracle.swift`: the independent oracle.
  - `DuplicatePropertyTests.swift`: the AC-M2-07 property and the AC-M2-08 marking property.
  - `DuplicateFixtures.swift`: builders only, no rule logic.
- Not changed: `TendCore`, `TendSourceScan`, `IngestionModel.swift`, `IngestionDraft.swift`, every protected path, every
  dependency.

### Decisions the Reviewer should know (technical choices or literal readings; each one is tested)
- **D1, how an on-device claim names an existing task.** The Tool returns no IDs (AC-M2-07), so the model names the
  entry by its **title**. `DuplicateLookupLog.taskID(forTitle:)` takes the first entry, in call order and then rank
  order, whose title equals the claim after the keyword fold (`TextFolding.foldWithoutArticle`: case, diacritics, width,
  quotes and whitespace, with no article strip). A title that no lookup in this parse returned is ignored, so a model
  can only point at tasks the local Tool actually showed it. This is a technical choice; WI-M2-M2 may refine it (open
  question 2).
- **D2, the in-input collapse goes to the first draft.** A valid `sameAsItem` k (1 ≤ k < own position, and k became a
  draft) gives `ofDraft` of k's draft ID. If k is itself `ofDraft(r)`, it gives `ofDraft(r)`. This is AC-M2-07's
  wording: "a repeat within one input collapses into its first draft". Positions count every item in the model's output,
  skipped ones included, and are mapped to `draftID`s. A claim pointing at a skipped item is ignored. The brief writes
  `ofDraft(k)` with k as the position; the type's associated value is a `draftID` (WI-M2-05), so the marker converts.
  When nothing is skipped, the two are the same.
- **D3, precedence (round 2, PO WI-M2-07 rulings 1 and 3).** Per draft: (1) a valid in-input claim → `ofDraft`;
  (2) the model's valid existing-task claim (on device: a title the Tool returned; Q12 = yes: a valid shortlist index)
  → `ofExisting`; (3) the **word-match floor**, `LocalWordMatch.target` over the whole household, on **every** path →
  `ofExisting`; (4) `none`. An invalid claim falls through to the next step. Under Q12 = no, step 2 does not exist.
  Commit creates nothing for (1)–(3). Choosing `ofDraft` keeps the draft out even if the `ofExisting` target is gone by
  commit time, because the first draft is then created.
- **D4, a claim for another path is ignored (round 2: the floor half is reversed by PO WI-M2-07 ruling 1).** On device,
  only `sameAsTitle` counts as a claim. Under Q12 = yes, only `sameAsShortlistIndex` counts. Under Q12 = no, the index
  and title claims are ignored. **Round 1 said the on-device path never falls back to the word-match. That is
  superseded:** every path now ends with the floor, so the round 1 mutant M6 is now the built behaviour. Its reverse
  mutants are killed (Round 2 mutation table).
- **D5, a task's room.** A task's room is the **first** household room with its `roomID`. A `roomID` that matches no
  room means "no room" in both the shortlist (no R, no room name) and the word-match (compatible with anything). The
  brief does not cover a dangling `roomID`, and M1 does not forbid it.
- **D6, the last tie-break.** Steps 5a–5d settle every case except two tasks with the same `id` (forbidden by W3-F6 but
  not by the type). Household order is used for that, so the sort is total. The oracle uses the same rule. The
  coverage log shows `offset 0`: it never decides in the property.
- **D7, trimming.** The entry title is `title.trimmingCharacters(in: .whitespacesAndNewlines)`, which is "as stored
  (trimmed)". Inner whitespace is not collapsed.
- **D8, the re-check at commit.** `DuplicateRecheck.atCommit` keeps `ofExisting(id)` only while a task with that ID
  exists and is not `completed`; otherwise it gives `none`. `ofDraft` and `none` pass through unchanged. What commit
  does with an `ofDraft` whose first draft was dismissed is WI-M2-08's decision (open question 3).
- **D9, the oracle's independence** (file header of `DuplicateOracle.swift`). The oracle calls **no** `TendIngestion`
  code, not even the WI-M2-04 primitives:
  - its own fold (a literal quote table plus Foundation `folding` in `en_US_POSIX`, the brief's primitive);
  - its own `Character.isLetter || isNumber` split, on a restricted generator alphabet;
  - the stop-word list pasted from the brief's text;
  - its own byte comparison;
  - ranking by repeated selection, not a sort;
  - a brute-force word-match;
  - its own position table for the collapse.
  So, unlike WI-M2-05, the property also catches a defect in `Keywords.of` or `TextFolding.foldWithoutArticle` (for
  example, mutant S10 "article stripped in key" is killed by both properties).

### Integration points (for WI-M2-06, 08, 10, 12 and M2; nothing in their code is changed here)
- **WI-M2-06, stream assembly.** At each item completion, call `marker.mark(draft, position:, claim:, check:)` before
  `emitted`. `position` is the 1-based item position in the output, skipped items included. Keep one `DuplicateMarker`
  per parse. On device, pass `.toolLookups(currentLog)`. For cloud, pass
  `CloudTitleSharing.<answer>.existingTaskCheck(capture:household:)`, computed once per capture.
- **The claim's source field.** `ItemSnapshot` has no duplicate field yet. Which output field carries `sameAsItem`,
  `sameAsShortlistIndex` and `sameAsTitle` is the schemas' business: WI-M2-M2 `@Generable`, WI-M2-10 cloud schema,
  WI-M2-12 reader. Whether those fields count for item completion rule (a) is WI-M2-06's call. Nothing in this item
  depends on that choice.
- **WI-M2-10.** The Q12 = yes titles are `DuplicateShortlist.entries(for: capture, in: household).map(\.title)`, in
  index order. The marker's `.sentShortlist` must be built from the same call, as `CloudTitleSharing` does.
- **Round 2 shape:** `ExistingTaskCheck.sentShortlist(entries, household)` now carries the household for the floor.
  `.toolLookups(log)` uses `log.household`. `CloudTitleSharing.existingTaskCheck` builds the new shape.
- **WI-M2-08.** Apply `DuplicateRecheck.atCommit` to each confirmed draft (in ascending `draftID`, D6 of WI-M2-05),
  then create a task only when `createsTask` is true.
- **WI-M2-M2.** The `Tool` keeps one `DuplicateLookupLog` per session behind its own isolation (an actor or a
  `Mutex`), returns `lookUp(query)`, and hands a copy of the log to the marker at each completion.

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-07 shortlist | `DuplicateShortlistTests` (13 tests, hand-written): synonym query (entry fields, trimmed title); room-only after keyword matches; completed left out, other states kept; stop-word-only and empty queries (6 cases); a room with no keywords never matches; R needs every room keyword; steps 5a K before R, 5b R before title, 5c folded title in byte order before ID, 5d `uuidString`; more than 10 eligible → first 10, numbered 1…10; rooms that share an ID; a dangling room ID | PASS (Linux) |
| AC-M2-07 `Tool` lookup (neutral half) | `DuplicateLookupTests` (4 tests, 9 cases): lookup = shortlist reduced to title, kind and room name, ≤ 10 (6 queries); `Mirror` shows exactly `["title", "kind", "roomName"]`; reads only the household it is given; the log records calls and returns the same entries, and the household is unchanged (Q7) | PASS (Linux). The `Tool` conformance is WI-M2-M2 (Mac) |
| AC-M2-07 word-match (Q12 = no) | `LocalWordMatchTests` (18 hand-written cases): equal sets; no room on either side; different rooms; proposed against a room; subset with ≥ 2 keywords (both directions); a 1-keyword subset is rejected; equal 1-keyword sets; completed task; no keywords; most shared keywords wins over a lower ID; a tie goes to the lowest `uuidString`; no stemming | PASS (Linux) |
| AC-M2-07 marking, collapse, Q12 parameter, completed, Q7 | `DuplicateMarkingTests` (12 tests): an on-device title claim (folded); an unseen title is ignored; a cloud index 1…count is valid, and 0, −1, count + 1, 11, `Int.max` and `Int.min` are not; Q12 = yes ignores title claims; Q12 = no word-matches and ignores the index; the `CloudTitleSharing` parameter; a completed one-off and a completed restock are never targets on any path; in-input collapse to the first draft (with a skipped position, a claim to itself, a later one and 0); in-input over existing; an invalid in-input claim falls back; the other fields are kept; the household is unchanged (Q7) | PASS (Linux) |
| AC-M2-07 "commit creates nothing for it" (rule half) | `DuplicateRecheckTests`: `ofExisting(live)` kept and `createsTask == false`; completed or missing target → `none`; `ofDraft` kept | PASS (Linux). Commit itself is WI-M2-08 |
| **AC-M2-07 oracle property (T-06)** | "AC-M2-07: 600 seeded households: …". Seeds `0x0D0B1E5EED000701`, `…0702`, `…0703`, 200 households each (3–60 tasks, 0–6 rooms; theme words make > 10 eligible tasks common; repeated and re-cased titles; near-equal UUIDs), 14 queries and 14 word-match drafts per household. Shortlist and lookup equal the oracle, and so does the word-match. Coverage is required on every seed | PASS (Linux): **8,400 queries (24,311 entries), 0 mismatches; 8,400 word-match drafts, 0 mismatches** |
| **AC-M2-08 marking property (Linux half)** | "AC-M2-08: 600 seeded households × 3 paths: …". Seeds `0x0D0B1E5EED000801`, `…0802`, `…0803`. Scripted mock items: fresh, exact title, synonym, in-input repeat, completed repeat, bogus claim, skipped item; each household runs on device (the mock calls the Tool), cloud Q12 = yes and cloud Q12 = no. Per draft: marker = oracle. A planted duplicate the path can see is never `none`. `ofExisting` names a live, non-completed task. `ofDraft` names an earlier draft that is not itself `ofDraft` | PASS (Linux): **0 oracle mismatches** over 3 × 600 draft sets |
| AC-M2-09, AC-M2-12 (regression) | "AC-M2-09: Rules 1–6 hold …": `17 files in total, 0 violations`. "AC-M2-12 vocabulary scan": `17 files, 9 exempted (the list), 0 violations` | PASS (Linux) |

**AC-M2-07 coverage counts** (sum of the three seeds; per-seed lines are in the log). Neighbours in the ranking are
decided at K: 2,399, R: 622, title: 14,850, `uuidString`: 2,027, household order: 0. More than 10 eligible: 741
queries. Room-only entries: 5,530. Completed tasks that share a keyword and were left out: 7,062. Stop-word-only
queries: 1,465, all with an empty shortlist. Word-match classes: equal sets 3,135; subset 1,228; tie on shared count
693; several qualify 819; no match 5,162; 1-keyword subset rejected 1,494; completed equal set left out 1,373; room
incompatible 1,442.

**AC-M2-08 marking counts** (sum of the three seeds, 600 households each; "visible" = the path can see the target):

| Plant | On device: planted / visible / marked | Cloud Q12 = yes | Cloud Q12 = no |
|---|---|---|---|
| exact title | 816 / 813 / 813 | 816 / 760 / 760 | 816 / 816 / 816 |
| synonym (scripted) | 753 / 751 / 751 | 753 / 372 / 372 | 753 / — / 0 (by design: the word-match misses synonyms, brief Q12) |
| in-input repeat | 640 / 640 / 640 | 640 / 640 / 640 | 640 / 640 / 640 |
| completed repeat | 742 / — / 170 (all `ofExisting` of a **live** task with the same folded title; never the completed one) | 742 / — / 0 | 742 / — / 245 (live task with matching keywords) |
| bogus claim | 782 / — / 0 | 782 / — / 0 | 782 / — / 13 (word-match after an invalid in-input claim) |
| fresh | 893 / — / 0 | 893 / — / 0 | 893 / — / 17 (word-match) |

**Round 2:** these round 1 counts are from before the floor. With the floor, every exact plant is marked on every
path (see "Round 2"). The remainder of this paragraph describes round 1.

Not visible means the target was not in what the model saw: on device, more than 10 tasks outrank it even for its own
title. For Q12 = yes, it was outside the 10-title shortlist of the whole capture: 56 exact and 381 synonym plants. The
mock cannot claim those, so commit would create them. That is the brief's design (Q = the capture text, cap 10), but
the size matters (open question 1).

### Test runs
| Command (in `swift:6.2-noble`, Swift 6.2.4, `swift build` first for each package) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 150 tests in 18 suites passed after 14.506 seconds.` (117 before this item + 33 new; `Build complete!`, 0 warnings) |
| `swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 1.318 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 84.900 seconds.` (unchanged package) |

### Mutation check
A script applied each mutant alone to `Sources/TendIngestion/Duplicates/` and ran
`--filter "Duplicate|LocalWordMatch"` with `-warnings-as-errors`, then restored the file. The first run was stopped by
a time limit while mutant M6 was applied. That file was restored by hand, every mutated line was checked against the
original, and the remaining mutants ran in two short batches. Two mutants first "died" only because an unused
variable broke the build (L2, W7). They were rewritten so that they compile, and both are now killed by failing tests.
**32 of 33 killed. 1 is equivalent (M2).**

| Mutant | Killed by (failing tests) |
|---|---|
| S1 completed tasks not excluded | AC-M2-07 property, completed left out, completed not target, AC-M2-08 property (4) |
| S2 a keywordless room matches | 9, incl. "room with no keywords", the stop-word cases, both properties |
| S3 K ascending / S4 R ascending | 8 / 3 (step 5a / 5b tests, both properties) |
| S5 title descending / S6 `uuidString` descending | 7 / 3 (step 5c / 5d, cap test, both properties) |
| S7 cap 11 | cap test, both properties (3) |
| S8 title not trimmed / S9 no room name | synonym query, AC-M2-07 property (2 each) |
| S10 article stripped in the step 5c key | both properties (2), which shows that the oracle is independent of `TextFolding` |
| S11 R ignored | 6 |
| S12 last room with a shared ID wins | rooms that share an ID (1). It **survived** the first run; that test was added |
| L1 lookup drops the room name | lookup = shortlist, AC-M2-07 property (2) |
| L2 title claim compared without folding | on-device claim, AC-M2-08 property (2) |
| L3 last lookup wins / L4 a claim matches any household task | AC-M2-08 property (1) / unseen title, AC-M2-08 property (2) |
| W1 1-keyword subset accepted | 3 |
| W2 proposed room compatible | word-match cases, AC-M2-07 property (2) |
| W3 completed included / W4 tie to the highest ID / W5 fewest shared wins | 4 / 3 / 3 |
| W6 any shared keyword / W7 rooms ignored | 5 / 3 |
| M1 no collapse to the first draft | in-input collapse, AC-M2-08 property (2) |
| **M2 `k <= position`** | **Was equivalent only under the old one-call-per-position contract** (a position was recorded only after its own `mark` call). PO WI-M2-06 ruling 5 allows repeat calls, so it is no longer equivalent (review R21-F6, P6). **Killed in the WI-M2-06/07 integration** by "R21-F6 …: a repeat call for a position that claims itself …" (see that section, mutant M1) |
| M3 index 0 accepted / M4 index off by one | 2 / 4 |
| M5 existing claim before in-input | in-input over existing (1) |
| M6 on-device falls back to the word-match | unseen title, AC-M2-08 property (2) |
| M7 Q12 = no sends the shortlist | Q12 parameter, AC-M2-08 property (2) |
| M8 positions recorded by `draftID` | in-input collapse, AC-M2-08 property (2) |
| R1 completed target kept at commit / R2 `createsTask` true for `ofDraft` | re-check (1 each) |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 150 tests: AC-M2-07 (Linux half), AC-M2-08 marking half, AC-M2-09 and AC-M2-12 scans | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141 tests, TendSourceScan 63 tests (unchanged) | ✔ container | — | — | — | — |
| `Tool` conformance returns exactly the lookup's entries and fields | — | — | — | — | WI-M2-M2, owner-run Mac |
| Keyword folding on Darwin (R-10) | — | — | — | — | Plan B2, owner-run Mac |
| Commit creates nothing for a duplicate; no ID repeated (AC-M2-08 commit half) | — | — | — | — | WI-M2-08 |

Device ACs: none in this item.

### Things the reviewer should look at closely
- D1, title-based on-device claims through `DuplicateLookupLog`, and whether the first match in call order is the right
  tie rule.
- D3, precedence of an in-input claim over an existing-task claim.
- Whether the AC-M2-08 "visible" rule is the right reading of "under the deterministic rule the mock scripts".
  Non-visible plants are counted, not asserted (the table above).
- The oracle's independence (D9) and the generator alphabet it depends on.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| `ItemSnapshot` and the schemas have no claim fields yet | — | WI-M2-06 / M2 / 10 / 12 (integration points) |
| `mark` is not wired into stream assembly | — | WI-M2-06 |
| The commit half of AC-M2-08 | — | WI-M2-08 |
| Under Q12 = yes, a target outside the capture's 10-title shortlist cannot be caught (56 / 816 exact plants in the property) | — | Open question 1 |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Duplicates are found without asking the user anything. A marked draft is simply not created (Q7). |
| UX-2 Rule of Three | pass | The shortlist goes to the model or the payload, never to a "what to do now" surface. It is capped at 10 for the model, and committed tasks reach Now only through `NowSelector`. |
| UX-3 Zero-Guilt | pass | No state, count or copy about repeats. A completed task said again is needed again, not a duplicate. All case names pass the AC-M2-12 vocabulary scan (0 violations). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The lookup reads only the local household and is meant for the on-device `Tool`. It is never given to a cloud model (AC-M2-24). |
| P-2 No data leaves device | pass | Pure functions, no networking, logging or I/O (AC-M2-09: 0 violations). Task IDs never leave `ShortlistEntry`; the Tool entry has no ID. |
| P-3 Cloud AI opt-in, minimised | pass | Under Q12 = yes only the ≤ 10 trimmed titles are meant for the payload (WI-M2-10). Under Q12 = no nothing about tasks is sent, and the word-match runs on the phone. |
| P-4 Media not persisted | pass | Nothing is stored. The household is never changed (Q7 test). |

### Open questions
1. ~~**PO (AC-M2-26 risk, not blocking):**~~ **Closed: PO WI-M2-07 ruling 1.** The query and the cap of 10 stay. A
   word-match floor on every path catches exact and near-exact repeats outside the 10 on the phone. It is built in
   round 2, and the brief is amended in this PR. Original question: under Q12 = yes the shortlist query is the **whole capture** (brief
   Definitions), capped at 10. In a long brain-dump in a big household, a repeated task can fall outside the 10 and be
   created again (56 of 816 exact-title plants and 381 of 753 synonym plants in the property). Built literally. Should
   the cap or the query change (for example, one shortlist per item) before the AC-M2-14 freeze? That would change
   AC-M2-20's golden bytes.
2. **Planner / WI-M2-M2 (technical, not blocking; PO ruling 3: technical):** on device the model names an existing task by the title the Tool
   returned (D1). If the on-device adapter prefers an index into the last lookup, `DuplicateLookupLog` can add that
   without changing the rules.
3. ~~**WI-M2-08 (product meaning, small):**~~ **Closed: PO WI-M2-07 ruling 2.** A confirmed `ofDraft(k)` is never
   created, whatever happened to draft k (brief AC-M2-06 sentence added in this PR; WI-M2-08 tests it). Original
   question: when a confirmed draft is `ofDraft(k)` and draft k was dismissed or left
   unconfirmed, should the repeat be created? This item leaves the marker as `ofDraft` (D8). The literal reading of
   AC-M2-06 ("exactly the confirmed drafts that are not duplicates") says no; commit decides.

### Round 2 (review round 1: CHANGES REQUIRED; PO rulings `po-m2-wi07.md`)
| Finding | Change |
|---|---|
| **R21-F1 Major** (PO ruling 1, items 1–4) | **The word-match floor on every path.** `DuplicateMarker` now runs, per draft: in-input claim → the model's existing-task claim → `LocalWordMatch.target` over the whole household → `none`. `ExistingTaskCheck.sentShortlist` now carries the household (`.sentShortlist(entries, household)`), and the on-device case uses `log.household`. A new `ExistingTaskCheck.household` property feeds the floor. Under Q12 = no nothing changes. The oracle (`DupOracle.marks`) has the same precedence. The AC-M2-08 property now **asserts** that every planted exact-title duplicate whose room is compatible (word-match rule) is marked on every path, and it counts floor-only marks. New hand-written tests: "an exact repeat ranked 11th (outside the 10 titles sent) is marked by the floor" (the oracle confirms rank 11); "the model's claim wins over the floor when they disagree" (device title and cloud index); "on device, with no claim at all, the floor marks an exact repeat". "A title the Tool never returned" now expects the floor's answer. The Q12 = yes title-claim test now checks that the floor still runs. D3, D4, the marking-table note and open questions 1 and 3 are updated. |
| Brief amendment (PO ruling 1 "Brief text changes", ruling 2) | `brief.md`: the new Definitions bullet "Word-match floor"; the AC-M2-07 sentence; the AC-M2-08 sentence; the Q12 answer sentence; the AC-M2-06 sentence on `ofDraft(k)`. The text is exactly the PO's. No protected path is touched; the DECISIONS.md entries wait for the human-merged governance PR. |
| R21-F2 Minor | New test "the entry title is trimmed of spaces, tabs and newlines at both ends; inner text is kept" (`"\n\tBuy  dish pods \n"` → `"Buy  dish pods"`, shortlist and lookup). The generator now wraps 20 % of the repeated titles in `\n\t … \n`. The reviewer's mutant G (`.whitespaces` only) is killed. |
| R21-F3 Minor | Both options are done. The oracle now splits at characters that are not "a Unicode letter or decimal digit" by the first scalar's general category (L* or Nd), which is the brief's words. New hand-written test: `½cup` and `cup²` give the keyword `cup`, `3` is a keyword, and `½ ² Ⅷ` gives none. The production mutant "digits = `Character.isNumber`" is killed. |
| R21-F4 Nit | A draft `existing(id)` whose room is not in the household now counts as no room in the word-match, as on the task side (D5). The oracle does the same. New word-match case; its mutant is killed. |
| R21-F5 Nit | `for _ in 1...rnd.int(4...14)`. The `_ = position` line is gone. |

**Round 2 test runs** (`swift:6.2-noble`, Swift 6.2.4, `-warnings-as-errors`, `swift build` first, 0 warnings):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 155 tests in 18 suites passed after 13.650 seconds.` (150 + 5 new: floor on device, claim beats floor, 11th caught by floor, newline trim, decimal digits; plus one new word-match case). AC-M2-09 `17 files in total, 0 violations`; AC-M2-12 vocabulary `17 files, 9 exempted (the list), 0 violations` |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 1.177 seconds.` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 84.418 seconds.` |

**Round 2 AC-M2-07 property** (same seeds; the generator now adds tab and newline titles, so the counts moved): 8,400
queries (24,249 entries), **0 shortlist mismatches**; 8,400 word-match drafts, **0 mismatches**. Neighbours are
decided at K 2,362, R 619, title 14,645 and `uuidString` 2,326. More than 10 eligible: 755. Room-only entries: 6,026.
Completed tasks left out: 6,797. Stop-word-only queries: 1,426. All eight word-match classes occur on every seed.

**Round 2 AC-M2-08 marking property** (same seeds, 600 households × 3 paths): **0 oracle mismatches**. Sum of the
three seeds:

| Plant | On device: planted / visible / marked (by the floor alone) | Cloud Q12 = yes | Cloud Q12 = no |
|---|---|---|---|
| exact title (all 798 in a compatible room; **asserted marked on every path**) | 798 / 795 / **798** (3) | 798 / 732 / **798** (66) | 798 / 798 / **798** (the floor is the only check) |
| synonym (scripted) | 802 / 800 / 800 | 802 / 396 / 396 | 802 / — / 0 (by design: the word-match misses synonyms) |
| in-input repeat | 637 / 637 / 637 | 637 / 637 / 637 | 637 / 637 / 637 |
| completed repeat | 715 / — / 239 (80 by the floor) | 715 / — / 239 (239) | 715 / — / 239 (239) |
| bogus claim / fresh | 780 / 3 · 912 / 14 (all by the floor) | same | same |

Every mark on a completed-repeat plant names a **live** task with matching words, never the completed one (asserted).
The 3 + 66 exact plants are the repeats the model could not see: the gap PO ruling 1 closes. Synonym repeats outside
the 10 stay a model and eval risk, as the PO ruling says.

**Round 2 mutation check: 39 mutants, 38 killed, 1 equivalent (M2, unchanged).** Every round 1 mutant was re-run on the
new code. M6 ("on device falls back to the word-match") is now the built behaviour, so it was replaced by its reverses.
W7 and M7 were rewritten so that they compile against the new shapes, and both are killed by failing tests. New
mutants:

| Mutant | Killed by |
|---|---|
| F1a no floor on device | unseen Tool title, on-device floor, AC-M2-08 property (3) |
| F1b no floor under Q12 = yes | Q12 = yes title claim, 11th caught by floor, AC-M2-08 property (3) |
| F1c floor before the model claim | invalid in-input claim falls back, claim beats floor, AC-M2-08 property (3) |
| F1d floor only under Q12 = no (the round 1 code) | 5 |
| G entry title trimmed with `.whitespaces` only (reviewer) | newline trim, AC-M2-07 property (2) |
| F3 production digits = `Character.isNumber` (`TextFolding.isDecimalDigit`) | decimal digits (1) |
| F4 dangling draft room counted as a room | word-match cases (1) |

All the other round 1 mutants (S1–S12, L1–L4, W1–W7, M1, M3–M5, M7, M8, R1, R2) are still killed. Several now also
fail the new floor tests.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Orchestrator | Developer | accepted (H2) | WI-M2-07 Ready: WI-M2-01 and 05 merged (`2f9f86f`). Binding: PO WI-M2-05 ruling 1; confirmed drafts in ascending `draftID`; independent oracle with seeds printed. Q12 open, so both paths are built. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 150, TendSourceScan 63, TendCore 141 green, 0 warnings, Linux. AC-M2-07 property: 8,400 queries and 8,400 word-match drafts, 0 mismatches. AC-M2-08 marking: 0 mismatches. 32 of 33 mutants killed, 1 equivalent. Three open questions. Pushed; no PR opened. |
| 2026-11-21 | Reviewer (via Orchestrator) | Developer | returned (round 1) | CHANGES REQUIRED: R21-F1 Major (PO WI-M2-07 ruling 1, word-match floor on every path); R21-F2, F3 Minor; F4, F5 Nit. PO rulings `po-m2-wi07.md`: 1 floor plus brief text; 2 `ofDraft(k)` never created (WI-M2-08); 3 D1–D8 accepted except D4. |
| 2026-11-21 | Developer | Reviewer (via Orchestrator) | sent (round 2) | R21-F1 fixed (floor, oracle, asserted property, three hand cases, reverse mutants killed); brief amended with the PO's exact text (rulings 1 and 2); F2–F5 fixed. TendIngestion 155, TendSourceScan 63, TendCore 141 green, 0 warnings. 38 of 39 mutants killed, 1 equivalent. Review file committed with the fix. |

## WI-M2-06/07 integration

- **Owner:** Developer  ·  **Branch:** `m2/stream-duplicates`, from `origin/main` at `00928fc` (WI-M2-06 PR #22 and
  WI-M2-07 PR #21 merged)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): no new file under `Sources`, Foundation and TendCore
  only, no I/O, no logging.
- **Requirements:** FR-A1. AC-M2-05 (the `updated` bullet: "After `finished`, each draft's duplicate marker equals what
  the duplicate rules give for the final drafts in `draftID` order"), AC-M2-07 (word-match floor on every path),
  AC-M2-08 (marking half: "every planted exact-title duplicate whose room is compatible is marked on every path").
- **Binding inputs:** PO WI-M2-06 ruling 5 (re-mark after updates), PO WI-M2-07 rulings 1 and 2, the integration
  ticket and "From PR #21" in `po-q21-q22.md`, review tickets R22-R2-F1, R22-R2-F2 and R21-F6. **Must merge before
  WI-M2-08 starts.**
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work.
- **Parallel work:** WI-M2-09 (routing and consent) is built elsewhere. This item does not touch `ModelRoute.swift` or
  any routing code. `DraftPipeline.swift` changes only in one doc comment (the `duplicateCheck` parameter).

### What changed
- `Model/IngestionModel.swift`:
  - `ItemSnapshot.sameAsItem: Int?` (the in-input claim) and `ItemSnapshot.sameAsExisting: ExistingTaskClaim?` (the
    existing-task claim: `.lookupTitle(String)` on device, `.shortlistIndex(Int)` for cloud with Q12 = yes). Both are
    neutral values. The schemas map into them (WI-M2-M2 `@Generable`, WI-M2-10 cloud schema, WI-M2-12 reader).
    `ItemSnapshot.duplicateClaim` turns them into the WI-M2-07 `DuplicateClaim`.
  - **The claims are not completion fields.** Rule (a) is still the nine fields (PO WI-M2-06 ruling 2). A claim that
    arrives after emission re-marks the draft (below), so it is never lost.
  - `IngestionSnapshot.lookupQueries: [String]`: on device, every query the duplicate `Tool` received so far in this
    parse, in call order. Empty for cloud models.
  - The `IngestionModel` adapter contract gains item 4: carry the Tool queries in every snapshot, yield one more
    snapshot after a Tool call that no snapshot has carried yet, and have the Tool read the same `Household` value the
    rules were given.
- `Stream/DraftStreamEvent.swift`: `DraftDuplicateCheck.duplicate(of:earlier:lookupQueries:)` now takes
  `DuplicateCheckEntry` values (draft, 1-based item position with skipped items counted, and the claim from the latest
  item). Earlier entries carry their latest markers. The doc states the calling rule, and it now states the
  **purity requirement** (R22-R2-F2).
- `Stream/DraftStreamAssembler.swift`: the re-mark starts at the lowest draft whose **content or claim** changed. When
  the snapshot's lookup queries differ from the last ones, it starts at draft 1. Everything else is as built in
  WI-M2-06: updates come before new emissions, there is one `updated` per draft whose content or marker changed, and
  there is no call when nothing the check reads changed.
- `Duplicates/DuplicateMarker.swift`:
  - The rules are one static function, `DuplicateMarker.duplicate(for:position:claim:check:earlierAt:)`. The stateful
    `mark` (WI-M2-07's API, unchanged) and the new conformance both use it.
  - New `DraftDuplicateRules: DraftDuplicateCheck` with `.onDevice(household:)` and
    `.cloud(_ sharing:capture:household:)`. On device, title claims resolve through the replayed queries. On a cloud
    path the check is fixed for the capture (Q12 = yes: the shortlist sent; Q12 = no: the word-match only), and lookup
    queries are ignored.
  - New `ExistingTaskCheck.toolQueries([String], Household)` and `ExistingTaskClaim`.
  - The "once per draft" comments are replaced (R21-F6 (c)). The `mark` doc says that a re-mark must run in ascending
    position over the lowest changed position and every later one.
- `Duplicates/DuplicateLookup.swift`: `DuplicateLookupLog.taskID(forTitle:replaying:in:)` gives the same resolution
  as the log (first match in call order, then rank order), over replayed queries. Each shortlist is computed only
  until the title is found.
- Tests (written first; the first build failed with "cannot find type 'ExistingTaskClaim' in scope"):
  - new `DraftStreamDuplicateTests.swift` (11 hand-written tests and the end-to-end property, 3 seeds);
  - `DraftStreamTests.swift`: R22-R2-F1, and the test doubles moved to the new signature;
  - `DuplicateRulesTests.swift`: R21-F6 (1) and (2);
  - `DraftStreamPropertyTests.swift`: the oracle passes item positions (signature only).
- Not changed: `TendCore`, `TendSourceScan`, `ModelRoute.swift`, `IngestionDraft`, every protected path, every
  dependency.

### Decisions the Reviewer should know
- **I1, the growing Tool log (R22-R2-F2): option (b), re-mark every draft when the log changes.**
  - The log is carried as **queries**, not results. The household is fixed for the parse (Q7; the household value is
    captured when the rules are made), so the results are a pure function of the queries. The check is then pure in
    (entry, earlier entries, lookup queries) plus fixed context. The stream re-marks from draft 1 whenever the
    queries differ from the ones used for the last marking.
  - **Why not (a), freeze the log?** Frozen at the start, it is empty, so no title claim would ever count on device.
    Frozen at each draft's emission, a claim the model wrote before the Tool call reached a snapshot stays
    unresolved. That draft then falls to the floor, which can give `none`, and a repeat would be created. Option (b)
    never does that.
  - **Why not (c), prove it cannot matter?** It can matter. A model may name a title before the call shows in a
    snapshot (for example, the user said the exact title). The e2e property plants this case
    (`onDevice.claimBeforeQuery`, 683 drafts).
  - **(b) only ever adds marks.** The household is fixed and the first match in call order wins, so a resolved title
    keeps its task as the log grows. Through Tool-log growth alone, a marker only goes from `none` to `ofExisting`, or
    from the floor's target to the model's resolved target (the model's claim outranks the floor, PO WI-M2-07 ruling 1
    precedence). Marks can still be removed or changed by content or claim updates; that is ruling 5 and is intended
    (PO precision, `po-m2-wi0607.md`; review R23-N2). So it can never let a repeat be created that (a) would have
    caught.
  - **This is what the brief says.** "On device: a title the `Tool` returned in this parse" (Definitions, word-match
    floor) means the whole parse.
  - It changes what the user may see: a marker can change after emission, through `updated`. The brief already allows
    that (`updated` includes the marker). I built the option that never lets a repeat be created. **Open PO question
    1** asks the PO to confirm.
- **I2, the evidence rule for the ruling 5 invariant.**
  - **Linux:** after `finished`, each draft's marker equals one pass of the rules in ascending `draftID` over the final
    drafts. Each draft is read with its item position, the claim from **the last version of its item that mapped to a
    draft** (a later version that Q5 skips, or a snapshot without the item, keeps the last claim; review R23-F1) and
    the **final snapshot's** `lookupQueries`. The household and path are the ones the rules were made with. The
    invariant tests and the e2e property check exactly this, and the oracle (`DupOracle.marks` with
    `queriesSoFar = final queries`) is built the same way.
  - **On device (WI-M2-M2 and the eval, owner-run Mac):** the same rule. The adapter test records, per draft, the last
    version of its item that mapped to a draft (usually the final snapshot's), the final `lookupQueries` and the final
    `DraftStreamSummary`. It runs `DraftDuplicateRules.onDevice(household:)`
    once over them and compares. It must also check that the Tool's own log equals `lookupQueries` of the final
    snapshot (adapter contract item 4). A difference is a defect in the adapter, not in the rules.
- **I3, a claim change is a re-mark trigger.** Ruling 5 says to re-mark "on a snapshot that produces updates". A claim
  that arrives after rule (a) fired changes no draft field, but it changes what the rules read. So the stream re-marks
  from that draft. It sends an `updated` only if the marker changes (test "a claim that arrives after emission …").
  Without this, a late `sameAsItem` would be ignored and a repeat created.
- **I4, the claim fields stay out of rule (a).** Adding them would hold back emission for every item whose model says
  nothing, which would cost TTFI (AC-M2-16). Suggestion for WI-M2-M2 (technical): declare the claim properties
  **before** the nine fields in the `@Generable` type, so that they are usually present at emission. Correctness does
  not depend on this (I3).
- **I5, positions.** The entry position is the item's 1-based position in the output, skipped items included (WI-M2-07
  D2). The stateful `mark` and the pure rules resolve `sameAsItem` the same way. In the pure rules the
  `k < position` guard is redundant, because `earlier` holds only lower positions. In `mark` it is load-bearing for
  repeat calls, and it is now pinned (R21-F6 test, mutant M1).
- **I6, commit order.** Unchanged: confirmed drafts go to commit in ascending `draftID`. `DraftStreamSummary.drafts` is
  in that order after re-marks (test "D6: confirmed drafts stay in ascending draftID after re-marks").
- **I7, cost.** A re-mark costs one floor scan of the household per draft. A title claim on device adds at most one
  shortlist per replayed query, and only until the title is found. A Tool-log change re-marks all drafts, but it
  happens a handful of times per parse. Measure on device (AC-M2-16) in WI-M2-M2.

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-05 re-mark rule (ruling 5) with the real rules | `DraftStreamDuplicateTests`, each through the assembler **and** `DraftPipeline`: "on device, a title claim the Tool had not returned yet is resolved when the lookup queries grow; every draft is re-marked"; "a claim that arrives after emission re-marks the draft"; "cascade through the stream: draft 2 drops its claim, so draft 3 (content unchanged) collapses into draft 2"; "positions count skipped items; a claim pointing at a skipped item is ignored"; "cloud Q12 = yes: an index claim marks the shortlist entry; Tool queries and title claims do not apply on this path"; "the word-match floor marks an exact repeat on every path, with no claim" | PASS (Linux) |
| AC-M2-05 hook contract (R22-R2-F1, R22-R2-F2) | "only the highest draft retitled gives exactly one re-mark call, (3, [1, 2])"; "the hook gets the item position, the latest claim and the latest queries; grown queries re-mark every draft, equal queries none" (positions [2, 3, 2, 3, 3], queries [[], [], [bread], [bread], [bread]], latest claim, and earlier entries with latest markers) | PASS (Linux) |
| AC-M2-05 invariant (ruling 5, I2) | "invariant with the real rules: after finished, the markers equal one pass over the final drafts, claims and queries" (3 scripts); the e2e property (below); the WI-M2-06 invariant test and property (unchanged meaning, new signature) | PASS (Linux) |
| AC-M2-07 marker re-calls (R21-F6) | "a repeat call for a position that claims itself never makes the draft a repeat of itself"; "re-marking in ascending position from the lowest changed one recomputes the cascade from the latest entries" (3 → `ofDraft(2)`); "DraftDuplicateRules gives the same markers as DuplicateMarker.mark called once per position with the same evidence" (3 paths, with a skipped position) | PASS (Linux) |
| Snapshot claim fields | "ItemSnapshot carries the model's two claims as neutral values; they map to DuplicateClaim and are not completion fields" | PASS (Linux) |
| **AC-M2-05 + AC-M2-08 e2e property** | "AC-M2-05 + AC-M2-08: 600 seeded households × 3 paths through DraftPipeline …". Seeds `0x0D0B1E5EED060701…0703`, 200 households each, generated by the WI-M2-07 `DupHouseholdGenerator`. There are 3–12 items per script, planted as fresh, exact title, synonym, in-input, completed repeat, bogus claim or skipped. They run on device (the mock calls the Tool and carries its queries), cloud Q12 = yes (openAI route) and cloud Q12 = no (gemini route), each through the real `DraftPipeline` and `DraftDuplicateRules`. The snapshots are progressive: titles grow by prefixes, fields arrive at random steps, claims arrive at random steps (often after emission), and Tool calls are made at random steps (often after the claim). Reads are capped at 5,000 events. **Asserted per parse:** (1) the final `DraftStreamSummary.drafts` equal the oracle exactly: content from the shared `DraftMapper` (AC-M2-01/02) and markers from `DupOracle.marks` (independent of production) over the final claims and final queries; (2) the ruling 5 invariant as stated (one pass of the production rules); (3) every planted exact-title duplicate whose final room is compatible is marked; (4) a visible exact, synonym or in-input plant is never `none`; (5) the outcome, `draftID`s 1, 2, 3 …, `updated` only after `emitted`, and ascending `draftID` order. Coverage is required per seed and path | PASS (Linux): **0 oracle mismatches, 0 invariant misses** on every seed |

**E2E property counts** (sum of the three seeds):

| Count | On device | Cloud Q12 = yes | Cloud Q12 = no |
|---|---|---|---|
| exact-title plants / in a compatible room / marked | 641 / 601 / **641** | 641 / 601 / **641** | 641 / 601 / **609** (every compatible one; the rest are rooms the floor does not match) |
| synonym plants / marked | 665 / 665 | 665 / 272 (the rest are outside the 10 titles sent) | 665 / 0 (by design) |
| in-input plants / marked | 570 / 570 | 570 / 570 | 570 / 570 |
| completed repeats / marked (a live task with the same words, never the completed one) | 607 / 230 | 607 / 230 | 607 / 230 |
| drafts whose final marker differs from their emitted marker | 1,200 | 886 | 759 |
| `updated` events | 9,009 | 9,049 | 8,744 |
| claim written before its Tool call reached a snapshot (I1) | 683 | — | — |

### Test runs
| Command (`swift:6.2-noble`, Swift 6.2.x, `-Xswiftc -warnings-as-errors`, 0 warnings) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 210 tests in 27 suites passed after 41.686 seconds.` (195 on `main` + 15 new; final run after the M16 test addition). AC-M2-09 `22 files in total, 0 violations`; AC-M2-12 vocabulary `22 files, 9 exempted (the list), 0 violations` |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 5.421 seconds.` (unchanged) |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 121.517 seconds.` (unchanged) |

### Mutation check
Each mutant was applied alone to a scratch copy of the sources (never the worktree), run with
`--filter "DraftStream|Duplicate|PlainNote|NoModel|CloudOutcome"` and `-warnings-as-errors` under a 900 s timeout,
and then restored from the worktree. The copy was compared with the worktree afterwards (identical). Every async read
in the new tests is capped (`collectCapped`, 5,000 events), and no mutant hung. **17 of 17 killed.** M5 first failed
to compile (a redeclared name). It was rewritten so that it compiles, and it is killed by failing tests. M16
**survived the first run**: the hook-input test had no snapshot after the claim change. That snapshot was added
("… equal queries and a kept claim none"), and M16 is now killed.

| # | Mutant | Failing tests |
|---|---|---|
| M1 | `k <= position` in the rules (R21-F6 (a); the reviewer's P6, WI-M2-07 M2) | 1: R21-F6 repeat-call self-claim |
| M2 | no re-mark when the lookup queries change (option (a), frozen per draft) | 4, incl. the e2e property, Tool-log growth, real-rules invariant |
| M3 | a claim change does not trigger a re-mark | 4, incl. the e2e property, late claim, cascade |
| M4 | claim read from the emitted item, not the latest | 6, incl. the e2e property |
| M5 | **R3b**: re-mark from draft 1 whenever anything changed (R22-R2-F1) | 2: "(3, [1, 2])", hook inputs |
| M6 | earlier entries' positions = `draftID` | 3, incl. the e2e property, skipped positions |
| M7 | emission position = `draftID` | 3, incl. the e2e property, skipped positions |
| M8 | emission ignores the lookup queries | 1: the e2e property |
| M9 | on-device rules ignore the lookup queries | 4, incl. the e2e property, rules = marker |
| M10 | cloud rules use the lookup queries | 2: cloud Q12 = yes, rules = marker |
| M11 | a re-mark sees stale lower markers | 3, incl. the e2e property, cascade |
| M12 | replayed lookups: last match in call order | 1: the e2e property |
| M13 | no floor on the replayed on-device path | 3, incl. the e2e property, floor on every path |
| M14 | `duplicateClaim` drops `sameAsItem` when there is a title claim | 1: snapshot claims |
| M15 | `updated` for every re-marked draft, changed or not | 2, incl. the WI-M2-06 property |
| M16 | claims not stored after a re-mark (calls on every later snapshot) | 1: hook inputs (after the fix above) |
| M17 | lookup queries not stored | 4, incl. the e2e property |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 210 tests: the stream with the real rules, R22-R2-F1/F2, R21-F6, the e2e property, AC-M2-09 and AC-M2-12 scans | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| The on-device adapter fills `sameAsItem`, `sameAsExisting` and `lookupQueries` (contract item 4) and the I2 device evidence rule | — | — | — | — | WI-M2-M2 on the owner-run Mac |
| Cloud schemas fill the claims (index under Q12 = yes) | — | — | — | — | WI-M2-10, WI-M2-12 |
| Re-mark cost on device (I7) | — | — | — | — | AC-M2-16 latency runs |

Device ACs: none in this item.

### Things the reviewer should look at closely
- I1, the choice of option (b), and its argument that re-marks only add marks. I2, the evidence rule.
- `refreshEmitted`: the trigger (content, claim or queries), and the `earlier` list built incrementally with the newly
  computed markers.
- The protocol change: every conformance must be pure (stated in the doc). `RecordingCheck` is impure on purpose
  (it logs), but its result depends only on its inputs.
- The e2e oracle's independence. It shares only `DraftMapper.map` (for content) and the WI-M2-07 household
  generator. Markers come from `DupOracle`, which calls no production code. The mock's claims, visibility and Tool
  queries come from the oracle's shortlist.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The adapters must fill the claim fields and `lookupQueries` (contract item 4), and the Tool must read the rules' household value | — | WI-M2-M2 (on device), WI-M2-10/12 (cloud) |
| Device evidence for the ruling 5 invariant per I2 | — | WI-M2-M2, eval harness |
| `@Generable` property order: claims first (I4, technical suggestion) | — | WI-M2-M2 |
| Commit: `DuplicateRecheck.atCommit`, ascending `draftID`, a confirmed `ofDraft(k)` never created (PO WI-M2-07 ruling 2) | — | WI-M2-08 (now unblocked once this merges) |
| PO watch item (unchanged): the floor does not catch a missed in-input repeat | watch | dev-set eval before the AC-M2-14 freeze |

### Open questions
1. ~~**PO (confirm, not blocking; built to the option that never lets a repeat be created):**~~ **Closed: PO ruling
   `po-m2-wi0607.md` (2026-11-22): option (b) CONFIRMED, no code change** (closed in WI-M2-08, review R23-N2). I1 now
   carries the PO's precision. Original question: on device, when the Tool's
   log grows during a parse, the stream re-marks every draft (I1, option (b)). A draft first shown as "not a
   repeat" (the floor found nothing, and the model's title claim was not yet backed by a Tool result) can then change
   to "repeat of an existing task" through `updated`. A mark never goes away this way. Is that the intended meaning
   of "a title the `Tool` returned in this parse"? If the PO prefers option (a) (each draft is judged against the log
   at its last re-mark), the change is one line in `refreshEmitted`, but repeats could then be created.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Markers are inferred and kept current. The user is asked nothing, and the review shows what commit will do (PO WI-M2-05 ruling 1). |
| UX-2 Rule of Three | n.a. | No selection surface. Drafts reach Now only via commit and `NowSelector`. |
| UX-3 Zero-Guilt | pass | No repeat state or copy. New names (`sameAsItem`, `sameAsExisting`, `lookupTitle`, `shortlistIndex`, `lookupQueries`, `DraftDuplicateRules`) pass the AC-M2-12 scan (0 violations). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The rules are local and deterministic. Lookup queries are replayed on the phone's own household. |
| P-2 No data leaves device | pass | Nothing new is sent. No networking, I/O or logging (AC-M2-09: 0 violations). |
| P-3 Cloud AI opt-in, minimised | pass | Cloud paths read only the shortlist that ADR-0005 allows (Q12 = yes) or nothing (Q12 = no). No request field is added. Lookup queries are never used on a cloud path. |
| P-4 Media not persisted | pass | Nothing is stored. The household is never changed (Q7). |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Developer | accepted (H2) | WI-M2-06/07 integration ticket. Binding: PO WI-M2-06 ruling 5; R22-R2-F1, R22-R2-F2, R21-F6; ascending `draftID` commit order; e2e property on three paths. Must merge before WI-M2-08. |
| 2026-11-22 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 210, TendSourceScan 63, TendCore 141 green, 0 warnings, Linux. E2E property: 600 households × 3 paths through `DraftPipeline`, 0 oracle mismatches, 0 invariant misses, every compatible exact plant marked. 17 of 17 mutants killed, no hang. R22-R2-F1, R22-R2-F2 (option (b)), R21-F6 done. One PO question (confirm option (b)). Pushed; no PR opened. |

## WI-M2-08 — `commit(confirmed:)`: injected IDs with collision skip, proposed rooms, the `ofExisting` re-check, contract over both M1 repositories, the AC-M2-08 property

- **Owner:** Developer  ·  **Branch:** `m2/commit`, from `origin/main` at `9e640b6` (WI-M2-05, 06, 07 and the
  WI-M2-06/07 integration merged)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none new. Follows
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): one new file under `TendIngestion/Sources`
  (`Commit/DraftCommit.swift`), Foundation and TendCore only, no I/O except the `HouseholdRepository` protocol, no
  network, no logging.
- **Requirements:** FR-A1, Q7, Q10 (W3-F6), UX-1, P-4. **Owns AC-M2-06 and AC-M2-08** ([plan.md](plan.md) WI-M2-08);
  also the commit clauses of AC-M2-04 ("a proposed room is created only on commit … one room") and AC-M2-07 ("commit
  creates nothing for it").
- **Binding inputs:** PO WI-M2-04 ruling 2 (rooms at commit), PO WI-M2-07 ruling 2 (a confirmed `ofDraft(k)` is never
  created), PO `po-m2-wi0607.md` (brief wording, closing integration question 1), the D6 commit order, and the tickets
  R19-F1, R19-F2, R23-F1, R23-N2 and R23-F2 (`po-q21-q22.md`, "From PR #24").
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. This is M2 work.
- **Parallel work:** WI-M2-09 (routing, PR #24) is in review. This item does not touch `Routing/` or
  `DraftPipeline.swift`.

### What changed
- `Sources/TendIngestion/Commit/DraftCommit.swift` (new):
  - `protocol CommitIDGenerator { mutating func next() -> UUID }`: the injected ID source (Q10, T-29). The app passes
    one that returns `UUID()`; tests and the eval harness pass seeded ones.
  - `DraftCommit.commit(confirmed:parsedWith:to:ids:) async throws(CommitError) -> CommitPlan`: the only write path. It
    loads the household once, plans every decision, and then writes the new rooms (`updateRoom`), then the new tasks
    (`upsertTask`) in ascending `draftID`. If nothing is confirmed, the repository is not called.
  - `DraftCommit.plan(confirmed:parsedWith:household:ids:) throws(CommitError) -> CommitPlan`: the pure decision step
    (rules C1–C5 below).
  - `CommitPlan` (`drafts: [CommittedDraft]`, `newRooms`, `newTasks`), `CommitDecision` (`created(id)`,
    `alreadyOnList(id)`, `sameChoreAsDraft(k)`), and `CommitError`. `householdUnreadable`, `draftIDRepeated`,
    `taskRejected` and `idGeneratorExhausted` mean nothing was written. `writeStopped(error, planned:, roomsWritten:,
    tasksWritten:)` says exactly what was stored.
  - `CommitIDAllocator`: every ID skips the household's task **and** room IDs and every ID already issued in this
    commit (W3-F6, R19-F2). It is bounded: after (number in use + 1,024) draws for one ID it throws
    `idGeneratorExhausted`, so it never hangs.
- `Rooms/RoomLinker.swift`: `commitPlan` now runs on a shared `CommitRoomResolver` (`peek` and `resolve`, one draft at a
  time), so `commitPlan` and `DraftCommit` apply the same AC-M2-04 rules. `commitPlan` is generic over a typed-throwing
  `makeID`, which is source-compatible with non-throwing callers. Its doc states the R19-F2 precondition: `makeID` must
  return unused IDs, and `DraftCommit` guarantees that.
- `Stream/DraftStreamAssembler.swift`, `Stream/DraftStreamEvent.swift`: doc wording only (R23-F1). The claim is the one
  from "the last version of its item that mapped to a draft".
- `Duplicates/DuplicateMarker.swift`: the `DuplicateRecheck` doc now points to `DraftCommit`.
- `docs/milestones/M2/brief.md`: the PO's Word-match floor clarification from `po-m2-wi0607.md`, inserted word for word
  after "a title the `Tool` returned in this parse" (the line was re-wrapped).
- This file: the WI-M2-06/07 integration section. Open question 1 is closed (citing `po-m2-wi0607.md`), I1 is
  reworded with the PO's precision (R23-N2), and I2 and the device evidence rule use the R23-F1 wording.
- Tests (written first; the first build failed with "cannot find 'DraftCommit' in scope"):
  - new `CommitTests.swift`: the contract suite over both M1 repositories, the rule suite and the test doubles
    (`ScriptedIDs`, `StuckIDs`, `SpyRepository`);
  - new `CommitPropertyTests.swift`: the AC-M2-08 property and its independent `CommitOracle`;
  - `DraftStreamDuplicateTests.swift`: the R23-F1 hand test.
- Not changed: `TendCore`, `TendSourceScan`, `Routing/`, `DraftPipeline.swift`, every protected path, every dependency.

### The commit rules as built (`DraftCommit.plan`; each is tested)
Confirmed drafts are taken in **ascending `draftID`**, whatever order they are passed in (D6, PO WI-M2-04 ruling 2a;
stated in the API docs). The same draft passed twice counts once. Two different drafts with one `draftID` are refused
before any write.

| Rule | Marker at commit | Result |
|---|---|---|
| C1 | `ofDraft(k)` | `sameChoreAsDraft(k)`, never created, whether k is confirmed, dismissed or unconfirmed (PO WI-M2-07 ruling 2) |
| C2 | `ofExisting(t)`, t not completed | `alreadyOnList(t)`. Nothing is created, and t is not changed (Q7) |
| C3 | `ofExisting(t)`, t completed or gone | Not a duplicate **of t** (brief re-check), but never a second copy of a chore. In order: (1) an earlier draft in this commit with the same gone t → follow its decision; (2) word-match floor, draft's title, over the household → `alreadyOnList`; (3) word-match on **t's title and room** (t as it was in `parsedWith`) over the household → a live task that repeats t → `alreadyOnList`; (4) floor over the tasks created so far in this commit → `sameChoreAsDraft`; (5) created |
| C4 | `none` | created. The parse already ran the floor on this household; there is no commit-time re-check |
| C5 | rooms and IDs | A created draft's room follows AC-M2-04 / PO WI-M2-04 ruling 2: a proposal that folds to an existing room's name uses it (lowest `id.uuidString`); proposals that fold equal make one room, named by the lowest `draftID`; a gone `existing` room gives no room. A not-created draft creates no room. The ID draw order is the new room (if any), then the task, draft by draft. |

### Decisions the Reviewer should know
- **C3, the re-check when the target is gone (product meaning; see open question 1).** The brief says: "If the target
  is missing or `completed`, the draft is treated as not a duplicate". Read literally, the draft is always created.
  The property found three ways that makes a repeat. I built the reading that never creates a repeat and never loses
  the person's item (the orchestrator's rule for unsettled meaning):
  - two drafts that marked the same gone t ("refill it", "dishwasher tablets") would both be created (C3.1);
  - another live task the floor finds would be repeated (C3.2);
  - a live task that repeats t itself (word-match on t's title and room) would be repeated by a synonym draft whose
    claim named t (C3.3).
  C3.4 catches two gone twins whose drafts repeat each other. If none of these apply, the draft is created, as the
  brief says. Mutant M7 (the literal reading) shows what the tests catch.
- **`parsedWith` (technical, needed by C3.3).** A target removed since the parse is no longer in the household, so
  commit cannot know its title. The caller passes the household value the parse's duplicate rules read (the one given
  to `DraftDuplicateRules`). Commit uses it only to look up a gone target.
- **C4, `none` drafts are not re-checked.** Two `none` drafts with the same words are both created ("bake bread",
  "bake bread"). That is the PO WI-M2-07 watch item: the floor does not cover a missed in-input repeat, and adding a
  local in-input floor is a later PO decision. The test "A none draft is not re-checked at commit" pins this so that a
  change is a visible decision. The property counts these pairs (`unflaggedInInputPairCreated`, below).
- **Twin in another room.** The Tool resolves a title claim by folded title only (D1), so on device a claim can name a
  same-titled task in another room. By the brief's Duplicate definition ("in the same room when a room is known") that
  is a different chore. So C3.3 uses the word-match room rule, and a twin in another room does not block creation.
  The property's ground truth checks the task the mock's claim actually names. It first checked the planted target
  and reported three false misses, all different-room twins.
- **Writes are per item, not one `save`.** A whole-household `save` would be all-or-nothing. But it would replace
  anything another writer stored between `load` and `save`, such as a completion from a widget in M4 ("completions must
  never be lost"). Per-item `updateRoom` and `upsertTask` keep the M1 per-call atomicity, with rooms written before
  tasks. A refused write stops the commit. `writeStopped` reports the counts and warns that committing the same drafts
  again would add their chores twice (test "Errors …"). M3 should retry only the unwritten drafts.
- **Concurrent writers.** A task another writer adds between this commit's `load()` and its writes is not seen by the
  re-check. The app runs one commit at a time per household, and M5 sync handles concurrent writers. This is stated in
  the API docs.
- **IDs are unique across tasks and rooms.** A task never takes a room's ID either. This is stricter than W3-F6 and
  costs nothing.
- **Why the bound on draws.** A generator that never repeats a value needs at most (number in use + 1) draws. The
  1,024 margin lets a generator repeat itself a little. Mutant M19 (no margin) shows that the test pins the margin.
- **R23-F2 (wiring the rules to the route) is not done here.** WI-M2-09 (PR #24) is not merged on `origin/main`
  (`9e640b6`), and this item must not touch `Routing/`. The ticket stays with the WI-M2-08/09 wiring, which comes
  after PR #24 merges. Options: build `DraftDuplicateRules` inside the pipeline from `(route, sharing, household)`, or
  add one wiring test per route that asserts the rule path. Commit does not depend on it. It reads only the markers
  and `parsedWith`, which must be the same household the rules were built with (stated in the API docs).

### AC coverage
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-06 "nothing is written" during a parse | "AC-M2-06: a parse writes nothing to the HouseholdRepository; only commit writes" (`SpyRepository`: the real `DraftPipeline` makes no repository call; the commit then makes exactly `load`, one `updateRoom`, two `upsertTask`) | PASS (Linux) |
| AC-M2-06 exactly the confirmed non-duplicates, with their proposed rooms | contract suite, **each test on `InMemoryHouseholdRepository` and `JSONFileHouseholdRepository`** (the file store is also reopened as a restart): "exactly the confirmed drafts that are not duplicates are upserted …"; "dismissed drafts and drafts left unconfirmed are not saved …"; "proposed rooms …"; "an ofExisting target that is still not completed creates nothing and is not changed, whatever its other state" (4 states, Q7) | PASS (Linux) |
| AC-M2-06 `ofExisting` re-checked at commit | "an ofExisting target completed or removed by commit time … is created" (both repositories); rule suite: "another live task the word-match floor finds"; "a live twin of the gone target …" (completed / removed); "a later draft with the same gone target …"; "… a task created in this commit …" | PASS (Linux) |
| AC-M2-06 / PO WI-M2-07 ruling 2: a confirmed `ofDraft(k)` | "a confirmed ofDraft(k) is never created …" × k **confirmed / dismissed / unconfirmed** × both repositories (6 cases): 1 bread task, 0, 0 | PASS (Linux) |
| AC-M2-06 IDs (W3-F6, R19-F2) | "R19-F2 (AC-M2-06, W3-F6): the generator's in-use task IDs, in-use room IDs and repeats are skipped …" (both repositories: a task ID in use, a room ID in use, an ID issued earlier in the commit, for a room and for tasks; every old task and room unchanged; IDs unique); "a generator that only returns IDs in use ends with idGeneratorExhausted before any write" (exactly 5 + 1,024 draws) | PASS (Linux) |
| AC-M2-04 commit clauses, R19-F1 | "R19-F1 (PO WI-M2-04 ruling 2b): a proposal that folds equal to two existing rooms uses the lowest id.uuidString, in any array order" (3 rooms, 3 orders, both repositories); "R19-F1: RoomLinker.commitPlan picks the lowest …" (3 orders); "proposed rooms …" (fold-equal names → one room named by draft 1 though passed last; a room added since the parse; a gone room → none); "… a not-created draft's proposed room is not created" | PASS (Linux) |
| Order, repeats, errors | "confirmed drafts are committed in ascending draftID …"; "writes: every new room first, then each new task in ascending draftID …"; "the same draft passed twice …"; "Errors: …" (unreadable household, rejected task, refused second write → `writeStopped(…, roomsWritten: 1, tasksWritten: 0)`) | PASS (Linux) |
| **AC-M2-08 + AC-M2-06 property** | "AC-M2-08 + AC-M2-06: 600 seeded households × 3 paths …". Seeds `0x0C0A11CEED080801`, `…0802`, `…0803`, 200 households each (the WI-M2-07 `DupHouseholdGenerator`), 3–12 items each, planted as fresh, **exact title**, **synonym (scripted claim)**, **in-input**, completed repeat or skipped. Each is parsed by the real `DraftPipeline` and `DraftDuplicateRules` on device, cloud **Q12 = yes** (openAI route) and cloud **Q12 = no** (gemini route). Then the household changes (targets completed or removed, rooms added), about 20 % of drafts are left unconfirmed, the rest are shuffled (sometimes with one passed twice), and the commit runs with a colliding ID generator (25 % in-use IDs, 12 % repeats). It goes to `InMemoryHouseholdRepository`, or `JSONFileHouseholdRepository` for every 10th household. **Asserted:** (1) the parse markers equal `DupOracle`; (2) the commit equals `CommitOracle` exactly (decisions, new rooms, new tasks with IDs); (3) ground truth: the store holds exactly the old household plus the new rooms and tasks; nothing old is overwritten; no ID repeats; no committed task word-matches a task live at commit; no in-input repeat is committed; no repeat the mock scripted against a live task is committed; no two committed tasks are the same chore unless the later one was unflagged; no confirmed `ofDraft` is created; no new room folds equal to another room. Coverage is required per seed. | PASS (Linux): **0 oracle mismatches, 0 ground-truth misses** on every seed |
| R23-F1 | "R23-F1: an emitted draft whose item is later skipped by Q5, or missing from a shorter snapshot, keeps its last content and its last claim (no updated)" (assembler and pipeline, plus the summary marker) | PASS (Linux) |
| AC-M2-09, AC-M2-12 (regression) | AC-M2-09 scan `23 files in total, 0 violations`; AC-M2-12 vocabulary `23 files, 9 exempted (the list), 0 violations` (the new names pass) | PASS (Linux) |

**Oracle independence.** `CommitOracle` (`CommitPropertyTests.swift`) calls no production rule code of
`TendIngestion`. It has its own markers (`DupOracle.marks`, WI-M2-07), its own name fold (the `DupOracle` fold,
whitespace collapse, article strip), word-matching by `DupOracle.wordMatch` (brute force), ordering by selection, and its
own ID skip, replayed from a copy of the generator. The only shared production code is `IngestionDraft.task(id:roomID:)`
(the M1 initialiser mapping, AC-M2-01/02) for the new tasks' field values, and `DraftMapper.map` for draft content. The
ground-truth checks use the plants and the stored household only.

**Property counts** (sum of the three seeds; per-seed lines are in the log; 600 households × 3 paths):

| Count | Value |
|---|---|
| Commits to `JSONFileHouseholdRepository` (the rest went to `InMemoryHouseholdRepository`) | 180 |
| ID skips: task ID in use / room ID in use / issued again, for **rooms** | 383 / 100 / 88 |
| ID skips: task ID in use / room ID in use / issued again, for **tasks** | 1,621 / 343 / 447 |
| New rooms / created drafts sharing a folded proposal / a room added since the parse used | 1,058 / 135 / 116 |
| Target gone, created: completed / removed | 231 / 203 |
| Target gone, not created: C3.1 follows the first / C3.2 floor / C3.3 live twin / C3.4 created in this commit | 88 / 154 / 38 / 2 |
| Confirmed `ofDraft(k)`: k confirmed / k not confirmed (all 0 created) | 1,189 / 327 |
| Created per path (on device / Q12 yes / Q12 no): fresh | 714 / 718 / 721 |
| Created: exact-title plants (target gone, or its room was not compatible) | 76 / 99 / 101 |
| Created: synonym plants, of which the mock scripted no claim (Q12 = no; outside the 10; the Tool did not return it) | 79 (1) / 344 (309) / 582 (582) |
| Created: completed repeats (a completed task is not a target) | 351 / 371 / 354 |
| Created on device although the claim named a twin in another room (a different chore by the room rule) | 5 |
| Pairs created together where the later draft was unflagged at parse (PO watch item: missed in-input repeat) | 29 / 45 / 34 |

A synonym that the mock scripted no claim for is created by design. That is the brief's accepted Q12 = no and
outside-the-10 limit, measured on device by AC-M2-17/26. It is not a repeat "under the deterministic rule the mock
scripts". Every **scripted** synonym that was created had its target completed or gone at commit.

### Test runs
| Command (`swift:6.2-noble`, Swift 6.2.x, `-Xswiftc -warnings-as-errors`, 0 warnings, `swift build` first) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 233 tests in 30 suites passed after 51.368 seconds.` (210 on `main` + 23 new). AC-M2-09 `23 files in total, 0 violations`; AC-M2-12 vocabulary `23 files, 9 exempted (the list), 0 violations`. Property lines: `seed 0xC0A11CEED080801/…0802/…0803, 200 households × 3 paths, 0 oracle mismatches, 0 ground-truth misses` (the print drops the leading 0 of `0x0C0A…`) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 2.827 seconds.` (unchanged) |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 110.440 seconds.` (unchanged) |

### Mutation check
Each mutant was applied alone by a script to a scratch copy of the packages (`/tmp/b08-mut/src`, never the
worktree). It was run with `--filter "Commit|DraftStream|RoomLinking"` and `-warnings-as-errors` under a 900 s
timeout, and the copy was then reset from the worktree. After the run the copy was compared with the worktree:
identical. Every async read is capped (`collectCapped`), and the ID allocator is bounded, so no mutant hung.
**22 of 22 killed.** M16 first failed to compile, because an unmutated `var` breaks `-warnings-as-errors`. It was
rewritten as `+= 0` and is killed. M22 **survived the first run**, because nothing checked that an empty commit
makes no call. The test "nothing confirmed means no repository call at all" was added, and M22 is killed.

| # | Mutant | Killed by |
|---|---|---|
| M1 | no collision skip | property, R19-F2 skip, stuck generator |
| M2 | room IDs not in the in-use set | property, R19-F2 skip, stuck generator |
| M3 | issued IDs not remembered | property, R19-F2 skip |
| M4 | no ascending `draftID` order | ascending draftID, property, proposed rooms |
| M5 | `ofDraft` created | exactly-confirmed, property, ruling 2 (6 cases) |
| M6 | no re-check (an `ofExisting` is never created) | 5 re-check tests |
| M7 | literal re-check only (a gone target is always created) | same gone target, property |
| M8 | no C3.1 (follow the first draft with the same gone target) | same gone target, property |
| M9 | no C3.3 (live twin) | live twin (2 cases), property |
| M10 | no C3.4 (created in this commit) | created-in-this-commit, property |
| M11 | a not-created draft still creates its room | live target unchanged, property |
| M12 | R19-F1: tie takes the last room (`rooms.last(where:)`, the reviewer's surviving mutant) | AC-M2-04 link tie, both R19-F1 tests |
| M13 | proposal not matched to existing rooms at commit | 5, incl. the property and R19-F1 |
| M14 | no fold de-dup of new rooms | 5, incl. the property |
| M15 | tasks written before rooms | write order, parse-writes-nothing, errors |
| M16 | `roomsWritten` not counted (compiling variant) | errors (`writeStopped` counts) |
| M17 | conflicting `draftID` silently dropped | repeated draftID |
| M18 | **R23-F1 / reviewer R2**: claim read from a skipped re-map | R23-F1 kept claim (assembler and pipeline) |
| M19 | no extra draws margin | stuck generator, property |
| M20 | a gone `existing` room kept | AC-M2-04 gone room, proposed rooms |
| M21 | twin check reads the target from the commit household, not `parsedWith` | live twin (removed case), property |
| M22 | an empty commit still loads | nothing confirmed, no call (after the fix above) |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 233 tests: AC-M2-06 contract on both M1 repositories, AC-M2-08 property, R19-F1, R19-F2, R23-F1, AC-M2-09 and AC-M2-12 scans | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| `JSONFileHouseholdRepository` commit on Darwin Foundation | — | — | — | — | Mac repeat in MS-2 (plan: AC-M2-06 "Mac repeat in MS-2") |
| Commit from the eval harness with its seeded generator (T-29) and the M3 review surface | — | — | — | — | WI-M2-M7 / M3 |

Device ACs: none in this item.

### Things the reviewer should look at closely
- C3 (gone targets): whether rules C3.1–C3.4 are the right "never a second copy" reading (open question 1).
- `parsedWith`: an extra required parameter. It must be the same household value the duplicate rules were built with.
- Per-item writes instead of one `save`, and the `writeStopped` retry guidance.
- The oracle's independence (above), and the ground-truth fix for different-room twins (Decisions).
- `RoomLinker.commitPlan` became generic over typed throws. Existing callers compile unchanged.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| R23-F2: build the duplicate rules from the route (or add a wiring test per route) | Minor (ticket) | WI-M2-08/09 wiring, after PR #24 merges |
| A missed in-input repeat (both drafts `none`) is committed twice | watch | PO WI-M2-07 watch item; dev-set eval before the AC-M2-14 freeze |
| Concurrent writers between `load()` and the writes are not re-checked | — | M5 sync |
| A partial commit (`writeStopped`) must be finished by committing only the unwritten drafts | — | M3 review surface |
| R23-N1 (shortlist cache per query) | watch | AC-M2-16 |
| Darwin rerun of the file-store commit | — | MS-2 |

### Open questions
1. ~~**PO (AC-M2-06 re-check, product meaning):**~~ **Closed: PO WI-M2-08 ruling 1 (`po-m2-wi08.md`): C3.1–C3.4
   accepted as built.** "Not a duplicate" means not a duplicate of that target; a completed or gone t never blocks
   creation on its own. The brief now has the **Commit re-check** bullet (inserted word for word in round 2).
   Mutants M7–M10 and M21 stay defects. Original question: when a draft's `ofExisting` target is completed or gone at commit, the brief
   says "the draft is treated as not a duplicate". I built that as "not a duplicate **of that target**". The draft is
   still not created when:
   - (C3.1) an earlier confirmed draft had the same gone target (the later one is the same chore as that draft);
   - (C3.2) the word-match floor finds another live task;
   - (C3.3) a live task repeats the target itself (word-match on t's title and room);
   - (C3.4) it repeats a task this commit just created.
   Otherwise it is created. Please confirm, or choose the literal reading (mutant M7; 154 + 38 + 88 + 2 drafts in the
   property would then be created as repeats).
2. ~~**PO (confirm, small):**~~ **Closed: PO WI-M2-08 ruling 2 (`po-m2-wi08.md`): confirmed as built.** The review
   showed each `none` row as new, so commit does what the screen showed. The watch item stays, and any fix would be
   parse-time. The pinning test stays. Original question: `none` drafts are not re-checked at commit (C4), so two unflagged same-words drafts are
   both created. That is the existing watch item. Built literally; a commit-time in-input floor would be a new rule.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Confirming is the one act: commit takes the confirmed drafts and infers every room and ID. It asks nothing. |
| UX-2 Rule of Three | n.a. | Commit only upserts into the repository that `NowSelector` reads. No M2 API returns "what to do now" items (T-21). |
| UX-3 Zero-Guilt | pass | New tasks are `active`, with no overdue or lateness state. Decision and error names (`alreadyOnList`, `sameChoreAsDraft`, `writeStopped`, `idGeneratorExhausted` …) pass the AC-M2-12 vocabulary scan (0 violations). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. The re-check is local and deterministic. |
| P-2 No data leaves device | pass | Only `HouseholdRepository` calls. No network, I/O or logging (AC-M2-09: 0 violations). |
| P-3 Cloud AI opt-in, minimised | n.a. | Nothing is sent. |
| P-4 Media not persisted | pass | Nothing is stored before commit, and a parse makes no repository call (spy test). Only confirmed drafts are written, and dismissed or unconfirmed ones never are. |

### Round 2 (review round 1: APPROVE with 3 Minors and 1 Nit, `review-WI-M2-08.md`; PO rulings `po-m2-wi08.md`)
| Finding | Change |
|---|---|
| **R25-F1 Minor** | `CommitIDAllocator` now treats as in use: every room ID that an existing task points to (a dangling `roomID` included), and every task and room ID of `parsedWith` (removed since the parse included), plus everything before. New test "R25-F1 (AC-M2-06): a room ID an existing task still points to … and IDs removed since the parse are in use …" (the reviewer's probe P1, "Dust the shelf" → `…DD`; both repositories). The property generator now also returns dangling room IDs and IDs from the parse household (skips over 3 seeds: dangling 84, removed since the parse 94). The property's ground truth asserts that no new room takes an ID a task points to, and that no new task reuses a removed task's ID. The oracle has its own skip rule for both. |
| **R25-F2 Minor** | New test "R25-F2: a refused later task write reports the tasks already written (tasksWritten), and they are stored": write 2 of 3 refused → `writeStopped(…, roomsWritten: 0, tasksWritten: 1)`, exact calls, and the stored household. It kills the reviewer's R1 (M25). |
| **R25-F3 Minor (docs)** | Open questions 1 and 2 are closed, citing `po-m2-wi08.md`. C3.3 is reworded to "word-match on t's title and room" here and in the `DraftCommit.plan` doc. `brief.md` gets the PO's text word for word: the two Q12 = yes commit sentences are deleted, the new **Commit re-check** Definitions bullet sits after the Word-match floor, AC-M2-06 now says "(**Commit re-check**, Definitions)", and there is a Handoff-log row for WI-M2-08 Q1/Q2 (DECISIONS.md entry in the governance PR). |
| **R25-N1 Nit** | The `commit` doc now says that cancellation does not interrupt a commit once it has started. |

**Round 2 test runs** (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 235 tests in 30 suites passed after 49.966 seconds.` (233 + 2). AC-M2-09 `23 files in total, 0 violations`; AC-M2-12 vocabulary `23 files, 9 exempted (the list), 0 violations`; property: 0 oracle mismatches, 0 ground-truth misses on all three seeds |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 3.520 seconds.` (unchanged) |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 115.617 seconds.` (unchanged) |

**Round 2 mutants** (same script and scratch copy as round 1; the worktree was never touched, and the copy was
identical afterwards). The three new mutants and the four existing allocator mutants were run on the new code.
**7 of 7 killed.** M2's anchor moved with the allocator change; it was re-anchored and rerun. The other 18 round 1
mutants touch code that round 2 did not change, and the round 2 change only adds tests, so they were not rerun.

| # | Mutant | Killed by |
|---|---|---|
| M23 | dangling room IDs not in use (R25-F1) | R25-F1 test (both repositories), property |
| M24 | IDs of the parse household not in use (R25-F1) | R25-F1 test (both repositories), property |
| M25 | `tasksWritten += 0` (the reviewer's R1, R25-F2) | R25-F2 test |
| M1, M2, M3, M19 | allocator mutants from round 1, on the new allocator | still killed (property, R19-F2, R25-F1, stuck generator) |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Developer | accepted (H2) | WI-M2-08 Ready: WI-M2-05, 06, 07 and the 06/07 integration merged (`9e640b6`). Tickets R19-F1, R19-F2, R23-F1, R23-N2, R23-F2 (note), the brief wording from `po-m2-wi0607.md`, and PO WI-M2-07 ruling 2. |
| 2026-11-22 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 233, TendSourceScan 63, TendCore 141 green, 0 warnings, Linux. Property: 600 households × 3 paths, 0 oracle mismatches, 0 ground-truth misses. 22 of 22 mutants killed (M22 after adding a test). R23-F2 left as a note (PR #24 not merged). Two PO questions. Pushed; no PR opened. |
| 2026-11-22 | Reviewer (via Orchestrator) | Developer | returned (round 1) | APPROVE with R25-F1, F2, F3 Minor and R25-N1 Nit. PO `po-m2-wi08.md`: both questions accepted as built. |
| 2026-11-22 | Developer | Reviewer (via Orchestrator) | sent (round 2) | R25-F1 to N1 fixed (see Round 2). TendIngestion 235, TendSourceScan 63, TendCore 141 green, 0 warnings. Brief text inserted word for word. Review file committed with the fix. |

---

## WI-M2-09 — routing and consent: `RouteRules`, `ModelRouter`, consent and key stores, orphan-key deletion, turn-off semantics, restored-state fixtures (i)–(iii)

- **Owner:** Developer  ·  **Branch:** `m2/routing-and-consent`, from `origin/main` at `00928fc` (WI-M2-06 and WI-M2-07
  merged)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none new. It follows
  [ADR-0005](../../architecture/adr/0005-cloud-ai-providers.md) Decisions 1, 2, 5 and 7 and
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): new files under `TendIngestion/Sources/TendIngestion/Routing/`,
  Foundation only.
- **Requirements:** FR-A1, P-1, P-2, P-3, P-4, UX-3. The item delivers ● **AC-M2-19** (full), and the Linux parts of
  ○ **AC-M2-18** (consent, route, cancel and the in-memory key store) and ○ **AC-M2-10** (route level)
  ([plan.md](plan.md) WI-M2-09; the plan's "Route matrix").
- **Not in this item:** the real Keychain delete for AC-M2-18 (a) and all of AC-M2-21 (WI-M2-M5, owner-run Mac), the
  neutral `CloudTransport` protocol, deadline and retry (WI-M2-14), the `URLSession` transport (WI-M2-M4), the
  provider adapters (WI-M2-M6), the `SystemLanguageModel.Availability` mapping (WI-M2-M2) and the durable consent
  store (M3, Q21).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. The DoR "deps merged" is met (WI-M2-06 is on
  `main`).
- **Parallel work:** the stream/duplicate integration is being built at the same time. This item changes **no**
  existing source file: nothing in `Stream/`, `Duplicates/` or the assembler. It uses `DraftPipeline.events(from:)`,
  `RoutedModel`, `Route`, `CloudProvider` and `OnDeviceUnavailableReason` as they are on `main`.

### What changed
All new files are in `Packages/TendIngestion`.
- `Sources/TendIngestion/Routing/RouteRules.swift`:
  - `OnDeviceAvailability` (`available`, `unavailable(OnDeviceUnavailableReason)`);
  - `RoutePreference` (`onDeviceFirst`, `alwaysCloud`);
  - `CloudStatus` (`off`, `on(CloudProvider)`);
  - `RouteRules.route(availability:preference:cloud:)`, ADR-0005 Decision 1 as one pure function.
- `Sources/TendIngestion/Routing/CloudStores.swift`:
  - `APIKey`. Its text is hidden from `description`, `debugDescription` and reflection, and is read only through
    `withSecret`.
  - `CloudStoreError` (`notAccessibleNow`, `storeUnavailable`).
  - The protocols `APIKeyStore` (`hasKey`, `key`, `save`, `deleteKey`) and `CloudConsentStore` (`selectedProvider`,
    `select`, `hasConsent`, `recordConsent`, `clearConsent`), all `async throws(CloudStoreError)`.
  - The in-memory actors `InMemoryAPIKeyStore` and `InMemoryCloudConsentStore`, which start empty (a fresh install).
- `Sources/TendIngestion/Routing/ModelRouter.swift`:
  - `OnDeviceModelSource` (availability and model) and `CloudModelSource` (`model(for:key:)`), for the `TendAI`
    adapters.
  - The `ModelRouter` actor: `cloudStatus()`, `route(preference:)`, `events(for:preference:)`, `turnCloudOn(_:key:)`,
    `turnCloudOff()`, `removeKey(for:)` and `select(_:)`.
  - The internal `ConsentCheckedCloudModel`, which asks the router at the moment its request would start, and
    `CloudAccessEnded`.
- `Sources/TendIngestion/Routing/RoutedDraftEvents.swift`: `RoutedDraftEvents`, an `AsyncSequence` with
  `Failure == Never`. It carries the chosen `route` and turns a turned-off cloud capture into
  `finished(.cancelled(route:))`.
- Tests (new, written first; the first build failed with "cannot find type 'CloudStoreError' in scope"):
  - `RoutingSupport.swift`: the neutral `RecordingTransport` mock, `MockCloudModel`, `RecordingCloudModels`,
    `FixedOnDevice`, the stored-state fixtures (`StoredState.planRows` = the plan's S0…S8; `StoredState.everyState` =
    all 256 states), and bounded helpers (`collectBounded`, `eventually`, `awaitConsumer`).
  - `RouteMatrixTests.swift`: AC-M2-19 and route-level AC-M2-10.
  - `CloudConsentTests.swift`: AC-M2-18, the stores, and `APIKey` formatting.

### The rules as built (each one is tested)
- **Cloud on** (brief Definitions "Cloud model"): `cloudStatus()` is `.on(X)` only when X is selected, X has a
  consent record, X has a stored key, and X was not blocked in this session. Everything else, including a store
  error, is `.off`.
- **Route** (ADR-0005 Decision 1): `RouteRules.route`.

  | availability | cloud off | cloud on (X), on device first | cloud on (X), always cloud |
  |---|---|---|---|
  | available | `onDevice` | `onDevice` | `cloud(X)` |
  | each unavailable reason | `none` | `cloud(X)` | `cloud(X)` |

  "Always cloud" with cloud off is ignored (T-12).
- **Orphan keys** (T-14): every `cloudStatus()`, and so every route choice, first deletes each stored key whose
  provider has no consent record. A key whose provider has consent is kept, even when that provider is not selected
  (plan S5, S7).
- **One model per capture.** `events(for:preference:)` chooses the route once and gives the pipeline one
  `RoutedModel`. An on-device stop ends `noModel` or `interrupted` on route `onDevice`, and the cloud is never asked
  (AC-M2-10, P-1).
- **Consent is checked again when the request starts.** The cloud capture's model calls `beginRequest`, which reads
  the stores again (`cloudStatus()`), reads the key only now, and builds the provider model with it. If cloud is no
  longer on for that provider, no model is built and the capture is ended.
- **Turn-off** (AC-M2-18 (a)–(d)): `turnCloudOff()` blocks every provider for the session, ends every in-flight cloud
  capture, clears every consent record and deletes every key. Every step is tried; the first store error is thrown at
  the end. `removeKey(for: X)` does the same for X only. Ending a capture finishes its snapshot stream, which cancels
  the forwarding task, which ends the provider model's stream (the `IngestionModel` adapter contract, part 3). Its
  `RoutedDraftEvents` then gives `finished(.cancelled(route: .cloud(X)))` next, and nothing after it. No event decided
  after the turn-off reaches the consumer, because the check runs after every event the pipeline gives.
- **Turn-on:** `turnCloudOn(X, key:)` records consent, stores the key (if that fails, it clears the consent again),
  selects X and lifts X's block. Lifting a block needs a new consent and a new key.

### Decisions the Reviewer should know
- **D1, where routing lives.** Routing is a new `Routing/` folder, not part of `Stream/`, so the parallel stream work
  is not touched. `RoutedModel` stays as WI-M2-06 built it: the router builds it, and the pipeline holds one model.
- **D2, fail closed.** Any store error while reading means cloud off. An orphan key that cannot be deleted never turns
  cloud on, because `cloudStatus` still needs a consent record. This is tested with a key store and with a consent
  store whose reads fail.
- **D3, the session block** (AC-M2-18 (c) when the Keychain cannot delete). If a store cannot clear the consent or
  delete the key, `turnCloudOff` and `removeKey` still cancel in-flight work, keep the provider off for the rest of
  the session, and throw the store error so M3 can tell the user calmly. After a relaunch, the restore rule applies
  again: a key with no consent is deleted, and a consent with no key is off. Only the case where **both** stores
  failed to change would turn cloud on again after a relaunch. M3 must show that error (follow-up).
- **D4, why `RoutedDraftEvents` wraps the pipeline.** The pipeline gives `cancelled` only when the consuming task is
  cancelled, and a turn-off cannot cancel the consumer's task. When the turn-off ends the request stream, the pipeline
  sees a throw and would give `noModel` or `interrupted`. The wrapper replaces that, and anything decided after the
  turn-off, with `cancelled`, as AC-M2-18 (d) requires. This needs no change to `DraftPipeline` or the assembler.
  - The cost is one actor hop per event on cloud captures. On-device and `none` captures have no watch, and their
    events pass straight through.
- **D5, `select(_:)` cancels the previous provider's in-flight captures.** This is a product-meaning reading (open
  question 1), and it is the most private one. Selecting the provider already in use cancels nothing. Switching
  clears no consent and deletes no key.
- **D6, the key is read only at request start,** and only for the routed provider. Route choice uses `hasKey`, which
  never reads the key's text.
- **D7, `APIKey` hides its text.** It conforms to `CustomStringConvertible`, `CustomDebugStringConvertible` and
  `CustomReflectable` (with no children). So `print`, interpolation, `dump`, `String(reflecting:)` and a containing
  value's description all show `APIKey(hidden)`. It is `Equatable` (so a test can check that a key reads back), but
  not `Hashable` or `Codable`. The masked display form (`••••` plus the last 4) is WI-M2-M5's (AC-M2-21), and is not
  built here.
- **D8, unstructured task.** `ConsentCheckedCloudModel` forwards through one `Task`, because `snapshots(for:)` is
  synchronous and the consent check is an actor call. The task is cancelled from the stream's `onTermination`, so the
  consumer cancelling, the pipeline dropping its iterator, and a turn-off all end it. There is no clock, timer,
  `DispatchQueue`, lock or `@unchecked Sendable`.
- **D9, the mock transport is neutral and test-only.** `RecordingTransport` records the neutral request values and
  how each request stream ended. It stands in for WI-M2-14's `CloudTransport`, which does not exist yet. When that
  protocol lands, the real adapters (WI-M2-M6) put it between `CloudModelSource` and the network. The routing tests do
  not depend on it.
- **D10, capture bookkeeping.** A cloud capture is forgotten when its `RoutedDraftEvents` returns `finished`. A
  sequence that is abandoned without being read to the end keeps one small entry (a provider, a flag, and a finished
  continuation) until the router is released. Unknown captures count as ended (fail closed).

### AC coverage
| AC (part) | Test(s) | Result |
|---|---|---|
| AC-M2-19, pure rule | "AC-M2-19: the pure route rule equals the plan matrix …" (5 availabilities × 2 preferences × 4 cloud statuses = 40 cells against `planRoute`, which is written from the plan table); "… the named rules …" (on device first never goes to the cloud; always cloud with cloud off is ignored) | PASS (Linux) |
| AC-M2-19, full matrix | "AC-M2-19: the full matrix through the router …": all **340 cells** (34 stored states S0…S8 over every provider and every X/Y pair × 5 × 2), checking the route, the orphan side effect, that consents are unchanged, and that `cloud(Y)` occurs only for the selected Y. The matrix is printed to the log, one line per cell | PASS (Linux) |
| AC-M2-19, through a capture | "… submitting a capture in every cell …": 340 cells. The outcome carries the route. Only `cloud(X)` cells send exactly one request, to X, with X's key and the capture text. `onDevice` cells ask only the on-device model. `none` cells give `noModel(.onDeviceUnavailable(reason))` with the input and a plain note, and 0 requests. "the route is part of the outcome and of the routed sequence" | PASS (Linux) |
| AC-M2-19 + AC-M2-18, exhaustive | "every stored state (256) × availability × preference": **2,560 cells** against an independent oracle written from the brief Definitions (48 cloud-on states × 9 cloud cells = 432 cloud cells). Orphan keys are deleted, consents and the selection are unchanged | PASS (Linux) |
| AC-M2-10, route level | "cloud off, each on-device reason unavailable" (4 reasons × every cloud-off plan row × 2 preferences): `noModel` on route `none`, the input and a plain note, 0 requests. "on-device generation stops before the first draft, cloud on or off" (16 `ModelStopReason`s × S0, S4, S7): `noModel(.stoppedBeforeFirstDraft)` on route `onDevice`, 0 cloud requests, the cloud source never asked. "a stop after the first draft is interrupted …, still zero cloud requests" | PASS (Linux). The adapter mapping of `Availability` and `GenerationError` is WI-M2-M2 (Mac) |
| AC-M2-18, fresh install | "a fresh install … never routes to the cloud and sends nothing" (the in-memory stores start empty; 10 cells) | PASS (Linux) |
| AC-M2-18, no consent | "every stored state with no consent record for the selected provider …": all 160 such states × 10 cells, never cloud, 0 requests | PASS (Linux) |
| AC-M2-18, restored (i) | "restored (i): a key for X with no consent record …" (per provider): never cloud, 0 requests, and the key is deleted at the first route choice | PASS (Linux) |
| AC-M2-18, restored (ii) | "restored (ii): a consent record for X and no key …" (per provider) | PASS (Linux) |
| AC-M2-18, restored (iii) | "restored (iii): a consent record and a key for Y while X is selected …" (every X/Y pair): never cloud, 0 requests, Y's key kept | PASS (Linux) |
| AC-M2-18, only `cloud(X)` | "given consent and a key for the selected X, the route is only ever cloud(X) …" (consent and keys for all three) | PASS (Linux) |
| AC-M2-18 (a)–(d), turn-off | "turning cloud off deletes every key, clears every consent, cancels the in-flight request with outcome cancelled, writes no task, and no request starts afterwards" (per provider). The request is held open with one draft emitted. After the turn-off: the events are `emitted(1)` then `finished(cancelled(cloud(X)))` then nil; the transport stream ended `cancelled`; the repository is unchanged; data sent after the turn-off reaches nobody; and a new capture under both preferences gives route `none` with the request count still 1 | PASS (Linux). (a) with the real Keychain is WI-M2-M5 (Mac) |
| AC-M2-18 (c) | "a capture routed to the cloud before turn-off but started after it sends no request and ends cancelled" | PASS (Linux) |
| AC-M2-18 (a)–(d), remove key | "removing the key of the provider in use …" (per provider; other providers' keys and consents kept); "removing the key of a provider that is not in use leaves the in-flight request … running" | PASS (Linux) |
| AC-M2-18 (c), behind the router | "consent cleared in the store after the route was chosen (not through the router) …" and "the selection changed in the store after the route was chosen …": the request is refused when it would start, 0 requests, the outcome is `cancelled`. "a capture the user cancels while its request is being prepared (key being read) sends nothing" | PASS (Linux) |
| AC-M2-18, restored (i), D2 | "a key with no consent record that cannot be deleted still never turns cloud on" (per provider) | PASS (Linux) |
| AC-M2-18, failing stores | "when the stores cannot delete or clear, turn-off still cancels …, reports the store error, and no request starts afterwards in this session" (and only turn-on lifts the block); "removing a key that cannot be deleted still blocks …"; "a key store / consent store that cannot be read keeps cloud off" | PASS (Linux) |
| AC-M2-18, other | "turning cloud on records consent, stores the key and selects …"; "selecting another provider cancels the in-flight request of the previous one" (D5); "selecting the provider already in use … does not cancel"; "the user cancelling a cloud capture …" (consent and keys untouched); "an on-device capture is not affected by turning cloud off"; "turning cloud off when nothing is stored is calm" | PASS (Linux) |
| Stores, `APIKey` | in-memory key store (save, read, replace, idempotent delete); in-memory consent store; "an APIKey never shows its text in description, debug description, reflection, dump or interpolation" (10 forms, including a containing struct and an array); calm names (UX-3) | PASS (Linux). Not evidence for AC-M2-21 (Mac) |
| AC-M2-09, AC-M2-12 (regression) | the AC-M2-09 scan: `26 files in total, 0 violations`; the AC-M2-12 vocabulary scan: `26 files, 9 exempted (the list), 0 violations` | PASS (Linux) |

### Test runs
| Command (in `swift:6.2-noble`, `--scratch-path /tmp/b09-<pkg>`, `-Xswiftc -warnings-as-errors`) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 232 tests in 30 suites passed after 22.130 seconds.` (195 on `main` + 37 new), 0 warnings |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 93.464 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 2.877 seconds.` (unchanged package) |

The first full run found one error in my own test: the expected count of cloud cells in the exhaustive test was 48 × 6,
and the right number is 48 × 9 (each cloud-on state has 1 available/always-cloud cell plus 4 reasons × 2 preferences).
The constant and its comment were corrected. No assertion was relaxed.

### Mutation check
Each mutant was applied alone by a script to a **scratch copy** of the worktree (never the worktree), and run with
`--filter "Route|Consent|CloudTurnOff|CloudStore|RouterNoModel"` and `-warnings-as-errors` inside a 600 s timeout. The
held-request tests have a 1-minute time limit, and every wait is bounded (`eventually`, `awaitConsumer`,
`collectBounded`), so a broken rule fails and never hangs. The script's baseline run on the unmutated copy passed (39
tests). **28 mutants: 27 killed, 1 equivalent.**

| # | Mutant | Killed by (failing tests / issues) |
|---|---|---|
| M1 | on device first goes to the cloud when cloud is on | pure rule, named rules, matrix ×3, … (158 issues) |
| M2 | "always cloud" ignored when cloud is on | matrix, named rules, … (150 failing lines) |
| M3 | unavailable + cloud on gives `none` | matrix, restored, turn-off … (1,115 issues) |
| M4 | cloud on without the consent check | undeletable orphan key (D2), … (12 issues). **Survived the first pass** (orphan deletion hid it); killed after the D2 test was added |
| M5 | cloud on without the key check | 1,395 issues |
| M6 | the session block ignored | failing-store turn-off and remove key (4 issues; one at the time limit) |
| M7 | no orphan-key deletion | restored (i), matrix, exhaustive (1,576 issues) |
| M8 | the orphan rule deletes keys that have consent | restored (iii), matrix (1,681 issues) |
| M9 | nothing selected: a provider with consent and key is on | S6 cells (433 issues) |
| M10 | turn-off does not cancel in-flight captures | turn-off (a)–(d), failing stores (4 issues, by `awaitConsumer`) |
| M11 | turn-off keeps the keys | 3 issues |
| M12 | turn-off keeps the consent records | 3 issues |
| M13 | turn-off does not block | failing stores (4 issues) |
| M14 | remove key cancels every provider | remove another key (3 issues) |
| M15 | remove key does not cancel | remove key in flight (3 issues) |
| M16 | select does not cancel the previous provider | switch provider (1 issue) |
| M17 | request start does not re-check cloud status | selection changed behind the router (2 issues, one at the time limit). **Survived the first pass**; killed after that test was added |
| M18 | a refused start does not end the capture (outcome becomes `noModel`) | consent cleared behind the router (1 issue). **Survived the first pass**; killed after that test was added |
| M19 | `RoutedDraftEvents` ignores the turn-off | 10 issues |
| M20 | ending the stream does not cancel the forwarding task | the transport stream ends `cancelled` (7 issues) |
| M21 | turn-off does not finish the request stream | 8 issues |
| M22 | turn-on does not lift the block | 1 issue |
| M23 | turn-on records no consent | 4 issues |
| M24 | `APIKey.description` shows the key | formatting (6 issues) |
| M25 | the mirror shows the key | formatting, `dump` (5 issues) |
| M26 | the key is read for another provider | the request carries X's key (27 issues) |
| M27 | route `none` uses the on-device model | 1,520 issues |
| M28 | no `!Task.isCancelled` check after `beginRequest` | **equivalent in the tests.** When the user cancels, `RoutedDraftEvents` releases the capture before the suspended preparation resumes, so `beginRequest`'s own re-check refuses it first (test "… cancels while its request is being prepared …"). The check guards only a scheduling race between those two actor calls, which cannot be ordered from a test. It is kept as defence in depth |

Two mutants (M2, M17) first failed to compile under `-warnings-as-errors` (an unused binding). That was not counted as
a kill. They were respelled (`_ = provider`, `status == status`) and both were then run.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 232 tests: AC-M2-19, the Linux parts of AC-M2-18 and AC-M2-10, the stores, `APIKey` formatting, the AC-M2-09 and AC-M2-12 scans | ✔ container (`swift:6.2-noble`) | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| Actor reentrancy and `AsyncThrowingStream` termination on Darwin | — | — | — | — | Not verified (no Mac). Plan B2 (the `TendIngestion` suite on the owner-run Mac) covers it |
| AC-M2-18 (a) with the real Keychain; AC-M2-21 | — | — | — | — | WI-M2-M5, owner-run Mac (Simulator host). The in-memory store is not evidence |
| `Availability` / `supportsLocale` mapped to `OnDeviceAvailability` | — | — | — | — | WI-M2-M2, owner-run Mac |

Device ACs: none in this item.

### Things the reviewer should look at closely
- **The concurrency in `ModelRouter`.** Every check that matters is read again after its last `await` (actor
  reentrancy): in `cloudStatus` (the block) and in `beginRequest` (ended, and one request per capture).
  `endCaptures` finishes the request stream synchronously on the actor.
- **`ConsentCheckedCloudModel`'s forwarding `Task`** (D8), and how `onTermination` cancels it in all three end paths
  (the consumer cancels, the pipeline drops its iterator, a turn-off).
- **`RoutedDraftEvents`** (D4): one check after every inner event. When it replaces an inner `noModel` or
  `interrupted` with `cancelled`, is that the right reading of AC-M2-18 (d)?
- **The failing-store semantics** (D2, D3). Turn-off throws the first store error, after trying every step.
- **`APIKey`** (D7): `Equatable` compares the text, so a failing `#expect(a == b)` on two keys prints
  `APIKey(hidden)`, never the key.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The Keychain adapter conforms to `APIKeyStore` (`hasKey` must not read the key's data); AC-M2-18 (a) proven with the real Keychain; turn-off and remove key delete the item | — | WI-M2-M5 |
| The on-device adapter conforms to `OnDeviceModelSource` (exhaustive `Availability` switch, `supportsLocale` → `unsupportedLocale`) | — | WI-M2-M2 |
| The cloud adapters conform to `CloudModelSource` over WI-M2-14's `CloudTransport`; they read the key text only in `withSecret` for the auth header | — | WI-M2-14, WI-M2-M6 |
| A durable consent store that a restore cannot bring back (Q21). Settings screens call `turnCloudOn`, `turnCloudOff`, `removeKey` and `select`, not the stores directly. M3 shows a calm message when turn-off throws a `CloudStoreError` (D3: if **both** stores fail to change, a relaunch could turn cloud on again) | — | M3 brief (PO, Q21); Designer for copy |
| An abandoned `RoutedDraftEvents` (never read to `finished`) keeps one small entry in the router (D10) | Nit | Revisit if M3 keeps routers alive for long |
| M28 is an equivalent mutant (a race only) | Nit | — |
| Not verified on Darwin | — | Plan B2, MS-2 |

### Open questions (PO; built to the most literal and most private reading, work continues)
All three are closed by the PO rulings in `po-m2-wi09.md` (2026-11-22). Each is accepted as built, with no code change.
The brief amendments are applied word for word in round 2.
1. ~~**Selecting another provider while a capture is in flight.**~~ **Closed: ruling 1.** It ends the previous provider's
   in-flight captures as a turn-off does. Its consent and key are kept. Selecting the provider already in use
   cancels nothing.
2. ~~**Does turning cloud off clear the selection?**~~ **Closed: ruling 2.** The selection is kept. The ruling's
   conditions are binding: the selection alone never turns cloud on, it is never sent, and M3 never uses it to skip
   the consent screen or to nag.
3. ~~**Outcome when a turn-off meets a capture whose request had not started.**~~ **Closed: ruling 3.** It is
   `cancelled`, with 0 requests, for every cloud-access end the user caused in Settings. The binding M3 rule: when
   the user did not cancel the capture itself, M3 keeps the input and offers the plain note locally.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. Turning cloud on is a Settings step (M3), not capture. |
| UX-2 Rule of Three | n.a. | No selection surface. Drafts still reach Now only through commit and `NowSelector`. |
| UX-3 Zero-Guilt | pass | The new names (`notAccessibleNow`, `storeUnavailable`, `onDeviceFirst`, `alwaysCloud`, `off`, `on`) are calm and describe the store or the setting, never the person (test "store and route names are calm"; AC-M2-12 vocabulary scan, 0 violations). Turn-off ends with `cancelled`, not a failure. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | On device first is the rule (340 + 2,560 cells). An on-device stop never asks the cloud (16 reasons × 3 states, 0 requests). The pipeline holds one model. |
| P-2 No data leaves device (except user iCloud) | pass | There is no networking in `TendIngestion` (AC-M2-09, 0 violations). Requests exist only as a test recorder. The key is read only at request start, and only for the routed provider. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Off by default. Cloud is on only with consent **and** a key for the selected provider. Orphan keys are deleted. Restored fixtures (i)–(iii) never route to the cloud. A store error means off. Turn-off and remove key cancel in-flight work at once and block new requests, even when a store fails. Consent is checked again at request start. |
| P-4 Media not persisted without consent | pass | Nothing is written: no file, log or `UserDefaults` API (AC-M2-09). `APIKey` cannot reach a log through formatting. A cancelled capture writes no task (repository unchanged). |

### Round 2 (review round 1: CHANGES REQUIRED; PO rulings `po-m2-wi09.md`)
The review is committed with this fix: [review-WI-M2-09.md](review-WI-M2-09.md). `origin/main` at `3bac3ce` (PRs #23
and #25) is merged in, with no rebase and no force-push. The dev-notes conflict was resolved by keeping main's
sections first, then this section. In `IngestionModel.swift`, main's new adapter-contract item 4 and the R24-F7
sentence are both kept. The numbers in this section replace the round 1 test and mutant numbers above.

| Finding | Change |
|---|---|
| **R24-F1 Major** | New tests in `CloudConsentRaceTests.swift`:<br>- "R24-F1, R24-F2: a Settings action while the key is being read …" runs end to end for turn-off, remove-key and select-another-provider. `SuspendingKeyStore` holds the key read. Expected: only `finished(cancelled(cloud(openAI)))`, `afterFinished == nil`, 0 requests.<br>- "R24-F1: beginRequest reads the capture again after the key read …" calls `beginRequest` directly for the same three actions and expects nil.<br>- A control without an action expects one allowed start, and a second start is refused.<br>All waits are bounded (`eventually`, `awaitConsumer`, a 1-minute time limit). After `release()` the store stays open, so a mutant that reads again cannot hang.<br>The reviewer's **mutant A is killed in 0.3 s by 3 assertion failures**, one per action, with no hang. So is A with M28 also removed (both request-start guards gone). |
| **R24-F2 Minor (fixed)** | `ModelRouter.attach(_:continuation:)` stores the capture's stream as soon as the forwarding task starts, before `beginRequest` reads any store. `endCaptures` therefore finishes it at once, even during the key read, and the consumer ends with `cancelled` before the key read returns. That is asserted in the end-to-end F1 test ("the consumer did not end before the key read returned"). The `started` flag keeps one request per capture. Mutant F2m2 ("late attach", the round 1 behaviour) is killed by that assertion. |
| **R24-F3 Minor (fixed)** | Settings actions now carry numbers (`nextActionNumber`). Each turn-off or remove-key records its number per provider (`lastEnded`). When `turnCloudOn` finishes, it checks whether a turn-off or remove-key for its provider started after it did. If so, the later action wins: the turn-on clears the consent and deletes the key it wrote, leaves the block in place, and returns `.off`. `turnCloudOn` now returns the resulting `CloudStatus` (`@discardableResult`). Numbers are strictly increasing, so there are no ties. Tests: "a turn-off that overlaps a turn-on wins …"; "a remove-key for the same provider that overlaps a turn-on wins; for another provider it does not"; and the control "a turn-on that starts after a turn-off has returned turns cloud on". `SuspendingConsentStore` holds `recordConsent`. Mutants F3m, F3m2, F3m3 and F3m4 are killed. |
| **R24-F4 Minor (fixed)** | "a turn-off while cloudStatus is reading the stores gives off, even when the stores cannot clear or delete": the first `hasKey` is held, the consent store cannot clear, and the key store cannot delete. The reviewer's mutant D is killed. |
| **R24-F5 Minor (fixed)** | "when the key cannot be stored, turn-on throws the store error, clears the consent again, and cloud stays off". The reviewer's mutant K is killed. |
| **R24-F6 Nit (done)** | Internal `trackedCaptureCount`, and the test "the router tracks a cloud capture while it runs and forgets it once its events were read to the end" (on-device captures are never tracked). The reviewer's mutant I is killed. Mutant H (unknown counts as not ended) stays equivalent: it is reachable only after `isDone`. |
| **R24-F7 Nit (done)** | `IngestionModel` adapter contract, part 3: a stream created inside an already cancelled task cancels its transport at once and sends nothing (WI-M2-M6). |
| **R23-F2 (ticket from the WI-M2-06/07 integration review)** | The public capture API is now `ModelRouter.events(input:household:now:calendar:timeZone:titleSharing:preference:)`. It chooses the route first, then builds the `DraftPipeline` with that route's rules: `DraftDuplicateRules.onDevice(household:)` on device or for `none`, and `DraftDuplicateRules.cloud(titleSharing, capture: input, household:)` on the cloud. The rooms come from `household.rooms`. The pipeline-taking `events(for:preference:)` is now internal and used by tests only, so the public API cannot pair the rules of one route or capture with another. Tests in `RouteWiringTests.swift`:<br>- 680 cells (34 plan states × 5 availabilities × 2 preferences × 2 Q12 answers): the pipeline's rules path equals the route's, with this capture's text and rooms.<br>- Under Q12 = yes the rules hold this capture's shortlist; the fixture makes the shortlist depend on the capture. Under Q12 = no, only the word-match.<br>- On-device rules are used when cloud is on but the route is on device.<br>Mutants killed: W1 (cloud gets on-device rules), W2 (cloud rules for another capture; it survived until the fixture was made capture-sensitive) and W3 (the Q12 answer ignored). |
| PO rulings | Open questions 1–3 are closed above. The brief amendments from `po-m2-wi09.md` are applied word for word to `brief.md`: the Cloud model bullet, the `cancelled` bullet, and the AC-M2-18 lead-in and (d). Main's own brief amendments (PRs #23 and #25) are kept. No protected path is touched. |

**Round 2 test runs** (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings, merged tree):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 284 tests in 37 suites passed after 92.546 seconds.` That is 272 on the merge commit (main plus round 1), plus 12 new: 9 race tests and 3 wiring tests. AC-M2-09: `27 files in total, 0 violations`. AC-M2-12 vocabulary: `27 files, 9 exempted (the list), 0 violations` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 146.823 seconds.` (unchanged) |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 4.288 seconds.` (unchanged) |

**Round 2 mutation check: 43 mutants, 41 killed, 2 equivalent.**
- How they were run: each mutant was applied alone to a scratch copy (never the worktree), with `--filter
  "Route|Consent|CloudTurnOff|CloudStore|RouterNoModel|R24|Wiring"` and a 600 s timeout.
- What was run: M1–M28 were re-run on the round 2 code. The reviewer's A, D, K and I, the fix mutants (F2m, F2m2,
  F3m–F3m4, S1) and W1–W3 are new. A, A+M28, D, F2m2, F3m and W1–W3 were run again on the merged tree.
- Run interruption: Docker stopped once, during the run. The remaining mutants, the baseline and the three mutants
  that are killed at the time limit (M6, M13, M17) were run again after the restart.

| Mutant | Result |
|---|---|
| M1–M27 (round 1) | all killed again. M6, M13 and M17 fail partly at the 1-minute time limit (a held request that never ends); the rest fail on assertions |
| M28 no `!Task.isCancelled` check | **equivalent**, as in round 1: the capture's own re-check refuses first |
| A, A + M28 | killed (3 assertions each, 0.3 s) |
| D, K, I | killed (1 assertion each) |
| F2m (a turn-off skips streams whose request has not started) | **equivalent**: `started` is set before the key read, so the stream is always finished during preparation. F2m2 is the real "late attach" mutant |
| F2m2 late attach | killed ("the consumer did not end before the key read returned", 12 issues) |
| F3m, F3m2, F3m3, F3m4 | killed |
| S1 a second request per capture | killed (the control test) |
| W1, W2, W3 | killed (164, 82 and 82 issues) |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Developer | accepted (H2) | WI-M2-09 Ready: WI-M2-06 merged (`00928fc`). Binding: P-1 (one model), P-2/P-3 (own key and consent; turn-off cancels in flight, no new request), the `APIKeyStore` protocol with an in-memory implementation, a neutral mock transport only, and no edits to `Duplicates/` or the assembler's marking. |
| 2026-11-22 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 232, TendCore 141, TendSourceScan 63 green, 0 warnings, Linux. AC-M2-19: 340 plan cells + 2,560 exhaustive cells, 0 mismatches. 28 mutants: 27 killed, 1 equivalent (M28). 3 PO open questions. No existing source file changed. Pushed; no PR opened. |
| 2026-11-22 | Reviewer (via Orchestrator) | Developer | returned (round 1) | CHANGES REQUIRED: R24-F1 Major (test the `beginRequest` re-check after the key read; kill mutant A); R24-F2…F5 Minor; F6, F7 Nit. PO `po-m2-wi09.md`: Q1–Q3 accepted as built, brief amendments. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1 tests (mutant A killed by assertion, no hang). F2, F3, F4, F5 fixed with tests; F6 and F7 done. R23-F2 wired (rules built from the route). PO brief amendments applied; open questions closed. Merged `origin/main` `3bac3ce`. TendIngestion 284, TendCore 141, TendSourceScan 63 green, 0 warnings. 43 mutants: 41 killed, 2 equivalent. Review file committed with the fix. |
