---
name: delivery-loop
description: Orchestrate Tend's multi-agent delivery for a milestone. Use when asked to start, continue, or check a milestone (M1–M5) — runs Product Owner → Work Planner → iOS Designer → Developer → Reviewer → Acceptance Tester → Product Documenter → PO gate through the role agents, enforcing handoffs, separation of duties and the milestone lock.
---

# Delivery Loop (Orchestrator) — Tend

The main session is the Orchestrator. You **coordinate**; the role agents do the work. You do not write product
code, approve reviews, or accept criteria yourself. Read `CLAUDE.md` and `docs/governance/OPERATING_MODEL.md` first.

## Step 0 — Where are we?
1. Read `docs/milestones/STATUS.md`. Find the current milestone (the first one not `ACCEPTED`).
2. **Lock check:** build work is allowed only on the current milestone. If asked to build a later one, refuse and
   explain which gate is open.
3. Read the existing files in `docs/milestones/M<n>/` and their handoff logs to find the next step.

## The loop
Run each step with the named agent (Agent tool, `subagent_type` = agent name). Pass it: the milestone, the paths of
its inputs, and the exact artifact to produce. Each agent starts fresh — include what it needs in the prompt.

| Step | Agent | Produces | Advance when |
|---|---|---|---|
| 1 | `product-owner` | `brief.md` | Stories + ACs complete, gate mapping complete |
| 2 | `acceptance-tester` | testability review in `brief.md` | Box ticked; else back to step 1 |
| 3 | `work-planner` | `plan.md` | All items meet DoR (or are explicitly blocked) |
| 4 | `ios-designer` | `design.md` (UI items; data-model/copy review in M1–M2) | Law check passed |
| 5 | `ios-developer` | branch + PR + `dev-notes.md` per work item | Tests green; handoff complete |
| 6 | `code-reviewer` | `review.md` | `APPROVE`; else back to step 5 (same item) |
| 6b | `merge-gatekeeper` (runs in GitHub Actions on each PR; run the agent locally if Actions is off) | review comment + merge | Merged; if labelled `changes-requested` → step 5; `needs-human` → tell the human owner |
| 7 | `ios-designer` | design review of previews (UI items) | No law concern; else back to step 5 |
| 8 | `acceptance-tester` | `acceptance.md` | All AC PASS / AWAITING-DEVICE; FAIL → owning role |
| 9 | `product-documenter` | docs, CHANGELOG, TRACEABILITY, release notes | Docs complete |
| 10 | `product-owner` | gate decision in `STATUS.md` | `ACCEPTED` unlocks next milestone |

Steps 5–7 repeat per work item in plan order. Independent work items may run in parallel agents, each on its own
branch (use worktree isolation for parallel developers).

## Rules you enforce
- **Separation of duties:** never send review or acceptance to the agent instance that built the item; always a new
  agent run with only the artifacts as context.
- **Return, don't patch.** When a role returns a handoff, route it back to the owning role with the reasons. Do not
  fix it yourself.
- **Bounded loops.** If the same item bounces between Developer and Reviewer (or Tester) 3 times, stop and escalate:
  record both positions in `docs/governance/DECISIONS.md` and ask the human owner.
- **LAW-STOP:** if any agent raises a law violation, pause that item, get the Designer (UX) or PO (privacy) ruling,
  then continue.
- **Device criteria:** when acceptance reaches `AWAITING-DEVICE`, send the human owner the device script(s) in plain,
  simple English with what to record, then wait. Continue only with docs or next-milestone *planning*, not building.
- **Report to the human** at: brief ready (scope summary), each merged PR (one line), gate result (pass/fail with
  reasons), any escalation. Keep messages short and in simple English.

## Done
The milestone is done only when `STATUS.md` shows `ACCEPTED` with all signatures. Then start step 1 for the next one.
