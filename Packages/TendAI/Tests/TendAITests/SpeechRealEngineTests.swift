// The real `SpeechAnalyzer` engine on macOS (WI-M2-M3, B4). The audio is a sentence synthesised by the system `say`
// tool into a temporary file, read back and fed to the analyzer as buffers through a test-only audio source; nothing
// is recorded from a microphone and the file is deleted after the test. This is the macOS half only: the iOS 26.5
// Simulator has no usable speech model (WI-M2-M1, R-8), and DS-1 / DS-2 run the live microphone path on device.
// Precondition (as in MS-1): the en-US speech assets are installed on the Mac.

import AVFAudio
import Foundation
import Speech
import Testing
@testable import TendAI
import TendIngestion

/// Audio from a file, converted to the analyzer's format, then the end of the utterance. Test target only.
struct FileAudioSource: CaptureAudioSource {
    let url: URL

    func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        let url = url
        return AsyncThrowingStream { continuation in
            do {
                let file = try AVAudioFile(forReading: url)
                let source = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                          frameCapacity: AVAudioFrameCount(file.length)))
                try file.read(into: source)
                let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))
                let ratio = format.sampleRate / file.processingFormat.sampleRate
                let out = try #require(AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1_024))
                nonisolated(unsafe) var given = false
                var error: NSError?
                converter.convert(to: out, error: &error) { _, status in
                    if given { status.pointee = .endOfStream; return nil }
                    given = true
                    status.pointee = .haveData
                    return source
                }
                if let error { throw error }
                continuation.yield(AnalyzerInput(buffer: out))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

enum SpokenFixture {
    static let sentence = "We are almost out of dishwasher pods, and the AC needs servicing before summer."

    /// Synthesises `sentence` with the system voice into a temporary 16 kHz file.
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tend-speech-\(UUID().uuidString).wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--data-format=LEI16@16000", sentence]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0)
        return url
    }

    static func words(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

@Suite("Speech, real engine on macOS (WI-M2-M3; AC-M2-25 Mac half)", .serialized)
struct SpeechRealEngineTests {
    let en = Locale(identifier: "en_US")

    @Test("On this Mac the capture chooses SpeechTranscriber and transcribes the sentence on device")
    func speechTranscriber() async throws {
        let url = try SpokenFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let capture = SpeechCapture(locale: en)
        #expect(await capture.readiness() == .ready(.speechTranscriber))
        var events: [SpeechCaptureEvent] = []
        for await event in capture.events(from: FileAudioSource(url: url)) { events.append(event) }
        #expect(events.first == .transcriberChosen(.speechTranscriber))
        guard case let .finished(.transcribed(transcript))? = events.last else {
            Issue.record("expected a transcript, got \(events)")
            return
        }
        #expect(transcript.transcriber == .speechTranscriber)
        let words = SpokenFixture.words(transcript.text)
        #expect(words.contains("dishwasher pods"))
        #expect(words.contains("before summer"))
    }

    @Test("The DictationTranscriber fallback also transcribes the sentence on device")
    func dictationTranscriber() async throws {
        let url = try SpokenFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = SpeechAnalyzerEngine()
        let format = try #require(await engine.audioFormat(for: .dictationTranscriber, locale: en))
        var finals: [String] = []
        for try await piece in engine.transcribe(.dictationTranscriber, locale: en,
                                                 input: FileAudioSource(url: url).audio(in: format))
        where piece.isFinal {
            finals.append(piece.text)
        }
        let words = SpokenFixture.words(TranscriptText.join(finals))
        #expect(words.contains("dishwasher pods"))
        #expect(words.contains("before summer"))
    }
}
