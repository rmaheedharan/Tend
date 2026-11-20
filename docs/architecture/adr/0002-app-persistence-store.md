# ADR-0002: App persistence store with CloudKit household sharing in mind

- **Status:** Proposed (decision direction only; no adapter ships in M1. To be confirmed by a macOS/Xcode 26 spike before the
  first app-store adapter is built in M3, and before M5 sharing work)
- **Date:** 2026-11-20
- **Deciders:** Developer (proposer); Reviewer; Product Owner informed (FR-E1 scope)
- **Requirements:** FR-B1, FR-B2 (data must survive restart, S-M1-02), FR-E1 (multi-person household sync over iCloud,
  M5), P-2 (no data leaves the device except via the user's own iCloud, with encrypted fields for sensitive data); brief
  Q9; CLAUDE.md §3 "Persistence & sync"

## Context
- M1 ships only the `HouseholdRepository` protocol with an in-memory store and a Foundation-only JSON file store in
  `TendCore` (WI-M1-02, ADR-0001). Those stores are enough to prove AC-M1-04…07 on Linux.
- The app (M3 onward) needs a production store on iOS 26. In M5 that store must sync a household between family
  members' devices through **CloudKit shared databases (`CKShare`)** (FR-E1).
- Sync must use the user's own iCloud with encrypted fields for sensitive data (P-2). Conflict resolution must be
  deterministic, and a completion must never be lost (developer skill, persistence playbook).
- Whatever is chosen must stay behind `HouseholdRepository`, so `TendCore` and its tests never see it.
- **Environment limit:** this container is Linux. Nothing below was verified against the iOS 26 SDK. The statements about
  framework capabilities reflect the published behaviour of the frameworks up to iOS 18. A Mac spike must re-check them
  against the iOS 26 documentation before this ADR becomes `Accepted`.

## Options considered
1. **SwiftData with its built-in CloudKit sync.**
   - Pros: modern Swift API; integrates with SwiftUI.
   - Cons: built-in CloudKit sync has supported only the user's **private** database, not shared databases or `CKShare`,
     so FR-E1 could not be met without a second sync path. There is little control over conflict merging.
   - Rejected unless the spike shows that iOS 26 SwiftData supports shared databases with per-record control.
2. **Core Data with `NSPersistentCloudKitContainer` (private and shared stores).**
   - Pros: first-party support for private **and shared** CloudKit databases, including creating and accepting shares.
     It supports encrypted attributes for sensitive fields (P-2). It is mature and well documented.
   - Cons: an older API needs mapping code between managed objects and `TendCore` values. Merges are object- and
     attribute-level policies; domain merges (for example "completions are never lost") have to be designed into the
     schema, for example append-only completion records, rather than written as merge code.
3. **A local store of our own (Core Data or the `TendCore` JSON file) plus `CKSyncEngine`.**
   - Pros: full control of record mapping and conflict resolution (per-field last-writer-wins with logical clocks;
     domain merge for completions). Works with private and shared databases.
   - Cons: we write and own the sync state machine, record mapping, share management and the migration story. This
     is the most code and the most test surface.
4. **Third-party sync or database SDK.** Rejected: CLAUDE.md forbids new dependencies without strong reason, and P-2
   rules out third-party data paths.

## Decision
Proposed direction: **option 2, Core Data with `NSPersistentCloudKitContainer`**, behind `HouseholdRepository` in a
`TendPersistence` module, with **option 3 (`CKSyncEngine`) as the named fallback**.

Design rules now, so that M3 and M5 do not paint us into a corner:
- Model completions as **append-only records** (task ID, completion instant, device), merged by union, so a completion
  can never be lost to a last-writer-wins overwrite. This needs a WI-M5 design; `TendCore`'s model is not changed by
  this ADR.
- Keep the D-2 rule in the store: no reschedule counters or original-window columns. A store schema may not reintroduce
  what the domain model forbids.
- Sensitive fields (titles, notes) use CloudKit encrypted fields.
- `HouseholdRepository` stays the only interface the engine and the UI use. The JSON file store remains the reference
  implementation for contract tests (AC-M1-04).

We pick option 2 because it is the only first-party path that offers shared databases without writing a sync engine,
and because it supports encrypted fields. If the spike shows that `NSPersistentCloudKitContainer` cannot meet the
"completions are never lost" rule or deterministic merge in practice, we switch to option 3. The repository protocol
keeps that switch local.

## Consequences
- Positive: M1 is unaffected (no adapter ships). M3 has a clear default. M5 has a first-party sharing path.
- Negative: Core Data mapping code is needed in `TendPersistence`. Sync behaviour cannot be tested on Linux; it needs
  Simulator and device runs (M5 is a device gate).
- Follow-up:
  1. A macOS spike before the M3 adapter: confirm SwiftData's sharing status on iOS 26, and confirm private + shared
     stores, share accept and encrypted attributes with `NSPersistentCloudKitContainer`.
  2. Move this ADR to `Accepted` or switch to option 3.
  3. Record the CloudKit schema and the conflict rules in an M5 ADR.
- We would know this was wrong if two devices completing the same task offline can lose one completion, or if the
  shared-store setup cannot be tested deterministically.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Storage only. |
| UX-2 Rule of Three | n.a. | Selection stays in `TendCore`; the store never returns "what to do now" lists to views. |
| UX-3 Zero-Guilt | pass (rule) | The store schema must not add counters, original windows or history (design D-2). |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No AI. |
| P-2 No data leaves device (except user iCloud) | pass (rule) | Only the user's own iCloud (CloudKit private and shared databases), with encrypted fields for sensitive data. No third-party SDK. |
| P-3 Cloud escalation | n.a. | No model inference involved. |
| P-4 Media not persisted | n.a. | No media stored by this decision. |
