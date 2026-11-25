# ADR-0003: Xcode project generation (XcodeGen vs Tuist)

- **Status:** Accepted (WI-M2-M1, 2026-11-25, on the owner-run Mac). Proposed 2026-11-20; accepted when the first app
  targets were created (M2 `TendEval`, `TendAITestHost` and the `Tend` skeleton), as this ADR's follow-up said.
- **Date:** 2026-11-20
- **Deciders:** Developer (proposer, WI-M2-M1); Reviewer (to confirm on the WI-M2-M1 PR)
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
**Option 1, XcodeGen**, pinned to one exact release. `project.yml` sits at the repo root and references
`Packages/TendCore`, `Packages/TendIngestion` and `Packages/TendAI` as local packages. The generated `Tend.xcodeproj` is
git-ignored and always regenerated (`xcodegen generate --spec project.yml`). **Agents never hand-edit `.pbxproj`;** a
PR that contains a `.pbxproj` change is returned (M2 plan WI-M2-M1).

Why: our graph is small (one app, about four extensions, a few local packages). XcodeGen's flat YAML is the easiest
format for agents to edit and for the Reviewer and Merge Gatekeeper to diff. It adds no telemetry or hosted-service
surface. Tuist's strengths (caching, very large graphs) do not pay for its extra toolchain here.

### The pinned tool (the dependency record, CLAUDE.md §6)
| Item | Value |
|---|---|
| Tool | XcodeGen (github.com/yonaskolb/XcodeGen), MIT licence |
| Version | **2.46.0** (released 2026-07-16). 2.47.0 and 2.48.0 came out on 2026-11-17 and 2026-11-19; we pin the release that has been out for four months, not one from last week. Moving the pin is a one-line PR that updates this table and `options.minimumXcodeGenVersion` in `project.yml`. |
| Artifact | `https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip` (5,738,697 bytes) |
| SHA-256 of the zip | `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806` (matches the digest GitHub publishes for the asset) |
| SHA-256 of `bin/xcodegen` | `8774da746668bc18fe74e54cbaf10f2631a1fb05947cd374179aa912f14f99db` (universal x86_64 + arm64) |
| Install method | The GitHub release binary, not Homebrew or Mint (no extra package manager, and an exact artifact we can checksum). See below. |
| Enforced in the spec | `options.minimumXcodeGenVersion: 2.46.0` in `project.yml` |

Install (owner-run Mac; no `sudo`, nothing in `/usr/local`):
```bash
mkdir -p "$TMPDIR/xcodegen-2.46.0" && cd "$TMPDIR/xcodegen-2.46.0"
curl -sSL -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
echo "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806  xcodegen.zip" | shasum -a 256 -c
unzip -q xcodegen.zip
mkdir -p ~/.local/opt ~/.local/bin && cp -R xcodegen ~/.local/opt/xcodegen-2.46.0
printf '#!/bin/sh\nexec "$HOME/.local/opt/xcodegen-2.46.0/bin/xcodegen" "$@"\n' > ~/.local/bin/xcodegen
chmod +x ~/.local/bin/xcodegen && xcodegen --version      # Version: 2.46.0
```
The binary finds its `SettingPresets` relative to its own path (`../share/xcodegen`). A **symlink** in `~/.local/bin`
does not work: generation then prints `No "iOS" settings found` and produces a project without the platform presets
(seen on 2026-11-25). Use the wrapper script above.

## Consequences
- Positive: no `.pbxproj` merge conflicts; project changes are small YAML diffs that cite requirement IDs.
- Negative: one more dev tool on macOS machines (installed by pinned version and checksum, above). YAML mistakes only
  show up when generating, so every Mac run does `xcodegen generate` before `xcodebuild` (M2 plan B3).
- There is no macOS CI lane (Q8: no paid macOS runner). The owner-run Mac is the Mac lane, and Mac-only PRs are merged
  under D-032. If a macOS CI job is added later, it installs the same artifact and checks the same SHA-256; the
  workflow is a protected path, so the human owner merges that change.
- Things learnt when the first targets were generated (XcodeGen 2.46.0, Xcode 27.2):
  - `options.createIntermediateGroups` must stay off: with it, `Packages/TendAI/HostedTests` is placed under both the
    local-package group and the target group, and Xcode refuses to open the project ("is a member of more than one
    group").
  - Xcode has no `INFOPLIST_KEY_` setting for `UIFileSharingEnabled`, so `TendEval`'s Debug-only file sharing is a
    partial `Info.plist` set by `INFOPLIST_FILE` in the Debug configuration only, merged with the generated keys.
  - A source entry with `type: folder` and `group:` resolved to the wrong path; the eval fixtures are listed file by
    file instead (which also matches M2 Q23: a small, fixed set of bundled files).
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
| P-2 No data leaves device | pass | Nothing is linked into the app. The chosen tool has no telemetry and no account; it runs only on the developer Mac. |
| P-3 Cloud escalation | n.a. | Build tooling. |
| P-4 Media not persisted | n.a. | Build tooling. |
