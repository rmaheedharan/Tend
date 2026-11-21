# ADR-0005: Opt-in cloud AI with the user's own provider key (BYOK)

- **Status:** Proposed. The human owner chose the key model (BYOK) on 2026-11-21 (D-030). The whole ADR is awaiting
  the human owner's approval, given by merging the PR that adds it (protected paths). Under P-3 it also needs the
  Product Owner's approval, which the PO gives by writing it.
- **Date:** 2026-11-21
- **Deciders:** Human owner (product direction, key model), Product Owner (policy, P-3). Developer and Reviewer to
  confirm the technical parts during M2 planning.
- **Requirements:** FR-A1 (M2), FR-A2 and FR-A3 (M4), UX-1, UX-2, UX-3, P-1, P-2, P-3, P-4; AC-M1-23; AC-M2-09…11,
  AC-M2-16, AC-M2-18…27; CLAUDE.md §2, §3, §9 item 2; PRD §1, §3, §4

## Context
On 2026-11-21 the human owner wrote: "I'd like to use cloud ai as well when appropriate. I wanted this to be compatible
with iphone 13 too which does not have on device model, so it'd be good to have support to access cloud models outside
of apple - like open ai, claude api, gemini, etc".

The rules before this ADR said something different:
- P-1: all routine AI inference runs on device.
- P-2: no cloud LLM APIs, and no household data leaves the device except through the user's own iCloud.
- P-3: cloud escalation only through Apple Private Cloud Compute (PCC) or an equivalent zero-retention service.
- CLAUDE.md §3: the hardware floor is the iPhone 15 Pro (A17 Pro).

Facts that shape the decision:
- `FoundationModels` (the Apple Intelligence on-device model) needs an Apple Intelligence device, which means iPhone 15
  Pro or later. iPhone 13, iPhone 14 and iPhone 15 (non-Pro) run iOS 26 but report `SystemLanguageModel.availability`
  as unavailable (device not eligible).
- Third-party apps cannot call Apple PCC directly for our use case (CLAUDE.md §9 item 2). "Apple's cloud only" therefore
  gives nothing to iPhone 13 users today.
- On-device speech (`SpeechAnalyzer` with `SpeechTranscriber` or `DictationTranscriber`) and Vision run on iPhone 13
  class hardware. Only the language-model step is missing there. Whether `SpeechTranscriber` itself is supported on
  A15 is checked on device in M2 (AC-M2-25). If it is not, `DictationTranscriber` (on device) is used.
- OpenAI, Anthropic and Google Gemini all offer HTTPS APIs with streaming and structured (JSON-schema) output. Their
  data terms differ, and they change. As of this ADR (to be re-checked by the Developer at build and by the PO before
  release):
  - OpenAI API: not used for training by default. Abuse-monitoring logs are kept for a limited period. Zero data
    retention exists only by arrangement with OpenAI, which a personal key normally does not have. The `store: false`
    request parameter turns off stored completions.
  - Anthropic API: not used for training by default. Inputs and outputs are kept for a limited period. Zero data
    retention exists only by arrangement.
  - Google Gemini API: on the paid tier, prompts are not used to improve Google's products. On the **free tier**,
    Google may use prompts and responses to improve its products, and human reviewers may read them.
  So Tend cannot promise zero retention for any provider with a user's own key. It can only minimise what it sends and
  tell the truth about what each provider keeps.
- App Store Review Guideline 5.1.2(i), as updated in 2025, asks apps to say clearly when personal data is shared with
  third-party AI and to get explicit permission first.
- `TendCore` must stay Foundation-only with no networking (ADR-0001, AC-M1-23).

## Options considered
1. **User adds their own API key (BYOK). The phone calls the provider directly. No Tend server.**
   - Pros: there is no Tend server to run, secure or breach, and Tend never holds household data or keys. The user picks
     the provider and has a direct relationship with it (their own account, billing and data settings). Works on iPhone
     13. Fits the owner's request exactly.
   - Cons: the user must create a provider account and paste a key, which adds a one-time setup step for a persona that
     wants less admin. The user pays the provider. Retention depends on the user's account (for example the Gemini free
     tier). The key sits on the device, so it could be extracted from a compromised (jailbroken) phone; it is the user's
     own key and the user can revoke it. Each provider's API needs its own adapter and eval.
2. **Tend runs its own server that holds the provider keys (proxy).**
   - Pros: no key setup for the user. Tend could negotiate zero-retention terms with providers for all users. One place
     to switch models.
   - Cons: every capture passes through a Tend server, which creates a new place where household data could be logged
     or breached. Running it costs money and needs accounts, abuse protection and an operations owner. It needs its own
     security and retention ADR and a privacy-policy change. It is a bigger departure from "no household data leaves
     the device" than the owner asked for.
3. **Apple's cloud only (Private Cloud Compute).**
   - Pros: the strongest privacy story. It matches the old P-3.
   - Cons: no third-party API for our use case, and no help for iPhone 13, which is the owner's main reason for the
     change. It is the same as "on-device only" in practice.

## Decision
We choose **option 1, bring your own key (BYOK)**. The human owner picked it on the decision card on 2026-11-21
(D-030). The policy below is binding on every role. CLAUDE.md §2 P-1…P-3 point here.

**1. On-device first.**
- If `SystemLanguageModel.default.availability` is `.available`, Tend uses `FoundationModels`. This holds unless the user
  has explicitly picked "Always use my cloud model" in Settings.
- Cloud is used only when cloud is turned on **and** one of these is true:
  - (a) the on-device model is unavailable for any reason (device not eligible, Apple Intelligence off, model not
    ready, unsupported language);
  - (b) the user explicitly picked "Always use my cloud model".
- An on-device **error** on a device where the model is available (guardrail, context too long) never silently
  escalates to the cloud. It returns the calm outcome (AC-M2-10).
- Speech recognition and Vision always run on device. Audio and camera frames are **never** sent to a cloud provider,
  and no cloud speech-to-text service is used.

**2. Off by default, explicit consent, easy to turn off.**
- Cloud AI is off on install and after restore. It is turned on only from Settings, never by a prompt that appears
  during capture or by a nudge.
- Turning it on shows a plain-language consent screen before any key is accepted. The screen:
  - names the provider;
  - says what is sent ("the words of the thing you just captured, and your room names", plus up to 10 short task
    titles if M2 brief Q12 allows it; Q13 and Q14 below also refer to the M2 brief);
  - says what is never sent (voice recordings, photos, people's names, your whole household, anything identifying you
    to Tend);
  - states the provider's retention in one honest sentence from the per-provider table, and the Gemini free-tier
    warning where it applies;
  - says how to turn it off.
- Turning it off takes one switch. It stops all cloud calls at once and deletes the stored key.
- Consent is per provider. Switching provider shows that provider's consent screen.
- There is no nagging. Tend never asks the user to turn cloud on, and never shows a "you're missing out" message.

**3. Data minimisation. One request per capture, and nothing else.** A cloud request may contain only:
- the fixed system instructions and output schema, which hold no household data;
- the text of the **single** capture being processed. That is the final on-device transcript, the typed text, or (from
  M4) on-device Vision or VisionKit extracted text;
- the list of the household's **room names**, so rooms can be linked;
- **if Q12 is answered yes:** up to 10 existing task titles, pre-filtered on device (same room or shared keywords) as
  duplicate candidates. Each title carries a per-request index number (1…10) and no ID.

A cloud request must never contain any of these:
- task IDs, room IDs, household or member identifiers;
- household member or assignee names, or the user's name;
- other tasks' notes, dates, history or state;
- location, time zone, device identifiers or the Tend install ID;
- audio, images or documents;
- the date and time. Time phrases come back as structured hints that the local resolver applies (M2 Q6).

Other rules:
- The duplicate-lookup `Tool` is **not** given to cloud models. Cloud models get no tool access to the household.
  Duplicate marking against the shortlist is checked again locally before commit.
- Raw images going to the cloud is **out of scope** until an M4 ADR addendum and a separate consent line exist (Q14).
- The request is built by a pure, Foundation-only **payload builder** in the platform-neutral ingestion layer (outside
  `TendCore`). It returns plain values: provider, path, header names, body bytes. Tests can compare its output byte for
  byte on Linux. The builder is the only code that may read household data for a request. Adding a field to it needs a
  new ADR approved by the PO and the human owner.

**4. Retention and training: ask for the least, claim only what is true.**
- Each provider adapter sets every request-level option that reduces retention or training where the API offers one.
  For OpenAI this is `store: false`. The Developer lists the options for each provider in the dev notes and the
  Reviewer checks them against current provider docs.
- Tend's copy never says "zero retention", "never stored" or "private" about a cloud provider unless that provider
  guarantees it for this key. The per-provider disclosure table lives in the String Catalog (M3). The PO reviews it
  before any release.

**5. Keys.**
- Pasted in Settings only, one key per provider.
- Stored in the iOS Keychain as a generic password, accessible `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It is
  not synced to iCloud Keychain and not in backups.
- Never written to `UserDefaults`, files, logs, crash reports, analytics or CloudKit, and never shown again in full
  after saving (masked).
- Sent only in the provider's auth header, over TLS, to that provider's fixed host.
- "Remove key" and "turn cloud off" both delete the Keychain item.
- Validating a key may send one fixed test prompt with no household data.

**6. Transport.**
- Plain HTTPS with `URLSession` (ephemeral configuration, no cookies, no URL cache).
- Hosts come from a fixed allowlist: `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com`.
- No custom base URL or "any OpenAI-compatible server" in this ADR (Q13).
- No provider SDKs. Adding any SPM package needs its own ADR (CLAUDE.md §6).
- No analytics, ad or tracking SDKs.
- Models come from a curated list per provider in the app, which a release can update. There is no free-text model ID.

**7. Calm fallback.**
- If there is no usable model, the pipeline returns a calm typed outcome and the input text in memory (AC-M2-10).
  "No usable model" covers: cloud off and no on-device model; offline; provider error, rate limit or invalid key.
- The caller can then offer to keep the words as **one plain note**. This is a single draft whose title is the user's
  own words, with the default fields from M2 Q5. It is committed only on confirm.
- Tend does not queue or retry captures in the background, so no unsaved transcript is kept (P-4).
- No outcome or copy blames the user or the provider in alarming terms (UX-3).

**8. Code boundaries.**
- `TendCore` is unchanged. It stays Foundation-only with no networking, and AC-M1-23 stands.
- `TendAI` gets one `IngestionModel` protocol with two kinds of implementation: the on-device adapter and one cloud
  adapter per provider. Both return the same structured draft stream.
- Networking APIs are allowed only in the cloud-adapter source files named in a fixed allowlist (AC-M2-09).

**9. Disclosure.**
- `PrivacyInfo.xcprivacy` and the App Store privacy label declare the cloud use. The likely declaration is "User
  Content: other user content", sent to a third party for app functionality, not used for tracking. The PO reviews the
  exact declaration at M3, when the app target ships.
- The in-app privacy page names the three providers.

**10. Hardware floor.**
- The floor becomes **iOS 26 on iPhone 13 (A15)**.
- The Action Button (iPhone 15 Pro and later) and the Dynamic Island (iPhone 14 Pro and later) degrade gracefully on
  phones without them, as on iPad. The fallbacks are the in-app trigger, Siri and Shortcuts, Control Center controls
  and the Lock Screen Live Activity.
- ProMotion 120 Hz applies where the display has it. Other displays must hold 60 Hz.

## Consequences
- **Positive:** iPhone 13 to iPhone 15 (non-Pro) users get AI capture. There is no Tend server, so there is no central
  store of household data and no running cost for Tend. Owners of the on-device model keep the fully offline path by
  default.
- **Negative:**
  - The "nothing leaves your phone" story is no longer true for users who turn cloud on, so the copy must say so
    honestly.
  - BYOK adds setup work for the user.
  - Each provider needs its own adapter, schema mapping, eval run and data-terms check, and provider APIs and terms
    change.
  - Cloud latency depends on the network, so M2 has a separate cloud latency target (AC-M2-27).
  - Gemini free-tier keys allow training use; we can warn about it but we cannot detect or block it.
- **Follow-up work:**
  - M2 brief stories S-M2-07 and S-M2-08 (adapters, consent, minimisation, keys, fallback, latency).
  - Law-check labels for P-1…P-3 in `docs/governance/templates/*` are to be updated to the new wording.
  - String Catalog disclosure table (M3).
  - Privacy Manifest and label (M3).
  - M4 addendum for document and image text, and for any raw image.
  - Re-check provider terms before each release.
- **How we would know this was wrong:**
  - Users who turn cloud on cannot say in plain words what is sent. Check this with the consent copy test in M3.
  - A payload test finds a field outside the list in Decision 3.
  - Provider terms change so that we can no longer describe retention honestly.
  - The owner later wants zero-retention guarantees for everyone. That would mean revisiting option 2 with negotiated
    terms.

## Law check
| Law | Status | Note |
|---|---|---|
| UX-1 Zero-Form Entry | pass | Capture stays voice, text or camera. Key entry is a one-time Settings step, not a capture form. The no-model fallback is one free-text note, not a multi-field form. |
| UX-2 Rule of Three | pass | Cloud drafts flow through the same pipeline and reach Now only through `NowSelector` (≤ 3). |
| UX-3 Zero-Guilt | pass | No nagging to turn cloud on, and calm outcomes for offline, key and provider errors. The calm-words guard (AC-M2-12) applies to cloud output too. |
| UX-4 Design craft | n.a. | Consent and Settings screens are designed in M3 (Designer owns copy, motion and accessibility). |
| P-1 On-device first (rewritten) | pass | The on-device model is preferred whenever available. Speech and Vision are always on device. Cloud is used only in the two cases in Decision 1. |
| P-2 Data leaves only via iCloud or a P-3 request (rewritten) | pass | Direct HTTPS to three fixed hosts. No Tend server, SDKs or analytics. Payload contents are locked by the builder and tests. |
| P-3 Cloud AI opt-in and minimised (rewritten) | pass | This ADR is the required ADR. The PO approves it by writing it, and the owner approves it by merging. |
| P-4 Media not persisted | pass | Audio, images and documents are never sent and never stored. There is no background queue. The key is in the Keychain only. The Privacy Manifest and label are updated (Decision 9). |
