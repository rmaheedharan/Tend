// SP-1 review I-1 (P-4): a stop the person gives after Start but before the adapter asks the source for audio (while
// the transcriber is chosen) must end the capture, and the microphone must never open. WI-M2-M3; AC-M2-11, AC-M2-25.

import AVFAudio
import Foundation
import Speech
import Testing
@testable import TendAI

/// A source with the microphone source's rules (`MicrophoneCaptureState`), minus the hardware: it records whether
/// the "microphone" was ever opened.
final class StateBackedSource: CaptureAudioSource, @unchecked Sendable {
    // @unchecked Sendable: every field is touched only under `lock`. Test target only.
    private let lock = NSLock()
    private var state = MicrophoneCaptureState()
    private var continuation: (UInt64, AsyncThrowingStream<AnalyzerInput, any Error>.Continuation)?
    private(set) var opened = 0
    private(set) var audioRequests = 0

    var phase: MicrophoneCaptureState.Phase { lock.withLock { state.phase } }
    var micOpened: Int { lock.withLock { opened } }
    var requests: Int { lock.withLock { audioRequests } }

    func captureWillStart() { lock.withLock { state.arm() } }

    func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        AsyncThrowingStream { continuation in
            let token: UInt64? = lock.withLock {
                audioRequests += 1
                return state.begin()
            }
            guard let token else {
                continuation.finish(throwing: MicrophoneAudioStop.audioNotStarted)
                return
            }
            let mayOpen = lock.withLock { state.mayActivate(token) }
            guard mayOpen else {
                continuation.finish()   // stopped before the microphone opened: an empty utterance
                return
            }
            let running = lock.withLock { () -> Bool in
                guard state.markRunning(token) else { return false }
                opened += 1
                self.continuation = (token, continuation)
                return true
            }
            guard running else {
                lock.withLock { state.finishTeardown(token) }
                continuation.finish()
                return
            }
        }
    }

    func stop() {
        let result = lock.withLock { state.stop() }
        guard case let .wasRunning(token) = result else { return }
        let continuation = lock.withLock { () -> AsyncThrowingStream<AnalyzerInput, any Error>.Continuation? in
            defer { self.continuation = nil; state.finishTeardown(token) }
            return self.continuation?.1
        }
        continuation?.finish()
    }
}

/// An engine whose choice and format wait on a gate, so a test can stop inside that window.
final class GatedEngine: SpeechEngine, @unchecked Sendable {
    // @unchecked Sendable: the gates are actors; `format` is immutable. Test target only.
    let choiceGate = Gate()
    let formatGate = Gate()
    let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)

    func choice(for locale: Locale, excluding excluded: Set<SpeechTranscriberKind>) async -> TranscriberChoice {
        await choiceGate.wait()
        return .use(.speechTranscriber)
    }

    func audioFormat(for kind: SpeechTranscriberKind, locale: Locale) async -> AVAudioFormat? {
        await formatGate.wait()
        return format
    }

    func transcribe(_ kind: SpeechTranscriberKind, locale: Locale,
                    input: AsyncThrowingStream<AnalyzerInput, any Error>) -> AsyncThrowingStream<TranscriptPiece, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await _ in input {}
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

@Suite("Early stop (SP-1 review I-1; P-4)", .serialized, .timeLimit(.minutes(1)))
struct EarlyStopTests {
    private let en = Locale(identifier: "en_US")

    private func collect(_ events: AsyncStream<SpeechCaptureEvent>) async -> [SpeechCaptureEvent] {
        var all: [SpeechCaptureEvent] = []
        for await event in events { all.append(event) }
        return all
    }

    @Test("A stop before transcriberChosen ends the capture as nothing heard; the microphone never opens")
    func stopBeforeTranscriberChosen() async {
        let engine = GatedEngine()
        let source = StateBackedSource()
        let events = SpeechCapture(engine: engine, locale: en).events(from: source)
        source.stop()                                 // the person tapped Stop at once
        await engine.choiceGate.release()
        await engine.formatGate.release()
        let all = await collect(events)
        #expect(all.last == .finished(.nothingHeard(.speechTranscriber)))
        #expect(source.micOpened == 0)
        #expect(source.phase == .idle)
    }

    @Test("A stop after the transcriber is chosen but before the source is asked for audio still ends it empty")
    func stopBeforeSourceStart() async {
        let engine = GatedEngine()
        let source = StateBackedSource()
        let events = SpeechCapture(engine: engine, locale: en).events(from: source)
        await engine.choiceGate.release()            // chosen; the format is still being read
        try? await Task.sleep(for: .milliseconds(50))
        #expect(source.requests == 0)
        source.stop()
        await engine.formatGate.release()
        let all = await collect(events)
        #expect(all.last == .finished(.nothingHeard(.speechTranscriber)))
        #expect(source.requests == 1)
        #expect(source.micOpened == 0)
    }

    @Test("A stale stop (with no capture started) never ends a later capture")
    func staleStopIgnored() async {
        let engine = GatedEngine()
        let source = StateBackedSource()
        source.stop()                                 // nothing running: ignored
        let events = SpeechCapture(engine: engine, locale: en).events(from: source)
        await engine.choiceGate.release()
        await engine.formatGate.release()
        for _ in 0..<500 where source.micOpened == 0 { await Task.yield() }
        #expect(source.micOpened == 1)                // the new capture opened the microphone
        source.stop()                                 // the real stop ends it
        let all = await collect(events)
        #expect(all.last == .finished(.nothingHeard(.speechTranscriber)))
        #expect(source.phase == .idle)
    }

    @Test("State: arm then stop makes the next begin start already stopped; arming again clears it")
    func stateRules() throws {
        var state = MicrophoneCaptureState()
        state.arm()
        let stopped = state.stop()
        #expect(stopped == .beforeAudio)
        let begun = state.begin()
        let token = try #require(begun)
        #expect(state.phase == .stopRequested(token))
        let activate = state.mayActivate(token)
        #expect(activate == false)
        #expect(state.phase == .idle)
        // A stop with nothing armed does nothing; arming clears an old stop.
        let idleStop = state.stop()
        #expect(idleStop == .nothing)
        state.arm()
        _ = state.stop()
        state.arm()
        let fresh = state.begin()
        let next = try #require(fresh)
        #expect(state.phase == .starting(next))
    }
}
