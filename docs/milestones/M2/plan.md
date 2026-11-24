# M2 Work Plan — On-Device AI Ingestion

- **Owner:** Work Planner  ·  **Brief:** [brief.md](brief.md) (Draft v4, Tester testability review ticked 2026-11-21 at
  `580d23e`, recorded at `29e2d74`)  ·  **Design:** M2 has no product UI. One small Designer naming item is needed
  (WI-M2-02, see "Design need")  ·  **Status:** Draft. WI-M2-01 is Ready now. Every other item becomes Ready when its
  dependencies and the conditions in its DoR row are met.
- **PO decisions applied (2026-11-21):** P1–P7 acknowledged, with a change to P3 (T10, E15, E16); T11 "next week" is 7
  calendar days; the Q18 model list is approved with five conditions (see WI-M2-10); HM-2 has a recommended rule
  (proposed D-032, see HM-2). Source: the PO's saved decisions of 2026-11-21.
- **PO decisions M2 Q23 and Q24 applied (2026-11-21, stricter only, from the PR #15 review):** the fixtures loader
  row in "Named files", the Developer constraint and the timing notes in WI-M2-01 (AC-M2-09).
- **Requirements:** FR-A1 (pipeline only), UX-2, UX-3, P-1, P-2, P-3, P-4 (as rewritten by D-030), ADR-0005, CLAUDE.md
  §3; carried M1 tickets D-016, W2-F3, W3-F6 (and the W3-F1 Darwin rerun). ACs: **AC-M2-01…28**.
- **Milestone lock:** `STATUS.md` shows **M1 `ACCEPTED`** (2026-11-20), so M2 build work is unlocked (CLAUDE.md §5).
  `STATUS.md` still reads "PLANNING … awaiting Tester testability review". The PO should set M2 to `IN-BUILD` before
  WI-M2-01 merges. This is a protected path (owner merge), and a bookkeeping step, not a DoR failure.
- **Environments** (brief Definitions, binding):
  - **Linux:** `swift test` in this container (Swift 6.2.x) and in Linux CI (`swift:6.2-noble`).
  - **Owner-run Mac:** the owner's MacBook Air M4 or Mac mini M1 with Xcode 26. The owner runs it, or an agent drives it
    through Remote Control. Every run produces the evidence record in "Owner-run Mac evidence record" below. A Mac run
    is never evidence for a device AC.
  - **Device:** the owner's iPhone 15 Pro (DS-1) and iPhone 13 (DS-2). These criteria stay `AWAITING-DEVICE` until the
    owner's run is recorded.

## Module and file layout (binding for the scans; settles the brief's deferred file paths)

The brief fixes the module names (`TendIngestion`, `TendAI`, `TendEval`). This plan fixes where they live. WI-M2-01
records the layout in **ADR-0006 (M2 module layout)**. Moving a file named below needs a plan update and the Tester's
note, because AC-M2-09 scans these paths.

| Path | What | Builds on |
|---|---|---|
| `Packages/TendCore/` | M1 engine, unchanged apart from WI-M2-02 (one invariant case) | Linux + Mac |
| `Packages/TendSourceScan/` | Test-only SwiftPM library: the Swift lexer (moved from the M1 test support, see WI-M2-01) and the AC-M2-09 rule engine. Foundation only. Never linked into an app target. | Linux + Mac |
| `Packages/TendIngestion/Sources/TendIngestion/` | The platform-neutral layer (brief Definitions). Imports `Foundation` and `TendCore` only. **Scanned by Rule 1.** | Linux + Mac |
| `Packages/TendIngestion/Tests/TendIngestionTests/` | All Linux tests for M2, including the AC-M2-09 scan over the three module roots and the AC-M2-28 `project.yml` scan | Linux + Mac |
| `Packages/TendAI/Sources/TendAI/` | Apple-framework adapters. Apple-only (not built on Linux). **Scanned by Rules 2, 3 and 5.** | Owner-run Mac |
| `Packages/TendAI/Tests/TendAITests/` | macOS `xcodebuild test` of mocks and adapters | Owner-run Mac |
| `Packages/TendAI/HostedTests/` | Tests that need an iOS host app (Keychain, AC-M2-21; `URLProtocol` transport, AC-M2-22) | Owner-run Mac (Simulator) |
| `Apps/Tend/` | A build skeleton of the shipped app target with no product UI. It exists only so that AC-M2-28 can prove the Release and Archive products hold no `TendEval`. It is never distributed in M2. | Owner-run Mac |
| `Apps/TendAITestHost/` | A blank, never-shipped iOS host app for `HostedTests` | Owner-run Mac |
| `Apps/TendEval/Sources/` | The debug-only eval harness (AC-M2-28). **Scanned by Rule 6.** | Owner-run Mac |
| `Tools/TendTools/` | A separate SwiftPM package with two executables, `tend-eval-score` and `tend-payload-dump`. It sits **outside** `TendIngestion/Sources`, so it may read files and print (brief Rule 1, T-26). | Linux + Mac |
| `Fixtures/M2/eval/` | The frozen eval: `inputs.json`, `household.json`, `golden.json`, `results-v1.schema.json`, `MANIFEST.sha256` (WI-M2-16). Bundled into `TendEval` at build time. | — |
| `Fixtures/M2/payload/` | Golden requests (3 households × 3 providers) and the per-provider allowed key-path lists (WI-M2-10) | — |
| `Fixtures/M2/provider-streams/` | Synthetic and recorded provider stream fixtures (WI-M2-12, 13, M6) | — |
| `project.yml` (repo root) | XcodeGen spec (ADR-0003, settled in WI-M2-M1). The generated `Tend.xcodeproj` is git-ignored. **Agents never hand-edit `.pbxproj`;** every project change is a `project.yml` diff. | Owner-run Mac |

**Named files (the brief's "before Definition of Ready" list):**

| Brief item | File path(s) | Rule |
|---|---|---|
| Cloud-adapter allowlist (closed list of 3 files) | `Packages/TendAI/Sources/TendAI/Cloud/CloudHTTPTransport.swift` (ephemeral `URLSession`, redirect refusal through `URLSessionTaskDelegate`, `bytes(for:delegate:)`, URL built with `URLComponents` from the builder's bare host and path)<br>`Packages/TendAI/Sources/TendAI/Cloud/CloudFailureMapping.swift` (`URLError` and `HTTPURLResponse` status to the neutral failure reason)<br>`Packages/TendAI/Sources/TendAI/Cloud/KeychainAPIKeyStore.swift` (the only file that imports `Security`) | AC-M2-09 Rule 3; Rule 4 (`https://` literals only here) |
| Provider adapters (not allowlisted, no `URL*` types) | `Packages/TendAI/Sources/TendAI/Cloud/CloudIngestionModel.swift` and one file per provider, `OpenAIIngestionModel.swift`, `AnthropicIngestionModel.swift`, `GeminiIngestionModel.swift`. They use only the neutral transport protocol and the `TendIngestion` parsers. | Rule 2 |
| Speech adapter files (the only `TendAI` files where media types may appear) | `Packages/TendAI/Sources/TendAI/Speech/SpeechTranscriptionAdapter.swift` (`SpeechAnalyzer` with `SpeechTranscriber`, falling back to `DictationTranscriber`)<br>`Packages/TendAI/Sources/TendAI/Speech/MicrophoneAudioSource.swift` (`AVAudioEngine` tap to `AnalyzerInput`, in memory only) | Rule 2, Rule 5 |
| Speech-permission file | `Packages/TendAI/Sources/TendAI/Speech/SpeechPermission.swift`. The Rule 5 exception (`SFSpeechRecognizer.requestAuthorization(`, `SFSpeechRecognizer.authorizationStatus(`, `SFSpeechRecognizerAuthorizationStatus`) applies here **only if** the T-27 check in WI-M2-M1 confirms that iOS 26 needs it. Until WI-M2-M1 records the result, the scanner runs with **no exception**. | Rule 5 |
| Results writer (the only `TendEval` file with write APIs) | `Apps/TendEval/Sources/Results/EvalResultsWriter.swift`. It writes only `EvalResultsFileV1` (the results-file type, defined in `TendIngestion` next to the scorer) as canonical JSON to the harness's Documents directory. | Rule 6 |
| Fixtures loader (the only TendEval file allowed `Data(contentsOf:`, bundle resources named by string literals only; M2 Q23) | `Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift` | Rule 6 |
| Harness transport wrapper (N-2) | `Apps/TendEval/Sources/Run/RecordingTransport.swift`. It wraps the neutral `CloudTransport` protocol (plain request value in, byte-chunk stream out) and records only the byte count and key paths. It uses no `URL*` type. | Rule 6 |
| Scoring tool | `Tools/TendTools/Sources/tend-eval-score/` (see "Scoring tool and command") | Outside Rule 1 |
| Payload builder provider table (the only file where the three bare hosts may appear; review R1-F6, named by WI-M2-10) | `Packages/TendIngestion/Sources/TendIngestion/Payload/CloudProviderTable.swift` | AC-M2-09 Rule 4 (`IngestionScanConfiguration.providerTableFile`) |

## Work items

Every AC has exactly **one owning item (●)**. Items marked ○ deliver a part of an AC that the owner item completes.
An AC that crosses the Linux/Mac line is owned by the item that completes its evidence. "Where verified" is where the
item's own tests must pass before it merges.

Sizes: S ≤ half a day, M ≤ 1 day. No item is L. WI-M2-11, 13 and M6 are at the upper bound (R-23).

### Phase A — Linux-provable (this container + Linux CI)

| ID | Title | ACs (● own, ○ part) | Size | Depends on | Design? | Owner | Branch | Where verified | DoR |
|---|---|---|---|---|---|---|---|---|---|
| WI-M2-01 | `TendIngestion` and `TendSourceScan` packages, ADR-0006, text primitives (name folding, keywords, stop words, banned-token matcher), canonical JSON writer, the AC-M2-09 scanner (Rules 1–6) with negative tests | ● AC-M2-09 | M | — (merge needs HM-1) | no | Developer | `m2/ingestion-foundation` | Linux | ☑ **Ready** |
| WI-M2-02 | `TendCore`: one new `TaskInvariantViolation` case for a non-finite `windowStart`/`windowEnd`; both M1 repositories reject such a file with a typed error (W2-F3, Q9) | ○ AC-M2-02 | S | Designer names the case | **yes** (naming only) | Developer | `m2/nonfinite-date-invariant` | Linux | ☐ Designer name |
| WI-M2-03 | `TimeHint` and the Q6 time resolver (the full table below) | ● AC-M2-03 | M | WI-M2-01 | no | Developer | `m2/time-resolver` | Linux | ☑ Tester review of the Q6 table done (APPROVED 2026-11-21, 3 non-blocking findings applied: E17–E21 and the T9/T14 daypart rule); PO acknowledged P1–P7 on 2026-11-21, with the P3 change |
| WI-M2-04 | Calm-words guard (AC-M2-12), room linking with name folding (AC-M2-04), `sourcePhrase` substring check | ● AC-M2-04, ● AC-M2-12 | M | WI-M2-01 | no | Developer | `m2/calm-words-and-rooms` | Linux | ☐ WI-M2-01 merged |
| WI-M2-05 | Neutral model contract (`IngestionModel`, item snapshots, `IngestionDraft`), the Q5 repairs in order, mapping to `HouseholdTask`, ≥ 1,000-output property test against an independent Q5 oracle with counts per repair rule | ● AC-M2-01, ● AC-M2-02 | M | WI-M2-02, 03, 04 | no | Developer | `m2/draft-mapping` | Linux | ☐ deps merged |
| WI-M2-06 | Draft stream assembly over neutral snapshots: item completion, `emitted` / `updated` / `itemSkipped` / `finished`, the four outcomes with route, cancellation, `noModel` for each neutral reason, the plain-note draft | ○ AC-M2-05, ○ AC-M2-10, ○ AC-M2-23 | M | WI-M2-05 | no | Developer | `m2/draft-stream` | Linux | ☐ deps merged |
| WI-M2-07 | Duplicate rules: the deterministic shortlist, the neutral duplicate-lookup function that the `Tool` will wrap, in-input collapse, the cloud re-check (Q12 yes) and the local word-match (Q12 no), ≥ 500-household oracle | ○ AC-M2-07, ○ AC-M2-08 | M | WI-M2-01, 05 | no | Developer | `m2/duplicate-rules` | Linux | ☐ deps merged |
| WI-M2-08 | `commit(confirmed:)`: injected ID generator with collision skip (W3-F6), proposed-room creation with fold de-duplication, `ofExisting` re-check at commit, contract over both M1 repositories, ≥ 500-household property with planted duplicates (exact, synonym, in-input; cloud drafts under Q12 yes and no) | ● AC-M2-06, ● AC-M2-08 | M | WI-M2-06, 07 | no | Developer | `m2/commit` | Linux | ☐ deps merged |
| WI-M2-09 | Routing and consent: `Route`, neutral availability reasons, preference, consent-store and `APIKeyStore` protocols with in-memory implementations, orphan-key deletion, the full route matrix below, turn-off semantics (cancel in flight, no new request) through a neutral mock transport, restored-state fixtures (i)–(iii) | ● AC-M2-19, ○ AC-M2-18, ○ AC-M2-10 | M | WI-M2-06 | no | Developer | `m2/routing-and-consent` | Linux | ☐ deps merged |
| WI-M2-10 | Context selector and payload builder for the three providers: provider table with bare hosts, canonical JSON body, header list, key placement, opt-outs, sampling, curated model IDs (Q18), the builder input type (`String`, `[String]`, `[String]`) with its `Mirror` test, recording mock transport, the 3 × 3 golden requests and the per-provider allowed key-path lists with roles (N-3) | ○ AC-M2-20 | M | WI-M2-07 | no | Developer | `m2/payload-builder` | Linux | ☐ deps merged; owner answers Q12/Q16/Q17 or the PO confirms the defaults stand. (Q18 list approved by the PO 2026-11-21, with the five Q18 conditions.) |
| WI-M2-11 | Payload proof: ≥ 500-household byte-level unique sentinels (AC-M2-20(a), four date forms, interval sentinels 600…729) and the structural key-path and value check (AC-M2-20(b)) for each provider | ● AC-M2-20 | M | WI-M2-10 | no | Developer | `m2/payload-sentinels` | Linux (golden bytes repeated on the Mac in MS-2) | ☐ deps merged |
| WI-M2-12 | Server-sent-event framing and an incremental JSON reader that turns a growing JSON text into neutral item snapshots (field order, split chunks, truncation, invalid JSON, unknown enum values, non-integer numbers to `nil`) | ○ AC-M2-24 | M | WI-M2-06 | no | Developer | `m2/stream-json-snapshots` | Linux | ☐ deps merged |
| WI-M2-13 | The three provider stream dialects (OpenAI, Anthropic, Gemini) on top of WI-M2-12, with synthetic fixtures for happy paths, out-of-order and split chunks, truncation, invalid JSON, schema-violating fields, unknown enums and a refusal; refusal before a draft → `noModel`, truncation after one → `interrupted` | ○ AC-M2-24 | M | WI-M2-12 | no | Developer | `m2/provider-dialects` | Linux | ☐ deps merged |
| WI-M2-14 | Cloud deadline and retry: the neutral `CloudTransport` protocol (N-2), per-attempt timeouts from the 10.0 s deadline on an injected clock, the single 429/5xx retry rule with `Retry-After` delta-seconds, neutral failure reasons to outcomes and the plain-note offer, no background queue | ○ AC-M2-22, ○ AC-M2-23 | M | WI-M2-06, 10 | no | Developer | `m2/cloud-deadline-retry` | Linux | ☐ deps merged |
| WI-M2-15 | Eval scorer: `EvalResultsFileV1`, `results-v1.schema.json` and a Foundation-only conformance check, the scorer exactly to the eval scoring rules, self-tests with hand-built results files (false merge, duplicate created, proposed-room match, tie in matching, every rule), `EvalIDGenerator`, the `Tools/TendTools` package with `tend-eval-score` and `tend-payload-dump` | ○ AC-M2-14 | M | WI-M2-01, 05 | no | Developer | `m2/eval-scorer` | Linux | ☐ deps merged |
| WI-M2-16 | Eval fixtures and freeze: the 20 inputs, seeded household with fixed version-4 UUIDs and match groups, golden set (written by the **Tester**); PO approval of the composition; the composition check on the real fixtures and `MANIFEST.sha256` (Developer); the Tester's independent re-score of one self-test file; the freeze, with the golden requests and key-path lists from WI-M2-10 | ● AC-M2-14 | M | WI-M2-15, 11 | no | Acceptance Tester (fixtures) + Developer (check) | `m2/eval-fixtures-freeze` | Linux + Tester review | ☐ deps merged; Tester fixtures; PO composition approval |

### Phase B — Owner-run Mac (grouped into three sessions)

| ID | Title | ACs (● own, ○ part) | Size | Depends on | Design? | Owner | Branch | Where verified | DoR |
|---|---|---|---|---|---|---|---|---|---|
| WI-M2-M1 | **First Mac item (MS-1).** Settle ADR-0003 (XcodeGen, pinned version and checksum, moved to `Accepted`); `project.yml` with `Tend` (skeleton), `TendEval` (Debug shell), `TendAITestHost` and `TendAIHostedTests`; `.gitignore` for the generated project; the `TendAI` package scaffold; the **T-27 check**; confirm the exact `xcodebuild` commands below; an information-only FoundationModels latency probe | ○ AC-M2-09 (Rule 5 decision), ○ AC-M2-13, ○ AC-M2-28 | M | WI-M2-01 | no | Developer (on the owner's Mac) | `m2/xcodegen-project` | Owner-run Mac | ☐ WI-M2-01 merged; MS-1 booked with the owner |
| WI-M2-M2 | On-device adapter (MS-2): `@Generable`/`@Guide` schema, instructions, prewarm, `streamResponse` `PartiallyGenerated` to neutral snapshots, exhaustive mapping (no `default`) of every `SystemLanguageModel.Availability` case, `supportsLocale` and every `LanguageModelSession.GenerationError` case, the duplicate `Tool` returning exactly the shortlist's entries and fields | ● AC-M2-05, ● AC-M2-07, ● AC-M2-10 | M | WI-M2-M1, 06, 07, 09 | no | Developer | `m2/on-device-adapter` | Owner-run Mac (macOS `xcodebuild test`) | ☐ deps merged |
| WI-M2-M3 | Speech adapter (MS-2): `SpeechAnalyzer` + `SpeechTranscriber`, falling back to `DictationTranscriber`; the transcriber used is reported; the speech-permission file per T-27; tests over a protocol with a fake audio source | ○ AC-M2-09, ○ AC-M2-11, ○ AC-M2-25 | M | WI-M2-M1 | no | Developer | `m2/speech-adapter` | Owner-run Mac | ☐ WI-M2-M1 merged |
| WI-M2-M4 | Cloud transport and failure mapping (MS-2): allowlist files 1 and 2; ephemeral configuration, no cookies, no URL cache; HTTPS and routed-host-only; redirect to another host refused before sending; timeouts from WI-M2-14; each `URLError` and HTTP status to a neutral reason; `URLProtocol` mock tests in the Simulator host | ● AC-M2-22, ● AC-M2-23 | M | WI-M2-M1, 10, 14 | no | Developer | `m2/cloud-transport` | Owner-run Mac (Simulator host) | ☐ deps merged |
| WI-M2-M5 | Keychain key store (MS-2): allowlist file 3; generic password, data-protection keychain, `WhenUnlockedThisDeviceOnly`, not synchronizable, proven by `kSecReturnAttributes`; masked form; delete leaves `errSecItemNotFound`; formatting test of every key-holding type; turn-off and remove-key delete the item | ● AC-M2-18, ● AC-M2-21 | M | WI-M2-M1, 09 | no | Developer | `m2/keychain-key-store` | Owner-run Mac (Simulator host) | ☐ deps merged |
| WI-M2-M6 | Cloud adapters end to end (MS-2): the three provider `IngestionModel`s over the transport, every fixture through a mock transport; the cloud model is never given the `Tool`; **one real recording per provider** made by the owner (see "Real provider recordings") | ● AC-M2-24 | M | WI-M2-M4, M5, 13 | no | Developer + owner (recordings) | `m2/cloud-adapters` | Owner-run Mac | ☐ deps merged; owner keys available in MS-2; each model still meets the five Q18 conditions |
| WI-M2-M7 | `TendEval` harness (MS-3): everything in AC-M2-28 "What it does", the results writer, file sharing in Debug only, the fixtures hash on screen, the Release and Archive check, and the Linux `project.yml` scan test | ● AC-M2-28 | M | WI-M2-M2, M3, M6, 15, 16 | no (debug tool, not product UI; brief) | Developer | `m2/eval-harness` | Owner-run Mac + Linux (scan) | ☐ deps merged |
| WI-M2-M8 | M2 green run on the merge commit (MS-3): Linux CI link, Mac commands B1–B5, the AC → test table with the environment of every test, the skip rule (T-22), then `TendEval` installed on both iPhones at that commit | ● AC-M2-13 | S | every item above | no | Developer | `m2/gate-green-run` | Linux CI + Owner-run Mac | ☐ all merged |

### Phase C — Device (the human owner)

| ID | Title | ACs | Depends on | Owner | Where verified | DoR |
|---|---|---|---|---|---|---|
| WI-M2-D1 | DS-1, iPhone 15 Pro, on device: the 20 gated inputs (cold start first), then the 3 airplane-mode inputs | ● AC-M2-11, ● AC-M2-15, ● AC-M2-16, ● AC-M2-17 | WI-M2-M8; DS-1 in `acceptance.md` (Tester); Q20 | Human owner (run), Acceptance Tester (script and scoring) | Device; scoring on Linux | ☐ |
| WI-M2-D2 | DS-2, iPhone 13, cloud: AC-M2-25 offline then online, then all 20 inputs per Q16 provider; the information-only cloud run on the iPhone 15 Pro | ● AC-M2-25, ● AC-M2-26, ● AC-M2-27 | WI-M2-M8; DS-2 in `acceptance.md`; Q16; Q20; owner keys | Human owner (run), Acceptance Tester | Device; scoring on Linux | ☐ |

**AC coverage check:** 28 of 28 ACs have exactly one owning item (●). There are no orphans, and every item serves at
least one AC.

| AC | Owner | Parts | AC | Owner | Parts |
|---|---|---|---|---|---|
| AC-M2-01 | WI-M2-05 | — | AC-M2-15 | WI-M2-D1 | WI-M2-15, 16, M7 |
| AC-M2-02 | WI-M2-05 | WI-M2-02 (W2-F3 clause) | AC-M2-16 | WI-M2-D1 | WI-M2-M7 |
| AC-M2-03 | WI-M2-03 | — | AC-M2-17 | WI-M2-D1 | WI-M2-08, 15 |
| AC-M2-04 | WI-M2-04 | — | AC-M2-18 | WI-M2-M5 | WI-M2-09 (Linux) |
| AC-M2-05 | WI-M2-M2 | WI-M2-06 (Linux) | AC-M2-19 | WI-M2-09 | — |
| AC-M2-06 | WI-M2-08 | — | AC-M2-20 | WI-M2-11 | WI-M2-10; Mac repeat in MS-2 |
| AC-M2-07 | WI-M2-M2 | WI-M2-07 (Linux) | AC-M2-21 | WI-M2-M5 | — |
| AC-M2-08 | WI-M2-08 | WI-M2-07 | AC-M2-22 | WI-M2-M4 | WI-M2-14 (Linux arithmetic) |
| AC-M2-09 | WI-M2-01 | WI-M2-M1, M3 (and every later PR re-runs the scan) | AC-M2-23 | WI-M2-M4 | WI-M2-06, 14 (Linux) |
| AC-M2-10 | WI-M2-M2 | WI-M2-06, 09 (Linux) | AC-M2-24 | WI-M2-M6 | WI-M2-12, 13 (Linux) |
| AC-M2-11 | WI-M2-D1 | WI-M2-M3 | AC-M2-25 | WI-M2-D2 | WI-M2-M3 |
| AC-M2-12 | WI-M2-04 | — | AC-M2-26 | WI-M2-D2 | WI-M2-10, 15 |
| AC-M2-13 | WI-M2-M8 | WI-M2-M1 | AC-M2-27 | WI-M2-D2 | WI-M2-M7 |
| AC-M2-14 | WI-M2-16 | WI-M2-15 | AC-M2-28 | WI-M2-M7 | WI-M2-M1 |

AC-M2-09 is owned by WI-M2-01, but its evidence is taken on the M2 merge commit (WI-M2-M8), when all three module
roots exist. Until then, the scan asserts "> 0 files" only for the roots that exist, using a committed scope table
(`ScanScope.swift` in the test target). The item that creates a root (WI-M2-M1 for `TendAI` and `TendEval`) switches
it to `required`. A required root with 0 files fails the test (lesson from M1 R-6). Every PR re-runs the scan.

### Scope notes per item (what "done" contains; ACs stay as the PO wrote them)

**Applies to every item:**
- Swift 6, strict concurrency, `-warnings-as-errors`. Swift Testing (`@Test`, `#expect`, parameterised tests).
- `TendIngestion` takes `now`, calendar, time zone, clock and IDs as injected inputs. It has no ambient time, randomness
  or locale (AC-M2-09 Rule 1, AC-M1-23 list), apart from `Locale(identifier: "en_US_POSIX")`.
- Every outcome, reason, error and case name passes the banned-token rule (AC-M2-10, 12, 23). The Developer picks the
  names (brief). The Reviewer checks that none blames the user (T-18) and that none uses the M1 design-forbidden list
  (`urgent`, `escalat*`, `alarm`, `alert`, `warning`, `stale`, `lapsed`, …; M1 design.md).
- No public API returns "what to do now" items (UX-2). The draft stream is a capture review (Q11).
- Independent oracles live in the test target and are written from the brief's definitions, never by calling
  production helpers (M1 R-4).
- Property tests print their seed range and counts. Every PR records its test runtime in `dev-notes.md` (R-18).
- No new SPM dependency or SDK. `TendSourceScan` and `Tools/TendTools` are our own local packages; ADR-0006 records
  them.

**WI-M2-01 — `m2/ingestion-foundation`**
- `Packages/TendIngestion/Package.swift`: tools 6.2, Swift 6 mode, iOS 26 / macOS 26 platforms, builds on Linux,
  library `TendIngestion` (depends on `../TendCore`), test target `TendIngestionTests` (depends on `TendIngestion` and
  `../TendSourceScan`).
- `Packages/TendSourceScan`: move the M1 lexer (`Packages/TendCore/Tests/TendCoreTests/Support/SourceScanner.swift`)
  into a library so both test targets can use one lexer. The M1 test copy stays unchanged in M2, so no accepted M1 test
  is touched. Switching `TendCoreTests` to the shared library is a later chore (R-16).
- Text primitives exactly as the brief's Definitions: name folding, keywords of a text, the closed stop-word list, the
  banned-token whole-token matcher (split at non-letters, then name-fold), and a hand-written **canonical JSON writer**
  (keys sorted by UTF-8 bytes, no insignificant whitespace, `/` not escaped, non-ASCII as UTF-8, no floating point).
  Do not rely on `JSONEncoder.sortedKeys`, which may sort differently on Darwin and Linux (R-10).
- The AC-M2-09 scanner, all six rules and the three closed lists, exactly as the brief writes them:
  - Rule 3 identifier tokens are **whole Swift identifiers, no camelCase split** (N-1). Negative tests: the near-miss
    `willPerformHTTPRedirection` passes; `URLSessionWebSocketTask` and `URL(string:` are caught; a file that uses only
    the allowed subset passes.
  - Rule 4 matches the **whole literal** (T-30). Negative tests: `tend.ai.key` and `com.tend.eval` pass;
    `api.example.com` and `https://api.example.com/v1` are caught; `https://api.openai.com` outside an allowlisted file
    is caught; a bare host in the `TendIngestion` provider table passes.
  - Rule 5: `SFSpeechRecognizer(` in the speech-permission file is caught. The two exception calls are allowed only when
    the scope table says the T-27 exception is on (off until WI-M2-M1).
  - Rule 6: one planted write API outside `EvalResultsWriter.swift`, and one log API anywhere in `TendEval`, are caught.
  - One planted hit for every other rule. The log prints the file count per module.
- **M2 Q24 (stricter lists, Rule 3 session methods, Rule 6 imports, new negative tests; brief AC-M2-09):** build it in
  WI-M2-01 round 2 if the brief amendment merges first. Otherwise it goes in a follow-up scanner PR, which must merge
  before WI-M2-M4 or WI-M2-M7 is reviewed.
- **M2 Q23 (the fixtures loader exception in Rule 6):** a scanner follow-up after the brief amendment, merged before
  WI-M2-M7 opens for review. WI-M2-01 round 2 stays strict: it has no loader exception.
- **Developer constraints (M2 Q24, M2 Q23; also WI-M2-M5, the key store, and every later item):**
  - No source method in TendIngestion, TendAI or TendEval may share a name and first label with any session-method
    call in the AC-M2-09 networking list (for example `data(for:`, `bytes(from:`, `upload(for:`, `download(from:`).
  - Fixtures are bundled as a small, fixed set of files. Each is loaded by its own literal
    `Bundle.main.url(forResource:` call.
  - If the harness needs an import that Rule 6 does not list (for example `AVFAudio` or `UniformTypeIdentifiers`), the
    Developer raises it with the PO before building. It is never added without a PO decision.
- The `DECISIONS.md` entries for M2 Q23 and Q24 go in the human-merged governance PR. They say "revised after the
  Tester's testability review of PR #16 (findings 1–9)".
- **ADR-0006 (M2 module layout):** the table above, the canonical JSON choice, the scan library, and the reason the
  scoring tool sits outside `TendIngestion/Sources`.

**WI-M2-02 — `m2/nonfinite-date-invariant`**
- One new `TaskInvariantViolation` case, named by the Designer. Its position in the case order is part of the naming
  decision, because `firstInvariantViolation()` checks cases in order.
- Construction with a non-finite `windowStart` or `windowEnd` throws it.
- Both M1 repositories reject a non-finite window date with a typed `HouseholdStoreError`, as in AC-M1-06, and keep
  their previous contents (PO, 2026-11-21):
  - `JSONFileHouseholdRepository`, loading a hand-written file: `unreadableFile`, because strict JSON cannot carry a
    non-finite number. The file bytes are unchanged and no empty household is returned.
  - `JSONFileHouseholdRepository`, saving a value set through an `internal(set)` setter: `writeUnsuccessful`. The
    previous file is kept, as in AC-M1-07. The AC-M1-07 assertion is not changed.
  - `InMemoryHouseholdRepository`, `save` or `upsertTask`: `invalidTask(.windowDateNotFinite)`. Nothing is stored.
    The PO also accepts that this guard checks every model invariant, not only finiteness (`invalidTask(<case>)`);
    it stays within AC-M1-25 and AC-M2-02.
  - The model decode throws `windowDateNotFinite`. A test proves this with a lenient decoder, which no repository
    uses.
- Extending the M1 test that lists the cases is an extension, not a weakening. The Reviewer confirms that no M1
  assertion is removed. AC-M1-25 is not edited (T-21).

**WI-M2-03 — `m2/time-resolver`**: implement the Q6 table below exactly. Test every row, every worked example (E1–E26),
the DST and year-boundary cases, and every invalid-anchor rule. The Tester adds cases of their own. The Tester confirms
the rows changed by PO Q-T1 and Q-T2 (R5, the note under the repeat table, the invalid-anchor bullet, E22–E26) before
PR #18 is reviewed.

**WI-M2-05 — `m2/draft-mapping`**: Q5 runs in the brief's order (1)–(9). Steps 5 and 6 call the WI-M2-03 resolver.
Step 7 calls the WI-M2-04 guard. Step 8 is the `sourcePhrase` check. The ≥ 1,000-output generator covers every
degenerate class in AC-M2-02, including non-finite and out-of-range time hints and unknown enum values.

**WI-M2-07 — `m2/duplicate-rules`**: the shortlist exactly as Definitions steps 1–6, and the Q12 = no word-match. The
oracle cases are ties at every ranking step, more than 10 eligible tasks, completed tasks, room-only matches and
stop-word-only queries.

**WI-M2-10 — `m2/payload-builder`**
- Proposed endpoints (the Developer re-checks them against current provider docs at build; dev notes record them):
  - OpenAI: `POST api.openai.com /v1/chat/completions`, `stream: true`, `response_format` JSON schema (strict),
    `store: false`, `temperature: 0`. Headers: `Authorization`, `Content-Type`.
  - Anthropic: `POST api.anthropic.com /v1/messages`, `stream: true`, structured output by one forced tool schema,
    `temperature: 0`. Headers: `x-api-key`, `anthropic-version`, `Content-Type`.
  - Gemini: `POST generativelanguage.googleapis.com /v1beta/models/<model>:streamGenerateContent?alt=sse`,
    `responseMimeType: application/json`, `responseSchema`, `temperature: 0`, thinking off where the model allows it.
    Headers: `x-goog-api-key`, `Content-Type`. Never `key=` in the query.
- **Q18, curated default models (approved by the PO 2026-11-21, with five conditions):** OpenAI `gpt-6-luna`,
  Anthropic `claude-haiku-4-5-20251001`, Gemini `gemini-3.5-flash-lite` (PO 2026-11-23, WI-M2-10 ruling 7; the
  2026-11-21 list failed live check L1). Fallbacks, only by PO ruling: Anthropic `claude-haiku-5-5`, Gemini
  `gemini-3.8-flash`. Each model must meet **all five** conditions. WI-M2-10
  checks them when it writes the provider table, and WI-M2-M6 checks them again before the real recordings:
  1. **Current:** the model is offered by the provider and is not deprecated or announced for removal.
  2. **Pinned model:** a dated snapshot ID where the provider offers one; else an ID the provider documents as one fixed
     snapshot; else, only if no suitable model offers either, the provider's only listed snapshot name. Never a
     `-latest`, preview or experimental alias. The served model ID reported in the response is recorded in every real
     recording and in an Outcome-sample recording right before and after each provider's DS-2 run; a difference voids
     that provider's run until a PO ruling.
  3. **Structured streaming:** the model streams output that follows the JSON schema (AC-M2-24).
  4. **Fixed sampling:** `temperature: 0` where the provider documents that the model accepts it and does not advise
     against it; otherwise `temperature` is omitted. The choice is fixed in the golden request. The DS-2 dev-set run
     runs each dev-set input twice per provider and reports the share of inputs with identical Q3-scored fields
     (watch; below 90% goes to the PO before the AC-M2-14 freeze).
  5. **Least reasoning:** the request sets the model's lowest documented reasoning or thinking level explicitly (off if
     the model allows it), never the default or adaptive. Reasoning and thinking tokens are read from usage in every
     real recording and reported. AC-M2-27 is the gate and is not relaxed (R-5).
  Live check L2a: as soon as the regenerated golden requests exist, the owner makes one real Outcome-sample recording
  per provider (commands under "Real provider recordings"). It shows no 4xx, a schema-valid stream, the served model
  ID and the reasoning-token count. L2a is in the WI-M2-16 Definition of Ready. WI-M2-M6's check L2 is unchanged.
  If a model fails any condition, the Developer stops and asks the PO for a replacement. The Developer never picks a
  different model alone (R-6).
- Fixed numeric body parameters (for example a max-tokens value) and every number in the instructions and schema must
  not contain any decimal string 600…729, because those are the interval sentinels (N-3).
- The key-path lists give each path a role: `fixed`, `capture`, `roomName` or `shortlistTitle` (N-3). Value
  comparison uses concrete array indices. If the user content is a templated string, the template is part of the
  golden, and the slots are compared after the template is removed. `Content-Length` and other transport-set headers
  are listed as "derived from the body" and left out of the Linux header comparison.
- The golden requests and key-path lists are reviewed by the Tester before the AC-M2-14 freeze (WI-M2-16).

**WI-M2-14 — `m2/cloud-deadline-retry`**: the transport protocol is neutral (N-2): `CloudRequest` (the builder's plain
value) in, an `AsyncSequence` of byte chunks or a neutral failure out, plus the per-attempt timeouts as plain
`Double` seconds. Arithmetic: deadline 10.0 s from receipt of input; resource timeout = time left; request timeout =
min(time left, 4.0 s); one retry for 429/5xx only; pause p = max(0.5 s, `Retry-After` delta-seconds, unreadable or
missing = 0); retry only if ≥ 3.0 s remain after the pause.

**WI-M2-15 — `m2/eval-scorer`**: the scorer takes the results file and fixtures as `Data` and returns a value (Rule 1,
T-26). It rejects a file that does not conform to v1. The conformance check is hand-written in Foundation for the
schema's subset (types, required keys, enums, `additionalProperties: false`). A test checks that every constraint in
`results-v1.schema.json` has a matching check (R-22).

**WI-M2-M1 — `m2/xcodegen-project`** (first Mac item; it settles project generation)
- **ADR-0003 → `Accepted`.** XcodeGen, one exact release version, installed from the GitHub release binary with its
  SHA-256 recorded in the ADR. `project.yml` at the repo root; `Tend.xcodeproj` git-ignored and always regenerated.
  **Agents never hand-edit `.pbxproj`** (CLAUDE.md §3, §6). A PR that contains a `.pbxproj` change is returned.
- `project.yml` targets: `Tend` (skeleton app, shipped later; no dependency on `TendEval`), `TendEval` (own bundle ID,
  Debug only, file sharing in Debug only, fixtures bundled, its scheme's Archive action off), `TendAITestHost` and
  `TendAIHostedTests`. The `Tend` scheme archives only `Tend`.
- **T-27 check:** on the iOS 26 Simulator and macOS, test whether `SpeechAnalyzer` with `SpeechTranscriber` (and
  `DictationTranscriber`) runs without `SFSpeechRecognizer.requestAuthorization(_:)`, and what Apple's iOS 26
  documentation requires. Record the result, the Xcode and OS builds and the doc reference in `dev-notes.md`.
  Then set the scope table's Rule 5 exception on or off and update the speech-permission row of this plan. A device
  confirmation follows in DS-1 and DS-2 preconditions (the permission prompt must appear once).
- Run every Mac command below once and fix any scheme or destination name that differs. Update the plan in the same
  PR.
- Information only, never evidence: TTFI of one FoundationModels `streamResponse` call with a draft-sized schema on the
  Mac, to size R-1 early.

**WI-M2-M5 — `m2/keychain-key-store`**: the Developer constraints in WI-M2-01 apply (M2 Q24): no source method may
share a name and first label with any session-method call in the AC-M2-09 networking list (for example `data(for:`,
`bytes(from:`, `upload(for:`, `download(from:`).

**WI-M2-M7 — `m2/eval-harness`**: the harness's debug screens are plain test controls (input list, script text, start,
retake reason, network fields, key field, export, "Remove key"). They are not product UI and are not judged against
UX-4 (brief). It uses only the public API of `TendIngestion` and `TendAI`.

## Q6 time-phrase table (AC-M2-03; Tester review is a DoR condition for WI-M2-03)

The model never sends dates. It sends a structured `TimeHint`. The resolver turns the hint into window, dayparts,
weekdays and interval using the injected `now`, calendar and time zone.

**The hint (neutral type in `TendIngestion`; the on-device `@Generable` type and the cloud schema mirror it):**
- `anchor`: `none`, `today`, `tonight`, `tomorrow`, `weekday`, `thisWeekend`, `thisWeek`, `nextWeek`, `beforeMonth`,
  `beforeSeason`, `inDays`, `inWeeks`.
- `daypart`: optional `morning`, `afternoon`, `evening`, `night`.
- `weekday`: optional `monday` … `sunday` (needed by `weekday`).
- `month`: optional integer 1…12 (needed by `beforeMonth`).
- `season`: optional `spring`, `summer`, `autumn`, `winter` (needed by `beforeSeason`).
- `count`: optional integer (needed by `inDays`, 1…366, and `inWeeks`, 1…52).
- `repeatEvery`: optional integer ≥ 1, with `repeatUnit`: `day`, `week`, `month`, `year`.

**Notation:**
- `D` is the local calendar day that contains `now` (injected calendar and time zone).
- `mid(d)` is local 00:00 of day `d`, resolved with the M1 Q11 policy: a time that does not exist moves to the next
  existing instant (`.nextTime`), and a repeated time takes its first occurrence (`.first`). So "end of today" =
  `mid(D+1)`, and a day is 23 h or 25 h long on a DST day (Q6(e)).
- `slot(p, d)` is the M1 slot of daypart `p` on day `d`: morning [05:00, 12:00), afternoon [12:00, 17:00), evening
  [17:00, 22:00), night [22:00, 05:00 on `d+1`), with the same DST policy.
- `at(h, d)` is local `h`:00 on day `d`, with the same policy.
- `nextMon` is the first day after `D` (1…7 days ahead) whose weekday is Monday. The week starts on **Monday** whatever
  the calendar's `firstWeekday` (Q6(a)).
- `7d` in rows T1 and T15 is **604,800 seconds** (absolute), the same arithmetic as M1 `Completion` (`days × 86,400`)
  and as the Q5 fallback `[now, now + 7 days)`. Calendar rows (T5, T7, T9, T11, T14) use `mid(…)` and so follow the
  local calendar across a DST change.
- "∅" means the resolver leaves the set empty and Q5 step 3 fills the default: dayparts → `Daypart.defaultAllowed`
  (morning, afternoon, evening), weekdays → all seven. The resolver itself always returns the ∅ sets. It never fills
  the defaults. WI-M2-05 applies the Q5 step-3 defaults to the resolver's empty sets after step 5.
- **Source:** "Q6" means a brief default or settled point. **P1…P7 are Planner proposals** that the brief does not
  cover. The eval composition needs them (for example "no wait, Thursday", Q3). The Tester reviews them with the
  table, and the **PO acknowledges P1–P7** as product meaning before WI-M2-03 is Ready. If the PO rejects a row, that
  hint maps to T1. **The PO acknowledged P1–P7 on 2026-11-21**, with one change to P3: "this week" said on a Sunday at
  or after 18:00 means next week (row T10, examples E15 and E16).

**Anchor rows:**

| # | Phrase family (examples) | Hint | Window `[start, end)` | Dayparts | Weekdays | Source |
|---|---|---|---|---|---|---|
| T1 | no time phrase | `none` | `[now, now + 7d)` | ∅ | ∅ | Q5, Q6 |
| T2 | "today" | `today` | `[now, mid(D+1))` | ∅ | ∅ | Q6, Q6(e) |
| T3 | "this morning", "this afternoon", "this evening" | `today` + `p` | `[max(now, slot(p, D).start), slot(p, D).end)`. If `slot(p, D).end ≤ now`, the window is `slot(p, D+1)` (the next one). | {p} | ∅ | **P1** |
| T4 | "tonight" | `tonight` (a `daypart` is ignored) | `[now, at(05, D+1))` | {evening, night} | ∅ | Q6(d) |
| T5 | "tomorrow" | `tomorrow` | `[mid(D+1), mid(D+2))` | ∅ | ∅ | Q6 |
| T6 | "tomorrow morning" … "tomorrow night" | `tomorrow` + `p` | `slot(p, D+1)` | {p} | ∅ | Q6 |
| T7 | "Thursday", "on Thursday", "no wait, Thursday" | `weekday` W | `[mid(d), mid(d+1))`, where `d` is the first day **after** `D` with weekday W (1…7 days ahead; said on a Thursday it means next Thursday) | ∅ | ∅ | **P2** |
| T8 | "Thursday evening" | `weekday` W + `p` | `slot(p, d)`, with `d` as in T7 | {p} | ∅ | **P2** |
| T9 | "this weekend" | `thisWeekend` | Mon–Fri: `[mid(Sat), mid(Sat+2))`, where Sat is the first Saturday after `D`. Saturday: `[now, mid(D+2))`. Sunday, local time before 18:00: `[now, mid(D+1))`. Sunday at or after 18:00: `[mid(D+6), mid(D+8))` (the coming Saturday and Sunday). **With a daypart `p`:** let `first` and `last` be the first and last weekend days of that window. The window is `[max(now, slot(p, first).start), slot(p, last).end)`. If that end ≤ now (Sunday before 18:00, for example "this weekend in the morning" said Sunday 15:00), use the coming weekend: `[slot(p, D+6).start, slot(p, D+7).end)`. | ∅, or {p} if a daypart is given | {saturday, sunday} | Q6, Q6(b), PO 2026-11-21 (daypart) |
| T10 | "this week", "sometime this week" | `thisWeek` | `[now, mid(nextMon))`. Sunday at or after 18:00 local time: next week, the same window as T11, `[mid(nextMon), mid(nextMon+7))` (PO change, 2026-11-21). | ∅ | ∅ | **P3** (PO-acknowledged, changed) |
| T11 | "next week" | `nextWeek` | `[mid(nextMon), mid(nextMon+7))`. The brief's "+7 days" means **7 calendar days** (PO decision T11, 2026-11-21), so the window ends at local midnight across a DST change. | ∅ | ∅ | Q6, PO T11 |
| T12 | "before March", "by June" | `beforeMonth` M | `[now, b)`, where `b` is the **earliest** `mid(1 M y)` that is **later than** `now`. In the current month that is next year's (Q6(f)). | ∅ | ∅ | Q6, Q6(f) |
| T13 | "before summer", "before winter" | `beforeSeason` S | `[now, b)`, where `b` is the earliest `mid(1 Ms y)` later than `now`; Ms is 1 Mar (spring), 1 Jun (summer), 1 Sep (autumn), 1 Dec (winter): meteorological, northern hemisphere (Q6(c)). In the current season that is next year's start (Q6(f)). | ∅ | ∅ | Q6, Q6(c), Q6(f) |
| T14 | "in 3 days", "in two weeks" | `inDays` N (1…366) or `inWeeks` N (1…52) | No daypart: `[mid(d), mid(d+1))`. With a daypart `p`: `slot(p, d)`, the same as T6 and T8. In both cases `d = D + N` (or `D + 7N`). | ∅, or {p} if a daypart is given | ∅ | **P4**, PO 2026-11-21 (daypart) |
| T15 | "in the morning", "some evening" (no day) | `none` + `p` | `[now, now + 7d)` | {p} | ∅ | **P5** |

A `daypart` given with `thisWeek`, `nextWeek`, `beforeMonth` or `beforeSeason` sets dayparts to {p} and does not change
the window.

**Repeat rows** (combine with any anchor row; the anchor row gives window, dayparts and weekdays unless stated):

| # | Phrase family | Hint | Interval (days) | Weekdays | Source |
|---|---|---|---|---|---|
| R1 | "every N days", "daily" (1), "every other day" (2) | `repeatEvery` N, `day` | N | anchor | Q6 |
| R2 | "every N weeks", "weekly" (1), "every other week" (2) | N, `week` | 7N | anchor | Q6 |
| R3 | "every N months", "monthly" (1), "quarterly" (3) | N, `month` | 30N (1 month = 30 days) | anchor | Q6 |
| R4 | "every year", "yearly", "every two years" | N, `year` | 365N | anchor | **P6** |
| R5 | "every Thursday", "every other Thursday", "monthly on Thursday", "every year on a Thursday" | `weekday` W + N `week`, `month` or `year` | 7N, 30N or 365N (as R2, R3, R4) | **{W}**; window T7 | **P7**, PO Q-T1 2026-11-21 |
| R6 | "every weekend" | `thisWeekend` + 1 `week` | 7 | {saturday, sunday}; window T9 | **P7** |
| R7 | "every morning", "every evening" | `none` + `p` + 1 `day` | 1 | ∅; window T15, dayparts {p} | **P7** |

A weekday anchor sets weekdays to {W} only together with a `week`, `month` or `year` repeat (R5). With a `day` repeat
("daily from Thursday") weekdays stay ∅: the weekday sets only the first window (T7), and the item stays daily. A
one-off "on Thursday" (T7) keeps all seven weekdays, so if the user does not do it that day the M1 rescheduler can
move it to any day. If Q5 step 6 drops the interval (the final kind is not `recurring`, or the interval is outside
1…730), the {W} from R5 is dropped with it, and weekdays are all seven, as for T7 (PO Q-T1, 2026-11-21).

**How the hint meets Q5** (the resolver never decides the kind):
- The interval is used only if the item's final kind is `recurring` (Q5 step 6). A repeat on a one-off or restock item
  is dropped. A `recurring` item with no repeat, or with an interval outside 1…730, becomes a one-off (step 6). So
  "every 25 months" (750 days) becomes a one-off.
- **An invalid anchor is "no anchor" (T1 window, Q5 step 5); the rest of the hint still counts (PO Q-T2,
  2026-11-21).** The anchor is invalid if any of these is true: it is unknown; its required field is missing or out of
  range (`weekday` with no weekday, `month` not 1…12, unknown season, `count` out of range); its computed window has
  end ≤ start; or the window is out of range (start < now, start > now + 366 × 86,400 s, or end > start + 366 ×
  86,400 s). Then the window is the T1 window and weekdays are ∅. A valid `daypart` still sets dayparts to {p} (as
  T15). A valid repeat still gives its interval (R1–R4); R5's {W} does not apply without a valid weekday. `basis`
  still records the fallback reason. With no valid daypart and no valid repeat, the result equals no hint (T1).
- `basis` is a diagnostic field that records which rule gave the window (or the fallback reason). WI-M2-05 uses it
  for the per-rule repair counts in AC-M2-02. Its exact values are not part of AC-M2-03's "equal the table" check.
  (Technical choice, no PO meaning.)
- An unknown `daypart` or `repeatUnit` is dropped (step 2). A `repeatEvery` < 1 means no repeat.
- Numbers: the neutral hint carries counts as `Int?`. The provider parsers (WI-M2-12) and the on-device mapping turn
  any non-integer, non-finite or out-of-range JSON number into `nil` before the resolver sees it.
- "Before 18:00" and "at or after 18:00" on a Sunday (T9 and T10) compare the local wall-clock time of `now` with 18:00:00.
- The calendar is the injected one. The eval and the tests use the Gregorian calendar (en-US, Q2). Month and season
  rows assume Gregorian months.

**Worked examples** (time zone `America/New_York`; US DST 2026 starts Sun 8 Mar, ends Sun 1 Nov; checked against
tzdata). The Tester adds a zone whose DST change is at local midnight (for example `America/Santiago`, verified against
tzdata in the test), so that `mid(d)` moves to 01:00.

| # | Row | `now` (local) | Expected window (UTC) | Other |
|---|---|---|---|---|
| E1 | T2 today, 23 h day | Sun 2026-03-08 10:00 EDT | `[2026-03-08T14:00Z, 2026-03-09T04:00Z)` (14 h) | — |
| E2 | T4 tonight, 25 h day | Sun 2026-11-01 19:00 EST | `[2026-11-02T00:00Z, 2026-11-02T10:00Z)` | dayparts {evening, night} |
| E3 | T9 Sunday at 18:00 | Sun 2026-11-01 18:00 EST | `[2026-11-07T05:00Z, 2026-11-09T05:00Z)` | weekdays {sat, sun} |
| E4 | T9 Sunday before 18:00 | Sun 2026-11-01 17:59 EST | `[2026-11-01T22:59Z, 2026-11-02T05:00Z)` | weekdays {sat, sun} |
| E5 | T9 Saturday, across spring-forward | Sat 2026-03-07 11:00 EST | `[2026-03-07T16:00Z, 2026-03-09T04:00Z)` | — |
| E6 | T11 next week, year boundary | Thu 2026-12-31 15:00 EST | `[2027-01-04T05:00Z, 2027-01-11T05:00Z)` | — |
| E7 | T5 tomorrow, year boundary | Thu 2026-12-31 15:00 EST | `[2027-01-01T05:00Z, 2027-01-02T05:00Z)` | — |
| E8 | T13 before summer, in summer | Mon 2026-06-15 09:00 EDT | `[2026-06-15T13:00Z, 2027-06-01T04:00Z)` | Q6(f) |
| E9 | T13 before winter, in winter (January) | Sun 2027-01-10 09:00 EST | `[2027-01-10T14:00Z, 2027-12-01T05:00Z)` | — |
| E10 | T12 before March | Fri 2026-02-20 09:00 EST | `[2026-02-20T14:00Z, 2026-03-01T05:00Z)` | — |
| E11 | T12 before December, in December | Thu 2026-12-31 15:00 EST | `[2026-12-31T20:00Z, 2027-12-01T05:00Z)` | Q6(f) |
| E12 | T6 tomorrow morning, 23 h day | Sat 2026-03-07 21:00 EST | `[2026-03-08T09:00Z, 2026-03-08T16:00Z)` | dayparts {morning} |
| E13 | T1 no phrase, across spring-forward | Sat 2026-03-07 11:00 EST | `[2026-03-07T16:00Z, 2026-03-14T16:00Z)` (604,800 s; local end 12:00 EDT) | — |
| E14 | R3 / Q5 step 6 | any | "every 3 months" → interval 90; "every 25 months" → one-off, no interval | — |
| E15 | T10 this week, Sunday at 18:00 (means next week) | Sun 2026-11-01 18:00 EST | `[2026-11-02T05:00Z, 2026-11-09T05:00Z)` | PO P3 change |
| E16 | T10 this week, Sunday before 18:00 | Sun 2026-11-01 17:59 EST | `[2026-11-01T22:59Z, 2026-11-02T05:00Z)` | PO P3 change |
| E17 | T11 next week, across fall-back (25 h Sunday) | Thu 2026-10-22 10:00 EDT | `[2026-10-26T04:00Z, 2026-11-02T05:00Z)` (169 h) | Tester finding |
| E18 | T11 next week, across spring-forward (23 h Sunday) | Thu 2026-02-26 10:00 EST | `[2026-03-02T05:00Z, 2026-03-09T04:00Z)` (167 h) | Tester finding |
| E19 | T4 tonight, said after midnight | Mon 2026-11-23 01:00 EST | `[2026-11-23T06:00Z, 2026-11-24T10:00Z)` (Mon 01:00 to Tue 05:00 local) | dayparts {evening, night}; Tester finding |
| E20 | T14 "in 3 days at night" | Thu 2026-11-19 10:00 EST | `[2026-11-23T03:00Z, 2026-11-23T10:00Z)` (Sun 22:00 to Mon 05:00 local) | dayparts {night}; PO 2026-11-21 |
| E21 | T9 "this weekend in the morning", Sunday 15:00 (morning has passed) | Sun 2026-11-01 15:00 EST | `[2026-11-07T10:00Z, 2026-11-08T17:00Z)` (Sat 05:00 to Sun 12:00 local) | dayparts {morning}, weekdays {sat, sun}; PO 2026-11-21 |
| E22 | Invalid anchor: `weekday` with no weekday, + 1 `week` (PO Q-T2) | Mon 2026-11-23 10:00 EST | `[2026-11-23T15:00Z, 2026-11-30T15:00Z)` (T1 window, 604,800 s) | resolver output; dayparts ∅, weekdays ∅, interval 7; a recurring item stays recurring |
| E23 | R5: `weekday` Thursday + 1 `month` (PO Q-T1) | Mon 2026-11-23 10:00 EST | `[2026-11-26T05:00Z, 2026-11-27T05:00Z)` (T7, Thu 26 Nov local) | resolver output; dayparts ∅, weekdays {thursday}, interval 30 |
| E24 | `weekday` Thursday + 1 `day` ("daily from Thursday"; PO Q-T1) | Mon 2026-11-23 10:00 EST | `[2026-11-26T05:00Z, 2026-11-27T05:00Z)` (T7) | resolver output; dayparts ∅, weekdays ∅, interval 1 |
| E25 | Invalid anchor: `inDays` 400 (out of 1…366) + `evening` (PO Q-T2) | Mon 2026-11-23 10:00 EST | `[2026-11-23T15:00Z, 2026-11-30T15:00Z)` (T1 window, 604,800 s) | resolver output; dayparts {evening}, weekdays ∅, no interval |
| E26 | Settlement: E23's resolution with final kind one-off (Q5 step 6; PO Q-T1) | Mon 2026-11-23 10:00 EST | `[2026-11-26T05:00Z, 2026-11-27T05:00Z)` (T7) | after Q5 settlement; no interval; weekdays all seven ({thursday} dropped with the interval); dayparts ∅, which becomes the default `Daypart.defaultAllowed` (morning, afternoon, evening) after Q5 |

## Route matrix (AC-M2-19, the full expected matrix)

**Inputs:**
- **A**, on-device availability: `available`, or one of four unavailable reasons: `deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`, `unsupportedLocale`.
- **P**, preference: `onDeviceFirst` or `alwaysCloud`.
- **S**, the stored cloud state. X and Y range over every ordered pair of different providers from {OpenAI, Anthropic,
  Gemini}.

| S | Stored state | cloud on? | Side effect when the route is chosen |
|---|---|---|---|
| S0 | fresh install: nothing selected, no consent, no key | off | — |
| S1 | X selected; no consent, no key | off | — |
| S2 | X selected; consent X; no key (restored (ii)) | off | — |
| S3 | X selected; key X; no consent (restored (i)) | off | key X deleted (orphan) |
| S4 | X selected; consent X + key X | **on (X)** | — |
| S5 | X selected; consent Y + key Y (restored (iii)) | off | — (Y's key has Y's consent, so it is kept) |
| S6 | nothing selected; consent Y + key Y | off | — |
| S7 | X selected; consent X + key X; consent Y + key Y | **on (X)** | — |
| S8 | X selected; consent X; key Y; no consent Y | off | key Y deleted (orphan) |

**Expected route:**

| S | A = available, P = onDeviceFirst | A = available, P = alwaysCloud | A = each of the 4 unavailable reasons, either P (8 cells) |
|---|---|---|---|
| S0, S1, S2, S3, S5, S6, S8 (cloud off) | `onDevice` | `onDevice` ("always cloud" with cloud off is ignored) | `none` |
| S4, S7 (cloud on X) | `onDevice` | `cloud(X)` | `cloud(X)` |

- Cell count: 5 availability values × 2 preferences × (S0 + S6 for each Y + S1…S5, S7, S8 for each X or X/Y pair). The
  test enumerates every cell and logs the matrix.
- `cloud(Y)` never appears where Y is not selected.
- After a route is chosen, an on-device generation error never re-routes to the cloud (AC-M2-10, AC-M2-19). Every
  outcome carries its route.

## Order of work (critical path)

```
HM-1 (CI) ──┐
WI-01 ──┬── WI-03 (after Tester Q6 review) ─┐
        ├── WI-04 ──────────────────────────┼─ WI-05 ── WI-06 ──┬─ WI-07 ──┬─ WI-08
WI-02 (Designer name) ──────────────────────┘                   │          └─ WI-10 ── WI-11 ─┐
        │                                                       ├─ WI-09                     │
        │                                                       ├─ WI-12 ── WI-13            │
        │                                                       └─ WI-14 (needs WI-10)       │
        ├── WI-15 (after WI-05) ─────────────────────────────── WI-16 freeze (Tester) ◄──────┘
        └── MS-1: WI-M1 ── MS-2: WI-M2, M3, M4, M5, M6 ── MS-3: WI-M7, M8 ── DS-1 (D1), DS-2 (D2) ── gate
```

1. **WI-M2-01 first.** Every other item builds on its package, primitives and scan. The scan protects every later PR.
   The M2 Q24 scanner work is in WI-M2-01 round 2, or in a follow-up scanner PR that merges before WI-M2-M4 or WI-M2-M7
   is reviewed. The M2 Q23 loader exception is a follow-up scanner PR that merges before WI-M2-M7 opens for review.
2. **WI-M2-02, 03, 04 next**, in parallel. 02 waits only for the Designer's name. 03 waits for the Tester's Q6 review.
3. **WI-M2-05 → 06** is the spine: the draft and event contract that every adapter targets.
4. **WI-M2-07…14** fan out after WI-M2-06. Suggested order to unblock MS-2 soonest: 07, 09, 10, 12, 14, 13, 08, 11.
5. **WI-M2-15** can start as soon as WI-M2-05 is merged. **WI-M2-16** needs the Tester's fixtures and the frozen
   golden requests (WI-M2-11).
6. **MS-1 (WI-M2-M1)** runs as soon as WI-M2-01 is merged, in parallel with Phase A. It settles ADR-0003 and T-27
   early, and it gives a first latency signal (R-1).
7. **MS-2** starts when WI-M2-06, 07, 09, 10, 13 and 14 are merged.
8. **MS-3** runs after everything else is merged and the eval is frozen. DS-1 and DS-2 follow as soon as `TendEval` is
   installed (a free signing profile lasts 7 days; R-14).

## Owner-run Mac sessions (grouped so the owner runs as few as possible)

| Session | Items | Owner presence needed | Length (estimate) | Before it |
|---|---|---|---|---|
| **MS-1** (early) | WI-M2-M1: ADR-0003, `project.yml`, `TendAI` scaffold, T-27 check, command check, latency probe | Remote Control on; Xcode 26 installed and opened once (licence accepted, iOS 26 Simulator runtime downloaded) | ~2 h | WI-M2-01 merged |
| **MS-2** (adapters) | WI-M2-M2, M3, M4, M5, M6; the Mac repeat of the `TendIngestion` suite (AC-M2-20 golden bytes) and of the `TendCore` suite (W3-F1 Darwin DST rerun); optional device spike SP-1 | Remote Control on. **The owner is needed in person for about 20 minutes** to paste each provider key for the real recordings (they never leave the Mac's shell; see below) and, for SP-1, to plug in the iPhone 15 Pro | 1–2 days, one setup | WI-M2-06, 07, 09, 10, 13, 14 merged |
| **MS-3** (gate) | WI-M2-M7 final build, WI-M2-M8 green run (B1–B5), Release and Archive check, `TendEval` installed on both iPhones | Remote Control on; both iPhones connected, unlocked, Developer Mode on, signed into the signing team (Q20) | ~3 h | everything merged; eval frozen |
| DS-1, DS-2 (device, not Mac) | WI-M2-D1, D2 | The owner runs the Tester's scripts; voice inputs are read aloud live | ~2 h + ~3 h (3 providers) | MS-3 |

**SP-1 (optional, information only):** at the end of MS-2, install a development `TendEval` on the iPhone 15 Pro and
time 3 non-eval sentences on device. It is not evidence for any AC. It tells us early whether AC-M2-16 (< 1.5 s TTFI)
is realistic with the chosen schema, and whether the instructions need to shrink before MS-3 (R-1, R-3).

**How Mac code is written:** in MS-2 the Developer agent works on the owner's Mac through Remote Control, builds and
tests there, and pushes from there. Writing `TendAI` code in the Linux container without a compiler is allowed only for
first drafts. Nothing is "done" until it is built and tested on the Mac.

## Exact commands

### Linux (container and CI; every Phase A PR)
```bash
swift build --package-path Packages/TendCore       -Xswiftc -warnings-as-errors
swift test  --package-path Packages/TendCore       -Xswiftc -warnings-as-errors
swift test  --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors
swift build --package-path Packages/TendIngestion  -Xswiftc -warnings-as-errors
swift test  --package-path Packages/TendIngestion  -Xswiftc -warnings-as-errors 2>&1 | tee tendingestion-test.log
swift build --package-path Tools/TendTools         -Xswiftc -warnings-as-errors
```
`Packages/TendAI` is never built on Linux (Apple-only frameworks).

### Owner-run Mac (from the repo root, at the commit under test; each output is saved to a log)
WI-M2-M1 confirms these on the Mac and corrects any scheme or destination name in the same PR.
```bash
# B0 — evidence header (always first)
git rev-parse HEAD && git status --porcelain        # the second must print nothing
sw_vers && xcodebuild -version && swift --version && xcodegen --version
xcrun simctl list runtimes | grep -i ios

# B1 — TendCore on Darwin Foundation (W3-F1 rerun; part of AC-M2-13(b))
swift test --package-path Packages/TendCore -Xswiftc -warnings-as-errors 2>&1 | tee mac-B1-tendcore.log

# B2 — TendIngestion on Darwin (AC-M2-20 golden bytes repeated on the Mac; all Linux logic again)
swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors 2>&1 | tee mac-B2-tendingestion.log

# B3 — generate the project (never hand-edit .pbxproj)
xcodegen generate --spec project.yml

# B4 — TendAI mock and adapter tests on macOS (AC-M2-05, 07, 10, 24 adapter halves; AC-M2-13(b))
(cd Packages/TendAI && xcodebuild test -scheme TendAI -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1) | tee mac-B4-tendai-macos.log

# B5 — iOS Simulator host-app tests (AC-M2-18(a), 21, 22, 23 adapter half; AC-M2-13(b))
xcodebuild test -project Tend.xcodeproj -scheme TendAIHostedTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath build/results/B5-hosted.xcresult \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES 2>&1 | tee mac-B5-hosted.log

# B6 — AC-M2-28: Release and Archive products hold no TendEval
xcodebuild build -project Tend.xcodeproj -scheme Tend -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-release CODE_SIGNING_ALLOWED=NO 2>&1 | tee mac-B6-release.log
find build/dd-release/Build/Products -iname '*TendEval*'          # must print nothing
xcodebuild archive -project Tend.xcodeproj -scheme Tend \
  -destination 'generic/platform=iOS' -archivePath build/Tend.xcarchive CODE_SIGNING_ALLOWED=NO 2>&1 | tee mac-B6-archive.log
find build/Tend.xcarchive -iname '*TendEval*'                     # must print nothing
xcodebuild build -project Tend.xcodeproj -scheme TendEval -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-eval CODE_SIGNING_ALLOWED=NO 2>&1 | tee mac-B6-eval-debug.log

# B7 — install TendEval on an iPhone (MS-3; <UDID> from the first command, <TEAM_ID> from Q20)
xcrun devicectl list devices
xcodebuild build -project Tend.xcodeproj -scheme TendEval -configuration Debug \
  -destination 'platform=iOS,id=<UDID>' -derivedDataPath build/dd-device \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=<TEAM_ID> 2>&1 | tee mac-B7-install-build.log
xcrun devicectl device install app --device <UDID> build/dd-device/Build/Products/Debug-iphoneos/TendEval.app
```
AC-M2-13(b) is B1, B2, B4 and B5 on the M2 merge commit. A test compiled out on Linux counts as run only if it appears
in B4 or B5 (T-22); the AC → test table in `dev-notes.md` names the command for every test.

### Owner-run Mac evidence record (one per session, committed under `docs/milestones/M2/evidence/mac/`)
Who ran it (the owner, or the agent driving the owner's Mac); which Mac (M4 Air or M1 mini) and the macOS build; the
Xcode build; the Simulator runtime; the commit SHA from B0; each exact command; and the full log files with their
SHA-256. A Mac record is never evidence for a device AC.

### Real provider recordings (WI-M2-M6, in MS-2; AC-M2-24, T-19)
For each provider, the owner types the key at a hidden prompt. Only the response stream is saved. The request body is
built from the fixed Outcome sentence of the brief with an empty household (no rooms, no titles), so it holds no
household data.
```bash
swift run --package-path Tools/TendTools tend-payload-dump --provider openai --outcome-sample > /tmp/body.json
read -rs TEND_KEY          # the key is typed, never echoed, never in shell history
curl -sS -N https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $TEND_KEY" -H 'Content-Type: application/json' --data-binary @/tmp/body.json \
  > Fixtures/M2/provider-streams/openai/recorded-outcome-sample.sse
unset TEND_KEY; rm /tmp/body.json
```
The Anthropic and Gemini commands are the same, with the path and auth header from WI-M2-10 (`x-api-key` plus
`anthropic-version`; `x-goog-api-key`). WI-M2-M6 writes the three commands into `dev-notes.md`. The Reviewer checks
that no recorded file contains a request header or the key.

## Scoring tool and command (AC-M2-14, 15, 17, 26; T-26)

- **Tool:** `tend-eval-score`, an executable in `Tools/TendTools` (outside `TendIngestion/Sources`). It reads the files,
  calls the `TendIngestion` scorer with `Data`, writes the scorer log, and returns an exit code: **0** = scored and the
  profile passes, **1** = scored and the profile fails, **2** = file rejected (not v1, or the fixtures hash does not
  match).
- **Profiles:** `ds1-gated` (AC-M2-15, 16, 17: the Q3 thresholds, on-device timing < 1.5 s / ≤ 5.0 s, 0 duplicates, ≤ 1
  false merge); `ds1-offline` (AC-M2-11 per-input rules); `ds2-offline` and `ds2-online` (AC-M2-25); `ds2-gated`
  (AC-M2-26, 27: the Q3 thresholds, cloud timing < 3.0 s / ≤ 10.0 s, 0 duplicates, ≤ 1 false merge, sent key paths a
  subset of the provider's allowed list); `info` (no pass rule; cold start and the iPhone 15 Pro cloud run).
- **Command (Linux, from the repo root):**
```bash
sha256sum -c Fixtures/M2/eval/MANIFEST.sha256
swift run --package-path Tools/TendTools -c release tend-eval-score \
  --profile ds1-gated \
  --fixtures Fixtures/M2/eval \
  --expected-fixtures-sha256 "$(sha256sum Fixtures/M2/eval/MANIFEST.sha256 | cut -d' ' -f1)" \
  --results docs/milestones/M2/evidence/device/<results-file>.json \
  --log docs/milestones/M2/evidence/device/<results-file>.score.log
```
- **Fixtures hash:** the SHA-256 of the `MANIFEST.sha256` file's bytes. The manifest lists the SHA-256 of every fixture
  file. `TendEval` computes the same hash over its bundled manifest (CryptoKit), checks each bundled file against it,
  and shows the hash. The scorer needs no crypto code, so `TendIngestion` stays Foundation-only.

## Eval harness ID generator (AC-M2-28, T-29)

`EvalIDGenerator` lives in `TendIngestion` next to the scorer (eval namespace). It is a plain value that the harness
passes through the public commit API, so it is not a hook into the pipeline. It is deterministic and is unit-tested on
Linux. For input number `i` (the 1-based position of the input in `inputs.json`, 1…20) and attempt `a` (1…15), the
`n`-th ID (n = 1, 2, 3 …, restarting for every attempt, because every attempt gets a fresh household) is the UUID with
these 16 bytes:

| Bytes | Value |
|---|---|
| 0–3 | `0x54 0x45 0x56 0x4C` (ASCII "TEVL") |
| 4–5 | `i`, big-endian `UInt16` |
| 6 | `0x80 \| a` (version 8, RFC 9562 custom UUID) |
| 7 | `0x00` |
| 8 | `0x80` (RFC 9562 variant) |
| 9–15 | `n`, big-endian 56-bit |

- Every fixture UUID is version 4 (byte 6 high nibble `4`, written by the Tester). The composition check in WI-M2-16
  asserts this, so the generator can never yield a fixture UUID.
- Commit still skips any ID already in use (AC-M2-06), so even a broken fixture cannot cause an overwrite.
- The same input and attempt always give the same IDs.

## Linux CI growth (`.github/workflows/ci.yml` is protected: human-merge items)

The current `ci.yml` builds and tests only `Packages/TendCore`. The Merge Gatekeeper's G3 refuses to merge a Swift PR
when no build or test check ran for it, so **no Phase A PR can merge until HM-1 is in**.

**HM-1 (owner merge, needed before WI-M2-01 merges).** Add a second job. The Planner does not edit the file; the
Orchestrator prepares the PR for the owner. Proposed job:
```yaml
  tendingestion-linux:
    name: TendIngestion swift test (Linux)
    runs-on: ubuntu-latest
    container: swift:6.2-noble
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Toolchain version
        run: swift --version
      - name: Test TendSourceScan
        shell: bash
        run: |
          if [ ! -f Packages/TendSourceScan/Package.swift ]; then echo "::notice::TendSourceScan not present yet"; exit 0; fi
          swift test --package-path Packages/TendSourceScan -Xswiftc -warnings-as-errors 2>&1 | tee tendsourcescan-test.log
          exit "${PIPESTATUS[0]}"
      - name: Build TendIngestion (warnings are errors)
        shell: bash
        run: |
          if [ ! -f Packages/TendIngestion/Package.swift ]; then echo "::notice::TendIngestion not present yet"; exit 0; fi
          swift build --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors
      - name: Test TendIngestion
        shell: bash
        run: |
          if [ ! -f Packages/TendIngestion/Package.swift ]; then exit 0; fi
          swift test --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors 2>&1 | tee tendingestion-test.log
          exit "${PIPESTATUS[0]}"
      - name: Build tools
        shell: bash
        run: |
          if [ ! -f Tools/TendTools/Package.swift ]; then exit 0; fi
          swift build --package-path Tools/TendTools -Xswiftc -warnings-as-errors
      - name: Upload test logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: tendingestion-linux-test-logs
          path: "*-test.log"
          if-no-files-found: ignore
```
- The "not present yet" guards let HM-1 merge before WI-M2-01. They are the same vacuous-pass risk as M1 R-6, so the
  Reviewer and Gatekeeper confirm from the log that the tests ran (count > 0) on every Phase A PR.
- **HM-1b (optional, owner merge, after WI-M2-15):** remove the guards so a missing package fails CI.
- The job must never build `Packages/TendAI`.
- The 30-minute timeout covers the M2 property tests (≥ 1,000 + 3 × ≥ 500 households). If a PR's runtime gets close,
  the Developer reports it; the counts the ACs need are never lowered (R-18).

**HM-2 (needed before the first Mac PR merges, MS-1). Status: proposed D-032, needs a human-merged governance PR.**
No CI lane builds `TendAI`, `project.yml` or `TendEval` (Q8: no paid macOS runner). Under G3, the Gatekeeper cannot
merge a Mac-only PR on Linux CI alone. The PO recommends this rule (2026-11-21):
- **The owner merges** every Mac-only PR (a human merge).
- The PR carries an owner-run **Mac evidence record for its exact head commit**. A record for any other commit does not
  count; a new push needs a new record.
- The Gatekeeper reviews the PR and gives **`APPROVE` on every rule except G3**. G3 is the one rule it cannot check on
  Linux CI, so the Mac evidence record and the owner's merge stand in for it.
- The Mac PRs of one session may be merged together at its end, each with its own record.
This rule is not in force until it is recorded as **D-032** in `DECISIONS.md` (and, if needed, in
`.claude/skills/merge-gatekeeper`). Both are protected paths, so this needs a governance PR that the human owner merges.

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-1 | On-device TTFI is ≥ 1.5 s on the iPhone 15 Pro (schema size, instructions, a `Tool` round trip before the first item) | M | H | Mac probe in MS-1; optional device spike SP-1 in MS-2; compact `@Generable` schema with `title` first; prewarm on capture start; measure the `Tool` call's cost and keep the shortlist small. AC-M2-16 is never relaxed; a miss goes back to the PO. | Developer |
| R-2 | On-device accuracy falls below the Q3 thresholds (small model) | M | H | Tune instructions against a Developer dev set that is **not** the frozen eval; the Tester runs an exploratory charter with unseen inputs (R-19). | Developer; Acceptance Tester |
| R-3 | Context window: long dumps + schema + instructions + tool output exceed the on-device limit | M | M | Eval inputs are ≤ 80 words (Q3); log token counts in dev notes; "context too long" maps to the calm `noModel` (AC-M2-10). | Developer |
| R-4 | `PartiallyGenerated` snapshot order does not match the item-completion rules (fields arrive in declaration order; arrays grow) | M | M | WI-M2-06 is defined over neutral snapshots; WI-M2-M2 maps and tests every snapshot shape; Linux stream tests are the oracle. | Developer |
| R-5 | Cloud TTFI ≥ 3.0 s (model reasoning or thinking tokens, structured-output warm-up, network) | M | H | Q18 models are approved only with no reasoning tokens (Gemini thinking budget 0) and temperature 0; the real recordings in MS-2 give an early timing; the run record holds a speed test (Q15). Q18 conditions 4 and 5 revised 2026-11-23 (PO WI-M2-10 ruling 7): lowest documented reasoning level, fixed; AC-M2-27 measured in the dev-set run. | Developer |
| R-6 | Provider APIs, model names or data terms change before the device run | M | M | Curated list per release; the Developer re-checks at WI-M2-10 and the Reviewer against current docs; a change goes to the PO (golden bytes under a PO decision). | Developer; PO |
| R-7 | `SpeechTranscriber` is not supported on A15, or speech assets are missing in airplane mode | M | M | `DictationTranscriber` fallback, with the transcriber recorded (AC-M2-25); DS-1 and DS-2 preconditions download the assets online first. | Developer; Acceptance Tester |
| R-8 | The T-27 answer is unclear from the Simulator alone | M | L | MS-1 records the docs and the Simulator result; DS-1 and DS-2 confirm the permission prompt on device; if the rule changes, the scope table and this plan are updated. | Developer |
| R-9 | Keychain tests fail in the Simulator host (`errSecMissingEntitlement`, signing) | M | M | A dedicated `TendAITestHost` with a keychain access group, "Sign to Run Locally"; attributes read back with `kSecReturnAttributes`. | Developer |
| R-10 | Linux and Darwin Foundation differ (string folding, sorting, JSON, `Calendar` DST) | M | H | Own canonical JSON writer; folding with fixed `en_US_POSIX`; B1 and B2 rerun every Linux suite on Darwin in MS-2 and MS-3; any difference is a defect, not a skip. | Developer |
| R-11 | HM-1 is not merged, so G3 blocks every Phase A merge | H | H | HM-1 is the first owner item; work continues on branches meanwhile. | Orchestrator → owner |
| R-12 | Mac PRs cannot pass G3 (no macOS CI) | H | M | HM-2 rule (proposed D-032): owner merges, with a Mac evidence record for the exact head commit; Gatekeeper `APPROVE` on all rules except G3. Needs a human-merged governance PR. | Orchestrator → owner |
| R-13 | Owner time becomes the bottleneck (3 Mac sessions, 2 device sessions, keys, API cost of 3 × 20 inputs plus recordings) | M | H | Sessions are grouped and booked ahead; scripts and commands are ready before each session; Remote Control for everything except keys and phones. | Orchestrator |
| R-14 | The free signing profile expires (7 days) or Developer Mode is off on a phone | M | L | Install in MS-3 within 7 days of DS-1 and DS-2; B7 can be rerun in minutes. | Human owner |
| R-15 | Owner answers to Q12, Q16 or Q17 arrive after WI-M2-10, so the golden requests and runs change | M | M | Ask before WI-M2-10 starts; the effect is written down in the brief; regenerate under a PO decision before the freeze. | PO → owner |
| R-16 | Scanner false positives or misses (Rule 3 whole-identifier rule, Rule 4 whole-literal regex), or the two lexers drift (M1 copy and `TendSourceScan`) | M | H | N-1 and T-30 near-miss tests; the Reviewer inspects the rule engine; the M1 copy is unchanged in M2 and a later chore unifies them. | Developer; Reviewer |
| R-17 | Eval code leaks into shipped modules, or `TendEval` ships | L | H | AC-M2-28 `project.yml` scan, B6 Release and Archive check, the Reviewer checks that no pipeline code references the eval namespace. | Reviewer |
| R-18 | Property tests (≥ 1,000 mappings, ≥ 500 households ×3 providers for sentinels, ≥ 500 for duplicates and commit) are too slow for CI | M | M | Seeded fast RNG, no quadratic oracles; runtime in every dev note; counts never lowered; raise the CI timeout through the owner if needed. | Developer |
| R-19 | Prompts get over-fitted to the frozen eval, so the gate passes but real use is weaker | M | M | A separate dev set; the Tester's unseen-input charter; prompt changes after the freeze are listed in dev notes. | Developer; Acceptance Tester |
| R-20 | An iOS or model update between MS-3 and the device runs changes results | L | M | Record the iOS build in each run; do not update iOS during the gate; a change means a new run, recorded. | Human owner |
| R-21 | The incremental JSON reader for partial provider streams is harder than estimated | M | M | WI-M2-12 is isolated and fixture-driven; split it into SSE framing and the JSON reader if it runs past one round. | Developer; Work Planner |
| R-22 | The hand-written results-file conformance check drifts from `results-v1.schema.json` | M | M | A test maps every schema constraint to a check; the Tester reviews the schema with the fixtures. | Developer; Acceptance Tester |
| R-23 | WI-M2-11, 13 and M6 are at the 1-day limit | M | M | If one runs past one round, split it (sentinels vs structural; one dialect per PR; adapters vs recordings). The ACs stay the same. | Work Planner |
| R-24 | Planner proposals P1–P7 in the Q6 table are product meaning | L | M | Closed 2026-11-21: the PO acknowledged P1–P7, with the P3 change (T10, E15, E16). The Tester's Q6 review is done (APPROVED 2026-11-21). | PO |

## Verification environments

| AC | Where it can be proven | Owning item |
|---|---|---|
| AC-M2-01 | Linux | WI-M2-05 |
| AC-M2-02 | Linux | WI-M2-05 |
| AC-M2-03 | Linux | WI-M2-03 |
| AC-M2-04 | Linux | WI-M2-04 |
| AC-M2-05 | Linux (stream assembly) + owner-run Mac B4 (`PartiallyGenerated` mapping) | WI-M2-M2 |
| AC-M2-06 | Linux | WI-M2-08 |
| AC-M2-07 | Linux (rules, shortlist, collapse) + owner-run Mac B4 (`Tool` conformance) | WI-M2-M2 |
| AC-M2-08 | Linux | WI-M2-08 |
| AC-M2-09 | Linux (scan over the three roots) + Reviewer | WI-M2-01 |
| AC-M2-10 | Linux (neutral reasons) + owner-run Mac B4 (exhaustive availability and error mapping) | WI-M2-M2 |
| AC-M2-11 | **Device** DS-1, iPhone 15 Pro (AWAITING-DEVICE) | WI-M2-D1 |
| AC-M2-12 | Linux | WI-M2-04 |
| AC-M2-13 | Linux CI (a) + owner-run Mac B1, B2, B4, B5 (b), on the M2 merge commit | WI-M2-M8 |
| AC-M2-14 | Linux (scorer self-tests, composition check) + Tester review and re-score | WI-M2-16 |
| AC-M2-15 | **Device** DS-1; scored on Linux (AWAITING-DEVICE) | WI-M2-D1 |
| AC-M2-16 | **Device** DS-1 (AWAITING-DEVICE) | WI-M2-D1 |
| AC-M2-17 | **Device** DS-1; scored on Linux (AWAITING-DEVICE) | WI-M2-D1 |
| AC-M2-18 | Linux (consent, route, cancel, in-memory key store) + owner-run Mac B5 (real Keychain delete) | WI-M2-M5 |
| AC-M2-19 | Linux | WI-M2-09 |
| AC-M2-20 | Linux + owner-run Mac B2 (golden bytes) | WI-M2-11 |
| AC-M2-21 | Owner-run Mac B5 (Simulator host) + Reviewer | WI-M2-M5 |
| AC-M2-22 | Owner-run Mac B5 (`URLProtocol`, redirects) + Linux (deadline and retry arithmetic) | WI-M2-M4 |
| AC-M2-23 | Linux (outcomes, plain note, retry decisions) + owner-run Mac B5 (`URLError` and status mapping) + Reviewer | WI-M2-M4 |
| AC-M2-24 | Linux (three parsers, re-check) + owner-run Mac B4 (adapters end to end over fixtures) | WI-M2-M6 |
| AC-M2-25 | **Device** DS-2, iPhone 13 (AWAITING-DEVICE) | WI-M2-D2 |
| AC-M2-26 | **Device** DS-2; scored on Linux (AWAITING-DEVICE) | WI-M2-D2 |
| AC-M2-27 | **Device** DS-2 (AWAITING-DEVICE) | WI-M2-D2 |
| AC-M2-28 | Linux (`project.yml` scan, schema and rejection tests) + owner-run Mac B6 + Reviewer | WI-M2-M7 |

The seven device ACs are flagged now so the Tester can write DS-1 and DS-2 in `acceptance.md` early, in parallel with
Phase A, not at the end.

## Design need

- **WI-M2-02** needs the Designer to name the new `TaskInvariantViolation` case and its position (brief Q9). That is a
  short naming addendum in `docs/milestones/M2/design.md`, not a full spec.
- Optional, advisory: the Designer may review the outcome and reason case names that WI-M2-06, 09 and 14 introduce
  before M3 copy is written. The Reviewer's banned-token and "blames nobody" check is binding either way.
- No other M2 item has UI, copy, haptics, notifications, widgets or Live Activities. `TendEval` screens are a debug
  tool (brief). The Settings, consent and key-entry screens are M3.

## Definition of Ready check

| Check | 01 | 02 | 03 | 04 | 05–15 | 16 | M1 | M2–M6 | M7, M8 | D1, D2 |
|---|---|---|---|---|---|---|---|---|---|---|
| Cites requirement IDs and AC IDs | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ |
| ACs testable, verification type known | ☑ | ☑ | ☑ Q6 review APPROVED 2026-11-21 | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ (DS scripts pending) |
| Design spec `Ready` (if UI, copy or naming) | n.a. | ☐ name | n.a. | n.a. | n.a. | n.a. | n.a. | n.a. | n.a. (debug tool) | n.a. |
| Dependencies merged or stubbed | ☑ | ☑ | ☐ WI-01 | ☐ WI-01 | ☐ per table | ☐ WI-15, 11, fixtures | ☐ WI-01 | ☐ per table | ☐ all | ☐ M8, scripts, Q20 |
| Size ≤ 1 day; owner; branch | ☑ | ☑ | ☑ | ☑ | ☑ (R-23) | ☑ | ☑ | ☑ (R-23) | ☑ | ☑ |
| Milestone lock (M1 `ACCEPTED`) | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ | ☑ |
| Owner condition | merge needs HM-1 | — | ☑ PO ack P1–P7 (2026-11-21) | — | WI-10: ☑ Q18 approved with 5 conditions; Q12/16/17 asked | PO composition approval | MS-1 booked; HM-2 | MS-2 booked; keys | MS-3 booked | Q16, Q20, keys |

**Build start:** **WI-M2-01 is Ready now** and can be built in this container. Its PR can merge only after HM-1. No
other DoR problem was found. All other items fail only the boxes shown, and each becomes Ready when they are met.

## Owner and other-role actions (summary)

| # | Action | Who | Needed before |
|---|---|---|---|
| HM-1 | Merge the CI job above (`.github/workflows/ci.yml`) | Human owner (Orchestrator prepares) | WI-M2-01 merge |
| HM-2 | Merge the governance PR that records proposed D-032 (owner merges Mac-only PRs with a Mac evidence record for the exact head commit; Gatekeeper `APPROVE` on all rules except G3) | PO prepares, human owner merges | MS-1 merge |
| O-1 | Merge D-031 (`DECISIONS.md`) and the `STATUS.md` change to M2 `IN-BUILD` | PO prepares, owner merges | WI-M2-01 merge |
| O-2 | Answer Q12 (titles for cloud duplicates), Q16 (which providers gate M2), Q17 (Gemini free tier), or confirm the PO defaults | Human owner | WI-M2-10 start |
| O-3 | Q20: name the signing team (a free personal team is enough; 7-day profile) | Human owner | MS-3 |
| O-4 | Book MS-1, MS-2 (about 20 min in person for keys, optional iPhone 15 Pro for SP-1) and MS-3 (both iPhones) | Human owner | each session |
| O-5 | Provider keys for the recordings (MS-2) and the DS-2 runs; the API cost of 3 × 20 inputs | Human owner | MS-2, DS-2 |
| O-6 | Run DS-1 and DS-2 | Human owner | gate |
| R-a | Review the Q6 table — **done, APPROVED 2026-11-21** (3 non-blocking findings applied: E17–E21, T9/T14 daypart rule) | Acceptance Tester | WI-M2-03 |
| R-b | Approve the eval composition (P1–P7 and the Q18 list are done, 2026-11-21) | Product Owner | WI-M2-16 |
| R-c | Name the new invariant case | iOS Designer | WI-M2-02 |
| R-d | Write the fixtures and golden set; review the key-path lists and golden requests; write DS-1 and DS-2 | Acceptance Tester | WI-M2-16; first device run |
| R-e | ADR-0005's status line still says `Proposed`, though PR #11 merged it (the owner's approval). Update it to `Accepted` | Product Owner | when convenient |

## Law check

| Law | Status (pass / n.a. / concern) | Note — items reviewers should watch |
|---|---|---|
| UX-1 Zero-Form Entry | pass (watch) | Capture is one text or one utterance; every field is inferred (WI-M2-03…05). Watch WI-M2-M7: the harness's debug fields must not become a pattern for a product "new task" form. The plain note is one free-text draft (WI-M2-06). |
| UX-2 Rule of Three | pass (watch) | No item adds a "what to do now" API. Watch WI-M2-06 and 08: the draft stream and commit must not expose a "candidates" or "next up" list. Committed tasks reach Now only through `NowSelector`; the M1 suite stays green (AC-M2-13). |
| UX-3 Zero-Guilt | pass (watch) | Calm-words guard (WI-M2-04); case names checked (WI-M2-06, 09, 14, M2, M4). Watch the failure and outcome names (no "failed", "missed", "late"), the time resolver (no "overdue" or "past-due" helper in WI-M2-03), and any count of how often a capture was retried. |
| UX-4 Design craft | n.a. | No product UI in M2. `TendEval` is a never-shipped debug tool (brief). The `Tend` target is a build skeleton with no UI. |
| P-1 On device first | pass (watch) | Route matrix (WI-M2-09). Watch WI-M2-M2 and M4: an on-device error must never call the cloud. Speech always on device (WI-M2-M3; no `SFSpeech*` except the T-27 exception, if confirmed). |
| P-2 Data leaves only via iCloud or a P-3 request | pass (watch) | Networking only in the three allowlisted files (WI-M2-M4, M5), three fixed hosts, no SDKs (AC-M2-09). Watch `Tools/TendTools` (Linux tool only, never linked into an app) and the recording step (`curl` on the Mac, run by the owner, response only). |
| P-3 Cloud AI opt-in and minimised (ADR-0005) | pass (watch) | Payload builder input type is `String`/`[String]` only (WI-M2-10); sentinel and structural proof (WI-M2-11); Keychain only (WI-M2-M5); off by default and orphan-key deletion (WI-M2-09). Watch any new request field (needs a new ADR) and the Gemini `key=` query ban. Owner questions Q12, Q16, Q17 open (O-2). |
| P-4 Media not persisted | pass (watch) | Audio stays in memory in the speech adapter files (WI-M2-M3); no background queue (WI-M2-14); the results writer is the only write path in `TendEval` and holds no audio, bodies, headers or keys (WI-M2-M7). Watch recorded provider fixtures for headers or keys (WI-M2-M6). Privacy Manifest ships with the app target in M3. |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-21 | Acceptance Tester → Product Owner | Work Planner | accepted (H1) | Brief Draft v4 with the testability tick (`580d23e`, recorded at `29e2d74`). 10 stories, 28 ACs, all citing FR/UX/P IDs, all with an environment and evidence. The Tester's "before DoR" conditions are answered in this plan: the Q6 table (for the Tester's review), the allowlist, speech, speech-permission and results-writer paths, the exact `xcodebuild` commands, the scoring tool and command, the harness ID generator, and the T-27 check as an early Mac item (WI-M2-M1). Nits N-1…N-3 are in WI-M2-01 and WI-M2-10 scope. Milestone lock satisfied (M1 `ACCEPTED`). |
| 2026-11-21 | Work Planner | Acceptance Tester | sent for review | The Q6 table (T1–T15, R1–R7, and the worked examples, now E1–E21), including Planner proposals P1–P7 and the T11 "+7 days" reading (now a PO decision). This is the DoR condition for WI-M2-03 (AC-M2-03). |
| 2026-11-21 | Work Planner | Product Owner | sent | Please acknowledge P1–P7, approve the Q18 model list before WI-M2-10, set M2 to `IN-BUILD` and prepare D-031 (O-1), and update ADR-0005's status line. |
| 2026-11-21 | Work Planner | iOS Designer | sent | Name the non-finite-date `TaskInvariantViolation` case and its position (WI-M2-02, Q9). |
| 2026-11-21 | Work Planner | Developer (via Orchestrator) | sent (H2) | 16 Linux items, 8 owner-run Mac items in 3 sessions, 2 device items; every AC owned once. **WI-M2-01 is Ready now** (`m2/ingestion-foundation`); its merge needs HM-1. |
| 2026-11-21 | Work Planner | Orchestrator → human owner | sent | HM-1 (CI job), HM-2 (Mac PR merges), O-1…O-6. |
| 2026-11-21 | Product Owner | Work Planner | accepted | PO decisions applied: P1–P7 acknowledged; P3 changed ("this week" on a Sunday at or after 18:00 means next week; T10, E15, E16); T11 is 7 calendar days; Q18 models approved with five conditions (current, pinned snapshot ID, structured streaming, temperature 0, no reasoning tokens with Gemini thinking budget 0; WI-M2-10, WI-M2-M6); HM-2 recommended rule recorded as proposed D-032 (needs a human-merged governance PR). No AC changed (AC-M2-03, 20, 24, 27). |
| 2026-11-21 | Work Planner | Acceptance Tester | sent for review | Please include the changed T10 row and E15, E16 in the Q6 review (WI-M2-03 DoR, AC-M2-03). |
| 2026-11-21 | iOS Designer | Work Planner | accepted | WI-M2-02 case named `windowDateNotFinite`, no associated value, after `noAllowedWeekdays` and before `windowEndNotAfterStart` (recorded as `design.md` Addendum A). |
| 2026-11-21 | Product Owner | Work Planner | accepted | WI-M2-02 store errors (Q9, W2-F3): `unreadableFile` is acceptable for a hand-written non-finite file; the stores may throw different errors for values set through internal setters; AC-M1-07 unchanged; the in-memory all-invariants guard is in scope. Needs a DECISIONS.md entry (human merge). |
| 2026-11-21 | Work Planner | Orchestrator → Product Owner, human owner | sent | HM-2: prepare and merge the D-032 governance PR before the first Mac PR merges (MS-1). |
| 2026-11-21 | Acceptance Tester | Work Planner | accepted | Q6 table APPROVED with 3 non-blocking findings. Applied: E17, E18 (T11 across DST, 169 h / 167 h), E19 (T4 "tonight" after midnight), and the PO decision on finding 2 (T9 and T14 with a daypart; E20, E21). No AC meaning changed (AC-M2-03). WI-M2-03 DoR: Q6 review box ticked. All new UTC values checked with Python `zoneinfo` (America/New_York). The PO logs the daypart decision in `DECISIONS.md` as a separate entry with its own number, in the same human-merged governance PR as D-032. |
| 2026-11-21 | Product Owner | Work Planner | accepted | PO 2026-11-21, stricter only, from the PR #15 review: M2 Q23 and Q24 (AC-M2-09; AC-M1-23 cross-reference). Added the fixtures loader to "Named files", the Developer constraint (no `data(for:`/`data(from:` method names; unlisted Rule 6 imports go to the PO) and the timing: Q24 in WI-M2-01 round 2 or a follow-up before WI-M2-M4/M7 review; Q23 in a follow-up before WI-M2-M7 review; WI-M2-01 round 2 stays strict. Fixed two Gatekeeper minors from PR #14: R-24 now records the Tester's Q6 review as done; the daypart decision is its own `DECISIONS.md` entry in the D-032 governance PR. No AC changed. |
| 2026-11-21 | Product Owner | Work Planner | accepted | Tester returned PR #16 (findings 1-9); PO accepted all, stricter only. Applied the v2 texts: the fixtures loader row now says "bundle resources named by string literals only"; the v1 `data(for:`/`data(from:` constraint is replaced in WI-M2-01 and WI-M2-M5 by the session-method name rule, the literal-only fixtures rule and the import rule; the DECISIONS.md wording for Q23/Q24 is recorded. Timing unchanged. No AC changed. |
| 2026-11-21 | Developer | Product Owner | answered | Q-T1, Q-T2 answered (FR-A1, Q5, Q6, UX-3). |
| 2026-11-21 | Product Owner | Work Planner, Acceptance Tester, Developer | accepted | Plan text applied: R5 row, the note under the repeat table, and the invalid-anchor bullet (PO Q-T1 / Q-T2, 2026-11-21); E22–E26 added (UTC checked with Python `zoneinfo`, America/New_York); WI-M2-03 test scope is E1–E26. Tester confirms the changed rows before PR #18 review; Developer reworks PR #18. No AC wording changed (AC-M2-03). The `DECISIONS.md` entry "PO Q-T1 / Q-T2, 2026-11-21, M2 Q6 table" goes in the human-merged governance PR. |
| 2026-11-21 | Acceptance Tester | Work Planner | accepted | Q-T1/Q-T2 rows APPROVED with 3 findings, applied: `basis` defined as a diagnostic field (used by WI-M2-05 for the AC-M2-02 repair counts, not part of the AC-M2-03 table check; technical choice); the resolver returns ∅ sets and WI-M2-05 fills the Q5 step-3 defaults after step 5; E22–E25 labelled "resolver output", E26 "after Q5 settlement" with dayparts → `Daypart.defaultAllowed` (morning, afternoon, evening), checked against brief Q5 step 3 and `Daypart.swift`. No AC changed (AC-M2-02, AC-M2-03). |
