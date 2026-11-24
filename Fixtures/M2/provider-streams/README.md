# Provider stream fixtures (AC-M2-24, T-19)

Response bodies of the three cloud providers' streaming APIs. They are read by `ProviderStreamReader`
(`Packages/TendIngestion/Sources/TendIngestion/CloudOutput/`) in the Linux tests (`ProviderStreamFixtureTests`).
The cloud adapters read them end to end through a mock transport on the owner-run Mac (WI-M2-M6).

Every fixture holds **response bodies only**: no request, no headers, no key, no household data. Each one was written for
the brief's Outcome sample sentence: "The AC needs servicing before summer, we're almost out of dishwasher pods, and
let's deep clean the balcony this weekend if it doesn't rain".

## Synthetic (WI-M2-13)

`synthetic/<provider>/<name>.sse`, 11 per provider, 33 in total. Each one follows that provider's documented streaming
format:

- **openai:** Chat Completions with `stream: true` and `stream_options.include_usage`. Each event is a `data:` line
  holding a `chat.completion.chunk` with `"usage":null`. After the `finish_reason` chunk comes the usage chunk
  (`"choices":[]`, usage with `completion_tokens_details.reasoning_tokens`), and the body ends with `data: [DONE]`.
- **anthropic:** Messages with `stream: true` and one forced tool. The events are named, and the tool input arrives as
  `input_json_delta`.
- **gemini:** `streamGenerateContent?alt=sse` with `responseJsonSchema` and `thinkingLevel: "minimal"`. Each event is a
  `data:` line with CRLF line ends, and the body has no end sentinel. `usageMetadata` has `thoughtsTokenCount`, and the
  first part of `happy-path` and `finished-output-no-end` carries a `thoughtSignature`. The output members are in sorted
  key order, as Gemini writes them for a `responseJsonSchema` request.

The shapes follow the request of PO WI-M2-10 ruling 7, and a length stop is the fixed output cap of ruling 3. The model
IDs in the bodies are the served models of ruling 7: `gpt-6-luna`, `claude-haiku-4-5-20251001` and
`gemini-3.5-flash-lite`. The formats were written from the providers' documentation and are not verified against a
live stream (WI-M2-13 K9); the recorded fixtures of WI-M2-M6 check them. The fixtures were written by a one-off generator script that is not
kept in the repo. The test table in `ProviderStreamFixtureTests` is the specification: it states the exact result of
each fixture, and a test fails if a file is added or missing.

| Name | What it covers | Result through `DraftPipeline` |
|---|---|---|
| `happy-path` | 3 items in many small pieces. Item 1 has no room (`"room":""`), so it completes by rule (a) before item 2 starts. Item 3's title arrives last. | `completed`; 3 drafts |
| `out-of-order-fields` | Every item's members in another order (item 3's title still last), an unknown root key, and noise per provider. OpenAI: CRLF, `: keep-alive` comments, empty and `null` content, reordered chunk keys, a usage chunk split over two `data:` lines. Anthropic: a text block before the tool block, pings, an unknown event type. Gemini: two text parts in one chunk and a `thought` part. | `completed`; the same 3 drafts |
| `truncated-after-first-draft` | The body stops inside item 2, with no provider end (OpenAI and Gemini also stop inside an event) | `interrupted(outputCutShort)`; 1 draft; the in-progress item is discarded |
| `length-limit-after-first-draft` | The provider's length limit inside item 2 (`length`, `max_tokens`, `MAX_TOKENS`) | `interrupted(outputCutShort)`; 1 draft |
| `invalid-json-after-first-draft` | A bare word (`"kind":restock`) in item 2's output JSON | `interrupted(unreadableOutput)`; 1 draft |
| `invalid-event-before-draft` | An event whose data is not one JSON object, before any output | `noModel(unreadableOutput)` with the plain-note offer |
| `schema-violating-fields` | `null`, wrong types, a non-object item, an unknown nested key, a fractional interval, `1e400` | `completed`; 2 drafts after Q5 repairs; 1 `itemSkipped(noTitle)` |
| `unknown-enum-values` | `"chore"`, `"Restock"`, `"medium"`, `"LOW"`, `"someday"`, `"dusk"`, `"monsoon"` (exact match only) | `completed`; 2 drafts with the Q5 defaults |
| `refusal-before-draft` | OpenAI: `delta.refusal` text. Anthropic: `stop_reason` `refusal`. Gemini: `promptFeedback.blockReason`. | `noModel(refusal)` with the plain-note offer |
| `provider-error-after-first-draft` | An in-stream error after item 1 (`server_error`, `overloaded_error`, code 503) | `interrupted(serviceUnavailable)`; 1 draft |
| `finished-output-no-end` | The whole output JSON is finished, but the body ends without the provider's normal end (OpenAI: no `finish_reason` and no `[DONE]`; Anthropic: `content_block_stop` but no `message_delta` or `message_stop`; Gemini: no `finishReason`). A cloud stream counts as truncated without that end (PO 2026-11-24, WI-M2-13 K2). | `interrupted(outputCutShort)`; 3 drafts |

## Recorded (WI-M2-M6)

`recorded/<provider>/`, at least one per provider. The owner records them on the owner-run Mac with the sample
sentence, and saves the response stream only. There are none yet.
