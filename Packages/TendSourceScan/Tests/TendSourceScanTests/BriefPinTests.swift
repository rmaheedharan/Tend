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
          `import Network`, `import CFNetwork`, `SFSpeech`, and the session-method calls `dataTask(`, `uploadTask(`,
          `downloadTask(`, `streamTask(`, `webSocketTask(`, `data(for:`, `data(from:`, `bytes(for:`, `bytes(from:`,
          `upload(for:`, `upload(from:`, `download(for:`, `download(from:`, `download(resumeFrom:` (M2 Q24).
        """
    static let briefMethodReferences = """
          - The task-creating names `dataTask`, `uploadTask`, `downloadTask`, `streamTask` and `webSocketTask` also match
            as whole tokens without `(` (method references).
        """
    static let briefMedia = """
        - **Media types:** `AVAudioBuffer`, `AVAudioPCMBuffer`, `AVAudioFile`, `AVAsset`, `CMSampleBuffer`,
          `CVPixelBuffer`, `CVImageBuffer`, `CGImage`, `CIImage`, `UIImage`, `NSImage`.
        """
    static let briefWrite = """
        - **Write APIs:** `write(to:`, `write(toFile:`, `FileManager`, `FileHandle`, `OutputStream`, `createFile(`,
          `UserDefaults`, `NSUbiquitousKeyValueStore`, `AppStorage`, `SceneStorage`, `archiveRootObject(`, `fopen(`,
          `freopen(`, `fdopen(`, `fwrite(`, `fputs(`, `fputc(`, `mkstemp(`, `tmpfile(`, `creat(` (M2 Q24).
        """
    static let briefLog = """
        - **Log APIs:** `print(`, `debugPrint(`, `dump(`, `NSLog(`, `os_log(`, `os_signpost(`, `Logger`, `OSLog`,
          `printf(`, `fprintf(`, `vprintf(`, `vfprintf(`, `dprintf(`, `puts(`, `putc(`, `putchar(`, `perror(`, `syslog(`
          (M2 Q24).
        """
    static let briefRule6Imports = """
          - The only imports are `Foundation`, `SwiftUI`, `CryptoKit` (for the fixtures SHA-256), `TendCore`,
            `TendIngestion` and `TendAI`.
        """
    static let briefRule6ImportHits = """
          - So `Darwin`, `Glibc`, `FoundationNetworking`, `Network`, `CFNetwork`, `os`, `AVFAudio`,
            `UniformTypeIdentifiers` and every third-party module are hits.
        """
    static let briefPositives = """
        - Anywhere: `inputs(`, `snprintf(`, `metadata(for:`, `reprint(`, `data(forKey:`, `append(contentsOf:)` and
          `insert(contentsOf:at:)`.
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
        let names = items.filter { !$0.hasPrefix("import ") && !$0.contains("(") }
        let sessionCalls = items.filter { $0.contains("(") && $0 != "URL(string:" }
        #expect(IngestionSourceRules.addedNetworkingNames == names)
        #expect(IngestionSourceRules.sessionMethodCalls == sessionCalls)                      // M2 Q24
        #expect(sessionCalls.count == 14)
        #expect(IngestionSourceRules.methodReferenceNames == backticked(Self.briefMethodReferences)
            .filter { $0 != "(" })
        #expect(IngestionSourceRules.streamingReadCall == "bytes(for:")
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

    @Test("Pin: the Write APIs and the Log APIs are exactly the brief's two lists (M2 Q24)")
    func writeAndLogPin() {
        let write = backticked(Self.briefWrite)
        let log = backticked(Self.briefLog)
        #expect(Set(IngestionSourceRules.writeNames + IngestionSourceRules.writeCalls) == Set(write))
        #expect(IngestionSourceRules.writeNames.count + IngestionSourceRules.writeCalls.count == write.count)
        #expect(Set(IngestionSourceRules.logNames + IngestionSourceRules.logCalls) == Set(log))
        #expect(IngestionSourceRules.logNames.count + IngestionSourceRules.logCalls.count == log.count)
        // Type names have no `(`; call patterns do.
        #expect(IngestionSourceRules.writeNames.allSatisfy { !$0.contains("(") })
        #expect(IngestionSourceRules.writeCalls.allSatisfy { $0.contains("(") })
        #expect(IngestionSourceRules.logNames.allSatisfy { !$0.contains("(") })
        #expect(IngestionSourceRules.logCalls.allSatisfy { $0.contains("(") })
    }

    @Test("Pin: the Rule 6 import list is exactly the brief's (M2 Q24), and the brief's named hits are not in it")
    func rule6ImportsPin() {
        #expect(IngestionSourceRules.rule6Imports == Set(backticked(Self.briefRule6Imports)))
        for module in backticked(Self.briefRule6ImportHits) {
            #expect(!IngestionSourceRules.rule6Imports.contains(module), "\(module)")
        }
        #expect(backticked(Self.briefRule6ImportHits).count == 8)
    }

    @Test("Brief positives (M2 Q24): inputs(, snprintf(, metadata(for:, reprint(, data(forKey:, append/insert(contentsOf:) pass in every module")
    func briefPositivesPass() {
        let forms = backticked(Self.briefPositives)
        #expect(forms.count == 7)
        // One hand-written call per brief form, in the same order.
        let calls = ["let a = inputs(x)", "let b = snprintf(&buf, 8, f)", "let c = metadata(for: k)",
                     "let d = reprint(x)", "let e = defaults.data(forKey: k)", "xs.append(contentsOf: ys)",
                     "xs.insert(contentsOf: ys, at: 0)"]
        for (form, call) in zip(forms, calls) {
            // The call name and first label of the form: `insert(contentsOf:at:)` → `insert(contentsOf:`.
            let prefix = form.firstIndex(of: ":").map { String(form[...$0]) } ?? form
            #expect(call.contains(prefix), "plant `\(call)` does not use the brief form `\(form)`")
        }
        let code = calls.joined(separator: "\n")
        for (module, path, rule) in [Self.ingestion, Self.adapter, Self.cloud, Self.eval, Self.writer] {
            let found = scan(module, path, code)
            #expect(found.isEmpty, "\(rule) in \(path): \(found)")
        }
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
        // M2 Q24
        ("try s.write(toFile: p, atomically: true, encoding: .utf8)", "write API write(toFile:"),
        ("@AppStorage(\"k\") var key = \"\"", "write API AppStorage"),
        ("@SceneStorage(\"k\") var tab = 0", "write API SceneStorage"),
        ("NSKeyedArchiver.archiveRootObject(x, toFile: p)", "write API archiveRootObject("),
        ("let f = fopen(p, m)", "write API fopen("),
        ("let f = freopen(p, m, stdout)", "write API freopen("),
        ("let f = fdopen(fd, m)", "write API fdopen("),
        ("fwrite(b, 1, n, f)", "write API fwrite("),
        ("fputs(s, f)", "write API fputs("),
        ("fputc(c, f)", "write API fputc("),
        ("let fd = mkstemp(&t)", "write API mkstemp("),
        ("let f = tmpfile()", "write API tmpfile("),
        ("let fd = creat(p, 0o600)", "write API creat("),
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
        // M2 Q24
        ("printf(f, s)", "log API printf("),
        ("fprintf(stderr, f, s)", "log API fprintf("),
        ("vprintf(f, a)", "log API vprintf("),
        ("vfprintf(h, f, a)", "log API vfprintf("),
        ("dprintf(2, f, s)", "log API dprintf("),
        ("puts(s)", "log API puts("),
        ("putc(c, h)", "log API putc("),
        ("putchar(c)", "log API putchar("),
        ("perror(s)", "log API perror("),
        ("syslog(p, f, s)", "log API syslog("),
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
        // M2 Q24 session-method calls.
        ("let t = s.dataTask(with: r)", "networking dataTask("),
        ("let t = s.uploadTask(with: r, from: d)", "networking uploadTask("),
        ("let t = s.downloadTask(with: r)", "networking downloadTask("),
        ("let t = s.streamTask(withHostName: h, port: 1)", "networking streamTask("),
        ("let t = s.webSocketTask(with: r)", "networking webSocketTask("),
        ("let (d, r) = try await s.data(for: q)", "networking data(for:"),
        ("let (d, r) = try await s.data(from: u)", "networking data(from:"),
        ("let (b, r) = try await s.bytes(for: q)", "networking bytes(for:"),
        ("let (b, r) = try await s.bytes(from: u)", "networking bytes(from:"),
        ("let (d, r) = try await s.upload(for: q, from: b)", "networking upload(for:"),
        ("let (d, r) = try await s.upload(from: b)", "networking upload(from:"),
        ("let (u, r) = try await s.download(for: q)", "networking download(for:"),
        ("let (u, r) = try await s.download(from: u)", "networking download(from:"),
        ("let (u, r) = try await s.download(resumeFrom: d)", "networking download(resumeFrom:"),
        // M2 Q24 method references (whole tokens, no `(`).
        ("let f = s.dataTask", "networking dataTask"),
        ("let f = s.uploadTask", "networking uploadTask"),
        ("let f = s.downloadTask", "networking downloadTask"),
        ("let f = s.streamTask", "networking streamTask"),
        ("let f = s.webSocketTask", "networking webSocketTask"),
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

    @Test("Hand-written host plants: only the three brief hosts pass (T-30), bare only in the provider table (R1-F6)")
    func hostPlants() {
        for host in ["api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com"] {
            #expect(scan(.tendIngestion, PlanPaths.providerTable, "let h = \"\(host)\"").isEmpty, "\(host)")
            #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "let h = \"\(host)\"")
                .contains { $0.check == "bare host outside the provider table" }, "\(host)")
            #expect(scan(.tendAI, PlanPaths.transport, "let h = \"https://\(host)\"").isEmpty, "\(host)")
        }
        for host in ["api.example.org", "api.openai.co", "openai.com", "api.anthropic.ai", "googleapis.com",
                     "api.openai.com.evil.io"] {
            #expect(scan(.tendIngestion, PlanPaths.ingestionFile, "let h = \"\(host)\"")
                .contains { $0.rule == .rule4 }, "\(host)")
            #expect(scan(.tendIngestion, PlanPaths.providerTable, "let h = \"\(host)\"")
                .contains { $0.rule == .rule4 }, "\(host)")
            #expect(scan(.tendAI, PlanPaths.transport, "let h = \"https://\(host)\"")
                .contains { $0.rule == .rule4 }, "\(host)")
        }
    }
}
