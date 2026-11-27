// Live microphone audio for one voice capture (WI-M2-M3; plan "Named files": `AVAudioEngine` tap to `AnalyzerInput`,
// in memory only). FR-A1, P-1, P-4.
//
// The input node's tap gives buffers in the hardware format; each is converted to the transcriber's format and passed
// straight on as an `AnalyzerInput`. No buffer is kept after it is passed on, and nothing is written or logged (P-4).
// - `stop()` (the person is done speaking) ends the utterance: the stream finishes normally. A stop that comes after
//   the capture started but before it asked for audio (while the transcriber is chosen) is kept too: the audio then
//   ends at once, empty, and the microphone is never opened (SP-1 review I-1). A stop (or a stream termination)
//   that comes while the capture is still starting is remembered: the engine is published only after
//   `engine.start()` succeeded, and if a stop came meanwhile the start path stops its own engine at once, so the
//   microphone never keeps running after a stop and no other thread touches an engine that is starting (review PR #42
//   M1, M1-r2).
// - **One capture at a time:** a second `audio(in:)` while one is starting, running or still being torn down finishes
//   at once with `audioNotStarted` and does not touch the first (m1, m6). After the teardown, the source can be used
//   again.
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
    // `engine` and `continuation`, and every read or write of them. The `AVAudioEngine` methods run outside the lock,
    // but one engine is only ever called by one party: the start path creates, prepares and starts it and publishes
    // it in `engine` only after `start()` returned (`markRunning`); if a stop came first, the start path itself stops
    // it and never publishes it. Once published, the engine is taken out of `engine` under the lock exactly once (by
    // `stop()`, the stream's termination or a conversion stop), and only that party stops it. The tap block only reads
    // the converter (made before the tap is installed, never changed) and calls the continuation, which is
    // `Sendable`. The source is idle again only after a teardown has finished (`finishTeardown`), so a new capture
    // never overlaps an old teardown.
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

    /// A capture started (before its transcriber is chosen): a stop from now on ends it (SP-1 review I-1).
    public func captureWillStart() {
        lock.withLock { state.arm() }
    }

    /// The person is done speaking: ends the utterance (the stream finishes normally). While the capture is still
    /// starting, or has not asked for audio yet, the stop is remembered and the capture ends empty.
    public func stop() {
        let result = lock.withLock { state.stop() }
        guard case let .wasRunning(token) = result else { return }
        let continuation = takeContinuation(token)
        tearDown(takeEngine(token), token: token)
        continuation?.finish()
    }

    private func start(token: UInt64, format: AVAudioFormat,
                       continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation) {
        guard lock.withLock({ state.mayActivate(token) }) else {
            // Stopped before anything was activated: an empty utterance.
            _ = takeContinuation(token)
            continuation.finish()
            return
        }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            giveUp(token, continuation, engine: nil, error: .audioNotStarted)
            return
        }
        #endif
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hardware, to: format) else {
            giveUp(token, continuation, engine: nil, error: .audioNotStarted)
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
        do {
            engine.prepare()
            try engine.start()
        } catch {
            giveUp(token, continuation, engine: engine, error: .audioNotStarted)
            return
        }
        // Published only now that it runs (M1-r2). A stop or termination that came during prepare/start is seen here.
        let running = lock.withLock { () -> Bool in
            guard state.markRunning(token) else { return false }
            self.engine = (token, engine)
            return true
        }
        guard running else {
            // The state is `stopping(token)`: this path still owns the engine; stop it and end the utterance.
            _ = takeContinuation(token)
            tearDown(engine, token: token)
            continuation.finish()
            return
        }
    }

    /// The start path could not finish: tear down what it made, then end the stream with `error`.
    private func giveUp(_ token: UInt64, _ continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation,
                        engine: AVAudioEngine?, error: MicrophoneAudioStop) {
        lock.withLock { state.startGaveUp(token) }
        _ = takeContinuation(token)
        tearDown(engine, token: token, sessionActive: true)
        continuation.finish(throwing: error)
    }

    /// The stream of `token` ended (termination): a running capture is torn down here; a starting one is ended by
    /// its start path.
    private func end(_ token: UInt64) {
        let owned = lock.withLock { state.end(token) }
        _ = takeContinuation(token)
        if owned { tearDown(takeEngine(token), token: token) }
    }

    /// Called from the tap thread: the teardown runs on a task, never inside the tap callback (review m2).
    private func conversionStopped(_ token: UInt64) {
        Task { [weak self] in
            guard let self else { return }
            guard self.lock.withLock({ self.state.end(token) }) else { return }
            let continuation = self.takeContinuation(token)
            self.tearDown(self.takeEngine(token), token: token)
            continuation?.finish(throwing: MicrophoneAudioStop.conversionStopped)
        }
    }

    private func takeContinuation(_ token: UInt64) -> AsyncThrowingStream<AnalyzerInput, any Error>.Continuation? {
        lock.withLock {
            guard let stored = self.continuation, stored.token == token else { return nil }
            self.continuation = nil
            return stored.continuation
        }
    }

    /// Takes the published engine of `token` out of the source, once.
    private func takeEngine(_ token: UInt64) -> AVAudioEngine? {
        lock.withLock {
            guard let stored = self.engine, stored.token == token else { return nil }
            self.engine = nil
            return stored.engine
        }
    }

    /// Stops `engine` (if any), sets the iOS session inactive, and only then lets a new capture begin (m6).
    private func tearDown(_ engine: AVAudioEngine?, token: UInt64, sessionActive: Bool = true) {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if engine != nil || sessionActive { Self.deactivateSession() }
        lock.withLock { state.finishTeardown(token) }
    }

    private static func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
