# M2 Code Review — WI-M2-16: eval freeze, `MANIFEST.sha256` (PR #36, `m2/eval-freeze`, head `b600eca`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2 (round 1 CHANGES REQUIRED at `b600eca`; round 2 APPROVE at `60c9293`, see "Round 2" at the end)
- **Requirements:** AC-M2-14 ("committed, with a SHA-256 manifest, and frozen"), GR-4 (L2a), FR-A1, P-3; feeds
  AC-M2-11, 15, 16, 17, 25, 26, 27.
- **Binding inputs checked:** `CLAUDE.md`; dev-notes "WI-M2-16 (Developer part 2)", "To freeze" steps;
  `po-m2-wi16.md` ruling 1 (conditions a–f), ruling 10 (GR-4), F2 (L2a revert path), EC-Q8 (re-approved `golden.json`
  `0e819a89…`); `owner-decisions.md` "L2a outcome" (2026-11-25 01:39 UTC); owner evidence
  `/mnt/project-files/owner/l2a-results-2026-11-25/` (6 files) and the L2a procedure `l2a-real-call-check.md`.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. WI-M2-16 is M2 work. Allowed. No protected path
  touched: the diff against `52cba62` has only `Fixtures/M2/eval/MANIFEST.sha256` (new),
  `Packages/TendIngestion/Tests/TendIngestionTests/EvalFreezeTests.swift`, `docs/milestones/M2/acceptance.md`,
  `docs/milestones/M2/eval-composition.md`.
- **Not claimed here:** a merge APPROVE would not accept AC-M2-14 or any device AC. The overall AC-M2-14 verdict is
  taken at the M2 merge commit (`acceptance.md` says so).

## Summary

**1. Manifest bytes (AC-M2-14).** In the worktree at `b600eca`, I ran the documented command (`EvalManifest.command`,
`EvalCompositionSupport.swift:616`) without the redirection:
`(cd Fixtures/M2/eval && LC_ALL=C sha256sum golden.json household.json inputs.json results-v1.schema.json) | cmp - Fixtures/M2/eval/MANIFEST.sha256`
gave **IDENTICAL**. `sha256sum -c MANIFEST.sha256` gave 4 × `OK`. The three Tester files match the approved hashes
byte for byte: `golden.json` `0e819a89fcb65adb0a764d296f1d0dc8f30275cfe074495a4fe9c793a0f4b771` (EC-Q8 re-approval),
`household.json` `089a22bd…17f66`, `inputs.json` `b32e45af…ebcec` (ruling 1). These are also the values in
`EvalFreeze.approvedSHA256`. `results-v1.schema.json` `ffc01f37…` has no PO pin (it is a Developer file from WI-M2-15).
It equals the `sha256sum` of the file at base `52cba62`, so it is unchanged.

**2. No fixture byte changed.** `git diff --name-status 52cba62..HEAD -- Fixtures` lists only `A MANIFEST.sha256`. No
`Sources/`, `Package.swift` or `Tools/` file changed. No dependency.

**3. Test code: only the flag moved.** The only code change is `EvalFreeze.declaredFrozen` `false` → `true`
(`EvalFreezeTests.swift:26`), plus its doc comment (lines 23–25). No assertion, argument list, `.enabled(if:)` trait
or helper changed. No test is weakened. The freeze-state test (`freezeStateAgrees`, line 85) checks both directions
(manifest exists == declared frozen; status contains "Not frozen" == !declared frozen), so it still binds after the
flip. Its display name ("NOT frozen yet — no MANIFEST.sha256 …") and the file header comment (lines 5–6, 13–15) now
describe the old state. See m1.

**4. Build and tests (my own run, Linux, Docker `swift:6.2-noble`, `-warnings-as-errors`, scratch `/tmp/rev36-ing`).**
`docker run --rm -v /home/user/wt-rev36:/w -w /w swift:6.2-noble swift test --scratch-path /tmp/rev36-ing --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors`
→ exit 0, `Test run with 564 tests in 66 suites passed after 99.844 seconds`, 0 `warning:` lines, 0 `✘`, **0 `➜`
skips**. The test that was skipped by design in PR #34 now runs and passes:
`✔ Test "AC-M2-14: MANIFEST.sha256 verifies against every file in Fixtures/M2/eval" passed`. Also passed:
`freezeStateAgrees`, the documented-command test (`/usr/bin/sha256sum` present), the 3 PO-pin cases, and all
`EvalCompositionTests` cases, which is ruling 1 condition (e) at the freeze commit.

**5. Mutants (scratch copy from `git archive b600eca`, same Docker image, `--filter EvalFreezeTests`).** All killed:

| # | Mutant | Result | Killed by |
|---|---|---|---|
| M0 | none (baseline) | exit 0 | — |
| M1 | one byte in `inputs.json` (offset 3823, `e` → `E`) | exit 1 | "MANIFEST.sha256 verifies …" (line 161) **and** "PO ruling 1 … PO-approved SHA-256" |
| M2 | one hash in the manifest (`results-v1.schema.json` line, `ffc01f37` → `ffc01f38`) | exit 1 | "MANIFEST.sha256 verifies …" (only guard for the unpinned schema file) |
| M3 | `declaredFrozen = false` again | exit 1 | `freezeStateAgrees` |
| M4 | manifest deleted, flag `true` | exit 1 | `freezeStateAgrees` |
| M5 | Status bullet says "Not frozen" again | exit 1 | `freezeStateAgrees` |

**6. GR-4 evidence (owner L2a, 2026-11-25).** I re-read the owner's files. `gemini.status` is `HTTP/2 200`,
`content-type: text/event-stream`. I joined the `text` parts of `gemini.sse` into one JSON object (3 items) and
validated it with `jsonschema` (Draft 2020-12) against the `generationConfig.responseJsonSchema` of
`Fixtures/M2/payload/golden/g1-outcome-empty-gemini.body.json` at `52cba62`: **SCHEMA VALID**. `finishReason` is
`STOP`, `modelVersion` is `gemini-3.5-flash-lite`, and `usageMetadata` has no `thoughtsTokenCount`. There is an empty
part with a `thoughtSignature`, which is not a thinking-token count. `null` appears in `daypart`, `repeatUnit`,
`season` and `weekday`. So Gemini accepts `responseJsonSchema`, `thinkingLevel: "minimal"` and `null` in `enum`, as the
GR-4 row says. OpenAI `HTTP/2 429` `insufficient_quota` and Anthropic `HTTP/2 400` "credit balance is too low" are
billing errors, so their requests are not verified, as the docs say. The golden bodies last changed at `12bd68c`
(2026-11-24 17:31 UTC). PR #32 reached `main` before 18:05 UTC, and L2a ran at about 01:31–01:35 UTC on 2026-11-25 from
a fresh clone of `main`. So L2a ran on the committed bodies. Note: L2a sends only the `g1-outcome-empty` body for each
provider (procedure Steps 2–4). The docs say "the committed golden body" (singular), which is accurate.

**7. Docs.** `eval-composition.md` (Status, the condition row, GR-4 row, P-3 row, handoff log) and `acceptance.md`
(AC-M2-14 row, AC-M2-26 note, P-3 row, DS-2 P11, handoff log) match the owner's decision and the evidence. One gap
(M1 below): P11 covers less than the owner's decision does, and the script's default path runs into the gap.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| M1 | **Major** | `docs/milestones/M2/acceptance.md:305-309` (P11), `:24` (AC-M2-25 row), `:26` (AC-M2-26 row), `:341` (Part B provider), `:381-394` (record), `:409-415` (pass rules) | The owner's decision ("L2a outcome") says OpenAI and Anthropic L2a "must pass before **their DS-2 runs** count". P11 narrows this to "an OpenAI or Anthropic **Part C** run", which counts only for "**AC-M2-26 or AC-M2-27**". DS-2 Part B (AC-M2-25) is a cloud run too. By default it uses "the first one you run in Part C (default **OpenAI**)" (line 341). So the script's default path sends an OpenAI request whose L2a has not passed. Today that run fails on the 429. After the owner adds credit, the AC-M2-25 pass rule (S2, S3, S7) would count it with no L2a check. Part D (default OpenAI, information only) has the same gap. Also, P11 says L2a must be "recorded in this report", but no field in "What to record" holds it, and the AC-M2-25/26/27 pass rules do not cite P11. This is wrong behaviour in a real scenario of the gate script: it can produce evidence that, under the owner's decision, does not count. | (1) P11 covers every DS-2 cloud run: Parts B, C and D, and AC-M2-25, 26 and 27. (2) Part B uses a provider whose L2a is recorded PASS (Gemini today), not "default OpenAI". Or Part B waits until the first Part C provider's L2a passes. (3) Add a row to the DS-2 "What to record" table for each provider's L2a result (date, HTTP status, schema-valid yes/no, evidence file). (4) The AC-M2-25, AC-M2-26 and AC-M2-27 pass rules (and the AC-M2-25 Results row) cite P11. No AC text changes. | Open |
| m1 | Minor | `Packages/TendIngestion/Tests/TendIngestionTests/EvalFreezeTests.swift:83`, `:5-6`, `:13-15` | The display name still reads `"AC-M2-14 freeze state: NOT frozen yet — no MANIFEST.sha256, and the Tester's composition status says \"Not frozen\" …"`. Since the flip, the test asserts the opposite (manifest present, status without "Not frozen"). A passing run log now prints a claim that is false. Evidence logs cite display names, so this misleads readers of the evidence (CLAUDE.md §4 rule 2). The header comment ("this branch writes no manifest", "skipped … until then") is also out of date. The assertion is correct and symmetric. | Rename to a state-neutral name, for example `"AC-M2-14 freeze state agrees: MANIFEST.sha256 exists exactly when EvalFreeze.declaredFrozen, and the composition Status says \"Not frozen\" exactly when not"`. Update the header comment. Do not change the assertion. Changing only a display string and comments does not weaken a test, so it can go in this PR. | Open (ticket) |
| m2 | Minor | `docs/milestones/M2/acceptance.md:307`, `docs/milestones/M2/eval-composition.md` GR-4 row | The Gemini PASS rests on files outside the repo (`/mnt/project-files/owner/l2a-results-2026-11-25/`). P11 points the owner at `/mnt/project-files/owner/l2a-real-call-check.md`, a container path that the owner's Mac cannot open. The evidence and the procedure are not reproducible from the repo. | Commit the L2a procedure under `docs/milestones/M2/` (or `evidence/`) and refer to it there. Commit `gemini.status` and `gemini.sse` as evidence. Check the OpenAI/Anthropic files before committing them: `anthropic.status` holds `anthropic-organization-id` and `anthropic-workspace-id`, so redact them or leave that file out. | Open (ticket) |
| m3 | Minor | `docs/milestones/M2/eval-composition.md:6-15`; `docs/governance/DECISIONS.md` (not in this PR) | Ruling 1 condition (d) "L2a (GR-4)" is met only partly. The freeze relies on the owner's override, which is recorded only in `owner-decisions.md` outside the repo. The "To freeze" step says "after L2a and the PO's go". The handoff log shows Orchestrator → Tester, with no PO go recorded. The owner's decision is above the PO, so I do not block on this. But the decision trail must reach the repo. | Governance PR (human-merged): add a DECISIONS.md entry for "L2a outcome" (freeze with Gemini L2a only; OpenAI/Anthropic L2a as a DS-2 precondition) and a PO acknowledgment. | Open (ticket, Documenter/PO) |
| n1 | Nit | `docs/milestones/M2/eval-composition.md:3`; `docs/milestones/M2/dev-notes.md:5116` | The header **Date** still reads 2026-11-24, while the Status is now dated 2026-11-25. The dev-notes Part 2 ends "Still not frozen … `declaredFrozen = false`". That is a historical Developer note, but nothing points forward to the freeze. | Optional: bump the date. The Developer or Documenter adds a one-line "Frozen at PR #36" pointer. | Open |
| i1 | Info | `Fixtures/M2/eval/MANIFEST.sha256:4` | `results-v1.schema.json` is guarded only by the manifest (no PO pin). Mutant M2 shows the manifest test catches a change. This is enough. | None. | — |

## Checklist
- [x] Correctness vs ACs: AC-M2-14 manifest is correct and verified. The DS-2 precondition text has a gap (M1).
- [x] Tests meaningful (would fail if code broke): 5/5 mutants killed.
- [x] Swift 6 concurrency safe: no product code changed; `-warnings-as-errors` clean.
- [x] No force unwraps / try! in product code paths: no product code changed.
- [x] Privacy (P-1…P-4): no data path change. See the Law check.
- [x] UX-2/UX-3 enforced in engine: not applicable (no engine change).
- [x] Accessibility (UI): not applicable.
- [x] Performance: not applicable.
- [x] No new dependency without ADR: none added.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No fixture byte changed, so F3's banned-token rule still holds (composition tests passed). The new doc text holds no banned word in UI copy (P11 is owner-facing script text). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference path changed. |
| P-2 No data leaves device (except user iCloud) | pass | Invented fixtures only. The manifest holds hashes. The L2a request held only the fixed g1 sample with an empty household. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | concern (M1) | Gemini's acceptance of the exact golden body is proven. Under the owner's decision, an OpenAI/Anthropic DS-2 run is not valid evidence until its L2a passes. P11 does not yet cover Part B (AC-M2-25), whose default provider is OpenAI. |
| P-4 Media not persisted without consent | n.a. | No media. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Reviewer | accepted | Review PR #36 at `b600eca` (freeze, AC-M2-14, GR-4, P11). |
| 2026-11-25 | Reviewer | Orchestrator → Acceptance Tester | returned | CHANGES REQUIRED: M1 (P11 covers all DS-2 cloud runs incl. Part B / AC-M2-25; Part B provider; record field; pass rules cite P11). m1 rename can go in the same commit (Developer or Tester; display string only). m2, m3 ticketed (Tester / Documenter / PO). Manifest, fixtures, flag and tests verified: 564 passed, 0 skipped, 5/5 mutants killed. Only the Reviewer lifts M1. |

## Round 2 — head `60c9293` (Tester fix commit on top of `48ffc7e`, which is my round-1 file)

- **Owner:** Reviewer  ·  **Verdict:** **APPROVE**  ·  **Diff reviewed:** `b600eca..60c9293`. That covers
  `EvalFreezeTests.swift` (comments and one `@Test` display string), `acceptance.md`, `eval-composition.md`,
  `dev-notes.md` (a pointer), the new `l2a-real-call-check.md`, and this file. No file under `Fixtures/`, `Sources/` or
  `Package.swift` changed (`git diff --stat b600eca..HEAD -- Fixtures Packages/*/Sources` is empty). No protected path
  is touched. The milestone lock is unchanged: M1 `ACCEPTED`, M2 `IN-BUILD`.

### Build and tests (my run, Linux, Docker `swift:6.2-noble`, `-warnings-as-errors`, scratch `/tmp/rev36-ing2`)
Exit 0, `Test run with 564 tests in 66 suites passed after 132.720 seconds`, 0 `warning:`, 0 `✘`, 0 `➜` skips. Two
tests matter most here: `✔ Test "AC-M2-14: MANIFEST.sha256 verifies against every file in Fixtures/M2/eval" passed` and
`✔ Test "AC-M2-14 freeze state agrees: MANIFEST.sha256 exists exactly when EvalFreeze.declaredFrozen, and the composition
Status says "Not frozen" exactly when not" passed`. The assertions, fixtures and manifest have the same bytes as in
round 1, so the five round-1 mutants (M1–M5) still apply unchanged. I did not re-run them.

### Findings re-checked
| # | Round 1 | Verified in `60c9293` | Status |
|---|---|---|---|
| M1 | Major | (1) P11 (`acceptance.md` DS-2 preconditions) now names **Parts B, C and D** and **AC-M2-25, 26, 27**. A run whose provider's L2a row is not PASS "does not count for any DS-2 AC". This matches the owner's "L2a outcome" wording ("before their DS-2 runs count"). (2) Part B now uses "only one whose L2a row is PASS … today that is Gemini", and step 1 checks P11. Part C checks P11 per provider and runs Gemini first while the others are pending. Part D defaults to Gemini. (3) "What to record" has an L2a row per provider: Gemini PASS with date, `HTTP/2 200`, schema-valid, evidence file; OpenAI 429 and Anthropic 400 are "not verified (pending)". (4) The AC-M2-25/26/27 pass rules each start with "P11 holds …" and list "P11 L2a row(s)" under "Read from". The AC-M2-25 and AC-M2-27 Results rows cite P11. No AC text changed. | **CLOSED** |
| m1 | Minor | The display name is now state-neutral (quoted above) and describes the symmetric assertion. The header comment describes the frozen state. Only the `@Test` string and `//` comments changed. `freezeStateAgrees` has the same body, so no test is weakened. | **CLOSED** |
| m2 | Minor | `docs/milestones/M2/l2a-real-call-check.md` equals the owner's procedure: Steps 1–4 match byte for byte, Step 5 only changes the hand-over wording, and the file adds a provenance comment and a "Pass rule and record" section. The pass rule matches my round-1 check (200, event-stream, joined text valid against the g1 body's schema, normal finish). It treats billing errors as "not verified" and a 4xx refusal as "stop, PO decision". No `.status` file is committed, and the reason (Anthropic account IDs) is stated. The cited evidence `Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse` is **not in this PR**. It is on `origin/m2/gemini-recording` (`f3cc00d`, PR #37), and I confirmed it is **byte-identical** (`cmp`) to the owner's `gemini.sse`. It is not on `origin/main` (`52cba62`) yet. See r2-1. | **CLOSED** (residual r2-1) |
| m3 | Minor | Left open for the governance PR (DECISIONS.md "L2a outcome" entry and PO acknowledgment). The GR-4 row and the handoff logs say so. It does not block. | Open (ticket, Documenter/PO) |
| n1 | Nit | `eval-composition.md` header gives "2026-11-24, v6 2026-11-25". `acceptance.md` header moves to 2026-11-25. `dev-notes.md` has a forward pointer to the freeze. The historical note is kept. | **CLOSED** |

### New in round 2
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| r2-1 | Minor | `docs/milestones/M2/acceptance.md` P11 and L2a row; `docs/milestones/M2/l2a-real-call-check.md` "Results so far" | The Gemini L2a evidence path names a file that arrives with PR #37. If #36 merges first, the link points at nothing on `main` until #37 merges. The content is verified identical to the owner's stream, so the evidence exists. Only the order of merges matters. | Merge PR #37 before or right after #36. Or, if #37 is dropped, commit the stream in a follow-up. The Orchestrator or Merge Gatekeeper tracks this. | Open (ticket) |

### Law check (round 2)
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No fixture or UI copy changed. The banned-token composition rule still passes. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | n.a. | No inference path changed. |
| P-2 No data leaves device (except user iCloud / P-3 request) | pass | Invented fixtures only. No account identifiers are committed (`.status` files withheld). |
| P-3 Cloud AI opt-in, BYOK, minimised, per ADR-0005 | pass | The round-1 concern is resolved. Every DS-2 cloud run (Parts B, C, D) needs a recorded L2a PASS for its provider, and only Gemini has one today. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Verdict
**APPROVE.** No open Blocker or Major. Minor m3 and r2-1 are open as tickets. This is a merge decision on PR #36 only.
It does not accept AC-M2-14 (overall verdict at the M2 merge commit) or any `AWAITING-DEVICE` criterion.

### Handoff log (round 2)
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Reviewer | accepted | Round 2 at `60c9293`. |
| 2026-11-25 | Reviewer | Orchestrator → Merge Gatekeeper, Acceptance Tester, Documenter | sent | APPROVE. M1, m1, m2, n1 closed. m3 open (governance PR). r2-1: merge order with PR #37 (evidence path). 564 tests passed, 0 warnings, 0 skips. |
