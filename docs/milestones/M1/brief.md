# M1 Brief — Core Engine & Cognitive Shielding

- **Owner:** Product Owner  ·  **Status:** Ready for planning
- **PRD scope:** *M1: Core Engine & Cognitive Shielding* — Household data persistence, the "Rule of Three" selection
  algorithm, energy/time filtering, and compassionate rescheduling logic. (No UI or AI yet.)
  Gate: • Automated unit test suite passes 100%. • Tests prove: given 50+ mixed tasks, the engine always returns ≤ 3
  contextually valid items. • Tests prove: missed tasks reschedule smoothly without generating overdue debt states.
- **Requirements in scope:** FR-B1 (selection engine, not the canvas), FR-B2 (rescheduling logic), UX-2 (enforced in
  the engine API), UX-3 (enforced in the data model), FR-B3 (data only: a per-room "last tended" timestamp),
  P-1/P-2 (engine is local and Foundation-only), CLAUDE.md §3 (pure `TendCore`, injected `now`/calendar/weather/RNG).
- **Out of scope (explicit):**
  - Any UI, copy rendering, haptics, motion, widgets, Live Activities, App Intents — the Now canvas view is **M3**,
    system surfaces are **M4**. (UX-4 is n.a. in M1.)
  - Any AI: brain-dump parsing, effort/room inference, duplicate detection (FR-A1, M2); camera and Share Sheet
    (FR-A2, FR-A3, M4). M1 tasks are created programmatically in tests and fixtures.
  - Sprint builder / 15-Minute Reset (FR-C1, FR-C2, FR-C3) — **M3**. Estimated minutes per task are deferred to the M3
    brief.
  - Room Pulse view and warmth/tint mapping (FR-B3 view) — **M3**. M1 stores only `lastTendedAt` per room.
  - Room proximity as a selection signal (FR-B1 "room proximity") — not modelled in M1; revisit in the M3 brief.
  - Load balancing and assignees (FR-E2) — **M5**. CloudKit, `CKShare`, multi-device sync (FR-E1) — **M5**.
  - SwiftData / Core Data adapters and the store choice — a Developer ADR during M1; adapters ship when the app target
    exists (M3) and sharing lands in M5.
  - Fetching real weather (WeatherKit) — weather is an injected input only (see open question Q8).
  - Notifications of any kind, including the wording of the "gentle resurface" prompt — **M3** (copy) / **M4**.

## Outcome
At the end of M1 the household "brain" exists and is proven on Linux: a `TendCore` engine that can hold a household's
tasks and rooms, save and reload them without losing anything, and — given the moment (`now`, calendar, weather) and
the user's energy — return **at most three** things that genuinely make sense to do right now. When life gets busy
and a task's window passes, the engine quietly renegotiates: deep cleans step down to maintenance mode, critical
items (a bill, food about to expire) come back gently, everything else moves to its next sensible window — and
nothing anywhere in the model ever counts, stores, or names lateness. This is the foundation every later surface
(Now canvas, widget, Live Activity, sprint) reads from, so the Rule of Three and Zero-Guilt are guaranteed by the
engine's types rather than by each screen remembering to behave.

## Definitions used in this brief (product meaning, binding for M1)
All intervals below are half-open `[start, end)`. All wall-clock times are resolved in the **injected** calendar
(Gregorian in tests) and time zone. A nonexistent local time (DST spring-forward) resolves to the next existing
instant; a repeated local time (DST fall-back) resolves to its first occurrence (Foundation `.nextTime` /
`.first` policies). See Q11.

- **Daypart:** morning `[05:00, 12:00)`, afternoon `[12:00, 17:00)`, evening `[17:00, 22:00)`, night
  `[22:00, 05:00 next day)`. A task has a non-empty set of allowed dayparts; default is morning + afternoon + evening
  (night is quiet unless a task explicitly allows it). See Q2.
- **Slot:** one daypart on one calendar day `d`, e.g. "Saturday morning". The night slot of day `d` runs from 22:00 on
  `d` to 05:00 on `d + 1` and **belongs to day `d`'s weekday** (so 01:00 on Sunday is in Saturday's night slot). A task
  has a non-empty set of allowed weekdays. An **allowed slot** for a task is a slot whose daypart is allowed and whose
  owning day's weekday is allowed. See Q11.
- **Energy match:** Low energy → Low-effort tasks only; Normal → Low + Normal; High → Low + Normal + High. A task in
  `maintenance` counts as Low effort (its stored effort is unchanged). See Q1.
- **Weather-safe:** a weather-dependent task is valid only when the injected weather is `clear` or `cloudy`. `wet`
  (rain/snow), `severe` (storm/extreme heat/cold) and `unknown` (no weather supplied) exclude it. Tasks that are not
  weather-dependent ignore weather. Weather never affects rescheduling (future weather is unknown). See Q3.
- **Effective state at `now`:** a task in `deferred(until: u)` with `u ≤ now` (a **lapsed deferral**) is treated
  exactly as `active` by the selector and the rescheduler. A task in `deferred(until: u)` with `u > now` is
  **resting**: never valid, never touched by the rescheduler. See Q12.
- **Window open:** `windowStart ≤ now < windowEnd`.
- **Window passed:** `windowEnd ≤ now` (inclusive: `windowEnd == now` is passed), and the task is neither `completed`
  nor resting. (The PRD gate line says "missed tasks"; code and data model must not use that word — see AC-M1-02.)
- **Contextually valid at `now`** = all of: effective state is `active`, `maintenance` or `resurfaced`; window open;
  `now` lies in an allowed slot; energy match; weather-safe. Completed and resting tasks are never valid. A task whose
  window has passed is **not** valid until the rescheduler has moved it; the selector never mutates and never
  reschedules. See Q13.
- **Next eligible window from anchor `a`**, written `E(a, D)`, where `D = windowEnd − windowStart` of the task
  (absolute seconds, preserved exactly): new `windowStart = s`, where `s = a` if `a` lies in an allowed slot, otherwise
  `s` = the start of the earliest allowed slot that begins after `a`; new `windowEnd = s + D`. The rescheduler uses
  `a = now` for every kind (one-off, recurring, restock alike: a passed occurrence is never skipped or doubled, it
  simply moves). Completing a recurring task uses `a = now + interval` calendar days (same wall-clock time, injected
  calendar). See Q14.
- **Critical** = a task flagged critical (e.g. paying a bill, food about to expire). **Deep clean** = a task flagged as
  deep clean; a task cannot be both (AC-M1-25). Flags are set by whoever creates the task (tests in M1, AI in M2).
- **Model invariants** (enforced at construction and on decode, AC-M1-25): allowed dayparts non-empty; allowed weekdays
  non-empty; `windowEnd > windowStart`; a recurring task has `interval ≥ 1` day and a non-recurring task has no
  interval; not both critical and deep clean; state `maintenance` only on a deep-clean task; state `resurfaced` only on a
  critical task. Random generators in property tests produce only valid tasks. See Q15.

## Stories

### S-M1-01 A household model that cannot express debt  (FR-B1, FR-B2, FR-B3, UX-3)
As a busy household member, I want Tend to remember my tasks and rooms without ever keeping score of what I didn't
get to, so that opening the app never feels like opening a bill.

**Acceptance criteria**
- **AC-M1-01** Given the `TendCore` public model, when a test constructs one task of each kind (one-off errand,
  recurring maintenance, consumable restock), each with optional room, effort (Low/Normal/High), critical flag,
  deep-clean flag, weather-dependent flag, allowed dayparts, allowed weekdays, window start/end, optional recurrence
  interval (days) and a lifecycle state, then every combination allowed by the model invariants is representable and
  `Equatable`/`Codable` (invalid ones are rejected per AC-M1-25), and a
  `Room` carries an optional `lastTendedAt`.  *Verification:* unit  *Evidence expected:* Swift Testing test name(s) +
  Linux `swift test` log.
- **AC-M1-02** Given all `.swift` files under `Packages/TendCore/Sources/`, when a source-scan test removes comments
  (line, block and doc comments are out of scope) and splits every remaining identifier and string literal into
  tokens (split on camelCase humps, `_`, digits and non-letters; compared case-insensitively as **whole tokens**, so
  `template` or `latest` are not hits), then no token equals *overdue, late, lateness, missed, failed, behind,
  penalty, debt, streak*; and the lifecycle state is a closed set of exactly `active`, `deferred(until:)`,
  `maintenance`, `resurfaced`, `completed`, with no counter of passed windows on any type. (Developer note: an error
  case such as `writeFailed` would be a hit; use e.g. `writeUnsuccessful`.)  *Verification:* unit (source scan)
  *Evidence expected:* test name + log listing files scanned (> 0) and zero hits; a negative test proving the scanner
  detects a planted token.
- **AC-M1-03** Given a task in room R at injected `now` in any non-completed state (incl. `maintenance`, `resurfaced`,
  `deferred`), when it is completed, then (a) a one-off or restock task becomes `completed` with `completedAt == now`
  and its other fields unchanged; (b) a recurring task becomes `active` (leaving `maintenance`/`resurfaced`/`deferred`),
  keeps its stored effort and flags, and its new window is exactly `E(now + interval days, D)`; (c) R's
  `lastTendedAt == now`; a task with no room changes no room.  *Verification:* unit (parameterised, incl. a DST-day
  case)  *Evidence expected:* test name + log.
- **AC-M1-25** Given each invariant in "Model invariants" (empty dayparts, empty weekdays, `windowEnd ≤ windowStart`,
  recurring without interval or with `interval < 1`, non-recurring with interval, critical + deep clean, `maintenance`
  on a non-deep-clean task, `resurfaced` on a non-critical task), when a task is constructed with that violation, then
  construction throws a typed error (or the failable initialiser returns `nil`), and when a JSON file containing that
  violation is loaded, the repository throws a typed error as in AC-M1-06.  *Verification:* unit (parameterised, one
  case per invariant)  *Evidence expected:* test name + log.

### S-M1-02 My household is kept safely on my device  (FR-B1, FR-B2, P-2; groundwork for FR-E1)
As a household member, I want everything Tend knows to survive a restart exactly as it was, so that I never re-enter
anything and never lose a reminder for a bill.

**Acceptance criteria**
- **AC-M1-04** Given the `HouseholdRepository` protocol, when one shared contract test suite (save, load, upsert task,
  remove task, update room) runs against the in-memory implementation and the Foundation-only JSON file
  implementation, then both pass every case.  *Verification:* unit (contract suite, parameterised by implementation)
  *Evidence expected:* test names for both implementations + log.
- **AC-M1-05** Given ≥ 200 seeded random households of valid tasks (0–500 tasks each, covering every task kind, flag,
  state, non-empty daypart/weekday set, and dates with sub-second components), when each is saved by the file repository and loaded by
  a **new** repository instance on the same file, then the loaded household equals the saved one (`==`) field for
  field, with dates exactly equal.  *Verification:* unit (property, fixed seeds)  *Evidence expected:* test name, seed
  list/range and household count in log.
- **AC-M1-06** Given a file that is corrupt (truncated / not JSON), declares an unknown schema version, or contains a
  task violating a model invariant (AC-M1-25), when it is
  loaded, then the repository throws a typed error, never returns an empty household, and the file's bytes are
  unchanged afterwards.  *Verification:* unit  *Evidence expected:* test name + log.
- **AC-M1-07** Given household A was saved successfully, when a later save of household B fails mid-way (injected
  write failure), then loading returns A intact (no partial or empty file).  *Verification:* unit (fault injection)
  *Evidence expected:* test name + log.

### S-M1-03 Only what fits this moment  (FR-B1)
As someone with limited energy and a specific moment in the day, I want Tend to consider only tasks that actually fit
my energy, the time, the day and the weather, so that what I'm shown is doable now.

**Acceptance criteria**
- **AC-M1-08** Given tasks of Low, Normal and High effort (and one High-effort deep clean in maintenance mode), when
  validity is evaluated at each energy state, then Low accepts only Low (incl. the maintenance task), Normal accepts
  Low + Normal, High accepts all.  *Verification:* unit (parameterised 3 × 4)  *Evidence expected:* test name + log.
- **AC-M1-09** Given tasks with different allowed dayparts, when validity is evaluated at the boundary times 04:59,
  05:00, 11:59, 12:00, 16:59, 17:00, 21:59, 22:00 local, and at one instant expressed in two injected time zones whose
  local dayparts differ, then the task is valid exactly when the local daypart is in its allowed set, and a task with
  default dayparts is never valid at night.  *Verification:* unit (parameterised)  *Evidence expected:* test name +
  log. Boundary instants are exact: 11:59:59.999 is morning, 12:00:00.000 is afternoon.
- **AC-M1-10** Given a task allowed only on Saturday and Sunday with all four dayparts allowed, when validity is
  evaluated at 10:00 local on each of the seven weekdays using an injected Gregorian calendar and time zone, then it is
  valid on Saturday/Sunday only; an instant that is Sunday 10:00 in one injected zone and Monday in another follows the
  injected zone; and 01:00 on Monday (Sunday's night slot) is valid while 23:00 on Friday is not and 01:00 on Saturday
  (Friday's night slot) is not.  *Verification:* unit  *Evidence expected:* test name + log.
- **AC-M1-11** Given a weather-dependent task and an otherwise identical non-weather task, when validity is evaluated
  for each injected weather value (`clear`, `cloudy`, `wet`, `severe`, `unknown`), then the weather-dependent task is
  valid only for `clear` and `cloudy`, and the non-weather task is valid for all five.  *Verification:* unit
  (parameterised)  *Evidence expected:* test name + log.
- **AC-M1-12** Given otherwise-valid tasks (open window, allowed slot, energy and weather match) that differ only in
  one of: (a) `completed`; (b) `deferred(until: now + 1 s)`; (c) `deferred(until: now)`; (d) `deferred(until: now − 1 h)`;
  (e) `windowStart == now`; (f) `windowStart == now + 1 s`; (g) `windowEnd == now`; (h) `windowEnd == now + 1 s`;
  (i) `windowEnd == now − 1 h`, when validity is evaluated, then (c), (d), (e) and (h) are valid and (a), (b), (f),
  (g) and (i) are not.  *Verification:* unit (parameterised)  *Evidence expected:* test name + log.

### S-M1-04 Never more than three  (UX-2, FR-B1)
As an overloaded parent, I want Tend to hand me at most three things, ever, so that I can act instead of triage.

**Acceptance criteria**
- **AC-M1-13** Given the public selection API, when a caller asks for Now items, then the only return type is
  `NowSelection`, whose capacity of 3 is enforced by the type (constructing one with 4+ items is impossible or throws
  / returns nil), and no public API in `TendCore` returns an unbounded list of "what to do now" items.
  *Verification:* unit (+ Reviewer API inspection)  *Evidence expected:* test that 4 items cannot be held + public API
  listing in dev notes.
- **AC-M1-14** **(Gate)** Given ≥ 1,000 seeded random households of 50–500 mixed valid tasks (every kind, flag, state
  incl. resting and lapsed deferrals, effort, non-empty daypart/weekday set, window not yet open / open / passed incl.
  `windowEnd == now`) and a random context per household (`now`, time zone, weather,
  energy), when Now items are selected, then every selection has ≤ 3 items, no duplicates, and every item passes an
  **independent oracle** implementation of the "contextually valid" definition written in the test target.
  *Verification:* unit (property, fixed seeds; the failing seed is printed on failure)  *Evidence expected:* test name,
  seed range, household count and min/max task count in log.
- **AC-M1-15** Given the same property households plus households of 0–49 tasks, when Now items are selected, then
  the count equals `min(3, number of contextually valid tasks)` — never padded with invalid tasks, never empty when a
  valid task exists — and an empty or all-invalid household returns an empty selection without error.
  *Verification:* unit (property)  *Evidence expected:* test name + log.
- **AC-M1-16** Given any set of valid candidates, when selection runs, then the returned items, in order, are the
  first `min(3, n)` candidates sorted by this exact key: (1) `resurfaced` before every other state (only critical tasks
  can be `resurfaced`, AC-M1-25); (2) earlier `windowEnd` first; (3) critical before non-critical; (4) ascending task ID
  (`UUID.uuidString`, lexicographic). No randomness is used in M1 ranking. Example cases include 5 resurfaced
  criticals (only 3 returned), equal `windowEnd` ties, and a mix where a non-resurfaced critical competes with a
  non-critical.  *Verification:* unit (examples + property against the oracle's sort)  *Evidence expected:* test name +
  log.

### S-M1-05 When life gets busy, Tend renegotiates quietly  (FR-B2, UX-3)
As someone whose week went sideways, I want tasks I didn't get to to rearrange themselves calmly, so that I come back
to a realistic plan, not a pile of debt.

**Acceptance criteria**
Rescheduling rules, applied by one pass at `now` to every task (rule order is binding):
R0 `completed` or resting → unchanged. R1 lapsed deferral → state becomes `active` (then R2–R4 apply if its window
passed; otherwise nothing else changes). R2 window passed and deep clean → state `maintenance`, window `E(now, D)`.
R3 window passed and critical → state `resurfaced`, window `E(now, D)`. R4 window passed, any other task → state
unchanged (`active`), window `E(now, D)`. In R2–R4 every other field (title, room, kind, stored effort, flags,
dayparts, weekdays, interval, ID) is unchanged. A task whose window is open or not yet open is unchanged (except R1).

- **AC-M1-17** Given a deep-clean task (state `active` or `maintenance`) whose window passed, when rescheduling runs at
  `now`, then its state is `maintenance` (counted as Low effort by the energy match, stored effort unchanged) and its
  window is exactly `E(now, D)`.  *Verification:* unit (incl. `windowEnd == now`, `now` inside / outside an allowed
  slot, a night slot crossing midnight, and a DST day)  *Evidence expected:* test name + log.
- **AC-M1-18** Given a critical task (bill / expiring food; state `active` or `resurfaced`) whose window passed, when
  rescheduling runs, then its state is `resurfaced`, its window is exactly `E(now, D)`, its stored effort is unchanged,
  and it carries no urgency/severity escalation field (the only prompt metadata allowed is a calm, fixed tone marker
  that never changes across passes; wording is M3).  *Verification:* unit  *Evidence expected:* test name + log.
- **AC-M1-19** Given any other task (not critical, not deep clean; one-off, recurring or restock) whose window passed,
  when rescheduling runs, then it stays `active` with window exactly `E(now, D)` and every other field unchanged.
  *Verification:* unit (parameterised by kind)  *Evidence expected:* test name + log.
- **AC-M1-20** **(Gate)** Given a task of each rule type (R2, R3, R4) whose window passes N consecutive times
  (N = 1…60; each time `now` advances to the task's current `windowEnd` and the rescheduler runs), when its **decoded**
  structure after N passes is compared with the structure after 1 pass, then the set of encoded keys is identical,
  every non-window field value is identical, every collection has the same count, and `windowEnd − windowStart` is
  identical; only `windowStart`/`windowEnd` differ. No field, count or collection grows with N. (Encoded byte size is
  not compared.)  *Verification:* unit (property)  *Evidence expected:* test name + log.
- **AC-M1-21** **(Gate)** Given ≥ 500 seeded households of 50–500 valid tasks in which at least half have passed
  windows (including `windowEnd == now`, lapsed deferrals with passed windows, and resting tasks with passed windows),
  when rescheduling runs at `now`, then afterwards: (a) every task whose state is not `completed` and not resting has
  `windowEnd > now`; (b) no lapsed deferral remains (all became `active`, `maintenance` or `resurfaced` per R1–R4);
  (c) completed and resting tasks are unchanged field for field (a resting task may keep a passed window until its
  deferral lapses); (d) every task equals the independent oracle's application of R0–R4; (e) a second run at the same
  `now` changes nothing; (f) Now selection on the result still satisfies AC-M1-14 and AC-M1-15.  *Verification:* unit
  (property)  *Evidence expected:* test name, seed range and counts in log.

### S-M1-06 The same moment always gives the same answer  (FR-B1, FR-B2, P-1, P-2; CLAUDE.md §3)
As the team (and, through us, the user), we want the engine to be deterministic and self-contained, so that every
result can be reproduced, trusted and tested on any machine without touching the network.

**Acceptance criteria**
- **AC-M1-22** Given identical inputs (household, `now`, calendar, time zone, weather, energy, RNG seed), when
  selection and rescheduling each run 100 times, then all 100 outputs are identical; and running with two different
  RNG seeds gives identical outputs too (M1 uses no randomness in selection or rescheduling).  *Verification:* unit
  (property over seeded households)  *Evidence expected:* test name + log.
- **AC-M1-23** Given all `.swift` files under `Packages/TendCore/Sources/` with comments removed, when a source-scan
  test runs, then (a) the only `import` is `import Foundation` (no `FoundationNetworking`, `Network`, `CFNetwork`,
  `Dispatch`-only or other modules); and (b) none of these closed-list patterns occurs: `Date()`, `Date.now`,
  `Date(timeIntervalSinceNow`, `timeIntervalSinceNow`, `Calendar.current`, `Calendar.autoupdatingCurrent`,
  `TimeZone.current`, `TimeZone.autoupdatingCurrent`, `Locale.current`, `Locale.autoupdatingCurrent`,
  `ProcessInfo`, `UUID()`, `SystemRandomNumberGenerator`, any call to `.random(`, `.randomElement(`, `.shuffled(` or
  `.shuffle(` whose argument list does not contain `using:`, `URLSession`, `URLRequest`, `URLConnection`,
  `NSURLConnection`, `Socket`, `NSStream`, `Stream(`, `InputStream(`, `OutputStream(`, `getStreamsToHost`, `Host(`,
  `Host.current`, `URL(string:`, `arc4random` (any `arc4random*`), `drand48`, `erand48`, `lrand48`, `srand48`, `rand(`,
  `random()`, and string literals containing `http://` or `https://`. `contentsOf:` (e.g. `Data(contentsOf:)`,
  `String(contentsOf:)`) is banned everywhere **except** in the source file(s) implementing the JSON file repository,
  which the scan test names in a fixed allowlist; there it is allowed only because `URL(string:` is banned and file URLs
  come from file-path initialisers. Exactly two type names are exempt from the `Stream(` pattern: `AsyncStream` and
  `AsyncThrowingStream` (Swift concurrency, not networking); no other exemption may be added without a PO decision.
  Names are matched at camelCase word boundaries. A negative test proves the scanner detects each pattern when planted,
  and a positive test proves `AsyncStream(` / `AsyncThrowingStream(` and allowlisted `contentsOf:` are not reported.  *Verification:* unit (source
  scan) + Linux build  *Evidence expected:* test name + log.
- **AC-M1-24** **(Gate)** Given the M1 merge commit, when `swift test --package-path Packages/TendCore` runs on Linux
  CI (Swift 6.2, strict concurrency), then 100% of tests pass with 0 failures, 0 skipped/disabled tests, and 0 compiler
  warnings, and every other AC (AC-M1-01…23 and AC-M1-25) maps to at least one named test.  *Verification:* CI run  *Evidence expected:* CI run
  link + log excerpt (test counts, warning count) + AC→test table in `acceptance.md`.

No AC in M1 needs a physical device. All ACs are verifiable on Linux.

## Gate mapping
| PRD §4 gate line | Covered by ACs |
|---|---|
| Automated unit test suite passes 100% | AC-M1-24 (with AC-M1-22, AC-M1-23 guaranteeing reproducibility) |
| Tests prove: given 50+ mixed tasks, the engine always returns ≤ 3 contextually valid items | AC-M1-13, AC-M1-14, AC-M1-15, AC-M1-16, with validity defined by AC-M1-08…12 and AC-M1-25 |
| Tests prove: missed tasks reschedule smoothly without generating overdue debt states | AC-M1-02, AC-M1-03, AC-M1-17, AC-M1-18, AC-M1-19, AC-M1-20, AC-M1-21 |
| Scope: household data persistence | AC-M1-04, AC-M1-05, AC-M1-06, AC-M1-07, AC-M1-25 |

## Assumptions and open questions
Product decisions made by the PO for M1 (recorded here because `DECISIONS.md` is a protected path in this PR; the
Documenter/human owner should copy them into `DECISIONS.md` as D-002… on the next governance change).

| # | Question | Default if unanswered | Needed by |
|---|---|---|---|
| Q1 | How does energy map to effort (FR-B1)? | Low → Low only; Normal → Low + Normal; High → all. Maintenance mode counts as Low. (PO decision) | M1 (decided) |
| Q2 | What are the dayparts and should anything surface at night? | Morning 05–12, afternoon 12–17, evening 17–22, night 22–05 in the injected zone; tasks default to non-night. Quiet nights protect UX-3. (PO decision) | M1 (decided) |
| Q3 | When is a weather-dependent task "weather-safe"? | Only `clear` / `cloudy`. `unknown` excludes it (we never send someone to the balcony on a guess). (PO decision) | M1 (decided) |
| Q4 | What counts as a "hectic week" that triggers maintenance mode (FR-B2)? | Any passed window of a non-critical deep clean is the signal; no weekly load metric in M1. Revisit with real usage in M3/M5. (PO decision) | M1 (decided) |
| Q5 | What is "maintenance mode"? | A state in which the deep clean is treated as a Low-effort light-touch version on its next eligible window; original effort is kept; completing it ends maintenance mode. Its user-facing wording is M3. (PO decision) | M1 (decided); copy M3 |
| Q6 | Do critical items bypass energy/daypart/weekday filters? | No. Same validity rules for all tasks; criticals win on ranking (AC-M1-16), not by breaking the filter. (PO decision) | M1 (decided) |
| Q7 | How are Now items ranked ("high-leverage")? | Exact key (resolves T-07): `resurfaced` first → earliest `windowEnd` → critical before non-critical → ascending `UUID.uuidString`. No randomness in M1. A non-critical `resurfaced` task cannot exist (Q15). Richer leverage scoring may come with AI in M2/M3 but must keep AC-M1-13…16. (PO decision) | M1 (decided) |
| Q8 | Is WeatherKit allowed under P-2 (CLAUDE.md open question 3)? | Engine takes weather as an injected value; no fetching in M1. Needs the human owner's confirmation and an ADR before any real weather source is wired (M3/M4). | Human owner, before M1 closes (non-blocking for build) |
| Q9 | Persistence store for the app (SwiftData vs Core Data vs other) with CloudKit sharing in mind? | Technical: Developer writes an ADR in M1; M1 ships only the repository protocol, in-memory and JSON file implementations. | M1 (ADR) |
| Q10 | Project generation (XcodeGen vs Tuist)? | Technical: Developer ADR when the app target is first created; M1 needs only the SwiftPM package. | M3 at latest |
| Q11 | Which weekday does the after-midnight part of the night belong to, and how are DST gaps handled? (T-02) | Night belongs to the day it starts (Saturday 22:00 → Sunday 05:00 is "Saturday night"), matching how people talk. Nonexistent local times resolve to the next instant, repeated ones to the first occurrence. (PO decision) | M1 (decided) |
| Q12 | What does `deferred` mean once its date has passed, and when its window has also passed? (T-01) | A lapsed deferral (`until ≤ now`) is treated exactly as `active` by the selector and is converted to `active` by the rescheduler (then the passed-window rules apply). A resting deferral (`until > now`) is never shown and never touched, even if its window has passed; the user asked for rest, so the engine honours it. (PO decision) | M1 (decided) |
| Q13 | Is `windowEnd == now` passed, and can the selector show a passed-but-not-yet-rescheduled task? (T-03) | Windows are half-open: `windowEnd == now` is passed. The selector is pure: a passed window is not valid, and the selector never reschedules. Callers (app, widget, intents in M3/M4) run the rescheduler before selecting; the M3 brief will require that. (PO decision) | M1 (decided); M3 wiring |
| Q14 | What exactly is the "next eligible window"? (T-02) | `E(a, D)` as defined above: start at `a` if `a` is inside an allowed slot, else at the start of the next allowed slot; keep the original duration `D`. All kinds, recurring included, move by this rule when a window passes (never skipped, never doubled); recurrence `interval` applies only on completion, anchored at `now + interval` days. Keeping `D` means a task given a week gets another week, and nothing shrinks or grows. (PO decision) | M1 (decided) |
| Q15 | What happens with degenerate inputs? (T-04) | They are rejected as model invariants at construction and on decode (AC-M1-25), never silently repaired. A task can't be both critical and deep clean; `maintenance` only on deep cleans; `resurfaced` only on criticals. M2's parser must map its output onto these invariants. (PO decision) | M1 (decided); M2 parser |
| Q16 | Scan scope for banned words and banned APIs (T-05, T-06)? | Whole-token match after camelCase/underscore/digit split, identifiers and string literals only; comments are excluded (they are not user-facing or model state). Banned API list is the closed list in AC-M1-23. (PO decision) | M1 (decided) |
| Q17 | Review Q-R1: may `AsyncStream(` / `AsyncThrowingStream(` be used when `Stream(` is matched at camelCase boundaries? (P-2) | Yes. These two names exactly are exempt; they are Swift concurrency types and send nothing off the device. Any further exemption needs a PO decision, never a Developer allowlist. AC-M1-23 updated. (PO decision, after build start: tightening only, no AC removed) | M1 (decided) |
| Q18 | Review Q-R2: extend the AC-M1-23 list with `getStreamsToHost`, `contentsOf:` with a URL, `arc4random*`, `drand48`? (P-2, determinism) | Yes. Added `getStreamsToHost`, `InputStream(`/`OutputStream(`, `URL(string:`, `arc4random*`, `drand48`/`erand48`/`lrand48`/`srand48`, `rand(`, `random()`. `contentsOf:` is banned except in the JSON file repository's file(s), named in the scan's fixed allowlist; banning `URL(string:` keeps those reads local. Planner: re-check the scanner work item and the persistence item (AC-M1-04…07) against this. (PO decision, after build start: tightening only) | M1 (decided) |

## Tester testability review
- [x] Every AC is observable and measurable  - [x] Device ACs identified (none expected in M1)  - Reviewer note:
  **v2 accepted (Acceptance Tester, 2026-11-20).**
  - T-01…T-08 are resolved.
  - All 25 ACs can be checked on Linux and are precise enough to compare against an independent oracle written in
    the test target:
    - validity: Definitions, AC-M1-08…12;
    - ranking: AC-M1-16;
    - rescheduling: R0–R4 with `E(a, D)`, AC-M1-03 and 17…21.
  - Consistency checks passed:
    - AC-M1-12 cases (c), (e) and (g) agree with the half-open windows and the lapsed-deferral rule.
    - AC-M1-21(a) follows from `E(now, D)`, because `D > 0` (AC-M1-25) gives `windowEnd > s ≥ now`.
    - `E` always terminates within 7 days, because allowed dayparts and weekdays are non-empty.
    - AC-M1-10's night-slot cases match the Slot definition.
  - All three PRD §4 M1 gate lines are covered (Gate mapping table). There are no device ACs.
  - Environment check: Swift 6.2.4 and tzdata (`/usr/share/zoneinfo`) are present in the Linux container, so the
    named-zone and DST cases can run.
  - Two nits for the Developer and Reviewer; neither changes AC meaning:
    - **N-1** The AC-M1-23 scanner should match patterns at an identifier boundary so that, for example,
      `startDate()` is not reported as `Date()`. The required negative test should include such a near-miss.
    - **N-2** The AC-M1-02/23 scanners must strip comments correctly inside string literals and multi-line
      `"""` strings. The negative tests should cover this.
  **Returned to PO (Acceptance Tester, 2026-11-20).** The brief is strong: all 24 ACs name a verification type and
  evidence. All are Linux `swift test`-verifiable. None needs a device, which is confirmed. All three PRD §4 M1 gate
  lines are mapped: line 1 → AC-M1-24; line 2 → AC-M1-13…16 on 08…12; line 3 → AC-M1-02, 17…21.
  However, three conflicts or gaps stop me from writing the independent oracle that AC-M1-14 and AC-M1-21 require.
  The gate-line ACs cannot pass until the PO resolves them. I have not changed any AC meaning.

  *Major (blocks the testability tick):*
  - **T-01 `deferred` contradiction** (Definitions vs AC-M1-12, AC-M1-21).
    - The "Contextually valid" definition requires the state to be `active`, `maintenance` or `resurfaced`, so a
      task in `deferred(until: <past>)` is invalid. AC-M1-12 says that same task is valid.
    - The brief also does not say what a lapsed deferral is. Is it treated as `active`? Does the rescheduler convert
      it? What happens when it also has a passed window (AC-M1-17/18/19 do not cover `deferred`)?
    - AC-M1-21 says "still-deferred tasks are untouched" and also "no non-completed task has `windowEnd ≤ now`".
      Both cannot hold for a task deferred to the future whose `windowEnd ≤ now`.
    - The PO needs to state one rule that the oracle can encode.
  - **T-02 "Next eligible window" is undefined** (AC-M1-17, 18, 19, 20, 21; also AC-M1-03(b)). The brief says only
    "respecting dayparts and weekdays, ends after `now`". To check new window dates exactly, the PO needs to define:
    - the new `windowStart`, e.g. the start of the earliest allowed daypart on an allowed weekday at or after `now`,
      or `now` itself if that slot is current;
    - the new `windowEnd`, e.g. the end of that daypart, or start plus the original duration;
    - whether a recurring task (AC-M1-19) is moved by daypart/weekday or by its `interval`;
    - in AC-M1-03(b), what the next window's `windowEnd` is and whether `interval` days after `now` must land in an
      allowed daypart/weekday.
    - Without these, only weak properties can be tested ("ends after now"), and the rule "a test weaker than the AC
      fails the AC" would apply.
  - **T-03 Boundary at `windowEnd == now`.** "Window passed" is strict (`now` after `windowEnd`), so a task with
    `windowEnd == now` is not passed and would not be rescheduled. AC-M1-21 nevertheless requires that no task has
    `windowEnd ≤ now`. Related product question: the validity definition never checks `windowEnd`, so a
    passed-window task that has not been rescheduled is "valid" and can be selected (AC-M1-14/15). Please confirm
    this is intended, or add `now ≤ windowEnd` (or `<`) to validity.

  *Minor (fix wording when convenient; does not block on its own):*
  - **T-04 Degenerate inputs.** These cases have no defined outcome, and random generation ("every daypart/weekday
    set", AC-M1-05/14/21) will produce them:
    - an empty set of allowed dayparts or weekdays (no eligible window ever exists);
    - `windowEnd < windowStart`;
    - a recurring task with no `interval`, or a one-off task with one.
    - The PO should either state these as model invariants that construction rejects, or define the behaviour.
  - **T-05 AC-M1-23 needs a closed list.** "Other networking APIs" should be an explicit token list, e.g.
    `URLSession`, `URLRequest`, `Network`, `CFNetwork`, `Socket`, `NSStream`, `Host`, `http://`/`https://`
    literals. "Argument-less `.random(`" should read "any `.random(`/`.shuffled()`/`.randomElement()` without
    `using:`", because `Int.random(in:)` takes arguments but still uses the system RNG.
  - **T-06 AC-M1-02 scan rules.** State that the scan matches exact tokens after the camelCase/underscore split (so
    `template` or `latest` are not hits), and whether comments are in scope. Note for the Developer: names like
    `writeFailed` for the AC-M1-07 error would trip the scan.
  - **T-07 AC-M1-16 tie-break.** "Stable ID order, or the injected RNG" lets the Developer choose. The chosen rule
    must be recorded in dev notes so the oracle can assert the exact order. The AC should also say whether a
    `resurfaced` non-critical task can exist and how it ranks, because random states may produce one.
  - **T-08 AC-M1-20 comparison.** Compare decoded structure (key set, non-date field values, collection counts)
    rather than encoded byte size, because the encoding of dates alone can change the size.
  - My own independent cases will include: DST transition days (nonexistent 02:30, repeated 01:30) at daypart
    boundaries, a far-future `now`, a 0-task household, and a 500-task household where everything is invalid.

  **PO response (Product Owner, 2026-11-20, brief v2) — all findings addressed, no AC deleted, none weakened:**
  - T-01: "Effective state" definition + rule R1 + Q12. Lapsed deferral = `active` (valid in the selector, converted
    by the rescheduler, then R2–R4). Resting deferral is never valid and never touched, even with a passed window.
    AC-M1-12 is rewritten as nine exact cases. AC-M1-21(a)/(c) exempts resting tasks explicitly, so the two clauses no
    longer conflict.
  - T-02: "Slot" and `E(a, D)` definitions + Q11/Q14. The rescheduler uses `E(now, D)` for every kind. Recurring
    completion uses `E(now + interval days, D)` (AC-M1-03(b)). Night belongs to the day it starts. DST policy is
    stated. AC-M1-17/18/19 now assert exact windows.
  - T-03: windows are half-open. `windowEnd == now` is passed (Definitions, AC-M1-12(g), AC-M1-17). Validity requires
    `now < windowEnd`. The selector is pure and never reschedules (Q13).
  - T-04: model invariants + new **AC-M1-25** (construction and decode reject them) + Q15. Generators produce valid
    tasks only.
  - T-05: AC-M1-23 now has a closed pattern list, including `using:`-less random calls and `UUID()`, plus a negative
    test.
  - T-06: AC-M1-02 matches whole tokens after the split, excludes comments, has a negative test, and carries the
    `writeFailed` note (Q16).
  - T-07: AC-M1-16 has an exact four-key sort with no RNG. A non-critical `resurfaced` task is impossible (AC-M1-25).
  - T-08: AC-M1-20 compares decoded structure (key set, non-window values, collection counts, duration), not bytes.
  - Your DST, far-future, 0-task and all-invalid cases are welcome. They fall under AC-M1-03/09/15/17 as written.
  Please re-review. The testability box stays unticked until you confirm.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry UI in M1; the model has no requirement for multi-field input (all fields have defaults or are set by tests/AI later). |
| UX-2 Rule of Three | pass | Enforced in the engine type (`NowSelection`, AC-M1-13) and proven by property tests over 50–500-task households (AC-M1-14, AC-M1-15, AC-M1-21). |
| UX-3 Zero-Guilt | pass | No overdue state or counter in the model, banned-token scan of identifiers and strings (AC-M1-02), no debt growth (AC-M1-20), calm resurfacing without escalation (AC-M1-18), quiet nights by default (Q2). |
| UX-4 Design craft | n.a. | No UI in M1 (M3). |
| P-1 On-device inference | n.a. | No AI in M1; engine runs locally and is Foundation-only (AC-M1-23). |
| P-2 No data leaves device (except user iCloud) | pass | No networking APIs in `TendCore` (AC-M1-23); persistence is a local file (AC-M1-04…07). Weather is injected, not fetched (Q8). |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud use in M1. |
| P-4 Media not persisted without consent | n.a. | No camera, audio or documents in M1. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Product Owner | Acceptance Tester | sent for testability review | Brief v1: 6 stories, 24 ACs (AC-M1-01…24), no device ACs. After Tester review, PO addresses any findings, then hands off to Work Planner (H1). |
| 2026-11-20 | Acceptance Tester | Product Owner | returned | Testability review: 3 Major (T-01 `deferred` contradiction; T-02 "next eligible window" undefined; T-03 `windowEnd == now` boundary and whether validity checks `windowEnd`) and 5 Minor (T-04…T-08). Gate-line coverage is complete. No device ACs. Box 1 left unticked until T-01…T-03 are resolved; PO to revise and resend. |
| 2026-11-20 | Product Owner | Acceptance Tester | resent for testability review | Brief v2 resolves T-01…T-08: new definitions (slot, effective state, window open/passed, `E(a, D)`, invariants), rescheduling rules R0–R4, rewritten AC-M1-02/03/10/12/16/17–21/23, new AC-M1-25 (25 ACs). New PO decisions Q11–Q16 are in the Assumptions table (to be copied to DECISIONS.md by the governance owner). No human-owner question added. |
| 2026-11-20 | Acceptance Tester | Product Owner | accepted | v2 re-review: T-01…T-08 resolved. All 25 ACs are observable, measurable and Linux-verifiable. Gate lines are fully covered. No device ACs. Two nits (N-1, N-2) on scanner precision for the Developer and Reviewer. PO may hand off to the Work Planner (H1). |
| 2026-11-20 | Reviewer (WI-M1-01 review.md) | Product Owner | answered | Q-R1 → Q17: `AsyncStream`/`AsyncThrowingStream` exact exemption. Q-R2 → Q18: AC-M1-23 list extended; `contentsOf:` only in the file repository's allowlisted file(s); `URL(string:` banned. AC-M1-23 tightened, not weakened. Planner to re-check affected items; copy Q17/Q18 to DECISIONS.md with Q1–Q16. |
