# M1 Docs Sign-off — Core Engine & Cognitive Shielding

- **Owner:** Product Documenter  ·  **Build / commit:** `main` at `6fff92c` (PRs #3, #5, #6, #7, #8); acceptance report
  at `0a9eb87` on `m1/acceptance`  ·  **Date:** 2026-11-20
- **Requirements:** FR-B1, FR-B2, FR-B3 (data only), UX-2, UX-3, P-1, P-2; AC-M1-01…25
- **Verdict:** **DOCS COMPLETE — SIGNED OFF (H7).** Traceability is complete for all 25 ACs and the four M1 laws. No
  doc describes behaviour that does not exist. The follow-ups below do not block the gate.

## What I checked

1. **Traceability.** Every AC-M1-01…25 has a story, a work item, at least one named test and a doc. No orphan AC, no
   untested criterion. Every source file in `Packages/TendCore/Sources/TendCore/` maps to an AC. UX-2, UX-3, P-1 and
   P-2 each have their own row.
2. **Test names are real.** I reran the suite on `0a9eb87` in the Linux container (Swift 6.2,
   `-Xswiftc -warnings-as-errors`): `✔ Test run with 127 tests in 17 suites passed after 111.042 seconds.`,
   0 `warning:` lines, 0 `✘` lines. Each AC-M1-01…23 and AC-M1-25 has at least one passing test whose name carries
   its ID; AC-M1-24 is the run itself (CI run 44824227807 on `6fff92c`). This matches the Acceptance Tester's RUN-CI
   and RUN-L.
3. **Docs match the code.** I read the public API in `Sources/` (`NowSelection`, `NowSelector`, `Moment`,
   `Rescheduler`, `Household.complete`, `JSONFileHouseholdRepository`, `TaskState`) against the overview and the
   explanation pages.
4. **DocC.** Every public type and every public function with behaviour has a doc comment that cites its
   requirement IDs. A few self-explanatory members have none (`Household.init`, `Room.init`, `Moment.init`, some
   stored properties, protocol witnesses). Nit, optional, Developer.
5. **UX-3 in the docs.** The user-facing pages avoid the banned words. The builder docs name the banned word list
   only where they explain the scanner.

## Deliverables

| Deliverable | Path | Notes |
|---|---|---|
| Traceability | [`docs/product/TRACEABILITY.md`](../../product/TRACEABILITY.md) | M1 detail table (25 ACs), law table, code → AC table |
| Changelog | [`docs/product/CHANGELOG.md`](../../product/CHANGELOG.md) | `[0.1.0]` M1 entry; dated when the PO accepts the gate |
| ADR index and module map | [`docs/architecture/README.md`](../../architecture/README.md) | 0001 Accepted; 0002, 0003, 0004 Proposed; weather ADR listed as planned |
| ADR-0004 note | [`docs/architecture/adr/0004-household-json-file-format.md`](../../architecture/adr/0004-household-json-file-format.md) | W2-F1: non-file URLs are refused in `init(fileURL:)` |
| Architecture overview | [`docs/architecture/overview.md`](../../architecture/overview.md) | Model, Persistence, Selection, Rescheduling; injected inputs; UX-2 and UX-3 enforcement; verified where |
| Explanation pages | [`rule-of-three.md`](../../product/explanation/rule-of-three.md), [`compassionate-rescheduling.md`](../../product/explanation/compassionate-rescheduling.md) | M1 deliverables from the Documenter skill; user-facing, plain language |
| Release notes | [`docs/product/release-notes/M1.md`](../../product/release-notes/M1.md) | Internal milestone; no App Store text yet |

## Follow-ups (not blocking the M1 gate)

| # | Item | Owner | When |
|---|---|---|---|
| F-1 | Copy the decisions below into `docs/governance/DECISIONS.md` (protected; human merge). | Human owner (via Orchestrator) | Next governance PR |
| F-2 | `docs/milestones/STATUS.md` still shows M1 `NOT-STARTED`. Update at the gate (protected). | Product Owner | M1 gate |
| F-3 | ADR-0004 is still `Proposed`. The Reviewer agreed with it in the WI-M1-02 review and said the status change belongs to the ADR owner and the Documenter. I left it `Proposed` as instructed; the Developer (owner) may move it to `Accepted`, and I will update the index. | Developer | Optional, before M3 |
| F-4 | CLAUDE.md suggestions (protected, see below). | Human owner | Next governance PR |
| F-5 | Weather ADR (WeatherKit, coarse location) before any weather wiring (Q22). Listed as planned in the index. | Developer + PO | M3/M4 |
| F-6 | W2-F4: either add a protection class, or add one line to ADR-0004 that the JSON store is not the on-device app store. | Developer | M3 |
| F-7 | R4-F4: `plan.md` still says the engine takes an RNG; the overview says it takes none (matches the code). | Work Planner | Optional |
| F-8 | DocC Nits (check 4). | Developer | Optional |

### CLAUDE.md suggestions (I did not edit it)

- **§7 Commands is correct.** `swift test --package-path Packages/TendCore` works (rerun above). The xcodegen line
  should stay commented out until the app target exists (ADR-0003 is Proposed). Optional addition, to match CI and
  AC-M1-24:
  ```bash
  swift build --package-path Packages/TendCore -Xswiftc -warnings-as-errors
  swift test  --package-path Packages/TendCore -Xswiftc -warnings-as-errors
  ```
- **§9 item 3 (weather) is resolved** by Q22: WeatherKit is allowed with coarse location only, after a PO-approved
  ADR. The text could say "Resolved 2026-11-20 (Q22); ADR before wiring in M3/M4".
- **§4 "Auto review and merge"** describes the paid workflow. The owner decided on 2026-11-20 that merges run from the
  Claude session (local Merge Gatekeeper) and set `AUTO_MERGE_ENABLED` to `false` (D-028 below). A one-line note would
  keep §4 accurate.

## Ready-to-paste entries for `docs/governance/DECISIONS.md`

Numbering continues after D-001, as the brief asks ("D-002…"). Q*n* becomes D-(*n*+1). Design rules D-1…D-3 become
D-025…D-027, so they do not clash with the log's own D-numbers. Newest first, as the log requires. Copy the rows below
the existing header, above D-001.

```markdown
| D-028 | 2026-11-20 | PRs are merged from the Claude session by the local Merge Gatekeeper, not by the paid `claude-review-merge.yml` workflow. The repo variable `AUTO_MERGE_ENABLED` is set to `false`. Gatekeeper rules G1–G8 and the protected-path rule still apply; changes to protected files still need a human merge. | Cost; the owner keeps the kill switch off. | Human owner | — |
| D-027 | 2026-11-20 | Design rule D-3 (M1 design.md): no `priority`, `score` or `weight` that grows with time since a window ended. Now ranking stays the fixed AC-M1-16 key. Violation is a Blocker. | A growing score would add urgency that grows with time (UX-3, UX-2). | iOS Designer | — |
| D-026 | 2026-11-20 | Design rule D-2 (M1 design.md): no original-window fields, counters or reschedule history (`rescheduleCount`, `deferCount`, `timesMoved`, `originalWindowStart`/`End`, `firstWindow`, `initialDueDate`, history arrays), in the model or in any later store schema (ADR-0002). Violation is a Blocker. | A fixed-size original date or counter would let someone compute lateness later, which AC-M1-20 alone would not catch (UX-3). | iOS Designer | — |
| D-025 | 2026-11-20 | Design rule D-1 (M1 design.md): code, test names and evidence say a deferral's rest is **over** (`isRestOver(at:)`, `restEnded`), never "lapsed"; say "window ended", never "missed". Product meaning unchanged. | "Lapsed" implies a fault (UX-3). | iOS Designer | — |
| D-024 | 2026-11-20 | Q23 (Merge Gatekeeper GK-1, PR #8), option (b). Outside the allowlisted JSON file-repository file(s), every `contentsOf:` argument label is banned in `TendCore/Sources`, on any type, initialiser or function. The only exception: a `contentsOf:` whose immediately enclosing call is named exactly `append` or `insert` (the collection methods). Any further exception needs a PO decision. The PO also adopts the rest of the AC-M1-23 body (Q17–Q20 lists, `URL(string:`/`NSURL`/`URLComponents`/`CFURL`, clock and socket families, `AsyncStream` exemption) and the Q19/Q20 rows as its own decisions. Compared with Q19 this is **stricter**: Q19 banned only eight named URL-loading initialisers plus `.init(contentsOf:`, so `NSMutableData(contentsOf:)` and similar escaped. Compared with Q18 it keeps the same blanket ban and the same allowlisted file, **except** that it keeps Q19's exemption for `append`/`insert(contentsOf:)`, which Q18 did not have; those calls do not load URLs. | Close the `NSMutableData(contentsOf:)` gap (P-2) while keeping harmless collection calls legal. | Product Owner | D-020 (`contentsOf:` part) |
| D-023 | 2026-11-20 | Q22 (closes Q8 / CLAUDE.md §9 item 3). Weather MAY come from Apple's WeatherKit, with coarse location only and no household data, task text or identifiers in the request. A PO-approved ADR is required before wiring: coarse-location method, request contents, caching, Privacy Manifest and privacy-label impact, and failure/denied behaviour (weather is `unknown`; no other fallback, no extra prompt). `TendCore` keeps weather as an injected input and never fetches it. Nothing to build in M1; wiring and ADR in M3/M4. | Owner answer 2026-11-20 17:40Z (P-2, P-4). | Human owner, recorded by PO | D-009 (default) |
| D-022 | 2026-11-20 | Q21 (AC-M1-20 "identical"). "Identical" means bit-identical (`bitPattern`) as far as `Date` can represent it. Within one binade (between consecutive powers of two of seconds since 2001) the duration must be bit-identical, no tolerance. Only when a window crosses a binade edge may the duration change, by exactly one ulp of the **finer** grid below the edge (half a coarse ulp; 2^-23 s at the 2^30 s edge), only for odd-step durations, at most once per edge, at the pass that first reaches the edge or the next; then identical again. No other change. Evidence: strict bit-pattern gate over 2024–2029 plus a named edge-case test with an explicit edge predicate (no tolerance). Snapping the start and storing a duration are rejected. | `Date` is a `Double`; one rounding at a binade edge is unavoidable and is not debt growth (UX-3). Wording corrected per review R4-F2. | Product Owner | — |
| D-021 | 2026-11-20 | Q20 (review Q-R4, F-9). Ban `CFAbsoluteTimeGetCurrent`, `DispatchTime`, `DispatchWallTime`, `ContinuousClock`, `SuspendingClock`, `mach_absolute_time`, `clock_gettime`, `gettimeofday`, `CFHost`, `CFReadStream`, `CFWriteStream`, `CFSocket`, lower-case `socket(`, `getaddrinfo`, `gethostbyname` in `TendCore/Sources`. The engine gets time only from the injected `now`. | Determinism (AC-M1-22) and P-2. Tightening only. | Product Owner | — |
| D-020 | 2026-11-20 | Q19 (review Q-R3, F-8). Ban `NSURL`, `URLComponents` and `CFURL` outright. Narrow the `contentsOf:` ban to URL-loading initialisers (allowed only in the allowlisted file-repository file(s)); allow `append(contentsOf:)` / `insert(contentsOf:at:)`. **The `contentsOf:` part is superseded by D-024 (Q23).** | Close URL-from-string gaps (P-2); free harmless collection calls. | Product Owner | D-019 (`contentsOf:` part) |
| D-019 | 2026-11-20 | Q18 (review Q-R2). Add `getStreamsToHost`, `InputStream(`/`OutputStream(`, `URL(string:`, `arc4random*`, `drand48`/`erand48`/`lrand48`/`srand48`, `rand(`, `random()` to the AC-M1-23 list. `contentsOf:` is banned except in the JSON file repository's file(s), named in a fixed allowlist. | P-2 and determinism. Tightening only. | Product Owner | — |
| D-018 | 2026-11-20 | Q17 (review Q-R1). `AsyncStream(` and `AsyncThrowingStream(` are exempt from the `Stream(` pattern. Exactly these two; any further exemption needs a PO decision, never a Developer allowlist. | Swift concurrency types; they send nothing off the device (P-2). | Product Owner | — |
| D-017 | 2026-11-20 | Q16. Scan scope: AC-M1-02 matches whole tokens after a camelCase / underscore / digit split, in identifiers and string literals only; comments are excluded. The banned API list is the closed list in AC-M1-23. | Testable scans without false hits like `template` or `latest` (UX-3, P-2). | Product Owner | — |
| D-016 | 2026-11-20 | Q15. Degenerate inputs are model invariants, rejected at construction and on decode (AC-M1-25), never silently repaired: non-empty dayparts and weekdays; `windowEnd > windowStart`; recurring has interval ≥ 1 day, non-recurring has none; not both critical and deep clean; `maintenance` only on deep cleans; `resurfaced` only on criticals. The M2 parser must map onto these. | Every outcome must be defined for the oracle (Tester T-04). | Product Owner | — |
| D-015 | 2026-11-20 | Q14. Next eligible window `E(a, D)`: start at `a` if `a` is in an allowed slot, else at the start of the next allowed slot; keep the original duration `D`. All kinds move by this rule when a window ends (never skipped, never doubled); the recurrence interval applies only on completion, anchored at `now + interval` days. | A task given a week gets another week; nothing shrinks or grows (FR-B2, UX-3; Tester T-02). | Product Owner | — |
| D-014 | 2026-11-20 | Q13. Windows are half-open; `windowEnd == now` has ended. The selector is pure: a task whose window ended is not valid and the selector never reschedules. Callers run the rescheduler before selecting (M3 brief to require it). | One exact boundary rule (Tester T-03). | Product Owner | — |
| D-013 | 2026-11-20 | Q12. A deferral whose rest is over (`until ≤ now`) is treated exactly as `active` by the selector and becomes `active` in the rescheduler (then the ended-window rules apply). A resting deferral (`until > now`) is never shown and never touched, even if its window ended. | The user asked for rest; the engine honours it (UX-3; Tester T-01). | Product Owner | — |
| D-012 | 2026-11-20 | Q11. The night slot belongs to the day it starts (Saturday 22:00 to Sunday 05:00 is Saturday night). A nonexistent local time (DST spring-forward) resolves to the next instant; a repeated one (fall-back) to its first occurrence. | Matches how people talk; deterministic DST (Tester T-02). | Product Owner | — |
| D-011 | 2026-11-20 | Q10. Project generation is a technical decision: see ADR-0003 (Proposed: XcodeGen), to be accepted when the app target is created (M3 at the latest). | Technical choice, owned by the Developer. | Product Owner (delegated to ADR) | — |
| D-010 | 2026-11-20 | Q9. The app persistence store is a technical decision: see ADR-0002 (Proposed: Core Data + `NSPersistentCloudKitContainer`, fallback `CKSyncEngine`). M1 ships only the repository protocol, an in-memory store and a JSON file store. | Technical choice, with FR-E1 (M5) in mind. | Product Owner (delegated to ADR) | — |
| D-009 | 2026-11-20 | Q8. The engine takes weather as an injected value and never fetches it in M1. A real source needs the owner's confirmation and an ADR first. **Resolved by D-023 (Q22).** | P-2. | Product Owner | — |
| D-008 | 2026-11-20 | Q7. Now ranking is an exact key: `resurfaced` first, then earliest `windowEnd`, then critical before non-critical, then ascending `UUID.uuidString`. No randomness in M1. Richer scoring later must keep AC-M1-13…16. | Deterministic and testable (UX-2; Tester T-07). | Product Owner | — |
| D-007 | 2026-11-20 | Q6. Critical items do not bypass the energy, daypart or weekday filters. They win on ranking, not by breaking the filter. | Same validity rules for every task (FR-B1). | Product Owner | — |
| D-006 | 2026-11-20 | Q5. Maintenance mode: a deep clean is treated as a light, low-effort version on its next eligible window; its stored effort is kept; completing it ends maintenance mode. User-facing wording is M3. | FR-B2, UX-3. | Product Owner | — |
| D-005 | 2026-11-20 | Q4. The signal for maintenance mode is any ended window of a non-critical deep clean. No weekly load metric in M1; revisit with real usage in M3/M5. | Simple, testable rule (FR-B2). | Product Owner | — |
| D-004 | 2026-11-20 | Q3. A weather-dependent task is weather-safe only in `clear` or `cloudy`. `wet`, `severe` and `unknown` exclude it. Weather never affects rescheduling. | Never send someone outside on a guess (FR-B1). | Product Owner | — |
| D-003 | 2026-11-20 | Q2. Dayparts in the injected zone: morning 05–12, afternoon 12–17, evening 17–22, night 22–05. Tasks default to non-night. | Quiet nights protect UX-3. | Product Owner | — |
| D-002 | 2026-11-20 | Q1. Energy to effort: Low → Low only; Normal → Low + Normal; High → all. Maintenance mode counts as Low. | FR-B1. | Product Owner | — |
```

## Law check

| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry UI in M1. The docs describe no form. |
| UX-2 Rule of Three | pass | Traced to AC-M1-13…16 (and AC-M1-21 (f)); the overview explains the type-level cap; the explanation page says "no more than three" and never describes a longer list. |
| UX-3 Zero-Guilt | pass | Traced to AC-M1-02, 03, 17…21, 25 and D-1…D-3. User-facing pages use none of the banned words and never describe tasks as late. |
| UX-4 Design craft | n.a. | No UI in M1. Docs use headings, and every Mermaid diagram has a text version. |
| P-1 On-device inference | n.a. | No AI in M1. The engine is Foundation-only (AC-M1-23); traced and documented. |
| P-2 No data leaves device (except user iCloud) | pass | Traced to AC-M1-23, AC-M1-04…07 and the W2-F1 tests. Weather is injected only; the WeatherKit ADR is listed as planned (Q22). No privacy page is needed yet: there is no app, no Privacy Manifest and no App Store label in M1. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud use. |
| P-4 Media not persisted without consent | n.a. | No media in M1. |

## Handoff log

| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Acceptance Tester | Product Documenter | received | acceptance.md at `0a9eb87`: PASS 25/25, no device AC. |
| 2026-11-20 | Product Documenter | Product Owner (H7) | **accepted — Docs complete** | Traceability, changelog, ADR index, overview, explanation pages and release notes done. Suite rerun: 127 tests / 17 suites, 0 warnings. Follow-ups F-1…F-8 do not block. Decisions D-002…D-028 ready to paste (human merge). Next: PO gate and `STATUS.md`. |
