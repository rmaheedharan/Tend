<!-- Copied 2026-11-25 by the Acceptance Tester from the owner's procedure (WI-M2-16, GR-4, review PR #36 m2) so it can be
run from the repository. Steps 1-5 are unchanged; "Pass rule and record" is added. -->

# Real call check (L2a): one test call to each cloud AI

**Why:** before we lock the eval test set, we must see that each AI service accepts our exact request.
**Time:** about 10 minutes. **Cost:** one tiny request per service (a few cents at most).
**Privacy:** the request holds only one fixed sample sentence and no household data. Your key is typed at a hidden prompt. It is not saved, not shown on screen and not kept in shell history.

You need: your Mac, the Terminal app, and the API keys you want to test (OpenAI, Anthropic, Gemini). If you skip a provider, tell me.

## Step 1: get the code
Open Terminal and paste:
```bash
cd ~ && rm -rf tend-l2a && git clone --depth 1 https://github.com/rmaheedharan/Tend.git tend-l2a && cd tend-l2a && mkdir -p ~/tend-l2a-out
```
If it asks you to sign in, use your GitHub account (the repository may be private).

## Step 2: OpenAI
```bash
read -rs TEND_KEY   # paste your OpenAI key, then press Return (nothing is shown)
curl -sS -N -D ~/tend-l2a-out/openai.status https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $TEND_KEY" -H 'Content-Type: application/json' \
  -H 'User-Agent: Tend' -H 'Accept-Language: en-US' \
  --data-binary @Fixtures/M2/payload/golden/g1-outcome-empty-openai.body.json \
  > ~/tend-l2a-out/openai.sse; unset TEND_KEY
```

## Step 3: Anthropic
```bash
read -rs TEND_KEY   # paste your Anthropic key, then press Return
curl -sS -N -D ~/tend-l2a-out/anthropic.status https://api.anthropic.com/v1/messages \
  -H "x-api-key: $TEND_KEY" -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' \
  -H 'User-Agent: Tend' -H 'Accept-Language: en-US' \
  --data-binary @Fixtures/M2/payload/golden/g1-outcome-empty-anthropic.body.json \
  > ~/tend-l2a-out/anthropic.sse; unset TEND_KEY
```

## Step 4: Gemini
```bash
read -rs TEND_KEY   # paste your Gemini key, then press Return
curl -sS -N -D ~/tend-l2a-out/gemini.status 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:streamGenerateContent?alt=sse' \
  -H "x-goog-api-key: $TEND_KEY" -H 'Content-Type: application/json' \
  -H 'User-Agent: Tend' -H 'Accept-Language: en-US' \
  --data-binary @Fixtures/M2/payload/golden/g1-outcome-empty-gemini.body.json \
  > ~/tend-l2a-out/gemini.sse; unset TEND_KEY
```

## Step 5: check no key leaked, then hand over the files
```bash
grep -l -i -E 'sk-|x-api-key|authorization|AIza' ~/tend-l2a-out/* || echo "OK: no key in the files"
open ~/tend-l2a-out
```
If it says **OK**, give the files to the Acceptance Tester (through the Orchestrator). If it lists a file name, do not send that file; say so instead.

The `.status` files hold only the reply headers from the service. The `.sse` files hold only the reply. None of them hold your key.

## Pass rule and record (Acceptance Tester; DS-2 precondition P11 in `acceptance.md`)
- **PASS** for a provider: its `.status` is `HTTP/2 200` with `content-type: text/event-stream`, and the joined text of
  the stream is one JSON object valid against the output schema in that provider's
  `Fixtures/M2/payload/golden/g1-outcome-empty-<provider>.body.json`, with a normal finish (no 4xx, no refusal).
- **Not verified** (neither pass nor fail): a billing or quota error (for example HTTP 429 `insufficient_quota`, HTTP
  400 "credit balance is too low"). Run the step again after adding credit.
- **Refused** (4xx naming a request field): stop. The golden bodies change only under a PO decision in
  `docs/governance/DECISIONS.md` (PO ruling 10, GR-4).
- The Tester records each provider's result in `acceptance.md` (DS-2 "What to record", L2a rows) and commits the
  reply stream as evidence under `Fixtures/M2/provider-streams/<provider>/`. `.status` files are not committed when
  they carry account identifiers (Anthropic's holds `anthropic-organization-id` and `anthropic-workspace-id`).
- Results so far: Gemini **PASS** 2026-11-25 (evidence `Fixtures/M2/provider-streams/gemini/recorded-outcome-sample.sse`,
  committed in PR #37). OpenAI and Anthropic **not verified** 2026-11-25 (billing errors); deferred by the owner's
  decision until credit is added.
