# ADR-0001: `TendCore` is a Foundation-only, deterministic domain package

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** Developer (technical decision within CLAUDE.md §3; Reviewer to confirm in the WI-M1-01 review)
- **Requirements:** FR-B1, FR-B2, FR-B3 (data), UX-2, UX-3, P-1, P-2; AC-M1-01, AC-M1-02, AC-M1-22, AC-M1-23, AC-M1-24;
  CLAUDE.md §3

## Context
M1 builds the household engine before any UI or AI exists (brief "Outcome"). The engine must be proven on Linux in a cloud
container and in Linux CI (`swift:6.2-noble`, `-warnings-as-errors`), because no macOS, Xcode or device is available in M1.
The engine also carries two product laws in its types: the Rule of Three (UX-2) and Zero-Guilt (UX-3). Its results must
be reproducible: the same moment always gives the same answer (S-M1-06). Later milestones add on-device AI (M2), the
Liquid Glass UI (M3), system surfaces (M4) and CloudKit sharing (M5). None of those may leak into the engine.

## Options considered
1. **One app target with the engine inside it.** Pros: no package plumbing. Cons: cannot build or test on Linux;
   Apple frameworks would be reachable from engine code; laws would rely on reviewers alone.
2. **A pure SwiftPM package `TendCore` (Foundation only) plus adapter packages on top.** Pros: `swift test` on Linux and
   CI; a source-scan test can enforce the boundary (AC-M1-23); domain types stay `Sendable` values. Cons: adapters must
   map between framework types and domain types; Foundation behaviour on Linux (`swift-corelibs-foundation` /
   `swift-foundation`) can differ from Darwin in edge cases (calendar, DST, JSON number formatting).
3. **A pure package with no Foundation at all.** Pros: maximum portability. Cons: `Date`, `Calendar`, `TimeZone`, `UUID`
   and `Codable` JSON would have to be rebuilt by hand. That adds risk and gives no product benefit.

## Decision
We choose **option 2**.

- **Location:** `Packages/TendCore` (swift-tools-version 6.2, Swift 6 language mode, so strict concurrency is complete).
  It declares iOS 26 and macOS 26 platforms and builds on Linux. It has one library target `TendCore` and one test target
  `TendCoreTests` (Swift Testing).
- **Imports:** `TendCore` imports only `Foundation`. No `FoundationNetworking`, `Dispatch`, `Network` or Apple-only
  frameworks. This is enforced by the AC-M1-23 source scan, which runs on every PR.
- **Determinism:** engine logic never reads ambient state. `now`, `Calendar`, `TimeZone`, weather, energy and any
  `RandomNumberGenerator` are injected parameters. IDs are supplied by the caller (no `UUID()` in `Sources/`). The banned
  list is the closed list in AC-M1-23.
- **Value types:** every domain type is an `Equatable`, `Hashable`, `Codable`, `Sendable` value type. Model invariants
  (AC-M1-25) are checked in one throwing initialiser (typed throws, `TaskInvariantViolation`) that `init(from:)` also uses,
  so no invalid task can be built or decoded. Stored properties are `public internal(set)`: other modules can read but not
  mutate, so the invariants hold outside `TendCore`; engine code inside the module is responsible for its own output.
- **No copy in the engine:** `TendCore` emits codes (`TaskState`, `PromptTone`, later `RescheduleOutcome`). User-facing
  words live in the M3 String Catalog (design.md).
- **Future split:** adapters live in separate modules behind protocols with fakes:
  - `TendAI`: FoundationModels, Speech, Vision (M2, M4);
  - `TendPersistence`: the app store per ADR-0002, plus CloudKit in M5;
  - `TendUI`: SwiftUI and Liquid Glass (M3);
  - app, widget, Live Activity, Share and Intents targets (M3, M4).

  They depend on `TendCore`; `TendCore` depends on nothing of theirs. The `HouseholdRepository` protocol and its in-memory
  and Foundation-only JSON file implementations live in `TendCore` (WI-M1-02), because they need only Foundation.

## Consequences
- Positive: every engine AC is provable with `swift test --package-path Packages/TendCore` on Linux (plan "Verification
  environments"). The laws are checked by tests on every PR, not by memory.
- Negative: Linux Foundation and Darwin Foundation may differ in calendar and DST edge cases (plan R-3). This needs a
  macOS CI job or an Xcode run once the app target exists (M3). That run is not available in M1, and the dev notes say so.
- Negative: callers must pass `now`, calendar and time zone explicitly. This is intended.
- Follow-up: add a macOS CI lane when the app target exists (M3, ADR-0003). Add adapter packages per the split above.
- We would know this was wrong if an engine feature truly needed an Apple-only framework. In that case the feature goes
  behind a protocol in an adapter, and the boundary stays.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. The task initialiser has defaults for all optional data; it is a programmatic API, not a form. |
| UX-2 Rule of Three | pass | The engine owns the 3-cap type (`NowSelection`, WI-M1-03); views consume it. |
| UX-3 Zero-Guilt | pass | The closed lifecycle set and the banned-vocabulary scan (AC-M1-02) live in the engine package and run on every PR. |
| UX-4 Design craft | n.a. | No UI in the engine. |
| P-1 On-device inference | pass | The engine has no AI and no network; AI adapters are on-device modules (M2). |
| P-2 No data leaves device | pass | No networking API can be used in `TendCore` (AC-M1-23 scan). |
| P-3 Cloud escalation | n.a. | No cloud path. |
| P-4 Media not persisted | n.a. | No media in the engine. |
