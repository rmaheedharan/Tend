# CLAUDE.md — Tend

This file is the standing brief for every Claude session and every agent working in this repo.
Read it fully before you do anything. When this file and a skill disagree, this file wins.
When this file and [`docs/PRD.md`](docs/PRD.md) disagree on *what* to build, the PRD wins.

---

## 1. What we are building

**Tend** is an AI-first, zero-admin household operating system for iPhone (and iPad).
It is not a to-do list. It is a calm chief of staff for the home: it **captures** messy reality
(voice, camera, shared documents), **shields** the user from overload (never more than 3 things
at once), and **guides** short bursts of action (the 15-Minute Reset).

- Product name is **Tend**. The PRD also says "Hearth" in places; that is the same product.
  Never use "Hearth" in code, identifiers, UI copy, or docs.
- Full requirements: [`docs/PRD.md`](docs/PRD.md). Requirement IDs (`FR-A1`, `UX-2`, `M3` …) are
  stable and must be cited in stories, tests, commits, and docs.

## 2. The laws (non-negotiable)

Any role may stop the line for a law violation. No milestone passes with an open law violation.

### UX laws (from PRD §2)

| ID | Law | What it means in practice |
|---|---|---|
| **UX-1** | Zero-Form Entry | Primary capture is voice, camera, or Share Sheet. No multi-field "New Task" form as an entry point. Editing a captured item is a secondary, single-field-at-a-time refinement. |
| **UX-2** | Rule of Three | The Now canvas, widgets, and any "what should I do" surface show **≤ 3 actionable items**. Enforce it in the **engine** (type-level / API contract), not only in the view. No scrolling task walls on the primary surface. |
| **UX-3** | Zero-Guilt | No red badges, no "overdue", no "X days late", no streak-loss, no shaming copy, no alarm-style notifications. The data model has **no overdue state**; missed work is rescheduled, downgraded, or gently resurfaced. Banned words in UI copy: *overdue, late, missed, failed, behind, penalty*. |
| **UX-4** | Design-award craft | Liquid Glass materials, spring motion, purposeful haptics, full Dynamic Type (incl. accessibility sizes), Light + Dark, VoiceOver, Reduce Motion, Reduce Transparency, 120 Hz-smooth. |

### Privacy laws (from PRD §1)

| ID | Law |
|---|---|
| **P-1** | All routine AI inference runs **on device** (`FoundationModels`, `Speech`, `Vision`). |
| **P-2** | No third-party analytics, ad SDKs, or cloud LLM APIs. No household data leaves the device except via the user's own iCloud (CloudKit, encrypted fields for sensitive data). |
| **P-3** | Any cloud escalation must be Apple Private Cloud Compute or an equivalent zero-retention service, behind an ADR approved by the Product Owner **and** the human owner. Until then, the fallback for "model unavailable" is graceful degradation, never a cloud call. |
| **P-4** | Camera frames, audio, and shared documents are processed in memory and not persisted unless the user saves the result. Ship an accurate Privacy Manifest (`PrivacyInfo.xcprivacy`). |

## 3. Technical targets and defaults

These are defaults. Changing one needs an ADR in `docs/architecture/adr/`.

- **Platforms:** iOS 26+ / iPadOS 26+. Hardware floor iPhone 15 Pro (A17 Pro). iPad gets an adaptive
  layout; features that need Action Button or Dynamic Island degrade gracefully on iPad.
- **Language:** Swift 6, strict concurrency on, no warnings. SwiftUI first; UIKit only by ADR.
- **Architecture:** a pure-Swift domain package (**`TendCore`**: models, Rule-of-Three selector,
  energy/time filter, compassionate rescheduler, sprint builder, load balancer). It imports only
  `Foundation`, has no UI and no Apple-only frameworks, and takes `now`, calendar, weather and
  randomness as injected inputs so every result is deterministic and testable (ideally on Linux too).
  Feature modules sit on top: `TendAI` (FoundationModels/Speech/Vision adapters behind protocols),
  `TendPersistence`, `TendUI`, plus app, widget, Live Activity, Share and Intents extensions.
- **Persistence & sync:** SwiftData or Core Data behind a repository protocol. Household sharing
  (FR-E1) needs CloudKit shared databases (`CKShare`); pick the store in an ADR during M1 with M5 in mind.
- **On-device AI:** `FoundationModels` — `SystemLanguageModel` (always check `.availability`),
  `LanguageModelSession`, `@Generable` / `@Guide` structured output, `streamResponse` for FR-A1
  streaming, `Tool` for duplicate lookup. Speech via `SpeechAnalyzer`/`SpeechTranscriber` (on device).
  Images via `Vision` / `VisionKit` (text, barcodes, classification) feeding text to the model.
- **System surfaces:** App Intents (+ `AppShortcutsProvider`) for Siri, Spotlight, Shortcuts and the
  Action Button; WidgetKit interactive widgets with `AppIntent` buttons; ActivityKit Live Activity with
  `LiveActivityIntent` check-off.
- **Design:** Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glass` button styles), spring
  animations, `sensoryFeedback` / Core Haptics, SF Symbols, semantic colours.
- **Tests:** Swift Testing (`@Test`, `#expect`, parameterised tests) for logic; XCTest/XCUITest for UI
  flows; snapshot/preview matrix for M3; an AI eval harness with fixtures for M2.
- **Project generation:** prefer a generated Xcode project (XcodeGen `project.yml` or Tuist) so agents
  never hand-edit `.pbxproj`. Decide in the first M1 ADR.

## 4. The team (multi-agent delivery)

Seven expert roles, plus an automated Merge Gatekeeper, work as one team. Each has a **skill** (how to do the job) and an **agent**
(a sub-agent that runs the job with its own context). The main session is the **Orchestrator**: it
does not write product code itself; it runs the loop below by delegating to the agents.

| Role | Agent | Skill | Owns (handoff artifact) | Can block |
|---|---|---|---|---|
| Product Owner | `product-owner` | `.claude/skills/product-owner` | Milestone brief, stories, acceptance criteria, gate decision | Scope; final gate sign-off |
| Work Planner | `work-planner` | `.claude/skills/work-planner` | Work plan, work items, dependency order, risk list | Start of build (Definition of Ready) |
| iOS Designer | `ios-designer` | `.claude/skills/ios-designer` | Design spec, copy, motion/haptic spec, design review | Any UX-law or craft violation |
| Developer | `ios-developer` | `.claude/skills/ios-developer` | Code, tests, dev handoff note | Ambiguous or untestable requirements |
| Reviewer | `code-reviewer` | `.claude/skills/code-reviewer` | Review report | Merge (Blocker/Major findings) |
| Acceptance Tester | `acceptance-tester` | `.claude/skills/acceptance-tester` | Acceptance report, test evidence, device scripts | Milestone gate (any FAIL) |
| Product Documenter | `product-documenter` | `.claude/skills/product-documenter` | Docs, changelog, release notes, traceability | Gate if docs/traceability incomplete |
| Merge Gatekeeper | `merge-gatekeeper` | `.claude/skills/merge-gatekeeper` | Independent review comment + merge decision on each PR | Merge (rules G1–G8) |

The full operating model — RACI, handoff contracts, severity scale, escalation — is in
[`docs/governance/OPERATING_MODEL.md`](docs/governance/OPERATING_MODEL.md). The loop is run with the
**`delivery-loop`** skill.

**Auto review and merge.** Every non-draft PR runs `.github/workflows/claude-review-merge.yml`: the Merge Gatekeeper
reviews it independently and merges it only if the review is `APPROVE`, all checks are green, the milestone lock allows
it, and no protected file (`CLAUDE.md`, `docs/PRD.md`, `.claude/**`, `.github/**`, `docs/governance/**`,
`docs/milestones/STATUS.md`) is touched. Changes to the team's own rules always need a human merge. The repo variable
`AUTO_MERGE_ENABLED` is the kill switch. A merge never means a milestone is accepted.
Since 2026-11-20 (D-028) the workflow is off (`AUTO_MERGE_ENABLED=false`): the orchestrator session runs the
`merge-gatekeeper` agent locally and merges only on its `DECISION: MERGE`, under the same rules G1–G8.

### The delivery loop (per milestone)

```
PO brief ─► Planner plan ─► Designer spec ─► Developer build ─► Reviewer review ─► Tester acceptance ─► Documenter docs ─► PO gate
   ▲              │               │                  ▲                │                    │                     │            │
   └──────────────┴── questions ──┴──────────────────┴── findings ────┴──── defects ───────┴─────────────────────┘            ▼
                                                                                                         STATUS.md: M(N) ACCEPTED
```

Rules that hold the team accountable:

1. **Separation of duties.** The agent that wrote code never reviews or accepts it. Review and
   acceptance always run in fresh agent contexts.
2. **Evidence, not claims.** Every PASS links to evidence: a test name and run log, a screenshot,
   a preview render, a device recording. "Should work" is a FAIL.
3. **Every artifact has a Law Check** section (UX-1…UX-4, P-1…P-4): pass / not applicable / concern.
4. **Traceability.** `docs/product/TRACEABILITY.md` links each FR → story → acceptance criterion → test → doc.
   No orphan code, no untested criterion.
5. **Blocks are binding.** Only the role that raised a block, or the human owner, can lift it.
   Disagreements go to `docs/governance/DECISIONS.md` and, if unresolved, to the human owner.

## 5. Milestone gates (hard rule)

Build in five vertical slices, **M1 → M5**, as defined in PRD §4. Gate status lives in
[`docs/milestones/STATUS.md`](docs/milestones/STATUS.md).

- **Do not start any work item for M(N+1)** until `STATUS.md` shows M(N) as `ACCEPTED`.
  Planning the next milestone's brief is allowed; building is not.
- A milestone is `ACCEPTED` only when: every acceptance criterion is PASS with evidence, the
  Reviewer has no open Blocker/Major, the Documenter has signed off, and the PO has signed.
- **Real-device gates need the human.** M2 (latency eval on iPhone 15 Pro), M4 (physical end-to-end),
  and M5 (multi-device sync, 120 Hz, thermal) cannot be proven from a cloud container. The Acceptance
  Tester writes an exact device test script; the criterion stays `AWAITING-DEVICE` until the human owner
  runs it and the result is recorded. Never mark a device criterion PASS from simulation alone.
- A failed gate loops back to the role that owns the defect. No partial acceptance.

## 6. How to work autonomously here

- **Branches:** one branch per milestone work item group, named `m<n>/<slug>`, e.g. `m1/rule-of-three-selector`
  (the Merge Gatekeeper reads the milestone from it). PRs are small, cite requirement IDs, and are merged by the
  Merge Gatekeeper, not by the Developer.
- **Commits:** imperative, scoped, cite IDs: `TendCore: cap Now selection at 3 (UX-2, FR-B1)`.
- **Never** skip, disable, or weaken a test to get green. Never delete an acceptance criterion to pass a gate.
- **Never** add a dependency (SPM package, SDK) without an ADR; prefer Apple frameworks.
- **Ask, don't guess, on product meaning.** Technical choices: decide, record an ADR, move on.
  Product meaning (what the user sees or what counts as "done"): ask the PO agent; if the PO cannot
  answer from the PRD, escalate to the human owner and continue on unblocked work.
- **Environment limits:** a Linux cloud container cannot build or run iOS targets. Keep `TendCore`
  buildable with plain `swift build` / `swift test` where possible, and state clearly in handoffs what
  was verified where (Linux, macOS CI, Simulator, device).

## 7. Commands

> Fill in as the project is created (owned by the Developer; kept current by the Documenter).

```bash
# Core engine (platform-independent)
swift build --package-path Packages/TendCore -Xswiftc -warnings-as-errors
swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors   # same as CI (AC-M1-24)

# App (macOS + Xcode 26 required)
# xcodegen generate && xcodebuild test -scheme Tend -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 8. Map of the repo

```
CLAUDE.md                     ← you are here
docs/PRD.md                   ← product requirements (source of truth)
docs/governance/              ← operating model, decision log, handoff templates
docs/milestones/STATUS.md     ← gate ledger (single source of milestone truth)
docs/milestones/M<n>/         ← brief, plan, design, review, acceptance per milestone
docs/architecture/adr/        ← architecture decision records
docs/product/                 ← user-facing docs, traceability, changelog, release notes
.claude/skills/               ← role skills + delivery-loop
.claude/agents/               ← role sub-agents
.github/workflows/            ← CI and the auto review-and-merge workflow
```

## 9. Open questions (owned by the PO; resolve before the milestone that needs them)

1. **iPad scope.** The owner said "iPhone & iPad"; the PRD targets iPhone 15 Pro. Default: iPad is
   supported with adaptive layout from M3; no iPad-only features. Confirm before M3.
2. **Private Cloud Compute.** Third-party access to PCC through `FoundationModels` may not exist for
   our use case. Default: on-device only, degrade gracefully. Confirm before M2.
3. **Weather context (FR-B1, FR-A1).** *Resolved 2026-11-20 (D-023):* the owner allows WeatherKit with
   coarse location only; an ADR is required before wiring (M3/M4). The engine keeps weather as an injected input.
4. **Naming.** PRD uses "Hearth" in places. Treated as Tend. PO to clean the PRD text when convenient.
