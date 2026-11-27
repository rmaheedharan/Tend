// Live microphone audio for one voice capture (WI-M2-M3; plan "Named files": `AVAudioEngine` tap to `AnalyzerInput`,
// in memory only). FR-A1, P-1, P-4.
//
// The input node's tap gives buffers in the hardware format; each is converted to the transcriber's format and passed
// straight on as an `AnalyzerInput`. No buffer is kept after it is passed on, and nothing is written or logged (P-4).
// - `stop()` (the person is done speaking) ends the utterance: the stream finishes normally. A stop that comes while
//   the capture is still starting is remembered, so the microphone never starts after it (review PR #42 M1).
// - **One capture at a time:** a second `audio(in:)` while one is starting or running finishes at once with
//   `audioNotStarted` and does not touch the first. After a capture ends, the source can be used again.
// - An engine that cannot start, or a converter that cannot be made, finishes the stream with `audioNotStarted`; on
//   iOS the audio session is set inactive again on every such exit (review m2). A buffer that cannot be converted
//   finishes it with `conversionStopped`; the teardown then runs on a task, never inside the tap callback.
//
// It needs the microphone permission (`SpeechPermission`), and on iOS an active audio session, which this source sets
// for recording while it runs. Verified on device in DS-1 and DS-2 (a headless Mac test and the Simulator have no
// microphone to drive); the state rules are unit-tested in `MicrophoneCaptureState`.

import AVFAudio
import Foundation
import Speech

/// Why the microphone audio stopped by itself.
public enum MicrophoneAudioStop: Error, Hashable, Sendable {
    /// The audio engine could not start (no input, the session could not be activated, or another capture is active).
    case audioNotStarted
    /// A buffer could not be converted to the transcriber's format.
    case conversionStopped
}

public final class MicrophoneAudioSource: CaptureAudioSource, @unchecked Sendable {
    // @unchecked Sendable (Reviewer sign-off needed, skill rule): `lock` guards the three stored fields, `state`,
    // `engine` and `continuation`, and every read or write of them. The `AVAudioEngine` methods (`prepare`, `start`,
    // `removeTap`, `stop`) run outside the lock, but only by the one party that owns the capture's token at that
    // moment: the start path until `markRunning` succeeds, then whoever takes the engine out of `engine` under the lock
    // (`stop()`, the stream's termination, or a conversion stop), which happens once. So no two threads ever call one
    // engine at the same time. The tap block only reads the converter (made before the tap is installed, never
    // changed) and calls the continuation, which is `Sendable`.
    private let lock = NSLock()
    private var state = MicrophoneCaptureState()
    private var engine: (token: UInt64, engine: AVAudioEngine)?
    private var continuation: (token: UInt64, continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation)?

    public init() {}

    public func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        AsyncThrowingStream { continuation in
            guard let token = lock.withLock({ state.begin() }) else {
                continuation.finish(throwing: MicrophoneAudioStop.audioNotStarted)
                return
            }
            lock.withLock { self.continuation = (token, continuation) }
            continuation.onTermination = { [weak self] _ in self?.end(token) }
            start(token: token, format: format, continuation: continuation)
        }
    }

    /// The person is done speaking: ends the utterance (the stream finishes normally). Before the capture has started,
    /// it is remembered and the microphone never starts.
    public func stop() {
        let (result, continuation) = lock.withLock { () -> (MicrophoneCaptureState.StopResult,
                                                            AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?) in
            let result = state.stop()
            guard case .wasRunning = result else { return (result, nil) }
            let current = self.continuation?.continuation
            self.continuation = nil
            return (result, current)
        }
        if case let .wasRunning(token) = result {
            tearDown(takeEngine(token))
            continuation?.finish()
        }
    }

    private func start(token: UInt64, format: AVAudioFormat,
                       continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation) {
        guard lock.withLock({ state.mayActivate(token) }) else {
            // Stopped while starting: an empty utterance, and nothing was activated.
            finishStart(token, continuation, error: nil, sessionActive: false)
            return
        }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            finishStart(token, continuation, error: .audioNotStarted, sessionActive: true)
            return
        }
        #endif
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hardware, to: format) else {
            finishStart(token, continuation, error: .audioNotStarted, sessionActive: true)
            return
        }
        let ratio = format.sampleRate / hardware.sampleRate
        input.installTap(onBus: 0, bufferSize: 4_096, format: hardware) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                self?.conversionStopped(token)
                return
            }
            var given = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if given {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                given = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if status == .error || error != nil {
                self?.conversionStopped(token)
                return
            }
            if converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        let running = lock.withLock { () -> Bool in
            guard state.markRunning(token) else { return false }
            self.engine = (token, engine)
            return true
        }
        guard running else {
            // Stopped while the engine was being made: remove the tap, never start it.
            input.removeTap(onBus: 0)
            finishStart(token, continuation, error: nil, sessionActive: true)
            return
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            _ = lock.withLock { state.end(token) }
            tearDown(takeEngine(token))
            continuation.finish(throwing: MicrophoneAudioStop.audioNotStarted)
        }
    }

    /// Ends a capture that never ran: the state is released, the iOS session set inactive if it was activated, and
    /// the stream finished (normally after a stop, else with `error`).
    private func finishStart(_ token: UInt64, _ continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation,
                             error: MicrophoneAudioStop?, sessionActive: Bool) {
        lock.withLock {
            _ = state.end(token)
            if self.continuation?.token == token { self.continuation = nil }
        }
        if sessionActive { Self.deactivateSession() }
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }

    /// The stream of `token` ended (termination): tear down that capture only.
    private func end(_ token: UInt64) {
        let owned = lock.withLock { () -> Bool in
            let owned = state.end(token)
            if self.continuation?.token == token { self.continuation = nil }
            return owned
        }
        if owned { tearDown(takeEngine(token)) }
    }

    /// Called from the tap thread: the teardown runs on a task, not inside the tap callback (review m2).
    private func conversionStopped(_ token: UInt64) {
        Task { [weak self] in
            guard let self else { return }
            let continuation = self.lock.withLock { () -> AsyncThrowingStream<AnalyzerInput, any Error>.Continuation? in
                guard self.state.end(token), self.continuation?.token == token else { return nil }
                let current = self.continuation?.continuation
                self.continuation = nil
                return current
            }
            guard let continuation else { return }
            self.tearDown(self.takeEngine(token))
            continuation.finish(throwing: MicrophoneAudioStop.conversionStopped)
        }
    }

    /// Takes the engine of `token` out of the source, once.
    private func takeEngine(_ token: UInt64) -> AVAudioEngine? {
        lock.withLock {
            guard let stored = self.engine, stored.token == token else { return nil }
            self.engine = nil
            return stored.engine
        }
    }

    private func tearDown(_ engine: AVAudioEngine?) {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        Self.deactivateSession()
    }

    private static func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
