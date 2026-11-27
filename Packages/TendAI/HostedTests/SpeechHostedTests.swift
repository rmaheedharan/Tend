// The speech adapter inside an iOS app in the iOS 26.5 Simulator (WI-M2-M3, B5). The Simulator has no usable speech
// model (WI-M2-M1: `SpeechTranscriber.isAvailable` is false and dictation offers no audio format), so this proves the
// iOS build of the adapter runs there and ends calmly. Transcription itself is proven on macOS (B4) and on device
// (DS-1, DS-2).

import AVFAudio
import Foundation
import Speech
import Testing
import TendAI

/// A few silent buffers, then the end of the utterance.
struct SilentAudioSource: CaptureAudioSource {
    func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        AsyncThrowingStream { continuation in
            for _ in 0..<3 {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600) else { break }
                buffer.frameLength = 1_600
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            continuation.finish()
        }
    }
}

@Suite("Speech adapter in the iOS Simulator host (WI-M2-M3)")
struct SpeechHostedTests {

    @Test("A voice capture ends with exactly one finished event, last, and no transcript from silence")
    func endsCalmly() async {
        let capture = SpeechCapture(locale: Locale(identifier: "en_US"))
        var events: [SpeechCaptureEvent] = []
        for await event in capture.events(from: SilentAudioSource()) { events.append(event) }
        let finished = events.filter { if case .finished = $0 { true } else { false } }
        #expect(finished.count == 1)
        guard case let .finished(outcome)? = events.last else {
            Issue.record("no finished event: \(events)")
            return
        }
        if case .transcribed = outcome { Issue.record("silence gave a transcript: \(outcome)") }
        if !SpeechTranscriber.isAvailable {
            #expect(await capture.readiness() != .ready(.speechTranscriber))
        }
    }

    @Test("Reading the microphone permission does not ask (no prompt in a test)")
    func permission() {
        let permission = SpeechPermission.microphone()
        #expect([MicrophonePermission.allowed, .notAsked, .notAllowed].contains(permission))
    }
}
