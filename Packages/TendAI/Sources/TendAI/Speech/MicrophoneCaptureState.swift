// The life cycle of one microphone capture (WI-M2-M3 round 2; review PR #42 M1, m1). FR-A1, P-4.
//
// A plain value with no audio types, so the rules are unit-tested; `MicrophoneAudioSource` keeps one under its lock.
// - **One capture at a time.** `begin` gives a token only when no capture is starting or running; a second
//   `audio(in:)` meanwhile is refused (it ends `audioNotStarted`) and never touches the first capture.
// - **Stop is sticky.** A `stop()` while the capture is still starting is remembered. The start path asks
//   `mayActivate` before it activates the audio session and `markRunning` when it stores the engine; after a stop
//   either answer is no, so the microphone never starts after the person stopped.
// - **Teardown is per capture.** `end(token)` is true only for the capture that holds the state, so one stream's
//   termination never stops another capture's engine.

import Foundation

struct MicrophoneCaptureState: Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case idle
        case starting(UInt64)
        case running(UInt64)
        /// `stop()` arrived while this capture was still starting.
        case stopRequested(UInt64)
    }

    /// What `stop()` found.
    enum StopResult: Hashable, Sendable {
        /// Nothing to stop.
        case nothing
        /// The capture was still starting; the start path will finish it without starting the microphone.
        case wasStarting
        /// The capture was running; the caller tears down this capture's engine and ends its stream.
        case wasRunning(UInt64)
    }

    private(set) var phase: Phase = .idle
    private var lastToken: UInt64 = 0

    /// A new capture's token, or nil while another capture is starting or running.
    mutating func begin() -> UInt64? {
        guard case .idle = phase else { return nil }
        lastToken += 1
        phase = .starting(lastToken)
        return lastToken
    }

    mutating func stop() -> StopResult {
        switch phase {
        case .idle, .stopRequested: return .nothing
        case let .starting(token):
            phase = .stopRequested(token)
            return .wasStarting
        case let .running(token):
            phase = .idle
            return .wasRunning(token)
        }
    }

    /// Before the audio session is activated: true while `token` is still starting. After a stop it ends the capture
    /// (the state goes back to idle) and answers false.
    mutating func mayActivate(_ token: UInt64) -> Bool {
        switch phase {
        case .starting(token): return true
        case .stopRequested(token):
            phase = .idle
            return false
        default: return false
        }
    }

    /// When the engine is stored: true (now running) while `token` is still starting. After a stop it ends the
    /// capture and answers false: the caller tears down the engine it just made and ends the stream normally.
    mutating func markRunning(_ token: UInt64) -> Bool {
        switch phase {
        case .starting(token):
            phase = .running(token)
            return true
        case .stopRequested(token):
            phase = .idle
            return false
        default: return false
        }
    }

    /// The stream of `token` ended (its termination, an error, or a start that gave up). True when `token` held the
    /// state, which is then idle; the caller tears down that capture. False for any other token.
    mutating func end(_ token: UInt64) -> Bool {
        switch phase {
        case .starting(token), .running(token), .stopRequested(token):
            phase = .idle
            return true
        default:
            return false
        }
    }
}
