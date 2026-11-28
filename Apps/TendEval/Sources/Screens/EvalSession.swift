// The state of one eval session on the iPhone (AC-M2-28 "What it does"; brief "Device-run rules"; plan WI-M2-M7). The
// screens are plain test controls, not product UI (plan WI-M2-M7).
//
// - **Setup:** operator, network (kind, speed test), route (on device or one provider), route preference, and for a
//   cloud run the owner's key, which goes straight into the AC-M2-21 key store (`KeychainAPIKeyStore`) and is then
//   cleared from the field. Consent for the selected provider is recorded in memory only (`EvalRunner`).
// - **Inputs:** each input's script is shown. Showing an input (and starting a recording) prewarms the on-device
//   session (AC-M2-16). Text inputs are fed verbatim; voice inputs are captured live through the M2 speech adapter.
// - **Attempts:** a text input runs once. A voice input may have one retake, only with a reason (a misread). Every
//   attempt is kept, in the order run (T-20).
// - **Cold start** (on device only, information only, Q4): input 1 once, before anything is prewarmed, through a fresh
//   session; only its TTFI is kept, in `coldStart`. It is not one of the scored attempts.
// - **Export:** the results file, written only by `EvalResultsWriter`; its name and SHA-256 are shown.
// - **Remove key** at the end of a cloud run.
// Nothing here writes or logs.

import CryptoKit
import Foundation
import SwiftUI
import TendAI
import TendCore
import TendIngestion

/// The route of a run, as the setup picker shows it.
enum EvalRouteChoice: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case openai
    case anthropic
    case gemini

    var id: String { rawValue }

    var provider: CloudProvider? {
        switch self {
        case .onDevice: nil
        case .openai: .openAI
        case .anthropic: .anthropic
        case .gemini: .gemini
        }
    }

    var label: String {
        switch self {
        case .onDevice: "On device"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }
}

@MainActor
@Observable
final class EvalSession {
    // MARK: Bundle

    /// The bundled eval, or nil when it could not be read (then nothing can run).
    let bundle: EvalBundle?
    let bundleProblem: String?
    let commitSHA = EvalRunRecord.appCommitSHA()

    var commitIsKnown: Bool {
        commitSHA.count == 40 && commitSHA.allSatisfy { "0123456789abcdef".contains($0) }
    }

    // MARK: Setup

    var operatorName = ""
    var networkKind = "home Wi-Fi"
    var downMbps = ""
    var upMbps = ""
    var latencyMs = ""
    var routeChoice: EvalRouteChoice = .onDevice
    var alwaysCloud = false
    /// The owner's key, typed into a secure field; cleared as soon as it is stored.
    var keyText = ""

    // MARK: Run

    private(set) var runner: EvalRunner?
    private(set) var startedAt: Date?
    private(set) var attempts: [EvalResultsFileV1.InputAttempt] = []
    private(set) var coldStart: EvalResultsFileV1.ColdStart?
    private(set) var isBusy = false
    /// A plain status line for the operator.
    private(set) var status = ""
    var selectedInputID: String?
    var retakeReason = ""

    // MARK: Voice

    private(set) var isRecording = false
    private(set) var liveText = ""
    private var microphone: MicrophoneAudioSource?

    // MARK: Export

    private(set) var exportedName: String?
    private(set) var exportedSHA256: String?
    private(set) var keyRemoved = false

    init() {
        do {
            let loaded = try EvalBundle.load()
            bundle = loaded
            bundleProblem = loaded.allMatch ? nil : "A bundled fixture does not match MANIFEST.sha256."
        } catch {
            bundle = nil
            bundleProblem = "The bundled fixtures could not be read."
        }
    }

    // MARK: Setup checks

    var network: EvalResultsFileV1.Network? {
        guard !networkKind.trimmingCharacters(in: .whitespaces).isEmpty,
              let down = Int(downMbps), let up = Int(upMbps), let latency = Int(latencyMs),
              down >= 0, up >= 0, latency >= 0 else { return nil }
        return .init(kind: networkKind.trimmingCharacters(in: .whitespaces), downMbps: down, upMbps: up,
                     latencyMs: latency)
    }

    var kind: EvalRunKind {
        guard let provider = routeChoice.provider else { return .onDevice }
        return .cloud(provider, preference: alwaysCloud ? .alwaysCloud : .onDeviceFirst)
    }

    /// What still stops the run from starting, or nil.
    var setupProblem: String? {
        if bundleProblem != nil { return bundleProblem }
        if !commitIsKnown { return "Build with TEND_COMMIT set to the commit under test (plan WI-M2-M7)." }
        if operatorName.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the operator." }
        if network == nil { return "Enter the network kind and the speed test (whole numbers)." }
        if routeChoice.provider != nil, keyText.isEmpty { return "Enter the key for \(routeChoice.label)." }
        return nil
    }

    // MARK: Start

    func startRun() async {
        guard runner == nil, setupProblem == nil, let bundle else { return }
        isBusy = true
        defer { isBusy = false }
        let runner = EvalRunner(bundle: bundle, kind: kind, onDevice: FoundationModelsOnDeviceSource(),
                                transport: CloudHTTPTransport(), keys: KeychainAPIKeyStore())
        if routeChoice.provider != nil {
            let key = APIKey(keyText)
            keyText = ""
            do {
                guard try await runner.turnCloudOn(key: key) == .on(try provider()) else {
                    status = "Cloud did not turn on for \(routeChoice.label). Check the key and start again."
                    return
                }
            } catch {
                status = "The key was not stored. Check it and start again."
                return
            }
        }
        self.runner = runner
        startedAt = Date()
        status = "Run started."
    }

    private func provider() throws -> CloudProvider {
        guard let provider = routeChoice.provider else { throw CancellationError() }
        return provider
    }

    // MARK: Inputs

    var inputs: [EvalFixtureInput] { bundle?.fixtures.inputs ?? [] }

    func attemptCount(_ inputID: String) -> Int { attempts.filter { $0.inputID == inputID }.count }

    /// Whether a new attempt of `input` may start, and why not.
    func nextAttemptProblem(_ input: EvalFixtureInput) -> String? {
        if runner == nil { return "Start the run first." }
        if isBusy || isRecording { return "An attempt is running." }
        let done = attemptCount(input.id)
        switch input.mode {
        case .text:
            return done == 0 ? nil : "A text input runs once."
        case .voice:
            if done == 0 { return nil }
            if done >= 2 { return "A voice input has at most one retake." }
            return retakeReason.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Enter the retake reason (a misread of the script)." : nil
        }
    }

    /// An input was shown: prewarm the on-device session for it (AC-M2-16).
    func show(_ inputID: String) async {
        selectedInputID = inputID
        await runner?.prewarm()
    }

    var canColdStart: Bool {
        runner != nil && kind.provider == nil && coldStart == nil && attempts.isEmpty && !isBusy && !isRecording
    }

    /// Input 1 once through a fresh, never-prewarmed session; only its TTFI is kept (information only, Q4).
    func runColdStart() async {
        guard canColdStart, let bundle, let first = inputs.first else { return }
        isBusy = true
        defer { isBusy = false }
        status = "Cold start: \(first.id)…"
        // Its own on-device source, so no session prepared by showing an input can be used.
        let fresh = EvalRunner(bundle: bundle, kind: .onDevice, onDevice: FoundationModelsOnDeviceSource(),
                               transport: CloudHTTPTransport(), keys: InMemoryAPIKeyStore())
        let attempt = await fresh.run(inputID: first.id, attempt: 1, retakeReason: nil, voice: nil)
        coldStart = .init(inputID: first.id, ttfiMs: attempt?.ttfiMs)
        status = "Cold start done: TTFI \(attempt?.ttfiMs.map { "\($0) ms" } ?? "none")."
    }

    func runText(_ input: EvalFixtureInput) async {
        guard input.mode == .text, nextAttemptProblem(input) == nil, let runner else { return }
        isBusy = true
        defer { isBusy = false }
        await runner.prewarm()
        status = "Running \(input.id)…"
        await record(runner.run(inputID: input.id, attempt: 1, retakeReason: nil, voice: nil), for: input.id)
    }

    // MARK: Voice

    func startVoice(_ input: EvalFixtureInput) async {
        guard input.mode == .voice, nextAttemptProblem(input) == nil, let runner else { return }
        switch SpeechPermission.microphone() {
        case .allowed: break
        case .notAsked:
            guard await SpeechPermission.requestMicrophone() == .allowed else {
                status = "Microphone access is off for TendEval. Turn it on in Settings."
                return
            }
        case .notAllowed:
            status = "Microphone access is off for TendEval. Turn it on in Settings."
            return
        }
        let attempt = attemptCount(input.id) + 1
        let reason = attempt == 2 ? retakeReason.trimmingCharacters(in: .whitespaces) : nil
        let microphone = MicrophoneAudioSource()
        self.microphone = microphone
        isRecording = true
        liveText = ""
        status = "Listening for \(input.id). Read the script, then tap Stop."
        await runner.prewarm()
        let clock = runner.clock
        var final: VoiceResult?
        var ending = "The capture ended with no transcript."
        for await event in SpeechCapture().events(from: microphone) {
            switch event {
            case .transcriberChosen: break
            case let .textSoFar(text): liveText = text
            case let .finished(outcome):
                switch outcome {
                case let .transcribed(transcript):
                    final = VoiceResult(transcript: transcript.text, transcriber: Self.transcriber(transcript.transcriber),
                                        finalResultAt: clock.now)
                case .nothingHeard: ending = "Nothing was heard. Try again."
                case .unavailable: ending = "Speech is not ready on this iPhone for this language."
                case .stopped: ending = "The audio stopped. Try again."
                case .cancelled: ending = "The capture was cancelled."
                }
            }
        }
        isRecording = false
        self.microphone = nil
        guard let final else {
            status = ending
            return
        }
        isBusy = true
        defer { isBusy = false }
        status = "Running \(input.id) (attempt \(attempt))…"
        await record(runner.run(inputID: input.id, attempt: attempt, retakeReason: reason, voice: final),
                     for: input.id)
        retakeReason = ""
    }

    func stopVoice() {
        microphone?.stop()
    }

    static func transcriber(_ kind: SpeechTranscriberKind) -> EvalTranscriber {
        switch kind {
        case .speechTranscriber: .speechTranscriber
        case .dictationTranscriber: .dictationTranscriber
        }
    }

    private func record(_ attempt: EvalResultsFileV1.InputAttempt?, for inputID: String) {
        guard let attempt else {
            status = "\(inputID) could not run."
            return
        }
        attempts.append(attempt)
        status = "\(inputID) attempt \(attempt.attempt): \(attempt.outcome.rawValue), "
            + "TTFI \(attempt.ttfiMs.map { "\($0) ms" } ?? "none"), total \(attempt.totalMs) ms, "
            + "\(attempt.drafts.count) drafts, \(attempt.committed.count) committed."
    }

    // MARK: Export and Remove key

    var canExport: Bool { runner != nil && !attempts.isEmpty && !isBusy && !isRecording }

    func export() {
        guard canExport, let bundle, let startedAt, let network else { return }
        let device = EvalRunRecord.deviceModel()
        let run = EvalResultsFileV1.Run(
            operatorName: operatorName.trimmingCharacters(in: .whitespaces),
            startedAtUTC: EvalRunRecord.startedAtUTC(startedAt), deviceModel: device,
            iOSBuild: EvalRunRecord.iOSBuild(), appCommitSHA: commitSHA, fixturesSHA256: bundle.fixturesSHA256,
            locale: Locale.current.identifier(.bcp47),
            routePreference: kind.preference == .alwaysCloud ? .alwaysCloud : .onDeviceFirst,
            provider: kind.provider.map(EvalProvider.init), modelID: kind.modelID, sampling: kind.sampling,
            prewarm: kind.provider == nil || kind.preference == .onDeviceFirst, network: network)
        let file = EvalResultsFileV1(run: run, coldStart: coldStart, inputs: attempts)
        let name = EvalRunRecord.fileName(deviceModel: device, kind: kind, startedAt: startedAt)
        do {
            let data = try EvalResultsWriter.write(file, name: name)
            exportedName = name
            exportedSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            status = "Saved \(name) in TendEval's Documents."
        } catch {
            status = "The results file could not be saved."
        }
    }

    var canRemoveKey: Bool { runner != nil && kind.provider != nil && !keyRemoved && !isBusy && !isRecording }

    func removeKey() async {
        guard canRemoveKey, let runner else { return }
        do {
            try await runner.removeKey()
            keyRemoved = true
            status = "The key was removed from this iPhone."
        } catch {
            status = "The key could not be removed. Try again."
        }
    }
}
