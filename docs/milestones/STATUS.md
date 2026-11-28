# Milestone Gate Ledger

Single source of truth for milestone state. **Build work for M(N+1) may not start until M(N) is `ACCEPTED`.**
Only the Product Owner changes a milestone's state, after the gate procedure in
[`OPERATING_MODEL.md` §8](../governance/OPERATING_MODEL.md#8-milestone-gate-procedure).

States: `NOT-STARTED` → `PLANNING` → `IN-BUILD` → `IN-ACCEPTANCE` → (`AWAITING-DEVICE`) → `ACCEPTED`
(or back to `IN-BUILD` on a failed gate).

| Milestone | State | Brief | Acceptance report | Gate signed |
|---|---|---|---|---|
| M1 Core Engine & Cognitive Shielding | **ACCEPTED** | [M1/brief.md](M1/brief.md) | [M1/acceptance.md](M1/acceptance.md) (25/25 PASS) | 2026-11-20, Product Owner ([signature](#m1--accepted--2026-11-20)) |
| M2 On-Device AI Ingestion | **IN-BUILD** (since 2026-11-21; build unlocked by M1 ACCEPTED. Brief Draft v4, Tester testability review ticked, recorded at `29e2d74`; plan at `81fd80a`; meaning changes in D-031. All build PRs merged up to #54, `main` at `9c44bc0`; eval frozen 2026-11-25 and re-frozen 2026-11-28 under D-059. Next: SP-1, MS-3 green run, DS-1, DS-2. Seven device ACs are `AWAITING-DEVICE`: AC-M2-11, 15, 16, 17, 25, 26, 27. See [M2 build progress](#m2--build-progress-not-a-gate-decision)) | [M2/brief.md](M2/brief.md), [M2/plan.md](M2/plan.md) | — | — |
| M3 Award-Caliber Liquid Glass UI | NOT-STARTED (locked) | — | — | — |
| M4 Multimodal & System Surfaces | NOT-STARTED (locked) | — | — | — |
| M5 Household Sync & Polish | NOT-STARTED (locked) | — | — | — |

## M2 — build progress (not a gate decision)

Updated 2026-11-28 by the Product Owner. M2 stays **IN-BUILD**. Nothing here accepts an AC: a merge never means a
milestone or an AC is accepted. ACs are taken at the M2 merge commit in [M2/acceptance.md](M2/acceptance.md).

**Merged since the last ledger update (PRs #43 to #54).** The Mac-only PRs were merged by the owner under D-032 (read
as in D-064).

| PR | Branch | What it delivered | IDs |
|---|---|---|---|
| #43 | `m2/on-device-adapter-v2` | WI-M2-M2: the `FoundationModels` on-device adapter (re-creates PR #41), with the one-`Tool`-call cap from the R-1 ruling (D-062) | FR-A1, AC-M2-05, AC-M2-06, AC-M2-07, AC-M2-16 (harness side), P-1 |
| #44 | `m2/speech-adapter-v2` | WI-M2-M3: the on-device speech adapter (re-creates PR #42), audio kept in memory only | AC-M2-11 (voice path), P-1, P-4 |
| #45 | `m2/keychain-key-store` | WI-M2-M5: the Keychain key store and the key mask | AC-M2-21, AC-M2-18 (a), P-3 |
| #46 | `m2/cloud-transport` | WI-M2-M4: the cloud HTTPS transport and its failure mapping | AC-M2-22, AC-M2-23, P-2, P-3 |
| #47 | `m2/key-paste-cleanup` | Pasted-key clean-up (D-063) and the PR #45 and #46 follow-ups | AC-M2-21, AC-M2-22, AC-M2-23 |
| #48 | `m2/sp1-device-script` | The SP-1 device script for the iPhone 15 Pro latency spike, and DS-1 Part C | R-1, AC-M2-16, AC-M2-11 |
| #49 | `m2/sp1-script-r3` | SP-1 script v3, matched to the probe build | R-1, SP-1 |
| #50 | `m2/cloud-adapters` | WI-M2-M6: the OpenAI, Anthropic and Gemini adapters end to end; the cloud deadline counted from receipt | AC-M2-24, AC-M2-22, AC-M2-23, AC-M2-27, P-3 |
| #51 | `m2/scanner-loader-exception` | The AC-M2-09 source scanner with the M2 Q23 fixtures-loader rule (D-037) | AC-M2-09, P-2, P-4 |
| #52 | `m2/eval-harness` | WI-M2-M7: the `TendEval` debug harness, results file v1 with per-array element counts, and the scorer checking every request of every attempt (D-059). Merge `1b81e7b` | AC-M2-28, AC-M2-26, AC-M2-14 |
| #53 | `m2/d059-docs` | D-059 docs: the AC-M2-28 wording, the plan text, the DS-2 S4 command, the re-freeze record. Merge `19675a3` | AC-M2-26, AC-M2-28, R50-F4 |
| #54 | `m2/pre-ms3-fixes` | Review PR #53 fixes: `TEND_COMMIT` in the install steps (B7, Appendix A), and the Tester's independent re-score with key-path and count checks (DS-2 S6). `main` now at `9c44bc0` | AC-M2-13, AC-M2-14, AC-M2-26, AC-M2-28 |

**Eval freeze.** Frozen 2026-11-25. Reopened for `results-v1.schema.json` only under D-059 and re-frozen 2026-11-28 by
the Acceptance Tester at `e014fab`. Fixtures hash `7fdc056e92e419a4b416ea14493a7cc2ab9188bb559c796bd79ed45d2141de22`.
The data files are unchanged ([M2/eval-composition.md](M2/eval-composition.md)).

**What is next (in this order).**
1. **SP-1 on the iPhone 15 Pro** (owner runs the Tester's script, [M2/device-scripts/SP-1.md](M2/device-scripts/SP-1.md)).
   It decides R-1 (D-062). It is a spike, not AC-M2-16 evidence. It should run before DS-1, because a result of 1.5 s or more may lead to
   option (b), which changes the cloud golden bodies and needs L2a again.
2. **WI-M2-M8 green run at MS-3**: Linux CI link, Mac B1 to B5 on the M2 merge commit, the AC-to-test table, then
   `TendEval` installed on both iPhones with `TEND_COMMIT` (B7) (AC-M2-13).
3. **DS-1** (iPhone 15 Pro, on device): AC-M2-11, 15, 16, 17.
4. **DS-2** (iPhone 13, cloud): AC-M2-25, 26, 27, per provider, each only after its L2a PASS (D-061).

**Device ACs.** AC-M2-11, 15, 16, 17, 25, 26 and 27 stay `AWAITING-DEVICE` until the owner runs DS-1 and DS-2 and
the results are recorded. AC-M2-24 stays open for OpenAI and Anthropic until their real recordings are made and
reviewed (D-061).

**Waiting on the human owner.**
- **Q20 signing team:** name the team for B7 (a free personal team is enough, D-034; profiles last 7 days).
- **Book MS-3** (both iPhones connected, unlocked, Developer Mode on) and the SP-1 session.
- **OpenAI and Anthropic:** add credit, then run their L2a check and the real recordings (AC-M2-24; D-061).
- **review-pr52 m6:** a local folder name is in branch history (already in `main`'s history since `02c1d84`). Whether
  to rewrite history is the owner's call. The tree at `main` is clean.
- **Merge the governance PR** that records D-059 to D-064 (protected paths).

## Gate signatures

<!-- Copy this block per milestone when its gate is decided.
### M<n> — <ACCEPTED | REJECTED | AWAITING-DEVICE> — <date>
- Acceptance Tester: <PASS count>/<total> PASS, evidence: <link>
- Reviewer: no open Blocker/Major (<links to review.md>)
- iOS Designer: law check clear (<link>)
- Product Documenter: docs + traceability complete (<link>)
- Human device run (if any): <who, date, device, iOS build, link to recorded result>
- Product Owner: <decision and one-line reason>
-->

### M1 — ACCEPTED — 2026-11-20
- Acceptance Tester: 25/25 PASS, evidence: [M1/acceptance.md](M1/acceptance.md). Primary run: CI `push` on merge
  commit `6fff92c` ([run 44824227807](https://github.com/rmaheedharan/Tend/actions/runs/44824227807/job/136592581524)),
  Swift 6.2.4, `-warnings-as-errors`, "127 tests in 17 suites passed", 0 failures, 0 skipped, 0 warnings. Repeat run
  RUN-L in a fresh worktree gave the same result. Six exploratory charters found nothing. Acceptance raised 0 defects.
- PRD §4 gate lines, all met ([acceptance.md § PRD §4 gate lines](M1/acceptance.md#prd-4-gate-lines)):
  - Automated unit suite passes 100%: AC-M1-24.
  - Given 50+ mixed tasks the engine always returns ≤ 3 contextually valid items: AC-M1-13…16 on AC-M1-08…12 and
    AC-M1-25 (1,000-household gate, 273,931 tasks, independent oracle).
  - Tasks whose window ended reschedule without any debt state: AC-M1-02, 03, 17…21 (60-pass bit-identical structure;
    500 households, oracle-equal and idempotent).
  - Household data persistence: AC-M1-04…07, AC-M1-25.
- Reviewer: no open Blocker/Major. Final verdicts ([M1/review.md](M1/review.md)): WI-M1-01 round 2 APPROVE (F-1, F-2
  Major closed); WI-M1-02 round 1 APPROVE; WI-M1-03 round 1 APPROVE; WI-M1-04 round 3 APPROVE (R4-F1 Major closed in
  round 2). Only Minor/Nit tickets stay open. They are carried, with owners, in
  [acceptance.md § Open tickets carried forward](M1/acceptance.md#open-tickets-carried-forward-from-reviewmd-none-blocker-or-major-none-blocks-the-m1-gate).
- iOS Designer: law check clear ([M1/design.md](M1/design.md), APPROVED WITH MINOR, no LAW-STOP). D-1…D-3 are binding
  and were checked clean by the Reviewer in every WI. Open Designer Nits (W3-F5, R4-F5, naming list) are not law
  concerns.
- Product Documenter: docs and traceability complete ([M1/docs-signoff.md](M1/docs-signoff.md);
  [TRACEABILITY.md](../product/TRACEABILITY.md) covers 25/25 ACs and UX-2, UX-3, P-1, P-2).
- Law check: UX-2, UX-3 and P-2 pass. UX-1, UX-4, P-1, P-3 and P-4 are n.a. for M1. No open `LAW-STOP` or law concern
  in any M1 artifact.
- Human device run: none required. No M1 AC is a device AC (brief; acceptance charter C-6).
- Product Owner: **ACCEPTED.** Every AC is PASS with linked evidence, all four gate lines are met, and no Blocker,
  Major or law concern is open. M2 build work is unlocked. Interpretation recorded with this gate: AC-M1-22's RNG-seed
  clause is met by construction, because the engine takes no randomness (D-029). Carried Minor/Nit tickets go to their
  owners; W2-F3 and W3-F6 are taken up in the M2 brief. The ledger change takes effect when the human owner merges
  this PR (protected path).
