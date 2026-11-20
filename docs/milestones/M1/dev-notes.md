# M1 Developer Handoff — WI-M1-01, WI-M1-02, WI-M1-03 (later section: WI-M1-04)

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

---

## WI-M1-03 — Slot calendar and `E(a, D)`, context filter, `NowSelection` and the Rule-of-Three selector, gate property tests

- **Owner:** Developer  ·  **Branch:** `m1/rule-of-three-selector` (from `main` at `7556df7`, which includes WI-M1-01 and
  WI-M1-02)  ·  **PR:** _opened by the Orchestrator (link to be added)_  ·  **ADRs:** none new. ADR-0001 applies
  (Foundation only; `now`, calendar, time zone and weather are injected).
- **Requirements:** FR-B1, UX-2, plus the shared basis for FR-B2; S-M1-03, S-M1-04. **Owns** AC-M1-08…16. AC-M1-14 is
  a gate AC. AC-M1-02 and AC-M1-23 stay green over the larger `Sources/` tree. Risks R-3, R-4, R-5 and R-12.
- **Inputs:** [brief.md](brief.md) v2 (Definitions: Daypart, Slot, energy match, weather-safe, effective state, window
  open/passed, contextually valid, `E(a, D)`; Q1–Q3, Q7, Q11–Q14), [design.md](design.md) (`Moment`, `NowSelection`,
  `NowSelector`, `nextEligibleWindow(from:duration:)`, the UX-2 bypass ban, D-1, D-3), [plan.md](plan.md) (WI-M1-03
  scope).
- **Out of scope:** the rescheduler, completion and determinism (WI-M1-04). Nothing in this item changes a task.

### What changed
- **`Sources/TendCore/Selection/`** (5 new files, Foundation only; no change to the model or persistence files):
  - `Moment.swift`: `public struct Moment` with the design's members (`now`, `calendar`, `timeZone`, `weather`,
    `energy`). The injected `timeZone` is applied to the stored calendar, so the zone argument wins over the
    calendar's own zone.
  - `SlotCalendar.swift`:
    - `Daypart.startHour` (internal).
    - Internal `Slot` (daypart, owning weekday, `[start, end)`) and internal `SlotCalendar`:
      - wall-clock boundaries come from `date(bySettingHour:…, matchingPolicy: .nextTime, repeatedTimePolicy:
        .first)` (Q11);
      - days are anchored at local noon, which exists on every day;
      - `slot(containing:)` checks the day's own four slots and the previous day's night;
      - `nextAllowedStart(from:dayparts:weekdays:)` gives `s` in `E(a, D)`.
    - The public `HouseholdTask.nextEligibleWindow(from:duration:calendar:timeZone:)` returns
      `(windowStart: s, windowEnd: s + duration)`.
  - `ContextValidity.swift`: the brief's "contextually valid at `now`" as an **internal**
    `isContextuallyValid(in:slotOfNow:)`. It uses these helpers:
    - `EnergyLevel.accepts(_:)` (Q1);
    - `WeatherCondition.isSafeForWeatherDependentTasks` (Q3);
    - `effortForMatching`: maintenance counts as low; the stored effort is unchanged;
    - `isOfferable(at:)`: effective state, where a deferral whose rest is over counts as active (Q12, D-1).
  - `NowSelection.swift`: `public struct NowSelection` with `capacity = 3`, `empty`, `init?(items:)`, `items`, `count`
    and `isEmpty`. Storage is three private optionals (`first`, `second`, `third`), so the type has nowhere to put a
    fourth item. `init?(items:)` returns `nil` for more than 3 items or for a repeated task ID. There is no mutating API.
  - `NowSelector.swift`: `public enum NowSelector`.
    - `select(from: Household, in: Moment)` and `select(from: [HouseholdTask], in: Moment)` both return `NowSelection`.
    - The slot of `now` is computed once per call. One pass keeps a running top three; there is no full sort.
    - `ranksBefore` is the exact AC-M1-16 key: no score, priority or weight, and no randomness.
- **Tests** (`Tests/TendCoreTests/`): 29 new test functions in 3 new suites. **104 tests in 14 suites in total.**
  - `ContextValidityTests.swift` covers AC-M1-08…12. Each case is checked through the **public** API (a one-task
    household is selected exactly when the task is valid) **and** against the oracle. The expected values are tables
    written by hand from the brief, so the oracle is tested as well.
  - `NowSelectorTests.swift` covers AC-M1-13…16: the gate property and the ranking examples. It also holds
    `TieCorpus`, a set of tie-heavy households for the AC-M1-16 property.
  - `SlotCalendarTests.swift`: `E(a, D)` examples, the DST policy, night slots across DST, a calendar day that does not
    exist (Samoa, 30 December 2011), and a 1,000-case property against a brute-force oracle. It uses
    `@testable import` to reach `SlotCalendar.wallClock` and `slot(containing:)`.
  - `Support/ContextOracle.swift`: the **independent oracle** (R-4). See "Things the reviewer should look at closely".
  - `Support/SelectionCorpus.swift`: the seeded property corpus. It reuses `HouseholdGenerator` and `SplitMix64`
    (WI-M1-02) and adds a random context per seed: 16 named zones, `now` within ±3 years of the reference date with a
    sub-second part (a quarter of cases within ±12 h of a DST change in the chosen zone), weather and energy. The
    corpus is built once per test process and shared.
  - `Support/SelectionFixtures.swift`: named zones, a Gregorian calendar built in the test, local-time and UTC
    instants, `openTask`, and `isSelected`.
- **Docs:** this section and the title line of this file.
- **Not touched:** the WI-M1-01/02 sources, the scanner, `CLAUDE.md`, `.claude/**`, `.github/**`,
  `docs/governance/**`, `docs/PRD.md`, `docs/milestones/STATUS.md`.

### Public API added (AC-M1-13 listing, for the Reviewer's naming, UX-2, D-2 and D-3 check; R-12)
```
public struct Moment: Hashable, Sendable {
  public let now: Date; public let calendar: Calendar; public let timeZone: TimeZone
  public let weather: WeatherCondition; public let energy: EnergyLevel
  public init(now: Date, calendar: Calendar, timeZone: TimeZone, weather: WeatherCondition, energy: EnergyLevel) }
public struct NowSelection: Hashable, Sendable {
  public static let capacity = 3; public static let empty: NowSelection
  public init?(items: [HouseholdTask])            // nil for > 3 items or a repeated task ID
  public var items: [HouseholdTask] { get }       // ≤ 3, ranked
  public var count: Int { get }; public var isEmpty: Bool { get } }
public enum NowSelector {
  public static func select(from household: Household, in moment: Moment) -> NowSelection
  public static func select(from tasks: [HouseholdTask], in moment: Moment) -> NowSelection }
extension HouseholdTask {
  public func nextEligibleWindow(from anchor: Date, duration: TimeInterval, calendar: Calendar, timeZone: TimeZone)
    -> (windowStart: Date, windowEnd: Date) }
```
- **Every way to ask "what to do now" returns `NowSelection`.** No public API returns an unbounded list of "now"
  items. The validity predicate, `Slot`, `SlotCalendar`, the ranking comparator and the working array inside `select`
  are all `internal` or `private`. `[HouseholdTask]` appears in the public API only as an *input*
  (`select(from:)`, `NowSelection.init?(items:)`) and as `NowSelection.items` (≤ 3). `Household.tasks` (WI-M1-01) is
  the stored household, not a "now" surface.
- **Naming-list deviations (one):** `nextEligibleWindow(from:duration:)` has two extra arguments,
  `calendar:timeZone:`. Reason: `E(a, D)` must resolve slots in the injected calendar and zone (CLAUDE.md §3). A
  method on the task is the only place that knows the allowed dayparts and weekdays. The labels match the design's
  `Rescheduler.reschedule(_:at:calendar:timeZone:)`. The name itself is unchanged and passes the forbidden list.
- **Additions not in the naming list:** `NowSelection.empty`, `NowSelection.count`, and a second `select(from:in:)`
  overload over `[HouseholdTask]`. All of them are capped or are inputs.
- No new stored field on any model type (D-2). Nothing ranks by time elapsed since a window ended (D-3). A grep of
  `Selection/` for the design-forbidden list finds only the comment that says there is no score.

### Decisions the Reviewer should know (technical, reversible; no product meaning changed)
1. **Slots are intervals built from resolved boundaries.** Membership is `start ≤ t < end`; it is not the local hour.
   With the Q11 policies, the slots tile time with no gap. On a fall-back night the repeated hour stays inside the
   slot it started in.
2. **A day is anchored at local noon.** Day arithmetic uses `date(byAdding: .day)` from noon, then sets the boundary
   hour, so a nonexistent midnight cannot shift a day (for example `America/Santiago`).
3. **`E` searches up to 15 days ahead and starts one day early**, because before 05:00 the anchor is in the previous
   day's night slot. Allowed sets are never empty (AC-M1-25), so a real slot is always found within 8 days. The
   property's longest move is 155 h. If the calendar cannot resolve a day at all, `E` returns `s = anchor`. This is
   documented, cannot be reached with Gregorian, and is never a crash.
4. **A repeated task ID in the input:** only the better-ranked copy can be chosen, and `NowSelection` refuses
   duplicates. The repository already keeps IDs unique (upsert), so this is defence in depth. It is not a product
   rule, because the brief does not define duplicate IDs.
5. **`select` returns `NowSelection(items:) ?? .empty`.** The fallback cannot fire, because the loop keeps ≤ 3
   distinct IDs. The property tests would show it if it did (AC-M1-15 count check).
6. **`windowEnd = s.addingTimeInterval(D)`**, exactly as the brief writes `s + D`. See the AC-M1-20 risk under Known
   limitations.

### AC coverage
| AC | Test(s) (Swift Testing display names; suite) | Result |
|---|---|---|
| AC-M1-08 | "AC-M1-08: low energy accepts only low effort (incl. maintenance), normal adds normal, high accepts all". 3 × 4 parameterised (energy × low / normal / high / high deep clean in maintenance). Also asserts the stored effort stays `high`. | PASS (Linux), 12 cases |
| AC-M1-09 | "AC-M1-09: at each daypart boundary a task is valid exactly when the local daypart is allowed; default dayparts are quiet at night" (12 boundaries: 04:59, 04:59:59.999, 05:00, 11:59, 11:59:59.999, 12:00, 16:59, 16:59:59.999, 17:00, 21:59, 21:59:59.999, 22:00, Berlin). Each case checks the 4 single-daypart tasks, all 15 non-empty daypart sets and the default set. "AC-M1-09: one instant in two injected time zones follows each zone's local daypart" (Tokyo 19:00 / Los Angeles 02:00). "AC-M1-09: the injected time zone wins over the time zone carried by the injected calendar". | PASS (Linux) |
| AC-M1-10 | "AC-M1-10: a weekend-only task is valid on Saturday and Sunday only; the night slot belongs to the day it starts" (15 cases: 10:00 on each of 7 days; Friday 23:00 ✗; Saturday 01:00 ✗; Saturday 04:59:59.999 ✗; Saturday 05:00 ✓; Saturday 23:00 ✓; Monday 01:00 ✓; Monday 04:59:59.999 ✓; Monday 05:00 ✗). "AC-M1-10: an instant that is Sunday 10:00 in one injected zone and Monday in another follows the injected zone" (Los Angeles / Auckland). | PASS (Linux) |
| AC-M1-11 | "AC-M1-11: a weather-dependent task is valid only in clear or cloudy weather; others ignore the weather" (5 cases, both tasks each). | PASS (Linux) |
| AC-M1-12 | "AC-M1-12: state and half-open window boundaries decide validity exactly as the brief lists" (9 cases a–i, sub-second `now`). (c), (d), (e), (h) are valid; (a), (b), (f), (g), (i) are not. Also "AC-M1-12: maintenance and resurfaced tasks with an open window are valid; the selector does not change them". | PASS (Linux) |
| AC-M1-13 | "AC-M1-13: NowSelection holds 0 to 3 items and cannot be constructed with 4 or more" (4…10 → `nil`). "AC-M1-13: NowSelection rejects the same task twice". "AC-M1-13: NowSelection stores exactly three optional task slots, so a fourth item has nowhere to go" (Mirror log: `["first: Optional<HouseholdTask>", "second: Optional<HouseholdTask>", "third: Optional<HouseholdTask>"]`). "AC-M1-13: the selector returns a NowSelection of 3 even when 100 tasks are valid". "AC-M1-13 / Q13: the selector returns tasks unchanged and does not move a task whose window ended". Public API listing above. | PASS (Linux) + Reviewer API inspection |
| AC-M1-14 (Gate) | "AC-M1-14 (Gate): over 1,000 seeded households of 50-500 tasks every selection has at most 3 items, no duplicates, and every item passes the independent oracle". Log: `seeds 1...1000, 1000 households, 273931 tasks (min 50, max 500 per household), 10147 contextually valid per the oracle`; `selection sizes 0/1/2/3 = 20/42/49/889; 16 time zones, 5 weather values, 3 energy levels, 134 moments within 12 h of a DST change; task states seen: [active, completed, deferred (rest over), deferred (resting), maintenance, resurfaced]`. Each item is also checked to be an unchanged element of the household. Every failure message prints the seed and context. Window positions (ended, ends at `now`, open, starts at `now`, upcoming) come from the generator; their coverage is proven by WI-M1-02's `GeneratorTests`. | PASS (Linux) |
| AC-M1-15 | "AC-M1-15: the selection size equals min(3, number of contextually valid tasks) for 50-500 and 0-49 task households". Log: `seeds 1...1000 (50-500 tasks) and 100001...101000 (0-49 tasks), 2000 households, 14 with no tasks; selection sizes 0/1/2/3 = 494/307/197/1002`; the test requires every size to occur. "AC-M1-15: an empty household and a 500-task household with nothing valid give an empty selection without error". | PASS (Linux) |
| AC-M1-16 | Examples: "…five resurfaced criticals compete; only the three with the earliest windowEnd are returned, ahead of an earlier active task"; "…equal windowEnd ties go to critical tasks first, then ascending ID"; "…a non-resurfaced critical ranks after a non-critical with an earlier windowEnd, and before one with the same windowEnd"; "…the order does not depend on the order of the household's tasks" (50 seeded shuffles plus reversed). Property: "AC-M1-16: over the property households and 500 tie-heavy households the items are exactly the oracle's sorted first min(3, n)". Log: `2000 property households … and 500 tie-heavy households (seeds 200001...200500) match the oracle's order; 434 tie-heavy selections hold a windowEnd tie, 1117 resurfaced items selected`. | PASS (Linux) |
| `E(a, D)` (basis for AC-M1-03/17…21, owned by WI-M1-04) | "E(a, D): hand-computed examples, incl. slot starts, the night slot owned by its start day, and a full week ahead" (11 cases); "E(a, D): the task is not changed and only the requested duration is used"; "R-3 / Q11: a nonexistent local time resolves to the next instant, a repeated one to its first occurrence"; "R-3: a night slot across a DST change runs from 22:00 to 05:00 local (6 h in spring, 8 h in autumn) and belongs to Saturday"; "R-3: E(a, D) on DST days in America/New_York" (8 cases); "R-3: a calendar day that does not exist (Samoa skipped Friday 30 December 2011) moves a Friday task to the next Friday"; "E(a, D): over 1,000 seeded tasks, anchors and time zones the window equals the brute-force oracle's, with windowEnd = s + D". Log: `seeds 300001...301000, 1000 cases, 265 start at the anchor, 735 move to a later slot, 156 anchors within 12 h of a DST change, longest move 155 h`. | PASS (Linux) |
| AC-M1-02, AC-M1-23 (still clean) | `AC-M1-02 scan: 20 files scanned … 0 hits`; `AC-M1-23 scan: 20 files scanned … 0 hits`. The new code never writes `.now` without a receiver (only `moment.now`), and uses no `append(contentsOf:)`, no `random`, and no `Calendar.current`. | PASS (Linux) |

**Tests fail when the behaviour breaks.** Each mutation was applied to `Sources/TendCore/Selection/`, the full suite was
run, and the source was restored (checked with `diff` against a saved copy):

| Mutation | Tests that went red |
|---|---|
| M-a: normal energy accepts high effort | AC-M1-08, AC-M1-14 (oracle), AC-M1-15, AC-M1-16 property (673 issues) |
| M-b: maintenance not counted as low | AC-M1-08, AC-M1-12 maintenance test, AC-M1-15, AC-M1-16 property |
| M-c: `unknown` weather counted as safe | AC-M1-11, AC-M1-14, AC-M1-15, AC-M1-16 property |
| M-d: weekday ignored | both AC-M1-10 tests, AC-M1-14, AC-M1-15, AC-M1-16 property (3,425 issues) |
| M-e: ranking keys 2 and 3 swapped | AC-M1-16 critical-vs-non-critical example, AC-M1-16 property |
| M-f: DST repeated-time policy `.last` | R-3 / Q11 DST policy test |
| M-g: `E` never starts at the anchor | `E` examples, DST cases, `E` property |
| M-h: `E` ignores the previous day's night slot | `E` examples, DST cases, `E` property |
| M-i: the running top three drops the best item | all four AC-M1-16 tests |

### Verification environment
| Check | Linux `swift test` | macOS CI | Simulator | Device | Not verified (why) |
|---|---|---|---|---|---|
| `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors`: **104 tests in 14 suites passed**, 0 failures, 0 skipped, 0 warnings, about 15 s | ✔ container, Swift 6.2.4 (`swift:6.2-noble` via the Docker wrapper) | — | — | — | Linux CI runs the same command on the PR. The Gatekeeper should confirm "Test run with 104 tests" in the CI log (R-6). |
| Runtime (R-5) | ✔ The shared corpus is built once (about 5 s). AC-M1-14: 5.6 s; AC-M1-15: 5.8 s; AC-M1-16 property: 6.2 s (these run in parallel and share the corpus). The whole run is about 15 s of wall time, against about 10 s before this item. | — | — | — | Well inside the 20-minute CI timeout |
| Named zones and DST (R-3): New York spring and autumn 2026, Samoa 2011, 16 zones in the properties | ✔ container (tzdata present) | — | — | — | **Darwin not checked.** Foundation's `date(bySettingHour:…)` policies were probed on Linux only. The macOS lane (M3) should rerun `SlotCalendarTests` and the gate properties. |
| AC-M1-08…16 | ✔ container | — | — | — | — |

No AC in this item needs a device.

### Things the reviewer should look at closely
- **Oracle independence (R-4), in `Support/ContextOracle.swift`.** The oracle calls no `TendCore` function. It only reads
  public stored fields and `Moment`'s fields. Each step uses a different method from production:
  - **daypart and weekday:** the oracle reads the local `hour` and `weekday` components and has a written-out hour
    table. "Before 05:00 belongs to the previous weekday" is modular arithmetic on the weekday number. Production
    builds `[start, end)` slot intervals from resolved boundaries.
  - **energy, weather and state:** the oracle uses written-out tables. Production uses `switch`.
  - **ranking:** the oracle does a full sort on a tuple key and takes the prefix. Production keeps a running top three
    with a comparator.
  - **`E`:** the oracle scans forward in 15-minute steps. Production walks slot boundaries.

  Both sides share the injected `Calendar` (Foundation) and the brief's definitions; nothing else is shared. The
  hand-written tables in `ContextValidityTests` check the oracle too.
- **Oracle assumption.** The 15-minute brute-force `E` oracle assumes that every zone offset and DST change falls on a
  quarter hour. That holds for all 16 test zones and for Samoa in the years used. It does not hold for historical
  (pre-1970) local mean times, which the tests do not use.
- **Two ways to classify the same instant.** The hour-based oracle and the interval-based production code could only
  disagree in a zone whose DST change crosses a daypart boundary hour (05, 12, 17 or 22). No zone in the corpus does
  this. 134 gate moments and 156 `E` anchors fall within 12 h of a DST change, and all agree.
- **`@testable import TendCore`** in `SlotCalendarTests.swift`. It is the only new use, and it reaches
  `SlotCalendar.wallClock` and `slot(containing:)` to pin the Q11 DST policy directly. Every other new test uses the
  public API.
- **The one naming deviation** (`calendar:timeZone:` on `nextEligibleWindow`) and the extra `NowSelection.count`,
  `NowSelection.empty` and array overload (see the API listing).
- **Seeds and toolchains.** The corpus seeds replay on the same toolchain. Review W2-F6 also applies here, because
  `Int.random(in:using:)` maps seeds to ranges.

### Known limitations / follow-ups
| Item | Severity | Ticket |
|---|---|---|
| **Risk for WI-M1-04, AC-M1-20:** `windowEnd = s + D` is a `Double` addition. `(s + D) − s` can differ from `D` by 1 ulp for some `s`, so "`windowEnd − windowStart` identical after N passes" may not hold bit-for-bit. `E` here does exactly what the brief writes (tests check `windowEnd == s.addingTimeInterval(D)`). WI-M1-04 should measure this over its N = 1…60 property before choosing a fix. Options are to compare durations within 1 ulp (needs a PO reading of "identical") or to round `s` to a representable grid. No AC change is proposed here. | Minor (watch) | Developer, WI-M1-04 |
| Darwin rerun of the DST and slot tests (R-3) | Minor | M3 macOS CI lane |
| Duplicate task IDs have no product rule; the selector keeps the better-ranked copy (decision 4) | Nit | PO, only if duplicate IDs can ever arise (M2 parser, M5 sync) |
| `docs/product/TRACEABILITY.md` rows for AC-M1-08…16 | — | Product Documenter |

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | pass | The cap is in the engine type. `NowSelection` has three storage slots, and its only initialiser rejects 4+ items or a repeated task. Both `select` overloads return it. No public unbounded "now" list exists: the predicate, slots, comparator and working array are internal or private. Proven by AC-M1-13 and by the AC-M1-14/15 properties over 2,000 households. |
| UX-3 Zero-Guilt | pass | No new stored field and no counter (D-2). Ranking is the fixed four-key order; nothing grows with time (D-3). The code says "rest over" (`isRestOver`, D-1), never "lapsed". Test names and logs say "window ended", never "missed". An empty selection is a normal result, not an error. AC-M1-02 scan: 20 files, 0 hits. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | Pure computation on injected values. Weather is an input and is never fetched (Q8). AC-M1-23 scan: 20 files, 0 hits. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Orchestrator | Developer | accepted | WI-M1-03 on `m1/rule-of-three-selector`. Mid-task: the branch was brought up to date with `main` at `7556df7` (PRs #3, #5, #6 merged; fast-forward). |
| 2026-11-20 | Developer | Reviewer (via Orchestrator) | sent (H4) | Built test-first. 104 tests in 14 suites, 0 failures, 0 warnings on Linux Swift 6.2.4. AC-M1-08…16 PASS on Linux, with the AC-M1-14 gate over 1,000 households. Nine mutations, all red. One naming deviation (`calendar:timeZone:` on `nextEligibleWindow`). AC-M1-20 floating-point risk flagged for WI-M1-04. Not verified on Darwin. |
