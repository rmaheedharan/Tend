# M2 Brief — On-Device AI Ingestion

- **Owner:** Product Owner  ·  **Status:** Draft v2 (revised 2026-11-21 for D-030 / ADR-0005; awaiting the owner's
  merge of the policy PR and the Acceptance Tester testability review; not yet Ready for planning). Cloud stories
  S-M2-07…09 may not be built until D-030 and ADR-0005 are merged.
- **PRD scope:** *M2: On-Device AI Ingestion.* Voice and text brain-dump parsing, duplicate detection, and streaming
  structured output using on-device Foundation Models, plus the opt-in bring-your-own-key cloud path (ADR-0005) where
  on-device is unavailable.
  Gate:
  - Automated mock tests pass 100%.
  - Real-Device Eval Suite (iPhone 15 Pro, on-device): 20 messy real-world voice/text inputs parse accurately into
    tasks/rooms/efforts, with latency under 1.5 seconds and zero duplicate creation.
  - The same eval on iPhone 13 with the cloud path meets the same accuracy and zero duplicates, within the cloud
    latency target set in this brief (Q15).
- **Requirements in scope:**
  - FR-A1: parsing, room and effort inference, duplicate check, and streaming of parsed items. This is the pipeline
    only, not the screen.
  - UX-3: generated text.
  - P-1, P-2, P-3, P-4 (as rewritten by D-030): inference, speech and data handling.
  - ADR-0005: the cloud language-model adapters (OpenAI, Anthropic, Gemini), routing, consent state, data
    minimisation, Keychain key storage and calm fallback, as an API and logic layer (no screens).
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
  - The Settings, consent and key-entry **screens** and their copy are **M3**. M2 delivers the logic they call
    (consent record, key store, routing) and the per-provider disclosure facts the copy needs.
  - Apple Private Cloud Compute (not available to us; D-030). Any provider other than OpenAI, Anthropic and Gemini, any
    custom endpoint (Q13), and any Tend-run server.
  - Sending images or documents to a cloud model (M4; Q14). M2 cloud requests carry text only.
  - Saving the plain-note fallback to the store as a screen flow (M3). M2 provides the plain-note draft (AC-M2-23).
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
nothing anywhere and loses nothing the person said. On a phone without the on-device model, such as an iPhone 13, a
person who has chosen to add their own OpenAI, Claude or Gemini key gets the same result from the cloud. Only the words
of that one capture and their room names leave the phone, straight to the provider they chose, and never their voice,
their photos, their family's names or the rest of their household. Without any model, their words can still be kept
as a plain note. The M1 engine is unchanged, so everything captured still reaches
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
- **Cloud model:** a language model from OpenAI, Anthropic or Google Gemini, called directly from the phone with the
  user's own key under ADR-0005. **Cloud on** means the user has given consent for a provider and a key for that
  provider is stored. Anything else is **cloud off**, which is the default.
- **Route:** which model handles a capture: `onDevice`, `cloud(provider)` or `none`. ADR-0005 Decision 1 sets the
  route (AC-M2-19).
- **Cloud request:** the exact bytes (method, host, path, header names, body) the payload builder produces for one
  capture. **Allowed request content** is ADR-0005 Decision 3: fixed instructions and schema, the one capture's text,
  room names, and (only if Q12 is yes) at most 10 pre-filtered task titles with per-request index numbers.
- **Plain note:** one draft whose title is the user's own words (trimmed), with the Q5 default fields and no inference.
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

### S-M2-04 What I say stays on my phone unless I chose a cloud model  (FR-A1, P-1, P-2, P-3, P-4)
As a person speaking about my home, my bills and my family, I want all of it understood on my phone, nothing sent
anywhere I didn't choose, and nothing kept that I didn't keep, so that I can talk freely.

**Acceptance criteria**
- **AC-M2-09** Given the `TendAI` sources, when a source scan runs (the M1 AC-M1-23 approach), then:
  - Outside the cloud-adapter allowlist (a fixed list of file paths set in the plan), the only imports are
    `Foundation`, `FoundationModels`, `Speech`, `AVFAudio` and `TendCore`, and none of the AC-M1-23 networking patterns
    occurs.
  - Inside the allowlist, the only extra imports are `Security` (Keychain) and `Foundation` networking. The only
    network API is `URLSession`. Every host literal is one of the three ADR-0005 hosts, and no provider SDK or
    third-party module is imported.
  - Speech uses `SpeechTranscriber` or `DictationTranscriber` on device only, with no server-based recogniser API.
  - No audio, image or pixel-buffer type is passed to any cloud-adapter file.
  - Audio buffers, transcripts, request bodies, responses and keys are never written to disk, `UserDefaults` or logs.
    This is checked by the scan for file-writing and logging APIs and by Reviewer inspection.

  *Verification:* unit (source scan) + Reviewer  *Evidence expected:* test name + log + review note.
- **AC-M2-10** Given **cloud off**, and each `SystemLanguageModel.availability` value that is not available (device
  not eligible, Apple Intelligence not enabled, model not ready), and also (with cloud on or off) a mock in which
  on-device generation throws (guardrail, context too long), when a brain-dump is submitted, then the pipeline returns
  a calm typed outcome. It makes no network call (the mock transport records zero requests) and creates no task. It
  returns the input text to the caller in memory, so that M3 can keep it if the user wants. No outcome name or string
  contains a banned token.  *Verification:* unit  *Evidence expected:* test name + log.
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

### S-M2-06 Proven on a real iPhone 15 Pro, on device  (gate)
**Acceptance criteria**
- **AC-M2-13** **(Gate)** Given the M2 merge commit, when the automated suites run, then 100% of tests pass with 0
  failures, 0 skipped or disabled tests and 0 warnings, in two places: (a) `swift test` for `TendCore` and the
  platform-neutral ingestion layer on Linux CI. The ingestion layer includes the routing rules, the payload builder
  and the provider response parsers (AC-M2-19, 20, 24); (b) the `TendAI` mock tests on macOS with Xcode 26 (a CI lane, or a
  human-recorded Mac run if no lane exists; see Q8). The M1 suite stays green. Every other M2 AC maps to at least one
  named test or device step.  *Verification:* CI run (+ macOS run)  *Evidence expected:* run links + log excerpts + AC
  → test table.
- **AC-M2-14** Given the eval harness, when it is reviewed before the first device run, then the 20 inputs, the
  seeded household and the golden expectations are committed and frozen, and they meet the Q3 composition. The
  harness's scorer passes self-tests against a mock model with known right and wrong answers. Any change to the inputs
  or the golden set after the first device run needs a PO decision in `DECISIONS.md`.  *Verification:* unit (scorer
  self-test) + Tester review  *Evidence expected:* test name + fixture commit hash.
- **AC-M2-15** **(Gate)** (device) Given the frozen eval on an iPhone 15 Pro (iOS 26, Apple Intelligence on, cloud off, en-US), when
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

### S-M2-07 My older iPhone can use a cloud model I chose  (FR-A1, P-1, P-3; ADR-0005)
As someone with an iPhone 13, I want to plug in my own AI key and get the same capture as newer phones, and only when
I've said yes, so that I'm not left out and nothing goes anywhere without me knowing.

**Acceptance criteria**
- **AC-M2-18** Given a fresh install state, a restored state and every state without a consent record for the selected
  provider, when any brain-dump is submitted, then the route is never `cloud` and the mock transport records zero
  requests. Given consent and a key for provider X, the route can only be `cloud(X)`, never another provider. When cloud
  is turned off, or the key is removed, then (a) the Keychain item is deleted, (b) the consent record is cleared, (c) no
  request starts afterwards, and (d) an in-flight cloud request is cancelled with no task written.  *Verification:*
  unit (mock transport, in-memory key store)  *Evidence expected:* test name + log.
- **AC-M2-19** Given every combination of on-device availability (available; each unavailable reason), cloud (off; on
  for each provider), and preference ("on device first", "always use my cloud model"), when the route is chosen, then
  it equals the ADR-0005 Decision 1 rules exactly (the plan writes them out as the full expected matrix). In particular, a device with the model available and "on device
  first" set never routes to the cloud. An on-device generation error never re-routes to the cloud. The route is part
  of the outcome, so M3 can show which model handled the capture.  *Verification:* unit (parameterised, full matrix;
  Linux)  *Evidence expected:* test name + matrix log.
- **AC-M2-24** Given recorded provider stream fixtures for OpenAI, Anthropic and Gemini, when each cloud adapter parses
  them, then it emits drafts through the same `IngestionModel` contract as the on-device adapter, and AC-M2-01…08 and
  AC-M2-12 hold for cloud output too. The fixtures cover happy paths, out-of-order or split chunks, a truncated stream,
  invalid JSON, schema-violating fields, unknown enum values, and a refusal. The calm-words guard and Q5 repairs apply
  to cloud output, and the stream rules of AC-M2-05 hold. A cloud model is never given the duplicate-lookup `Tool`.
  *Verification:* unit (fixtures; parsers on Linux, adapters on macOS)  *Evidence expected:* test name + fixture list +
  log.

### S-M2-08 Only what's needed leaves my phone, and I'm told the truth about it  (P-2, P-3, P-4; ADR-0005)
As someone who turned the cloud on, I want only the one thing I just said to be sent, my key to stay safe, and Tend to
stay calm when the cloud isn't there, so that saying yes to the cloud never costs me my privacy or my words.

**Acceptance criteria**
- **AC-M2-20** Given ≥ 500 seeded households, when the payload builder builds a cloud request for a capture, for each
  provider, then:
  - The households carry planted sentinel values in member names, assignees, task IDs, room IDs, other tasks' titles
    and notes, dates, time zone and household ID. Each request body, decoded, contains only allowed request content
    (Definitions).
  - No sentinel value outside allowed content appears anywhere in the bytes. This includes headers, path and query.
  - For 3 fixed golden households per provider, the bytes equal a committed golden request exactly.
  - The request asks for every retention or training opt-out the provider's API offers, as listed in the plan
    (OpenAI `store: false` at least).
  - The API key appears only in that provider's auth header.
  - A capture with an attached image or audio is rejected by type before building.
  - The test sends through a recording mock transport and asserts on the captured request, not on the builder's
    intermediate values.

  *Verification:* unit (property + golden; the builder is pure Foundation in the ingestion layer, so this runs on
  Linux)  *Evidence expected:* test name, seeds, golden fixture hashes, log.
- **AC-M2-21** Given the key store, when a key is saved, read, replaced and deleted, then:
  - The Keychain item is a generic password with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and is not
    synchronizable.
  - Reading it back after save returns the same key.
  - Only a masked form (last 4 characters) is ever returned for display.
  - Delete leaves no item.
  - The key never appears in `UserDefaults`, files, logs, `CustomStringConvertible` or `CustomDebugStringConvertible`
    output, or error messages. The scan in AC-M2-09 checks this, together with a test that formats every key-holding
    type.

  *Verification:* unit (Keychain on macOS or Simulator; in-memory fake elsewhere) + Reviewer  *Evidence expected:*
  test name + log + review note.
- **AC-M2-22** Given the cloud transport, when it is configured, then it uses an ephemeral `URLSession` configuration
  with no cookie storage and no URL cache. It sends only HTTPS to the ADR-0005 host for the routed provider. A request
  to any other host, a redirect to another host, or a non-HTTPS URL is refused before sending. Each request has a
  timeout of no more than the Q15 total limit.  *Verification:* unit (mock `URLProtocol`)  *Evidence expected:* test
  name + log.
- **AC-M2-23** Given cloud on, when the mock transport returns each failure (offline, timeout, DNS failure, TLS
  failure, 401 or 403 bad key, 429 rate limit, 5xx, malformed body, provider refusal), then:
  - The pipeline returns a calm typed outcome, creates no task, and returns the input text in memory.
  - It also offers a **plain note** draft built from that text, which is committed only by `commit(confirmed:)`.
  - Nothing is queued or retried in the background, and nothing is written to disk. A single in-call retry is allowed
    only for 429/5xx, and only within the Q15 total limit.
  - The same plain-note offer exists when the route is `none`.
  - No outcome name or string contains a banned token, and none blames the user.

  *Verification:* unit  *Evidence expected:* test name + log.

### S-M2-09 Proven on a real iPhone 13 with a cloud model  (gate; ADR-0005)
**Acceptance criteria**
- **AC-M2-25** (device) Given an iPhone 13 on iOS 26 (en-US, cloud on with one provider), when 2 voice inputs are
  spoken in airplane mode, then:
  - The transcript is produced on device. The run records which transcriber was used (`SpeechTranscriber` or
    `DictationTranscriber`).
  - The cloud step returns the calm offline outcome with the plain-note offer, and no task is created.
  - Back online, the same inputs parse through the cloud.

  *Verification:* device-script  *Evidence expected:* human-recorded run (date, device, iOS build, results file).
  **Status until run: AWAITING-DEVICE.**
- **AC-M2-26** **(Gate)** (device) Given the frozen eval (AC-M2-14) on an iPhone 13 (iOS 26, cloud on, en-US), when
  all 20 inputs run once for **each** provider in Q16, using that provider's default model from the curated list, then
  each provider's run meets:
  - the Q3 rubric thresholds;
  - 0 duplicates created and at most 1 false merge (as AC-M2-17).

  The voice inputs are spoken live and no audio is stored. The results file also records, per request, the request
  byte count and the field names sent. These must match AC-M2-20's allowed content.  *Verification:* device-script
  *Evidence expected:* results file per provider + human run record. **Status until run: AWAITING-DEVICE.**
- **AC-M2-27** **(Gate)** (device) In the same runs, on the network stated in the run record (Q15), every input has:
  - cloud TTFI < 3.0 s;
  - total time ≤ 10.0 s.

  The run also reports the same figures on the iPhone 15 Pro with "always use my cloud model" for one provider, for
  information only. The on-device target stays AC-M2-16 (< 1.5 s, ≤ 5.0 s) and is not relaxed.  *Verification:*
  device-script  *Evidence expected:* per-input timings per provider in the results file. **Status until run:
  AWAITING-DEVICE.**

## Gate mapping
| PRD §4 gate line | Covered by ACs |
|---|---|
| Automated mock tests pass 100% | AC-M2-13, built on AC-M2-01…10, AC-M2-12 and AC-M2-18…24 |
| 20 messy voice/text inputs parse accurately into tasks/rooms/efforts (iPhone 15 Pro, on-device) | AC-M2-14, AC-M2-15 (rubric Q3) |
| Latency under 1.5 seconds (on-device) | AC-M2-16 (TTFI < 1.5 s; total ≤ 5 s, Q4) |
| Zero duplicate creation | AC-M2-07, AC-M2-08 (logic), AC-M2-17 (device, on-device), AC-M2-26 (device, cloud) |
| Same eval on iPhone 13 with the cloud path: accuracy and zero duplicates | AC-M2-24 (logic), AC-M2-26 (device) |
| Cloud latency target | AC-M2-27 (TTFI < 3.0 s; total ≤ 10 s, Q15) |
| Scope: on-device Foundation Models, streaming structured output | AC-M2-05, AC-M2-09, AC-M2-10, AC-M2-11 |
| Scope: opt-in BYOK cloud path under P-3 / ADR-0005 (off by default, consent, minimisation, keys, fallback) | AC-M2-18 (off by default, consent, turn-off), AC-M2-19 (routing), AC-M2-20 (payload), AC-M2-21 (keys), AC-M2-22 (transport), AC-M2-23 (fallback), AC-M2-25 (iPhone 13 speech on device) |

Device criteria AC-M2-11, AC-M2-15, AC-M2-16, AC-M2-17, AC-M2-25, AC-M2-26 and AC-M2-27 stay **AWAITING-DEVICE** until the human owner runs the
Tester's script and the result is recorded (CLAUDE.md §5). M2 cannot be `ACCEPTED` before that.

## Assumptions and open questions
| # | Question | Default if unanswered | Needed by |
|---|---|---|---|
| Q1 | CLAUDE.md §9 item 2: is any Private Cloud Compute or cloud path wanted for M2 (P-3)? | **Resolved 2026-11-21 (D-030, ADR-0005):** yes, an opt-in BYOK cloud path (OpenAI, Anthropic, Gemini), on device first, off by default. Final when the owner merges the policy PR. | Before M2 build |
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
| Q12 | For cloud duplicate checks, may Tend send up to 10 existing task **titles** (pre-filtered on the phone, no IDs, no other fields)? Without them, the cloud can only catch duplicates inside one capture; duplicates of existing tasks are left to a local word-match check, which misses synonyms ("buy dish pods" vs "dishwasher pods"). | **Yes, at most 10 titles**, named on the consent screen. If the owner says no, room names only, and AC-M2-26's duplicate threshold applies to the local check. **Human owner to confirm.** | Before M2 build |
| Q13 | Support a custom endpoint (another "OpenAI-compatible" server, a self-hosted model)? | **No.** Fixed hosts only (ADR-0005). A custom endpoint would let household text go to any server and needs its own ADR. | Before M3 |
| Q14 | May a raw photo or document go to a cloud model (M4 camera and Share Sheet)? | **No by default.** On-device Vision/VisionKit extracts text and only that text is sent. Raw images need an ADR-0005 addendum and a separate consent line in M4. | M4 |
| Q15 | What are the cloud latency targets, and on what network? | TTFI < 3.0 s and total ≤ 10.0 s **per input**, on home Wi-Fi (the run record states the network and a speed-test result). One retry for 429/5xx must fit inside the total. (PO default; the owner may tighten it.) | Before AC-M2-14 is frozen |
| Q16 | Which providers must pass the device eval for M2 to be accepted? | **All three** (OpenAI, Anthropic, Gemini), each with its default curated model, using the owner's own keys (the owner pays the API cost of 3 × 20 inputs). The owner may narrow this to fewer providers for M2. Any provider left out is hidden in the app until it passes, not shipped untested. **Human owner to decide.** | Before M2 build |
| Q17 | Gemini's free tier lets Google use prompts to improve its products, and human reviewers may read them. Tend cannot detect which tier a key is on. | Support Gemini, and show a plain warning on its consent screen recommending a paid-tier key. The owner could choose instead to leave Gemini out. **Human owner to confirm.** | Before M3 copy |
| Q18 | Which model per provider is the default? | The Developer proposes one model per provider in the plan: fast, structured-output capable, and in a curated list that can be updated per release. There is no free-text model ID. The PO approves the list. (PO default) | M2 planning |

## Tester testability review
- [ ] Every AC is observable and measurable  - [x] Device ACs identified (AC-M2-11, 15, 16, 17, 25, 26, 27)  -
  Reviewer note: **v2 returned to PO (Acceptance Tester, 2026-11-21).**
  - Reviewed against ADR-0005 and D-030 as merged in PR #11 (`a6009e8`), CLAUDE.md §2, §3 and §5, and PRD §4 M2.
  - The brief is strong. All 27 ACs name a verification type and the evidence they need. All three PRD §4 M2 gate
    lines are mapped. All seven device ACs are marked AWAITING-DEVICE. No AC is weaker than ADR-0005.
  - I am returning it because six gaps (T-01…T-06) stop me from writing an independent oracle, or stop the device
    runs from being carried out as written. I have not changed any AC meaning.
  - **Owner input received (via Orchestrator, 2026-11-21):** the owner can run tests on their own Apple-silicon Mac
    (M4 Air or M1 mini) with Xcode 26. The Orchestrator may also drive that Mac remotely.
    - This answers Q8. The "macOS lane" for AC-M2-13(b) is an owner-run Mac. Its results are recorded as owner-run
      evidence: who ran it, which Mac, Xcode build, commit SHA and log.
    - The same Mac builds and installs the eval build on both iPhones (T-05).
    - Device ACs still need the human owner to run them on the iPhones. An agent-driven Mac run is fine for Mac ACs.
      It is never evidence for a device AC.
  - Still open with the owner, with the PO defaults treated as current:
    - Q12 affects AC-M2-20, 24 and 26.
    - Q16 affects AC-M2-26 and 27 (how many provider runs, and whose keys).
    - Q17 affects AC-M2-26 and 27 (whether Gemini is run), and AC-M2-20 and 22 (whether Gemini's host stays on the
      list).

  **Where each AC can be proven**
  | Environment | ACs |
  |---|---|
  | Linux container / Linux CI (`swift test`) | AC-M2-01, 02, 03, 04, 06, 08, 12, 19, 20, 23 and 13(a). The scorer self-test and fixture-composition check in 14 (the freeze review is done by the Tester). The source scan in 09, which is a text scan, plus Reviewer review. The platform-neutral logic in 05 (stream assembly), 07 (duplicate rule and candidate provider), 10 (outcome for each neutral availability reason or error), 18 (consent, route and cancel with an in-memory key store) and 24 (the three provider stream parsers fed fixtures). |
  | Owner-run Mac, Xcode 26 (macOS tests or the iOS Simulator) | AC-M2-13(b), 21 (real Keychain, see T-16), 22 (`URLSession` and `URLProtocol`, see T-17). The adapter halves of 05 (`PartiallyGenerated` to neutral snapshot), 07 (the `Tool` conformance), 10 (mapping `SystemLanguageModel.availability` and `GenerationError`), 18(a) (real Keychain delete) and 24 (the cloud adapters end to end over fixtures). Building the eval harness for the devices (T-05). **All of these depend on the owner's Mac answer, which is now yes.** |
  | Device, run by the human owner (AWAITING-DEVICE) | iPhone 15 Pro: AC-M2-11, 15, 16, 17, and the information-only line in 27. iPhone 13: AC-M2-25, 26, 27. |

  *Major (blocks the testability tick):*
  - **T-01 Verification environment per AC.** AC-M2-02…08, 10, 12, 18, 21, 22 and 23 say only "unit". AC-M2-05,
    07, 09, 10 and 24 cross the Linux/Mac line.
    - Each AC needs to name where it runs, using the split above, or the PO's own version of it.
    - Each AC needs to say which part is platform-neutral (in the ingestion layer, on Linux) and which part is an
      adapter (`TendAI`, on the owner's Mac).
    - Q8 and AC-M2-13(b) should be reworded to "an owner-run Mac with Xcode 26". At present they say "a CI lane, or a
      human-recorded Mac run". Q8 can be closed.
  - **T-02 AC-M2-09 import rules break the intended design.**
    - The first bullet lets `TendAI` files outside the cloud-adapter allowlist import only `Foundation`,
      `FoundationModels`, `Speech`, `AVFAudio` and `TendCore`. But the on-device adapter must import the
      platform-neutral ingestion module, because the mapping, stream assembly, routing and `IngestionModel` contract
      live there (ADR-0005 Decision 3, AC-M2-13(a)). As written, a correct design fails the scan.
    - The scan only covers "`TendAI` sources". It leaves out the ingestion layer, which holds the payload builder and
      the parsers, where request bodies and responses exist.
    - On Linux, `URLSession` lives in `FoundationNetworking`, so "Foundation networking" needs to name the module.
    - Fix: name the ingestion module. Add it to the import list for `TendAI`. Give it its own scan rule: `Foundation`
      and `TendCore` only, no networking, and no file or log writes. The builder returns plain values, so it needs no
      networking.
  - **T-03 AC-M2-05 stream rules have no oracle.**
    - "As soon as all its required fields are present": the list of required fields is not given. Q5 gives a default
      for almost every field. The PO needs to say whether a title alone is enough, or whether the title plus kind plus
      `sourcePhrase` is needed.
    - "In input order" could mean the order of items in the model output or the order of `sourcePhrase` in the input.
      These can differ.
    - The brief does not say what happens to an item that is still incomplete when the stream ends early or throws.
      Is it dropped with a typed reason, or emitted with Q5 defaults?
    - The event types need naming: one `emitted` per draft ID, then zero or more `updated` events.
    - AC-M2-16 and 27 inherit this rule, because TTFI is defined by the first *complete* draft.
  - **T-04 The eval scorer is undefined** (AC-M2-14, 15, 17, 26; rubric Q3).
    - Matching: there is no rule for pairing a draft with a golden item. For voice inputs the `sourcePhrase` is a
      substring of the transcript, not of the fixture text, so the rule must survive transcription differences.
      Example: token overlap after folding, then a fixed one-to-one assignment with a tie-break.
    - Denominators: is each percentage over expected items (an unmatched one counts as wrong) or over matched pairs?
    - Room: how is a *proposed new* room scored against the golden set?
    - Item count: the golden set needs a stated minimum number of expected items (for example ≥ 50), so that 95%,
      90% and 85% are whole-number limits.
    - Household: does each input start from a fresh copy of the seeded household, or do the 20 inputs build on each
      other? This changes what counts as a duplicate in AC-M2-17 and 26.
    - False merges: how are they counted against the golden set?
    - The PO may delegate the details to the plan, as Q6 does. If so, the brief must say that the Tester reviews them
      before the AC-M2-14 freeze.
  - **T-05 The device runs have no harness surface and no build path.**
    - AC-M2-11, 15…17 and 25…27 need an app on the iPhone that does the following: captures live voice, runs the 20
      frozen inputs against the seeded household, times TTFI and total time, and writes a results file. But the
      out-of-scope list puts all UI in M3.
    - State that M2 includes a **debug-only eval harness target**. It is never shipped and is left out of the Release
      configuration. It is built and installed from the owner's Mac with Xcode 26 (signing team stated in the plan).
    - Define the results-file format and how the file is exported, for example via Files or AirDrop to the repo.
    - The harness has to record per-request metadata for AC-M2-26: byte count and JSON key paths, never values.
      Reconcile this with AC-M2-09's "request bodies … never written to disk".
  - **T-06 The Q12 pre-filter rule is not deterministic** (AC-M2-20 golden bytes and sentinel oracle; AC-M2-26).
    - With the Q12 default (yes), "same room or shared keywords" needs to be exact:
      - how keywords are found (folding and a stop-word list);
      - how candidates are ranked;
      - the tie-break;
      - the cap of 10;
      - completed tasks are left out (Definitions).
    - If the owner answers no, the golden requests change. The local word-match rule that AC-M2-26 then relies on
      needs the same precision.

  *Minor (fix wording when convenient; does not block on its own):*
  - **T-07 AC-M2-02 / Q5.**
    - Define "out-of-range date" with numbers.
    - "Default dayparts" should cite `Daypart.defaultAllowed` (morning, afternoon, evening).
    - Give the order in which repairs run. For example, an unknown kind becomes a one-off, and then any interval is
      dropped.
    - Say what happens to unknown daypart or weekday *elements*. Suggestion: drop the element, then apply the
      empty-set default.
  - **T-08 AC-M2-03 / Q6 table.** The Tester's review of the plan's table is a Definition of Ready condition for
    AC-M2-03. The table must fix these:
    - the first day of the week (Monday, or the calendar's `firstWeekday`);
    - "this weekend" when said on a Saturday, and on a Sunday evening;
    - how seasons are defined (meteorological or astronomical, and which hemisphere);
    - when "tonight" ends;
    - "end of today" on a DST day;
    - "before <month>" when that month is the current one.
  - **T-09 AC-M2-04 matching.** Say whether whitespace is trimmed and collapsed, whether a leading article is stripped
    ("the kitchen"), and which locale folding uses. State that matching is exact after folding, not fuzzy.
  - **T-10 AC-M2-12 guard rules.**
    - Matching is case-insensitive and on whole tokens split at non-letters.
    - Whitespace is collapsed after a token is removed.
    - "In the user's input" means anywhere in the whole input.
    - The guard also applies to proposed new room names, which are model-generated text.
  - **T-11 Closed token lists for the scans** (AC-M2-09, 21), as in M1 T-05.
    - Media types: `AVAudioBuffer`, `AVAudioPCMBuffer`, `CMSampleBuffer`, `CVPixelBuffer`, `CGImage`, `CIImage`,
      `UIImage`.
    - File-write and log APIs: `write(to:`, `FileManager` create and write, `FileHandle`, `OutputStream`,
      `UserDefaults`, `print`, `debugPrint`, `dump`, `NSLog`, `os_log`, `Logger`, `OSLog`.
  - **T-12 AC-M2-10 / 19 cases.**
    - Add "unsupported language/locale" as an unavailable reason (ADR-0005 Decision 1(a), Q2).
    - The matrix should also cover consent and a key stored for a provider that is *not* selected, and "always use my
      cloud model" while cloud is off.
  - **T-13 AC-M2-11 / 25 pass rules.**
    - "Equal to their online run" is fragile if sampling varies. Suggested rule: each fixed input (IDs named in the
      script) meets the per-item rubric match against the golden set.
    - The harness should use greedy sampling for the on-device model and the lowest-variance setting each provider
      offers, recorded in the results file.
    - AC-M2-25 "parse through the cloud" needs a pass rule. Suggested: route = `cloud(X)`, all drafts valid, and the
      segmentation matches the golden set.
  - **T-14 AC-M2-18 "restored state".** Define it as concrete fixtures. Note that a `ThisDeviceOnly` Keychain item
    can come back when an encrypted backup is restored to the *same* device. Give the rule that keeps cloud off after
    a restore anyway (ADR-0005 Decision 2). Say that a real restore is not exercised on a device in M2.
  - **T-15 AC-M2-20 details.**
    - Golden bytes must be identical on Linux and on the Mac: sorted keys and fixed escaping.
    - Say whether "rejected by type" means the builder's input type cannot carry media (a compile-time and API check)
      or a runtime rejection.
    - For each provider, list its opt-outs explicitly, or state "none offered".
    - PO to decide on room names that contain a person's name, for example "Sam's room". Suggested default: room names
      are user labels and are sent as written. The sentinel generator keeps member-name sentinels out of room names.
      The consent copy says room names are sent.
  - **T-16 AC-M2-21 Keychain environment.** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` needs the data-protection
    keychain. A plain macOS `swift test` with no host app may fail with `errSecMissingEntitlement`.
    - Specify an iOS Simulator test with a host app, run on the owner's Mac (`xcodebuild test`).
    - Assert on the attributes read back (`kSecReturnAttributes`).
    - Define the masked format, and what happens to short keys.
  - **T-17 AC-M2-22 timeout and environment.**
    - Say which timeout is meant (resource or request). The per-attempt timeout plus the one allowed retry must fit
      inside the 10 s total (Q15).
    - Run it on the owner's Mac. `URLProtocol` and redirect handling in Linux `FoundationNetworking` are not reliable
      enough to serve as evidence.
  - **T-18 AC-M2-23 "none blames the user".** This cannot be measured in M2, because M2 has no copy. Make it Reviewer
    inspection of the outcome case names, and leave the copy to the Designer in M3. Test the retry timing with an
    injected clock.
  - **T-19 AC-M2-24 fixtures.**
    - "Recorded" fixtures need real keys and the network. Either the owner records them on the Mac with fixed text
      that holds no household data, or they are synthetic from each provider's documented stream format, plus at
      least one real recording per provider.
    - Say which parts of AC-M2-01…08 apply to cloud output. The `Tool` clause of 07 does not apply; the local
      re-check of the shortlist replaces it.
  - **T-20 Device-run integrity.**
    - At most one retake per voice input, and only when the speaker misread the script. The reason is logged and
      every attempt is kept in the results file. No re-running to get a pass.
    - The run record names: iOS build, app commit SHA, the on-device model or provider model ID, and the network
      with a speed-test result (Q15).
  - **T-21 Traceability gaps.**
    - Q9 (W2-F3) changes an accepted M1 AC (AC-M1-25). Put the new invariant case in an M2 AC clause instead, for
      example in AC-M2-02 (Linux).
    - UX-2 is in scope but has no M2 AC. Say in Gate mapping that AC-M2-13 keeping the M1 `NowSelector` suite green
      covers it.
  - **T-22 AC-M2-13 skips.** A test compiled out on Linux (`#if canImport(...)`) does not count as skipped only if it
    runs on the Mac. The AC → test table gives the environment for every test.

  **Device script outlines** (the full scripts go in `acceptance.md` before the first run; these depend on T-04,
  T-05, T-13 and T-20):
  - **DS-1, iPhone 15 Pro, on device: AC-M2-15, 16, 17, then 11.**
    - Preconditions:
      - iOS 26.x (build recorded). Apple Intelligence on. Model ready. en-US. Cloud off.
      - Speech assets installed.
      - The eval harness from the owner's Mac at the commit under test, with the frozen fixtures (hash recorded) and
        the seeded household loaded.
    - Steps:
      1. Run the 20 inputs in fixture order. Type the text inputs from the fixture. Speak the voice inputs live from
         the printed script. No audio is stored.
      2. Export the results file.
      3. Turn airplane mode on, with Wi-Fi and Bluetooth off. Run the 3 named AC-M2-11 inputs (2 voice, 1 text) and
         export again.
    - Record: per-input TTFI and total time, the cold-start TTFI, the drafts, the rubric scores, duplicates and false
      merges.
    - Pass rules:
      - AC-M2-15: the Q3 thresholds.
      - AC-M2-16: every input has TTFI < 1.5 s and total ≤ 5.0 s.
      - AC-M2-17: 0 duplicates and ≤ 1 false merge.
      - AC-M2-11: each of the 3 meets the rubric offline (T-13).
  - **DS-2, iPhone 13, cloud: AC-M2-25, 26, 27.**
    - Preconditions:
      - iOS 26.x. en-US. On-device model reported as not eligible.
      - Home Wi-Fi, with a speed-test result recorded.
      - For each Q16 provider: consent given and the owner's key stored.
      - Speech assets installed.
    - Steps:
      1. AC-M2-25: in airplane mode, speak the 2 named voice inputs. Record the transcriber used, the calm offline
         outcome, the plain-note offer and that no task was created. Go back online and run the same 2.
      2. AC-M2-26/27: for each provider, run all 20 inputs and export the results. These record the route, timings,
         per-request byte counts and JSON key paths (no values).
      3. Information only: run one provider on the iPhone 15 Pro with "always use my cloud model".
    - Pass rules:
      - AC-M2-25: T-13.
      - AC-M2-26: for each provider, the Q3 thresholds, 0 duplicates, ≤ 1 false merge, and the sent key paths are a
        subset of the AC-M2-20 allowed content.
      - AC-M2-27: every input has cloud TTFI < 3.0 s and total ≤ 10.0 s.
  - All seven device ACs stay **AWAITING-DEVICE** until the human owner's run is recorded in `acceptance.md` with
    who, when, which device and which build.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Capture is voice or free text. Every field is inferred (AC-M2-01…04), and confirmation is a single act (AC-M2-06). No form exists or is needed. |
| UX-2 Rule of Three | pass | No new "what to do now" API. Committed tasks reach Now only through `NowSelection` (≤ 3, M1). The draft review list is defined as a capture review, not a Now surface (Q11). |
| UX-3 Zero-Guilt | pass | Calm-words guard (AC-M2-12). Calm outcomes when the model is unavailable (AC-M2-10). No new state or counter: the M1 model and D-2/D-3 are unchanged. |
| UX-4 Design craft | n.a. | No UI in M2 (M3). |
| P-1 On device first (D-030) | pass | `FoundationModels` is preferred whenever it is available (AC-M2-19). Speech is always on device (AC-M2-09, AC-M2-25), proven offline on device (AC-M2-11, AWAITING-DEVICE). Cloud is used only on the ADR-0005 routes. |
| P-2 Data leaves only via iCloud or a P-3 request (D-030) | pass | Networking only in allowlisted cloud files, only `URLSession`, only three fixed hosts, no SDKs (AC-M2-09, AC-M2-22). The duplicate `Tool` reads only the local household and is never given to a cloud model (AC-M2-07, AC-M2-24). |
| P-3 Cloud AI opt-in and minimised, ADR-0005 (D-030) | pass, **pending owner merge** | Off by default and consent-gated (AC-M2-18). Payload limited to allowed content, proven byte for byte on Linux (AC-M2-20). Keychain only (AC-M2-21). Calm fallback (AC-M2-23). Retention options requested (AC-M2-20); honest disclosure copy is M3. Owner questions Q12, Q16 and Q17 are open. |
| P-4 Media not persisted without consent | pass | Audio and transcripts stay in memory (AC-M2-09). No background queue (AC-M2-23). Nothing is saved before commit (AC-M2-06). Audio and images are never sent to a cloud model (AC-M2-09, AC-M2-20). Eval voice inputs are spoken live and never recorded (AC-M2-15, AC-M2-26). The Privacy Manifest and privacy label, including cloud use, ship with the app target (M3). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Product Owner | Acceptance Tester | to send for testability review | Brief v1 (Draft), written after the M1 gate (ACCEPTED, STATUS.md). 6 stories, 17 ACs (AC-M2-01…17); device ACs AC-M2-11, 15, 16 and 17 are AWAITING-DEVICE. Human-owner questions: Q1 (PCC), Q8 (macOS lane); Q3 thresholds are open to owner tightening. After the Tester's review, the PO hands off to the Work Planner (H1). |
| 2026-11-21 | Product Owner | Orchestrator → human owner | to merge (protected paths) | Brief v2 (still Draft) for D-030 / ADR-0005: the owner chose BYOK cloud AI and an iPhone 13 floor. Added S-M2-07…09 and AC-M2-18…27 (device: AC-M2-25, 26, 27, all AWAITING-DEVICE). Rewrote AC-M2-09 and AC-M2-10, and closed Q1. New owner questions: Q12 (task titles for duplicates), Q16 (which providers gate M2), Q17 (Gemini free tier). Q13, Q14, Q15 and Q18 are PO defaults. Next: the owner merges the policy PR, then the Acceptance Tester runs the testability review of v2, then the Work Planner. |
| 2026-11-21 | Acceptance Tester | Product Owner | returned | Testability review of v2 at `a6009e8`. Six Major items (T-01…T-06) block the tick; T-07…T-22 are Minor. The owner's Mac (Xcode 26) answers Q8 and gives the build path for the device harness. Q12, Q16 and Q17 are still open (PO defaults assumed). Split: Linux 01–04, 06, 08, 12, 19, 20, 23, 13(a) and the logic halves of 05, 07, 09, 10, 14, 18, 24; Mac 13(b), 21, 22 and the adapter halves; device 11, 15, 16, 17, 25, 26, 27 (AWAITING-DEVICE, outlines DS-1 and DS-2). |
