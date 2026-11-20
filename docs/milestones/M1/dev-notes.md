# M1 Developer Handoff — WI-M1-01, WI-M1-02 (later sections: WI-M1-03…04)

One section per work item. Each section follows the dev-notes template.

---

## WI-M1-01 — `TendCore` package scaffold, domain model, invariants, source-scan guards, foundation ADRs

- **Owner:** Developer  ·  **Branch:** `m1/core-model`  ·  **PR:** _opened by the Orchestrator (link to be added)_  ·
  **ADRs:** [ADR-0001](../../architecture/adr/0001-tendcore-module-boundary.md) (Accepted),
  [ADR-0002](../../architecture/adr/0002-app-persistence-store.md) (Proposed),
  [ADR-0003](../../architecture/adr/0003-project-generation.md) (Proposed)
- **Requirements:** FR-B1, FR-B2, FR-B3 (data only), UX-2, UX-3, P-1, P-2; CLAUDE.md §3. **Owns** AC-M1-01, AC-M1-02,
  AC-M1-23, AC-M1-25 (construction and `Codable` decode) per [plan.md](plan.md). Nits N-1 and N-2 are in scope.
- **Inputs:** [brief.md](brief.md) v2, [design.md](design.md) (binding naming list, forbidden names, D-1…D-3),
  [plan.md](plan.md).

### What changed
- **Package** `Packages/TendCore/Package.swift`: swift-tools-version 6.2, `swiftLanguageModes: [.v6]` (complete strict
  concurrency), platforms iOS 26 / macOS 26. One library target `TendCore`, which imports only Foundation, and one test
  target `TendCoreTests` (Swift Testing). No dependencies.
- **Model** `Sources/TendCore/Model/` (all names from the design naming list):
  - `HouseholdTask`: exactly the 15 listed stored fields (D-2).
    - Fields are `public internal(set)`: readable everywhere, mutable only inside `TendCore`.
    - One throwing initialiser, `throws(TaskInvariantViolation)`, checks the nine invariants (AC-M1-25). `init(from:)`
      calls the same initialiser, so decode validates too.
    - Custom `Codable`: sets are encoded in case order, so the same task always produces the same JSON.
    - Effective-state helpers `isResting(at:)`, `isRestOver(at:)`, `windowIsOpen(at:)` and `windowHasEnded(at:)`
      (D-1).
  - `TaskState`: exactly `active`, `deferred(until:)`, `maintenance`, `resurfaced`, `completed`. Custom `Codable` as
    `{"name": …, "until": …}`. An unknown name is rejected and never mapped to a default.
  - `TaskKind`, `Effort`, `EnergyLevel`, `Daypart` (with `defaultAllowed` = morning, afternoon, evening, per Q2),
    `Weekday`, `WeatherCondition`.
  - `PromptTone` with one case, `gentle`.
  - `TaskInvariantViolation` with the nine design cases.
  - `Room` (`lastTendedAt`), and `Household` (`tasks`, `rooms`, `schemaVersion`, `currentSchemaVersion = 1`).
  - Every type is `Equatable`/`Hashable`, `Codable` and `Sendable`.
- **Tests** `Tests/TendCoreTests/`: 40 Swift Testing tests in 6 suites, 126 test cases once the parameterised arguments
  are expanded.
  - `Support/SourceScanner.swift`: a small Swift lexer.
    - Removes `//`, `///` and nested `/* */` comments.
    - String-literal aware: `"…"`, `"""…"""`, raw `#"…"#` and `#"""…"""#`, escapes, and interpolation `\(…)` /
      `\#(…)`, whose contents are lexed as code again (N-2).
    - Whole-token camelCase / underscore / digit tokeniser for AC-M1-02.
    - Identifier-boundary regexes for the AC-M1-23 closed list (N-1), a balanced-paren check for `using:`-less
      randomness, an `import` check and an `http(s)://` literal check.
  - `Support/Fixtures.swift`: fixed dates and UUIDs (no `Date()` / `UUID()`).
- **ADRs:** 0001 (module boundary, Accepted: a technical decision within CLAUDE.md §3), 0002 (Core Data +
  `NSPersistentCloudKitContainer` proposed, `CKSyncEngine` as fallback; Proposed until a macOS spike), 0003 (XcodeGen
  proposed; Proposed until the M3 app target).
- **Repo:** `.gitignore` (`.build/`, `.swiftpm/`, Xcode user data).
- Not touched: `CLAUDE.md`, `.claude/**`, `.github/**`, `docs/governance/**`, `docs/PRD.md`, `docs/milestones/STATUS.md`,
  `docs/architecture/README.md` (the ADR index belongs to the Documenter, who should add ADR-0001…0003).

### Public API listing (for the Reviewer's naming, D-2, D-3 and UX-2 check; risk R-12)
```
public struct HouseholdTask: Identifiable, Hashable, Sendable, Codable
  public internal(set) var id: UUID, title: String, kind: TaskKind, roomID: UUID?, effort: Effort,
                           isCritical: Bool, isDeepClean: Bool, isWeatherDependent: Bool,
                           allowedDayparts: Set<Daypart>, allowedWeekdays: Set<Weekday>,
                           windowStart: Date, windowEnd: Date, recurrenceIntervalDays: Int?,
                           state: TaskState, completedAt: Date?
  public init(id:title:kind:roomID: = nil, effort:, isCritical: = false, isDeepClean: = false,
              isWeatherDependent: = false, allowedDayparts: = Daypart.defaultAllowed,
              allowedWeekdays: = Set(Weekday.allCases), windowStart:, windowEnd:,
              recurrenceIntervalDays: = nil, state: = .active, completedAt: = nil) throws(TaskInvariantViolation)
  public init(from: any Decoder) throws;  public func encode(to: any Encoder) throws
  public func isResting(at: Date) -> Bool;   public func isRestOver(at: Date) -> Bool
  public func windowIsOpen(at: Date) -> Bool; public func windowHasEnded(at: Date) -> Bool
public enum TaskState: Hashable, Sendable, Codable { active, deferred(until: Date), maintenance, resurfaced, completed }
public enum TaskKind: String, CaseIterable, Codable, Hashable, Sendable { oneOff, recurring, restock }
public enum Effort: … { low, normal, high }
public enum EnergyLevel: … { low, normal, high }
public enum Daypart: … { morning, afternoon, evening, night }; public static let defaultAllowed: Set<Daypart>
public enum Weekday: … { sunday, monday, tuesday, wednesday, thursday, friday, saturday }
public enum WeatherCondition: … { clear, cloudy, wet, severe, unknown }
public enum PromptTone: … { gentle }
public enum TaskInvariantViolation: Error, CaseIterable, Hashable, Sendable { noAllowedDayparts, noAllowedWeekdays,
  windowEndNotAfterStart, recurringWithoutInterval, intervalBelowOneDay, intervalOnNonRecurringTask,
  criticalAndDeepClean, maintenanceOnNonDeepClean, resurfacedOnNonCritical }
public struct Room: Identifiable, Hashable, Codable, Sendable { public let id: UUID; public var name: String;
  public var lastTendedAt: Date?; public init(id:name:lastTendedAt: = nil) }
public struct Household: Hashable, Codable, Sendable { public static let currentSchemaVersion = 1;
  public var tasks: [HouseholdTask]; public var rooms: [Room]; public var schemaVersion: Int;
  public init(tasks:rooms:schemaVersion: = Household.currentSchemaVersion) }
```
- No public API returns "what to do now" items. That arrives in WI-M1-03 as `NowSelection` only.
- No `priority`, `score` or `weight` (D-3). No counter, original window or history field (D-2), which is enforced by
  test.
- **Naming-list deviations:** none.
- **Additions beyond the list:** `Daypart.defaultAllowed` (the brief's Q2 default, as a named constant),
  `Household.currentSchemaVersion`, `Identifiable` on `HouseholdTask`/`Room`, and an internal (not public)
  `HouseholdTask.firstInvariantViolation()` for later engine items to check their own output.

### Decisions the Reviewer should know (technical, reversible; no product meaning changed)
1. **Invariant order.** When several invariants are broken, the first in `TaskInvariantViolation` case order is thrown
   (test: "AC-M1-25: when several invariants are broken, the first in the documented order is reported").
2. **Exactly nine invariants.** Nothing else is validated: no title rule, and no `completedAt`/state coupling. Adding
   more would reject combinations that AC-M1-01 requires to be representable.
3. **Initialiser defaults.** `effort` has **no default**: the brief gives none, so the caller must say it. `allowedWeekdays`
   defaults to all seven days. The brief requires only "non-empty" and gives no default, so this is the least
   restrictive choice; the PO can override it with no structural change. The other defaults follow Q2 and the brief
   (night quiet, `active`, flags false).
4. **`windowIsOpen` / `windowHasEnded` look only at the window.** They do not consider state. The brief's "window passed"
   additionally excludes completed and resting tasks; the rescheduler (WI-M1-04) composes that with `isResting(at:)`
   and the state. This keeps each helper a single fact. If the Designer reads the naming list as "`windowHasEnded`
   must include the state test", it is a one-line change.
5. **Mutability.** Fields are `public internal(set)`, so outside modules (later UI and adapters) cannot break
   invariants by mutation. The trade-off: code inside `TendCore` must keep the invariants. WI-M1-04 can assert this
   with `firstInvariantViolation()`.
6. **Date encoding** uses the encoder's strategy. With the default `JSONEncoder` (`.deferredToDate`), fractional dates
   round-trip exactly on Linux (tested here with sub-second dates). The file-format choice and its bit-exact proof over
   seeded households is WI-M1-02 (AC-M1-05, R-7).
7. **Schema version** is stored on `Household`, but unknown versions are rejected by the repository (WI-M1-02,
   AC-M1-06), not by `Household.init(from:)`.
8. **Decode error type.** `init(from:)` rethrows the `TaskInvariantViolation` itself, not a `DecodingError`, so WI-M1-02
   can wrap it as `HouseholdStoreError.invalidTask(_)`.

### AC coverage
| AC | Test(s) (Swift Testing display names; suite) | Result |
|---|---|---|
| AC-M1-01 | "AC-M1-01: one task of each kind (one-off errand, recurring maintenance, consumable restock) is representable, Equatable and Codable" (3 cases); "AC-M1-01: every field combination allowed by the model invariants is representable and round-trips through Codable" (1,440 combinations: 792 representable, 648 rejected exactly as the invariants predict); "AC-M1-01: every non-empty set of allowed dayparts and weekdays is representable and round-trips" (15 × 127 = 1,905 sets); "AC-M1-01: Equatable distinguishes every stored field of HouseholdTask"; "AC-M1-01: TaskState values are Equatable and Codable, including the deferral date (FR-B2)"; "AC-M1-01 / FR-B3: a Room carries an optional lastTendedAt and round-trips through Codable"; "AC-M1-01: a Household holds tasks, rooms and a schema version and round-trips through Codable"; "AC-M1-01: the default allowed dayparts are morning, afternoon and evening; night is quiet (Q2)"; "AC-M1-01: the value enums hold exactly the cases in the design naming list" — suite *Household model (AC-M1-01)* | PASS (Linux container) |
| AC-M1-02 | **Scan:** "AC-M1-02: no banned zero-guilt token in any identifier or string literal of TendCore/Sources" (log: `AC-M1-02 scan: 11 files scanned`, each file listed, `0 hits`). **Closed set and no counter:** "AC-M1-02: the lifecycle state is the closed set active, deferred(until:), maintenance, resurfaced, completed"; "AC-M1-02 / D-2: HouseholdTask stores exactly the fields in the design naming list (no counter, original window or history)"; "AC-M1-02 / D-2: the encoded HouseholdTask has exactly the naming-list keys"; "AC-M1-02 / D-2: Room and Household store no counters or history"; "AC-M1-25 / AC-M1-02: an unknown lifecycle state in JSON is rejected, not mapped to a default". **Negative (planted):** "AC-M1-02 negative: every banned token planted in an identifier is detected" (9 cases); "AC-M1-02 negative: every banned token planted in a string literal is detected" (9 cases); "AC-M1-02 negative: whole-token match ignores near-misses (template, latest, translate, relate)"; "AC-M1-02 negative: banned tokens inside comments are ignored (line, doc, block, nested block)"; "N-2: comment markers inside string literals do not hide the rest of the line or file"; "Scanner tokeniser splits camelCase humps, acronyms, underscores and digits"; "Scanner keeps line numbers aligned through comments and multi-line strings" | PASS (Linux container) |
| AC-M1-23 | **Scan:** "AC-M1-23: only \`import Foundation\`, no ambient time, randomness or networking API in TendCore/Sources" (log: `11 files scanned`, `11 import statements found`, `0 hits`). **Negative (planted):** "AC-M1-23 negative: every banned pattern planted in code is detected" (34 fixtures); "AC-M1-23 coverage: the planted fixtures exercise every pattern in the closed list" (every pattern has at least one planted fixture); "AC-M1-23 negative: imports other than Foundation are detected" (8 cases); "AC-M1-23: \`import Foundation\` alone is allowed; imports in comments and strings are ignored"; "N-1: near-misses at identifier boundaries are not reported" (`startDate()`, `makeUUID()`, `Calendar.currentWeek`, `myCalendar.current`, `Date.nowish`, `InputStream(`, `GhostHost(`, `using:` variants incl. nested parens, …); "AC-M1-23 negative: banned patterns in comments and plain string text are ignored". **Linux build:** `swift build`/`swift test` with `-warnings-as-errors` | PASS (Linux container) |
| AC-M1-25 | "AC-M1-25: constructing a task that violates an invariant throws the typed violation" (12 cases covering all 9 invariants, incl. equal and reversed windows, interval 0 and −3, one-off and restock with an interval); "AC-M1-25: decoding JSON that violates an invariant throws the typed violation" (9 cases, one per invariant); "AC-M1-25: decoding a household whose file contains one invalid task throws the typed violation"; "AC-M1-25: the cases cover all nine invariants in the design naming list"; "AC-M1-25: values just inside each invariant are accepted (boundary)"; "AC-M1-25: when several invariants are broken, the first in the documented order is reported"; "AC-M1-25 naming: TaskInvariantViolation has exactly the nine design-list cases". The repository part ("the repository throws a typed error as in AC-M1-06") is **WI-M1-02** per the plan. | PASS for construction and decode (Linux container); repository path pending WI-M1-02 |
| Design checks (no AC of their own) | "Design review: PromptTone has exactly one case, gentle (AC-M1-18 groundwork)"; "D-1: isResting and isRestOver split a deferral at now (until > now rests; until <= now rest is over)" (5 cases); "D-1: a task that is not deferred is neither resting nor at the end of a rest" (2 cases); "Window helpers are half-open: windowStart <= now < windowEnd is open; windowEnd <= now has ended" (5 cases) | PASS (Linux container) |

**Tests fail when the behaviour breaks.** Each mutation was applied locally and then reverted; the tests listed went red
each time:

| Mutation | Tests that went red |
|---|---|
| Remove the `resurfacedOnNonCritical` check | AC-M1-25 construction and decode, AC-M1-01 combinations |
| Skip validation on decode | AC-M1-25 decode, AC-M1-01 combinations |
| Add a stored `timesMoved: Int` | the D-2 stored-field test |
| Plant `import Dispatch`, `isOverdue()`, `Date()` and the literal `"the bill is late"` in `Sources/` | both source scans, with file and line reported |
| Add a sixth `TaskState` case | compile error (exhaustive switches) |
| Disable string-literal lexing in the scanner | the N-2, imports-in-strings and patterns-in-strings tests |
| Drop the identifier boundary on `Date()` | the N-1 near-miss test |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| `swift build --build-tests -Xswiftc -warnings-as-errors` (0 warnings) | ✔ container, Swift 6.2.4 (swift-6.2.4-RELEASE, x86_64-unknown-linux-gnu) | — | — | — | macOS / Xcode 26: no Mac in this environment |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors`: 40 tests in 6 suites, 0 failures, 0 skipped, about 0.2 s | ✔ container | — | — | — | Linux CI (`swift:6.2-noble`, `.github/workflows/ci.yml`) runs the same command on the PR; the Reviewer/Gatekeeper should confirm the CI log shows "Test run with 40 tests" (R-6: tests really ran) |
| AC-M1-01, 02, 23, 25 (above) | ✔ container | — | — | — | — |
| Darwin Foundation behaviour (JSON number formatting of dates, `Mirror` labels) | — | — | — | — | Not verified on macOS. Risk is low for these ACs; to be covered by the macOS lane in M3 (ADR-0001, ADR-0003) |
| ADR-0002 framework claims (SwiftData sharing, `NSPersistentCloudKitContainer` shares, encrypted attributes) | — | — | — | — | Not verifiable on Linux; the ADR stays `Proposed` until a macOS spike |

Device ACs: none in M1 (brief).

### Things the reviewer should look at closely
- **The scanner lexer** (`Tests/TendCoreTests/Support/SourceScanner.swift`, risk R-2). Check:
  - raw-string closing with `#` counts;
  - interpolation re-entry into code with nested parentheses and strings;
  - nested block comments;
  - the unterminated single-line string fallback;
  - escape decoding (`\u{…}`, line continuation in `"""`).

  Known blind spots, by design and per the AC wording:
  - (a) Regex literals `/…/` and `#/…/#` are lexed as code. A banned token inside a regex literal is still reported,
    but a `//` inside one would be read as a comment start. `TendCore` has no regex literals; a later item that adds
    one must check this.
  - (b) Whole-token matching means split spellings (`overDue`, `late_ness` → `late` is caught, but `over_due` is not)
    and synonyms are a Reviewer check (design "design-forbidden" list, R-12).
  - (c) Escapes `\n`, `\t`, `\r` and `\0` decode to a space, so they never glue onto a word.
  - (d) API patterns inside **plain string text** are not reported (`"Date()"` is text, not a call). Interpolations
    are reported, and `http(s)://` is checked in literals as the AC requires.
  - (e) Identifier-boundary matching (N-1) means `WebSocket…`, `InputStream(` and `…Host(` are **not** hits. The AC's
    closed list names `Socket`, `Stream(` and `Host(`, and N-1 asks for boundary matching. Networking types such as
    `URLSession` and `URLRequest` are still caught by name, and `FoundationNetworking` / `Network` cannot be imported.
- **The `Mirror`-based D-2 tests** read stored-property labels. They are reliable for structs. For the enum payload of
  `deferred(until:)`, the label check depends on Swift's reflection of single-element labelled payloads. It passes on
  Linux Swift 6.2.4 and has not been checked on Darwin.
- **Typed throws** (`throws(TaskInvariantViolation)`) on a public initialiser. This is Swift 6 API surface. Callers in
  later modules get a concrete error type without casting.
- **`public internal(set)` fields** (decision 5 above).
- **Test-log vocabulary.** The negative tests have to plant the banned words, so the words appear as test *arguments*
  and fixture text in test sources. They never appear in test *names*, and no "missed" wording is used in evidence
  names (D-1, design.md). Banned words appear in the log only when a negative test fails.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Repository wrapping of decode violations (`HouseholdStoreError.invalidTask`) and the file-bytes-unchanged check | — (planned) | WI-M1-02 (AC-M1-06, AC-M1-25 decode through the repository) |
| Exact date encoding for the file format, proven over seeded households | — (planned) | WI-M1-02 (AC-M1-05, R-7) |
| The `allowedWeekdays` default (all seven days) is a developer default; the brief gives none | Minor (PO may confirm) | PO (no AC impact) |
| `docs/architecture/README.md` ADR index lacks ADR-0001…0003 | Minor | Product Documenter |
| macOS/Darwin run of the package not available in M1 | Minor | M3 macOS CI lane (ADR-0003; `.github/**` is human-merged) |
| ADR-0002 and ADR-0003 stay `Proposed` | — | macOS spike before M3 build |
| Scanner blind spots (a)–(e) above | Minor | Reviewer check per PR (R-12) |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The task initialiser is a programmatic API with defaults for all optional data; only identity, title, kind, effort and window are required, and M2's on-device parser supplies them (FR-A1). |
| UX-2 Rule of Three | pass | No public API returns "what to do now" items in this item. `NowSelection` (WI-M1-03) will be the only one. |
| UX-3 Zero-Guilt | pass | Closed lifecycle set with no debt state, enforced by tests (AC-M1-02). No counter, original-window or history field (D-2, enforced by stored-field and encoded-key tests). No time-growing score (D-3). D-1 wording `isRestOver`. The banned-token scan is clean (11 files, 0 hits). `PromptTone` has one case, `gentle`. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. `TendCore` imports only Foundation (AC-M1-23). |
| P-2 No data leaves device (except user iCloud) | pass | No networking API or `http(s)` literal in `Sources/` (AC-M1-23 scan, 0 hits). |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Work Planner / iOS Designer | Developer | accepted (H2/H3) | WI-M1-01 Ready; design.md `Ready` with binding naming list and D-1…D-3. Milestone lock satisfied (M1 is first). |
| 2026-11-20 | Developer | Reviewer (via Orchestrator) | sent (H4) | WI-M1-01 built test-first on `m1/core-model`. 40 tests, 6 suites, 0 failures, 0 warnings on Linux Swift 6.2.4. ADR-0001 Accepted, ADR-0002 and 0003 Proposed. No naming deviations. Not verified on macOS or Xcode. Not committed: the Orchestrator commits and opens the PR. |

---

## WI-M1-02 — Persistence: `HouseholdRepository`, in-memory and JSON file stores, seeded test generators

- **Owner:** Developer  ·  **Branch:** `m1/persistence` (stacked on `m1/core-model`; rebase onto `main` once WI-M1-01
  is merged, and onto the Q17/Q18 scanner change)  ·  **PR:** _opened by the Orchestrator (link to be added)_  ·
  **ADRs:** [ADR-0004](../../architecture/adr/0004-household-json-file-format.md) (Proposed: file format, exact
  dates, atomic save); ADR-0001 (Foundation-only) applies
- **Requirements:** FR-B1, FR-B2, P-2, UX-3; S-M1-02. **Owns** AC-M1-04, AC-M1-05, AC-M1-06 and AC-M1-07, plus the
  repository part of AC-M1-25. Keeps AC-M1-02 and AC-M1-23 green over the larger `Sources/` tree. Risks R-7 and R-8.
- **Inputs:** [brief.md](brief.md) v2, [design.md](design.md) (repository and `HouseholdStoreError` names, codes only,
  D-2, D-3), [plan.md](plan.md) (WI-M1-02 scope), and the Orchestrator's note on PO decisions Q17/Q18: file I/O only
  in `JSONFileHouseholdRepository.swift`, no `URL(string:` or stream APIs.

### What changed
- **`Sources/TendCore/Persistence/`** (4 new files, Foundation only):
  - `HouseholdRepository.swift`:
    - The `public protocol HouseholdRepository: Sendable`, with its contract documented in the protocol (see the API
      listing below).
    - Internal `Household` edit helpers (`upsertTask`, `removeTask(id:)`, `updateRoom`, `checkSchemaVersionIsCurrent`,
      `empty`), shared by both stores so they edit a household the same way.
  - `HouseholdStoreError.swift`: exactly the four design cases.
  - `InMemoryHouseholdRepository.swift`: a `public actor`.
  - `JSONFileHouseholdRepository.swift`: a `public actor`. All file access in `TendCore` is in this file (Q17/Q18).
    - Format per ADR-0004: sorted keys; dates as `timeIntervalSinceReferenceDate` numbers, set explicitly; the
      `schemaVersion` probe is decoded first.
    - Load: missing file → empty household; any other problem → typed error; a load never writes.
    - Save: check the schema version, encode in full, then one call to the write primitive.
    - Edits: read-modify-write inside the actor.
    - Internal write seam `HouseholdFileWriter`. The standard writer is `Data.write(to:options: .atomic)`.
- **Tests** (`Tests/TendCoreTests/`): 33 new tests in 5 new suites. **73 tests in 11 suites in total.**
  - `Support/SplitMix64.swift`: a seeded RNG, checked against the published SplitMix64 reference values for seed 0.
  - `Support/HouseholdGenerator.swift`: a **valid-only** household and task generator, reused by WI-M1-03 and
    WI-M1-04.
    - Covers every kind, flag set, the weather flag, every state (including resting and rest-over deferrals), random
      non-empty daypart and weekday sets, five window positions relative to `now` (ended, ends at `now`, open, starts
      at `now`, upcoming), and sub-second dates.
    - Gives deterministic UUIDs (no `UUID()` call).
    - Every task goes through the throwing initialiser.
    - `allDates(in:)` collects every date for bit-exact checks.
  - `Support/RepositoryHarness.swift`: runs a test against each implementation, with `reopen()` meaning a new instance
    on the same file. It also creates a temporary directory per test and removes it afterwards, even when the test
    throws.
  - `RepositoryContractTests.swift`, `FileRepositoryRoundTripTests.swift`, `FileRepositoryLoadErrorTests.swift`,
    `FileRepositoryAtomicSaveTests.swift` and `GeneratorTests.swift`.
  - The new test files use `@testable import TendCore` to reach the internal write seam and encoder (`swift test`
    builds debug with testing enabled, as CI does).
- **Docs:** ADR-0004 (new), this section, and the title line of this file.
- **Not touched:**
  - the WI-M1-01 model or scanner (no change to `HouseholdTask`, `Household` or `Room`);
  - `CLAUDE.md`, `.claude/**`, `.github/**`, `docs/governance/**`, `docs/PRD.md`, `docs/milestones/STATUS.md`;
  - `docs/architecture/README.md` (the Documenter adds ADR-0004 to the index).

### Public API added (for the Reviewer's naming, D-2, D-3 and UX-2 check; R-12)
```
public enum HouseholdStoreError: Error, Hashable, Sendable {
  unreadableFile, unsupportedSchemaVersion(Int), invalidTask(TaskInvariantViolation), writeUnsuccessful }
public protocol HouseholdRepository: Sendable {
  func load() async throws(HouseholdStoreError) -> Household
  func save(_ household: Household) async throws(HouseholdStoreError)
  func upsertTask(_ task: HouseholdTask) async throws(HouseholdStoreError)
  func removeTask(id: HouseholdTask.ID) async throws(HouseholdStoreError)
  func updateRoom(_ room: Room) async throws(HouseholdStoreError) }
public actor InMemoryHouseholdRepository: HouseholdRepository { public init() }
public actor JSONFileHouseholdRepository: HouseholdRepository { public nonisolated let fileURL: URL; public init(fileURL: URL) }
```
- **Internal only:**
  - `JSONFileHouseholdRepository.init(fileURL:writer:)`, `encode(_:)` and `decode(_:)`;
  - `HouseholdFileWriter` (`write`, `standard`);
  - the `Household` edit helpers.
- **Naming-list deviations:** none.
  - The operation names `upsertTask`, `removeTask(id:)` and `updateRoom` follow the AC-M1-04 wording; the design lists
    no method names.
  - No new stored field on any model type (D-2). No priority, score or weight (D-3). No list API for "what to do now"
    (UX-2).
  - No error message strings: codes only (design.md `store.error.*`).

### Decisions the Reviewer should know (technical, reversible; no product meaning changed)
1. **A missing file means "nothing saved yet"** and loads as an empty household at schema version 1. A file that
   **exists** but cannot be read (including a 0-byte file, or a directory at that path) always throws, never returns
   empty (AC-M1-06). If the PO wants a first-run signal instead of an empty household, `load()` can be changed to
   return an optional.
2. **`save` rejects `schemaVersion != currentSchemaVersion`** with `unsupportedSchemaVersion(v)` in both stores, so
   nothing is stored that this build cannot read back. This reuses a design-list case for the write direction.
3. **`removeTask(id:)` with an unknown ID is a no-op.** **`updateRoom` with an unknown ID appends the room.** The four
   design error cases have no "not found" case, and idempotent edits are the calmer contract. Both are covered by
   contract tests on both stores.
4. **Edits on an unreadable file throw the load error and write nothing.** An older build or a damaged file is never
   overwritten by an `upsertTask`. An explicit `save` of a whole household over a damaged file is allowed: that is a
   deliberate replace.
5. **Atomic save (R-8).** On Linux Swift 6.2.4, `FileManager.replaceItemAt` removed the existing file and then threw,
   which loses data. `moveItem` will not overwrite. Both were observed in the container probe recorded in ADR-0004. So
   the standard writer is Foundation's `.atomic` write: it stages the bytes and renames them over the file. A test
   shows the file gets a new inode and no staging file is left. The seam's contract is "replace atomically or not at
   all". Fault injection replaces the primitive with one that fails at three points.
6. **Exact dates (R-7).** Dates are `Double` seconds since the reference date, and Swift writes the shortest digits
   that round-trip. AC-M1-05 compares the **bit patterns** of all 144,045 dates, not only `==`.
7. **Concurrency.** Both stores are actors, so each call is one isolated read-modify-write. A contract test runs 64
   concurrent upserts per store and checks that none is lost. There is no `@unchecked Sendable` and no
   `DispatchQueue`. Two instances on the same file are not coordinated; the last save wins whole (ADR-0004).

### AC coverage
| AC | Test(s) (Swift Testing display names; suite) | Result |
|---|---|---|
| AC-M1-04 | Suite *HouseholdRepository contract (AC-M1-04)*. Each test is parameterised over `InMemoryHouseholdRepository` and `JSONFileHouseholdRepository` (2 cases each): "…a repository with nothing saved loads an empty household at the current schema version"; "…save then load returns the household exactly, also from a reopened instance"; "…save replaces the whole household (nothing from the earlier save survives)"; "…upsert adds a task with a new ID at the end"; "…upsert replaces the task with the same ID in place, keeping the order of the others"; "…upsert into a repository with nothing saved creates a household with that task"; "…remove deletes only the task with that ID"; "…removing an ID that is not stored changes nothing and does not throw"; "…update room replaces the room with the same ID in place, including lastTendedAt (FR-B3)"; "…update room with a new ID adds the room at the end"; "…saving a household with a schema version this build cannot read is rejected and stores nothing"; "…concurrent upserts from many tasks are all kept (no lost update; Swift 6 isolation)". Also: "AC-M1-04 contract: a sequence of save, upsert, remove and update room gives the same household on both implementations" (60 seeded operations). All names start with "AC-M1-04 contract:". | PASS (Linux container), 25 test cases |
| AC-M1-05 | "AC-M1-05: 200 seeded households (0-500 tasks) round-trip through a new file repository instance exactly". Log: `seeds 1...200, 200 households, 51718 tasks (min 0, max 500 per household), 144045 dates compared bit-exact, 144045 with a sub-second part`. Each failure message names its seed. Also "R-7 / AC-M1-05: awkward sub-second dates are written and read back bit-exact" (11 dates, including `0.1+0.2`, `1e-7`, `nextUp`/`nextDown`, dates before 2001, the year 2131, and 1-ulp windows). Coverage of the generator over the same seeds: "Generator: over the AC-M1-05 seeds every kind, flag, state, daypart, weekday and window position occurs, and every task is valid" (all 15 daypart sets, 5 window positions, resting and rest-over deferrals). | PASS (Linux container) |
| AC-M1-06 | Each case writes the bad bytes, then checks: `load` throws the typed error; no household is returned; the bytes are unchanged; `upsertTask`, `removeTask` and `updateRoom` throw the same error and leave the bytes unchanged; a new instance throws the same error; no other file appears. Tests: "AC-M1-06: a corrupt file (truncated or not JSON) throws unreadableFile and is left byte-for-byte unchanged" (10 cases: truncated to half and by 1 byte, 0 bytes, plain text, binary noise, a JSON array, version only, no version, version as a string, a wrong field type); "AC-M1-06: a file with an unknown schema version throws unsupportedSchemaVersion and is left unchanged" (5 cases: 2, 0, −1, 99, and version 2 with a different shape); "AC-M1-06: a path that is a directory, not a file, throws unreadableFile"; "AC-M1-06: HouseholdStoreError has exactly the design-list cases and carries no user-facing text". Suite *JSON file repository load errors (AC-M1-06, AC-M1-25)*. | PASS (Linux container) |
| AC-M1-07 | "AC-M1-07: when a later save of B fails mid-way, loading returns A intact (no partial or empty file)" (3 injected failure points: before any bytes, halfway through staging, just before the replace); "AC-M1-07: a failed upsert, remove or room update leaves A intact" (3); "AC-M1-07: when the very first save fails, no household file is created and nothing was saved" (3); "AC-M1-07: after a failed save, the next successful save of B is stored and loads exactly"; "AC-M1-07: a save whose encoding fails part-way (a non-finite date) writes nothing and leaves A intact" (a real failure, no fake); "R-8 / AC-M1-07: the standard writer replaces the file by rename (new file identity), never rewrites it in place, and leaves no staging file"; "AC-M1-07: the write primitive is given the whole encoded household in one call, after encoding has finished". Suite *JSON file repository atomic save (AC-M1-07, R-8)*. | PASS (Linux container) |
| AC-M1-25 (repository part) | "AC-M1-25 / AC-M1-06: a file containing a task that violates an invariant throws invalidTask through the repository and is left unchanged" (9 cases, one per invariant). Each case puts one bad task at index 7 among 20 valid ones. It reuses WI-M1-01's `InvariantTests.violatingJSON`. Also "AC-M1-25: the repository cases cover all nine invariants". | PASS (Linux container). AC-M1-25 is now covered for construction, decode and the repository. |
| AC-M1-02, AC-M1-23 (still clean) | WI-M1-01 scans, now over 15 files: `AC-M1-02 scan: 15 files scanned … 0 hits`; `AC-M1-23 scan: 15 files scanned … 15 import statements found … 0 hits`. | PASS (Linux container) |
| Support | "SplitMix64 produces the published reference sequence for seed 0, so seeds replay on every platform"; "Generator: the same seed gives the same household; different seeds give different ones"; "ADR-0004: the file is JSON with schemaVersion 1 and dates as seconds since the reference date"; "ADR-0004: saving the same household twice writes identical bytes (stable key order)" | PASS (Linux container) |

**Tests fail when the behaviour breaks.** Each mutation was applied locally, the full suite was run, and the source was
restored (verified with `diff`):

| Mutation | Tests that went red |
|---|---|
| `load` returns an empty household when decoding fails | AC-M1-06 corrupt-file cases |
| Dates encoded as `.iso8601` | AC-M1-05 (200 households), R-7 awkward dates, ADR-0004 format, most AC-M1-04 file cases, AC-M1-07 (87 issues) |
| Standard writer is not atomic (`options: []`) | R-8 rename / new-identity test |
| File `save` skips the schema-version check | AC-M1-04 schema-version contract (file case) |
| Invariant violation mapped to `unreadableFile` | AC-M1-25 / AC-M1-06 repository invariant cases |
| A failed save removes the file | AC-M1-07 failed save and failed edit tests |
| `upsertTask` moves a replaced task to the end | AC-M1-04 "upsert replaces … in place" (both stores) |
| Keys not sorted | ADR-0004 identical-bytes test, AC-M1-07 "whole encoded household" test |

Not mutation-tested: removing actor isolation, because it cannot be done without a compile error under Swift 6.

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors`: **73 tests in 11 suites passed**, 0 failures, 0 skipped, 0 warnings, about 10.4 s | ✔ container, Swift 6.2.4 (`swift:6.2-noble` via the Docker wrapper) | — | — | — | Linux CI runs the same command on the PR. The Gatekeeper should confirm "Test run with 73 tests" in the CI log (R-6). |
| Runtime (R-5) | ✔ AC-M1-05: 4.6 s; generator coverage: 10.4 s (runs in parallel; it re-validates 51,718 tasks through JSON); whole run about 10.4 s wall time | — | — | — | Well inside the CI 20-minute timeout |
| AC-M1-04…07, AC-M1-25 (repository part); AC-M1-02 and 23 still clean | ✔ container | — | — | — | — |
| `replaceItemAt` / `moveItem` / `.atomic` behaviour (R-8) | ✔ container probe (Linux) | — | — | — | Darwin not checked. `replaceItemAt` is not used. `.atomic` and the inode test should run in the M3 macOS lane. |
| JSON `Double` formatting on Darwin (R-7) | — | — | — | — | Not verified on Darwin. iOS 26 uses the same swift-foundation encoder; the macOS lane should rerun AC-M1-05. |

Device ACs: none in M1 (brief).

### Things the reviewer should look at closely
- **The R-8 decision** (decision 5; ADR-0004 options 4–6).
  - The fault-injection writers stand in for the atomic primitive, so they test our code *around* the primitive. They
    show that we encode first, write in one call, never remove or truncate the file on failure, never cache B, and
    never overwrite on a failed edit.
  - The atomicity of the rename itself is Foundation's `.atomic`. Its only evidence is the inode-change test and the
    Linux probe. If the Reviewer wants our own staging file and rename, note that it needs a libc `rename` outside
    Foundation (ADR-0001, AC-M1-23).
- **`@testable import TendCore`** in five new test files. It is needed for the internal seam. CI uses debug `swift test`,
  so this works there. A release-mode test run would not compile these files.
- **Typed `async throws(HouseholdStoreError)` protocol requirements, met by synchronous actor methods.** This is valid
  in Swift 6.2. Callers get a concrete error type without casting.
- **`load()` returns empty for a missing file** (decision 1). This is the one path that returns an empty household.
  It is reached only when no file exists at the path.
- **Non-finite dates.** `Date(timeIntervalSinceReferenceDate: ±.infinity)` passes the model invariants. The file store
  cannot save it (`writeUnsuccessful`), but the in-memory store accepts it. See Known limitations.
- **Generator realism for WI-M1-03/04.** Windows sit around a fixed `now` (`Fixtures.referenceDate`, overridable). The
  generator does not try to land windows on allowed slots; the selector tests in WI-M1-03 should add their own bias if
  they need many valid tasks.
- **Design vocabulary.** A grep of `Persistence/` for the design-forbidden list (escalation words, D-2 counter or
  original-window names, D-3 score words, UX-2 bypass names) and for `URL(string`, `Stream(` and `random(` finds no
  hits.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| Non-finite dates pass the model invariants. The file store rejects them on save (`writeUnsuccessful`); the in-memory store accepts them. | Minor | PO/Developer: possibly a finiteness invariant in a later item (it would add a `TaskInvariantViolation` case, which needs a design-list change) |
| Two `JSONFileHouseholdRepository` instances on one file are not coordinated (last save wins whole) | Minor (documented) | App layer: one instance per file (M3) |
| Darwin run of AC-M1-05/07 and the R-8 inode test | Minor | M3 macOS CI lane (ADR-0003; `.github/**` is human-merged) |
| ADR-0004 stays `Proposed` until Reviewer confirmation | — | Reviewer (WI-M1-02 review) |
| `docs/architecture/README.md` index lacks ADR-0004 (and 0001…0003) | Minor | Product Documenter |
| `docs/product/TRACEABILITY.md` rows for AC-M1-04…07 and AC-M1-25 (repository) | — | Product Documenter |
| Rebase onto WI-M1-01 as merged, including the Q17/Q18 scanner change, and rerun the scans. File I/O is already confined to `JSONFileHouseholdRepository.swift`. | — | Orchestrator / Developer |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The repository is programmatic. |
| UX-2 Rule of Three | pass | No API returns "what to do now" items. `load()` returns the household for engine use, not for display, and has no ranking or "next" semantics. |
| UX-3 Zero-Guilt | pass | No new model field (D-2). No counter, history or score (D-3). Error names are calm codes (`writeUnsuccessful`, not a banned word). AC-M1-02 scan: 15 files, 0 hits. A failed load or save never silently loses data (AC-M1-06/07), which supports "never lose a reminder for a bill" (S-M1-02). |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | Writes only to a caller-supplied local file URL. No networking API (AC-M1-23 scan, 0 hits). No `URL(string:`. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Orchestrator | Developer | accepted | WI-M1-02 started on `m1/persistence`, stacked on `m1/core-model` (WI-M1-01 under review). Mid-task note: PO decisions Q17/Q18 confine file I/O to `JSONFileHouseholdRepository.swift`. This is followed. |
| 2026-11-20 | Developer | Reviewer (via Orchestrator) | sent (H4) | WI-M1-02 built test-first. 73 tests, 11 suites, 0 failures, 0 warnings on Linux Swift 6.2.4. ADR-0004 Proposed. R-8 finding: `replaceItemAt` loses data on Linux, so the store uses `.atomic`. No naming deviations. Not verified on macOS. Not committed. |
