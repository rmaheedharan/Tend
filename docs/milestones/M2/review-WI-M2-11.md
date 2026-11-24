# M2 Code Review — WI-M2-11 payload proof: sentinels and structure (PR #31, `m2/payload-sentinels`, head `bb006e8`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** ● AC-M2-20 (a) and (b), P-2, P-3, P-4, FR-A1. Also closes review tickets R28-F2 (prove it through
  the path that sends, plus the D11 blank-room test) and R28-F6 (compare concrete indices). Regression runs of AC-M2-09
  and AC-M2-12.
- **Binding inputs checked:** `CLAUDE.md`. Brief: Definitions ("Cloud request", "Duplicate shortlist"), AC-M2-20 in
  full, Q12 and Q19. Plan: the WI-M2-11 row and R-23. `review-WI-M2-10.md`: R28-F2 and R28-F6 (round 1 text and round 2
  status). Dev-notes: WI-M2-10 (D1–D17, round 2 tickets) and WI-M2-11 (D1–D7, open questions 1–2). PO notes
  `po-m2-wi10.md` and `owner-decisions.md`. The owner confirmed Q12 = yes (up to 10 titles), Q16 and Q17 on
  2026-11-24, so the committed goldens and allowed lists stand and nothing needed regenerating.
- **Milestone lock:** `STATUS.md` shows M2 `IN-BUILD`. WI-M2-10, the dependency, is merged (PR #28, `f1b6458`).
  Allowed.
- **Diff:** `git diff f1b6458...bb006e8`. Only 4 files change: two new test files
  (`PayloadSentinelSupport.swift`, `PayloadSentinelTests.swift`), one README paragraph
  (`Fixtures/M2/payload/README.md`) and `dev-notes.md`. No file under `Sources` changes, no fixture byte changes, no
  dependency is added and no protected path is touched.

## Summary
This is a strong proof. The checks are independent of the code under test, and I confirmed that they fail when the
code is wrong.
- Every capture goes `ModelRouter.events(…)` → `DraftPipeline` → the cloud model → `CloudPayloadBuilder` → the
  recording mock transport. The assertions run on the captured `CloudRequest`, as the AC requires.
- 520 seeded households per provider (≥ 500), for both Q12 answers: 1,040 requests per provider and 3,120 in total.
- The expectations come from outside the code under test:
  - the room names come straight from the household;
  - the titles come from `DupOracle`, the WI-M2-07 oracle, which calls no production code;
  - every fixed byte and value comes from the committed G1 golden files and allowed lists.
- Structural check (b): body bytes outside the user-content literal must equal G1's byte for byte. The request line
  must equal G1's, and so must the header names and every non-auth header value. The user content must parse to
  exactly the expected leaves. Together these pin every byte of the request except the auth header value (F1).

Two Minors and four Nits, none blocking.

### AC-M2-20, clause by clause
| Clause | Where | Verified | Result |
|---|---|---|---|
| ≥ 500 seeded households, for each provider | `PayloadSentinelTests.swift:19-22`; 520 households × 3 providers × Q12 yes/no; seed `0x0A1D_2011_0001`, printed | My run logs 520 households and 1,040 requests per provider for both (a) and (b), and `requests == households × 2` is asserted | pass |
| Context selector and payload builder build the request; sent through a recording mock transport; assert on the captured request | `PayloadRouterHarness` (`PayloadSentinelSupport.swift:588-617`) sets cloud on and the on-device model unavailable, so the route is `.cloud(provider)`, which is asserted. Exactly one captured request is required, or an issue is recorded. Selector = oracle is checked at `PayloadSentinelTests.swift:98-100` | Read. My mutant RM4 (only the selector trims room names) is killed by (b), D11 and the golden control | pass |
| (a) Sentinels: task and room IDs | `PayloadSentinels.forms(_ id:)`: upper and lower case, with and without hyphens; also the task's `roomID`, including dangling IDs | 92,720 task-ID and 16,360 room-ID sentinels per provider | pass |
| (a) Titles of tasks not on the shortlist | The trimmed title, plus a unique letters-only token `zq…` in every title. Under Q12 = no every title is a sentinel | 20,208 per provider; 136 shortlists cut at 10; 2,972 titles sent | pass |
| (a) `windowStart`, `windowEnd`, `completedAt`, `lastTendedAt`, in four forms | `forms(_ date:)`: ISO 8601 to the second (UTC and local), Unix seconds, Unix milliseconds, reference-date seconds. Dates have whole milliseconds, so each form is exact. Also `deferred(until:)` | Every label is present in the log line, and their presence is asserted (`:74-79`) | pass |
| (a) Interval sentinels 600…729: decimal form absent from fixed content and capture; no JSON number equals one, no string contains one; none in path, query or header values | `intervalProblems` walks the decoded body: integers, then 3-digit runs in strings, then the decoded user content. It also checks the path, the query and the header values. Words are letters only. All 130 values are used (`intervals.count >= 100` is asserted) | The run over the whole body shows the fixed content contains no 600…729 run. The precondition is checked, not assumed | pass |
| (a) `now`, time-zone identifier, calendar identifier | 10 zones and 10 calendars, plus a random `now` in four forms | I checked in `swift:6.2-noble` that all 10 zones resolve (no `.gmt` fallback). See N1 on the "Swift case name" form | pass |
| (a) Absent from method, path, query, header names, header values, body | `PayloadSentinels.parts`: also the host and the auth value | `sentinelsArePlanted` plants 6 forms in the body, path, query, a header name and a header value, and every plant is found | pass (escape forms: F2) |
| (b) Key-path set = the provider's allowed list (`[]` form) | `CloudRequestKeyPaths.leafPaths(ofBody:)` compared with the committed list | — | pass |
| (b) Capture, room names in order, titles with indices 1…n exact | `expectedUserContentLeaves` + `jsonEqual` (scalar-exact). Path sets must be equal, and the layout must be inside `userContentKeyPaths` | `structureCatchesUserContent`: extra room, reordered rooms and titles, a dropped title, a changed capture, index 0 and an extra slot member are all caught | pass |
| (b) Every other path = the golden's value | `fixedLeaves` at **concrete** indices (R28-F6), plus the byte frame before and after the user-content literal | `structureCatchesTampering`: an extra message, an extra part and an extra enum element keep the `[]` set (asserted) but are caught, and so are an added member and a changed value | pass |
| (b) Header names = fixed list; non-auth values = golden | `PayloadStructure.problems` lines 485-503 | Extra header, changed value, changed path and added query are caught. The auth value itself is not pinned (F1) | pass (F1) |
| Q12 = yes: titles = shortlist in rank order, n ≤ 10; Q12 = no: no title | Oracle titles under yes, none under no, in both properties | My mutant RM1 (shortlist ranking R step reversed) is killed by (a), (b) and the golden control | pass |
| Media by type, golden bytes, opt-outs, key placement | Unchanged WI-M2-10 tests (`PayloadGoldenTests`, `PayloadBuilderTests`), still green | Mac repeat of the golden bytes stays MS-2 B2 | not in scope here |

### Prior tickets
| # | Status in this round | Evidence |
|---|---|---|
| R28-F2 | **Closed** | Option (b): both properties run through `ModelRouter.events` and assert selector = oracle = sent, for both Q12 answers. The households include 365 blank names, 260 repeated names and 62 households with no room. A D11 test sends `""`, `"  "`, `"\t"`, `" \n "`, a repeated `Kitchen` and `Kids’ room` through the router for each provider. Review mutant M-C (the selector drops blank names) is killed (dev M9). My selector-only mutant RM4 is killed. |
| R28-F6 (WI-M2-11 part) | **Closed** | (b) compares concrete-index leaves and the byte frame. The negative test asserts the `[]` set is unchanged **and** the concrete check fires, for an extra message, an extra part and an extra enum element on all 3 providers. The Tester/PO question on `ds2-gated` element counts (AC-M2-26/28) is carried. It is not this PR's to close. |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R31-F1 | Minor | `Packages/TendIngestion/Tests/TendIngestionTests/PayloadSentinelSupport.swift:498-503`; dev-notes WI-M2-11 D5 | **The auth header value is the one byte region the property does not pin.** D5 says the value is compared "for holding the key", but line 501 only checks `isAuthorization`, which is the enum case `.key`. It does not look at the value. The prefix is a `String` from the provider table. My mutant **RM3** (`authValuePrefix: "Bearer "` → `"Bearer  "`) **survives the whole WI-M2-11 suite**. Only WI-M2-10's golden-bytes and key-placement tests catch it, on 3 households. The AC excepts the auth value from the golden comparison because real keys differ, but this harness uses the fixed `PayloadFixture.fakeKey`, and G1's head line holds exactly the expected value. Today the (a) sentinel scan does cover the auth value, so a household leak there would still be found. | Compare the auth header too: either `withValue { $0 } == golden.1` (same fake key), or `== authValuePrefix-from-the-allowed-list/golden + fakeKey`. Then (b) pins every byte of the request. Correct D5 to say what is checked. Add RM3 to the mutant table. | Open |
| R31-F2 | Minor | `PayloadSentinelSupport.swift:192-244, 256-274` | **The (a) scan matches raw bytes only, so an encoded leak can pass (a).** Forms it would miss: (1) JSON-escaped `\/`, so `Pacific\/Chatham` passes; (2) percent-encoding in the path or query (`%2F`); (3) a case change of the lower-case title token, or an ID in mixed case; (4) a coarser ISO form, such as date-only `yyyy-MM-dd` or minute precision. Titles that contain `\n` or `\t` would be escaped inside the body, so the full-title sentinel could not match them. The token still covers those titles. My mutant **RM2** (the pipeline appends the first room's `lastTendedAt` as date-only ISO to the capture) **passes (a)** and is killed by (b). This meets the AC as written: AC-M2-20 (a) names "ISO 8601" and byte-level matching. In this harness (b) is a complete backstop, because every byte except the auth value (F1) is pinned. Nothing leaks today. The gap matters if (a) is reused where (b) is weaker, for example WI-M2-M6 adapters or a request shape without a golden. | Either (i) add the cheap forms: a `\/` variant for sentinels that contain `/`, an upper-case token, and a date-only `yyyy-MM-dd` form for each date, after checking it does not collide with fixed content; or (ii) state in the test header and in dev-notes that (a) covers escaped, encoded and case-changed forms only through (b), and carry that sentence into the WI-M2-M6 ticket. Either is acceptable. | Open |
| R31-N1 | Nit | `PayloadSentinelSupport.swift:175`; dev-notes D4 | `String(describing: Calendar.Identifier)` gives the CLDR form on Linux (`islamic-civil`, `ethiopic`; checked in `swift:6.2-noble`). So the two `calendarNames` entries are the same and "the Swift case name as well" (D4) is not true on Linux. | Use literal case names (`"islamicCivil"`, `"ethiopicAmeteMihret"`, …) in the table, or drop the claim. | Open |
| R31-N2 | Nit | `PayloadSentinelSupport.swift:169` | `TimeZone(identifier:) ?? .gmt` falls back silently. On a platform without a zone, the time-zone sentinel becomes `GMT` and the case loses meaning without any failure. I verified all 10 zones resolve in `swift:6.2-noble`. | Make it a `precondition` or an `Issue.record`. | Open |
| R31-N3 | Nit | `PayloadSentinelSupport.swift:22` | `import Synchronization` is not used in this file. | Remove it. | Open |
| R31-N4 | Nit (for WI-M2-M6) | `PayloadSentinelSupport.swift:320` | The interval digit scan includes the auth header value. With a real key (WI-M2-M6, DS-2) a key that contains `650` would be a false positive. | When reusing for WI-M2-M6: decide with the PO whether "header values" in AC-M2-20 (a) includes the auth value. If it does, use a fake key. | Open (ticket WI-M2-M6) |

### My mutation check (scratch copy `/tmp/claude-0/rev31mut`, made with `tar --exclude=.git`; the worktree was not edited)
Each mutant was applied by a script that asserts the target occurs exactly once. Each run used `swift:6.2-noble`,
`-Xswiftc -warnings-as-errors` and `--filter PayloadSentinelTests`.

One incremental-build trap is worth recording for the Developer's mutant runs. Restoring a file with `mv` keeps the
original mtime, so SwiftPM did **not** rebuild it, and my first RM4 and RM5 runs still had RM1 compiled in. I re-ran
both after `touch`. The results below are from the clean re-runs.

| # | Mutant (production) | (a) | (b) | Other WI-M2-11 tests | Result |
|---|---|---|---|---|---|
| RM1 | `DuplicateShortlist` ranks the room match R ascending | killed | killed | golden control | killed |
| RM2 | `DraftPipeline` appends the first room's `lastTendedAt` as date-only ISO to the capture | **survives** | killed (1,794 issues) | — | killed (F2) |
| RM3 | OpenAI auth prefix `"Bearer  "` | survives | **survives** | — | **survives the suite**; killed by WI-M2-10 `golden bytes` and `key placement` (F1) |
| RM4 | `CloudContextSelector` trims room names (selector only) | n.a. | killed (selector = oracle) | D11, golden control | killed |
| RM5 | `DraftPipeline` appends 8 lower-case hex characters of the first room ID to the capture | killed (interval digits) | killed | D11 | killed |

### Developer's open questions
1. **`ds2-gated` per-array element counts (R28-F6, Tester/PO).** I agree it stays open with the Tester and PO. This PR
   closes the AC-M2-20 side. On device, AC-M2-26 still compares only `[]` path sets, so an extra element would not be
   seen there. My recommendation to the PO: record value-free element counts per array, since they carry no household
   content.
2. **`deferred(until:)` and task `roomID` as sentinels.** This is stronger than the AC and does not change its meaning.
   `deferred(until:)` is a household date field outside allowed content that the AC's list does not name. I recommend
   the PO add both to the AC-M2-20 (a) list in the next brief edit, so the coverage cannot be removed silently later.
   This does not block.

### Other checks
- **Determinism:** SplitMix64 (`DupRandom`) with a fixed seed. Sets are built by filtering `allCases`, and the
  dictionaries are used only for logging. Failure messages name the seed, household, Q12 answer and provider. The
  three providers see the same households, and my log counts match the dev-notes exactly.
- **Byte frame:** the frame is found at the first `"{\"capture\":` in the body. The golden control shows the fixed
  instructions do not contain it. A leak earlier in the body would change the prefix and fail anyway. `EvalJSONReader`
  rejects duplicate keys and floats, so the leaf maps cannot hide a duplicate.
- **Generator hygiene:** each capture asserts that no sentinel occurs in its allowed content. Without this, an absence
  check would prove nothing about leaks.
- **Field completeness:** I listed the TendCore model fields. `Household` has tasks, rooms and `schemaVersion` (a
  constant). `Room` has id, name and `lastTendedAt`. `HouseholdTask` has the 15 coding keys. Every field that can hold
  a unique value outside allowed content is a sentinel. Enum, Boolean and set fields are covered by (b).
- **Swift 6 concurrency:** one harness per parameterised case, so no shared state. The transport records under a
  `Mutex` (existing support code). There is no `@unchecked Sendable` and no `nonisolated(unsafe)` in the new files. The
  build has 0 warnings with `-warnings-as-errors`.
- **CI cost:** the TendIngestion suite ran in 159 s, and the new suite in about 90 s when filtered. Acceptable on Linux
  CI. It runs `Task.yield()` once per household.

### Test runs (this review, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, own scratch paths `/tmp/rev31-<pkg>`)
| Package | Result |
|---|---|
| TendIngestion | `✔ Test run with 449 tests in 52 suites passed after 159.416 seconds.` 0 warnings. AC-M2-09: `46 files in total, 0 violations`. AC-M2-12: `46 files, 9 exempted (the list), 0 violations`. The per-provider log lines for (a) and (b) match the dev-notes counts. |
| TendSourceScan | `✔ Test run with 63 tests in 4 suites passed after 4.522 seconds.` |
| TendCore | `✔ Test run with 141 tests in 18 suites passed after 130.833 seconds.` |

## Checklist
- [x] Correctness vs ACs (AC-M2-20 (a), (b), Q12 both answers, Q19/D11)  - [x] Tests meaningful (my 5 mutants; 4 killed by this suite, RM3 by WI-M2-10's tests, F1)  - [x] Swift 6 concurrency safe
- [x] No force unwraps / try! in product code paths (no product code changed)  - [x] Privacy (P-1…P-4)  - [x] UX-2/UX-3 enforced in engine (n.a.; AC-M2-12 scan clean)
- [x] Accessibility (UI) n.a.  - [x] Performance (CI cost acceptable)  - [x] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | n.a. | No copy or source change. The AC-M2-12 scan has 0 violations. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | Routing is unchanged. The harness reaches cloud only through the documented "on-device unavailable" route. |
| P-2 No data leaves device (except user iCloud) | pass | Test code only. The transport is a recording mock, and there is no networking. The AC-M2-09 scan has 0 violations. The key is a fake. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | This PR is the minimisation proof. Over 3,120 requests, no ID, date (four forms), interval, non-shortlisted title, `now`, time zone or calendar reaches any part of the request. Every byte except the auth value equals the golden, or is exactly the capture, the room names and ≤ 10 oracle titles. F1 and F2 tighten the proof but are not leaks. |
| P-4 Media not persisted without consent | pass | Text only, in memory. Nothing is written. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Reviewer | accepted | PR #31 at `bb006e8` (base `f1b6458`), detached worktree. Focus: AC-M2-20 (a)/(b) literally, R28-F2, R28-F6, oracle independence, encodings, controls, determinism, CI cost, open questions 1–2. |
| 2026-11-24 | Reviewer | Orchestrator → Merge Gatekeeper; Developer (F1, F2, N1–N3); Tester/PO (open question 1, N4); PO (open question 2) | sent: **APPROVE** (round 1) | 0 Blocker, 0 Major, 2 Minor, 4 Nit. R28-F2 and R28-F6 (WI-M2-11 part) closed. My 5 mutants: 4 killed by this suite, RM3 only by WI-M2-10 tests (F1). TendIngestion 449, TendSourceScan 63, TendCore 141 green, 0 warnings, Linux. The golden bytes repeat on the owner-run Mac stays MS-2 B2. |
