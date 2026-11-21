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
