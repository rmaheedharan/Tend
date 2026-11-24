# M2 Code Review — WI-M2-10 context selector and cloud payload builder (PR #28, `m2/payload-builder`, head `f1f6baf`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** FR-A1, P-1, P-2, P-3, P-4, UX-3. This PR delivers part of AC-M2-20; WI-M2-11 owns the AC and
  delivers the ≥ 500-household sentinel and structural proof. Also covered: AC-M2-09 Rule 4 narrowing (review R1-F6)
  and regression runs of AC-M2-09 and AC-M2-12. Inputs to AC-M2-21 (formatting), AC-M2-26 (`ds2-gated` allowed lists)
  and AC-M2-28 (key-path form).
- **Binding inputs checked:** `CLAUDE.md`. Brief: Definitions ("Cloud request", "Duplicate shortlist", "Keywords of a
  text", "Local duplicate re-check", "Item completion"), AC-M2-09 Rule 4, AC-M2-20, AC-M2-21, and Q12, Q16–Q19. Plan:
  WI-M2-10 row and detail section (provider shapes, Q18 models and the five conditions, N-3), "Named files", "Real
  provider recordings", R-6, R-15. ADR-0005 Decisions 3–6. Dev-notes WI-M2-10 (D1–D11, open questions 1–5). PO notes
  `po-m2-wi12.md` ruling 2, `po-m2-wi15.md` ruling 2, `po-q21-q22.md` (R1-F6 ticket), `owner-decisions.md` (Q12, Q16
  and Q17 still use the PO defaults). Received mid-review: `po-m2-wi10.md` (PO rulings 1–4 and 6–7 on this PR's open
  questions and the replacement model list) and `l1-model-check-2026-11-23.md` (the Orchestrator's live check, L1/L1b).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. This is M2 work, so it is allowed. No protected
  path is touched (`git diff --stat 6fd1bf4...f1f6baf`: Fixtures/M2/payload, Packages/TendIngestion, Packages/
  TendSourceScan, Tools/TendTools, `docs/milestones/M2/dev-notes.md`, and one new row in `docs/milestones/M2/plan.md`).
- **Limits of this review:** I had no web access myself. For model currency and API shapes I rely on the Orchestrator's
  live check (L1/L1b) and the PO's rulings. As the coordinator directed, model IDs do not block this PR; I record
  instead what in the code makes a model swap hard (F7).

## Summary
The builder is small, pure and Foundation-only. Its output type cannot carry anything outside ADR-0005 Decision 3.
Details:
- `CloudRequest` and `CloudRequestHeader` have no public initialiser. Only `CloudPayloadBuilder.request` can make one.
- The key is held as an `APIKey` inside an internal enum, and `withValue` is the only way to read it.
- The input type stores exactly `capture: String`, `roomNames: [String]` and `shortlistTitles: [String]`. The `Mirror`
  test pins this.

I went through the focus areas one at a time:

| Focus | What I checked | Result |
|---|---|---|
| Nothing outside the allowed fields leaves the phone (P-2, P-3, ADR-0005 D3) | I read all 9 golden bodies and listed every non-schema leaf path per provider (Python, outside the code under test). OpenAI: `max_completion_tokens, messages[].content, messages[].content[].text/type, messages[].role, model, response_format.type, store, stream, temperature`. Anthropic: `max_tokens, messages[]…, model, stream, system, temperature, tool_choice.name/type, tools[].description/name`. Gemini: `contents[].parts[].text, contents[].role, generationConfig.{maxOutputTokens, responseMimeType, temperature, thinkingConfig.thinkingBudget}, systemInstruction.parts[].text`. The rest is the output schema. No date, time zone, ID, state, locale or device field appears. The instructions contain no date. | pass |
| Headers and key placement per provider | Head files: OpenAI `Authorization: Bearer <key>`, `Content-Type`. Anthropic `x-api-key`, `anthropic-version: 2023-06-01`, `Content-Type`. Gemini `x-goog-api-key`, `Content-Type`, with query `alt=sse` only and no `key=`. Test `keyPlacement` checks that the key is in no other header value, the method, host, path, query or body. Dev mutant T2 (`key=` added) is killed. | pass |
| User content is one canonical JSON text that quotes, newlines or key-like text cannot break | `CloudPayloadBuilder.userContent` writes the three slots with `CanonicalJSONWriter`. Test `userContentIsData` uses 7 hostile texts: an injected `"},"rooms":…`, NUL, DEL, U+2028 and others. The `JSONSerialization` oracle reads back the same three slots, and the body key paths do not change. I decoded each golden user-content string in Python: it is canonical JSON with exactly `capture`, `existingTasks[{index,title}]` and `rooms`. | pass |
| Shortlist titles sent = the duplicate rules' shortlist, ≤ 10 (Q12 default) | In production, `ModelRouter.events` builds `DraftDuplicateRules.cloud(titleSharing, capture: input, …)` and `DraftPipeline` takes the titles from `rules.sentShortlistTitles`. So the titles sent and the index claims accepted come from one shortlist (`DuplicateMarker.swift:178`, `DraftPipeline.swift:37`). I derived the G2 shortlist (4 titles) and the G3 shortlist by hand from brief Definitions steps 1–6. G3 has 13 eligible titles: Fold, Wash (K = 2); Air, Dry, Replace, Sort (K = 1, R = 1); Bleach, Buy "soft", Count, Hang (K = 1, R = 0, by folded title). The list is cut at 10, and Iron, Mend, Stack and Paint are dropped. Both match the golden bytes exactly. The selector is checked against the WI-M2-07 oracle over 3,600 seeded captures. The builder itself does not cap the count (F3). | pass (see F2, F3) |
| Room names as written (Q19) | G3 sends `"  Hall  "`, `Laundry "nook"`, `Shed/Yard`, `Loft\attic` and `Café` unchanged, and G2 sends `Kids’ room` with the typographic apostrophe. No sentinel is in a room name. D11 (blank names sent) has no test (F2). | pass |
| No `null` in rule-(a) fields (PO `po-m2-wi12.md` ruling 2) | `title`, `room` and `sourcePhrase` are required strings. `kind`, `effort`, the three flags and `time.anchor` are non-nullable. `anchor` offers `none`, and `unrecognized` is never offered. Only the other time members and the two claims are nullable (`anyOf …null` in JSON Schema, `nullable: true` in Gemini). Tests: `schemaValues`, `ruleAWithoutNull`, `blankRoomAndPhrase` (`""`, spaces, tab/newline → room `none`, phrase nil), and `instructionsBlankMeaning` (no request to invent). | pass |
| Key paths in results-file form (PO `po-m2-wi15.md` ruling 2) | `allowedListPattern` reads the pattern from the committed `results-v1.schema.json`, pins it to `^\$(\.[A-Za-z0-9_-]+|\[\])*$`, and runs all 53/53/64 paths through it, with 6 bad paths refused. I checked independently in Python that each committed list's path set equals the leaf paths of all 3 goldens for that provider. | pass |
| Goldens are deterministic and checked independently | The goldens are written by the builder, but they do not rest on the builder alone. (1) I re-serialised all 9 bodies and 3 lists with Python `json.dumps(sort_keys, ensure_ascii=False, separators)`, checking for duplicate and sorted keys and refusing floats. All 12 are byte-identical: keys sorted by UTF-8, no `\/`, no `\u` escapes, no trailing newline. (2) The shortlists are hand-derived (above). (3) The leaf paths come from a `JSONSerialization` oracle. (4) The opt-outs and sampling are read at concrete paths through `JSONSerialization`. `.gitattributes` `* -text` protects the bytes. The test writes regenerated files only when `TEND_PAYLOAD_GOLDEN_OUT` is set, never into the repository. | pass |
| Rule 4 narrowing is not a weakening of AC-M2-09 | Before this PR, a bare host passed in any `TendIngestion` file. Now it passes only at `providerTableFile` (exact path); anywhere else in TendIngestion it is "bare host outside the provider table", and outside TendIngestion it is unchanged. The brief text ("the payload builder's provider table … holds the bare hosts") is now enforced literally. The 4 removed assertions are each replaced by the same check at the table path plus a new negative check at the old path. Nothing is relaxed. One gap: the exact-path match is not pinned by any test (F1). | pass (F1) |
| No key ever printed | `CloudRequest`/`CloudRequestHeader` `description`, `debugDescription` and `customMirror` show `(hidden)` and the body byte count only. `requestFormatting` covers `String(describing:)`, `String(reflecting:)` and `dump` for the request and each header, and checks that the key, the capture and a room name are absent. `tend-payload-dump` takes no key (`--key` exits 64) and prints the body only. Test `print`s show byte and path counts only. The fake key appears only in fixtures and test literals. | pass |
| Swift 6 concurrency | All new production types are `Sendable` value types with no isolation. There is no `@unchecked Sendable`, `nonisolated(unsafe)`, `Task {}`, `try!` or force unwrap in the diff. The test transport uses `Mutex` (Synchronization, macOS 26 / iOS 26 platforms). | pass |
| AC-M2-09 / AC-M2-12 scans | My run: `AC-M2-09 scan: 46 files in total, 0 violations`; `AC-M2-12 vocabulary scan: 46 files, 9 exempted (the list), 0 violations`. The exemption list is not changed by this PR. | pass |

**Wiring (D6).** The `DraftDuplicateCheck.sentShortlistTitles` requirement has a default of `[]`, so every
non-cloud check sends no titles. Only `DraftDuplicateRules` on the cloud Q12 = yes path returns entries. Before this
PR, the `ModelRouter` comment already said the rules are built for the chosen route with `input` as the capture, so the
titles cannot belong to another route or capture. Stream, marker and router behaviour are unchanged: all 401 earlier
TendIngestion tests are green unchanged.

**Provider shapes and models (R-6; superseded by L1/L1b and PO ruling 7).** The live check found that the built model
list no longer holds. `gpt-4.1-mini-2025-04-14` is deprecated, with shutdown on Jan 14, 2027. Access to
`gemini-2.5-flash` is limited for new projects. `claude-haiku-4-5-20251001` is active. PO ruling 7 sets the final M2
list:
- OpenAI `gpt-6-luna`: no `temperature`, `reasoning_effort: "none"`, `stream_options.include_usage`.
- Anthropic `claude-haiku-4-5-20251001`: unchanged from this PR.
- Gemini `gemini-3.5-flash-lite`: no `temperature`, `thinkingLevel: "minimal"`. The schema moves to the JSON-Schema
  dialect (type arrays with `"null"`; no `nullable`, `format: "enum"` or `propertyOrdering`). The schema member is
  probably `responseJsonSchema`.

So the OpenAI and Gemini goldens and allowed lists in this PR are known to be stale. They must be regenerated in this
PR or a follow-up before the WI-M2-16 golden review and the AC-M2-14 freeze (PO ruling 7). That is not a blocker for
this merge, because nothing ships from these goldens before then. The privacy properties reviewed here (content, key
placement, canonical body, roles) do not depend on the model. My original notes on the built shapes follow, for the
record. As far as I know, these shapes are accepted: OpenAI
Chat Completions with `response_format.json_schema` `strict: true` (all members required, `additionalProperties:
false`, `anyOf` with `null`, nesting within the limit), `store`, `max_completion_tokens` and `stream`; Anthropic
Messages with `system`, one forced tool (`tool_choice {type: tool}`), `input_schema` and `anthropic-version
2023-06-01`; Gemini `v1beta …:streamGenerateContent?alt=sse` with `systemInstruction`, `responseSchema` (OpenAPI
subset: upper-case types, `nullable`, `format: "enum"`, `propertyOrdering`; no `additionalProperties`, which is
correct for `responseSchema`) and `thinkingConfig.thinkingBudget: 0`. Things the live check in WI-M2-M6 should confirm
(R-6):
- Model currency and Gemini condition 2: answered by L1/L1b and PO rulings 1, 6 and 7 (above).
- Whether Anthropic streams a forced tool's `input_json_delta` finely enough for AC-M2-27 TTFI without a beta header.
  If a header is needed, it is a new request header and goes to the PO under ADR-0005 D3/D6.
- Whether any request-level retention option now exists for Anthropic or Gemini (AC-M2-20 "Opt-outs": any option
  found is added under a PO decision).

## Test runs (this review, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, worktree at `f1f6baf` mounted read-only, scratch `/tmp/rev28-scratch`)
| Package | Summary line | Warnings |
|---|---|---|
| Packages/TendIngestion | `✔ Test run with 437 tests in 51 suites passed after 98.988 seconds.` | 0 |
| Packages/TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 4.286 seconds.` | 0 |
| Packages/TendCore | `✔ Test run with 141 tests in 18 suites passed after 152.462 seconds.` | 0 |
| Tools/TendTools | `✔ Test run with 8 tests in 1 suite passed after 0.138 seconds.` | 0 |

These counts match the dev notes. From the log: golden heads are 128/142/182 bytes. Bodies: G1 3835/3848/3976, G2
4069/4082/4210, G3 4348/4361/4489 (OpenAI/Anthropic/Gemini). Titles sent: 0, 4, 10.

## Probes and mutants (scratch copy `/tmp/rev28-mut/w` from `git archive HEAD`; restored after each run; its `Packages/` was diffed equal to HEAD afterwards; the worktree was never edited)
| # | Probe / mutant | Result |
|---|---|---|
| P1 | Independent canonical check of 9 golden bodies + 3 allowed lists (Python: duplicate-key and UTF-8 key-order hook, float refusal, re-serialise) | 12/12 byte-identical; no `\/`, no `\u`, no trailing newline |
| P2 | Independent decode of each golden user-content string; leaf paths of all goldens = committed list per provider | equal for all 3 providers (47/47/58 body leaf paths) |
| P3 | Hand derivation of the G2 and G3 shortlists from brief steps 1–6 | equal to the golden bytes |
| P4 | Body contents walk (non-schema leaf paths per provider, listed in Summary) | only fixed protocol members + the user slot + instructions + schema |
| M-A | Rule 4: `path == providerTableFile` → `path.hasSuffix("CloudProviderTable.swift")` (TendSourceScan, all tests) | **survived** (63/63 pass) → F1 |
| M-B | Selector trims the capture | killed (131 issues) |
| M-C | Selector drops blank room names (contradicts D11 / Q19) | **survived** (36/36 Payload tests pass) → F2 |

The developer's 28 mutants (S1–D1) cover the builder, schema, opt-outs, key, formatting, key-path function, lists and
the tool. I re-read the kill list against the tests and did not repeat them.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R28-F1 | Minor | `Packages/TendSourceScan/Sources/TendSourceScan/IngestionSourceRules.swift:359`; `Tests/TendSourceScanTests/IngestionSourceRulesTests.swift` (Rule 4 plants), `BriefPinTests.swift` `hostPlants` | Rule 4 matches the provider table by exact path, as it should. No test pins that, though: M-A (`hasSuffix("CloudProviderTable.swift")`) passes all 63 tests. With that mutant, a second file named `CloudProviderTable.swift` anywhere in TendIngestion could hold bare hosts. The rule says "one named file". | Add two Rule 4 plants: a bare host in `Packages/TendIngestion/Sources/TendIngestion/Duplicates/CloudProviderTable.swift` (same file name, other folder) → "bare host outside the provider table"; and one in `Packages/TendAI/Sources/TendAI/Cloud/CloudProviderTable.swift` → "bare host outside TendIngestion". M-A must then fail. | Open (ticket; WI-M2-11 or the next scanner PR) |
| R28-F2 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Payload/CloudPayloadInput.swift:44-51`; `Stream/DraftPipeline.swift:37-38` | The cloud input is derived twice. `CloudContextSelector.input` is what the AC names and what the 3,600-capture property test checks, but no production code calls it. Production goes `ModelRouter` → `DraftPipeline` (`household.rooms.map(\.name)` + `rules.sentShortlistTitles`) → `CloudPayloadInput(request)`. The two match by construction today, and `routerWiring` checks them on the 3 goldens. A later change to only one of them would not be caught: M-C (the selector drops blank room names) survives, and D11 ("blank room names are sent as written") has no test. WI-M2-11's ≥ 500-household proof must cover the path that really sends. | Do one of these: (a) make production use the selector (for example, `DraftPipeline`/`ModelRouter` builds the cloud `IngestionRequest` from `CloudContextSelector.input`), or (b) add a seeded property test, at least the existing 3 × 200 × 6, that compares `CloudPayloadInput(pipeline.request)` from `ModelRouter.events(… titleSharing:)` with `CloudContextSelector.input` for both Q12 answers, with households that include blank, whitespace-only and duplicate room names. Either way, add a D11 test (`""` and `"  "` room names are sent in order). Ticket for WI-M2-11: drive the AC-M2-20 (a)/(b) proof through the router path, or through the selector once (a) is done. | Open (ticket, WI-M2-11) |
| R28-F3 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Payload/CloudPayloadBuilder.swift:50` | The "at most 10 titles" limit (Q12, ADR-0005 D3, AC-M2-20 "n ≤ 10") is enforced only upstream, in `DuplicateShortlist`. `CloudPayloadInput.init` is public, so a future adapter (TendAI, WI-M2-M6) could pass 11+ titles and the builder would send them all with indices 11, 12, … The builder is the minimisation boundary named in ADR-0005 D3. | Enforce the cap in the builder: either throw a typed error for > 10 titles, or make the input type's initialiser refuse them. Add a test where 11 titles are refused or never reach the body. | Open (ticket) |
| R28-F4 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Payload/CloudRequestKeyPaths.swift:63`; `Fixtures/M2/payload/allowed-key-paths-*.json` `headers` | This agrees with the developer's ticket (open question 5). On Darwin, `URLSession` adds `User-Agent` (app name and version, CFNetwork and Darwin build), `Accept-Language` (the user's preferred languages), `Accept`, `Accept-Encoding` and `Connection` unless they are set. The lists name only `Content-Length` and `Host` as derived. ADR-0005 D3 forbids device identifiers and location. The OS build and the language list are close to that line, and AC-M2-20 (b) says "the header names equal the provider's fixed list". | WI-M2-M4: set a fixed `User-Agent` (for example `Tend/1`), send no `Accept-Language` (or a fixed value), prove the full header set on the wire in the `URLProtocol` test, and update the lists' `headers` (fixed or derived) under the R-15 regeneration. **Update:** PO `po-m2-wi10.md` ruling 4 now requires exactly `User-Agent: Tend` and `Accept-Language: en-US`, set explicitly, with `Accept`, `Accept-Encoding` and `Connection` listed as transport-set. That ruling replaces my example values. | Open (ticket WI-M2-M4, per PO ruling 4) |
| R28-F5 | Minor | `CloudPayloadBuilder.swift:33-34` (auth header from `APIKey` as stored) | A key pasted with a trailing newline or space (common when copying) goes into the header value as it is. Depending on the platform, this can fail every request with an invalid-key-looking error, or, with CR/LF, inject a header. AC-M2-21 says "Save does not reject short keys" but says nothing about whitespace or control characters. | WI-M2-M5/M4: trim surrounding whitespace at save, refuse control characters, or both. The transport refuses a header value with CR/LF before sending. Add a test in each place. The PO decides whether the user-facing behaviour is "trim" or "refuse" (copy in M3). | Open (ticket) |
| R28-F6 | Minor | `Fixtures/M2/payload/allowed-key-paths-*.json` (`[]` paths only); brief AC-M2-26 | Paths with `[]` do not count array elements. A body with an extra element of the same shape, for example a second user message `messages[2].content[0].text`, has exactly the same leaf-path set. AC-M2-20 (b) covers this, because every `fixed` path is compared at concrete indices against the golden, which is how the README describes it. `ds2-gated` (AC-M2-26) compares path sets only, though, so on device an extra element would pass. | WI-M2-11: the structural check must compare concrete-index paths (or element counts) with the golden, and a test must show that an added message or part is caught. Tester and PO: decide whether AC-M2-28's recorded data (byte count + key paths) is enough for AC-M2-26, or whether per-array element counts (value-free) should also be recorded. That would be a brief question; this PR changes nothing for it. | Open (ticket WI-M2-11; Tester/PO question) |
| R28-F7 | Minor | `Payload/CloudPayloadBuilder.swift:57-123`; `Payload/CloudOutputSchema.swift:183-190, 229-288`; `Payload/CloudProviderTable.swift:76-104, 147-148`; tests `PayloadBuilderTests.swift:105-141, 217-247`, `Tools/TendTools/Tests/TendToolsTests/TendToolsTests.swift` (`payloadDump` targets) | **A model swap is harder than it needs to be** (coordinator's question; PO ruling 7 swaps two of the three models). (1) Model-dependent request members are hard-coded per **provider**, not per **model**, in the builder's `switch model.provider`: `temperature: 0`, `thinkingConfig.thinkingBudget: 0`, and the lack of any reasoning or usage member. Ruling 7 needs per-model differences, and its named fallbacks (`claude-haiku-5-5`: no temperature, an effort level; `gemini-3.8-flash`: `thinkingLevel: "low"`) are same-provider models with **different** members. With this design, switching to a fallback is a builder code change, not a table change. (2) The schema dialect is chosen per provider (`CloudSchemaDialect(provider)`), and the Gemini dialect hard-codes OpenAPI-only keywords (`nullable`, `format: "enum"`, `propertyOrdering`) plus the member name `responseSchema`. Ruling 7 moves Gemini to the JSON-Schema dialect. (3) `CloudModel` case names encode the model (`gpt41Mini`, `gemini25Flash`), and the provider-table header comment states model facts ("`gpt-4.1-mini` is not a reasoning model") that become false after a swap. (4) Tests pin model IDs and sampling in several places: `providerTable`, `optOutsAndSampling` (temperature 0 for all three), the TendTools target strings, and `curated(for:) == [default]`. The last one forbids listing a fallback model at all. The regeneration path itself is good: `TEND_PAYLOAD_GOLDEN_OUT`, lists derived from G2, and README steps. | In the ruling-7 regeneration PR, make the model the unit of configuration. Give each `CloudModel` a fixed **request profile** in `CloudProviderTable.swift`: sampling (`temperature: 0` or omitted), reasoning member and value (`reasoning_effort`, `thinkingLevel`, `thinkingBudget` or none), usage member (`stream_options.include_usage` or none), and schema dialect and member name. The builder then reads the profile instead of branching on provider for these members. Use neutral case names, or accept a rename per swap, and remove model claims from comments, or move them into the profile with the L1 citation. Make the tests profile-driven (expected members derived from a hand-written per-model table in the test, not from production). Relax `curated(for:)` to "the default is first, and every curated model has a profile", so fallbacks can be listed without being selectable until a PO ruling. Each new fixed member is checked against PO ruling 3's six-part test and N-3, and the ruling-7 mutants are added. | Open (ticket; the ruling-7 regeneration PR, before WI-M2-16) |
| R28-N1 | Nit | `Packages/TendSourceScan/Tests/TendSourceScanTests/IngestionSourceRulesTests.swift` `rule1Positive` | The Rule 1 positive now runs only at the provider-table path, so a general TendIngestion file no longer has a Rule 1 positive. Rule 1 does not depend on the path inside TendIngestion, so nothing is lost today. | Optional: keep the old positive at `PlanPaths.ingestionFile` without the bare-host line, and the table variant as it is. | — |
| R28-N2 | Nit | `Payload/CloudOutputSchema.swift:159-160, 172` (instructions) | "room: a name from "rooms" when the chore belongs there" (an inferred link) and "Never invent a room … the person did not mention" pull in slightly different directions. This is prompt quality, not law. The dev-set eval (AC-M2-26 room accuracy) is the judge. | Optional: watch room accuracy in the DS-2 dev-set run. If it is low, reword (for example "never propose a new room the person did not name") under the freeze rules. | — |
| R28-N3 | Nit | `docs/milestones/M2/plan.md:61` | The Developer added the "Named files" row. The R1-F6 ticket asked for it, but the plan belongs to the Work Planner. | Planner: confirm the row in the next plan edit. | — |

**On the developer's open questions (updated with PO `po-m2-wi10.md`).**
1. (R-6, Q18 conditions 1–2.) Closed by PO rulings 1, 6 and 7 after the L1/L1b live check. The final list is
   `gpt-6-luna`, `claude-haiku-4-5-20251001` and `gemini-3.5-flash-lite`, with revised conditions 2, 4 and 5. The
   regeneration is a ticket before WI-M2-16 and the freeze, and does not block this merge (coordinator direction). See
   F7 for what makes the swap costly.
2. (title last, D5.) PO ruling 2: no product action, Tester watch in the DS-2 dev-set run. I agree.
3. (D8, fixed protocol members.) PO ruling 3: these are allowed fixed values and not new request fields, under a
   six-part test for any future fixed member. Confirmed. I checked every non-schema member in the 9 goldens against the
   six parts: all are constant, carry no person or device data, are protocol, schema or instruction members, grant no
   extra reach, are `fixed` in the lists, and meet N-3. Ruling 3's ticket (a cap stop counts as truncated) goes to
   WI-M2-13/M6.
4. (Tester, roles and layout, D2.) This stays with the Tester (WI-M2-16), per the PO. I can review it as written, with
   one addition (F6).
5. (Darwin default headers.) PO ruling 4: fixed `User-Agent: Tend` and `Accept-Language: en-US`. See F4.

No Blocker or Major is open. F1–F7 are Minor tickets with named owners and do not block the merge.

## Checklist
- [x] Correctness vs ACs (this PR's part of AC-M2-20: input type + `Mirror`, selector, builder, provider table, key placement, opt-outs, sampling, canonical body, 3 × 3 goldens, allowed lists with roles; AC-M2-09 Rule 4 narrowing)
- [x] Tests meaningful: independent oracles (`JSONSerialization`, WI-M2-07 shortlist oracle, hand-derived G2/G3), my Python canonical re-check, 28 developer mutants killed. Two gaps: M-A and M-C survive (F1, F2, Minor)
- [x] Swift 6 concurrency safe (pure `Sendable` values; no `@unchecked`, no `nonisolated(unsafe)`)
- [x] No force unwraps / `try!` in product code paths
- [x] Privacy (P-1…P-4): see Law check; F3–F5 are hardening tickets for later items; F7 (model-swap design) is maintainability, not privacy
- [x] UX-2/UX-3 enforced in engine: n.a. for UX-2; the instructions hold no banned token (`instructionsBlankMeaning`, AC-M2-12 scan 0)
- [x] Accessibility (UI): n.a., no UI
- [x] Performance: pure functions, bodies about 4 KB, no main-thread or hot-loop concern
- [x] No new dependency without ADR (Foundation, TendCore, Synchronization in tests only)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | The instructions and tool description hold no banned token (test plus AC-M2-12 scan 0 violations). They ask for the person's words and never ask the model to invent. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Routing is unchanged. On-device requests carry no titles (`pipelineRequest`), and the cloud route is only reached through ADR-0005 D1 (unchanged `ModelRouter`). |
| P-2 No data leaves device (except user iCloud) | pass | Pure functions with no networking (AC-M2-09 Rule 1: 46 files, 0 violations). Bare hosts appear only in the provider table (Rule 4 narrowed; F1 is a test gap). No SDK or dependency. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass (concerns ticketed) | The request holds only the fixed instructions and schema, the one capture, the room names as written, ≤ 10 shortlist titles with indices, and fixed protocol members. No ID, date, time zone, state, location or device field (goldens, P4). The key is only in the provider's auth header and never in `key=`. OpenAI `store: false`. The key and body never format. Concerns: builder-level cap (F3), Darwin default headers (F4), key whitespace (F5), `[]`-only path sets on device (F6). The model list is replaced by PO ruling 7 after L1/L1b, and the OpenAI and Gemini goldens are to be regenerated with the new fixed members, each checked against ruling 3's test (F7). |
| P-4 Media not persisted without consent | pass | Text only, in memory. The input type cannot hold media (`Mirror` test). Nothing is written except by the opt-in `TEND_PAYLOAD_GOLDEN_OUT` test hook, outside the repository. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-23 | Orchestrator | Reviewer | accepted | PR #28 at `f1f6baf`, base `6fd1bf4`; fresh context; worktree `/home/user/wt-rev28`. |
| 2026-11-23 | Reviewer | Orchestrator → Merge Gatekeeper; tickets to Developer (WI-M2-11, M4, M5), Tester, PO, Planner | accepted (APPROVE, round 1) | 4 packages green, 0 warnings (437/63/141/8). No Blocker/Major. Minor tickets: F1 Rule 4 exact-path plant; F2 one derivation path or equivalence property + D11 test, WI-M2-11 proof through the production path; F3 builder-level ≤ 10 cap; F4 Darwin default headers (WI-M2-M4, PO); F5 key whitespace/control characters (WI-M2-M5/M4); F6 concrete-index structural check (WI-M2-11) and the `ds2-gated` element-count question (Tester/PO). PO: R-6 live check of models, shapes and opt-outs and the Gemini stable-ID question before the WI-M2-16 freeze; confirm D8. Planner: confirm the plan "Named files" row. |
| 2026-11-24 | Orchestrator | Reviewer | accepted | Mid-review: PO rulings `po-m2-wi10.md` (1–4, 6, 7) and live check `l1-model-check-2026-11-23.md`. Direction: do not block on model IDs; note what makes a model swap hard. |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper; Developer (ruling-7 regeneration PR), PO, Tester, Planner | accepted (APPROVE, round 1, updated) | Verdict unchanged. Added F7 (model-dependent members hard-coded per provider; Gemini dialect fixed; tests pin models; `curated == [default]` forbids fallbacks). The OpenAI and Gemini goldens and lists are known stale under ruling 7 and must be regenerated before WI-M2-16 and the freeze. F4 is aligned with PO ruling 4. D8 is confirmed under ruling 3. Open questions 1, 2, 3 and 5 are closed by the PO; 4 stays with the Tester. |
