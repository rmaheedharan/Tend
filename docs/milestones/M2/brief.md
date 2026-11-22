# M2 Brief — On-Device AI Ingestion

- **Owner:** Product Owner  ·  **Status:** Draft v4 (2026-11-21). v3 answered the Tester's v2 review (T-01…T-22, now
  closed). v4 answers the v3 review (T-23…T-30). Every change is listed in the "v3 change record" and "v4 change
  record" below. The Tester approved testability (commit `29e2d74`), and the brief is Ready for planning. D-030 and ADR-0005 were merged in PR #11 (`a6009e8`), as the Tester's review records.
  Q12, Q16 and Q17 are still open with the owner. The PO defaults apply until the owner answers.
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
    - The one exception is the **debug-only eval harness** (`TendEval`, AC-M2-28). It is a test tool, not product
      UI. It is never shipped and is not judged against UX-4.
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
- **Modules (binding names for the scans; a rename needs a PO decision that updates AC-M2-09):**
  - **`TendIngestion`** is the platform-neutral ingestion layer. It imports only `Foundation` and `TendCore` and
    builds and tests on Linux. It holds:
    - the neutral model contract (`IngestionModel` snapshots and events);
    - mapping and Q5 repairs, the Q6 time resolver and room linking;
    - stream assembly, the duplicate rules and the shortlist;
    - the calm-words guard, routing, consent and route logic, the payload builder and the three provider stream
      parsers;
    - failure and retry decisions, commit, and the eval scorer.
  - **`TendAI`** holds the Apple-framework adapters: the on-device `FoundationModels` and `Speech` adapters, and the
    cloud adapters, transport and key store (cloud-adapter allowlist files only). It builds and tests on the owner-run
    Mac.
  - **`TendEval`** is the debug-only eval harness app target (AC-M2-28).
- **Environments (T-01):**
  - **Linux** means `swift test` on Linux CI or the Linux container.
  - **Owner-run Mac** means the human owner's Apple-silicon Mac (MacBook Air M4 or Mac mini M1) with Xcode 26
    installed. It runs `xcodebuild test` for macOS or the iOS Simulator. The owner runs it, or an agent drives that Mac
    remotely for the owner.
    - Its evidence record states: who ran it, which Mac and macOS build, the Xcode build, the commit SHA, the exact
      command and the full log.
    - A Mac run is never evidence for a device AC.
  - **Device** means an iPhone run by the human owner. Its status stays AWAITING-DEVICE until the run is recorded.
- **Draft (`IngestionDraft`), the field set (T-03):**
  - `draftID`: a per-parse number (1, 2, 3 …) in emission order. It is not a task ID.
  - `title`: non-empty after trimming and the calm-words guard.
  - `kind`: `TaskKind`.
  - `room`: one of `existing(roomID)`, `proposed(name)` or `none`.
  - `effort`: `Effort`.
  - `isCritical`, `isDeepClean`, `isWeatherDependent`.
  - `allowedDayparts`, `allowedWeekdays`, `windowStart`, `windowEnd`, `recurrenceIntervalDays`. The Q6 resolver
    computes these from the model's structured time hint. The model never sends dates.
  - `sourcePhrase`: optional. It is the user's own words for the item. It is kept only if it occurs in the input as a
    substring after name folding. Otherwise it is `nil`.
  - `duplicate`: one of `none`, `ofExisting(taskID)` or `ofDraft(draftID)`.
  A draft is not in the household until it is **committed**.
- **Item completion (T-03):** an item in the model's output is **complete** at the first of these moments:
  - (a) every field of its output schema has a value, where an unknown enum value counts as a value;
  - (b) the model has started the next item;
  - (c) the stream finishes normally.
  On completion, the Q5 repairs fill any missing field. The only **required** field is `title`. An item with no
  usable title is skipped with a typed reason and is never emitted.
- **Draft stream events (T-03):** the pipeline returns an `AsyncSequence` that never throws. Its events are:
  - `emitted(draft)`: exactly once per `draftID`, at completion, in the order items appear in the **model's output**
    (not the order of `sourcePhrase` in the input). The duplicate marker is already set.
  - `updated(draft)`: zero or more per `draftID`, only after that draft's `emitted`. It is a full replacement with the
    same `draftID`, including its duplicate marker: when an update changes a draft, the duplicate marker of that draft
    and of every later draft is computed again on the latest drafts, and every draft whose content or marker changes
    gets an `updated` (PO 2026-11-21, WI-M2-06 Q5). A draft is never withdrawn.
  - `itemSkipped(reason)`: an item dropped by Q5. It has no `draftID`.
  - `finished(outcome)`: exactly once, and always last. The outcome is one of:
    - **completed:** the stream finished normally. If no draft was emitted (the output had no items, or every item was
      skipped), the input text and a plain-note offer are also returned, as for `noModel` (PO 2026-11-21, WI-M2-06 Q1).
    - **interrupted:** the stream ended with an error or was truncated after it started. Drafts already emitted stay
      available for confirmation. The in-progress, not yet complete item is discarded with a typed reason. The input
      text is returned in memory. No plain note is offered: a stop before any draft is `noModel` (T-25), so an
      `interrupted` outcome always has at least one draft.
    - **noModel:** there was no usable model, or the model returned an error, a refusal or a guardrail before any
      draft. No draft is emitted. The input text and a plain-note offer are returned.
    - **cancelled:** nothing is written.
    Every outcome carries the route.
  The Developer picks the Swift case names. Each must pass the banned-token rule (AC-M2-10, AC-M2-12).
  - **TTFI** ends at the first `emitted` event. **Total time** ends at `finished`.
- **Name folding** (rooms, `sourcePhrase` and room keywords; T-09), applied to both sides:
  - Trim, and collapse runs of whitespace to one space.
  - Map typographic apostrophes and quotes to ASCII.
  - Fold with `[.caseInsensitive, .diacriticInsensitive, .widthInsensitive]` in the fixed `en_US_POSIX` locale.
  - Strip one leading article: "the", "a", "an", "my" or "our".
  - Matching after folding is exact equality, never fuzzy. There is no plural or stem folding.
- **Keywords of a text** (the shortlist, the local word-match and the scorer):
  - Fold as in name folding, without stripping the article.
  - Split at every character that is not a Unicode letter or decimal digit, and drop empty tokens.
  - Drop the stop words, and keep the distinct remaining tokens. There is no stemming.
  - The closed stop-word list is: a, an, the, and, or, but, of, to, in, on, at, for, with, from, by, about, before,
    after, this, that, these, those, it, its, is, are, be, been, was, were, we, us, our, i, me, my, you, your, re, s, t,
    ll, ve, d, m, need, needs, let, lets, get, got, some, any, all, more, almost, out, up, again, also, just, really,
    please, maybe, should, must, can, will, would, could, do, does, did, have, has, had, if, then, so, too, very, no,
    not, wait, um, uh, like, okay, ok.
  - Changing this list after the AC-M2-14 freeze needs a PO decision.
- **Duplicate shortlist (Q12 pre-filter; T-06), deterministic.** Input: a query text Q and the household.
  1. Candidates are the household's tasks whose state is not `completed`.
  2. For each candidate t, K(t) is the number of distinct keywords in both Q and t's title.
  3. R(t) = 1 when t has a room and every keyword of that room's name is a keyword of Q. A room name with no keywords
     never matches. Otherwise R(t) = 0.
  4. t is shortlisted when K(t) ≥ 1 or R(t) = 1.
  5. Rank by K descending, then R descending, then the keyword-folded title in ascending UTF-8 byte order, then
     `id.uuidString` in ascending byte order.
  6. Keep at most the first **10**. Number them 1…n in rank order.
  Two callers use it:
  - The on-device duplicate `Tool`: Q is the Tool's query argument. It returns title, kind and room name per entry.
  - The cloud payload, when Q12 is yes: Q is the capture text. It sends only the title as stored (trimmed) and the
    index number.
- **Local duplicate re-check for cloud drafts:**
  - **When Q12 is yes:** a cloud draft that names shortlist index n becomes `ofExisting(shortlist[n].id)` only when
    1 ≤ n ≤ the shortlist count. Any other index is ignored, and the draft is not marked. A cloud draft that names an
    earlier item k of the same response becomes `ofDraft(k)` only when k is lower than its own position. Commit checks
    each `ofExisting` target again. If the target is missing or `completed`, the draft is treated as not a duplicate.
  - **When Q12 is no (local word-match):** a cloud draft is marked `ofExisting(t)` when all of these are true:
    - t is not `completed`;
    - both titles have keywords;
    - the keyword sets are equal, or the smaller is a subset of the larger and has ≥ 2 keywords;
    - the rooms are compatible: either side has no room, or both are the same existing room (a proposed room never
      equals an existing room).
    If several tasks qualify, the one with the most shared keywords wins, then the lowest `id.uuidString`.
- **Word-match floor (every path; PO 2026-11-21, WI-M2-07 Q1):** a draft with no valid in-input claim and no valid
  existing-task claim (on device: a title the `Tool` returned in this parse; cloud with Q12 = yes: a valid shortlist
  index) is checked on the phone with the local word-match rule above against the whole household, and is marked
  `ofExisting(t)` when it qualifies. Order per draft: in-input claim, then the model's existing-task claim, then this
  floor. It sends nothing. With Q12 = no it is the only existing-task check, as before.
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
  user's own key under ADR-0005.
  - At most one provider is **selected** at a time.
  - **Cloud on** means the selected provider has a consent record and a stored key. Anything else is **cloud off**,
    which is the default.
  - A consent record or key for a provider that is not selected never makes cloud on (T-12).
  - A stored key with no consent record for its provider is deleted the first time a route is chosen (T-14).
- **Route:** which model handles a capture: `onDevice`, `cloud(provider)` or `none`. ADR-0005 Decision 1 sets the
  route (AC-M2-19).
- **Cloud request:** the exact bytes (method, host, path, header names, body) the payload builder produces for one
  capture. **Allowed request content** is ADR-0005 Decision 3: fixed instructions and schema, the one capture's text,
  room names, and (only if Q12 is yes) at most 10 task titles with per-request index numbers.
  - The titles come from the duplicate shortlist above.
  - Room names and titles are user labels and are sent as the user wrote them (Q19).
  - The payload builder's input type holds only the capture text (`String`), the room names (`[String]`) and the
    shortlist titles (`[String]`). A pure, separate context selector derives them from the household.
- **Plain note:** one draft whose title is the user's own words (trimmed), with the Q5 default fields and no inference.
- **Banned tokens:** the AC-M1-02 list (*overdue, late, lateness, missed, failed, behind, penalty, debt, streak*).
  - In source code and case names they are matched as AC-M1-02 does.
  - In generated text they are matched as whole tokens: split at non-letters, then name-fold.

## Stories

### S-M2-01 One messy sentence becomes separate, valid tasks  (FR-A1, D-016)
As a person carrying the household in my head, I want to say everything at once and have Tend split it into proper
tasks, so that I never sort or fill anything in myself.

**Acceptance criteria**
- **AC-M2-01** Given a scripted mock model output for each PRD item type (one-off errand, recurring maintenance,
  consumable restock, weather-dependent task), when the pipeline maps it, then each draft becomes a `HouseholdTask` that
  passes the M1 initialiser, with the expected kind, room, effort and flags. Date fields are computed only from the
  injected `now`, calendar and time zone.  *Verification:* unit (parameterised)  *Environment:* Linux (`TendIngestion`
  mapping).  *Evidence expected:* test name + log.
- **AC-M2-02** Given ≥ 1,000 seeded random structured outputs, when they are mapped, then the pipeline never crashes
  and never emits an invalid task.
  - The outputs include degenerate ones: missing or blank title, empty dayparts or weekdays, unknown daypart or
    weekday elements, end ≤ start, critical + deep clean, interval on a one-off, a recurring task with no interval or
    with an interval outside 1…730 days, non-finite or out-of-range time hints, and unknown enum values.
  - Each item is repaired by exactly the Q5 rules, **in the Q5 order**, or it is skipped calmly with a typed reason
    (`itemSkipped`).
  - The result equals an independent oracle of Q5.
  - **(W2-F3, Q9; T-21)** `TendCore` gains one `TaskInvariantViolation` case for a non-finite `windowStart` or
    `windowEnd` (the Designer names it). Constructing such a task throws it. A JSON file whose date decodes to a
    non-finite value is rejected by both M1 repositories with a typed error, as in AC-M1-06. The parser never produces
    one.
  *Verification:* unit (property, fixed seeds; plus one parameterised case for the new invariant)  *Environment:*
  Linux.  *Evidence expected:* test name, seed range, counts per repair rule.
- **AC-M2-03** Given the time phrases in the Q6 table, each the way the model reports it as a structured time hint,
  when they are resolved at fixed `now` values (including a DST day and a year boundary), then the window, dayparts,
  weekdays and interval equal the table exactly. The table must settle every point in Q6 (T-08). The Tester's review of
  the plan's table is a Definition of Ready condition for this AC.  *Verification:* unit (parameterised)
  *Environment:* Linux.  *Evidence expected:* test name + log.
- **AC-M2-04** Given a household with rooms, when a draft names a room, then:
  - It is linked to the existing room whose name equals it after **name folding** (Definitions; exact, not fuzzy).
  - If several rooms fold to the same name, it is linked to the room with the lowest `id.uuidString`.
  - If none matches, it carries `proposed(name)`, where the name is the model's text after the calm-words guard. If the
    guard leaves it empty, the room is `none`.
  - A proposed room is created only on commit. If two confirmed drafts propose names that fold to the same name, one
    room is created.
  - No room is created or renamed during parsing.
  *Verification:* unit (parameterised)  *Environment:* Linux.  *Evidence expected:* test name + log.

### S-M2-02 I see each item as soon as Tend understands it  (FR-A1 feedback)
As someone in the middle of a busy moment, I want each item to appear as soon as it's recognised, and nothing to stick
unless I say so, so that capture feels instant and safe.

**Acceptance criteria**
- **AC-M2-05** Given a mock model that streams partial snapshots, when the pipeline consumes it, then the event
  sequence obeys the **draft stream events** and **item completion** rules (Definitions) exactly. The snapshots cover
  fields that arrive out of order, an item split across snapshots, an item with no title, a stream that finishes
  normally mid-item, a stream that throws mid-item, and cancellation.
  - There is exactly one `emitted` per `draftID`, at the moment of completion, in model-output order.
  - `updated` events come only after `emitted`, with the same ID. A draft is never withdrawn. After `finished`, each
    draft's duplicate marker equals what the duplicate rules give for the final drafts in `draftID` order.
  - An item still in progress when the stream **finishes normally** is completed and repaired (Q5), then emitted if it
    has a title.
  - A stream that finishes normally with no draft emitted (no items, or every item skipped) ends with `completed`, the
    input text and a plain-note offer.
  - An item still in progress when the stream **throws** is discarded with a typed reason. Earlier drafts stay. The
    outcome is `interrupted`.
  - `finished` comes exactly once and last. The sequence never throws.
  - Cancelling ends the sequence with `cancelled`, and no task is written.
  - The test oracle is a scripted list of snapshots with the exact event list expected.
  *Verification:* unit  *Environment:* Linux for stream assembly over neutral snapshots (`TendIngestion`). Owner-run
  Mac for the on-device adapter's mapping of `streamResponse` `PartiallyGenerated` snapshots to neutral snapshots
  (`TendAI`).  *Evidence expected:* test names + logs from both environments.
- **AC-M2-06** Given any parse, when it runs, then nothing is written to the `HouseholdRepository`. When
  `commit(confirmed:)` runs, then:
  - Exactly the confirmed drafts that are not duplicates are upserted, together with their proposed rooms. The
    `ofExisting` targets are checked again at commit (Definitions). A confirmed `ofDraft(k)` is never created; if
    draft k is not committed, that chore is not created.
  - Dismissed drafts and drafts left unconfirmed are not saved.
  - Each new task and room gets its ID from an injected ID generator. No two tasks in the household ever share an ID
    (W3-F6). If the generator returns an ID already in use, commit takes the next one and never overwrites.
  *Verification:* unit (contract over both M1 repositories, plus a property)  *Environment:* Linux.  *Evidence
  expected:* test name + log.

### S-M2-03 Never the same chore twice  (FR-A1)
As someone who mentions the dishwasher pods every other day, I want Tend to know when something is already on my list,
so that my list never doubles up.

**Acceptance criteria**
- **AC-M2-07** Given a household and drafts (mock model plus the duplicate-lookup `Tool`), when duplicates are checked,
  then a draft matching an existing non-completed task is marked `duplicateOf(existingID)` and commit creates nothing
  for it. The existing task is not changed in M2 (Q7). A repeat within one input collapses into its first draft. A
  match against a completed one-off or restock task is not a duplicate. A draft the model did not validly mark is then
  checked with the **word-match floor** (Definitions) on every path.
  - The `Tool` returns exactly the **duplicate shortlist** for its query (Definitions): at most 10 entries, only from
    the local household, and only title, kind and room name for each.
  - The shortlist and the local word-match rule (Definitions) equal an independent oracle over ≥ 500 seeded households
    (T-06). The cases include:
    - ties at every ranking step;
    - more than 10 eligible tasks;
    - completed tasks, which must be left out;
    - room-only matches;
    - stop-word-only queries, which give an empty shortlist.
  *Verification:* unit  *Environment:* Linux for the duplicate rule, the shortlist and the in-input collapse
  (`TendIngestion`). Owner-run Mac for the `Tool` conformance, which must return exactly the shortlist's entries and
  fields (`TendAI`).  *Evidence expected:* test names + logs from both.
- **AC-M2-08** Given ≥ 500 seeded households and draft sets, including planted duplicates by exact title, by synonym
  (scripted in the mock) and within one input, when commit runs, then no committed task is a duplicate of another
  non-completed task under the deterministic rule the mock scripts, and no ID is repeated. The same holds for cloud
  drafts marked through the local re-check, for both Q12 = yes and Q12 = no. Every planted exact-title duplicate whose
  room is compatible (word-match rule) is marked on every path, whether or not it was on the Q12 shortlist.
  *Verification:* unit (property)
  *Environment:* Linux.  *Evidence expected:* test name, seeds and counts.

### S-M2-04 What I say stays on my phone unless I chose a cloud model  (FR-A1, P-1, P-2, P-3, P-4)
As a person speaking about my home, my bills and my family, I want all of it understood on my phone, nothing sent
anywhere I didn't choose, and nothing kept that I didn't keep, so that I can talk freely.

**Acceptance criteria**
- **AC-M2-09** Given all `.swift` files under the `Sources` of `TendIngestion`, `TendAI` and `TendEval`, with
  comments removed (the AC-M1-23 approach), when the source scan runs, then each rule below holds. The scan logs the
  number of files it scanned for each module (> 0). A negative test plants one hit for each rule and shows that the
  scanner catches it.
  - **M2 Q24 list plants.** One plant for each pattern added by M2 Q24 is caught on its own, in TendIngestion, as a
    parameterised test. This covers:
    - every session-method call;
    - `write(toFile:`, `AppStorage`, `SceneStorage`, `archiveRootObject(`;
    - each C call on the write and log lists.
  - **Also caught:**
    - `import Darwin` in TendEval, and `fwrite(` in TendEval, each on its own;
    - `@AppStorage("k") var key = ""` in TendEval;
    - `let t = s.uploadTask(with: r, from: d)` and `let w = s.webSocketTask(with: r)` in an allowlisted Rule 3 file;
    - `session.bytes(for: request)` (no `delegate:`) in an allowlisted Rule 3 file;
    - `let f = s.dataTask` in an allowlisted Rule 3 file is caught.
    - `Data(contentsOf: u)` in a TendAI file outside the allowlist, in an allowlisted Rule 3 file, and in a TendEval
      file other than the loader.
  - **Caught in the fixtures-loader file:**
    - `func load(_ u: URL) throws -> Data { try Data(contentsOf: u) }`
    - `Bundle.main.resourceURL!.appendingPathComponent("x.json")`
    - `Bundle.main.url(forResource: "../x", withExtension: "json")`
    - `String(contentsOf:`
    - `let u = URL(fileURLWithPath: "/tmp/x.json")`, and `NSURL(fileURLWithPath: "/tmp/x.json")` (caught by the
      networking list)
    - `func load(_ u: Path) throws -> Data { try Data(contentsOf: u) }` together with a separate
      `let u = Bundle.main.url(forResource: "fixtures", withExtension: "json")` is caught.
  - **Positive (not reported):**
    - In the loader file, exactly
      `guard let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") else { throw LoaderError.missing }; return try Data(contentsOf: u)`.
    - In an allowlisted Rule 3 file, exactly
      `let (stream, response) = try await session.bytes(for: request, delegate: redirectRefuser)`.
    - Anywhere: `inputs(`, `snprintf(`, `metadata(for:`, `reprint(`, `data(forKey:`, `append(contentsOf:)` and
      `insert(contentsOf:at:)`.
  - The Reviewer confirms that the loader reads only bundle resources.
  - **Lists used by the rules (closed; T-11):**
    - **Networking patterns:** the AC-M1-23 networking patterns, plus `FoundationNetworking`, `URLSession`,
      `URLRequest`, `URLProtocol`, `URLSessionConfiguration`, `URL(string:`, `URLComponents`, `NWConnection`,
      `import Network`, `import CFNetwork`, `SFSpeech`, and the session-method calls `dataTask(`, `uploadTask(`,
      `downloadTask(`, `streamTask(`, `webSocketTask(`, `data(for:`, `data(from:`, `bytes(for:`, `bytes(from:`,
      `upload(for:`, `upload(from:`, `download(for:`, `download(from:`, `download(resumeFrom:` (M2 Q24).
    - **Media types:** `AVAudioBuffer`, `AVAudioPCMBuffer`, `AVAudioFile`, `AVAsset`, `CMSampleBuffer`,
      `CVPixelBuffer`, `CVImageBuffer`, `CGImage`, `CIImage`, `UIImage`, `NSImage`.
    - **Write APIs:** `write(to:`, `write(toFile:`, `FileManager`, `FileHandle`, `OutputStream`, `createFile(`,
      `UserDefaults`, `NSUbiquitousKeyValueStore`, `AppStorage`, `SceneStorage`, `archiveRootObject(`, `fopen(`,
      `freopen(`, `fdopen(`, `fwrite(`, `fputs(`, `fputc(`, `mkstemp(`, `tmpfile(`, `creat(` (M2 Q24).
    - **Log APIs:** `print(`, `debugPrint(`, `dump(`, `NSLog(`, `os_log(`, `os_signpost(`, `Logger`, `OSLog`,
      `printf(`, `fprintf(`, `vprintf(`, `vfprintf(`, `dprintf(`, `puts(`, `putc(`, `putchar(`, `perror(`, `syslog(`
      (M2 Q24).
    - "Write and log APIs" in the rules below means both lists.
    - **How call patterns match (M2 Q24):**
      - Every call pattern (a name followed by `(`) matches only when the character before the name is not a letter,
        digit or `_`. A `.` receiver is fine.
      - Matching is case-sensitive.
      - Whitespace and newlines are ignored between the name and `(`, and between `(` and the first label. Backticks
        around the name are removed first.
      - So `inputs(` does not match `puts(`, `snprintf(` does not match `printf(`, and `fprintf(` and `fputs(` are
        their own patterns.
      - Type-name patterns (`Logger`, `FileManager`, `OSLog`, `AppStorage` and the rest) keep the AC-M1-23 camelCase
        word-boundary rule, and so do the inherited AC-M1-23 patterns. This bullet relaxes none of them.
      - The task-creating names `dataTask`, `uploadTask`, `downloadTask`, `streamTask` and `webSocketTask` also match
        as whole tokens without `(` (method references).
  - **Rule 1, `TendIngestion`:**
    - The only imports are `Foundation` and `TendCore`.
    - None of the full AC-M1-23 closed list (clock, randomness, locale and networking) occurs, apart from
      `Locale(identifier: "en_US_POSIX")`.
    - No networking pattern, no media type and no write or log API occurs.
    - The payload builder returns plain values (provider, path, header names, body bytes), so it needs no networking.
    - **Scorer I/O (T-26):** the scorer in `TendIngestion` takes the results file and fixtures as `Data` and returns
      a value. Reading files and writing the scorer log happen outside `TendIngestion/Sources`, in its test target or
      in a named scoring tool. The plan names the tool and the exact scoring command.
  - **Rule 2, `TendAI` outside the cloud-adapter allowlist:**
    - The only imports are `Foundation`, `FoundationModels`, `Speech`, `AVFAudio`, `TendCore` and `TendIngestion`.
    - No networking pattern and no write or log API occurs.
    - No `contentsOf:` argument label occurs (the AC-M1-23 rule), except in calls named exactly `append` or `insert`
      (AC-M1-23 exception (ii)). AC-M1-23 exception (i), the TendCore file repository, does not apply here.
    - Media types appear only in the speech adapter files, which are named in the plan.
  - **Rule 3, `TendAI` cloud-adapter allowlist (a fixed list of file paths in the plan):**
    - The only imports are those in Rule 2, plus `Security`. `FoundationNetworking` is never imported, because
      `TendAI` is Apple-only.
    - **Allowed networking subset (closed; T-23):**
      - `URLSession`, `URLSessionConfiguration`, `URLSessionTask`, `URLSessionTaskDelegate`;
      - `URLSession.AsyncBytes` and the streaming read, a `bytes(for:` call whose argument list contains `delegate:`
        (checked like AC-M1-23's `using:` rule).
      - `URLRequest`, `URL`, `URLComponents` (the one way to build the URL from the builder's host and path);
      - `URLResponse`, `HTTPURLResponse`, `URLError`.
    - **Scan rule:** in an allowlisted file, every networking-pattern hit, and every identifier token that starts with
      `URL`, `NSURL`, `HTTP`, `NW`, `CFHost`, `CFStream` or `CFNetwork`, must be in the allowed subset. In particular,
      `URL(string:`, `URLSessionWebSocketTask`, `URLSessionStreamTask`, `URLSessionUploadTask`,
      `URLSessionDownloadTask`, `URLSessionDataDelegate`, `URLProtocol` and `URLCache` are hits. Setting
      `configuration.urlCache = nil` and `httpCookieStorage = nil` uses lower-case properties and is not a hit.
    - **Session methods (M2 Q24):**
      - The only session-method call allowed is a `bytes(for:` call whose argument list contains `delegate:`.
      - Every other session-method call in the networking list is a hit, even when its task type is inferred.
      - `bytes(for:` without `delegate:` is a hit.
    - No `contentsOf:` argument label occurs (the AC-M1-23 rule), except in calls named exactly `append` or `insert`
      (AC-M1-23 exception (ii)). AC-M1-23 exception (i) does not apply here.
    - **Negative test:** one planted hit just outside the subset (`URLSessionWebSocketTask`) and one `URL(string:`
      must both be caught, and a file that uses only the subset must pass.
    - Test targets may use `URLProtocol` for mocks; the scan covers `Sources` only.
    - No provider SDK or third-party module is imported.
    - No media type and no write or log API occurs.
  - **Rule 4, host literals in all three modules (T-30):**
    - A literal is **host-like** when it contains `://`, or when the **whole literal** matches
      `(?i)^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|net|org|io|ai|dev|app|co|cloud)(:\d+)?(/\S*)?$`.
      - Reverse-DNS strings such as bundle IDs and Keychain service names (`com.tend.eval`, `tend.ai.key`) are not
        host-like.
    - Every host-like literal is exactly one of `api.openai.com`, `api.anthropic.com` and
      `generativelanguage.googleapis.com`, or `https://` followed by one of them.
    - **Where they may appear (T-26):**
      - The payload builder's provider table in `TendIngestion` holds the **bare hosts** only.
      - `https://` literals appear only in allowlisted cloud-adapter files.
    - **Negative test:** `tend.ai.key` passes, while `api.example.com` and `https://api.example.com/v1` are caught.
  - **Rule 5, speech:** speech uses only `SpeechAnalyzer` with `SpeechTranscriber` or `DictationTranscriber`. No
    `SFSpeech*` API (the server-capable recogniser) occurs, with one exception (T-27).
    - If the Developer confirms on the owner-run Mac during planning that iOS 26 still needs it for `SpeechAnalyzer`,
      exactly `SFSpeechRecognizer.requestAuthorization(` and `SFSpeechRecognizer.authorizationStatus(` (with the
      `SFSpeechRecognizerAuthorizationStatus` type) are allowed.
    - They are allowed in one speech-permission file named in the plan, and only there.
    - If the Developer finds they are not needed, there is no exception.
    - **Negative test:** an `SFSpeechRecognizer(` initialiser in the speech-permission file is caught.
  - **Rule 6, `TendEval` (AC-M2-28):**
    - **Imports (M2 Q24):**
      - The only imports are `Foundation`, `SwiftUI`, `CryptoKit` (for the fixtures SHA-256), `TendCore`,
        `TendIngestion` and `TendAI`.
      - The module is the first path component after `import` and any kind keyword (`import struct Darwin.C` is
        `Darwin`).
      - Attributes such as `@preconcurrency` are ignored. `@_exported` and `@_implementationOnly` imports count.
      - So `Darwin`, `Glibc`, `FoundationNetworking`, `Network`, `CFNetwork`, `os`, `AVFAudio`,
        `UniformTypeIdentifiers` and every third-party module are hits.
      - Any other import needs a PO decision.
    - No networking pattern occurs.
    - No `contentsOf:` argument label occurs (the AC-M1-23 rule), except:
      - in calls named exactly `append` or `insert` (AC-M1-23 exception (ii));
      - under the fixtures-loader exception below.

      AC-M1-23 exception (i), the TendCore file repository, does not apply here.
    - **Fixtures-loader exception (M2 Q23).** One file, the fixtures loader named in the plan
      (`Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift`), may read bundled fixtures with `Data(contentsOf:`.
      This is the only `contentsOf:` exception in AC-M2-09 beyond AC-M1-23 exception (ii). In that file, all of these
      hold, and matching is case-sensitive:
      - The only `contentsOf:` form is `Data(contentsOf: <name>)`. `<name>` is one plain identifier and there are no
        other arguments. It is bound in the same file by `let <name> = Bundle.main.url(forResource:`,
        `guard let <name> = Bundle.main.url(forResource:` or `if let <name> = Bundle.main.url(forResource:`.
      - `<name>` is bound exactly once in the file, in the same function body and before the `Data(contentsOf:` call.
        No function, initialiser, subscript or closure in the loader file declares a parameter.
      - The whole token `URL` does not occur.
      - The only use of `Bundle` is `Bundle.main.url(forResource:`. `Bundle(`, `.resourceURL`, `.bundleURL`,
        `.urls(forResourcesWithExtension:`, `.path(forResource:`, `appendingPathComponent(`, `appending(path:`,
        `appending(component:` and `deletingLastPathComponent` are hits.
      - The `forResource:` and `subdirectory:` arguments are string literals matching `^[A-Za-z0-9_-]+$`.
      - The `withExtension:` argument, if present, is a string literal matching `^[A-Za-z0-9]+$`.
      - Identifiers, array elements and interpolated strings are not allowed as these arguments.
      - No literal contains `://`. No write or log API occurs.
      - The loader returns the bytes as `Data` and keeps nothing.
    - **Write APIs:** they occur in exactly one file, the results writer named in the plan. It writes only the
      results-file type, which holds no audio, request body, response body or key fields.
    - **Log APIs:** they never occur.
  - **Reviewer:** the Reviewer confirms that audio buffers, request bodies, responses and keys are never persisted or
    logged anywhere in the three modules. Transcripts are never persisted in `TendIngestion` or `TendAI`. The only
    exception is `TendEval`, which records the transcript of a **scripted eval utterance** and the parsed drafts in its
    results file (AC-M2-28).
  *Verification:* unit (source scan) + Reviewer  *Environment:* Linux (text scan, run from the `TendIngestion` test
  target over the repository paths) + Reviewer.  *Evidence expected:* test name + log with file counts + negative
  test + review note.
- **AC-M2-10** Given a brain-dump is submitted, then the pipeline ends with the calm typed outcome `noModel`
  (Definitions) in each case below. It makes no network call (the mock transport records zero requests), creates no
  task, and returns the input text in memory so that M3 can keep it if the user wants. No outcome name or string
  contains a banned token. The cases are:
  - **cloud off** with each on-device reason that is not available: device not eligible, Apple Intelligence not
    enabled, model not ready, and **unsupported language or locale** (T-12; Q2; ADR-0005 Decision 1(a));
  - **cloud on or off** with a mock in which on-device generation throws **before the first draft is emitted**
    (guardrail, context too long, any other generation error; T-25). A throw after the first draft gives
    `interrupted` (AC-M2-05). Either way, the route never changes to the cloud.
  *Verification:* unit  *Environment:* Linux for the outcome for each neutral reason (`TendIngestion`). Owner-run Mac
  for the adapter mapping of every `SystemLanguageModel.Availability` case, `supportsLocale` and every
  `LanguageModelSession.GenerationError` case to a neutral reason (`TendAI`; an exhaustive switch with no `default`).
  *Evidence expected:* test names + logs from both.
- **AC-M2-11** (device) Given an iPhone 15 Pro in airplane mode, with Wi-Fi and Bluetooth off, when the 3 eval inputs
  named in the device script (2 voice, 1 text) are run, then for each input (T-13):
  - the route is `onDevice` and the outcome is `completed`;
  - every golden item of that input is matched, and there are 0 extra drafts (the scoring rules);
  - every draft passes the M1 invariants;
  - there are 0 introduced banned tokens and 0 duplicates created.
  Field accuracy is gated by AC-M2-15, not here.  *Verification:* device-script  *Environment:* Device (DS-1).
  *Evidence expected:* human-recorded run (date, device, iOS build, results file). **Status until run:
  AWAITING-DEVICE.**

### S-M2-05 Tend's words are always calm  (UX-3)
As someone who already feels behind, I want Tend never to add a guilt word, so that capture never stings.

**Acceptance criteria**
- **AC-M2-12** Given mock outputs whose titles and proposed room names contain banned tokens, some present in the input
  and some not, when the calm-words guard runs, then (T-10):
  - Tokens are split at non-letters and compared after name folding, as whole tokens.
  - Any banned token that does **not** occur anywhere in the whole input (the typed text or final transcript) is
    removed from the title and from a proposed room name.
  - After a removal, whitespace runs collapse to one space, and whitespace and punctuation are trimmed at both ends.
  - If a title would then be empty, it becomes the draft's `sourcePhrase`. If that is `nil` or also empty, the item is
    skipped with a typed reason. If a proposed room name would be empty, the room becomes `none`.
  - Banned tokens that the user said are kept, because they are the user's words.
  - Model instructions (on-device and cloud) and every outcome and reason name contain no banned token.
  *Verification:* unit (parameterised)  *Environment:* Linux.  *Evidence expected:* test name + log.

### S-M2-06 Proven on a real iPhone 15 Pro, on device  (gate)
**Acceptance criteria**
- **AC-M2-13** **(Gate)** Given the M2 merge commit, when the automated suites run, then 100% of tests pass with 0
  failures, 0 skipped or disabled tests and 0 warnings (`-warnings-as-errors`), in two places:
  - **(a) Linux CI:** `swift test` for `TendCore` and `TendIngestion`. `TendIngestion` holds the mapping, stream
    assembly, duplicate and shortlist rules, the calm-words guard, routing, the payload builder, the provider stream
    parsers, the failure and retry rules, commit and the eval scorer.
  - **(b) Owner-run Mac with Xcode 26:** `xcodebuild test` for the `TendAI` mock and adapter tests, and the iOS
    Simulator host-app tests (AC-M2-21). The plan gives the exact commands. The record is the owner-run Mac evidence
    record (Definitions).
  - The M1 suite stays green, including the `NowSelector` suite that carries UX-2.
  - **Skips (T-22):** a test compiled out on Linux (`#if canImport(...)`) does not count as skipped only if it runs in
    (b). No test may be absent from both (a) and (b).
  - Every other M2 AC maps to at least one named test or device step. The AC → test table gives the environment of
    every test.
  *Verification:* CI run + owner-run Mac run  *Environment:* Linux (a) and owner-run Mac (b).  *Evidence expected:*
  CI run link + Mac evidence record + log excerpts + AC → test table with environments.
- **AC-M2-14** Given the eval fixtures and scorer, when they are reviewed before the first device run, then:
  - The 20 inputs, the seeded household (with match groups for each task) and the golden expectations meet the Q3
    composition and the **eval scoring rules** below. They hold **≥ 50 expected items** in total, with ≥ 1 per input.
  - They are committed, with a SHA-256 manifest, and frozen. The `TendEval` harness shows that hash.
  - **Authorship:** the Acceptance Tester writes the inputs, the household and the golden set. The PO approves the
    composition. The Developer implements the scorer to the rules below and does not write golden expectations.
  - The scorer (`TendIngestion`) passes self-tests against hand-built results files with known right and wrong
    answers. They cover every rule below, including a false merge, a duplicate created, a proposed-room match and a tie
    in matching.
  - The Tester re-scores one self-test file independently and gets the same scores.
  - Any change to the inputs, the household, the golden set, the stop words or the scoring rules after the freeze
    needs a PO decision in `DECISIONS.md`.
  *Verification:* unit (scorer self-test) + Tester review  *Environment:* Linux (self-test, fixture-composition check)
  + Tester review.  *Evidence expected:* test name + fixture commit hash + manifest hash + Tester's re-score note.
- **AC-M2-15** **(Gate)** (device) Given the frozen eval on an iPhone 15 Pro (iOS 26, Apple Intelligence on, cloud off,
  en-US), when all 20 inputs run under the device-run rules, then the scorer's results for the exported results file
  meet the Q3 thresholds:
  - segmentation, kind, room, effort and each flag;
  - 100% valid drafts;
  - 0 introduced banned tokens.
  The voice inputs are spoken live from the script by the human owner, and no audio is stored. The scores come from
  the committed scorer run on Linux over the exported file. The Tester's re-score must agree.  *Verification:*
  device-script  *Environment:* Device (DS-1); scoring on Linux.  *Evidence expected:* results file + scorer log + human
  run record. **Status until run: AWAITING-DEVICE.**
- **AC-M2-16** **(Gate)** (device) In the same run, every one of the 20 gated inputs has TTFI < 1.5 s and total time ≤
  5.0 s (Q4; Definitions). The session is prewarmed when the input is shown or recording starts.
  - Before the gated runs, the harness runs input 1 once from a fresh launch with no prewarm. Its cold-start TTFI is
    reported for information only and is not scored.
  - Timings use the harness's monotonic clock:
    - text inputs: from handing the fixture text to the pipeline;
    - voice inputs: from the transcriber's final result.
  *Verification:* device-script  *Environment:* Device (DS-1).  *Evidence expected:* per-input timings in the results
  file. **Status until run: AWAITING-DEVICE.**
- **AC-M2-17** **(Gate)** (device) In the same run, the harness commits every draft that the pipeline does not mark as
  a duplicate, each input into its own **fresh copy** of the seeded household. Under the eval scoring rules, this
  creates **0** duplicates across all 20 inputs, and there is **at most 1** false merge in total.  *Verification:*
  device-script  *Environment:* Device (DS-1); scoring on Linux.  *Evidence expected:* results file + scorer log.
  **Status until run: AWAITING-DEVICE.**

#### Eval scoring rules (binding for AC-M2-11, 14, 15, 17, 25, 26; T-04)
- **Fixtures.**
  - **Fixed IDs (T-29).** Every seeded task and room has a **fixed UUID** in the fixtures, because the shortlist
    tie-break and the AC-M2-20 golden requests use `id.uuidString`. No fixture ID is generated at run time.
  - Each **seeded task** has a stable key, its M1 fields and **match groups**. A match group is a set of synonym
    tokens, already keyword-folded, for example `{ac, aircon, air, conditioner, hvac}` and
    `{service, servicing, serviced, check}`.
  - Each **golden item** has a key, match groups, the expected kind, room, effort and the three flags, and an
    `expect`. The `expect` is either `create` or `existing(seededKey)`.
  - The expected room is one of:
    - `existing(roomKey)`;
    - `new(name, alternates)`;
    - `none`.
- **Household state.** Every input starts from a fresh copy of the seeded household. The 20 inputs never build on each
  other, so retakes and input order cannot change a score.
- **Draft text.** The draft text is the keywords of the draft's final `title`, joined with the keywords of its
  `sourcePhrase`. A draft **satisfies** a target when the draft text holds at least one token from **each** of the
  target's match groups. Overlap(d, g) is the number of draft-text tokens that appear in any of g's groups.
- **Segmentation matching (one-to-one).**
  - A draft is **primary** when it is not marked `ofDraft`.
  - Form every (primary draft, golden item) pair where the draft satisfies the item.
  - Sort the pairs by overlap descending, then golden order ascending, then `draftID` ascending.
  - Take pairs greedily, skipping any pair whose draft or item is already taken.
  - A golden item with no pair is **not found**. A primary draft with no pair is **extra**.
- **Denominators.** N is the total number of golden items over all 20 inputs (N ≥ 50). For segmentation, kind, room,
  effort and each flag, an item scores only if it is found **and** that field is correct. Not-found items count as
  wrong.
  - The required count is ⌈p × N⌉ (with N = 50: 95% → 48, 90% → 45, 85% → 43).
  - Extra drafts: ≤ 2 in total.
  - **Validity** counts all emitted drafts (100% must pass the M1 invariants).
  - **Calm words** counts all titles and proposed room names (0 introduced banned tokens).
- **Room scoring.**
  - `existing(roomKey)` is correct only when the draft is linked to that room.
  - `new(name, alternates)` is correct only when the draft is `proposed(x)` and the name-folded x equals the
    name-folded name or one of the alternates. Linking it to an existing room is wrong.
  - `none` is correct only when the draft room is `none`.
- **Best target (many-to-one, for duplicates).**
  - The targets of an input are its `create` golden items plus the seeded tasks that are not `completed`.
  - For each draft, its best target is the target it satisfies with the highest overlap. Ties go to golden items
    before seeded tasks, then to the lower key.
  - A draft that satisfies no target has no best target.
- **Duplicates created.** Let c(x) be the number of committed drafts whose best target is x. Per input, the
  duplicates created are Σ over `create` items g of max(0, c(g) − 1), plus Σ over seeded tasks t of c(t). The gate
  needs 0 over all 20 inputs.
- **False merges.** A `create` golden item g is a false merge when:
  - at least one draft whose best target is g was marked as a duplicate (`ofExisting` or `ofDraft`); and
  - c(g) = 0.
  Each g counts once. The gate allows at most 1 over all 20 inputs.
- **Output.** The scorer writes per-input and total counts for every metric, each pairing, and each best target.
  This is the scorer log used as evidence.

#### Device-run rules (binding for every device AC; T-13, T-20)
- **Build.** The `TendEval` debug build is installed from the owner-run Mac at the commit under test. The run record
  holds the commit SHA and the fixture manifest hash.
- **Sampling.**
  - On device: greedy sampling.
  - Cloud: the lowest-variance setting each provider offers (temperature 0, or the lowest allowed).
  - The setting is recorded in the results file.
- **Text inputs** are handed to the pipeline verbatim from the fixture by the harness, so no typing errors enter the
  result.
- **Voice inputs** are read aloud live from the printed script.
  - At most **one retake** per voice input, and only when the speaker misread the script.
  - The reason is entered in the harness. Every attempt is kept in the results file, and the last attempt is the one
    scored.
  - There is no re-running to get a pass. A whole run is repeated only for an environment fault (crash, wrong build,
    wrong network). The reason is recorded, and every run file is kept.
- **Run record** (in `acceptance.md`):
  - who ran it, and the date and time;
  - the device model and iOS build;
  - the app commit SHA and the fixture hash;
  - the on-device model, or the provider and model ID;
  - the sampling setting;
  - the network and a speed-test result (download and upload speed and latency; for cloud runs, Q15);
  - the results-file names and their SHA-256.

### S-M2-07 My older iPhone can use a cloud model I chose  (FR-A1, P-1, P-3; ADR-0005)
As someone with an iPhone 13, I want to plug in my own AI key and get the same capture as newer phones, and only when
I've said yes, so that I'm not left out and nothing goes anywhere without me knowing.

**Acceptance criteria**
- **AC-M2-18** Given any of the states below, when any brain-dump is submitted, then the route is never `cloud` and
  the mock transport records zero requests. The states are:
  - a **fresh install** (no key, no consent);
  - every state with no consent record for the selected provider;
  - the **restored-state fixtures (T-14)**:
    - (i) a key for X is present and there is no consent record. This is the same-device encrypted-backup case,
      because a `ThisDeviceOnly` Keychain item can come back while the consent record does not. The key is deleted.
    - (ii) a consent record for X and no key.
    - (iii) a consent record and a key for Y while X is selected.

  The restore rule (ADR-0005 Decision 2) is: cloud is on only when the selected provider has both a consent record and
  a key, and an orphan key is deleted. The durable consent store must therefore not be restorable from backup or
  iCloud. It is delivered in M3 (Q21). M2 tests the rule with these fixtures and does not exercise a real restore on a
  device.

  Given consent and a key for the selected provider X, the route can only be `cloud(X)`, never another provider. When
  cloud is turned off, or the key is removed, then:
  - (a) the Keychain item is deleted;
  - (b) the consent record is cleared;
  - (c) no request starts afterwards;
  - (d) an in-flight cloud request is cancelled, the outcome is `cancelled`, and no task is written.
  *Verification:* unit (mock transport, in-memory key store)  *Environment:* Linux for consent, route and cancel with
  the in-memory key store (`TendIngestion`). Owner-run Mac (iOS Simulator host app) for (a) with the real Keychain.
  *Evidence expected:* test names + logs from both.
- **AC-M2-19** Given every combination of the inputs below, when the route is chosen, then it equals the ADR-0005
  Decision 1 rules exactly. The plan writes them out as the full expected matrix. The inputs are:
  - on-device availability: available, or each unavailable reason **including unsupported locale**;
  - cloud: off; on for each provider; consent and key stored for a provider that is **not** selected (T-12);
  - preference: "on device first" or "always use my cloud model".

  In particular:
  - A device with the model available and "on device first" set never routes to the cloud.
  - "Always use my cloud model" while cloud is off is ignored: the route is `onDevice` if available, otherwise `none`
    (T-12).
  - An on-device generation error never re-routes to the cloud.
  - The route is part of the outcome, so M3 can show which model handled the capture.
  *Verification:* unit (parameterised, full matrix)  *Environment:* Linux.  *Evidence expected:* test name + matrix
  log.
- **AC-M2-24** Given provider stream fixtures for OpenAI, Anthropic and Gemini, when each provider parser and cloud
  adapter handles them, then drafts flow through the same `IngestionModel` contract and draft stream events as the
  on-device adapter.
  - **Fixtures (T-19):**
    - Most are **synthetic**, built from each provider's documented streaming format.
    - There is also **at least one real recording per provider**. The owner records it on the owner-run Mac with the
      fixed sample sentence from this brief's Outcome, which holds no household data. Only the response stream is
      saved. Request headers and the key are never saved.
    - The set covers happy paths, out-of-order or split chunks, a truncated stream, invalid JSON, schema-violating
      fields, unknown enum values, and a refusal.
  - **What applies to cloud output (T-19):**
    - AC-M2-01…06, AC-M2-08 and AC-M2-12 apply in full, including the Q5 repairs and the calm-words guard.
    - AC-M2-07 applies except its `Tool` clause. For cloud drafts the **local duplicate re-check** (Definitions)
      replaces it, for the Q12 answer in force.
    - A cloud model is never given the duplicate-lookup `Tool`.
    - A truncated stream or invalid JSON after the first draft ends `interrupted`. A refusal before any draft ends
      `noModel`.
  *Verification:* unit (fixtures)  *Environment:* Linux for the three provider stream parsers and the local re-check
  (`TendIngestion`). Owner-run Mac for the cloud adapters end to end over the fixtures through a mock transport
  (`TendAI`).  *Evidence expected:* test names + fixture list (which are synthetic and which recorded) + logs.

### S-M2-08 Only what's needed leaves my phone, and I'm told the truth about it  (P-2, P-3, P-4; ADR-0005)
As someone who turned the cloud on, I want only the one thing I just said to be sent, my key to stay safe, and Tend to
stay calm when the cloud isn't there, so that saying yes to the cloud never costs me my privacy or my words.

**Acceptance criteria**
- **AC-M2-20** Given ≥ 500 seeded households, when the context selector and the payload builder build a cloud request
  for a capture, for each provider, then:
  - **(a) Byte-level unique sentinels (T-24)** cover every field outside allowed content that can hold a unique value:
    - task IDs and room IDs;
    - the titles of tasks **not** on the shortlist;
    - `windowStart`, `windowEnd`, `completedAt` and each room's `lastTendedAt`;
    - the interval;
    - the injected `now`, the time-zone identifier and the calendar identifier.
    Each date sentinel is checked in four forms: ISO 8601, Unix seconds, Unix milliseconds and reference-date seconds.
    - **String sentinels** (IDs, titles, date forms, identifiers) must appear nowhere in the captured request: not in
      the method, path, query, header names, header values or body bytes.
    - **Interval sentinels** use whole-day values in 600…729 whose decimal form occurs nowhere in the fixed
      instructions, the schema or the capture text. In the decoded body, no JSON number equals one and no string
      contains one. In the path, the query and the header values, none appears.
  - **(b) Structural check (T-24)** covers enum, Boolean and set fields (kind, effort, flags, dayparts, weekdays,
    state), which cannot hold unique values and whose case names appear legitimately in the fixed schema. For each
    decoded body:
    - The set of JSON key paths equals that provider's **allowed key-path list** (AC-M2-26), with array indices
      written as `[]`.
    - The value at the capture path is exactly the capture text.
    - The values at the room-name paths are exactly the selector's room names, in order.
    - The values at the shortlist paths are exactly the shortlist titles with indices 1…n.
    - Every other path holds exactly the value at that path in the provider's golden request. These are the fixed
      instructions, the schema, the model ID and the opt-outs.
    - The header names equal the provider's fixed list. Every header value except the auth header equals the golden
      value.
    So no household field can change any byte outside the capture, room-name and title values.
  - The M1 model has no member, assignee, notes or household-ID fields. When M5 adds members and assignees (FR-E2), the
    M5 brief extends this AC with their sentinels (T-15; PO, due with the M5 brief).
  - **Shortlist (Q12 = yes).** The titles sent are exactly the duplicate shortlist for the capture text (Definitions),
    in rank order with indices 1…n, and n ≤ 10. When Q12 = no, no task title is sent, and the golden requests are
    regenerated under a PO decision.
  - **Golden bytes (T-15).** For 3 fixed golden households per provider, the bytes equal a committed golden request
    exactly, on Linux **and** on the owner-run Mac.
    - The body is canonical JSON: keys sorted by UTF-8 bytes, no insignificant whitespace, `/` not escaped, non-ASCII
      written as UTF-8 and not as `\u` escapes, and no floating-point values.
  - **Opt-outs (T-15; PO default, re-checked by the Developer at build and by the Reviewer against current provider
    docs).**
    - OpenAI: `store: false`.
    - Anthropic: none offered at request level.
    - Gemini: none offered at request level, because training use depends on the key's tier (Q17).
    - Any option found at build is added to this list and to the golden bytes under a PO decision.
  - **Key placement.** The API key appears only in that provider's auth header:
    - OpenAI: `Authorization: Bearer …`;
    - Anthropic: `x-api-key`;
    - Gemini: `x-goog-api-key`, **never** the `key=` query parameter.
  - **Media (T-15).** Media is rejected **by type**. The builder's input type can hold only `String` and `[String]`
    (Definitions), so there is no runtime path. Proof is an API test that lists the input type's stored properties
    through `Mirror`, plus Reviewer inspection.
  - The test sends through a recording mock transport and asserts on the captured request, not on the builder's
    intermediate values.
  *Verification:* unit (property + golden)  *Environment:* Linux (the builder and selector are in `TendIngestion`).
  The golden-bytes test is repeated on the owner-run Mac.  *Evidence expected:* test name, seeds, golden fixture
  hashes, logs from both.
- **AC-M2-21** Given the key store, when a key is saved, read, replaced and deleted, then:
  - The Keychain item is a generic password (`kSecClassGenericPassword`) in the data-protection keychain. It has
    `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and is not synchronizable.
    - The test proves this by reading the attributes back with `kSecReturnAttributes`, not by checking the query it
      sent (T-16).
  - Reading it back after save returns the same key.
  - **Masked form (T-16):** only a masked form is ever returned for display. It is `••••` followed by the last 4
    characters when the key has ≥ 12 characters, and `••••` alone for shorter keys. Save does not reject short keys.
    Key validation is the optional ADR-0005 test prompt.
  - Delete leaves no item (a lookup returns `errSecItemNotFound`).
  - The key never appears in `UserDefaults`, files, logs, `CustomStringConvertible` or `CustomDebugStringConvertible`
    output, or error messages. The scan in AC-M2-09 checks this, together with a test that formats every key-holding
    type.
  *Verification:* unit + Reviewer  *Environment:* Owner-run Mac. The Keychain tests run on the **iOS Simulator with a
  host app** (`xcodebuild test`), because a plain macOS `swift test` may fail with `errSecMissingEntitlement`. The
  in-memory fake used by Linux tests is not evidence for this AC.  *Evidence expected:* test name + Mac evidence
  record + log + review note.
- **AC-M2-22** Given the cloud transport, when it is configured, then it uses an ephemeral `URLSession` configuration
  with no cookie storage and no URL cache. It sends only HTTPS to the ADR-0005 host for the routed provider. A request
  to any other host, a redirect to another host, or a non-HTTPS URL is refused before sending.
  - **Timeouts (T-17; Q22).** Each capture has a cloud deadline of 10.0 s, measured on an injected clock from the
    moment the pipeline receives the input.
    - Each attempt sets `timeoutIntervalForResource` to the time left before the deadline, and
      `timeoutIntervalForRequest` to min(time left, 4.0 s).
    - **Retry rule (one rule, also in Q22; T-28).**
      - The one allowed retry (AC-M2-23, 429/5xx only) waits a pause p = max(0.5 s, `Retry-After`). `Retry-After` is
        read only in its delta-seconds form; a missing or unreadable value counts as 0.
      - The retry starts only if, after the pause, ≥ 3.0 s are left before the deadline. Otherwise there is no retry.
  *Verification:* unit (mock `URLProtocol`; injected clock)  *Environment:* Owner-run Mac. `URLProtocol` and redirect
  handling in Linux `FoundationNetworking` are not evidence. The deadline and retry arithmetic is also unit-tested on
  Linux (`TendIngestion`).  *Evidence expected:* test name + Mac evidence record + log.
- **AC-M2-23** Given cloud on, when the mock transport returns each failure (offline, timeout, DNS failure, TLS
  failure, 401 or 403 bad key, 429 rate limit, 5xx, malformed body, provider refusal), then:
  - The pipeline returns a calm typed outcome (`noModel` before any draft, `interrupted` after one), creates no task,
    and returns the input text in memory.
  - When no draft was emitted, it also offers a **plain note** draft built from that text. The plain note is committed
    only by `commit(confirmed:)`.
  - Nothing is queued or retried in the background, and nothing is written to disk. A single in-call retry is allowed
    only for 429/5xx, and only within the AC-M2-22 deadline rule. This is tested with an injected clock (T-18).
  - The same plain-note offer exists when the route is `none`.
  - No outcome or reason name contains a banned token.
  - **"None blames the user" (T-18)** is checked by Reviewer inspection of the outcome and reason case names. The
    user-facing copy is designed and reviewed by the Designer in M3.
  *Verification:* unit + Reviewer  *Environment:* Linux for the outcome, plain note and retry decisions over a neutral
  failure reason (`TendIngestion`). Owner-run Mac for the cloud adapter's mapping of each `URLError` and HTTP status
  to a neutral reason (`TendAI`).  *Evidence expected:* test names + logs from both + review note.

### S-M2-09 Proven on a real iPhone 13 with a cloud model  (gate; ADR-0005)
**Acceptance criteria**
- **AC-M2-25** (device) Given an iPhone 13 on iOS 26 (en-US, cloud on with one provider), when 2 voice inputs are
  spoken in airplane mode, then:
  - The transcript is produced on device. The run records which transcriber was used (`SpeechTranscriber` or
    `DictationTranscriber`).
  - The cloud step returns the calm offline outcome (`noModel`) with the plain-note offer, and no task is created.
  - Back online, the same inputs **parse through the cloud (T-13)**. That means, for each input:
    - the route is `cloud(X)` and the outcome is `completed`;
    - every draft passes the M1 invariants;
    - every golden item is matched and there are 0 extra drafts (the scoring rules);
    - 0 duplicates are created.
  *Verification:* device-script  *Environment:* Device (DS-2).  *Evidence expected:* human-recorded run (date,
  device, iOS build, results file). **Status until run: AWAITING-DEVICE.**
- **AC-M2-26** **(Gate)** (device) Given the frozen eval (AC-M2-14) on an iPhone 13 (iOS 26, cloud on, en-US), when
  all 20 inputs run once for **each** provider in Q16, using that provider's default model from the curated list, then
  each provider's run meets:
  - the Q3 rubric thresholds;
  - 0 duplicates created and at most 1 false merge (as AC-M2-17, under the eval scoring rules, with a fresh household
    per input);
  - the JSON key paths sent are, for every request, a subset of that provider's **allowed key-path list**. That list
    is derived from the AC-M2-20 golden requests and committed with them.
  The voice inputs are spoken live and no audio is stored. The results file records, per request attempt, the request
  byte count and the JSON key paths only, never the values (AC-M2-28). If Q12 is answered no, the duplicate threshold
  applies to the local word-match re-check.  *Verification:* device-script  *Environment:* Device (DS-2); scoring on
  Linux.  *Evidence expected:* results file per provider + scorer log + human run record. **Status until run:
  AWAITING-DEVICE.**
- **AC-M2-27** **(Gate)** (device) In the same runs, on the network stated in the run record (Q15), every input has:
  - cloud TTFI < 3.0 s;
  - total time ≤ 10.0 s.

  The run also reports the same figures on the iPhone 15 Pro with "always use my cloud model" for one provider, for
  information only. The on-device target stays AC-M2-16 (< 1.5 s, ≤ 5.0 s) and is not relaxed. Timings follow
  AC-M2-16's clock rules.  *Verification:* device-script  *Environment:* Device (DS-2).  *Evidence expected:*
  per-input timings per provider in the results file. **Status until run: AWAITING-DEVICE.**

### S-M2-10 A test harness that proves it on the phone, and never ships  (gate support; T-05)
As the human owner running the device gate, I want one simple debug app that runs the frozen eval and hands me a
results file, so that the gate can be proven on real iPhones without any product UI or any risk of shipping test code.

**Acceptance criteria**
- **AC-M2-28** Given the `TendEval` target, then:
  - **Never shipped.**
    - `TendEval` is its own app target with its own bundle ID. It is built only in the Debug configuration.
    - No shipped target (the `Tend` app and every extension) depends on it or embeds it.
    - The `Tend` scheme's Archive action does not include it. It is never archived or uploaded.
    - `TendIngestion` and `TendAI` hold no eval-only code paths or hooks. The harness uses only their public API and
      wraps the transport protocol to record metadata.
    - The proof is a scan of `project.yml` (or the generator file chosen in ADR-0003), plus Reviewer inspection.
  - **Build path.**
    - It is built and installed on both iPhones from the owner-run Mac with Xcode 26.
    - The signing team is stated in the plan (Q20).
    - The fixtures are bundled at build time, and the harness shows their SHA-256 manifest hash.
  - **What it does.**
    - It loads a fresh copy of the seeded household into the M1 in-memory repository for every input.
    - Its injected ID generator for committed tasks and rooms is **deterministic** (T-29). It is seeded from the
      input ID and attempt number, as defined in the plan, and never yields a fixture UUID.
    - It shows each input's script.
    - It feeds text inputs verbatim, and captures voice inputs live through the M2 speech adapter.
    - It prewarms as AC-M2-16 says, times TTFI and total time on a monotonic clock, commits as AC-M2-17 says, and
      follows the device-run rules (retake reason entry, every attempt kept).
    - For cloud runs, it takes the owner's key through the AC-M2-21 key store, records an in-memory consent for the
      selected provider, and offers "Remove key" at the end of the run.
    - It writes nothing except the results file.
  - **Results file (format v1).** One UTF-8 JSON file per run, in canonical JSON (sorted keys). It is named
    `m2-eval-<deviceModel>-<onDevice|openai|anthropic|gemini>-<UTC yyyyMMdd'T'HHmmss'Z'>.json`. It contains:
    - `schemaVersion` (1).
    - `run`: `operator`, `startedAtUTC`, `deviceModel`, `iOSBuild`, `appCommitSHA`, `fixturesSHA256`, `locale`,
      `routePreference`, `provider`, `modelID`, `sampling`, `prewarm`, and `network` (`kind`, `downMbps`, `upMbps`,
      `latencyMs`, entered by the owner).
    - `coldStart`: `inputID`, `ttfiMs`. This is for information only.
    - `inputs[]`, one entry per attempt, with:
      - `inputID`, `mode` (text or voice), `attempt`, `retakeReason`;
      - `transcript` (voice only; the transcript of the scripted eval utterance) and `transcriber`;
      - `route`, `outcome`, `ttfiMs`, `totalMs`;
      - `events[]` (`type`, `draftID`, `tMs`);
      - `drafts[]`: each draft's final state, with every field in the draft field set. Room IDs and task IDs are
        written as the fixture keys.
      - `committed[]`, the draft IDs;
      - `cloudRequests[]`: `attempt`, `bytes`, `keyPaths[]`. A key path is a JSON path with array indices written as
        `[]`, sorted and unique. It never holds a value.
    - The file **never** holds audio, a request or response body, header values or a key.
    - A JSON Schema for v1 is committed with the fixtures. The scorer rejects a file that does not conform.
  - **Export.**
    - The file is written only to the harness's Documents directory. File sharing is enabled in the Debug target only.
    - The owner moves it to the Mac through the Files app, Finder or AirDrop, and commits it under
      `docs/milestones/M2/evidence/device/`. Its SHA-256 goes in the run record.
    - The harness never uploads anything.
  - **Reconciliation with AC-M2-09.** The shipped modules never persist transcripts, bodies, responses or keys. The
    harness's results file is the only exception, and only for scripted eval text, parsed drafts and request
    metadata. Eval inputs are fixtures and the household is synthetic, so no real household data is written (P-4).
  *Verification:* unit (results-file schema validation and the scorer's rejection test on Linux; the `project.yml`
  scan on Linux) + Reviewer + an owner-run Mac build of the Debug and Release configurations, showing that the Release
  products contain no `TendEval`.  *Environment:* Linux + owner-run Mac + Reviewer.  *Evidence expected:* test names +
  logs + Mac evidence record + review note.

## Gate mapping
| PRD §4 gate line | Covered by ACs |
|---|---|
| Automated mock tests pass 100% | AC-M2-13 (Linux (a) + owner-run Mac (b)), built on AC-M2-01…10, AC-M2-12, AC-M2-18…24 and AC-M2-28 |
| 20 messy voice/text inputs parse accurately into tasks/rooms/efforts (iPhone 15 Pro, on-device) | AC-M2-14, AC-M2-15 (rubric Q3, eval scoring rules), run with the AC-M2-28 harness |
| Latency under 1.5 seconds (on-device) | AC-M2-16 (TTFI < 1.5 s; total ≤ 5 s, Q4) |
| Zero duplicate creation | AC-M2-07, AC-M2-08 (logic), AC-M2-17 (device, on-device), AC-M2-26 (device, cloud) |
| Same eval on iPhone 13 with the cloud path: accuracy and zero duplicates | AC-M2-24 (logic), AC-M2-26 (device) |
| Cloud latency target | AC-M2-27 (TTFI < 3.0 s; total ≤ 10 s, Q15) |
| Scope: on-device Foundation Models, streaming structured output | AC-M2-05, AC-M2-09, AC-M2-10, AC-M2-11 |
| Scope: opt-in BYOK cloud path under P-3 / ADR-0005 (off by default, consent, minimisation, keys, fallback) | AC-M2-18 (off by default, consent, turn-off), AC-M2-19 (routing), AC-M2-20 (payload), AC-M2-21 (keys), AC-M2-22 (transport), AC-M2-23 (fallback), AC-M2-25 (iPhone 13 speech on device) |
| Scope: UX-2, captured tasks reach Now only through `NowSelector` (T-21) | AC-M2-13: the M1 `NowSelector` suite (AC-M1-13…16) stays green, and commit (AC-M2-06) only upserts into the repository the selector reads. No M2 API returns "what to do now" items. |
| Device-gate support: a harness that is never shipped (T-05) | AC-M2-28 |

Device criteria AC-M2-11, AC-M2-15, AC-M2-16, AC-M2-17, AC-M2-25, AC-M2-26 and AC-M2-27 stay **AWAITING-DEVICE** until the human owner runs the
Tester's script and the result is recorded (CLAUDE.md §5). M2 cannot be `ACCEPTED` before that.

## Assumptions and open questions
| # | Question | Default if unanswered | Needed by |
|---|---|---|---|
| Q1 | CLAUDE.md §9 item 2: is any Private Cloud Compute or cloud path wanted for M2 (P-3)? | **Resolved 2026-11-21 (D-030, ADR-0005):** yes, an opt-in BYOK cloud path (OpenAI, Anthropic, Gemini), on device first, off by default. Final when the owner merges the policy PR. | Before M2 build |
| Q2 | Which languages? | en-US only in M2. The model's locale support is checked at runtime. Other locales degrade the same way as an unavailable model. | M2 (PO default) |
| Q3 | What does "parse accurately" mean (the rubric)? | Scored per expected item over all 20 inputs, one-to-one matching against the golden set, exactly as the **eval scoring rules** (under AC-M2-17) say: ≥ 50 expected items, denominators over expected items, ⌈p × N⌉ required, and a fresh household per input. **Segmentation:** ≥ 95% of expected items found and ≤ 2 extra items in total. **Kind** ≥ 95% exact. **Room** ≥ 90% (an exact room, or both none). **Effort** ≥ 85% exact on Low/Normal/High. **Flags** (critical, deep clean, weather-dependent) ≥ 95% exact each. **Validity:** 100% of drafts pass the M1 invariants. **Calm words:** 0 introduced banned tokens. **Composition:** 20 inputs, of which ≥ 8 voice and ≥ 8 text; 10–80 words each; all four item types; ≥ 5 with a weather condition; ≥ 3 critical (bill, expiring food); ≥ 3 deep cleans; ≥ 5 mentioning an existing task; ≥ 3 with a repeat inside the input; ≥ 4 with filler or self-correction ("no wait, Thursday"). (PO default; the owner may tighten it.) | Before AC-M2-14 is frozen |
| Q4 | What does the latency clock cover? | TTFI as defined, < 1.5 s for **each** input (not an average). Total ≤ 5.0 s per input. Prewarming the session when capture starts is allowed; cold start is reported but does not gate. (PO default) | M2 (PO default) |
| Q5 | How are degenerate model outputs mapped onto the M1 invariants (D-016)? | The repairs run **in this order** (T-07). (1) Title: trim and collapse whitespace; if it is empty, skip the item (typed reason). (2) Unknown enum values become that field's default: kind one-off, effort Normal, room `none`. Unknown daypart or weekday **elements** are dropped. (3) Empty dayparts → `Daypart.defaultAllowed` (morning, afternoon, evening). Empty weekdays → all seven. (4) Critical + deep clean → critical; deep clean is cleared. (5) Time hint → window via Q6. No hint, end ≤ start, a non-finite date, or an **out-of-range** date → `[now, now + 7 days)`. Out of range means `windowStart` < `now` or > `now + 366 days`, or `windowEnd` > `windowStart + 366 days`. (6) Interval: a recurring item with no interval, or one outside 1…730 whole days → becomes a one-off with no interval. A non-recurring item with an interval → the interval is dropped. (7) The calm-words guard (AC-M2-12). (8) `sourcePhrase` check (Definitions). (9) The M1 initialiser. If it still rejects the task, which the oracle must show never happens, the item is skipped with a typed reason. Repairs happen only in `TendIngestion`; the M1 model still rejects invalid tasks. (PO default) | M2 (PO default) |
| Q6 | How are time phrases resolved? | The model reports a structured hint and a deterministic resolver applies the injected calendar. The Developer and Tester write the exact table. Defaults: "today" → `[now, end of today)`; "tonight" → evening + night, today; "tomorrow (morning/…)" → that daypart of tomorrow; "this weekend" → Saturday and Sunday of the current or coming weekend; "next week" → `[next Monday, +7 days)`; "before <season/month>" → `[now, start of it)`; "every N days/weeks/months" → recurring, interval in days (1 month = 30 days); no phrase → `[now, now + 7 days)`. **Settled points (T-08):** (a) the week starts on **Monday** whatever the calendar's `firstWeekday`; (b) "this weekend" said on a Saturday → `[now, end of Sunday)`; said on a Sunday before 18:00 → `[now, end of Sunday)`; on a Sunday at or after 18:00 → the coming Saturday and Sunday; (c) seasons are **meteorological, northern hemisphere** (spring 1 Mar, summer 1 Jun, autumn 1 Sep, winter 1 Dec; en-US only, Q2); (d) "tonight" → evening + night dayparts, window `[now, 05:00 tomorrow)`, using the M1 daypart boundaries; (e) "end of today" is the next local midnight in the injected calendar, so the day is 23 h or 25 h long on a DST day, and local times that don't exist follow M1 Q11; (f) "before <month or season>" when that month or season is the current one → its next start, a year ahead. The Planner adds the full table to the plan; the Tester's review of it is a Definition of Ready condition for AC-M2-03. (PO default) | M2 planning |
| Q7 | What happens to the existing task when a duplicate is mentioned? | Nothing in M2: no new task, existing task unchanged. Gently refreshing the existing task (for example bringing a restock forward) is a product question for M3, with its copy. (PO default) | M3 |
| Q8 | `TendAI` needs Xcode 26 on macOS to build and run its mock tests. Is there a macOS CI lane (a paid runner), or does the owner run them on a Mac? | **Closed 2026-11-21 (owner answer, via Orchestrator):** there is no paid CI lane. All Mac evidence comes from the **owner-run Mac** (MacBook Air M4 or Mac mini M1, Apple silicon, with Xcode 26 installed; Definitions). The owner runs it, or an agent drives it remotely; either way it is recorded as owner-run Mac evidence. The same Mac builds and installs `TendEval` on both iPhones and reruns W3-F1 (Darwin DST). | Closed |
| Q9 | W2-F3: should non-finite dates become a model invariant? | Yes. Add a `TaskInvariantViolation` case for a non-finite date (Designer names it), so both M1 stores agree. This is carried as a clause of **AC-M2-02** (T-21). The accepted M1 AC-M1-25 is not edited; the M2 AC extends it. No AC is removed. The parser never emits one (Q5). (PO default; Designer to name it) | M2 |
| Q10 | W3-F6: duplicate task IDs. | Forbidden. Commit takes IDs from an injected generator and the household never holds two tasks with one ID (AC-M2-06). Sync-time collisions are M5. (PO default) | M2; M5 for sync |
| Q11 | Does a long dump break the Rule of Three? | No. The draft stream is a review of what was just captured, not a "what to do now" surface. Committed tasks reach Now only through `NowSelector` (≤ 3). How many drafts are shown at once is an M3 design question. (PO default) | M3 design |
| Q12 | For cloud duplicate checks, may Tend send up to 10 existing task **titles** (pre-filtered on the phone, no IDs, no other fields)? Without them, the cloud can only catch duplicates inside one capture; duplicates of existing tasks are left to a local word-match check, which misses synonyms ("buy dish pods" vs "dishwasher pods"). | **Yes, at most 10 titles**, chosen by the deterministic **duplicate shortlist** (Definitions; T-06) and named on the consent screen. If the owner says no, room names only are sent, and AC-M2-26's duplicate threshold applies to the **local word-match** re-check (Definitions). The AC-M2-20 golden requests are then regenerated under a PO decision. **PO default, owner may change.** Titles outside the 10 are never sent; the word-match floor catches their exact and near-exact repeats on the phone (PO 2026-11-21). | Before M2 build |
| Q13 | Support a custom endpoint (another "OpenAI-compatible" server, a self-hosted model)? | **No.** Fixed hosts only (ADR-0005). A custom endpoint would let household text go to any server and needs its own ADR. | Before M3 |
| Q14 | May a raw photo or document go to a cloud model (M4 camera and Share Sheet)? | **No by default.** On-device Vision/VisionKit extracts text and only that text is sent. Raw images need an ADR-0005 addendum and a separate consent line in M4. | M4 |
| Q15 | What are the cloud latency targets, and on what network? | TTFI < 3.0 s and total ≤ 10.0 s **per input**, on home Wi-Fi (the run record states the network and a speed-test result). One retry for 429/5xx must fit inside the total, under the AC-M2-22 deadline rule (Q22). (PO default; the owner may tighten it.) | Before AC-M2-14 is frozen |
| Q16 | Which providers must pass the device eval for M2 to be accepted? | **All three** (OpenAI, Anthropic, Gemini), each with its default curated model, using the owner's own keys (the owner pays the API cost of 3 × 20 inputs). The owner may narrow this to fewer providers for M2. Any provider left out is hidden in the app until it passes, not shipped untested. **PO default, owner may change.** | Before M2 build |
| Q17 | Gemini's free tier lets Google use prompts to improve its products, and human reviewers may read them. Tend cannot detect which tier a key is on. | Support Gemini, and show a plain warning on its consent screen recommending a paid-tier key. Gemini stays on the AC-M2-20/22 host list and in the AC-M2-26/27 runs. The owner could choose instead to leave Gemini out; that removes its host, adapter and runs under a PO decision. **PO default, owner may change.** | Before M2 build (it affects AC-M2-20, 22, 26 and 27); copy before M3 |
| Q18 | Which model per provider is the default? | The Developer proposes one model per provider in the plan: fast, structured-output capable, and in a curated list that can be updated per release. There is no free-text model ID. The PO approves the list. (PO default) | M2 planning |
| Q19 | Room names (and shortlisted titles) may contain a person's name, for example "Sam's room" (T-15). | They are user labels and are sent **as the user wrote them**. M2 has no member model, so Tend cannot recognise names in labels. The M3 consent copy must say "your room names, as you wrote them". The AC-M2-20 sentinel generator never puts sentinels into room names. M5 revisits this when members exist (FR-E2). (PO default) | M2 (copy in M3) |
| Q20 | Which Apple signing team installs `TendEval` on the iPhones (AC-M2-28)? | The owner's own team: a personal (free) team is enough for a debug install, but its profile lasts 7 days, so reinstall before each run. The Planner records it in the plan. **Human owner to confirm.** | Before the first device run |
| Q21 | Where is the consent record stored so that a restore never turns cloud on (T-14)? | M2 defines the rule and tests it with fixtures (AC-M2-18). The durable consent store is delivered in **M3** together with the Settings screens. It must be excluded from device backups and from iCloud, so a restore always gives "no consent". The orphan-key deletion in AC-M2-18 then also removes a restored key. Owner: PO (an M3 brief AC), due with the M3 brief. | M3 brief |
| Q22 | What are the cloud timeout and retry numbers (T-17)? | A 10.0 s per-capture deadline. Each attempt's resource timeout is the time left. The request (idle) timeout is min(time left, 4.0 s). One retry, only for 429/5xx, after a pause p = max(0.5 s, `Retry-After` in delta-seconds; a missing or unreadable value counts as 0), and only if ≥ 3.0 s are left before the deadline after the pause (the same rule as AC-M2-22; T-28). (PO default; the owner may tighten it.) | M2 planning |
| Q23 | PR #15 review, R1-F1 point 4: how may the `TendEval` harness read its bundled fixtures under the `contentsOf:` ban (AC-M1-23)? (P-2, P-4) | **In one named file only:** the fixtures loader `Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift` may use `Data(contentsOf: <name>)`, where `<name>` is bound in the same file by `Bundle.main.url(forResource:`. The resource arguments are string literals only (no identifiers, array elements or interpolation, no `../`). The token `URL` does not occur, `Bundle` is used only as `Bundle.main.url(forResource:`, and no other URL or path building, no `://` literal and no write or log API occur. It returns `Data` and keeps nothing. Everywhere else in the three modules, `contentsOf:` is banned except in `append`/`insert` calls. Tests are in AC-M2-09. AC-M1-23 gets a cross-reference only. (PO decision 2026-11-21, revised after the Tester's testability review of PR #16 (findings 1–9); stricter only: one narrow exception with new checks; no AC removed) | M2, before WI-M2-M7 is reviewed |
| Q24 | PR #15 review, R1-F5: the closed lists do not name some session method calls, C file and print calls or `write(toFile:`, and Rule 6 has no import list. Close the gaps? (P-2, P-3, P-4) | **Yes.** The networking list adds the session-method calls (`dataTask(` … `download(resumeFrom:`, including `bytes(for:` and `bytes(from:`). The write list adds `write(toFile:`, `AppStorage`, `SceneStorage`, `archiveRootObject(` and the C calls `fopen(`, `freopen(`, `fdopen(`, `fwrite(`, `fputs(`, `fputc(`, `mkstemp(`, `tmpfile(`, `creat(`. The log list adds `printf(`, `fprintf(`, `vprintf(`, `vfprintf(`, `dprintf(`, `puts(`, `putc(`, `putchar(`, `perror(`, `syslog(`. Call patterns match at a fixed, case-sensitive boundary; type-name patterns keep the AC-M1-23 rule. In Rule 3 the only session-method call allowed is `bytes(for:` with `delegate:` in its argument list. Rule 6 gets a closed import list (no `AVFAudio`, `UniformTypeIdentifiers`, `os` or `Darwin`). New plants and positive tests are in AC-M2-09. (PO decision 2026-11-21, revised after the Tester's testability review of PR #16 (findings 1–9); stricter only; no AC removed) | M2, before WI-M2-M4 or WI-M2-M7 is reviewed |

**Note on Q19 (before M3):** room names may contain a person's name, for example "Sam's room". The PO must settle how
this fits the P-3 consent wording (ADR-0005) before the M3 brief. This note does not change any M2 AC.

## Tester testability review
- [x] Every AC is observable and measurable  - [x] Device ACs identified (AC-M2-11, 15, 16, 17, 25, 26, 27)  -
  Reviewer note: **v4 accepted (Acceptance Tester, 2026-11-21, at `580d23e`).**
  - **T-23…T-30 are closed.** I checked each row of the v4 change record against the brief text.
    - **T-23:** the Rule 3 allowed subset covers exactly what AC-M2-22, 23 and 24 need: the task delegate for
      redirect refusal, `URLError`, `AsyncBytes` and `URLComponents`. `URL(string:` stays banned. The negative test
      is defined.
    - **T-24:** the AC-M2-20 check is now (a) unique byte sentinels for fields that can hold a unique value, plus (b)
      a structural key-path and value check against the golden request. Together these are as strong as the v3 intent
      or stronger, and both can be tested.
    - T-25…T-30 are fixed as asked.
  - **All 28 ACs** are observable and measurable, name a verification type and an environment, and define their
    evidence. I can write an independent oracle for each logic AC. For the eval, I can write an independent re-scorer
    from the scoring rules.
  - All three PRD §4 M2 gate lines, and the UX-2 and harness lines, are mapped (Gate mapping).
  - All seven device ACs stay **AWAITING-DEVICE**. Each has a pass rule, the device-run rules and an outline (DS-1 and
    DS-2 below, in the v2 note).

  **Where each AC can be proven (final)**
  | Environment | ACs |
  |---|---|
  | Linux only | AC-M2-01, 02, 03, 04, 06, 08, 09 (scan, plus Reviewer), 12, 14 (plus Tester review), 19 and 13(a). |
  | Linux + owner-run Mac | AC-M2-05, 07, 10, 18, 20 (golden bytes repeated on the Mac), 23, 24 and 28 (Release build check on the Mac). |
  | Owner-run Mac only | AC-M2-13(b), 21 (Simulator host app), and 22 (with its deadline and retry arithmetic also on Linux). |
  | Device, run by the human owner, scored on Linux (AWAITING-DEVICE) | iPhone 15 Pro: AC-M2-11, 15, 16, 17. iPhone 13: AC-M2-25, 26, 27. |

  - **Owner dependencies, none of which blocks the tick:**
    - The Mac answer is in (Q8 closed). Every Mac AC, and installing `TendEval` for every device AC, needs that Mac.
    - Q12, Q16 and Q17 are PO default, and the owner may change them. If one changes, the effect is already written
      down (Q12: AC-M2-20, 26; Q16 and Q17: AC-M2-20, 22, 26, 27). The golden requests and the provider runs then
      change under a PO decision, and I re-check them before the AC-M2-14 freeze.
    - Q20 (signing team) is needed before the first device run.
  - **The tick holds on these conditions** (from the v3 and v4 deferred lists):
    - **Before the Definition of Ready, in `plan.md`:**
      - the full Q6 table, which I review (AC-M2-03);
      - the allowlist, speech, speech-permission and results-writer file paths;
      - the `xcodebuild` commands, and the scoring tool and command;
      - the harness ID generator.
    - **Before the AC-M2-14 freeze:** the fixtures and golden set (written by me), the per-provider allowed key-path
      lists and the golden requests.
    - **Before the first device run:** the full DS-1 and DS-2 in `acceptance.md` (written by me).
    - **D-031:** the M rows still need D-031 in `DECISIONS.md`, through the owner's protected-path PR.
  - **Nits for the plan and the Developer** (they do not change AC meaning):
    - **N-1, Rule 3 prefix rule.** "Identifier token" means the whole Swift identifier, with no camelCase split. So the
      delegate label `willPerformHTTPRedirection` is not a hit. The negative test should include this near-miss.
    - **N-2, the `TendEval` transport wrapper.** Rule 6 bans every networking pattern, including `URLRequest`, in
      `TendEval`. The transport protocol that the harness wraps (AC-M2-28) must therefore be expressed in neutral
      types: the builder's plain request value in, and a byte or chunk stream out. Then the wrapper needs no `URL*`
      type.
    - **N-3, AC-M2-20(b) paths.** The per-provider allowed key-path list should give each path a role: fixed,
      capture, room name or shortlist title. Value comparison uses concrete array indices, because the `[]` form joins
      system and user content in chat APIs. If the user content is a templated string, the template is part of the
      golden, and the slots are compared after the template is removed.
      - Fixed numeric body parameters, such as a max-tokens value, count as part of the "schema" for the interval
        sentinel range 600…729.
      - Transport-set headers (for example `Content-Length`) are left out of the Linux header comparison, or listed
        as derived from the body.
      - I check all of this when I review the key-path lists before the freeze.

  Earlier review, v3 (kept as written):
  **v3 returned to PO (Acceptance Tester, 2026-11-21, at `20862e2`).**
  - **T-01…T-22 are closed.** I checked each row of the v3 change record against the text it points to. All six v2
    Majors are fixed in the brief:
    - environments per AC;
    - module names and scan scope;
    - draft fields, events and end rules;
    - eval scoring rules with N ≥ 50 and a fresh household per input;
    - the `TendEval` harness and results file v1 (AC-M2-28);
    - the exact duplicate shortlist.
    The Minors are fixed, or deferred with an owner and a due date. I accept the M rows as product meaning that the
    PO owns. They still need D-031 in `DECISIONS.md`, through the owner's protected-path PR.
  - I accept the authorship rule in AC-M2-14: I write the 20 inputs, the seeded household and the golden set as test
    fixtures. The scoring rules are exact enough for me to write an independent re-scorer.
  - I am returning v3 for **two new contradictions**, T-23 and T-24. A correct implementation cannot pass them as
    written. They change AC wording, so the PO must make the fix. Everything else is ready.

  **Where each AC can be proven (v3, 28 ACs)**
  | Environment | ACs |
  |---|---|
  | Linux only | AC-M2-01, 02, 03, 04, 06, 08, 09 (scan, plus Reviewer), 12, 14 (plus Tester review), 19 and 13(a). |
  | Linux + owner-run Mac | AC-M2-05, 07, 10, 18, 20 (golden bytes repeated on the Mac), 23, 24 and 28 (Release build check on the Mac). |
  | Owner-run Mac only (Linux fakes are not evidence) | AC-M2-13(b), 21 (Simulator host app) and 22 (the deadline arithmetic also runs on Linux). |
  | Device, run by the human owner, scored on Linux (AWAITING-DEVICE) | iPhone 15 Pro: AC-M2-11, 15, 16, 17. iPhone 13: AC-M2-25, 26, 27. |

  - Owner dependencies:
    - The Mac answer is in (Q8 closed). Every Mac AC, and the `TendEval` install for every device AC, now has a path.
    - Q12, Q16 and Q17 are PO default; the owner may change them. Their effect on the ACs is written down (Q12:
      AC-M2-20, 26; Q16 and Q17: AC-M2-20, 22, 26, 27).
    - Q20 (signing team) must be answered before the first device run, not before the Definition of Ready.

  *Major (blocks the tick):*
  - **T-23 AC-M2-09 Rule 3 forbids what AC-M2-22 and 23 require.** Rule 3 allows only `URLSession`,
    `URLSessionConfiguration`, `URLRequest`, `URL` and `HTTPURLResponse` in the cloud-adapter allowlist, and the
    networking-pattern list bans `URL(string:` and `URLComponents`. But a correct transport needs these:
    - a task delegate (`URLSessionTaskDelegate`, or `URLSessionDataDelegate`) to refuse a cross-host redirect
      **before** it is sent (AC-M2-22);
    - `URLError` to map offline, timeout, DNS and TLS failures to neutral reasons (AC-M2-23);
    - a streaming read (`URLSession.AsyncBytes` / `bytes(for:delegate:)`) for the provider streams (AC-M2-24);
    - one way to build the URL from the builder's host and path (`URLComponents` or `URL(string:`).
    Fix: give a closed **allowed subset** for allowlisted files, for example the types above plus `URLError`. State
    the scan rule as "every networking-pattern hit in an allowlisted file is in the subset". Add a negative test with
    one hit just outside the subset.
  - **T-24 AC-M2-20 sentinels cannot be planted in enum, Boolean or small-number fields.** The sentinel bullet lists
    kind, effort, flags, dayparts, weekdays and state. Their values cannot be unique strings, and they also appear
    legitimately in the bytes: the enum case names are in the fixed output schema, and `false` is in OpenAI's
    `store: false`. So "no sentinel appears anywhere in the bytes" cannot be tested for them.
    Fix: split the bullet.
    - **(a) Byte-level unique sentinels** for the fields that can hold a unique value:
      - task IDs and room IDs;
      - titles not on the shortlist;
      - window dates, `completedAt` and `lastTendedAt`;
      - the interval, using values that never occur in the schema or the capture text;
      - the injected `now`, the time-zone identifier and the calendar identifier.
    - **(b) A structural check** for enum and Boolean fields: the decoded body's key-path set equals that provider's
      allowed key-path list, and the only values at the capture, room-name and title paths are exactly the selector's
      inputs.

  *Minor (fix wording when convenient; does not block on its own):*
  - **T-25 AC-M2-10 versus AC-M2-05.** AC-M2-10 expects `noModel` when on-device generation throws. A throw after the
    first draft gives `interrupted` (Definitions, AC-M2-05). Say that the AC-M2-10 throwing mocks throw before the
    first draft.
  - **T-26 Rule 1 and the scorer, and the builder's hosts.** Rule 1 bans `contentsOf:`, every write and log API, and
    `https://` literals in `TendIngestion`.
    - The scorer therefore takes `Data` and returns a value. Reading the results file and writing the scorer log
      happen in a test target or a named tool outside `TendIngestion/Sources`. The plan names the exact scoring
      command (add it to the deferred list).
    - The builder's provider table holds bare hosts, which Rule 4 allows, never `https://…` literals.
  - **T-27 Rule 5 and speech permission.** If `SpeechAnalyzer` on iOS 26 still needs
    `SFSpeechRecognizer.requestAuthorization(_:)`, Rule 5 must allow exactly that one call. The Developer confirms
    this on the owner-run Mac during planning.
  - **T-28 Retry-After wording.** Q22 says "a longer `Retry-After`". AC-M2-22 says "longer than the time left". Also
    say whether the pause is a fixed 0.5 s or max(0.5 s, `Retry-After`). State one rule in both places.
  - **T-29 Fixed fixture IDs (nit).**
    - Seeded tasks and rooms carry fixed UUIDs in the fixtures, because the shortlist tie-break and the AC-M2-20
      golden requests use `id.uuidString`.
    - The harness's ID generator for committed tasks is deterministic.
  - **T-30 Rule 4 near-misses (nit).** Keychain service names, bundle IDs and similar strings must not trip the host
    pattern (for example `tend.ai.key`). The negative test includes one near-miss that should pass and one that should
    fail.

  - Still DoR conditions for the plan after the tick, unchanged from v3:
    - the full Q6 table, reviewed by me (AC-M2-03);
    - the allowlist paths, the speech file list, the results-writer file and the exact `xcodebuild` and scoring
      commands;
    - the Rule 3 allowed subset (T-23).
  - Before the AC-M2-14 freeze: the allowed key-path lists and the golden requests.
  - Before the first device run: the full DS-1 and DS-2 scripts in `acceptance.md` (my action) and Q20.

  Earlier review, v2 (kept as written):
  **v2 returned to PO (Acceptance Tester, 2026-11-21).**
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

## v3 change record (PO response to T-01…T-22, 2026-11-21)
The Tester's review above is kept as written. Each change below is either a clarification (C), which makes a rule
exact without changing what it accepts, or a meaning change (M), which changes what passes. Every meaning change is
listed here and in the handoff log. It should be mirrored into `DECISIONS.md` as one entry through the owner's
protected-path PR; the PO proposes D-031 for this. No AC was removed.

| T-item | Sev. | Change | C / M | Where |
|---|---|---|---|---|
| T-01 | Major | Defined three environments: Linux, owner-run Mac (M4 Air or M1 mini, Xcode 26, with an evidence record) and Device. Every AC now has an *Environment:* line, and those that cross the line are split into a `TendIngestion` (Linux) part and a `TendAI` (Mac) part. AC-M2-21 and 22 move to Mac-only evidence. Q8 is closed; AC-M2-13(b) now reads "owner-run Mac". | C (M for 21, 22: Linux fakes are no longer evidence) | Definitions; every AC; Q8 |
| T-02 | Major | Named the modules `TendIngestion`, `TendAI` and `TendEval`. AC-M2-09 now scans all three, with six rules. `TendAI` may import `TendIngestion`. `TendIngestion` gets Foundation + TendCore only, the full AC-M1-23 closed list, no networking, no write or log APIs. `FoundationNetworking` is banned everywhere, because `TendAI` is Apple-only and the builder needs no networking. Added a host-literal regex, an `SFSpeech*` ban and a negative test. | M (scan scope and import list widened; one new rule set) | AC-M2-09; Definitions |
| T-03 | Major | Defined the draft field set, item completion (three moments; only `title` is required), the four event types (`emitted`, `updated`, `itemSkipped`, `finished`), model-output order, and the end and error rules: a normal finish completes the item; an error discards the in-progress item and gives `interrupted`, and emitted drafts stay. Outcomes are `completed`, `interrupted`, `noModel` and `cancelled`. | M (exact oracle; adds `interrupted`, so drafts emitted before a cloud error can still be confirmed) | Definitions; AC-M2-05, 10, 23, 24 |
| T-04 | Major | Added the binding **eval scoring rules**: match groups; greedy one-to-one matching with a fixed tie-break; denominators over expected items; ⌈p × N⌉; N ≥ 50; existing, new and none room scoring; a fresh household per input; best-target counting for duplicates created; the false-merge definition; and the scorer log. The Tester authors the golden set and the Developer implements the scorer. | M (thresholds now strictly over expected items; the fresh-household rule) | After AC-M2-17; AC-M2-14; Q3 |
| T-05 | Major | Added S-M2-10 / **AC-M2-28**: the debug-only `TendEval` target is never shipped (Debug only, own bundle ID, no shipped dependency, not archived; proven by a `project.yml` scan, a Release build check and the Reviewer). It is built and installed from the owner-run Mac. Added results-file format v1, its JSON Schema, export via Files or AirDrop to `docs/milestones/M2/evidence/device/`, and request metadata as byte counts and key paths only. Reconciled with AC-M2-09 Rule 6: only scripted transcripts, drafts and metadata, never audio, bodies or keys. | M (new AC; out-of-scope list gains the exception) | S-M2-10; AC-M2-09; Out of scope |
| T-06 | Major | Defined the duplicate shortlist exactly: candidates, K and R, eligibility, the 4-step ranking, the cap of 10 and index numbers. It is shared by the on-device `Tool` and the Q12 payload. Defined the local re-check for Q12 = yes and the local word-match for Q12 = no. Added an oracle property to AC-M2-07. | C | Definitions; AC-M2-07, 08, 20, 24, 26; Q12 |
| T-07 | Minor | Q5 is now an ordered 9-step list. Out-of-range is defined in days, `Daypart.defaultAllowed` is cited, unknown elements are dropped, and the interval range is 1…730 days. | M (the numbers are new) | Q5; AC-M2-02 |
| T-08 | Minor | Q6 settles the week start (Monday), "this weekend" on Saturday or Sunday (18:00 cut-off), meteorological northern-hemisphere seasons, "tonight" ending at 05:00, "end of today" on a DST day, and "before" the current month. The Tester's table review is a DoR condition. | M (new defaults) | Q6; AC-M2-03 |
| T-09 | Minor | Name folding: trim and collapse, ASCII apostrophes, `en_US_POSIX` case, diacritic and width folding, strip one leading article, exact match. A tie goes to the lowest room ID, and duplicate proposals make one room. | C | Definitions; AC-M2-04 |
| T-10 | Minor | Guard: whole tokens split at non-letters; "in the input" means the whole input; whitespace and punctuation tidied; also applies to proposed room names; skip if both the title and `sourcePhrase` are empty. | C (M: the room-name coverage is new) | AC-M2-12 |
| T-11 | Minor | Closed lists for networking patterns, media types, and write and log APIs (the Tester's lists plus `AVAudioFile`, `AVAsset`, `CVImageBuffer`, `NSImage`, `createFile(`, `NSUbiquitousKeyValueStore`, `os_signpost(`). | C | AC-M2-09 |
| T-12 | Minor | Added unsupported locale as an unavailable reason. The matrix now covers consent and a key for a provider that is not selected, and "always use my cloud model" with cloud off (ignored). Defined the "selected provider". | C | AC-M2-10, 19; Definitions |
| T-13 | Minor | AC-M2-11 and 25 now have exact per-input pass rules (route, outcome, all golden items matched, 0 extras, all valid, 0 banned, 0 duplicates). "Equal to the online run" is removed. Greedy or lowest-variance sampling is recorded. | M (pass rule replaced) | AC-M2-11, 25; device-run rules |
| T-14 | Minor | Restored state is now three fixtures. A key with no consent record is deleted. The durable consent store must not be restorable and is deferred to **M3 (Q21; owner: PO; due with the M3 brief)**. No real device restore in M2. | M (orphan-key deletion is new) | AC-M2-18; Definitions; Q21 |
| T-15 | Minor | Canonical JSON identical on Linux and the Mac. Media rejected by type (the input type is `String`/`[String]` only). Opt-outs listed per provider (OpenAI `store: false`; Anthropic none; Gemini none). The Gemini key goes in the `x-goog-api-key` header, not the query. The sentinel list now matches the real M2 model. Member and assignee sentinels are deferred to **M5 (owner: PO; due with the M5 brief)**. Room names are sent as written (Q19, PO default). | M (sentinel list matches the model; header rule is new) | AC-M2-20; Definitions; Q19 |
| T-16 | Minor | Keychain tests run on the iOS Simulator with a host app on the owner-run Mac. Attributes are asserted through `kSecReturnAttributes`. The masked format is defined, including short keys. | C | AC-M2-21 |
| T-17 | Minor | Resource and request timeouts are defined against a 10.0 s deadline, with the retry rule (Q22, PO default). Evidence comes from the owner-run Mac, with deadline arithmetic also on Linux. | M (numbers new) | AC-M2-22; Q15; Q22 |
| T-18 | Minor | "None blames the user" is now Reviewer inspection of case names, with copy left to the Designer in M3. The retry is tested with an injected clock. | C | AC-M2-23 |
| T-19 | Minor | Fixtures are synthetic plus ≥ 1 real recording per provider, made by the owner on the Mac with the Outcome sample sentence, and response only. The AC-M2-07 `Tool` clause is replaced for cloud output by the local re-check, and the brief lists what applies. | C | AC-M2-24 |
| T-20 | Minor | Device-run rules: one retake per voice input only for a misread, every attempt kept, no re-run for a pass, and the run-record fields. | C | Device-run rules |
| T-21 | Minor | The Q9 invariant moves into an AC-M2-02 clause; AC-M1-25 is not edited. UX-2 is mapped to AC-M2-13 in the gate mapping. | C | AC-M2-02; Q9; Gate mapping |
| T-22 | Minor | Rule for tests compiled out on Linux; the AC → test table states an environment for every test. | C | AC-M2-13 |

**Deferred items, with owner and due date:**
- The durable consent store, so that a restore never turns cloud on (Q21). Owner: PO, as an M3 brief AC. Due: the
  M3 brief.
- Member and assignee sentinels in AC-M2-20 (T-15). Owner: PO, in the M5 brief. Due: the M5 brief.
- The full Q6 table (T-08). Owner: Work Planner, in `plan.md`. Due: before the Definition of Ready, with the Tester's
  review.
- The cloud-adapter allowlist paths, the speech-adapter file list, the results-writer file and the exact `xcodebuild`
  commands (T-02, T-05). Owner: Work Planner with the Developer, in `plan.md`. Due: before the Definition of Ready.
- The per-provider allowed key-path lists and golden requests (AC-M2-20, 26). Owner: the Developer, reviewed by the
  Tester. Due: before the AC-M2-14 freeze.
- The full device scripts DS-1 and DS-2 in `acceptance.md`. Owner: Acceptance Tester. Due: before the first device
  run.

## v4 change record (PO response to T-23…T-30, 2026-11-21)
The same C / M convention applies as in v3. The M rows are added to the proposed D-031 entry (protected path, owner
merge). No AC was removed, and the AC count stays 28.

| T-item | Sev. | Change | C / M | Where |
|---|---|---|---|---|
| T-23 | Major | AC-M2-09 Rule 3 now has a **closed allowed networking subset** for allowlisted cloud-adapter files: `URLSession`, `URLSessionConfiguration`, `URLSessionTask`, `URLSessionTaskDelegate`, `URLSession.AsyncBytes` / `bytes(for:delegate:)`, `URLRequest`, `URL`, `URLComponents`, `URLResponse`, `HTTPURLResponse` and `URLError`. The scan rule is that every networking-pattern hit, and every `URL`/`NSURL`/`HTTP`/`NW`/`CFHost`/`CFStream`/`CFNetwork` identifier, in an allowlisted file is in the subset. `URLComponents` is the one way to build a URL; `URL(string:` stays banned. Negative test: `URLSessionWebSocketTask` and `URL(string:` are caught, and a subset-only file passes. This makes the redirect refusal (AC-M2-22), error mapping (AC-M2-23) and streaming read (AC-M2-24) possible within the scan. The subset is now fixed in the brief, so the plan only names the files. | M (allowed set widened to exactly what AC-M2-22…24 need) | AC-M2-09 Rule 3 |
| T-24 | Major | The AC-M2-20 sentinels are split into two checks. (a) **Byte-level unique sentinels:** IDs, non-shortlisted titles, window dates, `completedAt`, `lastTendedAt` (each in four date forms), the interval (600…729 days, chosen to collide with nothing), and the `now`, time-zone and calendar identifiers. String sentinels are absent from the whole request; interval sentinels are absent as numbers and digits in the body, path, query and header values. (b) **Structural check** for enum, Boolean and set fields: the key-path set equals the allowed list; the capture, room-name and title values are exactly the selector's inputs; every other value and header equals the golden request. Enum and Boolean fields are no longer byte sentinels. | M (the test method changes; the protection is the same or stronger) | AC-M2-20 |
| T-25 | Minor | The AC-M2-10 throwing mocks throw **before the first draft**. A throw after a draft is `interrupted` (AC-M2-05). The route never changes to the cloud either way. | C | AC-M2-10 |
| T-26 | Minor | The scorer in `TendIngestion` takes `Data` and returns a value. File reading and log writing happen in its test target or a named scoring tool, and the plan names the tool and the command. Rule 4: the builder's provider table holds bare hosts only; `https://` literals appear only in allowlisted files. | C | AC-M2-09 Rules 1 and 4 |
| T-27 | Minor | Rule 5 has a conditional exception: exactly `SFSpeechRecognizer.requestAuthorization(` and `authorizationStatus(` (and the status type), in one named speech-permission file, and only if the Developer confirms on the owner-run Mac that iOS 26 needs them. Otherwise there is no exception. There is a negative test for the `SFSpeechRecognizer(` initialiser. | M (narrow, conditional exception) | AC-M2-09 Rule 5 |
| T-28 | Minor | One retry rule in AC-M2-22 and Q22: the pause is max(0.5 s, `Retry-After` in delta-seconds, where missing or unreadable counts as 0). The retry happens only if ≥ 3.0 s are left after the pause. | M (the `Retry-After` value is now honoured, not only compared) | AC-M2-22; Q22 |
| T-29 | Minor | Seeded tasks and rooms carry fixed UUIDs in the fixtures. The harness ID generator is deterministic (seeded by input and attempt, defined in the plan) and never yields a fixture UUID. | C | Eval scoring rules; AC-M2-28 |
| T-30 | Minor | Rule 4 matches host-like literals against the **whole literal**, so reverse-DNS bundle IDs and Keychain service names are not hits. Negative test: `tend.ai.key` passes; `api.example.com` and `https://api.example.com/v1` are caught. | C | AC-M2-09 Rule 4 |

**Added to the deferred list (v4):**
- The scoring tool and the exact scoring command (T-26). Owner: Work Planner with the Developer, in `plan.md`. Due:
  before the Definition of Ready.
- The speech-permission check and the file name (T-27). Owner: Developer, on the owner-run Mac. Due: during planning,
  before the Definition of Ready.
- The speech-permission file name and the harness ID-generator definition (T-27, T-29). Owner: Work Planner, in
  `plan.md`. Due: before the Definition of Ready.
- The Rule 3 allowed subset is no longer deferred; it is fixed in the brief. The plan only lists the allowlisted files.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Capture is voice or free text. Every field is inferred (AC-M2-01…04), and confirmation is a single act (AC-M2-06). No form exists or is needed. |
| UX-2 Rule of Three | pass | No new "what to do now" API. Committed tasks reach Now only through `NowSelector` (≤ 3, M1). The draft review list is defined as a capture review, not a Now surface (Q11). |
| UX-3 Zero-Guilt | pass | Calm-words guard (AC-M2-12). Calm outcomes when the model is unavailable (AC-M2-10). No new state or counter: the M1 model and D-2/D-3 are unchanged. |
| UX-4 Design craft | n.a. | No product UI in M2 (M3). The `TendEval` harness is a debug-only test tool that is never shipped (AC-M2-28), so it is not judged against UX-4. |
| P-1 On device first (D-030) | pass | `FoundationModels` is preferred whenever it is available (AC-M2-19). Speech is always on device (AC-M2-09, AC-M2-25), proven offline on device (AC-M2-11, AWAITING-DEVICE). Cloud is used only on the ADR-0005 routes. |
| P-2 Data leaves only via iCloud or a P-3 request (D-030) | pass | Networking only in allowlisted cloud files, only a closed `URLSession` subset, only three fixed hosts, no SDKs (AC-M2-09 Rules 3 and 4, AC-M2-22). The duplicate `Tool` reads only the local household and is never given to a cloud model (AC-M2-07, AC-M2-24). |
| P-3 Cloud AI opt-in and minimised, ADR-0005 (D-030) | pass (ADR-0005 merged in PR #11) | Off by default and consent-gated, an orphan key is deleted, and a restore never turns cloud on (AC-M2-18, Q21). Payload limited to allowed content through a narrow builder input type and a deterministic shortlist, proven byte for byte on Linux and the Mac (AC-M2-20). The key travels only in the auth header, never the URL. Keychain only (AC-M2-21). Calm fallback (AC-M2-23). Retention options requested (AC-M2-20); honest disclosure copy is M3. Owner questions Q12, Q16 and Q17 are open. |
| P-4 Media not persisted without consent | pass | Audio and transcripts stay in memory in the shipped modules (AC-M2-09). The never-shipped harness writes only scripted eval transcripts, drafts and request metadata, never audio, bodies or keys (AC-M2-28). No background queue (AC-M2-23). Nothing is saved before commit (AC-M2-06). Audio and images are never sent to a cloud model (AC-M2-09, AC-M2-20). Eval voice inputs are spoken live and never recorded (AC-M2-15, AC-M2-26). The Privacy Manifest and privacy label, including cloud use, ship with the app target (M3). |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-20 | Product Owner | Acceptance Tester | to send for testability review | Brief v1 (Draft), written after the M1 gate (ACCEPTED, STATUS.md). 6 stories, 17 ACs (AC-M2-01…17); device ACs AC-M2-11, 15, 16 and 17 are AWAITING-DEVICE. Human-owner questions: Q1 (PCC), Q8 (macOS lane); Q3 thresholds are open to owner tightening. After the Tester's review, the PO hands off to the Work Planner (H1). |
| 2026-11-21 | Product Owner | Orchestrator → human owner | to merge (protected paths) | Brief v2 (still Draft) for D-030 / ADR-0005: the owner chose BYOK cloud AI and an iPhone 13 floor. Added S-M2-07…09 and AC-M2-18…27 (device: AC-M2-25, 26, 27, all AWAITING-DEVICE). Rewrote AC-M2-09 and AC-M2-10, and closed Q1. New owner questions: Q12 (task titles for duplicates), Q16 (which providers gate M2), Q17 (Gemini free tier). Q13, Q14, Q15 and Q18 are PO defaults. Next: the owner merges the policy PR, then the Acceptance Tester runs the testability review of v2, then the Work Planner. |
| 2026-11-21 | Acceptance Tester | Product Owner | returned | Testability review of v2 at `a6009e8`. Six Major items (T-01…T-06) block the tick; T-07…T-22 are Minor. The owner's Mac (Xcode 26) answers Q8 and gives the build path for the device harness. Q12, Q16 and Q17 are still open (PO defaults assumed). Split: Linux 01–04, 06, 08, 12, 19, 20, 23, 13(a) and the logic halves of 05, 07, 09, 10, 14, 18, 24; Mac 13(b), 21, 22 and the adapter halves; device 11, 15, 16, 17, 25, 26, 27 (AWAITING-DEVICE, outlines DS-1 and DS-2). |
| 2026-11-21 | Product Owner | Acceptance Tester | to re-review (v3) | Brief v3 answers T-01…T-22; see "v3 change record". All six Majors are fixed in the brief: environments per AC (T-01), the AC-M2-09 modules, imports and scope (T-02), the draft fields, events and end/error rules (T-03), the eval scoring rules (T-04), the never-shipped `TendEval` harness with results file v1 as new S-M2-10 / AC-M2-28 (T-05), and the exact duplicate shortlist (T-06). All Minors T-07…T-22 are fixed or deferred with an owner and due date. Meaning changes (M rows) are recorded in the change record; the PO proposes D-031 to mirror them in `DECISIONS.md` (protected path, owner merge). No AC was removed; the AC count is now 28. Q8 is closed (owner-run Mac). Q12, Q16 and Q17 stay **PO default, owner may change**. New: Q19 and Q22 (PO defaults), Q20 (signing team, owner), Q21 (consent store, deferred to M3). Next: the Tester re-reviews v3. If it is ticked, the brief goes to the Work Planner. |
| 2026-11-21 | Acceptance Tester | Product Owner | returned | Re-review of v3 at `20862e2`. T-01…T-22 are closed. Two new Majors block the tick: T-23 (the AC-M2-09 Rule 3 networking allowlist forbids the delegate, `URLError`, streaming bytes and the URL building that AC-M2-22, 23 and 24 need) and T-24 (the AC-M2-20 sentinels cannot be planted in enum or Boolean fields; split into byte-level and structural checks). T-25…T-30 are Minor or nit. Split: Linux 01–04, 06, 08, 09, 12, 14, 19, 13(a); Linux + Mac 05, 07, 10, 18, 20, 23, 24, 28; Mac 13(b), 21, 22; device 11, 15, 16, 17, 25, 26, 27 (AWAITING-DEVICE, scored on Linux). Q12, Q16, Q17 PO default; Q20 before the first device run. |
| 2026-11-21 | Product Owner | Acceptance Tester | to re-review (v4) | Brief v4 answers T-23…T-30; see "v4 change record". T-23: closed allowed networking subset in AC-M2-09 Rule 3, with an identifier-prefix scan rule and a negative test. T-24: AC-M2-20 sentinels split into (a) byte-level unique sentinels and (b) a structural key-path and value check against the golden request. T-25…T-30 are all fixed in the brief. Meaning changes: T-23, T-24, T-27 and T-28 (M rows), to be added to the proposed D-031 (owner merge). No AC was removed; there are still 28 ACs. New planning items: the scoring tool and command, the speech-permission check (Developer, on the Mac) and the ID-generator definition. Owner items unchanged: Q12, Q16, Q17 (PO default, owner may change) and Q20 (before the first device run). Next: the Tester re-reviews v4; if it is ticked, the Work Planner. |
| 2026-11-21 | Acceptance Tester | Product Owner → Work Planner | accepted (testability ticked) | Re-review of v4 at `580d23e`. T-23…T-30 are closed, so T-01…T-30 are all closed. All 28 ACs are observable and measurable, with an environment and evidence each. Final split: Linux 01–04, 06, 08, 09, 12, 14, 19, 13(a); Linux + Mac 05, 07, 10, 18, 20, 23, 24, 28; Mac 13(b), 21, 22; device 11, 15, 16, 17, 25, 26, 27 (AWAITING-DEVICE, scored on Linux). Nits N-1…N-3 go to the plan and the Developer. Conditions: the plan items before the DoR (Q6 table reviewed by the Tester, file paths, commands, scoring tool, ID generator); the fixtures, key-path lists and golden requests before the AC-M2-14 freeze; DS-1 and DS-2 before the first device run; D-031 by owner merge. Q12, Q16, Q17 PO default; Q20 before the first device run. |
| 2026-11-21 | Product Owner | Work Planner → Developer, Reviewer | accepted | PO 2026-11-21, stricter only, from PR #15 review (R1-F1 point 4, R1-F5). Q23: one fixtures-loader exception for `Data(contentsOf:` in `Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift`, bundle URLs only, with negative and positive tests (AC-M2-09 Rule 6; cross-reference in M1 AC-M1-23). Q24: session method calls added to the networking list; C file and print calls and `write(toFile:` added to the write and log list; Rule 3 allows only `bytes(for:delegate:)`; Rule 6 gets a closed import list; new negative tests (AC-M2-09). No AC removed; there are still 28 ACs. DECISIONS.md entries for M2 Q23 and Q24 go in the human-merged governance PR. Timing is in `plan.md`. |
| 2026-11-21 | Acceptance Tester → Product Owner | Work Planner | accepted | Tester returned PR #16 (findings 1-9); PO accepted all, stricter only. AC-M2-09 v2 texts applied, replacing the v1 Q23/Q24 wording: separate write and log lists (new `AppStorage`, `SceneStorage`, `archiveRootObject(`, `mkstemp(`, `tmpfile(`, `creat(`, `vprintf(`, `vfprintf(`, `dprintf(`, `puts(`, `putc(`, `putchar(`, `perror(`, `syslog(`), `bytes(for:` added to the session-method calls, an exact call-pattern matching rule, `contentsOf:` bullets in Rules 2, 3 and 6, the Rule 3 session-method rule (`bytes(for:` only with `delegate:`), Rule 6 rewritten (import parsing, literal-only fixtures loader), and new plant and positive tests. Q23/Q24 rows updated; M1 AC-M1-23 cross-reference revised. No AC removed; there are still 28 ACs. |
| 2026-11-21 | Acceptance Tester | PO -> Work Planner | accepted (testability ticked) | Re-review of PR #16 at 25ddc36; findings 1-9 closed; Minors 1-3 folded in (stricter only). |
