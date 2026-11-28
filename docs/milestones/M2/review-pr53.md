# M2 Code Review — PR #53 (`m2/d059-docs`, head `7f46141`, base `main` `1b81e7b`)

- **Owner:** Reviewer (fresh context; did not write these edits)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** `git diff origin/main...HEAD`: docs only, 4 files, 73 added lines. `docs/milestones/M2/acceptance.md`,
  `brief.md`, `eval-composition.md`, `plan.md`. No code, no fixture, no protected path (`CLAUDE.md`, `docs/PRD.md`,
  `.claude/**`, `.github/**`, `docs/governance/**`, `docs/milestones/STATUS.md` are untouched).
- **Checked against:** PO ruling D-059 (`po-m2-element-counts.md`, 2026-11-27); the Tester's D-059 freeze re-check,
  round 2 PASS at `e014fab`, section R2-7 (the doc edits it asked for); the merged code at this head (PR #52, merge
  `1b81e7b`): `Tools/TendTools/Sources/TendToolsSupport/EvalScoreCommand.swift`,
  `Packages/TendIngestion/Sources/TendIngestion/Eval/EvalProfile.swift`,
  `Packages/TendIngestion/Sources/TendIngestion/Payload/CloudRequestKeyPaths.swift`,
  `Apps/TendEval/Sources/Run/RecordingTransport.swift`, `Fixtures/M2/eval/results-v1.schema.json`,
  `Fixtures/M2/eval/MANIFEST.sha256`, `Fixtures/M2/eval/household.json`, `Fixtures/M2/payload/**`; review
  `review-pr52.md` (Info i2); review `review-pr50.md` (R50-F4).
- **IDs:** AC-M2-14, AC-M2-24, AC-M2-25, AC-M2-26, AC-M2-27, AC-M2-28, D-050, D-053, D-054, D-058, D-059, Q12, Q16,
  R50-F4, P-3, P-4, UX-3.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 docs work on an `m2/` branch. OK.

## Summary

The docs match what the merged code does. The DS-2 S4 command is complete and uses only options the tool knows. No
acceptance criterion is removed or weakened; every changed rule is the same or stricter. I found no Blocker and no
Major. There are three Minor findings and two Info notes. None blocks the merge.

What I checked, one by one:

1. **Docs match the code.**
   - Fixtures hash. `sha256sum Fixtures/M2/eval/MANIFEST.sha256` at this head gives
     `7fdc056e92e419a4b416ea14493a7cc2ab9188bb559c796bd79ed45d2141de22`. That equals `FIXTURE-HASH` in
     `acceptance.md:139` and the value in `eval-composition.md` Status. `(cd Fixtures/M2/eval && sha256sum -c
     MANIFEST.sha256)` prints 4 x `OK`. The schema line is `096161326b04…869a`; the three data lines are `0e819a89…`,
     `089a22bd…`, `b32e45af…`, as the docs say.
   - Schema (`results-v1.schema.json`): both count arrays have `uniqueItems: true` (lines 392 and 408), as the plan
     WI-M2-15 bullet and `eval-composition.md` v7 say.
   - Scorer (`EvalProfile.swift:315-336`): `ds2-gated` runs the key-path check and `arrayCountFailures` over
     `file.inputs`, so every request of every attempt, retakes included. This matches the S4 note, the AC-M2-26 pass
     rule and the plan ("both over every request of every attempt").
   - Count rule (`EvalProfile.swift:349-399`): null member fails; body counts must equal the golden body's, path for
     path; user content must hold only `$.existingTasks` and `$.rooms`; `rooms` equals `fixtures.rooms.count`;
     `existingTasks` at most 10. `household.json` has 9 rooms, so "rooms = 9" in the AC-M2-26 pass rule is right.
   - The check label in the pass rule, "per-array element counts match the golden body and the seeded household
     (AC-M2-26, D-059)", is the exact string at `EvalProfile.swift:339`.
   - Recorder: `RecordingTransport.swift:35` calls `CloudRequestKeyPaths.arrayCounts(ofBody: request.body)`, the shared
     function, on the bytes handed to the transport. This matches the new plan WI-M2-M7 bullet.
   - Swift types and `schemaVersion` 1: as the plan bullet says (checked in `review-pr52.md`; unchanged since).
2. **DS-2 S4 command (`acceptance.md:432-434`).**
   - It has `--golden-body Fixtures/M2/payload/golden/g1-outcome-empty-<p>.body.json`.
   - Every option it uses (`--profile`, `--fixtures`, `--expected-fixtures-sha256`, `--results`,
     `--allowed-key-paths`, `--golden-body`, `--log`) is in the tool's option list (`EvalScoreCommand.swift:42-44`).
     `ds2-gated` without `--allowed-key-paths` or `--golden-body` is a usage error (exit 64, lines 53-58), so the
     command as written passes both guards.
   - All six referenced fixture files exist for `openai`, `anthropic` and `gemini`. `$H` is set in S1 and is quoted.
   - The form is the same as DS-1 S2 (`acceptance.md:284`), which is the known working form.
   - Limit: I could not run it here. The container's `swift` needs Docker, and the Docker daemon is not running. I
     checked it by reading the argument parser. The Tester ran the same options in Docker in the D-059 re-check
     (round 2, R2-5), with exit codes as expected.
3. **No AC weakened.**
   - Removed lines are only: the empty `FIXTURE-HASH` cell, the short S4 line, the short S6 line, the old AC-M2-26 pass
     rule, the brief's "The exact format is set in the plan", two `eval-composition.md` header phrases, and the old
     `ds2-gated` profile line. Each one is replaced by the same text plus more.
   - AC-M2-26's pass rule adds the counts clause; nothing was taken out. "Read from" adds the S4 counts line.
   - Brief AC-M2-28: the new sentence is the PO's wording from D-059, word for word. AC-M2-26 brief text is unchanged.
     Still 28 ACs.
   - All seven device ACs (AC-M2-11, 15, 16, 17, 25, 26, 27) stay `AWAITING-DEVICE` in `acceptance.md:19-26`.
   - AC-M2-24: the new plan paragraph (`plan.md:635-641`) says it "stays open for OpenAI and Anthropic" and that the
     Gemini recording does not stand in for them. This also records the owner's choice that R50-F4 asked for (the
     `DECISIONS.md` entry is still for the governance PR).
4. **IDs.** D-059, AC-M2-26, AC-M2-28, D-050, D-053, D-054, D-058, Q12, Q16 and R50-F4 are used the same way in all four
   files and in the ruling. D-058 is the last entry in `DECISIONS.md` on `main`, so D-059 is the next free ID, as the
   PO note asked to check.
5. **Copy and privacy.** I grepped the added lines for the UX-3 banned words (*overdue, late, missed, failed, behind,
   penalty*), for "Hearth", for local paths (`/home/`, `/mnt/`), for e-mail addresses and for the owner's name: no hits.
   The word "fails" appears only as scorer exit-code text for the team ("the run fails (exit 1)"), not as user copy.
   No hostnames, keys or header values.
6. **Law Check:** below. All pass or n.a.

**review-pr52 Info i2.** Half addressed.
- DS-2 `--golden-body`: **addressed** (`acceptance.md:433`).
- MS-3 / DS install with `TEND_COMMIT`: **not addressed** in this PR. See F3.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F1 | Minor | `docs/milestones/M2/acceptance.md:139`; `docs/milestones/M2/eval-composition.md` Status (lines 7-16) | Both say the fixtures hash "is valid on `main` only once `m2/eval-harness` (with `e014fab`) is merged; until then `main` still holds the old schema and manifest". That was true when the text was drafted, but PR #52 is now merged: `e014fab` is an ancestor of `origin/main` `1b81e7b`, and `main`'s manifest hashes to `7fdc056e…`. The owner reads `FIXTURE-HASH` before a gate run, so a stale condition next to it can cause doubt. | Replace the condition with a plain fact, for example "merged to `main` in PR #52 (`1b81e7b`)". Same in the `acceptance.md` handoff row if you like. | Open |
| F2 | Minor | `docs/milestones/M2/plan.md` new WI-M2-M7 bullet ("This text is in place before WI-M2-M7 is reviewed and before any DS-2 run") | D-059 said the plan text must be in place before WI-M2-M7 is reviewed. In fact WI-M2-M7 was reviewed (`review-pr52.md`, round 1) and merged (PR #52) before this text. The review used the ruling note as the spec, so no harm was done, but the sentence states an order that did not happen (CLAUDE.md §4 rule 2, evidence not claims). The handoff row also says "Planner to confirm the text": the Planner has not confirmed it yet. | Reword to what happened, for example "The WI-M2-M7 review (PR #52) used D-059 directly; this plan text was added after it, before any DS-2 run." Planner confirms the WI-M2-15 and WI-M2-M7 text (Planner owns `plan.md`). | Open |
| F3 | Minor | `docs/milestones/M2/acceptance.md:456-475` (Appendix A, Xcode GUI install, step 8 "Press ⌘R"); `docs/milestones/M2/plan.md:604-609` (B7) | Carry-over of `review-pr52.md` i2, second half. `project.yml:99` sets `TEND_COMMIT: ""`. A GUI ⌘R build or the B7 `xcodebuild` line as written leaves it empty, and the harness then will not start a run (`EvalSession.swift:131`). Neither Appendix A nor B7 passes `TEND_COMMIT=$(git rev-parse HEAD)`. The `dev-notes.md` build note has it, but the owner follows Appendix A and B7. It fails safe (the app says why and no run is recorded), and no device run is due before MS-3, so this is not a merge block. Not in this PR's diff. | Tester (Appendix A) and Planner (B7): add `TEND_COMMIT=$(git rev-parse HEAD)` to the B7 `xcodebuild build` line, and in Appendix A either use that Terminal line or say how to set `TEND_COMMIT` in Xcode. Do it before MS-3. | Open (for Tester / Planner) |
| i1 | Info | `docs/milestones/M2/acceptance.md:435-437` (S6) | S6 now says the Tester's independent re-score also checks key paths and counts for every attempt. The Tester's note (R2-7) says `independent-rescore.py` does not read `cloudRequests` yet; it is a Tester action before the first DS-2 run. The doc reads as if it is ready. Not a weakening: it adds a control. | Tester: extend the script before the first DS-2 run, as planned. Optional: say "to be added before the first DS-2 run" in S6. | Info |
| i2 | Info | `docs/milestones/M2/plan.md:655-657` ("Scoring tool and command" block) | Not in this diff. `sha256sum -c Fixtures/M2/eval/MANIFEST.sha256` from the repo root fails ("4 listed files could not be read"), because the manifest lists bare file names. `acceptance.md` S1 uses the correct form `(cd Fixtures/M2/eval && sha256sum -c MANIFEST.sha256)`. Also, the plan's `ds2-gated` rule mentions "0 if Q12 is ever no", but the scorer has only the ≤ 10 rule; Q12 = yes is confirmed (D-050), and any change would need a PO decision and a code change anyway. | Planner: use the `cd` form in the plan block when convenient. | Info |

## Checklist
- [x] Correctness vs ACs (AC-M2-26 pass rule, AC-M2-28 wording, FIXTURE-HASH, S4 command checked against the merged code)
- [x] Tests meaningful: n.a. (docs only; the Tester's re-check runs are the evidence the docs cite)
- [x] Swift 6 concurrency safe: n.a. (no code)
- [x] No force unwraps / try! in product code paths: n.a. (no code)
- [x] Privacy (P-1…P-4): no change to what is sent or stored; docs describe integers and paths only
- [x] UX-2/UX-3 enforced in engine: n.a.; no banned words in added text
- [x] Accessibility (UI): n.a.
- [x] Performance: n.a.
- [x] No new dependency without ADR: none added
- [x] No AC removed or weakened; device ACs stay AWAITING-DEVICE; AC-M2-24 stays open for OpenAI and Anthropic
- [x] No protected path touched

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Docs for a debug harness and scorer; no product entry path. |
| UX-2 Rule of Three | n.a. | No product surface. |
| UX-3 Zero-Guilt | pass | No banned word in the added lines. Scorer wording ("fails", exit codes) is team text, not user copy. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Routing text unchanged; "on device first" kept in DS-2. |
| P-2 No data leaves device (except user iCloud) | pass | No dependency, host or server added. Scoring runs offline on Linux. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | The docs now make the on-device minimisation proof complete: counts and key paths checked on every request of every attempt (D-059, AC-M2-26). No new request field. |
| P-4 Media not persisted without consent | pass | The format holds integers and member-name paths only; never a body, value, header or key (AC-M2-28). No personal data, local path or hostname in the docs. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-28 | Orchestrator | Reviewer | accepted | PR #53, head `7f46141`, base `main` `1b81e7b`. D-059 docs after PR #52. |
| 2026-11-28 | Reviewer | Orchestrator → Merge Gatekeeper; Documenter (F1); Planner (F2, F3 B7, i2); Acceptance Tester (F3 Appendix A, i1) | sent | **APPROVE**, round 1. No Blocker or Major. Minors F1–F3, Info i1–i2. Fixtures hash and manifest verified with `sha256sum`; S4 command checked against the tool's option parser (not run: no Docker daemon here). review-pr52 i2: `--golden-body` done, `TEND_COMMIT` still open (F3). File not committed. |
