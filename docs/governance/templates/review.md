# M<n> Code Review — <PR link>

- **Owner:** Reviewer  ·  **Verdict:** APPROVE | CHANGES REQUIRED  ·  **Round:** 1

## Summary
## Findings
| # | Severity | File:line | Finding | Required change | Status |
|---|---|---|---|---|---|

## Checklist
- [ ] Correctness vs ACs  - [ ] Tests meaningful (would fail if code broke)  - [ ] Swift 6 concurrency safe
- [ ] No force unwraps / try! in product code paths  - [ ] Privacy (P-1…P-4)  - [ ] UX-2/UX-3 enforced in engine
- [ ] Accessibility (UI)  - [ ] Performance (main thread, allocations, 120 Hz)  - [ ] No new dependency without ADR

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | | |
| UX-2 Rule of Three | | |
| UX-3 Zero-Guilt | | |
| UX-4 Design craft | | |
| P-1 On-device inference | | |
| P-2 No data leaves device (except user iCloud) | | |
| P-3 Cloud AI only opt-in, BYOK, minimised, per ADR-0005 | | |
| P-4 Media not persisted without consent | | |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
