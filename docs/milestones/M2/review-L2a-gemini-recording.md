# M2 Code Review — PR #37 (`m2/gemini-recording`): the real Gemini L2a recording through the draft pipeline

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Head reviewed:** `f3cc00d9e35bdf802ab9031c36d90af90fa35f50`  ·  **Base:** `main` `52cba62`
- **Scope:** AC-M2-24 (Fixtures T-19, cloud output), AC-M2-05, AC-M2-04 (draft fields), GR-4 (L2a), WI-M2-16 DoR,
  plan.md "Real provider recordings", PO WI-M2-13 ruling K2, owner decision "L2a outcome" (2026-11-25 01:39 UTC).
- **Milestone lock:** `STATUS.md` shows M1 ACCEPTED, M2 IN-BUILD. This is M2 work on an `m2/` branch: allowed.

## Summary
The PR commits the owner's real Gemini L2a response body as
`Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse`, adds 6 Linux tests in
`Packages/TendIngestion/Tests/TendIngestionTests/ProviderStreamRecordingTests.swift`, and updates the provider-stream
README and `dev-notes.md`. No production code, no existing test and no existing fixture is changed (the diff
`52cba62..f3cc00d` touches 4 files: 2 new, README and dev-notes only).

What I verified myself:

1. **Byte-for-byte match with the owner's original.** `cmp` of the worktree file and of the committed blob
   (`git show HEAD:…`) against `/mnt/project-files/owner/l2a-results-2026-11-25/gemini.sse`: identical. SHA-256
   `1f5784a01926fae19bb3ca4871b5a865d6756e7d8b8fac6afa0ab4e89109102f` for all three, 6 551 bytes, 28 CR bytes
   (14 events x CRLF CRLF). No `.gitattributes` exists, so git applies no line-ending conversion.
2. **No key, request, header or household data (P-2, P-3, P-4, AC-M2-21 "the key never appears in files", plan.md
   "The Reviewer checks that no recorded file contains a request header or the key").** I read all 14 lines. Every
   non-empty line is `data: {GenerateContentResponse}`. There is no key, no `x-goog-api-key`, no `AIza`, no header
   (the owner's status/headers file `gemini.status` was correctly left out), no `contents` / `systemInstruction` /
   `generationConfig`. The only natural-language content is the model's reply to the brief's fixed Outcome sentence
   (AC, dishwasher pods, balcony), sent with an empty household. The two opaque values, `responseId`
   (`UjsGa7voPIqkqfkPk6OL6QI`) and the trailing `thoughtSignature`, are provider-generated tokens for this one
   response; they are not credentials and derive only from the fixed golden request (see N3).
3. **Request-profile claims.** Golden body `g1-outcome-empty-gemini.body.json` SHA-256 is `7be08e83…8207827` at
   this head, as dev-notes says. The head file targets `gemini-3.5-flash-lite:streamGenerateContent?alt=sse`. The owner's
   status file shows `HTTP/2 200`, `content-type: text/event-stream`. Body: `modelVersion` `gemini-3.5-flash-lite` in
   all 14 events, no `thoughtsTokenCount`, final usage 549 + 297 = 846, `finishReason` `STOP` only in the last event,
   whose single part is `{"text":"","thoughtSignature":"…"}`. All as stated in README and dev-notes.
4. **K2 compliance.** The recording ends with Gemini's normal end (`STOP`), so `completed` is the correct outcome under
   PO WI-M2-13 K2. The test also proves the converse on real bytes: the body without its last event gives
   `cutShort(.noFinish)` with all 3 items read (truncated, never `completed`).
5. **Build and full suite (Linux, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, my scratch path
   `/tmp/rev37-ing`, worktree `/home/user/wt-rev37`):** exit 0, `Test run with 570 tests in 67 suites passed`
   (564 before + 6 new), 0 warnings in the build output. All 6 recording tests passed.
6. **Mutation check (scratch copy outside the worktree; every `.swift` touched after each change and each restore;
   `--filter ProviderStreamRecordingTests`):**

   | Mutant | Where | Result |
   |---|---|---|
   | M1: skip the finish reason of a candidate whose chunk adds no text (`if step.output.isEmpty { continue }` before `finishReason`), i.e. mishandle the real trailing empty-text part | `CloudOutput/GeminiStreamDialect.swift:48` | **killed**: 4 of 6 tests fail (trailing part, outcome, split chunks; 46 issues) |
   | M2: capitalise proposed room names (`.capitalized`) | `Rooms/RoomLinker.swift:34` | **killed**: drafts test fails (`.proposed("balcony")`) |
   | M3: drop the model's `isDeepClean` (`var isDeepClean = false`) | `Draft/DraftMapper.swift:155` | **killed**: drafts test fails |
   | M4 (fixture): prepend a `content-type: text/event-stream` header line to the recording | `recorded-outcome-sample.sse` | **killed**: response-only test and split-chunk test fail |
   | Restored copy | — | 6 of 6 pass; `diff -r` of `Packages/` and `cmp` of the fixture against the worktree: identical |

   The tests assert exact values (titles, rooms, kinds, efforts, flags, source phrases, outcome, token counts, event
   count, typed joined output) and use independent Foundation parsing as their oracle where they inspect the body. The
   random cut sets are seeded (`0x6E3A11A2A ^ byteCount`, printed in every message).

The PR meets the brief for a real recording (AC-M2-24 T-19) for Gemini. OpenAI and Anthropic recordings remain open, as
the PR says honestly. Findings below are Minor or Nit only.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| N1 | Minor | `docs/milestones/M2/dev-notes.md:5202`, `:5204` (also `:5146-5148`) | The "Known limitations" table says OpenAI/Anthropic L2a is "blocking freeze (AC-M2-14)" and leaves "Whether L2a for Gemini alone is enough to close GR-4" as an open question. The owner already decided this (`owner-decisions.md`, "L2a outcome", 2026-11-25 01:39 UTC): "Gemini now, others later": freeze the eval now; OpenAI and Anthropic L2a must pass **before their DS-2 runs count**, not before the freeze. As written, the note states a blocker that the owner has removed and could hold up the AC-M2-14 freeze. | Reword the row to "blocks the OpenAI/Anthropic DS-2 runs (AC-M2-26, AC-M2-27), not the AC-M2-14 freeze (owner decision 'L2a outcome', 2026-11-25)" and close the GR-4 question row citing the same decision (GR-4 closure itself stays with the Tester/PO). Ticket; does not block. | OPEN |
| N2 | Minor | `ProviderStreamRecordingTests.swift:142`, `:153`, `:174`, `:197` (via `ProviderPipeline.events` default `pipeline: ProviderFixtures.pipeline()`, i.e. rooms `MappingFixtures.rooms` = Kitchen, Bathroom) | The recording was made for an **empty** household, but the pipeline under test links rooms against Kitchen and Bathroom. The results are the same today (`""` -> `.none`, `balcony` -> `.proposed`), so nothing is wrong, but the test does not replay the household the request was made with, and a later change to the shared fixture rooms (e.g. adding "Balcony") would change this test's meaning silently. | Pass an explicit empty-household pipeline (`StreamFixtures`/`DraftPipeline` with `rooms: []`) for the recording, or state in the file header why the synthetic rooms are used. Ticket. | OPEN |
| N3 | Nit | `ProviderStreamRecordingTests.swift:66-67` | The banned-string scan is case-sensitive (`"Content-Type"`), while real HTTP/2 headers are lower case (`content-type`, as in the owner's `gemini.status`). The every-line-is-`data: {` check (`:72`) already catches any header line (mutant M4 was killed by it), so this is belt and braces only. | Optional: compare case-insensitively (`text.lowercased()` against lower-case tokens). | OPEN |
| N4 | Nit | `Fixtures/M2/provider-streams/README.md:6` | "The real recordings (section "Recorded") follow the same rule." The sentence before it is about who reads the fixtures, so "the same rule" is ambiguous; the rule meant is "response bodies only" in the next paragraph. | Optional: "The real recordings (section "Recorded") also hold response bodies only." | OPEN |
| N5 | Nit | `dev-notes.md` L2a section, "What changed" | The `responseId` and `thoughtSignature` values are opaque provider tokens committed verbatim. They are not keys and derive from the fixed golden request only, so P-2/P-4 are not affected; a one-line note saying so would pre-empt the question at the Tester/PO privacy check. | Optional: add the note. | OPEN |

No Blocker. No Major.

## Checklist
- [x] Correctness vs ACs (AC-M2-24 recorded fixture for Gemini, AC-M2-05 `completed` per K2, AC-M2-04 fields)
- [x] Tests meaningful (would fail if code broke): 4 mutants, all killed; exact values; independent oracle
- [x] Swift 6 concurrency safe (test-only code; `async` tests over the existing `ChunkedProviderModel`; no
  `@unchecked Sendable`, no `nonisolated(unsafe)`; builds with warnings as errors)
- [x] No force unwraps / try! in product code paths (no product code changed; tests use `#require`)
- [x] Privacy (P-1…P-4): recording holds response body only; verified by reading, by test, and by mutant M4
- [x] UX-2/UX-3 enforced in engine: n.a. (no engine change); recorded titles contain no banned word
- [x] Accessibility (UI): n.a.
- [x] Performance: n.a. (tests; split-chunk test runs in ~15 s on Linux, in line with the synthetic suite)
- [x] No new dependency without ADR (none added)
- [x] No existing test or fixture weakened (diff touches only the 2 new files, README and dev-notes)

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Tests, fixture and docs only; no entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. The recording yields 3 drafts, which are capture drafts, not a Now surface. |
| UX-3 Zero-Guilt | pass | No UI copy added. The recorded titles and source phrases contain none of the banned words. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No routing change. The recording is the reply of the opt-in cloud path (P-3), made by the owner. |
| P-2 No data leaves device (except user iCloud / P-3) | pass | Tests send nothing. The owner's live call sent only the golden body (fixed Outcome sentence, empty household) directly to the chosen provider. The committed file holds no request, header, key or household data (verified byte for byte against the owner's original). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The key is in no committed file (AC-M2-21); the header file was not committed. The recording confirms that Google accepts the ADR-0005 golden members (`responseJsonSchema`, `thinkingLevel: "minimal"`, `null` in `enum`). |
| P-4 Media not persisted without consent | n.a. | Text only; no camera, audio or document data. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Reviewer | accepted | Review PR #37 at `f3cc00d`: byte comparison with the owner's original, privacy of the recording, test strength (mutants), no weakening, README, Linux run. |
| 2026-11-25 | Reviewer | Orchestrator (for Developer, Acceptance Tester) | sent | APPROVE. 0 Blocker, 0 Major, 2 Minor (N1 dev-notes vs owner "L2a outcome" decision; N2 empty-household pipeline), 3 Nit. Minors to be ticketed; N1 should be fixed before the Tester uses dev-notes for the AC-M2-14 freeze. Not committed, not pushed, no GitHub comment. |
