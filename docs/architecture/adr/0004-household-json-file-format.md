# ADR-0004: Household JSON file format, exact dates and atomic save in `TendCore`

- **Status:** Proposed (Developer, WI-M1-02; the Reviewer confirms in the WI-M1-02 review. Reversible: the file carries
  a schema version)
- **Date:** 2026-11-20
- **Deciders:** Developer (proposer); Reviewer
- **Requirements:** FR-B1, FR-B2, P-2; S-M1-02; AC-M1-04, AC-M1-05, AC-M1-06, AC-M1-07, AC-M1-25; plan risks R-7 and R-8;
  ADR-0001 (Foundation only)

## Context
- WI-M1-02 ships `JSONFileHouseholdRepository`, a Foundation-only file store. It must:
  - round-trip dates exactly, including sub-second parts (AC-M1-05);
  - reject an unknown schema version with a typed error (AC-M1-06);
  - never leave a partial or empty file when a save fails part-way (AC-M1-07).
- **R-7.** The `JSONEncoder` ISO-8601 date strategy drops everything below a second.
- **R-8.** Atomic replace behaves differently on Linux. We probed Swift 6.2.4 on Linux in the container:
  - `FileManager.replaceItemAt(_:withItemAt:)` **removed the original file and then threw** "file doesn't exist", which
    loses data.
  - `FileManager.moveItem(at:to:)` refuses to overwrite an existing file.
  - `Data.write(to:options: .atomic)` replaced the file with a new inode and left no staging file, which means it
    staged the bytes and renamed them over the file.
- `TendCore` may import only Foundation (AC-M1-23). It cannot call POSIX `rename(2)` directly. Since PO decisions
  Q17/Q18, file APIs such as `contentsOf:` are allowed only in `JSONFileHouseholdRepository.swift`.

## Options considered
1. **Dates as ISO-8601 strings with fractional seconds.**
   - Pros: readable.
   - Cons: `.iso8601` has no fractional seconds. A custom formatter rounds to a fixed number of digits, so it is not
     bit-exact. Rejected (R-7).
2. **Dates as `timeIntervalSinceReferenceDate` JSON numbers (`.deferredToDate`, written explicitly).**
   - Pros: Swift writes the shortest digits that read back to the same `Double`, so the round trip is bit-exact. It is
     also the encoding WI-M1-01's `Codable` model already uses.
   - Cons: not human-readable as a calendar date. A non-finite date cannot be encoded.
3. **Dates as the `Double` bit pattern (hex string).**
   - Pros: bit-exact by construction.
   - Cons: opaque. It needs custom `Codable` on every date field. Option 2 is already exact, so this is unnecessary.
4. **Atomic save with `replaceItemAt`.** Rejected: on Linux it can lose the original (R-8).
5. **Our own staging file plus `rename(2)`.** Rejected: it needs a libc call outside Foundation (ADR-0001, AC-M1-23).
6. **Atomic save with Foundation's `Data.write(to:options: .atomic)`, behind an injectable write seam.**
   - Pros: Foundation-only. It replaces by rename on Linux and Darwin.
   - Cons: we rely on Foundation for the rename step. Fault injection tests our code around that primitive, not the
     kernel rename itself.

## Decision
- **File:** one UTF-8 JSON object, the encoded `Household`:
  - `schemaVersion` is `1` (`Household.currentSchemaVersion`);
  - `tasks` and `rooms` are arrays;
  - keys are sorted (`.sortedKeys`), so the same household always gives the same bytes;
  - output is compact.
- **Dates:** option 2. Each date is a JSON number of seconds since 2001-01-01T00:00:00Z. The strategy is set
  explicitly on both the encoder and the decoder.
- **Loading:**
  1. A missing file means nothing has been saved yet, so `load()` returns an empty household.
  2. Otherwise, read the bytes, then decode only `schemaVersion`. If that fails, throw `unreadableFile`. If the version
     is not 1, throw `unsupportedSchemaVersion(v)`.
  3. Then decode the full household. A `TaskInvariantViolation` becomes `invalidTask(_)`; any other failure becomes
     `unreadableFile`.
  4. A load never writes.
- **Saving:** option 6.
  1. Reject a household whose `schemaVersion` is not current.
  2. Encode the whole household in memory. If encoding fails, throw `writeUnsuccessful`.
  3. Hand the complete bytes to `HouseholdFileWriter.write`, whose contract is "replace atomically or not at all".
     The standard writer is `.atomic`. The seam is `internal`, so only tests can replace it.
  4. Edits (`upsertTask`, `removeTask`, `updateRoom`) read, edit and save inside the actor. They write nothing if the
     read fails.
- **Local file URLs only (note added 2026-11-20, review W2-F1; P-2, brief Q19).** `init(fileURL:)` throws
  `unreadableFile` for any URL that is not a local file URL (for example `https:`, `http:`, `ftp:`, `data:` or a
  relative URL without a scheme). The check runs in the initialiser, before any read or write, so `Data(contentsOf:)`
  can never be handed a remote URL. This matters because, on Darwin, `Data(contentsOf:)` would fetch an `http(s)` URL
  over the network. Tests: `FileRepositoryLoadErrorTests` "W2-F1 / P-2: a repository refuses a URL that is not a local
  file URL before any read or write" and "W2-F1: a file URL from a path is accepted". The Acceptance Tester confirmed
  it independently (acceptance.md, charter C-4 (b)).

## Consequences
- AC-M1-05 is proven over 200 seeded households and awkward dates by comparing bit patterns. AC-M1-07 is proven by
  injected failures at three points, by a real encoding failure, and by an inode-change check on the standard writer.
- A non-finite `Date` passes the model invariants, but the file store cannot save it (`writeUnsuccessful`). The
  in-memory store accepts it. This is a known contract gap, Minor. A later item may add a finiteness check if the PO
  wants one.
- Two repository instances on the same file are not coordinated. The last save wins whole, and a file is never torn.
  The app uses one instance per file.
- **Future schema versions:** bump `currentSchemaVersion` and add an explicit migration step in `decode`. Today an
  older build reports `unsupportedSchemaVersion` and never overwrites a newer file through an edit.
- **Not verified on Darwin:** `.atomic` behaviour and number formatting were not checked there. The macOS lane (M3)
  should rerun the suite. Darwin's `replaceItemAt` is not used, so its behaviour does not matter here.
- **How we would know this was wrong:** a CI or device run where the R-8 inode test or AC-M1-07 fails, or a date that
  does not round-trip.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1…UX-4 | n.a. | No UI. Errors are codes only; M3 maps them to calm copy (design.md `store.error.*`). The file stores no lateness datum (D-2). |
| P-1 | n.a. | No AI. |
| P-2 | pass | The file is written only to a caller-supplied local URL. No networking (AC-M1-23). |
| P-3 | n.a. | No cloud. |
| P-4 | n.a. | No media. |
