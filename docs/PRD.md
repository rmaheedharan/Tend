# Product Requirements Document: Tend

> **Source of truth.** This is the product brief as written by the product owner (Maheedharan Rengarajan), stored as received.
> Only the Product Owner role may change the meaning of this file, and every change must be logged in
> [`docs/governance/DECISIONS.md`](governance/DECISIONS.md).
>
> **Editor's note on naming.** The original text uses both **"Tend"** and **"Hearth"**. The product name is **Tend**.
> Any remaining "Hearth" below means Tend. Do not use "Hearth" in code, UI copy, bundle IDs or docs.
>
> **Requirement IDs** (FR-A1, M1, UX-1 …) are stable. Stories, tests, and docs must reference them.
> The `UX-1`…`UX-4` labels on the UX laws were added by the editor so they can be traced; the text is unchanged.

## 1. Product Vision & Target Hardware

Tend is an AI-first, zero-admin household operating system for iOS. Its sole purpose is to eliminate the cognitive overload of managing a home. Unlike traditional chore apps that act as passive databases requiring manual data entry and triage, Hearth acts as an autonomous chief of staff that captures messy reality, shields the user from overwhelm, and surfaces only what matters right now.

- **Target Hardware Floor:** iPhone 15 Pro (A17 Pro, Action Button, Dynamic Island, ProMotion 120Hz).
- **Target OS:** Latest iOS (iOS 26+), leveraging native on-device AI (`FoundationModels`), Liquid Glass design language, App Intents, and ActivityKit.
- **Privacy Stance:** Local-first and privacy-preserving. All routine AI inference MUST run on-device. Any escalation to cloud intelligence MUST use Apple's Private Cloud Compute (or equivalent zero-retention privacy standards).

## 2. Non-Negotiable UX Laws & Anti-Patterns

Claude MUST enforce these laws across every screen and interaction:

1. **UX-1 Zero-Form Entry:** The primary way to add or update chores MUST NOT be a multi-field form (Title, Due Date, Recurrence, Assignee, Priority). Capture must happen via voice, camera, or shared content. Manual editing is allowed only as a secondary refinement.
2. **UX-2 The Rule of Three (Cognitive Shielding):** The home screen MUST NEVER display more than 3 actionable items at a time. Users must never be confronted with a scrolling wall of 30+ tasks.
3. **UX-3 Zero-Guilt Design:** The app MUST NOT use red overdue badges, angry notifications, or "X days overdue" counters. Missed tasks are treated as a signal of a busy life, not user failure.
4. **UX-4 Apple Design Award Craft:** Every interaction must feel physical, fluid, and intentional—utilizing Liquid Glass materials, spring-based motion, Core Haptics feedback, and Dynamic Type support across Light and Dark modes.

## 3. Functional Requirements

### Module A: Ambient & Multimodal Capture

The app must turn unstructured, messy human input into organized household state with zero manual categorization.

- **FR-A1 (Voice Brain-Dump):** Users MUST be able to tap a single primary trigger (or press the iPhone 15 Pro Action Button) and speak naturally (e.g., "The AC needs servicing before summer, we're almost out of dishwasher pods, and let's deep clean the balcony this weekend if it doesn't rain").
  - *Expected Behavior:* The AI parses the stream into distinct items (one-off errands, recurring maintenance, consumable restocks, weather-dependent tasks), infers the room and estimated effort, and checks against existing tasks to prevent duplicates.
  - *Feedback:* Parsed items MUST stream visually onto the screen as they are recognized, allowing a single-tap "Looks Good" confirmation or quick swipe-to-dismiss.
- **FR-A2 (Visual Room Sweep):** Users MUST be able to point their camera at a room, pantry, or appliance.
  - *Expected Behavior:* The app analyzes the visual state (e.g., overflowing laundry, cluttered counter, dry plant) or reads appliance labels/barcodes to suggest relevant tasks or auto-generate recurring maintenance schedules (e.g., filter replacements, descaling).
- **FR-A3 (Share Sheet Ingestion):** Users MUST be able to share a utility bill, appliance warranty PDF, or grocery receipt from any iOS app into Hearth.
  - *Expected Behavior:* The app extracts relevant dates, appliance models, or consumable items to quietly update household maintenance and restock timelines.

### Module B: Cognitive Load Shielding ("Now, Next, Invisible")

The app must actively decide what the user should—and should not—see.

- **FR-B1 (The "Now" Canvas):** The default home screen displays at most 3 high-leverage items selected dynamically based on:
  - Time of day (e.g., morning vs. evening routines).
  - Estimated effort vs. user's selected energy state (Low / Normal / High).
  - Contextual relevance (e.g., weather, day of week, or room proximity).
- **FR-B2 (Compassionate Rescheduling):** When tasks are not completed by their target window, the system MUST automatically renegotiate the schedule in the background.
  - *Expected Behavior:* Non-critical deep-cleaning tasks downgrade gracefully to "maintenance mode" during hectic weeks. Critical items (e.g., paying a bill, expiring food) gently resurface with a calm, supportive prompt rather than an alarm.
- **FR-B3 (Room Pulse View):** Users MUST have a secondary, glanceable view of their home organized by rooms. Each room card subtly shifts visual warmth/tint based on when it was last tended to, giving an instant 2-second intuition of household health without reading text lists.

### Module C: The "15-Minute Reset" (Guided Execution)

- **FR-C1 (Time-Boxed Micro-Sprints):** Users MUST be able to tap a quick trigger ("I have 15 minutes" or "I have 5 minutes").
  - *Expected Behavior:* The AI assembles a cohesive micro-sprint of high-impact tasks (preferring tasks in the same room to minimize context switching) that fit within the chosen time window.
- **FR-C2 (Hands-Free / Messy Hands Mode):** During an active sprint or multi-step routine, users MUST be able to mark steps complete via voice confirmation so they do not have to touch the screen with wet or dusty hands.
- **FR-C3 (Tactile Completion):** Completing any task MUST deliver distinct, crisp haptic feedback and a fluid visual transition.

### Module D: System-Wide iOS Integration

- **FR-D1 (Dynamic Island & Lock Screen Live Activities):** During an active "15-Minute Reset" sprint, a Live Activity MUST display the current task, remaining sprint time, and an interactive check-off button directly on the Lock Screen and Dynamic Island.
- **FR-D2 (Action Button & Siri / App Intents):** Core actions (Brain-Dump, Start 15-Minute Reset, Log Completed Chore) MUST be exposed as App Intents so they work seamlessly with Siri, Spotlight, Shortcuts, and the iPhone 15 Pro Action Button.
- **FR-D3 (Interactive Widgets):** Provide a Lock Screen and Home Screen widget showing only the single next high-leverage action with one-tap completion.

### Module E: Household Sync & Shared Mental Load

- **FR-E1 (Multi-Person Household Sync):** Support real-time, encrypted syncing across family/partner iPhones via iCloud.
- **FR-E2 (Invisible Load Balancing):** Avoid transactional "point leaderboards." Instead, the AI quietly tracks both physical chores and cognitive tasks (planning, restocking, coordinating) and subtly nudges fair distribution when suggesting assignments.

## 4. Incremental Build & Verification Plan (For Claude)

Claude MUST build this application incrementally in 5 vertical slices. Claude MUST NOT proceed to Milestone N+1 until all Acceptance Criteria for Milestone N are verified and passing.

| Milestone | Scope | Definition of Done & Verification Gate |
|---|---|---|
| **M1: Core Engine & Cognitive Shielding** | Household data persistence, the "Rule of Three" selection algorithm, energy/time filtering, and compassionate rescheduling logic. (No UI or AI yet). | • Automated unit test suite passes 100%.<br>• Tests prove: given 50+ mixed tasks, the engine always returns ≤ 3 contextually valid items.<br>• Tests prove: missed tasks reschedule smoothly without generating overdue debt states. |
| **M2: On-Device AI Ingestion** | Voice/text brain-dump parsing, duplicate detection, and streaming structured output using on-device Foundation Models. | • Automated mock tests pass 100%.<br>• Real-Device Eval Suite (iPhone 15 Pro): 20 messy real-world voice/text inputs parse accurately into tasks/rooms/efforts with latency under 1.5 seconds and zero duplicate creation. |
| **M3: Award-Caliber Liquid Glass UI** | The "Now" Canvas, Room Pulse view, streaming Brain-Dump UI, 15-Minute Reset flow, Core Haptics, and fluid transitions. | • Visual inspection via Xcode Previews across Light Mode, Dark Mode, and Accessibility Dynamic Type (XL) shows zero text clipping, high contrast, and clean Liquid Glass layering.<br>• Zero forms required to capture and complete a chore. |
| **M4: Multimodal & System Surfaces** | Camera Room Sweep, Share Sheet receipt/bill parsing, App Intents (Siri + Action Button), Interactive Widgets, and Dynamic Island Live Activity. | • End-to-end physical test on iPhone 15 Pro: Action Button → Voice/Camera → Task saved → 15-Minute Reset started → Task checked off from Dynamic Island.<br>• App Intents execute reliably via Siri/Shortcuts. |
| **M5: Household Sync & Polish** | iCloud shared household sync, conflict resolution, invisible load balancing, and performance/thermal profiling. | • Multi-device sync test (changes reflect across devices within seconds without data loss).<br>• Smooth 120Hz scrolling on ProMotion display; no thermal throttling during on-device AI inference. |
