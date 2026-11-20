# ADR-0003: Xcode project generation (XcodeGen vs Tuist)

- **Status:** Proposed (options analysis lands in M1 so M3 is not blocked; to be accepted when the app target is first
  created, at the latest at the start of M3 build)
- **Date:** 2026-11-20
- **Deciders:** Developer (proposer); Reviewer
- **Requirements:** CLAUDE.md §3 "Project generation" and §6 (agents never hand-edit `.pbxproj`; no dependency without
  an ADR); brief Q10; P-2 (no third-party analytics)

## Context
- M1 needs only the SwiftPM package `Packages/TendCore` (ADR-0001); no Xcode project exists yet.
- From M3 the repo needs an app target, plus widget, Live Activity, Share and Intents extensions (M4). These need
  entitlements, App Groups and a Privacy Manifest.
- Agents edit this repo in parallel through PRs. A hand-edited `project.pbxproj` causes merge conflicts that agents
  cannot resolve reliably, so the project should be generated from a reviewable text spec.
- The tool runs only on developer machines and macOS CI; it ships nothing in the app.
- Nothing here can be tried on Linux. This ADR is an options analysis.

## Options considered
1. **XcodeGen (`project.yml`).**
   - Pros: a single binary with a small YAML spec that is easy for agents and reviewers to diff. It covers app and
     extension targets, entitlements, Info.plist, schemes and local SwiftPM packages. It has no telemetry, server or
     account. The generated project is plain Xcode.
   - Cons: YAML has no type checking (mitigated by CI that runs `xcodegen generate` and builds). Its feature growth is
     slower than Tuist's. Very large graphs get verbose.
2. **Tuist (`Project.swift` manifests).**
   - Pros: manifests are type-checked Swift; strong for many modules; it has caching and graph tooling.
   - Cons: a heavier toolchain with its own versioning and install path (`mise` or similar). Some features are tied to
     its hosted service, and analytics have to be opted out explicitly (P-2 hygiene for our dev environment). Manifests
     run code at generation time.
3. **No generator: a checked-in project with Xcode buildable folders.**
   - Pros: no extra tool, and folder-synchronised groups reduce `.pbxproj` churn.
   - Cons: target, entitlement and build-setting changes still edit `.pbxproj`. That conflicts with CLAUDE.md §3/§6.

## Decision
Proposed: **option 1, XcodeGen**, pinned to an exact version in CI. The `project.yml` will sit at the repo root and
reference `Packages/TendCore` (and later adapter packages) as local packages. The generated `.xcodeproj` is
git-ignored and regenerated in CI and locally (`xcodegen generate`), matching the command already listed in CLAUDE.md §7.

Why: our graph is small (one app, about four extensions, a few local packages). XcodeGen's flat YAML is the easiest
format for agents to edit and for the Reviewer and Merge Gatekeeper to diff. It adds no telemetry or hosted-service
surface. Tuist's strengths (caching, very large graphs) do not pay for its extra toolchain here.

## Consequences
- Positive: no `.pbxproj` merge conflicts; project changes are small YAML diffs that cite requirement IDs.
- Negative: one more dev tool on macOS machines and CI (installed by pinned version; recorded here as the dependency
  decision). YAML mistakes only show up when generating, so CI must run `xcodegen generate` before `xcodebuild`.
- Follow-up: when the M3 app target is created, add `project.yml`, the macOS CI job (generate, build, test on the
  Simulator), `.gitignore` entries for the generated project, and move this ADR to `Accepted`. The CI workflow is a
  protected path, so the human owner merges that change.
- We would know this was wrong if the project needs features that XcodeGen cannot express (for example complex build
  phases per extension) or the YAML grows hard to review. Then we re-evaluate Tuist with a superseding ADR.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | n.a. | Build tooling. |
| UX-2 Rule of Three | n.a. | Build tooling. |
| UX-3 Zero-Guilt | n.a. | Build tooling. |
| UX-4 Design craft | n.a. | Build tooling. |
| P-1 On-device inference | n.a. | Build tooling. |
| P-2 No data leaves device | pass | Nothing is linked into the app. The chosen tool has no telemetry. |
| P-3 Cloud escalation | n.a. | Build tooling. |
| P-4 Media not persisted | n.a. | Build tooling. |
