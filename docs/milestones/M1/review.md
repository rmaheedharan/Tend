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

---

## WI-M1-01 round 2 — [PR #5](https://github.com/rmaheedharan/Tend/pull/5) (`m1/core-model`, commit `899ea43`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2
- **Diff reviewed:** `git diff d6b7950 899ea43`. Changes are in `SourceScanner.swift`, `SourceScannerSelfTests.swift`,
  `SourceScanTests.swift`, `InvariantTests.swift` (comment only), `.gitignore`, plus brief.md (PO Q17/Q18, AC-M1-23
  tightened), dev-notes.md and review.md. `Packages/TendCore/Sources/` is **unchanged** (empty diff), so the round-1
  model findings (AC-M1-01, AC-M1-02, AC-M1-25 met; D-2/D-3 clean) still hold.
- **Inputs:** [brief.md](brief.md) AC-M1-23 as amended by Q17 and Q18, [dev-notes.md](dev-notes.md) (WI-M1-01 round 2,
  blind spots (a)–(h)), round-1 findings above.
- **Verified by the Reviewer (Linux container, Swift 6.2 via Docker wrapper):**
  `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` → "Test run with 42 tests in 6 suites
  passed", 0 failures, 0 warnings, 0 skipped. The planted-pattern test runs 74 cases. Scan log: `AC-M1-23 scan: 11 files
  scanned`, `11 import statements found`, `contentsOf: allowlist ["JSONFileHouseholdRepository.swift"], 0 allowlisted
  files present`, `0 hits`; `AC-M1-02 scan: 0 hits`. GitHub check run "TendCore swift test (Linux)" on head `899ea43`
  is `success`. The `gatekeeper` check on the same head is `failure`. That is the Merge Gatekeeper's gate, not part of
  this review; the Orchestrator should read its log before it re-runs.
- **Reviewer mutations** (a throwaway copy of the package in the session scratchpad; nothing in the repo changed). Each
  one turned the suite red:
  - M1: remove the `AsyncStream` exemption → the Q17/Q18 positive test fails.
  - M2: match networking names only as the last words of an identifier → planted cases 47–50 fail.
  - M3: switch off implicit-`.now` detection → planted cases 38–41 fail.
  - M4: ignore the `contentsOf:` allowlist → the positive test fails.
  - M5: drop the `arc4random*` rule → two planted cases and the coverage test fail.
  These agree with the Developer's mutation table (dev-notes).
- **Reviewer probes** (same scratchpad copy, one probe test; results quoted in F-7…F-9).

### Summary
Round 1's two Majors are fixed and verified. **F-1:** the networking names now match at camelCase word boundaries,
using the same word split as the AC-M1-02 tokeniser. `URLSessionWebSocketTask`, `URLSessionConfiguration`,
`URLSessionDataTask`, `SocketPort(`, `CFSocketCreate(`, `CFStreamCreatePairWithSocketToHost(`, `NSStreamDelegate`,
`NSMutableURLRequest`, `InputStream(` and `OutputStream(` are all planted and reported. The N-1 fixture no longer
asserts the gap, and its new near-misses (`Sockets`, `XURLSessionLike`, `upstream(`, `Hostname(`, `Host.currently`)
stay clean. **F-2:** `Date.init()`, `UUID.init()`, `Date.init(timeIntervalSinceNow:` and nine implicit-member `.now`
forms are planted and reported, including the default-argument idiom `at now: Date = .now`. Receiver forms are
proven clean: `moment.now`, `self.now`, `f().now`, `xs[0].now`, `x?.now`, `x!.now`, `Box<Int>.now`, a member chain on
the next line, and `Date.nowish`. `let d: Date = .init()` is recorded as known limit (f), as round 1 required.

**Q17 and Q18 are implemented as written.**
- Every new closed-list entry is in the scanner and has a planted fixture: `InputStream(`, `OutputStream(`,
  `getStreamsToHost`, `URL(string:` (also the `.init` spelling), `arc4random*`, the four `*rand48`, `rand(`,
  `random()` and `contentsOf:`.
- The coverage test now builds the expected rule set from all four rule tables plus `Host.current`, `http(s) literal`
  and `contentsOf:`, and it requires the planted set to be exactly that set.
- Exactly two names are exempt from `Stream(` (`streamCallExemptions`). The exemption is an exact identifier match:
  `MyAsyncStream(` is still reported.
- The `contentsOf:` allowlist is a named constant, and the test pins it to exactly
  `["JSONFileHouseholdRepository.swift"]`. The allowlist covers only `contentsOf:`; other rules still fire in that file.
  The scan also fails if an allowlisted file name appears twice under `Sources/`.
- The required positive test (`AsyncStream(`, `AsyncThrowingStream(`, allowlisted `contentsOf:`) is there.

The Developer recorded the AC's side effects in dev-notes (h) for the PO, which I consider correct: `makeStream(`,
`append(contentsOf:)` and the lower-case POSIX `socket(`.

F-4 is fixed (the `Package.resolved` line is removed from `.gitignore`) and F-6 is fixed (doc comment corrected).

The new gaps I found are spellings and APIs outside the AC's closed list, or rarely used `.init` spellings of call
names. None of them occurs in `Sources/`, and none is a law violation. They are Minor tickets (F-7…F-9) and do not
block. **No open Blocker or Major.**

### Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| F-1 | Major | `Support/SourceScanner.swift:82-96, 179-221`; `SourceScannerSelfTests.swift` planted list, N-1 test | Round 1: networking names matched only at identifier boundaries. | Done as required: camelCase word-boundary matching (`containsWords`, `subTokens`), N-1 fixture corrected, planted positives added, blind spot (e) withdrawn in dev-notes. Verified by test run, probes and mutation M2. | **Closed** |
| F-2 | Major | `Support/SourceScanner.swift:57-72, 102-104, 223-258`; `SourceScannerSelfTests.swift` planted list, `nowWithReceiverNotReported` | Round 1: `Date.init()`, `UUID.init()` and implicit `.now` not caught. | Done as required. Verified by test run, probes (`Date\n.now`, `let t: Date = .now`, `Date(\n)` all reported) and mutation M3. Known limit (f) documented. False positives `case .now:` (dev-notes (g)) and the key path `\.now` (probe) are acceptable: they fail closed. | **Closed** |
| F-3 | Minor | — | Round 1: P-2/determinism hardening beyond the closed list (Q-R2). | The PO answered with Q18. AC-M1-23 is extended and the extension is implemented (see Summary). | **Closed** |
| F-4 | Minor | `.gitignore` | Round 1: `Package.resolved` ignored repo-wide. | Line removed. | **Closed** |
| F-5 | Nit | `Support/SourceScanner.swift` header; dev-notes blind spot (a) | Regex literals lexed as code; `Int.random` function reference not reported (probe confirms it is still not reported). | No change. Reviewer checks per PR. | Open (watch) |
| F-6 | Nit | `InvariantTests.swift:9-10` | Round 1: stale doc comment. | Fixed; now points to `violatingJSON(_:)`. | **Closed** |
| F-7 | Minor | `Support/SourceScanner.swift:89-96, 189-197` | **Explicit `.init` on the networking call names is not reported** (the F-2 principle was applied to `Date`, `UUID` and `URL(string:` but not here). Probes found 0 hits for `Host.init(name: n)`, `InputStream.init(url: u)` and `Stream.init()`. They are the same calls as `Host(`, `InputStream(` and `Stream(`. Not Major: this spelling is rare, `Host` is macOS-only, and a stream on a remote URL also needs a URL from a string, which `URL(string:` blocks. | Treat `Name.init(` like `Name(` for `networkingCallNames`, and keep the `AsyncStream.init(` / `AsyncThrowingStream.init(` exemption consistent. Add planted cases. Can go in WI-M1-02 (the scanner is shared) or a follow-up; it does not block this PR. | Open (ticket) |
| F-8 | Minor | `Support/SourceScanner.swift:72, 97-100`; brief AC-M1-23 (Q18 rationale) | **The Q18 rationale ("allowed only because `URL(string:` is banned") can be bypassed inside the allowlisted file.** Probes found 0 hits for `NSURL(string: s)`, `URLComponents(string: s)?.url` and `NSURLRequest(url: u)`. `NSURL` and `NSURLRequest` split as the single hump `NSURL`, so the `URL…` rules do not see them. Any of the first two gives `Data(contentsOf:)` a remote URL in `JSONFileHouseholdRepository.swift`. The implementation matches the AC's closed list as written; the gap is in the list. | **Question Q-R3 (PO):** add `NSURL(`, `URLComponents(` and `NSURLRequest` to AC-M1-23, or require that the allowlisted file builds URLs only from `URL(fileURLWithPath:)` / `FileManager` URLs. Until the PO decides, the Reviewer reads the allowlisted file by hand in WI-M1-02 (R-12). | Open (ticket, PO) |
| F-9 | Minor | brief AC-M1-23 (closed list) | **Ambient time outside the closed list.** Probes found 0 hits for `CFAbsoluteTimeGetCurrent()`, `DispatchTime.now()`, `ContinuousClock.now` and `ContinuousClock().now`. `ContinuousClock` is in the standard library, so it needs no import. `CFHostCreateWithName(` and `CFReadStreamCreateWithFTPURL(` are also not reported, because neither has a `Socket` word or ends in `Stream(`/`Host(`. None of these occurs in `Sources/`. | **Question Q-R4 (PO):** extend AC-M1-23 with `CFAbsoluteTimeGetCurrent`, `DispatchTime`/`DispatchWallTime`, `ContinuousClock`/`SuspendingClock` and `CFHost`/`CFReadStream`/`CFWriteStream`? No Developer action unless the PO amends the AC. | Open (ticket, PO) |

**Reviewer positions on dev-notes (h) (for the PO, non-blocking):**
- `AsyncStream.makeStream(of:)` hits `Stream(` (confirmed by probe). This is the AC's letter: Q17 names two type names,
  not factory methods. A Developer allowlist would be wrong. If WI-M1-03/04 needs it, the PO should decide.
- `append(contentsOf:)` / `insert(contentsOf:at:)` hit `contentsOf:` outside the allowlisted file. This also follows the
  AC's letter. It will cause friction in engine code, so the PO may want to narrow the rule to `Data(`/`String(`
  receivers (Q-R3 can cover both).
- Lower-case POSIX `socket(` is not in the list. I agree with raising it as a PO question (fold it into Q-R4).

**AC trace (owned ACs, round 2):**
| AC | Code | Test(s) | Reviewer result |
|---|---|---|---|
| AC-M1-01 | `Model/*.swift` (unchanged) | `ModelTests` | Met (round 1 holds; `Sources/` unchanged) |
| AC-M1-02 | unchanged | `SourceScanTests.noBannedVocabulary`, `ZeroGuiltModelTests`, scanner self-tests | Met (0 hits) |
| AC-M1-23 (as amended by Q17, Q18) | `Package.swift`, all `Sources/` | `foundationOnlyAndDeterministic` (0 hits), 74 planted cases, coverage test, N-1 near-miss test, F-2 receiver test, Q17/Q18 positive test, import tests | **Met.** Each closed-list item is detected when planted; the exemptions and allowlist are exact and pinned by tests; mutations M1–M5 turn the suite red. F-7…F-9 are Minor. |
| AC-M1-25 | unchanged | `InvariantTests` | Met (construction and decode; repository path is WI-M1-02) |

### Checklist
- [x] Correctness vs ACs (AC-M1-01, 02, 23 as amended, 25)
- [x] Tests meaningful: every new rule, exemption and allowlist has a planted or positive test. Reviewer mutations
  M1–M5 all turned red. No test was weakened or skipped; the only fixture lines removed from N-1 were the three that
  asserted the F-1 gap, which moved to the planted positives.
- [x] Swift 6 concurrency safe (no change to `Sources/`; scanner types `Sendable`, 0 warnings with `-warnings-as-errors`)
- [x] No force unwraps / `try!` in product code paths (no product code change)
- [x] Privacy (P-1…P-4): the P-2 guard is restored. Residual gaps are Minor, outside the closed list (F-8, F-9).
- [x] UX-2/UX-3 enforced in engine (unchanged from round 1)
- [x] Accessibility (UI): n.a.
- [x] Performance: scan about 0.2 s; n.a. for the model
- [x] No new dependency without ADR: none; `Package.resolved` is now committable for when one is approved

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | pass | No change; no public "what to do now" API yet (WI-M1-03). |
| UX-3 Zero-Guilt | pass | `Sources/` unchanged; AC-M1-02 scan 0 hits; no banned vocabulary in the new test names or fixtures outside planted negatives. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI; Foundation-only imports (scan). |
| P-2 No data leaves device (except user iCloud) | pass | Round-1 concern resolved: the guard now catches the compound Darwin networking APIs (F-1 closed). Residual list gaps are PO tickets (F-8, F-9), and there is no networking code in `Sources/`. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Open questions
- **Q-R3 (PO):** F-8. Should AC-M1-23 ban `NSURL(`, `URLComponents(` and `NSURLRequest`, or require file-path-only URL
  construction in the allowlisted repository file? Should `contentsOf:` be narrowed so `append(contentsOf:)` is allowed?
  Answer needed before WI-M1-02 adds `JSONFileHouseholdRepository.swift`.
- **Q-R4 (PO):** F-9. Should AC-M1-23 be extended with `CFAbsoluteTimeGetCurrent`, `DispatchTime`/`DispatchWallTime`,
  `ContinuousClock`/`SuspendingClock`, `CFHost`/`CFReadStream`/`CFWriteStream`, and lower-case `socket(`? Not blocking.
- **Orchestrator:** the `gatekeeper` check on `899ea43` is `failure` (run 44738021817). That is the Merge Gatekeeper's
  call, not this review's. Check its log before the PR is re-run.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer (via Orchestrator) | Reviewer | received (round 2) | Commit `899ea43`; dev-notes WI-M1-01 round 2; brief Q17/Q18. |
| 2026-11-20 | Reviewer | Orchestrator → Acceptance Tester | accepted — APPROVE | F-1, F-2 (Major) closed and verified; F-3, F-4, F-6 closed; F-5 watched. New Minor tickets: F-7 (networking `.init` spellings), F-8 → Q-R3 (PO), F-9 → Q-R4 (PO). No open Blocker or Major. 42 tests / 0 failures / 0 warnings locally; Linux CI green; Reviewer mutations M1–M5 red as expected. Not committed (per instructions). |
