# Changelog

All notable changes to Tend. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/). Owned by the Product Documenter.

Versioning note: the app has not shipped. Milestones are recorded as pre-1.0 versions (`0.<milestone>.0`). A version
gets a date only when the Product Owner accepts its milestone gate in `docs/milestones/STATUS.md`.

## [Unreleased]

### Added
- Project operating model, role skills and agents, and the PRD.

## [0.1.0] — M1 Core Engine & Cognitive Shielding (gate pending PO sign-off)

Engine only. No app, UI or AI yet. Verified on Linux (container and CI, Swift 6.2): 127 tests in 17 suites, 0
warnings, on `main` at `6fff92c`.

### Added
- `TendCore`, a Foundation-only Swift package at `Packages/TendCore` that builds and tests on Linux (ADR-0001;
  AC-M1-23, AC-M1-24; P-1, P-2).
- Household model: tasks (one-off, recurring, restock) with effort, critical / deep-clean / weather flags, allowed
  dayparts and weekdays, a window and a lifecycle state; rooms with `lastTendedAt`; nine model invariants checked at
  construction and on decode (FR-B1, FR-B2, FR-B3 data; AC-M1-01, AC-M1-25).
- A closed lifecycle with no debt state: `active`, `deferred(until:)`, `maintenance`, `resurfaced`, `completed`
  (UX-3; AC-M1-02).
- `HouseholdRepository` with an in-memory store and a local JSON file store: exact date round trip, typed errors on
  bad files, atomic save (FR-B1, FR-B2, P-2; AC-M1-04…07; ADR-0004).
- Context filter for energy, daypart, weekday, weather and window, in an injected calendar and time zone (FR-B1;
  AC-M1-08…12).
- Rule-of-Three selector: `NowSelector.select` returns a `NowSelection` that can hold at most three tasks, in a fixed
  order (UX-2, FR-B1; AC-M1-13…16).
- Compassionate rescheduler R0–R4: deep cleans become lighter (`maintenance`), important tasks come back gently
  (`resurfaced`), others move to their next good window, with the same length (FR-B2, UX-3; AC-M1-17…21).
- Task completion: one-off and restock tasks are done; recurring tasks start again after their interval; the room is
  marked as tended (FR-B1, FR-B3; AC-M1-03).
- Determinism: same inputs, same outputs; no clock, device calendar or random source in the engine (AC-M1-22).
- Source-scan tests for banned zero-guilt words and banned time, random and network APIs (UX-3, P-2; AC-M1-02,
  AC-M1-23, PO decisions Q16–Q20, Q23).
- Docs: [TendCore architecture overview](../architecture/overview.md), ADR index, explanation pages
  [Rule of Three](explanation/rule-of-three.md) and
  [compassionate rescheduling](explanation/compassionate-rescheduling.md), [M1 release notes](release-notes/M1.md),
  full M1 [traceability](TRACEABILITY.md).

### Security
- The JSON file store refuses any URL that is not a local file URL, before it reads or writes (P-2; review W2-F1).

### Known limitations
- Proven on Linux Foundation only. Calendar and DST behaviour on Darwin is rerun in the M3 macOS lane (W3-F1).
- Weather is an input only. A real weather source needs a PO-approved ADR first (Q22; planned for M3/M4).
- Carried Minor tickets: W2-F2, W2-F3, W2-F4, R4-F8 (see `docs/milestones/M1/acceptance.md`).
