# M2 Code Review — PR #51 (`m2/scanner-loader-exception`, head `b88c384`, base `main` `65c06cd`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE** (round 2, head `9126548`; round 1 was CHANGES REQUIRED)  ·  **Round:** 2
- **Scope:** `git diff 65c06cd b88c384`, 9 files (+1237 / -25): `TendSourceScan/FixturesLoaderRule.swift` (new),
  `IngestionSourceRules.swift`, `SourceScanner.swift` (lexer), `Q23LoaderTests.swift` (new), `Q24RulesTests.swift`,
  `IngestionSourceRulesTests.swift`, TendIngestion `ScanScope.swift` and `IngestionSourceScanTests.swift`,
  `dev-notes.md` (section "M2 Q23 — scanner follow-up").
- **Checked against:** brief AC-M2-09 (Rule 6 "Fixtures-loader exception (M2 Q23)", the Q23 plants and positive, "The
  Reviewer confirms that the loader reads only bundle resources") and the Q23 row of the question table; plan "Named
  files" (fixtures loader row), the WI-M2-01 timing note for Q23 and the Developer constraints; the real loader
  `Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift` on `origin/m2/eval-harness` at `e014fab`.
- **IDs:** AC-M2-09 (Rule 6, M2 Q23), AC-M2-28, AC-M1-23 (cross-reference, exception (ii)), WI-M2-M7, P-2, P-4.
- **Milestone lock:** `STATUS.md` shows M2 `IN-BUILD`; this is M2 work on an `m2/` branch. No M3+ work. OK.

## Summary

The exception is well built and mostly as narrow as the brief says. It applies only in the one named file, only
for the `TendEval` module, and only to the exact `return try Data(contentsOf: <name>)` read. `<name>` must be bound
once by a literal-only `Bundle.main.url(forResource:…)`. Every other rule and list is unchanged. The lexer change does
not change any existing result: I compared the old and new lexers on 228 inputs and they were identical. The real
loader on `origin/m2/eval-harness` passes the rule cleanly: the repository scan reports 79 files and 0 violations, and
the same file gets 4 `contentsOf:` hits under any other path. The replaced test (`loaderFileIsStrictUntilQ23` →
`loaderFileExceptionIsNarrow`) is a fair replacement of a planned temporary state, not a weakening.

I tried 29 bypass plants of my own. One is a **Major** bypass. A `#if` block whose condition is never set can hold the
`Bundle.main.url` binding. The compiler drops it, the read then uses a same-named `static let` declared in another
TendEval file, and the scan reports nothing. I built a two-file proof with `-warnings-as-errors`. It compiles cleanly
and reads a file that is not in the bundle. So the exception is wider than the brief's "bound … by
`Bundle.main.url(forResource:`". There are also three Minor findings, one Nit and one Info note. **CHANGES REQUIRED**
until F1 is fixed.

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | **Major** | `FixturesLoaderRule.swift:278` (`isAllowedRead`), `:316` (`functionBody`); no handling of compiler directives anywhere in the rule | **A binding inside an inactive `#if` block counts as the binding.** The loader file below reports **0 findings**. Its only `inputsFile` binding is inside `#if NEVER_DEFINED … #endif`, so the compiler drops it. `inputsFile` then resolves to `extension EvalFixturesLoader { static let inputsFile = <any URL> }` in another TendEval file. In the results writer, where `FileManager` is allowed, that file also reports **0 findings** (in any other TendEval file the only hit is `write API FileManager`). I built this two-file program with Swift 6.2 and `-warnings-as-errors` (the same setting as `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` in `project.yml`). It compiled with no warning, and running it printed `read 13 bytes from a non-bundle path`. The compiler does not type-check code in an inactive block, so it gives no "never used" warning. This breaks the brief's "`<name>` … is bound in the same file by `guard let <name> = Bundle.main.url(forResource:`" (AC-M2-09 Rule 6, M2 Q23). In the compiled program it is not bound by that call. It also breaks "The Reviewer confirms that the loader reads only bundle resources", which the scan is meant to keep true when the loader is edited later. Loader text: `static func inputs() throws -> Data {` / `#if NEVER_DEFINED` / `guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else { throw LoaderError.missing }` / `#endif` / `return try Data(contentsOf: inputsFile)` / `}` | In the loader file, report every compiler-directive line (`#if`, `#elseif`, `#else`, `#endif`; also `#sourceLocation`) as a loader finding. This is stricter only, and the real loader at `e014fab` has none. Add a plant test with the text above, and a second one where the read sits inside an `#if` block. Keep the check fail-closed: any `#` directive, not only `#if`. | Open |
| F2 | Minor | `FixturesLoaderRule.swift:278`, `:316` | **The scope check is "same function body", not "the binding is in scope at the read".** `functionBody` skips control-flow blocks. So the scan also accepts each of these: `if let u = Bundle.main.url(…) { }` then `return try Data(contentsOf: u)` after the `if`; `guard let u = …` inside `do { }`, `for … { }` or `if … { }` with the read after that block; and `if let u = … { throw … } else { return try Data(contentsOf: u) }` (my plants P01, P02, P12, P29, all 0 findings). In each case the read uses an outer `u`, not the binding. Today only the compiler's "value 'u' was defined but never used" warning, made an error by `project.yml`, stops this from building. The Linux scan cannot see that setting. Not Major, because it does not build under the current settings. | Require lexical scope: for `let` / `guard let`, the read's innermost `{` must be the binding's innermost `{` or nested inside it, with no function or closure boundary between them. For `if let`, the read must be inside the `{ … }` block that directly follows the call. Add the four plants above. This is best done together with F1, since it is the same function. | Open (ticket) |
| F3 | Minor | `FixturesLoaderRule.swift` (no check on `Data` / `typealias`) | **Shadowing `Data` in the loader file.** `typealias Data = String` at the top of the loader, with the brief's positive below it, reports 0 findings (P07). That is `String(contentsOf:` (a brief plant) under another name. It reads only a bundle resource, so there is no privacy loss, but it breaks "returns the bytes as `Data`". Shadowing across files is outside what a text scan can see: `enum Bundle { static let main = … }`, `typealias Data = …` or `extension Foundation.Bundle` in another TendEval file each report 0 findings there (P22, P23, P25). The brief leaves this to the Reviewer. I confirmed that the real harness at `e014fab` has no such declaration (the only other `Bundle` use is `Bundle.main.object(forInfoDictionaryKey:)` in `EvalRunner.swift`). | In the loader file, report `typealias` and any declaration named `Data` or `Bundle`. Add "no TendEval file declares or extends a type named `Bundle` or `Data`, and no `typealias` of either" to the Reviewer confirmation in the dev-notes (or a cheap module-wide check). | Open (ticket) |
| F4 | Minor | `Q23LoaderTests.swift:306` ("bound after the call"), `:378`; `FixturesLoaderRule.swift:246`, `:276`, `:505` | **Some conditions have no test that isolates them.** My mutants (each applied alone; full `TendSourceScan` suite run): **killed** with `>= 2` occurrences (m01), the function-body check off (m02), `bindingEnds` off (m04), the `}`/`;` follow check off (m05), the `://` check off (m07), the `URL` token check off (m08), the parameter checks off (m10), a loose resource pattern (m12), the lexer `codeCount` frozen (m13), and the exception applied to every TendEval file (m14). **Survived:** m09 (`binding.nameOffset < argument.startOffset` → `true`). The "bound after the call" plant is caught only because `let` follows the read, so the follow check rejects it first. Also survived: m03 (`startsStatement` off; `bindingEnds` covers every current plant), m06 (`!hasInterpolation` off; an interpolated value is never blank code) and m11 (`inside.count == 1` → `>= 1`). For m11 no plant puts a literal inside an interpolation, e.g. `forResource: "\("fixtures")"`, which the real code rejects only by the count. | Add `return try Data(contentsOf: u); let u = Bundle.main.url(forResource: "fixtures")` (kills m09) and `forResource: "\("fixtures")"` (kills m11). Either add a plant that only `startsStatement` catches, or note in the file header that it is defence in depth. | Open (ticket) |
| F5 | Nit | `dev-notes.md:6353` | "The real loader file does not exist yet" is out of date. `origin/m2/eval-harness` at `e014fab` has the loader, and it passes (see "Real loader fit" below). | Update the note and the "Not verified" row when F1 is fixed. | Open |
| I1 | Info | `SourceScanner.swift:30` (pre-existing) | A known limit that this PR does not change: regex literals are lexed as code, so `let a = /"/, b = try String(contentsOf: Bundle.main.resourceURL!), c = /"/` hides everything between the two `"` from every rule, in every file. It also hides it in the loader file (P08, 0 findings). This was documented before this PR as a Reviewer check. The real loader has no `/` outside comments. | None for this PR. A lexer fix would cover all of AC-M1-23 and AC-M2-09, so it should be its own ticket if the PO wants it. | Info |

## What I checked and how

### The exception is only where the brief allows it
- **One file, one module.** The filter runs only in `rule6` (TendEval) and only when
  `facts.file.path == configuration.fixturesLoaderFile` (`IngestionSourceRules.swift`). The brief's positive is still a
  `contentsOf:` hit in 8 other places (the PR's own test) and in my plants P13 (TendAI file), P14 (TendIngestion, also
  the AC-M1-23 hit) and P18 (the loader path under module TendAI). Mutant m14 (exception in every TendEval file) is
  killed by 6 tests.
- **Only the literal shape.** Here is what the scan does with each plant (P = my plant; none are in the PR):
  - Caught: a second read of the same name (P05: both reads reported); an interpolated resource with code inside it
    (P10); a read in a nested function (P28); a capture list `[u = other]` (P27); a read inside a closure assigned to a
    stored property (P20); `#if` around the read only (P19, no binding in scope at the read).
  - Caught in the loader file: write and log APIs, `Logger(` (P16) and `write(to:` in another function (P17).
  - Not caught, and correctly so: the multi-line form (P06), the read inside the `if let` block (P11), a parameterless
    closure that holds both the binding and the read (P21), and a read in a `switch` case (P26). These pass and fit the
    brief.
  - Not caught, and wrongly so: P03 with P04 (F1); P01, P02, P12 and P29 (F2); P07 (F3); P08 (I1).
  - The PR's own 80 condition plants, 7 brief plants and the comment and string checks also pass.
- **No other rule or list got looser.** `networkingViolations` only gained `allowedContentsOfOffsets` (default empty).
  Only Rule 6 passes a non-empty set, and only in the loader file. A hit with no offset is never removed (fail
  closed). `allPatterns` only gained patterns, so the compile self-test covers more. Rules 1–5, every list, the Q24
  call matching and the Rule 6 imports, write list and log list are unchanged in the diff. Write and log APIs stay hits
  in the loader file, because it is not the results writer.
- **`IngestionScanConfiguration.init` gained a required parameter.** Any other branch that builds its own configuration
  will fail to compile until it passes the loader path. That is loud and intended.

### Changed test (not weakened)
`Q24RulesTests.loaderFileIsStrictUntilQ23` recorded the planned WI-M2-01 state: "WI-M2-01 round 2 stays strict: it has
no loader exception" (plan, WI-M2-01 note; Q23 "a scanner follow-up … merged before WI-M2-M7 opens for review"). Q23 is
the PO decision that ends that state, so the old assertion now has to flip. The replacement
`loaderFileExceptionIsNarrow`:
- asserts the positive now passes in the loader file;
- adds an assertion that the same text is still caught in another TendEval file;
- keeps the `String(contentsOf:` assertion unchanged.

The R1-F1 table in `IngestionSourceRulesTests` now also runs in the loader file, which is stricter. **Fair replacement,
not a weakening.**

### Lexer change (whole string literal spans)
- Every `code.append` became `appendCode`, which appends the same scalar and counts it. The one remaining
  `code.append` is inside `appendCode`. `stringLiterals` is a new output. `code` and `literals` are built exactly as
  before.
- **Differential run:** I lexed 227 `.swift` files from the repository with the real eval harness in place (all
  packages, `Apps/`, tests), plus a hand-made edge file (interpolation, raw `#"…\#(…)"#` and `##"…"#…"##`, a multi-line
  string with a nested literal inside an interpolation, an unterminated string, nested block comments, `"//"`, `\u{…}`).
  I compared the base (`65c06cd`) lexer with the head lexer. `code`, the literal texts and the literal lines were
  identical for all 228 inputs, and every new span was in range.
- Mutant m13 (span count frozen) is killed by 12 issues.

### Real loader fit (`origin/m2/eval-harness` `e014fab`)
- The loader has four static functions, `inputs()`, `household()`, `golden()` and `manifest()`. Each one is
  `guard let <x>File = Bundle.main.url(forResource: "<lit>", withExtension: "<lit>") else { throw LoaderError.missing }`
  then `return try Data(contentsOf: <x>File)`. Each name is used once, no function has a parameter, there is no `URL`
  token and no `#if`, and the only `Bundle` use is the lookup. The literals are `inputs`, `household`, `golden`,
  `MANIFEST`, `json` and `sha256`, and all match the brief's patterns. It fits the rule **cleanly**, with nothing
  forced or awkward.
- **Repository scan** with `Apps/TendEval` replaced by `git archive origin/m2/eval-harness Apps/TendEval`:
  - TendIngestion: 581 tests in 68 suites passed.
  - `AC-M2-09 scan`: TendIngestion 56, TendAI 15, TendEval 8, "79 files in total, 0 violations".
  - AC-M2-12 vocabulary scan: 79 files, 0 violations.
- **Direct check:** the real loader text gives 0 findings at the loader path and 4 `networking contentsOf:` findings at
  any other TendEval path. So it passes because of the exception, not because nothing was scanned.
- **Reviewer confirmation (brief):** at `e014fab` the loader reads only bundle resources. No TendEval file shadows or
  extends `Bundle` or `Data`, and nothing declares a static or global that has the loader's bound names. Re-confirm at
  WI-M2-M7 review, after F1 is fixed.

### Runs (Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, one scratch copy per run, tree at `b88c384`)
| Package | Result |
|---|---|
| `TendSourceScan` | 78 tests in 5 suites passed, 0 warnings |
| `TendIngestion` (includes the AC-M2-09 repository scan: 72 files, 0 violations) | 581 tests in 68 suites passed, 0 warnings |
| `TendCore` | 141 tests in 18 suites passed, 0 warnings |
| `TendIngestion` with the real `Apps/TendEval` from `e014fab` | 581 tests in 68 suites passed; scan 79 files, 0 violations |
| Mutants m01–m14 (scratch copies; reverted by deletion) | 10 killed, 4 survived (see F4) |
| F1 proof (two-file Swift 6 package, Linux Foundation) | Build complete with `-warnings-as-errors`, no warnings; prints "read 13 bytes from a non-bundle path"; the scan of both files reports 0 findings (the second file placed at the results-writer path) |

Every check here was run on Linux. I verified nothing on macOS, the Simulator or a device; nothing in this PR needs
them.

## Checklist
- [x] Correctness vs ACs: AC-M2-09 Rule 6 Q23 positive and every brief plant are tested and pass. **Exception: F1, a
  bypass of the Q23 binding condition.**
- [x] Tests meaningful (would fail if code broke): 10 of 14 mutants killed; gaps in F4.
- [x] Swift 6 concurrency safe: value types only, no shared state, no `@unchecked`, no `nonisolated(unsafe)`.
- [x] No force unwraps / `try!` in product code paths (test-only library).
- [ ] Privacy (P-1…P-4): **concern F1** (P-4: the guard meant to keep the loader to bundle resources can be bypassed).
- [x] UX-2/UX-3 enforced in engine: n.a. (no selection surface; no user copy).
- [x] Accessibility (UI): n.a.
- [x] Performance: O(n) brace maps; the `isControlFlowBlock` back-walk only happens per binding and read in one file.
- [x] No new dependency without ADR: none added (Foundation only; ADR-0006 scan library).

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Test-only scan library; no UI or entry path. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No user copy. Check names are neutral. The AC-M2-12 vocabulary scan stays green (79 files, 0 violations). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No model path touched. |
| P-2 No data leaves device (except user iCloud) | pass | No networking added. Every networking pattern stays a hit in the loader file (`URLSession`, `NSURL` tested). Rules 3 and 4 unchanged. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path touched. |
| P-4 Media not persisted without consent | **concern (F1)** | Write and log APIs stay hits in the loader file, so nothing can be persisted or logged there. But F1 lets the loader read a file outside the bundle while the scan stays green, which defeats the "reads only bundle resources" guard (AC-M2-09 Rule 6, Q23). It closes when the loader rule rejects compiler directives. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-28 | Developer (via Orchestrator) | Reviewer | received | PR #51 `m2/scanner-loader-exception` head `b88c384`, base `65c06cd`. |
| 2026-11-28 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: F1 Major (inactive `#if` binding bypass, proof built). F2–F4 Minor (ticket; F2 and F4 are best fixed with F1), F5 Nit, I1 Info. Re-review checks the F1 plants and re-runs the real-loader fit. Must merge before WI-M2-M7 opens for review (plan). |

---

## Round 2 — head `9126548` (review of `git diff 0a3dc32 9126548`)

- **Verdict:** **APPROVE**. There is no open Blocker or Major. Two new Minors (F6, F7) and one Nit (N1) need a ticket
  and do not block.
- **Scope:** `FixturesLoaderRule.swift` (+148 / -28), `Q23LoaderTests.swift` (+172), `dev-notes.md` (round 2 section).
  No other source file changed, so every other rule and list is still the round 1 state I checked.
- **Real loader:** `origin/m2/eval-harness` at `32a6be8`. `EvalFixturesLoader.swift` is byte-identical to `e014fab`.
- **IDs:** AC-M2-09 (Rule 6, M2 Q23), AC-M2-28, WI-M2-M7, P-2, P-4.

### Summary (round 2)

All five round 1 findings are fixed, and I checked each one in the new code:
- **F1:** every `#` left in code in the loader file is reported, and with any of them no read is allowed.
- **F2:** "in scope at the read" replaces "same function body".
- **F3:** a `typealias`, or any declaration named `Data` or `Bundle`, is reported in the loader file.
- **F4:** the new plants kill m03, m06 and m11. m09 is now an equivalent mutant (explained below).
- **F5:** the dev-notes text is corrected.

Results:
- My #if proof and the four F2 forms are caught.
- 12 new bypass attempts aimed at the new scope logic are handled correctly, with one exception (F6).
- 18 of 20 mutants are killed.
- The real loader still fits with 0 findings.

**F6 (Minor):** a regex literal can still hide `#if` lines from the lexer. This revives the F1 effect: a two-file
program compiles cleanly with `-warnings-as-errors` and reads a file outside the bundle. It is the pre-existing
regex-literal limit of the lexer (round 1 I1), not new logic in this PR. Unlike F1, nobody writes it by accident: it
needs deliberate `_ = /"""/` lines around the directives. So it is Minor with a cheap fix, not a block.

### Round 1 findings, re-checked

| # | Round 1 | Fix (code) | Evidence (round 2) | Status |
|---|---|---|---|---|
| F1 | Major | `FixturesLoaderRule.swift:237-246`: `loaderDirectivePattern` `#\s*[\p{L}_]*` over lexed code; each hit reported; `guard directives.isEmpty else { return result }` | My round 1 proof loader now gives `compiler directive or # name` ×2 + `networking contentsOf:`. My P03: the same. `#` inside an interpolation (`"\(#line)"`) is reported (fail closed). `#if` text inside a multi-line raw string is literal text to the compiler too, and it is correctly not reported. The PR's 7 directive plants, the proof test, and the comment/raw-delimiter negative pass. Mutants m15 (reads allowed despite directives) and m20 (directive reporting off) are killed (1 and 7 issues). | **Closed** |
| F2 | Minor | `bindingScope` (`:320`), `isInScope` (`:340`); `functionBody` removed | My P01, P02, P12 and P29 are all caught now. New tries, all caught: R02 (labelled `outer: do { guard … }`, read after), R03 (read in the `catch` of the binding's `do`), R12 (`guard` inside a `switch` case, read after the `switch`), R13 (read in a closure inside the `if let` block), R14 (`guard` at type level), R17 (read in a closure inside `defer`), P28 (nested `func`). Positives still pass: P06 (multi-line), P11, P21 (a parameterless closure holding both), P26 (read in a `switch` case in scope), R08 (`else` on the next line), R16 (read inside `while` in scope). Mutants killed: m02 (scope check → `true`, 10 issues), m17 (scope-start check off, 1), m18 (control-flow-only walk off, 2), m19 (`if let` scope = the enclosing block, 2). | **Closed** |
| F3 | Minor | `shadowViolations` (`:420`) | My P07 (`typealias Data = String`) is now caught twice (typealias, and shadows `Data`). R07 (`enum L<T, Bundle: P>`, `Bundle` after `,` rather than `<`) is caught by the Bundle-use check. R06 (`` struct `Data` ``, backticked) is missed by the shadow check but caught by the `init` parameter check, and a usable `Data(contentsOf:)` shadow always needs that `init` (see N1). m16 (shadow check off) is killed (12 issues). Shadowing from another file is still a Reviewer check, as the dev-notes say. Confirmed at `32a6be8`: no TendEval file declares or extends `Bundle` or `Data`, there is no `typealias` and no `extension EvalFixturesLoader`, and the only other `Bundle` use is `Bundle.main.object(forInfoDictionaryKey:)` in `EvalRunner.swift:170`. | **Closed** |
| F4 | Minor | 4 new plants (`Q23LoaderTests.swift`) | m03, m06 and m11 are now killed (1 issue each). m09 survives. It is equivalent: `isInScope` requires `offset > scopeStart`, and `scopeStart` (the call's `)`, the `else` block's `}`, or the `if` block's `{`) is always after `nameOffset`. So `nameOffset < argument.startOffset` can never decide the result alone. Keeping it as defence in depth is fine. | **Closed** |
| F5 | Nit | `dev-notes.md` round 2 section | The note is corrected, and the "Not verified" row now records the fit check. | **Closed** |
| I1 | Info | — | Superseded by F6 below. | Replaced by F6 |

### New findings (round 2)

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F6 | Minor | `SourceScanner.swift:30` (pre-existing known limit); `FixturesLoaderRule.swift:237-246` | **Regex literals hide directives from the F1 check.** The loader text below gives **0 findings** (my R01). A bare regex `/"""/` is lexed as the start of a multi-line string, so the lexer treats everything up to the next `"""` as string text. Each of the two hidden regions holds one directive line. The binding between them stays visible to the scanner, but the compiler drops it. I built it in a Swift 6 package, using the round 1 `Other.swift` (a `static let inputsFile` in another file). With `-warnings-as-errors` it reported "Build complete", with no warning, and printed `read 13 bytes from a non-bundle path`. Correcting round 1: I1 was understated there. Round 1 plant P08 already showed that a regex literal can hide any call in the loader (and in every other scanned file), including a non-bundle read. Not Major, because it is the documented lexer limit (R-12 header note) and only deliberately evasive code triggers it. An innocent `#if` (F1's realistic case) is now caught. The brief keeps "the loader reads only bundle resources" as a Reviewer confirmation, and I confirm it for `32a6be8`: the real loader has no `/` outside comments. Loader text: `static func inputs() throws -> Data {` / `_ = /"""/` / `#if NEVER_DEFINED` / `_ = /"""/` / `guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else { throw LoaderError.missing }` / `_ = /"""/` / `#endif` / `_ = /"""/` / `return try Data(contentsOf: inputsFile)` / `}` | Ticket. Cheapest fix, stricter only: in the loader file, report any `/` left in lexed code (comments are already removed, and the loader needs no division), and allow no read when there is one. Add the R01 text and the P08 text as plants. The lexer-wide fix (lex `/…/` and `#/…/#` regex literals) would close the limit for AC-M1-23 and AC-M2-09 everywhere and belongs in its own ticket. | Open (ticket) |
| F7 | Minor | `FixturesLoaderRule.swift:290` (`bindingEnds`), `:353` | **m04 (`bindingEnds` off) now survives.** In round 1 it was killed, but the plants that killed it are now also caught by `bindingScope`. `bindingEnds` still guards a real case on its own: `let u = Bundle.main.url(forResource: "inputs") ?? fallback` (or `?? fallback` on the next line) followed by `return try Data(contentsOf: u)`. The real code reports `networking contentsOf:` for both forms. Under m04 both give **0 findings**, although `u` would then be `fallback`, a value that can come from another file. The behaviour is correct today, but no test pins it. | Add both `??` forms as condition plants (each kills m04). | Open (ticket) |
| N1 | Nit | `FixturesLoaderRule.swift:384` (`isControlFlowBlock`), `:420` | (a) Walking back from a closure's `{` does not stop at a newline, so `repeat { } while false` followed by a line holding `let g = { return try Data(contentsOf: u) }` makes the closure look like a `while` block, and the read is allowed (R05). This is harmless: `u` is still the in-scope bundle binding, captured by the closure. It is only looser than "same function body". (b) The shadow check does not see backticked names such as `` struct `Data` `` (R06). Other checks cover it today. | Optional: stop the back-walk at a newline that ends a statement, or note it in the header's known limits. Strip backticks in `shadowViolations`. | Open (optional) |

### Bypass attempts (round 2)

| Plant | Result | Expected? |
|---|---|---|
| P01, P02, P12, P29 (round 1 F2 forms); R02 labelled `do`; R03 `catch`; R12 `switch` then after; R14 type-level `guard` | caught (`networking contentsOf:`) | yes |
| P03 and the round 1 proof file (`#if` around the binding) | caught (directive ×2 + contentsOf:) | yes |
| R09 `"\(#line)"` in the loader | caught (directive) | yes (fail closed) |
| R10 a single-line raw string broken by a newline, leaving `#if X"#` in code | caught | yes (fail closed) |
| R11 `#if` text inside a multi-line raw string `#"""…"""#` | not reported | yes (it is string text to the compiler) |
| **R01 `#if` hidden by `/"""/` regex literals** | **0 findings; compiles cleanly; non-bundle read** | **no: F6** |
| P08 call hidden by a `/"/` regex literal (round 1) | 0 findings | no: F6 |
| P07 `typealias Data = String`; R07 `<T, Bundle: P>` | caught | yes |
| R06 `` struct `Data` { init(contentsOf: Int) {} } `` | caught (init parameter; not by the shadow check) | yes (N1 b) |
| R04 read in an immediately-called closure; R13 closure in an `if let`; R17 closure in `defer`; P28 nested `func` | caught (stricter than needed) | yes |
| R05 closure after `repeat {} while false` | 0 findings | harmless (N1 a) |
| `let u = Bundle.main.url(…) ?? fallback` (same line and next line) | caught by the real code; 0 findings under m04 | yes (F7: untested) |
| P05 second read; P10 code in an interpolation; P16 `Logger`; P17 `write(to:`; P13, P14, P18 shape outside the loader or module | caught | yes |
| P06 multi-line, P11, P21, P26, R08, R15, R16 (valid forms) | 0 findings | yes |
| P04 static `u` in the results writer (another file) | 0 findings | yes: a text scan of that file cannot know; the loader side is what must stop it, and it does except via F6 |

### Mutants (round 2; 20 total, each in its own scratch copy of `9126548`; full `TendSourceScan` suite)

| Killed (issues) | Survived |
|---|---|
| m01 `>= 2` occurrences (1); m02 scope → `true` (10); m03 `startsStatement` off (1); m05 follow check off (2); m06 interpolation flag off (1); m07 `://` off (2); m08 `URL` token off (4); m10 parameter checks off (10); m11 `>= 1` literal (1); m12 loose resource pattern (10); m13 lexer span count frozen (16); m14 exception in every TendEval file (6); m15 reads allowed despite directives (1); m16 shadow check off (12); m17 scope start off (1); m18 control-flow-only walk off (2); m19 `if let` scope = enclosing (2); m20 directive reporting off (7) | m04 `bindingEnds` off (F7); m09 order check off (equivalent, see F4) |

### Lexer and real loader (round 2)
- The lexer is not touched in this round. The differential re-run (base `65c06cd` lexer against the head lexer, 227
  repository files with the `32a6be8` harness, plus my edge file, 228 inputs) found **0 differences**.
- **Real loader `32a6be8`:** 0 findings at the loader path, 4 `networking contentsOf:` at any other TendEval path. It
  fits cleanly: no `#`, no `/` in code, no `typealias`, no shadowing declaration. Each read is inside the scope of its
  own `guard` (read after the `else` block's `}`, in the same function block).
- **Reviewer confirmation (brief AC-M2-09 Rule 6):** at `32a6be8` the loader reads only bundle resources named by
  literals (`inputs`, `household`, `golden`, `MANIFEST`; `json`, `sha256`). No other TendEval file shadows `Bundle` or
  `Data`, extends `EvalFixturesLoader`, or declares a global with one of the loader's bound names. Re-confirm at the
  WI-M2-M7 review.

### Runs (round 2; Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, fresh scratch copies of `9126548`)

| Package | Result |
|---|---|
| `TendSourceScan` | 84 tests in 5 suites passed, 0 warnings |
| `TendIngestion` | 581 tests in 68 suites passed, 0 warnings; AC-M2-09 scan TendIngestion 56, TendAI 15, TendEval 1, 72 files, 0 violations; AC-M2-12 72 files, 0 violations |
| `TendCore` | 141 tests in 18 suites passed, 0 warnings |
| `TendIngestion` with `Apps/TendEval` from `origin/m2/eval-harness` `32a6be8` | 581 tests in 68 suites passed, 0 warnings; AC-M2-09 scan TendIngestion 56, TendAI 15, TendEval 8, "79 files in total, 0 violations"; AC-M2-12 79 files, 0 violations |
| Proof builds (Linux Foundation, Swift 6 language mode, `-warnings-as-errors`) | Round 1 `#if` proof: now caught by the scan. F6 regex proof: build complete, no warnings, non-bundle read, 0 scan findings |

Every check here was run on Linux. I verified nothing on macOS, the Simulator or a device; nothing in this PR needs
them.

### Checklist (round 2)
- [x] Correctness vs ACs (AC-M2-09 Rule 6 Q23: positive passes, all brief plants caught, F1/F2/F3 closed)
- [x] Tests meaningful: 18 of 20 mutants killed; m09 equivalent; m04 is F7 (Minor)
- [x] Swift 6 concurrency safe (value types, no shared state)  - [x] No force unwraps / `try!` in product paths
- [x] Privacy (P-1…P-4): no open Major. F6 is a Minor gap in a pre-existing, documented lexer limit, and the Reviewer
  confirmation for the real loader is given above.
- [x] UX-2/UX-3: n.a. / pass  - [x] Accessibility: n.a.  - [x] Performance: linear passes over one file
- [x] No new dependency without ADR

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Test-only scan library. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No user copy; neutral check names; AC-M2-12 vocabulary scan green (72 and 79 files, 0 violations). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No model path touched. |
| P-2 No data leaves device (except user iCloud) | pass | No networking added; every networking pattern is still a hit in the loader file. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No cloud path touched. |
| P-4 Media not persisted without consent | pass | The F1 concern is closed: an ordinary or accidental `#if` can no longer hide the binding, and an out-of-scope or shadowed `Data`/`Bundle` is reported. Write and log APIs stay hits in the loader file. The remaining gap (F6) needs deliberately evasive regex literals, is the documented lexer limit, and is ticketed. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-28 | Developer (via Orchestrator) | Reviewer | received | PR #51 round 2, head `9126548` (round 1 review at `0a3dc32`). |
| 2026-11-28 | Reviewer | Merge Gatekeeper / Orchestrator; Developer for tickets | accepted | **APPROVE.** F1–F5 closed with evidence. New Minors F6 (regex-literal-hidden directives in the loader; a loader-local `/` ban suggested; lexer-wide fix as its own ticket) and F7 (pin `bindingEnds` with the `?? fallback` plants), and Nit N1, all to be ticketed; none blocks. Merge before WI-M2-M7 opens for review (plan). Re-confirm the loader's bundle-only reads at the WI-M2-M7 review. |
