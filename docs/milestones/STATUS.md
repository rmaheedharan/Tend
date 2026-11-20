# Milestone Gate Ledger

Single source of truth for milestone state. **Build work for M(N+1) may not start until M(N) is `ACCEPTED`.**
Only the Product Owner changes a milestone's state, after the gate procedure in
[`OPERATING_MODEL.md` §8](../governance/OPERATING_MODEL.md#8-milestone-gate-procedure).

States: `NOT-STARTED` → `PLANNING` → `IN-BUILD` → `IN-ACCEPTANCE` → (`AWAITING-DEVICE`) → `ACCEPTED`
(or back to `IN-BUILD` on a failed gate).

| Milestone | State | Brief | Acceptance report | Gate signed |
|---|---|---|---|---|
| M1 Core Engine & Cognitive Shielding | NOT-STARTED | — | — | — |
| M2 On-Device AI Ingestion | NOT-STARTED (locked) | — | — | — |
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
