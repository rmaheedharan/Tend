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
    ]

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
        var expected = Set(SourceScanner.bannedAPIPatterns.map(\.name))
        expected.formUnion(SourceScanner.randomCallNames.map { ".\($0)( without using:" })
        expected.insert("http(s) literal")
        #expect(planted == expected)
    }

    @Test("N-1: near-misses at identifier boundaries are not reported")
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
            let i = WebSocketLike.self
            let j = InputStream(data: x)
            let k = GhostHost(name: n)
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
}
