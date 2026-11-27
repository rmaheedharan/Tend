# M2 Code Review — PR #46 (`m2/cloud-transport`, WI-M2-M4, round 1 @ `c98536e`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** WI-M2-M4, the cloud HTTPS transport and its failure mapping (**AC-M2-22**, **AC-M2-23**, Mac halves;
  ADR-0005 Decisions 6 and 7; `CloudTransport` contract points 1-5). Three commits: `d406a7d` (code and hosted tests),
  `1854d54` (two `URLError` codes named by raw value for AC-M2-12), `c98536e` (Mac evidence record and dev-notes, docs
  only). Diff: 21 files, +9,798 / −0. Product code: `Packages/TendAI/Sources/TendAI/Cloud/CloudHTTPTransport.swift`
  (+179) and `CloudFailureMapping.swift` (+59), both on the AC-M2-09 cloud-adapter allowlist. Tests:
  `Packages/TendAI/HostedTests/CloudHTTPTransportHostedTests.swift` (+400, 17 tests). No protected path is touched.
- **Inputs read:** `CLAUDE.md`; the `code-reviewer` skill; `plan.md` WI-M2-M4 row and the Developer constraints
  (M2 Q24/Q23); `brief.md` AC-M2-22 and AC-M2-23; ADR-0005 Decisions 4-8; `CloudTransport.swift`, `CloudRequest.swift`,
  `CloudProviderTable.swift`, `CloudTiming.swift`, `CloudResponseBody.swift` (WI-M2-14, unchanged); the dev-notes
  WI-M2-M4 section; the evidence record `evidence/mac/WI-M2-M4/`; the PO ruling of 2026-11-27 on R28-F5 (key
  whitespace and control characters, option (c)).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. An `m2/` work item is allowed (CLAUDE.md §5).

## Summary

The transport is small and does what AC-M2-22 and AC-M2-23 ask. Each attempt gets its own ephemeral session with no
cookie, cache or credential store. The URL is built only from `URLComponents` with the scheme fixed to `https`, and
the request host must equal the ADR-0005 host for its provider. Every refusal (another host, a non-HTTPS form, a CR,
LF or NUL in a header name or value) happens in the synchronous stream builder, before any `URLSession` exists. The
redirect delegate returns nil, so no redirect is followed. Statuses and `URLError`s map to the WI-M2-14 neutral
reasons through total switches. `Retry-After` is passed on only for 429 and 5xx. There is no retry in the transport,
and cancellation is never a failure. Product code has no `@unchecked Sendable` and no `nonisolated(unsafe)`. The
hosted tests are real: each one checks what the `URLProtocol` stub actually received. The 9 Developer mutants map to
assertions that would fail. I found no Blocker and no Major. Two Minor test gaps (m1, m2) and three Nits are optional.
The auth-value U+0021...U+007E check from the PO's R28-F5 ruling (rule 6) is not implemented yet. It is queued and
tracked as follow-up i2, not as a new finding.

### 1. AC-M2-22: configuration, host lock, refusals before sending
- **Ephemeral, no stores** (`CloudHTTPTransport.swift:40-52`): `.ephemeral`, `httpCookieStorage = nil`,
  `httpShouldSetCookies = false`, `.never`, `urlCache = nil`, `urlCredentialStorage = nil`,
  `.reloadIgnoringLocalAndRemoteCacheData`, `waitsForConnectivity = false`. `URLRequest.httpShouldHandleCookies =
  false` (`:75`) is also set. Tested by `configuration()` (every property, plus `httpAdditionalHeaders == nil`) and by
  `noCookies()` (a `Set-Cookie` on attempt 1 is not sent on attempt 2; T6 mutant killed).
- **One session per attempt** also means a connection is never reused across attempts. So CFNetwork cannot silently
  replay the POST on a stale keep-alive connection, which keeps "never retried" true below the API level as well.
- **Routed host only** (`:60-71`): `request.host` must equal `routedHostName(provider)` (from
  `CloudProviderTable.hosts`), and the built URL must again be `https` to that host. The test `otherHost` covers 4
  hosts, including another provider's host and a suffix trick, with 0 requests at the stub. `notHTTPS` covers 3 forms
  that would change the scheme or authority (`http://…`, `:80`, `user@…`), with 0 requests and `urlRequest == nil`.
  The scheme is a literal, so a non-HTTPS URL cannot be built at all. The second guard is defence in depth.
- **Before any session or request:** `urlRequest(_:timeouts:)` runs inside the `AsyncThrowingStream` build closure,
  which runs synchronously, before `URLSession(configuration:)` (`:98-104`). A refusal finishes the stream with
  `requestNotSent` there. A stream built in an already-cancelled task finishes empty and sends nothing
  (`createdCancelled`).
- **Header injection** (`:76-83`, `:88-90`): CR, LF or NUL in a header name or value causes a refusal. Tested with
  `"a\r\nCookie: x"` (T8 killed). The PO ruling's wider auth-value rule is i2.
- **Redirects** (`:166-172`): `RedirectRefuser` answers every redirect with nil, and the 3xx becomes the final
  response. A `Location` that names another host (absolute or scheme-relative) gives `requestNotSent`. Anything else
  gives `unexpectedResponse`. Both tests are real. If the delegate is removed, the stub sees a second request (to
  `evil.example.com`, or to the same host in a loop), and `sent.count == 1` fails (T2 killed). The stub delivers the
  redirect the way the HTTP loader does when the delegate declines it.
- **Exact headers** (`:76-83`): every builder header is set with `setValue`, and nothing else is set. The builder ends
  with `User-Agent: Tend` and `Accept-Language: en-US`. The `headers` test checks both values for 3 providers and
  checks that every header the stub sees is either a builder header or one of the transport-set headers (T3 killed).
  It does not check that each builder header is present with its exact value (m1).
- **Timeouts (WI-M2-14):** `timeoutIntervalForResource = timeouts.resource` and `timeoutIntervalForRequest =
  timeouts.request` come from `CloudTiming.timeouts(timeLeft:)`. `CloudResponseBody` sends only when `left > .zero`,
  so the transport never gets a zero or negative interval. `URLRequest.timeoutInterval` is the same request value.
  `silentTimesOut` (1.0 s, ended in 1.001 s in B5) and `silentBodyTimesOut` would fail under the default 60 s / 7 days
  (T5 killed).

### 2. Body chunking (R29-N2)
Bytes are collected and passed on when the chunk ends with a blank line (`\n\n` or `\n\r\n`) or reaches 4 KiB
(`:120-128`, `:153-158`). `endsEvent` needs at least 2 bytes, so a cut at an event end or at the 4 KiB limit can never
yield a 1-byte chunk. The only possible 1-byte chunk is the final remainder of a body (n1). The `body` test uses 300
events plus 9,000 bytes split across two stub deliveries and checks order, the 4 KiB bound and no 1-byte chunk.

### 3. AC-M2-23: status and `URLError` mapping, `Retry-After`, no retry, cancellation
- **Status** (`CloudFailureMapping.swift:44-52`) is total. 2xx gives nil (the body is read), 401/403 give
  `keyNotAccepted`, 429 gives `rateLimited`, 500-599 give `serviceUnavailable`, and everything else, including 1xx and
  any 3xx the delegate did not handle, gives `unexpectedResponse`. 12 statuses go through the session with `Retry-After:
  7`. The raw `"7"` comes back only where `allowsRetry`, and the stub sees exactly 1 request each (T4, T9 killed).
- **`URLError`** (`:28-41`) is a switch over a struct with `default → unexpectedResponse`, so every code maps to a
  neutral `CloudFailureReason`. Only `.cancelled` maps to nil. 11 codes go through the session, and the table test
  covers the same codes directly (m2 lists the gap).
- **Raw-value naming (`1854d54`):** `-1_006` and `-1_200` are correct. The hosted `mappingTable` test checks them
  against Foundation's `.dnsLookupFailed` and `.secureConnectionFailed` on iOS. I checked the same equality on Linux
  `FoundationNetworking` (both `true`; `cannotFindHost` is -1003 and `cancelled` is -999). HostedTests are outside the
  AC-M2-12 scan roots (`ScanScope.roots` lists `Sources` only), so the Foundation names there are allowed. **Mutant
  (mine):** putting `.dnsLookupFailed` back into `CloudFailureMapping.swift:33` makes the AC-M2-12 vocabulary scan
  fail with `[token:failed] dnsLookupFailed`. So the rename is needed and the scan guards it.
- **Cancellation (contract points 4 and 5):** `onTermination` cancels the inner task and calls
  `invalidateAndCancel()`. `URLError.cancelled`, `CancellationError` and any error after a cancel all finish the
  stream with no error. `cancelMidBody` shows that the transport ends without a `CloudTransportFailure` and that
  `CloudResponseBody` ends with `CancellationError` (T7 killed). `onTermination` also runs on every normal or failed
  finish, so each session is released after every attempt.
- **Other errors:** a response that is not HTTP, or any other error that is not a cancellation, gives
  `unexpectedResponse`.

### 4. R28-F4: could the OS add its own `User-Agent` or `Accept-Language`? (assessment requested)
My assessment is that the risk is low and that this PR's evidence cannot close it. Apple's URL Loading System adds
`User-Agent`, `Accept-Language`, `Accept` and `Accept-Encoding` only when the request does not already have them. A
value set with `setValue(_:forHTTPHeaderField:)` is kept. Neither header is on Apple's reserved list (`Authorization`,
`Connection`, `Host`, `Content-Length`, `Proxy-Authenticate`, `Proxy-Authorization`, `WWW-Authenticate`). The session
has no `httpAdditionalHeaders`, which `configuration()` proves. So the wire should carry `User-Agent: Tend` and
`Accept-Language: en-US`. It should also carry the transport-set names already allowed by AC-M2-22
(`CloudAllowedKeyPaths.transportSetHeaders`: `Content-Length`, `Host`, `Accept`, `Accept-Encoding`, `Connection`).
Two residual points can only be shown on the wire:
- whether the HTTP/2 or HTTP/3 stack adds any header that is not on that list (for example `Priority`);
- whether `Authorization` (OpenAI's auth header, which is on the reserved list) is sent unchanged. It normally is
  when the session does not handle the challenge itself.

The `URLProtocol` stub sees the request above that layer, as the dev-notes honestly say. See i1 for the check I
recommend.

### 5. Swift 6 concurrency
- Product code: `CloudHTTPTransport` is a `Sendable` struct whose only stored property is a `@Sendable` closure.
  `RedirectRefuser` is a `final` `NSObject` subclass with no stored properties and *checked* `Sendable`, which is
  allowed for a direct `NSObject` subclass. The inner `Task` captures only `Sendable` values (`continuation`,
  `URLSession`, `URLRequest`, `String`). The `adjust` hook runs synchronously on a configuration that is local to the
  call, and it is `internal` (tests only; no source calls `init(adjust:)`). There is no `@unchecked Sendable` and no
  `nonisolated(unsafe)`.
- The unstructured `Task {}` does not inherit cancellation. That is correct here, because the stream's
  `onTermination` carries cancellation to it, and the build-time `Task.isCancelled` check covers a stream created in a
  cancelled task.
- Tests: `StubBook` and `StubProtocol` are `@unchecked Sendable`. Each has a justifying comment, `StubBook` is guarded
  by `NSLock`, and both are test-only. This is acceptable.
- B4/B5 build with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and the logs have no compiler warnings (the only `warning:`
  lines are the known `appintentsmetadataprocessor` notices).

### 6. Evidence record (`docs/milestones/M2/evidence/mac/WI-M2-M4/`)
- The record names `1854d549c3fb89b9378a23ea83857550f142ccd3` as the commit tested (README table, B0 line 2). `git
  status --porcelain` is empty before (B0) and after (B9) the run.
- `git diff --name-only 1854d54 c98536e` lists only files under `docs/` (18 files). So `c98536e` is docs only, and the
  code under review is exactly the code that was run.
- `sha256sum -c` on the README's 16 lines: all 16 `OK`.
- `run-evidence.sh` matches the MS-1 script except for the stated `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the 4 B6
  builds.
- No local home path, username or hostname appears anywhere in the diff. Paths use `$REPO` (2,270), `$HOME` (1,532),
  `$USER` (3), `$TMPDIR` (2) and `$SCRATCH` (1). There is no `/Users/<name>`, `/var/folders` or `*.local` host, and no
  `<name>-Mac…` string. The DerivedData folder suffixes are Xcode path hashes, as in MS-1. The hardware model
  (`Macmini9,1`) is not personal.
- Commit author and committer emails are `noreply@anthropic.com` on all 3 commits.
- B5: `✔ Test run with 19 tests in 2 suites passed`, `** TEST SUCCEEDED **`, all 17 new tests listed and 0 skipped.
  B2: 571 passed, and the AC-M2-09 scan read both new files (TendAI 3 files, 0 violations).

### 7. What I ran (Linux, Docker `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`, at `c98536e`)
| Command | Result |
|---|---|
| `swift test --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed` |
| `swift test --package-path Packages/TendIngestion` | `✔ Test run with 571 tests in 67 suites passed` (includes the AC-M2-09 and AC-M2-12 scans over the new TendAI files) |
| `swift test --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed` |
| `swift test --package-path Tools/TendTools` (the package is under `Tools/`, not `Packages/`) | `✔ Test run with 11 tests in 1 suite passed` |
| Foundation raw values, `swiftc` on Linux | `-1006 -1200 true true -1003 -999` |
| Scan mutants on a copy of the tree (`git archive` into scratch): `.dnsLookupFailed` restored in `CloudFailureMapping.swift:33`, and the bare host `"api.example.com"` added to `CloudHTTPTransport.swift` | 2/2 killed: AC-M2-12 `[token:failed] dnsLookupFailed`, AC-M2-09 `[Rule 4 host-like literal not allowed]` |

The hosted transport tests need the iOS Simulator. I could not run them on Linux. For them I rely on the owner-run Mac
record (B5) and on reading the assertions.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| m1 | Minor | `CloudHTTPTransportHostedTests.swift:187-203` | The `headers` test checks `User-Agent`, `Accept-Language` and "no header outside the allowed names". It never checks that each builder header (auth, `anthropic-version`, `Content-Type`, …) reaches the stub with its exact value. A mutant that skips `setValue` for the auth or provider headers would pass every test in this PR. That cannot leak data (P-3 is about extra data, which is tested), and WI-M2-M6's real recordings would catch it. | Optional: for each `header` in `request.headers`, assert `fields[header.name] == header.withValue { $0 }`. Then the auth value is proven byte for byte (it also prepares PO R28-F5 test 10). | Open |
| m2 | Minor | `CloudHTTPTransportHostedTests.swift:282-309`; `CloudFailureMapping.swift:28-41` | 7 codes in the switch have no test row: `internationalRoamingOff`, `callIsActive`, `serverCertificateHasUnknownRoot`, `serverCertificateNotYetValid`, `clientCertificateRejected`, `clientCertificateRequired`, `appTransportSecurityRequiresSecureConnection`. No test checks that `.cancelled` is the *only* code mapping to nil. A mutant that adds another code to the nil case would turn a real failure into a silent empty end, and it would survive. Every AC-M2-23 category does have at least one test. | Optional: add the 7 rows. Add one sweep, for example raw values −3000…0, asserting that `reason(for:)` is non-nil for every code except −999. | Open |
| n1 | Nit | `CloudHTTPTransport.swift:15-16`, `:127`; test title `:160` | The final remainder of a body can still be 1 byte (for example a body of 4,097 bytes, or `"…\n\nX"`). The claim "no chunk is a single byte" is true for every cut, but not for the last piece. | Reword it to "no cut makes a single-byte chunk; only the final remainder can be shorter". | Open |
| n2 | Nit | `dev-notes.md` WI-M2-M4 header | The backtick after the commit hash is not closed, so the parenthesis and `d406a7d` render as code. "PR: none yet" should now be PR #46. | Fix in the next docs touch. | Open |
| n3 | Nit (PO taste) | `CloudFailureMapping.swift:40` | `.cannotConnectToHost` (−1004) maps to `unexpectedResponse`. It is neutral and allowed by "any other transport error", but on a captive or partial network `offline` might describe it better. | Optional. PO decides; no AC change needed. | Open |
| i1 | Info (R28-F4) | — | §4: the explicit `User-Agent` and `Accept-Language` should win on the wire, but a stub cannot prove it, and HTTP/2 or HTTP/3 extra headers and the reserved `Authorization` are unverified at wire level. | Acceptance Tester and owner: during the WI-M2-M6 real recordings or DS-2, capture one request per provider with Instruments' **HTTP Traffic** instrument (it shows the app's own `URLSession` headers before TLS). Record that the header set is the builder's plus the transport-set names only. Until then, R28-F4 stays open as "wire check pending", not closed. | — |
| i2 | Info (tracked follow-up, not a new finding) | `CloudHTTPTransport.swift:76-90` | PO ruling 2026-11-27 (R28-F5, rule 6; AC-M2-22 Headers amendment) has three parts: the transport also refuses an auth value with any character outside U+0021...U+007E; transport test 10; mutant 11. Only the CR, LF, NUL refusal exists today. This is known and queued. | Developer: add it in the queued WI-M2-M4/M5 follow-up with the PO's test 10, and kill mutant 11. Reviewer will verify it in that PR. | Tracked |
| i3 | Info | `CloudHTTPTransport.swift:133-139` | Contract point 5 means a `URLError.cancelled` that Tend did not cause (rare) ends the stream normally with no bytes. That follows the contract. What the cloud adapter does with an empty normal end belongs to WI-M2-M6. Likewise, a real 401 should arrive as a 401 response (no credential store, default challenge handling) and not as −1012. | WI-M2-M6: include one real wrong-key recording per provider, and an empty-body case, and check that each ends calmly (`keyNotAccepted` / neutral). | — |

## Checklist
- [x] Correctness vs ACs: AC-M2-22 (ephemeral, no cookies or cache, HTTPS to the routed host only, refusals before
  sending, redirects not followed, explicit `User-Agent` and `Accept-Language`, per-attempt timeouts) and AC-M2-23
  (each status and `URLError` to a neutral reason, `Retry-After` only for 429/5xx, no retry, a separate
  `requestNotSent`) each have code and a hosted test. Wire-level headers: i1.
- [x] Tests meaningful: each test checks what the stub received or how the stream ended. The 9 Developer mutants map
  to assertions that would fail. 2/2 of my scan mutants were killed. Gaps m1 and m2 are Minor.
- [x] No weakening: the diff is additions only (0 removed lines). No test was skipped, made conditional or loosened.
- [x] Swift 6 concurrency safe: no `@unchecked Sendable` or `nonisolated(unsafe)` in product code. The delegate is
  checked-`Sendable` and stateless. Cancellation reaches the inner task through `onTermination`.
- [x] No force unwraps or `try!` in product code paths.
- [x] Privacy (P-1…P-4): see the Law check.
- [x] UX-2/UX-3 enforced in engine: no new reason or outcome name. The existing names are neutral and pass the
  AC-M2-12 scan.
- [x] Accessibility (UI): not applicable.
- [x] Performance: per-byte loop over `AsyncBytes`, with one reserved 4 KiB buffer reused. Off the main actor. Fine
  for SSE bodies.
- [x] No new dependency without ADR: Foundation only.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | Reasons name the situation (`keyNotAccepted`, `requestNotSent`, …), never the person. The banned token in two Foundation names is kept out of Sources by naming them by raw value (scan-guarded; mutant killed). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | pass | The transport is only reached on the opt-in `cloud` route (router, WI-M2-09). No routine inference path changed. |
| P-2 No data leaves device (except user iCloud) | pass | Networking only in the allowlisted files (AC-M2-09 scan 0 violations; Rule 4 mutant killed). Three fixed ADR-0005 hosts. No SDK. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Only the builder's headers and body are sent. No cookie, cache or credential store. No redirect is followed, so nothing goes to another host. The key is only in its header. The auth-value character rule is a tracked follow-up (i2). Wire-level header check is pending (i1). |
| P-4 Media not persisted without consent | pass | Body bytes live in memory for one attempt. Nothing is logged or written. The ephemeral session keeps nothing on disk. |

## Verdict
**APPROVE.** No open Blocker or Major. m1 and m2 are Minor test gaps, and n1-n3 are Nits. None blocks a merge. i1
(R28-F4 wire check) and i2 (PO R28-F5 auth-value rule, queued) stay tracked for WI-M2-M6 and the follow-up PR. This
is a merge decision on PR #46 only. It does not accept AC-M2-22 or AC-M2-23. The Acceptance Tester records those with
the Linux halves (WI-M2-06, WI-M2-14) and this Mac B5 record.

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Review PR #46 at `c98536e` (WI-M2-M4; AC-M2-22, AC-M2-23); evidence at `1854d54`; PO R28-F5 ruling as context. |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper, Developer, Acceptance Tester, PO | sent | APPROVE. Linux: TendCore 141, TendIngestion 571, TendSourceScan 63, TendTools 11, all passed, warnings as errors. Evidence hashes 16/16 OK, `c98536e` docs only, no personal paths, neutral emails. 2/2 scan mutants killed. Optional: m1, m2, n1-n3. Developer: i2 (R28-F5 transport rule) in the queued follow-up. Tester and owner: i1 (Instruments HTTP Traffic capture during WI-M2-M6/DS-2), i3. PO: n3 (optional). |
