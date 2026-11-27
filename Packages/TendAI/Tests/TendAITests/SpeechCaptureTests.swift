// The speech adapter over a scripted engine and a fake audio source (WI-M2-M3; AC-M2-09 Rule 5 support, AC-M2-11 and
// AC-M2-25 Mac halves: the transcriber used is reported; the brain-dump input is the final transcript). P-1, P-4.

import AVFAudio
import Foundation
import Speech
import Testing
@testable import TendAI
import TendIngestion

/// A scripted transcriber: its choice, its format, and the pieces it gives once the audio has ended.
struct ScriptedEngine: SpeechEngine {
    var chosen: TranscriberChoice = .use(.speechTranscriber)
    var format: AVAudioFormat? = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
                                               interleaved: true)
    /// Pieces given while the audio runs (one per audio buffer received, in order), then after it ends.
    var whileAudio: [TranscriptPiece] = []
    var atEnd: [TranscriptPiece] = []
    var failAtEnd = false
    let log = EngineLog()

    func choice(for locale: Locale) async -> TranscriberChoice { chosen }
    func audioFormat(for kind: SpeechTranscriberKind, locale: Locale) async -> AVAudioFormat? { format }

    func transcribe(_ kind: SpeechTranscriberKind, locale: Locale,
                    input: AsyncThrowingStream<AnalyzerInput, any Error>) -> AsyncThrowingStream<TranscriptPiece, any Error> {
        let script = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                var index = 0
                do {
                    for try await _ in input {
                        await script.log.received()
                        if index < script.whileAudio.count { continuation.yield(script.whileAudio[index]) }
                        index += 1
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                for piece in script.atEnd { continuation.yield(piece) }
                if script.failAtEnd {
                    continuation.finish(throwing: SpeechEngineStop.localeGone)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await script.log.terminated() }
            }
        }
    }
}

actor EngineLog {
    private(set) var buffers = 0
    private(set) var terminations = 0
    func received() { buffers += 1 }
    func terminated() { terminations += 1 }
}

/// A fake audio source: a number of silent buffers in the format asked for, then the end of the utterance (or an
/// interruption, or it waits until stopped).
struct FakeAudioSource: CaptureAudioSource {
    enum Ending: Sendable { case endOfUtterance, interruption, waitForStop }
    var buffers = 3
    var ending: Ending = .endOfUtterance
    let log = AudioLog()

    struct Interrupted: Error {}

    func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error> {
        let source = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                await source.log.started(format)
                for _ in 0..<source.buffers {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160) else { break }
                    buffer.frameLength = 160
                    continuation.yield(AnalyzerInput(buffer: buffer))
                }
                switch source.ending {
                case .endOfUtterance: continuation.finish()
                case .interruption: continuation.finish(throwing: Interrupted())
                case .waitForStop: while !Task.isCancelled { await Task.yield() }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await source.log.stopped() }
            }
        }
    }
}

actor AudioLog {
    private(set) var formats: [AVAudioFormat] = []
    private(set) var stops = 0
    func started(_ format: AVAudioFormat) { formats.append(format) }
    func stopped() { stops += 1 }
}

private func collect(_ capture: SpeechCapture, _ source: some CaptureAudioSource) async -> [SpeechCaptureEvent] {
    var events: [SpeechCaptureEvent] = []
    for await event in capture.events(from: source) { events.append(event) }
    return events
}

private let en = Locale(identifier: "en_US")

@Suite("Speech capture (WI-M2-M3; AC-M2-11, AC-M2-25 Mac half)")
struct SpeechCaptureTests {

    @Test("The final transcript is the final results joined; volatile text is reported for display only")
    func finalTranscript() async {
        let engine = ScriptedEngine(
            whileAudio: [TranscriptPiece(text: "we're almost", isFinal: false),
                         TranscriptPiece(text: "We're almost out of dishwasher pods,", isFinal: true),
                         TranscriptPiece(text: "and the A", isFinal: false)],
            atEnd: [TranscriptPiece(text: " and the AC needs servicing. ", isFinal: true)])
        let events = await collect(SpeechCapture(engine: engine, locale: en), FakeAudioSource())
        #expect(events == [
            .transcriberChosen(.speechTranscriber),
            .textSoFar("we're almost"),
            .textSoFar("We're almost out of dishwasher pods,"),
            .textSoFar("We're almost out of dishwasher pods, and the A"),
            .textSoFar("We're almost out of dishwasher pods, and the AC needs servicing."),
            .finished(.transcribed(FinalTranscript(text: "We're almost out of dishwasher pods, and the AC needs servicing.",
                                                   transcriber: .speechTranscriber))),
        ])
    }

    @Test("AC-M2-25: the transcriber used is reported, for both transcribers",
          arguments: SpeechTranscriberKind.allCases)
    func reportsTranscriber(kind: SpeechTranscriberKind) async {
        let engine = ScriptedEngine(chosen: .use(kind), atEnd: [TranscriptPiece(text: "Mop the floor", isFinal: true)])
        let events = await collect(SpeechCapture(engine: engine, locale: en), FakeAudioSource())
        #expect(events.first == .transcriberChosen(kind))
        #expect(events.last == .finished(.transcribed(FinalTranscript(text: "Mop the floor", transcriber: kind))))
    }

    @Test("The audio is asked for in the transcriber's format, and every buffer reaches the transcriber")
    func audioFormatAndBuffers() async throws {
        let engine = ScriptedEngine(atEnd: [TranscriptPiece(text: "x", isFinal: true)])
        let source = FakeAudioSource(buffers: 5)
        _ = await collect(SpeechCapture(engine: engine, locale: en), source)
        let format = try #require(engine.format)
        #expect(await source.log.formats == [format])
        #expect(await engine.log.buffers == 5)
    }

    @Test("Audio with no words ends with nothingHeard and no transcript")
    func nothingHeard() async {
        let engine = ScriptedEngine(atEnd: [TranscriptPiece(text: "  ", isFinal: true)])
        let events = await collect(SpeechCapture(engine: engine, locale: en), FakeAudioSource())
        #expect(events.last == .finished(.nothingHeard(.speechTranscriber)))
    }

    @Test("No usable transcriber: the capture ends unavailable before asking for audio",
          arguments: SpeechUnavailableReason.allCases)
    func unavailable(reason: SpeechUnavailableReason) async {
        var engine = ScriptedEngine(chosen: reason == .audioFormatUnavailable ? .use(.dictationTranscriber)
                                        : .unavailable(reason))
        if reason == .audioFormatUnavailable { engine.format = nil }
        let source = FakeAudioSource()
        let events = await collect(SpeechCapture(engine: engine, locale: en), source)
        #expect(events == [.finished(.unavailable(reason))])
        #expect(await source.log.formats.isEmpty)
    }

    @Test("Audio that stops by itself ends with stopped(audioInterrupted); no transcript is returned")
    func audioInterrupted() async {
        let engine = ScriptedEngine(whileAudio: [TranscriptPiece(text: "Buy", isFinal: true)])
        let events = await collect(SpeechCapture(engine: engine, locale: en), FakeAudioSource(ending: .interruption))
        #expect(events.last == .finished(.stopped(.audioInterrupted)))
        #expect(!events.contains { if case .finished(.transcribed) = $0 { true } else { false } })
    }

    @Test("A transcriber error ends with stopped(transcriptionStopped)")
    func transcriberStops() async {
        let engine = ScriptedEngine(atEnd: [TranscriptPiece(text: "Buy pods", isFinal: true)], failAtEnd: true)
        let events = await collect(SpeechCapture(engine: engine, locale: en), FakeAudioSource())
        #expect(events.last == .finished(.stopped(.transcriptionStopped)))
    }

    @Test("Cancelling the consumer ends the events with no transcript and stops both the audio and the transcriber")
    func cancellation() async {
        let engine = ScriptedEngine(whileAudio: [TranscriptPiece(text: "Buy pods", isFinal: true)])
        let source = FakeAudioSource(buffers: 1, ending: .waitForStop)
        let capture = SpeechCapture(engine: engine, locale: en)
        let task = Task {
            var events: [SpeechCaptureEvent] = []
            for await event in capture.events(from: source) {
                events.append(event)
                if case .textSoFar = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return events
        }
        let events = await task.value
        #expect(events == [.transcriberChosen(.speechTranscriber), .textSoFar("Buy pods")])
        for _ in 0..<500 {
            if await source.log.stops > 0, await engine.log.terminations > 0 { break }
            await Task.yield()
        }
        #expect(await source.log.stops == 1)
        #expect(await engine.log.terminations == 1)
    }

    @Test("A capture started inside a cancelled task asks for no audio")
    func startedCancelled() async {
        let source = FakeAudioSource()
        let capture = SpeechCapture(engine: ScriptedEngine(), locale: en)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await collect(capture, source)
        }
        #expect(await task.value == [.finished(.cancelled)])
        #expect(await source.log.formats.isEmpty)
    }

    @Test("Readiness reports the chosen transcriber or the reason")
    func readiness() async {
        #expect(await SpeechCapture(engine: ScriptedEngine(chosen: .use(.dictationTranscriber)), locale: en).readiness()
                == .ready(.dictationTranscriber))
        #expect(await SpeechCapture(engine: ScriptedEngine(chosen: .unavailable(.languageNotSupported)), locale: en)
            .readiness() == .unavailable(.languageNotSupported))
    }
}

@Suite("Transcriber choice (WI-M2-M3; plan: SpeechTranscriber, falling back to DictationTranscriber)")
struct TranscriberChoiceTests {
    static func status(_ bits: Int) -> TranscriberStatus {
        TranscriberStatus(isAvailable: bits & 1 != 0, supportsLocale: bits & 2 != 0, assetsInstalled: bits & 4 != 0)
    }

    @Test("Every combination of the two transcribers' states gives the plan's choice (64 cases, independent table)")
    func everyCombination() {
        var seen: Set<TranscriberChoice> = []
        for s in 0..<8 {
            for d in 0..<8 {
                let speech = Self.status(s), dictation = Self.status(d)
                let speechUsable = speech.isAvailable && speech.supportsLocale && speech.assetsInstalled
                let dictationUsable = dictation.isAvailable && dictation.supportsLocale && dictation.assetsInstalled
                let anyLanguage = (speech.isAvailable && speech.supportsLocale)
                    || (dictation.isAvailable && dictation.supportsLocale)
                let expected: TranscriberChoice = speechUsable ? .use(.speechTranscriber)
                    : dictationUsable ? .use(.dictationTranscriber)
                    : anyLanguage ? .unavailable(.assetsNotInstalled) : .unavailable(.languageNotSupported)
                let got = TranscriberChoice.choose(speech: speech, dictation: dictation)
                #expect(got == expected, "speech \(speech) dictation \(dictation)")
                seen.insert(got)
            }
        }
        #expect(seen == [.use(.speechTranscriber), .use(.dictationTranscriber), .unavailable(.assetsNotInstalled),
                         .unavailable(.languageNotSupported)])
    }

    @Test("SpeechTranscriber wins whenever it is usable; dictation is only the fallback")
    func preference() {
        let ready = TranscriberStatus(isAvailable: true, supportsLocale: true, assetsInstalled: true)
        let noAssets = TranscriberStatus(isAvailable: true, supportsLocale: true, assetsInstalled: false)
        let notOnDevice = TranscriberStatus(isAvailable: false, supportsLocale: true, assetsInstalled: true)
        #expect(TranscriberChoice.choose(speech: ready, dictation: ready) == .use(.speechTranscriber))
        #expect(TranscriberChoice.choose(speech: noAssets, dictation: ready) == .use(.dictationTranscriber))
        #expect(TranscriberChoice.choose(speech: notOnDevice, dictation: ready) == .use(.dictationTranscriber))
    }

    @Test("Joining final results trims each piece and drops empty ones")
    func join() {
        #expect(TranscriptText.join([" a ", "", "b\n", "  "]) == "a b")
        #expect(TranscriptText.join([]) == "")
    }
}

@Suite("Speech names are calm (AC-M2-12)")
struct SpeechNamesTests {
    @Test("No speech outcome or reason name holds a banned token")
    func calm() {
        let names = SpeechUnavailableReason.allCases.map { "\($0)" } + SpeechStopReason.allCases.map { "\($0)" }
            + SpeechTranscriberKind.allCases.map(\.rawValue)
            + ["transcribed", "nothingHeard", "unavailable", "stopped", "cancelled", "transcriberChosen", "textSoFar"]
        for name in names {
            #expect(!BannedTokens.containsBannedToken(name), "\(name)")
            // Source-code names are matched as AC-M1-02 does (a case-insensitive substring of the identifier).
            #expect(!BannedTokens.all.contains { name.lowercased().contains($0) }, "\(name)")
        }
    }
}
