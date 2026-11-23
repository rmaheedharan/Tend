# M2 Code Review — WI-M2-15 eval scorer, results file v1, self-test set, Tools/TendTools (PR #27, `m2/eval-scorer`, head `2af0afe`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Requirements:** FR-A1, UX-3; ○ AC-M2-14 (scorer self-tests; the freeze is WI-M2-16); AC-M2-28 (results-file
  schema, the scorer's rejection, deterministic ID generator, Linux half); the Linux scoring halves of AC-M2-11, 15,
  16, 17, 25, 26, 27 (all stay AWAITING-DEVICE); regression AC-M2-09 (Rule 1, T-26) and AC-M2-12.
- **Binding inputs checked:** `CLAUDE.md`; brief Definitions (Draft field set, Draft stream events, Name folding,
  Keywords of a text, Banned tokens), **Eval scoring rules**, Device-run rules, AC-M2-05, 09, 11, 12, 14–17, 25–28;
  plan WI-M2-15/16 rows, "Scoring tool and command", "Eval harness ID generator", R-22; dev-notes WI-M2-15; PO notes
  `po-m2-wi07.md`, `po-m2-wi08.md` (commit re-check, C4) and `po-m2-wi15.md` (2026-11-23, received mid-review: rulings
  on the developer's Q1–Q3).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed. No protected path is
  touched (`git diff --stat 3bac3ce...2af0afe`: Fixtures, Packages/TendIngestion, Tools/TendTools, dev-notes only).

## Summary
The scorer is pure and Foundation-only. It takes `Data` and returns a value (`EvalScorer.run`), and `tend-eval-score`
does all file I/O outside `TendIngestion/Sources` (AC-M2-09 Rule 1, T-26). I checked `EvalScorer.swift` against the
brief's eval scoring rules one at a time. All of them are implemented as written:

| Brief rule | Code | Verified |
|---|---|---|
| Household state: fresh copy per input | `scoreInput` uses only the input's golden items and the seeded tasks (`EvalScorer.swift:203`) | yes |
| Draft text = keywords(title) joined with keywords(sourcePhrase); S1 distinct union (PO `po-m2-wi15.md` R3) | `draftText(of:)` `:284-288` | yes, S1 exactly |
| Satisfies: ≥ 1 token from **each** group; Overlap: draft-text tokens in any group | `:292-299` | yes |
| Primary = not `ofDraft` | `:302-305` | yes |
| Segmentation: pairs sorted overlap ↓, golden order ↑, draftID ↑, greedy | `:310-336` | yes |
| Not found / extra (primary drafts only) | `:211-212`, `:273` | yes |
| Denominators: only found items score; ⌈p × N⌉ | `EvalMetric.requiredCount` `:124-126` (`(p·N+99)/100`) | yes (48/45/43 at N = 50) |
| Room scoring: existing / new(name, alternates) after name folding / none; linking a `new` item to an existing room is wrong | `roomIsCorrect` `:341-350` | yes |
| Validity counts all emitted drafts | `:250-251` (M1 initialiser) | yes |
| Calm words: titles + proposed room names; tokens the user said are kept; S4 per occurrence | `:255-268` | yes, S4 exactly as PO ruling 3 (probe below), but see F2/F3 for tests |
| Best target: create items + non-completed seeded tasks; highest overlap; ties golden before seeded, then lower key (UTF-8) | `:353-385` | yes |
| Duplicates created: Σ max(0, c(g) − 1) + Σ c(t), c over committed drafts | `:234-241` | yes |
| False merge: marked draft with best target g and c(g) = 0, each g once | `:244-247` | yes |
| Last attempt scored (device-run rules) | `score` `:173` | yes |
| Output: per-input and total counts, each pairing, each best target | `EvalScoreLog.render` | yes |

**Independent re-score.** I wrote my own re-scorer in Python from the brief text only (keywords, stop words, name
folding, the rules above; no Swift helper consulted) and ran it over `Fixtures/M2/eval-selftest/results-selftest-1.json`.
It agrees with the committed `results-selftest-1.score.log` on every draft text, pairing, extra, best target, c(x),
duplicate count (6), false merge (1: `g02-oven`), introduced token (2) and total (N 16; segmentation 14, kind 13, room
11, effort 13, each flag 13). The test expectations in `EvalScorerSelfTests.swift` are literals with a written
derivation, and none is computed by calling production code. The log is pinned byte for byte (`:319`). The hand
derivation holds up against an independent oracle, so the self-test set counts as hand-derived evidence (AC-M2-14).
This does not replace the Tester's own re-score in WI-M2-16.

**Profiles** (`EvalProfile.swift`) match the plan: ds1-gated = Q3 thresholds + 0 duplicates + ≤ 1 false merge +
on-device route + TTFI < 1500 ms / total ≤ 5000 ms (AC-M2-15/16/17); ds1-offline = 3 inputs, 2 voice, per-input clean
parse including calm words (AC-M2-11); ds2-offline/online (AC-M2-25, online without calm words, as the AC says);
ds2-gated adds the key-path subset check (AC-M2-26) and cloud timing (AC-M2-27). A missing TTFI fails timing.

**Schema completeness.** `results-v1.schema.json` has every AC-M2-28 member (`run` 13 members + `network` 4,
`coldStart`, per-attempt 14 members, `events[]`, `cloudRequests[]`) and the full brief draft field set (15 members).
I walked the schema: all 14 object nodes are `additionalProperties: false` and list every property as required. So
there is no place for audio, a body, a header value or a key (P-3, P-4). `EvalSchemaCheck` interprets the committed
schema and fails closed on unknown keywords. That design does stop drift (R-22), except for the regex semantics in F1.

**Canonical-JSON strictness (focus question).** The check is not stricter than device runs need. `EvalJSONReader` is
the exact inverse of `CanonicalJSONWriter`: the writer writes raw UTF-8 apart from `"`, `\` and C0 controls, and does
no normalisation; the reader keeps scalars as they are and refuses duplicate keys by UTF-8 bytes. So any file the
harness writes with `canonicalJSON` reads back byte-identical. Only a hand-edited or re-saved file is refused, and that
is what we want for evidence whose SHA-256 goes in the run record. There is no `.gitattributes` or `.editorconfig`
that could rewrite bytes on commit. Note for the Tester (N3 below): the E4 Python one-liner produces different bytes,
so it must never be used on a device file.

**Cross-field rules (focus question).** None is stricter than the brief needs: `finished` exactly once and last for
every outcome, including `cancelled` (Definitions, AC-M2-05); `committed` = the unmarked drafts (AC-M2-17; consistent
with `po-m2-wi08.md` ruling 2, `none` drafts are not re-checked, and the harness commits immediately into a fresh
household); text inputs get 1 attempt and voice inputs ≤ 2 (device-run rules); `ttfiMs`/`totalMs` equal the first
`emitted`/`finished` times (Definitions, TTFI and Total time).

**Developer's open questions.** All three are answered by the PO in `po-m2-wi15.md`: Q1, keep many-to-one best target,
in04 is correct, and the eval fixtures get a checked `referencePhrase` in WI-M2-16 (the brief amendment is not yet in,
and per the PO's ruling I do not count it as missing in this PR); Q2, E3 key-path form confirmed; Q3, S1 and S4
accepted. The code matches S1 and S4 exactly. Two parts of the calm-words rule are not pinned by any test (F2, F3).

**`@unchecked Sendable` in `TendToolsTests.Captured` (`TendToolsTests.swift:8`): signed off.** `ToolIO` must be
`Sendable` (`ToolIO.live` is a `static let` under Swift 6), so its closures are `@Sendable` and a capture box must be
`Sendable`. `EvalScoreCommand.run` is synchronous and has no `Task` or queue, and each test owns its own box, so
nothing races. It is test-only and documented. The checked alternative is optional (N1). There is no other
`@unchecked`, `nonisolated(unsafe)`, `Task {}` or queue in the new sources or tests.

**AC-M2-09 / AC-M2-12 / dependencies.** Eval/ contains no `contentsOf:` read (only `append(contentsOf:)`), no
FileManager, print, clock, calendar, locale or formatter; the source scan logs `TendIngestion ... 33 files scanned`,
`0 violations`. No banned token occurs in the new Sources or in the tool's output strings. The banned words in
`Fixtures/M2/eval-selftest/` ("late", "overdue", "missed") are deliberate calm-words test data and are not UI copy.
`Tools/TendTools` depends only on `../../Packages/TendIngestion` (named in the plan and ADR-0006), so no new
dependency is added.

## Test runs (this review, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, worktree at `2af0afe`)
| Package | Result |
|---|---|
| Packages/TendIngestion | `✔ Test run with 297 tests in 37 suites passed after 63.488 seconds.` 0 warnings, 0 skipped. AC-M2-09 `33 files in total, 0 violations` |
| Packages/TendCore | `✔ Test run with 141 tests in 18 suites passed after 117.194 seconds.` |
| Packages/TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 1.766 seconds.` |
| Tools/TendTools | `✔ Test run with 7 tests in 1 suite passed after 0.075 seconds.` |
| `tend-eval-score` release build, end to end | info over the canonical self-test file: exit 0 and stdout byte-identical to `results-selftest-1.score.log`; ds1-gated: exit 1; the readable (non-canonical) copy: exit 2; ds2-gated without `--allowed-key-paths`: exit 64 |

## Probes and mutants (scratch copy only; the worktree was never edited; the copy's `Packages/` was diffed equal afterwards)
| # | Probe / mutant | Result |
|---|---|---|
| P1 | `EvalSchemaCheck` with `pattern: "^[0-9a-f]{40}$"` on 40 hex + `"\n"`; key-path pattern on `"$.messages[].content\n"` | **0 issues: accepted** (F1) |
| P2 | Whole self-test file with `run.appCommitSHA` = valid SHA + `"\n"` through `EvalResultsFileV1.read` | **ACCEPTED** (F1) |
| P3 | in06: title "Clean the overdue overdue oven" and "Pay the late late gas bill" | introduced = [overdue, overdue, missed] = 3: S4 as ruled |
| M-R1 | Calm words counted once per distinct token per title (breaks S4 "two in one title = 2") | **survived**: 62/62 Eval tests pass (F3) |
| M-R2 | Voice inputs checked against the fixture text instead of the attempt's transcript (`EvalScorer.swift:255`) | **survived**: 62/62 Eval tests pass (F2) |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R27-F1 | **Major** | `Packages/TendIngestion/Sources/TendIngestion/Eval/EvalSchemaCheck.swift:208-213`, `:229-232` | The `pattern` check uses ICU (`NSRegularExpression`) `$`, which also matches before a final line terminator. JSON Schema patterns are ECMA-262, where `$` without `m` matches only at the end of input. So the scorer accepts files that do **not** conform to the committed schema: P1/P2 show `appCommitSHA`, `fixturesSHA256`, `startedAtUTC`-shaped strings and key paths with a trailing `"\n"` all pass. This breaks AC-M2-28 "The scorer rejects a file that does not conform" and the R-22 promise that the check "cannot drift from the file". The Tester's independent validator (AC-M2-14 re-score) would refuse a file the scorer scores. The comment at `:229` ("the part ICU and ECMA-262 read the same way") is wrong for `$`. The R-22 walk did not catch it because its mutations come from the schema and never add a line terminator. | Make `pattern` match with ECMA-262 end-of-input semantics. For example, for a pattern that ends in an unescaped `$`, require the match to end at the end of the string (or refuse any string holding `\n`, `\r`, U+0085, U+2028 or U+2029). Fix the comment. Add tests: for each of the 6 schema patterns, a value with a trailing `"\n"`, `"\r\n"` and `"\u{2028}"` is rejected at its path, and the valid value is still accepted. Linux evidence is enough; note the Darwin ICU behaviour is the same. | Open |
| R27-F2 | **Major** | `EvalScorer.swift:255-256`; `Fixtures/M2/eval-selftest/results-selftest-1.json` (in02, in06) | AC-M2-14 says the self-tests "cover every rule". The calm-words rule says "introduced" is judged against the typed text or the **final transcript** (AC-M2-12; PO `po-m2-wi15.md` R3: "the scored attempt's transcript for voice inputs"). No test separates the two: in06's transcript repeats its fixture text, and mutant M-R2 (always use the fixture text) passes all 62 Eval tests. The gate has ≥ 8 voice inputs that are spoken live (AC-M2-15, 26), so the transcript will differ from the script. A wrong branch here can flip the "0 introduced banned tokens" gate either way. | Add a hand-built case to the self-test file, with its hand derivation and the pinned log updated. Use a voice attempt whose transcript and fixture text differ in a banned token, both ways: a token only in the transcript is kept (0), and a token only in the script is introduced (counted). M-R2 must then fail. Keep the case in the file the Tester re-scores. | Open |
| R27-F3 | Minor | `EvalScorer.swift:259-266`; `EvalScorerSelfTests.swift` (in06) | S4 is now a PO ruling ("two in one title = 2"; a token the user said counts 0 however often it appears). The code does exactly that (P3), but no test pins it: mutant M-R1 survives. It changes only the reported number, never pass/fail (PO R3). | Add a case where an introduced token appears twice in one title (expect 2) and a said token appears twice (expect 0). | Open (ticket) |
| R27-F4 | Minor | `Fixtures/M2/eval-selftest/results-selftest-1.json`; dev-notes mutant M15 | "Satisfies needs a token from **each** group" is guarded only by a unit test. No draft in the hand-built file satisfies some but not all of an item's groups, so the Tester's re-score of the file does not exercise the rule (AC-M2-14 "self-tests against hand-built results files … cover every rule"). The unit test is real, which is why this is Minor. | Add one draft that holds tokens from one group only of a multi-group item (for example "Sort the shelves" against `g05-garage`), so it is extra or not paired in the file, and update the derivation and log. | Open (ticket) |
| R27-F5 | Minor | `.github/workflows/ci.yml` (protected; not in this PR) | CI only builds `Tools/TendTools`; its 7 tests (exit-code contract 0/1/2/64) run nowhere in CI. The scorer logic itself is all in TendIngestion and is run in CI. | Ticket for the owner's HM-1b: add `swift test --package-path Tools/TendTools -Xswiftc -warnings-as-errors`. No change in this PR. | Open (ticket, owner) |
| R27-N1 | Nit | `Tools/TendTools/Tests/TendToolsTests/TendToolsTests.swift:8` | `@unchecked Sendable` is signed off (see Summary). | Optional: make `Captured` hold a `Mutex` from `Synchronization` (available on Linux and macOS 26), so the compiler checks it and the `@unchecked` goes. | — |
| R27-N2 | Nit | `EvalSchemaCheck.swift:211`, `:230` | `compile(pattern)` builds an `NSRegularExpression` for every string it checks. The cost is trivial at this file size. | Optional: cache the compiled patterns at `init` (they are already compiled there once to fail closed). | — |
| R27-N3 | Nit | dev-notes WI-M2-15 E4; `results-v1.schema.json` `network` | (a) The E4 Python one-liner changes the bytes (and the SHA-256) of any file with non-ASCII text. (b) `downMbps`/`upMbps` are whole Mbit/s, so a 0.6 Mbit/s upload reads 0. The run record keeps the speed test anyway. | (a) Tester: DS-1/DS-2 should say the exported file is committed byte for byte and never re-saved or re-formatted. (b) None needed unless the PO wants decimals; if so, use a unit such as kbit/s, which stays an integer. | — |

## Checklist
- [x] Correctness vs ACs: the rules match the brief exactly (table above), and an independent re-score agrees. F1
  (AC-M2-28 rejection) is open.
- [ ] Tests meaningful (would fail if code broke): mostly yes (27 developer mutants killed; R-22 walk 214/214), but
  M-R1 and M-R2 survive (F2, F3) and the R-22 walk misses line terminators (F1).
- [x] Swift 6 concurrency safe: strict mode, 0 warnings; the one test-only `@unchecked Sendable` is signed off.
- [x] No force unwraps / `try!` in product code paths: typed throws throughout, and `ValueReader` gives a typed
  rejection, never a crash.
- [x] Privacy (P-1…P-4): no I/O, network or logging in TendIngestion; the schema is closed and has no field for audio,
  body, header or key.
- [x] UX-2/UX-3 enforced in engine: n.a. / the calm-words count is implemented; no banned token in Sources.
- [x] Accessibility (UI): n.a. (no UI).
- [x] Performance: fine at eval size (N2).
- [x] No new dependency without ADR: only the local TendIngestion package (plan, ADR-0006).

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Eval tooling only; no entry surface. |
| UX-2 Rule of Three | n.a. | Nothing selects "what to do now" items. |
| UX-3 Zero-Guilt | pass | The scorer counts introduced banned tokens (Q3 calm words; AC-M2-12 user's-words exception). No banned token in new Sources identifiers, literals or tool output. Banned words appear only as deliberate self-test data. F2 is a test gap in this rule's scorer, not a copy violation. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference. |
| P-2 No data leaves device (except user iCloud) | pass | No networking in `Eval/` (AC-M2-09 Rule 1, 0 violations) or in TendTools; local files only. No dependency added. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The file records only request byte counts and key paths. Every schema object is closed, so a body, header or key member is refused (tested). ds2-gated checks the sent key paths against the allowed list (AC-M2-26). The F1 regex gap lets a key path carry a trailing newline, but no value. |
| P-4 Media not persisted without consent | pass | v1 has no field for audio, bodies, header values or keys. The shipped modules gain no write or log API. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Reviewer | accepted | PR #27, `m2/eval-scorer` at `2af0afe` (base `3bac3ce`), fresh context. |
| 2026-11-23 | Orchestrator | Reviewer | accepted | Mid-review: PO rulings `po-m2-wi15.md` on Q1–Q3. The code was checked against S1/S4; the `referencePhrase` amendment is not counted as missing. |
| 2026-11-23 | Reviewer | Developer (via Orchestrator) | returned | CHANGES REQUIRED: R27-F1 (Major, ICU `$` accepts trailing line terminators, so AC-M2-28 rejection and R-22 fail) and R27-F2 (Major, the transcript-vs-text calm-words branch is untested, mutant survives). F3–F5 Minor (ticket), N1–N3 optional. `@unchecked Sendable` in TendToolsTests is signed off. Re-review: round 2 in this file. |
