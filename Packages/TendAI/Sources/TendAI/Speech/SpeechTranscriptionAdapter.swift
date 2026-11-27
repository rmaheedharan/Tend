// The on-device speech adapter (WI-M2-M3; brief Definitions "Brain-dump input", "Time to first item"; AC-M2-09 Rules 2
// and 5, AC-M2-11, AC-M2-25; plan "Named files"). FR-A1, P-1, P-4, UX-3.
//
// - **On device only (P-1, Rule 5).** Speech runs through `SpeechAnalyzer` with `SpeechTranscriber`, falling back to
//   `DictationTranscriber`. Their modules send no audio to Apple's servers. No server-capable recogniser is used, and
//   no speech-recognition authorization is asked for (T-27, WI-M2-M1): only the microphone permission
//   (`SpeechPermission.swift`).
// - **Which transcriber (AC-M2-25).** `SpeechTranscriber` when it is available on this device, supports the locale and
//   its assets are installed; otherwise `DictationTranscriber` when it supports the locale and its assets are
//   installed; otherwise the capture is unavailable, with a neutral reason. The transcriber used is reported.
// - **The brain-dump input is the final transcript** (brief Definitions): the transcriber's final results, joined, once
//   the audio has ended. Volatile (in-progress) text is reported for display only. The moment the final transcript is
//   reported is the end of speech for TTFI (brief Definitions "Time to first item").
// - **In memory only (P-4).** Audio buffers go from the audio source straight into the analyzer and are never kept,
//   written or logged; transcripts are returned, never stored. Media types appear only in this file and in
//   `MicrophoneAudioSource.swift` (Rule 2).
// - Every outcome and reason name passes the banned-token rule and names the situation, never the person.

import AVFAudio
import Foundation
import Speech

/// The transcriber that produced a transcript (recorded per voice input, AC-M2-25).
public enum SpeechTranscriberKind: String, CaseIterable, Hashable, Sendable {
    case speechTranscriber
    case dictationTranscriber
}

/// Why a voice capture cannot run on this device now.
public enum SpeechUnavailableReason: CaseIterable, Hashable, Sendable {
    /// Neither transcriber supports the capture's language.
    case languageNotSupported
    /// The speech assets for the language are not on the device yet (`SpeechCapture.prepareAssets()`).
    case assetsNotInstalled
    /// The transcriber offers no audio format this device can give it.
    case audioFormatUnavailable
}

/// Whether a voice capture can run now.
public enum SpeechReadiness: Hashable, Sendable {
    case ready(SpeechTranscriberKind)
    case unavailable(SpeechUnavailableReason)
}

/// Why a voice capture stopped before its final transcript.
public enum SpeechStopReason: CaseIterable, Hashable, Sendable {
    /// The microphone or the audio session stopped giving audio.
    case audioInterrupted
    /// The transcriber stopped with an error.
    case transcriptionStopped
}

/// The transcript of one finished utterance: the brain-dump input (brief Definitions).
public struct FinalTranscript: Hashable, Sendable {
    public let text: String
    public let transcriber: SpeechTranscriberKind

    public init(text: String, transcriber: SpeechTranscriberKind) {
        self.text = text
        self.transcriber = transcriber
    }
}

/// How a voice capture ended. Exactly one per capture, last.
public enum SpeechCaptureOutcome: Hashable, Sendable {
    /// The audio ended and the final transcript is ready (the end of speech for TTFI).
    case transcribed(FinalTranscript)
    /// The audio ended with no words in it.
    case nothingHeard(SpeechTranscriberKind)
    /// The capture could not start.
    case unavailable(SpeechUnavailableReason)
    /// The capture stopped before its final transcript.
    case stopped(SpeechStopReason)
    /// The caller cancelled the capture.
    case cancelled
}

/// The events of one voice capture. The sequence never throws. `finished` comes exactly once, last, except when the
/// consuming task itself is cancelled: then the sequence simply ends (an `AsyncStream` returns nil to a cancelled
/// consumer), and the audio and the transcriber are stopped.
public enum SpeechCaptureEvent: Hashable, Sendable {
    /// The transcriber chosen for this capture (before any text).
    case transcriberChosen(SpeechTranscriberKind)
    /// The text so far, final results followed by the volatile one (display only, never stored).
    case textSoFar(String)
    case finished(SpeechCaptureOutcome)
}

/// Live audio for one capture.
public protocol CaptureAudioSource: Sendable {
    /// Starts the audio, converted to `format`. The stream finishes when the person stops (the end of the utterance)
    /// and throws if the audio stops by itself. Its termination stops the audio.
    func audio(in format: AVAudioFormat) -> AsyncThrowingStream<AnalyzerInput, any Error>
}

// MARK: - The choice of transcriber (pure; tested)

/// What one transcriber can do for a locale on this device.
struct TranscriberStatus: Hashable, Sendable {
    /// The module is usable on this device at all (`SpeechTranscriber.isAvailable`; always true for dictation).
    var isAvailable: Bool
    /// The transcriber supports an equivalent of the locale.
    var supportsLocale: Bool
    /// Its assets for the locale are installed.
    var assetsInstalled: Bool
}

enum TranscriberChoice: Hashable, Sendable {
    case use(SpeechTranscriberKind)
    case unavailable(SpeechUnavailableReason)

    /// The choice when `excluded` transcribers are not usable (a transcriber with no audio format, review PR #42 m4).
    static func choose(speech: TranscriberStatus, dictation: TranscriberStatus,
                       excluding excluded: Set<SpeechTranscriberKind>) -> TranscriberChoice {
        var speech = speech, dictation = dictation
        if excluded.contains(.speechTranscriber) { speech.assetsInstalled = false; speech.isAvailable = false }
        if excluded.contains(.dictationTranscriber) { dictation.assetsInstalled = false; dictation.isAvailable = false }
        return choose(speech: speech, dictation: dictation)
    }

    static func choose(speech: TranscriberStatus, dictation: TranscriberStatus) -> TranscriberChoice {
        if speech.isAvailable && speech.supportsLocale && speech.assetsInstalled { return .use(.speechTranscriber) }
        if dictation.isAvailable && dictation.supportsLocale && dictation.assetsInstalled {
            return .use(.dictationTranscriber)
        }
        let anyLocale = (speech.isAvailable && speech.supportsLocale) || (dictation.isAvailable && dictation.supportsLocale)
        return .unavailable(anyLocale ? .assetsNotInstalled : .languageNotSupported)
    }
}

// MARK: - The transcriber behind a protocol (the real one below; scripted ones in the tests)

/// One result from a transcriber.
struct TranscriptPiece: Hashable, Sendable {
    var text: String
    var isFinal: Bool
}

protocol SpeechEngine: Sendable {
    /// Which transcriber this capture uses, or why none can, leaving out `excluded` (ones with no audio format).
    func choice(for locale: Locale, excluding excluded: Set<SpeechTranscriberKind>) async -> TranscriberChoice
    /// The audio format the transcriber takes, or nil.
    func audioFormat(for kind: SpeechTranscriberKind, locale: Locale) async -> AVAudioFormat?
    /// Transcribes `input` until it ends, then finalizes. Ends normally after the last final result, or throws.
    /// Its termination cancels the analysis.
    func transcribe(_ kind: SpeechTranscriberKind, locale: Locale,
                    input: AsyncThrowingStream<AnalyzerInput, any Error>) -> AsyncThrowingStream<TranscriptPiece, any Error>
}

// MARK: - The capture

/// Voice capture for brain-dumps.
public struct SpeechCapture: Sendable {
    let engine: any SpeechEngine
    let locale: Locale

    /// - Parameter locale: the capture language (the device locale in the app).
    public init(locale: Locale = .current) {
        self.init(engine: SpeechAnalyzerEngine(), locale: locale)
    }

    init(engine: any SpeechEngine, locale: Locale) {
        self.engine = engine
        self.locale = locale
    }

    /// Which transcriber a capture would use now, or why none can (the eval's preconditions; M3's capture screen).
    public func readiness() async -> SpeechReadiness {
        switch await engine.choice(for: locale, excluding: []) {
        case let .use(kind): .ready(kind)
        case let .unavailable(reason): .unavailable(reason)
        }
    }

    /// The events of one capture from `source`.
    public func events(from source: some CaptureAudioSource) -> AsyncStream<SpeechCaptureEvent> {
        let engine = engine
        let locale = locale
        return AsyncStream { continuation in
            guard !Task.isCancelled else {
                continuation.yield(.finished(.cancelled))
                continuation.finish()
                return
            }
            let task = Task {
                let outcome = await Self.run(engine: engine, locale: locale, source: source) { event in
                    continuation.yield(event)
                }
                continuation.yield(.finished(Task.isCancelled ? .cancelled : outcome))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(engine: any SpeechEngine, locale: Locale, source: some CaptureAudioSource,
                            emit: (SpeechCaptureEvent) -> Void) async -> SpeechCaptureOutcome {
        // SpeechTranscriber first, then DictationTranscriber; a transcriber with no audio format on this device is
        // left out and the next one tried (review PR #42 m4). The one used is reported.
        var excluded: Set<SpeechTranscriberKind> = []
        var picked: (kind: SpeechTranscriberKind, format: AVAudioFormat)?
        while picked == nil {
            switch await engine.choice(for: locale, excluding: excluded) {
            case let .use(kind):
                if let format = await engine.audioFormat(for: kind, locale: locale) {
                    picked = (kind, format)
                } else {
                    excluded.insert(kind)
                }
            case let .unavailable(reason):
                return excluded.isEmpty ? .unavailable(reason) : .unavailable(.audioFormatUnavailable)
            }
        }
        guard let (kind, format) = picked else { return .unavailable(.audioFormatUnavailable) }
        emit(.transcriberChosen(kind))
        let audio = AudioEndWatch(source.audio(in: format))
        var finals: [String] = []
        do {
            for try await piece in engine.transcribe(kind, locale: locale, input: audio.stream) {
                if piece.isFinal {
                    finals.append(piece.text)
                    emit(.textSoFar(TranscriptText.join(finals)))
                } else {
                    emit(.textSoFar(TranscriptText.join(finals + [piece.text])))
                }
            }
        } catch {
            if Task.isCancelled { return .cancelled }
            return await audio.didThrow ? .stopped(.audioInterrupted) : .stopped(.transcriptionStopped)
        }
        if Task.isCancelled { return .cancelled }
        if await audio.didThrow { return .stopped(.audioInterrupted) }
        let text = TranscriptText.join(finals)
        return text.isEmpty ? .nothingHeard(kind) : .transcribed(FinalTranscript(text: text, transcriber: kind))
    }
}

/// Joins final results into one transcript: each piece trimmed, empty pieces dropped, one space between.
enum TranscriptText {
    static func join(_ pieces: [String]) -> String {
        pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Passes the audio through and remembers whether it ended with an error (the audio stopped by itself).
final class AudioEndWatch: Sendable {
    let stream: AsyncThrowingStream<AnalyzerInput, any Error>
    private let state = AudioEndState()

    init(_ source: AsyncThrowingStream<AnalyzerInput, any Error>) {
        let state = state
        stream = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await input in source { continuation.yield(input) }
                    continuation.finish()
                } catch {
                    await state.markThrown()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var didThrow: Bool {
        get async { await state.thrown }
    }
}

actor AudioEndState {
    private(set) var thrown = false
    func markThrown() { thrown = true }
}

// MARK: - The real engine

/// `SpeechAnalyzer` with `SpeechTranscriber` or `DictationTranscriber`, on device.
struct SpeechAnalyzerEngine: SpeechEngine {
    func choice(for locale: Locale, excluding excluded: Set<SpeechTranscriberKind>) async -> TranscriberChoice {
        let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        // "Installed" is read from the device's installed locales: `AssetInventory.status` reads `supported` for an
        // installed locale until this process has asked for it once (probed on the Mac, WI-M2-M3).
        let speechInstalled = await SpeechTranscriber.installedLocales
        let dictationInstalled = await DictationTranscriber.installedLocales
        let speech = TranscriberStatus(
            isAvailable: SpeechTranscriber.isAvailable, supportsLocale: speechLocale != nil,
            assetsInstalled: speechLocale.map { wanted in speechInstalled.contains { Self.same($0, wanted) } } ?? false)
        let dictation = TranscriberStatus(
            isAvailable: true, supportsLocale: dictationLocale != nil,
            assetsInstalled: dictationLocale.map { wanted in dictationInstalled.contains { Self.same($0, wanted) } }
                ?? false)
        return TranscriberChoice.choose(speech: speech, dictation: dictation, excluding: excluded)
    }

    /// Two locales name the same language and region (`en_US` = `en-US`).
    static func same(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier(.bcp47) == rhs.identifier(.bcp47)
    }

    func audioFormat(for kind: SpeechTranscriberKind, locale: Locale) async -> AVAudioFormat? {
        guard let resolved = await Self.locale(kind, locale) else { return nil }
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [Self.module(kind, resolved)])
    }

    func transcribe(_ kind: SpeechTranscriberKind, locale: Locale,
                    input: AsyncThrowingStream<AnalyzerInput, any Error>) -> AsyncThrowingStream<TranscriptPiece, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let resolved = await Self.locale(kind, locale) else {
                    continuation.finish(throwing: SpeechEngineStop.localeGone)
                    return
                }
                // The assets are on the device (checked by `choice`); this registers them for this process and
                // returns nil. A non-nil request means a download, which a capture never starts.
                let module = Self.module(kind, resolved)
                guard await AssetCheck.installed({
                    try await AssetInventory.assetInstallationRequest(supporting: [module])
                }) else {
                    continuation.finish(throwing: SpeechEngineStop.assetsMissing)
                    return
                }
                let analyzer: SpeechAnalyzer
                let results: Task<Void, any Error>
                switch kind {
                case .speechTranscriber:
                    let module = SpeechTranscriber(locale: resolved, preset: .progressiveTranscription)
                    analyzer = SpeechAnalyzer(modules: [module])
                    results = Task {
                        for try await result in module.results {
                            continuation.yield(TranscriptPiece(text: String(result.text.characters),
                                                               isFinal: result.isFinal))
                        }
                    }
                case .dictationTranscriber:
                    // `.progressiveLongDictation`: the short presets gave no final result for a 4.8 s utterance in
                    // the MS-1 probe; brain-dumps are often longer.
                    let module = DictationTranscriber(locale: resolved, preset: .progressiveLongDictation)
                    analyzer = SpeechAnalyzer(modules: [module])
                    results = Task {
                        for try await result in module.results {
                            continuation.yield(TranscriptPiece(text: String(result.text.characters),
                                                               isFinal: result.isFinal))
                        }
                    }
                }
                do {
                    try await withTaskCancellationHandler {
                        _ = try await analyzer.analyzeSequence(input)
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        try await results.value
                    } onCancel: {
                        results.cancel()
                        Task { await analyzer.cancelAndFinishNow() }
                    }
                    continuation.finish()
                } catch {
                    results.cancel()
                    await analyzer.cancelAndFinishNow()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func locale(_ kind: SpeechTranscriberKind, _ locale: Locale) async -> Locale? {
        switch kind {
        case .speechTranscriber: await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        case .dictationTranscriber: await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
    }

    static func module(_ kind: SpeechTranscriberKind, _ locale: Locale) -> any SpeechModule {
        switch kind {
        case .speechTranscriber: SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        case .dictationTranscriber: DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        }
    }
}

/// Whether a module's assets may be used now: only when the installation request says there is nothing to download
/// (nil). A pending request (a download) or a thrown error (an unknown asset state) means no: the capture ends
/// `stopped(transcriptionStopped)` and never starts a download (review PR #42 m5).
enum AssetCheck {
    static func installed<Request>(_ request: () async throws -> Request?) async -> Bool {
        do {
            return try await request() == nil
        } catch {
            return false
        }
    }
}

enum SpeechEngineStop: Error {
    case localeGone
    case assetsMissing
}
