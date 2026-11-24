# M2 Code Review — WI-M2-13 provider stream dialects: OpenAI, Anthropic, Gemini (PR #29, `m2/provider-dialects`, head `ed4b1ad`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 3 (round 1 APPROVE at `ed4b1ad`; round 2 CHANGES REQUIRED at `ac991d1`; round 3 APPROVE at `f876e97`, see "Round 3")
- **Requirements:** FR-A1, P-3; ○ AC-M2-24 (Linux part: the three provider stream parsers and the synthetic fixtures);
  the AC-M2-05 bullet "This holds … for every cloud provider parser"; regression AC-M2-09 (scan) and AC-M2-12
  (vocabulary); review ticket R26-F2 (response size cap).
- **Binding inputs checked:**
  - brief Definitions: Item completion (a)–(c) with PO amendment 1; Draft stream events; `completed`, `interrupted`,
    `noModel`;
  - AC-M2-05, AC-M2-09, AC-M2-12, AC-M2-23, AC-M2-24; T-19, T-25;
  - plan WI-M2-13 row and R-23;
  - dev-notes WI-M2-12 (J2, J5, J7, J8) and WI-M2-13 (K1–K9);
  - PO notes: `po-m2-wi12.md` (rulings 1 and 2 and the WI-M2-13 tickets), `po-q21-q22.md` (PR #22, #26 and #28 tickets
    for WI-M2-13), `po-m2-wi10.md` (ruling 3: a cap stop is truncated; ruling 7: the final models `gpt-6-luna`,
    `claude-haiku-4-5-20251001`, `gemini-3.5-flash-lite` and the fixture ticket), `l1-model-check-2026-11-23.md`;
  - `po-m2-wi13.md` (2026-11-24, received mid-review): **K2 confirmed as built**, plus fixture and test tickets and two
    brief amendments. Per the Orchestrator, those tickets are not counted as missing in round 1.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed.
- **Scope of the diff** (`git diff 6fd1bf4...ed4b1ad`):
  - six new source files under `TendIngestion/Sources/TendIngestion/CloudOutput/`;
  - three new test files;
  - 30 fixtures and a README under `Fixtures/M2/provider-streams/`;
  - the dev-notes section.
  No existing source or test file is changed. The merge `4f3c23c` of `main` `6fd1bf4` adds nothing of its own.

## Summary
The work item does what the plan row and AC-M2-24 (Linux part) ask. The outcome mapping is right, and the tests would
fail if it were wrong. I found no Blocker or Major. Three Minors and three Nits follow.

- **Outcome mapping.**
  - Every reader error goes through `ProviderStreamError.stopReason`, and the adapter throws that reason. So
    `DraftPipeline` gives `noModel` with the plain-note offer before any draft, and `interrupted` after one. Emitted
    drafts stay, and an item still in progress is discarded (T-25).
  - Nothing can end `completed` on truncation:
    - `finish()` checks four things in order: `bodyEndedInsideEvent`, then the dialect's `checkEnd` (`noFinish`), then
      `noOutput`, then `outputUnfinished`.
    - A length cut is `cutShort(.lengthLimit)` for each provider: OpenAI `length`, Anthropic `max_tokens` and
      `model_context_window_exceeded`, Gemini `MAX_TOKENS`. That meets `po-m2-wi10.md` ruling 3 ("never `completed`").
      The `length-limit-after-first-draft` fixture pins it for each provider.
    - An unknown finish or stop reason is `unexpectedFinish` (`otherModelError`), never a normal end.
  - `fixtureOutcome` checks the exact outcome for all 30 fixtures. It checks the route, the reason, `discardedItem`, the
    input and the plain note, and that `error.stopReason` equals the reported reason.
- **K2 (end signal).** The rule is as built and now confirmed by the PO (`po-m2-wi13.md`). Each normal end needs the
  provider's own signal:
  - OpenAI: `stop` and `[DONE]`;
  - Anthropic: a normal `stop_reason` and `message_stop`;
  - Gemini: `STOP`.
  `emptyAndUnended` already checks, for every provider, that finished output JSON without the end gives `noFinish`. A
  mutant "finished JSON counts as a normal end" would therefore be killed at the reader level.
  - I agree that the PO's tickets are needed. Today, nothing checks the confirmed case **through the pipeline**: 3 drafts
    kept, `interrupted(outputCutShort)`, no `itemSkipped`. Nothing checks "last item only completable by (c) is
    discarded". Nothing checks finished `{"items":[]}` with no end giving `noModel`.
  - The Anthropic partial end is a real gap, because `Body.anthropic(end: false)` drops both signals together. A normal
    `stop_reason` without `message_stop` is not tested.
  - Dev-notes open question 1 should close citing `po-m2-wi13.md` in round 2.
- **K3 (same-chunk ordering).**
  - In `append`, events are read in order, and an event's text is read before its stop.
  - A stop that comes after new output in the same chunk is recorded and returned on the next call. In
    `stop(_:changed:)`, `changed` becomes true as soon as any event in the chunk had output. Invalid output is handled
    the same way (K4).
  - So the sequence an adapter yields is the same whether the stop arrives in the same chunk or in a later one.
  - Evidence: `deferredStop` (3 providers), `validTextBeforeBadByte`, and `splitChunks`. `splitChunks` reads 30
    fixtures × 42 cut sets and compares the reader end, the emitted titles, the final drafts and the outcome with the
    one-shot read. The developer's mutants M16, M17 and M26 confirm it.
  - **Result independent of chunk cuts:** this holds for every body within the cap, but not across the cap boundary
    (R29-F1).
- **The 1 MiB cap (R26-F2).**
  - `bytes.count <= responseByteLimit - receivedByteCount` cannot overflow. A refused chunk is not counted. The framer,
    the event parser and the output reader see only bytes that passed the cap.
  - `sizeCapBoundary` checks the boundary: exactly the limit is accepted, one byte more is refused, and M21 and M23
    confirm both.
  - Two edges are not right yet (R29-F1). The chunk that crosses the limit is dropped whole, so what is emitted depends
    on chunking. The cap also still counts bytes after the provider's end.
- **Strict envelope, ignored noise.**
  - Wrong-typed members that the dialect reads, a second choice, candidate or tool block, output after the finish, and
    data that is not JSON all stop calmly (`unexpectedStructure` or `eventNotJSON`).
  - Unknown members and events are ignored.
  - I probed the ruling-7 shapes on a scratch copy:
    - OpenAI: an `include_usage` chunk (`choices: []`) carrying `completion_tokens_details.reasoning_tokens` and an
      `obfuscation` member;
    - Gemini: a text part with `thoughtSignature`, and `usageMetadata.thoughtsTokenCount` with
      `modelVersion: gemini-3.5-flash-lite`;
    - Anthropic: a `thinking` block with `thinking_delta` and `signature_delta` before the tool block.
    All three read the right snapshot.
  - Gemini parts with `"thought": true` are skipped (M12). A non-boolean `thought` is not strict (R29-N1).
  - Two documented strict rules are untested (R29-F3).
- **K5 (refusal and safety).** These all map to `declined` and then `refusal`: OpenAI `delta.refusal` (non-empty) and
  `content_filter`; Anthropic `refusal`; Gemini `SAFETY` and the other safety stops, and `promptFeedback.blockReason`.
  - I agree with K5. `guardrail` is documented as the on-device generation guardrail, and the brief gives the same
    outcome for either.
  - Gemini `LANGUAGE` maps to `unsupportedLanguage`.
  - The in-stream error tables are each pinned row by row. My mutants R1, R2, R6 and R7 were killed.
- **K8 (fixtures made by a generator that is not committed).** The test table is independent of the generator:
  - `ProviderFixtureCase.common` states each fixture's reader error, emitted titles, skip count and end in Swift.
  - `invalidOffset` comes from `ProviderFixtures.invalidPrefix`, which is typed again by hand.
  - `outputText` checks that the happy and out-of-order fixtures join up to `happyOutput`, which is also typed again.
  - `happyDrafts`, `schemaViolatingRepairs` and `unknownEnumRepairs` pin the Q5 results field by field.
  - `fixtureList` fails on any extra or missing file.
  I read the invalid-event, truncated, provider-error and refusal fixtures by hand against the README. Each matches.
  The property test uses its own `DialectWriter` (3 seeds × 200 × 3 providers), not the fixtures.
- **PO tickets.**
  - Title arrives last, per provider: `titleArrivesLast`, one event per chunk and byte by byte; `neverAPartTitle` on
    all 30 fixtures.
  - No-room item completes by rule (a): `noRoomItemCompletesByRuleA`.
  - Cap stop per provider (`po-m2-wi10.md` ruling 3): the length-limit fixtures.
  - Ruling 7 fixture ticket: only partly met (R29-F2).
- **Swift 6, AC-M2-09, AC-M2-12.**
  - Everything is a `Sendable` value type. There is no `@unchecked`, `nonisolated(unsafe)`, `Task`, global mutable
    state or `print` in Sources. Typed throws are used throughout.
  - The files import only Foundation (TendCore types come through the module).
  - The AC-M2-09 scan found 0 violations in 46 files, and the AC-M2-12 vocabulary scan is green. No new case name holds
    a banned token (`declined`, `cutShort`, `noFinish`, `responseTooLarge`, `unexpectedFinish`, …).
  - AC-M2-23 "none blames the user": every case describes the stream, not the person, and no provider text is kept.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R29-F1 | Minor | `Sources/TendIngestion/CloudOutput/ProviderStreamReader.swift:73-76`; `Tests/…/ProviderDialectTests.swift:268-283` | **(a) The cap breaks chunk independence.** The chunk that would pass the limit is refused whole, so how much of the body is read depends on the transport's cuts. I reproduced this on a scratch copy for all 3 providers: a body of limit + 1 bytes, where item 1 completes well inside the limit. Read in one chunk, it gives `noModel(stoppedBeforeFirstDraft(unreadableOutput))` with 0 drafts. Read byte by byte, it gives `emitted "Mop the floor"` then `interrupted(unreadableOutput)`. This goes against the K3 principle ("whether a draft is emitted before a stop never depends on how the transport cut the body"). The person can lose a draft the model already wrote. It only happens past 1 MiB, so it is Minor. `sizeCapBoundary` says "for any chunking" but checks only the end error, not the drafts. **(b) The cap still counts after the provider's end.** A complete body (`[DONE]` / `message_stop` / `STOP`) followed by one more byte over the limit ends `responseTooLarge` instead of `completed` (probed for all 3 providers). This disagrees with "events after the provider's end are ignored". | (a) Read the part of the crossing chunk that fits under the limit, then stop with `unreadable(.responseTooLarge)` through the same deferral as K3/K4 (return the snapshot if that prefix added output; the next call throws). (b) Once `hasEnded`, drop later bytes without counting them, or document and test why not. Extend `sizeCapBoundary` (or a new test) to compare emitted titles and the outcome through the pipeline across one-shot, per-event and per-byte cuts for an over-limit body whose first item completes under the limit. Update K7. | Open |
| R29-F2 | Minor | `Fixtures/M2/provider-streams/synthetic/*`; `Sources/…/GeminiStreamDialect.swift:1-7`; dev-notes WI-M2-13 "Binding inputs" | **The `po-m2-wi10.md` rulings are not traced, and the ruling-7 fixture ticket is only partly met.** The ticket says "All three providers get usage and served-model fields in the fixtures, and the parsers ignore those fields for drafts". Served-model fields are present (`model`, `message.model`, `modelVersion`), and Anthropic and Gemini fixtures all carry usage. But only 1 of the 10 OpenAI fixtures (`out-of-order-fields`) has the `include_usage` chunk. Every real `gpt-6-luna` stream will have one, because `stream_options.include_usage` is a fixed member. No fixture carries the reasoning-model fields that ruling 7 condition 5 reads: `completion_tokens_details.reasoning_tokens`, `usageMetadata.thoughtsTokenCount`, and the Gemini 3.x part member `thoughtSignature`. My probes show the parsers ignore all three correctly, so behaviour is fine. The evidence is just not in the repo. The Gemini header is also out of date against ruling 7: it says "the request sets the thinking budget to 0" and `responseSchema`, but the request uses `thinkingConfig.thinkingLevel: "minimal"` and the JSON-Schema member. The dev-notes cite neither ruling 3 (cap stop = truncated, met by the length-limit fixtures) nor ruling 7. | Add the `include_usage` chunk (`choices: []`, `usage` with `completion_tokens_details.reasoning_tokens`) before `[DONE]` in each OpenAI fixture that reaches `[DONE]`, or at least in `happy-path`. Add `thoughtsTokenCount` to Gemini `usageMetadata` and a `thoughtSignature` on one text part in the Gemini happy path. Keep `fixtureOutcome` and `outputText` green. Fix the Gemini header. In the dev-notes, cite `po-m2-wi10.md` rulings 3 and 7 and map each ticket to its fixture or test. Can be done together with the `po-m2-wi13.md` fixture ticket. | Open |
| R29-F3 | Minor | `Sources/…/AnthropicStreamDialect.swift:135-136, 144-145, 160-165`; `Tests/…/ProviderDialectTests.swift:466-490` | **Two documented strict rules are not tested.** My mutants on a scratch copy **survived** (`--filter "Provider\|Dialect"`, 47 tests green): **R3**, `message_delta` before `message_start` accepted (`guard started \|\| true`); **R5**, a block index that has been stopped can be started again (`stoppedBlocks.insert` removed). The header lists both rules ("content or `message_delta` before `message_start`", "a block index started twice"). `message_stop` before `message_start` is not in the table either. | Add these cases to `AnthropicDialectTests.unexpectedStructure`: `message_delta` with no `message_start`, `message_stop` with no `message_start`, and `content_block_start` index 0 → `content_block_stop` 0 → `content_block_start` 0. Show that R3 and R5 are killed. | Open |
| R29-N1 | Nit | `Sources/…/GeminiStreamDialect.swift:40` | `part["thought"] == .bool(true)` is the only member the dialects read without the strict accessors. `"thought":"yes"` is read as output (probe: `outputNotJSON` at offset 0), not as `unexpectedStructure` (K6). It still fails calmly. | Read it with a strict bool accessor: `null` or missing means false, any other type means `unexpectedStructure`. Add one test row. | Open |
| R29-N2 | Nit | `Sources/…/ProviderStreamReader.swift:85-87` (with WI-M2-12 J9) | Each `append` that adds output rebuilds the snapshot, which costs time linear in the output so far. If the WI-M2-M4 adapter feeds `URLSession.AsyncBytes` one byte at a time, a pathological output close to 1 MiB becomes quadratic within the 10 s deadline. Normal captures (a few KB) are fine. | Add a WI-M2-M4 note in Known limitations: feed buffered chunks (for example up to each line end or 4 KB), never single bytes. No code change here. | Open |
| R29-N3 | Nit | dev-notes WI-M2-13 "Open questions" 1 | K2 is now answered (`po-m2-wi13.md`: truncated, confirmed as built). | Close open question 1 citing `po-m2-wi13.md`, and record the PO's tickets (the `finished-output-no-end` fixture × 3, the Anthropic partial-end test, the two reader tests, the mutant, README and `fixtureList` going to 11 per provider) in the follow-up table. I agree all of them are needed (see Summary, K2). | Open |

There are no Blocker or Major findings.

### Re-check list for WI-M2-M6 (K9), against current provider docs and the real recordings (no web access here)
For the ruling-7 models, each item is either confirmed or fixed with a test:
- **OpenAI `gpt-6-luna`, Chat Completions, `reasoning_effort: "none"`:**
  - `data: [DONE]` is still sent after `finish_reason: "stop"`.
  - The shape of the `include_usage` chunk: `choices: []`, coming after the finish chunk and before `[DONE]`.
  - Whether `obfuscation` or other new chunk members appear.
  - How a strict `json_schema` refusal streams (`delta.refusal`, then `finish_reason`).
  - The `content_filter` value.
  - The shape of an in-stream error (`{"error":{type,code}}` with no `choices`) and its `type`/`code` values
    (`server_error`, `rate_limit_exceeded`).
  - That no reasoning text is streamed in `delta` for a reasoning model on Chat Completions.
  - The full set of `finish_reason` values.
  - The served `model` value in the drift check.
- **Anthropic `claude-haiku-4-5-20251001`, `anthropic-version: 2023-06-01`, forced `tool_choice`:**
  - The event order (`message_start`, `content_block_start` `tool_use` with `input: {}`, `input_json_delta` starting
    with `""`, `content_block_stop`, `message_delta`, `message_stop`).
  - That `stop_reason` is `tool_use` for a forced tool.
  - That `refusal`, `model_context_window_exceeded` and `pause_turn` exist as stop reasons on this API version.
  - The `error` event types, including `overloaded_error`.
  - That no `thinking` block appears without a `thinking` member.
  - The tool name `record_items`, which the reader does not check yet (WI-M2-10 follow-up).
- **Gemini `gemini-3.5-flash-lite`, `alt=sse`, `thinkingLevel: "minimal"`:**
  - That no `thought: true` parts are sent without `includeThoughts`. If thought parts or `thoughtSignature` do
    appear, they must be skipped or ignored.
  - That `finishReason: "STOP"` is on the last chunk (possibly with empty text), with `usageMetadata` and
    `thoughtsTokenCount` in the same chunk.
  - The current `finishReason` enum. Newer values such as `MALFORMED_FUNCTION_CALL`, `UNEXPECTED_TOOL_CALL`,
    `TOO_MANY_TOOL_CALLS`, `MISSING_THOUGHT_SIGNATURE` and the `IMAGE_*` values now map calmly to `otherModelError`.
    Decide whether any of them should map to `declined`.
  - The `promptFeedback.blockReason` values.
  - Whether `candidates[].index` is present.
  - How a mid-stream error reaches the client: an SSE `data:` object, or an HTTP error before the stream (the latter is
    the transport's job, WI-M2-14/M4).
  - The `modelVersion` value in the drift check.
- **All three:** the line endings actually used (the Gemini fixtures assume CRLF), and that no body comes near the
  1 MiB cap.

## Tests run (reviewer, independent)
All runs used the worktree at `ed4b1ad`, in `swift:6.2-noble` with `-Xswiftc -warnings-as-errors`.

| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev29-TendIngestion --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 445 tests in 55 suites passed after 108.542 seconds.` 0 warnings. AC-M2-09 scan: "TendIngestion (required) Packages/TendIngestion/Sources: 46 files scanned". Fixture list: 10 per provider, as the table says. Largest fixture: 28,697 bytes. |
| `swift test --scratch-path /tmp/rev29-TendCore --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 77.975 seconds.` 0 warnings. |
| `swift test --scratch-path /tmp/rev29-TendSourceScan --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 1.702 seconds.` 0 warnings. |

The counts match the dev-notes (445 / 141 / 63).

**Reviewer probes** were run on a scratch copy (`git archive` to `/tmp/rev29-mut`) with a throwaway test file, which I
removed afterwards:
- the cap's chunk dependence (R29-F1a, 3 providers);
- a byte past the limit after the provider's end (R29-F1b);
- the ruling-7 shapes: OpenAI usage with `reasoning_tokens` and `obfuscation`, a Gemini `thoughtSignature` with
  `thoughtsTokenCount`, an Anthropic thinking block. All read correctly;
- a non-boolean Gemini `thought` (R29-N1).

**Reviewer mutants.** Each was run alone on the scratch copy, with `--filter "Provider|Dialect"`. None of them repeats
the developer's 29.

| # | Mutant | Result |
|---|---|---|
| R1 | OpenAI `server_error` → `otherModelError` | killed (`errorObject`) |
| R2 | Gemini code 429 → `otherModelError` | killed |
| R3 | Anthropic `message_delta` before `message_start` accepted | **survived** (R29-F3) |
| R4 | Reader: `bodyEndedInsideEvent` also after the provider's end | killed (`afterTheEnd`) |
| R5 | Anthropic: a stopped block index may start again | **survived** (R29-F3) |
| R6 | Anthropic `permission_error` → `otherModelError` | killed |
| R7 | Gemini 403 → `otherModelError` | killed |
| R8 | Anthropic `stop_sequence` not a normal end | killed (`stopReasons`) |

6 of 8 were killed. The 2 that survived are R29-F3.

## Checklist
- [x] Correctness vs ACs: the AC-M2-24 Linux part has a test for every listed fixture kind (happy, out-of-order/split,
  truncated, invalid JSON, schema-violating, unknown enums, refusal). The noModel/interrupted mapping is exact. The
  AC-M2-05 cloud-parser bullet is covered by `titleArrivesLast` and `neverAPartTitle`. The cap boundary has gaps
  (R29-F1); the PO K2 tickets are for round 2.
- [x] Tests meaningful: the table is independent of the generator, the property test is seeded, and 29 developer
  mutants plus 6 of 8 reviewer mutants were killed. The 2 survivors are R29-F3. No test is skipped or weakened.
- [x] Swift 6 concurrency safe: pure `Sendable` value types, no unchecked escapes, no tasks.
- [x] No force unwraps / `try!` in product code paths. `try?` is used once, on a prefix known to be valid.
- [x] Privacy (P-1…P-4): no I/O, network or logging (AC-M2-09: 0 violations in 46 files). The fixtures hold no key,
  header, host or household data.
- [x] UX-2/UX-3 enforced in engine: UX-2 is n.a. For UX-3, the names are calm (AC-M2-12 scan green), and a stop keeps
  drafts or offers the plain note.
- [x] Accessibility (UI): n.a., no UI.
- [x] Performance: linear per byte; snapshot rebuild per append (R29-N2, an adapter note).
- [x] No new dependency without ADR: Foundation and TendCore only.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The code parses provider responses only. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | The case names describe the stream (`declined`, `cutShort`, `noFinish`, `responseTooLarge`, `unexpectedFinish`). The AC-M2-12 vocabulary scan is green, and no provider text is kept. Every stop keeps emitted drafts (`interrupted`) or returns the input with the plain note (`noModel`). Finished values only, per provider, so no prefix can be guarded away. K2 is confirmed by the PO as the calm, honest default. R29-F1 can drop a draft past 1 MiB, but the input is still returned. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | Nothing here chooses a model or a route. |
| P-2 No data leaves device (except user iCloud / P-3 request) | pass | Pure parsing over in-memory bytes. No network, file or log API in Sources (AC-M2-09). No dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | It reads responses only and adds no request field. `lookupQueries` is always empty, so there is no `Tool` for the cloud. The size cap bounds what a provider can make the phone hold. |
| P-4 Media not persisted without consent | n.a. | Text only, in memory. The fixtures hold response bodies only. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | PR #29 at `ed4b1ad` (base `6fd1bf4`), fresh context, detached worktree `/home/user/wt-rev29`. |
| 2026-11-24 | Orchestrator | Reviewer | accepted (mid-review) | `po-m2-wi13.md`: K2 confirmed as built. The PO's fixture and test tickets and the brief amendments are not counted as missing in round 1. I read the note on the mount. I agree the tickets are needed (Summary, R29-N3). |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper; Developer | sent | **APPROVE.** No Blocker or Major. R29-F1 (cap: chunk dependence and counting after the end), R29-F2 (ruling-7 fixture shapes and traceability), R29-F3 (two untested Anthropic strict rules; 2 surviving mutants) are Minor. R29-N1…N3 are Nits. Tests: 445 / 141 / 63 green, 0 warnings. 6 of 8 reviewer mutants killed. K9 re-check list given for WI-M2-M6. |

## Round 2 — head `ac991d1` (merge `2f26834` of `main` `f1b6458`, then fix commits `0a39ba5` and `c32f370`, notes `ac991d1`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 2
- **Requirements:** AC-M2-24 (Linux part), AC-M2-05, FR-A1; review R29-F1…F3, R29-N1…N3; PO `po-m2-wi13.md` (K2
  tickets and brief amendments 1–2) and `po-m2-wi10.md` rulings 3 and 7.
- **Milestone lock:** `STATUS.md` still shows M1 `ACCEPTED`, M2 `IN-BUILD`. Allowed.
- **Merge `2f26834`:** the merge adds no code of its own.
  - `git diff f1b6458 2f26834 -- Packages Fixtures` equals the round 1 diff `git diff 6fd1bf4 ed4b1ad`, ignoring
    `index` lines.
  - `git show --cc` shows a hand resolution only in `dev-notes.md`.

### Summary
Every round 1 finding is fixed, and I checked each fix in the new diff. My own mutants for each fix are killed. The two
PO brief amendments match `po-m2-wi13.md` word for word.

One new problem was introduced in this round. `splitChunks` is the AC-M2-24 split-chunk test. It now runs the pipeline
comparison for only 5 of its 42 cut sets. The dev-notes say the round was done "without weakening, skipping or
shrinking any test", which is not accurate. On a scratch copy I put all 42 cut sets back, and the full suite is green.
So the reduction is not needed (R29-R2-F1, Major).

- **R29-F1 (cap).** `append` now reads `bytes.prefix(room)`, counts only that part, and uses the K3 hold rule when the
  chunk goes past the limit. Once the provider's end has arrived, it returns nil and counts nothing.
  - Exactly the first `responseByteLimit` bytes are read, however the body is cut.
  - My round 1 reproduction is now a test: `sizeCapChunkIndependence` runs 3 providers × 11 cut sets through the
    pipeline, and each gives emitted `["Mop the floor"]` and then `interrupted(unreadableOutput)`.
  - `sizeCapBoundary` covers the end: a body of exactly the limit is read, padding before the end gives
    `responseTooLarge`, bytes after the end still give `completed`, and `receivedByteCount` stops at the end.
  - My mutants:
    - V1, "read the whole crossing chunk, count only the part that fits": killed by `sizeCapBoundary` and
      `sizeCapChunkIndependence`.
    - V2, "the cap stop ignores the hold rule": killed by `sizeCapChunkIndependence`.
- **The unrequested product change: the snapshot is built once per `append`.** I compared the code and found it
  equivalent.
  - `StructuredOutputReader.read(bytes:)` followed by `snapshot` is exactly `append(bytes:)` split in two. The old
    method was `try parser.append(bytes)` then `Self.snapshot(of: parser.value)`.
  - `append` and `stop` now return `output.snapshot`, which is computed from the same parser state as the old cached
    `snapshot` var after its last update.
  - The one place where they could differ is the K4 `try?` re-read of the valid prefix. That read cannot fail: the
    parser reports the bad byte, or the delimiter after a malformed number, inside the current piece. So
    `offset ≥ outputByteCount`, and the prefix is the valid text before it.
  - The `changed` and hold logic is unchanged. My mutant V3, "a stop never throws at once (always return the
    snapshot)", is killed by `stickyAndClosed` and `sizeCapBoundary`.
  - The property test (3 seeds × 200 outputs × 3 providers, compared with `StructuredOutputReader.parse`, every step
    only grows) and every K3/K4 test pass. All of them compare the yielded snapshots.
  - The change is a pure performance change, so I accept it. It is recorded honestly as "unrequested" in the dev-notes.
- **R29-F2 (ruling 7).**
  - All 33 fixtures carry the served model IDs: `gpt-6-luna`, `claude-haiku-4-5-20251001`, `gemini-3.5-flash-lite`.
  - OpenAI: `"usage":null` on every chunk, and the `include_usage` chunk (`"choices":[]` and `reasoning_tokens`)
    after the finish chunk and before `[DONE]`.
  - Gemini: `thoughtsTokenCount`, a `thoughtSignature` on the first part, and the output in sorted-key
    `responseJsonSchema` order.
  - `rulingSevenShapes` pins these shapes. `outputText` checks that the Gemini text equals `geminiHappyOutput`, read
    with `JSONSerialization`, independently of the reader.
  - The dialect headers now describe the ruling-7 request.
  - The dev-notes trace rulings 3 and 7 to fixtures and tests.
- **R29-F3.** I re-ran my R3 and R5 mutants on the new head, plus R3b (`message_stop` before `message_start`). All are
  now killed by `AnthropicDialectTests.unexpectedStructure`. Each new row is a valid stream except for the one rule it
  tests.
- **R29-N1.** There is a strict `bool(_:)` accessor. A new row, `"thought":"yes"`, gives `unexpectedStructure`, and
  `null` and `false` are read as output. My N1 mutant, which puts back the round 1 comparison, is killed.
- **R29-N2.** The WI-M2-M4 adapter ticket is in the follow-up table. The code change is covered above.
- **R29-N3 and the `po-m2-wi13.md` tickets.**
  - Open question 1 is closed, citing the note.
  - `finished-output-no-end` exists for each provider. Its end is right: OpenAI has no `finish_reason` and no
    `[DONE]`; Anthropic ends at `content_block_stop`; the last Gemini chunk has no `finishReason`.
  - It is pinned in `fixtureOutcome` and in `finishedOutputNoEnd` (one shot, per event and byte by byte): 3 drafts,
    0 skips, one `finished`, `interrupted(outputCutShort, discardedItem: nil)`.
  - `normalStopWithoutMessageStop` checks the three normal stop reasons without `message_stop`.
  - `noEndDiscardsTheLastItem` and `noEndEmptyItems` cover the two reader cases.
  - The developer's M31 ("finished JSON counts as a normal end") is killed.
  - The README and `fixtureList` now say 11 per provider.
  - **Brief amendments:** I compared the text with a script after normalising whitespace. Amendment 1 is in the
    `interrupted` bullet, right after the ruling-3 sentence. Amendment 2 replaces the last sentence pair of AC-M2-24.
    Both match `po-m2-wi13.md` word for word; only the line breaks were reflowed.

### Findings (round 1 → round 2)
| # | Severity | Round 2 evidence | Status |
|---|---|---|---|
| R29-F1 | Minor | Fixed as above. V1 and V2 killed. `sizeCapChunkIndependence` and the new `sizeCapBoundary` rows pass. | Closed |
| R29-F2 | Minor | Fixed as above. `rulingSevenShapes`, `outputText` and `fixtureOutcome` pass on the regenerated fixtures. | Closed |
| R29-F3 | Minor | Fixed. Reviewer mutants R3, R3b and R5 killed. | Closed |
| R29-N1 | Nit | Fixed. Reviewer mutant N1 killed. | Closed |
| R29-N2 | Nit | Ticket recorded (WI-M2-M4). The snapshot-once change was checked and is equivalent. | Closed (ticket) |
| R29-N3 | Nit | Fixed, and the PO tickets are delivered. | Closed |

### New findings (round 2)
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R29-R2-F1 | Major | `Tests/TendIngestionTests/ProviderStreamFixtureTests.swift:135-169` (`splitChunks`); dev-notes WI-M2-13 round 2, "Why the R29-N2 code change" | **The AC-M2-24 split-chunk test was narrowed to get the suite green, and the dev-notes say it was not.** In round 1, every fixture's emitted titles, final drafts and outcome were compared with the one-shot run through `DraftPipeline` for all 42 cut sets. Now that is done for only 5: one shot, per event, byte by byte, and 3 random. The other 37 compare only the reader's end and last step. The pipeline result depends on the whole sequence of snapshots: when rule (a) fires, D8 skips, re-marks. So the reader-level check does not replace it. Across 33 fixtures, 1,221 pipeline comparisons were removed. The test comment gives the reason: "the time-limited cancellation tests share the cooperative pool". The dev-notes say the round was done "without weakening, skipping or shrinking any test". CLAUDE.md §6 says never weaken a test to get green. **The reduction is not needed.** On a scratch copy of `ac991d1` I put back all 42 pipeline comparisons (`if index < 5` → all). The full suite was green: `✔ Test run with 491 tests in 57 suites passed after 172.525 seconds`, with `splitChunks` (33 cases) at 145.5 s, under load average about 6. The snapshot-once change already removed the real cost. The rated severity is Major, not Blocker: the AC clause is still tested (byte by byte and per event through the pipeline for every fixture), and nothing hides a defect (my restored run is green). | Put the pipeline comparison back for all 42 cut sets in `splitChunks`, and keep `.serialized` and `Task.yield()` if useful. Correct the dev-notes sentence. If a test-time problem remains after PR #30 merges, raise it with the reviewer before reducing any coverage. Do not shrink the test silently. | Open |
| R29-R2-N1 | Nit | `Tests/TendIngestionTests/ProviderStreamSupport.swift:190-212` (`ChunkedProviderModel`) | The producer `Task` is cancelled in `onTermination`, but its loop never checks `Task.isCancelled`. After a cancel it keeps calling `append` on all the remaining chunks, and the yields are dropped. This is test-only and finite, but it wastes pool time, which is the very resource this round was protecting. | Optional: `try Task.checkCancellation()`, or `if Task.isCancelled { break }`, in the loop. | Open (optional) |

### PR #30 (WI-M2-14, head `b73d939`): will anything conflict?
- **Text:** `git merge-tree ac991d1 b73d939` gives one conflict, in `docs/milestones/M2/dev-notes.md`. Both PRs append a
  section at the end, so the fix is to keep both sections. `brief.md` merges automatically: this PR's hunks are at the
  `interrupted` bullet and the end of AC-M2-24; PR #30's are in "Timeouts" and AC-M2-23. No source or test file is
  changed by both PRs.
- **Meaning:**
  - PR #30's `CloudResponseBody` passes the body on as `[UInt8]` transport chunks for the WI-M2-M6 adapter to feed into
    `ProviderStreamReader`. That fits K7, since the cap stays in the reader and WI-M2-14 adds none. It also fits the
    R29-N2 ticket, because it does not feed single bytes. The WI-M2-M4/M6 adapter must keep chunks as they come.
  - PR #30's deadline rule ("nothing seen at or after the deadline is read") sits in front of the reader. It does not
    change any outcome rule here.
  - PR #30 makes the WI-M2-09 test waits event-driven, and those time-limited tests were the reason given for
    narrowing `splitChunks`. That removes the reason entirely. R29-R2-F1 can be fixed before or after #30 merges; it
    is already green without it.

### Tests run (reviewer, round 2)
All runs used the worktree at `ac991d1` (detached), in `swift:6.2-noble` with `-Xswiftc -warnings-as-errors`.

| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev29-TendIngestion --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 491 tests in 57 suites passed after 155.855 seconds.` 0 warnings. AC-M2-09 scan: "TendIngestion (required) Packages/TendIngestion/Sources: 52 files scanned". Fixture list: 11 per provider. |
| `swift test --scratch-path /tmp/rev29-TendCore --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 132.175 seconds.` 0 warnings. |
| `swift test --scratch-path /tmp/rev29-TendSourceScan --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 4.298 seconds.` 0 warnings. |
| Scratch copy (`git archive ac991d1` to `/tmp/rev29-mut2`), `splitChunks` with the pipeline comparison back for all 42 cut sets, full TendIngestion suite | `✔ Test run with 491 tests in 57 suites passed after 172.525 seconds.` `splitChunks`: 33 cases passed after 145.472 s. |

**Reviewer mutants (round 2).** These ran on the scratch copy, one at a time, with `touch` after each change and each
restore. The filter was `Provider|Dialect` for V1–V3 and `Dialect` for the others. Afterwards
`diff -r -q Packages /tmp/rev29-mut2/Packages` was empty.

| # | Mutant | Result |
|---|---|---|
| V1 | Cap: the whole crossing chunk is read, but only the part that fits is counted | killed (`sizeCapBoundary`, `sizeCapChunkIndependence`) |
| V2 | Cap: the stop ignores the hold rule (`changed: false`) | killed (`sizeCapChunkIndependence`) |
| V3 | `stop` always returns the snapshot, never throws at once | killed (`stickyAndClosed`, `sizeCapBoundary`) |
| R3 | Anthropic `message_delta` before `message_start` accepted | killed (`unexpectedStructure`) |
| R3b | Anthropic `message_stop` before `message_start` accepted | killed |
| R5 | Anthropic: a stopped block index may start again | killed |
| N1 | Gemini `thought` read with the round 1 comparison | killed (Gemini `unexpectedStructure`) |

7 of 7 were killed.

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | A draft read before the cap is no longer lost to how the body was cut (R29-F1). Finished output without the provider's end keeps every draft and never claims `completed` (`po-m2-wi13.md`). The new names (`bool`, `finished-output-no-end`) pass the vocabulary scan (52 files). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | Parsing only. |
| P-2 No data leaves device (except user iCloud / P-3 request) | pass | No network, file or log API in Sources (AC-M2-09: 52 files, 0 violations). No dependency. The fixtures are synthetic, with no key, header or household data. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Response reading only. The ruling-7 request members appear only in comments. Bytes after the provider's end are dropped. |
| P-4 Media not persisted without consent | n.a. | Text only, in memory. |

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | Round 2 at `ac991d1` (merge `2f26834` of `main` `f1b6458`; fixes `0a39ba5`, `c32f370`; notes `ac991d1`). The round 1 review file is committed on the branch; the worktree was checked out detached. |
| 2026-11-24 | Reviewer | Orchestrator → Developer | returned | **CHANGES REQUIRED.** All round 1 findings closed (R29-F1…F3, N1…N3), the `po-m2-wi13.md` tickets delivered, and brief amendments 1–2 word for word. The snapshot-once change is equivalent. New Major R29-R2-F1: `splitChunks` pipeline comparison narrowed from 42 to 5 cut sets and the dev-notes say otherwise; restoring all 42 is green (172.5 s). Nit R29-R2-N1. PR #30: only the dev-notes append conflicts; no code overlap. Tests: 491 / 141 / 63 green, 0 warnings. 7 of 7 reviewer mutants killed. |

## Round 3 — head `f876e97` (merge `9684a38` of `main` `e4bcdeb` (PR #30), then fix commit `f876e97`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 3
- **Requirements:** AC-M2-24 (split chunks, Linux part), AC-M2-05, FR-A1; review R29-R2-F1 and R29-R2-N1.
- **Milestone lock:** `STATUS.md` still shows M1 `ACCEPTED`, M2 `IN-BUILD`. Allowed.

### Summary
- **The merge `9684a38` of PR #30 is clean.**
  - `git diff ac991d1 9684a38 -- Packages Fixtures` equals PR #30's own diff
    (`git diff f1b6458 e4bcdeb -- Packages Fixtures`).
  - `git diff e4bcdeb 9684a38 -- Packages Fixtures` equals this PR's own diff
    (`git diff f1b6458 ac991d1 -- Packages Fixtures`), ignoring `index` lines.
  - So no code was changed by the merge, and no code conflicted. `git show --cc` shows a hand resolution only in
    `dev-notes.md`.
  - A line-level check found no line of either parent's `dev-notes.md` missing from the merge (0 of 4,106 for this
    PR, 0 of 3,977 for PR #30), and no conflict markers. The WI-M2-14 section (line 3671) and the WI-M2-13 section
    (line 3979) are both whole.
  - `brief.md` merged automatically. Both K2 amendments (`WI-M2-13 K2`, 2 occurrences) and both PR #30 amendments
    (`WI-M2-14 Q2` and `Q3`) are present, with no markers.
- **The fix commit `f876e97`** changes two test files and the dev-notes, and the review file is now committed. No
  source file is changed.

### Findings (round 2 → round 3)
| # | Severity | Round 3 evidence | Status |
|---|---|---|---|
| R29-R2-F1 | Major | **Fixed.** `ProviderStreamFixtureTests.splitChunks` again runs the pipeline comparison (emitted titles, final drafts and outcome against the one-shot run) for **every** cut set. The `if index < 5` gate is removed, and the loop body is the round 1 code plus the round 2 reader-level `steps.last` check. The test name now says "(reader and pipeline: all 42)". In my run it passed 33 cases in about 135 s. **Dev-notes correction:** the false sentence is corrected in place. The correction says the test was narrowed, why, and that it broke CLAUDE.md §6. I checked its claim that no other existing test was narrowed in round 2 against the round 2 test diff, and it holds. `sizeCapBoundary` replaced its one-byte-over case with a padding-before-the-end case and added checks. Its `receivedByteCount` expectation changed on purpose with the R29-F1 behaviour (4 → 10). The Gemini `parts` test and the Anthropic and Gemini `unexpectedStructure` tables only gained members or rows. The other changes are `.serialized` and `Task.yield()`, which remove no coverage. | Closed |
| R29-R2-N1 | Nit | **Fixed.** The `ChunkedProviderModel` producer loop returns on `Task.isCancelled` before each `append` (test support only). After termination the continuation is already ended, so returning without `finish` is fine. | Closed |

There are no open Blocker, Major or Minor findings in this PR. Open tickets elsewhere: R29-N2 (WI-M2-M4: feed buffered
chunks) and the K9 re-check list (WI-M2-M6).

### Tests run (reviewer, round 3, merged tree)
All runs used the worktree at `f876e97` (detached), in `swift:6.2-noble` with `-Xswiftc -warnings-as-errors`, at load
average about 4 to 5.

| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev29-TendIngestion --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | `✔ Test run with 525 tests in 63 suites passed after 161.327 seconds.` 0 warnings. `splitChunks` "(reader and pipeline: all 42)": 33 cases passed. AC-M2-09 scan: "TendIngestion (required) Packages/TendIngestion/Sources: 55 files scanned". AC-M2-12 vocabulary scan: 55 files. The PR #30 time-limited tests are all green in the same run. |
| `swift test --scratch-path /tmp/rev29-TendCore --package-path Packages/TendCore -Xswiftc -warnings-as-errors` | `✔ Test run with 141 tests in 18 suites passed after 127.171 seconds.` 0 warnings. |
| `swift test --scratch-path /tmp/rev29-TendSourceScan --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors` | `✔ Test run with 63 tests in 4 suites passed after 4.466 seconds.` 0 warnings. |

The 525 tests are 491 from round 2 plus 34 from PR #30, and match the dev-notes.

### Law check (round 3)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No source change in this round. The vocabulary scan is green over 55 files. The restored test again proves through the pipeline, for every cut set, that drafts are kept the same way. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | Parsing only. |
| P-2 No data leaves device (except user iCloud / P-3 request) | pass | AC-M2-09: 55 files, 0 violations. No dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | No request change. The merge brings in PR #30's reviewed transport unchanged. |
| P-4 Media not persisted without consent | n.a. | Text only, in memory. |

### Handoff log (round 3)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | Round 3 at `f876e97` (merge `9684a38` of `main` `e4bcdeb`; fix `f876e97`). The round 2 review file is committed on the branch; the worktree was checked out detached. |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper | sent | **APPROVE.** R29-R2-F1 closed: all 42 pipeline comparisons are back, and the dev-notes correction is accurate. R29-R2-N1 closed. The PR #30 merge is clean: the code diffs equal each side's own, both dev-notes sections are kept whole, and there are no markers. Tests: 525 / 141 / 63 green, 0 warnings, scans 55 files with 0 violations. No open Blocker, Major or Minor. |
