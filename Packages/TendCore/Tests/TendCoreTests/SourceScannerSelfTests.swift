// Negative tests for the source-scan guard (AC-M1-02, AC-M1-23; nits N-1 and N-2; risk R-2).
// They run the scanner over in-memory fixture strings and prove it reports planted tokens and patterns, ignores
// comments, does not trip on near-misses, and is not fooled by comment markers inside string literals.

import Testing

@Suite("Source scanner self-tests (AC-M1-02, AC-M1-23 negative tests)")
struct SourceScannerSelfTests {

    // MARK: AC-M1-02 vocabulary

    @Test("AC-M1-02 negative: every banned token planted in an identifier is detected",
          arguments: SourceScanner.bannedTokens)
    func bannedTokenInIdentifier(token: String) {
        let capitalised = token.prefix(1).uppercased() + token.dropFirst()
        let fixtures = [
            "let is\(capitalised) = true",               // camelCase hump
            "var \(token)Count = 0",                      // leading lower-case word
            "let HOUSE_\(token.uppercased())_FLAG = 1",   // snake case, upper case
            "case \(token)2",                             // digit split
            "func `\(token)`() {}",                       // backticked identifier
        ]
        for fixture in fixtures {
            let hits = SourceScanner.vocabularyHits(in: fixture, file: "fixture.swift")
            #expect(hits.contains { $0.rule == "token:\(token)" }, "not detected in: \(fixture)")
        }
    }

    @Test("AC-M1-02 negative: every banned token planted in a string literal is detected",
          arguments: SourceScanner.bannedTokens)
    func bannedTokenInStringLiteral(token: String) {
        let fixtures = [
            "let s = \"This is \(token) now\"",
            "let s = \"x\\n\(token)\"",                          // escape decoded, not glued to the token
            "let s = \"\\u{20}\(token)\"",
            "let s = #\"raw \(token) text\"#",
            "let s = \"\"\"\n    multi-line \(token)\n    \"\"\"",
            "let s = #\"\"\"\n    raw multi-line \(token)\n    \"\"\"#",
            "let s = \"before \\(x) \(token) after\"",            // segment after an interpolation
        ]
        for fixture in fixtures {
            let hits = SourceScanner.vocabularyHits(in: fixture, file: "fixture.swift")
            #expect(hits.contains { $0.rule == "token:\(token)" }, "not detected in: \(fixture)")
        }
    }

    @Test("AC-M1-02 negative: whole-token match ignores near-misses (template, latest, translate, relate)")
    func vocabularyNearMisses() {
        let fixture = """
            let template = "latest translate plated"
            let behindhand = 1
            let streaks2 = "debts"
            let unfailed = 0
            let relate = "ballet"
            """
        let hits = SourceScanner.vocabularyHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    @Test("AC-M1-02 negative: banned tokens inside comments are ignored (line, doc, block, nested block)")
    func vocabularyCommentsIgnored() {
        let fixture = """
            // overdue late lateness missed failed behind penalty debt streak
            /// A doc comment that says late.
            /* a block comment: missed
               spanning lines: failed */
            /* outer /* nested penalty */ still comment debt */
            let calm = 1 // trailing comment: streak
            """
        let hits = SourceScanner.vocabularyHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    @Test("N-2: comment markers inside string literals do not hide the rest of the line or file")
    func commentMarkersInsideStrings() {
        let cases: [(fixture: String, expectedToken: String)] = [
            // `//` inside a string is not a comment, so the token after it is still string content.
            ("let s = \"// not a comment: overdue\"", "overdue"),
            // `/*` inside a string must not open a block comment that swallows the next line.
            ("let s = \"/* not a comment\"\nlet isLate = true", "late"),
            // `http://` must not start a comment; the identifier after it is still scanned.
            ("let u = \"http://example\"; let missedTask = 1", "missed"),
            // A quote inside a comment must not start a string that swallows the next line.
            ("// it's a \"quoted thing\nlet behindSchedule = 1", "behind"),
            // Multi-line string with embedded quotes and comment markers.
            ("let s = \"\"\"\n  he said \"hi\" // still the string, failed\n  \"\"\"", "failed"),
            // Raw string with an embedded quote and comment marker.
            ("let s = #\"a \"quoted\" // penalty\"#", "penalty"),
            // Escaped quote does not end the string early.
            ("let s = \"say \\\"hi\\\" then debt\"", "debt"),
            // Code after a closed multi-line string is scanned as code again.
            ("let s = \"\"\"\n  /* text\n  \"\"\"\nlet streakValue = 1", "streak"),
        ]
        for testCase in cases {
            let hits = SourceScanner.vocabularyHits(in: testCase.fixture, file: "fixture.swift")
            #expect(hits.contains { $0.rule == "token:\(testCase.expectedToken)" },
                    "not detected in: \(testCase.fixture)")
        }
    }

    @Test("Scanner tokeniser splits camelCase humps, acronyms, underscores and digits")
    func tokeniser() {
        #expect(SourceScanner.subTokens(of: "isOverdueTask") == ["is", "Overdue", "Task"])
        #expect(SourceScanner.subTokens(of: "URLSession") == ["URL", "Session"])
        #expect(SourceScanner.subTokens(of: "LATE_FEE") == ["LATE", "FEE"])
        #expect(SourceScanner.subTokens(of: "slot2late") == ["slot", "late"])
        #expect(SourceScanner.subTokens(of: "template") == ["template"])
    }

    @Test("Scanner keeps line numbers aligned through comments and multi-line strings")
    func lineNumbers() {
        let fixture = "/* one\n two */\nlet s = \"\"\"\n  x\n  \"\"\"\nlet isLate = 1"
        let hits = SourceScanner.vocabularyHits(in: fixture, file: "fixture.swift")
        #expect(hits.map(\.line) == [6])
    }

    // MARK: AC-M1-23 imports and API patterns

    @Test("AC-M1-23 negative: imports other than Foundation are detected",
          arguments: [
            "import FoundationNetworking",
            "import Network",
            "import CFNetwork",
            "import Dispatch",
            "@testable import Glibc",
            "@preconcurrency import Combine",
            "import struct Foundation.Date",
            "import Foundation; import Darwin",
          ])
    func bannedImports(fixture: String) {
        let hits = SourceScanner.apiHits(in: fixture, file: "fixture.swift")
        #expect(hits.contains { $0.rule == "import" }, "not detected in: \(fixture)")
    }

    @Test("AC-M1-23: `import Foundation` alone is allowed; imports in comments and strings are ignored")
    func allowedImports() {
        let fixture = """
            import Foundation
            @preconcurrency import Foundation
            // import Network
            /* import Dispatch */
            let s = "import FoundationNetworking"
            let importance = 1
            """
        let hits = SourceScanner.apiHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    static let plantedPatterns: [(pattern: String, fixture: String)] = [
        ("Date()", "let now = Date()"),
        ("Date()", "let now = Foundation.Date( )"),
        ("Date.now", "let now = Date.now"),
        ("Date(timeIntervalSinceNow", "let d = Date(timeIntervalSinceNow: 60)"),
        ("timeIntervalSinceNow", "let t = d.timeIntervalSinceNow"),
        ("Calendar.current", "let c = Calendar.current"),
        ("Calendar.autoupdatingCurrent", "let c = Calendar.autoupdatingCurrent"),
        ("TimeZone.current", "let z = TimeZone.current"),
        ("TimeZone.autoupdatingCurrent", "let z = TimeZone.autoupdatingCurrent"),
        ("Locale.current", "let l = Locale.current"),
        ("Locale.autoupdatingCurrent", "let l = Locale.autoupdatingCurrent"),
        ("ProcessInfo", "let p = ProcessInfo.processInfo.environment"),
        ("UUID()", "let id = UUID()"),
        ("SystemRandomNumberGenerator", "var g = SystemRandomNumberGenerator()"),
        (".random( without using:", "let n = Int.random(in: 0..<10)"),
        (".random( without using:", "let b = Bool.random()"),
        (".random( without using:", "let n = Int.random(in: f(1)..<g(2))"),
        (".randomElement( without using:", "let x = xs.randomElement()"),
        (".shuffled( without using:", "let ys = xs.shuffled()"),
        (".shuffle( without using:", "xs.shuffle()"),
        ("URLSession", "let s = URLSession.shared"),
        ("URLRequest", "let r = URLRequest(url: u)"),
        ("URLConnection", "let c: URLConnection? = nil"),
        ("NSURLConnection", "let c: NSURLConnection? = nil"),
        ("Socket", "let s: Socket? = nil"),
        ("NSStream", "let s: NSStream? = nil"),
        ("Stream(", "let s = Stream(data: d)"),
        ("Host(", "let h = Host(name: n)"),
        ("Host.current", "let h = Host.current()"),
        ("http(s) literal", "let u = \"http://example.org\""),
        ("http(s) literal", "let u = \"HTTPS://example.org\""),
        ("http(s) literal", "let u = #\"https://example.org\"#"),
        ("Date()", "let s = \"stamp \\(Date())\""),            // interpolation is code
        ("UUID()", "let s = \"\"\"\n  id \\(UUID())\n  \"\"\""),  // interpolation in a multi-line string
        // Review F-2: explicit `.init` spellings and implicit-member `.now` (no receiver).
        ("Date()", "let d = Date.init()"),
        ("Date()", "let d = Date . init ( )"),
        ("UUID()", "let u = UUID.init()"),
        ("Date(timeIntervalSinceNow", "let d = Date.init(timeIntervalSinceNow: 5)"),
        ("Date.now", "func complete(at now: Date = .now) {}"),
        ("Date.now", "select(from: h, at: .now)"),
        ("Date.now", "let t: Date = .now"),
        ("Date.now", "func f() -> Date { return .now }"),
        ("Date.now", "let t = given ?? .now"),
        ("Date.now", "let ts: [Date] = [.now]"),
        ("Date.now", "let t = flag ? .now : other"),
        ("Date.now", "f(a,.now)"),
        ("Date.now", "if a > .now {}"),
        // Review F-1: networking names at camelCase word boundaries inside identifiers.
        ("URLSession", "let t: URLSessionWebSocketTask? = nil"),
        ("Socket", "let t: URLSessionWebSocketTask? = nil"),
        ("URLSession", "let c = URLSessionConfiguration.default"),
        ("URLSession", "let t: URLSessionDataTask? = nil"),
        ("Socket", "let p = SocketPort(tcpPort: 80)"),
        ("Socket", "let s = CFSocketCreate(nil, 0, 0, 0, 0, nil, nil)"),
        ("Socket", "CFStreamCreatePairWithSocketToHost(nil, h, 80, &r, &w)"),
        ("Host(", "let k = GhostHost(name: n)"),
        ("Socket", "let i = WebSocketLike.self"),
        ("NSStream", "let d: NSStreamDelegate? = nil"),
        ("URLRequest", "var r: NSMutableURLRequest? = nil"),
        // Brief AC-M1-23 additions (Q18).
        ("InputStream(", "let j = InputStream(url: u)"),
        ("Stream(", "let j = InputStream(url: u)"),
        ("OutputStream(", "let o = OutputStream(toMemory: ())"),
        ("getStreamsToHost", "Stream.getStreamsToHost(withName: n, port: 80, inputStream: &i, outputStream: &o)"),
        ("URL(string:", "let u = URL(string: text)"),
        ("URL(string:", "let u = URL.init(string: text)"),
        ("arc4random*", "let n = arc4random()"),
        ("arc4random*", "let n = arc4random_uniform(6)"),
        ("drand48", "let x = drand48()"),
        ("erand48", "let x = erand48(&seed)"),
        ("lrand48", "let x = lrand48()"),
        ("srand48", "srand48(42)"),
        ("rand(", "let x = rand()"),
        ("random()", "let x = random()"),
        // Brief Q19 (review F-8): URL-from-string types, and the URL-loading initialisers (narrowed `contentsOf:`).
        ("NSURL", "let u = NSURL(string: text)"),
        ("NSURL", "let r = NSURLRequest(url: u)"),
        ("NSURL", "let c = NSURLComponents(string: text)"),
        ("URLComponents", "let u = URLComponents(string: text)?.url"),
        ("URLComponents", "var c = URLComponents()"),
        ("CFURL", "let u = CFURLCreateWithString(nil, text as CFString, nil)"),
        ("CFURL", "let u: CFURL? = nil"),
        // Brief Q23 (review GK-1): every `contentsOf:` label outside the allowlisted file, except directly inside
        // `append(` / `insert(`.
        (contentsOf, "let d = try Data(contentsOf: url)"),
        (contentsOf, "let m = try NSMutableData(contentsOf: url)"),
        (contentsOf, "let d: Data = try .init(contentsOf: url)"),
        (contentsOf, "let g = try Gizmo(contentsOf: url)"),
        (contentsOf, "let v = try x.load(contentsOf: url)"),
        (contentsOf, "let d = try Foundation.Data(contentsOf: url)"),
        (contentsOf, "let s = try String(contentsOf: url, encoding: .utf8)"),
        (contentsOf, "let p = XMLParser(contentsOf: url)"),
        (contentsOf, "let d = try Data . init ( contentsOf : url)"),
        (contentsOf, "let m = try NSMutableData.init(contentsOf: url)"),
        (contentsOf, "let t = MyData(contentsOf: url) + Database(contentsOf: x)"),
        (contentsOf, "f(a, contentsOf: url)"),
        (contentsOf, "let r = reader.read(\n    contentsOf: url)"),
        (contentsOf, "xs.append(contentsOf: try Data(contentsOf: url))"),    // the inner call is `Data`
        (contentsOf, "xs.append(load(contentsOf: url))"),                    // the inner call is `load`
        (contentsOf, "xs.appendAll(contentsOf: ys)"),                        // not exactly `append`
        (contentsOf, "xs.Append(contentsOf: ys)"),
        (contentsOf, "xs.insertion(contentsOf: ys, at: 0)"),
        (contentsOf, "let q = items[contentsOf: key]"),                      // a subscript, not a call
        (contentsOf, "let c = { (contentsOf: URL) in 0 }"),                  // not inside a named call
        // Brief Q20 (review F-9): ambient clocks.
        ("DispatchTime", "let t = DispatchTime.now()"),
        ("DispatchTime", "let i: DispatchTimeInterval = .seconds(1)"),
        ("DispatchWallTime", "let t = DispatchWallTime.now()"),
        ("ContinuousClock", "let t = ContinuousClock.now"),
        ("ContinuousClock", "let t = ContinuousClock().now"),
        ("SuspendingClock", "let c = SuspendingClock()"),
        ("mach_absolute_time", "let t = mach_absolute_time()"),
        ("clock_gettime", "clock_gettime(CLOCK_REALTIME, &spec)"),
        ("gettimeofday", "gettimeofday(&tv, nil)"),
        ("CFAbsoluteTimeGetCurrent", "let t = CFAbsoluteTimeGetCurrent()"),
        // Brief Q20: CoreFoundation and POSIX networking.
        ("CFHost", "let h = CFHostCreateWithName(nil, name as CFString)"),
        ("CFReadStream", "CFReadStreamCreateWithFTPURL(nil, u)"),
        ("CFWriteStream", "let w: CFWriteStream? = nil"),
        ("CFSocket", "let s = CFSocketCreate(nil, 0, 0, 0, 0, nil, nil)"),
        ("socket(", "let fd = socket(AF_INET, SOCK_STREAM, 0)"),
        ("socket(", "let fd = Glibc.socket(2, 1, 0)"),
        ("getaddrinfo", "getaddrinfo(host, nil, &hints, &result)"),
        ("gethostbyname", "let h = gethostbyname(name)"),
        ("gethostbyname", "let h = gethostbyname2(name, AF_INET6)"),
        // Review F-7: the explicit `.init(` spelling of the call names.
        ("Host(", "let h = Host.init(name: n)"),
        ("Host(", "let h = Host . init (name: n)"),
        ("InputStream(", "let j = InputStream.init(url: u)"),
        ("Stream(", "let j = Stream.init()"),
        ("Stream(", "let s = MyAsyncStream.init(Int.self)"),
        ("OutputStream(", "let o = OutputStream.init(toMemory: ())"),
    ]

    static let contentsOf = SourceScanner.contentsOfRule

    @Test("AC-M1-23 negative: every banned pattern planted in code is detected",
          arguments: plantedPatterns.indices)
    func bannedPatternDetected(index: Int) {
        let planted = Self.plantedPatterns[index]
        let hits = SourceScanner.apiHits(in: planted.fixture, file: "fixture.swift")
        #expect(hits.contains { $0.rule == planted.pattern },
                "pattern \(planted.pattern) not detected in: \(planted.fixture); hits: \(hits)")
    }

    @Test("AC-M1-23 coverage: the planted fixtures exercise every pattern in the closed list")
    func plantedFixturesCoverClosedList() {
        let planted = Set(Self.plantedPatterns.map(\.pattern))
        var expected = Set(SourceScanner.identifierPatterns.map(\.name))
        expected.formUnion(SourceScanner.networkingNames)
        expected.formUnion(SourceScanner.clockNames)
        expected.formUnion(SourceScanner.networkingCallNames.map { "\($0)(" })
        expected.formUnion(SourceScanner.randomCallNames.map { ".\($0)( without using:" })
        expected.formUnion(["Host.current", "http(s) literal", SourceScanner.contentsOfRule])
        #expect(planted == expected)
    }

    @Test("N-1: near-misses at identifier and camelCase word boundaries are not reported")
    func patternNearMisses() {
        let fixture = """
            import Foundation
            let a = startDate()
            let b = makeUUID()
            let c = Calendar.currentWeek
            let d = myCalendar.current
            let e = TimeZone.currentOffset
            let f = Date.nowish
            let g = startDate(timeIntervalSince: other)
            let g2 = d.timeIntervalSinceNowish
            let h = MyProcessInfo()
            let i = Sockets.self
            let j = XURLSessionLike.self
            let k = upstream(data: x)
            let k2 = Hostname(value: n)
            let k3 = Host.currently
            let k4 = operand(x) + brand(y)
            let k5 = randomize(xs) + arc(4) + drand(48)
            let k6 = URL(fileURLWithPath: path)
            let k7 = myURL(string: s)
            let k8 = contentsOfFile
            let k9 = try String(contentsOfFile: path)
            var r1 = xs; r1.append(contentsOf: ys)
            r1.insert(contentsOf: zs, at: 0)
            r1.replaceSubrange(0..<1, with: zs)
            r1.append (contentsOf: (0..<3).map { f($0) })
            self.insert(
                contentsOf: [g(1), g(2)], at: r1.count)
            append(contentsOf: [h("(") ])
            let r3 = NSURLish + nsurl + myNSURLx + fileURLComponent + CFURLish
            let r4 = DispatchTimer() + ContinuousClockwise + timeOfDay + getTimeOfDay() + machAbsoluteTime
            let r5 = CFHostname + freeaddrinfo(p) + hostbyname
            let socket = 1
            let r6 = websocket(x) + sockets(y) + socketCount
            let r7 = Hostess.init(x) + upstream.init(y) + Host.initial
            let l = Int.random(in: 0..<3, using: &generator)
            let m = xs.randomElement(using: &generator)
            let n = xs.shuffled(using: &generator)
            xs.shuffle(using: &generator)
            let o = Int.random(in: f(1)..<g(2), using: &generator)
            let p = Date(timeIntervalSinceReferenceDate: 0)
            let q = randomize(xs)
            """
        let hits = SourceScanner.apiHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    @Test("AC-M1-23 negative: banned patterns in comments and plain string text are ignored")
    func patternsInCommentsAndStringsIgnored() {
        let fixture = """
            // let now = Date()
            /// Uses Calendar.current in the docs only. See https://example.org
            /* URLSession.shared */
            let label = "Date() and UUID() and ProcessInfo as plain text"
            """
        let hits = SourceScanner.apiHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    @Test("Review F-2: `.now` with a receiver is not reported (moment.now, self.now, chains, optional chaining)")
    func nowWithReceiverNotReported() {
        let fixture = """
            let a = moment.now
            let b = self.now
            let c = context.now
            let d = makeMoment().now
            let e = moments[0].now
            let f = maybe?.now
            let g = forced!.now
            let h = Box<Int>.now
            let i = moment
                .now
            let j = Date.nowish
            let k = x.nowhere
            """
        let hits = SourceScanner.apiHits(in: fixture, file: "fixture.swift")
        #expect(hits.isEmpty, "unexpected hits: \(hits)")
    }

    @Test("AC-M1-23 positive: AsyncStream( and AsyncThrowingStream( (Q17), any contentsOf: in the allowlisted file (Q18, Q23) and append/insert(contentsOf:) (Q23) are not reported")
    func exemptionsAndAllowlistNotReported() {
        let exempt = """
            let s = AsyncStream(Int.self) { continuation in continuation.finish() }
            let t = AsyncThrowingStream(Int.self) { continuation in continuation.finish() }
            let u = AsyncStream<Int> { continuation in continuation.finish() }
            let v = AsyncStream.init(Int.self) { continuation in continuation.finish() }
            let w = AsyncThrowingStream.init(Int.self) { continuation in continuation.finish() }
            """
        #expect(SourceScanner.apiHits(in: exempt, file: "fixture.swift").isEmpty)

        // Exactly two names: anything else ending in `Stream(` is still reported.
        let notExempt = "let s = MyAsyncStream(Int.self)"
        #expect(SourceScanner.apiHits(in: notExempt, file: "fixture.swift").contains { $0.rule == "Stream(" })

        let read = "let data = try Data(contentsOf: fileURL); let m = NSMutableData(contentsOf: fileURL); x.load(contentsOf: u)"
        for allowlisted in SourceScanner.contentsOfAllowlist {
            let path = "Sources/TendCore/Persistence/\(allowlisted)"
            #expect(SourceScanner.apiHits(in: read, file: path).isEmpty, "\(path) is allowlisted")
        }
        #expect(SourceScanner.contentsOfAllowlist == ["JSONFileHouseholdRepository.swift"])
        // The allowlist covers only `contentsOf:`; other rules still apply in that file.
        let otherRule = "let u = URL(string: text)"
        #expect(!SourceScanner.apiHits(in: otherRule, file: "Sources/TendCore/JSONFileHouseholdRepository.swift")
            .isEmpty)
        // A file with a different name is not allowlisted.
        #expect(SourceScanner.apiHits(in: read, file: "Sources/TendCore/Model/Household.swift")
            .contains { $0.rule == SourceScanner.contentsOfRule })

        // Q23: `contentsOf:` directly inside a call named `append` or `insert` (with or without a receiver) is allowed in
        // any file.
        let collections = """
            var xs = [1]
            xs.append(contentsOf: [2, 3])
            xs.insert(contentsOf: [0], at: 0)
            var text = "a"
            text.append(contentsOf: "bc")
            text.insert(contentsOf: "z", at: text.startIndex)
            append(contentsOf: [4])
            insert(contentsOf: [5], at: 0)
            xs.append(
                contentsOf: [6, 7].map { $0 * (1 + 1) })
            """
        #expect(SourceScanner.apiHits(in: collections, file: "Sources/TendCore/Model/Household.swift").isEmpty)
    }
}
