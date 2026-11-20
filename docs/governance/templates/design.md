# M<n> Design Spec — <surface>

- **Owner:** iOS Designer  ·  **Work items:** <WI IDs>  ·  **Status:** Draft | Ready | Reviewed-in-build

## Intent
What the user should feel and understand in under 2 seconds.

## Layout and hierarchy
Structure per size class (iPhone compact, iPad regular). Max actionable items shown: ≤ 3 (UX-2).

## States
| State | What is shown | Copy | Motion | Haptic |
|---|---|---|---|---|
| Empty | | | | |
| Loading / streaming | | | | |
| Normal | | | | |
| Model unavailable | | | | |
| Error (calm) | | | | |
| Completed | | | | |

## Materials, colour, type
Liquid Glass usage (which layers are glass, which are content), semantic colours, SF Symbols, type styles.

## Motion and haptics
| Event | Animation (spring params) | Reduce Motion fallback | Haptic |
|---|---|---|---|

## Copy deck
| Key | Text | Tone note (zero-guilt) |
|---|---|---|

## Accessibility
VoiceOver labels and order, Dynamic Type up to AX5 behaviour, contrast, Reduce Transparency fallback, hit targets ≥ 44 pt.

## Design review of build
| Check | Result | Evidence (preview/screenshot) |
|---|---|---|

## Law check
| Law | Status (pass / n.a. / concern) | Note |
|---|---|---|
| UX-1 Zero-Form Entry | | |
| UX-2 Rule of Three | | |
| UX-3 Zero-Guilt | | |
| UX-4 Design craft | | |
| P-1 On-device inference | | |
| P-2 No data leaves device (except user iCloud) | | |
| P-3 Cloud escalation only via PCC + ADR | | |
| P-4 Media not persisted without consent | | |

## Handoff log
| Date | From | To | Result (accepted / returned) | Notes |
|---|---|---|---|---|
