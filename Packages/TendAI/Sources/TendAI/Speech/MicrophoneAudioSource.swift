// Live microphone audio for one voice capture (WI-M2-M3; plan "Named files": `AVAudioEngine` tap to `AnalyzerInput`,
// in memory only). FR-A1, P-1, P-4.
//
// The input node's tap gives buffers in the hardware format; each is converted to the transcriber's format and passed
// straight on as an `AnalyzerInput`. No buffer is kept after it is passed on, and nothing is written or logged (P-4).
// The audio stops when the stream ends: `stop()` (the person is done speaking) finishes it normally, which is the end
// of the utterance; an engine that cannot start, or a converter error, finishes it with an error.
//
// It needs the microphone permission (`SpeechPermission`), and on iOS an active audio session, which this source sets
// for recording while it runs. Verified on device in DS-1 and DS-2 (the iOS Simulator and a headless Mac test have no
// microphone).

import AVFAudio
import Foundation
import Speech

/// Why the microphone audio stopped by itself.
public enum MicrophoneAudioStop: Error, Hashable, Sendable {
    /// The audio engine could not start (no input, or the session could not be activated).
    case audioNotStarted
    /// A buffer could not be converted to the transcriber's format.
    case conversionStopped
}

public final class MicrophoneAudioSource: CaptureAudioSource, @unchecked Sendable {
    // @unchecked Sendable: `engine` and `continuation` are touched only under `lock`; the tap block reads the
    // converter, which is created before the tap is installed and never changed. Reviewer sign-off needed (skill).
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?

    public init() {}

    public func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.tearDown() }
            do {
                try start(format: format, continuation: continuation)
            } catch {
                continuation.finish(throwing: MicrophoneAudioStop.audioNotStarted)
            }
        }
    }

    /// The person is done speaking: ends the utterance (the stream finishes normally).
    public func stop() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<AnalyzerInput, any Error>.Continuation? in
            let current = self.continuation
            self.continuation = nil
            return current
        }
        tearDown()
        continuation?.finish()
    }

    private func start(format: AVAudioFormat,
                       continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])
        #endif
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hardware, to: format) else {
            throw MicrophoneAudioStop.audioNotStarted
        }
        let ratio = format.sampleRate / hardware.sampleRate
        input.installTap(onBus: 0, bufferSize: 4_096, format: hardware) { buffer, _ in
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                continuation.finish(throwing: MicrophoneAudioStop.conversionStopped)
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
                continuation.finish(throwing: MicrophoneAudioStop.conversionStopped)
                return
            }
            if converted.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        lock.withLock {
            self.engine = engine
            self.continuation = continuation
        }
        engine.prepare()
        try engine.start()
    }

    private func tearDown() {
        let engine = lock.withLock { () -> AVAudioEngine? in
            let current = self.engine
            self.engine = nil
            self.continuation = nil
            return current
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
