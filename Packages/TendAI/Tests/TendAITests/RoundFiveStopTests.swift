// PR #44 review round 4: m7 (arming must not depend on an earlier capture's phase) and m8 (a capture cancelled during
// the transcriber choice must not ask for audio), plus n5 (the real MicrophoneAudioSource arms). P-4. WI-M2-M3.

import AVFAudio
import Foundation
import Speech
import Testing
@testable import TendAI

@Suite("Speech round 5 (PR #44 review round 4 m7, m8, n5)", .serialized, .timeLimit(.minutes(1)))
struct RoundFiveStopTests {
    private let en = Locale(identifier: "en_US")

    @Test("m7: a second capture armed while the first is still being torn down keeps its stop")
    func armWhileOldCaptureStopping() throws {
        var state = MicrophoneCaptureState()
        let first = state.begin()
        let one = try #require(first)
        _ = state.mayActivate(one)
        _ = state.markRunning(one)
        let stopOne = state.stop()
        #expect(stopOne == .wasRunning(one))         // the first capture's teardown runs now
        state.arm()                                  // the person starts a second capture meanwhile
        let stopTwo = state.stop()                   // and stops it at once
        #expect(stopTwo == .beforeAudio)
        state.finishTeardown(one)                    // the first teardown finishes
        let second = state.begin()                   // the second capture asks for audio
        let two = try #require(second)
        #expect(state.phase == .stopRequested(two))
        let activate = state.mayActivate(two)
        #expect(activate == false)                   // the microphone never opens
        #expect(state.phase == .idle)
    }

    @Test("m7: a second capture armed while the first is still starting or running keeps its stop", arguments: [0, 1])
    func armWhileOldCaptureActive(running: Int) throws {
        var state = MicrophoneCaptureState()
        let first = state.begin()
        let one = try #require(first)
        if running == 1 {
            _ = state.mayActivate(one)
            _ = state.markRunning(one)
        }
        state.arm()
        let result = state.stop()                    // stops the active capture and keeps the stop for the next one
        #expect(result != .nothing)
        // The first capture ends (its start path or its teardown).
        if running == 1 {
            state.finishTeardown(one)
        } else {
            _ = state.mayActivate(one)
            _ = state.markRunning(one)
            state.finishTeardown(one)
        }
        let second = state.begin()
        let two = try #require(second)
        #expect(state.phase == .stopRequested(two))
    }

    @Test("m8: a capture cancelled during the transcriber choice never asks the source for audio")
    func cancelledDuringChoice() async {
        let engine = GatedEngine()
        let source = StateBackedSource()
        let capture = SpeechCapture(engine: engine, locale: en)
        let consumer = Task {
            var count = 0
            for await _ in capture.events(from: source) { count += 1 }
            return count
        }
        try? await Task.sleep(for: .milliseconds(50))
        consumer.cancel()                            // e.g. the screen goes away
        try? await Task.sleep(for: .milliseconds(50))
        await engine.choiceGate.release()
        await engine.formatGate.release()
        _ = await consumer.value
        try? await Task.sleep(for: .milliseconds(200))
        #expect(source.requests == 0)
        #expect(source.micOpened == 0)
    }

    @Test("n5: the real MicrophoneAudioSource keeps a stop given after captureWillStart: its audio ends at once, empty")
    func realSourceArms() async throws {
        let source = MicrophoneAudioSource()
        source.captureWillStart()
        source.stop()
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
                                                interleaved: true))
        var buffers = 0
        var ended: (any Error)?
        do {
            for try await _ in source.audio(in: format) { buffers += 1 }
        } catch {
            ended = error
        }
        #expect(buffers == 0)
        #expect(ended == nil)                        // a normal, empty end: no engine was created
    }
}
