# M1 Developer Handoff — WI-M1-01 (later sections: WI-M1-02…04)

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
- **Tests** `Tests/TendCoreTests/`: 42 Swift Testing tests in 6 suites, 168 test cases once the parameterised arguments
  are expanded (round 2; round 1 had 40 tests and 126 cases).
  - `Support/SourceScanner.swift`: a small Swift lexer.
    - Removes `//`, `///` and nested `/* */` comments.
    - String-literal aware: `"…"`, `"""…"""`, raw `#"…"#` and `#"""…"""#`, escapes, and interpolation `\(…)` /
      `\#(…)`, whose contents are lexed as code again (N-2).
    - Whole-token camelCase / underscore / digit tokeniser for AC-M1-02.
    - AC-M1-23 rules, in two kinds (round 2, review F-1/F-2, brief AC-M1-23 as updated with Q17/Q18):
      - **identifier boundary** (N-1) for time, ID, randomness and URL patterns: `Date()`, `Date.now`,
        `Date(timeIntervalSinceNow`, `timeIntervalSinceNow`, `Calendar`/`TimeZone`/`Locale` `.current` and
        `.autoupdatingCurrent`, `ProcessInfo`, `UUID()`, `SystemRandomNumberGenerator`, `URL(string:`,
        `arc4random*`, `drand48`/`erand48`/`lrand48`/`srand48`, `rand(`, `random()`. `Date()`, `UUID()`,
        `Date(timeIntervalSinceNow` and `URL(string:` also match the explicit `.init` spelling (`Date.init()`);
      - **implicit-member `.now`** with no receiver (`= .now`, `(at: .now`, `return .now`, `?? .now`,
        `cond ? .now :`, `[.now]`, `a > .now`), reported as `Date.now`. A dot with a receiver is clean: `moment.now`,
        `self.now`, `f().now`, `xs[0].now`, `x?.now`, `x!.now`, `Box<T>.now`, and a chain continued on the next line;
      - **camelCase word boundary** for networking names, using `subTokens(of:)` (the AC-M1-02 split). `URLSession`,
        `URLRequest`, `URLConnection`, `NSURLConnection`, `Socket`, `NSStream` and `getStreamsToHost` are hits when
        their words appear consecutively anywhere in an identifier (`URLSessionWebSocketTask`, `CFSocketCreate`,
        `SocketPort`, `NSMutableURLRequest`). `Stream(`, `InputStream(`, `OutputStream(` and `Host(` are hits when
        their words end an identifier that is called (`GhostHost(`, `MyAsyncStream(`). `Host.current` is a hit when
        an identifier ending in `Host` is followed by `.current…`;
      - **exactly two exemptions** from `Stream(`: the identifiers `AsyncStream` and `AsyncThrowingStream` (named
        constant `streamCallExemptions`, brief Q17);
      - **`contentsOf:`** is banned except in files whose name is in the named constant `contentsOfAllowlist` =
        `["JSONFileHouseholdRepository.swift"]` (brief Q18; that file arrives in WI-M1-02). The real-source scan logs
        the allowlist and checks that no allowlisted file name appears more than once under `Sources/`;
      - a balanced-paren check for `using:`-less `.random(` / `.randomElement(` / `.shuffled(` / `.shuffle(`, an
        `import` check and an `http(s)://` literal check (unchanged).
  - `Support/Fixtures.swift`: fixed dates and UUIDs (no `Date()` / `UUID()`).
- **ADRs:** 0001 (module boundary, Accepted: a technical decision within CLAUDE.md §3), 0002 (Core Data +
  `NSPersistentCloudKitContainer` proposed, `CKSyncEngine` as fallback; Proposed until a macOS spike), 0003 (XcodeGen
  proposed; Proposed until the M3 app target).
- **Repo:** `.gitignore` (`.build/`, `.swiftpm/`, Xcode user data). Round 2 (review F-4): `Package.resolved` is no
  longer ignored, so any future dependency pin (ADR-approved) gets committed.
- **Round 2 also:** fixed the `InvariantCase` doc comment (review F-6). No model (`Sources/`) change in round 2.
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
| AC-M1-23 | **Scan:** "AC-M1-23: only \`import Foundation\`, no ambient time, randomness or networking API in TendCore/Sources" (log: `11 files scanned`, `11 import statements found`, `contentsOf: allowlist ["JSONFileHouseholdRepository.swift"], 0 allowlisted files present`, `0 hits`). **Negative (planted):** "AC-M1-23 negative: every banned pattern planted in code is detected" (74 fixtures, round 2: incl. `Date.init()`, `UUID.init()`, nine implicit `.now` forms, `URLSessionWebSocketTask`, `URLSessionConfiguration`, `URLSessionDataTask`, `SocketPort(`, `CFSocketCreate(`, `CFStreamCreatePairWithSocketToHost(`, `GhostHost(`, `WebSocketLike`, `NSStreamDelegate`, `NSMutableURLRequest`, `InputStream(`, `OutputStream(`, `getStreamsToHost`, `URL(string:` and `URL.init(string:`, `arc4random()`, `arc4random_uniform(`, the four `*rand48`, `rand()`, `random()`, `Data(contentsOf:)`, `String(contentsOf:)`); "AC-M1-23 coverage: the planted fixtures exercise every pattern in the closed list" (every rule name has at least one planted fixture); "AC-M1-23 negative: imports other than Foundation are detected" (8 cases); "AC-M1-23: \`import Foundation\` alone is allowed; imports in comments and strings are ignored"; "N-1: near-misses at identifier and camelCase word boundaries are not reported" (`startDate()`, `makeUUID()`, `Calendar.currentWeek`, `myCalendar.current`, `Date.nowish`, `Sockets`, `XURLSessionLike`, `upstream(`, `Hostname(`, `Host.currently`, `operand(`, `brand(`, `randomize(`, `drand(48)`, `URL(fileURLWithPath:`, `myURL(string:`, `contentsOfFile`, `using:` variants incl. nested parens, …); "Review F-2: \`.now\` with a receiver is not reported (moment.now, self.now, chains, optional chaining)"; **positive (Q17/Q18):** "AC-M1-23 positive: AsyncStream( and AsyncThrowingStream( (Q17) and allowlisted contentsOf: (Q18) are not reported" (also shows `MyAsyncStream(` is still a hit, the allowlist covers only `contentsOf:`, and other file names are not allowlisted); "AC-M1-23 negative: banned patterns in comments and plain string text are ignored". **Linux build:** `swift build`/`swift test` with `-warnings-as-errors` | PASS (Linux container, round 2) |
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
| *Round 2:* switch off implicit `.now` detection | planted-pattern test (9 cases) |
| *Round 2:* treat every identifier word before `.now` as a keyword (no receivers) | the F-2 receiver near-miss test |
| *Round 2:* treat whitespace after `?`/`!`/`>` as still a receiver | planted-pattern test (3 cases) |
| *Round 2:* networking names back to whole-identifier match | planted-pattern test (10 cases) |
| *Round 2:* drop the `.init` spelling from `Date()` | planted-pattern test (2 cases) |
| *Round 2:* remove the `AsyncStream` exemption, or widen it to any name containing `Async` | the Q17/Q18 positive test |
| *Round 2:* ignore the `contentsOf:` allowlist | the Q17/Q18 positive test |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| `swift build --build-tests -Xswiftc -warnings-as-errors` (0 warnings) | ✔ container, Swift 6.2.4 (swift-6.2.4-RELEASE, x86_64-unknown-linux-gnu) | — | — | — | macOS / Xcode 26: no Mac in this environment |
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors`: 42 tests in 6 suites (168 cases), 0 failures, 0 skipped, about 0.3 s (round 2, clean `.build`) | ✔ container | — | — | — | Linux CI (`swift:6.2-noble`, `.github/workflows/ci.yml`) runs the same command on the PR; the Reviewer/Gatekeeper should confirm the CI log shows "Test run with 42 tests" (R-6: tests really ran) |
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
  - ~~(e) Identifier-boundary matching for networking names.~~ **Withdrawn in round 2** (review F-1): networking names
    now match at camelCase word boundaries; only the time, ID, randomness and URL patterns keep identifier boundaries.
  - (f) *Round 2, known limit (review F-2):* the implicit `.init()` with a type annotation, `let d: Date = .init()` (and
    `UUID` likewise), cannot be typed by a lexical scanner and is **not** reported. Reviewer check (R-12).
  - (g) *Round 2, possible false positive:* `case .now:` on an enum that has its own `now` case is reported as
    `Date.now`, because the scanner cannot see the type. `TendCore` has no such enum; rename the case if one is added.
  - (h) *Round 2, AC side effects for later items (PO awareness, not a scanner bug):*
    - `AsyncStream.makeStream(of:)` hits `Stream(`, because `makeStream` is not one of the two exempt names. Use
      `AsyncStream(…) { continuation in … }` instead, or ask the PO for an exemption (Q17 forbids a Developer
      allowlist).
    - `contentsOf:` also matches harmless collection APIs such as `array.append(contentsOf:)` and
      `insert(contentsOf:at:)` outside the allowlisted file. WI-M1-03/04 code must avoid that label
      (for example `+=`, or a loop) unless the PO widens Q18.
    - The POSIX lower-case `socket(` is not in the closed list (`Socket` is case-sensitive). On Darwin it is reachable
      through `import Foundation`. This is a PO question if wanted; it does not block.
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
| Scanner blind spots (a)–(d), (f), (g) above | Minor | Reviewer check per PR (R-12) |
| (h) `makeStream(` and `append(contentsOf:)` are caught by the AC as written; lower-case `socket(` is not in the list | Minor | PO (Q17/Q18 follow-up), only if a later item needs them |

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
| 2026-11-20 | Reviewer | Developer (via Orchestrator) | returned (round 1: CHANGES REQUIRED) | F-1, F-2 Major; F-3 to PO (became Q18); F-4 Minor; F-5, F-6 Nit. PO updated AC-M1-23 (Q17, Q18). |
| 2026-11-20 | Developer | Reviewer (via Orchestrator) | sent (round 2) | F-1 fixed (camelCase word-boundary networking rules; N-1 fixture corrected; planted positives added). F-2 fixed (`Date.init()`, `UUID.init()`, implicit `.now`; receiver near-misses; `let d: Date = .init()` listed as known limit (f)). AC-M1-23 Q17/Q18 additions implemented, with named constants `streamCallExemptions` and `contentsOfAllowlist` and the required positive test. F-4 fixed (`Package.resolved` no longer ignored). F-6 fixed. F-5 still watched. Scanner and tests only; no `Sources/` change. 42 tests, 168 cases, 0 failures, 0 warnings on a clean Linux build. Every new rule was shown to turn red under mutation. Not committed. |
