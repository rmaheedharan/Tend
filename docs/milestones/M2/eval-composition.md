# M2 eval composition (WI-M2-16, AC-M2-14): fixtures for PO approval

- **Owner:** Acceptance Tester  ·  **Base commit:** `1d1caa3` (branch `m2/eval-fixtures-freeze`; v6 on `m2/eval-freeze`)  ·  **Date:** 2026-11-24, v6 2026-11-25, v7 2026-11-28
- **Status:** composition **APPROVED by the PO with conditions** (`po-m2-wi16.md` ruling 1, 2026-11-24) for the three
  fixture files at commit `95491ed`, re-approved for `golden.json` with the EC-Q8 relabel (hashes in "PO approval"
  below). **FROZEN 2026-11-25** by the Acceptance Tester (WI-M2-16, AC-M2-14): `Fixtures/M2/eval/MANIFEST.sha256` is
  committed, written by the documented command, and lists `golden.json` `0e819a89…`, `household.json` `089a22bd…`,
  `inputs.json` `b32e45af…` (the PO-approved hashes) and `results-v1.schema.json` `ffc01f37…`. **Reopened 2026-11-27 for `results-v1.schema.json` only under D-059**
  (PO, `po-m2-element-counts.md`; per-array element counts). **Re-frozen 2026-11-28 by the Acceptance Tester at commit
  `e014fab` on `m2/eval-harness`:** `results-v1.schema.json`
  `096161326b049b9f0f3aa62756d7e98e8d43bb3705619620623d40bbbd97869a`. `MANIFEST.sha256` changed on line 4 only and
  verifies (`sha256sum -c`, 4 × OK). The three data files are unchanged (`0e819a89…`, `089a22bd…`, `b32e45af…`). The
  fixtures hash (SHA-256 of `MANIFEST.sha256`, shown by TendEval) is
  **`7fdc056e92e419a4b416ea14493a7cc2ab9188bb559c796bd79ed45d2141de22`** (was `e85dde40…5e39`). `m2/eval-harness`
  (with `e014fab`) is merged to `main` in PR #52 (merge commit `1b81e7b`), so this hash is valid on `main`; `main`'s
  `MANIFEST.sha256` hashes to it. The D-054 / D-058 composition approval stands. Tester re-check: `tester-freeze-recheck-d059.md`. Ruling 1 conditions:
  (a) GR-1, (b) GR-2 and (c) GR-3 CLOSED at PR #32 head `02f944e` (merged; the golden payload files on `main` equal
  `02f944e`'s), GR-5 CLOSED there too; (d) L2a (GR-4): Gemini **PASS** on the committed golden body, OpenAI and
  Anthropic **deferred by the owner's decision** ("L2a outcome", 2026-11-25: their calls returned billing errors only,
  so nothing was verified; their L2a must pass before their DS-2 runs count, `acceptance.md` AC-M2-26); (e) the
  Developer's Linux composition check passes at the freeze commit; (f) doc edits done. Any data change from now on
  needs a PO decision in `DECISIONS.md` and a pin and manifest update in the same commit.
- **Revisions:** v1 at `95491ed` (for approval). v2: PO rulings of `po-m2-wi16.md` applied to this document
  only. v3: GR-1, GR-2, GR-3 and GR-5 verified on PR #32 (`m2/cloud-instructions`, head `02f944e`) and
  closed; GR-9 and GR-10 added; AQ-2/AQ-4 answered (PO follow-up rulings F3, F4). v4: review WI-M2-16 round 1 F2 answered
  (rule 9 states that the person's verb decides; EC-Q8 to the PO: relabel `g16-carservice` effort `low`). v5: PO approved EC-Q8; `golden.json` relabelled in that one value (`$.items[43].effort`, `g16-carservice`,
  `normal` → `low`), new SHA-256 recorded; EC-Q8 and review F2 closed. `inputs.json` and `household.json` are
  **unchanged**. v6 (2026-11-25): **frozen** (Status above; GR-4 row; the
  manifest). No fixture data changed.
  v7 (2026-11-28): D-059. Only `results-v1.schema.json` changed (two required count members,
  `uniqueItems`); manifest line 4 and the fixtures hash updated. No fixture data changed.
- **Requirement IDs:** FR-A1, UX-3, P-3, AC-M2-14 (also feeds AC-M2-11, 15, 16, 17, 25, 26, 27), brief rubric Q3,
  Q5, Q6, Q12, brief "Eval scoring rules", PO WI-M2-15 ruling 1 ("Distinguishable targets").

## Files (written by the Acceptance Tester, AC-M2-14 "Authorship")

| File | SHA-256 (as committed, pre-freeze) | Content |
|---|---|---|
| `Fixtures/M2/eval/inputs.json` | `b32e45afeb25a6d8972ce9f3b78a6dd051686d4ac6b7d87564769bf92c7ebcec` | 20 inputs (10 voice, 10 text). Extra members the reader ignores: `composition` (tags for the composition check) and `q6Rows` (the time-phrase rows each input uses, information only). |
| `Fixtures/M2/eval/household.json` | `089a22bd5a0b3da9ef6b057b186f61b459963f02bbee322c30a47b2af8e17f66` | 9 rooms and 19 seeded tasks (16 not completed: 13 `active`, 1 `maintenance`, 1 `resurfaced`, 1 `deferred`; 3 `completed`). Fixed version-4 UUIDs `E7A1C0DE-0000-4000-8000-0000000001nn` (rooms) and `…0000000002nn` (tasks). Each task has match groups. |
| `Fixtures/M2/eval/golden.json` | `0e819a89fcb65adb0a764d296f1d0dc8f30275cfe074495a4fe9c793a0f4b771` (v5; was `882c2906…` before the EC-Q8 relabel) | 58 golden items: 41 `create`, 17 `existing(seededKey)`. Each has a `referencePhrase` (PO WI-M2-15 ruling 1; on every item, not only `create`). |

The files use exactly the WI-M2-15 reader format (`EvalFixtures.swift`). `results-v1.schema.json` is unchanged. The
self-test set `Fixtures/M2/eval-selftest/` is unchanged. Sources and tests are unchanged.

## PO approval (AC-M2-14 "Authorship": the PO approves the composition)

| What | Value |
|---|---|
| Decision | **APPROVED, with conditions** (`po-m2-wi16.md` ruling 1, PO, 2026-11-24). C1–C12 meet rubric Q3 and AC-M2-14; the extra cases are accepted. |
| Approved at | commit `95491ed` (branch `m2/eval-fixtures-freeze`) |
| `Fixtures/M2/eval/inputs.json` | `b32e45afeb25a6d8972ce9f3b78a6dd051686d4ac6b7d87564769bf92c7ebcec` |
| `Fixtures/M2/eval/household.json` | `089a22bd5a0b3da9ef6b057b186f61b459963f02bbee322c30a47b2af8e17f66` |
| `Fixtures/M2/eval/golden.json` | `882c2906a15704b9b8376cfdd62aa3b909239b4b6f7ca9ce4d370fa69580d4dc` (approved at `95491ed`; superseded by the EC-Q8 re-approval below) |
| EC-Q8 re-approval | `po-m2-wi16.md` "EC-Q8" (PO, 2026-11-24): composition re-approved for a `golden.json` whose only difference from `882c2906…` is `g16-carservice` effort `normal` → `low`. |
| `Fixtures/M2/eval/golden.json` (current, approved) | **`0e819a89fcb65adb0a764d296f1d0dc8f30275cfe074495a4fe9c793a0f4b771`**. This is the hash the Developer pins in `EvalFreezeTests.swift` and `MANIFEST.sha256`. |
| One-value diff (evidence) | `git diff -U1` on `golden.json`: one line, `-      "effort": "normal",` / `+      "effort": "low",` at line 1123 (numstat `1 1`). A JSON tree comparison of the old and new file (my script, `python3 -I`) gives exactly one difference: `$.items[43].effort: 'normal' -> 'low'`, and `items[43].key` is `g16-carservice`. |
| Re-checked | v5, 2026-11-24, after the relabel: `inputs.json` `b32e45af…ebcec` and `household.json` `089a22bd…17f66` unchanged; `golden.json` = the current hash above. Earlier (v2): `sha256sum` of the three files after the v2 doc edit: identical to the values above (the PO note gives the 8-character prefixes `b32e45af…`, `089a22bd…`, `882c2906…`). |
| Change rule | Any data change before the freeze goes back to the PO; after the freeze it needs a PO decision in `DECISIONS.md` (AC-M2-14). |
| Conditions before the freeze | (a) GR-1 fixed (ruling 3) and the 9 golden bodies regenerated; (b) the room, effort and weather instruction lines of rulings 4, 5 and 9 in the same regeneration; (c) GR-3 (WI-M2-M4); (d) L2a (GR-4); (e) the Developer's Linux composition check passes; (f) these doc edits (done in v2). **v3:** (a), (b), (c) verified at PR #32 head `02f944e` ("Verification of the regenerated golden requests" below), to hold when PR #32 merges; (d) and (e) open. **v6 (freeze, 2026-11-25):** PR #32 merged with those golden files; (d) Gemini L2a PASS, OpenAI and Anthropic L2a deferred by the owner's decision (GR-4 row); (e) passes (TendIngestion suite at the freeze commit). All met or covered: **frozen**. |

## Q3 composition: each rule and the inputs that meet it (for PO approval)

Read from the brief's rubric Q3 "Composition" and AC-M2-14. Counts come from the fixtures (my generator's check) and
match the `composition` tags. The checker refuses a tag that disagrees with the golden flags.

| # | Q3 / AC-M2-14 rule | Required | In the fixtures | Inputs |
|---|---|---|---|---|
| C1 | 20 inputs | 20 | 20 | in01…in20 |
| C2 | voice inputs | ≥ 8 | 10 | in02, 04, 06, 08, 10, 12, 14, 16, 17, 20 |
| C3 | text inputs | ≥ 8 | 10 | in01, 03, 05, 07, 09, 11, 13, 15, 18, 19 |
| C4 | 10–80 words each (whitespace-split) | all | 21–35 | all 20 |
| C5 | all four item types (one-off errand, recurring maintenance, consumable restock, weather-dependent) | all four | oneOff 36, recurring 12, restock 10 items; 12 weather-dependent items | e.g. one-off in02, recurring in09, restock in11, weather in13 |
| C6 | a weather condition | ≥ 5 inputs | 9 inputs (12 items) | in01, 04, 07, 10, 13, 14, 16, 19, 20 |
| C7 | critical (bill, expiring food) | ≥ 3 inputs | 5 inputs (8 items): bills in02, 08, 18; expiring food in05, 11, 18; also car insurance (in08) and smoke alarms (in11) | in02, 05, 08, 11, 18 |
| C8 | deep cleans | ≥ 3 inputs | 5 inputs (6 items) | in01, 05, 09, 14, 19 |
| C9 | mentioning an existing task | ≥ 5 inputs | 15 inputs (17 items) | in01, 02, 04, 05, 06, 07, 08, 09, 10, 11, 12, 14, 16, 17, 19 |
| C10 | a repeat inside the input | ≥ 3 inputs | 4 | in03 (milk), in06 (toilet paper), in12 (trash), in18 (property tax) |
| C11 | filler or self-correction ("no wait, Thursday") | ≥ 4 inputs | 10 (self-corrections in02, 08, 14, 16, 20) | in02, 04, 06, 08, 10, 12, 14, 16, 17, 20 |
| C12 | ≥ 50 expected items, ≥ 1 per input | N ≥ 50 | N = 58, 2–3 per input | all 20 |

**Extra cases I added beyond Q3** (they make the duplicate gate meaningful, AC-M2-17, 26):
- **A completed task said again is new** (brief Definitions "Duplicate"): in03 milk (`t-milk` completed) and the hallway
  bulb (`t-bulb` completed) are `create`.
- **False-merge traps** (same object, different chore or room): in15 "water the bathroom plants" against the live
  `t-plants` (garden); in04 "trash bags" against `t-bins` ("Take the trash out"); in16 "car … service" against `t-car`
  ("Wash the car").
- **Non-`active` targets:** `maintenance` oven (in05), `resurfaced` car insurance (in08), `deferred` fence (in14).
- **A synonym the model must see:** in06 and in17 say "dishwasher tablets" for `t-pods` ("Buy dishwasher pods"). The
  local word-match floor cannot catch it, so the model's own claim is tested.
- **New rooms:** Balcony (in01), Patio and Shed (in07), Porch (in13), scored as `new(name, alternates)`.
- **in01 is the PRD FR-A1 sentence** word for word.

### P1–P7 (plan Q6 table): coverage, information only

The Orchestrator's task names a "P1–P7 composition", but P1–P7 in the plan are the Planner's Q6 time-phrase rows, not composition
rules (open question EC-Q3). The eval scoring rules do not score windows, so this coverage is for information only.
Each row is used at least once:

| Row | Phrase family | Inputs |
|---|---|---|
| P1 (T3) | "this afternoon" | in20 |
| P2 (T7/T8) | weekday, "no wait, Thursday" | in02, 07, 11, 15, 16 |
| P3 (T10) | "this week" | in08, 18 |
| P4 (T14) | "in three days" | in17 |
| P5 (T15) | "some evening" | in18 |
| P6 (R4) | "every year" | in10, 20 |
| P7 (R5/R6/R7) | "every Tuesday", "every weekend", "every morning" | in12, 13, 10 |

Other Q6 rows used: T1, T2, T4, T5, T9, T11, T13, R2, R3.

## Fixture rules I applied (checked by my generator on every build)

1. **Version-4 UUIDs.** Every room and task ID has version nibble `4` and variant `8` (plan "Eval harness ID
   generator"), so `EvalIDGenerator` (version 8) can never yield one. IDs are unique across rooms and tasks.
2. **No decimal digit run holds 600…729** in any of the three files (IDs, dates, intervals, text). The interval
   sentinels (N-3, AC-M2-20) cannot be confused with fixture data.
3. **Calm words (AC-M2-12, UX-3).** No banned token (*overdue, late, lateness, missed, failed, behind, penalty, debt,
   streak*) appears as a whole token in any file. So any banned token in a draft is "introduced" (PO WI-M2-15 S4).
4. **Match-group tokens are single keywords.** Each token is `Keywords.of(token) == [token]`, so none is a stop word.
   The Swift reader also enforces this.
5. **Distinguishable targets** (PO WI-M2-15 ruling 1). For every golden item, I take the keywords of its
   `referencePhrase`, of a natural title, and of title plus phrase (and the repeat phrase for C10), and I check the
   best target under the brief's rule. Each `create` item's best target is that item, and no seeded task ties or beats
   it. Each `existing` item's best target is its seeded task. The Swift scorer confirms this on the hand-made perfect
   file (below).
6. **Every existing-task mention can be reached on every path.** For each input I computed the Q12 duplicate
   shortlist (brief Definitions steps 1–6). Each of the 17 `existing` items' seeded tasks is on its input's shortlist
   (≤ 6 eligible per input, so the cap of 10 never cuts). This holds for the Q12 = yes cloud path, and the on-device
   `Tool` can find it with any input keyword. No `create` item's natural title is caught by the local word-match floor
   against a live task, so the pipeline's own floor cannot cause a false merge. (While doing this I found and fixed
   one case: "dish tablets" shared no keyword with "Buy dishwasher pods". That would have made AC-M2-26's
   0-duplicate gate impossible to pass by construction, and it is now "dishwasher tablets"; see EC-Q5.)
7. **Golden fields of an `existing` item equal its seeded task** (kind, room, effort, three flags). Each input states
   the repeat ("like every week", "a monthly thing", "every Tuesday") when the seeded task is recurring, so the golden
   kind is what the person said.
8. **Rooms (EC-Q1; confirmed by PO ruling 2).** An `existing(room)` expectation is used only when the person says that
   room's name in the input. The checker enforces this. Chores with no place (paying, booking, buying, outdoors with no
   room named) are `none`. A place the person names that is not in the household is `new`. Pure inference without a
   named room is not scored in M2 (ruling 2; unnamed-room cases such as "descale the kettle" go to the M3 dev-set).
9. **Effort (EC-Q4; wording per PO ruling 5).** `low` is a quick errand or touch-up (pay, book, buy, wipe, water, test,
   sweep). `high` is a deep clean or a long job (a big sort-out, painting or staining: the shed sort-out, the fence).
   `normal` otherwise. (v1 said "a job the person calls big"; the fence is high without being called big, so the PO
   fixed the wording to "a long job". The golden data is unchanged.) **v4 (review WI-M2-16 F2):** the person's verb
   decides. When they say "book" (or pay, buy) the item is the booking and is `low` (`g02-dentist`, `g14-cleaner`,
   `g20-chimney`); when they name only the service ("the AC needs servicing", "get the water heater serviced") it is
   `normal` (`g01-ac`, `g10-heater`). `g16-carservice` ("book the car in for a service") was `normal` and broke this
   rule; v5 relabels it `low` (EC-Q8, PO approved; booking, paying, buying or ordering is `low`).
10. **en-US phrasing** (brief Q2): trash, toilet paper, property tax, water heater. No names, addresses or real
    personal data.

## Inputs

| # | Mode | Words | Text | Tags | Q6 rows (info) |
|---|---|---|---|---|---|
| in01 | text | 24 | The AC needs servicing before summer, we're almost out of dishwasher pods, and let's deep clean the balcony this weekend if it doesn't rain | weather, deepClean, existingTask | T13, T9 |
| in02 | voice | 31 | Um, okay, so I need to pay the electric bill by Friday, no wait, Thursday, and, uh, book the dentist for the kids, and the bathroom sink is draining really slowly | critical, existingTask, fillerOrCorrection | T7 |
| in03 | text | 25 | We're out of milk, grab some on the way home, the hallway light keeps flickering so swap the bulb, and seriously, don't forget the milk | repeat, completedTaskSaidAgain | T1 |
| in04 | voice | 35 | So, uh, the gutters are full of leaves again, clear those once it's dry, and mow the back garden every week from now on, but only when it's not raining, and grab more trash bags | weather, existingTask, fillerOrCorrection | R2 |
| in05 | text | 28 | The chicken in the kitchen fridge needs cooking by tomorrow, the oven still needs that deep clean, and give the bathroom grout a proper deep scrub this weekend | critical, deepClean, existingTask | T5, T9 |
| in06 | voice | 32 | Okay, uh, we're nearly out of dishwasher tablets, and toilet paper, we need toilet paper, and um the washing machine in the laundry room smells funny so run a hot cleaning cycle | existingTask, repeat, fillerOrCorrection | T1 |
| in07 | text | 28 | Sweep the patio every other week when it's dry, wash the car this Saturday if the sun's out, and have a big sort-out of the shed before winter | weather, existingTask, newRoom | R2, T7, T13 |
| in08 | voice | 28 | Right, the water bill, pay that by the twentieth, um, no, by the fifteenth, and renew the car insurance this week, and, uh, pick up a birthday card | critical, existingTask, fillerOrCorrection | T10 |
| in09 | text | 26 | Deep clean the carpet in the kids room, it's sticky everywhere, the weekly sheet change in our bedroom, and vacuum the living room like every week | deepClean, existingTask | R2 |
| in10 | voice | 29 | Um, so water the garden plants every morning, and, uh, the windows, wash the outside windows when there's no rain forecast, and get the water heater serviced every year | weather, existingTask, fillerOrCorrection | R7, R4 |
| in11 | text | 23 | Test the smoke alarms, it's a monthly thing, the yogurt expires on Wednesday so eat it before then, and buy more coffee beans | critical, existingTask | R3, T7 |
| in12 | voice | 27 | Take the trash out tonight, it's trash day every Tuesday, um, fix the squeaky garage door this weekend, and, uh, yeah, the trash, don't forget the trash | existingTask, repeat, fillerOrCorrection | T4, R5, T9 |
| in13 | text | 28 | Every weekend sweep the front porch, rake the leaves in the garden when it's dry, and hang the clothes out on the line today if it stays sunny | weather, newRoom | R6, T2 |
| in14 | voice | 32 | Okay so, um, paint the garden fence when it's dry, no, actually, just stain it, sometime next week, and deep clean the kitchen fridge, it smells, and, uh, book the window cleaner | weather, deepClean, existingTask, fillerOrCorrection | T11 |
| in15 | text | 22 | Water the bathroom plants on Thursday, top up the hand soap in the bathroom, and clean the shower screen every two weeks | sameChoreOtherRoom | T7, R2 |
| in16 | voice | 31 | Uh, book the car in for a service on Monday, no wait, Tuesday, and, um, the gutters, clear the gutters before the rain comes, and bleed the radiators in the bedroom | weather, existingTask, fillerOrCorrection | T7 |
| in17 | voice | 29 | We're low on cat food, the kibble, so order more, and the dishwasher tablets, yeah, those too, and, um, sort through the kids room toy box in three days | existingTask, fillerOrCorrection | T14 |
| in18 | text | 32 | Pay the property tax this week, eat the leftover soup today before it goes off, wipe down the kitchen counters some evening, and the property tax, please don't let me forget it | critical, repeat | T10, T2, T15 |
| in19 | text | 21 | Every three months change the furnace filter, deep clean the garage floor on a dry day, and buy more olive oil | weather, deepClean, existingTask | R3 |
| in20 | voice | 34 | Um, okay, the bedroom windows, no, the living room windows, wash them this afternoon if it's sunny, and dust the bookshelves in the hallway, and, um, book the chimney sweep every year before winter | weather, fillerOrCorrection | T3, R4, T13 |

## Golden items (58)

| Input | Key | Expect | Kind | Room | Effort | Crit | Deep | Weather | Match groups |
|---|---|---|---|---|---|---|---|---|---|
| in01 | g01-ac | create | oneOff | none | normal | - | - | - | {ac, aircon, air, conditioner, conditioning} / {service, servicing, serviced, check, tune} |
| in01 | g01-pods | existing t-pods | restock | none | low | - | - | - | {dishwasher, dish} / {pods, tablets, capsules, detergent} |
| in01 | g01-balcony | create | oneOff | new "Balcony" | high | - | yes | yes | {balcony} |
| in02 | g02-electric | create | oneOff | none | low | yes | - | - | {electric, electricity, power, energy} / {bill, bills} |
| in02 | g02-dentist | existing t-dentist | oneOff | none | low | - | - | - | {dentist, dental} |
| in02 | g02-sink | create | oneOff | existing Bathroom | normal | - | - | - | {sink, drain, draining, plughole} |
| in03 | g03-milk | create | restock | none | low | - | - | - | {milk} |
| in03 | g03-bulb | create | oneOff | existing Hallway | low | - | - | - | {bulb, bulbs, lightbulb, light} |
| in04 | g04-gutters | existing t-gutters | oneOff | none | normal | - | - | yes | {gutters, gutter} |
| in04 | g04-mow | create | recurring | existing Garden | normal | - | - | yes | {mow, mowing, lawn, grass} |
| in04 | g04-trashbags | create | restock | none | low | - | - | - | {trash, garbage, bin, bins} / {bags, bag, liners, sacks} |
| in05 | g05-chicken | create | oneOff | existing Kitchen | normal | yes | - | - | {chicken} |
| in05 | g05-oven | existing t-oven | oneOff | existing Kitchen | high | - | yes | - | {oven} |
| in05 | g05-grout | create | oneOff | existing Bathroom | high | - | yes | - | {grout, tiles, tile} |
| in06 | g06-pods | existing t-pods | restock | none | low | - | - | - | {dishwasher, dish} / {pods, tablets, capsules, detergent} |
| in06 | g06-toiletpaper | create | restock | none | low | - | - | - | {toilet} / {paper, roll, rolls, tissue} |
| in06 | g06-washer | create | oneOff | existing Laundry room | low | - | - | - | {machine, washer} |
| in07 | g07-patio | create | recurring | new "Patio" | low | - | - | yes | {patio} |
| in07 | g07-car | existing t-car | oneOff | none | normal | - | - | yes | {car} / {wash, washing, clean, cleaning} |
| in07 | g07-shed | create | oneOff | new "Shed" (alt: garden shed) | high | - | - | - | {shed} / {sort, tidy, clear, declutter, organise, organize} |
| in08 | g08-water | create | oneOff | none | low | yes | - | - | {water} / {bill, bills} |
| in08 | g08-insurance | existing t-insurance | oneOff | none | normal | yes | - | - | {insurance} |
| in08 | g08-card | create | oneOff | none | low | - | - | - | {card, birthday} |
| in09 | g09-carpet | create | oneOff | existing Kids room | high | - | yes | - | {carpet, carpets, rug} |
| in09 | g09-sheets | existing t-sheets | recurring | existing Bedroom | normal | - | - | - | {sheets, sheet, bedding, linens} / {bedroom} |
| in09 | g09-vacuum | existing t-vacuum | recurring | existing Living room | normal | - | - | - | {vacuum, vacuuming, hoover, hoovering} / {living, lounge} |
| in10 | g10-plants | existing t-plants | recurring | existing Garden | low | - | - | - | {water, watering} / {plants, plant, pots, flowers} / {garden} |
| in10 | g10-windows | create | oneOff | none | normal | - | - | yes | {windows, window} |
| in10 | g10-heater | create | recurring | none | normal | - | - | - | {heater, boiler} |
| in11 | g11-smoke | existing t-smoke | recurring | none | low | yes | - | - | {smoke} / {alarm, alarms, detector, detectors} |
| in11 | g11-yogurt | create | oneOff | none | low | yes | - | - | {yogurt, yoghurt} |
| in11 | g11-coffee | create | restock | none | low | - | - | - | {coffee} |
| in12 | g12-trash | existing t-bins | recurring | none | low | - | - | - | {trash, garbage, bins, bin, rubbish} |
| in12 | g12-door | create | oneOff | existing Garage | normal | - | - | - | {door, doors, hinge, hinges} |
| in13 | g13-porch | create | recurring | new "Porch" (alt: front porch) | low | - | - | - | {porch} |
| in13 | g13-leaves | create | oneOff | existing Garden | normal | - | - | yes | {leaves, leaf} / {rake, raking, clear, collect, sweep} |
| in13 | g13-clothes | create | oneOff | none | low | - | - | yes | {clothes, laundry, washing} / {hang, line, clothesline, dry} |
| in14 | g14-fence | existing t-fence | oneOff | existing Garden | high | - | - | yes | {fence} |
| in14 | g14-fridge | create | oneOff | existing Kitchen | high | - | yes | - | {fridge, refrigerator} |
| in14 | g14-cleaner | create | oneOff | none | low | - | - | - | {cleaner, cleaners} / {window, windows} |
| in15 | g15-plants | create | oneOff | existing Bathroom | low | - | - | - | {water, watering} / {plants, plant, pots, flowers} / {bathroom} |
| in15 | g15-soap | create | restock | existing Bathroom | low | - | - | - | {soap, handwash} |
| in15 | g15-shower | create | recurring | existing Bathroom | normal | - | - | - | {shower} |
| in16 | g16-carservice | create | oneOff | none | low | - | - | - | {car} / {service, servicing, mechanic} |
| in16 | g16-gutters | existing t-gutters | oneOff | none | normal | - | - | yes | {gutters, gutter} |
| in16 | g16-radiators | create | oneOff | existing Bedroom | normal | - | - | - | {radiator, radiators} |
| in17 | g17-catfood | existing t-catfood | restock | none | low | - | - | - | {cat} / {food, kibble} |
| in17 | g17-pods | existing t-pods | restock | none | low | - | - | - | {dishwasher, dish} / {pods, tablets, capsules, detergent} |
| in17 | g17-toys | create | oneOff | existing Kids room | normal | - | - | - | {toy, toys} |
| in18 | g18-tax | create | oneOff | none | low | yes | - | - | {tax, taxes} |
| in18 | g18-soup | create | oneOff | none | low | yes | - | - | {soup, leftover, leftovers} |
| in18 | g18-counters | create | oneOff | existing Kitchen | low | - | - | - | {counter, counters, worktop, worktops} |
| in19 | g19-filter | existing t-filter | recurring | none | low | - | - | - | {filter, filters} / {furnace, heating, hvac} |
| in19 | g19-floor | create | oneOff | existing Garage | high | - | yes | yes | {floor, floors} / {garage} |
| in19 | g19-oil | create | restock | none | low | - | - | - | {oil} / {olive} |
| in20 | g20-windows | create | oneOff | existing Living room | normal | - | - | yes | {windows, window} / {living, lounge} |
| in20 | g20-books | create | oneOff | existing Hallway | low | - | - | - | {bookshelves, bookshelf, books, shelves} |
| in20 | g20-chimney | create | recurring | none | low | - | - | - | {chimney, flue} |

## Seeded household

Rooms: Kitchen (`kitchen`, `E7A1C0DE-0000-4000-8000-000000000101`), Bathroom (`bathroom`, `E7A1C0DE-0000-4000-8000-000000000102`), Living room (`living`, `E7A1C0DE-0000-4000-8000-000000000103`), Bedroom (`bedroom`, `E7A1C0DE-0000-4000-8000-000000000104`), Kids room (`kids`, `E7A1C0DE-0000-4000-8000-000000000105`), Hallway (`hallway`, `E7A1C0DE-0000-4000-8000-000000000106`), Garage (`garage`, `E7A1C0DE-0000-4000-8000-000000000107`), Garden (`garden`, `E7A1C0DE-0000-4000-8000-000000000108`), Laundry room (`laundry`, `E7A1C0DE-0000-4000-8000-000000000109`)

| Key | ID | Title | Kind | Room | Effort | Flags | Interval | State | Match groups |
|---|---|---|---|---|---|---|---|---|---|
| t-pods | `E7A1C0DE-0000-4000-8000-000000000201` | Buy dishwasher pods | restock | none | low | - | - | active | {dishwasher, dish} / {pods, tablets, capsules, detergent} |
| t-gutters | `E7A1C0DE-0000-4000-8000-000000000202` | Clear the gutters | oneOff | none | normal | weather | - | active | {gutters, gutter} |
| t-oven | `E7A1C0DE-0000-4000-8000-000000000203` | Deep clean the oven | oneOff | Kitchen | high | deepClean | - | maintenance | {oven} |
| t-insurance | `E7A1C0DE-0000-4000-8000-000000000204` | Renew the car insurance | oneOff | none | normal | critical | - | resurfaced | {insurance} |
| t-fence | `E7A1C0DE-0000-4000-8000-000000000205` | Paint the garden fence | oneOff | Garden | high | weather | - | deferred | {fence} |
| t-plants | `E7A1C0DE-0000-4000-8000-000000000206` | Water the garden plants | recurring | Garden | low | - | 3 | active | {water, watering} / {plants, plant, pots, flowers} / {garden} |
| t-bins | `E7A1C0DE-0000-4000-8000-000000000207` | Take the trash out | recurring | none | low | - | 7 | active | {trash, garbage, bins, bin, rubbish} |
| t-filter | `E7A1C0DE-0000-4000-8000-000000000208` | Change the furnace filter | recurring | none | low | - | 90 | active | {filter, filters} / {furnace, heating, hvac} |
| t-sheets | `E7A1C0DE-0000-4000-8000-000000000209` | Change the bedroom sheets | recurring | Bedroom | normal | - | 7 | active | {sheets, sheet, bedding, linens} / {bedroom} |
| t-milk | `E7A1C0DE-0000-4000-8000-000000000210` | Buy milk | restock | none | low | - | - | completed | {milk} |
| t-bulb | `E7A1C0DE-0000-4000-8000-000000000211` | Replace the hallway bulb | oneOff | Hallway | low | - | - | completed | {bulb, bulbs, lightbulb, light} |
| t-vacuum | `E7A1C0DE-0000-4000-8000-000000000212` | Vacuum the living room | recurring | Living room | normal | - | 7 | active | {vacuum, vacuuming, hoover, hoovering} / {living, lounge} |
| t-dentist | `E7A1C0DE-0000-4000-8000-000000000213` | Book the dentist appointment | oneOff | none | low | - | - | active | {dentist, dental} |
| t-smoke | `E7A1C0DE-0000-4000-8000-000000000214` | Test the smoke alarms | recurring | none | low | critical | 30 | active | {smoke} / {alarm, alarms, detector, detectors} |
| t-car | `E7A1C0DE-0000-4000-8000-000000000215` | Wash the car | oneOff | none | normal | weather | - | active | {car} / {wash, washing, clean, cleaning} |
| t-kettle | `E7A1C0DE-0000-4000-8000-000000000216` | Descale the kettle | oneOff | Kitchen | low | - | - | active | {kettle} / {descale, descaling, limescale} |
| t-shelves | `E7A1C0DE-0000-4000-8000-000000000217` | Sort the garage shelves | oneOff | Garage | normal | - | - | active | {shelves, shelf} / {garage} |
| t-towels | `E7A1C0DE-0000-4000-8000-000000000218` | Wash the bath towels | oneOff | Bathroom | normal | - | - | completed | {towels, towel} |
| t-catfood | `E7A1C0DE-0000-4000-8000-000000000219` | Buy cat food | restock | none | low | - | - | active | {cat} / {food, kibble} |

## Scorer evidence (Linux, Docker `swift:6.2-noble`, working tree = `1d1caa3` + these three fixture files)

Commands (from the repo root, run inside the container):
```bash
swift test --scratch-path /tmp/evalfix-ing --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors
swift build --scratch-path /tmp/evalfix-tools --package-path Tools/TendTools -Xswiftc -warnings-as-errors
tend-eval-score --profile ds1-gated --fixtures Fixtures/M2/eval \
  --expected-fixtures-sha256 bbbb…bbbb --results <hand-made results file> --log <file>.score.log
```
There is no manifest before the freeze. So the hand-made files carry the placeholder hash `b` × 64, and the same value
is passed as `--expected-fixtures-sha256`. Each hand-made file is canonical results v1, built from the golden set by my
generator. It is kept in `/tmp` and not committed: it would have to be rebuilt after the freeze, because the hash
changes.

| Run | Result | Key scorer-log lines |
|---|---|---|
| `TendIngestion` tests | exit 0 | `Test run with 534 tests in 64 suites passed` (the same count as the `1d1caa3` baseline; no test reads these fixtures yet) |
| `TendTools` build | exit 0 | warnings as errors |
| **Perfect file** (one draft per golden item, `sourcePhrase` = `referencePhrase`, each repeat draft `ofDraft`, each `existing` draft `ofExisting`), `ds1-gated` | **exit 0, PASS** | `N 58, extras 0, drafts 62, valid 62, introduced banned tokens 0, duplicates created 0, false merges 0`; segmentation, kind, room, effort, critical, deepClean and weatherDependent each 58 of 58 (required 56 / 56 / 53 / 50 / 56 / 56 / 56); best targets: 44 golden, 18 seeded, 0 none |
| **One planted false merge** (in15 `g15-plants` marked `ofExisting(t-plants)`, not committed) | exit 0, PASS (the gate allows ≤ 1) | `in15 … false merges: 1 (g15-plants)`; `check PASS: false merges <= 1 (AC-M2-17/26): 1` |
| **Two planted false merges** (also in04 `g04-trashbags` marked `ofExisting(t-bins)`) | **exit 1, FAIL** | `false merges: 1 (g04-trashbags)`, `false merges: 1 (g15-plants)`; `check FAIL: false merges <= 1 (AC-M2-17/26): 2` |
| **One duplicate created** (in05 oven draft left `none` and committed) | **exit 1, FAIL** | `in05 best target: draft 2 -> seeded t-oven`; `c(x): … seeded t-oven=1`; `check FAIL: 0 duplicates created (AC-M2-17/26): 1` |
| Wrong fixtures hash | exit 2 | `file rejected: the fixtures hash does not match` |
| Self-test file against its own fixtures (`info`) | exit 0 | unchanged by this work |

SHA-256 of the hand-made files (kept in `/tmp/evalfix-results/final3/`, not evidence for any device AC, CLAUDE.md §5):

- perfect `255ecc1176e8dbeb8efcd80832be8ed128cf84253e2b20539e61a3cd0f80d720`
- one false merge `7078fd290ae60e4a7926809136f233ee79a100f46e50abb78b344a89f9782423`
- two false merges `f48070dae41dd3be7180fa4cd38840d158156ab46f08ce9f6eb2d38ccddc245b`
- duplicate created `50d22586b137d3b85f98bc6b68cf9a5670b68aca2506760c843270fd2bc76073`

## Review of the WI-M2-10 golden requests and key-path lists (plan "golden requests … reviewed by the Tester")

Scope: `Fixtures/M2/payload/golden/*` (9 bodies, 9 heads), `allowed-key-paths-{openai,anthropic,gemini}.json`, read
against brief AC-M2-20 and Definitions "Cloud request", PO WI-M2-10 rulings 3, 4 and 7, PO WI-M2-11 rulings 1–3, and
`l1-model-check-2026-11-23.md`.

| ID | Severity | Finding | Owner | Due |
|---|---|---|---|---|
| GR-1 | Major, **CLOSED (verified at PR #32 `02f944e`)** | The fixed instructions (`CloudOutputSchema.swift:41`, in all 9 golden bodies) say *"isCritical: true only for safety or health."* The PRD (FR-B2 "Critical items (e.g., paying a bill, expiring food)") and rubric Q3 ("critical (bill, expiring food)") define critical differently. Following the instructions, a cloud model would mark the eval's bills (in02, 08, 18) and expiring food (in05, 11, 18) as not critical. 8 golden items are critical, and the critical threshold is 56 of 58, so AC-M2-26 would fail because of the instruction, not because of the model. The on-device instructions (`TendAI`, not written yet) must use the same definition. | PO (meaning, EC-Q2), then Developer (instructions, regenerate the 9 golden bodies; key paths unchanged) | Before the AC-M2-14 freeze |
| | | **PO ruling 3 (2026-11-24):** my reading is confirmed (critical = waiting has a real cost: a bill, tax or other payment, a renewal with a date, food that will expire, a home safety check; routine servicing and appointments are not). The exact replacement line for `CloudOutputSchema.swift:41` is in `po-m2-wi16.md` ruling 3, and the on-device `@Guide` uses the same sentence. The Developer is regenerating the bodies on `m2/cloud-instructions`. **Stays open (Major)** until I verify the regenerated golden bodies: each of the 9 holds the ruling 3, 4, 5 and 9 lines word for word, the old line is gone, the key-path lists are unchanged, N-3 and banned-token checks pass. Only I lift GR-1. | Developer, then Tester | Before the freeze |
| | | **Verified 2026-11-24 at PR #32 head `02f944e` (V1–V4, V7 below): CLOSED.** All 9 bodies carry one identical instruction text holding the ruling 3 critical line, the ruling 9 deep-clean and weather lines, each word for word on its own line; "safety or health" is gone; outside the instruction text (and the OpenAI system shape, GR-5) every body is unchanged; the key-path lists change only by GR-3 and GR-5. The on-device `@Guide` half of ruling 3 is not in this PR (TendAI, WI-M2-M2): tracked as GR-9. | — | — |
| GR-2 | Minor, **CLOSED (verified at PR #32 `02f944e`)** | The room instruction ("a name from rooms when the chore belongs there") asks for inference, while the golden set expects a room only when the person names it (EC-Q1). The fixtures avoid most conflicts by always naming the room of a located chore. Remaining risk: "hang the clothes out on the line" (golden `none`; the model might pick Laundry room) and restocks (golden `none`; the model might pick Kitchen). **PO ruling 4:** the room instruction changes to state the "no room" cases (exact line in `po-m2-wi16.md` ruling 4; the same meaning in the on-device `@Guide`). Closes when I verify the regenerated bodies, together with GR-1. **Verified at PR #32 head `02f944e`: CLOSED.** The ruling 4 room line and the ruling 5 effort line are word for word in all 9 bodies; the old room and effort wording is gone (V1, V2). `@Guide` parity: GR-9. | PO (EC-Q1), then Developer | Before the freeze |
| GR-3 | Minor, **CLOSED (verified at PR #32 `02f944e`)** | The allowed lists' `headers` have only `auth`, `Content-Type` (and `anthropic-version`) and the transport-set `Content-Length` and `Host`. PO WI-M2-10 ruling 4 requires `User-Agent: Tend` and `Accept-Language: en-US` as fixed, and `Accept`, `Accept-Encoding` and `Connection` listed as transport-set. These are the WI-M2-M4 (Mac) deliverables. The golden heads are correct as builder output if the lists name these headers. PO ruling 10: noted, before the freeze. **Verified at `02f944e` (V5): CLOSED.** All 9 heads end with `User-Agent: Tend` and `Accept-Language: en-US` after the auth and provider headers (order accepted, PO F1); all 3 lists name them `fixed` and name exactly `Content-Length`, `Host`, `Accept`, `Accept-Encoding`, `Connection` as `derivedByTransport`; no other header was added or removed. Per F1 the device checks compare header names and values as a set (DS-2 S6 to say so, GR-10). | Developer (WI-M2-M4) | Before the freeze |
| GR-4 | Minor, **Gemini PASS; OpenAI and Anthropic DEFERRED by owner decision** (2026-11-25) | **L2a outcome (owner, 2026-11-25, `owner-decisions.md` "L2a outcome"; results `l2a-results-2026-11-25/`):** Gemini HTTP 200, `text/event-stream`, served model `gemini-3.5-flash-lite`; I re-read `gemini.sse`: the concatenated text parses as one JSON object (`items`, the results field set, `null` in the enum-typed `time` members accepted), `finishReason` `STOP`, no thoughts token count; so `responseJsonSchema`, `thinkingLevel` and `null` in `enum` are accepted: no golden change. OpenAI HTTP 429 `insufficient_quota` and Anthropic HTTP 400 credit balance: billing errors, the request was **not** verified (not a pass, not a fail). The owner froze now; OpenAI and Anthropic L2a must pass (and, if a body is refused, the goldens change under a PO decision) before their DS-2 runs count (`acceptance.md`). Evidence in the repo: the Gemini reply stream is committed as `Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse` (PR #37); the procedure and pass rule are in `docs/milestones/M2/l2a-real-call-check.md`; `.status` files are not committed (Anthropic's holds account identifiers). Open (m3 of review PR #36): a `DECISIONS.md` entry for the owner's decision, in a later governance PR. Original finding: Gemini: `generationConfig.responseJsonSchema` and `thinkingConfig.thinkingLevel` on `streamGenerateContent`, and `null` inside `enum` (daypart, repeatUnit, season, weekday), are not confirmed by Google's pages (L1b note, 2026-11-24). They are in the golden bytes. L2a must show a schema-valid stream with no 4xx before the freeze; if it fails, the goldens change under a PO decision. PO ruling 10: L2a runs on the bodies regenerated by rulings 3, 4, 5 and 9. | Owner (L2a), Developer | WI-M2-16 DoR |
| GR-5 | Minor, **CLOSED (verified at PR #32 `02f944e`)** | OpenAI: `$.messages[].content` is both a string leaf (the system message) and the parent of `$.messages[].content[].text` (the user message). On device, `ds2-gated` checks only that key paths are a subset of the list. A request whose user content became a plain string would show only `$.messages[].content`, which is allowed, so the device check cannot see the change. The Linux structural check (AC-M2-20 (b), concrete indices) does catch it. Suggest sending the system message as a text-part array too, or recording the value type per path with the element counts of PO WI-M2-11 ruling 1. PO ruling 10: noted, before the freeze. **Verified at `02f944e` (V6): CLOSED** under PO F2. The OpenAI system message is `content: [{"text": <instructions>, "type": "text"}]` (one text part) in all 3 OpenAI bodies; the OpenAI list lost `$.messages[].content` and gained no path; no list path is both a leaf and a container. My mutants: the user content or the system content turned into a plain string each yields `$.messages[].content`, which is now outside the list. Accepted residual (F2): `$.messages[].content[].text` is shared by the instructions and the user content; the Linux concrete-index check pins the instructions. Conditions that reopen it: L2a rejects the array system content (revert `12bd68c`, option B; re-verify). Per-array element counts (PO WI-M2-11 ruling 1) stay with the Planner. | Developer (technical choice) | With the WI-M2-11 ruling 1 ticket |
| GR-6 | pass | **Shortlists.** I derived the shortlists by hand and they match the golden bodies. G2: water balcony plants (K3), dishwasher pods (K2, R1), kitchen bin (K2, R1), oven (K0, R1); "buy…" < "take…"; completed tasks are excluded. G3: 13 eligible tasks cut to 10, in rank order K2 (fold, wash), then K1 + R1 (air, dry, replace, sort), then K1 + R0 (bleach, buy "soft", count, hang). Titles are trimmed with the inner tab kept, and room names are sent as written (Q19). | — | — |
| GR-7 | pass | **Fixed members** equal PO WI-M2-10 ruling 7: `gpt-6-luna`, `reasoning_effort: "none"`, `store: false`, `stream_options.include_usage`, `max_completion_tokens: 4096`, no `temperature`; `claude-haiku-4-5-20251001`, `anthropic-version: 2023-06-01`, `temperature: 0`, forced `tool_choice`, no `thinking`; `gemini-3.5-flash-lite`, `thinkingLevel: "minimal"`, `maxOutputTokens: 4096`, no `temperature`, no `thinkingBudget`, `propertyOrdering` or `nullable`. The auth header holds only the fake key. | — | — |
| GR-8 | pass (re-checked at `02f944e`, V3) | **N-3.** No decimal digit run in any of the 18 golden files or 3 lists contains 600…729. The instructions contain no banned token. The key paths use the results-file form (PO WI-M2-15 ruling 2). | — | — |
| GR-9 | Minor, **OPEN** (new, v3) | PO ruling 3 (and 4, 5, 9): the on-device `@Guide` descriptions must carry the same meanings, with the **same sentence** for `isCritical` (one shared constant or a string-comparison test). PR #32 changes only the cloud instructions; the Developer ticketed parity to WI-M2-M2 (dev-notes, WI-M2-16 Developer part, follow-ups). Not a ruling 1 freeze condition, but P-1 and P-3 must be asked the same thing before DS-1 results count for AC-M2-15. I verify at WI-M2-M2 review: the test comparing the strings, and the `room`, `effort`, `isWeatherDependent` guides against rulings 4, 5, 9. | Developer (WI-M2-M2) | Before DS-1 |
| GR-10 | Minor, **CLOSED in v3** (new, my own doc) | After GR-3 the app sends `User-Agent: Tend` and `Accept-Language: en-US`, but my DS-2 Part A served-model `curl` lines (`acceptance.md`) sent only auth, provider headers and `Content-Type`, so curl added its own `User-Agent`. Fixed in v3: all three `curl` lines add `-H 'User-Agent: Tend' -H 'Accept-Language: en-US'`, so the Mac check sends the same fixed headers as the app. Also recorded for the WI-M2-M4 / AC-M2-22 evidence I will read: per PO F1, header names and values are compared **as a set** (a transport reorder is not a defect; a changed value or an extra header is). | Acceptance Tester | Done |

## Verification of the regenerated golden requests (PR #32, `m2/cloud-instructions`, head `02f944e`, 2026-11-24)

Read-only: files taken with `git archive origin/m2/cloud-instructions` into my scratch directory; compared with the same
files at `1d1caa3` (PR #31 merge, the bodies I reviewed in v1). Checks are my own Python scripts (`python3 -I`), not the
Developer's tests; then I re-ran the Developer's suite at the same commit.

| # | Check | Result |
|---|---|---|
| V1 | Each of the 9 bodies' instruction text (OpenAI `messages[0].content[0].text`, Anthropic `system`, Gemini `systemInstruction.parts[0].text`) contains, as whole lines, exactly the PO sentences: room (ruling 4), effort (ruling 5), isCritical (ruling 3), isDeepClean and isWeatherDependent (ruling 9). | 9/9, all 5 lines each. One distinct instruction text across the 9 bodies. |
| V2 | Old wording gone: "safety or health", "when the chore belongs there", `"low", "normal" or "high"`. | 0 occurrences in 9/9. |
| V3 | N-3: no decimal digit run in any of the 18 golden files, 3 lists or README has a substring whose value is 600…729. Banned tokens (overdue, late, missed, failed, behind, penalty, debt, streak, lateness) in the instructions. | 0 hits; 0 banned tokens. The new lines add no digit (the instruction's only digits are the unchanged "1 to 12", "2 weeks", "from 1"). |
| V4 | Each body at `02f944e` equals its `1d1caa3` version once the instruction string is masked (and, for OpenAI, the old string system content is wrapped as one text part). Bodies stay canonical (sorted keys, compact). | 9/9 equal; 9/9 canonical. So the user content (capture, rooms, shortlist) is unchanged. |
| V5 | Heads and header lists (GR-3). | 9/9 heads: auth, provider headers, `User-Agent: Tend`, `Accept-Language: en-US`; the only change from `1d1caa3` is these 2 lines. 3/3 lists: +2 `fixed`, +3 `derivedByTransport` (`Accept`, `Accept-Encoding`, `Connection`), nothing removed. |
| V6 | OpenAI list and system shape (GR-5). | OpenAI list: removed `$.messages[].content` (fixed), added nothing; Anthropic and Gemini key paths unchanged. Every golden body's key paths equal its list exactly (no extra, no unused). Mutants (user or system content as a plain string) produce `$.messages[].content`, outside the list. |
| V7 | G2/G3 shortlists against my GR-6 derivation. | Unchanged and still match: G2 = water balcony plants, buy dishwasher pods, take out the kitchen bin, clean the oven; G3 = fold, wash (tab kept), air, dry, replace, sort, bleach, buy "soft", count, hang; rooms as written. User content byte-identical across the 3 providers. |
| V8 | Re-run at `02f944e` (Linux, Swift 6.2.4, `swift test --package-path Packages/TendIngestion` on the archived tree). | `Test run with 538 tests in 64 suites passed`. Includes "PO WI-M2-16 rulings 3, 4, 5, 9 (GR-1, GR-2 …) … the PO's exact sentences", the GR-3 header-list test, both GR-5 tests and "AC-M2-20 golden bytes: 3 households × 3 providers … exactly". |

Result: **GR-1, GR-2, GR-3, GR-5 CLOSED at `02f944e`.** If PR #32's golden files or lists change before merge (for
example the F2 revert after L2a), the closure lapses and I re-verify. GR-4 (L2a) stays open and must run on these bodies.

## Open questions for the PO: all answered (`po-m2-wi16.md`, 2026-11-24; EC-Q8 in v5)

Every reading below was confirmed; no fixture data changes. The PO's watch items (unnamed-room inference, synonym-only
duplicates) go to the M3 dev-set and are not scored in M2.

| ID | Question | Reading applied (most faithful to the PRD, as I read it) | Answer |
|---|---|---|---|
| EC-Q1 | When is a room expected? PRD FR-A1 says the AI "infers the room". | `existing(room)` only when the person says the room's name; `none` for chores with no place; `new` for a named place that is not in the household. Every located chore in the inputs names its room, so naming and inference agree, except for the risks in GR-2. | **ANSWERED, ruling 2:** confirmed and made precise (room = where the chore is done; buying, paying, booking and errands have none unless a room is named). Watch item for M3: unnamed-room inference. |
| EC-Q2 | What is "critical"? | PRD FR-B2 and Q3: a bill or obligation with a date (electric, water and property-tax bills, the insurance renewal) and expiring food (chicken, yogurt, soup) are critical, and so is a safety check (smoke alarms). A routine appointment (the dentist) is not. This needs GR-1 fixed. | **ANSWERED, ruling 3:** confirmed (critical = waiting has a real cost). The instruction text changes (GR-1, still open until I verify the regenerated bodies). |
| EC-Q3 | The task names "P1–P7 composition"; the brief's composition is rubric Q3, and P1–P7 are the plan's Q6 time-phrase rows. | Both are covered: Q3 is the binding table above (C1–C12), and P1–P7 coverage is information only. Windows are not scored, and no change to the scoring rules is proposed. | **ANSWERED, ruling 6:** confirmed. Q3 (C1–C12) is binding; P1–P7 coverage is information only. |
| EC-Q4 | Effort convention. | `low` = a quick errand or touch-up; `normal` = default; `high` = a deep clean or a job the person calls big (v1 wording; v2 rule 9 says "a long job", ruling 5). | **ANSWERED, ruling 5:** confirmed, with the wording "a long job" (rule 9 updated) and stated in the instructions. |
| EC-Q5 | Should the eval include an existing-task mention with **no** shared keyword (for example "dish tablets" for "Buy dishwasher pods")? | Excluded. Under Q12 = yes no cloud model is sent that title, and the word-match floor cannot match it, so the cloud run's 0-duplicate gate (AC-M2-26) could never pass. If the PO wants it, it needs a non-gated watch item, which is a scoring-rule change, so I do not propose it. | **ANSWERED, ruling 7:** confirmed, excluded from the gated set. Watch item for M3: synonym-only duplicates. |
| EC-Q6 | What is "a repeat inside the input"? | The same chore said twice in one input. It is one golden item; the second draft should be `ofDraft` (it is not primary, so it is not an extra). | **ANSWERED, ruling 8:** confirmed. A second committed draft is a duplicate created (c(g) − 1). |
| EC-Q7 | What is "a weather condition"? | The person states one for that chore (rain, dry, sunny, "before the rain comes"). The item is `isWeatherDependent`. | **ANSWERED, ruling 9:** confirmed (the person ties the chore to the weather; never inferred in M2) and stated in the instructions. |
| EC-Q8 | Review WI-M2-16 F2 (Minor): effort of `g16-carservice` ("book the car in for a service", in16). It is `normal`; the 3 other "book" items are `low`, and rule 9 lists "book" as `low`. Relabel it `low`? | **Relabel to `low`.** The reviewer's other reading ("scored on the service") is not consistent with my own labels: "book the dentist for the kids" (`g02-dentist`) is also an appointment the person attends, and it is `low`. PO ruling 4 puts booking with buying, paying and errands, and the instruction the model reads (ruling 5) says "low for a quick errand", so a model that follows it says `low` and would lose this item to my label. Items without "book" (`g01-ac`, `g10-heater`) stay `normal`. Impact: 1 of 58 effort labels (gate 50 of 58); a perfect file stays 58/58 once relabelled; composition C1–C12 unchanged. It changes `golden.json` and its approved hash `882c2906…` (pinned in `EvalFreezeTests.swift`), so under ruling 1 I do **not** change it until the PO re-approves; then I relabel, the Developer updates the pin and `MANIFEST.sha256`, and only then the freeze. | **ANSWERED (PO, `po-m2-wi16.md` "EC-Q8", 2026-11-24): relabel approved; rule 9 confirmed.** Done in v5 (one-value diff and new hash in "PO approval"). EC-Q8 and review WI-M2-16 F2 **CLOSED**. |

## Still open in WI-M2-16
- The Developer's Linux composition check on these fixtures, including `referencePhrase` best-target and version-4
  UUID checks, and `MANIFEST.sha256` (Developer).
- PR #32 merges with the golden files verified at `02f944e` (GR-1, GR-2, GR-3, GR-5 closed there). L2a on these
  bodies (owner, GR-4), including the OpenAI array system content (F2). GR-9 (`@Guide` parity, WI-M2-M2, before
  DS-1) does not block the freeze. GR-10 (my DS-2 Part A headers) is fixed in v3.
- EC-Q8 done (v5). The Developer updates the `golden.json` pin in `EvalFreezeTests.swift` to `0e819a89…4b771` and
  writes `MANIFEST.sha256` (the pin test fails until then; expected).
- The freeze itself: no change after it without a PO decision in `DECISIONS.md`.

Done since v1:
- PO approval of the composition and answers to EC-Q1…Q7 (`po-m2-wi16.md`; see "PO approval" and the table above).
- My independent re-score of `results-selftest-1`: same scores as the committed scorer log
  (`docs/milestones/M2/acceptance.md`, "AC-M2-14 independent re-score").
- DS-1 and DS-2 drafted in `docs/milestones/M2/acceptance.md`. AC-M2-11 subset: in01 (text), in02 and in10 (voice) (v3: corrected from a slip "in12"; `acceptance.md` always said in10). Both subsets fixed by PO F3.
  AC-M2-25 subset: in08 and in16 (voice). Every device AC stays AWAITING-DEVICE.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Every input is a free spoken or typed brain-dump (FR-A1). Nothing is form-shaped. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | pass | No banned token in any fixture file (rule 3). The inputs use calm wording ("please don't let me forget it"), with no lateness or shaming phrasing. Any banned token in a draft is therefore "introduced" and fails the gate. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On device first | pass | The fixtures are the same for the on-device (DS-1) and cloud (DS-2) runs. Voice inputs are read live and no audio is stored (AC-M2-15). |
| P-2 No data leaves the device | pass | Invented household data only: no names, addresses or IDs from real people. Nothing is sent by this work. |
| P-3 Cloud AI opt-in, minimised | pass; GR-1, 2, 3, 5 closed at `02f944e`; GR-4 Gemini PASS, OpenAI/Anthropic deferred (owner) | During DS-2 a request carries one input, the 9 room names and at most 10 shortlist titles (≤ 6 eligible per input), all invented. GR-3 and GR-5 strengthen the minimisation proof. |
| P-4 Media not persisted | pass | No audio or images in the fixtures. |

## Handoff log
| Date | From | To | Result | Notes |
|---|---|---|---|---|
| 2026-11-24 | Orchestrator | Acceptance Tester | accepted | WI-M2-16 (AC-M2-14), Tester part: fixtures, a scorer proof, the golden-request review and this composition table. |
| 2026-11-24 | Acceptance Tester | Product Owner (via Orchestrator) | sent for approval | Composition C1–C12 met (N = 58). EC-Q1…Q7 to answer. GR-1 (Major) needs a PO meaning ruling, then a Developer fix, before the freeze. |
| 2026-11-24 | Acceptance Tester | Developer (via Orchestrator) | sent | Composition check and `MANIFEST.sha256` (after PO approval); GR-1 after the PO ruling; GR-3 (WI-M2-M4); GR-5 (with WI-M2-11 ruling 1). Not frozen. |
| 2026-11-24 | Product Owner | Acceptance Tester (via Orchestrator) | answered | `po-m2-wi16.md`: composition approved with conditions at `95491ed`; EC-Q1…Q7 confirmed (rulings 2, 3, 5, 6, 7, 8, 9); GR-1 and GR-2 ruled with exact instruction lines (rulings 3, 4); GR-3, 4, 5 noted (ruling 10). |
| 2026-11-24 | Acceptance Tester | Developer, Product Owner (via Orchestrator) | sent | v2 doc edits done (rule 9 wording, answers, approval record); fixture data unchanged. GR-1 stays open (Major) and GR-2 is answered, until I verify the bodies regenerated on `m2/cloud-instructions`. |
| 2026-11-24 | Acceptance Tester | Orchestrator → PO, Developer, owner | sent | v3: regenerated golden requests verified on PR #32 head `02f944e` (V1–V8): GR-1, GR-2, GR-3, GR-5 CLOSED there. New: GR-9 (Minor, open, Developer WI-M2-M2, `@Guide` parity before DS-1), GR-10 (Minor, my DS-2 Part A `curl` headers; fixed in v3); slip in12 → in10 corrected. GR-4 (L2a), composition check, manifest and freeze still open. |
| 2026-11-24 | Acceptance Tester | PO, Reviewer, Developer (via Orchestrator) | sent | v4 (review WI-M2-16 round 1): F2 answered as EC-Q8, proposal relabel `g16-carservice` effort `normal` → `low` (rule 9 now states that the person's verb decides); no data change until the PO re-approves (ruling 1, hash pin). F1 and N4 fixed in `acceptance.md`. Still not frozen. |
| 2026-11-24 | Product Owner | Acceptance Tester (via Orchestrator) | answered | EC-Q8: relabel approved, composition re-approved for the one-value change. |
| 2026-11-24 | Acceptance Tester | Developer, Reviewer, PO (via Orchestrator) | sent | v5: `g16-carservice` effort `low`; one-value diff shown; `golden.json` SHA-256 `0e819a89fcb65adb0a764d296f1d0dc8f30275cfe074495a4fe9c793a0f4b771`; inputs and household unchanged. EC-Q8 and F2 closed. Developer: pin and manifest. Not frozen. |
| 2026-11-25 | Orchestrator | Acceptance Tester | accepted | Freeze after the owner's L2a outcome (Gemini PASS; OpenAI, Anthropic deferred). |
| 2026-11-25 | Acceptance Tester | Orchestrator → PO, Documenter, Developer, Reviewer | sent | v6: **frozen**. `MANIFEST.sha256` written by the documented command; `EvalFreeze.declaredFrozen = true`; GR-4 Gemini PASS, OpenAI/Anthropic L2a deferred by owner decision and a precondition of their DS-2 runs (`acceptance.md`). No fixture data changed. |
| 2026-11-25 | Acceptance Tester | Orchestrator → Reviewer | sent | v6 after review PR #36 round 1: header date; GR-4 row points at the repo evidence (PR #37 stream, `l2a-real-call-check.md`); m3 (DECISIONS.md entry) noted open. |
| 2026-11-28 | Acceptance Tester | Orchestrator → PO, Documenter, Developer | sent | D-059 freeze re-check at e014fab PASS (F1–F3 closed); schema 09616132…, fixtures hash 7fdc056e…; data files unchanged. |
| 2026-11-28 | Product Documenter | Orchestrator | sent | v7 text applied from `tester-freeze-recheck-d059.md` R2-7 (Status, Revisions, this row). The fixtures hash holds on `main` only after `m2/eval-harness` (`e014fab`) merges. |
