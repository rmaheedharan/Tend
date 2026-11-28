// AC-M2-09 negative and near-miss tests for the rule engine (Rules 1–6), over in-memory planted files.
// Brief M2 v4 AC-M2-09 (T-11, T-23, T-27, T-30), nit N-1; plan WI-M2-01. P-1, P-2, P-3, P-4.
//
// Each planted fixture names the rule it must trip. Near-miss fixtures must produce no violation at all.
// The real scan over the repository runs in `TendIngestionTests` (AC-M2-09 evidence).

import Testing
import TendSourceScan

/// The plan's named files (M2 plan "Named files"), used as the scan configuration in these tests.
enum PlanPaths {
    static let transport = "Packages/TendAI/Sources/TendAI/Cloud/CloudHTTPTransport.swift"
    static let failureMapping = "Packages/TendAI/Sources/TendAI/Cloud/CloudFailureMapping.swift"
    static let keychain = "Packages/TendAI/Sources/TendAI/Cloud/KeychainAPIKeyStore.swift"
    static let speechAdapter = "Packages/TendAI/Sources/TendAI/Speech/SpeechTranscriptionAdapter.swift"
    static let microphone = "Packages/TendAI/Sources/TendAI/Speech/MicrophoneAudioSource.swift"
    static let speechPermission = "Packages/TendAI/Sources/TendAI/Speech/SpeechPermission.swift"
    static let resultsWriter = "Apps/TendEval/Sources/Results/EvalResultsWriter.swift"
    /// The payload builder's provider table: the only file where bare hosts may appear (review R1-F6, WI-M2-10).
    static let providerTable = "Packages/TendIngestion/Sources/TendIngestion/Payload/CloudProviderTable.swift"

    static let ingestionFile = "Packages/TendIngestion/Sources/TendIngestion/Planted.swift"
    static let aiFile = "Packages/TendAI/Sources/TendAI/Cloud/OpenAIIngestionModel.swift"
    static let evalFile = "Apps/TendEval/Sources/Run/EvalRunner.swift"

    static func configuration(speechException: Bool = false) -> IngestionScanConfiguration {
        IngestionScanConfiguration(
            cloudAdapterAllowlist: [transport, failureMapping, keychain],
            speechAdapterFiles: [speechAdapter, microphone],
            speechPermissionFile: speechPermission,
            speechPermissionExceptionEnabled: speechException,
            resultsWriterFile: resultsWriter,
            providerTableFile: providerTable,
            fixturesLoaderFile: fixturesLoader
        )
    }
}

/// One planted fixture: where it is, what it contains, and which rule (and check fragment) must report it.
struct Planted: Sendable, CustomTestStringConvertible {
    var module: ScannedModule
    var path: String
    var code: String
    var rule: IngestionScanRule
    /// A fragment of `RuleViolation.check` that must appear, e.g. `"media type CGImage"`.
    var check: String

    var testDescription: String { "\(rule) [\(check)] in \(path): \(code)" }

    static func ingestion(_ code: String, _ check: String) -> Planted {
        Planted(module: .tendIngestion, path: PlanPaths.ingestionFile, code: code, rule: .rule1, check: check)
    }

    static func ai(_ code: String, _ check: String) -> Planted {
        Planted(module: .tendAI, path: PlanPaths.aiFile, code: code, rule: .rule2, check: check)
    }

    static func cloud(_ code: String, _ check: String) -> Planted {
        Planted(module: .tendAI, path: PlanPaths.transport, code: code, rule: .rule3, check: check)
    }

    static func eval(_ code: String, _ check: String, path: String = PlanPaths.evalFile) -> Planted {
        Planted(module: .tendEval, path: path, code: code, rule: .rule6, check: check)
    }
}

func scan(_ module: ScannedModule, _ path: String, _ code: String, speechException: Bool = false)
    -> [RuleViolation] {
    IngestionSourceRules.violations(in: ScannedFile(module: module, path: path, text: code),
                                    configuration: PlanPaths.configuration(speechException: speechException))
}

@Suite("AC-M2-09 rule engine: planted hits and near-misses (TendSourceScan)")
struct IngestionSourceRulesTests {

    // MARK: Patterns

    @Test("AC-M2-09: every fixed scanner regex compiles (no silent pass from a broken pattern)")
    func everyPatternCompiles() {
        for pattern in IngestionSourceRules.allPatterns {
            #expect(SourceScanner.isValidPattern(pattern), "invalid pattern: \(pattern)")
        }
    }

    @Test("AC-M2-09: an invalid regex fails closed (it yields a match, so the rule reports a hit)")
    func invalidPatternFailsClosed() {
        let result = SourceScanner.matches(of: "(unclosed", in: "anything")
        #expect(result.count == 1)
        #expect(result.first?.text.hasPrefix(SourceScanner.invalidPatternMarker) == true)
    }

    // MARK: Planted hits, one per list entry and rule

    static let rule1Planted: [Planted] = {
        var planted: [Planted] = [
            .ingestion("import Combine", "AC-M1-23 import"),
            .ingestion("import Security", "AC-M1-23 import"),
            .ingestion("import FoundationModels", "AC-M1-23 import"),
            .ingestion("import Network", "networking import"),
            .ingestion("import CFNetwork", "networking import"),
            .ingestion("import FoundationNetworking", "networking import"),
            .ingestion("let now = Date()", "AC-M1-23 Date()"),
            .ingestion("let c = Calendar.current", "AC-M1-23 Calendar.current"),
            .ingestion("let l = Locale.current", "AC-M1-23 Locale.current"),
            .ingestion("let id = UUID()", "AC-M1-23 UUID()"),
            .ingestion("let n = Int.random(in: 0..<3)", "AC-M1-23 .random( without using:"),
            .ingestion("let p = ProcessInfo.processInfo", "AC-M1-23 ProcessInfo"),
            .ingestion("let c = ContinuousClock()", "AC-M1-23 ContinuousClock"),
            // T-26: no `contentsOf:` allowlist in TendIngestion; the scorer takes `Data`.
            .ingestion("let d = try Data(contentsOf: url)", "AC-M1-23 contentsOf:"),
            .ingestion("let s = try String(contentsOf: url, encoding: .utf8)", "AC-M1-23 contentsOf:"),
            .ingestion("let u = \"https://api.openai.com\"", "AC-M1-23 http(s) literal"),
            .ingestion("let u = URL(string: s)", "networking URL(string:"),
        ]
        for name in IngestionSourceRules.networkingNames {
            planted.append(.ingestion("let x: \(name)Thing? = nil", "networking \(name)"))
        }
        for name in IngestionSourceRules.mediaTypes {
            planted.append(.ingestion("let x: \(name)? = nil", "media type \(name)"))
        }
        for name in IngestionSourceRules.writeNames {
            planted.append(.ingestion("let x = \(name).self", "write API \(name)"))
        }
        planted.append(.ingestion("try data.write(to: url)", "write API write(to:"))
        planted.append(.ingestion("_ = fm.createFile(atPath: p, contents: nil)", "write API createFile("))
        for name in IngestionSourceRules.logNames {
            planted.append(.ingestion("let x = \(name)(subsystem: s, category: c)", "log API \(name)"))
        }
        for call in IngestionSourceRules.logCalls {
            planted.append(.ingestion("\(call)value)", "log API \(call)"))
        }
        return planted
    }()

    static let rule2Planted: [Planted] = {
        var planted: [Planted] = [
            .ai("import Security", "import"),          // Security only in allowlisted files (Rule 3)
            .ai("import OpenAI", "import"),            // no provider SDK
            .ai("import Vision", "import"),
            .ai("import Network", "networking import"),
            .ai("import FoundationNetworking", "networking import"),
            .ai("let u = URL(string: s)", "networking URL(string:"),
            .ai("let u = URL.init(string: s)", "networking URL(string:"),
            .ai("let h = Host(name: n)", "networking Host("),
            .ai("let s = InputStream(data: d)", "networking InputStream("),
            .ai("let fd = socket(2, 1, 0)", "networking socket("),
            .ai("let x = CGImage.self", "media type CGImage"),           // not a speech adapter file
            .ai("let b: AVAudioPCMBuffer? = nil", "media type AVAudioPCMBuffer"),
            .ai("let a = AVAssetReader.self", "media type AVAsset"),     // substring of the identifier
            .ai("let d = UserDefaults.standard", "write API UserDefaults"),
            .ai("try body.write(to: file)", "write API write(to:"),
            .ai("let log = AppLogger()", "log API Logger"),
            .ai("let t = OSLogType.debug", "log API OSLog"),
            .ai("Swift.print(x)", "log API print("),
            .ai("NSLog(\"%@\", x)", "log API NSLog("),
        ]
        for name in IngestionSourceRules.networkingNames {
            planted.append(.ai("let x = \(name).self", "networking \(name)"))
        }
        return planted
    }()

    /// Rule 3: everything just outside the subset (T-23), including the brief's named examples.
    static let rule3Planted: [Planted] = [
        .cloud("let t: URLSessionWebSocketTask? = nil", "networking outside subset: URLSession"),
        .cloud("let t: URLSessionWebSocketTask? = nil", "networking prefix outside subset"),
        .cloud("let u = URL(string: s)", "networking outside subset: URL(string:"),
        .cloud("let u = URL . init ( string: s)", "networking outside subset: URL(string:"),
        .cloud("let t: URLSessionStreamTask? = nil", "networking prefix outside subset"),
        .cloud("let t: URLSessionUploadTask? = nil", "networking prefix outside subset"),
        .cloud("let t: URLSessionDownloadTask? = nil", "networking prefix outside subset"),
        .cloud("let t: URLSessionDataTask? = nil", "networking prefix outside subset"),
        .cloud("final class D: URLSessionDataDelegate {}", "networking prefix outside subset"),
        .cloud("final class P: URLProtocol {}", "networking outside subset: URLProtocol"),
        .cloud("let c = URLCache.shared", "networking prefix outside subset"),
        .cloud("let c = URLCredential(user: u, password: p, persistence: .none)", "networking prefix outside subset"),
        .cloud("let s: URLs = []", "networking prefix outside subset"),
        .cloud("let s = NSURLSession.self", "networking outside subset: NSURL"),
        .cloud("let h = HTTPCookieStorage.shared", "networking prefix outside subset"),
        .cloud("let m = NWPathMonitor()", "networking prefix outside subset"),
        .cloud("let c: NWConnection? = nil", "networking outside subset: NWConnection"),
        .cloud("let h = CFHostCreateWithName(nil, n)", "networking prefix outside subset"),
        .cloud("CFStreamCreatePairWithSocketToHost(nil, h, 443, &r, &w)", "networking prefix outside subset"),
        .cloud("let e = CFNetworkCopySystemProxySettings()", "networking prefix outside subset"),
        .cloud("let s = InputStream(data: d)", "networking outside subset: InputStream("),
        .cloud("let h = Host.current()", "networking outside subset: Host.current"),
        .cloud("import FoundationNetworking", "import"),
        .cloud("import FoundationNetworking", "networking outside subset: import"),
        .cloud("import Network", "import"),
        .cloud("import Alamofire", "import"),          // no third-party module
        .cloud("let x: CGImage? = nil", "media type CGImage"),
        .cloud("try body.write(to: file)", "write API write(to:"),
        .cloud("let f = FileManager.default", "write API FileManager"),
        .cloud("print(response)", "log API print("),
        .cloud("let l = Logger()", "log API Logger"),
        .cloud("let r: SFSpeechRecognizer? = nil", "networking outside subset: SFSpeech"),
    ]

    /// Rule 4 (T-30): host-like literals that are not allowed where they appear.
    static let rule4Planted: [Planted] = [
        Planted(module: .tendIngestion, path: PlanPaths.ingestionFile, code: "let h = \"api.example.com\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"https://api.example.com/v1\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"https://api.openai.com/v1/responses\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"http://api.openai.com\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"https://\\(host)\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"API.OPENAI.COM:443\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = \"wss://api.openai.com\"",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.transport, code: "let h = #\"localhost.dev\"#",
                rule: .rule4, check: "host-like literal not allowed"),
        Planted(module: .tendAI, path: PlanPaths.aiFile, code: "let h = \"https://api.openai.com\"",
                rule: .rule4, check: "https:// host outside the cloud-adapter allowlist"),
        Planted(module: .tendIngestion, path: PlanPaths.ingestionFile, code: "let h = \"https://api.anthropic.com\"",
                rule: .rule4, check: "https:// host outside the cloud-adapter allowlist"),
        Planted(module: .tendEval, path: PlanPaths.evalFile,
                code: "let h = \"https://generativelanguage.googleapis.com\"",
                rule: .rule4, check: "https:// host outside the cloud-adapter allowlist"),
        Planted(module: .tendAI, path: PlanPaths.aiFile, code: "let h = \"api.openai.com\"",
                rule: .rule4, check: "bare host outside TendIngestion"),
        Planted(module: .tendEval, path: PlanPaths.evalFile, code: "let h = \"api.anthropic.com\"",
                rule: .rule4, check: "bare host outside TendIngestion"),
        // R1-F6 (WI-M2-10): a bare host in a TendIngestion file other than the provider table.
        Planted(module: .tendIngestion, path: PlanPaths.ingestionFile, code: "let h = \"api.openai.com\"",
                rule: .rule4, check: "bare host outside the provider table"),
        Planted(module: .tendIngestion,
                path: "Packages/TendIngestion/Sources/TendIngestion/Payload/CloudPayloadBuilder.swift",
                code: "let h = \"generativelanguage.googleapis.com\"",
                rule: .rule4, check: "bare host outside the provider table"),
    ]

    /// Rule 5 (T-27): `SFSpeech*` APIs, with the exception off (the state until WI-M2-M1).
    static let rule5Planted: [Planted] = [
        Planted(module: .tendAI, path: PlanPaths.speechPermission, code: "let r = SFSpeechRecognizer(locale: l)",
                rule: .rule5, check: "SFSpeech* API"),
        Planted(module: .tendAI, path: PlanPaths.speechPermission,
                code: "SFSpeechRecognizer.requestAuthorization { _ in }", rule: .rule5, check: "SFSpeech* API"),
        Planted(module: .tendAI, path: PlanPaths.speechPermission,
                code: "let s = SFSpeechRecognizer.authorizationStatus()", rule: .rule5, check: "SFSpeech* API"),
        Planted(module: .tendAI, path: PlanPaths.speechPermission,
                code: "let s: SFSpeechRecognizerAuthorizationStatus = .notDetermined", rule: .rule5,
                check: "SFSpeech* API"),
        Planted(module: .tendAI, path: PlanPaths.speechAdapter,
                code: "let r = SFSpeechURLRecognitionRequest(url: u)", rule: .rule5, check: "SFSpeech* API"),
        Planted(module: .tendIngestion, path: PlanPaths.ingestionFile,
                code: "let t = SFSpeechAudioBufferRecognitionRequest.self", rule: .rule5, check: "SFSpeech* API"),
    ]

    /// Rule 6: networking, write APIs outside the results writer, log APIs anywhere in `TendEval`.
    static let rule6Planted: [Planted] = {
        var planted: [Planted] = [
            .eval("let r = URLRequest(url: u)", "networking URLRequest"),      // N-2: no URL* request type
            .eval("let s = URLSession.shared", "networking URLSession"),
            .eval("let u = URL(string: s)", "networking URL(string:"),
            .eval("import Network", "networking import"),
            .eval("try data.write(to: url)", "write API write(to:"),
            .eval("let f = FileManager.default", "write API FileManager"),
            .eval("let h = try FileHandle(forWritingTo: url)", "write API FileHandle"),
            .eval("UserDefaults.standard.set(1, forKey: k)", "write API UserDefaults"),
            // Log APIs are banned in the results writer too.
            .eval("print(results)", "log API print(", path: PlanPaths.resultsWriter),
            .eval("let l = Logger()", "log API Logger", path: PlanPaths.resultsWriter),
        ]
        for call in IngestionSourceRules.logCalls {
            planted.append(.eval("\(call)x)", "log API \(call)"))
        }
        return planted
    }()

    /// The hand-written M2 Q24 plants (TendIngestion, Rule 1) are part of the set, so the coverage test sees them.
    static let allPlanted = rule1Planted + rule2Planted + rule3Planted + rule4Planted + rule5Planted + rule6Planted
        + Q24RulesTests.q24Plants.map { Planted.ingestion($0.0, $0.1) }

    @Test("AC-M2-09 negative: every planted hit is caught by its rule", arguments: allPlanted)
    func plantedHitIsCaught(planted: Planted) {
        let found = scan(planted.module, planted.path, planted.code)
        #expect(found.contains { $0.rule == planted.rule && $0.check.contains(planted.check) },
                "not caught: \(planted.testDescription); found: \(found)")
    }

    @Test("AC-M2-09 coverage: the planted fixtures exercise every entry of the three closed lists and all six rules")
    func plantedFixturesCoverLists() {
        let checks = Self.allPlanted.map(\.check)
        for name in IngestionSourceRules.networkingNames {
            #expect(checks.contains("networking \(name)"), "no planted networking hit for \(name)")
        }
        for name in IngestionSourceRules.mediaTypes {
            #expect(checks.contains("media type \(name)"), "no planted media hit for \(name)")
        }
        for name in IngestionSourceRules.writeNames + IngestionSourceRules.writeCalls {
            #expect(checks.contains("write API \(name)"), "no planted write hit for \(name)")
        }
        for name in IngestionSourceRules.logNames + IngestionSourceRules.logCalls {
            #expect(checks.contains("log API \(name)"), "no planted log hit for \(name)")
        }
        #expect(Set(Self.allPlanted.map(\.rule)) == Set(IngestionScanRule.allCases))
        // The brief's named Rule 3 examples (T-23).
        let rule3Code = Self.rule3Planted.map(\.code).joined(separator: "\n")
        for example in ["URL(string:", "URLSessionWebSocketTask", "URLSessionStreamTask", "URLSessionUploadTask",
                        "URLSessionDownloadTask", "URLSessionDataDelegate", "URLProtocol", "URLCache"] {
            #expect(rule3Code.contains(example), "Rule 3 example \(example) not planted")
        }
    }

    // MARK: Brief-named negative tests

    @Test("AC-M2-09 Rule 3 (T-23): URLSessionWebSocketTask and URL(string: are caught; a subset-only file passes")
    func rule3BriefNegativeTest() {
        let webSocket = scan(.tendAI, PlanPaths.transport, "let t: URLSessionWebSocketTask? = nil")
        #expect(webSocket.contains { $0.rule == .rule3 })
        let fromString = scan(.tendAI, PlanPaths.transport, "let u = URL(string: \"x\")")
        #expect(fromString.contains { $0.rule == .rule3 })

        let subsetOnly = """
            import Foundation
            import TendIngestion
            import Security

            final class CloudHTTPTransport: NSObject, URLSessionTaskDelegate {
                private let session: URLSession

                init(delegateQueue: OperationQueue?) {
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.urlCache = nil
                    configuration.httpCookieStorage = nil
                    configuration.httpShouldSetCookies = false
                    session = URLSession(configuration: configuration)
                    super.init()
                }

                func send(host: String, path: String, body: Data) async throws -> (URLSession.AsyncBytes, URLResponse) {
                    var components = URLComponents()
                    components.scheme = "https"
                    components.host = host
                    components.path = path
                    guard let url: URL = components.url else { throw URLError(.badURL) }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.httpBody = body
                    let task: URLSessionTask? = nil
                    _ = task
                    return try await session.bytes(for: request, delegate: self)
                }

                func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest) async -> URLRequest? {
                    nil
                }

                func status(of response: URLResponse) -> Int {
                    (response as? HTTPURLResponse)?.statusCode ?? 0
                }
            }
            """
        let found = scan(.tendAI, PlanPaths.transport, subsetOnly)
        #expect(found.isEmpty, "subset-only file reported: \(found)")
    }

    @Test("AC-M2-09 Rule 3 (N-1): whole identifiers, no camelCase split: willPerformHTTPRedirection is not a hit")
    func rule3WholeIdentifierNearMiss() {
        let code = """
            func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse,
                            newRequest q: URLRequest) async -> URLRequest? { nil }
            let urlCache: Int? = nil
            let httpCookieStorage: Int? = nil
            let isHTTPS = true
            let myURLValue = 1
            let pathURL = 2
            """
        let found = scan(.tendAI, PlanPaths.transport, code)
        #expect(found.isEmpty, "near-misses reported: \(found)")
        // The same identifier with the prefix at the start is a hit.
        #expect(scan(.tendAI, PlanPaths.transport, "let x = HTTPRedirection.self").contains { $0.rule == .rule3 })
    }

    @Test("AC-M2-09 Rule 3: the allowed subset is exactly the brief's closed list (T-23)")
    func rule3SubsetIsClosed() {
        #expect(IngestionSourceRules.allowedNetworkingSubset == [
            "URLSession", "URLSessionConfiguration", "URLSessionTask", "URLSessionTaskDelegate",
            "URLRequest", "URL", "URLComponents", "URLResponse", "HTTPURLResponse", "URLError",
        ])
        #expect(IngestionSourceRules.networkingPrefixes == ["URL", "NSURL", "HTTP", "NW", "CFHost", "CFStream",
                                                            "CFNetwork"])
    }

    @Test("AC-M2-09 Rule 4 (T-30): tend.ai.key and com.tend.eval pass; api.example.com and https://api.example.com/v1 are caught")
    func rule4BriefNegativeTest() {
        for module in ScannedModule.allCases {
            let path = module == .tendIngestion ? PlanPaths.ingestionFile
                : module == .tendAI ? PlanPaths.transport : PlanPaths.evalFile
            let reverseDNS = scan(module, path, "let k = \"tend.ai.key\"; let b = \"com.tend.eval\"")
            #expect(reverseDNS.isEmpty, "\(module): reverse-DNS literal reported: \(reverseDNS)")
            #expect(scan(module, path, "let h = \"api.example.com\"").contains { $0.rule == .rule4 }, "\(module)")
            #expect(scan(module, path, "let h = \"https://api.example.com/v1\"").contains { $0.rule == .rule4 },
                    "\(module)")
        }
    }

    @Test("AC-M2-09 Rule 4: bare hosts pass only in the provider table (R1-F6); https:// hosts pass only in allowlisted files")
    func rule4AllowedPlacements() {
        let table = """
            let hosts = ["api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com"]
            """
        #expect(scan(.tendIngestion, PlanPaths.providerTable, table).isEmpty)
        // R1-F6: the same table anywhere else in TendIngestion is caught, once per host.
        let elsewhere = scan(.tendIngestion, PlanPaths.ingestionFile, table)
        #expect(elsewhere.count == 3 && elsewhere.allSatisfy {
            $0.rule == .rule4 && $0.check == "bare host outside the provider table"
        }, "\(elsewhere)")
        // The table file's path in another module's configuration does not help a TendAI or TendEval file.
        #expect(scan(.tendAI, PlanPaths.aiFile, table).count == 3)
        // R28-F1: the match is on the exact path, not the file name. A file with the table's name in another folder
        // of TendIngestion, or in another module, is caught.
        let sameNameIngestion = "Packages/TendIngestion/Sources/TendIngestion/Duplicates/CloudProviderTable.swift"
        let sameNameIngestionFound = scan(.tendIngestion, sameNameIngestion, table)
        #expect(sameNameIngestionFound.count == 3 && sameNameIngestionFound.allSatisfy {
            $0.rule == .rule4 && $0.check == "bare host outside the provider table"
        }, "\(sameNameIngestionFound)")
        let sameNameAI = "Packages/TendAI/Sources/TendAI/Cloud/CloudProviderTable.swift"
        let sameNameAIFound = scan(.tendAI, sameNameAI, table)
        #expect(sameNameAIFound.count == 3 && sameNameAIFound.allSatisfy {
            $0.rule == .rule4 && $0.check == "bare host outside TendIngestion"
        }, "\(sameNameAIFound)")
        let prefixed = "Packages/TendIngestion/Sources/TendIngestion/Payload/OldCloudProviderTable.swift"
        #expect(scan(.tendIngestion, prefixed, table).count == 3, "a longer name ending in the table's name")
        for file in [PlanPaths.transport, PlanPaths.failureMapping, PlanPaths.keychain] {
            let found = scan(.tendAI, file, """
                let a = "https://api.openai.com"
                let b = "https://api.anthropic.com"
                let c = "https://generativelanguage.googleapis.com"
                """)
            #expect(found.isEmpty, "\(file): \(found)")
        }
    }

    @Test("AC-M2-09 Rule 4: host-like is decided on the whole literal", arguments: [
        ("api.openai.com", true), ("https://api.example.com/v1", true), ("api.example.com", true),
        ("Example.IO", true), ("a-b.c-d.cloud:8080/x/y", true), ("x://y", true), ("file:///tmp/a", true),
        ("tend.ai.key", false), ("com.tend.eval", false), ("tend.eval.results", false), ("keychain.tend.app.key", false),
        ("api.example.com is down", false), ("see api.example.com", false), ("", false), ("v1/responses", false),
        ("hello.world", false), ("results-v1.json", false),
    ])
    func hostLikeTable(literal: String, expected: Bool) {
        #expect(IngestionSourceRules.isHostLike(literal) == expected, "\(literal)")
    }

    @Test("AC-M2-09 Rule 5 (T-27): SFSpeechRecognizer( in the speech-permission file is caught, with the exception off and on")
    func rule5InitialiserCaught() {
        for exception in [false, true] {
            let found = scan(.tendAI, PlanPaths.speechPermission, "let r = SFSpeechRecognizer(locale: l)",
                             speechException: exception)
            #expect(found.contains { $0.rule == .rule5 }, "exception \(exception): \(found)")
            let explicitInit = scan(.tendAI, PlanPaths.speechPermission, "let r = SFSpeechRecognizer.init()",
                                    speechException: exception)
            #expect(explicitInit.contains { $0.rule == .rule5 }, "exception \(exception): \(explicitInit)")
        }
    }

    @Test("AC-M2-09 Rule 5 (T-27): the two exception calls and the status type pass only with the exception on, only in the speech-permission file")
    func rule5ExceptionScope() {
        let exceptionCode = """
            import Speech
            func ask() async -> SFSpeechRecognizerAuthorizationStatus {
                await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization({ c.resume(returning: $0) }) }
            }
            let current = SFSpeechRecognizer.authorizationStatus()
            """
        #expect(scan(.tendAI, PlanPaths.speechPermission, exceptionCode, speechException: true).isEmpty)
        #expect(scan(.tendAI, PlanPaths.speechPermission, exceptionCode, speechException: false)
            .filter { $0.rule == .rule5 }.count == 3)
        // The brief allows exactly `requestAuthorization(`; the trailing-closure spelling is not the exact form.
        #expect(scan(.tendAI, PlanPaths.speechPermission, "SFSpeechRecognizer.requestAuthorization { _ in }",
                     speechException: true).contains { $0.rule == .rule5 })
        #expect(scan(.tendAI, PlanPaths.speechAdapter, exceptionCode, speechException: true)
            .contains { $0.rule == .rule5 })
        // Other members of the recogniser stay hits even with the exception on.
        #expect(scan(.tendAI, PlanPaths.speechPermission, "let r = SFSpeechRecognizer.supportedLocales()",
                     speechException: true).contains { $0.rule == .rule5 })
    }

    @Test("AC-M2-09 Rule 6: a write API outside EvalResultsWriter.swift and a log API anywhere in TendEval are caught")
    func rule6BriefNegativeTest() {
        let write = "try encoded.write(to: url, options: .atomic)"
        #expect(scan(.tendEval, PlanPaths.evalFile, write).contains { $0.rule == .rule6 })
        #expect(scan(.tendEval, PlanPaths.resultsWriter, write).isEmpty)
        #expect(scan(.tendEval, PlanPaths.resultsWriter, "let f = FileManager.default").isEmpty)
        #expect(scan(.tendEval, PlanPaths.resultsWriter, "print(x)").contains { $0.rule == .rule6 })
        #expect(scan(.tendEval, PlanPaths.evalFile, "os_log(\"x\")").contains { $0.rule == .rule6 })
    }

    // MARK: Positives and near-misses

    @Test("AC-M2-09 Rule 1 positive: Foundation + TendCore imports, Locale(identifier: \"en_US_POSIX\"), append(contentsOf:), a bare host (in the provider table, R1-F6)")
    func rule1Positive() {
        let code = """
            import Foundation
            import TendCore

            public enum NameFold {
                static let posix = Locale(identifier: "en_US_POSIX")
                static let hosts = ["api.openai.com"]
                static func keys(_ xs: [String]) -> [String] {
                    var out: [String] = []
                    out.append(contentsOf: xs)
                    return out
                }
                static func stream() -> AsyncStream<Int> { AsyncStream { $0.finish() } }
                static func pick<G: RandomNumberGenerator>(_ xs: [Int], using g: inout G) -> Int? {
                    xs.randomElement(using: &g)
                }
                static let reprint = 1
                static let isWriteable = true
                static let loggerName = "x"
            }
            """
        let found = scan(.tendIngestion, PlanPaths.providerTable, code)  // the bare host: provider table only (R1-F6)
        #expect(found.isEmpty, "unexpected: \(found)")
        // R28-N1: the same code without the bare host is clean in a general TendIngestion file (Rule 1 does not
        // depend on the path inside TendIngestion).
        let general = code.replacingOccurrences(of: "    static let hosts = [\"api.openai.com\"]\n", with: "")
        #expect(general != code)
        let generalFound = scan(.tendIngestion, PlanPaths.ingestionFile, general)
        #expect(generalFound.isEmpty, "unexpected: \(generalFound)")
    }

    @Test("AC-M2-09 Rule 2 positive: allowed imports; media types in the speech adapter files only")
    func rule2Positive() {
        let code = """
            import Foundation
            import FoundationModels
            import Speech
            import AVFAudio
            import TendCore
            import TendIngestion
            let s = AsyncThrowingStream<Int, Error> { $0.finish() }
            let analyzer: SpeechAnalyzer? = nil
            let transcriber: SpeechTranscriber? = nil
            let dictation: DictationTranscriber? = nil
            let model = SystemLanguageModel.default
            let urlString = "not a host"
            """
        #expect(scan(.tendAI, PlanPaths.aiFile, code).isEmpty)
        let media = "let b: AVAudioPCMBuffer? = nil\nlet f: AVAudioFile? = nil"
        #expect(scan(.tendAI, PlanPaths.speechAdapter, media).isEmpty)
        #expect(scan(.tendAI, PlanPaths.microphone, media).isEmpty)
        #expect(!scan(.tendAI, PlanPaths.speechPermission, media).isEmpty)
    }

    @Test("AC-M2-09: rule hits in comments and plain string text are ignored")
    func commentsAndStringsIgnored() {
        let code = """
            // URLSession, URLRequest(string:), print(x), FileManager, CGImage, SFSpeechRecognizer(
            /* import Network; Logger(); "https://api.example.com" is in a comment */
            let s = "URLSession print( FileManager CGImage SFSpeechRecognizer"
            """
        for module in ScannedModule.allCases {
            let path = module == .tendIngestion ? PlanPaths.ingestionFile
                : module == .tendAI ? PlanPaths.aiFile : PlanPaths.evalFile
            #expect(scan(module, path, code).isEmpty, "\(module)")
        }
    }

    @Test("AC-M2-09 Rule 6 positive: plain harness code, Bundle URLs and the results writer's writes pass in TendEval")
    func rule6Positive() {
        let code = """
            import Foundation
            import TendIngestion
            let url = Bundle.main.url(forResource: "inputs", withExtension: "json")
            let name = url?.lastPathComponent ?? "none"
            var items: [Int] = []
            items.append(contentsOf: [1, 2])
            let stream = AsyncStream<Int> { $0.finish() }
            """
        #expect(scan(.tendEval, PlanPaths.evalFile, code).isEmpty)
        #expect(scan(.tendEval, PlanPaths.resultsWriter, "try bytes.write(to: url, options: .atomic)").isEmpty)
    }

    // MARK: R1-F1: `contentsOf:` URL loading is a networking pattern in Rules 2, 3 and 6

    static let contentsOfPlants: [String] = [
        "let d = try Data(contentsOf: u)",
        "let s = try String(contentsOf: u, encoding: .utf8)",
        "let d: Data = try .init(contentsOf: u)",
        "let d = try Data(contentsOf: components.url!)",
        "let m = NSMutableData(contentsOf: u)",
        "let v = try x.load(contentsOf: u)",
    ]

    static let contentsOfLocations: [(ScannedModule, String, IngestionScanRule)] = [
        (.tendAI, PlanPaths.transport, .rule3),          // allowlisted: outside the T-23 subset (review P01)
        (.tendAI, PlanPaths.failureMapping, .rule3),
        (.tendAI, PlanPaths.keychain, .rule3),
        (.tendAI, PlanPaths.aiFile, .rule2),             // a provider adapter (review P02)
        (.tendAI, PlanPaths.speechAdapter, .rule2),
        (.tendEval, PlanPaths.evalFile, .rule6),         // review P03
        (.tendEval, PlanPaths.resultsWriter, .rule6),    // the write exception is not a read exception
        (.tendEval, PlanPaths.fixturesLoader, .rule6),   // M2 Q23: none of these is the loader's exact form
        (.tendIngestion, PlanPaths.ingestionFile, .rule1),
    ]

    @Test("AC-M2-09 (R1-F1) negative: Data(contentsOf:, String(contentsOf:, .init(contentsOf: … are caught in every module and file kind",
          arguments: contentsOfPlants)
    func contentsOfCaught(code: String) {
        for (module, path, rule) in Self.contentsOfLocations {
            let found = scan(module, path, code)
            #expect(found.contains { $0.rule == rule && $0.check.contains("contentsOf:") },
                    "\(rule) did not catch `\(code)` in \(path): \(found)")
        }
    }

    @Test("AC-M2-09 (R1-F1) positive: append(contentsOf:) and insert(contentsOf:at:) pass in Rules 1, 2, 3 and 6")
    func contentsOfCollectionExemption() {
        let code = """
            var xs = [1]
            xs.append(contentsOf: [2, 3])
            xs.insert(contentsOf: [0], at: 0)
            append(contentsOf: [4])
            """
        for (module, path, rule) in Self.contentsOfLocations {
            let found = scan(module, path, code)
            #expect(found.isEmpty, "\(rule) in \(path): \(found)")
        }
        // Only exactly `append` / `insert`: the inner call of a nested load is still caught.
        #expect(scan(.tendEval, PlanPaths.evalFile, "xs.append(contentsOf: try Data(contentsOf: u))")
            .contains { $0.rule == .rule6 })
        #expect(scan(.tendAI, PlanPaths.transport, "xs.appendAll(contentsOf: ys)").contains { $0.rule == .rule3 })
    }

    @Test("AC-M2-09: each module is checked by its own rule (dispatch)")
    func moduleDispatch() {
        // The same text gives Rule 1 in TendIngestion, Rule 2 in TendAI, Rule 3 in an allowlisted file, Rule 6 in
        // TendEval.
        let code = "let s = URLSessionWebSocketTask.self"
        #expect(Set(scan(.tendIngestion, PlanPaths.ingestionFile, code).map(\.rule)) == [.rule1])
        #expect(Set(scan(.tendAI, PlanPaths.aiFile, code).map(\.rule)) == [.rule2])
        #expect(Set(scan(.tendAI, PlanPaths.transport, code).map(\.rule)) == [.rule3])
        #expect(Set(scan(.tendEval, PlanPaths.evalFile, code).map(\.rule)) == [.rule6])
        // An allowlisted file that uses only the subset is clean, but the same file outside the allowlist is Rule 2.
        let subset = "let s: URLSession? = nil"
        #expect(scan(.tendAI, PlanPaths.transport, subset).isEmpty)
        #expect(scan(.tendAI, PlanPaths.aiFile, subset).contains { $0.rule == .rule2 })
    }
}
