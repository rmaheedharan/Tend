# ADR-0006: M2 module layout, canonical JSON, and the shared source-scan library

- **Status:** Proposed (Developer, 2026-11-21, WI-M2-01). The layout itself is fixed by the M2 plan ("Module and file
  layout"); this ADR records it and the technical choices made in WI-M2-01. It moves to Accepted when the Reviewer
  approves the WI-M2-01 PR. Each choice is reversible.
- **Date:** 2026-11-21
- **Deciders:** Developer (proposed), Reviewer (to confirm). Work Planner (the layout table in `plan.md`).
- **Requirements:** FR-A1; UX-2, UX-3; P-1, P-2, P-3, P-4; AC-M2-09 (owned by WI-M2-01), AC-M2-14, AC-M2-20, AC-M2-28;
  CLAUDE.md §3 (module boundaries, no dependency without an ADR); ADR-0001 (TendCore boundary); ADR-0005 (cloud AI);
  plan risks R-10, R-16.

## Context
M2 adds an ingestion pipeline on top of `TendCore` (ADR-0001). The brief (v4, Definitions) fixes three module names that
the AC-M2-09 source scan relies on:
- `TendIngestion` is platform-neutral: Foundation and `TendCore` only, and it builds and tests on Linux.
- `TendAI` holds the Apple-framework adapters and is Apple-only.
- `TendEval` is the debug-only eval harness.

Three technical questions came up before any M2 logic could be written:
1. Where do the packages live, and how does the scan find them?
2. How do we get request bodies and results files whose bytes are identical on Linux and Darwin? The AC-M2-20 golden
   requests are compared byte for byte, and the Mac rerun (plan B2) repeats them. `JSONEncoder` with `.sortedKeys` is
   not guaranteed to sort or escape the same way on swift-corelibs-foundation and on Darwin Foundation (R-10).
3. The AC-M2-09 scan needs the same comment- and string-aware Swift lexer that M1 built for AC-M1-23. In M1 that lexer
   lives in `TendCoreTests/Support`, where no other package can link it.

## Options considered
1. **Packages and layout**
   - (a) Separate SwiftPM packages under `Packages/` (the plan's table), each with its own manifest.
     - Pros: `TendIngestion` cannot import anything its manifest does not list. `swift test --package-path` runs each
       package on Linux. `TendAI` never has to build on Linux.
     - Cons: there are more manifests to keep in step.
   - (b) One multi-target package.
     - Pros: one manifest.
     - Cons: Linux CI would have to resolve the Apple-only `TendAI` target, or carry conditional target lists, and it is
       easier to grow an unintended dependency.
2. **Canonical JSON**
   - (a) A small hand-written writer over an explicit value type, with integers only.
     - Pros: we own every byte, the output is identical on every platform by construction, and it is simple to test with
       hand-written golden bytes.
     - Cons: it is our own code to review.
   - (b) `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`.
     - Pros: no new code.
     - Cons: the order and escaping are not specified across platforms, floating-point formatting differs, and
       `[String: …]` keys merge canonically equivalent strings.
3. **Lexer sharing**
   - (a) Move the lexer into a test-only library package, `TendSourceScan`. Leave the M1 copy untouched in M2.
     - Pros: one lexer for all M2 scans, and no accepted M1 test is edited.
     - Cons: there are two copies until a later chore unifies them (R-16).
   - (b) Copy the lexer into `TendIngestionTests`.
     - Cons: three copies, and the AC-M2-09 rules would sit in a test target, out of reach of later scans (for example
       the AC-M2-28 `project.yml` scan).
   - (c) Switch `TendCoreTests` to the library now.
     - Cons: it edits accepted M1 tests during M2. The plan defers this (R-16).

## Decision
- **1(a).** The packages are:
  - `Packages/TendIngestion`: library `TendIngestion`, depending on `../TendCore`. The test target `TendIngestionTests`
    depends on `TendIngestion` and `../TendSourceScan`.
  - `Packages/TendSourceScan`: a Foundation-only library with its own test target.
  - `Packages/TendAI`, `Apps/TendEval`, `Apps/Tend`, `Apps/TendAITestHost` and `Tools/TendTools` are created by later
    items at the paths in the plan table.

  All of them use tools 6.2, Swift 6 language mode and iOS 26 / macOS 26 platforms. They are our own local packages, so
  no third-party dependency is added (CLAUDE.md §6).
- **2(a).** `TendIngestion/JSON/CanonicalJSON.swift` defines `CanonicalJSON` (null, bool, integer, string, array,
  object with an ordered member list) and `CanonicalJSONWriter`. The output has:
  - keys sorted by UTF-8 bytes, with a duplicate key (equal bytes) as a typed error;
  - no whitespace;
  - only `"` and `\` escaped, plus `\b \t \n \f \r` and `\u00xx` (lower-case) for the other C0 controls;
  - `/` not escaped, and every other scalar written as raw UTF-8 with no normalisation;
  - integers only.
- **3(a).** `TendSourceScan` holds:
  - `SourceScanner`: the M1 lexer and the AC-M1-23 and AC-M1-02 matchers. It is public, parameterised by the allowed
    imports and the `contentsOf:` allowlist, and fails closed on an invalid regex.
  - `IngestionSourceRules`: the AC-M2-09 rule engine (Rules 1–6, the brief's closed lists, the file paths passed in as
    a configuration).

  The committed scope table (`ScanScope.swift`, which roots are required and the T-27 flag) lives in
  `TendIngestionTests`, as the plan says. `TendSourceScan` is linked only into test targets and never into an app or
  extension target. The AC-M2-28 `project.yml` scan (WI-M2-M7) will check this.
- **Scoring tool outside `TendIngestion/Sources`.** Rule 1 bans every file read and write and every log API in
  `TendIngestion` (T-26). The scorer therefore takes `Data` and returns a value, and the `tend-eval-score` executable that
  reads files and prints sits in `Tools/TendTools` (WI-M2-15).

## Consequences
- **Positive:**
  - `TendIngestion` can only see Foundation and `TendCore`, both in its manifest and in the scan.
  - Golden bytes do not depend on the platform's JSON encoder.
  - One lexer serves every M2 scan, and the scan's rule engine has its own planted-hit and near-miss tests.
- **Negative:**
  - There are two copies of the lexer (the M1 test copy and `TendSourceScan`) until the R-16 chore. A fix to one must
    be made in the other, and the Reviewer checks this.
  - The canonical writer has no floating point. A future need for decimals needs a decision (a fixed-point string or an
    integer of minor units).
  - Text folding uses Foundation's `folding(options:locale:)`, which may differ between platforms. The Linux results are
    pinned in tests (for example `ß` gives `ss`), and the Darwin rerun (B2) must match them.
- **How we would know this was wrong:**
  - B2 on the Mac gives different golden bytes or fold results;
  - the AC-M2-09 rule engine needs a case that the configuration cannot express;
  - or the two lexer copies drift.
- **Follow-ups:**
  - WI-M2-M1 switches the `TendAI` and `TendEval` roots to `required` and records the T-27 result.
  - A later chore points `TendCoreTests` at `TendSourceScan` (R-16).

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 | n.a. | No entry surface. |
| UX-2 | n.a. | No selection surface. The layout keeps `NowSelector` in `TendCore`, the only path to Now. |
| UX-3 | pass | The banned-token matcher lives in `TendIngestion` for the calm-words guard (AC-M2-12). |
| UX-4 | n.a. | No UI. |
| P-1 | pass | The on-device adapters stay in `TendAI`. The neutral layer has no inference and no networking (Rule 1). |
| P-2 | pass | No new dependency. Networking, including `contentsOf:` URL loading (only `append` / `insert` are exempt, per AC-M1-23 / Q23), is banned in `TendIngestion` (Rule 1), in `TendAI` outside the allowlist (Rule 2) and in `TendEval` (Rule 6). In the three allowlisted `TendAI` files, only the T-23 subset is allowed (Rule 3), and `contentsOf:` is outside it. M2 Q24 adds the session-method calls; the only one allowed is `bytes(for:` with `delegate:`, in the allowlisted files. `TendEval` has a closed import list. The scan enforces all of this. |
| P-3 | pass | The builder's provider table holds bare hosts only. `https://` hosts appear only in the allowlisted files (Rule 4). Request bodies are canonical bytes, which AC-M2-20 can check byte for byte. |
| P-4 | pass | There are no write or log APIs in `TendIngestion` or `TendAI` (Rules 1–3). `TendEval` writes only in its results writer (Rule 6). |
