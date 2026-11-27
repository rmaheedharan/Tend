# M2 Code Review — PR #47 (`m2/key-paste-cleanup`, PO ruling R28-F5 + PR #45 / #46 follow-ups, round 1 @ `f1e5374`, base `c60b335`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** `git diff c60b335 f1e5374`, two commits. `d447eb4` has the code and tests (13 files under `Packages/`).
  `f1e5374` is docs only (`git diff --name-only d447eb4 f1e5374` lists nothing outside `docs/`): the Mac evidence record
  `evidence/mac/key-paste-cleanup/` and the dev-notes section. The base `c60b335` merges PR #45 (`m2/keychain-key-store`)
  into PR #46 (`m2/cloud-transport`). Both were reviewed APPROVE in `review-pr45.md` and `review-pr46.md`.
  Requirements: **AC-M2-21**, **AC-M2-22** (Headers amendment), **AC-M2-23**, **AC-M2-09 / AC-M2-21** key-leak scan,
  **AC-M2-18** (through the router). No protected path is touched.
- **Inputs read:** `CLAUDE.md`; the `code-reviewer` skill; the PO ruling of 2026-11-27 on R28-F5 (option (c): 6 rules,
  copy, AC amendments, 11 required tests and mutants); `review-pr45.md` (m1 K2, n1, n2); `review-pr46.md` (m1, m2, n1,
  n2, i2); the full product and test diff; `ModelRouter.turnCloudOn`; `CloudHTTPTransport.urlRequest`; the dev-notes
  section; the evidence README, the logs and `run-evidence.sh`.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. An `m2/` work item is allowed (CLAUDE.md §5).
  No M3 work is included: the refuse copy and its screen are left to M3, as the ruling says.

## Summary

The ruling is implemented as written. A new pure-Foundation type, `TendIngestion/Routing/APIKeyText.swift`, does the
work:
- It trims, at both ends only, every Unicode `White_Space` scalar, every `Cc` scalar, and U+200B, U+200C, U+200D,
  U+2060 and U+FEFF. That is the ruled set exactly. Line breaks (LF, CR, U+0085, U+2028, U+2029) and NBSP are all
  `White_Space`.
- It then accepts the key only if the result is non-empty and every scalar is in U+0021...U+007E. There is no length or
  prefix rule.

`KeychainAPIKeyStore.save`, `InMemoryAPIKeyStore.save` and `ModelRouter.turnCloudOn` all apply the rule before they
write anything. A refused key throws one payload-free case, `CloudStoreError.keyTextNotAccepted`. `APIKeyMask` masks
the trimmed key. As defence in depth, the transport refuses an auth header whose key is empty or outside the range. It
does this before any `URLSession` exists, via `CloudRequestHeader.keyIsSendable`.

All five open review asks from PR #45 and PR #46 are closed, with tests that would fail if the code were wrong.

I re-ran the three Linux packages: all green, no warnings. I also ran 11 mutants of my own on Linux, and all 11 were
killed. The Mac record is complete and hashes clean.

I found no Blocker and no Major. There is one Minor: transport test 10 leaves out the ruled `\n` and `\r` auth-key
cases. Two Nits and three Info items follow. None is a merge condition.

### 1. The 11 tests and mutants the ruling requires

| # | Ruling item | Where | Meaningful? |
|---|---|---|---|
| 1 | Trimmed cases read back trimmed | Linux `APIKeyTextTests.trimmed`: 11 cases, covering every ruled case plus U+200C/U+200D/U+2060, NUL/DEL and a mixed case. Linux `inMemoryStore`. Mac `KeyPasteCleanupHostedTests.storedTrimmed`: 5 cases, and it reads the raw Keychain item bytes, not just the store's read-back. | Yes. My mutants A (no trim), B (no invisibles), C (no Cc) and J (leading trim only) were all killed. |
| 2 | Mask is computed from the trimmed key | Mac `storedTrimmed` (`masked(raw) == dots + "WXYZ"`). macOS `APIKeyMaskTests` row `"\n sk-…WXYZ \u{200B}"`. | Yes |
| 3 | Interior characters are refused | Linux `refused`: all 7 ruled cases. Mac `refusedKeepsEarlier`: space, LF, `é`, NUL. | Yes. Mutants G (accept space) and H (accept DEL) killed. |
| 4 | Empty after trim is refused | Linux: `""`, `"   "`, `"\r\n\t"`, `"\u{FEFF}\u{200B}"`, `"\u{00A0}"`. Mac: `"   "`, `""`. | Yes. The exact `"\n\u{FEFF}"` string is not present, but the same classes are covered (n2). |
| 5 | A refused save keeps the earlier key. With no earlier key, lookup is not found. | Linux `inMemoryStore` (`hasKey == false`). Mac `refusedKeepsEarlier`: the earlier item is kept byte for byte, and `errSecItemNotFound` is returned for a provider with no earlier key. | Yes. Mutants E and E2 (in-memory store skips the rule) killed. |
| 6 | Boundaries: every character U+0021...U+007E is kept | Linux `printableASCII`. Mac `acceptedKeys`. The string starts with `!` and ends with `~`. | Yes |
| 7 | A short key is saved | `"a"`, on Linux and on Mac | Yes |
| 8 | The neutral result never formats the input (sentinel) | Linux `refusalNeutral`: `description`, `String(reflecting:)`, interpolation and `dump` checked for no sentinel, no `é`, no digit (so no position). `localizedDescription` is checked for no sentinel. Mac `refusalFormatting`. The AC-M2-21 hosted `formatting` test (`KeychainAPIKeyStoreHostedTests.swift:184`) formats `CloudStoreError.allCases`, which now includes the new case. | Yes (see n1 for the Mac test's fallback) |
| 9 | Property test with a fixed seed | `paddingProperty`: SplitMix64 with seed `0x5EED_F5`, 2,000 keys, 24 junk scalars including U+0085, U+1680, U+3000, ESC. On my Linux run it printed "0 mismatches". | Yes. Seeded, so the run can be repeated. Mutant C kills it. |
| 10 | Transport: an auth value with `\n`, `\r`, a space or non-ASCII is refused, with 0 requests | Mac `badAuthKeyNotSent`: 3 providers × `"sk bad"`, `"clé"`, `"sk\u{200B}x"`, `""`. It expects `requestNotSent`, no chunks, and an empty `StubBook`. The no-retry half for `requestNotSent` is already on Linux (`CloudDeadlineRetryTests.swift:143`). | Yes for space and non-ASCII. `\n` and `\r` are missing (m1). |
| 11 | Mutants: no trim, and no transport check | Developer, Mac: P1, P1b, P2, P3, K2 killed (dev-notes). Reviewer, Linux, see §4: A (no trim) and F (`keyIsSendable` always true) killed. | Yes |

### 2. The two changed expectations (are they weakened?)
- **Keychain `exactText` (`KeychainAPIKeyStoreHostedTests.swift:116-119`).** Before: "any length and any characters",
  with arguments `""`, `"a"`, `"short-key"`, a Cyrillic/emoji key, and 4,096 × `x`. After: "any length in
  U+0021...U+007E", with arguments `"a"`, `"short-key"`, `"sk-ant-api03-…"`, and 4,096 × `x`.
  - Only the two inputs that rules 2 and 4 now refuse were removed: the empty key and the non-ASCII key.
  - Neither input lost its test. Both moved to refusal tests (`refusedKeepsEarlier` has `""` and `clé-1` on Mac;
    Linux has both classes), which assert the opposite outcome.
  - The length coverage (4,096) and the "no length or prefix check" claim stay.
  - **Verdict: exactly the ruling, not a weakening.**
- **Mask row `("ключ-ключ-ключ-🔑ab", "••••-🔑ab")` changed to `"••••"` (`APIKeyMaskTests.swift:13`).** The ruling says
  only that the mask is computed from the trimmed key. It does not say what a key the store would refuse shows.
  - The Developer chose dots only. A refused key is never stored, so it can never be shown as a saved key.
  - The new output reveals strictly less than the old one (no last-4 of a non-key), so it cannot leak more (P-3).
  - The ≥12 → last-4 behaviour is still tested by the three ASCII rows and the new padded row.
  - **Verdict: follows the ruling, and the extra behaviour is the conservative choice. Not a weakening.** It is
    recorded as i1 so that the PO knows about it.

### 3. Checks the Orchestrator asked for
- **Trim set exactly as ruled:** yes (§Summary). Nothing extra is trimmed. For example, U+00AD, U+180E and U+FE0F at an
  edge are refused, not trimmed, which is the ruled behaviour. Interior characters are never removed: `cleaned` takes
  the slice `first...last` unchanged, so the stored text is exactly what the user pasted (P-3).
- **Neutral refusal:** `keyTextNotAccepted` has no associated value. `CloudStoreError` is a plain enum with no custom
  description. The sentinel tests pass on Linux and on Mac. The `calmNames` banned-token test includes the new case,
  and the case count changed from 2 to 3, which is a correct, stricter update.
- **A refused save keeps the earlier key (both stores):** both `save`s `guard` before building any query or mutating
  any state (`KeychainAPIKeyStore.swift:65`, `CloudStores.swift:80`). Tested on Linux and on Mac.
- **`turnCloudOn` refuses before recording consent:** `ModelRouter.swift:166` comes before `nextActionNumber()` and
  `recordConsent`, and there is no `await` before it. Without the guard, the rollback path would *clear* an earlier
  consent for the same provider. `routerRefusal` asserts `cloudStatus() == .on(.openAI)` after a refused re-key, and my
  mutant D (guard removed) was killed by that assertion. So the test proves "earlier consent kept", not only "no new
  consent".
- **Mask from the trimmed key:** yes (§1 #2).
- **Transport auth-value check:** `CloudHTTPTransport.swift:63` runs inside the synchronous `urlRequest` builder. On
  nil, `send` finishes with `requestNotSent` before `URLSession(configuration:)` is created. The stub sees 0 requests
  (test 10). It checks the key, not the full header value, so OpenAI's `Bearer ` prefix (a space) is correctly allowed.
  The existing CR/LF/NUL check stays.
- **AC-M2-09 key-leak scan:**
  - The B2 log lists `Routing/APIKeyText.swift`, `Routing/CloudStores.swift` and `Payload/CloudRequest.swift` as
    scanned: 62 files, 0 violations.
  - The new type is covered by the formatting tests, as listed in §1 #8.
  - `APIKeyText` logs nothing and keeps no state.
- **Swift 6 concurrency:** `APIKeyText` is a stateless enum whose only stored property is a `static let Set<UInt32>`
  (Sendable). The stores are still actors. `InMemoryAPIKeyStore.save` now `throws(CloudStoreError)`, and its only
  production caller (`ModelRouter.swift:172`) already uses `try await`. There is no `@unchecked Sendable` and no
  `nonisolated(unsafe)`. The build is clean with `-warnings-as-errors` on Linux and on Mac.
- **P-3:** only the user's exact key characters, minus edge noise, are stored and sent. There is no new header, host or
  field, and no new dependency.

### 4. Reviewer reproduction (Linux, Docker `swift:6.2-noble`, `-warnings-as-errors`, head `f1e5374`)

| Package | Result |
|---|---|
| TendCore | 141 tests in 18 suites passed, exit 0, 0 warnings |
| TendIngestion | 579 tests in 68 suites passed, exit 0, 0 warnings. "R28-F5 property: seed 0x5EED_F5, 2000 keys, 0 mismatches". |
| TendSourceScan | 63 tests in 4 suites passed, exit 0, 0 warnings |

**Reviewer mutants.** Each mutant was run in a throwaway `git archive` copy, not in the worktree. Filter
`APIKeyTextTests|CloudStoreTests|CloudConsent`; the baseline is 45 tests in 5 suites. All 11 were killed:
- A: no edge trim
- B: empty invisible set
- C: no `Cc` in the trim set
- D: router guard removed
- E: in-memory store stores the raw key
- E2: in-memory store skips the rule
- F: `keyIsSendable` always true
- G: accept range starts at U+0020
- H: accept range ends at U+007F
- I: `isSendable` accepts empty
- J: trim leading edge only

The transport-side mutant (the `urlRequest` guard removed) can only run on the Mac. The Developer records it as P2,
killed. Mutant F kills the predicate that guard uses on Linux.

### 5. Mac evidence `evidence/mac/key-paste-cleanup/`
- It names `d447eb49ecb6299e4b9b10eea84f6b3a45756281`. B0 prints that hash with an empty `git status --porcelain`,
  and B9 is empty after the run. `f1e5374` is docs only (verified).
- `sha256sum -c` on the 16 README lines gives 16/16 OK.
- There is no username, hostname or home path. Paths use `$REPO` and `$HOME` tokens, and the only `@` hits are test
  argument strings (`user@api.openai.com`, `@preconcurrency`). The machine is identified only by its model
  (`Macmini9,1`).
- Both commits have author and committer `Claude <noreply@anthropic.com>` (neutral).
- The results match the dev-notes:
  - B1: 141 tests.
  - B2: 579 tests; AC-M2-09 scan 62 files, 0 violations.
  - B4: 3 tests.
  - B5: 34 tests in 4 suites, `TEST SUCCEEDED`. Every new hosted test is listed as passed, including
    `badAuthKeyNotSent` (3 cases), K2, non-UTF-8, the URLError rows (18) and the −3000...0 sweep.
  - B6: same as MS-1 (TendEval archive exit 66 is expected).
- The toolchain matches the earlier MS-2 records.

### 6. PR #45 and PR #46 follow-ups

| Ask | Status | Evidence |
|---|---|---|
| PR #45 **m1** (K2 survivor) | **Closed** | `synchronizableItemIgnored` plants a `kSecAttrSynchronizable: true` item holding a sentinel and asserts: `hasKey == false`, `key == nil`; after `save`, the planted item still holds the sentinel and a separate non-synchronizable item holds the key; `deleteKey` leaves the planted item. This is every assertion review-pr45 asked for, plus the delete path. The dev-notes K2 sentence now names the update path. Passed in B5. |
| PR #45 **n1** (PR number) | Closed | dev-notes WI-M2-M5 header: "PR: #45" |
| PR #45 **n2** (not-UTF-8 branch) | **Closed** | `notUTF8` plants `FF FE 00 C3` and expects `storeUnavailable`, with `hasKey == true`. Passed in B5. |
| PR #46 **m1** (exact header values) | **Closed** | `headers` now asserts, for each builder header, `sent.value(forHTTPHeaderField:) == header.withValue { $0 }`, so the auth value is checked byte for byte. |
| PR #46 **m2** (7 codes, nil only for cancelled) | **Closed** | The 7 rows were added (18 cases in B5). `onlyCancelledIsNil` sweeps −3000...0 and expects `[-999]`. |
| PR #46 **n1** (final-remainder wording) | Closed | The comment at `CloudHTTPTransport.swift:17-18` and the test title are reworded as asked. |
| PR #46 **n2** (backtick, PR number) | Closed | dev-notes WI-M2-M4 header fixed, "PR: #46" |
| PR #46 **i2** (R28-F5 rule 6) | Closed | §3, transport check, and §1 #10 |

## Findings

| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| m1 | Minor | `Packages/TendAI/HostedTests/CloudHTTPTransportHostedTests.swift:427` | Ruling test 10 names `\n`, `\r`, a space and non-ASCII. The loop covers space, non-ASCII, U+200B and empty, but not `\n` or `\r` in the **auth key**. `lineBreakHeader` uses an `X-Extra` text header, not the key. Those two cases go down the same `keyIsSendable` path, and the CR/LF/NUL guard is a second layer, so no behaviour is unproven. But the PO's list is not followed literally. | Add `"sk\nbad"` and `"sk\rbad"` to the loop at `:427`. Next Mac run. Not a merge condition. | Open |
| n1 | Nit | `Packages/TendAI/HostedTests/KeyPasteCleanupHostedTests.swift:131` | `let error = thrown ?? .storeUnavailable` with no `#expect(thrown == .keyTextNotAccepted)`. If the save ever succeeded, the formatting checks would run on `storeUnavailable` and pass without testing anything. The Linux twin (`APIKeyTextTests.swift:108-109`) has the expect, and `refusedKeepsEarlier` covers the throw on Mac. | Add `#expect(thrown == .keyTextNotAccepted)`. | Open |
| n2 | Nit | `Packages/TendIngestion/Tests/TendIngestionTests/APIKeyTextTests.swift` `refusedCases` | The ruled test-4 string `"\n\u{FEFF}"` is not present verbatim. It is covered by class (`"\r\n\t"`, `"\u{FEFF}\u{200B}"`). | Optional: add it verbatim for literal traceability. | Open |
| i1 | Info (PO) | `Packages/TendAI/Sources/TendAI/Cloud/APIKeyMask.swift:14-19`; `APIKeyMaskTests.swift:13` | The mask of a key the store would refuse is now `••••` only. The ruling does not address this case. The choice is conservative (it shows less), and I judge it within the ruling (§2). | PO: confirm, or say otherwise, when the AC-M2-21 amendment is written. No code change. | — |
| i2 | Info | — | The brief amendments to AC-M2-21 and AC-M2-22, the DECISIONS.md line for R28-F5, and the M3 refuse-copy AC belong to the PO's docs PR and governance PR, not to this PR. | PO / Orchestrator. | — |
| i3 | Info | — | `docs/product/TRACEABILITY.md` has no rows yet for the new Linux and hosted tests (AC-M2-21, AC-M2-22, AC-M2-23). The Acceptance Tester still has to record B5 for AC-M2-21 / AC-M2-22 / AC-M2-23 (Mac halves). | Documenter, Acceptance Tester. | — |

## Checklist
- [x] **Correctness vs ACs.** AC-M2-21 (trim, refuse, keep earlier, mask, no length or prefix rule), the AC-M2-22
  Headers amendment, and AC-M2-23 (`requestNotSent`, no retry) are all built as ruled.
- [x] **Tests meaningful.** All 11 ruled items are present (one partly, m1). 11 of 11 Reviewer mutants were killed.
  The two changed expectations follow the ruling and are not weakened (§2).
- [x] **Swift 6 concurrency safe.** A stateless pure type and unchanged actors. No unsafe escapes. Warnings are errors.
- [x] **No force unwraps / `try!` in product code paths.** The only `!` unwraps (`Unicode.Scalar($0)!` over 0x21...0x7E)
  are in tests.
- [x] **Privacy (P-1…P-4).** See the Law check.
- [x] **UX-2/UX-3 enforced in engine.** UX-2 does not apply. UX-3: the neutral case name passes the banned-token test.
- [x] **Accessibility (UI).** Not applicable: there is no UI, and the copy is M3.
- [x] **Performance.** Applies to one key-sized string per save or per request. No hot loop.
- [x] **No new dependency without ADR.** Foundation and Security only.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Still one secure field (M3). Silent trimming removes the most common re-paste. |
| UX-2 Rule of Three | n.a. | No "what to do" surface touched. |
| UX-3 Zero-Guilt | pass | One payload-free neutral case, `keyTextNotAccepted`, which passes the banned-token scan. No user copy ships in M2. |
| UX-4 Design craft | n.a. | M3 owns the field, its motion and haptics. |
| P-1 On-device inference | pass | Routing is unchanged. The router only refuses earlier. |
| P-2 No data leaves device (except user iCloud) | pass | No new host, header or dependency. The Keychain item is still this-device-only and not synchronised, and K2 is now killed. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | Only the user's exact key characters are stored and sent; no interior repair. A non-plain key never reaches a header (transport check, 0 requests). No consent is recorded for a refused key. |
| P-4 Media not persisted without consent | pass | Refused input is not written or logged. The sentinel tests prove that the result holds no key text. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | PR #47 round 1, head `f1e5374`, diff from `c60b335`. |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper, Developer, PO, Acceptance Tester, Documenter | sent | **APPROVE.** Linux: TendCore 141, TendIngestion 579, TendSourceScan 63, all passed with 0 warnings. 11/11 Reviewer mutants killed. Mac record: 16/16 hashes OK; names `d447eb4`; `f1e5374` docs only; no personal data; neutral emails. PR #45 m1/n1/n2 and PR #46 m1/m2/n1/n2/i2 closed. Developer: m1 (add `\n`, `\r` to transport test 10), n1, n2, all optional. PO: i1 (mask of a refused key), i2 (brief amendments, DECISIONS line). Documenter and Tester: i3. |
