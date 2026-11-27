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

## WI-M2-12 — server-sent-event framing and an incremental JSON reader that turns a growing JSON text into neutral item snapshots

- **Owner:** Developer  ·  **Branch:** `m2/stream-json-snapshots`, from `origin/main` at `3bac3ce` (WI-M2-06 and
  everything up to WI-M2-08 merged; `origin/main` merged again before the push, no change)  ·  **PR:** not opened (the
  Orchestrator opens it)  ·  **ADRs:** none new. Follows [ADR-0006](../../architecture/adr/0006-m2-module-layout.md):
  three new files under `TendIngestion/Sources/TendIngestion/CloudOutput/`, Foundation and TendCore only, no I/O, no
  network, no logging, no new dependency.
- **Requirements:** FR-A1, P-3. This item delivers the **first Linux part of AC-M2-24** ([plan.md](plan.md)
  WI-M2-12, ○): the framing and the reader the three provider parsers stand on. The provider dialects, their
  synthetic fixtures and the refusal case are WI-M2-13. The adapters end to end are WI-M2-M6 (Mac). It also feeds
  AC-M2-05 (the snapshots go into the same draft stream as on device) and the plan's "Numbers" rule
  ("How the hint meets Q5": the provider parsers turn any non-integer, non-finite or out-of-range JSON number into nil).
- **Binding inputs:** the brief's Definitions ("Item completion", "Draft stream events"), AC-M2-24, T-03, T-19, T-25;
  PO WI-M2-06 ruling 2 (rule (a) field set); the ticket in `po-q21-q22.md` "From PR #22": *WI-M2-12/13: test a title
  that arrives last (rule (a) can fire on a title prefix; `updated` fixes it)*; the WI-M2-06/07 integration fields
  (`ItemSnapshot.sameAsItem`, `sameAsExisting`, `IngestionSnapshot.lookupQueries`); `ModelNumber.wholeNumber`; the
  `.unrecognized` enum rule.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. This is M2 work. DoR "deps merged" is met
  (WI-M2-06 is on `main`).
- **Parallel work:** WI-M2-09 routing (`Routing/`, PR #24) and the eval scorer (`Tools/TendTools`, `Eval`) are built
  elsewhere. This item touches neither, nor any existing source file.

### What changed
All new files are in `Packages/TendIngestion`. No existing source or test file was changed.
- `Sources/TendIngestion/CloudOutput/ServerSentEventFramer.swift`: `ServerSentEvent` (`type`, `data`,
  `lastEventID`), `ServerSentEventEnd` (`complete`, `cutShort`) and `ServerSentEventFramer` (`append(_:)` gives the
  events each byte chunk completes; `finish()`). It follows the WHATWG HTML "Server-sent events" parsing rules (the
  file header lists them).
- `Sources/TendIngestion/CloudOutput/PartialJSONParser.swift`:
  - `PartialJSONValue` (`null`, `bool`, `number(text)`, `string(_, isComplete:)`, `array(_, isComplete:)`,
    `object(_, isComplete:)`), `PartialJSONMember`;
  - `JSONSyntaxIssue` (9 cases) and the typed `PartialJSONError` (`invalid(issue, byteOffset:)`, `cutShort`), with
    `stopReason` (invalid → `unreadableOutput`, cut short → `outputCutShort`);
  - `PartialJSONParser`: a byte-at-a-time push-down parser with a stack of open containers (each byte is read once).
    `value` is the JSON read so far; `finish()` gives the root value or `cutShort`;
  - `ModelNumber.wholeNumber(jsonText:)`: the exact whole-number reading of a JSON number's text.
- `Sources/TendIngestion/CloudOutput/StructuredOutputReader.swift`:
  - `StructuredOutputKey`: the cloud output schema's key names (`items`; the item's 11 keys; the hint's 8 keys);
  - `StructuredOutputReader`: `append(_ text:)` and `append(bytes:)` give the latest `IngestionSnapshot` after each
    chunk; `finish()`; `parse(_:)` (one shot); `snapshot(of:)` (the field-by-field mapping in the file header).
- Tests (new, written first; the first build failed with "cannot find 'PartialJSONError' in scope" and 150+ similar
  errors): `ServerSentEventFramerTests.swift`, `PartialJSONParserTests.swift`, `StructuredOutputReaderTests.swift`.

### The rules as built (each one is tested)
- **SSE framing.** CRLF, LF and CR line ends, also when a CR ends one chunk and its LF starts the next; `:` comments;
  the field name up to the first `:`, one leading space removed from the value, a line with no colon is a field with an
  empty value; `event`, `data` (lines joined with LF, one trailing LF removed), `id` (persists; ignored if it holds
  NUL); `retry` and unknown fields ignored; a blank line dispatches only when the data buffer is not empty, with type
  `message` by default, then clears the type and data; one BOM is dropped only at the very start; invalid UTF-8
  becomes U+FFFD (the event-stream decoding rule). Splitting is on bytes, so a cut inside a UTF-8 sequence changes
  nothing. `finish()` reports `cutShort` when a line or an undispatched event is left over (the event is dropped, as
  the rules say). After `finish()` the framer is closed.
- **Incremental JSON.** RFC 8259 over UTF-8 bytes, cut anywhere. After any chunk the value read so far is available:
  containers and strings may be open; an open string holds only whole characters (never half a UTF-8 sequence, half
  an escape, or half a surrogate pair); a number, `true`, `false` or `null` appears only once it is finished; an object
  member appears once its key is finished and its value has started. Invalid JSON is `invalid(issue, byteOffset:)`
  at the first byte that cannot be read (for a malformed number, the byte that ends it; R26-N1), and the same offset
  whatever the chunking; never a crash. A text that ends
  before its root value is finished is `cutShort`. The first error closes the parser.
- **Snapshots.** The reader maps the value read so far, after every chunk, to an `IngestionSnapshot`:
  - root object → `items` array → one `ItemSnapshot` per element, in output order;
  - `title`, `room` (→ `roomName`), `sourcePhrase`: strings; `kind`, `effort` and the hint's `anchor`, `daypart`,
    `weekday`, `season`, `repeatUnit`: `ModelChoice(raw:)`, so an unknown value is `.unrecognized` (exact match:
    `"High"` and `" day"` are unrecognized); the three flags: booleans; `time`: an object;
  - `month`, `count`, `repeatEvery`, `sameAsItem`: `ModelNumber.wholeNumber(jsonText:)`; `sameAsExisting`: the same
    reading, as `.shortlistIndex(n)` (the cloud claim with Q12 = yes; the WI-M2-07 local re-check decides validity);
  - `lookupQueries` is always empty (a cloud model has no `Tool`, AC-M2-24);
  - **only finished values are shown** (J2).

### Decisions the Reviewer should know
- **J1, the schema key names are fixed here (`StructuredOutputKey`).** WI-M2-10 (payload builder, not built yet)
  writes the schema it sends from these names, so the reader and the schema cannot drift. The names are the
  `ItemSnapshot` / `TimeHintSnapshot` field names, except `room` for `roomName` (the model is asked for a room, not a
  name field). A Mirror test checks that the key lists cover every snapshot field in order. The root is
  `{"items": [ … ]}`. This is a technical choice; WI-M2-10 may rename a key here in the same PR as the schema.
- **J2, only finished values are shown: no field is ever a prefix.** The PO ticket expected rule (a) to fire on a
  title prefix and `updated` to fix it. With WI-M2-06 D8 ("a skipped item stays skipped"), a prefix is not always
  fixable:
  - the snapshot right after `"title":"` has title `""`, so all nine fields have a value, rule (a) fires, Q5 skips
    the item (no title), and it stays skipped although the full title follows;
  - a prefix can also meet the calm-words guard wrongly: the prefix `"Late"` of `"Later: call the plumber"` is a
    banned token the user did not say (they said "later"), the guard removes it, the title is empty and the item is
    skipped for good.
  So the reader shows a string, a number or a literal only once it is finished. A field never changes once it is in a
  snapshot (the time hint gains sub-fields, each finished; R26-N2) (the property checks this on every step). Rule (a) fires when the last field closes, a few tokens later
  than on a prefix, and no draft is ever emitted with a part title. The ticket's test is built (`titleArrivesLast`:
  3-byte chunks, the title last; exactly one `emitted`, with the whole title, and no `updated`). This is the literal
  reading of "every field … has a value" (a half-written string is not yet the model's value). It touches TTFI
  (AC-M2-27 for the cloud) only by those few tokens. **Open question 1** (closed: PO WI-M2-12 ruling 1) asked the PO to confirm. The on-device `PartiallyGenerated`
  shows strings while they grow, so WI-M2-M2 meets the same blank-title case (note for WI-M2-M2 below).
- **J3, numbers are read exactly from their text, not through `Double`.** `wholeNumber(jsonText:)` splits the text by
  the JSON grammar and works in decimal digits: a whole number that fits `Int` (`2.0`, `0.3e1`, `100000e-5`, `1E+2`,
  `Int.max`, `Int.min`) is kept; a fraction, anything out of range (`9223372036854775808`, `1e19`, `1e400`, a
  24-digit exponent) and a malformed text are nil. It equals `wholeNumber(_: Double)` wherever a `Double` holds the
  value exactly (5,000 seeded cases), and is right where `Double` rounds: `9007199254740993` stays itself (the
  `Double` route gives `…992`) and `1.00000000000000001` is a fraction (the `Double` route gives 1). There is no
  floating point in the reader.
- **J4, strict where RFC 8259 leaves a choice, and the oracle's differences.** The parser rejects a duplicate object
  key (`duplicateKey`; which value would count is otherwise unclear) and a leading BOM (models do not send one). It
  caps nesting at 64 open containers (`nestingTooDeep`; the schema needs 4). Foundation's `JSONDecoder` (the test
  oracle) differs from RFC 8259 in two ways the tests found: it **accepts a trailing comma** (`[1,]`, `{"a":1,}`), and
  it **rejects a number beyond `Double`'s range** (`92233e72036854775808`), which RFC 8259 allows. This parser
  follows the RFC in both. The mutant property allows exactly these differences (plus duplicate names), checks each
  one, and counts them: 0, 0 and 1 over 1,200 mutants.
- **J5, schema-violating output is read calmly, never as an error.** `null`, a missing key and a wrong-typed value are
  all missing (nil), so Q5 repairs them. An `items` element that is not an object is an empty item (no title, so Q5
  skips it), so the positions that `sameAsItem` counts stay right (WI-M2-07 D2). A root that is not an object, or
  `items` that is not an array, gives no items (a normal finish is then `completed` with the plain-note offer, PO
  WI-M2-06 ruling 1). Unknown keys are ignored at every level, including an unknown key that holds `items` or `title`.
  Only invalid JSON and a cut-off text end the stream.
- **J6, `null` counts as missing for rule (a) (literal reading; TTFI watch).** OpenAI's strict structured output
  requires every key and uses `null` for "none". A `null` `room` or `sourcePhrase` is not a value, so such an item
  meets rule (a) only if every field is non-null; otherwise it completes by (b) or (c). That is the PO WI-M2-06
  ruling 2 watch item. If the dev-set eval shows TTFI misses from it, the schema shape (for example a required string
  with `""` for "no room") is a technical choice for WI-M2-10. **Open question 2.**
- **J7, the error mapping.** `PartialJSONError.stopReason`: invalid JSON → `unreadableOutput`, a cut-off text →
  `outputCutShort`. With WI-M2-06, after the first draft both give `interrupted`; before any draft, `noModel` (T-25).
  Both are tested through `DraftPipeline` with a cloud route. When a provider stream counts as cut off (its end
  event missing) is WI-M2-13's rule; `ServerSentEventEnd.cutShort` and the reader's `cutShort` are the inputs.
- **J8, the parser is public.** WI-M2-13 also has to read each event's own JSON payload (for example Anthropic's
  `{"type":"content_block_delta","delta":{"partial_json":…}}`). It can use `PartialJSONParser` one shot, so every JSON
  in the cloud path is read by one parser with the same rules on Linux and Darwin (R-10).
- **J9, cost.** Each byte is read once. Building the snapshot after a chunk walks the open containers and maps the
  items, so it costs the size of the output so far: fine for a few kilobytes of output, which is what one capture gives.
  The test file notes one test-side lesson: long synchronous property loops held all 4 cooperative-pool threads in the
  container and made the time-limited cancellation tests of WI-M2-06 run out of time. The property loops now
  `await Task.yield()` once per case; the WI-M2-06 tests are unchanged.

### AC coverage
| AC (Linux part) | Test(s) | Result |
|---|---|---|
| AC-M2-24 SSE framing | `ServerSentEventFramerTests` (15 tests): one event; event type and reset; data lines joined; CRLF/CR/LF mixed; CR at a chunk end with LF in the next (every CR position); comments, unknown fields, `retry`; no-colon fields and one-space removal; blank line without data; `id` persistence and NUL; BOM at the start only (every cut), BOM-only stream; every 1- and 2-cut split of a UTF-8-heavy event; invalid UTF-8 → U+FFFD; truncation (`cutShort`, 16 cases); closed after `finish`; events at the chunk that completes them | PASS (Linux) |
| AC-M2-24 SSE property | "3 seeds × 600 streams …": seeds `0x55E12001…03`; each random stream (random line ends, comments, ids, `retry`, BOM, spacing) framed one shot, byte by byte and at 3 random cut sets, against the events the generator meant | PASS (Linux): 0 mismatches; 1,804 / 1,850 / 1,838 events |
| AC-M2-24 JSON: split chunks, truncation, invalid JSON | `PartialJSONParserTests` (15 tests; the invalid-JSON table has 29 rows, the UTF-8 tables 11 + 9): every value kind; root scalars; open values while they grow; scalars only when finished; an open string never shows half a character (byte by byte through UTF-8, `\n`, `é` and a surrogate pair); every 1-cut and every 2-cut split (first cut every 3rd byte) give the one-shot value, and every byte-by-byte step is a prefix of it; each invalid text gives its issue at the same byte offset for every cut point, and the oracle rejects it too (J4 exceptions named); invalid UTF-8 (overlong, surrogate, above U+10FFFF, bad continuation) at the bad byte; every proper prefix gives `cutShort`; depth cap with 100,000 `[`; closed after an error; the stop-reason mapping | PASS (Linux) |
| AC-M2-24 non-integer numbers → nil | "whole numbers are read exactly …" (33 rows); "the exact rule agrees with `wholeNumber(Double)` …" (5,000 seeded); the reader's `numbers` test (12 rows × 5 number fields) | PASS (Linux) |
| AC-M2-24 field order, unknown enums, claims, schema-violating fields | `StructuredOutputReaderTests`: full item; key list ↔ snapshot fields (Mirror); 200 seeded member orders (item and hint, also wrapped with extra root keys); unknown enum values → `.unrecognized`; claims → `sameAsItem` and `sameAsExisting(.shortlistIndex)`, and `duplicateClaim`; null and wrong types → missing, unknown keys ignored; non-object items keep positions; wrong root → no items; only finished values appear (13 steps) | PASS (Linux) |
| AC-M2-24 + AC-M2-05, title arrives last (PO ticket) | "a title that arrives last (3-byte chunks) …": no step shows a part title; rule (a) is first met exactly when the title closes, before the end; through `DraftPipeline` (route `cloud(.anthropic)`): exactly one `emitted` with the whole title, no `updated`, `completed`; the events equal the one-shot script's | PASS (Linux) |
| AC-M2-24 truncation / invalid JSON outcomes | "a text cut off after the first draft ends interrupted (outputCutShort); the draft stays" (`cloud(.openAI)`, 7-byte chunks; the open item is discarded `stoppedBeforeComplete`); "invalid JSON before any draft ends noModel (unreadableOutput) with the plain-note offer" (`cloud(.gemini)`, offset 37) | PASS (Linux) |
| AC-M2-24 property (incremental = one-shot = independent oracle) | "3 seeds × 500 outputs …": seeds `0x0A11C0DE1211…13`. A seeded writer makes valid outputs with random fields, nulls, wrong types, unknown enums, unknown nested keys, non-object items, number spellings, escapes (`\uXXXX` upper and lower case, surrogate pairs, `\/`), raw Unicode and combining marks, whitespace and member order. Each is read one shot, at 3 random cut sets (1–12 cuts) and, every 25th, byte by byte. The final snapshot equals the one-shot parse and the **oracle** (`JSONDecoder` into `OracleJSON`, numbers through `Decimal`, mapped again by `ReaderOracle` from the schema table). Every step only grows (items never fewer; each field, once there, equals its final value). For the first cut set, the draft stream over the incremental snapshots ends with the same drafts as over the one-shot snapshot | PASS (Linux): 0 mismatches. Per seed (1211 / 1212 / 1213): items 1,269 / 1,182 / 1,210; with a title 935 / 862 / 921; unrecognized kind or anchor 415 / 404 / 416; with a claim 979 / 928 / 939; cut sets 1,550 each |
| AC-M2-24 invalid JSON never crashes (fuzz) | "3 seeds × 400 mutated outputs …": seeds `0x0A11C0DE1221…23`, 1–3 byte deletions, insertions or replacements from a JSON-ish alphabet (incl. NUL, LF, `C3 A9`, `FF`, `ED A0`). Chunked equals one shot; the reader accepts exactly when the oracle does (J4 differences checked and counted) and then agrees with it | PASS (Linux): accepted 97 / 109 / 114, rejected 303 / 291 / 285, oracle differences 0 / 0 / 1 |
| AC-M2-09 (regression) | "AC-M2-09: Rules 1–6 hold …": TendIngestion 26 files scanned, 0 violations | PASS (Linux) |
| AC-M2-12 vocabulary (regression) | the AC-M1-02 vocabulary scan over the module roots: 0 violations | PASS (Linux) |

### Test runs
| Command (in `swift:6.2-noble`, Swift 6.2.x, `-Xswiftc -warnings-as-errors`; the scratch path on a mounted cache volume) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 283 tests in 35 suites passed after 68.430 seconds.` (235 before this item + 48 new) |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 104.249 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 6.109 seconds.` (unchanged package) |

### Mutation check
Each mutant was applied alone by a script to a scratch copy of the worktree (never to this branch), built with
`-warnings-as-errors`, run with `--filter "ServerSentEvent|PartialJSON|StructuredOutput"` inside a 600 s timeout, and
then restored. **25 of 25 killed.** One script lesson: three mutants first "died" because they did not compile under
`-warnings-as-errors` (an unused or never-mutated variable). They were rewritten so that they compile cleanly, and the
table shows the second run. M10 traps on its own arithmetic (a UInt32 underflow in the surrogate formula), so M10b
was added as a non-trapping variant, together with the test row `"\ud83e\ue000"`.

| # | Mutant | Killed by |
|---|---|---|
| M1 | framer keeps the leading space after the colon | CRLF/CR/LF test, CR-split test, SSE property |
| M2 | framer counts a CR then an LF as two line ends | CR-split test, SSE property |
| M3 | framer keeps the leading BOM | BOM test, SSE property |
| M4 | framer keeps the trailing LF of the data | line-ends test, CR-split test, SSE property |
| M5 | `finish()` always says `complete` | truncation test, closed-after-finish test |
| M6 | an `id` holding NUL is accepted | `id` test |
| M7 | a UTF-8 lead byte is committed before its continuation bytes | "never shows half a UTF-8 sequence", every-cut test |
| M8 | no duplicate-key check | invalid-JSON table |
| M9 | no number-grammar check | invalid-JSON table, mutant property |
| M10 | no low-surrogate range check | trap (the mutant's own underflow) |
| M10b | the low-surrogate upper bound dropped | invalid-JSON table (new row) |
| M11 | nesting cap off by one | nesting test |
| M12 | no data-after-value check | invalid-JSON table, sticky test, mutant property |
| M13 | `ED` lead byte allows surrogate code points | invalid-UTF-8 table |
| M14 | no trailing-zero strip in the exact number rule | number tables, reader property, mutant property |
| M15 | 18-digit limit instead of 19 | number tables (`Int.max`, `Int.min`) |
| M16 | no control-character check in strings | invalid-JSON table, mutant property |
| M17 | the in-progress child is never shown | partial-string test, only-finished test, truncation outcome |
| M18 | the reader shows open strings | title-last test, only-finished test, reader property |
| M19 | `sameAsExisting` read from the `sameAsItem` key | claims, non-object items, both properties |
| M20 | non-object items are dropped (positions shift) | non-object-items test, both properties |
| M21 | enum values case-folded | field order, unknown enums, both properties |
| M22 | room read from a `roomName` key | title-last test, both properties |
| M23 | a wrong-typed `time` read as an empty hint | wrong-types test, both properties |
| M24 | the two stop reasons swapped | stop-reason test, truncation and invalid outcome tests |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 283 tests (SSE framing, JSON parser, reader, the two properties, the draft-stream end-to-end tests, AC-M2-09 and AC-M2-12 scans) | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| The same reader on Darwin Foundation (`String(decoding:)`, `JSONDecoder` oracle) | — | — | — | — | Mac repeat in MS-2 (B2/B4) |
| Real provider streams (OpenAI, Anthropic, Gemini) | — | — | — | — | WI-M2-13 (synthetic dialect fixtures) and WI-M2-M6 (owner recordings) |

Device ACs: none in this item.

### Things the reviewer should look at closely
- J2 (only finished values) against the PO ticket's wording, and whether a part title could still reach a draft.
- The parser's state machine in `structure(_:)` and `valueFinished(_:)`: each byte is read exactly once, and the
  number case reads its delimiter as structure after the number is finished.
- The oracle's independence: `JSONDecoder` is a different parser; `ReaderOracle` maps from the schema table again and
  reads numbers through `Decimal`; the corpus writer builds texts without the parser under test.
- The J4 allowances in the mutant property: each is checked (trailing comma at the failing byte, a number beyond
  `Double` present, a duplicate key), and counted.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The provider dialects (event types, the text pieces, end events, refusal) on top of this | — | WI-M2-13 |
| WI-M2-10 writes the schema from `StructuredOutputKey` (J1) | — | WI-M2-10 |
| On device, `PartiallyGenerated` shows strings while they grow: a `""` title at rule (a) is skipped for good (J2) | watch | WI-M2-M2: map an open string to nil, or require a non-blank title for rule (a) on device; Mac test |
| A `null` `room` or `sourcePhrase` delays completion to (b) or (c) (J6) | watch | WI-M2-10 schema shape without `null` for rule-(a) fields (PO WI-M2-12 ruling 2); AC-M2-27 cloud TTFI watch in the DS-2 dev-set run |
| R26-F2: no response-size cap. A stream with no line end grows the framer's `line` without limit (also `dataBuffer` and the string scanner's bytes); the 10.0 s deadline bounds time, not bytes | Minor (ticket) | WI-M2-13 or WI-M2-14: end with `unreadableOutput` once the body passes a fixed byte limit, with a test |
| Finished-values rule on device (`PartiallyGenerated` shows growing strings) | ticket | WI-M2-M2 (PO WI-M2-12 ruling 1): Mac evidence with a late title and a "Late" prefix, plus the mutant "open string counted as a value" |
| Per-provider fixtures: a no-room item completes by (a) before the next item; title arrives last | ticket | WI-M2-13 (PO WI-M2-12 tickets) |
| The Darwin rerun of these tests | — | MS-2 |

### Open questions
1. ~~**PO (confirm, J2):**~~ **Closed: PO WI-M2-12 ruling 1 (`po-m2-wi12.md`): accepted as built.** A field has a
   value only once the model has finished writing it; no `emitted` or `updated` draft ever holds part of a field the
   model is still writing. WI-M2-06 D8 stays. The PR #22 ticket is closed with the new expected result
   (`titleArrivesLast`). The same rule binds WI-M2-M2. The brief amendments 1–3 are in `brief.md` (round 2).
   Original question: the cloud reader shows only finished values, so rule (a) never fires on part of a title, and a
   draft never shows part of one. Without that, the blank first step of a late title (`""`), or a guarded prefix
   (`"Late"` of `"Later"`), is skipped for good under D8.
2. ~~**PO / Planner (watch, J6):**~~ **Closed: PO WI-M2-12 ruling 2 (`po-m2-wi12.md`): accepted as built.** `null` is
   not a value under rule (a). Correction: the cloud latency gate is **AC-M2-27**, not AC-M2-16. The schema
   direction (no `null` for rule-(a) fields; a blank `room` gives room `none`, a blank `sourcePhrase` gives nil) is
   for WI-M2-10. Original question: an OpenAI strict-mode item with `"room": null` completes only at (b) or (c).

### Round 2 (review round 1: APPROVE with 2 Minors and 3 Nits, `review-WI-M2-12.md`; PO rulings `po-m2-wi12.md`)
- **Merge:** `origin/main` at `aa38472` (PR #24, WI-M2-09) merged in, with no rebase. In the dev-notes conflict I kept
  main's file and appended this section at the end. No source conflict.
- **Brief:** I put PO WI-M2-12 amendments 1–3 into `brief.md` word for word: Item completion (a), the end of the
  `updated(draft)` bullet, and the new AC-M2-05 bullet.
- **R26-F1 (fixed):** new test "AC-M2-05 / AC-M2-24: a title whose prefix is a banned token ("Late" of "Later: call
  the plumber") …", parameterised over the 3 cloud routes and 1-, 2- and 3-byte chunks (9 cases). The input says
  "later", and the title arrives last. No step shows a part title. Through `DraftPipeline` there is exactly one
  `emitted` with the whole title, no `itemSkipped`, no `updated`, and the outcome is `completed`. A control assertion
  in the same test shows that the case is real: the same item with the prefix `"Late"` shown as a value gives
  `itemSkipped`.
- **R26-F2 (ticket):** the response-size cap is recorded in "Known limitations / follow-ups" for WI-M2-13 or WI-M2-14.
  This PR has no code change for it, as the review asks.
- **R26-N1 (fixed):** the parser header and the `byteOffset` doc now say "for a malformed number, the byte that ends
  it". So does the rules list above.
- **R26-N2 (fixed):** (a) the `value` doc now says "a root number or literal" (an open root string is shown); (b) the
  reader header and J2 now note that the time hint gains sub-fields.
- **R26-N3 (optional, not taken):** whole-value equality for values under unknown keys. The reader ignores those keys,
  so no AC depends on it. `everyCut` and `completeValues` keep the value-level oracle for fixed texts.
- **Mutant:** M18 ("the reader shows open strings") was run again and is killed by the new test too (and by
  `titleArrivesLast` and the reader property).
- **Tests** (Linux, `swift:6.2-noble`, `-warnings-as-errors`, 0 warnings):
  - TendIngestion: `✔ Test run with 333 tests in 42 suites passed after 47.441 seconds.` That is 284 on `main` at
    `aa38472`, plus 48 from round 1, plus 1 new test with 9 cases.
  - TendCore: `✔ Test run with 141 tests in 18 suites passed after 95.366 seconds.`
  - TendSourceScan: `✔ Test run with 63 tests in 4 suites passed after 1.498 seconds.`
  - AC-M2-09 scan: 30 files in total, 0 violations. AC-M2-12 vocabulary scan: 30 files, 0 violations.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The reader only turns model output into snapshots. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | J2 keeps a part title from being cut by the guard and a capture item from being lost. Every new name (`cutShort`, `unexpectedByte`, `dataAfterValue` …) passes the AC-M2-12 vocabulary scan (0 violations). The outcomes are the WI-M2-06 ones. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | Parsing only. Nothing here chooses a model. |
| P-2 No data leaves the device | pass | Pure parsing over bytes and strings: no network, file I/O or logging (AC-M2-09 Rule 1: 0 violations). No dependency. |
| P-3 Cloud AI opt-in, minimised | pass | The reader reads the response only. The cloud model gets no `Tool` (`lookupQueries` is always empty), and a cloud claim stays a shortlist index for the local re-check. |
| P-4 Media not persisted | n.a. | Text only, held in memory. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Developer | accepted (H2) | WI-M2-12 Ready (WI-M2-06 merged; `main` at `3bac3ce`). PO ticket "title that arrives last"; claim-field mapping. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 283, TendCore 141, TendSourceScan 63 green, 0 warnings, Linux. 25 of 25 mutants killed. Two PO questions (J2, J6). Pushed; no PR opened. |
| 2026-11-23 | Reviewer (via Orchestrator) | Developer | returned (round 1) | APPROVE with R26-F1, F2 (Minor) and R26-N1…N3 (Nits), `review-WI-M2-12.md`. PO `po-m2-wi12.md`: J2 and J6 accepted; brief amendments 1–3. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (round 2) | Merged `origin/main` `aa38472`. Brief amendments 1–3 inserted word for word. R26-F1 test added (9 cases; M18 kills it). R26-N1 and N2 reworded. R26-F2 recorded as a ticket. N3 not taken. TendIngestion 333, TendCore 141, TendSourceScan 63 green, 0 warnings. Review file committed with the fix. |

---

## WI-M2-15 — eval scorer: `EvalResultsFileV1`, `results-v1.schema.json` and its Foundation-only check, the scorer, self-tests, `EvalIDGenerator`, `Tools/TendTools`

- **Owner:** Developer  ·  **Branch:** `m2/eval-scorer`, from `main` at `3bac3ce` (origin/main is still `3bac3ce`, so the
  requested merge of origin/main is a no-op; nothing was rebased or force-pushed)  ·  **PR:** not opened (Orchestrator)  ·
  **ADRs:** [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (scoring tool outside Rule 1; canonical JSON).
  No new ADR: no dependency, no new module (`Tools/TendTools` is named in the plan and ADR-0006).
- **Requirements:** ○ **AC-M2-14** (scorer self-tests; the owner item is WI-M2-16). It also delivers the Linux halves
  that AC-M2-11, 15, 16, 17, 25, 26 and 27 score with, and the AC-M2-28 results-file schema validation and rejection
  test. FR-A1, UX-3 (calm-words count), P-4 (the file format has no place for audio, bodies, header values or keys).
- **Inputs:** brief Definitions (Keywords, Name folding, Banned tokens, Draft, Duplicate, False merge), **Eval scoring
  rules**, Device-run rules, AC-M2-11, 14–17, 25–28; plan WI-M2-15 row and scope note, "Module and file layout",
  "Named files", "Scoring tool and command", "Eval harness ID generator", R-22; ADR-0006; PO notes `po-m2-wi07.md`
  (watch item on in-input repeats), `po-m2-wi08.md` (commit re-check), `po-q21-q22.md` (GK-2, Q23 loader exception).
- **Milestone lock:** M1 `ACCEPTED`, M2 `IN-BUILD` (`STATUS.md`); WI-M2-15's dependencies WI-M2-01 and WI-M2-05 are
  merged. No protected path is touched (`.github/**` unchanged; CI's existing "Build tools" step now finds the package).

### What changed
- **`Packages/TendIngestion/Sources/TendIngestion/Eval/`** (Foundation + TendCore only, no I/O; scanned by AC-M2-09
  Rule 1 and the AC-M2-12 vocabulary scan):
  - `EvalJSON.swift`: a strict RFC 8259 reader (`EvalJSONReader`) into `EvalJSON`: integers only, duplicate keys
    refused by UTF-8 bytes, Boolean/number kept apart, depth limit 64, typed `EvalJSONError`.
  - `EvalSchemaCheck.swift`: the Foundation-only conformance check. It **interprets the committed schema** over a
    closed subset (`type`, `enum`, `const`, `properties`, `required`, `additionalProperties: false`, `items`,
    `minItems`, `uniqueItems: true`, `minimum`, `maximum`, `minLength`, `pattern`, `oneOf`, plus annotations) and fails
    closed on any other keyword or form. No JSON Schema library.
  - `EvalInstant.swift`: UTC millisecond instants by civil-calendar arithmetic (no formatter, calendar or locale).
  - `EvalResultsFileV1.swift`: the results-file type (plan "Named files"), its enums, `DraftRecord` (with
    `init(draft:roomKeys:taskKeys:)` for the harness and `invariantViolation` = the M1 initialiser), and
    `canonicalJSON` for the harness writer.
  - `EvalResultsReading.swift`: `EvalResultsFileV1.read(_:schema:fixtures:expectedFixturesSHA256:)` with typed
    `EvalRejection` and `EvalInconsistency` (order of checks below).
  - `EvalFixtures.swift`: the fixture formats for `inputs.json`, `household.json`, `golden.json` (below), strict
    readers with typed `EvalFixtureError`, `household` (a fresh M1 `Household`), key maps, `inputNumber(of:)`.
  - `EvalScorer.swift`: the scoring rules. `EvalProfile.swift`: the six profiles and `EvalScorer.run(_:)`, the one
    entry point. `EvalScoreLog.swift`: the scorer log. `EvalIDGenerator.swift`: the plan's ID generator.
- **`Fixtures/M2/eval/results-v1.schema.json`**: the v1 schema (214 constraints). WI-M2-16 adds the eval fixtures and
  `MANIFEST.sha256` next to it.
- **`Fixtures/M2/eval-selftest/`**: the hand-built self-test set (not the eval): `inputs.json` (7 inputs),
  `household.json` (3 rooms, 6 tasks, one completed, two identical), `golden.json` (16 items),
  `results-selftest-1.json` (readable), `results-selftest-1.canonical.json` (the same, canonical, scored by the tool),
  `results-selftest-1.score.log` (the expected scorer log, pinned by a test).
- **`Tools/TendTools/`** (new local package; may read files and print, outside Rule 1): library `TendToolsSupport`
  (hand-written argv parsing, `EvalScoreCommand`, `PayloadDumpCommand`, injected `ToolIO`), executables
  `tend-eval-score` and `tend-payload-dump`, tests `TendToolsTests`. It depends only on `../../Packages/TendIngestion`.
  - **`tend-payload-dump` is a stub.** The payload builder (WI-M2-10) is not built. The stub checks
    `--provider <openai|anthropic|gemini> --outcome-sample`, prints no body and exits **3** with "the payload builder
    is not built yet (WI-M2-10)". WI-M2-10 replaces the body of `PayloadDumpCommand.run`.
- **Not changed:** every other TendIngestion file, TendCore, TendSourceScan, all protected paths, every dependency.

### The scoring rules as built (brief "Eval scoring rules"; each has a hand-built self-test)
| Rule (brief heading) | Code | Self-test |
|---|---|---|
| Household state: a fresh copy per input | `scoreInput` uses only the input's golden items and the seeded tasks | in06 (oven item also in in02; c = 1, no duplicate) |
| Draft text = keywords(title) joined with keywords(sourcePhrase) | `draftText(of:)` | in01 d1, in05 d3 (item satisfied only through the phrase); unit test |
| Satisfies (a token from **each** group); Overlap | `satisfies`, `overlap` | unit test; M15 |
| Primary = not `ofDraft` | `isPrimary` | in03 d5 (neither paired nor extra) |
| Segmentation: pairs sorted overlap ↓, golden order ↑, draftID ↑, greedy | `segmentationPairs` | in05 (overlap 3 beats lower draftID), in04 (**tie in matching**), in03 |
| Not found / extra | `notFound`, `extras` | in02 (`g02-mirror`), in03 (2 extras), in05 (1), in07 (noModel) |
| Denominators: only found items score; ⌈p × N⌉ | `EvalMetric.requiredCount` | totals test (N = 16); 48/45/43 at N = 50; 49 at N = 51 |
| Room scoring: existing / new(name, alternates) / none | `roomIsCorrect` | in01 (**proposed-room match** via alternate "the Terrace"), in04, in06; 12-case table |
| Validity: all emitted drafts, the M1 invariants | `DraftRecord.invariantViolation` | in05 d3 (`windowEndNotAfterStart`) |
| Calm words: titles and proposed room names; a token the user said is kept | `scoreInput` with `BannedTokens` | in06 ("late" said and kept; "overdue" in a title, "missed" in a room name) |
| Best target: highest overlap; ties golden before seeded, then lower key; completed tasks are not targets | `bestTarget`, `precedes`, `targets` | in05 (golden over seeded; `t-plants-a` over `t-plants-b`), in04, completed `t-bins` test |
| Duplicates created: Σ max(0, c(g) − 1) + Σ c(t) | `scoreInput` | in03 (**duplicate created**: 3), in04 (1), in05 (2) |
| False merge: a marked draft with best target g and c(g) = 0, each g once | `scoreInput` | in02 (**false merge** `g02-oven`); in03 d5 is marked but c(g03-towels) = 2 |
| Last attempt scored (device-run rules) | `score` | in02 (attempt 2 of 2) |
| Output: per-input and total counts, each pairing, each best target | `EvalScoreLog.render` | log test + the committed `results-selftest-1.score.log` |

### Results-file checks, in order (all exit 2 in the tool)
1. JSON (`EvalJSONReader`). 2. `schemaVersion` = 1 (`notVersion1`). 3. Schema conformance (`schemaIssues`, with JSON
Pointer paths). 4. Canonical bytes: writing the parsed value with `CanonicalJSONWriter` gives the same bytes
(`notCanonical`; a trailing newline is refused). 5. `run.fixturesSHA256` = `--expected-fixtures-sha256`
(`fixturesHashMismatch`). 6. Cross-field rules (`EvalInconsistency`): known input and matching mode; attempts 1, 2, …
in file order; text 1 attempt, voice ≤ 2 (one retake); retake reason exactly on attempts ≥ 2; transcript and
transcriber exactly on voice; unique draft IDs; known room and task keys, `ofDraft(k)` only to an earlier draft; real
window dates; events (emitted once per draft, `updated` after it, `itemSkipped`/`finished` with no draft, `finished`
once and last, the drafts are exactly the emitted ones); non-decreasing times, `ttfiMs` = first `emitted`, `totalMs` =
`finished`; `noModel` has no draft, `interrupted` has ≥ 1; `committed` = exactly the unmarked drafts (none for
`cancelled`); cloud requests only on a cloud route, numbered 1, 2, …, key paths sorted by UTF-8; a real
`startedAtUTC`; a known cold-start input.

### Fixture formats (for the Tester, WI-M2-16; unused members are ignored, so notes and composition tags may be added)
- `inputs.json`: `{"schemaVersion":1,"inputs":[{"id","mode":"text|voice","text"}]}`. Order = input number for
  `EvalIDGenerator`.
- `household.json`: `{"schemaVersion":1,"rooms":[{"key","id":"<UUID>","name","lastTendedAt"?}],"tasks":[{"key","id",
  "title","kind","roomKey":null|"<room key>","effort","isCritical","isDeepClean","isWeatherDependent",
  "allowedDayparts":[…],"allowedWeekdays":[…],"windowStart","windowEnd","recurrenceIntervalDays":null|n,
  "state":"active|maintenance|resurfaced|completed|deferred","deferredUntil"? ,"completedAt"?,"matchGroups":[[…]]}]}`.
  Every task must pass the M1 initialiser. Dates are `yyyy-MM-ddTHH:mm:ss.SSSZ`.
- `golden.json`: `{"schemaVersion":1,"items":[{"inputID","key","matchGroups":[[…]],"kind","room":{"type":"existing",
  "roomKey"}|{"type":"new","name","alternates":[…]}|{"type":"none"},"effort","isCritical","isDeepClean",
  "isWeatherDependent","expect":{"type":"create"}|{"type":"existing","seededKey"}}]}`. File order is the "golden
  order".
- Checked: keys unique (golden and seeded keys share one namespace), IDs unique, references resolve, every match-group
  token is exactly one keyword (`Keywords.of(t) == [t]`; a capital, a stop word or two words can never match and are
  refused), no empty group. The v4-UUID check and the composition check are WI-M2-16.

### Decisions the Reviewer and Tester should know (technical readings; none changes a rule)
- **S1 Draft text is a set.** "joined" is read as the distinct union (title keywords, then new phrase keywords), as
  "Keywords of a text" keeps distinct tokens. A phrase that repeats the title does not double the overlap.
- **S2 Committed means confirmed.** `committed[]` is the draft IDs handed to commit. Under AC-M2-17 the harness commits
  every unmarked draft, and a `none` draft is never re-checked at commit (`po-m2-wi08.md` ruling 2), so this equals the
  created set; the reader refuses a file where it does not.
- **S3 "Lower key"** is ascending UTF-8 byte order (as every other tie-break in M2).
- **S4 Introduced tokens are counted per occurrence** in titles and proposed room names, against the fixture text
  (text) or the attempt's transcript (voice).
- **S5 Profiles add sanity checks** beyond the literal threshold list, each tied to the AC's Given: ds1 runs have no
  provider and every route is `onDevice`; ds2 runs route to `run.provider`; gated profiles need every fixture input and
  N ≥ 50; a missing TTFI (no draft) does not meet AC-M2-16/27; ds1-offline needs exactly 3 inputs (2 voice), ds2-offline
  and ds2-online exactly 2 voice inputs. `ds2-offline` cannot see the plain-note offer (not in the v1 file); DS-2 records
  it by eye.
- **E1 Integers only.** Times are whole ms; network speeds are whole Mbit/s (the canonical writer has no floats).
- **E2 Tagged objects** for `room` (`existing`/`proposed`/`none`) and `duplicate` (`none`/`ofExisting`/`ofDraft`),
  checked with `oneOf`.
- **E3 Key-path form** (`pattern`): `$` then `.name` or `[]` segments, names `[A-Za-z0-9_-]+`, e.g.
  `$.messages[].content`. WI-M2-10 must write its allowed lists in the same form (open question Q2).
- **E4 Strict canonical bytes.** A hand-edited or re-saved file is refused; the self-test keeps a readable copy and a
  canonical copy (a test checks they agree). For an ASCII-only file, `python3 -c 'import json,sys;
  sys.stdout.write(json.dumps(json.load(open(sys.argv[1])),sort_keys=True,separators=(",",":")))' f.json` gives the
  canonical form (keys sort the same in UTF-8 and code points for ASCII).
- **E5 Dates are recorded to the millisecond, rounded down.** The conversion works from `timeIntervalSinceReferenceDate`
  with an exact integer offset and corrects the floor, so `EvalInstant(i.date) == i` (20,000-sample property). The
  first version went through `timeIntervalSince1970` and was off by 1 ms for some values; the property test found it.
  Two window ends less than 1 ms apart would read as equal.
- **E6 The fixtures hash is compared, not computed.** The tool compares `--expected-fixtures-sha256` (the
  `sha256sum` of `MANIFEST.sha256`, plan command) with the file's `run.fixturesSHA256`; `sha256sum -c` checks the files
  first. No crypto code in either package.
- **T1 Tool exit codes:** 0 pass, 1 not pass, 2 rejected (also unreadable files, unusable schema or fixtures, an
  unwritable log), 64 usage (also `ds2-gated` without `--allowed-key-paths`), 3 for the `tend-payload-dump` stub.
  `--schema` defaults to `<fixtures>/results-v1.schema.json`. `--allowed-key-paths` takes a JSON array of strings, or
  `{"keyPaths":[…]}` of strings or `{"path": …}` objects (WI-M2-10's format with roles fits).

### AC coverage
| AC | Test(s) (suite › test) | Environment | Result |
|---|---|---|---|
| AC-M2-14 scorer self-tests (every rule; false merge, duplicate created, proposed-room match, tie in matching) | `AC-M2-14 scorer self-tests over hand-built results files` › in01 … in07, totals, rule units (draft text, satisfies, room table, ⌈p×N⌉, best target, completed not a target, absent inputs), log + committed log | Linux | PASS (18 tests) |
| AC-M2-14 Tester re-score | `Fixtures/M2/eval-selftest/results-selftest-1.*` + `results-selftest-1.score.log` | Tester | **For the Tester** (WI-M2-16) |
| AC-M2-28 schema validation and rejection (Linux half) | `WI-M2-15 results-v1 schema conformance check` (R-22 walk: 214 of 214 constraints mutated and rejected at their path; 18 keyword cases; 20 refused schemas); `WI-M2-15 results file v1: read, write, reject` (headline rejections incl. a request body refused, 32 cross-field cases, writer round trip byte for byte, harness draft record) | Linux | PASS |
| AC-M2-28 deterministic ID generator (T-29) | `WI-M2-15 EvalIDGenerator` (plan's byte table, determinism, never version 4 over 5 × 15 × 20, ranges, through `DraftCommit.plan`) | Linux | PASS |
| AC-M2-11, 15, 16, 17, 25, 26, 27 scoring (Linux half; the ACs stay AWAITING-DEVICE) | `WI-M2-15 scoring profiles at their thresholds` (each threshold at its boundary: 57/56 of 60, 2/3 extras, 1/2 false merges, 1 duplicate, TTFI 1499/1500 and total 5000/5001, cloud 2999/3000 and 10000/10001, key paths, routes, N < 50, absent input) | Linux | PASS (13 tests) |
| Fixture formats (AC-M2-14 "Fixtures") | `WI-M2-15 eval fixture formats` (reads; 13 typed golden errors; household and inputs errors) | Linux | PASS |
| Tool exit codes (plan "Scoring tool and command") | `TendToolsTests` (7) + an end-to-end run of both built executables | Linux (local; CI builds only) | PASS |
| AC-M2-09 / AC-M2-12 scans over the new files | `AC-M2-09: Rules 1–6 …` (33 files, 0 violations); `AC-M2-12: no banned token …` | Linux | PASS |

### Test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings in every package)
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 297 tests in 37 suites passed after 104.586 seconds.` (235 + 62 in 7 new suites; the cross-field test now has 32 cases). AC-M2-09 `33 files in total, 0 violations` |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 7.568 seconds.` (unchanged) |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 159.892 seconds.` (unchanged) |
| Tools/TendTools | `✔ Test run with 7 tests in 1 suite passed after 0.234 seconds.` |

### Verification environment
| What | Where | Status |
|---|---|---|
| TendIngestion, TendSourceScan, TendCore suites, `-warnings-as-errors` | Linux (`swift:6.2-noble` container) | PASS, 0 warnings |
| Tools/TendTools build and its 7 tests; both executables run end to end on the self-test files (exit 0, 1, 2; stub 3) | Linux (container) | PASS. **CI only builds this package** (the "Build tools" step); its tests are not run in CI. HM-1b (owner) could add `swift test --package-path Tools/TendTools`. |
| AC-M2-09 / AC-M2-12 scans over the new `Eval/` files | Linux | PASS (33 files, 0 violations) |
| TendIngestion and TendTools on Darwin Foundation | owner-run Mac (B2) | **Not verified.** The reader is hand-written to avoid Linux/Darwin differences (no `JSONSerialization`, no formatter); `NSRegularExpression` (schema `pattern`) is the one Foundation engine used, with ASCII-only patterns. |
| Scoring a real device file | Device run + Linux scoring | **Not applicable yet** (no eval fixtures until WI-M2-16; no device run). The device ACs stay AWAITING-DEVICE. |

### Things the reviewer should look at closely
- `EvalScorer.scoreInput` against the brief's rules word by word (table above), especially the two different tie-breaks:
  segmentation uses **golden order**, best target uses **key**.
- `EvalSchemaCheck`: the fail-closed keyword list, `oneOf` counting, type-specific keywords, and the R-22 walk in the test
  (mutations are generated from the schema, not hand-listed).
- `EvalResultsReading.checkConsistency`: every cross-field rule is a rejection (exit 2), not a score. Check none is
  stricter than the device-run rules need (`committed` = unmarked drafts; events and timing equalities).
- `EvalInstant(_ date:)` floor correction (E5).
- `TendToolsTests.Captured` is a test-only `@unchecked Sendable` box with a comment (Reviewer sign-off asked by the
  skill); the commands run synchronously.

### Known limitations / follow-ups
- `tend-payload-dump` is a stub until WI-M2-10.
- The eval fixtures, `MANIFEST.sha256`, the composition check and the freeze are WI-M2-16 (Tester + Developer).
- The real-fixture composition check (v4 UUIDs, Q3 composition, ≥ 50 items) is not here; the gated profiles do check
  N ≥ 50 and every input present.
- CI runs no TendTools tests (above). The scorer logic itself is all in TendIngestion and runs in CI.

### Open questions — all closed (PO rulings `po-m2-wi15.md`, 2026-11-23)
1. **Q1 (two `create` items with identical match groups): closed, ruling 1.** The scoring rule stays as written;
   in04's 1 duplicate created is correct and stays as a self-test case. The eval fixtures must make every `create` item
   distinguishable within its input (checked in WI-M2-16 with a `referencePhrase`; the scorer ignores the member). The
   brief amendment ("Distinguishable targets") is inserted word for word in round 2.
2. **Q2 (key-path form): closed, ruling 2.** E3 confirmed: `$`, then `.name` or `[]`, names `[A-Za-z0-9_-]+`;
   WI-M2-10's lists use the same form (Planner adds it to the WI-M2-10 row).
3. **Q3 (S1, S4): closed, ruling 3.** S1 accepted. S4 accepted as: introduced = not in the fixture text (text) or the
   scored attempt's transcript (voice); each occurrence counts; a said token never counts. Round 2 pins both halves
   with in08 (R27-F2, R27-F3).

### Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-form entry | n.a. | No entry surface; eval tooling only. |
| UX-2 Rule of Three | n.a. | No selection surface; nothing returns "what to do now" items. |
| UX-3 Zero-guilt | pass | The scorer counts introduced banned tokens (Q3 calm words). No new identifier or literal in the module Sources holds a banned token (AC-M2-12 scan). Tool and log wording use PASS / FAIL / "does not pass", never a banned word. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. |
| P-2 No data leaves device | pass | No networking anywhere (AC-M2-09 Rule 1 over `Eval/`; TendTools reads and writes local files only and has no network code). No dependency added. |
| P-3 Cloud AI opt-in, minimised | pass | The file records only request byte counts and key paths (pattern-checked, no values); `additionalProperties: false` refuses a body, header or key member (tested). The `ds2-gated` profile checks sent key paths against the allowed list (AC-M2-26). |
| P-4 Media not persisted | pass | The v1 format has no field for audio, request or response bodies, header values or keys. The shipped modules gain no write or log API (Rule 1). |

### Mutation check (scratch copy `/tmp/claude-0/mut`, one mutant at a time, `--filter Eval`; the worktree was never touched and the copy's `Packages` was identical to it afterwards)
**27 of 27 killed** (M27 after adding a test).
| # | Mutant | Killed by |
|---|---|---|
| M1 | segmentation tie: draftID descending | in03, in04 (tie in matching), log |
| M2 | segmentation tie: golden order descending | in01, in03, in04, in05, totals, log |
| M3 | segmentation: overlap ascending | in01, in05, log |
| M4 | best target: seeded before golden | in05, ds1-gated duplicate checks, log |
| M5 | best target: higher key wins | in04, in05, log |
| M6 | `ofDraft` drafts are primary | in03, totals, log |
| M7 | create duplicates: c(g) instead of max(0, c(g) − 1) | 17 tests (self-tests and every profile) |
| M8 | completed seeded tasks are targets | "Best target counts completed seeded tasks out" |
| M9 | false merge without c(g) = 0 | in03, totals, log |
| M10 | draft text without the sourcePhrase | in01, in05, totals, draft-text unit, log |
| M11 | new room compared without name folding | in01, room table, totals, log |
| M12 | calm words: the user's own tokens not kept | in06, totals, log |
| M13 | first attempt scored instead of the last | in02, totals, log |
| M14 | required count rounded down | ⌈p×N⌉ test, log |
| M15 | satisfies with any group instead of each | satisfies unit test only (no in-file case differs; the unit test is the guard) |
| M16 | canonical-bytes check removed | headline rejections |
| M17 | `additionalProperties: false` ignored | headline rejections (request body), keyword table, R-22 walk (the script labelled it "BUILD ERROR" because test output holds the text `error:`; it built and 3 tests failed) |
| M18 | committed = unmarked check removed | cross-field cases |
| M19 | ID generator version nibble 4 | byte table, never-version-4, commit plug-in |
| M20 | instant floor not corrected upward | 20,000-sample round-trip property |
| M21 | TTFI boundary inclusive (1500 passes) | ds1 timing, ds2 timing |
| M22 | validity not checked | in05, totals, ds1 checks, log |
| M23 | fixtures hash not compared | headline rejections |
| M24 | extras threshold `<` 2 | extras boundary |
| M25 | `oneOf` accepts several branches | keyword table |
| M26 | duplicate JSON key accepted | reader rejections |
| M27 | `updated` accepted before its draft's `emitted` | **survived** at first: the case "updated before emitted" also removed draft 2's `emitted`, so another rule caught it. New case "updated before its draft's emitted, every draft still emitted" kills it (rerun: 1 issue at that case; clean copy green). |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Developer | accepted (H2) | WI-M2-15 Ready: WI-M2-01 and 05 merged (`3bac3ce`). Stay out of Routing/ (PR #24) and the SSE/JSON snapshot parsers. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first. TendIngestion 297, TendSourceScan 63, TendCore 141, TendTools 7 green, 0 warnings, Linux. R-22: 214/214 constraints. 27/27 mutants killed (M27 after a new case). `tend-payload-dump` is a stub (WI-M2-10 not built). Three open questions (Q1 fixture guidance to Tester/PO, Q2 key-path form to WI-M2-10, Q3 re-score confirmation). origin/main unchanged at `3bac3ce`, so no merge commit. Pushed; no PR opened. Next: Reviewer; then the Tester's independent re-score in WI-M2-16. |

### Round 2 (review round 1: CHANGES REQUIRED, `review-WI-M2-15.md`; PO rulings `po-m2-wi15.md`)
Merged `origin/main` at `aa38472` (PR #24) into the branch as `ccce8c1`, with no rebase and no force-push. In the `dev-notes.md` conflict I took main's file and appended this section at the end.

| Finding | Change |
|---|---|
| **R27-F1 Major** | `EvalSchemaCheck.compile` now gives `pattern` the ECMA-262 meaning. `icuPattern(fromECMA:)` rewrites every unescaped `$` outside a character class to ICU `\z` (end of input only). ICU `$` on Linux and on Darwin also matches before a final `\n`, `\r\n`, `\r`, U+0085, U+2028 or U+2029. The wrong comment ("the part ICU and ECMA-262 read the same way") is replaced. New tests: "R27-F1: the list covers every pattern in the committed schema (6)"; "R27-F1: each schema pattern refuses its valid value followed by …" (6 pattern locations × 6 terminators = 36 cases: `\n`, `\r\n`, U+2028, `\r`, U+0085, U+2029; each is rejected at its path with keyword `pattern`, and the valid value is still accepted); "R27-F1: a file with a trailing newline in a pattern field is rejected by the reader" (the review's probe P2); the ECMA-to-ICU spelling table (5 cases); and pattern semantics (an escaped `\$`, an unanchored pattern, U+2028). New mutant M28 (no rewrite) is killed by 4 tests. |
| **R27-F2 Major** | New hand-built voice input `in08` in the self-test set. Its script says "late" and not "behind"; its transcript says "behind" and not "late". d1 "Sort the post behind the door behind the shed" counts 0, because the user said "behind". d2 "Fix the late late gate" counts 2, because "late" is only in the script. The hand derivation is in the test "AC-M2-14 (in08): …", and the pinned `results-selftest-1.score.log` is regenerated. The review's mutant M-R2 (always use the fixture text) is now **killed** by 2 tests (in08, log). |
| **R27-F3 Minor** | in08 also pins S4: an introduced token twice in one title counts 2, and a said token twice counts 0. The review's mutant M-R1 (once per distinct token) is now **killed** by 3 tests. |
| **R27-F4 Minor** | New draft in05 d5 "Sort the shelves". It holds tokens from 2 of `g05-garage`'s 3 groups and none from `{garage}`, so it does not satisfy the item: it is extra, with no best target. M15 (any group instead of each) is now killed in the hand-built file as well (4 tests, including in05: c(g05-garage) would become 2). |
| **R27-F5 Minor (owner)** | **Owner ticket HM-1b:** add `swift test --package-path Tools/TendTools -Xswiftc -warnings-as-errors` to the CI "TendIngestion swift test (Linux)" job. `.github/**` is protected, so this needs a human merge. Until then, the 7 TendTools tests (the 0/1/2/64 exit-code contract and the stub's exit 3) run only locally and in review. |
| R27-N1 Nit | Done. `TendToolsTests.Captured` holds a `Synchronization.Mutex`, is checked `Sendable`, and has no `@unchecked`. |
| R27-N2 Nit | Not done. Caching would need `NSRegularExpression` values stored in a `Sendable` struct, and that type is not declared `Sendable` in swift-corelibs-foundation. At eval size the cost is trivial, as the review says. |
| R27-N3 Nit | Recorded for the Tester. (a) The E4 one-liner is only for the hand-built ASCII self-test file. A device results file is committed byte for byte and never re-saved or re-formatted (DS-1, DS-2). (b) Whole Mbit/s stays as it is unless the PO asks for more precision. |
| PO ruling 1 | The "Distinguishable targets" bullet is inserted into `brief.md` word for word, as the last sub-bullet of "Eval scoring rules" > **Fixtures**. Open questions 1–3 are closed above, citing rulings 1–3. |

**Self-test set after round 2:** 8 inputs and 18 golden items. The hand-derived totals are: N 18, found 16, kind 15, room 13, effort 15, each flag 15, extras 4, drafts 21 (20 valid), 4 introduced tokens, 6 duplicates created and 1 false merge. The regenerated log matches these numbers.

**Round 2 test runs** (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings in every package, on the merged tree):
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 352 tests in 44 suites passed after 82.799 seconds.` That is main's 284 (the WI-M2-09 routing tests are now included) plus 68 eval tests in 7 suites (62 + 6 new). AC-M2-09: `37 files in total, 0 violations`. The AC-M2-12 vocabulary scan passes. |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 6.452 seconds.` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 124.097 seconds.` |
| Tools/TendTools | `✔ Test run with 7 tests in 1 suite passed after 0.171 seconds.` |

**Round 2 mutants.** I ran them on a fresh scratch copy of the merged tree with `--filter Eval`. The worktree was never edited, and afterwards the copy's `Packages` and `Fixtures` were identical to it. All 27 round 1 mutants were rerun, plus the review's M-R1 and M-R2 and the new M28: **30 of 30 killed**. M17 was again labelled "BUILD ERROR" by my script only because the test output contains the text `error:`; it built, and 3 tests failed.

| # | Mutant | Killed by |
|---|---|---|
| M1–M14, M16–M27 | as in round 1 | the same tests as round 1 (M2 now 7 tests, M7 18, M12 4) |
| M15 | satisfies with any group | now 4 tests, including in05 (R27-F4) |
| M-R1 | calm words once per distinct token per title | in08, totals, log (R27-F3) |
| M-R2 | voice judged against the fixture text | in08, log (R27-F2) |
| M28 | `$` not rewritten to `\z` (ICU end of line) | the 4 R27-F1 tests |

**Second merge (round 2).** main moved again (PR #26, WI-M2-12). I merged `origin/main` at `03e98c6` as `0e03a66`, again with no rebase and no force-push. In the `dev-notes.md` conflict I took main's file and appended this section at the end. I re-ran all four packages on the merged tree (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, 0 warnings):
- TendIngestion: `✔ Test run with 401 tests in 49 suites passed after 93.359 seconds.` AC-M2-09: `40 files in total, 0 violations`.
- TendSourceScan: 63 tests.
- TendCore: 141 tests.
- Tools/TendTools: 7 tests.

The merge changes no file under `Eval/`, no eval test and no self-test fixture, so the 30 of 30 mutant result above still applies.

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Reviewer (via Orchestrator) | Developer | returned (round 1) | CHANGES REQUIRED: R27-F1 and F2 Major; F3–F5 Minor; N1–N3. PO `po-m2-wi15.md` answered Q1–Q3. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1–F4 fixed, F5 is owner ticket HM-1b, N1 done, N2 declined with a reason, N3 recorded. The brief amendment is inserted word for word, and Q1–Q3 are closed. origin/main `aa38472` and then `03e98c6` are merged. All four packages are green with 0 warnings on the merged tree (TendIngestion 401). 30/30 mutants killed. The review file is committed with the fix. |

---

## WI-M2-10 — context selector and payload builder for the three providers: provider table, canonical body, headers, key placement, opt-outs, sampling, curated models (Q18), input type, recording mock transport, 3 × 3 golden requests, allowed key-path lists with roles

- **Owner:** Developer  ·  **Branch:** `m2/payload-builder`, from `origin/main` at `6fd1bf4` (PRs up to #27 merged:
  routing and consent, stream reader, eval scorer)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none
  new. Follows [ADR-0005](../../architecture/adr/0005-cloud-ai-providers.md) Decisions 3–6 and
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): new files under `TendIngestion/Sources/TendIngestion/Payload/`,
  Foundation and TendCore only, no I/O, no network, no logging, no new dependency.
- **Requirements:** FR-A1, P-2, P-3, P-4, UX-3. **○ AC-M2-20** ([plan.md](plan.md) WI-M2-10): the selector, the
  builder, the input type and its `Mirror` test, the recording mock transport, the golden requests and the allowed lists.
  **WI-M2-11 owns AC-M2-20 (●)**: the ≥ 500-household byte-level sentinels (a) and the structural check (b). The golden
  bytes are repeated on the owner-run Mac in MS-2. The allowed lists feed AC-M2-26 (`ds2-gated`) and the AC-M2-28
  harness.
- **Binding inputs:** brief Definitions ("Cloud request", "Duplicate shortlist", "Item completion"), AC-M2-20, Q12,
  Q16–Q19; plan WI-M2-10 (provider shapes, Q18 models and the five conditions, N-3), R-6, R-15; PO WI-M2-12 ruling 2
  (no `null` in rule-(a) fields; blank room → `none`, blank `sourcePhrase` → nil); PO WI-M2-15 ruling 2 (key-path form,
  pattern test); review ticket R1-F6 (name the provider-table file and narrow Rule 4); WI-M2-12 J1 (schema from
  `StructuredOutputKey`); WI-M2-15 `tend-payload-dump` stub.
- **Q12, Q16, Q17 are still open with the owner. Built on the PO defaults** (`owner-decisions.md`): Q12 yes (up to 10
  shortlist titles), Q16 all three providers, Q17 Gemini kept (its consent-screen warning is M3 copy). The selector
  takes the Q12 answer (`CloudTitleSharing`); under Q12 = no it selects no title, so only the golden G2/G3 bytes change.
  A later owner answer is R-15: regenerate the goldens and lists under a PO decision before the freeze (see the fixtures
  README).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`; WI-M2-07 (the dependency) is merged.

### What changed
- **New, `Packages/TendIngestion/Sources/TendIngestion/Payload/`** (scanned by AC-M2-09 Rule 1 and the AC-M2-12
  vocabulary scan):
  - `CloudPayloadInput.swift`: `CloudPayloadInput` (stored properties `capture: String`, `roomNames: [String]`,
    `shortlistTitles: [String]`, nothing else) and `CloudContextSelector.input(capture:household:titleSharing:)`.
  - `CloudProviderTable.swift`: **the provider table**, the only file with the three bare hosts (R1-F6). `CloudModel`
    (the curated, pinned model IDs, Q18), `CloudProviderEndpoint` (host, auth header and prefix, fixed headers, query,
    path), `CloudProviderTable` (hosts, `Content-Type`, `anthropic-version`, the output cap).
  - `CloudRequest.swift`: `CloudRequest` (provider, model, method, bare host, path, query items, headers, body bytes),
    `CloudRequestHeader` (the key is held as an `APIKey`, read through `withValue`), `CloudQueryItem`.
  - `CloudOutputSchema.swift`: `CloudInstructions.text` (the fixed instructions) and the output schema in two dialects,
    written from `StructuredOutputKey` and the Swift enums.
  - `CloudPayloadBuilder.swift`: `request(_:model:key:)`, `body(_:model:)`, `userContent(_:)`.
  - `CloudRequestKeyPaths.swift`: `CloudRequestKeyPaths.leafPaths(ofBody:)` (the one key-path function for the harness,
    `ds2-gated` and WI-M2-11) and `CloudAllowedKeyPaths.list(for:)` (derives an allowed list with roles).
- **Changed (wiring, small):** `IngestionRequest` gains `shortlistTitles` (default `[]`); `DraftDuplicateCheck` gains
  `sentShortlistTitles` (default `[]`, implemented by `DraftDuplicateRules` for cloud Q12 = yes); `DraftPipeline` puts
  the rules' titles into the request. No behaviour of the stream, the marker or the router changes.
- **Changed, `TendSourceScan` (R1-F6):** `IngestionScanConfiguration.providerTableFile`; Rule 4 now allows bare hosts
  only in that file (`"bare host outside the provider table"` elsewhere in TendIngestion; other modules keep
  `"bare host outside TendIngestion"`). `ScanScope.swift` names the file. Plan "Named files" gains its row.
- **Changed, `Tools/TendTools`:** `tend-payload-dump --provider <p> --outcome-sample` is real: it prints the builder's
  body for the Outcome sentence with an empty household (no rooms, no titles), exit 0, and the method, host, path and
  query on standard error. Exit 3 ("not built yet") is gone. It never takes or prints a key.
- **New fixtures, `Fixtures/M2/payload/`:** `golden/` (9 × `.head.txt` + `.body.json`), `allowed-key-paths-<provider>.json`
  (3), `README.md`, `.gitattributes` (`* -text`, exact bytes).
- **Tests (written first; the first build failed with "cannot find 'CloudPayloadInput' in scope" and ~40 similar; the
  scanner tests first failed with "extra argument 'providerTableFile'"):** `PayloadTestSupport.swift` (golden
  households, fake key, the recording mock transport, independent `JSONSerialization` oracles),
  `PayloadBuilderTests.swift`, `PayloadGoldenTests.swift`; `TendSourceScan` Rule 4 tests; `TendToolsTests`.
- Not changed: `TendCore`, every protected path, every dependency.

### The requests as built (each line is tested; bodies are canonical JSON)
| | OpenAI | Anthropic | Gemini |
|---|---|---|---|
| Line | `POST api.openai.com /v1/chat/completions` | `POST api.anthropic.com /v1/messages` | `POST generativelanguage.googleapis.com /v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse` |
| Headers (order) | `Authorization: Bearer <key>`, `Content-Type: application/json` | `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `Content-Type: application/json` | `x-goog-api-key: <key>`, `Content-Type: application/json` |
| Model (Q18, pinned) | `gpt-4.1-mini-2025-04-14` (body `model`) | `claude-haiku-4-5-20251001` (body `model`) | `gemini-2.5-flash` (path) |
| Instructions | `messages[0]` (system, string) | `system` | `systemInstruction.parts[0].text` |
| User content | `messages[1].content[0].text` | `messages[0].content[0].text` | `contents[0].parts[0].text` |
| Structured output | `response_format` json_schema `tend_capture`, `strict: true` | one tool `record_items`, `tool_choice` forced | `responseMimeType: application/json`, `responseSchema` |
| Streaming | `stream: true` | `stream: true` | `:streamGenerateContent?alt=sse` |
| Sampling, reasoning | `temperature: 0` (not a reasoning model) | `temperature: 0`, no `thinking` member | `temperature: 0`, `thinkingConfig.thinkingBudget: 0` |
| Opt-outs (AC-M2-20) | `store: false` | none offered | none offered (Q17) |
| Output cap (fixed) | `max_completion_tokens: 4096` | `max_tokens: 4096` (required) | `maxOutputTokens: 4096` |

User content (all three): the canonical JSON text
`{"capture":"…","existingTasks":[{"index":1,"title":"…"},…],"rooms":["…",…]}`. Instructions, schema and every fixed
number hold no decimal string 600…729 (N-3, tested).

### Decisions the Reviewer should know (technical; product-meaning readings are flagged)
- **D1, the user content is one JSON text.** Capture, room names and titles go into one user text as canonical JSON. A
  quote, brace, newline or key-like text in a capture or label stays a JSON string value: it can never change the
  structure the model reads, or the body's key paths (tested with 7 hostile texts). The plan allows a templated user
  string ("the slots are compared after the template is removed"); here removing the template means parsing that JSON
  and checking its exact shape (`PayloadOracle.slots`). The instructions tell the model to treat it as data.
- **D2, roles (N-3) need two more names.** Because the three slots share one string, the outer list has two roles,
  `fixed` and `userContent` (one path, with its concrete path in `at`), and a second layout list
  (`userContentKeyPaths`) gives the slot roles `capture`, `roomName`, `shortlistTitle`, plus `shortlistIndex` (the
  1…n numbers) and `emptyList` (an empty `rooms` or `existingTasks`). The Tester reviews this in WI-M2-16 (open
  question 4).
- **D3, a key path is a leaf path.** The path of every scalar and of every empty array or object, in the results-file
  form, sorted and unique (`CloudRequestKeyPaths.leafPaths`). Containers are not listed: their leaves are. So the
  outer key-path set of a body is the same for every household (tested on all goldens and the hostile texts), and an
  added member or empty object is caught. The harness (AC-M2-28), `ds2-gated` (AC-M2-26) and WI-M2-11 must use this
  function. An independent `JSONSerialization` oracle agrees on every golden.
- **D4, `null` and rule (a) (PO WI-M2-12 ruling 2).** Every member is required in all three dialects (OpenAI strict
  mode needs it; the others are asked the same). The rule-(a) fields `title`, `kind`, `room`, `effort`, the three
  flags, `time.anchor` and `sourcePhrase` are never nullable; `""` means none for `room` and `sourcePhrase`, and
  `anchor: "none"` means no time. The other hint members and both claims may be `null` (`anyOf […, {"type":"null"}]`;
  Gemini `nullable: true`). Tests: a strict-mode item with `room: ""`, `sourcePhrase: ""`, `anchor: "none"` meets
  `hasValueForEveryField`; a blank (`""`, spaces, tab/newline) room maps to room `none` and a blank phrase to nil
  through `DraftMapper`. **No gap found for any provider** in the shapes as written; WI-M2-M6 confirms on the wire.
  The mapper's repair log still records `roomDefaulted` / `sourcePhraseDropped` for a blank value (diagnostic only;
  no draft field differs).
- **D5, member order: the canonical order.** The body must be canonical (sorted keys), and strict structured output
  writes members in schema order, so every provider writes `effort, isCritical, isDeepClean, isWeatherDependent, kind,
  room, sameAsExisting, sameAsItem, sourcePhrase, time, title`. Gemini gets the same order through
  `propertyOrdering`. Consequences: the claims come before the last rule-(a) field, so a duplicate marker is set
  before `emitted` (no `updated` just for a claim); the time hint finishes before the item completes; the title comes
  last, which WI-M2-12 J2 already handles (one `emitted`, whole title). Whether writing the title last costs accuracy
  is an R-2 watch item for the dev-set run (open question 2).
- **D6, one shortlist.** The cloud request's titles come from the duplicate rules' own shortlist
  (`DraftDuplicateRules.sentShortlistTitles`), so the titles sent and the index claims accepted cannot differ.
  `CloudContextSelector` computes the same values from the household; tests check selector = rules = what the router's
  cloud model sends, for every golden and provider, and selector = the WI-M2-07 independent oracle over 3,600
  seeded captures.
- **D7, the key never formats.** `CloudRequest` and `CloudRequestHeader` show the auth header as `(hidden)` and the
  body as a byte count in `description`, `debugDescription` and `dump`; the capture and room names never appear there
  either (P-4). The transport reads header values only through `withValue`.
- **D8, fixed protocol members beyond the plan's list.** `max_completion_tokens` / `max_tokens` / `maxOutputTokens`
  4096 (Anthropic requires one; it also bounds cost and response size, cf. R26-F2), the Anthropic tool name and
  description, the OpenAI schema name, and Gemini `format: "enum"` and `propertyOrdering`. None carries household data
  or varies per request. I read ADR-0005's "a new request field needs a new ADR" as household-data fields; the
  Reviewer should confirm (open question 3).
- **D9, R1-F6.** Two existing scanner tests placed a bare host in a generic TendIngestion file and expected it to pass.
  They now place it in the provider-table path, and new assertions show the same text elsewhere is caught. The rule is
  stricter; no assertion was removed.
- **D10, golden households live in test code** (`PayloadGolden`, fixed version-4 UUIDs, dates and states that are never
  sent). The test can regenerate the files into a directory named by `TEND_PAYLOAD_GOLDEN_OUT`, never into the
  repository; it always compares with the committed bytes.
- **D11, empty or blank room names are sent as written** (Q19, most literal reading). The selector does not filter or
  de-duplicate room names.

### AC coverage
| AC (part) | Test(s) | Result |
|---|---|---|
| AC-M2-20 media (input type) | "AC-M2-20 media: the builder's input type stores exactly capture: String, roomNames: [String], shortlistTitles: [String] (Mirror)"; "the builder input from a pipeline request …" | PASS (Linux) |
| AC-M2-20 shortlist (selector) | "… selector gives the capture, the room names as written in household order, and the shortlist titles in rank order (G2 hand-derived)"; "… at most 10 titles; completed tasks are never sent; titles are trimmed (G3)"; "AC-M2-20 Q12 = no …"; property "3 seeds × 200 households × 6 queries …" (seeds `0x0A1D20100001…03`, against the WI-M2-07 oracle) | PASS (Linux): 3,600 captures, 0 mismatches; 11,140 titles; 327 captures cut at 10 |
| AC-M2-20 shortlist (wiring) | "… through the router: a cloud capture's request carries the selector's titles …" (per provider, 3 goldens through `ModelRouter`, the request equals the golden request); "wiring: the pipeline's request holds the cloud rules' shortlist titles under Q12 = yes, none under Q12 = no, none on device" | PASS (Linux) |
| AC-M2-20 provider table, headers | "the provider table: bare hosts, method, path, query, header names in order, and the curated pinned model per provider"; "the curated list is closed …"; "AC-M2-20 headers: every header value except the auth header is fixed" | PASS (Linux) |
| AC-M2-20 key placement | "AC-M2-20 key placement: the key appears only in the provider's auth header … Gemini never uses key="; "requests with different keys differ only in the auth header value"; "P-3: a request, its headers and its body never show the key or the body in description, debugDescription or dump" | PASS (Linux) |
| AC-M2-20 canonical body, opt-outs, sampling | "AC-M2-20: the body is canonical JSON …" (9 goldens); "AC-M2-20 opt-outs and sampling …"; "ADR-0005 Decision 3: the instructions are fixed …"; "AC-M2-20: the user content is one text in the user slot whose three slots are exactly the selector's values"; "the user content is canonical JSON …"; "a capture, room name or title cannot change the user content's structure …" (7 texts) | PASS (Linux) |
| N-3 numbers | "N-3: no decimal string 600…729 occurs in any fixed part …" | PASS (Linux) |
| Schema (WI-M2-12 J1; PO WI-M2-12 ruling 2) | "the schema's root is {items: [item]} … all required"; "the enum values equal the Swift cases …; rule-(a) fields are never nullable; the others are"; "… meets completion rule (a) with no null in a rule-(a) field"; "… a blank room (\"\", spaces) maps to room none; a blank sourcePhrase maps to nil" (3 blanks); "… the instructions ask for \"\" … and never ask the model to invent one" | PASS (Linux) |
| AC-M2-20 golden bytes (Linux half) | "AC-M2-20 golden bytes: 3 households × 3 providers, the captured request equals the committed head and body files exactly"; "the G1 golden body is the tend-payload-dump --outcome-sample body"; "AC-M2-20 (a), golden households: no task or room ID, no non-shortlisted title, no date … appears" | PASS (Linux). Mac repeat: MS-2 (B2) |
| Allowed key-path lists (N-3; PO WI-M2-15 ruling 2) | "key paths: the leaf paths …" (4 cases) and "… not strict JSON gives nil" (4); "key paths of every golden body equal the independent oracle"; "N-3: each committed allowed key-path list equals the list derived from the golden requests …, byte for byte"; "N-3: the allowed paths equal the key paths of all three golden bodies; exactly one path has role userContent …"; "PO WI-M2-15 ruling 2: every path in each allowed list, and in the user-content layout, passes the results-v1 keyPaths pattern" (53 / 53 / 64 paths; 6 bad paths refused); "the user-content layout … names the four slot roles" | PASS (Linux) |
| `tend-payload-dump` (plan "Real provider recordings") | TendTools: "tend-payload-dump (WI-M2-10): each provider's body equals the committed G1 golden body …" (3 cases); "tend-payload-dump: usage errors exit 64 and print no body" | PASS (Linux, local; CI runs no TendTools tests until HM-1b) |
| AC-M2-09 Rule 4 narrowing (R1-F6) | TendSourceScan: planted "bare host outside the provider table" ×2; "AC-M2-09 Rule 4: bare hosts pass only in the provider table (R1-F6) …"; "Hand-written host plants … bare only in the provider table (R1-F6)" | PASS (Linux) |
| AC-M2-09, AC-M2-12 (regression) | "AC-M2-09: Rules 1–6 hold …": `46 files in total, 0 violations`; the AC-M1-02 vocabulary scan over the module roots: 0 violations | PASS (Linux) |

### Test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths, 0 warnings in every package)
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 437 tests in 51 suites passed after 109.437 seconds.` (401 on `main` + 36 new) |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 3.449 seconds.` (same count; Rule 4 cases added inside existing tests and plant tables) |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 147.313 seconds.` (unchanged package) |
| Tools/TendTools | `✔ Test run with 8 tests in 1 suite passed after 0.193 seconds.` (7 − 1 stub test + 2) |

Golden fixture SHA-256 (`sha256sum`, Linux): the three `.head.txt` files per provider are identical across households
(OpenAI `82582c2d…`, Anthropic `1c7eda46…`, Gemini `16de52de…`). Bodies: g1 OpenAI `8859c0df…`, Anthropic `266f52e9…`,
Gemini `ae7c6980…`; g2 `97fe378c…`, `137884f5…`, `f80aa910…`; g3 `e9cd972c…`, `3b54b5b9…`, `eb2022ee…`. Allowed lists:
OpenAI `c6ac48eb…`, Anthropic `0b3a88b2…`, Gemini `4cdaf9c6…`.

### Mutation check
Each mutant was applied alone by a script to a scratch copy of the worktree (`/tmp/claude-b10/mut`, never this
branch), built with `-warnings-as-errors` in `swift:6.2-noble` and run with `--filter "Payload|WI-M2-10"`
(TendSourceScan: `"Rule 4|host"`; TendTools: `payloadDump`), then restored. Afterwards the copy's `Packages` and
`Tools/TendTools/Sources` were identical to the branch. **28 of 28 killed; every mutant built.**

| # | Mutant | Killed by (count) |
|---|---|---|
| S1 | selector ignores Q12 = no | Q12 = no; pipeline wiring (2) |
| S2 | room names sorted | golden bytes, router wiring, selector property, G3 selector (6) |
| S3 | shortlist cut at 9 | golden bytes, router wiring, selector property, G3 selector (4) |
| W1 | pipeline request drops the titles | router wiring, pipeline wiring (2) |
| W2 | rules give no titles | router wiring, pipeline wiring (2) |
| T1 | Anthropic key value prefixed `Bearer ` | golden bytes, key placement (2) |
| T2 | Gemini key also in the query (`key=`) | golden bytes, key placement, formatting, provider table (4) |
| T3 | header order swapped | golden bytes, both list tests, provider table (4) |
| T4 | Gemini moving alias `gemini-flash-latest` | golden bytes, list bytes, provider table (3) |
| T5 | output cap 6500 (holds "650") | golden bytes, opt-outs, N-3 numbers (3) |
| B1 | OpenAI `store: true` | golden bytes, opt-outs (2) |
| B2 | OpenAI `temperature: 1` | golden bytes, opt-outs (2) |
| B3 | Gemini thinking budget dropped | golden bytes, opt-outs, both list tests (4) |
| B4 | user-content index from 0 | golden bytes, slots, hostile texts, shape (4) |
| B5 | Anthropic `stream: false` | golden bytes, opt-outs (2) |
| C1 | `room` nullable (a rule-(a) field) | golden bytes, both list tests, schema values (4) |
| C2 | anchor offers `unrecognized` | golden bytes, schema values (2) |
| C3 | Gemini `propertyOrdering` in declaration order | golden bytes, schema keys (2) |
| C4 | no `additionalProperties: false` | golden bytes, both list tests, schema keys (4) |
| C5 | Gemini `nullable` dropped | golden bytes, both list tests, schema values (4) |
| C6 | `daypart` not nullable | golden bytes, both list tests, schema values (4) |
| F1 | auth value shown in `description` | formatting (1) |
| F2 | request `description` shows the body | formatting (1) |
| K1 | empty arrays are not leaves | key-path function table (1) |
| K2 | allowed list keeps indices on the `userContent` path | list bytes (1) |
| K3 | transport-set headers not listed | list bytes (1) |
| R4 | Rule 4 narrowing reverted (bare host anywhere in TendIngestion) | host plants (1) |
| D1 | `tend-payload-dump` adds a trailing newline | tool body = G1 golden (1) |

Single-test kills (F1, F2, K1–K3, R4, D1) each have a dedicated test for exactly that property, as designed.

### Verification environment
| Check | Linux (container, `swift:6.2-noble`) | macOS / owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| Selector, builder, schema, key paths, goldens, lists, wiring | ✔ | not run (MS-2 B2 repeats the golden bytes) | n.a. | n.a. |
| Scanner narrowing | ✔ | not run | n.a. | n.a. |
| `tend-payload-dump` | ✔ (local) | not run | n.a. | n.a. |
| Real provider accepts each request (shape, model IDs, `propertyOrdering`, `format: enum`, caps) | **not verified** (no network, no web lookups, by instruction) | WI-M2-M6 recordings | — | DS-2 |

### Things the reviewer should look at closely
- The schema dialects against the providers' current docs (R-6): OpenAI strict-mode `anyOf` with `null`, Anthropic
  `input_schema` with `anyOf`, Gemini `nullable` / `format: "enum"` / `propertyOrdering`.
- D1/D2: the user content as one JSON text and the two extra roles.
- D5: the canonical member order puts `title` last for every provider.
- `CloudRequest` formatting (D7) and that `withValue` is the only way to read the key.
- The wiring change in four existing files (D6) does not alter stream, marker or router behaviour (all 401 earlier
  TendIngestion tests are unchanged and green).

### Known limitations / tickets
| Item | Severity | Ticket |
|---|---|---|
| Transport-set headers: on Darwin, `URLSession` adds `User-Agent` (app and OS build) and `Accept-Language` (the user's languages) unless set. ADR-0005 Decision 3 forbids location, device identifiers and similar; the languages and OS build are borderline. | concern (P-3) | WI-M2-M4: set `User-Agent` to a fixed value and send no `Accept-Language` (or a fixed one), prove it in the `URLProtocol` test, and add them to the lists' `headers` as fixed. PO/Reviewer to confirm. |
| Model IDs and API shapes not re-checked against current provider docs (no web) | watch (R-6) | WI-M2-M6 re-checks the five Q18 conditions; Reviewer checks against current docs |
| WI-M2-13 fixtures should use this schema's shape: `room: ""`, `sourcePhrase: ""`, `anchor: "none"`, members in canonical order (title last) | — | WI-M2-13 (PO WI-M2-12 ticket: a no-room item completes by (a) before the next item) |
| The ≥ 500-household sentinel and structural proof | — | WI-M2-11 (uses `CloudRequestKeyPaths`, the lists and the user-content layout) |
| The harness records `CloudRequestKeyPaths.leafPaths(ofBody:)` per request | — | WI-M2-M7 |
| TendTools tests are not in CI | Minor | HM-1b (owner) |

### Open questions (built to the most literal reading; work continues)
1. **PO (R-6, Q18 conditions 1 and 2):** I could not re-check the curated models in this container (no web, by
   instruction). (a) Are `gpt-4.1-mini-2025-04-14` and `claude-haiku-4-5-20251001` still current and not announced for
   removal in November 2026? (b) Gemini 2.5 Flash has, to my knowledge, no **dated** snapshot; its stable version ID
   `gemini-2.5-flash` is fixed (not a `-latest` alias). Does a stable version ID meet condition 2, or should the PO name
   a replacement? Is 2.5 Flash still current? I did not pick a different model (plan: "never picks a different model
   alone").
2. **Tester / Planner (R-2 watch, D5):** the canonical order makes every provider write `title` last. If the dev-set
   eval shows lower accuracy or TTFI misses (AC-M2-27), the fix is technical (rename schema keys so the sorted order
   is better), under the freeze rules.
3. **Reviewer / PO (D8):** confirm that fixed protocol members (output caps, tool name, schema name, Gemini schema
   keywords) are not "new request fields" in the ADR-0005 sense.
4. **Tester (WI-M2-16, D2):** confirm the roles and the user-content layout are reviewable as written.
5. **PO (P-3, ticket above):** transport-set `User-Agent` and `Accept-Language` on Darwin.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; the builder only shapes a request. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | The instructions hold no banned token (tested, and the AC-M2-12 vocabulary scan: 0 violations); they ask for the person's words and never to invent anything. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing is unchanged; on-device requests carry no titles (tested). |
| P-2 Data leaves only via iCloud or a P-3 request | pass | Pure functions, no networking (Rule 1: 0 violations); bare hosts only in the provider table (Rule 4 narrowed). No dependency. |
| P-3 Cloud AI opt-in, minimised | pass (one concern ticketed) | The input type holds only capture, room names and ≤ 10 titles (Mirror test); no ID, date, state or other title reaches a golden request (tested); the key only in the auth header, never `key=`; `store: false`; requests never format the key or the body. Concern: Darwin's default `User-Agent` / `Accept-Language` (WI-M2-M4 ticket). |
| P-4 Media not persisted | pass | Text only, in memory; the input type cannot hold media. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Developer | accepted (H2) | WI-M2-10 Ready (WI-M2-07 merged; `main` at `6fd1bf4`). PO defaults for Q12/Q16/Q17 stand. Tickets: PO WI-M2-12 ruling 2, PO WI-M2-15 ruling 2, R1-F6, the `tend-payload-dump` stub. |
| 2026-11-23 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red builds confirmed). TendIngestion 437, TendSourceScan 63, TendCore 141, TendTools 8 green, 0 warnings, Linux. AC-M2-09 46 files, 0 violations; AC-M2-12 vocabulary 0. 28/28 mutants killed. Built on the PO defaults for Q12/Q16/Q17. Five open questions (R-6 model currency and Gemini snapshot; title-last watch; fixed protocol members; roles review; Darwin default headers). Pushed; no PR opened. |

### Round 2 (review round 1: APPROVE with 7 Minor and 3 Nit, `review-WI-M2-10.md`; PO `po-m2-wi10.md` rulings 1–7, ruling 7 final; L1/L1b notes `l1-model-check-2026-11-23.md`)
`origin/main` had not moved (still `6fd1bf4` when fetched on 2026-11-24), so there was no merge. The review file is
committed with this round, unchanged.

**AC coverage:** unchanged from round 1 (this PR is the ○ part of AC-M2-20; WI-M2-11 owns the full proof). Round 2
adds: the builder-level ≤ 10 cap (AC-M2-20 "n ≤ 10", F3), the ruling-7 members in the golden bytes (AC-M2-20 "Golden
bytes", "Opt-outs"), the exact-path Rule 4 plants (AC-M2-09), and the brief's new AC-M2-22 **Headers** bullet, which is
WI-M2-M4's to prove (F4 ticket).

| Finding / ruling | Change |
|---|---|
| **PO ruling 7 (models and fixed members)** | Provider table: `gpt-6-luna`, `claude-haiku-4-5-20251001` (unchanged), `gemini-3.5-flash-lite`. OpenAI: no `temperature`; new fixed members `reasoning_effort: "none"` and `stream_options: {"include_usage": true}`; `store: false` and `max_completion_tokens: 4096` kept. Gemini: no `temperature`, no `thinkingBudget`; `thinkingConfig: {"thinkingLevel": "minimal"}`; the schema moves from `responseSchema` (OpenAPI subset) to `responseJsonSchema` (JSON Schema: lower-case types, `type` arrays with `"null"`, plain `enum`, no `nullable`, no `format`, no `propertyOrdering`); `maxOutputTokens: 4096` kept. Anthropic: unchanged, byte for byte. |
| **R28-F7 Minor** | The model is now the unit of configuration. `CloudRequestProfile` (in `CloudProviderTable.swift`) holds sampling, reasoning member and value, usage member, schema dialect and schema member; `CloudProviderTable.profile(for:)` gives one per `CloudModel`. The builder reads the profile; it branches on the provider only for the provider's protocol shape. Case names are neutral (`openAIDefault`, `anthropicDefault`, `geminiDefault`), and the header comment no longer states model facts. `curated(for:)` is "default first, then any listed fallback". Tests read their expectations from a hand-written per-model table (`PayloadExpectedModel.all`, from ruling 7's text, never from production): `providerTable`, `fixedHeaderValues`, `requestMembers` (present and absent members, for all 3 golden households), `curatedModels`, `noMovingAlias`, `schemaKeywords`. `profileDrivesBody` builds bodies from hypothetical profiles (never shipped) to show a same-provider swap needs no builder change. |
| **R28-F1 Minor** | Rule 4 plants: a bare host in `Packages/TendIngestion/Sources/TendIngestion/Duplicates/CloudProviderTable.swift` gives "bare host outside the provider table"; in `Packages/TendAI/Sources/TendAI/Cloud/CloudProviderTable.swift` it gives "bare host outside TendIngestion"; in `…/Payload/OldCloudProviderTable.swift` it is caught too. Mutant M-A (`hasSuffix("CloudProviderTable.swift")`) is now killed. |
| **R28-F3 Minor** | The builder enforces the Q12 cap itself. `CloudPayloadBuilder.userContent`, `body` and `request` throw `CloudPayloadError.tooManyShortlistTitles(count:)` for more than `CloudPayloadInput.maximumShortlistTitles` (= `DuplicateShortlist.limit`, 10) titles, so no bytes are made. Test `builderTitleCap` (all 3 providers): 11 titles are refused by all three entry points; 10 are sent with indices 1…10. |
| R28-F2 Minor | **Ticket WI-M2-11:** the selector is not on the production path (the pipeline takes the titles from the duplicate rules). WI-M2-11 either makes one derivation path, or adds an equivalence property between `CloudContextSelector.input` and `CloudPayloadInput(pipeline.request)`, and proves AC-M2-20 through the production path. It also adds the D11 blank-room test the review suggests. |
| R28-F4 Minor | **Ticket WI-M2-M4 (PO ruling 4):** the transport sets `User-Agent: Tend` and `Accept-Language: en-US` explicitly on every request; `URLProtocol` test; a mutant that drops either is killed; both go into the allowed lists' `headers` as `fixed`, and `Accept`, `Accept-Encoding` and `Connection` are added as transport-set (`CloudAllowedKeyPaths.transportSetHeaders`). Not done here: the builder's headers are the provider's headers only, as the coordinator directed. |
| R28-F5 Minor | **Ticket WI-M2-M5 / WI-M2-M4:** a key with leading or trailing whitespace or a control character. The PO decides between trim and refuse; the key store or transport then enforces it with a test. |
| R28-F6 Minor | **Ticket WI-M2-11:** `[]` paths do not count array elements, so a path set alone cannot see an extra element. WI-M2-11 adds a structural check on concrete indices. **Tester / PO question:** should `ds2-gated` also compare element counts? |
| R28-N1 Nit | Done: `rule1Positive` also runs the same code, without the bare host, at a general TendIngestion path. |
| R28-N2 Nit | Recorded for the Tester: watch room accuracy in the DS-2 dev-set run (AC-M2-26); a rewording goes under the freeze rules. |
| R28-N3 Nit | Planner: confirm the "Named files" row in the next plan edit. |
| PO rulings 3, 4, 7: brief | Applied word for word to `brief.md`: Q18 row (the ruling 7 sentence, which replaces ruling 1's never-applied sentence), the `interrupted` bullet (cap stop counts as truncated), the Cloud request sub-bullet (fixed header values and fixed protocol members), and the AC-M2-22 **Headers** bullet. No AC is deleted or weakened; AC-M2-22 gains a stricter clause. |
| PO ruling 7: plan | Applied word for word to `plan.md`: amendment 1 (Q18 model list and fallbacks), 2 (conditions 2, 4 and 5 replaced; the old condition 2 sentence "The exact ID is written in the provider table and in the golden requests" goes with it, and AC-M2-20 still requires the golden requests), 3 (live check L2a paragraph after the condition list) and 4 (R-5 mitigation). |

#### The requests as built after round 2 (each member is tested against the hand-written table)
- **OpenAI** `POST api.openai.com /v1/chat/completions`; headers `Authorization: Bearer <key>`, `Content-Type`. Body:
  `max_completion_tokens: 4096`, `messages`, `model: "gpt-6-luna"`, `reasoning_effort: "none"`, `response_format`
  (`json_schema`: `name: "tend_capture"`, `schema` with `anyOf` nulls, `strict: true`), `store: false`, `stream: true`,
  `stream_options: {"include_usage": true}`. No `temperature`.
- **Anthropic**: unchanged from round 1 (`temperature: 0`, no `thinking`, forced `record_items` tool). The three
  Anthropic golden requests and the Anthropic list are byte-identical to round 1.
- **Gemini** `POST generativelanguage.googleapis.com /v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse`;
  headers `x-goog-api-key`, `Content-Type`. Body: `contents`, `generationConfig` = {`maxOutputTokens: 4096`,
  `responseJsonSchema`, `responseMimeType: "application/json"`, `thinkingConfig: {"thinkingLevel": "minimal"}`},
  `systemInstruction`. No `temperature`, no `thinkingBudget`.

#### Decisions (round 2; technical)
- **D12 Profile shape.** The reasoning and usage members are provider-specific enum cases
  (`openAIReasoningEffort`, `geminiThinkingLevel`, `geminiThinkingBudget`, `openAIStreamOptionsIncludeUsage`), so a
  profile cannot name a member the provider does not have without `fits(_:)` saying so. `curatedModels` checks that
  every curated profile fits its provider. The builder ignores a member that has no place in the provider's body.
- **D13 No fallback is listed yet.** `curated(for:)` allows fallbacks after the default, but none is listed. Ruling 7
  says a switch needs a PO ruling, and `claude-haiku-5-5`'s lowest documented `effort` value and request member are
  not in the notes I have. A fallback is added with its own case, profile and table row when the PO rules.
- **D14 Gemini type-array dialect.** `additionalProperties: false` is kept on every object, as ruling 7 directs (L2a
  checks it; if Gemini rejects it, it is dropped for Gemini only and recorded). A nullable enum lists `null` in its
  `enum` as well as in `type` (`{"enum": [..., null], "type": ["string", "null"]}`). In JSON Schema `enum` constrains
  every value, so without `null` there a `null` would fail the enum. L2a confirms Gemini accepts it. If Gemini rejects
  it, the Developer removes `null` from the enum: it is a non-retention protocol member, which ruling 7 allows.
- **D15 Gemini schema member `responseJsonSchema` — to be confirmed by L2a.** The name comes from the L1b notes
  (structured-output page, Go example `ResponseJsonSchema`). It was **not** quoted from the Gemini REST reference:
  this container has no web access, and I was told not to browse. Ruling 7's ticket asks the Developer to quote the
  REST reference. That quote is open (open question 1 below). If the reference names another member, only
  `schemaMember` in the Gemini profile changes, and the Gemini goldens and list are regenerated.
- **D16 Cap enforcement by typed error, not truncation.** Silent truncation would hide an adapter bug and could
  separate the indices the model sees from the shortlist the duplicate rules check. The input initialiser stays
  non-failable, so the selector and pipeline code is unchanged. `CloudPayloadError` replaces `CanonicalJSONError` in
  the three public builder signatures (`json(_:)` wraps the writer's error, which cannot occur with fixed, distinct
  member names). Callers: `tend-payload-dump` (unchanged, generic `catch`) and the tests.
- **D17 PO ruling 3's six-part test for the new fixed members.**

| Member | (1) constant | (2) no household, person or device data | (3) protocol member or schema keyword | (4) no added reach | (5) `fixed` in the lists | (6) N-3 |
|---|---|---|---|---|---|---|
| `reasoning_effort: "none"` | yes | yes | OpenAI protocol | lowers reasoning; nothing more is sent or stored | yes (`$.reasoning_effort`) | no digits |
| `stream_options.include_usage: true` | yes | yes | OpenAI protocol | the provider only adds its token counts to the stream | yes | no digits |
| `thinkingConfig.thinkingLevel: "minimal"` | yes | yes | Gemini protocol | lowers thinking | yes | no digits |
| `responseJsonSchema` and its keywords (`type` arrays, `null` in `enum`, `additionalProperties: false`) | yes | yes | schema member and keywords | none | yes (Gemini list: 41 paths, 40 `fixed`, 1 `userContent`) | no number in the schema |

`noIntervalSentinelDigits` (all providers) passes on the regenerated bodies, the model IDs and the paths.

#### Independent checks of the regenerated files
- Regenerated with `TEND_PAYLOAD_GOLDEN_OUT=/tmp/b10/gold` (outside the repository), then copied in. Exactly the
  expected files changed: the 3 OpenAI bodies (heads unchanged), the 3 Gemini heads (model in the path) and bodies,
  and the OpenAI and Gemini lists. The 6 Anthropic files and the Anthropic list are byte-identical.
- Oracle 1 (Python, separate from the Swift code): it took the **round-1** committed goldens from `f1f6baf`, applied
  ruling 7's changes by hand (OpenAI: drop `temperature`, add the two members, new model; Gemini: drop
  `temperature`/`thinkingBudget`, add `thinkingLevel`, rename the member, rewrite the schema: lower-case types, drop
  `format`/`nullable`/`propertyOrdering`, `type` arrays with `"null"`, `null` in nullable enums, `additionalProperties`
  on objects; head: new model in the path), and wrote canonical JSON. All 12 files match byte for byte. It also found
  no `nullable`, `format`, `propertyOrdering`, upper-case type, `temperature`, `thinkingBudget`, `responseSchema` or
  fake key in any of the six bodies, and no 600…729 in the G1 bodies.
- Oracle 2 (Python): derived each list from the regenerated G2 body (leaf paths, roles, `at`) on top of the round-1
  list's other members. All 3 lists match byte for byte, and all three golden bodies of each provider have the same
  path set. OpenAI: added `$.reasoning_effort`, `$.stream_options.include_usage`; removed `$.temperature`.

#### Round 2 test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths `/tmp/b10/{ing,scan,core,tools}`, 0 warnings in every package)
Final run on the committed tree, after the brief and plan amendments (`BriefPinTests` reads the brief):

| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 441 tests in 51 suites passed after 48.946 seconds.` (437 in round 1: `optOutsAndSampling` became `requestMembers`; new `noMovingAlias`, `profileDrivesBody`, `builderTitleCap`, `schemaKeywords`.) AC-M2-09: `46 files in total, 0 violations`. AC-M2-12 vocabulary scan: `46 files, 9 exempted (the list), 0 violations`. |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 1.681 seconds.` (the F1 and N1 plants are inside existing tests) |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 86.871 seconds.` |
| Tools/TendTools | `✔ Test run with 8 tests in 1 suite passed after 0.074 seconds.` (`payloadDump` Gemini target now `…/gemini-3.5-flash-lite:streamGenerateContent?alt=sse`) |

Order of work, stated plainly: in this round I changed the production code and the table-driven tests in the same
step, before the first run, so there was no red run of the new tests against the old code. The first run failed only
in the golden-bytes and allowed-list tests for OpenAI and Gemini (17 issues; Anthropic passed), because the committed
files were stale, as expected. I then regenerated the goldens, checked them with the two oracles above, and copied
them in. The evidence that the new tests detect real defects is the mutant table below (F1 M-A, F3, F7 and ruling 7).

#### Mutation check (round 2)
Scratch copy `/tmp/claude-b10/mut` (made from the worktree with `tar --exclude=.git`), one mutant at a time,
`-Xswiftc -warnings-as-errors`, own scratch paths. Afterwards the copy's `Packages` and `Tools` were identical to the
worktree (`diff -rq`), and the worktree was never edited. TendIngestion mutants ran with `--filter Payload` (the
`PayloadBuilderTests` and `PayloadGoldenTests` suites). **48 of 48 killed.**

Two run notes, stated honestly:
- On the first pass, the TendSourceScan mutants ran with `--filter 'Rule 4|host|Rule 1'`. `swift test --filter`
  matches test identifiers (`rule4AllowedPlacements`), not display names, so the F1 test was not selected and M-A
  showed "survived". Rerun with no filter (all 63 tests): M-A killed by `rule4AllowedPlacements`, R4 killed by 3
  tests.
- F7-2 and F3-1 were first written so that they did not compile under `-warnings-as-errors` (an unused binding, and
  a guard the compiler proves never fails). I rewrote them so they compile (F7-2: `case .geminiThinkingLevel:` with
  `"minimal"` hard-coded; F3-1: the guard line replaced by `_ = count`). Both are then killed.

| # | Mutant | Result (tests that failed) |
|---|---|---|
| S1–S3, W1, W2, T1–T5, B1, B4, B5, C1, C2, C4, C6, F1, F2, K1–K3, D1 | round-1 mutants, re-pointed at the round-2 code (T4: `geminiDefault = "gemini-flash-latest"`; C1: room as `anyOfNull`; C4: no `additionalProperties`) | all killed (2–6 tests each) |
| B2, B3, C3, C5 (round 1) | replaced: the members they mutated no longer exist (OpenAI temperature, Gemini `thinkingBudget`, `propertyOrdering`, `nullable`); covered by R7-1, R7-4, R7-5, R7-6 | — |
| R7-1 | `temperature` put back for OpenAI (profile `.temperatureZero`) | killed (4: golden bytes, `requestMembers`, lists) |
| R7-2 | `temperature` put back for Gemini | killed (4) |
| R7-3 | `reasoning_effort` dropped | killed (4) |
| R7-4 | `thinkingLevel` dropped | killed (4) |
| R7-5 | `propertyOrdering` put back for Gemini | killed (4, including `schemaKeywords`) |
| R7-6 | `nullable: true` put back for Gemini | killed (4) |
| R7-7 | `format: "enum"` put back for Gemini | killed (4) |
| R7-8 | Gemini schema member back to `responseSchema` | killed (7) |
| R7-9 | Gemini schema back to `anyOf` | killed (4) |
| R7-10 | `null` dropped from a nullable enum | killed (2: golden bytes, `schemaValues`) |
| R7-11 | OpenAI `stream_options` dropped | killed (4) |
| R7-12 | OpenAI model back to `gpt-4.1-mini-2025-04-14` | killed (4) |
| R7-13 | Anthropic `temperature` dropped | killed (4) |
| R7-14 | Gemini nullable integer without `"null"` | killed (2) |
| F7-1 | builder takes the schema member from the model, not the given profile | killed (`profileDrivesBody`) |
| F7-2 | builder hard-codes Gemini `thinkingLevel: "minimal"` | killed (`profileDrivesBody`) |
| F7-3 | builder ignores the given sampling | killed (`profileDrivesBody`) |
| F7-4 | `fits` accepts `reasoning_effort` for any provider | killed (`profileDrivesBody`) |
| F7-5 | `fits` accepts `stream_options` for any provider | killed (`profileDrivesBody`) |
| F7-6 | `curated(for:)` leaves out the default | killed (`curatedModels`) |
| F3-1 | builder cap removed | killed (`builderTitleCap`) |
| F3-2 | builder cap `<` instead of `<=` (10 refused) | killed (9) |
| F3-3 | cap constant 11 | killed (`builderTitleCap`) |
| R4 | Rule 4: bare host anywhere in TendIngestion | killed (3) |
| M-A | Rule 4: file-name match (`hasSuffix("CloudProviderTable.swift")`) | killed (`rule4AllowedPlacements`, R28-F1) |

#### Verification environment (round 2)
| Check | Linux (container, `swift:6.2-noble`) | macOS / owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| Profiles, builder, schema dialects, cap, goldens, lists, scanner plants, `tend-payload-dump` | ✔ | not run (MS-2 B2 repeats the golden bytes) | n.a. | n.a. |
| Regenerated goldens and lists (two Python oracles) | ✔ | n.a. | n.a. | n.a. |
| Providers accept the requests (`gpt-6-luna` with `reasoning_effort: "none"` + strict `json_schema` + `stream` + `store: false` + `max_completion_tokens`; Anthropic unchanged; Gemini `responseJsonSchema` name, `additionalProperties`, `null` in `enum`, `thinkingLevel: "minimal"`) | **not verified** (no network, no web lookups, by instruction) | **L2a** (owner, real Outcome-sample recordings, before WI-M2-16) | — | DS-2 |
| Served model ID and reasoning/thinking tokens per provider | not verifiable here | L2a, WI-M2-M6 recordings, DS-2 drift check | — | DS-2 |

#### Tickets added in round 2
| Item | Owner |
|---|---|
| R28-F2: one derivation path (or equivalence property) and the D11 blank-room test; AC-M2-20 through the production path | WI-M2-11 |
| R28-F4: fixed `User-Agent: Tend`, `Accept-Language: en-US`; `Accept`, `Accept-Encoding`, `Connection` as transport-set in the lists; `URLProtocol` test and mutant | WI-M2-M4 |
| R28-F5: key whitespace and control characters (PO: trim or refuse) | WI-M2-M5 / WI-M2-M4, PO |
| R28-F6: concrete-index structural check; `ds2-gated` element-count question | WI-M2-11; Tester / PO |
| Quote the Gemini REST reference for the JSON-Schema member (`responseJsonSchema`), and confirm `additionalProperties` and `null` in `enum` | Orchestrator or owner (web access), L2a |
| WI-M2-13 Gemini stream fixtures use the new dialect; all providers' fixtures carry usage and served-model fields, ignored for drafts (ruling 7) | WI-M2-13 |
| Plan WI-M2-10 "Proposed endpoints" bullets still say `temperature: 0` for OpenAI and Gemini and `responseSchema` for Gemini; ruling 1's L1 sentence and the WI-M2-16 DoR items (L1, L2a) are not applied (only ruling 7's amendments 1–4 were asked for) | Planner |
| N2: room accuracy watch in the DS-2 dev-set run; N3: confirm the "Named files" row | Tester; Planner |

#### Open questions (round 2; work is not blocked)
1. **Orchestrator / owner (D15):** what member name does the current Gemini REST reference give for a JSON-Schema
   response schema in `generationConfig`? I built `responseJsonSchema` from the L1b notes, as directed, and did not
   look it up. L2a confirms it on the wire.
2. **PO (D14), only if L2a shows a 4xx:** with `null` removed from a nullable enum, the schema would allow `null` by
   `type` but not by `enum`. Gemini may still accept that and return `null`. I would record it and keep the
   key-path check as the guard. No product meaning changes.
3. **Tester (from round 1, open question 4):** the roles and user-content layout of the lists are unchanged; still
   yours to confirm in WI-M2-16.

#### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Instructions unchanged; AC-M2-12 vocabulary scan 0 violations. The brief now says a cap stop counts as truncated (`interrupted` or `noModel`), so no chore is silently lost (ruling 3). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | Same three hosts, only in the provider table (Rule 4 now pinned to the exact path, F1). No dependency. AC-M2-09: 0 violations. |
| P-3 Cloud AI opt-in, minimised | pass (watch) | No new request content. The new fixed members pass ruling 3's six-part test (D17). `store: false` kept. The builder now enforces ≤ 10 titles itself (F3). The P-3 header values are ticketed to WI-M2-M4 (F4). Watch: real-provider acceptance is unverified until L2a. |
| P-4 Media not persisted | pass | Text only, in memory; the input type is unchanged. |

#### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Reviewer (via Orchestrator) | Developer | accepted (round 1: APPROVE) | 7 Minor, 3 Nit. PO `po-m2-wi10.md` rulings 1–7 (7 final) and L1/L1b notes. Coordinator: ruling 7 models, F7 profiles, F1, F3, the other Minors as tickets, regenerate, amend brief and plan. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (round 2) | Ruling 7 models and fixed members; F7 per-model request profiles with a hand-written expectation table; F1 exact-path plants (M-A killed); F3 builder cap with a typed error; F2, F4, F5, F6 ticketed; N1 done. OpenAI and Gemini goldens and lists regenerated and checked by two independent oracles; Anthropic byte-identical. Brief (ruling 3, 4, 7) and plan (ruling 7, 1–4) amendments applied word for word. TendIngestion 441, TendSourceScan 63, TendCore 141, TendTools 8 green, 0 warnings, Linux. AC-M2-09 and AC-M2-12: 46 files, 0 violations. Mutants 48 of 48 killed. Gemini `responseJsonSchema` and the other provider-side facts await L2a. |

## WI-M2-14 — cloud deadline and retry: the neutral `CloudTransport` (N-2), per-attempt timeouts from the 10.0 s deadline on an injected clock, the single 429/5xx retry with `Retry-After` delta-seconds, neutral failure reasons to outcomes, no background queue

- **Owner:** Developer  ·  **Branch:** `m2/cloud-deadline-retry`, from `origin/main` at `f1b6458` (WI-M2-06 pipeline,
  WI-M2-09 router, WI-M2-10 payload builder merged)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none
  new. Follows [ADR-0005](../../architecture/adr/0005-cloud-ai-providers.md) Decisions 6 and 7 and
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): new files under `TendIngestion/Sources/TendIngestion/Transport/`,
  Foundation and TendCore only, no I/O, no network, no `Date`, no ambient clock, no logging, no new dependency.
- **Requirements:** FR-A1, P-2, P-3, P-4, UX-3. **○ AC-M2-22** (Linux part: the deadline and retry arithmetic, T-17,
  T-28, Q22) and **○ AC-M2-23** (Linux part: the outcome, plain note and retry decisions over a neutral failure reason,
  T-18). **WI-M2-M4 owns both (●)** on the owner-run Mac: `CloudHTTPTransport` (ephemeral session, HTTPS and routed host
  only, redirect refusal, the AC-M2-22 Headers bullet per PO WI-M2-10 ruling 4) and `CloudFailureMapping` (each
  `URLError` and HTTP status to a `CloudFailureReason`), with `URLProtocol` tests.
- **Binding inputs:** brief AC-M2-22 (incl. "Timeouts" and the Headers bullet, which is WI-M2-M4's), AC-M2-23, Definitions
  ("Draft stream events": `noModel`, `interrupted`, plain note), Q15, Q22, T-17, T-18, T-25, T-28; plan WI-M2-14 row and
  detailed section, N-2, named files (`CloudHTTPTransport.swift`, `CloudFailureMapping.swift`, `RecordingTransport.swift`);
  PO rulings `po-m2-wi06.md` (ruling 1, 4), `po-m2-wi09.md` (ruling 3), `po-m2-wi10.md` (ruling 3 cap stop =
  truncated; ruling 4 fixed headers = WI-M2-M4). `po-q21-q22.md` holds no WI-M2-14 ticket (its Q22 is M1's weather
  question; the M2 Q22 numbers are in the brief). WI-M2-13 (PR #29) owns the provider stream readers and the R26-F2
  response size cap; no `CloudOutput/` file is touched.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`; WI-M2-06 and WI-M2-10 (the dependencies) are merged.

### What changed
- **New, `Packages/TendIngestion/Sources/TendIngestion/Transport/`** (scanned by AC-M2-09 Rule 1 and the AC-M2-12
  vocabulary scan):
  - `CloudTransport.swift`: the protocol `CloudTransport` (`send(_ request: CloudRequest, timeouts:
    CloudAttemptTimeouts) -> AsyncThrowingStream<[UInt8], any Error>`) with its four-point contract;
    `CloudAttemptTimeouts` (`resource`, `request`, plain `Double` seconds); `CloudFailureReason` (9 neutral cases,
    `stopReason`, `allowsRetry`); `CloudTransportFailure` (reason + the raw `Retry-After` field value).
  - `CloudTiming.swift`: `CloudTiming` (the Q22 numbers as `Duration`, `timeouts(timeLeft:)`, `seconds(_:)`),
    `RetryAfterField.delaySeconds(_:)` (delta-seconds only), `CloudRetryRule.pause(after:attempt:bodyStarted:timeLeft:)`.
  - `CloudResponseBody.swift`: `CloudResponseBody<C: Clock>` (`C.Duration == Duration`), an `AsyncSequence` of body
    chunks for one capture: the attempts, timeouts, the one retry and the deadline, on the injected clock.
- **Changed:** `DraftPipeline.swift` header comment only (the retry lives in `CloudResponseBody`). No behaviour of the
  stream, router, builder or scanner changes.
- **Tests (written first; the first build failed with "cannot find 'CloudTiming' in scope" and ~110 similar):**
  `TransportTestSupport.swift` (`ManualClock`, a `Clock` whose `sleep` moves its own time at once, optionally late, or
  blocks until cancelled; `ScriptedTransport`, pull-based, moving the clock as the body is read; `HoldingTransport`;
  `TransportCloudModel`, a test-only stand-in for the WI-M2-M6 adapter over `StructuredOutputReader`) and
  `CloudDeadlineRetryTests.swift` (6 suites, 34 tests).
- Not changed: `TendCore`, `TendSourceScan`, `Tools/TendTools`, every `CloudOutput/` file, every protected path, every
  dependency.

### The rule as built (each line is tested)
| Step | Rule | Where |
|---|---|---|
| Deadline | `start + 10.0 s`, `start` = the clock instant the pipeline received the input (passed in by the adapter) | `CloudResponseBody.deadline` |
| Before each attempt | cancelled task → `CancellationError`, nothing sent; time left ≤ 0 → `timedOut`, nothing sent | `Iterator.step` |
| Timeouts | resource = time left; request = min(time left, 4.0 s); read from the clock just before `send` | `CloudTiming.timeouts(timeLeft:)` |
| Body | chunks passed on in order; a chunk or a normal end seen at or after the deadline → `timedOut` (not read) | `Iterator.step` |
| Retry | only `rateLimited` (429) / `serviceUnavailable` (5xx), only after attempt 1, only before any body byte; p = max(0.5 s, `Retry-After`); only if time left − p ≥ 3.0 s; then sleep p on the clock and check ≥ 3.0 s again with the clock's time; then send the same request once more | `CloudRetryRule.pause`, `Iterator.retry` |
| `Retry-After` | SP/HTAB trimmed at both ends, then 1+ ASCII digits; else 0 (missing, empty, HTTP-date, fraction, sign, `1e2`, non-ASCII digits, inner space, newline); values > 999,999,999 read as 999,999,999 (no retry either way) | `RetryAfterField` |
| Failure → outcome | `CloudFailureReason.stopReason` → the existing pipeline: `noModel(stoppedBeforeFirstDraft)` with input and plain note before a draft, `interrupted` with input after one | `CloudTransport.swift`; WI-M2-06 |
| Afterwards | after a throw or a normal end, `next()` is nil and nothing is sent; releasing the iterator releases the transport stream (its `onTermination` cancels the task) | `Iterator` |

| `CloudFailureReason` | Brief case (AC-M2-23) | `ModelStopReason` | Retry |
|---|---|---|---|
| `offline` | offline | `offline` | no |
| `timedOut` | timeout | `timedOut` | no |
| `hostNotFound` | DNS failure | `hostNotFound` | no |
| `secureConnectionUnavailable` | TLS failure | `secureConnectionUnavailable` | no |
| `keyNotAccepted` | 401 or 403 | `keyNotAccepted` | no |
| `rateLimited` | 429 | `rateLimited` | once, by the rule |
| `serviceUnavailable` | 5xx | `serviceUnavailable` | once, by the rule |
| `requestNotSent` | refused before sending (other host, redirect to another host, non-HTTPS; AC-M2-22) | `otherModelError` | no |
| `unexpectedResponse` | any other status or transport error | `otherModelError` | no |
| (body, not transport) | malformed body; provider refusal | `unreadableOutput`; `refusal` (WI-M2-13 reader) | no |

### Decisions the Reviewer should know (technical; product-meaning readings are flagged)
- **D1, where the retry lives.** In `CloudResponseBody` (neutral, Linux-tested), not in the transport. The transport
  contract forbids it to retry, queue or store. So the `TendEval` `RecordingTransport` (N-2) wraps one attempt and sees
  both attempts of a retried capture, and WI-M2-M4 has no timing logic to get wrong.
- **D2, the clock.** The standard library `Clock` protocol, generic, with `Duration`. The app passes a
  `ContinuousClock` from `TendAI` (that name is on the AC-M1-23 clock list, which Rule 1 applies to `TendIngestion`,
  so it may not appear here). All arithmetic is in `Duration`, exact for every Q22 number and every whole-second
  `Retry-After`; only the timeouts handed to the transport are `Double` seconds.
- **D3, the deadline start is an input.** "From the moment the pipeline receives the input" needs a clock read at
  receipt. `IngestionModel.snapshots(for:)` and `CloudModelSource.model(for:key:)` carry no instant, so the adapter
  passes `start`. Ticket for WI-M2-M6 (open question 1).
- **D4, no wait when the retry cannot happen.** The 3.0 s rule is checked before the pause with the planned pause (no
  needless wait), and again after the pause with the clock's time (the literal "after the pause, ≥ 3.0 s are left": a
  late wake-up that leaves less than 3.0 s ends with the original reason).
- **D5, no retry once body bytes were read.** A 429/5xx arrives with the status line, before any body byte, so in
  practice this only guards against a faulty transport; a retry after bytes would restart a body the reader has
  already read (duplicate drafts).
- **D6, the deadline also holds on the body.** A chunk or normal end seen at or after the deadline is `timedOut`. The
  transport's resource timeout should fire first; this makes the deadline true on the injected clock as well and is
  Linux-testable. *Product reading (literal):* a body whose end arrives at exactly 10.0 s counts as timed out, not
  completed (open question 2).
- **D7, a transport failure after the deadline keeps its own reason** (for example `rateLimited`), with no retry
  (less than 3.0 s left). Only the iterator's own deadline checks produce `timedOut`.
- **D8, errors the transport may throw.** `CloudTransportFailure` → its reason; `CancellationError` → passed on (the
  pipeline reads cancellation); anything else, including a `ModelStopReason`, → `otherModelError` (adapter contract
  rule 1; the transport is not trusted to name a model-level reason such as `guardrail`).
- **D9, `requestNotSent` and `unexpectedResponse` map to the existing `otherModelError`.** No new `ModelStopReason`
  case, so WI-M2-06's outcome table and the calm-names test are unchanged (open question 3).
- **D10, `Retry-After` cap.** Digits are accumulated with a cap at 999,999,999 (no overflow for any length); any capped
  value is far past the deadline, so it gives no retry, as the uncapped value would.

### AC coverage
| AC (part) | Test(s) (`CloudDeadlineRetryTests.swift`) | Environment |
|---|---|---|
| AC-M2-22 numbers (Q22) | "AC-M2-22 / Q22: the deadline is 10.0 s, the idle cap 4.0 s, the shortest pause 0.5 s, the retry floor 3.0 s" | Linux |
| AC-M2-22 resource / request timeouts | "AC-M2-22: resource timeout = time left; request timeout = min(time left, 4.0 s)" (8 cells); "… seconds conversion …"; "… a first attempt that answers … (10, 4) …"; "… the deadline runs from receipt of the input …"; "… with no time left at the start nothing is sent …" | Linux |
| AC-M2-22 `Retry-After` (T-28) | "AC-M2-22 / T-28: Retry-After field values" (36 cells) | Linux |
| AC-M2-22 / 23 retry rule | "… the pause before the one retry, or no retry" (25 cells); "… only 429 … and 5xx … allow the retry"; "429 at 1.0 s …"; "503 at 1.0 s with Retry-After 2 …"; "… a second 429/5xx ends the body …" (4); boundary 6.5 s / 6.501 s; "Retry-After 7 … 8 …" (4); "… checked again after the pause …"; "… after body bytes is not retried …" | Linux |
| AC-M2-22 deadline on the body | "… a chunk that arrives at or after the deadline …" (2); "… a normal end at or after the deadline …" (2) | Linux |
| AC-M2-22 / 23 property | "… 4,000 seeded scripts keep the rule …" (seed `0x7E9D001400220023`, independent integer-millisecond oracle, seed printed in every failure message) | Linux |
| AC-M2-23 failure → reason | "… each transport failure maps to one neutral stop reason …" (9); "… the mapping table covers every reason"; "… every other transport failure ends the body at once …" (7) | Linux |
| AC-M2-23 outcomes and plain note | "AC-M2-23: each transport failure before any draft …" (27 = 3 providers × 9: `noModel`, input, plain note, 2 sends for 429/5xx); "… after a draft …" (27: `interrupted`, input, no plain note, draft kept, 1 send); "429 then a good answer …" (3); "… a malformed body …"; "… an answer cut by the deadline …" | Linux |
| AC-M2-23 no background queue | "… after the body ends nothing more is sent, and a stopped read releases the transport stream"; "… cancelling during the pause …"; "… read inside an already cancelled task, nothing is sent"; "… a CancellationError from the transport …"; "… a foreign error is otherModelError …" | Linux |
| AC-M2-23 calm names (T-18, AC-M2-12) | "… no failure reason or transport type name contains a banned token …"; AC-M2-12 vocabulary scan | Linux; Reviewer inspects the case names |
| AC-M2-23 route `none` plain note; refusal | unchanged WI-M2-06 tests ("AC-M2-23: the same plain-note offer exists when the route is none"; `CloudOutcomeTests` with `.refusal`); refusal from a body is WI-M2-13's reader | Linux |
| AC-M2-22 ephemeral session, HTTPS, host, redirect, Headers; AC-M2-23 `URLError`/status mapping | — | **WI-M2-M4, owner-run Mac** (not in this item) |

### Test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths `/tmp/b14-*`, 0 warnings in every package)
| Package | Result |
|---|---|
| `Packages/TendIngestion` | 475 tests in 57 suites passed (441 before; +34 in 6 new suites). One earlier full run, while two other agents' containers were building, had the existing WI-M2-09 test "AC-M2-18: a capture the user cancels while its request is being prepared … sends nothing" hit its 60 s time limit; that suite alone passed in 0.26 s and the next full run passed (watch item for the WI-M2-09 owner: wall-clock time limit under load) |
| `Packages/TendCore` | 141 tests in 18 suites passed |
| `Packages/TendSourceScan` | 63 tests in 4 suites passed |
| `Tools/TendTools` | 8 tests in 1 suite passed |
| AC-M2-09 scan | `TendIngestion` (required) 49 files scanned, 0 violations (`TendAI`, `TendEval` not present, optional) |
| AC-M2-12 vocabulary scan | 0 violations |

### Mutation check (scratch copy `/tmp/b14mut`, one mutant at a time, `--filter` on the 6 new suites; the worktree was never touched)
23 of 23 killed.

| # | Mutant | Killed by |
|---|---|---|
| M1 | deadline 10 → 11 s | numbers; "429 at 1.0 s …" |
| M2 | no 4.0 s idle cap | timeouts table |
| M3 | shortest pause 0 | numbers; re-check after the pause |
| M4 | retry floor `>=` → `>` | retry-rule table; boundary 6.5 s |
| M5 | 401/403 retried | "every other transport failure …" |
| M6 | three attempts | retry-rule table; numbers |
| M7 | retry after body bytes | "… after body bytes is not retried …" |
| M8 | `Retry-After` ignored | retry-rule table |
| M9 | `Retry-After` not trimmed | `Retry-After` table |
| M10 | `Retry-After` read as a `Double` (fractions, `1e2`, `inf`) | `Retry-After` table |
| M11 | no 3.0 s re-check after the pause | "… checked again after the pause …" |
| M12 | send with no time left | "… with no time left at the start nothing is sent …" |
| M13 | no deadline check on chunks | "… a chunk that arrives at or after the deadline …" |
| M14 | chunk at exactly the deadline read | "… a normal end at or after the deadline …"; chunk test |
| M15 | foreign error passed through | "… a foreign error is otherModelError …" |
| M16 | no cancellation check before send | "… read inside an already cancelled task …" |
| M17 | a normal end restarts an attempt | "… after the body ends nothing more is sent …" (1b) |
| M18 | `requestNotSent` → `offline` | mapping table |
| M19 | timeouts from the full 10 s, not the time left | "503 … Retry-After 2 …"; "429 at 1.0 s …" |
| M20 | pause `min` instead of `max` | boundary tests |
| M21 | no cap on a huge `Retry-After` | `Retry-After` table (arithmetic-overflow trap) |
| M22 | transport `CancellationError` → `otherModelError` | "… a CancellationError from the transport …" |
| M23 | no pause before the retry | "429 then a good answer …" (sleeps) |

### Verification environment
| Check | Linux (container, `swift:6.2-noble`) | macOS / owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| Deadline, timeouts, `Retry-After`, retry rule, failure → outcome, no queue | ✔ | not run (MS-2 repeats the `TendIngestion` suite) | n.a. | n.a. |
| `URLSession` timeouts actually applied, ephemeral config, host/redirect refusal, Headers bullet, `URLError`/status mapping | **not verified here** | WI-M2-M4 (`URLProtocol`, Simulator host) | WI-M2-M4 | DS-2 |
| Real `ContinuousClock` passed by the adapter; deadline start at receipt | **not verified here** | WI-M2-M6 | WI-M2-M6 | DS-2 (AC-M2-27 total ≤ 10 s) |

### Things the reviewer should look at closely
- `CloudResponseBody.Iterator.step`: the state machine (`beforeAttempt` → `reading` → `ended`), that every throw ends it,
  and that the retry path never sends a third time.
- D4 (two checks of the 3.0 s rule) and D6 (deadline on the body, a product reading).
- The test clock and transports: `ScriptedTransport` is pull-based (`AsyncThrowingStream(unfolding:)`), so the clock
  moves exactly when the reader waits; `ManualClock`'s blocking mode resumes only on cancellation. No test waits on the
  wall clock (`yieldUntil` only yields).
- The property oracle is integer milliseconds, written independently of `CloudRetryRule`.
- The `CloudFailureReason` case names (T-18 "none blames the user").

### Known limitations / tickets
| Item | Severity | Ticket |
|---|---|---|
| The adapter must pass the instant the pipeline received the input as `start` (no current API carries it) | — | WI-M2-M6 (open question 1) |
| `CloudHTTPTransport` must set `timeoutIntervalForResource`/`timeoutIntervalForRequest` from `CloudAttemptTimeouts` per attempt (a new session configuration per attempt, or per-request `timeoutInterval` plus the resource timeout; their choice), throw only `CloudTransportFailure`, put the raw `Retry-After` value in it for 429/5xx, and never retry | — | WI-M2-M4 |
| The `TendEval` `RecordingTransport` (N-2) wraps `CloudTransport`; it sees each attempt | — | WI-M2-M7 |
| `ProviderStreamReader` (PR #29) reads the chunks in the real adapter; the test stand-in uses `StructuredOutputReader` | — | WI-M2-M6 |
| The test doubles `PayloadRecordingTransport` and `RecordingTransport` keep their own shapes (comments say WI-M2-14 will define the protocol); not changed, to keep this PR small | Nit | next touch of those files |

### Open questions (built to the most literal reading; work continues)
1. **Planner / WI-M2-M6 (technical, D3):** where the adapter reads the deadline start. The most literal point is
   `ModelRouter.events(input:…)` (the pipeline receives the input there); `snapshots(for:)` is called when iteration
   starts, normally at once. Either keeps the 10.0 s inside the AC-M2-27 total.
2. **Closed (PO 2026-11-24, `po-m2-wi14.md` ruling Q2: confirmed as built, incl. the "at or after" boundary; brief
   amendment 1 applied in round 2).** ~~**PO (product reading, D6):** a body that is still arriving at 10.0 s is ended as `timedOut` (drafts already emitted
   stay, `interrupted`; none, `noModel` with the plain note). Built as the literal deadline. Confirm, or say the
   deadline applies only to starting attempts and to the transport's timeouts.~~
3. **Closed (PO 2026-11-24, `po-m2-wi14.md` ruling Q3: one outcome reason is enough; the transport keeps
   `requestNotSent` apart, binding; brief amendment 2 applied in round 2).** ~~**PO / Reviewer (D9):** "refused before sending" (other host, redirect, non-HTTPS) and "any other status" report
   `otherModelError`. A separate neutral `ModelStopReason` is possible if M3 copy needs to tell them apart.~~

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Every failure ends in a calm typed outcome with the input kept and, before a draft, the plain note (tested per reason and provider). Case names hold no banned token (test + AC-M2-12 scan: 0). No user-facing copy (M3). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged; the retry is on the same cloud route only; an on-device error never reaches this code. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No networking in `TendIngestion` (AC-M2-09 Rule 1: 49 files, 0 violations); the protocol is neutral, the real transport is WI-M2-M4's allowlisted file. No dependency. |
| P-3 Cloud AI opt-in, minimised | pass | At most two sends of the same built request per capture, both inside the 10.0 s deadline; no new request content; cancellation (turn-off, WI-M2-09) stops the pause and the retry (tested). |
| P-4 Media not persisted | pass | No background queue, no store, nothing written; after the body ends nothing more is sent (tested). Bytes are passed on, never kept. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted (H2) | WI-M2-14 Ready (WI-M2-06, 09, 10 merged; `main` at `f1b6458`). Do not touch `CloudOutput/` (WI-M2-13, PR #29). Owner confirmed the Q12/Q16/Q17 defaults (Orchestrator FYI; no effect on this item). |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). TendIngestion 475, TendCore 141, TendSourceScan 63, TendTools 8 green, 0 warnings, Linux. AC-M2-09 49 files 0 violations; AC-M2-12 0. 23/23 mutants killed. Three open questions (deadline start plumbing; deadline on the body; `otherModelError` for refused/other). Pushed; no PR opened. |

### Round 2 (review round 1: APPROVE with 3 Minors and 2 Nits, `review-WI-M2-14.md`; PO rulings `po-m2-wi14.md`)
`origin/main` had not moved (still `f1b6458`), so nothing was merged. The review file is committed with this round.

#### Findings and what was done
| Finding | Severity | Done |
|---|---|---|
| R30-F1 a cancelled read ended as a normal end | Minor | `CloudResponseBody`: after the transport iterator returns nil, `try Task.checkCancellation()` before the deadline check, so a read cancelled mid-body ends with `CancellationError`, never a normal end. File header updated. `nothingAfterward` part 2 now waits for the first chunk (event), cancels, and asserts `count == 1` and the end type `CancellationError`. Mutant R2-M1 (the line removed) is killed by it. |
| R30-F2 the contract did not say how a cancelled attempt ends | Minor | `CloudTransport` contract point 5: a cancelled attempt is not a failure: finish without an error or throw `CancellationError`; never map `URLError.cancelled` (or any cancellation) to a `CloudFailureReason`. Point 3 refers to it. Also a WI-M2-M4 ticket (below). |
| R30-F3 the WI-M2-09 liveness waits polled with `Task.sleep(1 ms)` and starved under load | Minor (flake risk) | See "R30-F3" below. No assertion changed, no time limit raised. |
| R30-F4 the property test's `Double` timeout check reuses the formula | Nit | Kept (optional); the literal table test covers the conversion. |
| R30-F5 a silent attempt relies on the transport's resource timeout | Nit | Ticket for WI-M2-M4 (below). |
| N4 | — | Optional; not done. |

#### R30-F3: waits on events, not on a polling timer
- **Cause (confirmed).** The waits needed one cooperative-pool resumption per millisecond, while the CPU-heavy property
  suites held every pool thread. My first attempt replaced the two 200 ms "must not start" loops with 500
  `Task.yield()`s. That was **worse**: under the full run both tests hit the 60 s limit. Each yield re-queues behind the
  heavy suites' work, so resumptions, not wall-clock time, are what cost. So the fix reduces resumptions.
- **`StateChanges` (test support, `RoutingSupport.swift`).** A shared change signal with a generation counter, so a
  change between "check" and "wait" is never lost. Every double whose state a wait reads calls `changed()` after the
  change: `RecordingTransport` (request recorded, stream ended), `SeenEvents.append`, `SuspendingKeyStore` (a call
  held, a key read returned) and `SuspendingConsentStore` (a call held).
- **`eventually`** checks its condition again at each change, not every millisecond. Its bound for a broken rule is now
  10 s of wall-clock time, with one timer resumption. Before, 5,000 sleeps of at least 1 ms each, unbounded in real time
  under load. A condition that is true at the bound still returns true.
- **The two negative settles** ("a request must not start after the key read is released": `cancelWhilePreparing`,
  and `CloudConsentRaceTests.settle` in `actionDuringKeyRead`) now (1) wait, on an event, until the held key read has
  **returned** (`SuspendingKeyStore.returnedKeyCalls`, new), and then (2) use `staysFalse`. That is the same 200 ms window
  as the old 200 × 1 ms loop, but event-driven: a wrong request wakes it at once, and otherwise it costs one timer
  resumption. So the check is stricter than before: step (1) proves the released step ran.
- **Cooperative yields in the heavy loops that had none:** one `await Task.yield()` per outer iteration in the WI-M2-06/07
  integration property (`DraftStreamDuplicateTests`), the WI-M2-08 commit property, the WI-M2-10 selector property and
  this item's property test. This follows the AC-M2-24 suites, which already do it. Inputs, seeds, iteration counts and
  assertions are unchanged.
- **Evidence (full TendIngestion run, 475 tests, all suites in parallel, 4 cores):** the two tests print their **body**
  time (the time limit counts from body start): `actionDuringKeyRead` 2.63 s (each of the 3 cases),
  `cancelWhilePreparing` 2.75 s, against the 60 s limit. Alone they take 0.03 s. Before this round, the same test
  reported "passed after 94.5 s" in the reviewer's run and hit the 60 s limit once in mine. The reported "passed after"
  (about 52 s) still includes queueing before the body starts. Two more full runs were green.
- **Mutants for the reworked waits (scratch copy, `--filter CloudConsent|CloudResponseBodyTests`):** R2-M2
  (`beginRequest` ignores a capture ended during the key read) is killed by "R24-F1: beginRequest reads the capture
  again …". R2-M3 (the forwarding task ignores its own cancellation) survives, and it survives **the same way with the
  original `main` waits** (checked on a copy with `f1b6458`'s three test files). So it is not a regression. It is likely
  equivalent: after a cancel, the router has already released or ended the capture, so `beginRequest` returns nil.
  Recorded for the WI-M2-09 owner.

#### PO rulings applied (`po-m2-wi14.md`)
- Open questions 2 and 3 are closed above (Q2: deadline on the body confirmed as built; Q3: one outcome reason, the
  transport keeps `requestNotSent` apart, binding).
- **Brief amendment 1** (AC-M2-22 "Timeouts") and **brief amendment 2** (AC-M2-23, after the banned-token bullet) are applied
  to `brief.md` word for word (only the line wrapping is new).
- Open question 1 (D3) moves to the Planner (WI-M2-M6), per the PO note.

#### Tickets (for the Planner to put in the DoD lines; none is built here)
| For | Ticket | Source |
|---|---|---|
| WI-M2-M4 | `CloudHTTPTransport` follows contract point 5: a cancelled task finishes without an error or throws `CancellationError`, and `URLError.cancelled` is never mapped to a `CloudFailureReason`. Add a `URLProtocol` test: cancel mid-body, and the `CloudResponseBody` ends with `CancellationError`. | R30-F2 |
| WI-M2-M4 | One `URLProtocol` test where the stub never answers: the attempt ends `timedOut` at the resource timeout (`timeoutIntervalForResource` really applied per attempt, so AC-M2-27's total ≤ 10.0 s holds while an attempt is silent). | R30-F5 |
| WI-M2-M4 | The refusal tests assert `requestNotSent` **and** zero requests reaching the `URLProtocol` stub, for each of the three refusal kinds (other host, redirect to another host, non-HTTPS). | PO Q3 |
| WI-M2-M4 | Set both timeouts per attempt from `CloudAttemptTimeouts`; throw only `CloudTransportFailure`, with the raw `Retry-After` for 429/5xx; never retry (round 1 ticket, unchanged). | round 1 |
| WI-M2-M6 | DoD: "adapter passes the deadline start (D3) read at receipt, with a test". Reviewer fact: `ConsentCheckedCloudModel.snapshots(for:)` (`Routing/ModelRouter.swift`) calls the provider model's `snapshots(for:)` only after `beginRequest`, which comes after the cloud-status and **Keychain** reads. So `start` must be read **before the Keychain read**, no later than when the routed capture is created and handed through `model(for:key:)` or the request. An adapter that reads a fresh clock in its own `snapshots(for:)`, or one per attempt, starts the deadline late. | PO Q1 note; review open question 1 |
| WI-M2-M6 | Read the chunks with `ProviderStreamReader`; on `CancellationError` from `CloudResponseBody`, finish without calling the reader's `finish()` (R30-F1). | round 1; R30-F1 |
| WI-M2-M7 | The `RecordingTransport` (N-2) sees each attempt. It may record the transport-level `CloudFailureReason` **case name** per attempt (permitted, not required; Planner's choice). | PO Q3 |
| WI-M2-09 owner | R2-M3 (forwarding ignores its own cancellation) survives with both the old and the new waits; it is likely equivalent. Confirm, or add a test. | this round |

#### Test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths `/tmp/b14-*`, 0 warnings in every package)
| Package | Result |
|---|---|
| `Packages/TendIngestion` | 475 tests in 57 suites passed (the same count; the changes are inside existing tests) |
| `Packages/TendCore` | 141 tests in 18 suites passed |
| `Packages/TendSourceScan` | 63 tests in 4 suites passed |
| `Tools/TendTools` | 8 tests in 1 suite passed |
| AC-M2-09 scan | 49 files, 0 violations |
| AC-M2-12 vocabulary scan | 0 violations |

#### Verification environment (round 2)
| Check | Linux | Owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| R30-F1 end type, contract text, R30-F3 waits | ✔ | not run (MS-2 repeats the suite) | n.a. | n.a. |
| `URLError.cancelled` handling, silent-attempt resource timeout, refusal with zero requests | **not verified here** | WI-M2-M4 | WI-M2-M4 | — |

#### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | A cancelled read is reported as cancellation, never as a finished body (R30-F1), so no outcome claims something that did not happen. The brief now says the deadline ends calmly with the words kept (amendment 1). Case names unchanged; AC-M2-12: 0. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No networking in `TendIngestion` (AC-M2-09: 0 violations); no dependency. |
| P-3 Cloud AI opt-in, minimised | pass | The negative tests for "nothing sent after a turn-off or cancel" are now stricter (they first prove the released step ran). The refusal guard stays separately provable (`requestNotSent`, amendment 2, WI-M2-M4 ticket). |
| P-4 Media not persisted | pass | Nothing queued or stored; unchanged. |

#### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Reviewer (via Orchestrator) | Developer | accepted (round 1: APPROVE) | 3 Minor, 2 Nit. PO `po-m2-wi14.md`: Q2 and Q3 confirmed, 2 brief amendments, Q1 to the Planner. Coordinator: F1 and F2 fixed here, F3 fixed in the WI-M2-09 tests, F5 and the PO tickets recorded, N4 optional. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1 (code + test), F2 (contract), F3 (event-driven waits; body time about 2.7 s under the full run, against the 60 s limit; a failed yield-only attempt is recorded). Brief amendments 1 and 2 applied word for word. Open questions 2 and 3 closed. TendIngestion 475, TendCore 141, TendSourceScan 63, TendTools 8 green, 0 warnings. AC-M2-09 49 files 0 violations; AC-M2-12 0. Round-2 mutants: R2-M1 and R2-M2 killed; R2-M3 survives on `main` too (likely equivalent, ticketed). |

## WI-M2-13 — the three provider stream dialects (OpenAI, Anthropic, Gemini) on top of WI-M2-12, with synthetic fixtures

- **Owner:** Developer. **Branch:** `m2/provider-dialects`, from `origin/main` at `03e98c6` (PR #26, WI-M2-12, merged).
  `origin/main` at `6fd1bf4` (PR #27, WI-M2-15) was merged in before the push, with no conflict. **PR:** not opened;
  the Orchestrator opens it. **ADRs:** none new. The work follows
  [ADR-0005](../../architecture/adr/0005-cloud-ai-providers.md) and
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md): six new files under
  `TendIngestion/Sources/TendIngestion/CloudOutput/`, Foundation and TendCore only, with no I/O, no network, no
  logging and no new dependency.
- **Requirements:** FR-A1, P-3. This item delivers the **Linux part of AC-M2-24** ([plan.md](plan.md) WI-M2-13, ○):
  the three provider stream parsers and the synthetic fixtures. The cloud adapters end to end over these fixtures
  through a mock transport, and the real recordings, are WI-M2-M6 on the owner-run Mac. It also covers the AC-M2-05
  bullet "This holds … for every cloud provider parser". It closes review ticket **R26-F2** (response size cap).
- **Binding inputs:**
  - the brief's AC-M2-24, AC-M2-05 and Definitions ("Item completion" (a)–(c) with PO amendment 1; "Draft stream
    events"; `noModel` and `interrupted`);
  - T-19 and T-25;
  - PO WI-M2-12 rulings 1 and 2 and their tickets (`po-m2-wi12.md`: "per-provider fixture: no-room item completes by
    (a) before the next item; title-arrives-last per provider");
  - `po-q21-q22.md` "From PR #22" and "PR #26" (title arrives last);
  - WI-M2-12 J7 (when a provider stream counts as cut off is this item's rule) and J8 (the event JSON goes through the
    same parser);
  - the plan's WI-M2-10 endpoints (OpenAI Chat Completions, Anthropic Messages with one forced tool, Gemini
    `streamGenerateContent?alt=sse`).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. This is M2 work. DoR "deps merged" is met:
  WI-M2-12 is on `main`.
- **Network and data:** nothing was fetched. Each provider's format comes from its documented streaming format as I
  know it. Checking against the current provider documentation and real recordings is WI-M2-M6 (see K9). No personal
  data was used or sent anywhere.

### What changed
- New source files in `Packages/TendIngestion/Sources/TendIngestion/CloudOutput/`:
  - `ProviderStreamReader.swift`: the public entry point. `init(provider:responseByteLimit:)`; `append(_:)` takes a
    body chunk and returns `IngestionSnapshot?` (nil when the chunk added no output text); `finish()`;
    `read(_:provider:)` reads a whole body at once; `receivedByteCount`; `defaultResponseByteLimit` (1 MiB).
  - `ProviderStreamError.swift`: the typed error, `declined(ProviderDeclineSignal)`, `languageNotSupported`,
    `cutShort(ProviderCutShortCause)`, `unreadable(ProviderUnreadableCause)`, `providerError(ModelStopReason)` and
    `unexpectedFinish`, with `stopReason`, the neutral reason the adapter throws.
  - `OpenAIStreamDialect.swift`, `AnthropicStreamDialect.swift`, `GeminiStreamDialect.swift`: one internal dialect
    per provider. Each turns one `ServerSentEvent` into a `DialectStep` (the output text, then an optional stop) and
    checks the end. Each file header lists the documented format and the rules as built.
  - `ProviderEventJSON.swift`: reads one event's data with `PartialJSONParser` in one shot (J8), plus strict typed
    accessors (a missing member or `null` counts as absent; any other wrong type is `unexpectedStructure`).
- New fixtures: `Fixtures/M2/provider-streams/synthetic/{openai,anthropic,gemini}/*.sse`, 10 per provider (30 in all),
  plus `Fixtures/M2/provider-streams/README.md` (the fixture list: synthetic or recorded, and what each one covers).
  No existing source file was changed. No existing test file was changed.
- New tests, written first. The first build failed with "cannot find type 'ProviderStreamError' in scope" and about
  240 errors like it.
  - `ProviderStreamSupport.swift`: fixture loading; `ProviderRead`, which records what an adapter would yield;
    `ChunkedProviderModel`, a test-only adapter that follows the `IngestionModel` contract; and `DialectWriter`, an
    independent Swift writer of provider bodies for the property test.
  - `ProviderDialectTests.swift` (33 tests in 5 suites).
  - `ProviderStreamFixtureTests.swift` (11 tests).

### The rules as built (each one is tested)
- **Pipeline.** Body bytes go to `ServerSentEventFramer`, then to the provider's dialect, then to
  `StructuredOutputReader`. So every provider reaches the draft stream through the same `IngestionModel` contract and
  the same only-finished-values reader (J2) as the WI-M2-12 tests.
- **OpenAI** (Chat Completions, `stream: true`):
  - The output is `choices[0].delta.content`. A non-empty `delta.refusal` is a refusal; `null` and `""` are not.
  - `finish_reason`: `stop` is normal, `length` cuts the output, `content_filter` is a safety stop, and any other
    value is an unexpected finish.
  - An in-stream `error` object maps to a reason: `server_error` → `serviceUnavailable`, `rate_limit_exceeded` →
    `rateLimited`, anything else → `otherModelError`.
  - A normal end needs both `stop` and `data: [DONE]`.
  - Strict: choice index 0 only (a missing index counts as 0). Content after the finish reason is unexpected, and so
    is a wrong-typed member.
- **Anthropic** (Messages with one forced tool):
  - The output is the `partial_json` of the `input_json_delta`s for the one `tool_use` block. Other blocks (for
    example text) are ignored. `ping` and unknown event types are ignored. The data's `type` counts, not the SSE event
    name.
  - `stop_reason`: `tool_use`, `end_turn` and `stop_sequence` are normal. `max_tokens` and
    `model_context_window_exceeded` cut the output. `refusal` is a refusal. Anything else is an unexpected finish.
  - An `error` event maps by its type: overloaded or api → `serviceUnavailable`, rate limit → `rateLimited`,
    authentication or permission → `keyNotAccepted`, anything else → `otherModelError`.
  - A normal end needs a normal `stop_reason` and `message_stop`.
  - Strict: content before `message_start`; a second `message_start`; a block index started twice; a delta or stop
    for a block that is not open; a second `tool_use` block; a tool delta that is not `input_json_delta` with a string
    `partial_json`; an event with no `type`.
- **Gemini** (`streamGenerateContent?alt=sse`):
  - The output is the text of each part of `candidates[0].content.parts`, in order. A `thought` part is skipped.
  - `finishReason`: `STOP` is normal, `MAX_TOKENS` cuts the output, `LANGUAGE` → `languageNotSupported`, and
    `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII` and `IMAGE_SAFETY` are safety stops. Anything
    else is an unexpected finish.
  - `promptFeedback.blockReason` means the prompt was blocked.
  - An in-stream `error` object maps by its code: 429 → `rateLimited`, 5xx → `serviceUnavailable`, 401 or 403 →
    `keyNotAccepted`, anything else → `otherModelError`.
  - The normal end is `STOP`.
  - Strict: candidate index 0 only, and wrong-typed members are unexpected.
- **Shared reader rules:**
  - Within a chunk, events are read in order. An event's text is read before its stop.
  - A stop that comes after new output in the same chunk is **deferred** (K3).
  - Invalid output JSON stops at its first bad byte, and the valid text before that byte is still read (K4).
  - Events after the provider's end are ignored, including a part-written last line.
  - At `finish()`, the checks run in this order: inside an event → `bodyEndedInsideEvent`; no provider end →
    `noFinish`; no output → `noOutput`; unfinished JSON → `outputUnfinished`.
  - Errors are sticky. `finish()` is idempotent. A chunk after `finish()` reads nothing.
- **Response size cap (R26-F2):** a body longer than `responseByteLimit` (default 1,048,576 bytes) ends with
  `unreadable(.responseTooLarge)` at the chunk that would pass the limit. That chunk is not read and not counted.
- **Outcomes, through WI-M2-06:**
  - Before any draft, every stop is `noModel` with the plain-note offer. That covers a refusal, a safety stop, a
    blocked prompt, an invalid event or output, the size cap, a cut and a provider error.
  - After a draft, every stop is `interrupted`. The drafts stay, and the in-progress item is discarded.
  - `ProviderStreamError.stopReason` maps:

    | Error | Stop reason |
    |---|---|
    | `declined` | `refusal` |
    | `cutShort` | `outputCutShort` |
    | `unreadable` | `unreadableOutput` |
    | `languageNotSupported` | `unsupportedLanguage` |
    | `providerError(r)` | `r` |
    | `unexpectedFinish` | `otherModelError` |

### Decisions the Reviewer should know
- **K1, one public reader and internal dialects.** `ProviderStreamReader(provider:)` is the only API the cloud
  adapters (WI-M2-M4/M6) need. They pass it each chunk, yield the snapshots, yield `finish()`, or throw
  `error.stopReason`. The three dialects are internal value types behind an enum, so there are no existentials. The
  test adapter `ChunkedProviderModel` is the pattern the Mac adapter follows. The adapter itself (`onTermination`,
  cancellation, transport) stays in WI-M2-M4/M6 and is not in this item.
- **K2, the end needs the provider's own "finished".** A body with no normal end is `cutShort(.noFinish)`, even when
  its JSON happens to be finished. The normal end is OpenAI `stop` + `[DONE]`, Anthropic a normal `stop_reason` +
  `message_stop`, and Gemini `STOP`. This is the literal reading of "a truncated stream … ends `interrupted`". Without
  the end, nothing says the model was done, so the item in progress is discarded, not completed by rule (c), which
  needs "the stream finishes normally". **Open question 1** asks the PO to confirm.
- **K3, a stop after new output in the same chunk is deferred.** If one chunk holds output that completes an item and
  then a refusal, length cut or error, `append` returns that snapshot first, and the next call throws. Without this,
  the outcome would depend on how the transport cut the body: byte by byte gives `interrupted` with the draft, while
  one chunk gives `noModel`. The `splitChunks` test checks every fixture against 42 cut sets for exactly that. Mutant
  M17 shows the rule matters.
- **K4, valid output before a bad byte is read.** A piece such as `p"},{"kind":restock` finishes item 1 before the bad
  `r`. The reader reads that piece again, from the state before it, up to the bad byte (`StructuredOutputReader` is a
  value type, so this is a cheap copy). The draft is emitted and the end is `interrupted`, not `noModel`. The offset
  in `outputNotJSON` counts output bytes, the same as WI-M2-12's `byteOffset`.
- **K5, provider safety stops are `refusal`, not `guardrail`.** `ModelStopReason.guardrail` is documented as the
  on-device generation guardrail. `refusal` is documented as "the model or provider declined to answer", which fits
  OpenAI `content_filter`, Anthropic `refusal`, Gemini `SAFETY` (and the others) and a blocked prompt. Either way the
  brief gives the same outcome (`noModel` before a draft, `interrupted` after). Gemini `LANGUAGE` maps to the existing
  `unsupportedLanguage`. An unknown finish reason is `otherModelError`, never a normal end, so a provider change can
  never pass as success.
- **K6, strict structure, calm outcome.** A wrong-typed member, a second choice or candidate or tool block, a delta
  for a block that is not open, or output after the finish is `unexpectedStructure` (`unreadableOutput`). Unknown
  event types, pings, usage chunks, text blocks and thought parts are ignored, because the providers document that
  such events may appear. This follows WI-M2-12 J5: the output JSON is read leniently by Q5, but the provider envelope
  is not guessed.
- **K7, R26-F2 closed here, 1 MiB.** The cap belongs to the body reader, not the transport, so it also bounds the
  framer's line and data buffers, the event parser and the output text. Each of those is fed only bytes that have
  passed the cap. 1 MiB is about 35 times the largest synthetic fixture (28,697 bytes; a test asserts a factor ≥ 16)
  and far above one capture's output. The OpenAI per-chunk overhead is about 200 bytes per few tokens. The 10.0 s
  deadline (WI-M2-14) bounds time, and this bounds memory. WI-M2-14 needs no cap of its own. The limit is an init
  parameter only so the tests can use small limits. The adapters use the default.
- **K8, fixtures are files, not code.** The plan names `Fixtures/M2/provider-streams/` for synthetic and recorded
  fixtures, and WI-M2-M6 reads them again through a mock transport on the Mac. So the synthetic set is plain `.sse`
  files. I wrote them with a one-off generator (Python, not committed: it is not a tool the build uses).
  `ProviderStreamFixtureTests` is the specification: `fixtureList` fails on any missing or extra file, and
  `outputText` checks that the happy and out-of-order fixtures' pieces join up to exactly the output typed again in
  Swift (`ProviderFixtures.happyOutput`). The tests never write a fixture. The model ID in every file is
  `synthetic-model`, and the files hold no host, key or header.
- **K9, the provider formats as built are from the documented formats, not checked online here.** No web fetch was
  allowed or made. The dialect files list each rule they rely on. WI-M2-M6 must:
  1. check each rule against the current docs and the real recordings: the `[DONE]` need, `content_filter`, the
     in-stream error shapes, Gemini's last-chunk `finishReason`, the Anthropic stop reasons;
  2. add a recorded fixture per provider;
  3. change a dialect rule here only with a test.
  
  A mismatch fails calmly (`noFinish`, `unexpectedFinish` or `unexpectedStructure`), never by reading wrong output.

### AC coverage
| AC (Linux part) | Test(s) | Result |
|---|---|---|
| AC-M2-24 fixtures: happy path, out-of-order or split chunks, truncated stream, invalid JSON, schema-violating fields, unknown enums, refusal (T-19) | `ProviderStreamFixtureTests.fixtureOutcome`: 30 cases, one per fixture. Each checks the reader's exact error, the emitted titles, the skips, exactly one `finished`, the exact outcome through `DraftPipeline` on `cloud(provider)`, the plain-note offer for `noModel`, and that the error's `stopReason` is the outcome's reason. `fixtureList` checks that the files on disk equal the table (10 per provider, logged) | PASS (Linux) |
| AC-M2-24 split chunks | `splitChunks`: 30 cases. Each fixture is read one shot, one event per chunk, byte by byte and at 40 seeded random cut sets. The reader's end and, through the pipeline, the emitted titles, final drafts and outcome all equal the one-shot result. `ProviderDialectPropertyTests.randomBodies`: 3 seeds (`0x0D1A1EC71301…03`) × 200 WI-M2-12 corpus outputs × 3 providers. `DialectWriter` (random pieces, CR/LF/CRLF, comments, `data:` without a space, noise events) writes each body, which is read one shot and at 2 random cut sets: the end equals `StructuredOutputReader.parse(output)`, and every step only grows | PASS (Linux): 0 mismatches. Items per seed (1301 / 1302 / 1303): 505 / 520 / 464 per provider; 1,800 reads per seed |
| AC-M2-24 + AC-M2-05: title arrives last, per provider (PO tickets) | `titleArrivesLast`: 3 providers × {happy, out-of-order}, each one event per chunk and byte by byte. Rule (a) is first met for item 3 with the whole title, before the end; no earlier step shows its title; exactly one `emitted` for draft 3 with "Deep clean the balcony"; no `updated`; no `itemSkipped`. `neverAPartTitle`: 30 cases, every step of every fixture read byte by byte shows only finished titles | PASS (Linux) |
| AC-M2-24 + AC-M2-05: no-room item completes by (a) before the next item (PO WI-M2-12 ruling 2 ticket) | `noRoomItemCompletesByRuleA`: 3 providers. In each happy path, one event per chunk, draft 1 ("Service the AC", `"room":""`) is emitted at a step whose snapshot holds only that item (`hasValueForEveryField`, `roomName == ""`), and its room is `none` | PASS (Linux) |
| AC-M2-24: refusal before a draft → `noModel`; truncation, invalid JSON or a cut after a draft → `interrupted` | the fixture rows `refusal-before-draft` (×3), `truncated-…`, `length-limit-…`, `invalid-json-…`, `invalid-event-before-draft`, `provider-error-…`; `deferredStop` (a refusal or safety stop in the same chunk as a completed item → `interrupted(refusal)`, 3 providers); `validTextBeforeBadByte` (3) | PASS (Linux) |
| AC-M2-24: each dialect's rules | `OpenAIDialectTests` (7 tests, 21 cases), `AnthropicDialectTests` (5 tests, 27 cases), `GeminiDialectTests` (5 tests, 28 cases): finish and stop reason tables, refusal and blocked-prompt signals, ignored noise, every `unexpectedStructure` case, in-stream error mapping. Each expected error is checked one shot and byte by byte | PASS (Linux) |
| AC-M2-24: shared reader rules | `ProviderStreamReaderTests` (15 tests): the happy body per provider and `read(_:provider:)`; the stop-reason table (19 rows); empty and unended bodies; a body ending inside an event; unfinished output; no output; invalid output offsets; `eventNotJSON` (6 data texts × 3); K3 and K4; sticky and closed; after the end; nil without output; `lookupQueries` empty | PASS (Linux) |
| R26-F2 response size cap | `sizeCapBoundary` (3 providers × 3 chunkings: exactly the limit is read, one byte more is `responseTooLarge`; a refused chunk is not counted); `sizeCapOutcomes` (a stream with no line end stops within the limit; through the pipeline, after a draft `interrupted(unreadableOutput)`, before one `noModel` with the plain note); `fixturesUnderTheLimit` | PASS (Linux) |
| AC-M2-24 + AC-M2-02/04: Q5 repairs and room linking on cloud output | `happyDrafts` (rooms `none`, existing Kitchen, proposed "Balcony"; kinds, efforts, flags, `sourcePhrase`, duplicate `none`); `schemaViolatingRepairs`; `unknownEnumRepairs` (3 providers each) | PASS (Linux) |
| AC-M2-24: "a cloud model is never given the duplicate-lookup `Tool`" | `happyBody`: the reader's own snapshot has empty `lookupQueries` for every provider. The reader has no Tool path | PASS (Linux) |
| AC-M2-09 (regression) | "AC-M2-09: Rules 1–6 hold …" over 46 files | PASS (Linux): 0 violations |
| AC-M2-12 vocabulary (regression) | the AC-M1-02 vocabulary scan over the module roots, 46 files (every new case name and literal) | PASS (Linux): 0 violations |

### Test runs
| Command (in `swift:6.2-noble`, Swift 6.2.x, `-Xswiftc -warnings-as-errors`, scratch path `/tmp/b13-<pkg>` on a cache volume) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` (final head, after merging `6fd1bf4`) | `✔ Test run with 445 tests in 55 suites passed after 105.396 seconds.` That is 401 on `main` at `6fd1bf4` (`✔ … 401 tests in 49 suites …`, run on a scratch checkout) plus 44 new. Before the merge, on `03e98c6`: 377 = 333 + 44. |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 80.811 seconds.` (unchanged package) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 2.391 seconds.` (unchanged package) |

### Mutation check
Each mutant was applied alone by a script to a scratch copy of the head (`git archive`, never this branch). It was
built with `-warnings-as-errors`, run with `--filter "Provider|Dialect"` in a 900 s timeout, and then restored.
**29 of 29 killed.** M6, M8 and M9 at first did not compile under `-warnings-as-errors` (an unused value, and a
duplicate `case` literal), so the first attempt did not count. They were rewritten to compile cleanly, and the table
shows the second run.

| # | Mutant | Killed by (first failing tests) |
|---|---|---|
| M1 | OpenAI: an empty refusal piece counts as a refusal | a refusal piece stops the stream (refusal); a null or empty refusal is… |
| M2 | OpenAI: content_filter read as an unexpected finish | a stop in the same chunk as output that completes a draft is thrown on…; finish_reason stop then [DONE] is the only normal end; length, content… |
| M3 | OpenAI: [DONE] alone is a normal end (no finish reason needed) | [DONE] without a finish reason, or a stop finish without [DONE], is cu… |
| M4 | OpenAI: content after the finish reason accepted | output text after finish_reason stop is unexpected structure |
| M5 | OpenAI: choice index not checked | content after the finish reason, a second choice, or wrong-typed membe… |
| M6 | Anthropic: deltas of non-tool blocks read as output | in each provider's happy and out-of-order fixtures the title-last item…; each fixture gives its exact outcome, emitted titles and skips through…; a text block before the tool block is ignored; pings and unknown event… … |
| M7 | Anthropic: a second tool_use block replaces the first | deltas for a block never started or already stopped, a second tool blo… |
| M8 | Anthropic: stop_reason refusal read as a normal end | each fixture gives its exact outcome, emitted titles and skips through…; a stop in the same chunk as output that completes a draft is thrown on…; stop reasons tool_use, end_turn and stop_sequence end normally; the re… |
| M9 | Anthropic: max_tokens read as a normal end | each fixture gives its exact outcome, emitted titles and skips through…; stop reasons tool_use, end_turn and stop_sequence end normally; the re… |
| M10 | Anthropic: overloaded_error mapped to otherModelError | each fixture gives its exact outcome, emitted titles and skips through…; an error event stops the stream with a neutral reason |
| M11 | Anthropic: a delta for a stopped block accepted | deltas for a block never started or already stopped, a second tool blo… |
| M12 | Gemini: thought parts read as output | in each provider's happy and out-of-order fixtures the title-last item…; each fixture gives its exact outcome, emitted titles and skips through…; 3 seeds × 200 outputs × 3 providers; one shot and 2 random cut sets eq… … |
| M13 | Gemini: promptFeedback.blockReason ignored | each fixture gives its exact outcome, emitted titles and skips through…; a blocked prompt (promptFeedback.blockReason) is a refusal; feedback w… |
| M14 | Gemini: LANGUAGE read as a safety stop | finishReason STOP ends normally; the others stop the stream |
| M15 | Gemini: candidate index not checked | a second candidate or wrong-typed members are unexpected structure |
| M16 | Gemini: finish reason read before the text of its chunk | a stop in the same chunk as output that completes a draft is thrown on… |
| M17 | Reader: a stop after new output is thrown at once (no deferral) | valid output before a bad byte in the same piece is read, so a draft i…; each fixture gives its exact outcome, emitted titles and skips through…; a stop in the same chunk as output that completes a draft is thrown on… … |
| M18 | Reader: the valid text before a bad byte is not read | valid output before a bad byte in the same piece is read, so a draft i… |
| M19 | Reader: events after the provider end are read | events after the provider's end are ignored, including a part-written… |
| M20 | Reader: a body that stops inside an event is not reported | each fixture gives its exact outcome, emitted titles and skips through…; a body that stops inside an event (no blank line) is cut short (bodyEn… |
| M21 | Reader: size cap off by one (a body of exactly the limit is refused) | R26-F2 / AC-M2-24: a body of exactly the limit is read; one byte more… |
| M22 | Reader: no size cap | R26-F2 / AC-M2-24: a body of exactly the limit is read; one byte more…; R26-F2 / AC-M2-24: a stream with no line end (or one endless output) s… |
| M23 | Reader: a refused chunk is counted | R26-F2 / AC-M2-24: a body of exactly the limit is read; one byte more…; R26-F2 / AC-M2-24: a stream with no line end (or one endless output) s… |
| M24 | Reader: no noOutput check | a normal provider end with no output text at all is unreadable (noOutp… |
| M25 | Reader: unfinished output JSON reported as noFinish | a normal provider end with unfinished output JSON is cut short (output… |
| M26 | Reader: the step stop handled before the step output | a stop in the same chunk as output that completes a draft is thrown on… |
| M27 | Error: declined mapped to guardrail | each fixture gives its exact outcome, emitted titles and skips through…; a stop in the same chunk as output that completes a draft is thrown on…; every error maps to exactly one neutral stop reason (the adapter throw… |
| M28 | Event JSON: a non-object root accepted | event data that is not a JSON object is unreadable (eventNotJSON) |
| M29 | Event JSON: null is not absent | in each provider's happy and out-of-order fixtures the title-last item…; in each provider's happy path (one event per chunk) the no-room item (; valid output before a bad byte in the same piece is read, so a draft i… … |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 445 tests: the three dialects, the 30 fixtures, the property, the size cap, the pipeline outcomes, AC-M2-09 and AC-M2-12 scans | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 (unchanged) | ✔ container | — | — | — | — |
| The same reader on Darwin Foundation | — | — | — | — | Mac repeat in MS-2 |
| The cloud adapters end to end over these fixtures through a mock transport (AC-M2-24 Mac part) | — | — | — | — | WI-M2-M6 (owner-run Mac) |
| The dialect rules against real provider streams and current docs (K9) | — | — | — | — | WI-M2-M6 recordings; no network here |

Device ACs: none in this item.

### Things the reviewer should look at closely
- K2: whether a body with finished JSON but no provider end should be `interrupted` (as built) or `completed`
  (open question 1).
- K3 and K4 in `ProviderStreamReader.append` and `readOutput`: the deferred stop and the re-read up to the bad byte.
  Check that the outcome cannot depend on chunking. `splitChunks` and the property test check this.
- Each dialect's strict and ignored lists (K6) against the provider docs you know, and the in-stream error mappings.
- The fixtures: read two or three `.sse` files against the README table.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| The dialect rules are from the documented formats as I know them; nothing was checked online (K9) | watch | WI-M2-M6: verify each rule against the current docs and the real recordings; record one fixture per provider in `recorded/<provider>/`; change a rule only with a test |
| The forced tool's name is not checked (Anthropic), and neither are `n` / `candidateCount` (any second choice or candidate is refused) | — | WI-M2-10: send one forced tool with `disable_parallel_tool_use`, `n` 1 (default) and `candidateCount` 1, and say whether the reader should also check the tool name |
| The cloud adapter loop (`ChunkedProviderModel` is the test pattern): `onTermination`, cancellation, the transport | — | WI-M2-M4 / M6 |
| R26-F2 (response size cap) | closed | here (K7); WI-M2-14 needs no cap |
| The Darwin rerun of these tests | — | MS-2 |

### Open questions
1. **Closed in round 2 (review R29-N3): the PO confirmed K2 as built in `po-m2-wi13.md` (2026-11-24).** The original
   question follows. **PO (confirm, K2): a body that stops without the provider's end, even when its JSON is finished,
   counts as truncated.** Built: `cutShort(.noFinish)` → `outputCutShort`. After a draft the outcome is `interrupted`, and an
   item still in progress is discarded. Before any draft it is `noModel` with the plain note. The other reading would
   complete the items (rule (c)) and give `completed` whenever the JSON is finished. That would treat a connection that
   dropped just before the provider said "done" as a normal finish. Work continues on the literal reading. A change
   would be one line per dialect `checkEnd`, plus the fixture rows.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The reader only turns provider streams into snapshots. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Every new case name and literal passes the AC-M2-12 vocabulary scan (46 files, 0 violations). The names describe the stream, never the person (`declined`, `cutShort`, `responseTooLarge`, `unexpectedFinish`). No provider text (refusal wording, error messages) is kept or shown. A stop after drafts keeps them (`interrupted`), and a stop before any draft returns the input with the plain note, so nothing the person said is lost. The title-last and finished-values tests per provider mean no part title can be guarded away. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | Parsing only. Nothing here chooses a model or a route. |
| P-2 No data leaves the device | pass | Pure parsing over bytes and strings: no network, file I/O or logging in Sources (AC-M2-09: 46 files, 0 violations). No dependency. The fixtures hold no household data, key, header or host. |
| P-3 Cloud AI opt-in, minimised | pass | This reads responses only; it builds no request and adds no request field. The cloud model has no `Tool` (`lookupQueries` is always empty). The size cap bounds what a provider stream can make the phone hold. |
| P-4 Media not persisted | n.a. | Text only, held in memory. The reader keeps no body after `finish`. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Developer | accepted (H2) | WI-M2-13 Ready (WI-M2-12 merged as PR #26; `main` at `03e98c6`). PO tickets: per-provider title-arrives-last and no-room-by-(a) fixtures; R26-F2 here or in WI-M2-14. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first (red build confirmed). Merged `origin/main` `6fd1bf4`. TendIngestion 445, TendCore 141, TendSourceScan 63 green, 0 warnings, Linux. 29 of 29 mutants killed. R26-F2 closed (1 MiB cap). One PO question (K2). Pushed; no PR opened. |

### Round 2 (PR #29 review round 1: APPROVE with R29-F1…F3 and R29-N1…N3; PO `po-m2-wi13.md`)
Inputs: `review-WI-M2-13.md` (committed with this round), `po-m2-wi13.md` (K2 confirmed as built, tickets, two brief
amendments), `po-m2-wi10.md` rulings 3 and 7. `origin/main` `f1b6458` (PR #28) merged in, with no rebase. The only
conflict was this file: I took `main`'s copy and appended this section at the end.

#### Findings
| Finding | What changed | Evidence |
|---|---|---|
| R29-F1 (a) the cap depended on chunk cuts | `append` reads the part of the chunk that fits under the limit (`bytes.prefix(room)`) and counts only that part. If the chunk goes past the limit before the provider's end, the reader stops with `unreadable(.responseTooLarge)` through the same hold rule as every other stop (K3): if the part that fit added output, its snapshot is returned and the next call throws. So the drafts read before the limit no longer depend on the transport's cuts. | `sizeCapChunkIndependence` (3 providers): a body more than 1,000 bytes past a 2,048-byte limit, with item 1 complete under it. One shot, one event per chunk, byte by byte and 8 seeded random cut sets all give the reader error `responseTooLarge`, emitted `["Mop the floor"]` and `interrupted(unreadableOutput, stoppedBeforeComplete)` through the pipeline. In one shot, the first `append` returns the item-1 snapshot and `receivedByteCount == limit`. Mutant M23 (the round-1 behaviour) is killed. |
| R29-F1 (b) bytes after the end were counted | Once the provider's end has arrived (or after `finish`), `append` drops later bytes, does not count them and returns nil. The cap applies only before the end. | `sizeCapBoundary` (3 providers × 3 chunkings): a body of exactly the limit is read, and one byte more before the end is `responseTooLarge`. A complete body followed by extra bytes past the limit still finishes normally, and `receivedByteCount` does not move after the end. With limit 10, the append that crosses it counts exactly 10. Mutants M30 and M30b are killed. |
| R29-F2 ruling-7 fixture shapes | All 33 fixtures were regenerated. **OpenAI:** `model` `gpt-6-luna`, `"usage":null` on every chunk, and the `include_usage` chunk (`"choices":[]`, `usage` with `completion_tokens_details.reasoning_tokens`) after the finish chunk and before `[DONE]` in every fixture that reaches `[DONE]` (split over two `data:` lines in `out-of-order-fields`). **Anthropic:** `model` `claude-haiku-4-5-20251001`. **Gemini:** `modelVersion` `gemini-3.5-flash-lite`, `usageMetadata.thoughtsTokenCount`, a `thoughtSignature` on the first part of `happy-path` and `finished-output-no-end`, and full outputs in sorted key order (the `responseJsonSchema` order of ruling 7). The Gemini dialect header now names `responseJsonSchema` and `thinkingLevel: "minimal"`, and says `thoughtSignature` and `thoughtsTokenCount` are ignored. The OpenAI and Anthropic headers name the ruling-7 request too. | `rulingSevenShapes` (3 providers) reads those fields from the happy path and checks the reader still gives the intended snapshot. `fixtureOutcome`, `outputText` (the Gemini text equals `ProviderFixtures.geminiHappyOutput`, typed out again in Swift) and `splitChunks` are green on the new files. |
| R29-F3 Anthropic R3, R5 and `message_stop` first | No code change (the rules were already built). New rows in `AnthropicDialectTests.unexpectedStructure`: `message_delta` with no `message_start` (R3), `message_stop` with no `message_start`, and block 0 started, stopped and started again (R5). Each is checked one shot and byte by byte. | Mutants M32 (R3), M33 (R5) and M34 (`message_stop` first) are killed. These are the reviewer's 2 survivors, plus one more. |
| R29-N1 a non-Boolean Gemini `thought` | New strict accessor `ProviderEventJSON.bool(_:)`: missing or `null` gives nil, a Boolean is read, and any other type is `unexpectedStructure` (K6). Gemini reads `thought` with it. | A new `GeminiDialectTests.unexpectedStructure` row, `"thought":"yes"`. The parts test now also has `"thought":null` and `"thought":false` read as output. Mutant M35 (the round-1 comparison) is killed. |
| R29-N2 snapshot cost per append | The note asked only for an adapter ticket (follow-ups below). I also made one code change, because the property test showed the cost. The snapshot is now built once per `append` call, never per event (`StructuredOutputReader.read(bytes:)` plus `snapshot`). In round 1, a chunk with many events rebuilt it once per event. The outputs and the hold rule are unchanged (all K3/K4 tests are green). The reason is below. | The full suite is green. The property test is now fast enough not to starve the time-limited cancellation tests that share the pool. |
| R29-N3 open question 1 | Closed: the PO confirmed K2 as built (`po-m2-wi13.md`). Open question 1 above is marked closed, and the PO's tickets are mapped below. | — |

**Why the R29-N2 code change.** In round 2, the new tests made the property suite and the other suites run together. The
round-1 reader rebuilt the snapshot after every event with output. `DialectWriter` bodies have many small events per
chunk, so the property's one-shot reads were quadratic in the output, and the suite took about 113 s of CPU. Under the
container's load (other developers' runs, load average about 9), that starved three or four existing time-limited cancellation
tests (`CloudConsentRaceTests` R24-F1/F2 and `CloudConsentTests`). They hit their 60 s `.timeLimit`, but pass alone in
0.3 s. `main` alone was green under the same load. Building the snapshot once per `append` removes the quadratic cost.
**Correction (round 3, review R29-R2-F1):** an earlier version of this paragraph said this was done "without weakening,
skipping or shrinking any test". That was wrong. In the same round I also narrowed `splitChunks`. Its pipeline
comparison (emitted titles, final drafts and outcome through `DraftPipeline`) ran for only 5 of the 42 cut sets
(`if index < 5`), and the other 37 kept only the reader-level checks. I did that to save pool time for the
time-limited tests, and I did not record it. That breaks CLAUDE.md §6. Round 3 puts back all 42 pipeline comparisons;
see "Round 3" below. `.serialized` on the heavy fixture and property tests and
`await Task.yield()` in their loops also stay, so they share the pool fairly. The adapter ticket in R29-N2 still stands,
because a 1-byte feed would still rebuild one snapshot per byte.

#### PO rulings traced
| Ruling | What it asks of WI-M2-13 | Where it is met |
|---|---|---|
| `po-m2-wi10.md` ruling 3 (fixed members; a stop at the fixed output cap is truncated, never `completed`) | One cap-stop fixture per provider → `interrupted` (or `noModel` with no draft) | `length-limit-after-first-draft` × 3 (OpenAI `length`, Anthropic `max_tokens`, Gemini `MAX_TOKENS`) → `interrupted(outputCutShort)`, 1 draft (`fixtureOutcome`). The `model_context_window_exceeded` row is in `AnthropicDialectTests`. |
| `po-m2-wi10.md` ruling 7 (final models and fixed request members) | Usage and served-model fields in the fixtures, ignored for drafts | R29-F2 row above: the served-model IDs, OpenAI `include_usage` chunk with `reasoning_tokens`, Gemini `thoughtsTokenCount` and `thoughtSignature`, sorted keys. `rulingSevenShapes`, `fixtureOutcome`, `outputText`. |
| `po-m2-wi13.md` (K2 confirmed: no provider normal end = truncated, even with finished JSON) | See the ticket table | below |

#### `po-m2-wi13.md` tickets
| Ticket | Where it is met |
|---|---|
| `finished-output-no-end` per provider: the whole happy output, a clean end at an event boundary, no normal end → `interrupted(outputCutShort)`, 3 drafts, no `itemSkipped`, exactly one `finished` | 3 new fixtures. OpenAI has no `finish_reason` and no `[DONE]`. Anthropic has `content_block_stop`, but no `message_delta` stop and no `message_stop`. Gemini's last chunk has no `finishReason`. `fixtureOutcome` rows (reader error `cutShort(.noFinish)`, all 3 titles emitted). `finishedOutputNoEnd`: through the pipeline one shot, per event and byte by byte, 3 final drafts, 0 skips, one `finished`, `interrupted(outputCutShort, discardedItem: nil)`. |
| Anthropic normal `stop_reason` without `message_stop` → `cutShort(.noFinish)` | `AnthropicDialectTests.normalStopWithoutMessageStop` (finished output and `content_block_stop`, then each normal `stop_reason`: `tool_use`, `end_turn`, `stop_sequence`; no `message_stop`). The OpenAI `stop` without `[DONE]` case was already tested. |
| Reader: a last item that only rule (c) could complete, no normal end → discarded, earlier draft kept, `interrupted` | `noEndDiscardsTheLastItem` (3 providers): item 2 has only `title` and `kind`. The result is emitted `["Mop the floor"]` and `interrupted(outputCutShort, discardedItem: stoppedBeforeComplete)`. |
| Reader: finished `{"items":[]}`, no normal end → `noModel` with the plain-note offer | `noEndEmptyItems` (3 providers): one event, `noModel(stoppedBeforeFirstDraft(outputCutShort))`, input and note "mop". |
| Mutant "finished output JSON counts as a normal end" is killed | M31, killed (table below). |
| README (11 per provider, 33 in all) and `fixtureList` | Done. `fixtureList` logs 11 per provider. |
| Brief amendments 1 and 2, word for word | `brief.md`: amendment 1 is inserted after the ruling-3 sentence of the `interrupted` bullet. In AC-M2-24, the last bullet's two sentences are replaced by the PO's text. Both are copied exactly; only the line breaks were reflowed. |

#### K7, updated (supersedes the K7 text above)
The response byte cap is 1 MiB (`defaultResponseByteLimit`; the tests can lower it). Only bytes before the provider's
end count. A chunk that crosses the limit is read up to the limit, and then the reader stops with
`unreadable(.responseTooLarge)` through the hold rule (K3). So the drafts emitted before the limit never depend on how
the transport cut the body. The stop maps to `unreadableOutput`: `interrupted` after a draft, `noModel` with the plain
note before one. Bytes after the provider's end are dropped and not counted, so a finished body is never refused for
trailing bytes.

#### Test runs (round 2, final head)
| Command (in `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, scratch path `/tmp/b13-<pkg>` on a cache volume) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 491 tests in 57 suites passed after 263.000 seconds.` (on `c32f370`; the machine was shared, and `0a39ba5` gave the same 491 in 170.8 s). That is 441 on `main` `f1b6458` plus 50 for WI-M2-13 (44 in round 1, plus 6 new: `sizeCapChunkIndependence`, `noEndDiscardsTheLastItem`, `noEndEmptyItems`, `normalStopWithoutMessageStop`, `rulingSevenShapes`, `finishedOutputNoEnd`). 0 warnings. |
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed after 178.138 seconds.` (unchanged package; slow because the mutant run shared the machine) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed after 6.662 seconds.` (unchanged package) |
| AC-M2-09 scan | `AC-M2-09 scan: 52 files in total, 0 violations` |
| AC-M2-12 scan | `AC-M2-12 vocabulary scan: 52 files, 9 exempted (the list), 0 violations` |

The largest fixture is now 44,238 bytes, still far below 1 MiB (`fixturesUnderTheLimit`).

#### Mutation check (round 2)
Each mutant was applied alone by a script to a scratch copy of the head (`git archive`, never this branch), with
`touch` after each change and each restore so SwiftPM rebuilds. Each was built with `-warnings-as-errors`, run with
`--filter "Provider|Dialect"` in a 900 s timeout, and then restored. M21–M23 were rewritten for the round-2 cap code,
and M30–M35 are new (R29-F1 (b), the `po-m2-wi13.md` mutant, R29-F3, R29-N1).

**36 of 36 killed.** M1–M29 ran on `0a39ba5`. On that head, **M30, M32 and M33 survived**:
- the R3 and R5 rows were followed by a delta that failed on its own;
- the after-end count check had no room left under its limit (the cap itself stopped the count).
Commit `c32f370` makes each row a valid stream apart from the rule it tests, and gives the after-end reader room under
its limit. M30–M35 were then run again on `c32f370`, and all were killed. That commit changes only tests, and only makes
them stricter, so the M1–M29 results still hold.

| # | Mutant | Killed by (first failing tests) |
|---|---|---|
| M1 | OpenAI: an empty refusal piece counts as a refusal | AC-M2-24: a refusal piece stops the stream (refusal); a null or empty … |
| M2 | OpenAI: content_filter read as an unexpected finish | AC-M2-24: a stop in the same chunk as output that completes a draft is…; AC-M2-24: finish_reason stop then [DONE] is the only normal end; lengt… |
| M3 | OpenAI: [DONE] alone is a normal end (no finish reason needed) | AC-M2-24: [DONE] without a finish reason, or a stop finish without [DO… |
| M4 | OpenAI: content after the finish reason accepted | AC-M2-24: output text after finish_reason stop is unexpected structure |
| M5 | OpenAI: choice index not checked | AC-M2-24: content after the finish reason, a second choice, or wrong-t… |
| M6 | Anthropic: deltas of non-tool blocks read as output | AC-M2-05 / AC-M2-24: in each provider's happy and out-of-order fixture…; AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a text block before the tool block is ignored; pings and unk… … |
| M7 | Anthropic: a second tool_use block replaces the first | AC-M2-24: deltas for a block never started or already stopped, a secon… |
| M8 | Anthropic: stop_reason refusal read as a normal end | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a stop in the same chunk as output that completes a draft is…; AC-M2-24: stop reasons tool_use, end_turn and stop_sequence end normal… |
| M9 | Anthropic: max_tokens read as a normal end | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: stop reasons tool_use, end_turn and stop_sequence end normal… |
| M10 | Anthropic: overloaded_error mapped to otherModelError | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: an error event stops the stream with a neutral reason |
| M11 | Anthropic: a delta for a stopped block accepted | AC-M2-24: deltas for a block never started or already stopped, a secon… |
| M12 | Gemini: thought parts read as output | AC-M2-05 / AC-M2-24: in each provider's happy and out-of-order fixture…; AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: 3 seeds × 200 outputs × 3 providers; one shot and 2 random c… … |
| M13 | Gemini: promptFeedback.blockReason ignored | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a blocked prompt (promptFeedback.blockReason) is a refusal; … |
| M14 | Gemini: LANGUAGE read as a safety stop | AC-M2-24: finishReason STOP ends normally; the others stop the stream |
| M15 | Gemini: candidate index not checked | AC-M2-24: a second candidate or wrong-typed members are unexpected str… |
| M16 | Gemini: finish reason read before the text of its chunk | AC-M2-24: a stop in the same chunk as output that completes a draft is… |
| M17 | Reader: a stop after new output is thrown at once (no deferral) | AC-M2-05 / AC-M2-24: valid output before a bad byte in the same piece …; AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a stop in the same chunk as output that completes a draft is… … |
| M18 | Reader: the valid text before a bad byte is not read | AC-M2-05 / AC-M2-24: valid output before a bad byte in the same piece … |
| M19 | Reader: events after the provider end are read | AC-M2-24: events after the provider's end are ignored, including a par… |
| M20 | Reader: a body that stops inside an event is not reported | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a body that stops inside an event (no blank line) is cut sho… |
| M21 | Reader: size cap off by one (a body of exactly the limit is refused) | R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one b…; R29-F1 / AC-M2-05 / AC-M2-24: a body past the limit whose first item c… |
| M22 | Reader: no size cap | R26-F2 / AC-M2-24: a stream with no line end (or one endless output) s…; R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one b…; R29-F1 / AC-M2-05 / AC-M2-24: a body past the limit whose first item c… |
| M23 | Reader: the whole crossing chunk is dropped (round-1 behaviour, R29-F1 (a)) | R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one b…; R29-F1 / AC-M2-05 / AC-M2-24: a body past the limit whose first item c… |
| M24 | Reader: no noOutput check | AC-M2-24: a normal provider end with no output text at all is unreadab… |
| M25 | Reader: unfinished output JSON reported as noFinish | AC-M2-24: a normal provider end with unfinished output JSON is cut sho… |
| M26 | Reader: the step stop handled before the step output | AC-M2-24: a stop in the same chunk as output that completes a draft is… |
| M27 | Error: declined mapped to guardrail | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24: a stop in the same chunk as output that completes a draft is…; AC-M2-24: every error maps to exactly one neutral stop reason (the ada… |
| M28 | Event JSON: a non-object root accepted | AC-M2-24: event data that is not a JSON object is unreadable (eventNot… |
| M29 | Event JSON: null is not absent | AC-M2-05 / AC-M2-24: in each provider's happy and out-of-order fixture…; AC-M2-05 / AC-M2-24: in each provider's happy path (one event per chun…; AC-M2-05 / AC-M2-24: valid output before a bad byte in the same piece … … |
| M30 | Reader: bytes after the provider end are counted (R29-F1 (b)) | R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one b… |
| M30b | Reader: the cap applies after the provider end (R29-F1 (b)) | R26-F2 / R29-F1 / AC-M2-24: a body of exactly the limit is read; one b… |
| M31 | Reader: finished output JSON counts as a normal end (K2, po-m2-wi13) | AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted tit…; AC-M2-24 / AC-M2-05: finished output with no provider end keeps all 3 …; AC-M2-24 / AC-M2-05: finished output with no provider end: a last item… … |
| M32 | Anthropic R3: message_delta before message_start accepted | AC-M2-24: deltas for a block never started or already stopped, a secon… |
| M33 | Anthropic R5: a stopped block index can start again | AC-M2-24: deltas for a block never started or already stopped, a secon… |
| M34 | Anthropic: message_stop before message_start accepted | AC-M2-24: deltas for a block never started or already stopped, a secon… |
| M35 | Gemini N1: a non-Boolean thought ignored (R29-N1) | AC-M2-24: a second candidate or wrong-typed members are unexpected str… |

#### Verification environment (round 2)
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendIngestion 491 (the three dialects, 33 fixtures, cap, K2 tickets, property, scans) | ✔ container | — | — | — | Linux CI runs on the PR |
| TendCore 141, TendSourceScan 63 | ✔ container | — | — | — | — |
| Ruling-7 shapes against real `gpt-6-luna`, `claude-haiku-4-5-20251001`, `gemini-3.5-flash-lite` streams | — | — | — | — | WI-M2-M6 recordings and L2 (K9); no network here |
| Each provider's normal end in a real stream (`po-m2-wi13.md` WI-M2-M6 ticket) | — | — | — | — | WI-M2-M6 |

#### Follow-ups added in round 2
| Item | Severity | Ticket |
|---|---|---|
| R29-N2: the adapter must feed buffered chunks, never single bytes | Nit | WI-M2-M4: feed `URLSession.AsyncBytes` in buffered chunks (for example up to each line end or 4 KB), never one byte per `append`. The reader builds one snapshot per `append` call (round 2), which costs time linear in the output so far, so a 1-byte feed of a near-1 MiB output would be quadratic within the 10 s deadline. |
| `po-m2-wi13.md`: confirm each provider's normal end in L2 and the real recordings | — | WI-M2-M6. A mismatch is fixed in that dialect's `checkEnd`, with a test and a dev-notes record (the PO says no ruling is needed for that) |
| `po-m2-wi13.md`: DECISIONS.md entry for K2 | — | PO, in the next human-merged governance PR (protected path; not touched here) |
| `po-m2-wi13.md`: `interrupted` state copy | — | Designer, M3 |
| Reviewer K9 re-check list (review "Re-check list for WI-M2-M6") | watch | WI-M2-M6 |

#### Open questions (round 2)
None. K2 is closed by `po-m2-wi13.md`.

#### Law check (round 2)
| Law | Status | Note |
|---|---|---|
| UX-1 | n.a. | No entry surface. |
| UX-2 | n.a. | No selection surface. |
| UX-3 | pass | A draft read before the cap is now never lost to how the body was cut (R29-F1). A finished output without the provider's end keeps all 3 drafts and returns the input (`interrupted`), and never claims `completed` (`po-m2-wi13.md`). The scan covers 52 files with 0 violations. |
| UX-4 | n.a. | No UI. |
| P-1 | n.a. | Parsing only. |
| P-2 | pass | No network, file I/O or logging in Sources (AC-M2-09: 52 files, 0 violations). No dependency. The fixtures are synthetic, with no household data, key, header or host. |
| P-3 | pass | Response reading only. The ruling-7 request members are only described in comments, and no request is built here. |
| P-4 | n.a. | Text in memory only. Bytes after the end are dropped. |

#### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted | Round 2: R29-F1…F3, N1, N3; PO `po-m2-wi13.md` tickets and brief amendments; ruling-7 fixtures; merge `f1b6458`. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (H4) | Round 2 done. R29-F1, F2, F3, N1 and N3 fixed; N2 is a WI-M2-M4 ticket (plus one snapshot per `append`). `po-m2-wi13.md` tickets and brief amendments 1–2 applied. Rulings 3 and 7 traced. TendIngestion 491, TendCore 141, TendSourceScan 63 green, 0 warnings, Linux. Scans: 52 files, 0 violations. 36 of 36 mutants killed. Review file committed. Pushed; no PR opened. |

### Round 3 (PR #29 review round 2: CHANGES REQUIRED, R29-R2-F1 Major, R29-R2-N1 Nit)
| Finding | What changed | Evidence |
|---|---|---|
| R29-R2-F1 (Major): `splitChunks` pipeline comparison narrowed from 42 cut sets to 5, and the dev-notes said nothing was weakened | All 42 pipeline comparisons are back: for every fixture and every cut set, the emitted titles, final drafts and outcome through `DraftPipeline` equal the one-shot run, just as in round 1. The test name now says "reader and pipeline: all 42". The false sentence in "Why the R29-N2 code change" is corrected in place, and the correction says what happened. `.serialized` and `await Task.yield()` stay. No other test was narrowed in round 2: the other changes to existing tests only added rows or checks. | `splitChunks`: 33 cases passed in 135.2 s within the full run below. |
| R29-R2-N1 (Nit, optional): the producer kept reading after a cancel | Done. `ChunkedProviderModel`'s producer loop returns when `Task.isCancelled` (test support only). | Full suite green. |

`origin/main` `e4bcdeb` (PR #30, event-driven WI-M2-09 waits) is merged in, with no rebase. The only conflict was this
file: I took `main`'s copy and appended the WI-M2-13 section at the end. If a test-time problem comes back, I will
raise it with the Reviewer before reducing any coverage.

#### Test run (round 3, merged tree)
| Command (in `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, scratch path `/tmp/b13-TendIngestion`) | Summary line |
|---|---|
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 525 tests in 63 suites passed after 158.802 seconds.` 0 warnings. Load average about 5.5. |
| AC-M2-09 scan | `AC-M2-09 scan: 55 files in total, 0 violations` |
| AC-M2-12 scan | `AC-M2-12 vocabulary scan: 55 files, 9 exempted (the list), 0 violations` |

Verification environment: Linux container only, as in rounds 1 and 2. TendCore and TendSourceScan are not changed by
this round.

#### Law check (round 3)
No change from round 2. UX-3 and P-2 pass (scans: 55 files, 0 violations). The other laws are n.a.

#### Handoff log (round 3)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted | Review round 2 CHANGES REQUIRED: R29-R2-F1 (Major), R29-R2-N1 (optional). Merge `e4bcdeb`. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (H4) | R29-R2-F1 fixed (all 42 pipeline comparisons back) and the dev-notes sentence corrected. R29-R2-N1 done. Merged `e4bcdeb`. TendIngestion 525 green, 0 warnings, scans 0 violations. Review file committed. Pushed; no PR opened. |

## WI-M2-11 — payload proof: ≥ 500-household byte-level unique sentinels (AC-M2-20 (a)) and the structural key-path and value check at concrete indices (AC-M2-20 (b)), through the router path; R28-F2, R28-F6, D11

- **Owner:** Developer  ·  **Branch:** `m2/payload-sentinels`, from `origin/main` at `f1b6458` (PR #28, WI-M2-10,
  merged)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none new. Follows ADR-0005 Decision 3 and
  ADR-0006. **Only test code and one README paragraph change**: no file under `Sources`, no fixture byte, no
  dependency.
- **Requirements:** P-2, P-3, P-4, FR-A1. **● AC-M2-20**, parts (a) and (b) (plan WI-M2-11). Review tickets R28-F2
  (prove it through the path that really sends; D11 blank-room test) and R28-F6 (compare concrete indices so an extra
  array element is caught).
- **Binding inputs:** brief AC-M2-20 (a), (b), Definitions "Cloud request" and "Duplicate shortlist", Q12, Q19;
  plan WI-M2-11 row and R-23; dev-notes WI-M2-10 D1–D17 and the round 2 tickets; `review-WI-M2-10.md` R28-F2, R28-F6;
  PO notes `po-m2-wi10.md`, `po-q21-q22.md` (PR #28), `po-m2-wi15.md` ruling 2 (key-path form).
- **Q12, Q16, Q17:** the coordinator reports (2026-11-24) that the owner confirmed the PO defaults: up to 10 titles,
  all three providers, Gemini kept. So the committed goldens and allowed lists stand; nothing is regenerated.
- **Milestone lock:** `STATUS.md` shows M2 `IN-BUILD`; WI-M2-10 (the dependency) is merged.
- **R-23 split:** not needed. Both parts are done in this one round, in one PR.

### What changed
- **New, `Packages/TendIngestion/Tests/TendIngestionTests/PayloadSentinelSupport.swift`** (test support only):
  - `SentinelHouseholdGenerator` (SplitMix64 through `DupRandom`). Each household has 0–8 rooms and 1–60 tasks (35 %
    have 25–60, so the cut at 10 is common). Every value outside allowed content is unique and random:
    - task and room IDs (and dangling task room IDs);
    - every title holds a unique token, `zq` + 6 letters with no `z` or `q`, so one token can never occur inside
      another;
    - whole-millisecond dates (2025–2035) for `windowStart`, `windowEnd`, `completedAt`, `deferred(until:)` and
      `lastTendedAt`;
    - intervals in 600…729;
    - per capture, a random `now`, one of 10 time zones and one of 10 calendars.
    Kind, effort, the three flags, dayparts, weekdays and state are random within the M1 invariants. Room names are
    never sentinels (Q19): they include `""`, `"  "`, `"\t"`, repeated names, a typographic apostrophe, quotes, a
    slash, a backslash and non-ASCII. Words are letters only, so no interval digits occur in allowed content.
  - `PayloadSentinels` gives the string sentinels of a capture:
    - each ID in 4 text forms: upper and lower case, with and without hyphens;
    - each date in the four AC forms. ISO 8601 is checked to the second, in UTC and in the capture's zone, so any
      fraction, `Z` or offset still contains it. The others are Unix seconds, Unix milliseconds and reference-date
      seconds;
    - the token and trimmed title of every task **not** on the oracle's shortlist (every task under Q12 = no);
    - the `now` forms, the time-zone identifier, and the calendar identifier in its CLDR form and its Swift case name.
    It also checks hygiene: no sentinel may occur in the allowed content itself. The interval check works on the
    decoded body: no integer is in 600…729, and no string holds a 3-digit run in 600…729. The user-content string is
    decoded and walked too. The path, query and header values are checked the same way.
  - `SentinelScanner`: a multi-needle byte search indexed on each needle's first 4 bytes. It checks about 520 needles
    per request in one pass.
  - `PayloadStructure`: the (b) check of one request against the provider's **committed** G1 head and body and the
    allowed list (see D3).
  - `PayloadRouterHarness`: one `ModelRouter` per provider with cloud on and the on-device model unavailable. Each
    capture goes `router.events(…)` → `DraftPipeline` → `PayloadBuildingCloudModel` → `CloudPayloadBuilder` → the
    recording mock transport. The harness returns the one request captured; anything other than exactly one counts
    as a problem.
- **New, `…/PayloadSentinelTests.swift`**: 8 tests, 25 cases (listed under AC coverage).
- **Changed, `Fixtures/M2/payload/README.md`:** one paragraph on how WI-M2-11 uses the goldens and lists. No fixture
  byte changed.

### Decisions the Reviewer should know (technical; product-meaning readings are flagged)
- **D1, R28-F2: option (b), an equivalence check, not a production change.** Production keeps its one sending path
  (`ModelRouter` → `DraftPipeline`, with the titles from `DraftDuplicateRules`). The proof runs through that path. For
  every capture and both Q12 answers, the property checks two things:
  - `CloudContextSelector.input` equals the independent expectation: the household's room names in order, and
    `DupOracle.shortlist` titles under yes or none under no.
  - The captured request's user content equals the same values.
  So selector = oracle = what was really sent, over 1,040 captures per provider. The households include blank,
  whitespace-only and repeated room names. Review mutant M-C is now killed (M9 below). Option (a), routing production
  through the selector, would change `DraftPipeline` for no gain in protection, so I did not take it.
- **D2, the path that sends is a test cloud model.** The real `TendAI` adapters (WI-M2-M6) do not exist yet and need
  the Mac. `PayloadBuildingCloudModel` has their shape: it takes the pipeline's `IngestionRequest`, calls
  `CloudPayloadInput(request)` and the builder, and sends the result. WI-M2-M6 should run the same `PayloadStructure`
  and `PayloadSentinels` checks on the requests its adapters give to the mock transport (ticket below).
- **D3, (b) at concrete indices (R28-F6), plus a byte frame.** For each body:
  1. `CloudRequestKeyPaths.leafPaths(ofBody:)` equals the committed list's `keyPaths[].path`.
  2. The concrete leaf map (for example `$.messages[1].content[0].text`, with empty containers as leaves) has exactly
     G1's paths outside the user content, and each value is `jsonEqual` to G1's.
  3. The bytes before and after the user-content string literal equal G1's byte for byte. This is the AC sentence
     "no household field can change any byte outside the capture, room-name and title values", taken literally.
  4. The user content parses strictly, and its concrete leaves are exactly: `$.capture`, then `$.rooms[i]` in order
     (or an empty `$.rooms`), then `$.existingTasks[i].index` = i+1 and `.title` (or an empty `$.existingTasks`).
     Its `[]` paths are inside the committed `userContentKeyPaths`.
  5. The request line equals G1's head. The header names equal the list's `auth` and `fixed` names in order, and
     G1's names. Every non-auth value equals G1's. The auth header holds the key.
  A negative test shows that an added message, an added part and an added enum element keep the `[]` path set the
  same (the gap F6 names) but are caught by step 2.
- **D4, more forms than the AC lists (stronger, not a meaning change).**
  - IDs are checked without hyphens as well.
  - Dates are also checked as ISO in the local zone.
  - The calendar identifier is checked as the Swift case name as well as the CLDR form.
  - `deferred(until:)` and a task's `roomID` are sentinels too. They are household fields outside allowed content,
    even though the AC's list does not name them.
  - The interval check covers the whole range 600…729, not only the values used.
  - String sentinels are checked in the host as well.
- **D5, the auth header value.** The AC excepts the auth value from the golden comparison. I compare it only for
  holding the key. The string sentinels are still searched in it.
- **D6, one seed, three providers, both Q12 answers.** Seed `0x0A1D_2011_0001`, 520 households, the same households
  for each provider. Each test prints the seed, and each failure message names the household index and Q12 answer.
  Long loops call `await Task.yield()` once per household.
- **D7, test-first, stated honestly.** WI-M2-11 is a proof over code that is already merged, so the new tests passed
  on their first run (they could only fail on a defect). The evidence that they detect defects is the mutant table:
  21 production mutants, each one a realistic leak or shape change. Every check in the property also has a negative
  control test that plants the defect directly.

### AC coverage
| AC (part) | Test(s) | Result |
|---|---|---|
| AC-M2-20 (a) byte-level unique sentinels | "AC-M2-20 (a): 520 seeded households × Q12 yes/no, through the router — no task or room ID, non-shortlisted title, date (four forms), now, time-zone or calendar identifier appears …; no interval 600…729 appears as a number or digits" (3 providers) | PASS (Linux). Per provider: 1,040 requests, 539,574 string sentinels; 2,972 titles sent; 136 shortlists cut at 10; all 130 intervals 600…729 used; every sentinel kind present (counts in the log line) |
| AC-M2-20 (a) the check is real | "AC-M2-20 (a) control: a sentinel planted in the body, path, query, a header name or a header value is found; an interval planted as a number or as digits is found" (3); "the sentinel scanner finds needles …" | PASS (Linux) |
| AC-M2-20 (b) structural check | "AC-M2-20 (b): 520 seeded households × Q12 yes/no, through the router — the key-path set equals the allowed list; at concrete indices every fixed value equals the golden request; the user content is exactly …; the selector gives the same input; headers equal the golden" (3) | PASS (Linux). Per provider: 1,040 requests; 365 blank and 260 repeated room names; 62 households with no room; 47/41/48 allowed paths; 102/100/104 fixed concrete leaves (Anthropic/Gemini/OpenAI) |
| AC-M2-20 (b) the check is real (R28-F6) | "R28-F6: an added message, an added part or an added enum element keeps the [] key-path set but is caught at concrete indices; …" (3); "AC-M2-20 (b): a user content with an extra room, reordered rooms, … is caught" (3); "AC-M2-20 (b) control: the structural check passes every committed golden request" (9) | PASS (Linux) |
| R28-F2 through the sending path + equivalence | the two property tests above (router path; selector = oracle = sent, both Q12 answers) | PASS (Linux) |
| D11 / Q19 blank room names sent | "D11 (Q19): empty, whitespace-only and repeated room names are sent as written and in household order, through the router, for each provider" (3) | PASS (Linux) |
| AC-M2-20 golden bytes on the Mac | unchanged (WI-M2-10 test); MS-2 B2 | not run here |

### Test runs (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths `/tmp/b11-<pkg>`, 0 warnings in every package)
| Package | Summary line |
|---|---|
| TendIngestion | `✔ Test run with 449 tests in 52 suites passed after 182.602 seconds.` (441 on `main` + 8 new; the new suite alone runs in about 47 s, and its (a) property is the longest case). AC-M2-09: `46 files in total, 0 violations`. AC-M2-12 vocabulary: `46 files, 9 exempted (the list), 0 violations`. |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 7.605 seconds.` (unchanged) |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 157.343 seconds.` (unchanged) |
| Tools/TendTools | `✔ Test run with 8 tests in 1 suite passed after 0.140 seconds.` (unchanged) |

Seed `0x0A1D_2011_0001` (printed as `0xa1d20110001`). The per-provider log lines give the counts in the AC table; the
three providers see the same households, so the household-side counts are equal.

### Mutation check
Setup:
- Scratch copy `/tmp/claude-0/b11/mut`, made with `tar --exclude=.git` from the worktree. The worktree was never
  edited.
- Mutants were applied one at a time by a script that asserts each target string occurs exactly once.
- Each run: `-Xswiftc -warnings-as-errors`, `--filter PayloadSentinelTests`, own scratch path.
- Afterwards, `diff -rq` showed the copy's `Packages` identical to the worktree's.

**21 of 21 killed; every mutant built.** Every mutant is in production code (`Sources`), along the path that sends.

| # | Mutant | Killed by |
|---|---|---|
| M1 | pipeline sends `name + " " + id.uuidString` as each room name | (a) property, (b) property, D11 |
| M2 | pipeline appends `lastTendedAt` Unix seconds to room names | (a), (b) |
| M3 | shortlist candidates include completed tasks | (a), (b), golden control |
| M4 | shortlist limit 11 (the builder cap follows it) | (a), (b), golden control |
| M5 | OpenAI: the user message twice | (b), D11, R28-F6 |
| M6 | Anthropic: a second text part | (b), D11, R28-F6 |
| M7 | Gemini: a second part | (b), D11, R28-F6 |
| M8 | builder sends the rooms reversed | (b), user-content control, D11, R28-F6 |
| M9 | selector drops blank room names (review M-C, survived in WI-M2-10) | (b) (selector = oracle), D11 |
| M10 | pipeline drops blank room names | (b), D11 |
| M11 | output cap 650 | (a) (number 650), (a) control, (b), D11, R28-F6 |
| M12 | pipeline appends the time-zone identifier to the capture | (a), (b), D11 |
| M13 | pipeline appends the calendar identifier | (a), (b), D11 |
| M14 | pipeline appends `now.ISO8601Format()` | (a), (b), D11 |
| M15 | pipeline adds `now` reference-date seconds as a room | (a), (b), D11 |
| M16 | shortlist titles not trimmed | (b), golden control |
| M17 | builder adds a fixed `X-Client` header | (b), golden control, D11, R28-F6 |
| M18 | builder sends the titles reversed | (b), user-content control, R28-F6 |
| M19 | router ignores Q12 = no (always sends titles) | (a) (every title is a sentinel under no), (b) |
| M20 | user-content index from 0 | (b), D11, R28-F6 |
| M21 | instructions say "Every 700 days" | (a) (digits in a string), (a) control, (b), D11, R28-F6 |

### Verification environment
| Check | Linux (container, `swift:6.2-noble`) | macOS / owner-run Mac | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| (a) sentinels and (b) structure over 520 households × 3 providers × Q12 yes/no, through `ModelRouter` | ✔ | not run (the suite is Foundation-only; MS-2 may repeat it with the TendIngestion suite) | n.a. | n.a. | — |
| Controls, D11, scanner | ✔ | not run | n.a. | n.a. | — |
| The real `TendAI` adapters produce the same requests | — | WI-M2-M6 (ticket below) | — | DS-2 | the adapters do not exist yet (D2) |
| Golden bytes on the Mac | — | MS-2 B2 (WI-M2-10's test) | — | — | Mac session |

### Things the reviewer should look at closely
- The generator's coverage (log line): are any household fields that can hold a unique value missing from the
  sentinel list? I added `deferred(until:)` and task `roomID` beyond the AC's list (D4).
- The byte frame (D3, step 3) relies on the first `"{\"capture\":` in the body being the user content. The fixed
  instructions come first and do not contain it (checked by the golden control), and a capture's own `{"capture":`
  would be escaped inside the literal, after its start.
- `PayloadBuildingCloudModel` stands in for the real adapters (D2).

### Known limitations / tickets
| Item | Severity | Ticket |
|---|---|---|
| Run `PayloadStructure.problems` and `PayloadSentinels` on the requests the real `TendAI` adapters give the mock transport (the same seed, at least the G1–G3 households and a sample of the generator) | — | WI-M2-M6 |
| `ds2-gated` (AC-M2-26) compares `[]` path sets only, so on device an extra element would pass. Should the harness also record value-free per-array element counts? | question (from R28-F6) | Tester / PO; unchanged by this PR |

### Open questions (built to the most literal reading; work continues)
1. **Tester / PO (R28-F6, carried):** the `ds2-gated` element-count question above. This PR closes the AC-M2-20 side
   only.
2. **Reviewer (D4):** I treated `deferred(until:)` and a task's `roomID` as sentinels, though the AC's list does not
   name them. This is stronger, not a meaning change. If the PO wants the list in the brief to name them, that is a
   wording amendment.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | n.a. | No copy or source change; AC-M2-12 vocabulary scan 0 violations. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged. The harness forces cloud only by making the on-device model unavailable, the documented route. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | Test code only; no networking (the mock transport records). AC-M2-09: 0 violations. No dependency. Fake key only. |
| P-3 Cloud AI opt-in, minimised | pass | This PR is the proof: across 3,120 requests no ID, date, interval, non-shortlisted title, `now`, time zone or calendar reaches any byte. Every byte outside the user content equals the golden request's, and the user content holds exactly the capture, the room names and ≤ 10 oracle titles. 21 of 21 leak and shape mutants killed. |
| P-4 Media not persisted | pass | Text only, in memory; nothing written. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted (H2) | WI-M2-11 Ready (WI-M2-10 merged as PR #28, `main` at `f1b6458`). Tickets R28-F2, R28-F6 and D11. Owner confirmed Q12/Q16/Q17 defaults (coordinator), so the goldens stand. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (H4) | AC-M2-20 (a) and (b) over 520 seeded households × 3 providers × Q12 yes/no, through `ModelRouter` (R28-F2), compared at concrete indices and byte frame (R28-F6); D11 test. TendIngestion 449, TendSourceScan 63, TendCore 141, TendTools 8 green, 0 warnings, Linux. AC-M2-09 and AC-M2-12: 46 files, 0 violations. Mutants 21 of 21 killed. No R-23 split. Pushed; no PR opened. |

### Round 2 (review round 1: APPROVE with 2 Minor and 4 Nit, `review-WI-M2-11.md`)
`origin/main` had not moved (still `f1b6458` when fetched), so there was no merge. The review file is committed with
this round, unchanged.

| Finding | Change |
|---|---|
| **R31-F1 Minor** | `PayloadStructure.problems` now compares **every** header value with G1's head, the auth value included. This harness always uses `PayloadFixture.fakeKey`, and G1 holds exactly prefix + that key. So (b) now pins every byte of the request. **D5 is corrected:** in round 1, "holding the key" only checked that the header was the key case, not its value. The review's RM3 is mutant M22 below. |
| **R31-F2 Minor** | Both options (i) and (ii). (i) The (a) scan now also finds encoded forms, listed below. (ii) The file header of `PayloadSentinelSupport.swift` and this note now say what (a) still does not find and that (b) covers it. The WI-M2-M6 ticket carries the same sentence. The review's RM2 is mutant M23 below, and (a) now kills it. |
| **R31-N1 Nit** | Calendars carry the Swift case name as a literal (`islamicCivil`, `ethiopicAmeteMihret`). The name is checked when it differs from the CLDR form, so the round-1 D4 claim is now true on Linux. |
| **R31-N2 Nit** | A zone the platform lacks now gives `Issue.record`, never a silent `GMT`. |
| **R31-N3 Nit** | The unused `import Synchronization` is removed. |
| **R31-N4 Nit** | Carried into the WI-M2-M6 ticket below. |

The (a) scan now finds these forms (review R31-F2):
- **Case:** ASCII letters are compared without case in both the needle and the request. This covers an upper-case or
  mixed-case token, ID, identifier or title.
- **JSON-escaped:** with and without `\/`, and with every non-ASCII scalar written as `\u` escapes. This also covers
  titles that contain a tab or newline, which the body writes as `\t` or `\n`.
- **Percent- and form-encoded:** `%2F`, and both `%20` and `+` for a space.
- **Dates:** each date also as ISO 8601 to the minute and as the date alone, in UTC and in the local zone.

**What (a) still does not find, and relies on (b) for:** other date layouts (compact `yyyyMMdd`, locale-formatted,
days or hours since an epoch), base64 or any hash, a value split across fields, and a reworded value. In this harness
(b) pins every byte, so these are caught. The same mutant table shows it.

Hygiene, the check that no sentinel occurs in the allowed content, now uses the same caseless comparison. Per provider
there are now **1,115,215 string sentinels** over the 1,040 requests (round 1: 539,574). The property's label check
also requires the new forms: date-only, minute, `\/`, percent-encoded, form-encoded and `\u`-escaped.

**Run time.** Making a formatter per date form made the suite 8× slower (391 s). `ISOFormatters` now makes one per zone
and layout per capture, and a plain alphanumeric sentinel skips the variant work. The new suite now takes about 74 s.

**New test:** "R31-F2: a sentinel is found JSON-escaped (with \/ and as \u escapes), percent- and form-encoded, in
another letter case, and a date at minute precision or as the date alone" (3 providers, 16 plants each, in the body
and in a header value). The scanner test gains caseless cases, and a check that non-ASCII letters are still compared
exactly (`É` ≠ `é`).

#### Mutation check, round 2: round 1's results were not trustworthy, so they are replaced
The Reviewer is right. My round-1 script restored the scratch copy with `tar`, and `tar` keeps each file's original,
older mtime. SwiftPM's incremental build may then skip the restored file, so an earlier mutant could stay compiled into
later runs. For example, M1's room-ID change in `DraftPipeline.swift` could have stayed in M2…M21 if the restore was
not rebuilt. **The round-1 kill table cannot count as evidence.** The round-1 mutants are not trivially independent:
several share `DraftPipeline.swift`, and a mutant that only some tests kill could have been reported killed because of
a leftover.

Round 2 rerun (`/tmp/claude-0/b11/run2.sh`):
- A fresh scratch copy and a fresh build directory (`/scr/mut2`).
- Before **each** run: delete the copy's `Packages`, extract the worktree's again, `touch` every `.swift` file (so
  every file is newer than any earlier build), then apply the mutant.
- Each line records how many files differ from the worktree, which is 0 for the baseline and 1 or 2 for a mutant.
- A **no-mutant baseline (M0) runs first and last**. It must pass, which shows that no mutant stays compiled in.
- Afterwards, `diff -rq` showed the copy identical to the worktree.
- All 21 round-1 mutants were rerun against the round-2 tests, plus M22–M26 (new, from the review and R31-F2).

**Result: 26 of 26 killed; every mutant built. M0 passed first and last.** All of M1–M21 are again killed by the same
tests as in round 1, now with a clean rebuild each time, so the round-1 claims hold. The difference is that they are
now evidence.

| # | Mutant | Killed by |
|---|---|---|
| M0 | none (baseline, first and last) | — (all 9 tests pass both times) |
| M1–M21 | the round-1 mutants (table above) | the same tests as in round 1, each killed again |
| M22 | auth prefix `"Bearer  "` (review RM3; round 1: survived this suite) | (b) property, golden control, D11, R28-F6 (R31-F1) |
| M23 | pipeline appends the first room's `lastTendedAt` as date-only ISO (review RM2; round 1: passed (a)) | **(a)** property (R31-F2), (b) property |
| M24 | shortlist includes completed tasks, sent upper-cased | **(a)** property (caseless), (b), golden control |
| M25 | pipeline appends `now` at minute precision | **(a)** property, (b), D11 |
| M26 | pipeline adds the time-zone identifier percent-encoded (`%2F`) as a room | **(a)** property, (b), D11 |

#### Verification environment (round 2)
| Check | Linux (container, `swift:6.2-noble`) | owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| (a) with encoded forms, (b) with the auth value, the new control test, N1–N3 | ✔ | not run | n.a. | n.a. |
| Mutants M0, M1–M26, with `touch` after each restore | ✔ (before the merge of `main`; see the merge note) | n.a. | n.a. | n.a. |

#### Tickets (round 2)
| Item | Owner |
|---|---|
| **WI-M2-M6 (updated):** run `PayloadStructure.problems` and `PayloadSentinels` on the requests the real `TendAI` adapters give the mock transport. (a) finds raw, caseless, JSON-escaped, `\u`-escaped, percent- and form-encoded forms, and minute-precision and date-only ISO. It does **not** find other date layouts, base64, hashes, split or reworded values. In this suite (b) covers those by pinning every byte against the golden, so where (b) is weaker or there is no golden, that gap must be closed there. **R31-N4:** the interval digit scan includes the auth header value. With a real key (WI-M2-M6, DS-2) a key containing `650` is a false positive. Decide with the PO whether "header values" in AC-M2-20 (a) includes the auth value; if it does, use a fake key. | WI-M2-M6; PO (N4) |

#### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | n.a. | No copy or source change. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | Test code only; the mock transport records; no dependency; fake key only. |
| P-3 Cloud AI opt-in, minimised | pass | (b) now pins every request byte (auth value included). (a) also finds encoded and case-changed leaks. 26 of 26 mutants killed, with clean rebuilds. |
| P-4 Media not persisted | pass | Text only, in memory. |

#### Merge of `main` and test run on the merged tree
- `main` moved to `e4bcdeb` (PR #30, WI-M2-14) during this round. I merged it with `git merge --no-ff` (no rebase, no
  force-push). The only conflict was `dev-notes.md`: I took main's file and appended this section at the end.
- PR #30 changed `DraftPipeline.swift` in a comment only. The code lines that M1, M2, M10, M12–M15, M23, M25 and M26
  mutate are unchanged, so the mutant results above (run before the merge) still apply to the payload path. PR #30
  also changed `RoutingSupport.swift`, which the harness uses, so I reran the whole TendIngestion suite on the merged
  tree.
- TendIngestion on the merged tree (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, scratch `/tmp/b11-ing-r2`):
  `✔ Test run with 484 tests in 58 suites passed after 148.965 seconds.` (main's tests plus WI-M2-11's 9), 0 warnings. AC-M2-09: `49 files in total, 0 violations`.
  AC-M2-12 vocabulary: `49 files, 9 exempted (the list), 0 violations`.
- Not rerun in this round: TendSourceScan, TendCore and TendTools. This round changed none of them; they were green in
  round 1, and PR #30's own checks cover its changes.

#### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Reviewer (via Orchestrator) | Developer | accepted (round 1: APPROVE) | 2 Minor (F1 auth value, F2 encoded forms), 4 Nit (N1–N3 here, N4 to WI-M2-M6). Re-check the mutants: a `tar`/`mv` restore keeps old mtimes. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1 and F2 fixed (both options for F2), N1–N3 fixed, N4 and the F2 gap sentence ticketed to WI-M2-M6. Round-1 mutant table withdrawn as evidence; rerun with `touch` and M0 baselines: 26 of 26 killed (M1–M21 again, plus M22–M26, which include the review's RM2 and RM3). Merged `main` `e4bcdeb`. TendIngestion 484 green on the merged tree, 0 warnings; AC-M2-09 and AC-M2-12 0 violations. |

## WI-M2-16 (Developer part) — cloud instructions use the PO's item meanings (GR-1, GR-2), fixed client headers and transport-set list (GR-3), OpenAI system content as a part array (GR-5); goldens regenerated

- **Owner:** Developer  ·  **Branch:** `m2/cloud-instructions`, from `origin/main` at `1d1caa3`  ·  **PR:** not opened
  (the Orchestrator opens it)  ·  **ADRs:** none new (decision note DN-16-1 below; a fixed-member shape change under
  PO WI-M2-10 ruling 3, not architectural).
- **Requirements:** FR-A1, FR-B2, P-3, UX-3. **AC-M2-20** (golden bytes, headers), **AC-M2-22** (Headers bullet, Linux
  part), **AC-M2-26** (ds2-gated key-path subset), AC-M2-14 freeze conditions (a), (b), (c) of PO WI-M2-16 ruling 1.
- **Binding inputs:** PO `po-m2-wi16.md` rulings 3, 4, 5, 9, 10 and "Changes required" (Developer 1, 2, 4);
  `po-m2-wi10.md` rulings 3 (fixed members), 4 (headers), 7 (models); Tester review GR-1…GR-5 in
  `eval-composition.md` (branch `m2/eval-fixtures-freeze`); `po-m2-wi11.md` ruling 1 (element counts).
- **Milestone lock:** `STATUS.md` shows M2 in build; this is WI-M2-16 freeze-prerequisite work inside M2.

### What changed (three commits, one concern each, each green on its own)
1. **`17bd84a` GR-1, GR-2 + rulings 5 and 9** — `CloudOutputSchema.swift` `CloudInstructions.text`: the old room,
   effort and combined isCritical/isDeepClean/isWeatherDependent lines are replaced by the PO's five exact sentences,
   one per line (room, effort, isCritical, isDeepClean, isWeatherDependent). No other instruction line changed. 9 golden
   bodies regenerated; heads and allowed lists byte-identical (key paths unchanged).
2. **`558bb03` GR-3** — `CloudProviderTable.clientHeaders` = `User-Agent: Tend`, `Accept-Language: en-US`, appended to
   every provider's fixed headers (order: auth, provider headers, `User-Agent`, `Accept-Language`).
   `CloudAllowedKeyPaths.transportSetHeaders` = `Content-Length`, `Host`, `Accept`, `Accept-Encoding`, `Connection`
   (role `derivedByTransport`, left out of the Linux header comparison). 9 heads gain two lines; the 3 allowed lists
   change only in `headers`. The PO note puts GR-3 under WI-M2-M4 but rules "add … to all three allowed lists …
   Before freeze", so the Linux half (builder, lists, goldens, tests) is done here; the Darwin `URLProtocol` proof that
   the explicit values replace the system defaults stays with WI-M2-M4 (ticket below).
3. **`12bd68c` GR-5** — OpenAI system message sent as `[{"type":"text","text":<instructions>}]` (DN-16-1). The 3 OpenAI
   bodies change only in that shape; `allowed-key-paths-openai.json` loses `$.messages[].content`; Anthropic and
   Gemini files are byte-identical.
- `Fixtures/M2/payload/README.md`: one sentence on the header roles.

### DN-16-1 (GR-5 technical choice): no allowed key path is both a leaf and a container
- **Problem (GR-5):** OpenAI `$.messages[].content` was a string leaf (system) and the parent of
  `$.messages[].content[].text` (user). A user content flattened to a string sent only allowed paths, so the device
  `ds2-gated` subset check could not see it.
- **Options:** (A) send the system content as a text-part array too; (B) record a value type per path in the results
  file. (B) changes results v1, the schema pattern, the scorer and the harness recorder (AC-M2-28), a larger change on a
  format the Tester has reviewed. (A) is one builder line, Linux-side, a fixed protocol member value under PO WI-M2-10
  ruling 3 (constant, no household data, provider protocol shape, gives no extra reach, in the goldens and lists, N-3
  clean). OpenAI Chat Completions documents the system message `content` as a string or an array of text parts.
- **Decision:** (A). Invariant pinned by a test for all three providers: no allowed path is a leaf and the prefix of
  another path. Consequence: the erased path `$.messages[].content[].text` is shared by the fixed instructions
  (`$.messages[0]`) and the user content (`at` = `$.messages[1].content[0].text`); the Linux structural check
  (concrete indices) still pins the instructions byte for byte.
- **How we would know this was wrong:** L2a (owner live check) returns a 4xx for the array system content. Then revert
  `12bd68c` (goldens and list regenerate back) and take (B).
- **Not covered by DN-16-1:** extra elements (PO WI-M2-11 ruling 1, element counts) remain the Planner's open ticket;
  DN-16-1 only makes the string-vs-array shape visible.

### AC / ruling coverage
| Item | Test(s) | Result (Linux) |
|---|---|---|
| GR-1, GR-2, rulings 3/4/5/9 exact lines | `PayloadBuilderTests` "PO WI-M2-16 rulings 3, 4, 5, 9 (GR-1, GR-2; FR-B2, FR-A1): … exact sentences …" (each line exact, in order between `kind` and `time`, old wording gone, one line per field, no digit, no banned token) | pass; red before the change |
| Instructions in all slots, N-3, UX-3 | existing "ADR-0005 Decision 3: the instructions are fixed …", "N-3: no decimal string 600…729 …", "PO WI-M2-12 ruling 2 …" | pass |
| AC-M2-20 golden bytes | existing "AC-M2-20 golden bytes: 3 households × 3 providers …" on the regenerated files | pass |
| GR-3 builder | existing "the provider table …" and "AC-M2-20 headers: every header value except the auth header is fixed" with the hand-written table updated to both headers and values | pass; red before |
| GR-3 lists | new `PayloadGoldenTests` "GR-3, PO WI-M2-10 ruling 4 and WI-M2-16 ruling 10 …" (names and roles in order, exact transport-set list, builder never sends a transport-set header, values `Tend` / `en-US`) | pass; red before. Mutant `Accept-Language: en-GB` killed (7 tests fail) |
| GR-5 | new "GR-5 …: no allowed key path is both a leaf and a container …" and "GR-5 …: a system or user message whose content parts become a plain string sends a key path outside the allowed list …" (OpenAI system and user, Anthropic user, Gemini system and user) | pass; both red on the string system content (the mutant) |
| AC-M2-20 (a), (b) (WI-M2-11) | existing sentinel and structural suites on the new goldens and lists | pass |
| `tend-payload-dump --outcome-sample` | output compared with `cmp` to the 3 G1 bodies | identical |

### Golden diff summary
- Bodies (9): only the instructions leaf changes (`$.system`, `$.systemInstruction.parts[0].text`,
  `$.messages[0].content` → `$.messages[0].content[0].text`), checked leaf by leaf against `1d1caa3`. Sizes grow by
  446 bytes (Anthropic, Gemini) and 471 bytes (OpenAI: the part wrapper adds 25).
- Heads (9): `+User-Agent: Tend`, `+Accept-Language: en-US` after the provider's headers.
- Allowed lists: `headers` gain the 2 fixed and 3 transport-set names (all three); `keyPaths` byte-identical for
  Anthropic and Gemini; OpenAI loses `$.messages[].content` (GR-5) and gains nothing. `userContentKeyPaths` unchanged.
- N-3: no 3-digit window of any digit run in the 18 golden files or 3 lists falls in 600…729 (script and Swift test).
  Instruction digit runs are `1`, `12`, `2`, `1` (unchanged lines). Banned tokens (overdue, late, missed, failed,
  behind, penalty, debt, streak, lateness) in the instructions: none.
- SHA-256 (first 12 hex) for the Tester: bodies g1 a/g/o `0530a6105c2c` `7be08e830d1f` `e27887c3755f`, g2
  `2023877cc0a8` `74619173b3a7` `a8455b6bf511`, g3 `a4c4333e2673` `81f33f96777a` `ff8733432525`; heads a/g/o
  `5e0624bde48a` `6f64aadbfc47` `5b74a96d5a84`; lists a/g/o `0c642484511e` `9051458c0aed` `72f48767fa58`.
- Regenerated with `TEND_PAYLOAD_GOLDEN_OUT=<dir> swift test … --filter PayloadGoldenTests` once per commit (the
  repository's tool; no byte hand-edited). The final files equal a single-pass regeneration of the final tree.

### Verification environment
| Check | Linux (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`) | owner-run Mac | Simulator | Device |
|---|---|---|---|---|
| TendIngestion after each commit | ✔ 535 / 536 / **538 tests in 64 suites passed** (baseline at `1d1caa3`: 534), 0 warnings; AC-M2-09 `55 files … 0 violations`; AC-M2-12 `55 files, 9 exempted, 0 violations` | not run | n.a. | n.a. |
| TendCore | ✔ 141 tests in 18 suites | not run | n.a. | n.a. |
| TendSourceScan | ✔ 63 tests in 4 suites | not run | n.a. | n.a. |
| Tools/TendTools build + tests | ✔ build; 8 tests | not run | n.a. | n.a. |
| Explicit headers replace Darwin defaults on the wire | not verifiable on Linux | WI-M2-M4 | — | — |
| Providers accept the regenerated bodies (incl. OpenAI array system content) | not verifiable | — | — | owner L2a (GR-4) |

### Things the reviewer should look at closely
- The instruction text: compare each new line with `po-m2-wi16.md` rulings 3, 4, 5, 9 word for word (the test pins
  them, but the test's constants were also typed by me). Source uses `\` line continuations; the test checks the
  resulting single lines.
- DN-16-1: the OpenAI erased path is now shared by fixed instructions and user content; role list says `userContent`
  only. The concrete-index check still pins the instructions; confirm this is acceptable for AC-M2-26.
- Header order (provider headers, then `User-Agent`, `Accept-Language`) is my choice; the PO named values, not order.

### Known limitations / tickets
| Item | Severity | Ticket |
|---|---|---|
| **WI-M2-M2 (Mac, TendAI):** the on-device `@Generable` `@Guide` descriptions for `isCritical` (same sentence as the cloud line: one shared constant if the macro takes one, else a test comparing the strings), `room`, `effort` and `isWeatherDependent` (same meaning) per PO WI-M2-16 rulings 3, 4, 5, 9; P-1 and P-3 asked the same thing. `TendAI` is not in this repo's Linux packages, so not done here. | Major for freeze parity | WI-M2-M2 |
| **WI-M2-M4 (Mac):** `URLProtocol` test that the transport sets `User-Agent: Tend` and `Accept-Language: en-US` explicitly on every request and sends no header outside the lists; mutant dropping either; Reviewer confirms explicit values replace system defaults. | required before freeze | WI-M2-M4 |
| PO WI-M2-11 ruling 1: per-array element counts in results v1 and `ds2-gated`. Not done here; DN-16-1 does not replace it. | open | Planner |
| PO WI-M2-16 "Changes" 4: Linux composition check and `MANIFEST.sha256`. Not in this task's scope. | open (freeze condition (e)) | Developer, next |
| L2a must run on these regenerated bodies (GR-4), including the OpenAI array system content. | blocking freeze | Owner |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; the instructions ask the user nothing. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | New lines hold no banned token (test); "critical" means waiting has a real cost, no alarm wording. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Routing unchanged; on-device `@Guide` parity ticketed to WI-M2-M2. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No dependency; fake key; fixtures invented. |
| P-3 Cloud AI opt-in, minimised | pass | All changes are fixed members (constant, no household or device data, N-3 clean). The fixed `User-Agent` and `Accept-Language` remove the device's languages and versions from requests. GR-5 makes a shape change visible on device. |
| P-4 Media not persisted | n.a. | Text only. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted | WI-M2-16 Developer part: PO rulings 3, 4, 5, 9, 10; GR-1, GR-2, GR-3, GR-5; regenerate goldens. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent | 3 commits; TendIngestion 538 green, 0 warnings; TendCore, TendSourceScan, TendTools green. |
| 2026-11-24 | Developer | Acceptance Tester (via Orchestrator) | sent | Verify the regenerated bodies for GR-1 and GR-2 (only the Tester lifts GR-1); re-review GR-3 lists and GR-5 (OpenAI key-path list changed). |

---

## A-F1 fix: subset profiles take exactly their fixed input IDs and modes (PO ruling F4)
Branch `m2/scorer-subset-ids` (from `main` `1d1caa3`). Defect A-F1 (Tester, `m2/eval-fixtures-freeze` acceptance draft,
AQ-2), severity Minor. Rulings F3 and F4 in `po-m2-wi16.md` ("Follow-up rulings (PR #32 and acceptance)").
Requirement IDs: AC-M2-11, AC-M2-25, AC-M2-14 (scorer log as evidence), FR-A1.

### What changed
- `TendIngestion/Eval/EvalProfile.swift`: new `EvalSubsetInput` (ID + mode) and `EvalProfile.subset`, which pins the
  subsets in the profiles (not an argument): `ds1-offline` = in01 (text), in02 (voice), in10 (voice) (AC-M2-11);
  `ds2-offline` and `ds2-online` = in08 (voice), in16 (voice) (AC-M2-25); `ds1-gated`, `ds2-gated`, `info` = none.
  `EvalScorer.run` compares the file's distinct (input ID, mode) pairs with the subset after the file is read and
  before scoring; any difference throws the new `EvalScoringError.subsetMismatch(EvalSubsetMismatch)`. Its `reason`
  names the profile, the AC, the subset and the file's inputs, then what is not in the subset, what is not in the file,
  and each mode difference. A voice retake (attempt 2) does not count as another input.
- The old count-only check (`3 inputs, 2 voice` / `2 inputs, 2 voice`) is replaced by a second control in the profile:
  `inputs in01 (text), in02 (voice), in10 (voice) (AC-M2-11): file has …`. It prints the IDs and modes in the scorer
  log for every subset run, and fails if `evaluate` is reached without the `run` check.
- `TendTools/EvalScoreCommand.swift`: the mismatch exits 2 as `file rejected: <reason>`; usage text lists the subsets.
  `Package.swift`: the test target also depends on `TendIngestion` (to build the A-F1 files; no new package).
- Checked by hand against the Tester's frozen fixtures (`origin/m2/eval-fixtures-freeze`,
  `Fixtures/M2/eval/inputs.json`): in01 text, in02 voice, in10 voice, in08 voice, in16 voice. Matches AC-M2-11
  ("3 eval inputs … 2 voice, 1 text") and AC-M2-25 ("2 voice inputs"). `Fixtures/M2/eval/` not touched.

### AC → test
| Item | Test |
|---|---|
| Subsets pinned, whole-set profiles have none | `EvalProfileTests` "A-F1: the subsets are pinned in the profiles (PO ruling F3) …" |
| Fixed subset scored and passes (3 profiles) | "A-F1: the fixed subset is scored and passes" (3 cases) |
| Right count, wrong ID; wrong mode; too few; too many; whole set → refused with the exact mismatch and a calm reason | "A-F1: any other file is refused (exit 2) …" (16 cases: 7 wrong-ID right-count, 4 wrong-mode, 5 count) |
| Second control in the profile | "A-F1: the profile check also holds the subset (second control) …" |
| Scorer log prints IDs and modes | "A-F1: the scorer log prints the input IDs and modes of a subset run" |
| AC-M2-11 / AC-M2-25 per-input rules on the fixed IDs | `ds1Offline`, `ds2Offline`, `ds2Online` (same assertions as before, now on in01/in02/in10 and in08/in16; the 4-input and text-input files are now refusals) |
| Tool exit codes and messages | `TendToolsTests` "tend-eval-score (A-F1): the fixed subset is scored (exit 0 or 1, not 2) …" (3 cases), "… any other input set exits 2 with a plain reason …" (7 cases: wrong ID right count and wrong mode for each profile, plus the whole self-test file), "… the whole-set profiles take any input set" |

The synthetic eval in `EvalProfileTests` now uses the frozen fixtures' modes (was: odd numbers voice); `flipped` makes
the wrong-mode fixtures. No test was removed, skipped or loosened; the count-only failures became exit-2 refusals.
Mutation check: with the `run` guard disabled (`|| true`), 18 issues in `EvalProfileTests` (every refusal case, the
4-input and text-input refusals); restored and rerun green.

### Verification environment
| Check | Linux (container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`) | macOS CI | Simulator | Device |
|---|---|---|---|---|
| TendIngestion (incl. AC-M2-09 and AC-M2-12 source scans) | ✔ `Test run with 539 tests in 64 suites passed` (5 new tests), 0 warnings | not run | n.a. | n.a. |
| TendTools | ✔ `Test run with 11 tests in 1 suite passed` (3 new tests), 0 warnings | not run | n.a. | n.a. |
| Mutation (guard off) | ✔ killed | n.a. | n.a. | n.a. |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Tool only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No app copy. Reason text checked by test for the banned words. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | Scorer is Linux-side; AC-M2-11 subset identity now proven by the tool. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No dependency, no network; the test target dependency is an in-repo package. |
| P-3 Cloud AI opt-in, minimised | n.a. | No request change. |
| P-4 Media not persisted | n.a. | Text files only. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | PO (via Orchestrator) | Developer | accepted | F4: fix the tool for A-F1. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent | Subsets pinned; other files exit 2 with a plain reason; log prints IDs and modes. Only the Tester closes A-F1; S5/S7 stay as second controls. No PR opened (Orchestrator to open). |

### A-F1 round 2 (review `review-A-F1.md`, round 1 APPROVE: F1 Minor, N1, N2)
- **F1:** `EvalProfileTests` (TendIngestion, which CI runs) now covers what only `TendToolsTests` covered:
  "A-F1 (review F1): a voice retake of in02 … is one input" (in02 attempts 1 and 2: scored, passes, attempt 2 scored,
  log line; a retake outside the subset is still refused) and "A-F1 (review F1): the exact reason text for each note
  kind" (5 cases: both notes, "not in the subset" only, "not in the file" only, two mode notes). `Synthetic.request`
  gained `retakes:` (a no-draft `noModel` attempt 1, then the edited attempt as attempt 2 with a reason).
  Reviewer mutants rerun on `EvalProfileTests` alone (restore with `cp` + `touch`): M4 (no retake dedupe) 1 issue,
  M7 (no mode note) 2, M8 (no "not in the file") 3, M9 (no "not in the subset") 3; M0 baseline green. All killed.
- **N1:** the `ds2Online` text-input case asserts `found` (`in01 (text)`, `in08 (voice)`) and the exact reason.
- **N2:** `subsetAC` is `String?`, nil for `ds1-gated`, `ds2-gated`, `info`; test "A-F1 (review N2) …".
- **Merge:** `git merge --no-ff origin/main` (`368bb9e`, PR #32). Only conflict: `dev-notes.md`; took main's file and
  appended the A-F1 sections at the end.
- **Merged tree** (`swift:6.2-noble`, `-Xswiftc -warnings-as-errors`): TendIngestion `✔ Test run with 546 tests in
  64 suites passed` (main's 538 + 8 A-F1), 0 warnings; AC-M2-09 `55 files in total, 0 violations`; AC-M2-12
  `55 files, 9 exempted (the list), 0 violations`. TendTools `✔ Test run with 11 tests in 1 suite passed`, 0 warnings.
  macOS CI, Simulator, device: not run.
- Law check unchanged from round 1 (test code and an internal optional only).

| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Reviewer (via Orchestrator) | Developer | accepted (round 1: APPROVE) | F1 Minor, N1, N2. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F1, N1, N2 fixed; M4, M7–M9 now killed in TendIngestion; merged `main` `368bb9e`; 546 + 11 green. |

## WI-M2-16 (Developer part 2) — Linux composition check on the real eval fixtures; freeze state and MANIFEST.sha256 verifier (no manifest yet)

- **Owner:** Developer  ·  **Branch:** `m2/eval-fixtures-freeze` (merged `origin/main` at `368bb9e`, PR #32, with
  `--no-ff`; no conflict)  ·  **PR:** not opened (the Orchestrator opens it)  ·  **ADRs:** none (tests only; no
  dependency; the SHA-256 helper is test code, `TendIngestion` stays Foundation-only).
- **Requirements:** **AC-M2-14** (fixture-composition check on Linux; "committed, with a SHA-256 manifest, and
  frozen"), brief rubric Q3 "Composition", brief "Eval scoring rules" (Fixed IDs, Distinguishable targets), plan "Eval
  harness ID generator" (version-4 fixture UUIDs; AC-M2-28), N-3 (AC-M2-20), UX-3 (AC-M2-12), FR-A1.
- **Binding inputs:** PO `po-m2-wi16.md` ruling 1 (approved hashes; condition (e) "the Developer's Linux composition
  check passes"; condition (d) L2a), rulings 2, 5, 7, 8, 9 and follow-up F3 (subsets); the Tester's C1–C12 table and
  "Fixture rules I applied" 1–9 in `eval-composition.md` (v3); plan WI-M2-16 row and "Fixtures hash".
- **Not changed:** `Fixtures/M2/eval/inputs.json`, `household.json`, `golden.json`, `eval-composition.md`,
  `acceptance.md` (Tester-owned). No source file. No `MANIFEST.sha256` (the freeze waits for L2a).

### What changed (tests only, `Packages/TendIngestion/Tests/TendIngestionTests/`)
- **`EvalCompositionSupport.swift`** — `EvalCompositionCheck.violations(_:)`: a pure function of the three files'
  bytes returning every violation with a rule ID and a kind (`rule` = the Q3/brief threshold, `pin` = the exact value
  the Tester tabled for PO approval, `tag` = a composition tag that disagrees with the data). It uses the real code:
  `EvalFixtures` (the WI-M2-15 reader), `DuplicateShortlist.entries`, `LocalWordMatch.target`, `EvalScorer.bestTarget`
  / `targets` / `draftText` / `satisfies`, `Keywords`, `BannedTokens`, `TextFolding`. Also a test-only SHA-256 (FIPS
  180-4 vectors) and `EvalManifest` (render, verify, the documented command).
- **`EvalCompositionTests.swift`** — real fixtures pass; each of 25 rule IDs passes on its own; 63 negative controls
  (each a mutated in-memory copy, re-written canonically; nothing touches disk); every rule has ≥ 1 control; an identity
  round trip passes (the mutation writer adds nothing); the digit-run and whole-token readings; no `EvalIDGenerator` ID
  equals a fixture ID.
- **`EvalFreezeTests.swift`** — PO-approved SHA-256 pins of the three files; freeze state; manifest verifier with 8
  negative controls; the documented command equals the in-memory render (runs `sha256sum`, stdout only); the committed
  manifest verifies (skipped, with its reason, until it exists).

### What the composition check covers (rule → what is checked; threshold and tabled value both)
| Rule | Check (on `Fixtures/M2/eval` as committed) | Negative controls |
|---|---|---|
| C1 | 20 inputs; IDs in01…in20 in order | in20 removed; in01 renamed |
| C2 / C3 | ≥ 8 voice / ≥ 8 text; pinned 10 / 10 lists | 3 voice→text (7); 1 voice→text (pin); same for text |
| C4 | 10–80 whitespace words each; pinned per-input counts (21–35) | 9 words; 81 words; +1 word (pin) |
| C5 | ≥ 1 oneOff, recurring, restock, weather-dependent item; pinned 36 / 12 / 10, 12 weather items | no restock; no weather; one recurring→oneOff (pin) |
| C6 | ≥ 5 weather inputs; pinned 9 inputs, 12 items; `weather` tag = data | 3 inputs; one item cleared (pin); tag removed |
| C7 | ≥ 3 critical inputs; pinned the 8 critical keys (bills, insurance, expiring food, smoke alarms; PO ruling 3) and 5 inputs; tag = data | 2 inputs; g18-soup cleared (pin); tag added |
| C8 | ≥ 3 deep-clean inputs; pinned 5 inputs, 6 items; tag = data | 2 inputs; g05-grout cleared (pin); tag removed |
| C9 | ≥ 5 existing-task inputs; pinned 15 inputs, 17 existing / 41 create; tag = data | none existing; g17-pods→create (pin); tag removed |
| C10 | ≥ 3 repeat inputs; pinned in03, 06, 12, 18; each says the same word of every match group of one of its golden items twice (PO ruling 8) | 2 inputs; 3 (pin); in03's second "milk" changed |
| C11 | ≥ 4 filler/self-correction inputs; pinned 10; the tag = inputs saying "um"/"uh"; self-corrections ("no wait", ", no,") pinned in02, 08, 14, 16, 20 | 3 inputs; 9 (pin); in04 loses "uh"; in20 loses its correction |
| C12 | N ≥ 50, ≥ 1 per input; pinned N = 58, 2–3 per input | in05 empty; N = 49; N = 57 (pin) |
| TAG | only known tags; `newRoom` ⇒ a new-room item; `completedTaskSaidAgain` ⇒ a create item whose phrase satisfies a completed task | unknown tag; two wrong tags |
| HH | 9 rooms, 19 tasks, states 13 active / 1 maintenance / 1 resurfaced / 1 deferred / 3 completed | t-oven made active |
| SUB | PO F3 subsets exist with their modes: in01 text, in02, in10, in08, in16 voice | in10 made text |
| F1 | every room and task UUID is version 4 with the RFC variant (so the version-8 `EvalIDGenerator` never yields one) | version 8; non-RFC variant |
| F2 | no ASCII digit run in the raw bytes of any of the three files has a substring of value 600…729 (N-3), ignored members included | "1650"; "0700" |
| F3 | no banned whole token (`BannedTokens.all`) in the raw bytes of any file | "late"; "Overdue" title |
| F4 | match-group tokens are single keywords (the reader's `tokenNotKeyword`) | stop word; unfolded token |
| F5 | every golden item has a `referencePhrase` that is words of its input; as a draft text, its best target under the scorer's own rule is the item (create) or its seeded task (existing) | phrase not in input; missing; create and existing phrases pointed elsewhere |
| F6 | for each input the real duplicate shortlist of its text has < 10 entries (pinned ≤ 6); each `existing` item's task is not completed and is on its input's shortlist; no create item's phrase is merged by the local word-match floor (with its golden room) | task retitled off every shortlist; existing→completed task; floor merge; shortlist at cap |
| F7 | an existing item's kind, room, effort and three flags equal its seeded task | effort changed |
| F8 | `existing(room)` only when the input says the room's name (PO ruling 2); a new room is named in the input, is not an existing room, and the four new rooms are pinned | unnamed room; new = existing; renamed (pin) |
| F9 | deep clean ⇒ high effort (ruling 5); weather-dependent ⇔ the phrase says rain/raining/dry/sun/sunny (ruling 9); deep clean ⇔ the phrase says "deep" | each broken |
| READ | the WI-M2-15 reader accepts the files | unknown seeded key |
| (pin) | SHA-256 of `inputs.json`, `household.json`, `golden.json` = the PO ruling 1 values `b32e45af…`, `089a22bd…`, `882c2906…` (full hashes in the test) | one byte flipped |

Not machine-checked (Tester judgement, recorded so the Reviewer does not assume it): en-US phrasing (rule 10), the
meaning of each critical item (pinned by key, not derived), the "natural title" half of the Tester's rule 5 (no natural
titles are in the fixtures; I use the `referencePhrase`, which is what the brief names), effort beyond the deep-clean
case.

### Freeze design (AC-M2-14; the manifest is not written)
- **Documented command** (no manifest subcommand exists in `Tools/TendTools`; the scorer already takes the hash from
  `sha256sum`, plan "Scoring tool and command"), from the repo root:
  `cd Fixtures/M2/eval && LC_ALL=C sha256sum golden.json household.json inputs.json results-v1.schema.json > MANIFEST.sha256`
  (Mac: `shasum -a 256` with the same names writes the same format). It lists every file in the directory except the
  manifest (plan "MANIFEST lists the SHA-256 of every fixture file"; the schema is included, plan layout row). The
  string is `EvalManifest.command`; a test parses it, checks its names are exactly the directory's files, runs it
  without the redirection and compares the output byte for byte with the in-memory render.
- **Honest state, not a silent pass.** `EvalFreeze.declaredFrozen = false` is the one declaration. The test "AC-M2-14
  freeze state: NOT frozen yet …" asserts the manifest exists **exactly** when declared frozen, and that the Tester's
  `eval-composition.md` Status bullet says "Not frozen" exactly when not frozen. So adding the manifest without flipping
  the flag fails, flipping the flag without the manifest fails, and a status that disagrees fails. The test that
  verifies the committed manifest is reported as **skipped** with "not frozen yet: no MANIFEST.sha256 (waits for L2a, PO
  ruling 1)", never as a pass.
- **To freeze** (after L2a and the PO's go): run the command, set `declaredFrozen = true`, and the Tester updates the
  Status bullet, in one commit. The approved-hash pins stay; a later data change needs a PO decision in `DECISIONS.md`
  and a pin update in the same commit.

### AC → test
| AC / rule | Test |
|---|---|
| AC-M2-14 composition (Q3 C1–C12, F1–F9) | `EvalCompositionTests` "AC-M2-14: Fixtures/M2/eval as committed passes every composition rule …", "… each rule, threshold and tabled value, holds …" (25 cases), "… every rule refuses its mutated copy (negative controls)" (63 cases), "… every rule has at least one negative control" |
| AC-M2-28 / plan ID generator | "AC-M2-28 + plan ID generator: no EvalIDGenerator ID (version 8) can equal a fixture ID (version 4)" |
| PO ruling 1 approval | `EvalFreezeTests` "PO ruling 1: … have the PO-approved SHA-256 …" (3 cases) + negative control |
| AC-M2-14 manifest and freeze | "AC-M2-14 freeze state: NOT frozen yet …", "… a manifest rendered from the real files verifies …", "… manifest verifier, negative controls …" (7 cases), "… a fixture changed after the manifest was written is refused", "… the documented manifest command writes exactly the in-memory render …", "… MANIFEST.sha256 verifies …" (skipped until frozen) |

### Verification environment
| Check | Linux (Docker `swift:6.2-noble`, Swift 6.2.4) | macOS CI | Simulator | Device |
|---|---|---|---|---|
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | ✔ exit 0, `Test run with 556 tests in 66 suites passed` (538 before; +18 tests, 1 skipped by design: the committed-manifest test) | not run | n.a. | n.a. |
| `swift test --package-path Tools/TendTools -Xswiftc -warnings-as-errors` | ✔ exit 0, 8 tests in 1 suite (unchanged) | not run | n.a. | n.a. |
| Documented `sha256sum` command | ✔ (runs in the container) | `sha256sum` may be absent; the test then reports skipped | n.a. | n.a. |
| Freeze, L2a | not done (waits for the owner) | — | — | owner L2a |

### Things the reviewer should look at closely
- The pins are typed from the Tester's v3 table; a wrong pin would fail on the real files, and every pin passes, so
  pins and data agree. Check that the pins say what the table says (they do not check the table itself).
- F9's weather and deep-clean word rules are my machine reading of PO rulings 9 and Q3 on the `referencePhrase`; they
  hold for all 58 items. If the Tester adds an item tied to weather by another word ("storm"), the rule refuses it and
  the word list needs a reviewed change.
- F6's word-match floor uses the `referencePhrase` (not a natural title) and the golden room; stricter titles exist.
- C10's repeat evidence requires the same token twice per group (two synonyms do not count; the in03 control proves
  "light … bulb" is not taken as a repeat).

### Known limitations / tickets
| Item | Severity | Ticket |
|---|---|---|
| `MANIFEST.sha256` and the freeze | blocking AC-M2-14 | after owner L2a (GR-4) and PO go; Tester freezes per "To freeze" above |
| PO F4: `ds1-offline` / `ds2-*` profiles accept only the fixed input IDs (A-F1) | Minor | Developer, before DS-1/DS-2 scoring |
| GR-9 `@Guide` parity | Minor (before DS-1) | WI-M2-M2 |
| macOS CI does not run TendIngestion tests on this branch yet | info | HM-1 / CI owner |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Tests only; no entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | F3 refuses any banned whole token in the fixtures, so every banned token in a draft is "introduced" (AC-M2-12). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | The same fixtures serve DS-1 (on device) and DS-2; nothing routed. |
| P-2 Data leaves only via iCloud or a P-3 request | pass | No dependency; the SHA-256 is local test code; the test runs `sha256sum` locally; nothing is sent. |
| P-3 Cloud AI opt-in, minimised | pass | F2 (N-3) keeps fixture digits away from the interval sentinels; F6 proves the shortlist stays ≤ 6 titles per input. |
| P-4 Media not persisted | n.a. | Text only; mutations are in memory. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted | WI-M2-16: merge main (PR #32), Linux composition check with negative controls, manifest step without writing the manifest. |
| 2026-11-24 | Developer | Reviewer (via Orchestrator) | sent | Tests only; TendIngestion 556 green, 0 warnings; TendTools 8 green. Composition check passes on the committed fixtures: PO ruling 1 condition (e) met, pending review. |
| 2026-11-24 | Developer | Acceptance Tester (via Orchestrator) | sent | Freeze procedure ("To freeze"); the Status bullet of `eval-composition.md` is now read by a test ("Not frozen" ⇔ no manifest). No fixture file changed. |

### Update 2026-11-24: EC-Q8 golden pin, merge of main (PR #33)
- **EC-Q8 (PO `po-m2-wi16.md` "## EC-Q8"):** the Tester relabelled `g16-carservice` effort `normal` → `low` (`0c69143`;
  I checked that `golden.json` differs from `1184436` in that one value only). The PO re-approved the composition for
  that file. `EvalFreezeTests.approvedSHA256["golden.json"]` is now
  `0e819a89fcb65adb0a764d296f1d0dc8f30275cfe074495a4fe9c793a0f4b771`, and the comment records the EC-Q8 re-approval.
  `inputs.json` (`b32e45af…`) and `household.json` (`089a22bd…`) pins are unchanged. Before the update the pin test
  failed on `fc52a39`, as designed.
- **Composition check:** unchanged and green. No pin covers effort values. F9 tests only "deep clean ⇒ high", and
  `g16-carservice` is not a deep clean. The F6 word-match control on `g16-carservice` does not depend on effort.
- **Merge:** `origin/main` `4e13164` (PR #33, the A-F1 subset-profile fix, PO F4) was merged with `--no-ff`. For the
  `dev-notes.md` conflict I took main's file and appended this section. The "PO F4" ticket above is now done on main
  (main's "A-F1 fix" section).
- **Still not frozen:** no `MANIFEST.sha256` (waits for L2a). `EvalFreeze.declaredFrozen = false`.
- **Verification (Linux, Docker `swift:6.2-noble`, `-warnings-as-errors`, merged tree):** TendIngestion exit 0,
  `Test run with 564 tests in 66 suites passed` (the committed-manifest test skipped with its reason); TendTools exit 0,
  `Test run with 11 tests in 1 suite passed`. macOS not run.

| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Developer | accepted | EC-Q8 pin, merge main `4e13164`. |
| 2026-11-24 | Developer | Reviewer, Acceptance Tester (via Orchestrator) | sent | One-hash test change and the merge. 564 + 11 tests green. |

## L2a live check result (GR-4; WI-M2-16 DoR; AC-M2-24, AC-M2-14) and the first real recording (Gemini)

- **Owner:** Developer  ·  **Branch:** `m2/gemini-recording` (from `main` `52cba62`)  ·  **PR:** none yet  ·
  **ADRs:** ADR-0005 (unchanged)

### What happened (owner, 2026-11-25)
The owner ran L2a (plan.md "Real provider recordings") with the committed golden bodies for the Outcome sentence and an
empty household (`Fixtures/M2/payload/golden/g1-outcome-empty-<provider>.body.json`) and their golden headers, with the
owner's own key typed at a hidden prompt. Only the response stream was saved.

| Provider | L2a result | What it shows |
|---|---|---|
| Gemini | **PASS** | HTTP 200, `text/event-stream`, no 4xx. Body sent: `g1-outcome-empty-gemini.body.json` (SHA-256 `7be08e83…8207827` at `52cba62`). The stream is schema-valid: the joined output parses with `StructuredOutputReader` to 3 items, and a one-off Python check of the output against the body's `responseJsonSchema` (types, `enum`, `required`, `additionalProperties: false`, `maxItems`, string lengths; the schema uses no other keyword) found no error. Served model `gemini-3.5-flash-lite` (`modelVersion` in all 14 events). `usageMetadata` has no `thoughtsTokenCount` in any event: **0 reasoning tokens reported** (final usage: prompt 549, candidates 297, total 846 = 549 + 297). |
| OpenAI | **NOT RUN** | The call returned only a billing error, HTTP 429 `insufficient_quota` (no credit). That proves nothing about the request. No response was saved. |
| Anthropic | **NOT RUN** | The call returned only a billing error, HTTP 400 "credit balance" too low. That proves nothing about the request. No response was saved. |

**What the Gemini PASS confirms (GR-4):** Google accepted, with no 4xx, the three request members that its pages do not
document clearly (L1b note, 2026-11-24): `generationConfig.responseJsonSchema` on `streamGenerateContent`,
`generationConfig.thinkingConfig.thinkingLevel: "minimal"`, and `null` inside `enum` (daypart, repeatUnit, season,
weekday). Google also honoured the schema: the output keeps the sorted key order, has `null` for every unset hint member,
and every enum value is in its list. So for Gemini the golden request needs no change. For OpenAI (including the array
system content, F2) and Anthropic, L2a is still open. Those providers need credit on the owner's accounts, then the same
commands.

### What changed
- **Fixture (new):** `Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse` (owner's recording, the plan's
  path; SHA-256 `1f5784a0…5109102f`, 6 551 bytes, 14 `data:` events, CRLF). Before committing I checked that it holds no
  key, header or request. It contains no `x-goog-api-key`, `AIza`, `Authorization`, `Bearer`, the fake test key,
  `contents`, `systemInstruction` or `generationConfig`, and every non-empty line is `data: {…}`. A test checks the same
  thing. The only household-like text is the model's reply to the brief's fixed Outcome sentence.
- **Tests (new):** `Packages/TendIngestion/Tests/TendIngestionTests/ProviderStreamRecordingTests.swift`, 6 tests.
  The recording runs through the production path: `ProviderStreamReader(provider: .gemini)`, then `DraftPipeline` on
  `.cloud(.gemini)` through the existing test adapter `ChunkedProviderModel`, exactly as the synthetic fixture tests do.
- **Docs:** `Fixtures/M2/provider-streams/README.md` has a new "Recorded" section. It replaces the old `recorded/<provider>/`
  path, which did not match the plan's path. This section is new.
- **No production code changed.** The Gemini dialect already reads the trailing part correctly, so I found no defect.
  That part is `{"text":"","thoughtSignature":"…"}`, in the only event that carries `finishReason: "STOP"`. Its empty
  `text` adds nothing, the unknown member `thoughtSignature` is ignored, and `STOP` sets the normal end.

### AC coverage
| AC / item | Test (`ProviderStreamRecordingTests`) | Result (Linux) |
|---|---|---|
| AC-M2-24 / GR-4: response only, no key or request | "the Gemini recording holds the response body only: no request, no header, no key" | pass |
| GR-4 request profile | "what the recording shows about the request profile: served model gemini-3.5-flash-lite, no thoughtsTokenCount, no thought part, a trailing empty-text part with thoughtSignature and STOP". It checks one `responseId`, that `totalTokenCount = prompt + candidates` in every event, that the joined output equals the typed text, and it prints the usage. | pass |
| GR-4 trailing part | "the trailing empty-text part with thoughtSignature adds no output and gives the normal end (STOP)". The dialect reads the last event alone: output `""`, no stop, `hasEnded`. As a control, the body without the last event gives `cutShort(.noFinish)` with all 3 items read (K2). | pass |
| AC-M2-24 / AC-M2-05: outcome | "the Gemini recording gives completed, the 3 titles in order and no skip …": reader end equals `StructuredOutputReader.parse` of the typed output; emitted titles `["The AC needs servicing", "dishwasher pods", "deep clean the balcony"]`; no `updated`; one `finished`; `.completed(route: .cloud(.gemini))` | pass |
| AC-M2-24 / AC-M2-04: fields | "the recording's drafts …": rooms `[.none, .none, .proposed("balcony")]`, kinds `[oneOff, restock, oneOff]`, efforts `[normal, low, high]`, critical all false, deep clean `[f, f, t]`, weather `[f, f, t]`, no interval, source phrases as sent, no duplicates | pass |
| AC-M2-24: split chunks | "the recording gives the same result one shot, one event per chunk, byte by byte and at 40 seeded random cut sets (reader and pipeline: all 42)". The seed is printed in every message. Each cut set must give the same reader end and last snapshot, no part title in any step, the same emitted titles and final drafts, 0 skips and `completed`. | pass |

**The tests fail when the code breaks:** I briefly changed the dialect to reject a part that has a `thoughtSignature`.
Three of the 6 tests then failed (trailing part, outcome, split chunks; 45 issues). I restored the file, and
`git diff` shows no source change.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| New recording tests (6) | pass (Docker `swift:6.2-noble`, `-warnings-as-errors`) | not run | n.a. | n.a. | — |
| Full TendIngestion | exit 0, `Test run with 570 tests in 67 suites passed` (564 before + 6), 0 warnings | not run | n.a. | n.a. | — |
| L2a Gemini live call | n.a. | n.a. | n.a. | owner's machine, 2026-11-25 (as reported by the owner; I did not see the HTTP status myself, only the saved body) | — |
| L2a OpenAI, Anthropic | — | — | — | — | not run: billing errors, no credit |
| Real adapter end to end over this body | — | — | — | — | WI-M2-M6 on the owner-run Mac |

### Things the reviewer should look at closely
- The real wording differs from the synthetic fixtures. The titles are the model's own ("The AC needs servicing",
  "dishwasher pods"), the restock item has no room, and the balcony room is lower case. So these tests pin the
  recording's own values. They do not reuse `ProviderFixtures.happyTitles`.
- `thoughtSignature` now appears on the **last** part, with empty text, in the `STOP` event. The synthetic fixtures put
  it on the first part. Both are now covered.
- The synthetic Gemini fixtures carry `thoughtsTokenCount`. The real body under `thinkingLevel: "minimal"` has none, so
  the synthetic shape claims more than the API sent. That does not affect drafts, because the field is ignored. I did
  not change any synthetic fixture.
- `fixtureList` still counts only `synthetic/<provider>/`. The recording sits outside that folder, as the plan says.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| L2a for OpenAI (incl. array system content, F2) and Anthropic | not blocking the freeze (owner decision "L2a outcome", 2026-11-25); gates those providers' DS-2 runs (acceptance.md P11) | Owner: add credit, rerun the L2a commands; then a recording each, same test pattern |
| The schema check of the recorded output was a one-off Python script, not a committed test | Minor | Can become a Linux test once WI-M2-M6 adds a Foundation schema check for outputs |
| Whether L2a for Gemini alone is enough to close GR-4 (GR-4 names only Gemini members) | answered | Owner decision "L2a outcome" (2026-11-25): freeze now with Gemini PASS; OpenAI/Anthropic deferred (review R37 N1) |
| Recording tests use the shared test rooms, not the empty household the request was sent with (review R37 N2) | Minor | Ticket for WI-M2-M6 when real recordings per provider are added |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Tests and docs only; no entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No copy added; the recorded titles contain no banned word. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No routing change. The recording is the opt-in cloud path's reply. |
| P-2 No data leaves device (except user iCloud / P-3) | pass | Nothing is sent by the tests. The owner's call sent only the golden body: the fixed Outcome sentence and an empty household. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The key was never written to a file. I checked the recording for key and header strings, and a test checks it too. The request members are the ADR-0005 golden members; L2a shows Google accepts them. |
| P-4 Media not persisted without consent | n.a. | Text only. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Developer | accepted | Owner's L2a Gemini recording: test it through the production path, README note, L2a result. |
| 2026-11-25 | Developer | Reviewer, Acceptance Tester (via Orchestrator) | sent | Tests, fixture, docs only. No defect found in the Gemini dialect. 570 tests green, 0 warnings (Linux). OpenAI and Anthropic L2a still open. |

> **Update 2026-11-25 (Acceptance Tester, pointer only; the note above is kept as written):** the eval is now **frozen**
> on `m2/eval-freeze` (PR #36): `Fixtures/M2/eval/MANIFEST.sha256` committed, `EvalFreeze.declaredFrozen = true`,
> `eval-composition.md` v6. L2a (GR-4): Gemini PASS; OpenAI and Anthropic deferred by owner decision (DS-2 P11 in
> `acceptance.md`). The freeze-state test display name and header comment were updated to the frozen state (text only).

## Havana DST fixtures moved to the 2025 transitions (AC-M2-03 Q6(e), Q11; PO Havana tz fixtures, 2026-11-25)

- **Owner:** Developer  ·  **Branch:** `m2/havana-tz-fixtures` (from `main` `20c40ea`)  ·  **PR:** #39 (pushed
  2374aad)  ·  **ADRs:** none

### Why
On the owner's Mac (tzdata 2026f) 2 Havana tests in `TimeResolverTests.swift` fail: IANA tz 2026f (2026-10-27) says
"Cuba will not fall back to -05 on 2026-11-01 and instead plans to maintain -04 through 2027-11-07". The fixtures used
the 2026-03-08 spring-forward and the 2026-11-01 fall-back. Linux CI (tzdata 2026e) still passes, but would fail when it
updates. PO ruling "PO Havana tz fixtures, 2026-11-25": **option C**. Keep America/Havana (a midnight change), move the
cases to a settled past transition that both old and new tzdata agree on, and add a fixture guard. Option B
(expected values from `nextDaylightSavingTimeTransition`) is rejected.

### What changed (test file only; no product code)
`Packages/TendIngestion/Tests/TendIngestionTests/TimeResolverTests.swift`:

| Case (same ids, same count: 3) | Old `now` / window (UTC) | New `now` / window (UTC) |
|---|---|---|
| CU today before a repeated midnight (Q11 first occurrence) | Sat 2026-10-31 10:00 CDT; 2026-10-31T14:00Z to 2026-11-01T04:00Z | Sat 2025-11-01 10:00 CDT; 2025-11-01T14:00Z to 2025-11-02T04:00Z |
| CU tomorrow on the 25 h day | same now; 2026-11-01T04:00Z to 2026-11-02T05:00Z | same now; 2025-11-02T04:00Z to 2025-11-03T05:00Z |
| CU tomorrow on the 23 h day (midnight gap) | Sat 2026-03-07 10:00 CST; 2026-03-08T05:00Z to 2026-03-09T04:00Z | Sat 2025-03-08 10:00 CST; 2025-03-09T05:00Z to 2025-03-10T04:00Z |

- Same weekday (Saturday) and same hour for `now`, same anchors, same Q11 rule (a repeated midnight takes its first
  occurrence, 04:00Z). Window lengths are unchanged in kind: 25 h on 2025-11-02, 23 h on 2025-03-09.
- Expected instants are computed by hand from the Cuba rules (`Mar Sun>=8 0:00s`, `Nov Sun>=1 0:00s`, standard -5):
  2025-03-09 is the second Sunday of March, 00:00 CST = 05:00Z becomes 01:00 CDT. 2025-11-02 is the first Sunday of
  November, 01:00 CDT = 05:00Z becomes 00:00 CST, so local midnight is 04:00Z (CDT) and again 05:00Z (CST).
- **Fixture guard (new, PO ruling item 3):** `havanaTransitions` + `expectHavanaFixture()` assert the offset 1 s before
  and at each transition (-5 h to -4 h at 2025-03-09T05:00Z; -4 h to -5 h at 2025-11-02T05:00Z). Every parameterised
  Havana case runs the guard before `check(c)`, and the sanity test `havanaTzdata` runs it plus the four minute-level
  offset checks and `startOfDay(2025-03-09) == 05:00Z`. Every guard message starts "stale fixture: Havana tzdata
  changed". Nothing was removed, skipped or loosened; the change only adds checks.

### tzdata findings
| Source | 2025-03-09 05:00Z | 2025-11-02 05:00Z | 2026-11-01 05:00Z |
|---|---|---|---|
| tzdata 2026e (Linux container `swift:6.2-noble`, `tzdata 2026e-0ubuntu0.24.04.1`; also host python `zoneinfo`) | -5 to -4 | -4 to -5 | -4 to -5 (still falls back) |
| tzdata 2026f (`northamerica` at tag `2026f`, compiled with `zic`, read with `zdump -v`) | -5 to -4 | -4 to -5 | no change; next fall-back 2027-11-07 |

- 2026f `northamerica` Cuba rules: `2012 2025 Nov Sun>=1 0:00s`, `2013 2026 Mar Sun>=8 0:00s`, then `2027 max Nov`
  and `2028 max Mar`. So 2026f only ends the November rule after 2025 (and the March rule after 2026). 2025 is unchanged.
- tz NEWS for 2026a to 2026f: only 2026f mentions Cuba, and only as a change to future timestamps. Its "Changes to past
  timestamps" section is about Brazil 1965/1966. Nothing before 2026 changed for Cuba.
- Note: the 2026-03-08 spring case would not have failed on 2026f, but the PO ruling moves the Havana fixtures to a
  transition at least a year old, so it moved to 2025 too.

### AC coverage
| AC | Test | Result |
|---|---|---|
| AC-M2-03 Q6(e) / Q11 | `TimeResolverTests.havana` ("AC-M2-03 Q6(e) / Q11: a repeated and a missing local midnight (America/Havana)"), 3 cases | pass (Linux) |
| AC-M2-03 Q6(e) | `TimeResolverTests.havanaTzdata` ("AC-M2-03 Q6(e): tzdata sanity for the Havana cases (stale fixture if this fails)") | pass (Linux) |

Break check: I set the 2025-11-02 guard's "after" offset to -4 h and one expected end to 04:00Z. The run failed with
"stale fixture: Havana tzdata changed (offset from 2025-11-02T05:00:00Z is not -14400 s)" on all 3 cases and the
sanity test, plus the end mismatch. Then I restored the file (byte-identical, `cmp`).

### Verification environment
| Check | Linux (swift:6.2-noble, tzdata 2026e) | macOS / Xcode (tzdata 2026f) | Simulator | Device |
|---|---|---|---|---|
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | **570 tests in 67 suites passed**, 0 warnings | **not verified: owner Mac rerun still needed** | not verified | not verified |
| 2025 Havana offsets under 2026f | `zdump` of 2026f compiled with `zic` (Linux host) | not verified in Foundation on 2026f | n.a. | n.a. |

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Owner must rerun the TendIngestion tests on the Mac (tzdata 2026f) to confirm all 570 pass there | gates closing this item | Owner |
| DECISIONS.md entry "PO Havana tz fixtures, 2026-11-25" | Minor | Next human-merged governance PR (PO) |
| Tester to confirm the replaced cases still prove AC-M2-03 (same assertions, guard present) | required by ruling | Acceptance Tester |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Test fixtures only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Correct day bounds keep items on the right day. No copy added. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI path change. |
| P-2 No data leaves device | n.a. | Tests only; zone data is local. |
| P-3 Cloud escalation per ADR | n.a. | No change. |
| P-4 Media not persisted | n.a. | No media. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | PO (via Orchestrator) | Developer | accepted | Ruling C: keep Havana, move to the 2025 transitions, add the stale-fixture guard. |
| 2026-11-25 | Developer | Reviewer, Acceptance Tester, owner (via Orchestrator) | sent | Test-only change, local commit, not pushed. 570 green on Linux. Mac rerun on 2026f still needed. |

## Find sha256sum on macOS so the manifest-command test runs (AC-M2-13(b), AC-M2-14; WI-M2-16)

**Date:** 2026-11-25 · **Developer** · branch `m2/eval-freeze-sha256-path` (from `main` `2a47f75`), local commit, not pushed

### Why
The owner's Mac gate run (macOS 27.2.1, at `cf1261f`) skipped "AC-M2-14: the documented manifest command writes
exactly the in-memory render". The test looked for `sha256sum` only at `/usr/bin/sha256sum`, and on that Mac it is
at `/sbin/sha256sum`. AC-M2-13(b) needs 0 skipped on the Mac run, so this skip blocks it.

### What changed (test file only; no product code)
- `EvalFreezeTests.swift`: `EvalFreeze.resolveSHA256Sum(path:isExecutable:)` returns the first executable
  `sha256sum` in `/usr/bin`, `/sbin`, `/usr/sbin`, `/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, then each `PATH`
  directory in order. `EvalFreeze.sha256sum` is now that result (`String?`).
- The `.enabled(if:)` guard uses the resolved path (nil means skip). The skip message now names every place searched.
  The test body uses `#require` on the path. What the test asserts is unchanged.
- The header comment now describes the search instead of "Linux only".
- New parameterised test "AC-M2-13(b) / AC-M2-14: sha256sum is found in the fixed places in order, then PATH; nil
  only if absent everywhere" (6 cases, with an injected `isExecutable`, so no filesystem is involved). It covers Linux
  `/usr/bin`, macOS 27 `/sbin`, Homebrew before `PATH`, `PATH` order, and none found.

Break check: I swapped the order to `PATH` first. The resolver test failed on the "Homebrew before PATH" case
(got `/home/u/bin/sha256sum`). Then I restored the file (byte-identical, `cmp`).

### AC coverage
| AC | Test | Result |
|---|---|---|
| AC-M2-14 | `EvalFreezeTests.documentedCommandMatchesRender` (unchanged assertions) | pass (Linux, `/usr/bin/sha256sum`) |
| AC-M2-13(b), AC-M2-14 | `EvalFreezeTests.sha256sumResolver`, 6 cases | pass (Linux) |

### Verification environment
| Check | Linux (swift:6.2-noble) | macOS (owner Mac, macOS 27.2.1) | Simulator | Device |
|---|---|---|---|---|
| `swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | **571 tests in 67 suites passed, 0 skipped**, 0 warnings | **not verified: owner Mac rerun needed** (expect the manifest-command test to run from `/sbin/sha256sum`, 0 skipped) | not verified | not verified |

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Owner reruns TendIngestion on the Mac and confirms 0 skipped (AC-M2-13(b)) | gates AC-M2-13(b) | Owner |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Test only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | n.a. | No copy. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI path change. |
| P-2 No data leaves device | n.a. | A local `sha256sum` process in tests only. |
| P-3 Cloud escalation per ADR | n.a. | No change. |
| P-4 Media not persisted | n.a. | Nothing written (stdout only). |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Developer | accepted | Mac finding: skip at `/sbin/sha256sum` path, `cf1261f`. |
| 2026-11-25 | Developer | Reviewer, owner (via Orchestrator) | sent | Test-only, local commit, not pushed. 571 green, 0 skipped on Linux. Mac rerun needed. |

---

## WI-M2-M1 — XcodeGen project, `TendAI` scaffold, T-27 check, Mac command check, latency probe (MS-1)

- **Owner:** Developer, driving the owner's Mac over Remote Control  ·  **Branch:** `m2/xcodegen-project`, based on
  `main` at `20c40ea`  ·  **PR:** #38 (the owner merges Mac-only PRs under D-032)  ·
  **ADRs:** [ADR-0003](../../architecture/adr/0003-project-generation.md), now **Accepted**;
  [ADR-0006](../../architecture/adr/0006-m2-module-layout.md) (the layout followed).
- **Requirements:** ○ AC-M2-09 (the Rule 5 decision and the `TendAI` and `TendEval` roots switched to `required`),
  ○ AC-M2-13 (the Mac lane exists: B4 and B5 run), ○ AC-M2-28 (the target and scheme structure that its `project.yml`
  scan will check). T-27, R-1, R-8. P-1, P-2.
- **Mac evidence record:** [`evidence/mac/MS-1/`](evidence/mac/MS-1/README.md). It names the exact commit tested, every
  command, and the SHA-256 of each log.

### What changed
- **`project.yml`** (repo root, XcodeGen 2.46.0). It has four targets:
  - `Tend`: the app skeleton (`com.tend.app`). It has no dependencies, so it has none on `TendEval`.
  - `TendEval` (`com.tend.eval`): it depends on `TendCore`, `TendIngestion` and `TendAI`. The five frozen eval files
    are bundled file by file at the bundle root. File sharing is on in Debug only, through a partial `Info.plist` that
    only the Debug configuration sets.
  - `TendAITestHost` (`com.tend.aitesthost`): a blank host app.
  - `TendAIHostedTests`: a unit-test bundle over `Packages/TendAI/HostedTests`, hosted by `TendAITestHost`.

  It has three schemes:
  - `Tend` builds and archives only `Tend`.
  - `TendEval` uses Debug for every action and is not built for archiving, so `xcodebuild archive -scheme TendEval`
    is refused.
  - `TendAIHostedTests` builds the host and tests the bundle.

  Swift 6, complete strict concurrency, warnings as errors, iOS 26.0 deployment target, iPhone and iPad. The file is
  pinned with `minimumXcodeGenVersion: 2.46.0`.
- **`.gitignore`:** `/Tend.xcodeproj/` (always generated) and `/build/` (Mac logs, derived data and result bundles).
- **`Packages/TendAI`:**
  - `Package.swift`: tools 6.2, Swift 6, iOS 26 / macOS 26. The library `TendAI` depends on `../TendCore` and
    `../TendIngestion`. The test target is `TendAITests`.
  - `Sources/TendAI/TendAIModule.swift`: the scaffold. It imports `Foundation` only.
  - `Tests/TendAITests`: 1 test (macOS, B4).
  - `HostedTests`: 2 tests (iOS Simulator, B5). One checks that they run inside `com.tend.aitesthost`.
- **`Apps/Tend`, `Apps/TendAITestHost`, `Apps/TendEval`:** one SwiftUI `App` file each, with no product UI. The
  `TendEval` file imports `SwiftUI` only, has no write or log API, and passes Rule 6.
- **`ScanScope.swift`:** `TendAI` and `TendEval` are now `required`. The Rule 5 T-27 exception stays **off** (see
  below); its comment now gives the reason. The AC-M2-09 scan on the Mac: TendIngestion 55 files, TendAI 1, TendEval 1,
  57 in total, 0 violations.
- **`ProviderDialectTests.swift`, one line (a compile fix, not a test change):** `arguments: [...] as [String]` on the
  `unexpectedStructure` test. Xcode 27.2's Swift 6.4.2 compiler stops on that 13-row literal of `String +` chains with
  "unable to type-check this expression in reasonable time". Linux Swift 6.2 compiled it. The rows, the test body and
  the test name are unchanged, and the test runs the same 13 cases.
- **`plan.md`:**
  - The speech-permission row now records the T-27 result.
  - The Mac commands section has a "Confirmed by WI-M2-M1" paragraph and one new B6 check (the `TendEval` Archive
    action is off).
  - R-1 has the probe numbers. R-8 notes that the Simulator could not give the answer.
- **ADR-0003:** Accepted, with the pin, both checksums, the install method, and three things learnt while generating.

### T-27: does `SpeechAnalyzer` need `SFSpeechRecognizer.requestAuthorization(_:)`? **No.**
The probe is a throwaway project in the session scratchpad. It never calls `requestAuthorization`. Its source is
copied, for the record only, to [`evidence/mac/MS-1/probes/`](evidence/mac/MS-1/probes/), outside every scanned root.
The input was a 4.8 s, 16 kHz WAV made with `say` ("We are almost out of dishwasher pods, and the AC needs servicing
before summer.").

| Where | `authorizationStatus()` before → after | `SpeechTranscriber` | `DictationTranscriber` |
|---|---|---|---|
| macOS 27.2.1 (26B131), command-line tool with `NSSpeechRecognitionUsageDescription` embedded | `notDetermined` → `notDetermined` | `isAvailable = true`; assets `supported` → `installed` (first run; already `installed` in the committed run); **transcribed the sentence exactly**, from the file (0.40 s) and from converted buffers through `start(inputSequence:)` (0.19 s) | `.longDictation`: **transcribed it**, from the file (0.34 s) and from buffers (0.19 s). In the first run, `.shortDictation` returned no final result for this 4.8 s file (a note for WI-M2-M3, not a permission matter). |
| iOS 26.5 Simulator (23F77), iPhone 17 Pro | `notDetermined` → `notDetermined` | `isAvailable = false`; assets `unsupported`; an asset request fails with "not subscribed to transcription.en" | assets `supported` → `installed`, but `bestAvailableAudioFormat` is `nil` and analysis fails with "No common audio format among modules" |

- **On the Simulator, neither failure is an authorization error.** The Simulator has no usable speech model, so it
  cannot answer T-27 either way. This is risk R-8, and it happened.
- **Apple's documentation** ("Asking Permission to Use Speech Recognition", Speech framework, read 2026-11-25): the
  permission flow covers only speech recognition with `SFSpeechRecognizer`. The article says `SpeechAnalyzer`
  transcriber modules "don't send audio data of the user's voice to Apple's servers". The `SpeechAnalyzer`,
  `SpeechTranscriber` and `DictationTranscriber` reference pages name no authorization step.
- **Decision:** the Rule 5 exception stays **off** (`ScanScope.speechPermissionExceptionEnabled = false`). The
  speech-permission file holds no `SFSpeech*` API. Live capture still needs the **microphone** permission
  (`AVAudioApplication.requestRecordPermission`, `NSMicrophoneUsageDescription`), which is not an `SFSpeech*` API
  and is allowed by Rule 2 (`AVFAudio`).
- **For the Acceptance Tester (DS-1, DS-2 preconditions):** on device, the first capture should show the microphone
  prompt and **no** speech-recognition prompt. If a device shows a speech-recognition prompt or refuses to transcribe
  without one, T-27 is reopened. The scope table and the plan row are then changed under a PO decision.

### R-1 latency probe (information only, never evidence)
- **Setup:** M1 Mac mini (16 GB), macOS 27.2.1, `SystemLanguageModel.default.availability == .available`. A
  draft-sized `@Generable` schema: `items: [ProbeDraft]` with at most 10 items, 7 fields each, `title` first, no
  `Tool`.
- **Run:** a fresh session each run, `prewarm()` and 1 s idle, then `streamResponse` on the 3-task Outcome sentence.
  TTFI is the time to the first snapshot whose first item has a non-empty `title`, on `ContinuousClock`.

Committed run ([`probes/mac-probe-final.log`](evidence/mac/MS-1/probes/mac-probe-final.log)):

| Run | 1 | 2 | 3 | 4 | 5 | Median |
|---|---|---|---|---|---|---|
| TTFI (s) | 2.22 | 1.37 | 1.34 | 1.34 | 1.35 | **1.35** |
| Total (s) | 5.32 | 5.80 | 4.41 | 4.40 | 4.43 | 4.43 |

An earlier run in the same session gave a TTFI median of 1.36 s (range 1.33–2.12 s) and a total median of 4.46 s.

- Every run produced 3 items. Run 1 is a cold start.
- What this says for R-1: on the Mac the schema lands just under the 1.5 s AC-M2-16 bound once warm, with little room
  to spare, and before the duplicate `Tool` is added. The iPhone 15 Pro is slower than an M1, so SP-1 in MS-2 is worth
  running.
- **iOS 26.5 Simulator:** `availability == .available`, but every `streamResponse` failed with `GenerationError -1`.
  The underlying errors are `com.apple.SensitiveContentAnalysisML 15` and `ModelManagerError 1001` (the guardrail
  model is missing in this Simulator runtime). The Simulator gives no on-device-model numbers. WI-M2-M2 should not
  plan Simulator tests against the real model.

### Test runs (R-18 runtime record; the evidence record has the logs)
The clean run at `0065664`, with `build/`, every package `.build` and the project's DerivedData deleted first. The
Xcode builds are short because Xcode 27's shared compilation cache (`DerivedData/CompilationCache.noindex`) was warm
from earlier runs in the session.

| Command | Result | Runtime |
|---|---|---|
| B1 `swift test` TendCore | 141 tests in 18 suites passed, 0 warnings | 43 s wall (tests 30.7 s) |
| B2 `swift test` TendIngestion | 570 tests in 67 suites: **568 pass, 2 fail** (the Havana tzdata cases below), 0 warnings | 97 s wall (tests 70.7 s) |
| B4 `xcodebuild test -scheme TendAI` (macOS) | 1 test passed, `TEST SUCCEEDED` | 8 s |
| B5 `xcodebuild test -scheme TendAIHostedTests` (iPhone 17 Pro, iOS 26.5) | 2 tests passed, `TEST SUCCEEDED` | 9 s |
| B6 Release build and archive of `Tend`; `find … -iname '*TendEval*'` | both succeed; both `find`s print nothing; the archive holds only `Tend.app` | 5 s + 2 s |
| B6 `TendEval` Debug build | succeeds; the bundle holds the 5 fixture files, and its `MANIFEST.sha256` is byte-identical to the repo's (all 5 SHA-256 match); `UIFileSharingEnabled = true` (Debug) | 11 s |
| B6 `xcodebuild archive -scheme TendEval` | refused, exit 66: "Scheme TendEval is not currently configured for the archive action." (as intended) | — |

### B2 on macOS: two America/Havana tzdata failures (not caused by this item; owner of the fix: WI-M2-03)
- `AC-M2-03 Q6(e): tzdata sanity for the Havana cases` expects `secondsFromGMT(2026-11-01T05:00Z) == -5 h`. macOS
  gives **-4 h**.
- `… a repeated and a missing local midnight (America/Havana)`, case "CU tomorrow on the 25 h day", expects the window
  to end at 05:00Z. macOS gives 04:00Z.
- The Mac's tz database is **2026f** (`/var/db/timezone/zoneinfo/+VERSION`). In it Cuba does not fall back on
  2026-11-01. The Linux image (`swift:6.2-noble`) has older tzdata that still has the fall-back. The resolver is right
  for the zone data it is given. The test pins a tzdata fact that has changed.
- The sanity test exists to catch exactly this, and it did. **I did not change either test** (never weaken a test).
- Fix options for WI-M2-03's owner or the PO: move the "repeated midnight" case to a zone and date whose rule is
  stable in both tzdata versions; or make the fixture pick its date from the zone's actual transitions. The second
  option changes what the test proves, so the PO decides.
- Until then, AC-M2-13(b) cannot be green on this Mac. Linux CI will hit the same failure when its image gets 2026f.

### Verification environment
| Check | Linux `swift test` | macOS (owner-run Mac) | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendCore | not rerun | pass (B1) | n.a. | n.a. | — |
| TendIngestion | not rerun (CI runs it) | 568 / 570 (B2; tzdata, above) | n.a. | n.a. | — |
| TendAI scaffold | n.a. (Apple-only) | pass (B4) | pass (B5) | n.a. | — |
| AC-M2-28 structure | n.a. | B6 pass | n.a. | n.a. | The `project.yml` scan test is WI-M2-M7's (● AC-M2-28) |
| T-27 | n.a. | answered (no authorization needed) | no speech model | — | DS-1 and DS-2 confirm the prompts on device |

### Things the reviewer should look at closely
- **Xcode 27.2, not 26.** The App Store installed Xcode 27.2 (27B52) with the iOS 27.2 SDK. The only Simulator runtime
  on the Mac is iOS 26.5. The deployment target is iOS 26.0, so the iOS 26 floor is what is built against. The brief's
  "Xcode 26" commands run unchanged. If the PO wants exactly Xcode 26, that is an owner install, and the evidence must
  be redone.
- The `as [String]` line is the only edit to an existing test file apart from `ScanScope` and its one comment. It
  only adds a type annotation.
- **`TendEval` "Debug only".** All four of its scheme actions use Debug, the scheme cannot archive, and no other
  target depends on it. The target still has a Release configuration, because XcodeGen generates both configurations
  for every target. Nothing builds it in Release. If the Reviewer wants a hard guard (for example a Release-only build
  setting that fails the build), that is one more `project.yml` line.
- The `Tend` skeleton links nothing. When M3 gives it dependencies, `TendEval` must stay out of them (AC-M2-28).
- `com.tend.*` bundle IDs are placeholders until the signing team (Q20) is chosen. None of them is host-like under
  Rule 4.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Havana tzdata failures in B2 on macOS (tzdata 2026f) | **Major** for AC-M2-13(b); not caused by this item | WI-M2-03 owner and PO (above) |
| T-27 rests on the docs and macOS; the Simulator has no speech model | Minor | DS-1 and DS-2 prompt check (Tester) |
| `DictationTranscriber` `.shortDictation` gave no final result for a 4.8 s file; `.longDictation` worked | Minor | WI-M2-M3 (preset choice) |
| FoundationModels does not run in the iOS 26.5 Simulator (guardrail model missing) | Minor | WI-M2-M2 (test plan) |
| AC-M2-28 `project.yml` scan test | — | WI-M2-M7 (owner of AC-M2-28) |
| CLAUDE.md §7 still shows the commented Xcode command | Minor | Documenter (protected path) |

### Tickets (from review round 1, [review-pr38.md](review-pr38.md))
| Finding | Ticket | Where |
|---|---|---|
| m1(a) "All interface orientations must be supported…" warning for `Tend` and `TendEval` | Add `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` (and an explicit iPhone list) for both targets in `project.yml`; B6 re-run proves it clean. The iPad orientation set is the Designer's decision (CLAUDE.md §9 Q1). | MS-2 |
| m2 `TendEval` Release is excluded only by the schemes | Hard guard in the `TendEval` Release configuration, asserted by the AC-M2-28 `project.yml` scan test. | WI-M2-M7 |
| m4 T-27 rests on docs and a macOS command-line probe | T-27 check on the iPhone 15 Pro in SP-1: first capture shows only the microphone prompt, and transcribes (Planner / Tester). | MS-2 |
| n2 B6 builds without the warnings-as-errors flag | Pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` in the B6 commands on the next Mac run. | next Mac run (MS-2) |

The round 1 docs-only fixes (M1 path redaction to `$REPO`, m1(b) README warning sentence, m3 zip digest, n1 PR number)
are in the fix commit on top of `02c1d84`; no file outside `docs/` changed, so the Mac record still covers `0065664`
(review Q1 is open for the PO / owner).

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; the app skeletons show no UI. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No copy. The scaffold names pass the banned-token rule. |
| UX-4 Design craft | n.a. | No product UI in M2's skeletons. |
| P-1 On-device inference | pass | Both probes ran fully on device. T-27 keeps speech recognition on `SpeechAnalyzer`, which sends no audio to Apple. |
| P-2 No data leaves device | pass | No SDK and no networking code. XcodeGen is a dev tool, pinned by checksum (ADR-0003), and nothing from it is linked into an app. |
| P-3 Cloud AI only opt-in, BYOK, minimised | n.a. | No cloud code. No key was used. |
| P-4 Media not persisted | pass | The probe's audio was synthetic text-to-speech in the scratchpad. No user audio was captured. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Coordinator | Developer (owner's Mac) | accepted | WI-M2-M1 brief. The start was blocked until the owner installed Xcode and accepted its licence. |
| 2026-11-25 | Developer | Reviewer, Acceptance Tester, PO (via the coordinator) | sent | Branch pushed, no PR. Open items: the Havana tzdata failures (PO / WI-M2-03), and HM-2 / D-032 for the owner's merge. |
| 2026-11-25 | Reviewer | Developer | accepted | PR #38 round 1: CHANGES REQUIRED (M1, m1, m2, m3, m4, n1, n2). |
| 2026-11-25 | Developer | Reviewer (via Orchestrator) | sent | Docs-only fix: `$REPO` redaction (2,248 occurrences), 22 hashes recomputed (9 changed), README warning sentence, zip digest aligned with ADR-0003 (and ADR zip size corrected), PR #38 noted; tickets above. Not pushed. |

## WI-M2-M5 — Keychain key store: generic password, data-protection keychain, this device only, not synchronised; masked form; delete on turn-off and remove-key (MS-2)

- **Owner:** Developer, driving the owner's Mac over Remote Control  ·  **Branch:** `m2/keychain-key-store`, based on
  `main` at `41bf8fa`  ·  **PR:** #45 (owner merge under D-032)  ·  **ADRs:** ADR-0005 Decision 5, ADR-0006.
- **Requirements:** ● AC-M2-21, ● AC-M2-18 (the real-Keychain half of (a)). P-3, P-4, UX-3. T-14, T-16.
- **Mac evidence record:** [`evidence/mac/WI-M2-M5/`](evidence/mac/WI-M2-M5/README.md), for the code commit
  `73905869b83714e310ed4cb4397dddc9d8301b6b`.
- **Commit identity:** from this item on, the repo-local git identity is `Claude <noreply@anthropic.com>` (the
  orchestrator's instruction; the earlier two branches are re-created as `-v2` by the orchestrator).

### What changed
- **`TendAI/Cloud/KeychainAPIKeyStore.swift`** (allowlist file 3; the only file that imports `Security`) — an actor
  conforming to `APIKeyStore`:
  - one item per provider: `kSecClassGenericPassword`, service `tend.ai.key` (reverse-DNS, not host-like under Rule 4),
    account = the provider's raw name, `kSecUseDataProtectionKeychain = true`, `kSecAttrSynchronizable = false`,
    `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`;
  - `save` updates in place (data and accessibility) and adds only when no item exists, so a failed replace never
    leaves the provider without its old key;
  - `hasKey` asks for attributes only, never the data (WI-M2-09 ticket); `key` reads the data back;
  - `deleteKey` treats `errSecItemNotFound` as done;
  - every Keychain status becomes a neutral `CloudStoreError` (`errSecInteractionNotAllowed` → `notAccessibleNow`,
    anything else → `storeUnavailable`); no error holds the key or the status text.
  - The key is stored **exactly as given** (AC-M2-21 "Reading it back after save returns the same key"). Trimming or
    refusing surrounding whitespace and control characters is the open PO decision R28-F5; WI-M2-M4's transport
    refuses a header value with a line break before sending, so a pasted newline can never inject a header.
- **`TendAI/Cloud/APIKeyMask.swift`** — the only display form: `••••` plus the last 4 `Character`s for a key of 12 or
  more characters, `••••` alone for shorter keys (T-16). Not allowlisted (no `Security`, no networking).
- **Tests:** `TendAIHostedTests` +6 tests (iOS 26.5 Simulator, each with its own Keychain service, cleaned up);
  `TendAITests` +2 (the mask). Hosted tests use `ModelRouter` with the real store for AC-M2-18 (a).

### AC → test
| AC | Test(s) | Command | Result |
|---|---|---|---|
| AC-M2-21 item kind and attributes (read back with `kSecReturnAttributes`, T-16) | `KeychainAPIKeyStoreHostedTests` "AC-M2-21: save, read, replace and delete, with the item's attributes read back from the Keychain" (3 providers): after save and after replace, exactly one item; `kSecAttrAccessible` = `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; `kSecAttrSynchronizable` false; service and account; found by a generic-password search and by a search with `kSecUseDataProtectionKeychain`, and not by an internet-password search (the class is not among the returned attributes) | B5 | PASS |
| AC-M2-21 read back, replace, delete → `errSecItemNotFound` | same test; "Keys are kept per provider …"; "A key of any length and any characters is stored and read back exactly" (empty, 1 char, short, non-ASCII with emoji, 4,096 chars) | B5 | PASS |
| AC-M2-21 masked form | `APIKeyMaskTests` (6 keys: 0, 3, 11, 12, 26 characters, non-ASCII) and "never more than the last four" | B4 | PASS |
| AC-M2-21 no key in any formatting | "AC-M2-21: no formatting of any key-holding value shows the key": `String(describing:)`, `String(reflecting:)`, interpolation, `dump` and `Mirror` of `APIKey` and of the store, every `CloudStoreError`, the mask | B5 | PASS |
| AC-M2-18 (a) real Keychain | "turning cloud off deletes the item", "removing the key deletes the item" (lookup gives `errSecItemNotFound`; cloud status off), "An orphan key restored without consent is deleted from the Keychain at the first route choice (T-14)" | B5 | PASS |

**Mutants (each run in the Simulator host, then reverted):** accessibility `AfterFirstUnlock` on replace (K1),
item added as synchronizable (K2b), delete does nothing (K3), mask shows 5 characters (K4), mask threshold 11 (K5):
all killed. K2 (the query's `kSecAttrSynchronizable` widened to "any") survived round 1: the query is used by every
lookup, by `hasKey`, by `deleteKey` and by the **update** path of `save`, so the mutant would read, delete or overwrite a
synchronizable item with the same names; no round-1 test planted one. **Killed in `m2/key-paste-cleanup`** (review PR #45
m1): a planted synchronizable item holding a sentinel is not seen by `hasKey` or `key`, is still intact after `save`
(which adds a separate non-synchronizable item) and after `deleteKey`.

### Test runs (R-18; the evidence record has the logs)
The clean run at `7390586`.

| Command | Result | Runtime |
|---|---|---|
| B1 `swift test` TendCore | 141 tests in 18 suites passed, 0 skipped | 43 s wall |
| B2 `swift test` TendIngestion | 571 tests in 67 suites passed, 0 skipped; scan 59 files (TendAI 3), 0 violations | 95 s wall |
| B4 `xcodebuild test -scheme TendAI` (macOS) | 3 tests in 2 suites passed | 8 s |
| B5 `xcodebuild test -scheme TendAIHostedTests` (iPhone 17 Pro, iOS 26.5) | 9 tests in 2 suites passed | 9 s |
| B6 | as MS-1; both `find`s print nothing; `TendEval` archive refused (66) | 5 + 3 + 11 + 1 s |

### Things the reviewer should look at closely
- `kSecUseDataProtectionKeychain` is set on every query (it is what selects the data-protection keychain on macOS;
  on iOS every item is in it).
- The hosted tests' `UnavailableOnDevice` uses `OnDeviceModelSource.model()` as on `main`. If
  `m2/on-device-adapter-v2` merges first (it renames it to `model(household:)`), this test helper needs the one-line
  rename at merge.
- Personal data: the key never reaches a log, an error or a formatted value (test above); the Keychain item is not
  synchronised and not restorable to another device.
## WI-M2-M4 — cloud transport and failure mapping: ephemeral HTTPS to the routed host only, redirects refused, fixed client headers, `URLError` and status to neutral reasons (MS-2)

- **Owner:** Developer, driving the owner's Mac over Remote Control  ·  **Branch:** `m2/cloud-transport`, based on
  `main` at `41bf8fa`  ·  **PR:** #46 (owner merge under D-032)  ·  **ADRs:** ADR-0005 Decisions 6 and 7,
  ADR-0006.
- **Requirements:** ● AC-M2-22, ● AC-M2-23 (the Mac halves; the deadline and retry arithmetic and the outcomes are
  WI-M2-14 and WI-M2-06 on Linux). P-2, P-3, P-4, UX-3. Tickets closed here: R28-F4 / GR-3 (explicit headers on the
  wire), R29-N2 (no single-byte chunks), R30-F2 (cancellation is not a failure), R30-F5 (a silent attempt ends at the
  resource timeout), PO Q3 (refusals send nothing), round 1 (timeouts per attempt, raw `Retry-After`, never retry),
  and the transport half of R28-F5 (a header value with a line break is refused).
- **Mac evidence record:** [`evidence/mac/WI-M2-M4/`](evidence/mac/WI-M2-M4/README.md), for the code commit
  `1854d549c3fb89b9378a23ea83857550f142ccd3` (the branch has two code commits: `d406a7d` and the AC-M2-12 naming fix `1854d54`; an earlier evidence run at `d406a7d` stopped at B2 on that scan and was discarded).

### What changed
- **`TendAI/Cloud/CloudHTTPTransport.swift`** (allowlist file 1) — `CloudTransport` conformance:
  - **One attempt per call, its own session:** `URLSessionConfiguration.ephemeral` with `httpCookieStorage = nil`,
    `httpShouldSetCookies = false`, cookie policy `.never`, `urlCache = nil`, `urlCredentialStorage = nil`, cache
    policy `.reloadIgnoringLocalAndRemoteCacheData`, `waitsForConnectivity = false`, and
    `timeoutIntervalForResource` / `timeoutIntervalForRequest` from the attempt's `CloudAttemptTimeouts`. No retry.
  - **HTTPS to the routed host only:** the URL is built with `URLComponents` (scheme `https`, the builder's bare host,
    path and fixed query `alt=sse` through `query`, no `URLQueryItem`). The request host must equal the ADR-0005 host
    of the request's provider (`CloudProviderTable.hosts`), and the built URL must be `https` to that host; a
    header name or value with CR, LF or NUL is refused. Each refusal throws `CloudTransportFailure(.requestNotSent)`
    before a session exists.
  - **Redirects:** `RedirectRefuser` (a stateless `URLSessionTaskDelegate`, passed to `bytes(for:delegate:)`) answers
    every redirect with nil. The 3xx is then the final response: `requestNotSent` when its `Location` names another
    host, else `unexpectedResponse`.
  - **Headers:** exactly the builder's, each set with `setValue(_:forHTTPHeaderField:)` (the builder already ends with
    `User-Agent: Tend` and `Accept-Language: en-US`, so the device defaults are replaced).
  - **Body:** for a 2xx, bytes go on in chunks cut after each blank line (`\n\n` or `\n\r\n`, the end of a server-sent
    event) or at 4 KiB, so a whole event goes on at once and no chunk is a single byte (R29-N2). Other statuses throw
    `CloudTransportFailure(reason, retryAfter:)`, with the raw `Retry-After` value only for 429 and 5xx.
  - **Cancellation:** `onTermination` cancels the task and `invalidateAndCancel()`s the session; a cancelled attempt
    (or `URLError.cancelled`) finishes without an error (R30-F2). A stream created in a cancelled task sends nothing.
  - Naming note: the AC-M1-23 `Host(` call rule catches any called function whose name ends in `Host`; the two
    helpers are `routedHostName` and `pointsElsewhere`.
- **`TendAI/Cloud/CloudFailureMapping.swift`** (allowlist file 2) — `URLError.Code` → reason (offline: not connected,
  connection lost, data not allowed, roaming off, call active; `timedOut`; host not found: cannot find host, DNS; secure
  connection: TLS and certificate codes and ATS; `cancelled` → nil; everything else `unexpectedResponse`; `URLError.Code`
  is a struct, so this one switch needs a `default`). Status: 2xx → nil, 401/403 → `keyNotAccepted`, 429 →
  `rateLimited`, 5xx → `serviceUnavailable`, else `unexpectedResponse`.
- **Tests:** `TendAIHostedTests` +17 (iOS 26.5 Simulator), over a `URLProtocol` stub installed only through the
  transport's test hook (`adjust`), so no source names `URLProtocol`. The stub records every request that reaches it.

### AC → test (all B5)
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-22 ephemeral, no cookies or cache, timeouts | "each attempt uses an ephemeral configuration with no cookies, cache or credentials, and its timeouts"; "A response's Set-Cookie is never kept or sent back on the next attempt" | PASS |
| AC-M2-22 HTTPS to the routed host; refusals send nothing (PO Q3) | "a 2xx body arrives in order …" (3 providers: scheme, host, path, method, body bytes, Gemini query); "a request to a host other than the provider's is refused before sending" (4 hosts, 0 requests at the stub); "a non-HTTPS URL is refused before sending" (3 forms, 0 requests); "a redirect to another host is not followed and ends requestNotSent" (1 request, only to the routed host); "A redirect on the same host is not followed either"; "A header value with a line break is refused" | PASS |
| AC-M2-22 Headers (R28-F4, GR-3) | "User-Agent: Tend and Accept-Language: en-US are set explicitly; only the builder's headers are sent" (3 providers; every header the stub sees is the builder's or transport-set) | PASS |
| AC-M2-22 timeouts applied per attempt (R30-F5) | "a stub that never answers ends timedOut at the attempt's resource timeout" (1.0 s, under 5 s); "a body that stops arriving ends timedOut" | PASS |
| AC-M2-23 mapping | "each HTTP status maps to its neutral reason; Retry-After is passed on raw for 429 and 5xx only" (12 statuses, exactly 1 request each: never retried); "each URLError through the session maps to its neutral reason" (11 codes); "the mapping table, code by code" | PASS |
| Contract 4, 5 (R30-F2) | "cancelling mid-body ends without a failure, and CloudResponseBody ends with CancellationError"; "A stream created inside a cancelled task sends nothing" | PASS |
| R29-N2 | body test (no 1-byte chunk, ≤ 4 KiB), "An event ends at a blank line, LF or CRLF …" | PASS |

**Mutants (each run in the Simulator host, then reverted; all killed):** no host check (T1); redirect followed (T2);
`Accept-Language` not set (T3); `Retry-After` passed for every status (T4); resource timeout not applied (T5); cookie
storage kept (T6); cancellation mapped to a failure (T7); line breaks allowed in headers (T8); 403 not read as a key
problem (T9).

### Test runs (R-18; the evidence record has the logs)
The clean run at `1854d54`.

| Command | Result | Runtime |
|---|---|---|
| B1 `swift test` TendCore | 141 tests in 18 suites passed, 0 skipped | 45 s wall |
| B2 `swift test` TendIngestion | 571 tests in 67 suites passed, 0 skipped; AC-M2-09 scan 59 files (TendAI 3), 0 violations; AC-M2-12 vocabulary scan 0 violations | 110 s wall |
| B4 `xcodebuild test -scheme TendAI` (macOS) | 1 test passed (the scaffold; this item's tests are all hosted) | — |
| B5 `xcodebuild test -scheme TendAIHostedTests` (iPhone 17 Pro, iOS 26.5) | 19 tests in 2 suites passed | — |
| B6 | as MS-1; both `find`s print nothing; `TendEval` archive refused (66) | — |

**AC-M2-12 note:** Foundation names two codes `dnsLookupFailed` and `secureConnectionFailed`; the calm-vocabulary scan
does not allow that word in our source identifiers, so `CloudFailureMapping` names them by raw value
(`dnsLookup` = -1006, `secureConnection` = -1200), and a hosted test checks they equal the Foundation codes.

### Things the reviewer should look at closely
- The `URLProtocol` stub sees the request before the lowest network layer, so it shows the headers the session will
  send from the request and configuration; that the OS adds no `User-Agent` or `Accept-Language` of its own when they
  are set explicitly is Apple's documented behaviour, not something a stub can prove. DS-2's provider runs are the
  end-to-end check (Reviewer confirmation asked by the R28-F4 ticket).
- A redirect is answered with nil, and the 3xx response's `Location` decides `requestNotSent` vs `unexpectedResponse`.
- The test-only `adjust` hook is internal; the app uses `CloudHTTPTransport()`.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| R28-F5: trim or refuse a key with surrounding whitespace or a control character | Minor | PO decision; then a one-line change in `save` with a test |
| The durable consent store (not restorable from a backup) | — | M3 (Q21) |
| R28-F5 trim or refuse at save (key store) | Minor | PO decision; the transport already refuses line breaks |
| Real provider streams over this transport | — | WI-M2-M6 (needs the owner's keys) |

### Law check
| Law | Status | Note |
|---|---|---|
| UX-1 … UX-4 | n.a. | No UI; the error names are neutral (UX-3). |
| P-1 | n.a. | No model. |
| P-2 | pass | No networking; `Security` only in the allowlisted file. |
| P-3 | pass | Keychain only, this device only, not synchronised; deleted on turn-off, remove-key and orphan (tests). |
| P-4 | pass | Nothing written outside the Keychain item; nothing logged. |
| UX-1, UX-2, UX-4 | n.a. | No UI. |
| UX-3 | pass | Reason names are neutral (unchanged neutral types). |
| P-1 | pass | The transport is only reached on route `cloud` (router, WI-M2-09). |
| P-2 | pass | Networking only in the two allowlisted files (scan 0 violations); one host per provider; nothing else is reachable. |
| P-3 | pass | Only the builder's bytes are sent; no cookie, cache or credential store; the key only in its header. |
| P-4 | pass | Body bytes live in memory for one attempt; nothing logged or written. |

### Handoff log
| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-27 | Developer | Reviewer, Tester, PO (via the coordinator) | sent | Branch pushed, no PR. |

## Pasted-key cleanup (PO ruling R28-F5) and the open review asks on the key store (PR #45 m1, n2) and transport (PR #46 m1, m2, n1, n2)

- **Branch:** `m2/key-paste-cleanup`, from `origin/m2/cloud-transport` (`87e5710`) with `origin/m2/keychain-key-store`
  merged in (merge commit `c60b335`; PR #45 and PR #46 were not yet merged to `main`). The only merge conflict was the
  end of this file; both sections are kept.  ·  **Code commit:** `d447eb49ecb6299e4b9b10eea84f6b3a45756281`  ·  **Mac evidence
  record:** [`evidence/mac/key-paste-cleanup/`](evidence/mac/key-paste-cleanup/README.md).
- **Requirements:** AC-M2-21, AC-M2-23 (and AC-M2-18 through the router). P-3, UX-3.

### PO ruling R28-F5, as built
- **`TendIngestion/Routing/APIKeyText.swift`** (pure, Linux-tested): trims at both ends every Unicode whitespace
  (including line breaks, U+2028, NBSP), every control character (Cc, so NUL and DEL too) and U+200B, U+200C, U+200D,
  U+2060, U+FEFF; then refuses unless the result is non-empty and every character is in U+0021…U+007E. No length or
  prefix check.
- **One neutral result:** `CloudStoreError.keyTextNotAccepted` (a case with no payload: no key character, no
  position). `CloudStoreError` has 3 cases now; the case-count test changed from 2 to 3 for that reason.
- **Where it applies:** `InMemoryAPIKeyStore.save` and `KeychainAPIKeyStore.save` store the trimmed key or throw before
  writing anything (an earlier key is kept); `ModelRouter.turnCloudOn` checks first, so a refused key records no consent
  and leaves an earlier key and consent as they were; `APIKeyMask` masks the trimmed key (a refused key shows the dots
  only).
- **Transport:** `CloudRequestHeader.keyIsSendable`; `CloudHTTPTransport` refuses a request whose auth key is empty or
  outside U+0021…U+007E before any session exists (`requestNotSent`, 0 requests at the stub).
- **Expectations changed by the ruling (not weakened):** the WI-M2-M5 hosted test "any length and any characters"
  is now "any length in U+0021…U+007E" (empty and non-ASCII keys are refused and tested as such); the mask case for a
  non-ASCII key now expects the dots only, and a padded key's mask is from the trimmed key.

### Review asks
- **PR #45 m1 (kills mutant K2):** a synchronizable item with the same service and account, holding a sentinel, is not
  seen by `hasKey` or `key`; after `save` it still holds the sentinel and a separate non-synchronizable item holds the
  new key; `deleteKey` leaves it too. The Simulator accepted the planted synchronizable item. The K2 sentence in the
  WI-M2-M5 section now names the update path.
- **PR #45 n2:** stored data that is not UTF-8 reads as `storeUnavailable` (and `hasKey` is true).
- **PR #46 m1:** the headers test now checks every builder header's exact value at the stub (auth byte for byte).
- **PR #46 m2:** rows for the 7 untested codes, and a sweep over raw values −3000…0: only −999 (`cancelled`) maps to nil.
- **PR #46 n1:** the comment and the test name say no cut makes a single-byte chunk; only the final remainder can be
  shorter. **n2:** the WI-M2-M4 header backtick is closed and both sections name their PRs (#45, #46).

### AC → test
| Item | Test(s) | Command | Result |
|---|---|---|---|
| R28-F5 rule | `APIKeyTextTests`: 11 trimmed cases (`\n`, `\r\n`, spaces, tab, BOM, U+200B/U+200C, NBSP, U+2028, U+2060/U+200D, NUL/DEL, mixed); 12 refused cases (inner space, `\n`, tab, NUL, U+200B, é, DEL, empty, all-junk); every U+0021…U+007E kept; one-character key accepted; property seed `0x5EED_F5`, 2,000 padded keys, 0 mismatches | B2 | PASS |
| In-memory store and router | "padded key stored trimmed; refused key … keeps the earlier key"; "The refusal holds no character of the key and no position (sentinel)"; "Router: turning cloud on with a refused key changes nothing"; "An auth header is sendable only for a key in U+0021…U+007E" | B2 | PASS |
| Real Keychain | `KeyPasteCleanupHostedTests`: stored trimmed (item bytes read back raw) and mask from the trimmed key (5 cases); refused keeps the earlier item byte for byte (6 cases); short and full-ASCII keys; K2; non-UTF-8; the refusal never shows the key | B5 | PASS |
| Transport | `CloudHTTPTransportHostedTests`: "an auth key outside U+0021…U+007E is refused before sending; nothing reaches the stub" (3 providers × 4 keys); exact header values; 18 code rows; the −3000…0 sweep | B5 | PASS |

**Mutants (killed):** no trim (P1, 4 tests); invisible marks not trimmed (P1b, 2); transport check removed (P2); the
Keychain store skips the rule (P3); the query matches synchronizable items (K2).

### Test runs
At `d447eb4` (clean run): B1 TendCore 141 tests in 18 suites; B2 TendIngestion 579 in 68, AC-M2-09 scan 62 files, 0 violations, AC-M2-12 0 violations; B4 TendAI 3 tests; B5 hosted 34 tests in 4 suites; B6 as MS-1. All passed, 0 skipped, no compiler warnings.

### Law check
| Law | Status | Note |
|---|---|---|
| UX-3 | pass | One neutral refusal (`keyTextNotAccepted`) that blames nobody; M3 copy by the Designer. |
| P-2, P-3 | pass | A key that is not plain printable ASCII never reaches a header; nothing else is sent; the Keychain item stays this-device-only and not synchronised (K2 test). |
| P-4 | pass | Nothing written or logged; the refusal holds no key text (sentinel tests). |

## WI-M2-M2 — on-device adapter: `@Generable` schema, `PartiallyGenerated` mapping, availability and error mapping, duplicate `Tool`, prewarm (MS-2)

- **Owner:** Developer, driving the owner's Mac over Remote Control  ·  **Branch:** `m2/on-device-adapter`, based on
  `main` at `41bf8fa`  ·  **PR:** none yet (the owner merges Mac-only PRs under D-032)  ·  **ADRs:** ADR-0005,
  ADR-0006 (layout followed; the new files sit in `Packages/TendAI/Sources/TendAI/OnDevice/`, scanned by Rule 2).
- **Requirements:** ● AC-M2-05, ● AC-M2-07, ● AC-M2-10 (the Mac halves; the Linux halves are WI-M2-06, 07, 09); GR-9
  (eval-composition, `@Guide` parity). FR-A1, P-1, P-3, P-4, UX-3. R-1, R-4.
- **Mac evidence record:** [`evidence/mac/WI-M2-M2/`](evidence/mac/WI-M2-M2/README.md), for the code commit
  `94d02fe9b87cbc21b0608cc017c598c74f20eac2`.

### What changed
- **`TendAI/OnDevice/OnDeviceOutput.swift`** — the `@Generable` answer `{items: [OnDeviceItem]}`.
  - Field set and shape as the cloud schema (PO WI-M2-12 ruling 2): `title`, `room` and `sourcePhrase` are required
    strings (`""` = none), `time` is a required object with a required `anchor` (`none` = no time), the two claims are
    optional. Enum raw values equal the neutral ones (tested value by value).
  - **Declaration order is generation order:** `title`, `sourcePhrase`, `kind`, `room`, `effort`, `time`,
    `sameAsItem`, `sameAsExisting`, `isCritical`, `isDeepClean`, `isWeatherDependent`. `title` first (R-1); the claims
    before the flags (WI-M2-06 I4 suggestion, so they are usually known at emission); a `Bool` last (see below).
  - The fixed session instructions (`OnDeviceInstructions.text`) are short and hold no household data. The capture and
    the room names go in the **prompt** as a JSON object (`{"capture":…,"rooms":[…]}`), never in the instructions.
- **GR-9, one shared constant.** `TendIngestion` now has `ItemFieldMeaning`, one sentence per output field. The cloud
  instruction text is built from it (`- <field>: \(ItemFieldMeaning.<field>)`), and every on-device `@Guide` uses the
  same constant (the macro takes a constant expression; checked). The cloud text is **byte-identical** to `main`
  (compared directly in the session: equal, 2,030 bytes; and every golden-request test in B2 passes unchanged). Only
  `sameAsExisting` differs by route (on device: "the title of a task that findExistingTasks returned …", WI-M2-07 D1).
- **`OnDeviceSnapshotMapping.swift`** — `PartiallyGenerated` → `IngestionSnapshot`, **finished values only** (J2, PO
  WI-M2-12 ruling 1). Probed on this Mac: a `PartiallyGenerated` value shows a string while it grows (`"Buy di"`) and
  an integer while it grows; it never shows half an enum value (that prefix does not parse). Rule: a property is
  finished when a later property of the same item has started, or the item is not the last one (rule b), or the stream
  finished normally (rule c). The last property is a `Bool`, shown only once written. So rule (a) fires only when every
  field is whole, and the `""` / `"Late"` prefixes of WI-M2-12 J2 never reach the assembler.
- **`OnDeviceStopMapping.swift`** — exhaustive switches with no `default`:
  - `SystemLanguageModel.Availability` (frozen) and its `UnavailableReason` (not frozen, so a `@unknown default`,
    read as `modelNotReady`) and `supportsLocale` → `OnDeviceAvailability` (an unavailable model wins over the locale).
  - `LanguageModelSession.GenerationError`, every case (iOS 26) → `ModelStopReason`.
  - **SDK note:** the Mac has Xcode 27.2 with the iOS 27.2 / macOS 27.2 SDK (deployment target 26.0). iOS 27 deprecates
    `GenerationError` in favour of `LanguageModelError`, `LanguageModelSession.Error`, `SystemLanguageModel.Error` and
    `GeneratedContent.ParsingError`. The B4 host runs macOS 27.2, so it throws the new family. Both families are mapped
    (the new one behind `#available`), every case. No deprecation warning at the 26.0 target.
- **`DuplicateLookupTool.swift`** — the `findExistingTasks` `Tool`. Its `call` returns `DuplicateLookupLog.lookUp` (WI-M2-07)
  as `{tasks: [{title, kind, room?}]}`: exactly the shortlist, reduced to title, kind and room name. The log lives in
  an actor (`DuplicateLookupRecorder`), so the Tool is `Sendable` with no lock and no `@unchecked`.
- **`OnDeviceIngestionModel.swift`** — the `IngestionModel` (contract items 1–4): one `LanguageModelSession` per
  capture (`streamResponse(to:generating:options:)`, greedy sampling); stops thrown as `ModelStopReason`; no reference
  kept to the stream; `onTermination` cancels the generation task; a stream made inside a cancelled task starts nothing;
  every snapshot carries the Tool's queries so far, and after a normal end one more snapshot carries the whole answer
  (`isFinal`) and the final queries.
- **`FoundationModelsOnDeviceSource.swift`** — the `OnDeviceModelSource` for `ModelRouter`, and `prewarm(household:)`
  (Q4): it prepares and prewarms the next capture's session; the next `model(household:)` with an **equal** household
  takes it once (an actor slot, no lock).
- **`TendIngestion`, two small API changes:**
  - `OnDeviceModelSource.model()` → `model(household:)`. The router passes the capture's household, the one its
    `DraftDuplicateRules.onDevice(household:)` reads, so the Tool reads exactly that value (contract item 4). Before
    this the adapter had no way to get it. The test-only `events(for:preference:)` gained a defaulted `household:`.
  - `ItemFieldMeaning` (above).
- **Tests:** `TendAITests` grew from 1 to 47 tests (6 suites). `TendIngestionTests` +1 (`RouteWiringTests`:
  "WI-M2-M2: the on-device model is asked for with the capture's own household"), and the test source
  `FixedOnDevice` records the households it was asked for.
- **Scan:** AC-M2-09 over 63 files (TendIngestion 55, TendAI 7, TendEval 1), 0 violations. A first draft used
  `AsyncThrowingStream.makeStream(of:)`, which the AC-M1-23 `Stream(` call rule catches (only the `AsyncThrowingStream(`
  initialiser is exempt); it now uses the initialiser.

### AC → test (command: B4 for `TendAITests`, B2 for `TendIngestionTests`)
| AC | Test(s) | Result |
|---|---|---|
| AC-M2-05 (on-device mapping) | `OnDeviceSnapshotMappingTests`: "A title still being written is not shown …", "The prefix \"Late\" of \"Later: call the plumber\" never appears …", "A number still being written …", "Rule (a) fires only when the last property is written …", "An item is whole once the next item has started (rule b) …", "A field never changes once shown, over every growing prefix …" (steps 1, 2, 3, 7); `OnDeviceModelTests` through the real `DraftPipeline`: "\"Later: call the plumber\" streamed in small steps gives one emitted with the whole title, never a skip" (steps 1, 2, 3, 5), "emission happens at completion …", "an item in progress when the stream finishes normally is completed (rule c) …", "at a normal finish the last answer's last string is whole (rule c) …", "a throw mid-item after a draft gives interrupted …", "cancelling ends with cancelled and ends the model's work" | PASS (B4) |
| AC-M2-07 (`Tool` conformance) | `DuplicateLookupToolTests`: "the Tool returns exactly the duplicate shortlist for its query, as title, kind and room name" (8 queries: > 10 eligible, completed left out, room-only, stop-word-only, empty), "More than 10 eligible tasks give the first 10 …", "Each entry holds only title, kind and room …" (Mirror and schema), "records each query … never changes it (Q7)", "name, description and argument schema hold no household data"; `OnDeviceModelTests`: "a title the Tool returned marks the draft ofExisting; the Tool's log equals the final queries", "a title the Tool never returned is not a claim …", "A repeat within one input collapses into its first draft", "Contract 4 …" (2 tests), "The source gives a model whose Tool reads exactly the capture's household", router test | PASS (B4) |
| AC-M2-10 (adapter mapping) | `OnDeviceStopMappingTests`: every `Availability` case × `supportsLocale` (all four neutral reasons reached), every `GenerationError` case, every iOS 27 error case, pass-through; `OnDeviceModelTests`: "generation that throws before the first draft ends noModel, on device …" (9 errors), "Through the router: an unavailable on-device model with cloud off ends noModel and starts no generation" (cloud source never asked) | PASS (B4) |
| GR-9 | `OnDeviceSchemaTests`: "every on-device @Guide description is the cloud instruction line for the same field, word for word" (10 fields, read from the encoded `GenerationSchema`), "the isCritical sentence is PO ruling 3's …", "sameAsExisting on device names a title the Tool returned …" | PASS (B4) |
| Schema shape | `OnDeviceSchemaTests`: generation order, required fields, closed lists, prompt and instructions, calm words (AC-M2-12) | PASS (B4) |
| Router passes the household | `RouteWiringTests` "WI-M2-M2: …" | PASS (B2) |

**Mutants (each run, then reverted; all killed):** open string counted as a value (M1, 5 tests fail); no final
`isFinal` snapshot (M2); `onTermination` does not cancel (M3); locale ignored (M4); guardrail read as refusal (M5); no
cancelled-at-creation check (M6); prepared session given to any household (M7) or reused (M10); title claim dropped
(M8); no extra snapshot for a late Tool call (M9); Tool drops the room (M11); `/` escaped in the prompt (M12). M2 first
survived; the test "at a normal finish the last answer's last string is whole (rule c) …" was added and kills it.

### Real model on this Mac (information only, never evidence; R-1)
A throwaway probe in the session scratchpad ran the real session on macOS 27.2.1 (M1 Mac mini, availability
`available`), with the Outcome sentence, a household of 2 rooms and 1 task ("Buy dishwasher pods", Kitchen), prewarmed,
4 runs (logs: [`probes/`](evidence/mac/WI-M2-M2/probes/)).
- **Behaviour:** every run gave the same 3 drafts, route `onDevice`, outcome `completed`. The model called the Tool 3
  times (`"dishwasher pods"`, `"AC servicing"`, `"mop kitchen floor"`) before the answer. Draft 1 was marked
  `ofExisting` the pods task through its Tool title claim. No skip, no update.
- **Timing (pipeline TTFI = first `emitted`):** run 1 (cold) 7.94 s; runs 2–4 6.32, 6.37, 6.32 s. Total 10.8–12.5 s.
- **Split (same prompt, raw session, 3 runs each):** with the Tool, first snapshot 4.21–4.31 s, first item complete
  6.24–6.35 s; with no Tool, first snapshot 2.27–2.83 s, first item complete 3.46–4.01 s (runs 2 and 3 overlapped a
  compile in the session; an earlier quiet run gave 2.33–2.35 s and 3.51–3.56 s).
- **What it says:** the Tool calls cost about 2 s before the first token, and the schema with the shared guide
  sentences costs about 1 s more than the MS-1 7-field probe (1.35 s to a first non-empty title, which is not item
  completion). On this Mac the adapter misses the AC-M2-16 bound (TTFI < 1.5 s) by a wide margin. The iPhone 15 Pro is
  the gate, not this Mac, and AC-M2-16 is never relaxed; R-1 is now **likely**. Technical levers that keep the
  product meaning (my next steps if the Planner agrees): ask for at most one Tool call per capture (all the main words
  at once), shorten the guide sentences in both routes together (GR-9 keeps them equal; changes the golden bytes, so
  before the AC-M2-14 freeze), and measure on the iPhone in SP-1. Dropping the Tool would change AC-M2-07 and is a PO
  matter.

### Test runs (R-18; the evidence record has the logs)
The clean run at `94d02fe` (`build/`, every package `.build` and the project's DerivedData deleted first).

| Command | Result | Runtime |
|---|---|---|
| B1 `swift test` TendCore | 141 tests in 18 suites passed, 0 skipped, 0 warnings | 44 s wall |
| B2 `swift test` TendIngestion | 572 tests in 67 suites passed, 0 skipped, 0 warnings; scan 63 files, 0 violations | 98 s wall (tests 71.4 s) |
| B4 `xcodebuild test -scheme TendAI` (macOS) | 47 tests in 6 suites passed, `TEST SUCCEEDED` | 14 s |
| B5 `xcodebuild test -scheme TendAIHostedTests` (iPhone 17 Pro, iOS 26.5) | 2 tests passed, `TEST SUCCEEDED` | 19 s |
| B6 Release build and archive of `Tend`; `TendEval` Debug build; `TendEval` archive refused (66) | as MS-1; both `find`s print nothing | 5 + 3 + 11 + 1 s |

### Verification environment
| Check | Linux `swift test` | macOS (owner-run Mac) | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| TendCore | not rerun | pass (B1) | n.a. | n.a. | — |
| TendIngestion (incl. AC-M2-09 scan, goldens) | not rerun (CI runs it) | pass (B2) | n.a. | n.a. | — |
| TendAI on-device adapter | n.a. (Apple-only) | pass (B4, 47 tests) | B5 builds TendAI for iOS; no hosted on-device test (the Simulator has no usable model, MS-1) | n.a. | The real model's answers: information-only probe above; DS-1 runs it |
| AC-M2-16 timing | n.a. | probe only (misses on the Mac) | n.a. | DS-1 | SP-1 / DS-1 |

### Things the reviewer should look at closely
- The finished-values rule rests on FoundationModels generating properties in declaration order and never showing
  half a `Bool` or enum value. Both are what the framework documents and what the probe and tests show; if a later SDK
  breaks it, `OnDeviceSchemaTests` "Generation order …" and the mapping tests fail.
- `@unknown default` appears five times, only where the framework enum is not frozen (Swift 6 requires it). None is a
  plain `default`, and each switch still lists every known case (a missing one is a warning, an error here).
- `unsupportedGuide` / `unsupportedGenerationGuide`, `unsupportedCapability`, `unsupportedTranscriptContent` and
  `transcriptMutationWhileResponding` map to `otherModelError` (a defect on our side, not the person's).
  `LanguageModelError.timeout` maps to `timedOut`.
- `prewarm(household:)` prewarms a session for one household; a capture for a different household gets a fresh,
  unwarmed session (correctness over speed: the Tool must read the capture's household).
- The protocol change in `TendIngestion` is the only change to an accepted Linux API.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| R-1: on this Mac the on-device TTFI is about 6.3 s with the Tool (probe above) | **Major risk for AC-M2-16** (information only; the gate is the iPhone) | Planner / PO: SP-1 on the iPhone 15 Pro; technical levers above before the AC-M2-14 freeze |
| Orientation build-validation warning for `Tend` and `TendEval` (review PR #38 m1(a)) is still in B6 | Minor | Designer decides the iPad orientation set (CLAUDE.md §9 Q1); `project.yml` change after that |
| The device check that a real iPhone shows no partial value and calls the Tool | — | DS-1 (Tester) |

### Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface; the draft stream is a capture review (Q11). |
| UX-3 Zero-Guilt | pass | No new outcome or reason name; every guide, instruction and Tool text passes the banned-token rule (test). No partial "Late" title reaches the guard. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The adapter runs `FoundationModels` only; an on-device error is thrown as a stop reason and never reaches the cloud (router test: cloud source never asked). |
| P-2 No data leaves device | pass | No networking (Rule 2 scan, 0 violations). |
| P-3 Cloud AI opt-in, minimised | pass | The cloud instruction bytes are unchanged; the on-device and cloud models are asked the same thing (GR-9). |
| P-4 Media not persisted | pass | The prompt and answers live in memory for the capture; nothing is written or logged. |

### Handoff log
| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-27 | Coordinator | Developer (owner's Mac) | accepted | MS-2 brief, items M2, M3, M5, M4 in that order. |
| 2026-11-27 | Developer | Reviewer, Tester, PO (via the coordinator) | sent | Branch pushed, no PR. R-1 numbers for the Planner and PO. |

## WI-M2-M2 round 2 — review PR #41 m1 (framework cancel), PO R-1 ruling (a) (one Tool call per capture), nits n1 and n3

- **Branch:** `m2/on-device-adapter-v2` (the orchestrator re-created the branch with a neutral commit identity; same
  trees as `m2/on-device-adapter`), on top of the review commit `ff79f9c`  ·  **Code commit:** `fad715a3d1f81cadd17a9403b96dca12c3ba231d`  ·
  **Mac evidence record:** [`evidence/mac/WI-M2-M2-r2/`](evidence/mac/WI-M2-M2-r2/README.md).
- Review PR #41 M1 (commit identity) is handled by the re-created branch and the repo-local identity
  `Claude <noreply@anthropic.com>`; every commit here uses it.

### What changed
- **m1** (`OnDeviceIngestionModel.swift`): only a parse the consumer cancelled finishes the model stream quietly. A
  `CancellationError` the framework throws while the parse is not cancelled now goes through `OnDeviceStopMapping`
  (`otherModelError`), so it ends `interrupted` after a draft and `noModel` before one (AC-M2-05, AC-M2-10), never
  `completed`.
- **PO R-1 ruling (a): the duplicate-lookup Tool is answered at most once per capture, enforced in code.**
  `DuplicateLookupRecorder.answeredCallLimit = 1`. The first call gets exactly the shortlist and is recorded; every
  later call gets no entries, is **not** recorded (so `IngestionSnapshot.lookupQueries` and the rules' replay hold
  exactly what the model was shown, D1 unchanged), and is counted in `refusedCalls` (information). Re-mark on log
  growth is unchanged. A repeat that only a refused call would have found is still marked by the word-match floor.
  The instructions now say "call findExistingTasks once, with the main words of all the chores together"; the Tool's
  description and argument guide say the same.
- **n1:** the order comment no longer says `title` first helps TTFI (emission is at item completion).
- **n3:** the test script's `.hang` sleeps instead of spinning; it can also throw `CancellationError` on cancel, for the
  m1 tests.
- One existing test changed its expectation because the rule changed (not a weakening): "The Tool records the answered
  query …" now expects `["pods"]` and one refused call; the contract-4 snapshot test now expects `["pods"]` in every
  snapshot.

### AC → test (B4)
| Item | Test(s) | Result |
|---|---|---|
| m1 | `OnDeviceFollowUpTests`: "a CancellationError the consumer did not ask for, after a draft, ends interrupted", "… before any draft, ends noModel", "a cancel the consumer asked for still ends cancelled, even when the framework then throws CancellationError", "the model stream itself finishes without an error when its parse was cancelled and the framework throws" | PASS |
| R-1 (a) | "the first Tool call is answered with the shortlist; every later call gets no entries and is not recorded", "the snapshots carry only the one answered query, so the rules replay exactly what the model saw" (title claim still marks `ofExisting`), "a repeat that only a refused second call would have found is still marked, by the word-match floor", "the instructions and the Tool description ask for one call …" | PASS |

**Mutants (killed):** no cap (limit 100, R1, 5 tests); a refused call still answered (R2, 5 tests); framework
`CancellationError` read as a normal end (C1, 2 tests).

### Developer dev set (information only; never the frozen eval)
A throwaway probe in the session scratchpad ([`probes/`](evidence/mac/WI-M2-M2-r2/probes/)): 8 captures I wrote, a
household of 8 tasks in 3 rooms, 17 expected chores (8 repeats of an existing task, 9 new). Same Mac, real session,
prewarmed, one run each, before (`ff79f9c`) and after (`fad715a`):

| | Before (no cap) | After (one call) |
|---|---|---|
| Tool calls answered | 17 (one per chore) | 8 (one per capture; the model asked once with all the words) |
| Duplicates created (a repeat left unmarked) | 2 | 2 (the same two: "dishwasher tablets" vs "Buy dishwasher pods", "Kettle needs descaling" vs "Descale the kettle") |
| False merges | 0 | 0 |
| Chores found | 16 of 17 | 16 of 17 (the smoke-alarm battery chore got a title without "smoke" in both runs) |
| TTFI median (range), s | 5.87 (5.52–7.20) | 5.31 (4.95–5.67) |

No worse on duplicates or false merges; about 0.5 s faster to the first item. Still far above AC-M2-16's 1.5 s on
this Mac (R-1 stays likely; the iPhone 15 Pro is the gate).

### Eval manifest (for the PO; asked by the orchestrator)
- `Fixtures/M2/eval/MANIFEST.sha256` lists **4 files**: `golden.json`, `household.json`, `inputs.json`,
  `results-v1.schema.json` (not itself). This branch changes none of them.
- The AC-M2-14 freeze test pins **3** of them by SHA-256 in `EvalFreeze.approvedSHA256`,
  `Packages/TendIngestion/Tests/TendIngestionTests/EvalFreezeTests.swift:34-38` (`inputs.json` line 35,
  `household.json` line 36, `golden.json` line 37). `results-v1.schema.json` is covered by the manifest only.

### Test runs
At `fad715a` (clean run): B1 TendCore 141 tests in 18 suites; B2 TendIngestion 572 in 67, AC-M2-09 scan 63 files (TendAI 7), 0 violations; B4 TendAI 55 tests in 7 suites; B5 hosted 2; B6 as MS-1. All passed, 0 skipped, no compiler warnings.

### WI-M2-M2: brought up to date with main (PRs #45, #46, #47 merged)
- `origin/main` (`9e50012`) merged into `m2/on-device-adapter-v2` as `bd7be36` (merge commit; no rebase). The only
  conflict was this file: main's text is kept as it is and the two WI-M2-M2 sections follow it. Build fix `f4dd2ab`: the
  PR #45 hosted Keychain test helper now implements `OnDeviceModelSource.model(household:)` (the PR #43 rename); test
  helper only. Mac evidence record for `f4dd2ab`: [`evidence/mac/WI-M2-M2-main-merge/`](evidence/mac/WI-M2-M2-main-merge/README.md):
  B1 TendCore 141; B2 TendIngestion 580, scan 68 files, 0 violations; B4 TendAI 57; B5 hosted 34; B6 as MS-1; all passed,
  0 skipped, clean tree before and after.
