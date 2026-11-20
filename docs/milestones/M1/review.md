# M1 Code Review

One section per work item. Each section follows `docs/governance/templates/review.md`. Re-reviews add a new round inside
the same work-item section.

---

## WI-M1-01 — [PR #5](https://github.com/rmaheedharan/Tend/pull/5) (`m1/core-model`, commit `d6b7950`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Diff reviewed:** `git diff 0bc20bb d6b7950` (24 files, +2,234). **Owned ACs:** AC-M1-01, AC-M1-02, AC-M1-23,
  AC-M1-25 (construction and `Codable` decode). **Inputs:** [brief.md](brief.md) v2, [design.md](design.md) (binding
  naming list, forbidden names, D-1…D-3), [plan.md](plan.md) (WI-M1-01 scope, R-2, R-12), [dev-notes.md](dev-notes.md).
- **Verified by the Reviewer (Linux container, Swift 6.2 via Docker wrapper):**
  `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` → "Test run with 40 tests in 6 suites
  passed", 0 failures, 0 warnings, 0 skipped. Scan logs: `AC-M1-02 scan: 11 files scanned … 0 hits`,
  `AC-M1-23 scan: 11 files scanned … 0 hits`. GitHub check run "TendCore swift test (Linux)" on head `d6b7950` is
  `success` (R-6: the package exists at the path CI expects; local run confirms tests > 0).
- **Reviewer probes** (a throwaway copy of the package in the session scratchpad with one extra probe test; nothing in
  the repo was changed) were used to test the lexer and the API rules against inputs outside the Developer's fixtures.
  The results are quoted in the findings.

### Summary
The model is clean, small and well tested. `HouseholdTask` has exactly the 15 naming-list fields, all
`public internal(set)`. A single throwing initialiser (`throws(TaskInvariantViolation)`) enforces the nine invariants,
and `init(from:)` reuses it. `TaskState` is the closed five-case set, and its custom `Codable` rejects unknown names.
`PromptTone` has one case. Every type is `Sendable`, with no `@unchecked`, `nonisolated(unsafe)`, `try!` or force
casts. The tests are real: they enumerate 1,440 field combinations against an invariant oracle, check 1,905
daypart × weekday sets, test that `Equatable` notices each of the 15 fields, and use `Mirror` and encoded-key D-2 guards.
The Developer recorded mutations that turn these tests red. AC-M1-01, AC-M1-02 and AC-M1-25 (construction and decode)
are met. I checked D-2 and D-3 by hand (R-12) and found no violation.

The lexer works correctly. It handled every adversarial case I tried: raw strings with embedded `"#`, nested
interpolation containing `")"`, unterminated strings, line continuation, `*/` inside a string, empty strings and `#if`
blocks.

**The AC-M1-23 guard has two gaps that need a fix before merge.** This scan is the only automated check for P-2 and
determinism on Darwin, where `import Foundation` brings in the networking APIs. It runs on every later PR and the
auto-merge relies on it.
- (F-1) Identifier-boundary matching turns `Socket` into a pattern that can never match. It also lets every real socket
  or stream API in Foundation/CoreFoundation through. One test asserts this gap as correct behaviour.
- (F-2) Common equivalent spellings of `Date()`, `UUID()` and `Date.now` are not caught. The most likely one is the
  default argument `at now: Date = .now`.

Neither gap is a law violation in the current `Sources/`: the scan is clean and I found no networking or ambient-time
code by inspection. So both are **Major**, not Blocker.

### Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F-1 | **Major** | `Tests/TendCoreTests/Support/SourceScanner.swift:63-71`; `Tests/TendCoreTests/SourceScannerSelfTests.swift:267-269` | **AC-M1-23 / P-2: networking names are matched at identifier boundaries, so the guard misses the real networking APIs.** No Foundation or CoreFoundation type is named exactly `Socket`, so the `Socket` rule can never fire. The real APIs all have compound names. A Reviewer probe showed 0 hits for each of: `URLSessionWebSocketTask`, `SocketPort(tcpPort: 80)`, `CFSocketCreate(…)`, `CFStreamCreatePairWithSocketToHost(…)`, `InputStream(url: u)` and `URLSessionConfiguration.default`. The same goes for `URLSession`/`URLRequest`: because the right-hand boundary is strict, `URLSessionDataTask` and `URLSessionConfiguration` pass. On Darwin all of these compile with only `import Foundation`, so the import rule does not cover them. The N-1 near-miss test (`WebSocketLike`, `InputStream(`, `GhostHost(`) then asserts the gap as correct behaviour. Read literally, the AC's closed list (`Socket`, `Stream(`, `Host(`) contains `InputStream(` and `WebSocket`. T-05 describes them as *tokens*. N-1 asked for boundaries only so that the `Date()` family stops reporting `startDate()`. That reasoning does not apply to networking names. This is the question the Orchestrator asked: my decision is that identifier-boundary matching is **not acceptable** for the networking names. | (1) Match the networking names `Socket`, `NSStream`, `Stream(`, `Host(`, `Host.current`, `URLSession`, `URLRequest`, `URLConnection` and `NSURLConnection` at a **camelCase-hump boundary**, the same splitting the AC-M1-02 tokeniser already uses. A name that starts a hump anywhere inside an identifier is a hit, and the right side may continue with a new hump. (2) Keep the identifier boundary for `Date()`, `Date.now`, `UUID()`, `Calendar/TimeZone/Locale.current…`, `ProcessInfo`, `timeIntervalSinceNow` and `SystemRandomNumberGenerator` (N-1 still holds there; `startDate()` stays clean). (3) In the N-1 test, remove `WebSocketLike`, `InputStream(` and `GhostHost(` from the "not reported" fixture. Add planted positives: `URLSessionWebSocketTask`, `URLSessionConfiguration`, `SocketPort(`, `CFSocketCreate(`, `InputStream(`, `OutputStream(`. Keep the coverage test green. (4) Record the rule split in dev-notes (blind spot (e) is withdrawn). Known false positive: `AsyncStream(` / `AsyncThrowingStream(` will hit. Do **not** allowlist these on your own; see open question Q-R1. No AC text changes. | Open |
| F-2 | **Major** | `Tests/TendCoreTests/Support/SourceScanner.swift:50-51, 61` | **AC-M1-23 / CLAUDE.md §3 determinism: equivalent spellings of the banned time and ID calls are not caught.** A probe showed 0 hits for `let d = Date.init()` and `let u = UUID.init()`, which are the same calls as `Date()` / `UUID()`. The implicit-member form `.now` where the type is `Date` (for example `func complete(at now: Date = .now)` or `select(at: .now)`) is `Date.now` and is also missed. In modern Swift this default-argument idiom is the most likely way ambient time would get into WI-M1-03/04 code. It would defeat the injected-`now` contract, and with it AC-M1-22. | (1) Report `Date.init()` and `UUID.init()` (with optional whitespace, at the identifier boundary on the left) under the existing `Date()` / `UUID()` rules. (2) Report an implicit-member `.now` in expression position (no receiver before the dot, e.g. after `=`, `(`, `,`, `:`, `return`, `??`) under the `Date.now` rule. Keep `moment.now`, `context.now`, `self.now` and `Date.nowish` clean. (3) Add planted positives for each form and near-miss negatives for the receiver forms. (4) The implicit `.init()` (`let d: Date = .init()`) cannot be typed lexically. List it in dev-notes as a known limit (Reviewer check, R-12). | Open |
| F-3 | Minor | `Tests/TendCoreTests/Support/SourceScanner.swift:49-75` | P-2 hardening beyond the closed list: on Darwin these APIs are reachable from `import Foundation` and are not in AC-M1-23: `Stream.getStreamsToHost(…)`, `Data(contentsOf:)` / `String(contentsOf:)` with a non-file URL built at runtime (the `http(s)` literal rule only catches literals), and `arc4random*` / `drand48()` (ambient randomness). The Developer correctly kept to the closed list, so this does not block. | Ticket to the PO: should AC-M1-23's closed list be extended? (Q-R2). No Developer action unless the PO amends the AC. | Open (ticket) |
| F-4 | Minor | `.gitignore:4` | `Package.resolved` is ignored for the whole repo. Today there are no dependencies, but once an ADR approves one (CLAUDE.md §6), its pin would not be committed. That includes the Xcode workspace's `Package.resolved` in M3. | Remove the line, or limit it to `Packages/TendCore/Package.resolved`. Can be fixed in this round or ticketed for WI-M1-02. | Open (ticket) |
| F-5 | Nit | `Tests/TendCoreTests/Support/SourceScanner.swift` blind spot (a); `Tests/TendCoreTests/SourceScannerSelfTests.swift` | Regex literals are lexed as code (dev-notes blind spot (a)), and a function reference `Int.random` (no call) is not reported. Neither occurs in `Sources/`. | No change now. Any later item that adds a regex literal or a randomness function reference to `Sources/` must extend the lexer in the same PR. The Reviewer checks this per PR. | Open (watch) |
| F-6 | Nit | `Tests/TendCoreTests/InvariantTests.swift:219-220` | The doc comment on `InvariantCase` mentions "the JSON fields that … produce the same violation". That member does not exist; `violatingJSON(_:)` does the job. | Fix the comment when you are next in the file. | Open |

**Reviewer decisions on Developer questions (dev-notes "Things the reviewer should look at closely"):**
- *Lexer correctness (R-2, N-2):* accepted. Raw-string closing with `#` counts, interpolation re-entry with nested parens
  and strings, nested block comments, the unterminated single-line fallback, `\u{…}` and line continuation all behaved
  correctly in the Developer's tests and in my probes (for example `##"a "# still string"##; let isLate = 1` → one
  `late` hit, on the code; `"a \(f(")")) b"; let isLate = 1` → one hit).
- *Blind spot (e), identifier-boundary networking names:* **not accepted** → F-1.
- *Blind spots (a)–(d):* accepted as documented; (a) is watched under F-5.
- *`Mirror` D-2 tests:* accepted on Linux. The Darwin check is deferred to the M3 macOS lane, as dev-notes say.
- *Typed throws on the public initialiser; `public internal(set)` fields:* accepted. They keep the invariants
  (AC-M1-25) at the module boundary.
- *Decision 4 (`windowIsOpen`/`windowHasEnded` look only at the window):* accepted. It matches the design naming list
  and keeps each helper to one fact. WI-M1-04 must combine it with `isResting(at:)` and the state, and I will check that.
- *ADR-0001 (Accepted by the Developer):* confirmed. It is a technical decision inside CLAUDE.md §3 and adds no
  dependency. ADR-0002/0003 stay `Proposed`, which is correct.

**AC trace (owned ACs):**
| AC | Code | Test(s) | Reviewer result |
|---|---|---|---|
| AC-M1-01 | `Model/*.swift` | `ModelTests` (9 tests: per-kind, 1,440-combination, 1,905 sets, Equatable-per-field, state/room/household round-trips, defaults, enum cases) | Met |
| AC-M1-02 | `TaskState.swift`, `HouseholdTask.swift` (fields) | `SourceScanTests.noBannedVocabulary`, `ZeroGuiltModelTests` (closed set, stored fields, encoded keys, Room/Household), `SourceScannerSelfTests` negatives | Met. The vocabulary scanner is sound. |
| AC-M1-23 | `Package.swift`, all `Sources/` | `SourceScanTests.foundationOnlyAndDeterministic`, planted, coverage and N-1 tests | Met by the letter on the current `Sources/`, but the guard is unsound → F-1, F-2 (Major) |
| AC-M1-25 | `HouseholdTask.init`, `firstInvariantViolation()`, `init(from:)` | `InvariantTests` (12 construction cases, 9 decode cases, household decode, boundaries, order, unknown state) | Met for construction and decode. The repository path is WI-M1-02 (as planned). |

### Checklist
- [x] Correctness vs ACs (AC-M1-01, 02, 25 met; AC-M1-23 met on current sources, guard gaps F-1/F-2)
- [ ] Tests meaningful (would fail if code broke). Model and invariant tests: yes. The N-1 test locks in the F-1 gap,
  and the AC-M1-23 negatives miss the F-2 spellings.
- [x] Swift 6 concurrency safe: all value types `Sendable`; no `@unchecked`, `nonisolated(unsafe)`, `Task {}` or shared
  mutable state; Swift 6 language mode; 0 warnings with `-warnings-as-errors`
- [x] No force unwraps / `try!` in product code paths (one `preconditionFailure` in a test fixture only)
- [ ] Privacy (P-1…P-4): no violation in the code. The P-2 guard is weakened (F-1).
- [x] UX-2/UX-3 enforced in engine: closed state set, no counter, original window or history (D-2, checked by hand
  against the design forbidden list); no score, priority or weight (D-3); no public "what to do now" API yet
- [x] Accessibility (UI): n.a. (no UI)
- [x] Performance: n.a. for the model. The scanner runs in about 0.1 s.
- [x] No new dependency without ADR: none added

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The initialiser is a programmatic API with defaults (dev-notes). |
| UX-2 Rule of Three | pass | No public API returns "what to do now" items. No `allValidTasks` / `candidates` / `nextUp` / `queue` / `backlog` / `todo`. `NowSelection` arrives in WI-M1-03. |
| UX-3 Zero-Guilt | pass | Closed set `active`, `deferred(until:)`, `maintenance`, `resurfaced`, `completed`. Stored fields exactly match the naming list (D-2). No design-forbidden identifiers in `Sources/` (searched by hand for urgency, severity, escalation, alert, warning, lapsed, due, downgrade, demote, priority, score, weight, original, count, attempts, history). `isRestOver` follows D-1. `PromptTone` has one case. No D-1 vocabulary in test names. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. `TendCore` imports only Foundation. |
| P-2 No data leaves device (except user iCloud) | concern | No networking code exists today (scan clean, inspected by hand). The automated guard that later PRs depend on misses real Darwin networking APIs (F-1) and should be extended (F-3, PO ticket). |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Open questions
- **Q-R1 (PO):** with F-1 fixed, `Stream(` matches `AsyncStream(` and `AsyncThrowingStream(`. These are concurrency
  types, not networking. If a later item needs one, should AC-M1-23 add an explicit exception? The Reviewer will not
  accept an allowlist the Developer adds without the PO.
- **Q-R2 (PO):** should AC-M1-23's closed list grow to include `getStreamsToHost`, `contentsOf:` with a non-literal URL,
  `arc4random*` and `drand48` (F-3)? Not blocking for WI-M1-01.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer (via Orchestrator) | Reviewer | received (H4) | PR #5, commit `d6b7950`, dev-notes WI-M1-01. |
| 2026-11-20 | Reviewer | Developer (via Orchestrator) | returned — CHANGES REQUIRED | 2 Major (F-1 networking-name boundary in the AC-M1-23 guard; F-2 `Date.init()` / `UUID.init()` / implicit `.now` not caught), 2 Minor (F-3 PO ticket, F-4 `.gitignore`), 2 Nit. No Blocker, no law violation in the code, D-2/D-3 clean. Fix F-1 and F-2 in the scanner and its self-tests only; the model needs no change. Re-review in round 2 against the new diff. Q-R1 and Q-R2 go to the PO and do not block. |
