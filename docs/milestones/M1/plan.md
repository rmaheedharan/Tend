# M1 Work Plan — Core Engine & Cognitive Shielding

- **Owner:** Work Planner  ·  **Brief:** [brief.md](brief.md) (v2, Tester testability review ticked 2026-11-20)  ·
  **Design:** [design.md](design.md) (`Ready`, APPROVED WITH MINOR, D-1…D-3 binding)  ·  **Status:** Ready (WI-M1-01
  is Ready now; WI-M1-02…04 become Ready as each predecessor is merged)
- **Requirements:** FR-B1, FR-B2, FR-B3 (data only), UX-2, UX-3, P-1, P-2; CLAUDE.md §3. ACs: AC-M1-01…25.
- **Milestone lock:** M1 is the first milestone. No earlier milestone has to be `ACCEPTED`, so the lock is satisfied.
  `STATUS.md` still shows M1 `NOT-STARTED`. The PO should set it to `PLANNING` now and to `IN-BUILD` before WI-M1-01
  starts. This is a bookkeeping step, not a DoR failure.
- **Verification environment:** every item is verified with `swift test --package-path Packages/TendCore` in the Linux
  container (Swift 6.2.4) and in Linux CI (`.github/workflows/ci.yml` on `origin/main`, `swift:6.2-noble`, build and
  test with `-warnings-as-errors`). No macOS, Xcode, Simulator or device is needed or available in M1. No AC needs a
  device (brief, Tester review).

## Work items

Four items, one PR each, in a **linear chain**. Each PR branches from `main` after the previous PR has been merged by
the Merge Gatekeeper.

| ID | Title | Stories / ACs (owner ●, also exercised ○) | Size | Depends on | Design spec | Owner | Branch | DoR |
|---|---|---|---|---|---|---|---|---|
| WI-M1-01 | `TendCore` package scaffold, domain model, invariants, source-scan guards, foundation ADRs | S-M1-01, S-M1-06 · ● AC-M1-01, ● AC-M1-02, ● AC-M1-23, ● AC-M1-25 (construction and `Codable` decode) | M (≤ 1 day) | [design.md](design.md) = `Ready` (H3) ✔ | [design.md](design.md): binding naming list (model, enums, `TaskInvariantViolation`, `PromptTone`), forbidden names, D-1, D-2 | Developer | `m1/core-model` | ☑ Ready |
| WI-M1-02 | Persistence: `HouseholdRepository` protocol, in-memory and JSON file stores, seeded test generators | S-M1-02 · ● AC-M1-04, ● AC-M1-05, ● AC-M1-06, ● AC-M1-07 · ○ AC-M1-25 (decode path through the repository) · ○ AC-M1-02 (new error names) | M (≤ 1 day) | WI-M1-01 merged | [design.md](design.md): repository and `HouseholdStoreError` names, store-error copy rule (codes only) | Developer | `m1/persistence` | ☑ (when WI-M1-01 is merged) |
| WI-M1-03 | Slot calendar and `E(a, D)`, context filter (validity), `NowSelection` and the Rule-of-Three selector, gate property tests | S-M1-03, S-M1-04 · ● AC-M1-08, ● AC-M1-09, ● AC-M1-10, ● AC-M1-11, ● AC-M1-12, ● AC-M1-13, ● AC-M1-14, ● AC-M1-15, ● AC-M1-16 | M (≤ 1 day) | WI-M1-02 merged (reuses the seeded household generator) | [design.md](design.md): `Moment`, `NowSelection`, `NowSelector` names; UX-2 bypass ban; D-3 | Developer | `m1/rule-of-three-selector` | ☑ (when WI-M1-02 is merged) |
| WI-M1-04 | Completion, compassionate rescheduler (R0–R4), determinism, gate property tests, M1 green run | S-M1-01, S-M1-05, S-M1-06 · ● AC-M1-03, ● AC-M1-17, ● AC-M1-18, ● AC-M1-19, ● AC-M1-20, ● AC-M1-21, ● AC-M1-22, ● AC-M1-24 | M (≤ 1 day) | WI-M1-03 merged (uses `E(a, D)`, the selector and the validity oracle) | [design.md](design.md): `Rescheduler`, `complete(_:at:)`, `RescheduleOutcome` codes, `PromptTone.gentle`, D-1, D-2, D-3 | Developer | `m1/compassionate-rescheduler` | ☑ (when WI-M1-03 is merged) |

**AC coverage check:** 25 of 25 ACs have exactly one owning item (●). No orphan ACs. Every item owns at least one AC.
AC-M1-02 and AC-M1-23 are owned by WI-M1-01, but the scan tests run on every later PR over the growing `Sources/`
tree. So WI-M1-02…04 must also stay clean, and the Reviewer checks this per PR. AC-M1-24 is owned by WI-M1-04 because
it is proven on the **M1 merge commit**. Every earlier PR must also keep 0 failures, 0 skips and 0 warnings in CI.

### Scope notes per item (what "done" contains; ACs stay as the PO wrote them)

**Applies to every item** ([design.md](design.md), binding):
- Public `TendCore` names follow the design's **binding naming list**. A deviation is allowed only with the reason in
  `dev-notes.md`, and the new name must pass the naming list and the forbidden list.
- No **design-forbidden** names (Reviewer-enforced, not scanned). These include `urgent`/`urgency`/`severity`
  (`severe` is allowed only as a `WeatherCondition` case), `escalat*`, `nag`, `alarm`, `alert`, `warning`,
  `neglected`, `stale`, `abandoned`, `slipped`, `lapsed`, `isDue`/`dueState`, `downgrade` and `demote`.
- **D-1:** code says the rest **ended** (`isRestOver(at:)`, `restEnded`), never "lapsed". This also applies to test
  names and log lines that become acceptance evidence. Never use "missed" there either; say "window ended".
- **D-2:** no original-window fields, counters or history (`rescheduleCount`, `deferCount`, `timesMoved`,
  `originalWindowStart`/`End`, `firstWindow`, `initialDueDate`, reschedule history arrays). A violation is a Blocker.
- **D-3:** no `priority`, `score` or `weight` that grows with time. Ranking is the fixed AC-M1-16 key. A violation is
  a Blocker.
- **UX-2 bypass ban:** no public `allValidTasks`, `candidates`, `nextUp`, `queue`, `backlog` or `todo` API.
- `TendCore` holds no user-facing copy, only codes. Copy keys are reserved for the M3 String Catalog.

**WI-M1-01 — `m1/core-model`**
- `Packages/TendCore/Package.swift`: Swift 6 language mode, strict concurrency, one library target `TendCore` (imports
  only `Foundation`), one test target `TendCoreTests` using Swift Testing.
- Model, using the names in the design naming list:
  - `HouseholdTask` with exactly the listed members (`id`, `title`, `kind`, `roomID`, `effort`, `isCritical`,
    `isDeepClean`, `isWeatherDependent`, `allowedDayparts`, `allowedWeekdays`, `windowStart`, `windowEnd`,
    `recurrenceIntervalDays`, `state`, `completedAt`) and **no other stored field** (D-2).
  - `TaskKind`, `TaskState` (exactly `active`, `deferred(until:)`, `maintenance`, `resurfaced`, `completed`),
    `Effort`, `EnergyLevel`, `Daypart`, `Weekday`, `WeatherCondition`, `Room` (`lastTendedAt`), `Household`
    (`schemaVersion`), and `PromptTone` with **one case** `gentle`.
  - Effective-state helpers `isResting(at:)`, `isRestOver(at:)`, `windowIsOpen(at:)` and `windowHasEnded(at:)` (D-1).
  - Everything is `Equatable`, `Codable` and `Sendable`.
- Invariants are checked by a throwing initialiser **and** in `init(from:)`, using `TaskInvariantViolation` with the
  nine cases in the naming list (AC-M1-25). The repository wrapping of that error is WI-M1-02.
- A test asserts that `PromptTone` has exactly one case. This is a design-review check.
- Source-scan test helper, used by AC-M1-02 and AC-M1-23. It strips comments and is string-literal aware, including
  multi-line `"""` and raw strings (**N-2**). It tokenises identifiers and literals. The API patterns are matched at
  identifier boundaries (**N-1**: `startDate()` is not `Date()`). Negative tests run against in-memory fixture strings
  for every banned token, every banned pattern, the N-1 near-miss and the N-2 comment-in-string cases. The test log
  prints the number of files scanned (> 0).
- ADRs in `docs/architecture/adr/`:
  - **ADR-0001** `TendCore` module boundary: Foundation-only, injected `now`/calendar/time zone/weather/RNG, Linux-first
    tests, the future `TendAI` / `TendPersistence` / `TendUI` split.
  - **ADR-0002** App persistence store (SwiftData vs Core Data) for later CloudKit `CKShare` sharing (Q9, FR-E1). This
    is a decision only; no adapter ships in M1.
  - **ADR-0003** Project generation, XcodeGen vs Tuist (Q10). It may be marked `Proposed` until M3, but the options
    analysis lands now so M3 is not blocked.
- `CLAUDE.md` §7 is a protected path, so the Developer must **not** edit it. The commands it already lists match this
  layout.

**WI-M1-02 — `m1/persistence`**
- `HouseholdRepository` protocol, with `InMemoryHouseholdRepository` and the Foundation-only
  `JSONFileHouseholdRepository`. The file store has a schema version, atomic replace-on-write and an injectable write
  seam for fault injection (AC-M1-07).
- Load errors are typed as `HouseholdStoreError`: `unreadableFile`, `unsupportedSchemaVersion(Int)`,
  `invalidTask(TaskInvariantViolation)` and `writeUnsuccessful` (AC-M1-06, AC-M1-07, AC-M1-25; design naming list).
- Dates must round-trip exactly, including sub-second components (AC-M1-05). The default ISO-8601 strategy loses
  precision. Choose an exact encoding and record the choice in dev notes, or in ADR-0004 if it sets the file format.
- Test support: a seeded deterministic RNG (e.g. SplitMix64) and a **valid-only** task/household generator covering
  every kind, flag, state, daypart/weekday set and window position. Later items reuse it. Seeds are fixed and printed
  on failure.
- One contract suite parameterised over both implementations (AC-M1-04).

**WI-M1-03 — `m1/rule-of-three-selector`**
- Slot calendar on the injected `Calendar` and `TimeZone`:
  - daypart and slot membership, with night owned by its start day (Q11);
  - DST policy `.nextTime` / `.first`;
  - `E(a, D)`, unit-tested here because it is the shared basis for WI-M1-04 and AC-M1-03(b).
- Validity filter per the brief's definitions: effective state, half-open window, allowed slot, energy match with
  maintenance counted as Low, and weather-safe.
- `Moment` (or `SelectionContext`) with `now`, `calendar`, `timeZone`, `weather` and `energy`.
- `NowSelection`, with `items`, `isEmpty` and `static let capacity = 3`; the cap is enforced by the type (AC-M1-13).
- `NowSelector.select(from:in:) -> NowSelection`. This is the only public "what to do now" API, and candidate arrays
  stay `internal`/`private`. The selector is pure, never mutates and never reschedules (Q13).
- Ranking uses the exact four-key sort (AC-M1-16), with no score field (D-3).
- `nextEligibleWindow(from:duration:)` is the public name for `E(a, D)`.
- An **independent oracle** in the test target for validity and ranking (AC-M1-14, 16). It must be written apart from
  the production logic, not by calling it.
- The public API listing for AC-M1-13 goes in `dev-notes.md`.

**WI-M1-04 — `m1/compassionate-rescheduler`**
- Completion `complete(_:at:)` (AC-M1-03), including the recurring `E(now + interval days, D)` case and room
  `lastTendedAt`.
- `Rescheduler.reschedule(_:at:calendar:timeZone:) -> Household` applying R0–R4 in binding order. R1 is "rest ended"
  (D-1). Resurfaced criticals use the fixed `PromptTone.gentle` and carry no escalation field (AC-M1-18).
- If per-task outcomes are exposed, the only codes are `RescheduleOutcome`: `unchanged`, `restEnded`, `lightened`,
  `broughtBackGently` and `movedToNextWindow`.
- Nothing records how often or how far a task moved (D-2).
- An independent R0–R4 oracle in the test target (AC-M1-21(d)), the N-pass structure test (AC-M1-20) and the
  determinism property (AC-M1-22). The engine takes an injected RNG to meet the input contract but must not use it.
- Final CI run on the M1 merge commit with test count, 0 skipped and 0 warnings (AC-M1-24). The Developer gives the
  AC→test table in `dev-notes.md`; the Tester carries it into `acceptance.md`.

## Order of work (critical path)

`design.md` (Designer naming review, in parallel now) → **WI-M1-01** → **WI-M1-02** → **WI-M1-03** → **WI-M1-04** →
review/acceptance

1. **WI-M1-01 first.** It holds the foundations and the riskiest product law: the zero-guilt data model (UX-3) and the
   guards (AC-M1-02, AC-M1-23) that protect every later PR. The ADRs come first, as the skill requires. The Designer's
   binding naming list ([design.md](design.md)) is now issued, so names are frozen before code exists.
2. **WI-M1-02 second.** Persistence depends only on the model. It also builds the seeded valid-household generator
   that the gate property tests in WI-M1-03 and WI-M1-04 need.
3. **WI-M1-03 third.** The selector needs the model and generator. It also delivers the slot calendar and `E(a, D)`,
   which the rescheduler and recurring completion depend on.
4. **WI-M1-04 last.** It needs `E(a, D)`, the selector (AC-M1-21(f)) and the validity oracle. It closes the
   determinism and green-run gates.

Parallelism is deliberately given up to cut PR overhead (Orchestrator instruction).

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-1 | The design naming review is late or renames states after code exists, which delays the whole chain. | — | — | **Closed 2026-11-20.** `design.md` is `Ready` with a binding naming list. A deviation needs a reason in dev notes. | iOS Designer |
| R-12 | Design-forbidden names and D-2/D-3 fields are **not** caught by the AC-M1-02 scanner, so they rely on human inspection. | M | H | Every PR's `dev-notes.md` lists the public API and the stored fields of `HouseholdTask`. The Reviewer and Gatekeeper check them against the [design.md](design.md) forbidden list. A D-2 or D-3 hit is a Blocker. The Designer runs the "Design review of build" table after WI-M1-04. | Reviewer; iOS Designer |
| R-2 | The source scanners are imprecise: false positives (`startDate()`, `template`) or misses (tokens in `"""` strings, comment markers inside strings). The guard then gives false comfort or blocks good code. | M | H | N-1 and N-2 are part of WI-M1-01 scope. Negative tests cover each planted pattern and near-miss. The Reviewer inspects the tokenizer. | Developer (Reviewer checks) |
| R-3 | DST and time zone edge cases (nonexistent 02:30, repeated 01:30, a night slot across midnight) behave differently in Foundation on Linux than on Darwin. | M | H | Use only the injected `Calendar`/`TimeZone` with explicit `.nextTime`/`.first` policies. Use named zones (tzdata is present). Run the DST cases in AC-M1-09/10/17/03 on Linux CI. Record any Darwin difference as a risk for M3. | Developer |
| R-4 | The "independent" oracles copy production logic, so the gate tests prove nothing. | M | H | Oracles live in the test target and are written straight from the brief's definitions without calling production helpers. The Reviewer checks independence. The Tester adds cases of its own (DST, far-future `now`, 0-task and all-invalid). | Developer; Reviewer; Acceptance Tester |
| R-5 | Property tests (≥ 1,000 households × up to 500 tasks; ≥ 500 for the rescheduler; 100× determinism) are too slow for the CI 20-minute timeout. | M | M | Use a fast seeded RNG and avoid quadratic oracles. Measure locally per PR and record the runtime in dev notes. Do not lower the counts the ACs require. If CI time is tight, ask the human owner to raise the timeout (`.github/**` is protected). | Developer |
| R-6 | CI passes vacuously: `ci.yml` exits 0 when `Packages/TendCore/Package.swift` is missing, and a mis-pathed package would show green. | L | H | WI-M1-01 creates the package at exactly `Packages/TendCore`. The Reviewer and Gatekeeper confirm from the CI log that tests ran (count > 0). | Developer; Merge Gatekeeper |
| R-7 | Date round-trip loses sub-second precision with the default `JSONEncoder` date strategy, so AC-M1-05 fails. | H | M | Choose an exact encoding up front in WI-M1-02 (e.g. `timeIntervalSinceReferenceDate` as a `Double` written bit-exact, or a custom strategy), and test that it is bit-exact. | Developer |
| R-8 | Atomic write behaves differently on Linux Foundation (`.atomic` / `replaceItemAt`), so AC-M1-07 could be flaky. | L | M | Use an injectable write seam for fault injection and a temp-file-then-rename pattern. Test on Linux CI. | Developer |
| R-9 | The local working branch is behind `origin/main`: it lacks `ci.yml` (PR #2). A PR cut from a stale base would miss CI or conflict. | H | L | Every WI branch starts from a fresh `origin/main`. The Orchestrator rebases or recreates the brief/plan branch before opening its PR. | Orchestrator |
| R-10 | The WeatherKit/P-2 question (Q8) is still open at the M1 gate. | M | L | It does not block the build because weather is an injected enum. The human owner must answer before M1 closes, as the brief requires. | Product Owner → human owner |
| R-11 | WI-M1-03 and WI-M1-04 are at the upper bound of ≤ 1 day each, because each carries an oracle plus gate property tests. | M | M | If either runs past one round, split it: WI-M1-03 into a slot-calendar/validity part and a selector part; WI-M1-04 into completion plus rescheduler and determinism plus gates. The Planner re-plans; the ACs stay the same. | Work Planner |

## Verification environments

All ACs can be proven on **Linux** (container `swift test`, Swift 6.2.4) and on **Linux CI** (`swift:6.2-noble`,
`-warnings-as-errors`). Neither macOS CI, the Simulator nor a device is needed or available for M1.

| AC | Where it can be proven (Linux / macOS CI / Simulator / Device) | Owning item |
|---|---|---|
| AC-M1-01 | Linux + Linux CI | WI-M1-01 |
| AC-M1-02 | Linux + Linux CI (source scan; re-runs on every PR) | WI-M1-01 |
| AC-M1-03 | Linux + Linux CI (includes a DST day; needs tzdata) | WI-M1-04 |
| AC-M1-04 | Linux + Linux CI | WI-M1-02 |
| AC-M1-05 | Linux + Linux CI (property, fixed seeds) | WI-M1-02 |
| AC-M1-06 | Linux + Linux CI | WI-M1-02 |
| AC-M1-07 | Linux + Linux CI (fault injection) | WI-M1-02 |
| AC-M1-08 | Linux + Linux CI | WI-M1-03 |
| AC-M1-09 | Linux + Linux CI (named time zones) | WI-M1-03 |
| AC-M1-10 | Linux + Linux CI (named time zones) | WI-M1-03 |
| AC-M1-11 | Linux + Linux CI | WI-M1-03 |
| AC-M1-12 | Linux + Linux CI | WI-M1-03 |
| AC-M1-13 | Linux + Linux CI, plus Reviewer API inspection | WI-M1-03 |
| AC-M1-14 (Gate) | Linux + Linux CI (property, ≥ 1,000 households) | WI-M1-03 |
| AC-M1-15 | Linux + Linux CI (property) | WI-M1-03 |
| AC-M1-16 | Linux + Linux CI | WI-M1-03 |
| AC-M1-17 | Linux + Linux CI (includes DST and night-slot cases) | WI-M1-04 |
| AC-M1-18 | Linux + Linux CI | WI-M1-04 |
| AC-M1-19 | Linux + Linux CI | WI-M1-04 |
| AC-M1-20 (Gate) | Linux + Linux CI (property) | WI-M1-04 |
| AC-M1-21 (Gate) | Linux + Linux CI (property, ≥ 500 households) | WI-M1-04 |
| AC-M1-22 | Linux + Linux CI (property) | WI-M1-04 |
| AC-M1-23 | Linux + Linux CI (source scan and build; re-runs on every PR) | WI-M1-01 |
| AC-M1-24 (Gate) | Linux CI on the M1 merge commit (link + log) | WI-M1-04 |
| AC-M1-25 | Linux + Linux CI (construction in WI-M1-01; decode through the repository in WI-M1-02) | WI-M1-01 |

## Definition of Ready check

| Check | WI-M1-01 | WI-M1-02 | WI-M1-03 | WI-M1-04 |
|---|---|---|---|---|
| Cites requirement IDs and AC IDs | ☑ | ☑ | ☑ | ☑ |
| ACs are testable and the verification type is known | ☑ | ☑ | ☑ | ☑ |
| Design spec exists and is `Ready` (if UI/copy/naming) | ☑ [design.md](design.md) `Ready` | ☑ [design.md](design.md) | ☑ [design.md](design.md) | ☑ [design.md](design.md) (tone-marker wording is M3) |
| Dependencies merged or stubbed behind a protocol | ☑ (none in code) | ☐ until WI-M1-01 is merged | ☐ until WI-M1-02 is merged | ☐ until WI-M1-03 is merged |
| Size ≤ 1 day; owner named; branch named | ☑ | ☑ | ☑ (see R-11) | ☑ (see R-11) |
| Milestone lock satisfied | ☑ (M1 is first) | ☑ | ☑ | ☑ |

**Build start:** **WI-M1-01 is Ready** (re-checked 2026-11-20 after [design.md](design.md) reached `Ready`, H3).
The build hold is lifted. WI-M1-02…04 fail only the "dependencies merged" box, and each becomes Ready when its
predecessor is merged. No other DoR problem was found.

## Law check

| Law | Status (pass / n.a. / concern) | Note — items reviewers should watch |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry UI. Watch WI-M1-01: model initialisers must not grow into a required multi-field "new task" shape that M3 would surface as a form. Defaults are fine. |
| UX-2 Rule of Three | pass (watch) | WI-M1-03: the only "what now" API returns `NowSelection` (capacity 3 by type). The Reviewer must reject any public API returning `[HouseholdTask]` for "now", including a "candidates" or "debug" helper. |
| UX-3 Zero-Guilt | pass (watch) | Design D-1…D-3 are binding on all items. WI-M1-01: closed state set, no passed-window counter, no original-window fields, banned-token scan. WI-M1-02: error names (`writeUnsuccessful`). WI-M1-04: no escalation field, no "times rescheduled" counter, no structure growth (AC-M1-20). Watch for an "overdue" or "late" filter or a helper such as `isPastDue` sneaking in. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI in M1. |
| P-2 No data leaves device | pass (watch) | Foundation-only, and the AC-M1-23 scan bans networking APIs and `http(s)://` literals. WI-M1-02: the file store writes only to a caller-supplied local URL. No weather fetching (Q8). |
| P-3 Cloud escalation | n.a. | No cloud path. |
| P-4 Media not persisted | n.a. | No media. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Product Owner | Work Planner | accepted (H1) | Brief v2: 6 stories and 25 ACs, all citing FR/UX/P IDs, all Given/When/Then, and the Tester testability review is ticked. Nits N-1 and N-2 are carried into WI-M1-01 scope. Milestone lock satisfied (M1 is first). The PO should move M1 in `STATUS.md` to `PLANNING`, then `IN-BUILD`. |
| 2026-11-20 | Work Planner | iOS Designer, Developer | sent (H2) | 4 linear work items with every AC owned exactly once. WI-M1-01 is held on `design.md` = `Ready` (naming review of states, error cases and tone marker). WI-M1-02…04 become Ready as each predecessor merges. All verification is on Linux and Linux CI. Branches must start from fresh `origin/main` (R-9). |
| 2026-11-20 | iOS Designer | Work Planner | accepted (H3) | [design.md](design.md) `Ready`, APPROVED WITH MINOR. The binding naming list, forbidden names and D-1…D-3 are folded into every item's scope ("Applies to every item" plus per-item notes). New risk R-12 (scanner blind spots); R-1 closed. DoR re-checked: **WI-M1-01 Ready**, build hold lifted. WI-M1-02…04 Ready on merge of their predecessor. |
