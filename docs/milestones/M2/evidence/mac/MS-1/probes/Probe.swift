// WI-M2-M1 probes (information only, never product code, never committed into a scanned root).
// T-27: does SpeechAnalyzer + SpeechTranscriber / DictationTranscriber run without
//       SFSpeechRecognizer.requestAuthorization(_:)? We never call requestAuthorization here.
// R-1:  TTFI of one FoundationModels streamResponse with a draft-sized @Generable schema.
import AVFAudio
import Foundation
import FoundationModels
import Speech

enum ProbeLog {
    nonisolated(unsafe) static var lines: [String] = []
    static func say(_ s: String) {
        let line = "[probe] " + s
        lines.append(line)
        print(line)
        fflush(stdout)
    }
}

func authString(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .authorized: return "authorized"
    @unknown default: return "unknown(\(s.rawValue))"
    }
}

func platformLine() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersionString
    #if targetEnvironment(simulator)
    return "iOS Simulator \(v)"
    #elseif os(macOS)
    return "macOS \(v)"
    #else
    return "iOS \(v)"
    #endif
}

func ensureAssets(_ modules: [any SpeechModule], name: String) async {
    let before = await AssetInventory.status(forModules: modules)
    ProbeLog.say("\(name): asset status before = \(before)")
    if before != .installed {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                ProbeLog.say("\(name): downloading assets…")
                try await request.downloadAndInstall()
            } else {
                ProbeLog.say("\(name): no installation request returned")
            }
        } catch {
            ProbeLog.say("\(name): asset install error = \(String(reflecting: error))")
        }
        let after = await AssetInventory.status(forModules: modules)
        ProbeLog.say("\(name): asset status after = \(after)")
    }
}

func runSpeech(audioURL: URL, locale: Locale) async {
    ProbeLog.say("T-27 platform: \(platformLine())")
    ProbeLog.say("T-27 SFSpeechRecognizer.authorizationStatus (before) = \(authString(SFSpeechRecognizer.authorizationStatus()))")
    ProbeLog.say("T-27 SpeechTranscriber.isAvailable = \(SpeechTranscriber.isAvailable)")
    let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    ProbeLog.say("T-27 SpeechTranscriber supportedLocale(\(locale.identifier)) = \(supported?.identifier ?? "nil")")
    let dictSupported = await DictationTranscriber.supportedLocale(equivalentTo: locale)
    ProbeLog.say("T-27 DictationTranscriber supportedLocale(\(locale.identifier)) = \(dictSupported?.identifier ?? "nil")")

    // SpeechTranscriber
    do {
        let transcriber = SpeechTranscriber(locale: supported ?? locale, preset: .transcription)
        await ensureAssets([transcriber], name: "SpeechTranscriber")
        let file = try AVAudioFile(forReading: audioURL)
        let start = ContinuousClock.now
        let collector = Task { () -> String in
            var text = ""
            for try await r in transcriber.results where r.isFinal { text += String(r.text.characters) }
            return text
        }
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        _ = analyzer
        let text = try await collector.value
        ProbeLog.say("T-27 SpeechTranscriber RESULT ok in \(ContinuousClock.now - start): \"\(text)\"")
    } catch {
        ProbeLog.say("T-27 SpeechTranscriber RESULT error: \(String(reflecting: error))")
    }

    // DictationTranscriber
    do {
        let transcriber = DictationTranscriber(locale: dictSupported ?? locale, preset: .longDictation)
        await ensureAssets([transcriber], name: "DictationTranscriber")
        let file = try AVAudioFile(forReading: audioURL)
        let start = ContinuousClock.now
        let collector = Task { () -> String in
            var text = ""
            var all = 0
            for try await r in transcriber.results { all += 1; if r.isFinal { text += String(r.text.characters) } }
            return text + " [results seen: \(all)]"
        }
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        _ = analyzer
        let text = try await collector.value
        ProbeLog.say("T-27 DictationTranscriber RESULT ok in \(ContinuousClock.now - start): \"\(text)\"")
    } catch {
        ProbeLog.say("T-27 DictationTranscriber RESULT error: \(String(reflecting: error))")
    }
    ProbeLog.say("T-27 SFSpeechRecognizer.authorizationStatus (after) = \(authString(SFSpeechRecognizer.authorizationStatus()))")
}

// A draft-sized schema: roughly the WI-M2-M2 shape (title first), not the production schema.
@Generable
struct ProbeDraft {
    @Guide(description: "Short task title in the user's words")
    var title: String
    @Guide(description: "Room name if one is said, else empty")
    var room: String
    @Guide(description: "oneOff, recurring or restock")
    var kind: String
    @Guide(description: "low, normal or high")
    var effort: String
    var isDeepClean: Bool
    var isWeatherDependent: Bool
    @Guide(description: "The exact phrase from the input this item came from")
    var sourcePhrase: String
}

@Generable
struct ProbeCapture {
    @Guide(description: "One entry per household task in the input", .maximumCount(10))
    var items: [ProbeDraft]
}

func runLatency(runs: Int) async {
    let model = SystemLanguageModel.default
    ProbeLog.say("R-1 platform: \(platformLine())")
    ProbeLog.say("R-1 SystemLanguageModel.default.availability = \(model.availability)")
    guard case .available = model.availability else { return }
    let input = "The AC needs servicing before summer, we're almost out of dishwasher pods, and deep clean the balcony this weekend if it doesn't rain."
    let instructions = "You turn a short household note into task drafts. Use the user's own words for titles. Do not invent tasks."
    var ttfis: [Duration] = []
    var totals: [Duration] = []
    for run in 1...runs {
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
        try? await Task.sleep(for: .seconds(1))
        let start = ContinuousClock.now
        var firstItem: Duration?
        var count = 0
        do {
            let stream = session.streamResponse(to: input, generating: ProbeCapture.self)
            for try await snapshot in stream {
                if firstItem == nil, let first = snapshot.content.items?.first, let t = first.title, !t.isEmpty {
                    firstItem = ContinuousClock.now - start
                }
                count = snapshot.content.items?.count ?? count
            }
            let total = ContinuousClock.now - start
            ProbeLog.say("R-1 run \(run): TTFI=\(firstItem.map { "\($0)" } ?? "none") total=\(total) items=\(count)")
            if let firstItem { ttfis.append(firstItem) }
            totals.append(total)
        } catch {
            ProbeLog.say("R-1 run \(run): error \(String(reflecting: error))")
        }
    }
    func median(_ d: [Duration]) -> String {
        guard !d.isEmpty else { return "n/a" }
        let s = d.sorted(); return "\(s[s.count / 2])"
    }
    ProbeLog.say("R-1 summary: runs=\(runs) TTFI median=\(median(ttfis)) min=\(ttfis.min().map { "\($0)" } ?? "n/a") max=\(ttfis.max().map { "\($0)" } ?? "n/a"); total median=\(median(totals))")
}

func runAllProbes(audioURL: URL) async {
    await runSpeech(audioURL: audioURL, locale: Locale(identifier: "en-US"))
    await runConvertedAll(audioURL: audioURL)
    await runLatency(runs: 5)
    ProbeLog.say("DONE")
}

// Second attempt for the Simulator: convert the file to the analyzer's best format and feed buffers.
func runConverted(module: any SpeechModule, results: @escaping @Sendable () async throws -> String, name: String, audioURL: URL) async {
    do {
        let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        ProbeLog.say("T-27 \(name) bestAvailableAudioFormat = \(best.map { "\($0)" } ?? "nil")")
        guard let best else { return }
        let file = try AVAudioFile(forReading: audioURL)
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        let conv = AVAudioConverter(from: file.processingFormat, to: best)!
        let ratio = best.sampleRate / file.processingFormat.sampleRate
        let outBuf = AVAudioPCMBuffer(pcmFormat: best, frameCapacity: AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1024)!
        nonisolated(unsafe) var fed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { throw err }
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        let start = ContinuousClock.now
        let collector = Task { try await results() }
        try await analyzer.start(inputSequence: stream)
        cont.yield(AnalyzerInput(buffer: outBuf))
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        ProbeLog.say("T-27 \(name) (converted) RESULT ok in \(ContinuousClock.now - start): \"\(text)\"")
    } catch {
        ProbeLog.say("T-27 \(name) (converted) RESULT error: \(String(reflecting: error))")
    }
}

func runConvertedAll(audioURL: URL) async {
    let locale = Locale(identifier: "en_US")
    let st = SpeechTranscriber(locale: locale, preset: .transcription)
    await runConverted(module: st, results: {
        var t = ""; for try await r in st.results where r.isFinal { t += String(r.text.characters) }; return t
    }, name: "SpeechTranscriber", audioURL: audioURL)
    let dt = DictationTranscriber(locale: locale, preset: .longDictation)
    await runConverted(module: dt, results: {
        var t = ""; for try await r in dt.results where r.isFinal { t += String(r.text.characters) }; return t
    }, name: "DictationTranscriber", audioURL: audioURL)
    ProbeLog.say("T-27 SFSpeechRecognizer.authorizationStatus (after converted) = \(authString(SFSpeechRecognizer.authorizationStatus()))")
}
