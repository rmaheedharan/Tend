# M2 Code Review — PR #45 (`m2/keychain-key-store`, WI-M2-M5, round 1 @ `ce9c060`, base `origin/main` `41bf8fa`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** WI-M2-M5 (MS-2), the Keychain key store, for **AC-M2-21** and the real-Keychain part of **AC-M2-18 (a)**
  (T-14, T-16; ADR-0005 Decision 5). The PR has 2 commits:
  - `7390586` is the code commit. It adds `TendAI/Cloud/KeychainAPIKeyStore.swift` (+105),
    `TendAI/Cloud/APIKeyMask.swift` (+19), `TendAI/Tests/TendAITests/APIKeyMaskTests.swift` (+25) and
    `TendAI/HostedTests/KeychainAPIKeyStoreHostedTests.swift` (+205).
  - `ce9c060` adds docs only: the `dev-notes.md` section and the Mac evidence record
    `docs/milestones/M2/evidence/mac/WI-M2-M5/`.
  - No `Package.swift`, `project.yml`, `Fixtures/` or protected path is touched.
- **Inputs read:**
  - `CLAUDE.md` and the `code-reviewer` skill.
  - `plan.md`: the WI-M2-M5 row (`:100`), the Developer constraints under M2 Q24 (`:180-186`, `:292-294`) and the
    AC → environment rows (`:765`, `:768`).
  - `brief.md`: AC-M2-18 (`:696`), AC-M2-21 (`:822`), T-14 and T-16 (`:1305`, `:1316`).
  - ADR-0005 Decision 5 (Keys).
  - The `APIKeyStore` / `APIKey` / `CloudStoreError` contract (`TendIngestion/Routing/CloudStores.swift`) and the
    `ModelRouter` callers (`turnCloudOff`, `removeKey`, the orphan-key sweep).
  - The full diff, the new dev-notes section, and the evidence README, logs and script.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`, so an `m2/` build item is allowed
  (CLAUDE.md §5). Its dependencies are on `main`: WI-M2-M1 (the hosted scaffold, `TendAIHostedTests`) and WI-M2-09
  (`ModelRouter`, `APIKeyStore`). The scanner allowlist on `main` already names
  `Packages/TendAI/Sources/TendAI/Cloud/KeychainAPIKeyStore.swift` (`IngestionSourceRulesTests.swift:14`).

## Summary
The store is small, correct and matches ADR-0005 Decision 5 and AC-M2-21:
- one generic-password item per provider;
- `kSecUseDataProtectionKeychain = true` and `kSecAttrSynchronizable = false` on every query (copy, update, add,
  delete), and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on add and on update;
- replace by updating in place, which never deletes the old key first;
- `hasKey` never asks for data;
- every status becomes a neutral, payload-free `CloudStoreError`.

The hosted tests read the written item back with `kSecReturnAttributes` through an independent probe (T-16), not by
checking the store's own query. They cover save, read, replace, delete (`errSecItemNotFound`), per-provider
isolation, exact text (empty, non-ASCII and 4,096 characters), turn-off, remove-key, the orphan key, and formatting.

The Mac evidence record names `7390586`, the hashes check, and the record is clean of personal data. Linux reruns are
green.

One surviving mutant (K2: `kSecAttrSynchronizable` set to "any" on the store's query) is real but needs a
precondition that Tend cannot create today. I raise it as **Minor m1**, with a test that would kill it. There is no
Blocker and no Major.

### 1. AC-M2-21 against code and tests
| AC-M2-21 clause | Code | Test (B5, iOS 26.5 Simulator host) | Real? |
|---|---|---|---|
| Generic password, data-protection keychain | `KeychainAPIKeyStore.swift:91-99` (`kSecClassGenericPassword`, `kSecUseDataProtectionKeychain: true`) | `expectAttributes` `:78-102`: the probe searches the generic-password class only and finds exactly 1 item; an internet-password search for the same account finds nothing; a search with `kSecUseDataProtectionKeychain` finds it | Yes. On iOS every item is in the data-protection keychain, so the last check is confirmation, not proof. That is acceptable, because the AC environment is the iOS Simulator. |
| `WhenUnlockedThisDeviceOnly`, read back | `:68`, `:77` (update **and** add) | `:90`, after save **and** after replace | Yes. K1 (`AfterFirstUnlock` on replace) was killed. Setting it on update also fixes an item written with any other accessibility. |
| Not synchronizable, read back | `:97` on the query, which is also the add dictionary | `:91`, the probe uses `kSecAttrSynchronizableAny` and `kSecMatchLimitAll` and expects exactly one item (`:25`) | Yes for the written item: K2b (added as synchronizable) was killed. See m1 for the lookup side. |
| Read back after save returns the same key | `:44-61` | `lifecycle` `:61`, `exactText` `:116-124` (5 cases) | Yes |
| Replace | `:63-83`: `SecItemUpdate` first, `SecItemAdd` only on `errSecItemNotFound` | `lifecycle` `:64-66` | Yes. A failed update throws and leaves the old item untouched. A cross-process race on add gives `errSecDuplicateItem` → `storeUnavailable`, which is safe and loses no key. |
| Delete → `errSecItemNotFound` | `:85-88`. Not-found counts as done. | `:68-73`: the probe lookup (`any` sync, all matches) gives `errSecItemNotFound`; a second delete is not an error | Yes. K3 (delete does nothing) was killed. |
| Masked form | `APIKeyMask.swift:119-123`: `count >= 12` gives `••••` + `suffix(4)` in `Character`s, otherwise `••••` | `APIKeyMaskTests` with 0, 3, 11, 12, 26 and 18 (non-ASCII and emoji) characters, plus "never more than the last four" | Yes. The 11/12 boundary is pinned. K4 and K5 were killed. Save rejects nothing (`exactText`), as the AC says. |
| Never in `UserDefaults`, files, logs, descriptions or errors | No `UserDefaults`, file or log API in either file. `CloudStoreError` has no payload. `APIKey` redacts `description`, `debugDescription` and `customMirror` (on `main`). | `formatting` `:167-188`: `describing`, `reflecting`, interpolation, `dump`, `Mirror` of the key read back, the store, every `CloudStoreError`, and the mask. The AC-M2-09 scan covers logs and files. | Yes. `APIKey` is the only key-holding value type in this PR: the store keeps only `service`, and the router holds `APIKey?` only as a local (`ModelRouter.swift:247`). My scan mutants below confirm the scan side. |

**`hasKey` never reads data** (`:32-42`): the query sets `kSecReturnAttributes` and `kSecMatchLimitOne` and passes a
`nil` result pointer. There is no `kSecReturnData`. I checked this by reading the code. Asking for attributes with a
`nil` result is harmless.

### 2. AC-M2-18 (a) with the real Keychain
- `turnOffDeletes` (`:126-140`): `turnCloudOn(.openAI, …)` writes the item, and the probe sees it. After
  `turnCloudOff()`, the probe gives `errSecItemNotFound` for **all three** providers and the status is `.off`.
- `removeKeyDeletes` (`:142-153`) and `orphanDeleted` (`:155-165`, T-14 (i)) prove the same through the real store.
- These go through `ModelRouter` (`:188-218`, `:293-294`), so they test the real integration, not the store alone.

### 3. The surviving mutant K2 (`kSecAttrSynchronizable` widened to "any" in `itemQuery`)
The Developer recorded it honestly. My analysis follows.
- **Why it survives:** with `false` (or the attribute left out) a search matches only items that are not
  synchronizable. With "any" it matches both kinds. The tests never create a synchronizable item under the store's
  service, so both versions behave the same in every test.
- **What it would break if such an item existed:**
  - `hasKey` and `key(for:)` could return a key that lives in iCloud Keychain.
  - `SecItemUpdate` would **rewrite the synchronised item's data**, which would send the new key off the device
    through iCloud Keychain. That is against ADR-0005 Decision 5 ("not synced to iCloud Keychain") and P-3.
  - `SecItemDelete` would also delete it. That part is harmless.
- **The dev-notes wording is too narrow.** It says K2 "changes only which items a lookup may match". The update path
  matters more.
- **Severity: Minor, not Major.**
  - The AC-M2-21 property (the item Tend writes is not synchronizable, read back) is proven, and K2b kills the
    write-side regression.
  - The survivor needs a synchronizable `tend.ai.key` item to exist, and no Tend code path can create one. So the
    mutant is behaviour-equivalent in every state Tend can reach.
- **Is a test worth adding?** Yes. It is cheap, and it locks one line that guards a privacy law. K2b shows the
  Simulator accepts synchronizable items, so the test can be built. See m1.

### 4. Security import, neutral errors, Swift 6
- **Security import.** Run over the repo, `grep -rn "import Security" --include=*.swift` finds it in product source
  only at `KeychainAPIKeyStore.swift:18` (allowlist file 3, Rule 3). The other hits are the hosted test probe, which
  needs it and is outside the scanned `Sources`, and planted strings in scanner tests. The mask file imports only
  `Foundation` and `TendIngestion`.
- **Neutral errors (UX-3).** `errSecInteractionNotAllowed` maps to `notAccessibleNow` and everything else to
  `storeUnavailable` (`:102-104`). Undecodable data maps to `storeUnavailable` (`:52-54`). The case names describe the
  store, not the person, and contain no banned word.
- **Swift 6.**
  - `public actor` with one immutable `let service: String`.
  - The `[String: Any]` / `CFTypeRef?` values are locals and never cross an isolation boundary.
  - The synchronous `throws(CloudStoreError)` methods satisfy the `async throws(CloudStoreError)` protocol.
  - There is no `@unchecked Sendable`, no `nonisolated(unsafe)` and no `Task {}`.
  - The B4 and B5 logs show `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, with no compiler warning, only the 2 known
    `appintentsmetadataprocessor` notices.
  - The Keychain IPC runs on the actor's executor. It is short and never on the main actor.
- **No weakening.** The diff only adds lines (`git diff origin/main...HEAD | grep '^-[^-]'` is empty). No test is
  skipped: B4 and B5 have 0 skipped.

### 5. Mac evidence record and commit hygiene
- **Commit tested.** The record names `73905869b83714e310ed4cb4397dddc9d8301b6b` (README table and line 2 of
  `mac-B0-header.log`). B0 `git status --porcelain` is empty, and so is B9.
- **`ce9c060` is docs-only against `7390586`.** `git diff --name-only 7390586 ce9c060 | grep -v '^docs/'` prints
  nothing.
- **SHA-256.** I ran `shasum -a 256 -c` on the README's 16 lines: 16/16 OK.
- **Results match the logs.** B4 has 3 tests in 2 suites (the 2 new mask tests plus the scaffold test) and `TEST
  SUCCEEDED`. B5 has 9 tests in 2 suites (6 new plus 3 scaffold cases) and `TEST SUCCEEDED`. B2 scanned 59 files,
  including the 3 TendAI files, with 0 violations. B6 `find`s print nothing. `timings.txt` exit codes match the README.
  The environment header is the same as MS-1.
- **Personal data.** I grepped the whole diff for `/Users/`, `/home/`, `/private/var`, email domains, `hostname`,
  `localhost` and host-like names.
  - Paths appear only as the redaction tokens (`$HOME/.local/...`) or as system and Homebrew paths (`/Applications/
    Xcode.app/...`, `/opt/homebrew/...`).
  - The only machine identifiers are the model (`Macmini9,1`) and the OS build, as in MS-1.
  - There is no username, hostname or personal email.
- **Commit identity.** `git log --format='%ae %ce' origin/main..HEAD` gives `noreply@anthropic.com
  noreply@anthropic.com` for both commits.

### 6. What I ran (Linux container, `swift:6.2-noble`, `-Xswiftc -warnings-as-errors`)
| Command | Result |
|---|---|
| `swift test --scratch-path /tmp/rev45-TendCore --package-path Packages/TendCore` | `✔ Test run with 141 tests in 18 suites passed` |
| `… --package-path Packages/TendIngestion` | `✔ Test run with 571 tests in 67 suites passed`. This includes the real-tree AC-M2-09 scan over the new TendAI files. |
| `… --package-path Packages/TendSourceScan` | `✔ Test run with 63 tests in 4 suites passed` |
| `… --package-path Packages/TendTools` | Not run. The package does not exist at `ce9c060` (`Packages/` holds TendAI, TendCore, TendIngestion and TendSourceScan). |
| Scan mutant S1: `import Security` planted in `APIKeyMask.swift` (a copy of the tree, `--filter IngestionSourceScanTests`) | Killed: `APIKeyMask.swift:8: [Rule 2 import] import Security` |
| Scan mutant S2: `print(text)` planted in `KeychainAPIKeyStore.key(for:)` | Killed: `KeychainAPIKeyStore.swift:55: [Rule 3 log API print(]` |
| TendAI and the hosted Keychain tests | Not runnable on Linux. I rely on the owner's Mac record (B4, B5) at `7390586`. |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| m1 | Minor | `KeychainAPIKeyStore.swift:97`; `KeychainAPIKeyStoreHostedTests.swift` | Mutant K2 survives (`kSecAttrSynchronizable` set to "any" on the store's query). If a synchronizable `tend.ai.key` item ever existed, `hasKey` and `key` would match it, and `save`'s `SecItemUpdate` would rewrite it, so the key would sync through iCloud Keychain (ADR-0005 D5, P-3). Tend cannot create that state today (K2b is killed), so the mutant is behaviour-equivalent in every reachable state. The dev-notes text names only the lookup and omits the update path. | Recommended in this PR or as a follow-up before M2 closes. Add a hosted test that plants an item with the probe: same service and account, `kSecAttrSynchronizable: true`, data `"synced-sentinel"`. Then assert: (1) `hasKey == false` and `key == nil`; (2) after `save(longKey)`, the planted item's data is still `"synced-sentinel"` (read with `kSecAttrSynchronizable: true`, `kSecReturnData`) and a separate non-synchronizable item holds `longKey`; (3) `key(for:)` returns `longKey`. The probe's `attributes` helper expects exactly 1 item, so the test needs its own count. Fix the dev-notes K2 sentence. | Open |
| n1 | Nit | `dev-notes.md` WI-M2-M5 header | It still says "PR: none yet". The PR is #45. | Update when convenient. | Open |
| n2 | Nit | `KeychainAPIKeyStore.swift:52-54` | The "item data is not UTF-8 → `storeUnavailable`" branch has no test. It needs a planted item. | Optional: cover it with the same probe as in m1. | Open |
| i1 | Info | `KeychainAPIKeyStoreHostedTests.swift:192-194` | Merge-order hazard, which the Developer flagged. If `m2/on-device-adapter-v2` (`model()` → `model(household:)`) merges first, `UnavailableOnDevice` stops compiling. The hosted target is built only on the owner's Mac, not by Linux CI, so CI would stay green while B5 breaks. | Whichever of the two PRs merges second must rebase, apply the one-line rename and rerun B5 on the Mac before AC-M2-21 is accepted. | — |
| i2 | Info | — | `docs/product/TRACEABILITY.md` has no AC-M2-21 / AC-M2-18 (a) → hosted test rows yet. | Documenter: add the rows (the 6 hosted tests and the 2 mask tests). | — |
| i3 | Info | — | This review is a merge decision only. AC-M2-21 and AC-M2-18 (a) need the Acceptance Tester to record the Mac B5 evidence. | Acceptance Tester. | — |

## Checklist
- [x] **Correctness vs ACs.** Every AC-M2-21 clause and AC-M2-18 (a) maps to code and a hosted test (§1, §2).
  Replace never loses the old key. Delete leaves `errSecItemNotFound`.
- [x] **Tests meaningful (would fail if code broke).**
  - Attributes are read back through an independent probe (T-16).
  - Developer mutants K1, K2b, K3, K4 and K5 were killed.
  - My scan mutants S1 and S2 were killed.
  - K2 survives and is explained (m1).
- [x] **Swift 6 concurrency safe.** An actor with immutable state, locals only, no unsafe escapes. Warnings are errors
  and the build is clean.
- [x] **No force unwraps / `try!` in product code paths.** There are none in either source file.
- [x] **Privacy (P-1…P-4).** Keychain only, this device only, not synchronised, deleted on turn-off, remove-key and
  orphan. No log, file or `UserDefaults` use. No key in any formatted value or error.
- [x] **UX-2/UX-3 enforced in engine.** UX-2 n.a. UX-3: the error cases are neutral and no banned word appears.
- [x] **Accessibility (UI).** n.a.: no UI. The mask is a display string for M3.
- [x] **Performance.** Single Keychain calls, off the main actor.
- [x] **No new dependency without ADR.** `Security` is an Apple framework that ADR-0005 D5 and Rule 3 name.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. Pasting a key is the M3 Settings flow (ADR-0005 D5). |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | `CloudStoreError.notAccessibleNow` and `.storeUnavailable` describe the store. There is no user copy and no banned word in the diff. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference path. |
| P-2 No data leaves device (except user iCloud) | pass | No networking in either file. The scan passed over 3 TendAI files and S1 was killed. The key is not synchronised to iCloud Keychain (read back). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass (watch m1) | Matches ADR-0005 D5: generic password, `WhenUnlockedThisDeviceOnly`, not synced, masked, deleted on turn-off and remove-key (real Keychain), and orphan deletion (T-14). m1 hardens the "not synced" property against a future regression. |
| P-4 Media not persisted without consent | pass | No media. Nothing is persisted outside the one Keychain item. Hosted tests use their own service and clean up. |

## Verdict
**APPROVE.** There is no open Blocker or Major.
- m1 (Minor) is recommended: a planted-synchronizable-item test that kills K2, and a corrected dev-notes sentence. It
  is not a merge condition.
- n1 and n2 are optional.
- i1 must be handled by whichever PR merges second.

This is a merge decision on PR #45 only. It does not accept AC-M2-21 or AC-M2-18 (a).

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-27 | Orchestrator | Reviewer | accepted | Review PR #45 at `ce9c060` (WI-M2-M5; AC-M2-21, AC-M2-18 (a)). |
| 2026-11-27 | Reviewer | Orchestrator → Merge Gatekeeper, Developer, Acceptance Tester, Documenter | sent | APPROVE. Linux: TendCore 141, TendIngestion 571, TendSourceScan 63, all passed (TendTools absent). Evidence: 16/16 hashes OK, names `7390586`, `ce9c060` docs-only, no personal data, neutral emails. Scan mutants S1 and S2 killed. Developer: m1 test for K2 (recommended), n1. Tester: record B5 for AC-M2-21 and AC-M2-18 (a) (i3). Documenter: traceability (i2). Merge order with `m2/on-device-adapter-v2` (i1). |
