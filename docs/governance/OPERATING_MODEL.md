# Tend Delivery Operating Model

How seven agent roles build Tend together and share accountability for quality.
Applies to every milestone (M1–M5). Summary lives in [`CLAUDE.md`](../../CLAUDE.md) §4–5.

## 1. Principles

1. **Quality is everyone's job, and someone is named for each check.** Each gate has one accountable role.
2. **Shift left.** Defects are cheapest at the brief. The PO writes testable criteria; the Tester
   reviews them *before* build; the Designer checks laws *before* code.
3. **Evidence over assertion.** Every PASS has a link to proof.
4. **Separation of duties.** Author ≠ reviewer ≠ acceptor. Fresh agent context for each.
5. **Small batches.** Work items are ≤ 1 day of human-equivalent effort and ship behind passing tests.
6. **Stop the line.** Any role can raise a `LAW-STOP` (UX-1…4, P-1…4). Work on the affected item
   pauses until the Designer (UX) or PO (privacy) clears it.

## 2. Roles and decision rights

| Role | Accountable for | Decision rights | Can block | Cannot |
|---|---|---|---|---|
| **Product Owner** | Value, scope, acceptance criteria, gate sign-off | Priority, scope cuts within PRD, meaning of a requirement | Gate (final signature); out-of-scope work | Override a Tester FAIL or a Reviewer Blocker; change the PRD without logging a decision |
| **Work Planner** | Plan quality, sequencing, Definition of Ready, flow | Order and size of work items, branch plan | Build start if DoR not met | Change acceptance criteria |
| **iOS Designer** | Experience quality, UX laws, accessibility, copy tone | Visual, motion, haptic and copy decisions | Any UI/copy that breaks UX-1…4 or HIG | Change scope or acceptance criteria |
| **Developer** | Correct, tested, maintainable code; dev handoff | Technical design within ADRs; new ADRs | Work on an ambiguous / untestable item (returns it to PO/Planner) | Merge without Reviewer APPROVE; mark own work accepted |
| **Reviewer** | Code quality, security, privacy, concurrency, performance | Severity of findings | Merge (Blocker/Major open) | Rewrite the feature; accept the milestone |
| **Acceptance Tester** | Proof that each criterion is met as the user would experience it | PASS / FAIL / AWAITING-DEVICE per criterion | Milestone gate (any FAIL or missing evidence) | Fix product code; soften a criterion |
| **Product Documenter** | Docs, changelog, release notes, traceability, ADR index | Doc structure and standards | Gate if docs or traceability are incomplete | Change behaviour to match docs |
| **Merge Gatekeeper** (automated) | Independent review on every PR and the merge decision | Merge or block per rules G1–G8 | Merge | Merge protected paths (rules, PRD, gate ledger, workflows); accept a milestone |
| **Human owner** | Final authority | Anything | Anything | — |

## 3. RACI per milestone step

R = does the work, A = accountable (one per row), C = consulted, I = informed.

| Step | PO | Planner | Designer | Developer | Reviewer | Tester | Documenter |
|---|---|---|---|---|---|---|---|
| Milestone brief & acceptance criteria | **A/R** | C | C | C | I | C (testability) | I |
| Work plan & Definition of Ready | C | **A/R** | C | C | I | C | I |
| Design spec & law check | C | I | **A/R** | C | I | C | I |
| Build + automated tests | I | I | C | **A/R** | I | C | I |
| Code review | I | I | C (UI) | C | **A/R** | I | I |
| Acceptance testing | C | I | C | I | I | **A/R** | I |
| Docs, changelog, traceability | C | I | C | C | I | C | **A/R** |
| Gate decision | **A/R** | C | C | C | C | C | C |

## 4. Handoff contracts

Every handoff is a file in `docs/milestones/M<n>/` using a template from
[`templates/`](templates/). A handoff is **complete** only if every required section is filled.
The receiver checks the entry criteria and either **accepts** (records it in the file's Handoff Log)
or **returns** it with reasons.

| # | From → To | Artifact | Entry criteria for the receiver |
|---|---|---|---|
| H1 | PO → Planner | `brief.md` | Every story cites FR/UX IDs; every AC is Given/When/Then, measurable, and reviewed for testability by the Tester |
| H2 | Planner → Designer, Developer | `plan.md` | Every work item meets Definition of Ready; dependency order is acyclic; risks have owners |
| H3 | Designer → Developer | `design.md` | States (empty, loading, streaming, error, unavailable model), copy, motion, haptics, a11y specified; law check passed |
| H4 | Developer → Reviewer | PR + `dev-notes.md` | Builds, all tests green, new tests for each AC, verification-environment table filled |
| H4b | Developer → Merge Gatekeeper | PR (non-draft) | Reviewer `APPROVE`, all checks green, milestone lock OK, no protected path; Gatekeeper merges or labels `needs-human` / `changes-requested` |
| H5 | Reviewer → Tester | `review.md` | Verdict APPROVE; no open Blocker/Major |
| H6 | Tester → Documenter, PO | `acceptance.md` | Every AC has status and evidence; device scripts written for device ACs |
| H7 | Documenter → PO | docs PR + `TRACEABILITY.md` | Every AC traced to tests and docs; changelog and release notes drafted |
| H8 | PO → everyone | `STATUS.md` | Gate decision with all signatures |

## 5. Definitions

**Definition of Ready (work item)** — cites requirement IDs; has testable acceptance criteria;
has a design spec if it touches UI or copy; dependencies are done or stubbed; size ≤ 1 day; owner named.

**Definition of Done (work item)** — code merged by the Merge Gatekeeper after Reviewer APPROVE; tests for each AC pass in CI;
no new warnings; accessibility checked for UI; docs updated; traceability row updated.

**Definition of Done (milestone)** — all PRD §4 gate checks for that milestone met with evidence;
all ACs PASS (device ACs PASS with human-recorded result); no open Blocker/Major; docs signed off;
PO signed in `STATUS.md`.

## 6. Severity scale (used by Reviewer, Tester, Designer)

| Severity | Meaning | Effect |
|---|---|---|
| **Blocker** | Law violation (UX/P), data loss, crash, security/privacy leak, AC not met | Blocks merge and gate |
| **Major** | Wrong behaviour in a real scenario, missing test for an AC, concurrency hazard, a11y failure | Blocks merge and gate |
| **Minor** | Works, but quality issue (naming, small perf, unclear code) | Must be ticketed; does not block |
| **Nit** | Taste | Optional |

## 7. Escalation

1. Author and blocker discuss in the artifact (max two rounds).
2. Still stuck → record both positions in [`DECISIONS.md`](DECISIONS.md); the PO decides product
   meaning, the Developer (with an ADR) decides technical matters, the Designer decides craft.
3. Any law question, any cloud/privacy question, or any decision that changes the PRD → human owner.
   Continue with unblocked work while waiting.

## 8. Milestone gate procedure

1. Tester publishes `acceptance.md` with status per AC.
2. Documenter confirms docs + traceability.
3. Reviewer confirms no open Blocker/Major across the milestone's PRs.
4. Designer confirms no open law concern (M3+ mandatory; M1–M2 for copy/data model).
5. PO checks the PRD §4 gate line by line and signs `STATUS.md`.
6. If any device AC is `AWAITING-DEVICE`, status is `AWAITING-DEVICE`, not `ACCEPTED`. The human owner
   runs the script, the Tester records the result, then step 5 repeats.
7. Only `ACCEPTED` unlocks M(N+1) build work.
