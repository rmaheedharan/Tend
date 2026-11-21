# Milestone Gate Ledger

Single source of truth for milestone state. **Build work for M(N+1) may not start until M(N) is `ACCEPTED`.**
Only the Product Owner changes a milestone's state, after the gate procedure in
[`OPERATING_MODEL.md` §8](../governance/OPERATING_MODEL.md#8-milestone-gate-procedure).

States: `NOT-STARTED` → `PLANNING` → `IN-BUILD` → `IN-ACCEPTANCE` → (`AWAITING-DEVICE`) → `ACCEPTED`
(or back to `IN-BUILD` on a failed gate).

| Milestone | State | Brief | Acceptance report | Gate signed |
|---|---|---|---|---|
| M1 Core Engine & Cognitive Shielding | **ACCEPTED** | [M1/brief.md](M1/brief.md) | [M1/acceptance.md](M1/acceptance.md) (25/25 PASS) | 2026-11-20, Product Owner ([signature](#m1--accepted--2026-11-20)) |
| M2 On-Device AI Ingestion | **IN-BUILD** (since 2026-11-21; build unlocked by M1 ACCEPTED. Brief Draft v4, Tester testability review ticked, recorded at `29e2d74`; plan at `81fd80a`; meaning changes in D-031. Seven device ACs will need a human run: AC-M2-11, 15, 16, 17, 25, 26, 27) | [M2/brief.md](M2/brief.md), [M2/plan.md](M2/plan.md) | — | — |
| M3 Award-Caliber Liquid Glass UI | NOT-STARTED (locked) | — | — | — |
| M4 Multimodal & System Surfaces | NOT-STARTED (locked) | — | — | — |
| M5 Household Sync & Polish | NOT-STARTED (locked) | — | — | — |

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
