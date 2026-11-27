// The life cycle of one microphone capture (WI-M2-M3; review PR #42 M1, m1, round 2 M1-r2, m6, round 4 m7). FR-A1,
// P-4.
//
// A plain value with no audio types, so the rules are unit-tested; `MicrophoneAudioSource` keeps one under its lock.
// Phases of the capture that holds the source: `idle` → `starting` → `running` → `stopping` → `idle`, with
// `stopRequested` for a stop (or a stream termination) that arrives while it is still starting. Next to the phase, and
// independent of it, `next` records the capture that has started but not yet asked for audio.
// - **A stop before the microphone is asked for is kept (SP-1 review I-1; round 4 m7).** A capture arms the source
//   when it starts (`arm`, from `SpeechCapture.events(from:)`), before the transcriber is chosen. Arming works in every
//   phase, also while an earlier capture is still starting, running or being torn down. A `stop` while armed is kept
//   (`next = .stopped`), and the capture's `begin` then goes straight to `stopRequested`: the session is never
//   activated and the utterance ends empty, the same as a quick stop. The same `stop` also stops an earlier capture
//   that is still active. A stop with nothing armed or active does nothing, and arming clears an old stop, so a stale
//   [Stop] never ends a later capture. `audio(in:)` is meant to be called by `SpeechCapture`, which always arms first.
// - **One capture at a time.** `begin` gives a token only when the phase is `idle`: while a capture is starting,
//   running **or still being torn down** (`stopping`), a second `audio(in:)` is refused (m6: the old teardown's
//   session deactivation can then never stop a new capture).
// - **Only the start path touches the engine until it is running.** The engine is published (`markRunning`) only
//   after `engine.start()` succeeded (M1-r2). A stop or termination during start only sets `stopRequested`; the start
//   path sees it at `mayActivate` (before the session is activated) or at `markRunning` (after the engine started),
//   tears down its own engine and calls `finishTeardown`. So the microphone never keeps running after a stop.
// - **Teardown is per capture and finishes explicitly.** `stop` and `end` hand a running capture's token to one
//   caller, which tears it down and then calls `finishTeardown(token)`; only then is the source idle again.

import Foundation

struct MicrophoneCaptureState: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case idle
        case starting(UInt64)
        case running(UInt64)
        /// A stop or a termination arrived while this capture was still starting.
        case stopRequested(UInt64)
        /// This capture's teardown is running; nothing may start until it finishes.
        case stopping(UInt64)
    }

    /// The capture that has started but not yet asked for audio (round 4 m7: independent of `phase`).
    enum Next: Hashable, Sendable {
        case none
        /// It will ask for audio; the microphone is not asked for yet.
        case armed
        /// The person stopped it before it asked for audio: its audio will end at once, empty.
        case stopped
    }

    /// What `stop()` found.
    enum StopResult: Hashable, Sendable {
        /// Nothing to stop.
        case nothing
        /// The capture had not asked for audio yet; its audio will end at once when it does.
        case beforeAudio
        /// The capture was still starting; the start path will finish it.
        case wasStarting
        /// The capture was running; the caller tears down this capture, then calls `finishTeardown`.
        case wasRunning(UInt64)
    }

    private(set) var phase: Phase = .idle
    private(set) var next: Next = .none
    private var lastToken: UInt64 = 0

    /// A capture has started (before its transcriber is chosen): from now on a stop for it is kept, whatever an
    /// earlier capture is doing. Clears an old stop.
    mutating func arm() {
        next = .armed
    }

    /// A new capture's token, or nil while another capture is starting, running or being torn down. After a stop
    /// while armed, the capture begins already stopped (`stopRequested`), so its start path ends it empty.
    mutating func begin() -> UInt64? {
        let stopped = next == .stopped
        next = .none
        guard case .idle = phase else { return nil }
        lastToken += 1
        phase = stopped ? .stopRequested(lastToken) : .starting(lastToken)
        return lastToken
    }

    /// Stops the capture that is armed (kept for when it asks for audio) and any capture that is active.
    mutating func stop() -> StopResult {
        var result: StopResult = .nothing
        if next == .armed {
            next = .stopped
            result = .beforeAudio
        }
        switch phase {
        case .idle, .stopRequested, .stopping:
            return result
        case let .starting(token):
            phase = .stopRequested(token)
            return .wasStarting
        case let .running(token):
            phase = .stopping(token)
            return .wasRunning(token)
        }
    }

    /// Before the audio session is activated: true while `token` is still starting. After a stop nothing has been
    /// activated, so the capture ends here (idle) and the answer is false.
    mutating func mayActivate(_ token: UInt64) -> Bool {
        switch phase {
        case .starting(token): return true
        case .stopRequested(token):
            phase = .idle
            return false
        default: return false
        }
    }

    /// After `engine.start()` succeeded: true (now running; the engine may be published) while `token` is still
    /// starting. After a stop the answer is false and the phase is `stopping`: the start path tears down its own
    /// engine and session, then calls `finishTeardown`.
    mutating func markRunning(_ token: UInt64) -> Bool {
        switch phase {
        case .starting(token):
            phase = .running(token)
            return true
        case .stopRequested(token):
            phase = .stopping(token)
            return false
        default: return false
        }
    }

    /// The start path gave up before `markRunning` (the session, the converter or the engine could not start): it
    /// tears down what it made, then calls `finishTeardown`.
    mutating func startGaveUp(_ token: UInt64) {
        switch phase {
        case .starting(token), .stopRequested(token): phase = .stopping(token)
        default: break
        }
    }

    /// The stream of `token` ended (its termination, or a conversion stop). True when `token` was running: the
    /// caller tears it down, then calls `finishTeardown`. While it is still starting this acts as a stop (the start
    /// path finishes it) and the answer is false; for any other token it is false.
    mutating func end(_ token: UInt64) -> Bool {
        switch phase {
        case .running(token):
            phase = .stopping(token)
            return true
        case .starting(token):
            phase = .stopRequested(token)
            return false
        default:
            return false
        }
    }

    /// `token`'s teardown is done: the source is idle again.
    mutating func finishTeardown(_ token: UInt64) {
        if case .stopping(token) = phase { phase = .idle }
    }
}
