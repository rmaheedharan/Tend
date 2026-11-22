# M2 Code Review — WI-M2-06/07 integration (PR #23, `m2/stream-duplicates`, head `cb9e2d6`)

- **Owner:** Reviewer  ·  **Verdict:** APPROVE  ·  **Round:** 1
- **Requirements:** FR-A1; AC-M2-05 (ruling 5 re-mark and invariant bullet), AC-M2-07 (word-match floor on every
  path), AC-M2-08 (marking half: every compatible planted exact-title duplicate marked on every path).
- **Binding inputs checked:** PO WI-M2-06 ruling 5 (`po-m2-wi06.md`), PO WI-M2-07 rulings 1 and 2 (`po-m2-wi07.md`),
  `po-q21-q22.md` sections "WI-M2-06/07 integration ticket", "From PR #21" and "From PR #23", PO ruling
  `po-m2-wi0607.md` (2026-11-22, I1 option (b) confirmed, no code change), review tickets R22-R2-F1, R22-R2-F2
  (`review-WI-M2-06.md`), R21-F6 (`review-WI-M2-07.md`).
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED`, M2 `IN-BUILD`. This is M2 work. Allowed.

## Summary
The draft stream now marks duplicates with the WI-M2-07 rules through a new pure conformance, `DraftDuplicateRules`
(`.onDevice(household:)`, `.cloud(_:capture:household:)`). The hook gets a `DuplicateCheckEntry` (draft, 1-based item
position with skipped items counted, claim from the latest item), the lower entries with their latest markers, and the
snapshot's cumulative Tool `lookupQueries`. The assembler re-marks from the lowest draft whose content **or claim**
changed, and from draft 1 when the lookup queries changed (R22-R2-F2 option (b)). The on-device title claim resolves
by replaying the queries on the fixed household. The household is fixed and the first match in call order wins, so
log growth can only resolve a claim: `none` becomes `ofExisting`, or a floor target becomes the model's target. The PO
has confirmed this as the specified behaviour (`po-m2-wi0607.md`). `DuplicateMarker.mark` and the pure rules share one
static function, so the stateful API and the stream cannot drift apart.

The tickets are closed and verified in the diff:
- **R22-R2-F1:** `DraftStreamTests.onlyHigherDraftReMarked` expects exactly one re-mark call, `(3, [1, 2])`. A
  re-mark from draft 1 (R3b) would make 3 calls and fail it.
- **R22-R2-F2:** purity is stated in the `DraftDuplicateCheck` doc (`DraftStreamEvent.swift:451-453`). The claim
  fields are on `ItemSnapshot`, the log growth trigger is in `DraftStreamAssembler.swift:75-77,171-172`, and the I2
  evidence rule is in the dev notes. `DraftDuplicateRules` is pure: a value type, no clock, no randomness, no
  `static var`, no I/O, and the cloud shortlist is computed once at construction.
- **R21-F6:** (1) `reCallSelfClaim` kills `k <= position`: a re-call reading its own entry would give `ofDraft(1)`, not
  `none`. (2) `reMarkCascade`. (3) The "once per draft" comments are replaced (`DuplicateMarker.swift:1-10,91-95`).
  (4) The dev-notes M2 "equivalent" line is corrected.

**Commit order:** confirmed drafts stay in ascending `draftID` (`commitOrder`, plus the e2e property's per-parse
check).

**Oracle independence:** `DupOracle` (`DuplicateOracle.swift`) calls no production code of `TendIngestion`. It has
its own fold, keywords, ranking by selection, brute-force word-match and its own position table. The mock's claims,
visibility and queries come from the oracle's shortlist. Expected claims come from `Timed.claim`, not from
`ItemSnapshot.duplicateClaim`. The only shared production code is `DraftMapper.map`, for content, which AC-M2-01/02
prove separately. The second check in the property (one pass of the production rules) is the ruling 5 invariant as
worded, not a substitute for the oracle.

**Bounded reads:** every async read in the new tests uses `collectCapped` (5,000 events) and asserts `!capped`. The
property has `.timeLimit(.minutes(10))`. No hang was seen in 7 mutant runs.

Two Minor findings and two Nits. None blocks.

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| R23-F1 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Stream/DraftStreamAssembler.swift:161-167`; `docs/milestones/M2/dev-notes.md:1909` (I2) | **The claim kept when a re-map is skipped is not pinned, and I2 words it differently.** When a later version of an emitted item would be Q5-skipped, or the item is missing from a shorter snapshot, the draft keeps its last content **and its last claim**. That matches the code comment and "a draft is never withdrawn". My mutant R2 reads the claim from the latest item even when the re-map is skipped (new claim, old content). It **survives** all tests, because the e2e final snapshot always holds every item in full. I2 (the device evidence rule) says the claim comes "from the **final snapshot's** version of its item". In this edge case that differs from what the stream uses, so the WI-M2-M2 device check could report a false defect, or miss a real one. | Add a hand test (assembler and pipeline): draft 2 is emitted with claim `sameAsItem: 1`. A later snapshot re-maps item 2 to a Q5 skip and drops the claim. Expect the marker to stay `ofDraft(1)`, with no `updated`. Show R2 killed. Reword I2 to "the claim from the last version of its item that mapped to a draft" (and the same in `DraftStreamEvent.swift:454-455` if you want it exact). Can be done in this PR or in WI-M2-08. | Open (non-blocking) |
| R23-F2 | Minor | `Packages/TendIngestion/Sources/TendIngestion/Stream/DraftPipeline.swift:27-32,39` | **The rules and the route are wired separately.** `DraftPipeline` gets `any DraftDuplicateCheck` at `init`. The route arrives later, in `events(from: RoutedModel)`. Nothing ties `.onDevice` rules to an on-device route, or ties `.cloud(_, capture:)` to the same `input`. With a mismatch, the check quietly falls back to the floor. Examples: on-device rules on a cloud Q12 = yes route ignore index claims; cloud rules with another capture read the wrong shortlist. Synonym repeats would then be created (FR-A1, M2 gate "zero duplicate creation"). Today only the doc comment guards it. | When WI-M2-09 (routing) or WI-M2-08 wires the real call site, make the mismatch impossible or tested. Options: build the rules inside the pipeline from `(route, sharing, household)`, or add a wiring test per route that asserts the rule path. Ticket only. | Open (ticket, WI-M2-08/09) |
| R23-N1 | Nit (perf watch) | `Packages/TendIngestion/Sources/TendIngestion/Duplicates/DuplicateLookup.swift:15-18` | Each re-mark of a draft with a title claim recomputes `DuplicateShortlist.entries` for every replayed query until it finds a match. A Tool-log change re-marks every draft. In the worst case the cost is drafts × queries × household per Tool call. That is fine for M2 sizes, but it is wasted work. | Optional: memoize the shortlist per query inside one re-mark pass (it is pure). Measure under AC-M2-16 as I7 already says. | Open (watch) |
| R23-N2 | Nit (doc) | `docs/milestones/M2/dev-notes.md:2025-2031` | The PO answered open question 1 (`po-m2-wi0607.md`: option (b) confirmed, no code change). The answer includes the precision that log growth can also swap a floor target for the model's resolved target. | Close open question 1 citing the ruling, and reword the I1 phrase "it never turns a mark into `none`" to include that precision. Doc-only. | Open (doc) |

The developer's open PO question (a marker can change after emission on device, through `updated`, when the Tool log
grows) is **answered**: CONFIRMED, option (b), `po-m2-wi0607.md`. Per that ruling, mutant M2 (frozen log) stays a
defect. I re-checked that it is killed: dev mutant M2, and my R13 (log change detected only after 2+ new queries) is
killed by `toolLogGrowth`, `invariantWithRules` and the e2e property.

### Tests run (Reviewer, Linux container, `swift:6.2-noble`, CI commands with `-Xswiftc -warnings-as-errors`)
The tests ran on a `git archive` copy of `cb9e2d6`, with `--scratch-path /tmp/rev23-<pkg>`.

| Package | Build | Test summary | Warnings |
|---|---|---|---|
| TendIngestion | Build complete | `✔ Test run with 210 tests in 27 suites passed after 52.056 seconds.` | 0 |
| TendSourceScan | Build complete | `✔ Test run with 63 tests in 4 suites passed after 2.153 seconds.` | 0 |
| TendCore | Build complete | `✔ Test run with 141 tests in 18 suites passed after 94.122 seconds.` | 0 |

The e2e property printed `0 oracle mismatches, 0 invariant misses` for seeds `0xD0B1E5EED060701`, `…0702` and
`…0703` (200 households × 3 paths each). AC-M2-09 scan: `22 files in total, 0 violations`. AC-M2-12 vocabulary scan:
`22 files, 9 exempted (the list), 0 violations`.

### Reviewer mutants
Each mutant was applied alone to a scratch copy, not the worktree. The run used `--filter
"DraftStream|Duplicate|PlainNote|NoModel|CloudOutcome"`, `-warnings-as-errors` and a 900 s timeout. **6 of 7
killed**, no hang.

| # | Mutant | Result |
|---|---|---|
| R1 | the assembler stores the new lookup queries **after** the re-mark (re-mark reads stale queries) | killed (e2e property, 70 issues) |
| R2 | the claim is read from the latest item even when its re-map is Q5-skipped | **survived** → R23-F1 |
| R4 | the pure rules find the `sameAsItem` target by `draftID` instead of position | killed (e2e property, 165 issues) |
| R7 | replay only the last Tool query | killed (e2e property, 341 issues) |
| R9 | re-mark only the lowest changed draft, not every later one (no cascade) | killed (e2e property, 1,511 issues, plus cascade tests) |
| R12 | emission position off by one (`index`, not `index + 1`) | killed (e2e property) |
| R13 | log change detected only after 2+ new queries | killed (`toolLogGrowth`, `invariantWithRules`, e2e) |

The developer's own 17 mutants (dev notes, mutation check) are consistent with these results. R22-R2-F1 (R3b, dev M5)
and R21-F6 (P6, dev M1) are each killed by the named tests, as shown by inspecting the assertions.

## Checklist
- [x] Correctness vs ACs: AC-M2-05 re-mark and invariant, AC-M2-07 floor on every path and positions, AC-M2-08
  marking half (600 households × 3 paths, every compatible exact plant marked). The AC-M2-08 commit half is WI-M2-08.
- [x] Tests meaningful: independent oracle, seeded, coverage asserted per seed and path; 6/7 reviewer mutants killed.
  The survivor is Minor (R23-F1).
- [x] Swift 6 concurrency safe: all new types are `Sendable` value types. No `@unchecked Sendable`, no
  `nonisolated(unsafe)`, no new `Task {}`. The test doubles use `Mutex`. Builds clean with `-warnings-as-errors`.
- [x] No force unwraps / `try!` in product code paths.
- [x] Privacy (P-1…P-4): no networking, I/O or logging is added. Cloud paths ignore lookup queries.
- [x] UX-2/UX-3 enforced in engine: no selection surface is touched. No new guilt state or vocabulary (AC-M2-12 scan,
  0 violations).
- [x] Accessibility (UI): n.a., no UI. The PO's M3 note covers the visible marker change.
- [x] Performance: acceptable for M2. Watch R23-N1 under AC-M2-16.
- [x] No new dependency without ADR: none added. Imports are Foundation and TendCore only (ADR-0006).

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Markers stay inferred and current; the user is asked nothing. |
| UX-2 Rule of Three | n.a. | No selection surface; drafts reach Now only via commit and `NowSelector`. |
| UX-3 Zero-Guilt | pass | No repeat or lateness state. New identifiers pass the AC-M2-12 scan (0 violations). The marker change after emission is toward less work (`po-m2-wi0607.md`); the M3 transition design belongs to the Designer. |
| UX-4 Design craft | n.a. | No UI in this item. |
| P-1 On-device inference | pass | The rules are local and deterministic. Queries are replayed on the phone's own household. |
| P-2 No data leaves device (except user iCloud) | pass | Nothing new is sent. No networking, I/O or logging (AC-M2-09: 0 violations). |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | pass | No request field is added. Q12 = yes reads only the shortlist ADR-0005 allows, Q12 = no reads nothing, and lookup queries are never used on a cloud path. See R23-F2 for the wiring guard. |
| P-4 Media not persisted without consent | pass | Nothing is persisted, and the household is never changed (Q7). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-22 | Orchestrator | Reviewer | accepted | PR #23 head `cb9e2d6`, WI-M2-06/07 integration (AC-M2-05, 07, 08; FR-A1). The PO ruling `po-m2-wi0607.md` arrived mid-review and was applied. |
| 2026-11-22 | Reviewer | Orchestrator → Merge Gatekeeper; tickets to Developer (R23-F1, R23-N2 in this PR or WI-M2-08; R23-F2 at WI-M2-08/09 wiring) | sent | **APPROVE.** R22-R2-F1, R22-R2-F2 and R21-F6 closed and verified. 210/63/141 green, 0 warnings. 6 of 7 reviewer mutants killed; the survivor is R23-F1 (Minor). No Blocker or Major. |
