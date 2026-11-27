// The committed scope table for the AC-M2-09 scan (M2 plan, "AC-M2-09 is owned by WI-M2-01 …").
//
// A `required` root must exist and hold > 0 `.swift` files, or the scan fails (lesson from M1 R-6: no vacuous pass).
// An `optional` root is scanned when it exists and is logged as "not present" when it does not. The item that creates
// a root switches it to `required` in the same PR: WI-M2-M1 for `TendAI` and `TendEval`. Evidence for AC-M2-09 is taken
// on the M2 merge commit (WI-M2-M8), when all three roots are required.
//
// The file lists are the plan's "Named files" table. Moving a named file needs a plan update and the Tester's note.

import TendSourceScan

enum ScanScope {

    enum RootState: String, Sendable {
        case required
        case optional
    }

    struct Root: Sendable {
        var module: ScannedModule
        /// Repository-relative path of the module's `Sources`.
        var path: String
        var state: RootState
    }

    static let roots: [Root] = [
        Root(module: .tendIngestion, path: "Packages/TendIngestion/Sources", state: .required),
        Root(module: .tendAI, path: "Packages/TendAI/Sources", state: .required),       // required since WI-M2-M1
        Root(module: .tendEval, path: "Apps/TendEval/Sources", state: .required),       // required since WI-M2-M1
    ]

    /// Rule 5 (T-27): off. The T-27 check in WI-M2-M1 found that `SpeechAnalyzer` with `SpeechTranscriber` or
    /// `DictationTranscriber` does not need `SFSpeechRecognizer.requestAuthorization(_:)` (Apple's Speech
    /// documentation and the macOS run; dev-notes "WI-M2-M1"). DS-1 and DS-2 confirm it on device.
    static let speechPermissionExceptionEnabled = false

    static let configuration = IngestionScanConfiguration(
        cloudAdapterAllowlist: [
            "Packages/TendAI/Sources/TendAI/Cloud/CloudHTTPTransport.swift",
            "Packages/TendAI/Sources/TendAI/Cloud/CloudFailureMapping.swift",
            "Packages/TendAI/Sources/TendAI/Cloud/KeychainAPIKeyStore.swift",
        ],
        speechAdapterFiles: [
            "Packages/TendAI/Sources/TendAI/Speech/SpeechTranscriptionAdapter.swift",
            "Packages/TendAI/Sources/TendAI/Speech/MicrophoneAudioSource.swift",
        ],
        speechPermissionFile: "Packages/TendAI/Sources/TendAI/Speech/SpeechPermission.swift",
        speechPermissionExceptionEnabled: speechPermissionExceptionEnabled,
        resultsWriterFile: "Apps/TendEval/Sources/Results/EvalResultsWriter.swift",
        // Rule 4 (review R1-F6, WI-M2-10): the payload builder's provider table, the only file with bare hosts.
        providerTableFile: "Packages/TendIngestion/Sources/TendIngestion/Payload/CloudProviderTable.swift"
    )
}
