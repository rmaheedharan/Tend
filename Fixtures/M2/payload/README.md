# M2 payload fixtures (WI-M2-10; AC-M2-20, AC-M2-26)

Written by the payload builder and checked byte for byte by
`Packages/TendIngestion/Tests/TendIngestionTests/PayloadGoldenTests.swift`. The Tester reviews them before the AC-M2-14
freeze (WI-M2-16). Every file is exact bytes (`.gitattributes`: `-text`); do not re-save or re-format them.

## `golden/` — 3 households × 3 providers

`<household>-<provider>.head.txt` holds the method, bare host, path and query on the first line, then one
`Name: value` line per header, in order. The auth header holds the fake key `FAKE-TEST-KEY-not-a-real-key-0000`; no
real key is used anywhere. `<household>-<provider>.body.json` holds the exact canonical JSON body (no trailing newline).

| Household | Capture | Rooms | Titles sent (Q12 = yes) |
|---|---|---|---|
| `g1-outcome-empty` | the brief's Outcome sentence | none | none (the `tend-payload-dump --outcome-sample` body) |
| `g2-typical` | kitchen bin, dishwasher pods, balcony plants on Saturday morning | 5, one with a typographic apostrophe | 4 (hand-derived in the test file) |
| `g3-edge` | quotes, curly quotes, emoji, newline, slash, backslash | 5, with spaces, quotes, a slash, a backslash, non-ASCII | 10 of 13 eligible (the cap) |

The households (fixed version-4 UUIDs, dates, states) are in
`Packages/TendIngestion/Tests/TendIngestionTests/PayloadTestSupport.swift`.

## `allowed-key-paths-<provider>.json` — allowed key-path lists with roles (N-3)

Canonical JSON. `tend-eval-score --allowed-key-paths` reads `keyPaths[].path` (AC-M2-26).

- `keyPaths`: every leaf key path of the provider's body in the results-file form (`$`, then `.name` or `[]`; PO
  WI-M2-15 ruling 2). Role `userContent` (one path, with its concrete path in `at`) carries the capture, the room names
  and the titles; every other path is `fixed` (its value equals the golden request's value at the same concrete path).
- `userContentKeyPaths`: the layout of the user content, a canonical JSON object
  `{"capture": …, "existingTasks": [{"index": n, "title": …}], "rooms": [ … ]}`, with the roles `capture`, `roomName`,
  `shortlistIndex`, `shortlistTitle`, and `emptyList` for an empty `rooms` or `existingTasks`.
- `headers`: the builder's headers in order (`auth`, `fixed`), then headers the transport sets (`derivedByTransport`,
  left out of the Linux header comparison).

## Used by the payload proof (WI-M2-11, AC-M2-20 (a) and (b))

`PayloadSentinelTests.swift` reads the G1 head and body of each provider and its allowed list as the reference for
≥ 500 seeded households sent through the router: the key-path set must equal `keyPaths[].path`, every leaf outside the
user content must equal G1's at the same **concrete** index, every body byte outside the user-content string must
equal G1's, and the header names must equal the list's `auth` and `fixed` names in order.

## Regenerating (only under a PO decision, plan R-15)

```bash
TEND_PAYLOAD_GOLDEN_OUT=/tmp/payload-out swift test --package-path Packages/TendIngestion --filter PayloadGoldenTests
```
The test writes the files it builds to that directory (never into the repository) and still compares them with the
committed ones. Copy them here only with the PO decision recorded.
