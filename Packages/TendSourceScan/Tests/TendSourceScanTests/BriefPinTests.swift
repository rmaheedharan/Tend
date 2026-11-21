// Review R1-F2: pin every AC-M2-09 closed list to a literal copy of the brief text, and plant one hand-written hit
// per list entry. Nothing here is generated from the engine's own lists, so deleting, widening or misspelling an
// entry turns a test red. Brief M2 v4 AC-M2-09 (T-11, T-23, T-27, T-30); M1 brief AC-M1-23 (Q17–Q20, Q23).
//
// The quoted blocks below are copied unchanged from `docs/milestones/M2/brief.md` (AC-M2-09) and
// `docs/milestones/M1/brief.md` (AC-M1-23). Changing one needs a PO decision that updates the brief first.

import Testing
import TendSourceScan

/// The backticked items of a brief text, in order (`` `a`, `b` `` → `["a", "b"]`).
func backticked(_ text: String) -> [String] {
    text.split(separator: "`", omittingEmptySubsequences: false).enumerated()
        .filter { $0.offset % 2 == 1 }.map { String($0.element) }
}

@Suite("AC-M2-09 closed lists pinned to the brief text (review R1-F2)")
struct BriefPinTests {

    // MARK: Brief text, copied verbatim

    static let briefNetworking = """
        - **Networking patterns:** the AC-M1-23 networking patterns, plus `FoundationNetworking`, `URLSession`,
          `URLRequest`, `URLProtocol`, `URLSessionConfiguration`, `URL(string:`, `URLComponents`, `NWConnection`,
          `import Network`, `import CFNetwork`, `SFSpeech`.
        """
    static let briefMedia = """
        - **Media types:** `AVAudioBuffer`, `AVAudioPCMBuffer`, `AVAudioFile`, `AVAsset`, `CMSampleBuffer`,
          `CVPixelBuffer`, `CVImageBuffer`, `CGImage`, `CIImage`, `UIImage`, `NSImage`.
        """
    static let briefWriteAndLog = """
        - **Write and log APIs:** `write(to:`, `FileManager`, `FileHandle`, `OutputStream`, `createFile(`, `UserDefaults`,
          `NSUbiquitousKeyValueStore`, `print(`, `debugPrint(`, `dump(`, `NSLog(`, `os_log(`, `os_signpost(`, `Logger`,
          `OSLog`.
        """
    static let briefRule1Imports = "- The only imports are `Foundation` and `TendCore`."
    static let briefRule2Imports =
        "- The only imports are `Foundation`, `FoundationModels`, `Speech`, `AVFAudio`, `TendCore` and `TendIngestion`."
    static let briefRule3Imports = """
        - The only imports are those in Rule 2, plus `Security`. `FoundationNetworking` is never imported, because
        """
    static let briefHostRegex =
        #"`(?i)^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|net|org|io|ai|dev|app|co|cloud)(:\d+)?(/\S*)?$`."#
    static let briefHosts = """
        - Every host-like literal is exactly one of `api.openai.com`, `api.anthropic.com` and
          `generativelanguage.googleapis.com`, or `https://` followed by one of them.
        """
    static let briefT27 = """
          exactly `SFSpeechRecognizer.requestAuthorization(` and `SFSpeechRecognizer.authorizationStatus(` (with the
          `SFSpeechRecognizerAuthorizationStatus` type) are allowed.
        """
    /// AC-M1-23, the networking part of the closed list (M1 brief), verbatim.
    static let briefM1Networking = """
      `.shuffle(` whose argument list does not contain `using:`, `URLSession`, `URLRequest`, `URLConnection`,
      `NSURLConnection`, `Socket`, `NSStream`, `Stream(`, `InputStream(`, `OutputStream(`, `getStreamsToHost`, `Host(`,
      `Host.current`, `URL(string:`, `arc4random` (any `arc4random*`), `drand48`, `erand48`, `lrand48`, `srand48`, `rand(`,
      `random()`, `NSURL`, `URLComponents`, `CFURL`, `CFAbsoluteTimeGetCurrent`, `DispatchTime`, `DispatchWallTime`,
      `ContinuousClock`, `SuspendingClock`, `mach_absolute_time`, `clock_gettime`, `gettimeofday`, `CFHost`, `CFReadStream`,
      `CFWriteStream`, `CFSocket`, lower-case `socket(`, `getaddrinfo`, `gethostbyname`, and string literals containing
      `http://` or `https://`. **`contentsOf:` (URL loading)** — every occurrence of the argument label `contentsOf:` is
    """

    // MARK: Pins

    @Test("Pin: the M2 networking names and imports are exactly the brief's list (URL(string: kept from AC-M1-23)")
    func networkingPin() {
        let items = backticked(Self.briefNetworking)
        let imports = items.filter { $0.hasPrefix("import ") }.map { String($0.dropFirst("import ".count)) }
        let names = items.filter { !$0.hasPrefix("import ") && $0 != "URL(string:" }
        #expect(IngestionSourceRules.addedNetworkingNames == names)
        #expect(items.contains("URL(string:"))
        #expect(SourceScanner.identifierPatterns.contains { $0.name == "URL(string:" })
        // `FoundationNetworking` is a name in the list and is never imported (Rule 3), so its import is banned too.
        #expect(IngestionSourceRules.networkingImports == Set(imports + ["FoundationNetworking"]))
    }

    @Test("Pin: the AC-M1-23 networking names, call names and contentsOf: exemptions are exactly the M1 brief's list")
    func m1NetworkingPin() {
        let items = Set(backticked(Self.briefM1Networking))
        let m1Names: [String] = [
            "URLSession", "URLRequest", "URLConnection", "NSURLConnection", "Socket", "NSStream", "getStreamsToHost",
            "NSURL", "URLComponents", "CFURL", "CFHost", "CFReadStream", "CFWriteStream", "CFSocket", "getaddrinfo",
            "gethostbyname",
        ]
        for name in m1Names { #expect(items.contains(name), "\(name) not in the AC-M1-23 text") }
        #expect(SourceScanner.networkingNames == m1Names)
        #expect(SourceScanner.networkingCallNames == ["Stream", "InputStream", "OutputStream", "Host", "socket"])
        for call in ["Stream(", "InputStream(", "OutputStream(", "Host("] { #expect(items.contains(call)) }
        #expect(items.contains("Host.current") && items.contains("contentsOf:"))
        #expect(SourceScanner.contentsOfRule == "contentsOf:")
        #expect(SourceScanner.contentsOfCallExemptions == ["append", "insert"])   // AC-M1-23 / Q23
        #expect(SourceScanner.streamCallExemptions == ["AsyncStream", "AsyncThrowingStream"])  // Q17
    }

    @Test("Pin: the media types are exactly the brief's list")
    func mediaPin() {
        #expect(IngestionSourceRules.mediaTypes == backticked(Self.briefMedia))
    }

    @Test("Pin: the write and log APIs are exactly the brief's list, split into write (Rule 6) and log")
    func writeAndLogPin() {
        let brief = backticked(Self.briefWriteAndLog)
        let engine = IngestionSourceRules.writeNames + IngestionSourceRules.writeCalls
            + IngestionSourceRules.logNames + IngestionSourceRules.logCalls
        #expect(Set(engine) == Set(brief))
        #expect(engine.count == brief.count)
        // The split, hand-written: writing persists data; logging prints or records it.
        #expect(Set(IngestionSourceRules.writeNames + IngestionSourceRules.writeCalls) == [
            "write(to:", "FileManager", "FileHandle", "OutputStream", "createFile(", "UserDefaults",
            "NSUbiquitousKeyValueStore",
        ])
        #expect(Set(IngestionSourceRules.logNames + IngestionSourceRules.logCalls) == [
            "print(", "debugPrint(", "dump(", "NSLog(", "os_log(", "os_signpost(", "Logger", "OSLog",
        ])
    }

    @Test("Pin: the Rule 1, Rule 2 and Rule 3 import lists are exactly the brief's")
    func importsPin() {
        #expect(IngestionSourceRules.rule1Imports == Set(backticked(Self.briefRule1Imports)))
        #expect(IngestionSourceRules.rule2Imports == Set(backticked(Self.briefRule2Imports)))
        let rule3Extra = backticked(Self.briefRule3Imports).first.map { [$0] } ?? []
        #expect(rule3Extra == ["Security"])
        #expect(IngestionSourceRules.rule3Imports == Set(backticked(Self.briefRule2Imports) + rule3Extra))
        #expect(!IngestionSourceRules.rule3Imports.contains("FoundationNetworking"))
    }

    @Test("Pin: the Rule 4 hosts and the host-like regex are exactly the brief's (T-30)")
    func hostsPin() {
        let hosts = backticked(Self.briefHosts).filter { $0 != "https://" }
        #expect(IngestionSourceRules.allowedHosts == hosts)
        #expect(backticked(Self.briefHosts).contains("https://"))
        #expect([IngestionSourceRules.hostLikePattern] == backticked(Self.briefHostRegex))
    }

    @Test("Pin: the T-27 exception forms are exactly the brief's two calls and one type")
    func t27Pin() {
        let forms = backticked(Self.briefT27)
        #expect(forms.count == 3)
        #expect(IngestionSourceRules.speechExceptionType == forms[2])
        for call in forms[0...1] {
            let found = SourceScanner.matches(of: IngestionSourceRules.speechExceptionCallPattern, in: call)
            #expect(found.count == 1 && found.first?.text == call, "\(call) is not matched exactly")
        }
        for other in ["SFSpeechRecognizer.supportedLocales(", "SFSpeechRecognizer(", "SFSpeechRecognizer.init(",
                      "XSFSpeechRecognizer.requestAuthorization("] {
            #expect(SourceScanner.matches(of: IngestionSourceRules.speechExceptionCallPattern, in: other).isEmpty,
                    "\(other) must not be an exception form")
        }
    }

    // MARK: Hand-written plants, one per brief entry

    /// (code, expected check), written by hand from the brief lists, never from the engine's lists.
    static let mediaPlants: [(String, String)] = [
        ("let a: AVAudioBuffer? = nil", "media type AVAudioBuffer"),
        ("let a: AVAudioPCMBuffer? = nil", "media type AVAudioPCMBuffer"),
        ("let a: AVAudioFile? = nil", "media type AVAudioFile"),
        ("let a: AVAsset? = nil", "media type AVAsset"),
        ("let a: CMSampleBuffer? = nil", "media type CMSampleBuffer"),
        ("let a: CVPixelBuffer? = nil", "media type CVPixelBuffer"),
        ("let a: CVImageBuffer? = nil", "media type CVImageBuffer"),
        ("let a: CGImage? = nil", "media type CGImage"),
        ("let a: CIImage? = nil", "media type CIImage"),
        ("let a: UIImage? = nil", "media type UIImage"),
        ("let a: NSImage? = nil", "media type NSImage"),
    ]

    static let writePlants: [(String, String)] = [
        ("try d.write(to: u)", "write API write(to:"),
        ("let f = FileManager.default", "write API FileManager"),
        ("let h: FileHandle? = nil", "write API FileHandle"),
        ("let o: OutputStream? = nil", "write API OutputStream"),
        ("_ = fm.createFile(atPath: p, contents: d)", "write API createFile("),
        ("let u = UserDefaults.standard", "write API UserDefaults"),
        ("let k = NSUbiquitousKeyValueStore.default", "write API NSUbiquitousKeyValueStore"),
    ]

    static let logPlants: [(String, String)] = [
        ("print(x)", "log API print("),
        ("debugPrint(x)", "log API debugPrint("),
        ("dump(x)", "log API dump("),
        ("NSLog(f)", "log API NSLog("),
        ("os_log(f)", "log API os_log("),
        ("os_signpost(.begin, log: l, name: n)", "log API os_signpost("),
        ("let l = Logger()", "log API Logger"),
        ("let t: OSLog? = nil", "log API OSLog"),
    ]

    static let networkingPlants: [(String, String)] = [
        ("let x: FoundationNetworking.URLSession? = nil", "networking FoundationNetworking"),
        ("let x = URLSession.shared", "networking URLSession"),
        ("let x: URLRequest? = nil", "networking URLRequest"),
        ("let x: URLProtocol? = nil", "networking URLProtocol"),
        ("let x = URLSessionConfiguration.ephemeral", "networking URLSessionConfiguration"),
        ("let x = URL(string: s)", "networking URL(string:"),
        ("let x = URLComponents()", "networking URLComponents"),
        ("let x: NWConnection? = nil", "networking NWConnection"),
        ("import Network", "networking import"),
        ("import CFNetwork", "networking import"),
        ("let x: SFSpeechRecognizer? = nil", "networking SFSpeech"),
        ("let x: URLConnection? = nil", "networking URLConnection"),
        ("let x: NSURLConnection? = nil", "networking NSURLConnection"),
        ("let x: Socket? = nil", "networking Socket"),
        ("let x: NSStream? = nil", "networking NSStream"),
        ("let x = Stream(d)", "networking Stream("),
        ("let x = InputStream(data: d)", "networking InputStream("),
        ("let x = OutputStream(toMemory: ())", "networking OutputStream("),
        ("Stream.getStreamsToHost(withName: n, port: 1, inputStream: &i, outputStream: &o)",
         "networking getStreamsToHost"),
        ("let x = Host(name: n)", "networking Host("),
        ("let x = Host.current()", "networking Host.current"),
        ("let x: NSURL? = nil", "networking NSURL"),
        ("let x: CFURL? = nil", "networking CFURL"),
        ("let x = CFHostCreateWithName(nil, n)", "networking CFHost"),
        ("let x: CFReadStream? = nil", "networking CFReadStream"),
        ("let x: CFWriteStream? = nil", "networking CFWriteStream"),
        ("let x: CFSocket? = nil", "networking CFSocket"),
        ("let x = socket(2, 1, 0)", "networking socket("),
        ("getaddrinfo(h, nil, &hints, &r)", "networking getaddrinfo"),
        ("let x = gethostbyname(n)", "networking gethostbyname"),
        ("let x = try Data(contentsOf: u)", "networking contentsOf:"),
    ]

    static let ingestion = (ScannedModule.tendIngestion, PlanPaths.ingestionFile, IngestionScanRule.rule1)
    static let adapter = (ScannedModule.tendAI, PlanPaths.aiFile, IngestionScanRule.rule2)
    static let cloud = (ScannedModule.tendAI, PlanPaths.transport, IngestionScanRule.rule3)
    static let eval = (ScannedModule.tendEval, PlanPaths.evalFile, IngestionScanRule.rule6)
    static let writer = (ScannedModule.tendEval, PlanPaths.resultsWriter, IngestionScanRule.rule6)

    static func expectCaught(_ plants: [(String, String)],
                             in places: [(ScannedModule, String, IngestionScanRule)],
                             checkFor: (String, IngestionScanRule) -> String = { check, _ in check }) {
        for (code, check) in plants {
            for (module, path, rule) in places {
                let wanted = checkFor(check, rule)
                let found = scan(module, path, code)
                #expect(found.contains { $0.rule == rule && $0.check == wanted },
                        "\(rule) [\(wanted)] not caught for `\(code)` in \(path): \(found)")
            }
        }
    }

    @Test("Hand-written plant per media type: Rules 1, 2 (adapter) and 3")
    func mediaPlantsCaught() {
        Self.expectCaught(Self.mediaPlants, in: [Self.ingestion, Self.adapter, Self.cloud])
    }

    @Test("Hand-written plant per write API: Rules 1, 2, 3 and 6 (outside the results writer)")
    func writePlantsCaught() {
        Self.expectCaught(Self.writePlants, in: [Self.ingestion, Self.adapter, Self.cloud, Self.eval])
    }

    @Test("Hand-written plant per log API: Rules 1, 2, 3 and 6 (including the results writer)")
    func logPlantsCaught() {
        Self.expectCaught(Self.logPlants, in: [Self.ingestion, Self.adapter, Self.cloud, Self.eval, Self.writer])
    }

    @Test("Hand-written plant per networking pattern: Rules 1, 2 and 6, and Rule 3 outside the subset")
    func networkingPlantsCaught() {
        Self.expectCaught(Self.networkingPlants, in: [Self.ingestion, Self.adapter, Self.eval])
        // In an allowlisted file only the subset is allowed; these plants are all outside it, except the names
        // `URLSession`, `URLRequest`, `URLComponents` and `URLSessionConfiguration`, which are the subset.
        let subset: Set<String> = ["networking URLSession", "networking URLRequest", "networking URLComponents",
                                   "networking URLSessionConfiguration"]
        let outside = Self.networkingPlants.filter { !subset.contains($0.1) }
        Self.expectCaught(outside, in: [Self.cloud]) { check, _ in
            "networking outside subset: " + check.dropFirst("networking ".count)
        }
    }

    @Test("Hand-written import plants: a widened import list is caught (Rules 1, 2 and 3)")
    func importPlantsCaught() {
        // Rule 1 allows only Foundation and TendCore.
        for module in ["TendIngestion", "Security", "FoundationModels", "Speech", "AVFAudio", "Glibc"] {
            #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "import \(module)")
                .contains { $0.rule == .rule1 && $0.check == "AC-M1-23 import" }, "Rule 1: import \(module)")
        }
        // Rule 2 allows its six modules only: not Security, AVFoundation, Network, Vision.
        for module in ["Security", "AVFoundation", "Network", "Vision", "Darwin"] {
            #expect(scan(.tendAI, PlanPaths.aiFile, "import \(module)")
                .contains { $0.rule == .rule2 && $0.check == "import" }, "Rule 2: import \(module)")
        }
        // Rule 3 adds only Security: not Network, CFNetwork, AVFoundation, FoundationNetworking.
        for module in ["Network", "CFNetwork", "AVFoundation", "FoundationNetworking", "OpenAI"] {
            #expect(scan(.tendAI, PlanPaths.transport, "import \(module)")
                .contains { $0.rule == .rule3 && $0.check == "import" }, "Rule 3: import \(module)")
        }
        let allowed = """
            import Foundation
            import FoundationModels
            import Speech
            import AVFAudio
            import TendCore
            import TendIngestion
            """
        #expect(scan(.tendAI, PlanPaths.aiFile, allowed).isEmpty)
        #expect(scan(.tendAI, PlanPaths.transport, allowed + "\nimport Security").isEmpty)
        #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "import Foundation\nimport TendCore").isEmpty)
    }

    @Test("Hand-written host plants: only the three brief hosts pass (T-30)")
    func hostPlants() {
        for host in ["api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com"] {
            #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "let h = \"\(host)\"").isEmpty, "\(host)")
            #expect(scan(.tendAI, PlanPaths.transport, "let h = \"https://\(host)\"").isEmpty, "\(host)")
        }
        for host in ["api.example.org", "api.openai.co", "openai.com", "api.anthropic.ai", "googleapis.com",
                     "api.openai.com.evil.io"] {
            #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "let h = \"\(host)\"")
                .contains { $0.rule == .rule4 }, "\(host)")
            #expect(scan(.tendAI, PlanPaths.transport, "let h = \"https://\(host)\"")
                .contains { $0.rule == .rule4 }, "\(host)")
        }
    }
}
