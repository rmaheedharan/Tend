// The SP-1 speech screen (device spike, information only; SP-1.md Part D4). Never shipped, never archived; not
// product UI (no UX-4 review). It does nothing at launch: no permission request, no speech or asset call and no
// microphone until a button is tapped.
//
// It uses the product path only: `SpeechPermission`, `SpeechCapture(locale: en_US).events(from:)` and one
// `MicrophoneAudioSource` kept for the whole session. Each result is an `SP1|…` line, shown on screen and written
// unbuffered to standard output. The transcript is printed only because the owner reads a fixed invented sentence;
// nothing is stored and no audio is kept (P-4).

import Foundation
import Speech
import SwiftUI
import TendAI

@MainActor
@Observable
final class SP1SpeechModel {
    var lines: [String] = []
    var countdown: Int?
    var busy = false

    private var seq = 0
    private var captureNumber = 0
    private let capture = SpeechCapture(locale: Locale(identifier: "en_US"))
    private let source = MicrophoneAudioSource()
    private var askedMicrophone = false
    private var current: Task<Void, Never>?
    private var stopTappedAt: ContinuousClock.Instant?

    func emit(_ fields: String) {
        seq += 1
        let line = "SP1|seq=\(seq)|\(fields)"
        lines.append(line)
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func name(_ readiness: SpeechReadiness) -> String {
        switch readiness {
        case let .ready(kind): "ready(\(kind.rawValue))"
        case let .unavailable(reason): "unavailable(\(reason))"
        }
    }

    static func name(_ permission: MicrophonePermission) -> String {
        switch permission {
        case .allowed: "allowed"
        case .notAsked: "notAsked"
        case .notAllowed: "notAllowed"
        }
    }

    static func name(_ outcome: SpeechCaptureOutcome) -> String {
        switch outcome {
        case .transcribed: "transcribed"
        case .nothingHeard: "nothingHeard"
        case let .unavailable(reason): "unavailable(\(reason))"
        case let .stopped(reason): "stopped(\(reason))"
        case .cancelled: "cancelled"
        }
    }

    static func ms(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }

    func speechStatus() async {
        let readiness = await capture.readiness()
        emit("speech-status|readiness=\(Self.name(readiness))|mic=\(Self.name(SpeechPermission.microphone()))")
    }

    /// Downloads the en-US speech assets, only when tapped (online).
    func getSpeechModel() async {
        busy = true
        defer { busy = false }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            ?? Locale(identifier: "en_US")
        let modules: [any SpeechModule] = [SpeechTranscriber(locale: locale, preset: .progressiveTranscription),
                                           DictationTranscriber(locale: locale, preset: .progressiveLongDictation)]
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                emit("speech-model|download=started")
                try await request.downloadAndInstall()
                emit("speech-model|download=done")
            } else {
                emit("speech-model|download=notNeeded")
            }
        } catch {
            emit("speech-model|download=stopped|error=\(type(of: error))")
        }
        await speechStatus()
    }

    func start() async {
        guard current == nil else { return }
        captureNumber += 1
        let n = captureNumber
        emit("capture|n=\(n)|start|mic_before=\(Self.name(SpeechPermission.microphone()))")
        if !askedMicrophone {
            askedMicrophone = true
            let after = await SpeechPermission.requestMicrophone()
            emit("capture|n=\(n)|mic_after=\(Self.name(after))")
        }
        stopTappedAt = nil
        let events = capture.events(from: source)
        current = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case let .transcriberChosen(kind):
                    self.emit("capture|n=\(n)|transcriber=\(kind.rawValue)")
                case .textSoFar:
                    break
                case let .finished(outcome):
                    let ms = self.stopTappedAt.map { Self.ms($0.duration(to: ContinuousClock.now)) }
                    var fields = "capture|n=\(n)|finished=\(Self.name(outcome))|ms_stop_to_finished="
                        + (ms.map(String.init) ?? "none")
                    if case let .transcribed(transcript) = outcome {
                        let words = transcript.text.split(whereSeparator: \.isWhitespace).count
                        fields += "|words=\(words)|text=\(transcript.text)"
                    }
                    self.emit(fields)
                }
            }
            self?.current = nil
        }
    }

    func stop() {
        guard current != nil else { return }
        stopTappedAt = ContinuousClock.now
        emit("capture|n=\(captureNumber)|stop_tapped")
        source.stop()
    }

    /// Ten tries with the same source, 1 s apart: 1-5 stop right after the capture starts, 6-10 at
    /// `transcriberChosen` (the review PR #42 M1-r2 window).
    func quickStopTest() async {
        guard current == nil, !busy else { return }
        busy = true
        defer { busy = false }
        if !askedMicrophone {
            askedMicrophone = true
            _ = await SpeechPermission.requestMicrophone()
        }
        for attempt in 1...10 {
            let atChosen = attempt > 5
            let clock = ContinuousClock()
            var stoppedAt: ContinuousClock.Instant?
            var outcome = "none"
            let events = capture.events(from: source)
            if !atChosen {
                stoppedAt = clock.now
                source.stop()
            }
            for await event in events {
                switch event {
                case .transcriberChosen:
                    if atChosen, stoppedAt == nil {
                        stoppedAt = clock.now
                        source.stop()
                    }
                case .textSoFar:
                    break
                case let .finished(result):
                    outcome = Self.name(result)
                }
            }
            let ms = stoppedAt.map { Self.ms($0.duration(to: clock.now)) }
            emit("quickstop|try=\(attempt)|when=\(atChosen ? "atChosen" : "beforeChosen")|finished=\(outcome)"
                 + "|ms_stop_to_finished=\(ms.map(String.init) ?? "none")")
            try? await Task.sleep(for: .seconds(1))
        }
        emit("quickstop|done")
        for remaining in stride(from: 10, through: 1, by: -1) {
            countdown = remaining
            try? await Task.sleep(for: .seconds(1))
        }
        countdown = nil
    }
}

struct SP1SpeechScreen: View {
    @State private var model = SP1SpeechModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                button("Speech status") { await model.speechStatus() }
                button("Get speech model") { await model.getSpeechModel() }
            }
            HStack(spacing: 12) {
                button("Start") { await model.start() }
                button("Stop") { model.stop() }
            }
            button("Quick stop test") { await model.quickStopTest() }
            if let countdown = model.countdown {
                Text("Look at the top of the screen now (\(countdown))")
                    .font(.title2.bold())
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.body.monospaced()).textSelection(.enabled).id(index)
                        }
                    }
                }
                .onChange(of: model.lines.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding()
        .task {
            // Mac dry run only (SP-1 D5.3): with `TEND_SP1_SELFCHECK=1` in the launch environment, press
            // [Speech status] once, so the console path can be checked without a tap. Without it, nothing runs at
            // launch (D4.1). [Speech status] asks for no permission, starts no download and uses no microphone.
            if ProcessInfo.processInfo.environment["TEND_SP1_SELFCHECK"] == "1" { await model.speechStatus() }
        }
    }

    private func button(_ title: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 56)
            .buttonStyle(.borderedProminent)
    }
}
