// The life cycle of one microphone capture (WI-M2-M3; review PR #42 M1, m1, round 2 M1-r2, m6). FR-A1, P-4.
//
// A plain value with no audio types, so the rules are unit-tested; `MicrophoneAudioSource` keeps one under its lock.
// Phases: `idle` → `starting` → `running` → `stopping` → `idle`, with `stopRequested` for a stop (or a stream
// termination) that arrives while the capture is still starting.
// - **One capture at a time.** `begin` gives a token only in `idle`: while a capture is starting, running **or still
//   being torn down** (`stopping`), a second `audio(in:)` is refused (m6: the old teardown's session deactivation can
//   then never stop a new capture).
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

    /// What `stop()` found.
    enum StopResult: Hashable, Sendable {
        /// Nothing to stop.
        case nothing
        /// The capture was still starting; the start path will finish it.
        case wasStarting
        /// The capture was running; the caller tears down this capture, then calls `finishTeardown`.
        case wasRunning(UInt64)
    }

    private(set) var phase: Phase = .idle
    private var lastToken: UInt64 = 0

    /// A new capture's token, or nil while another capture is starting, running or being torn down.
    mutating func begin() -> UInt64? {
        guard case .idle = phase else { return nil }
        lastToken += 1
        phase = .starting(lastToken)
        return lastToken
    }

    mutating func stop() -> StopResult {
        switch phase {
        case .idle, .stopRequested, .stopping: return .nothing
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
