// One eval run (AC-M2-28 "What it does"; AC-M2-16 timing, AC-M2-17 commit; brief "Device-run rules"). Uses only the
// public API of TendCore, TendIngestion and TendAI.
//
// - Every attempt reads a **fresh copy** of the seeded household in a new M1 in-memory repository, and commits with
//   the deterministic `EvalIDGenerator` for its input number and attempt (T-29; it never yields a fixture UUID).
// - Text inputs are handed to the pipeline verbatim; the clock starts at that hand-off. Voice inputs come from the
//   M2 speech adapter; the clock starts at the transcriber's final result (the caller passes that instant).
// - The clock is `ContinuousClock` (monotonic). TTFI ends at the first `emitted`, total at `finished`.
// - Commit takes every draft the pipeline did not mark as a duplicate (AC-M2-17), in ascending `draftID`.
// - Cloud runs: the owner's key goes through the AC-M2-21 key store, consent is recorded in memory for the selected
//   provider only, and `removeKey()` deletes the key at the end of the run.
// - Request metadata comes from `RecordingTransport` (byte count, key paths and the D-059 element counts only).
// Nothing here writes or logs; the results file is written by `EvalResultsWriter` only.

import Foundation
import TendAI
import TendCore
import TendIngestion

/// What a run is: on device, or one cloud provider.
struct EvalRunKind: Hashable, Sendable {
    let provider: CloudProvider?
    let preference: RoutePreference

    static let onDevice = EvalRunKind(provider: nil, preference: .onDeviceFirst)
    static func cloud(_ provider: CloudProvider, preference: RoutePreference) -> EvalRunKind {
        EvalRunKind(provider: provider, preference: preference)
    }

    var fileRoute: String { provider.map { EvalProvider($0).rawValue } ?? "onDevice" }
    var modelID: String { provider.map { CloudModel.defaultModel(for: $0).rawValue } ?? "SystemLanguageModel.default" }

    /// The sampling setting (brief "Device-run rules"): greedy on device; each provider's fixed request profile.
    var sampling: String {
        guard let provider else { return "greedy" }
        return switch CloudModel.defaultModel(for: provider).requestProfile.sampling {
        case .temperatureZero: "temperature 0"
        case .providerDefault: "provider default (no temperature member)"
        }
    }
}

final class EvalRunner: @unchecked Sendable {
    // @unchecked Sendable: every stored property is immutable and Sendable except the router actor's own state; the
    // class has no mutable state of its own.
    let bundle: EvalBundle
    let kind: EvalRunKind
    let onDevice: any OnDeviceModelSource
    let prewarmSource: FoundationModelsOnDeviceSource?
    let recorder: RecordingTransport
    let router: ModelRouter
    let clock = ContinuousClock()

    /// - Parameters:
    ///   - onDevice: the on-device source (the real `FoundationModelsOnDeviceSource` in the app; a fake in tests).
    ///   - transport: the cloud transport the recorder wraps (`CloudHTTPTransport` in the app).
    ///   - keys: the key store (`KeychainAPIKeyStore` in the app, AC-M2-21).
    init(bundle: EvalBundle, kind: EvalRunKind, onDevice: any OnDeviceModelSource, transport: any CloudTransport,
         keys: any APIKeyStore) {
        self.bundle = bundle
        self.kind = kind
        self.onDevice = onDevice
        self.prewarmSource = onDevice as? FoundationModelsOnDeviceSource
        let recorder = RecordingTransport(transport)
        self.recorder = recorder
        router = ModelRouter(onDevice: onDevice, cloudModels: CloudAdapters(transport: recorder, clock: ContinuousClock()),
                             consents: InMemoryCloudConsentStore(), keys: keys)
    }

    /// Cloud runs: stores the owner's key (AC-M2-21) and records consent in memory for the run's provider only.
    func turnCloudOn(key: APIKey) async throws -> CloudStatus {
        guard let provider = kind.provider else { return .off }
        return try await router.turnCloudOn(provider, key: key)
    }

    /// "Remove key" at the end of a cloud run: deletes the key and the in-memory consent.
    func removeKey() async throws {
        guard let provider = kind.provider else { return }
        try await router.removeKey(for: provider)
    }

    /// When an input is shown or recording starts (AC-M2-16): prewarms the on-device session for the seeded household.
    func prewarm() async {
        guard kind.provider == nil || kind.preference == .onDeviceFirst else { return }
        await prewarmSource?.prewarm(household: bundle.fixtures.household)
    }

    /// One attempt of one input. For voice, `transcript` is the final transcript and `start` the instant of the
    /// transcriber's final result; for text the clock starts here, at the hand-off.
    func run(inputID: String, attempt: Int, retakeReason: String?, voice: VoiceResult?) async
        -> EvalResultsFileV1.InputAttempt? {
        guard let input = bundle.fixtures.input(inputID),
              let number = bundle.fixtures.inputNumber(of: inputID),
              var ids = EvalIDGenerator(inputNumber: number, attempt: attempt) else { return nil }
        let text = voice?.transcript ?? input.text
        let household = bundle.fixtures.household
        let repository = InMemoryHouseholdRepository()
        do { try await repository.save(household) } catch { return nil }
        recorder.reset()
        let start = voice?.finalResultAt ?? clock.now
        let routed = await router.events(input: text, household: household, now: Date(),
                                         calendar: Calendar(identifier: .gregorian), timeZone: .current,
                                         titleSharing: .shortlistTitles, preference: kind.preference)
        var events: [EvalResultsFileV1.Event] = []
        var summary = DraftStreamSummary()
        var ttfi: Int?
        var total = 0
        for await event in routed {
            let t = Self.ms(start.duration(to: clock.now))
            summary.apply(event)
            switch event {
            case let .emitted(draft):
                if ttfi == nil { ttfi = t }
                events.append(.init(type: .emitted, draftID: draft.draftID, tMs: t))
            case let .updated(draft):
                events.append(.init(type: .updated, draftID: draft.draftID, tMs: t))
            case .itemSkipped:
                events.append(.init(type: .itemSkipped, draftID: nil, tMs: t))
            case .finished:
                total = t
                events.append(.init(type: .finished, draftID: nil, tMs: t))
            }
        }
        let confirmed = summary.drafts.filter { $0.duplicate == .none }.sorted { $0.draftID < $1.draftID }
        _ = try? await DraftCommit.commit(confirmed: confirmed, parsedWith: household, to: repository, ids: &ids)
        let records = summary.drafts.compactMap {
            try? DraftRecord(draft: $0, roomKeys: bundle.fixtures.roomKeys, taskKeys: bundle.fixtures.taskKeys)
        }
        let outcome = summary.outcome.map(EvalOutcome.init) ?? .cancelled
        return EvalResultsFileV1.InputAttempt(
            inputID: inputID, mode: input.mode, attempt: attempt, retakeReason: retakeReason,
            transcript: voice?.transcript, transcriber: voice?.transcriber, route: EvalRoute(routed.route),
            outcome: outcome, ttfiMs: ttfi, totalMs: total, events: events, drafts: records,
            committed: confirmed.map(\.draftID), cloudRequests: recorder.recorded)
    }

    static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

/// A voice attempt's final transcript, the transcriber used, and when its final result came (AC-M2-16, AC-M2-25).
struct VoiceResult: Sendable {
    let transcript: String
    let transcriber: EvalTranscriber
    let finalResultAt: ContinuousClock.Instant
}

/// The run header and the file name (AC-M2-28 "Results file (format v1)").
enum EvalRunRecord {
    static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// The iOS build, from "Version 26.5 (Build 23F77)".
    static func iOSBuild() -> String {
        let text = ProcessInfo.processInfo.operatingSystemVersionString
        guard let range = text.range(of: "Build ") else { return text }
        return String(text[range.upperBound...].prefix { $0 != ")" })
    }

    /// The commit the build came from (`TEND_COMMIT` at build time; "unknown" when not passed).
    static func appCommitSHA() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "TendCommit") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "unknown"
    }

    static func utc(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// `yyyy-MM-ddTHH:mm:ssZ`.
    static func startedAtUTC(_ date: Date) -> String { utc(date, format: "yyyy-MM-dd'T'HH:mm:ss'Z'") }

    /// `m2-eval-<deviceModel>-<onDevice|openai|anthropic|gemini>-<UTC yyyyMMdd'T'HHmmss'Z'>.json`.
    static func fileName(deviceModel: String, kind: EvalRunKind, startedAt date: Date) -> String {
        "m2-eval-\(deviceModel)-\(kind.fileRoute)-\(utc(date, format: "yyyyMMdd'T'HHmmss'Z'")).json"
    }
}
