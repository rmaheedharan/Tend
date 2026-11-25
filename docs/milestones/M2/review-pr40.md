# M2 Code Review — PR #40 (`m2/eval-freeze-sha256-path`, round 1 @ `cc25baf`, base `origin/main` `2a47f75`)

- **Owner:** Reviewer (fresh context; did not write this code)  ·  **Verdict:** **APPROVE**  ·  **Round:** 1
- **Scope:** A test-only change under **AC-M2-13(b)** and **AC-M2-14** (WI-M2-16). The owner's Mac (macOS 27.2.1, at
  `cf1261f`) skipped "AC-M2-14: the documented manifest command writes exactly the in-memory render" because the test
  looked for `sha256sum` only at `/usr/bin/sha256sum`, and on that Mac it is at `/sbin/sha256sum`. AC-M2-13(b) needs
  0 skipped on the Mac. Diff: `git diff origin/main...HEAD` covers 2 files,
  `Packages/TendIngestion/Tests/TendIngestionTests/EvalFreezeTests.swift` (+42/−5) and `docs/milestones/M2/dev-notes.md`
  (+57). No file under `Sources/`, `Package.swift` or `Fixtures/` changed. No protected path is touched.
- **Inputs read:** `CLAUDE.md`; this skill; `brief.md` AC-M2-13 (gate, 0 skipped in (a) and (b), T-22) and AC-M2-14
  (SHA-256 manifest, frozen); the PR diff; the dev-notes section for this change; the full `EvalFreezeTests.swift`.
- **Milestone lock:** `STATUS.md` shows M1 `ACCEPTED` and M2 `IN-BUILD`. An `m2/` test fix is allowed (CLAUDE.md §5).

## Summary

The change only widens where the manifest-command test runs. It does not change what the test asserts. The resolver
searches `/usr/bin` first, so Linux behaves exactly as before. It then searches `/sbin` (macOS 27), the other fixed
places, and then `PATH` in order. The new resolver test is a real ordering test with an injected `isExecutable`, and
two mutants prove it. I simulated the Mac layout in the Linux container (`sha256sum` only at `/sbin`), and the
manifest-command test ran and passed instead of skipping. I found no Blocker and no Major.

### 1. Assertions unchanged, guard only widened (no weakening)
- The only removed lines (`git diff … | grep '^-'`) are: the header comment line, `static let sha256sum =
  "/usr/bin/sha256sum"`, the old `.enabled(if: isExecutableFile(atPath: "/usr/bin/sha256sum"))` guard and its message,
  and `process.executableURL = URL(fileURLWithPath: EvalFreeze.sha256sum)`. That line now uses the resolved local.
  Every `#expect` in `documentedCommandMatchesRender` (`:174-192`) is byte-identical to the base: the prefix and
  suffix of `EvalManifest.command`, the name list, exit status 0, and stdout equal to `EvalManifest.render`.
- Guard: before, the test was enabled iff `/usr/bin/sha256sum` was executable. Now it is enabled iff the resolver finds
  one, and `/usr/bin` is the first place it checks (`:49-50`). So every host that ran the test before still runs it,
  with the same binary. The set of hosts that run it only grows.
- `try #require(EvalFreeze.sha256sum)` (`:172`) makes a nil inside the body fail rather than pass. That cannot happen
  while the guard holds, but it is the right choice over a force unwrap.
- A wrong binary found through `PATH` cannot make the test pass falsely. Its stdout must equal the in-memory render
  byte for byte, or the test fails.

### 2. Resolver correctness and test meaning
- `resolveSHA256Sum` (`:54-62`) splits `PATH` on `:`, drops empty entries, appends them after the fixed list, and
  returns the first `dir + "/sha256sum"` for which `isExecutable` is true. A nil `PATH` gives the fixed list only. This
  is correct. The order (fixed places before `PATH`) is a reasonable choice: it pins the system binary and stops a user
  `PATH` from shadowing it.
- The 6 cases (`:85-93`) cover Linux `/usr/bin` beating `/sbin`, macOS 27 `/sbin` with `/sbin` also in `PATH`,
  Homebrew before `PATH`, `PATH` order with an empty entry (`/nix/bin::/home/u/bin`), none found, and no `PATH`. The
  injected predicate checks the exact full path, so the test checks the path joining as well as the order. It does not
  just repeat the implementation.
- **Mutants (my run, a copy of the tree in a scratch directory, `--filter EvalFreezeTests`):**
  - (a) The old behaviour (only `/usr/bin`, `PATH` ignored): the resolver test failed on cases 1, 2 and 3 (`→ nil ==
    "/sbin/sha256sum"`, …). With `sha256sum` moved to `/sbin`, the manifest-command test was
    `➜ … skipped: "no executable sha256sum in …"`, which is the Mac failure reproduced.
  - (b) `PATH` before the fixed list: case 2 failed (`"/home/u/bin/sha256sum" == "/opt/homebrew/bin/sha256sum"`).
  - 2/2 killed. I restored the file and checked it with `cmp` against the PR tree.

### 3. Swift 6 strict concurrency
`static let sha256sumFixedDirectories: [String]`, `static let sha256sum: String?` and `static let resolverCases`
(a tuple array of `String`, `Set<String>` and `String?`) are all immutable `static let`s of `Sendable` types. Those are
safe global constants under Swift 6 strict concurrency, and they are lazily initialised (thread-safe). There is no
`static var` with mutable state (`manifestExists` and the others are computed). There is no `nonisolated(unsafe)` and
no `@unchecked Sendable`. The default-argument closure is non-escaping. `-warnings-as-errors` builds clean.

### 4. What I ran
| Command | Result |
|---|---|
| `docker run --rm -v /home/user/wt-rev40:/w -w /w swift:6.2-noble swift test --scratch-path /tmp/rev40 --package-path Packages/TendIngestion -Xswiftc -warnings-as-errors` | exit 0, `✔ Test run with 571 tests in 67 suites passed after 144.170 seconds.`, 0 `warning:`, 0 `✘`, 0 `➜ … skipped` result lines. The manifest-command test passed, and the resolver test passed with 6 test cases. |
| Mac-layout simulation: same image, `mv /usr/bin/sha256sum /usr/sbin/sha256sum` (so it is at `/sbin/sha256sum`; `/sbin` links to `usr/sbin` on noble), `PATH=/usr/local/bin:/usr/bin`, `--filter EvalFreezeTests` | `✔ … documented manifest command … passed`, `✔ Test run with 10 tests in 1 suite passed`. The test resolves `/sbin/sha256sum` and runs. |
| Mutants (a) and (b), above | 2/2 killed |

## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|
| n1 | Nit | `EvalFreezeTests.swift:170` | The skip message lists the directories by hand, so it can drift from `sha256sumFixedDirectories` (`:49`). | Optional: build the message from the array, or leave a comment pointing to it. | Open |
| n2 | Nit | `EvalFreezeTests.swift:58` | A relative `PATH` entry (for example `.`) is kept and resolved against the test's working directory. The fixed list comes first, so this only matters on a host with no system `sha256sum`, and a wrong binary would fail, not pass. | None required. Optional: keep only absolute entries (`hasPrefix("/")`). | Open |
| i1 | Info | dev-notes "Verification environment" | The owner's Mac rerun has not happened yet. On the Mac, `/sbin/sha256sum` is Apple's own `sha256sum`, not GNU coreutils. If its output format ever differs from GNU's `<hash>  <name>`, the test will **fail**, not skip. That would be an honest AC-M2-14 signal, not a weakening, and Linux cannot check it. | Acceptance Tester: record the owner's Mac TendIngestion run (571 passed, 0 skipped) under AC-M2-13(b). | — |
| i2 | Info | — | `docs/product/TRACEABILITY.md` has no entry for `sha256sumResolver` (and none for `documentedCommandMatchesRender`). | Documenter: add the AC-M2-13(b)/AC-M2-14 → test rows when traceability for M2 is updated. | — |

## Checklist
- [x] Correctness vs ACs: AC-M2-14's manifest-command check now runs where `sha256sum` lives on macOS 27 (`/sbin`), which AC-M2-13(b) (0 skipped) needs. I proved this by simulating the Mac layout on Linux.
- [x] Tests meaningful (would fail if code broke): 2/2 resolver mutants killed. The old path-only behaviour reproduces the skip.
- [x] No weakening: every assertion in `documentedCommandMatchesRender` is unchanged, and the guard is a strict superset (`/usr/bin` first). No tolerance and no conditional pass. `#require` turns a nil into a failure.
- [x] Swift 6 concurrency safe: only immutable `static let`s of `Sendable` types. `-warnings-as-errors` builds clean.
- [x] No force unwraps / try! in product code paths: no product code changed.
- [x] Privacy (P-1…P-4): not applicable (a local process in tests only, writing to stdout).
- [x] UX-2/UX-3 enforced in engine: not applicable (no engine change).
- [x] Accessibility (UI): not applicable.
- [x] Performance: not applicable. The resolver does at most a few `stat` calls, once.
- [x] No new dependency without ADR: none added. `sha256sum` is a system tool that the test already used.

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | No entry surface. |
| UX-2 Rule of Three | n.a. | No selection surface. |
| UX-3 Zero-Guilt | n.a. | No user-facing copy. The skip message is test output only, and the diff has no banned token. |
| UX-4 Design craft | n.a. | No UI. |
| P-1 On-device inference | n.a. | No inference path changed. |
| P-2 No data leaves device (except user iCloud) | n.a. | A local `sha256sum` subprocess over the fixture files, in tests only. No network. |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | n.a. | No change. |
| P-4 Media not persisted without consent | n.a. | No media. Nothing is written (stdout only). |

## Verdict
**APPROVE.** No open Blocker or Major. n1 and n2 are optional Nits. This is a merge decision on PR #40 only. It does
not accept AC-M2-13(b), which still needs the owner's Mac TendIngestion run with 0 skipped (i1), recorded by the
Acceptance Tester.

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
| 2026-11-25 | Orchestrator | Reviewer | accepted | Review PR #40 at `cc25baf` (AC-M2-13(b), AC-M2-14, WI-M2-16): `sha256sum` at `/sbin` on macOS 27. |
| 2026-11-25 | Reviewer | Orchestrator → Merge Gatekeeper, Acceptance Tester, Documenter | sent | APPROVE. 571 passed, 0 skipped, 0 warnings. Assertions unchanged, guard only widened. Mac layout simulated: the test runs from `/sbin`. 2/2 mutants killed. Tester: record the owner's Mac rerun (i1). Documenter: traceability rows (i2). |
