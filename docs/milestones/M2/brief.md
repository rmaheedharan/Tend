# M2 Brief — On-Device AI Ingestion

- **Owner:** Product Owner  ·  **Status:** Draft (awaiting Acceptance Tester testability review; not yet Ready for planning)
- **PRD scope:** *M2: On-Device AI Ingestion.* Voice and text brain-dump parsing, duplicate detection, and streaming
  structured output using on-device Foundation Models.
  Gate:
  - Automated mock tests pass 100%.
  - Real-Device Eval Suite (iPhone 15 Pro): 20 messy real-world voice/text inputs parse accurately into
    tasks/rooms/efforts, with latency under 1.5 seconds and zero duplicate creation.
- **Requirements in scope:**
  - FR-A1: parsing, room and effort inference, duplicate check, and streaming of parsed items. This is the pipeline
    only, not the screen.
  - UX-3: generated text.
  - P-1, P-2, P-3, P-4: inference, speech and data handling.
  - UX-2: newly captured tasks reach Now only through `NowSelector`.
  - CLAUDE.md §3: `TendAI` adapters behind protocols; `SystemLanguageModel.availability`; `@Generable` / `@Guide`;
    `streamResponse`; `Tool` for duplicate lookup; `SpeechAnalyzer` / `SpeechTranscriber`.
  - Carried from M1: D-016 (the parser maps onto the model invariants), W3-F6 (duplicate task IDs) and W2-F3
    (non-finite dates).
- **Out of scope (explicit):**
  - The streaming Brain-Dump **UI**, the "Looks Good" and swipe-to-dismiss gestures, haptics, motion and copy rendering
    are **M3**. M2 delivers the API that M3 calls: a stream of drafts, then confirm or dismiss.
  - The Action Button, App Intents, Siri and Shortcuts triggers (FR-D2) are **M4**. The camera (FR-A2) and the Share
    Sheet (FR-A3) are **M4**.
  - Sprint building (FR-C1…C3) is **M3**. Load balancing and assignees (FR-E2) and sync (FR-E1) are **M5**.
  - Thermal profiling during inference is **M5**.
  - Wiring real weather is **M3/M4**, after the ADR in D-023. The parser only records that an item depends on weather.
  - Any cloud model or Private Cloud Compute path (P-3) is out of scope; see Q1.
  - Languages other than English (en-US); see Q2.
  - The Privacy Manifest file ships with the app target (**M3**). M2 records the data each adapter touches so the
    manifest can be written accurately.

## Outcome
At the end of M2, a busy person can say or type one messy sentence, for example "The AC needs servicing before summer,
we're almost out of dishwasher pods, and let's deep clean the balcony this weekend if it doesn't rain". On their own
iPhone, with no network, Tend turns it into separate, valid household tasks. Each task has its kind, room, effort,
weather condition and a sensible window. The tasks stream out one by one as they are understood. Nothing is saved
until the person confirms. Anything already on their list is recognised, so nothing is created twice. Tend never adds
a guilt word that the person didn't say. If the on-device model is unavailable, Tend says nothing alarming, sends
nothing anywhere and loses nothing the person said. The M1 engine is unchanged, so everything captured still reaches
the Now canvas only through the Rule of Three.

## Definitions used in this brief (product meaning, binding for M2)
- **Brain-dump input:** one finished text, or one finished voice utterance after its on-device transcript is final.
- **Draft:** a proposed task produced by parsing. It is not in the household until it is **committed**. A draft carries
  the fields the M1 model needs (title, kind, room or proposed new room, effort, critical / deep-clean /
  weather-dependent flags, dayparts, weekdays, window, interval). It also carries the user's own words for that item
  (`sourcePhrase`, a substring of the input) and a duplicate marker (below).
- **Duplicate:** a draft that describes the same real-world chore as either (a) an existing task that is not
  `completed`, or (b) an earlier draft in the same input. The same chore means the same action on the same thing, in the
  same room when a room is known. It does not depend on wording ("buy dish pods" = "we're almost out of dishwasher
  pods"). A completed one-off or restock task is not a duplicate target: saying it again means it is needed again.
- **Duplicate creation:** committing a draft adds a task that is a duplicate under this definition. **False merge:** a
  draft that the golden set says is distinct is marked as a duplicate and so not created.
- **Time to first item (TTFI):** for text, the time from handing the finished text to the pipeline until the first
  complete draft is emitted. For voice, the time from the end of speech (the transcriber's final result for the
  utterance) until the first complete draft is emitted. **Total time:** from the same start until the stream finishes.
  The language-model session may be prewarmed when capture starts, because the user taps or presses before speaking
  (Q4).
- **Banned tokens:** the AC-M1-02 list (*overdue, late, lateness, missed, failed, behind, penalty, debt, streak*), matched
  as whole tokens.

## Stories

### S-M2-01 One messy sentence becomes separate, valid tasks  (FR-A1, D-016)
As a person carrying the household in my head, I want to say everything at once and have Tend split it into proper
tasks, so that I never sort or fill anything in myself.

**Acceptance criteria**
- **AC-M2-01** Given a scripted mock model output for each PRD item type (one-off errand, recurring maintenance,
  consumable restock, weather-dependent task), when the pipeline maps it, then each draft becomes a `HouseholdTask` that
  passes the M1 initialiser, with the expected kind, room, effort and flags. Date fields are computed only from the
  injected `now`, calendar and time zone.  *Verification:* unit (Linux, platform-neutral mapping layer)  *Evidence
  expected:* test name + log.
- **AC-M2-02** Given ≥ 1,000 seeded random structured outputs, including degenerate ones (missing title, empty dayparts
  or weekdays, end ≤ start, critical + deep clean, interval on a one-off, a recurring task with no interval, non-finite or
  out-of-range dates, unknown enum values), when they are mapped, then the pipeline never crashes and never emits an
  invalid task. Each field is repaired by exactly the rules in Q5, or the item is dropped calmly with a typed reason.
  The result equals an independent oracle of Q5.  *Verification:* unit (property, fixed seeds)  *Evidence expected:*
  test name, seed range, counts per repair rule.
- **AC-M2-03** Given the time phrases in the Q6 table, each the way the model reports it as a structured time hint,
  when they are resolved at fixed `now` values (including a DST day and a year boundary), then the window, dayparts,
  weekdays and interval equal the table exactly.  *Verification:* unit (parameterised)  *Evidence expected:* test name +
  log.
- **AC-M2-04** Given a household with rooms, when a draft names a room, then it is linked to the existing room whose
  name matches case- and diacritic-insensitively, or, if none matches, it carries a proposed new room. That room is
  created only on commit. No room is created or renamed during parsing.  *Verification:* unit  *Evidence expected:* test
  name + log.

### S-M2-02 I see each item as soon as Tend understands it  (FR-A1 feedback)
As someone in the middle of a busy moment, I want each item to appear as soon as it's recognised, and nothing to stick
unless I say so, so that capture feels instant and safe.

**Acceptance criteria**
- **AC-M2-05** Given a mock model that streams partial snapshots (fields arrive out of order, an item is split across
  snapshots, the stream ends early or throws), when the pipeline consumes it, then each draft is emitted exactly once,
  as soon as all its required fields are present, in input order. An emitted draft is never withdrawn, and a later
  change to it arrives as an explicit update of the same draft ID. Cancelling stops the stream with no task written.
  *Verification:* unit  *Evidence expected:* test name + log.
- **AC-M2-06** Given any parse, when it runs, then nothing is written to the `HouseholdRepository`. When
  `commit(confirmed:)` runs, exactly the confirmed non-duplicate drafts are upserted, together with their proposed
  rooms. Dismissed drafts and drafts left unconfirmed are not saved. Each new task gets its ID from an injected ID
  generator, and no two tasks in the household ever share an ID (W3-F6).  *Verification:* unit (contract over both M1
  repositories, plus a property)  *Evidence expected:* test name + log.

### S-M2-03 Never the same chore twice  (FR-A1)
As someone who mentions the dishwasher pods every other day, I want Tend to know when something is already on my list,
so that my list never doubles up.

**Acceptance criteria**
- **AC-M2-07** Given a household and drafts (mock model plus the duplicate-lookup `Tool`), when duplicates are checked,
  then a draft matching an existing non-completed task is marked `duplicateOf(existingID)` and commit creates nothing
  for it. The existing task is not changed in M2 (Q7). A repeat within one input collapses into its first draft. A
  match against a completed one-off or restock task is not a duplicate. The `Tool` returns candidates only from the
  local household, and only the fields the model needs (title, kind, room name).  *Verification:* unit  *Evidence
  expected:* test name + log.
- **AC-M2-08** Given ≥ 500 seeded households and draft sets, including planted duplicates by exact title, by synonym
  (scripted in the mock) and within one input, when commit runs, then no committed task is a duplicate of another
  non-completed task under the deterministic rule the mock scripts, and no ID is repeated.  *Verification:* unit
  (property)  *Evidence expected:* test name, seeds and counts.

### S-M2-04 What I say stays on my phone  (FR-A1, P-1, P-2, P-3, P-4)
As a person speaking about my home, my bills and my family, I want all of it understood on my phone and nothing kept
that I didn't keep, so that I can talk freely.

**Acceptance criteria**
- **AC-M2-09** Given the `TendAI` sources, when a source scan runs (the M1 AC-M1-23 approach), then the only imports are
  `Foundation`, `FoundationModels`, `Speech`, `AVFAudio` and `TendCore`. None of the AC-M1-23 networking patterns
  occurs. Speech uses `SpeechTranscriber` on device only, with no server-based recogniser API. Audio buffers and
  transcripts are never written to disk, `UserDefaults` or logs; this is checked by the scan for file-writing APIs and
  by Reviewer inspection.  *Verification:* unit (source scan) + Reviewer  *Evidence expected:* test name + log + review
  note.
- **AC-M2-10** Given each `SystemLanguageModel.availability` value that is not available (device not eligible, Apple
  Intelligence not enabled, model not ready), and a mock in which generation throws (guardrail, context too long), when
  a brain-dump is submitted, then the pipeline returns a calm typed outcome. It makes no network call and creates no
  task, and it returns the input text to the caller in memory so that M3 can keep it if the user wants. No outcome name
  or string contains a banned token.  *Verification:* unit  *Evidence expected:* test name + log.
- **AC-M2-11** (device) Given an iPhone 15 Pro in airplane mode, with Wi-Fi and Bluetooth off, when 3 eval inputs (2
  voice, 1 text) are run, then all parse with results equal to their online run under the AC-M2-15 rubric.
  *Verification:* device-script  *Evidence expected:* human-recorded run (date, device, iOS build, results file).
  **Status until run: AWAITING-DEVICE.**

### S-M2-05 Tend's words are always calm  (UX-3)
As someone who already feels behind, I want Tend never to add a guilt word, so that capture never stings.

**Acceptance criteria**
- **AC-M2-12** Given mock outputs whose titles contain banned tokens, some present in the input and some not, when the
  calm-words guard runs, then any banned token that is **not** in the user's input is removed from the title. If the
  title would then be empty, it becomes the draft's `sourcePhrase`. Banned tokens that the user said are kept (they are
  the user's words). Model instructions and every outcome name contain no banned token.  *Verification:* unit
  *Evidence expected:* test name + log.

### S-M2-06 Proven on a real iPhone 15 Pro  (gate)
**Acceptance criteria**
- **AC-M2-13** **(Gate)** Given the M2 merge commit, when the automated suites run, then 100% of tests pass with 0
  failures, 0 skipped or disabled tests and 0 warnings, in two places: (a) `swift test` for `TendCore` and the
  platform-neutral ingestion layer on Linux CI; (b) the `TendAI` mock tests on macOS with Xcode 26 (a CI lane, or a
  human-recorded Mac run if no lane exists; see Q8). The M1 suite stays green. Every other M2 AC maps to at least one
  named test or device step.  *Verification:* CI run (+ macOS run)  *Evidence expected:* run links + log excerpts + AC
  → test table.
- **AC-M2-14** Given the eval harness, when it is reviewed before the first device run, then the 20 inputs, the
  seeded household and the golden expectations are committed and frozen, and they meet the Q3 composition. The
  harness's scorer passes self-tests against a mock model with known right and wrong answers. Any change to the inputs
  or the golden set after the first device run needs a PO decision in `DECISIONS.md`.  *Verification:* unit (scorer
  self-test) + Tester review  *Evidence expected:* test name + fixture commit hash.
- **AC-M2-15** **(Gate)** (device) Given the frozen eval on an iPhone 15 Pro (iOS 26, Apple Intelligence on, en-US), when
  all 20 inputs run (voice inputs are spoken live from the script by the human owner, and no audio is stored), then the
  Q3 rubric thresholds are met: segmentation, kind, room, effort, flags, 100% valid tasks, and 0 introduced banned
  tokens.  *Verification:* device-script  *Evidence expected:* results file + human run record. **Status until run:
  AWAITING-DEVICE.**
- **AC-M2-16** **(Gate)** (device) In the same run, every one of the 20 inputs has TTFI < 1.5 s and total time ≤ 5.0 s
  (Q4). The harness also reports the cold-start TTFI of the first input without prewarm, for information only.
  *Verification:* device-script  *Evidence expected:* per-input timings in the results file. **Status until run:
  AWAITING-DEVICE.**
- **AC-M2-17** **(Gate)** (device) In the same run, committing every draft the pipeline does not mark as a duplicate
  creates **0** duplicates across all 20 inputs (Definitions), and there is at most 1 false merge in total.
  *Verification:* device-script  *Evidence expected:* results file. **Status until run: AWAITING-DEVICE.**

## Gate mapping
| PRD §4 gate line | Covered by ACs |
|---|---|
| Automated mock tests pass 100% | AC-M2-13, built on AC-M2-01…10 and AC-M2-12 |
| 20 messy voice/text inputs parse accurately into tasks/rooms/efforts (iPhone 15 Pro) | AC-M2-14, AC-M2-15 (rubric Q3) |
| Latency under 1.5 seconds | AC-M2-16 (TTFI < 1.5 s; total ≤ 5 s, Q4) |
| Zero duplicate creation | AC-M2-07, AC-M2-08 (logic), AC-M2-17 (device) |
| Scope: on-device Foundation Models, streaming structured output | AC-M2-05, AC-M2-09, AC-M2-10, AC-M2-11 |

Device criteria AC-M2-11, AC-M2-15, AC-M2-16 and AC-M2-17 stay **AWAITING-DEVICE** until the human owner runs the
Tester's script and the result is recorded (CLAUDE.md §5). M2 cannot be `ACCEPTED` before that.

## Assumptions and open questions
| # | Question | Default if unanswered | Needed by |
|---|---|---|---|
| Q1 | CLAUDE.md §9 item 2: is any Private Cloud Compute or cloud path wanted for M2 (P-3)? | **No.** On-device only. Model unavailable means calm degradation (AC-M2-10), never a cloud call. **Human owner to confirm.** | Before M2 build |
| Q2 | Which languages? | en-US only in M2. The model's locale support is checked at runtime. Other locales degrade the same way as an unavailable model. | M2 (PO default) |
| Q3 | What does "parse accurately" mean (the rubric)? | Scored per expected item over all 20 inputs, one-to-one matching against the golden set. **Segmentation:** ≥ 95% of expected items found and ≤ 2 extra items in total. **Kind** ≥ 95% exact. **Room** ≥ 90% (an exact room, or both none). **Effort** ≥ 85% exact on Low/Normal/High. **Flags** (critical, deep clean, weather-dependent) ≥ 95% exact each. **Validity:** 100% of drafts pass the M1 invariants. **Calm words:** 0 introduced banned tokens. **Composition:** 20 inputs, of which ≥ 8 voice and ≥ 8 text; 10–80 words each; all four item types; ≥ 5 with a weather condition; ≥ 3 critical (bill, expiring food); ≥ 3 deep cleans; ≥ 5 mentioning an existing task; ≥ 3 with a repeat inside the input; ≥ 4 with filler or self-correction ("no wait, Thursday"). (PO default; the owner may tighten it.) | Before AC-M2-14 is frozen |
| Q4 | What does the latency clock cover? | TTFI as defined, < 1.5 s for **each** input (not an average). Total ≤ 5.0 s per input. Prewarming the session when capture starts is allowed; cold start is reported but does not gate. (PO default) | M2 (PO default) |
| Q5 | How are degenerate model outputs mapped onto the M1 invariants (D-016)? | No title → drop the item (typed reason). Empty dayparts → default dayparts. Empty weekdays → all seven. No window, end ≤ start, or a non-finite or out-of-range date → `[now, now + 7 days)`. Critical + deep clean → critical, deep clean cleared. Interval on a one-off → interval dropped. A recurring task with no interval → becomes a one-off. Unknown enum value → that field's default (effort Normal, kind one-off). Repairs happen only in the ingestion layer; the M1 model still rejects invalid tasks. (PO default) | M2 (PO default) |
| Q6 | How are time phrases resolved? | The model reports a structured hint and a deterministic resolver applies the injected calendar. The Developer and Tester write the exact table. Defaults: "today" → `[now, end of today)`; "tonight" → evening + night, today; "tomorrow (morning/…)" → that daypart of tomorrow; "this weekend" → Saturday and Sunday of the current or coming weekend; "next week" → `[next Monday, +7 days)`; "before <season/month>" → `[now, start of it)`; "every N days/weeks/months" → recurring, interval in days (1 month = 30 days); no phrase → `[now, now + 7 days)`. The Planner adds the full table to the plan for the Tester's review. (PO default) | M2 planning |
| Q7 | What happens to the existing task when a duplicate is mentioned? | Nothing in M2: no new task, existing task unchanged. Gently refreshing the existing task (for example bringing a restock forward) is a product question for M3, with its copy. (PO default) | M3 |
| Q8 | `TendAI` needs Xcode 26 on macOS to build and run its mock tests. Is there a macOS CI lane (a paid runner), or does the owner run them on a Mac? | Open a macOS CI lane in M2 if the owner agrees to the cost; otherwise AC-M2-13(b) is a human-recorded Mac run. The same lane closes W3-F1 (the Darwin DST rerun). **Human owner to decide.** | Before M2 build |
| Q9 | W2-F3: should non-finite dates become a model invariant? | Yes. Add a `TaskInvariantViolation` case for a non-finite date (Designer names it), so both M1 stores agree. AC-M1-25 gains the case; no AC is removed. The parser never emits one (Q5). (PO default; Designer to name it) | M2 |
| Q10 | W3-F6: duplicate task IDs. | Forbidden. Commit takes IDs from an injected generator and the household never holds two tasks with one ID (AC-M2-06). Sync-time collisions are M5. (PO default) | M2; M5 for sync |
| Q11 | Does a long dump break the Rule of Three? | No. The draft stream is a review of what was just captured, not a "what to do now" surface. Committed tasks reach Now only through `NowSelector` (≤ 3). How many drafts are shown at once is an M3 design question. (PO default) | M3 design |

## Tester testability review
- [ ] Every AC is observable and measurable  - [ ] Device ACs identified (AC-M2-11, 15, 16, 17)  - Reviewer note:
  pending.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Capture is voice or free text. Every field is inferred (AC-M2-01…04), and confirmation is a single act (AC-M2-06). No form exists or is needed. |
| UX-2 Rule of Three | pass | No new "what to do now" API. Committed tasks reach Now only through `NowSelection` (≤ 3, M1). The draft review list is defined as a capture review, not a Now surface (Q11). |
| UX-3 Zero-Guilt | pass | Calm-words guard (AC-M2-12). Calm outcomes when the model is unavailable (AC-M2-10). No new state or counter: the M1 model and D-2/D-3 are unchanged. |
| UX-4 Design craft | n.a. | No UI in M2 (M3). |
| P-1 On-device inference | pass | `FoundationModels` and `SpeechTranscriber` on device (AC-M2-09), proven offline on device (AC-M2-11, AWAITING-DEVICE). |
| P-2 No data leaves device (except user iCloud) | pass | Scan bans networking (AC-M2-09). The duplicate `Tool` reads only the local household (AC-M2-07). |
| P-3 Cloud escalation only via PCC + ADR | pass | No cloud path; degradation only (AC-M2-10). Q1 goes to the human owner. |
| P-4 Media not persisted without consent | pass | Audio and transcripts stay in memory (AC-M2-09). Nothing is saved before commit (AC-M2-06). Eval voice inputs are spoken live and never recorded (AC-M2-15). The Privacy Manifest ships with the app target (M3). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Product Owner | Acceptance Tester | to send for testability review | Brief v1 (Draft), written after the M1 gate (ACCEPTED, STATUS.md). 6 stories, 17 ACs (AC-M2-01…17); device ACs AC-M2-11, 15, 16 and 17 are AWAITING-DEVICE. Human-owner questions: Q1 (PCC), Q8 (macOS lane); Q3 thresholds are open to owner tightening. After the Tester's review, the PO hands off to the Work Planner (H1). |
