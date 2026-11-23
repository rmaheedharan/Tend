# M2 Code Review — WI-M2-12 cloud stream framing and partial structured-output reader (PR #26, `m2/stream-json-snapshots`, head `b92a92e`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2 (round 1 APPROVE at `b92a92e`; round 2 APPROVE at `e3932db`)
- **Requirements:** FR-A1, P-3; ○ AC-M2-24 (Linux part: SSE framing, incremental JSON, mapping to neutral snapshots,
  truncation and invalid JSON, unknown enum values, non-integer numbers to nil); through the same draft stream,
  AC-M2-05; regression AC-M2-09 (scan) and AC-M2-12 (vocabulary).
- **Binding inputs checked:** brief Definitions (Item completion (T-03), Draft stream events), AC-M2-05, AC-M2-09,
  AC-M2-12, AC-M2-24, T-19, T-25; plan WI-M2-12 row; dev-notes WI-M2-12 (J1–J9); PO notes `po-q21-q22.md` ("From
  PR #22" ticket: test a title that arrives last), `po-m2-wi06.md` (ruling 2: rule (a) field set, time counts once
  `anchor` is set; D8), and `po-m2-wi12.md` (2026-11-23, received mid-review: J2 and J6 ACCEPTED as built; the
  cloud latency gate is AC-M2-27, not AC-M2-16; brief amendment to be applied by the Developer after this review, so
  its absence is not a finding).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed.
- **Scope of the diff:** three new source files under `Packages/TendIngestion/Sources/TendIngestion/CloudOutput/`, three
  new test files, the dev-notes section. No existing source or test file is changed.

## Summary
The work item does what the plan row asks, and the tests would fail if the code were wrong. I checked each focus point
against the code and with my own mutants on a scratch copy.

- **Arbitrary cuts (AC-M2-24 split chunks).** `PartialJSONParser` reads one byte at a time and keeps all state between
  calls (open containers, `Scalar` in progress, `StringScanner` escape and UTF-8 state). So where a chunk is cut cannot
  change the result:
  - A UTF-8 sequence is staged in `sequence` and committed only when it is whole. Lead-byte ranges follow RFC 3629:
    `E0`≥`A0`, `ED`≤`9F`, `F0`≥`90`, `F4`≤`8F`, `C0`/`C1`/`F5+` rejected (`PartialJSONParser.swift:350-447`).
  - Escapes and surrogate pairs are staged in `Escape`. A pair is appended only once the low half is valid
    (`:409-419`).
  - Numbers are held as bytes and checked against the grammar only at their delimiter (`:201-209`, `:307-310`).
  - Tests: `everyCut` (every 1-cut, and every 2-cut with the first cut on every third byte), `partialStringsAreWhole`
    (byte by byte through `é`, an emoji, `\n`, `é` and a surrogate pair), the invalid tables checked at every cut
    point, and the property (3 × 500 outputs, 3 random cut sets each, plus byte by byte on every 25th).
- **Strictness vs RFC 8259.** I traced the grammar:
  - leading zeros, a bare `-`, `1.`, `1e`, `+1` and `.5` are rejected;
  - trailing commas in arrays and objects, missing colons and unquoted keys are rejected;
  - raw control characters (< U+0020) are rejected, and U+007F is accepted, which is correct;
  - lone and mismatched surrogate escapes are rejected;
  - data after the root value is rejected;
  - nesting is capped at 64 levels and the parser never recurses.
  The two strict choices (duplicate keys, a leading BOM) are allowed by RFC 8259, recorded in J4, and pinned by tests.
  The oracle's known leniencies (trailing comma, numbers beyond `Double`) are each checked and counted, not waived.
- **Monotonicity.**
  - Scalars appear only when finished. A member appears only in the `inValue` state. An array element in progress
    appears only when it is a string or a container (`value`, `:127-150`).
  - Once a field is in a snapshot it never changes. The `time` hint is the exception: its sub-fields arrive one by
    one, as PO WI-M2-06 ruling 2 allows.
  - The property checks this at every step (`isEarlierState`, field by field inside `time`; the item count never
    drops), and checks that the incremental and one-shot draft streams end with the same drafts.
- **Mapping to `IngestionSnapshot`.**
  - `room` maps to `roomName`. A Mirror test ties the key lists to the snapshot fields.
  - Enum fields go through `ModelChoice(raw:)`, so an unknown value is `.unrecognized` with an exact match.
  - Numbers are read exactly by `JSONNumberText.wholeNumber` (no floating point). The exponent cap prevents overflow.
    `Int.min`, `Int.max`, `9007199254740993` and `1.00000000000000001` are all handled.
  - `sameAsExisting` maps to `.shortlistIndex(n)` and is left for the WI-M2-07 local re-check to validate.
    `lookupQueries` is always empty (no `Tool` for the cloud, AC-M2-24).
  - `null`, wrong types and missing keys all read as nil. A non-object item becomes an empty item, so positions are
    kept. A wrong root gives no items.
- **Errors end only as `unreadableOutput` / `outputCutShort`.** `PartialJSONError` has exactly two cases. `stopReason`
  is tested over every `JSONSyntaxIssue`. The parser and the reader throw only the typed `PartialJSONError`. They do
  not trap on any input: the fuzz suite covers 3 × 400 mutants, and the 100,000 `[` depth test has no recursion. End to
  end, the error becomes `interrupted` after a draft and `noModel` before one, through `DraftPipeline` with cloud routes
  (T-25).
- **J2 and J6 (PO accepted, `po-m2-wi12.md`).**
  - `StructuredOutputReader.text` accepts only `isComplete: true` strings. The other value kinds are scalars that the
    parser never shows unfinished, so no field can hold a prefix. `titleArrivesLast` proves the PO ticket's case:
    exactly one `emitted` with the whole title and no `updated`. The developer's M18 mutant kills it.
  - `null` is nil, so it counts as missing for rule (a) (`claims`, `wrongTypes`).
  - The AC-M2-27 TTFI watch and the schema shape are handed on to WI-M2-10 by the PO. They are not part of this PR.
- **Test oracles are independent.** The oracle is Foundation's `JSONDecoder` into `OracleJSON`, with numbers read
  through `Decimal`, which is a different number path. `ReaderOracle` re-implements the schema mapping. The corpus
  writer builds the text by hand, with escapes, upper- and lower-case `\u`, surrogate pairs and raw Unicode, and never
  calls the code under test.
- **SSE framing.** I checked the framer against the WHATWG rules:
  - line ends, including a CRLF split across chunks;
  - comments, the one-space strip after the colon, and a line with no colon;
  - the `id` NUL rule and `id` persistence across events;
  - clearing the event type when a blank line dispatches with an empty data buffer;
  - dropping a BOM at the stream start only;
  - decoding invalid UTF-8 to U+FFFD.
  Lines are split on bytes and each field is decoded whole. CR, LF and `:` are ASCII, so this gives the same text as
  decoding the whole stream first.
- **Swift 6 and AC-M2-09.** All types are `Sendable` value types, with no `@unchecked`, `nonisolated(unsafe)`, globals
  or tasks. The files import only `Foundation` and `TendCore`. They do no I/O, use no network and do no logging. The
  only `contentsOf:` uses are `append(contentsOf:)`. The AC-M2-09 scan reports 26 files scanned and 0 violations. The
  AC-M2-12 vocabulary scan is clean. No new name contains a banned token (`cutShort`, `dataAfterValue`, `unexpectedByte`
  and the rest).

The findings below are all Minor or Nit. None blocks the merge.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R26-F1 | Minor | `Tests/TendIngestionTests/StructuredOutputReaderTests.swift:207-232` | The PO ruling (`po-m2-wi12.md` ruling 1, AC-M2-05 amendment 3) names a second case: a title whose prefix is a banned token the user did not say (`"Late"` of `"Later: call the plumber"`). It must give exactly one `emitted` with the whole title, and nothing may be skipped for it, "for every cloud provider parser". `titleArrivesLast` proves the mechanism (no prefix can reach a draft), and mutant M18 kills it. No Linux test uses the guard case itself, so the amended AC bullet has no direct cloud-side evidence. | Add one test, ideally next to `titleArrivesLast`. Feed a title `"Later: call the plumber"` in small chunks (for example 1–3 bytes, title last) with an input that contains "later", through `DraftPipeline` on a cloud route. Expect exactly one `emitted` with the whole guarded title, no `itemSkipped` and `completed`. Cite AC-M2-05 / AC-M2-24 and `po-m2-wi12.md`. The cleanest moment is when the brief amendment lands, so the test cites the new bullet. WI-M2-13 is the latest point. | Open (non-blocking) |
| R26-F2 | Minor | `Sources/TendIngestion/CloudOutput/ServerSentEventFramer.swift:178-204`, `PartialJSONParser.swift:341-361` | Nothing bounds memory. A stream that never sends a line end grows `line` without limit, and the same holds for `dataBuffer` and the scanner's `bytes`. The 10.0 s deadline (WI-M2-14) limits time, not bytes. One capture is a few KB, but a misbehaving endpoint could push megabytes inside the deadline. This is a hardening gap, not an AC failure in this item. | Give a response-size cap to WI-M2-13 or WI-M2-14 (for example, end with `unreadableOutput` once the body passes a fixed byte limit), with a test. Record the ticket in the dev-notes follow-up table. No change is needed in this PR. | Open (ticket) |
| R26-N1 | Nit | `Sources/TendIngestion/CloudOutput/PartialJSONParser.swift:11`, `:80` | The header and the `byteOffset` doc say the offset points at "the first byte that cannot be read". For a malformed number, the parser reports the delimiter after the number instead (`[01]` → 3, `[1-2]` → 4, a root `01` → the text length). The behaviour is deterministic and pinned by the table. Only the wording is wrong. | Reword it, for example: "…the first byte that cannot be read; for a malformed number, the byte that ends it". | Open |
| R26-N2 | Nit | `Sources/TendIngestion/CloudOutput/PartialJSONParser.swift:126`; `StructuredOutputReader.swift:19`; dev-notes J2 | Two comments are slightly off. (a) The `value` doc says it is nil "while a root scalar is open", but an open root **string** is returned as `.string(_, isComplete: false)` (`:130-131`). (b) "A field never changes once it is in a snapshot" does not hold for `time`, whose sub-fields arrive after `anchor` (allowed by PO WI-M2-06 ruling 2; the property checks sub-fields separately). | Say "a root number or literal" in (a). Add "(the time hint gains sub-fields)" in (b). | Open |
| R26-N3 | Nit | `Tests/TendIngestionTests/StructuredOutputReaderTests.swift:509-556` | The parser's full value is compared with the oracle only for fixed texts (`everyCut`, `completeValues`). In the random property, values under unknown keys (`extra`, `note`) are checked only for acceptance, not for value equality. The reader ignores those keys, so no AC is affected. | Optional: add a parser-level property that maps `PartialJSONValue` to `OracleJSON` (keys sorted) and compares whole values over the same corpus. | Open (optional) |

There are no Blocker or Major findings.

## Tests run (reviewer, independent)
All runs used the worktree at `b92a92e`, in `swift:6.2-noble` with `-Xswiftc -warnings-as-errors`.

| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev26-TendIngestion --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 283 tests in 35 suites passed after 69.146 seconds.` AC-M2-09 scan: TendIngestion 26 files scanned. |
| `swift test --scratch-path /tmp/rev26-TendCore --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 95.043 seconds.` |
| `swift test --scratch-path /tmp/rev26-TendSourceScan --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 3.340 seconds.` |

The counts match the dev-notes (283 / 141 / 63) and there are 0 warnings.

**Reviewer mutants.** I ran these on a scratch copy made with `git archive` (never in the worktree), one at a time, with
the filter `ServerSentEvent|PartialJSON|StructuredOutput`. None of them repeats the developer's 25.

| # | Mutant | Result |
|---|---|---|
| V | SSE `finish()` ignores a leftover event type | killed |
| Z | Control-character bound in strings `< 0x20` → `< 0x1F` (raw U+001F accepted) | killed |
| H | SSE resets `lastEventID` at every dispatch | killed |
| B | SSE keeps the event type after a blank line with an empty data buffer | killed |
| A | Upper-case hex digits `A`–`F` not accepted in `\u` escapes | killed |
| Q | SSE strips every leading space, not one | killed |
| W | SSE drops a BOM at the start of every line, not only the stream start | killed |

7 of 7 were killed.

## Checklist
- [x] Correctness vs ACs: the AC-M2-24 Linux part of WI-M2-12 (split chunks, truncation, invalid JSON, unknown enums,
  non-integer numbers to nil, field order) has a test for every clause. AC-M2-05 holds through `DraftPipeline`.
- [x] Tests meaningful: the oracle is independent, the properties are seeded with coverage floors, and 25 developer
  mutants plus 7 reviewer mutants were killed. No test is skipped or weakened.
- [x] Swift 6 concurrency safe: pure `Sendable` value types, no unchecked escapes.
- [x] No force unwraps / `try!` in product code paths.
- [x] Privacy (P-1…P-4): no I/O, network or logging (AC-M2-09 green).
- [x] UX-2/UX-3 enforced in engine: n.a. for UX-2. For UX-3, no prefix can be cut down by the calm-words guard (J2),
  and every new name passes the vocabulary scan.
- [x] Accessibility (UI): n.a., no UI.
- [x] Performance: each byte is read once. Building a snapshot after each chunk is linear in the output so far (J9),
  which is fine for KB-sized captures. Bounding memory is R26-F2.
- [x] No new dependency without ADR: Foundation and TendCore only.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The code parses model output only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Only finished strings reach the guard, so a prefix such as `"Late"` can never be cut and the item lost (J2, PO-accepted). The new names contain no banned token (AC-M2-12 scan green). R26-F1 asks for the direct guard-case test. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | Nothing here chooses a model or route. |
| P-2 No data leaves device (except user iCloud) | pass | Pure parsing over in-memory bytes. No network, file or log API (AC-M2-09 Rule 1: 0 violations). No dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The code reads the response only. `lookupQueries` is always empty (no `Tool` for the cloud model). A cloud duplicate claim stays a shortlist index for the local re-check. |
| P-4 Media not persisted without consent | n.a. | Text only, held in memory, nothing persisted. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Reviewer | accepted | PR #26 at `b92a92e` (base `3bac3ce`), fresh context. |
| 2026-11-23 | Orchestrator | Reviewer | accepted (mid-review) | `po-m2-wi12.md`: J2 and J6 ACCEPTED. The latency AC is AC-M2-27. The brief amendment follows after the review and is not a finding. Checked the note on the mount. |
| 2026-11-23 | Reviewer | Orchestrator → Merge Gatekeeper; Developer | sent | **APPROVE.** No Blocker or Major. R26-F1 (Minor, guard-case test, by WI-M2-13 at the latest), R26-F2 (Minor, response-size cap ticket for WI-M2-13/14), R26-N1…N3 (Nits). Tests re-run: 283 / 141 / 63 green, 0 warnings. 7 of 7 reviewer mutants killed. |

## Round 2 — head `e3932db` (merge `8867259` of `main` `aa38472`, then fix commit `e3932db`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2
- **Requirements:** AC-M2-05 (new PO bullet), AC-M2-24 (Linux part), FR-A1; PO `po-m2-wi12.md` rulings 1 and 2.
- **Milestone lock:** `STATUS.md` still shows M1 `ACCEPTED`, M2 `IN-BUILD`. Allowed.

### Summary
This was a short check of the round 1 findings, the merge and the PO brief amendments.

- **Merge `8867259`:** it adds nothing of its own to the code. `git diff aa38472 8867259 -- Packages` is
  byte-identical to the round 1 diff `git diff 3bac3ce b92a92e -- Packages`. The only changes against `main` are the
  WI-M2-12 files, `brief.md`, `dev-notes.md` and this review file.
- **Fix commit `e3932db`:**
  - adds one test (`bannedTokenPrefixTitleArrivesLast`);
  - changes doc comments in `PartialJSONParser.swift` and `StructuredOutputReader.swift`;
  - edits `brief.md` and `dev-notes.md`.
  No product logic changed.
- **Brief amendments:** I compared all three with `/mnt/project-files/notes/po-m2-wi12.md` and they match word for
  word. Amendment 2 is joined onto the existing line rather than wrapped at the file's width; the text is the same.
  - Amendment 1: Item completion (a).
  - Amendment 2: the end of the `updated(draft)` bullet.
  - Amendment 3: the new AC-M2-05 bullet after the `updated` bullet. The note's `\"Late\"` escaping is correctly
    written as plain quotes.

### Findings (round 1 → round 2)
| # | Severity | Round 2 evidence | Status |
|---|---|---|---|
| R26-F1 | Minor | **Fixed.** `StructuredOutputReaderTests.swift` `bannedTokenPrefixTitleArrivesLast` runs 9 cases (`CloudProvider.allCases` × chunks of 1, 2 and 3 bytes). The input says "later" and the title `"Later: call the plumber"` arrives last. It checks that no step shows a part title, and that through `DraftPipeline` there is exactly one `emitted` with the whole title, no `itemSkipped`, no `updated`, and `completed`. A control assertion shows the case is real: the same item with the title `"Late"` gives `itemSkipped`, because the guard empties it and the fixture `sourcePhrase` is not in the input. **My M18 mutant** (the reader's `text()` accepts open strings, on a scratch copy made with `git archive`) is **killed** by this test alone: `--filter bannedTokenPrefixTitleArrivesLast`, 1 test failed with 33 issues. | Closed |
| R26-F2 | Minor (ticket) | **Recorded.** It is in the dev-notes "Known limitations / follow-ups" table, for WI-M2-13 or WI-M2-14: end with `unreadableOutput` once the body passes a fixed byte limit, with a test. There is no code change, as round 1 asked. | Closed (ticket open in WI-M2-13/14) |
| R26-N1 | Nit | **Fixed.** The parser header and the `byteOffset` doc now say "for a malformed number, the byte that ends it" (and "the text length for a root number at `finish()`"). | Closed |
| R26-N2 | Nit | **Fixed.** (a) The `value` doc now says "a root number or literal" and notes that an open root string is shown. (b) The reader header and dev-notes J2 note that the time hint gains sub-fields (PO WI-M2-06 ruling 2). | Closed |
| R26-N3 | Nit (optional) | Not taken. The developer's reason holds: the reader ignores unknown keys, so no AC depends on it. | Closed (won't fix, accepted) |

There are no open Blocker, Major or Minor findings in this PR. The R26-F2 ticket now lives with WI-M2-13/14.

### Tests run (reviewer, round 2)
I ran this on the worktree at `e3932db`, in `swift:6.2-noble` with `-warnings-as-errors`.

| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev26-TendIngestion --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 333 tests in 42 suites passed after 100.600 seconds.` 0 warnings. The new test passed 9 of 9 cases. AC-M2-09 scan: TendIngestion 30 files scanned, 0 violations. AC-M2-12 vocabulary scan: 30 files. |

The count matches the dev-notes (333 = 284 on `main` at `aa38472` + 48 from round 1 + 1 new parameterised test).
TendCore and TendSourceScan are unchanged by this round (the Packages diff against `main` touches only TendIngestion),
so I did not re-run them. In round 1 they passed with 141 and 63 tests.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | The new test proves that a banned-token prefix the user did not say can never cut down a title and lose the item (AC-M2-05 amendment, AC-M2-12 intent). The vocabulary scan is clean. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No routing change. |
| P-2 No data leaves device (except user iCloud) | pass | No I/O, network or logging (AC-M2-09 green, 30 files). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Response reading only; no `Tool` for the cloud; claims stay shortlist indices for the local re-check. |
| P-4 Media not persisted without consent | n.a. | Text in memory only. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Reviewer | accepted | Round 2 at `e3932db` (merge `8867259` of `main` `aa38472`). |
| 2026-11-23 | Reviewer | Orchestrator → Merge Gatekeeper | sent | **APPROVE.** R26-F1, N1 and N2 closed with evidence. R26-F2 recorded as a WI-M2-13/14 ticket. N3 accepted as not taken. The brief amendments match `po-m2-wi12.md` word for word. TendIngestion 333 green, 0 warnings. My M18 mutant is killed by the new test (33 issues). |
