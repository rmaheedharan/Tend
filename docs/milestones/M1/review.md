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

---

## WI-M1-02 round 1 — [PR #6](https://github.com/rmaheedharan/Tend/pull/6) (`m1/persistence`, commit `b593d41`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Diff reviewed:** `git diff 899ea43 b593d41`, read against branch head `aaa08f0`. `git diff 899ea43 aaa08f0` touches
  only the WI-M1-02 files: 4 new `Sources/` files, 8 new test files, ADR-0004, dev-notes and this file. The scanner,
  `.gitignore` and model lines in the raw `b593d41` diff are only the reverse of WI-M1-01 round 2, which the merges
  bring back.
  **Owned ACs:** AC-M1-04, AC-M1-05, AC-M1-06, AC-M1-07, and AC-M1-25 (repository part). **Keeps green:** AC-M1-02,
  AC-M1-23 (as amended by Q17/Q18).
  **Inputs:** [brief.md](brief.md) v2 (incl. Q17, Q18), [design.md](design.md) (repository and `HouseholdStoreError`
  names, `store.error.*` codes-only rule, D-2, D-3), [plan.md](plan.md) (WI-M1-02 scope, R-7, R-8, R-12),
  [dev-notes.md](dev-notes.md) (WI-M1-02 section), and
  [ADR-0004](../../architecture/adr/0004-household-json-file-format.md).
- **Verified by the Reviewer (Linux container, Swift 6.2 via the Docker wrapper, on `aaa08f0`):**
  `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` gave "Test run with 75 tests in 11 suites
  passed", 0 failures, 0 warnings. The dev-notes count of 73 predates the merge of WI-M1-01 round 2.
  - Logs: `AC-M1-05: seeds 1...200, 200 households, 51718 tasks (min 0, max 500 per household), 144045 dates compared
    bit-exact, 144045 with a sub-second part`.
  - `AC-M1-02 scan: 15 files … 0 hits`.
  - `AC-M1-23 scan: 15 files … 0 hits; contentsOf: allowlist ["JSONFileHouseholdRepository.swift"], 1 allowlisted
    files present`.
- **Reviewer mutations.** These ran in a throwaway copy of the package in the session scratchpad. Nothing in the repo
  was changed.
  - **RM-1:** `InMemoryHouseholdRepository.upsertTask` always appends. Result: red. "AC-M1-04 contract: upsert replaces
    the task with the same ID in place…" failed for the in-memory case (13 tasks instead of 12).
  - **RM-2:** the file store's edits swallow load errors (`(try? load()) ?? .empty`). Result: red. Every AC-M1-06
    corrupt-file case failed: `upsertTask`, `removeTask` and `updateRoom` no longer threw, and the file bytes changed.
  - These results add to the Developer's eight recorded mutations. Each of those also turned the suite red.
- **R-12 / F-8 hand read of the allowlisted file:** `JSONFileHouseholdRepository.swift` has exactly one `contentsOf:`
  use, `Data(contentsOf: fileURL)` at line 42. It builds no URLs, uses no networking API and imports only Foundation.
  The URL comes from the caller (see W2-F1).

### Summary
This is a small, careful persistence layer, and it matches the design list exactly.
- **Types.**
  - `HouseholdRepository` is a `Sendable` protocol with typed `async throws(HouseholdStoreError)` requirements.
  - Both stores are actors. Their methods are synchronous inside the actor, so a read-modify-write never crosses an
    `await`. That means there is no reentrancy hazard.
  - There is no `@unchecked Sendable`, no `nonisolated(unsafe)`, no `Task {}`, no `try!` and no force unwrap.
  - The write seam `HouseholdFileWriter` is an internal `Sendable` struct holding a `@Sendable` closure.
- **Errors.** `HouseholdStoreError` has exactly the four design cases. Errors are codes only and carry no strings.
- **R-7, exact dates.** ADR-0004 option 2 writes each date as `timeIntervalSinceReferenceDate`, with the strategy set
  explicitly. It is proven bit-exact over 144,045 generated dates and 11 adversarial ones, comparing `bitPattern`, not
  only `==`.
- **R-8, atomic save.** The R-8 analysis is good evidence:
  - `replaceItemAt` was observed to lose the original on Linux, so it is avoided.
  - `.atomic` is used behind a seam whose contract is "atomically or not at all".
  - An inode-change test pins the standard writer to replace-by-rename. It catches the `options: []` mutation.
- **AC-M1-06.** The tests check the AC's three clauses for every operation that reads the file: the typed error, no
  household returned (`returned == nil`), and the bytes unchanged. They also check that edits on an unreadable file
  write nothing. I agree with decision 4, that an older build or a damaged file is never overwritten by an edit. That
  is the behaviour S-M1-02 needs.
- **Tests.** The contract suite really is shared across both implementations. `implementationsAgree` cross-checks
  60 seeded operations.

I found no Blocker or Major. The findings below are hardening tickets. W2-F1 and W2-F2 are worth doing before the
app layer creates a repository (M3).

### Findings
| ID | Severity | file:line | Problem | Required change | Status |
|---|---|---|---|---|---|
| W2-F1 | Minor | `Sources/TendCore/Persistence/JSONFileHouseholdRepository.swift:26-34, 37, 42` | **The public `init(fileURL:)` accepts any `URL`, and `load()` hands it to `Data(contentsOf:)`.** On Darwin, `Data(contentsOf:)` with an `http(s)` URL does a synchronous network fetch. The Q18 rationale ("allowed only because `URL(string:` is banned and file URLs come from file-path initialisers") holds inside `TendCore`, but this URL is built by the **caller**, outside the scan. In M1 nothing in `TendCore` can produce a remote URL, so P-2 is not violated today. It is defence in depth. Related: WI-M1-01 F-8 / Q-R3. | Reject non-file URLs at the boundary. Use `precondition(fileURL.isFileURL)` in `init`, or make `init` failable or throwing. Add a test that a non-file URL is refused before any read. If the PO answers Q-R3 with "file-path-only URLs in the allowlisted file", this check is how that rule is met. | Open (ticket) |
| W2-F2 | Minor | `JSONFileHouseholdRepository.swift:37` | **"No file" is decided by `FileManager.fileExists`, which is `false` for any `stat` failure, not only "no such file".** Examples: a dangling symlink, a path component that is a regular file (`ENOTDIR`), a symlink loop, or no search permission on a parent. In those cases `load()` returns an **empty** household for a path that is not provably empty. That bends the AC-M1-06 rule "never returns an empty household" for unreadable storage. Not Major: none of these is an AC-M1-06 input, and I found no data-loss path. A later `save` to an inaccessible parent fails with `writeUnsuccessful`, and a dangling symlink has nothing to lose. This is reasoned from Foundation behaviour, not probed. | Read first, and return `.empty` only for the "no such file" error (`CocoaError.fileReadNoSuchFile`, or `ENOENT` in the underlying `POSIXError`). Map every other read error to `unreadableFile`. Add a test with a dangling symlink and with a regular file as a parent component. | Open (ticket) |
| W2-F3 | Minor | `InMemoryHouseholdRepository.swift:16-19` vs `JSONFileHouseholdRepository.swift:96-102` | **The two stores disagree on non-finite dates.** The in-memory store accepts a household with a `±.infinity` date. The file store rejects it with `writeUnsuccessful`. The Developer documented this (Known limitations, ADR-0004 Consequences). AC-M1-04 still passes because the contract suite does not include such a household. | PO/Developer ticket, as dev-notes proposes: a finiteness invariant (this needs a design-list `TaskInvariantViolation` case, so the Designer and PO must agree), or the same encode-time check in both stores. Not in this PR. | Open (ticket, PO) |
| W2-F4 | Minor | `JSONFileHouseholdRepository.swift:140-142` | **Durability and protection class on device.** `.atomic` gives rename atomicity, but there is no explicit data-protection option and no `fsync`, so a power cut right after the save could leave a stale or, on some filesystems, an empty file. This does not matter for M1: the file store is Linux-tested, and the on-device store is ADR-0002's choice. | If `JSONFileHouseholdRepository` ever ships on device, add a protection class (for example `.completeFileProtectionUntilFirstUserAuthentication` under `#if os(iOS)`) and note durability in ADR-0004. Otherwise, add one line to ADR-0004 Consequences saying it is not the on-device store. | Open (ticket) |
| W2-F5 | Nit | `Tests/TendCoreTests/FileRepositoryLoadErrorTests.swift:175-187` | `errorCases` is close to a tautology. The exhaustive `switch` is a compile-time check, and `Set(all).count == 4` is true by construction. The name says "carries no user-facing text", but nothing asserts it, for example that the type is not `LocalizedError` and not `CustomStringConvertible` with prose. | Optional: assert `!(HouseholdStoreError.unreadableFile is any LocalizedError)`, or drop the "no user-facing text" claim from the name. | Open (optional) |
| W2-F6 | Nit | `Tests/TendCoreTests/Support/SplitMix64.swift:2`; `Support/HouseholdGenerator.swift:54` and elsewhere | The comment says seeds give the "same sequence, on every platform". That is true for `SplitMix64.next()`. But `Int.random(in:using:)` maps raw bits to a range with a standard-library algorithm that is not promised to stay the same across Swift releases. A seed could give a different household after a toolchain upgrade. The tests would still pass, because the coverage checks are not tied to a seed, but a printed failure seed might not replay. | Optional: reword the comment to "on every platform with the same toolchain", or add `rng.uniform(in:)` built on `next()`. | Open (optional) |

**ADR-0004:** the Reviewer agrees with options 2 and 6 and the load and save rules. The Reviewer part of its
confirmation is given. The status change to Accepted belongs to the ADR's owner and the Documenter. Two notes for the
ADR text are W2-F1 (file-URL precondition) and W2-F4 (not the on-device store).

**AC trace (owned ACs):**
| AC | Code | Test(s) | Reviewer result |
|---|---|---|---|
| AC-M1-04 | `HouseholdRepository.swift`, `InMemoryHouseholdRepository.swift`, `JSONFileHouseholdRepository.swift` | `RepositoryContractTests`: 12 tests × 2 implementations, plus `implementationsAgree` | **Met.** Covers save, load, upsert task, remove task and update room, plus reopen, schema rejection and 64 concurrent upserts. RM-1 turns it red. |
| AC-M1-05 | `JSONFileHouseholdRepository.encode/decode` (`.deferredToDate`, explicit) | `seededHouseholdsRoundTrip` (seeds 1…200, 0–500 tasks, new instance per load, `==` and `bitPattern`), `awkwardDatesAreExact` (11), `GeneratorTests` coverage | **Met** (Linux). The generator goes through the throwing initialiser and covers every kind, flag set, state, daypart and weekday set and window position. Darwin rerun is in the M3 macOS lane (R-7 residual, as dev-notes says). |
| AC-M1-06 | `load()` and `decode` (probe, then full decode) | `corruptFile` (10), `unknownSchemaVersion` (5), `directoryInsteadOfFile` | **Met.** Each case checks the typed error, `returned == nil`, unchanged bytes after load **and** after the three edits, a new instance and no stray files. RM-2 turns it red. |
| AC-M1-07 | `save` (encode fully, then one writer call), `HouseholdFileWriter.standard` (`.atomic`) | `failedSaveKeepsPreviousHousehold` (3 failure points), `failedMutationKeepsPreviousHousehold` (3), `failedFirstSaveCreatesNoFile` (3), `recoveryAfterFailure`, `encodingFailureKeepsPreviousHousehold` (real failure), `standardWriterReplacesByRename`, `writerReceivesCompleteBytes` | **Met** (Linux). The injected writers test our code around the primitive. The inode test pins the primitive to rename. The kernel-level atomicity of the rename is Foundation's (accepted, ADR-0004 option 6). Darwin rerun is in M3. |
| AC-M1-25 (repository part) | `decode`: `catch let violation as TaskInvariantViolation` → `.invalidTask` | `invalidTask` (9, one per invariant, bad task at index 7 of 20), `invariantCoverage` | **Met.** `TaskInvariantViolation` reaches the repository unwrapped by `JSONDecoder` (passes on Linux). |
| AC-M1-02, AC-M1-23 | all of `Sources/` (15 files) | WI-M1-01 scans | **Still met.** 0 hits. `contentsOf:` appears only in the allowlisted file. |

### Checklist
- [x] Correctness vs ACs (AC-M1-04, 05, 06, 07, 25 repository part). AC-M1-02 and 23 are still green.
- [x] Tests meaningful. Every AC has named tests that fail when the behaviour breaks: 8 Developer mutations and Reviewer
  RM-1 and RM-2. No test was weakened or skipped. At the branch head, `InvariantTests.swift` and the scanner are byte-identical
  to `899ea43`, so the raw `b593d41` diff on them is only the merge base.
- [x] Swift 6 concurrency safe. Both stores are actors with no suspension inside a read-modify-write. Everything that
  crosses isolation is `Sendable`. 0 warnings with `-warnings-as-errors`. One note: blocking file I/O on an actor runs
  on the cooperative pool. That is acceptable at this size; revisit if M3 loads large households on a hot path.
- [x] Typed errors. `throws(HouseholdStoreError)` is used throughout. Untyped Foundation errors are mapped at one place
  each (read, encode, write, decode).
- [x] No force unwraps or `try!` in product code
- [x] Privacy (P-1…P-4). Local file only; no networking API; `contentsOf:` only in the allowlisted file. The
  caller-URL hardening is W2-F1 (Minor).
- [x] UX-2/UX-3 enforced in engine. No ranking, "next" or list-for-display API. No new model field (D-2). No
  priority, score or weight (D-3). Error names are calm codes; `writeUnsuccessful` avoids the banned word *failed*.
- [x] Accessibility (UI): n.a. (no UI in M1)
- [x] Performance: AC-M1-05 takes about 4.6 s for 51,718 tasks, and the whole run about 10.8 s. Encoding is O(n) per
  save. Edits do a full load and save, which is fine for M1 sizes.
- [x] No new dependency without ADR. None was added. ADR-0004 records the file format.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; the repository is programmatic. |
| UX-2 Rule of Three | pass | `load()` returns the household for the engine. There is no "what to do now" surface and no ranking. The ≤ 3 cap stays WI-M1-03's `NowSelection`. |
| UX-3 Zero-Guilt | pass | No new stored field (D-2) and no time-growing score (D-3). The four error codes have no banned word (AC-M1-02 scan: 15 files, 0 hits). A failed load or save never silently loses or blanks data (AC-M1-06/07), which supports S-M1-02 "never lose a reminder for a bill". |
| UX-4 Design craft | n.a. | No UI in M1. `store.error.*` copy is reserved for M3. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | Writes and reads only a caller-supplied file. No networking API (AC-M1-23: 0 hits). The hand read of the allowlisted file found no URL construction. Defence in depth for non-file URLs is W2-F1 (Minor). |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Open questions
- **PO (W2-F3):** should a finite-date invariant join the model invariants (AC-M1-25 / design naming list), or should
  both stores reject non-finite dates at save? Not blocking.
- **PO (Q-R3, carried from WI-M1-01 F-8):** W2-F1 is a concrete way to meet "file URLs only" for the allowlisted file.
  Adopting it would answer Q-R3's second option.
- **Orchestrator:** dev-notes still says "PR: opened by the Orchestrator (link to be added)". The link is PR #6.
  ADR-0004 needs to be added to the `docs/architecture/README.md` index (Documenter). Traceability rows are needed for
  AC-M1-04…07 and AC-M1-25 (repository part) (Documenter).

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer (via Orchestrator) | Reviewer | received (round 1) | Commit `b593d41` on `m1/persistence` (PR #6), branch head `aaa08f0`. Inputs: dev-notes WI-M1-02 and ADR-0004 (Proposed). |
| 2026-11-20 | Reviewer | Orchestrator → Acceptance Tester | accepted — APPROVE | No Blocker or Major. Four Minor tickets: W2-F1 (file-URL precondition, P-2 defence in depth), W2-F2 (`fileExists` treats any `stat` failure as "no file"), W2-F3 (non-finite dates differ between the stores, PO), W2-F4 (protection class and durability if the store ships on device). Two Nits: W2-F5, W2-F6. 75 tests, 0 failures, 0 warnings locally (Linux, Swift 6.2). Reviewer mutations RM-1 and RM-2 turned the suite red. ADR-0004 confirmed by the Reviewer. Not committed (per instructions). |

---

## WI-M1-03 round 1 — [PR #7](https://github.com/rmaheedharan/Tend/pull/7) (`m1/rule-of-three-selector`, commit `813be42`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Diff reviewed:** `git diff 7556df7...813be42` (base `main` at `7556df7`). It adds 5 new `Sources/TendCore/Selection/`
  files, 3 new test suites, 3 new test support files and the WI-M1-03 dev-notes section. It does not touch WI-M1-01/02
  sources, the scanner, or any protected path.
  **Owned ACs:** AC-M1-08, AC-M1-09, AC-M1-10, AC-M1-11, AC-M1-12, AC-M1-13, AC-M1-14 (Gate), AC-M1-15, AC-M1-16, plus
  `E(a, D)` as the shared basis for WI-M1-04 (AC-M1-03, AC-M1-17…21). **Keeps green:** AC-M1-02, AC-M1-23.
  **Requirements:** FR-B1, UX-2, FR-B2 (basis only). **Inputs:** [brief.md](brief.md) v2 (Definitions, Q1–Q3, Q7,
  Q11–Q14), [design.md](design.md) (binding naming list, forbidden names, D-1…D-3), [plan.md](plan.md) (WI-M1-03, risks
  R-3, R-4, R-5, R-12), and [dev-notes.md](dev-notes.md) (WI-M1-03 section).
- **Verified by the Reviewer (Linux container, Swift 6.2 via the Docker wrapper, worktree at `813be42`):**
  `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` exited 0 with
  **"✔ Test run with 104 tests in 14 suites passed after 10.979 seconds."** It had 0 failures and 0 warnings.
  - Logs: `AC-M1-14 gate: seeds 1...1000, 1000 households, 273931 tasks (min 50, max 500 per household), 10147
    contextually valid per the oracle`.
  - `AC-M1-15: seeds 1...1000 (50-500 tasks) and 100001...101000 (0-49 tasks), 2000 households, 14 with no tasks;
    selection sizes 0/1/2/3 = 494/307/197/1002`.
  - `AC-M1-16: 2000 property households … and 500 tie-heavy households (seeds 200001...200500) match the oracle's
    order; 434 tie-heavy selections hold a windowEnd tie, 1117 resurfaced items selected`.
- **Reviewer mutation RM-3** (applied in the review worktree, then restored with `git checkout`; `git status` was clean
  afterwards). In `ContextValidity.swift:41`, `case .deferred: isRestOver(at: now)` was changed to
  `case .deferred: true`, so resting tasks become offerable. Result: **red.** AC-M1-12 case (b) "deferred until now + 1 s
  (resting)" failed, and the AC-M1-14 gate recorded many oracle failures. This adds to the Developer's nine recorded
  mutations (M-a…M-i).

### Summary
This is a clean, well-tested item. The engine now enforces the Rule of Three in its types, and the gate property tests
check it against an oracle that I judge to be independent.

- **UX-2, the type-level cap (AC-M1-13).**
  - `NowSelection` stores three private optionals (`NowSelection.swift:16-18`) and has no mutating API. Its only
    public initialiser returns `nil` for more than 3 items or for a repeated ID (`:28-30`).
  - Both `select` overloads return `NowSelection`.
  - I listed every `public` declaration in `Sources/`. The only `[HouseholdTask]` in the public API is
    `Household.tasks` (the stored household, WI-M1-01), the two inputs, and `NowSelection.items`, which is capped at 3.
  - The validity predicate, `Slot`, `SlotCalendar` and `ranksBefore` are internal. The working array is a local.
  - A `Mirror` test pins the storage at three optional fields. Nothing lets a surface see more than 3 items.
- **Oracle independence (R-4). Judged independent.**
  - `ContextOracle.swift` imports only the public API. It reads stored fields and `Moment` fields, and calls no
    production helper: not `isRestOver`, `windowIsOpen`, `accepts`, `SlotCalendar` or `ranksBefore`.
  - Each step uses a different method from production:
    - Slot membership: an hour table plus modular weekday arithmetic, against resolved `[start, end)` intervals in
      production.
    - Energy, weather and state: tables, against `switch`.
    - Ranking: a full tuple sort and prefix, against a running top three.
    - `E`: a 15-minute brute-force scan, against walking slot boundaries.
  - The only shared dependency is Foundation's `Calendar`. The DST and `E` example tests pin expected instants as
    hand-written UTC strings, so a Foundation calendar defect would not pass silently through both sides.
  - `ContextValidityTests` checks the oracle against hand tables (`ContextValidityTests.swift:20-21`).
  - I checked the two documented assumptions and accept them: all slot starts fall on quarter hours in the 16 zones,
    and the hour-based and interval-based views agree on DST days. Fall-back repeats an hour just below a transition,
    and both views put the repeated hour in the same daypart.
- **DST policy (Q11, R-3).** `SlotCalendar.wallClock` (`SlotCalendar.swift:59-64`) uses `.nextTime` / `.first` exactly
  as the brief says.
  - Day arithmetic is anchored at local noon (`:66-76`), so a missing midnight (Santiago) cannot shift a day.
  - The tests pin both policies in New York with UTC instants, the 6 h and 8 h night slots, eight `E` cases on DST
    days, and Samoa's skipped 30 December 2011.
  - 134 gate moments and 156 `E` anchors fall within 12 h of a DST change.
  - Linux only (see RF-1).
- **`E(a, D)` (Q14).** `nextAllowedStart` (`SlotCalendar.swift:116-127`) walks days −1…15 in ascending order, and slots
  in time order within a day. The first hit is therefore the earliest one. It returns `anchor` when the anchor is
  inside an allowed slot, otherwise the start of the next allowed slot. `windowEnd = s.addingTimeInterval(D)` is the
  brief's `s + D`. A 1,000-case property against the brute-force oracle passed; the longest move was 155 h.
- **Naming deviation.** `nextEligibleWindow(from:duration:calendar:timeZone:)` versus the design's
  `nextEligibleWindow(from:duration:)`: **accepted.** The base name is unchanged, and the extra labels are needed so
  that `E` resolves slots in the injected calendar and zone (CLAUDE.md §3). They mirror
  `Rescheduler.reschedule(_:at:calendar:timeZone:)`. design.md allows a change "only by recording the reason in the dev
  handoff note", and dev-notes records it. The Designer should ratify it in the naming list (RF-5).
- **D-1 / D-2 / D-3.**
  - D-1: the code says `isRestOver` / "rest over", never "lapsed".
  - D-2: no stored field was added to any model type, and nothing keeps an earlier window. `nextEligibleWindow` is
    pure.
  - D-3: `ranksBefore` (`NowSelector.swift:41-48`) is exactly the four-key AC-M1-16 order, with no score, priority or
    weight.
  - A grep of the added lines for the design-forbidden list found only the comments that say there is no score.
- **`@testable import`.** In the new files it appears only in `SlotCalendarTests.swift:8`, to pin `wallClock` and
  `slot(containing:)`. The other `@testable` uses are WI-M1-02 files that already existed. Every other new test uses
  the public API, and `ContextValidityTests` checks each case through `NowSelector` (`SelectionFixtures.isSelected`).
- **Swift 6 concurrency.**
  - All new types are value types and `Sendable`.
  - There is no `@unchecked Sendable`, no `nonisolated(unsafe)` and no `Task {}`.
  - The static corpora (`SelectionCorpus.gate` / `.small`) are immutable `let` values of `Result<[SelectionCase], any
    Error>`, which is `Sendable`.
- **Architecture and determinism.**
  - Every new source imports only Foundation.
  - There is no `Date()`, no `.current` and no unseeded randomness. All test randomness goes through `SplitMix64`.
  - AC-M1-02 and AC-M1-23 scans still show 0 hits.
- **Performance (R-5).** `select` makes one O(n) pass with an O(3) insert and computes the slot of `now` once. The whole
  suite runs in about 11 s.

I found no Blocker or Major.

### Findings
| ID | Severity | file:line | Problem | Required change | Status |
|---|---|---|---|---|---|
| W3-F1 | Minor | `Sources/TendCore/Selection/SlotCalendar.swift:59-64` | **The DST policy and slot boundaries are proven on Linux only (R-3).** On Swift 6.2, Linux and Darwin both use swift-foundation's `Calendar`, so the risk is lower than it was. But iOS 26 runs the system Foundation, which is not the binary these tests ran against. | Rerun `SlotCalendarTests`, `ContextValidityTests` and the AC-M1-14/15/16 properties on the macOS lane when it exists (M3), as dev-notes already lists. No change in this PR. | Open (ticket, M3 macOS lane) |
| W3-F2 | Minor (watch, for WI-M1-04) | `SlotCalendar.swift:151` | **Floating-point `windowEnd` and AC-M1-20.** Reviewer analysis, not run here: (1) Dates near today are in the binade [2^29, 2^30) s since 2001, so ulp is about 1.19e-7 s. (2) `windowEnd = fl(s + D)`, and `windowEnd − s` is exact (Sterbenz), so after **pass 1** the duration `D₁` is `D` rounded to that ulp grid, which may differ from the stored `D₀` by ≤ 1 ulp. (3) From pass 2 on, `s` is either the previous `windowEnd` (on the grid) or a whole-second slot start (on the grid), so `s + D₁` is exact and `D` stays bit-identical. (4) This holds unless a pass crosses a binade edge: 2018-01-05 18:48:32Z (2^29 s) or 2035-01-10 13:37:04Z (2^30 s). There ulp doubles and `D` can round once more. AC-M1-20 compares pass N with **pass 1**, so it should hold for corpus dates. A test case that runs N = 60 week-long passes across 2035-01-10 could see one more rounding. | WI-M1-04: in the AC-M1-20 property, compare `windowEnd − windowStart` by `bitPattern`, and include one task whose passes cross 2035-01-10 13:37:04Z. If that case differs, take a reading of "identical" to the PO, or snap `s` to a grid. Do not loosen the comparison silently. No change in this PR. | Open (watch, WI-M1-04) |
| W3-F3 | Nit | `SlotCalendar.swift:150`; `NowSelector.swift:37` | **Two "cannot happen" fallbacks are silent.** `nextEligibleWindow` falls back to `?? anchor`, and `select` falls back to `?? .empty`. If an invariant ever broke, these would hide it: an `E` that starts outside an allowed slot, or an empty selection where valid tasks exist. The property tests would catch the second, but only for corpus inputs. | Optional: add `assertionFailure("…")` before each fallback, so a debug or test run fails loudly. Release behaviour stays calm. | Open (optional) |
| W3-F4 | Nit | `NowSelection.swift:28` | **`NowSelection.init?(items:)` is public**, so any caller can wrap ≤ 3 arbitrary tasks, including ones that are not contextually valid, as a "Now selection". The UX-2 cap still holds, so this is not a law issue. AC-M1-13's wording ("constructing one with 4+ items … returns nil") allows a public initialiser. | Optional, revisit in M3: state in the doc comment that surfaces must obtain a `NowSelection` only from `NowSelector`, or make the initialiser `internal` once tests use `@testable` for it. | Open (optional) |
| W3-F5 | Nit | `SlotCalendar.swift:143-148`; design.md naming list | **The naming list still shows `nextEligibleWindow(from:duration:)`.** The deviation is accepted (see Summary). | iOS Designer: update the design.md "Next window" row to `nextEligibleWindow(from:duration:calendar:timeZone:)` at the next design touch. | Open (Designer) |
| W3-F6 | Nit | `NowSelector.swift:26-29` | **The brief does not define duplicate task IDs** (dev-notes decision 4). With duplicates, the count can be below `min(3, valid)` because two copies of one ID count as one. The repository's upsert keeps IDs unique, so M1 cannot reach this. | PO, only if the M2 parser or M5 sync can produce duplicate IDs. This matches the Developer's own follow-up. | Open (PO, deferred) |

**AC trace (owned ACs):**
| AC | Code | Test(s) | Reviewer result |
|---|---|---|---|
| AC-M1-08 | `EnergyLevel.accepts`, `effortForMatching` (`ContextValidity.swift:11-17, 32-34`) | 3 × 4 parameterised, plus stored effort stays `high` | **Met.** M-a and M-b turn it red. |
| AC-M1-09 | `SlotCalendar.slots/slot(containing:)`, `Slot.isAllowed` | 12 boundaries incl. `hh:59:59.999`, all 15 daypart sets plus the default set; Tokyo / Los Angeles instant; zone-wins-over-calendar | **Met.** The exact millisecond boundaries the AC names are covered. |
| AC-M1-10 | night owned by its start day (`SlotCalendar.swift:85-112`) | 7 weekdays at 10:00, Friday 23:00 ✗, Saturday 01:00 ✗, Monday 01:00 ✓ and their edges; Los Angeles / Auckland | **Met.** M-d turns it red. |
| AC-M1-11 | `isSafeForWeatherDependentTasks` | 5 weathers × both tasks | **Met.** M-c turns it red. |
| AC-M1-12 | `isOfferable`, `windowIsOpen` (half-open) | 9 cases a–i with a sub-second `now`, plus maintenance and resurfaced | **Met.** RM-3 turns case (b) red. |
| AC-M1-13 | `NowSelection` (3 optional slots, failable init), `NowSelector` | 4…10 → `nil`, duplicate → `nil`, `Mirror` storage, 100 valid → 3, purity; public API listing in dev-notes, confirmed by the Reviewer's `public` grep | **Met.** |
| AC-M1-14 (Gate) | `NowSelector.select` | seeds 1…1000, 1,000 households, 50–500 tasks (min 50, max 500), 16 zones, every state incl. resting and rest over, window positions incl. `windowEnd == now` from the generator; ≤ 3, no duplicates, oracle-valid, element of the household; the seed is printed on failure | **Met.** The oracle is independent (see Summary). |
| AC-M1-15 | as above | 2,000 households (incl. 0–49 tasks, 14 empty); `count == min(3, oracle valid)`; all sizes 0–3 occur; empty and all-invalid (500 tasks, +100 y) → `.empty` | **Met.** |
| AC-M1-16 | `ranksBefore` + running top three | five resurfaced, equal-`windowEnd` ties, critical vs non-critical, 51 input orders; property: 2,000 corpus + 500 tie-heavy households equal the oracle's sorted prefix | **Met.** M-e and M-i turn it red. |
| `E(a, D)` (basis) | `nextAllowedStart`, `nextEligibleWindow` | 11 examples, purity and duration, DST policy, DST nights, 8 DST cases, Samoa, 1,000-case brute-force property | **Met** for WI-M1-03's scope. W3-F2 is the watch item for AC-M1-20. |
| AC-M1-02, AC-M1-23 | all of `Sources/` (20 files) | WI-M1-01 scans | **Still met.** 0 hits. |

### Checklist
- [x] Correctness against the ACs. Every owned AC is traced above to code and a test.
- [x] Tests are meaningful. Hand-written tables check both production and the oracle. The property tests are seeded
  and print the seed on failure, the corpus is large, and coverage is asserted. Nine Developer mutations and RM-3 all
  turned the suite red. No test is skipped or weakened.
- [x] Swift 6 concurrency is safe. Everything is a value type and `Sendable`; there are no unsafe escapes and no tasks.
- [x] No force unwraps and no `try!` in product code. The `?? anchor` and `?? .empty` fallbacks are W3-F3.
- [x] Privacy (P-1…P-4). This is pure computation on injected values, with no I/O and no networking.
- [x] UX-2 and UX-3 are enforced in the engine. The type caps the selection at 3, and D-1…D-3 are clean.
- [x] Accessibility (UI): n.a., there is no UI in M1.
- [x] Performance. One O(n) pass, and the slot of `now` is computed once. The whole suite runs in about 11 s.
- [x] No new dependency without an ADR. Only Foundation is used.

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | pass | The ≤ 3 cap is in the engine type (FR-B1, AC-M1-13): three storage slots, and a failable initialiser that rejects 4+ items or a repeated ID. Every public "what to do now" path returns `NowSelection`. A public-API grep found no unbounded "now" list. AC-M1-14/15 prove the cap over 2,000 households. W3-F4 is a Nit about provenance, not about the cap. |
| UX-3 Zero-Guilt | pass | No overdue state, counter or original-window field (D-2). The ranking key is fixed and does not grow with time (D-3). The code says "rest over" (D-1). An empty selection is a calm result (AC-M1-15). AC-M1-02 scan: 0 hits. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | Weather is injected, never fetched (Q8). There is no I/O. AC-M1-23 scan: 0 hits. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Open questions
- **Developer (WI-M1-04):** W3-F2. Assert duration identity by `bitPattern` in AC-M1-20, and add a case that crosses
  2035-01-10 13:37:04Z.
- **iOS Designer:** W3-F5. Ratify the `calendar:timeZone:` labels in the naming list.
- **Orchestrator:** dev-notes still says "PR: opened by the Orchestrator (link to be added)". The link is PR #7.
  **Documenter:** add traceability rows for AC-M1-08…16 and for `E(a, D)` as the basis of AC-M1-03 and AC-M1-17…21.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer (via Orchestrator) | Reviewer | received (round 1) | PR #7, commit `813be42` on `m1/rule-of-three-selector`, base `main` `7556df7`. Inputs: dev-notes WI-M1-03, brief v2, design.md, plan.md. |
| 2026-11-20 | Reviewer | Orchestrator → Acceptance Tester | accepted — APPROVE | No Blocker or Major. Two Minor tickets: W3-F1 (Darwin rerun of the DST and slot tests, M3) and W3-F2 (floating-point duration watch for WI-M1-04 / AC-M1-20). Four Nits: W3-F3…W3-F6. The local run gave "Test run with 104 tests in 14 suites passed after 10.979 seconds" (Linux, Swift 6.2, `-warnings-as-errors`, 0 warnings). RM-3 turned the suite red. The oracle is judged independent (R-4). The naming deviation is accepted. |

---

## WI-M1-04 round 1 — [PR #8](https://github.com/rmaheedharan/Tend/pull/8) (`m1/rescheduler`, head `dcf3d2c` = code commit `5ce6640` + merge of `main`)

- **Owner:** Reviewer  ·  **Verdict:** CHANGES REQUIRED  ·  **Round:** 1
- **Diff reviewed:** `git diff origin/main...dcf3d2c` (base `main` at `d29f874`, which contains WI-M1-03). 19 files:
  3 new `Sources/TendCore/Rescheduling/` files, additive `SlotCalendar.swift` changes, the W2-F1 change to
  `JSONFileHouseholdRepository.swift` / `HouseholdStoreError.swift`, 3 new test suites, the new
  `Support/RescheduleOracle.swift`, scanner and generator changes, `brief.md` (Q19/Q20 rows) and the WI-M1-04 dev-notes
  section. No protected path is touched (`CLAUDE.md`, `docs/PRD.md`, `.claude/**`, `.github/**`, `docs/governance/**`,
  `docs/milestones/STATUS.md`).
  **Owned ACs:** AC-M1-03, AC-M1-17, AC-M1-18, AC-M1-19, AC-M1-20 (Gate), AC-M1-21 (Gate), AC-M1-22, AC-M1-24 (Gate, local
  part). **Also in scope:** AC-M1-23 as amended by PO decisions Q19/Q20, tickets F-7…F-9, W2-F1, W3-F2.
  **Requirements:** FR-B1, FR-B2, FR-B3 (data), UX-2, UX-3, P-2. **Inputs:** [brief.md](brief.md) (R0–R4, `E(a, D)`,
  Q11–Q14, Q19, Q20), [design.md](design.md) (naming list, D-1…D-3), [plan.md](plan.md) (WI-M1-04, R-4, R-5, R-12),
  [dev-notes.md](dev-notes.md) (WI-M1-04), and the PO's answer to **Q21** relayed by the Orchestrator during this review.
- **Verified by the Reviewer** (Linux container, Swift 6.2 via the Docker wrapper, clean worktree at `dcf3d2c`):
  `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` exited 0 with
  **"✔ Test run with 127 tests in 17 suites passed after 93.738 seconds."** 0 failures, 0 warnings, 1 m 54 s wall time
  including the build.
  - `AC-M1-20: seeds 600001...600040, 360 chains (R2, R3, R4 x one-off, recurring, restock), 21600 pass comparisons
    against pass 1 (N = 1...60), duration compared by bit pattern, longest chain moved 844 days`.
  - `W3-F2 measurement: 36 chains cross 2035-01-10 13:37:04 +0000 (2^30 s); one step = 1.1920928955078125e-07 s; 36
    chains change their duration once, by one step` (at N = 3, 5 or 7, signs + and −).
  - `AC-M1-21: seeds 400001...400500, 500 households, 135474 tasks (min 50, max 500 per household), 108303 with ended
    windows (54138 ending exactly at now; 15018 rest over, 14941 resting, 30337 completed)`; `outcomes unchanged 68626,
    restEnded 3823, lightened 22485, broughtBackGently 22622, movedToNextWindow 17918; selection sizes 0/1/2/3 after the
    pass = 0/1/2/497`.
  - `AC-M1-22: 10 households (seeds 400001...400010), 1000 repeated runs …: all identical`.
- **Reviewer probe RP-1** (a scratch copy of the package outside the repo; nothing in the PR changed). In
  `ReschedulerPropertyTests.swift:204` the duration generator was changed from `2k + 1` (odd) to `2k` (even, k ≥ 1)
  fine steps, and only `structureAcrossBinadeEdge` was run. Result: **0 of 36 even-step chains changed their duration**
  across 2^30 s, so production behaves as Q21 requires. The only failure was the guard at `:240` (`!report.isEmpty`).
  This shows that the shipped test runs **odd-step durations only**: its "no change for even steps" branch (`:225-227`)
  is never exercised. See R4-F1.

### Summary
The engine code is correct, small and law-clean. The one Major finding is about **evidence**: the AC-M1-20 edge test
does not yet cover the even-step half of the PO's Q21 reading.

- **R0–R4 vs the brief (AC-M1-17…21).** `Rescheduler.reschedule(_:at:slots:)` (`Rescheduler.swift:107-139`) follows the
  binding order exactly.
  - R0: `completed` or `isResting(at:)` (`until > now`) returns the task unchanged.
  - R1: `isRestOver(at:)` (`until <= now`) sets `active`. If the window has not ended, it returns `restEnded`.
  - Window ended (`windowEnd <= now`, half-open per Q13): new window = `E(now, D)` with `D = windowEnd − windowStart`.
    Then deep clean → `maintenance` (R2), critical → `resurfaced` (R3), otherwise the state stays `active` (R4).
  - The model invariants (AC-M1-25) make the deep-clean-before-critical order safe, and they rule out `maintenance` or
    `resurfaced` on an R4 task. Only `state`, `windowStart` and `windowEnd` are written. A second pass is a no-op,
    because the new `windowEnd > now` (`D > 0`).
  - The hand-computed tables in `ReschedulerTests.swift` pin exact UTC starts for `windowEnd == now`, inside/outside a
    slot, the night slot both ways across midnight, DST spring/autumn and the repeated 01:30. They also check `D` by
    `bitPattern` and every other field. AC-M1-21 (d) checks every task of 500 households against the oracle.
- **Completion (AC-M1-03).** `Household.complete` (`Completion.swift:17-29`) and `HouseholdTask.completed(at:slots:)`
  (`:34-52`) match (a)–(c).
  - The recurring anchor `sameWallClockTime` (`SlotCalendar.swift:120-136`) uses noon-anchored day arithmetic, then
    `date(bySettingHour:…, .nextTime, .first)`. That is the Q11 policy. The dev-notes probe explains why
    `date(byAdding: .day)` is not used, and mutation MS-3 pins the gap behaviour.
  - Sub-second preservation via `t − floor(t)` is correct, because zone offsets are whole seconds.
  - Completing a resting deferral completes it. AC-M1-03 lists `deferred`, so that is right.
  - Returning `false` for an unknown or already completed ID is outside the brief, but it is calm and documented.
- **UX-3 / D-1 / D-2 / D-3.**
  - No stored field was added. The `Mirror` test (`ReschedulerTests.swift`, "no escalation field") pins the 15 stored
    labels to the design list after 20 passes, and the encoded keys too.
  - `RescheduleOutcome` is returned, never stored. `promptTone` is computed and always `.gentle`, and `PromptTone` has
    one case (AC-M1-18).
  - There is no counter, no original window, no history (`completedAt` is the latest completion only, as the design
    row says) and no score.
  - A grep of `Rescheduling/` and the `SlotCalendar.swift` diff for the design-forbidden list finds only comments that
    say "never a count" or "never lapsed". AC-M1-02 scan: 0 hits.
- **Oracle independence (R-4). Judged independent.**
  - `Support/RescheduleOracle.swift` imports only the public API. It calls no engine function: not `Rescheduler`,
    `SlotCalendar`, `nextEligibleWindow`, `isRestOver` or `windowHasEnded`. It rebuilds expected tasks through the
    public validating initialiser, which is the model.
  - R0–R4 is a `switch` on the stored state with its own `until > now` and `windowEnd <= now` tests.
  - `E` reuses `ContextOracle.nextAllowedStart`, the brute-force 15-minute scan that WI-M1-03 already judged
    independent.
  - The recurring anchor works differently from production: UTC day arithmetic, then solving `local = utc + offset`
    over the offsets seen ±2 days, with `nextDaylightSavingTimeTransition` for a gap. Production uses
    `bySettingHour`/`.nextTime`.
  - The only shared piece is the one-line sub-second fraction `t − floor(t)`. MS-2 shows that dropping it turns tests
    red, so this is not a tautology.
  - The documented limit (non-DST offset gaps such as Samoa 2011 are outside the oracle's gap branch) is acceptable.
    No corpus zone hits it, and the hand tables are the second line of defence.
- **AC-M1-20 and Q21.** The PO answered Q21 during this review: "identical" means bit-identical within a binade, with
  no tolerance. Only at a binade edge may the duration change once, at the pass that first reaches the edge or the next
  one. Evidence must be a strict `bitPattern` gate over the realistic corpus, plus a named edge test with an explicit
  edge predicate that shows exactly one ±1-step change for odd-step durations and **none for even ones**.
  - The gate test (`ReschedulerPropertyTests.swift:131-177`) compares every pass N = 1…60 with pass 1 using exact
    `bitPattern` equality, with no tolerance. It also compares exact key sets, byte-equal canonical JSON of the
    non-window values, and collection counts. **This meets the gate part.**
  - The edge test (`:191-241`) has an explicit edge predicate (`edgePass = firstIndex { windowEnd >= binadeEdge }`,
    `change == edgePass || change == edgePass + 1`). It uses exact equality only (`changes.count == …`,
    `abs(Δ) == fineStep`), and it checks structure for all N. It is honest and not weakened.
  - **But it only generates odd-step durations** (`:204`, `2k + 1`), so the even-step clause is untested (RP-1). That
    is R4-F1.
  - The "one step" size is also worded differently in Q21 and in the code (R4-F2).
- **W3-F2.** Closed by the strict gate and the edge test. The remaining evidence gap is tracked as R4-F1.
- **Scanner vs Q19/Q20 (AC-M1-23). Matches exactly, and the tightening is acceptable.**
  - Q19: `NSURL`, `URLComponents` and `CFURL` are banned at camelCase boundaries. `urlLoadingInitPattern` covers exactly
    the eight listed types with `(contentsOf:` or `.init(contentsOf:`, plus any `.init(contentsOf:`, and only outside
    the fixed allowlist.
  - Q20: all 14 names are present (`clockNames`, `networkingNames`, `socket(` as a call name).
  - Planted positives cover every new name, including `Foundation.Data(`, `Data . init ( contentsOf :`,
    `.init(contentsOf:`, `Glibc.socket(` and `gethostbyname2`. Near-misses cover `append`/`insert(contentsOf:)`,
    `String(contentsOfFile:)`, `MyData(`, `NSURLish`, `fileURLComponent`, `ContinuousClockwise`, `machAbsoluteTime`,
    `freeaddrinfo`, `websocket(` and `let socket = 1`. The coverage test includes `clockNames` and the URL-loading rule.
  - Matching `DispatchTimeInterval` as a hit is stricter than "whole type names", but it follows the AC's general
    camelCase-boundary rule. I accept it as tightening only.
  - F-7 (`Name.init(`) is closed. The Q17 exemption stays exact: `MyAsyncStream.init(` is a planted hit.
  - **F-7, F-8 and F-9 are closed.**
- **W2-F1. Closed.** `init(fileURL:)` is `throws(HouseholdStoreError)` and rejects `!fileURL.isFileURL` before storing
  anything (`JSONFileHouseholdRepository.swift:29-38`). The test covers `https`, `http`, `ftp`, `data:` and a
  scheme-less relative URL, through both initialisers, and asserts the writer is never called. Reusing `unreadableFile`
  keeps the design's four-case error list.
- **No RNG parameter (plan deviation). Accepted.** An input the engine must never read would misstate the API, and the
  approved `NowSelector` (WI-M1-03) has none either. The AC-M1-22 clause "two different RNG seeds give identical
  outputs" is then met by construction: no engine API takes an RNG, and AC-M1-23 bans every ambient RNG. The test's
  perturbation of an unrelated generator adds little. The Work Planner should amend plan.md WI-M1-04 ("takes an
  injected RNG"), and the Acceptance Tester should read AC-M1-22's seed clause this way (R4-F4).
- **Naming deviation `Household.complete(_:at:calendar:timeZone:)`. Accepted.** It is the same reason as WI-M1-03's
  accepted `E` labels: the recurring anchor must resolve in the injected calendar and zone (CLAUDE.md §3). It lives on
  `Household` because it also tends the room. design.md allows a recorded deviation, and dev-notes records it. The
  Designer should ratify it in the naming list (R4-F5).
- **Swift 6 concurrency.** New sources are pure value-type code. The test-only `WriteCallCounter` is
  `final class: Sendable` over `Synchronization.Mutex`, which is available under the package's iOS 26 / macOS 26 floor.
  There is no `@unchecked Sendable`, no `nonisolated(unsafe)` and no `Task {}`.
- **Architecture.** Every new source imports only Foundation. There is no new dependency. AC-M1-23 scan: 0 hits.
- **Performance (R-5).** The suite went from about 11 s to about 94 s (AC-M1-21's brute-force `E` oracle over 135k
  tasks dominates, and AC-M1-22 shares the lazily built corpus). The production pass is O(n) with one `SlotCalendar`
  per pass. The suite is far inside the 20-minute CI timeout, and no AC count was lowered. Watch the first CI run
  (R4-F6).

### Findings
| ID | Severity | file:line | Problem | Required change | Status |
|---|---|---|---|---|---|
| R4-F1 | **Major** | `Tests/TendCoreTests/ReschedulerPropertyTests.swift:204, 225-227, 240` | **The AC-M1-20 edge test does not show "no change for even-step durations", which the PO's Q21 answer requires as evidence for this Gate AC.** The generator is `2 * k + 1`, so all 36 chains are odd-step and the `isOddSteps ? 1 : 0` branch never takes the `0` side. RP-1 shows production is right (0/36 even chains change), so this is missing evidence, not a code defect. Under the review rules, a missing test for an AC condition is Major. | Make the edge test generate both parities. For example, per seed, run each rule with one odd-step duration (`2k + 1`) and one even-step duration (`2k`, k ≥ 1). Keep the exact assertions. Add guards that at least one even chain and at least one odd chain ran, and that every even chain had `changes.isEmpty`. Log the counts (e.g. `odd n changed once; even m unchanged`). No tolerance anywhere. Update the test name and dev-notes evidence to match. | Open |
| R4-F2 | Minor (PO wording, before Q21 is recorded) | `ReschedulerPropertyTests.swift:193-194, 231`; Q21 text as relayed | **The step size in Q21 as relayed ("exactly one ulp of the coarser grid") does not match the arithmetic or the test.** Above 2^30 s the coarse ulp is 2^-22 s. An odd multiple of 2^-23 s added to a coarse-grid `s` lies exactly halfway between two coarse points, so round-to-nearest moves it by **2^-23 s**: one ulp of the finer grid below the edge, which is half a coarse ulp. The test asserts `abs(Δ) == fineStep` (2^-23 s), and the measured log agrees (`one step = 1.1920928955078125e-07 s`). If Q21 is recorded as written, the Tester would read the correct test as non-conforming. | **PO / Orchestrator:** record Q21 as "changes once by exactly one ulp of the finer grid below the edge (2^-23 s at 2^30 s; half an ulp of the coarser grid)", or as "by exactly one rounding step of `s + D`". No Developer change is needed if the PO confirms. | Open (PO) |
| R4-F3 | Minor (process) | `docs/milestones/M1/brief.md` (Q19/Q20 rows, handoff row) in Developer commit `5ce6640` | **The PO-owned brief was committed by the Developer** ("the PO's uncommitted Q19/Q20 edits, committed unchanged"). The text matches what the Reviewer asked for in Q-R3/Q-R4 and is tightening only, so nothing is wrong in substance. But the brief's provenance should be the PO's. | PO: confirm in the brief's handoff log that the committed Q19/Q20 text is the PO's decision, when Q21 is recorded. In future, the PO commits PO-owned edits. | Open (PO) |
| R4-F4 | Nit | `docs/milestones/M1/plan.md` WI-M1-04 ("engine takes an injected RNG … must not use it"); `ReschedulerPropertyTests.swift:331-362` | **Plan deviation: no RNG parameter.** Accepted on the merits (see Summary). The AC-M1-22 seed clause is met by construction, so the two-seed perturbation in the test proves little on its own. | Work Planner: amend plan.md to match. Acceptance Tester: read AC-M1-22's seed clause as "no engine input is random; ambient RNG banned by AC-M1-23". Reopen only if the PO wants the unused parameter. | Open (Planner / Tester) |
| R4-F5 | Nit | `Completion.swift:17-19`; design.md naming list (`complete(_:at:)`) | **Naming deviation**, accepted (same reason as W3-F5). | iOS Designer: update the naming list to `Household.complete(_:at:calendar:timeZone:)` together with W3-F5. | Open (Designer) |
| R4-F6 | Nit (watch, R-5) | `ReschedulerPropertyTests.swift:245-327`; `Support/RescheduleOracle.swift:40-48` | **Runtime is about 94 s (was about 11 s).** The brute-force `E` oracle over about 108k ended tasks dominates. This is fine against the 20-minute CI limit, but CI runners can be 2–4× slower. | Record the CI duration of the first run in dev-notes. If it ever gets tight, speed up the oracle (e.g. a 15-minute scan that skips whole disallowed days). Never lower the AC counts. | Open (watch) |
| R4-F7 | Nit | `Completion.swift:42-44` | **W3-F3 carried:** two silent "cannot happen" fallbacks are new (`recurrenceIntervalDays ?? 1`, `now + days × 86,400 s`). | Optional: `assertionFailure` before each, together with W3-F3. | Open (optional) |

Closed by this PR (verified in the diff and tests): **F-7, F-8 (via Q19), F-9 (via Q20), W2-F1, W3-F2** (the residual
evidence gap is R4-F1).

**AC trace (owned ACs):**
| AC | Code | Test(s) | Reviewer result |
|---|---|---|---|
| AC-M1-03 | `Completion.swift:17-52`, `SlotCalendar.sameWallClockTime` | (a) 2 kinds × 5 states; (b) 9 hand cases incl. New York gap 02:30:15.250 → 03:00, repeated 01:30 → first, Berlin weekly/weekend; (c) no room / unknown room; isolation; 300-household oracle property (4,250 completions, 45 near DST) | **Met.** MC-1…MC-4, MS-1…MS-3 red. |
| AC-M1-17 | `Rescheduler.swift:129-131` | 8 window cases × 3 start states incl. `windowEnd == now`, night across midnight, DST days; low-energy selection after the lightening | **Met.** |
| AC-M1-18 | `Rescheduler.swift:132-134`, `promptTone` | 8 × 3 states; 20-pass tone/labels/keys test | **Met.** No escalation field. |
| AC-M1-19 | `Rescheduler.swift:135-136` | 3 kinds × 8 cases (interval not applied); R1 + ended; R0; R1 only; open/upcoming unchanged | **Met.** |
| AC-M1-20 (Gate) | whole pass | strict `bitPattern` gate over 360 chains × 60; W3-F2 edge test (odd-step only) | **Gate part met. Edge evidence incomplete under Q21: R4-F1 (Major).** |
| AC-M1-21 (Gate) | whole pass | 500 households, 135,474 tasks, (a)–(f) incl. oracle order after the pass | **Met.** Oracle independent. |
| AC-M1-22 | whole pass + selector | 10 households × 100 runs, two seeds | **Met** (seed clause by construction, R4-F4). |
| AC-M1-23 (Q19/Q20) | `Support/SourceScanner.swift` | 117 planted, coverage, near-miss, positive tests; real scan 23 files, 0 hits | **Met.** |
| AC-M1-24 (Gate) | — | local run above | **Local part met.** CI on the M1 merge commit is the Tester's / Gatekeeper's. |
| AC-M1-02 | all `Sources/` | scan, 23 files | **Still met.** 0 hits. |

### Checklist
- [x] Correctness vs ACs. Code meets AC-M1-03 and 17…23. AC-M1-20 evidence is incomplete under Q21 (R4-F1).
- [ ] Tests meaningful: mostly yes. There are 21 Developer mutations, all red. The oracle is independent and seeded, and
  coverage is asserted. **Except** that the even-step branch of the edge test is dead (RP-1, R4-F1).
- [x] Swift 6 concurrency safe. Value types only; the test `Mutex` counter is `Sendable`.
- [x] No force unwraps / `try!` in product code. Silent fallbacks are R4-F7 / W3-F3.
- [x] Privacy (P-1…P-4). No I/O in the engine. W2-F1 adds a file-URL-only boundary; the AC-M1-23 guard is stricter.
- [x] UX-2/UX-3 enforced in engine. No unbounded "now" list; no counter, original window, history or score.
- [x] Accessibility (UI): n.a., no UI in M1.
- [x] Performance. O(n) pass; test runtime watched (R4-F6).
- [x] No new dependency without ADR. Foundation only (`Synchronization` in the test target only, part of the toolchain).

### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface; completion and rescheduling are engine calls. |
| UX-2 Rule of Three | pass | No new "what to do now" API. `Rescheduler` returns the stored household, and the per-task overload returns one task. AC-M1-21 (f) proves selection after a pass is ≤ 3, valid, `min(3, n)` and oracle-ordered over 500 households. |
| UX-3 Zero-Guilt | pass | Ended windows become `maintenance`, `resurfaced` or a new window; there is no overdue state (FR-B2). No counter, original window, history or time-growing score (D-2, D-3; pinned by the `Mirror`/key test after 20 passes). The structure does not grow over 60 passes (AC-M1-20 gate). The tone is fixed `gentle` (AC-M1-18). The code says "rest ended", never "lapsed" (D-1). AC-M1-02 scan: 0 hits. |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | Pure computation on injected values. W2-F1 refuses non-file URLs before any read or write. AC-M1-23 is stricter (Q19/Q20, F-7): 23 files, 0 hits. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

### Open questions
- **PO (R4-F2):** before Q21 is recorded in brief.md, correct the step size to "one ulp of the finer grid (2^-23 s at
  2^30 s), i.e. half an ulp of the coarser grid". As relayed ("one ulp of the coarser grid", 2^-22 s), it contradicts
  the measured and correct behaviour.
- **PO (R4-F3):** confirm the Q19/Q20 brief text committed by the Developer is the PO's.
- **Work Planner (R4-F4):** amend plan.md WI-M1-04 (no RNG parameter). **iOS Designer (R4-F5):** naming list.
- **Developer:** R4-F1 only. Everything else in this round is optional or for other roles.

### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer (via Orchestrator) | Reviewer | received (round 1) | PR #8, head `dcf3d2c` (code `5ce6640` + merge of `main` `d29f874`) on `m1/rescheduler`. Inputs: dev-notes WI-M1-04, brief (R0–R4, Q19, Q20), design.md, plan.md. Mid-review: the PO's Q21 answer, relayed by the Orchestrator. |
| 2026-11-20 | Reviewer | Orchestrator → Developer | returned — CHANGES REQUIRED | One Major: R4-F1 (the AC-M1-20 edge test never runs even-step durations, so Q21's "none for even ones" is unproven; RP-1 shows the code is right). Minor to PO: R4-F2 (Q21 step size is 2^-23 s, not a coarse ulp) and R4-F3 (brief provenance). Nits: R4-F4…F7. Closed: F-7, F-8, F-9, W2-F1, W3-F2. Local run: "Test run with 127 tests in 17 suites passed after 93.738 seconds" (Linux, Swift 6.2, `-warnings-as-errors`, 0 warnings). Oracle judged independent (R-4). RNG-parameter and naming deviations accepted. |

### WI-M1-04 round 2 — [PR #8](https://github.com/rmaheedharan/Tend/pull/8) (`m1/rescheduler`, head `6ac5caa`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 2
- **Diff reviewed:** `git diff a8ad7a7..6ac5caa`, which is two commits.
  - `0c30b21` (Developer): `Completion.swift`, `ReschedulerPropertyTests.swift`, and a round-2 dev-notes section.
  - `6ac5caa` (Orchestrator): brief.md records PO decisions Q21 and Q22, and marks Q8 as resolved by Q22.
  - No protected path is touched.
- **ACs:** AC-M1-20 (Gate) under PO decision Q21, and AC-M1-03 (R4-F7 fallbacks). **Requirements:** FR-B2, UX-3.
- **Verified by the Reviewer** (Linux container, Swift 6.2 via the Docker wrapper, fresh worktree at `6ac5caa`):
  - `swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors` exited 0 with
    **"✔ Test run with 127 tests in 17 suites passed after 95.998 seconds."**
  - There were 0 failures and 0 warnings. Wall time was 1 m 56 s, including the build.
  - Edge-test log: `W3-F2 / Q21 measurement: 72 chains cross 2035-01-10 13:37:04 +0000 (2^30 s); one step =
    1.1920928955078125e-07 s; odd-step 36 chains, 36 changed exactly once; even-step 36 chains, 36 unchanged`.
  - The AC-M1-20 gate and AC-M1-21 logs are identical to round 1 (360 chains / 21,600 comparisons; 500 households).

#### Summary
- **R4-F1 (Major), closed. The new edge test matches Q21 as recorded in brief.md, clause by clause.**
  - **Q21 (a), bit-identical within a binade, no tolerance:**
    - Durations are compared as `Double(bitPattern:)` values with `!=`, and the step check is `abs(Δ) == fineStep`.
    - No epsilon or tolerance appears anywhere in the test.
    - The AC-M1-20 gate test (`ReschedulerPropertyTests.swift:131-177`) is unchanged: strict `bitPattern` over the
      2024–2029 corpus.
  - **Q21 (b), exactly one ulp of the finer grid, odd-step only, at the edge pass or the next:**
    - The test pins `fineStep == 0x1p-23` and the coarse ulp `0x1p-22`, so the step is the finer grid's ulp.
    - For each seed, each rule type (R2, R3, R4) runs one odd-step chain (`2k + 1`) and one even-step chain (`2k`, k ≥ 1).
    - The edge predicate is explicit: `edgePass = firstIndex { windowEnd >= binadeEdge }` and
      `change == edgePass || change == edgePass + 1`.
    - Odd-step chains must change exactly once, by exactly one fine step. Even-step chains must not change at all.
    - Guards check that both parities ran (`oddChains > 0 && evenChains > 0`) and that every chain met its rule.
    - A new `isOddSteps == parity.odd` check proves that the pass-1 duration carries the generated parity. This closes
      the dead-branch gap that RP-1 found.
  - **Q21 (c), nothing else changes:**
    - Key paths, non-window values (canonical JSON) and collection counts are compared with pass 1 for all N = 1…60
      in every chain.
    - Each chain is asserted to cross the edge.
  - The Developer's drift mutation (one ulp added per pass above the edge) turned the test red. That matches my reading
    that the assertions are exact.
- **R4-F2 (Minor, PO), closed.**
  - brief.md Q21 now says "exactly one ulp of the finer grid below that edge (half an ulp of the coarser grid above
    it); at the 2^30 s edge that is 2^-23 s".
  - That matches the test (`abs(Δ) == fineStep`, `fineStep == 0x1p-23`) and the measured log (`one step =
    1.1920928955078125e-07 s`).
- **R4-F3 (Minor, process), closed.**
  - I confirm that brief.md lines 298–299 at `6ac5caa` are the Q19 and Q20 rows.
  - They are byte-identical to the rows the Developer committed in `5ce6640`: the same md5 over both lines,
    `f6df054e…`. `6ac5caa` changes neither row.
  - The PO's adoption of the rows as written is therefore valid.
  - The Q19/Q20 rows were checked against the scanner in round 1 and still match exactly.
- **R4-F7 (Nit), closed.**
  - Both unreachable fallbacks in `Completion.swift:41-57` now call `assertionFailure` before the calm release
    fallback: the missing recurrence interval (AC-M1-25 invariant) and a calendar day that cannot be resolved.
  - The messages contain no household content.
  - The suite passes in debug builds, so neither path is reached by any test. That is expected.
  - W3-F3's older fallbacks (WI-M1-03) are left as they were, which is fine.
- **Q22 (brief.md, Orchestrator commit).** The engine is not affected.
  - `TendCore` keeps weather as an injected input, and AC-M1-11 and AC-M1-23 are unchanged.
  - Any real weather source needs an ADR first (P-2). Noted for M3/M4, with no finding here.
- **No new product logic.** The only source change is R4-F7. The round-1 conclusions on R0–R4, UX-3/D-2/D-3, oracle
  independence, the scanner, W2-F1, the RNG deviation and the naming deviation still hold.

#### Findings
| ID | Severity | file:line | Problem | Required change | Status |
|---|---|---|---|---|---|
| R4-F1 | Major | `ReschedulerPropertyTests.swift:191-255` | Edge test ran odd-step durations only. | Both parities, exact assertions, count guards. | **Closed** (verified: 36 odd changed once, 36 even unchanged; matches Q21 (a)–(c)) |
| R4-F2 | Minor (PO) | brief.md Q21 | Step size wording. | Q21 says one ulp of the finer grid, 2^-23 s. | **Closed** (verified in brief.md at `6ac5caa`) |
| R4-F3 | Minor (process) | brief.md:298-299 | Brief rows committed by the Developer. | PO adopts the rows if they match. | **Closed** (rows byte-identical to `5ce6640`) |
| R4-F4 | Nit | plan.md WI-M1-04 | The plan still says the engine takes an injected RNG. | Work Planner amends plan.md; Tester reads AC-M1-22's seed clause as met by construction. | Open (Planner / Tester; non-blocking) |
| R4-F5 | Nit | design.md naming list | `Household.complete(_:at:calendar:timeZone:)` is not yet in the list. | iOS Designer ratifies it, together with W3-F5. | Open (Designer; non-blocking) |
| R4-F6 | Nit (watch, R-5) | test runtime | About 96 s locally. | Record the first CI duration. | Open (watch) |
| R4-F7 | Nit | `Completion.swift:41-57` | Silent fallbacks. | `assertionFailure` before each. | **Closed** |

#### Checklist
- [x] Correctness vs ACs. AC-M1-03 and AC-M1-17…23 are met. AC-M1-20 evidence now meets Q21 in full.
- [x] Tests meaningful. Both parities run, the guards make dead branches impossible, and the drift mutation turns the
  test red. No tolerance anywhere.
- [x] Swift 6 concurrency safe. Unchanged since round 1.
- [x] No force unwraps / `try!` in product code. The fallbacks now assert in debug builds.
- [x] Privacy (P-1…P-4). Q22 keeps weather injected; the ADR comes before any wiring.
- [x] UX-2/UX-3 enforced in engine.
- [x] Accessibility (UI): n.a.
- [x] Performance. The test-runtime watch (R4-F6) is the only open item.
- [x] No new dependency without ADR.

#### Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | pass | Unchanged from round 1. AC-M1-21 (f) holds over 500 households after the pass. |
| UX-3 Zero-Guilt | pass | The structure does not grow with N. That is proven bit for bit within a binade, and at the 2^30 s edge only by the single rounding step Q21 allows (FR-B2, AC-M1-20). There is no counter, original window or score (D-2, D-3). |
| UX-4 Design craft | n.a. | No UI in M1. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass | No source change touches I/O. Q22 keeps weather injected in `TendCore`, and any real source needs an ADR first. AC-M1-23 scan: 0 hits. |
| P-3 Cloud escalation only via PCC + ADR | n.a. | No cloud path. |
| P-4 Media not persisted without consent | n.a. | No media. |

#### Open questions
- None blocking. The remaining Nits go to their owners: R4-F4 (Work Planner / Acceptance Tester), R4-F5 (iOS Designer)
  and R4-F6 (watch the first CI run).
- AC-M1-24 still needs Linux CI on the M1 merge commit (Acceptance Tester / Merge Gatekeeper).

#### Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Developer + Orchestrator | Reviewer | received (round 2) | `0c30b21` (R4-F1, R4-F7) and `6ac5caa` (Q21 corrected wording, Q22) on `m1/rescheduler`. |
| 2026-11-20 | Reviewer | Orchestrator → Acceptance Tester | accepted — APPROVE | R4-F1 (Major), R4-F2, R4-F3 and R4-F7 closed and verified. Open Nits only: R4-F4, R4-F5, R4-F6. No open Blocker or Major. "Test run with 127 tests in 17 suites passed after 95.998 seconds" (Linux, Swift 6.2, `-warnings-as-errors`, 0 warnings). The edge test matches Q21 (a)–(c): 36 odd-step chains changed once by 2^-23 s, 36 even-step chains unchanged, no tolerance. |
