// AC-M2-09 Rule 6, PO decision M2 Q23: the fixtures-loader exception. Exactly one file, the fixtures loader named in
// the plan (`Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift`), may read bundled fixtures with
// `Data(contentsOf: <name>)`, under every condition the brief lists. Every plant and positive the brief names for Q23
// is here, written by hand from the brief text, plus one plant per condition so that each condition has its own test.
// P-2, P-4.

import Testing
import TendSourceScan

/// The functions of a fixtures-loader file that follows every Q23 condition: the plan's Developer constraint (one
/// literal `Bundle.main.url(forResource:` per fixture), in each of the three binding forms the brief allows.
let q23LoaderFunctions: [String] = [
    """
        static func inputs() throws -> Data {
            guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else {
                throw LoaderError.missing
            }
            return try Data(contentsOf: inputsFile)
        }
    """,
    """
        static func household() throws -> Data {
            if let householdFile = Bundle.main.url(forResource: "household", withExtension: "json",
                                                   subdirectory: "eval") {
                return try Data(contentsOf: householdFile)
            }
            throw LoaderError.missing
        }
    """,
    """
        static func goldenSet() throws -> Data {
            let goldenFile = Bundle.main.url(forResource: "golden_v1", withExtension: "json")
            return try Data(contentsOf: goldenFile)
        }
    """,
    """
        static func manifest() throws -> Data {
            guard let manifestFile = Bundle.main.url(forResource: "MANIFEST", withExtension: "sha256") else {
                throw LoaderError.missing
            }
            return try Data(contentsOf: manifestFile)
        }
    """,
]

/// The whole loader file built from `functions`.
func q23LoaderFile(_ functions: [String]) -> String {
    """
    import Foundation
    import CryptoKit

    enum LoaderError: Error { case missing }

    /// The bundled eval fixtures (WI-M2-16). Each is read by its own literal bundle lookup.
    enum EvalFixturesLoader {
    \(functions.joined(separator: "\n\n"))
    }
    """
}

/// A loader function whose argument is not one plain identifier (`goldFile!`) and whose name occurs three times.
let q23BadLoaderFunction = """
        static func golden() throws -> Data {
            let goldFile = Bundle.main.url(forResource: "golden", withExtension: "json")
            guard goldFile != nil else { throw LoaderError.missing }
            return try Data(contentsOf: goldFile!)
        }
    """

func scanLoader(_ code: String) -> [RuleViolation] {
    scan(.tendEval, PlanPaths.fixturesLoader, code)
}

/// The brief's exact positive (AC-M2-09, "Positive (not reported)").
let q23BriefPositive = """
    guard let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") else { throw LoaderError.missing }; return try Data(contentsOf: u)
    """

@Suite("AC-M2-09 Rule 6, M2 Q23: the fixtures-loader exception")
struct Q23LoaderTests {

    // MARK: Pins (brief text, copied verbatim)

    static let briefBundleHits = """
          - The only use of `Bundle` is `Bundle.main.url(forResource:`. `Bundle(`, `.resourceURL`, `.bundleURL`,
            `.urls(forResourcesWithExtension:`, `.path(forResource:`, `appendingPathComponent(`, `appending(path:`,
            `appending(component:` and `deletingLastPathComponent` are hits.
        """
    static let briefArgumentRules = """
          - The `forResource:` and `subdirectory:` arguments are string literals matching `^[A-Za-z0-9_-]+$`.
          - The `withExtension:` argument, if present, is a string literal matching `^[A-Za-z0-9]+$`.
        """
    static let briefLoaderPath = """
          (`Apps/TendEval/Sources/Fixtures/EvalFixturesLoader.swift`), may read bundled fixtures with `Data(contentsOf:`.
        """

    @Test("Pin (M2 Q23): the loader's named hits, argument patterns and file path are exactly the brief's")
    func loaderPins() {
        let hits = backticked(Self.briefBundleHits)
        #expect(hits.first == "Bundle")
        #expect(hits.dropFirst().first == "Bundle.main.url(forResource:")
        // `Bundle(` is reported by the Bundle-use check; every other named hit is its own pattern.
        #expect(IngestionSourceRules.loaderNamedHits == Array(hits.dropFirst(3)))
        #expect(hits[2] == "Bundle(")
        let arguments = backticked(Self.briefArgumentRules)
        #expect(arguments == ["forResource:", "subdirectory:", "^[A-Za-z0-9_-]+$", "withExtension:", "^[A-Za-z0-9]+$"])
        #expect(IngestionSourceRules.loaderResourceNamePattern == arguments[2])
        #expect(IngestionSourceRules.loaderExtensionPattern == arguments[4])
        #expect(backticked(Self.briefLoaderPath).first == PlanPaths.fixturesLoader)
    }

    @Test("AC-M2-09 M2 Q23: the argument patterns accept and reject exactly as the brief's regexes", arguments: [
        ("fixtures", true, true), ("golden_v1", true, false), ("eval-1", true, false), ("MANIFEST", true, true),
        ("x.json", false, false), ("../x", false, false), ("", false, false), ("a b", false, false),
        ("a\nb", false, false), ("fixtures\n", false, false), ("fixtüres", false, false), ("js-on", true, false),
        ("sha256", true, true),
    ])
    func argumentPatterns(text: String, resourceOK: Bool, extensionOK: Bool) {
        let decoded = text.replacingOccurrences(of: "\\n", with: "\n")
        #expect(IngestionSourceRules.isLoaderResourceName(decoded) == resourceOK, "\(text)")
        #expect(IngestionSourceRules.isLoaderExtension(decoded) == extensionOK, "\(text)")
    }

    // MARK: Positive (brief)

    @Test("AC-M2-09 M2 Q23 positive: the brief's exact loader form passes in the loader file")
    func briefPositivePasses() {
        let found = scanLoader(q23BriefPositive)
        #expect(found.isEmpty, "\(found)")
    }

    @Test("AC-M2-09 M2 Q23 positive: the brief's form inside a function, in each of the three binding forms", arguments: [
        """
        func inputs() throws -> Data {
            guard let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") else { throw LoaderError.missing }
            return try Data(contentsOf: u)
        }
        """,
        """
        func inputs() throws -> Data {
            if let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") {
                return try Data(contentsOf: u)
            }
            throw LoaderError.missing
        }
        """,
        """
        func inputs() throws -> Data {
            let u = Bundle.main.url(forResource: "fixtures", withExtension: "json", subdirectory: "eval-1")
            return try Data(contentsOf: u)
        }
        """,
        """
        func inputs() throws -> Data {
            guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
            return try Data(contentsOf: u)
        }
        """,
        """
        func inputs() throws -> Data {
            guard let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") else { throw LoaderError.missing }
            var xs: [UInt8] = []
            xs.append(contentsOf: [1])
            return try Data(contentsOf: u)
        }
        """,
    ])
    func bindingFormsPass(code: String) {
        let found = scanLoader(code)
        #expect(found.isEmpty, "\(found)")
    }

    @Test("AC-M2-09 M2 Q23 positive: a whole loader file with four fixtures, each with its own literal lookup, passes")
    func wholeLoaderFilePasses() {
        let found = scanLoader(q23LoaderFile(q23LoaderFunctions))
        #expect(found.isEmpty, "\(found)")
        // One extra function that breaks the rule is caught, and only that function's read is reported.
        let bad = scanLoader(q23LoaderFile(q23LoaderFunctions + [q23BadLoaderFunction]))
        #expect(bad.filter { $0.check.contains("contentsOf:") }.count == 1, "\(bad)")
        #expect(bad.allSatisfy { $0.rule == .rule6 }, "\(bad)")
    }

    // MARK: Only the loader file (brief "Also caught"; "Everywhere else … contentsOf: is banned")

    @Test("AC-M2-09 M2 Q23: the brief's loader form is still caught in every other file of the three modules")
    func loaderFormCaughtElsewhere() {
        let locations: [(ScannedModule, String, IngestionScanRule)] = [
            (.tendEval, PlanPaths.evalFile, .rule6),
            (.tendEval, PlanPaths.resultsWriter, .rule6),
            (.tendEval, "Apps/TendEval/Sources/Fixtures/EvalFixturesLoader2.swift", .rule6),
            (.tendEval, "Apps/TendEval/Sources/EvalFixturesLoader.swift", .rule6),
            (.tendAI, PlanPaths.aiFile, .rule2),
            (.tendAI, PlanPaths.transport, .rule3),
            (.tendIngestion, PlanPaths.ingestionFile, .rule1),
            // The loader's path under another module is not the loader.
            (.tendAI, PlanPaths.fixturesLoader, .rule2),
        ]
        for (module, path, rule) in locations {
            let found = scan(module, path, q23BriefPositive)
            #expect(found.contains { $0.rule == rule && $0.check.contains("contentsOf:") }, "\(path): \(found)")
        }
    }

    // MARK: Caught in the fixtures-loader file (brief, verbatim plants)

    @Test("AC-M2-09 M2 Q23: each of the brief's plants is caught in the fixtures-loader file", arguments: [
        "func load(_ u: URL) throws -> Data { try Data(contentsOf: u) }",
        "let r = Bundle.main.resourceURL!.appendingPathComponent(\"x.json\")",
        "let r = Bundle.main.url(forResource: \"../x\", withExtension: \"json\")",
        "let s = try String(contentsOf: u)",
        "let u = URL(fileURLWithPath: \"/tmp/x.json\")",
        "let u = NSURL(fileURLWithPath: \"/tmp/x.json\")",
        """
        func load(_ u: Path) throws -> Data { try Data(contentsOf: u) }
        let u = Bundle.main.url(forResource: "fixtures", withExtension: "json")
        """,
    ])
    func briefPlantsCaught(code: String) {
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 }, "`\(code)`: \(found)")
    }

    @Test("AC-M2-09 M2 Q23: NSURL(fileURLWithPath:) in the loader is caught by the networking list")
    func nsurlCaughtByNetworkingList() {
        #expect(scanLoader("let u = NSURL(fileURLWithPath: \"/tmp/x.json\")")
            .contains { $0.rule == .rule6 && $0.check == "networking NSURL" })
    }

    @Test("AC-M2-09 M2 Q23: the brief's parameter plant is caught as a parameter, a reused name and a contentsOf: hit")
    func parameterPlantReasons() {
        let found = scanLoader("""
            func load(_ u: Path) throws -> Data { try Data(contentsOf: u) }
            let u = Bundle.main.url(forResource: "fixtures", withExtension: "json")
            """)
        #expect(found.contains { $0.check == "fixtures loader: parameter declared (func)" }, "\(found)")
        #expect(found.contains { $0.check == "networking contentsOf:" }, "\(found)")
    }

    // MARK: One plant per condition

    /// Each condition of the brief's Q23 text, planted on its own in a file that is otherwise the brief's positive,
    /// with the check that must report it. (description, code, check fragment)
    static let conditionPlants: [(String, String, String)] = [
        // "The only contentsOf: form is Data(contentsOf: <name>) … one plain identifier and there are no other args."
        ("extra argument", wrap("return try Data(contentsOf: u, options: .mappedIfSafe)"), "contentsOf:"),
        ("force unwrap", wrap("return try Data(contentsOf: u!)"), "contentsOf:"),
        ("member argument", wrap("return try Data(contentsOf: self.u)"), "contentsOf:"),
        ("qualified Data", wrap("return try Foundation.Data(contentsOf: u)"), "contentsOf:"),
        ("Data.init", wrap("return try Data.init(contentsOf: u)"), "contentsOf:"),
        ("lower-case data (case-sensitive)", wrap("return try data(contentsOf: u)"), "contentsOf:"),
        ("NSData", wrap("return try NSData(contentsOf: u)"), "contentsOf:"),
        ("String(contentsOf:", wrap("return try String(contentsOf: u)"), "contentsOf:"),
        ("implicit member .init", wrap("let d: Data = try .init(contentsOf: u); return d"), "contentsOf:"),
        // "The loader returns the bytes as Data and keeps nothing."
        ("result kept in a local", wrap("let d = try Data(contentsOf: u); return d"), "contentsOf:"),
        ("result transformed", wrap("return try Data(contentsOf: u).base64EncodedData()"), "contentsOf:"),
        ("result transformed on next line", wrap("return try Data(contentsOf: u)\n    .base64EncodedData()"),
         "contentsOf:"),
        ("result stored", "static var cache = Data()\n" + wrap("cache = try Data(contentsOf: u); return cache"),
         "contentsOf:"),
        // "bound in the same file by let / guard let / if let <name> = Bundle.main.url(forResource:"
        ("var binding", """
            func f() throws -> Data {
                var u = Bundle.main.url(forResource: "fixtures", withExtension: "json")
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
        ("while let binding", """
            func f() throws -> Data {
                while let u = Bundle.main.url(forResource: "fixtures", withExtension: "json") {
                    return try Data(contentsOf: u)
                }
                throw LoaderError.missing
            }
            """, "contentsOf:"),
        ("second if-let clause", """
            func f() throws -> Data {
                if let a = Bundle.main.url(forResource: "a"), let u = Bundle.main.url(forResource: "fixtures") {
                    return try Data(contentsOf: u)
                }
                throw LoaderError.missing
            }
            """, "contentsOf:"),
        ("bound from another value", """
            func f() throws -> Data {
                guard let u = other else { throw LoaderError.missing }
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
        ("bound through a helper", """
            func f() throws -> Data {
                guard let u = Bundle.main.url(forResource: "fixtures").map({ $0 }) else { throw LoaderError.missing }
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
        ("not bound at all", "func f() throws -> Data { return try Data(contentsOf: u) }", "contentsOf:"),
        // "<name> is bound exactly once in the file, in the same function body and before the call."
        ("bound twice in the file", wrap(name: "f") + "\n" + wrap(name: "g"), "contentsOf:"),
        ("rebound in the same body", """
            func f() throws -> Data {
                guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                let w = u
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
        ("bound after the call", """
            func f() throws -> Data {
                return try Data(contentsOf: u)
                let u = Bundle.main.url(forResource: "fixtures")
            }
            """, "contentsOf:"),
        ("bound in another function", """
            func g() { let u = Bundle.main.url(forResource: "fixtures") }
            func f() throws -> Data {
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
        ("bound as a stored property", """
            struct Loader {
                let u = Bundle.main.url(forResource: "fixtures")
                func f() throws -> Data {
                    return try Data(contentsOf: u)
                }
            }
            """, "contentsOf:"),
        ("call in a nested closure", """
            func f() throws -> Data {
                guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                let read = { return try Data(contentsOf: u) }
                return try read()
            }
            """, "contentsOf:"),
        // "No function, initialiser, subscript or closure in the loader file declares a parameter."
        ("function parameter", "func f(name: String) -> Int { 0 }\n" + wrap(), "parameter declared"),
        ("generic function parameter", "func f<T>(_ x: T) -> Int { 0 }\n" + wrap(), "parameter declared"),
        ("initialiser parameter", "struct S { init(x: Int) {} }\n" + wrap(), "parameter declared"),
        ("failable initialiser parameter", "struct S { init?(x: Int) { nil } }\n" + wrap(), "parameter declared"),
        ("subscript parameter", "struct S { subscript(i: Int) -> Int { i } }\n" + wrap(), "parameter declared"),
        ("closure parameter", "let f = { (x: Int) in x }\n" + wrap(), "parameter declared"),
        ("closure shorthand parameter list", "let f: (Int) -> Int = { x in x }\n" + wrap(), "parameter declared"),
        ("closure implicit parameter", "let f: (Int) -> Int = { $0 }\n" + wrap(), "parameter declared"),
        ("accessor parameter", "var v = 0 { didSet(old) { } }\n" + wrap(), "parameter declared"),
        // "The whole token URL does not occur."
        ("URL type annotation", wrap("let x: URL = u; return try Data(contentsOf: u)"), "token URL"),
        ("URL( initialiser", "let t = URL(fileURLWithPath: \"/tmp/x.json\")\n" + wrap(), "token URL"),
        ("backticked URL", "let t = `URL`.self\n" + wrap(), "token URL"),
        // "The only use of Bundle is Bundle.main.url(forResource:." and the brief's named hits.
        ("Bundle(", "let b = Bundle(for: S.self)\n" + wrap(), "Bundle"),
        ("Bundle.main alone", "let b = Bundle.main\n" + wrap(), "Bundle"),
        ("qualified Bundle", wrap(qualifiedBundle: true), "Bundle"),
        ("Bundle(identifier:)", "let b = Bundle(identifier: \"com.tend.eval\")\n" + wrap(), "Bundle"),
        ("other bundle type", "let b = CFBundleGetMainBundle()\n" + wrap(), "Bundle"),
        ("url(forResource: on another receiver", "let x = thing.url(forResource: \"a\")\n" + wrap(), "forResource"),
        (".resourceURL", "let r = Bundle.main.resourceURL\n" + wrap(), "resourceURL"),
        (".bundleURL", "let r = Bundle.main.bundleURL\n" + wrap(), "bundleURL"),
        (".urls(forResourcesWithExtension:", "let r = Bundle.main.urls(forResourcesWithExtension: \"json\", subdirectory: nil)\n"
            + wrap(), "urls(forResourcesWithExtension:"),
        (".path(forResource:", "let r = Bundle.main.path(forResource: \"a\", ofType: \"json\")\n" + wrap(),
         "path(forResource:"),
        ("appendingPathComponent(", "let r = base.appendingPathComponent(\"x.json\")\n" + wrap(),
         "appendingPathComponent("),
        ("appending(path:", "let r = base.appending(path: \"x.json\")\n" + wrap(), "appending(path:"),
        ("appending(component:", "let r = base.appending(component: \"x.json\")\n" + wrap(), "appending(component:"),
        ("deletingLastPathComponent", "let r = base.deletingLastPathComponent()\n" + wrap(),
         "deletingLastPathComponent"),
        // "The forResource: and subdirectory: arguments are string literals matching ^[A-Za-z0-9_-]+$."
        ("resource name with a dot", wrap(resource: "\"x.json\""), "resource argument"),
        ("resource name with a slash", wrap(resource: "\"eval/x\""), "resource argument"),
        ("resource name ../", wrap(resource: "\"../x\""), "resource argument"),
        ("empty resource name", wrap(resource: "\"\""), "resource argument"),
        ("resource name with a space", wrap(resource: "\"a b\""), "resource argument"),
        ("resource name with a newline escape", wrap(resource: "\"a\\nb\""), "resource argument"),
        ("resource name escape that decodes to ../", wrap(resource: "\"\\u{2E}\\u{2E}/x\""), "resource argument"),
        ("non-ASCII resource name", wrap(resource: "\"fixtüres\""), "resource argument"),
        ("identifier resource name", wrap(resource: "name"), "resource argument"),
        ("array element resource name", wrap(resource: "names[0]"), "resource argument"),
        ("literal array element", wrap(resource: "[\"fixtures\"][0]"), "resource argument"),
        ("interpolated resource name", wrap(resource: "\"fix\\(n)\""), "resource argument"),
        ("concatenated resource name", wrap(resource: "\"fix\" + \"tures\""), "resource argument"),
        ("multi-line resource name", wrap(resource: "\"\"\"\n    fixtures\n    \"\"\""), "resource argument"),
        ("subdirectory with a slash", wrap(extra: ", subdirectory: \"a/b\""), "resource argument"),
        ("subdirectory identifier", wrap(extra: ", subdirectory: dir"), "resource argument"),
        ("subdirectory nil", wrap(extra: ", subdirectory: nil"), "resource argument"),
        // "The withExtension: argument, if present, is a string literal matching ^[A-Za-z0-9]+$."
        ("extension with a dot", wrap(ext: "\"js.on\""), "resource argument"),
        ("extension with a dash", wrap(ext: "\"js-on\""), "resource argument"),
        ("extension identifier", wrap(ext: "ext"), "resource argument"),
        ("extension nil", wrap(ext: "nil"), "resource argument"),
        ("empty extension", wrap(ext: "\"\""), "resource argument"),
        // Only the brief's three labels, `forResource:` first.
        ("localization argument", wrap(extra: ", localization: \"en\""), "resource argument"),
        ("no forResource: label", "let x = Bundle.main.url(\"fixtures\")\n" + wrap(), "resource argument"),
        // "No literal contains ://."
        ("scheme literal", "let s = \"file://x\"\n" + wrap(), "://"),
        ("scheme split by interpolation", "let s = \"file:/\\(a)/x\"\n" + wrap(), "://"),
        // "No write or log API occurs."
        ("write API", wrap("try Data().write(to: u); return try Data(contentsOf: u)"), "write API write(to:"),
        ("FileManager", "let m = FileManager.default\n" + wrap(), "write API FileManager"),
        ("log API", "print(1)\n" + wrap(), "log API print("),
        // PR #51 review F4: plants that isolate conditions the other plants cover only together.
        ("bound after the read, read ended by ;", """
            func f() throws -> Data {
                return try Data(contentsOf: u); let u = Bundle.main.url(forResource: "fixtures")
            }
            """, "contentsOf:"),
        ("literal inside an interpolation", wrap(resource: "\"\\(\"fixtures\")\""), "resource argument"),
        // Not valid Swift; only the interpolation flag rejects it (defence in depth: the code inside is blank).
        ("empty interpolation", wrap(resource: "\"fix\\( )tures\""), "resource argument"),
        // Only the statement-start check rejects it: `let` follows an attribute, not a statement boundary.
        ("binding after an attribute", """
            func f() throws -> Data {
                nonisolated(unsafe) let u = Bundle.main.url(forResource: "fixtures")
                return try Data(contentsOf: u)
            }
            """, "contentsOf:"),
    ]

    /// PR #51 review round 2, F7: `bindingEnds` on its own. The value would be `fallback`, not the bundle lookup.
    static let fallbackPlants: [String] = [
        """
        func f() throws -> Data {
            let u = Bundle.main.url(forResource: "inputs") ?? fallback
            return try Data(contentsOf: u)
        }
        """,
        """
        func f() throws -> Data {
            let u = Bundle.main.url(forResource: "inputs")
                ?? fallback
            return try Data(contentsOf: u)
        }
        """,
    ]

    @Test("AC-M2-09 M2 Q23 (PR #51 F7): a let binding with ?? fallback, on the same line or the next, is not a binding",
          arguments: fallbackPlants)
    func fallbackPlantCaught(code: String) {
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 && $0.check == "networking contentsOf:" }, "\(found)")
    }

    /// PR #51 review round 2, F6: a regex literal can make the lexer read a quote as the start of a string and hide
    /// directive lines or calls. In the loader file any `/` left in code is reported, and no read is allowed.
    static let slashPlants: [(String, String)] = [
        ("R01: #if hidden by /\"\"\"/ regex literals", """
            static func inputs() throws -> Data {
                _ = /\"\"\"/
            #if NEVER_DEFINED
                _ = /\"\"\"/
                guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else { throw LoaderError.missing }
                _ = /\"\"\"/
            #endif
                _ = /\"\"\"/
                return try Data(contentsOf: inputsFile)
            }
            """),
        ("P08: a call hidden by /\"/ regex literals",
         "let a = /\"/, b = try String(contentsOf: Bundle.main.resourceURL!), c = /\"/\n" + wrap()),
        ("plain regex literal", "let r = /fixtures/\n" + wrap()),
        ("division", "let half = 4 / 2\n" + wrap()),
    ]

    @Test("AC-M2-09 M2 Q23 (PR #51 F6): any / left in code in the loader file is reported, and no read is allowed",
          arguments: slashPlants.indices)
    func slashPlantCaught(index: Int) {
        let (description, code) = Self.slashPlants[index]
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 && $0.check.contains("slash") }, "\(description): \(found)")
        #expect(found.contains { $0.check.contains("contentsOf:") }, "\(description): \(found)")
    }

    @Test("AC-M2-09 M2 Q23 (PR #51 F6): / in comments and string text is not reported")
    func slashInCommentsAndStrings() {
        let code = "// a / b\n/* c / d */\n/// e/f\nlet s = \"g/h\"\n" + Self.wrap()
        let found = scanLoader(code)
        #expect(found.isEmpty, "\(found)")
    }

    @Test("AC-M2-09 M2 Q23 (PR #51 N1 a): a closure on the line after `repeat { } while false` is a closure, not a while block")
    func closureAfterRepeatWhile() {
        let code = """
            func f() throws -> Data {
                guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                repeat { } while false
                let g = { return try Data(contentsOf: u) }
                return try g()
            }
            """
        #expect(scanLoader(code).contains { $0.check == "networking contentsOf:" })
    }

    /// PR #51 review F1 (Major): compiler directives in the loader file. An inactive `#if` hides a binding from the
    /// compiler, so the read could resolve to a same-named value declared in another TendEval file. Every directive
    /// and every `#name` (fail closed) is reported, and the read is not allowed. (description, code)
    static let directivePlants: [(String, String)] = [
        ("#if around the binding (the review's proof)", """
            static func inputs() throws -> Data {
            #if NEVER_DEFINED
                guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else { throw LoaderError.missing }
            #endif
                return try Data(contentsOf: inputsFile)
            }
            """),
        ("#if around the read", """
            static func inputs() throws -> Data {
                guard let inputsFile = Bundle.main.url(forResource: "inputs", withExtension: "json") else { throw LoaderError.missing }
            #if NEVER_DEFINED
                return try Data(contentsOf: inputsFile)
            #else
                throw LoaderError.missing
            #endif
            }
            """),
        ("#elseif", "#if A\n#elseif B\n#endif\n" + wrap()),
        ("indented #if", "    #if DEBUG\n    #endif\n" + wrap()),
        ("#sourceLocation", "#sourceLocation(file: \"x.swift\", line: 1)\n" + wrap()),
        ("other # directive", "#warning(\"x\")\n" + wrap()),
        ("spaced directive", "# if A\n# endif\n" + wrap()),
    ]

    @Test("AC-M2-09 M2 Q23 (PR #51 F1): every compiler directive in the loader file is reported, and a read next to one is not allowed",
          arguments: directivePlants.indices)
    func directivePlantCaught(index: Int) {
        let (description, code) = Self.directivePlants[index]
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 && $0.check.contains("compiler directive") },
                "\(description): \(found)")
    }

    @Test("AC-M2-09 M2 Q23 (PR #51 F1): the review's #if proof also leaves the read reported as a contentsOf: hit")
    func directiveProofReadCaught() {
        let found = scanLoader(Self.directivePlants[0].1)
        #expect(found.contains { $0.check == "networking contentsOf:" }, "\(found)")
    }

    @Test("AC-M2-09 M2 Q23 (PR #51 F1): # in comments and raw string delimiters is not a directive")
    func hashInCommentsAndRawStrings() {
        let code = "// #if NEVER\n/* #endif */\nlet s = #\"raw\"#\n" + Self.wrap()
        let found = scanLoader(code)
        #expect(found.isEmpty, "\(found)")
    }

    /// PR #51 review F2: the binding must be in scope at the read. Each of these reads an outer name, not the binding.
    static let scopePlants: [(String, String)] = [
        ("empty if-let block, read after it", """
            func f() throws -> Data {
                if let u = Bundle.main.url(forResource: "fixtures") { }
                return try Data(contentsOf: u)
            }
            """),
        ("guard let inside do, read after it", """
            func f() throws -> Data {
                do { guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing } }
                return try Data(contentsOf: u)
            }
            """),
        ("guard let inside for, read after it", """
            func f() throws -> Data {
                for _ in 0..<1 { guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing } }
                return try Data(contentsOf: u)
            }
            """),
        ("guard let inside if, read after it", """
            func f() throws -> Data {
                if flag { guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing } }
                return try Data(contentsOf: u)
            }
            """),
        ("read in the else of an if let", """
            func f() throws -> Data {
                if let u = Bundle.main.url(forResource: "fixtures") { throw LoaderError.missing } else { return try Data(contentsOf: u) }
            }
            """),
        ("read in the else block of the guard", """
            func f() throws -> Data {
                guard let u = Bundle.main.url(forResource: "fixtures") else { return try Data(contentsOf: u) }
                throw LoaderError.missing
            }
            """),
        ("let binding inside a nested block, read after it", """
            func f() throws -> Data {
                do { let u = Bundle.main.url(forResource: "fixtures") }
                return try Data(contentsOf: u)
            }
            """),
    ]

    @Test("AC-M2-09 M2 Q23 (PR #51 F2): the binding must be in scope at the read", arguments: scopePlants.indices)
    func scopePlantCaught(index: Int) {
        let (description, code) = Self.scopePlants[index]
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 && $0.check.contains("contentsOf:") }, "\(description): \(found)")
    }

    @Test("AC-M2-09 M2 Q23 (PR #51 F2) positive: reads where the binding is in scope pass", arguments: [
        """
        func f() throws -> Data {
            guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
            if flag { return try Data(contentsOf: u) }
            throw LoaderError.missing
        }
        """,
        """
        func f() throws -> Data {
            if let u = Bundle.main.url(forResource: "fixtures") {
                if flag { return try Data(contentsOf: u) }
            }
            throw LoaderError.missing
        }
        """,
        """
        func f() throws -> Data {
            do {
                guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                return try Data(contentsOf: u)
            }
        }
        """,
    ])
    func scopePositivePasses(code: String) {
        let found = scanLoader(code)
        #expect(found.isEmpty, "\(found)")
    }

    /// PR #51 review F3: in the loader file, any `typealias` and any declaration named `Data` or `Bundle`.
    static let shadowPlants: [String] = [
        "typealias Data = String",
        "typealias Bytes = Foundation.Data",
        "struct Data {}",
        "enum Bundle { static let main = 0 }",
        "class Data {}",
        "actor Bundle {}",
        "protocol Data {}",
        "extension Data {}",
        "let Data = 1",
        "func Bundle() {}",
        "enum E { case Data }",
        "struct S<Data> {}",
        "struct `Data` {}",             // PR #51 N1 (b): backticked names
        "let `Bundle` = 1",
        "enum E { case `Data` }",
    ]

    @Test("AC-M2-09 M2 Q23 (PR #51 F3): a typealias or a declaration that shadows Data or Bundle in the loader file is reported",
          arguments: shadowPlants)
    func shadowPlantCaught(code: String) {
        let found = scanLoader(code + "\n" + Self.wrap())
        #expect(found.contains { $0.rule == .rule6 && $0.check.contains("shadow") }, "`\(code)`: \(found)")
    }

    @Test("AC-M2-09 M2 Q23: one plant per condition of the loader exception is caught in the loader file",
          arguments: conditionPlants.indices)
    func conditionPlantCaught(index: Int) {
        let (description, code, check) = Self.conditionPlants[index]
        let found = scanLoader(code)
        #expect(found.contains { $0.rule == .rule6 && $0.check.contains(check) },
                "\(description): `\(code)`: \(found)")
    }

    @Test("AC-M2-09 M2 Q23: every condition plant's base form is the brief's positive and passes on its own")
    func conditionBasesPass() {
        #expect(scanLoader(Self.wrap()).isEmpty, "\(scanLoader(Self.wrap()))")
        #expect(scanLoader(Self.wrap(name: "f")).isEmpty)
    }

    @Test("AC-M2-09 M2 Q23: the loader file keeps every other Rule 6 check (networking, imports, host literals)")
    func otherRule6ChecksKept() {
        #expect(scanLoader("import Darwin\n" + Self.wrap()).contains { $0.rule == .rule6 && $0.check == "import" })
        #expect(scanLoader("let s = URLSession.shared\n" + Self.wrap()).contains { $0.rule == .rule6 })
        #expect(scanLoader("let h = \"api.example.com\"\n" + Self.wrap()).contains { $0.rule == .rule4 })
        #expect(scanLoader("let s = SFSpeechRecognizer()\n" + Self.wrap()).contains { $0.rule == .rule5 })
    }

    @Test("AC-M2-09 M2 Q23: the exception is case-sensitive: guard-let spelled differently is not a binding")
    func caseSensitive() {
        let code = """
            func f() throws -> Data {
                guard let u = bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                return try Data(contentsOf: u)
            }
            """
        #expect(scanLoader(code).contains { $0.rule == .rule6 && $0.check.contains("contentsOf:") })
    }

    @Test("AC-M2-09 M2 Q23: comments and string text do not count as the binding")
    func commentsDoNotBind() {
        let code = """
            func f() throws -> Data {
                // guard let u = Bundle.main.url(forResource: "fixtures") else { throw LoaderError.missing }
                let note = "let u = Bundle.main.url(forResource: \\"fixtures\\")"
                return try Data(contentsOf: u)
            }
            """
        #expect(scanLoader(code).contains { $0.rule == .rule6 && $0.check.contains("contentsOf:") })
    }

    @Test("Lexer (M2 Q23): whole string literals record their joined text, interpolation and blank span in code")
    func lexerStringLiteralSpans() {
        let lexed = SourceScanner.lex(#"let a = "x\(b)y"; let c = "d" // "e""#)
        #expect(lexed.stringLiterals.map(\.text) == ["xy", "d"])
        #expect(lexed.stringLiterals.map(\.hasInterpolation) == [true, false])
        let scalars = Array(lexed.code.unicodeScalars)
        for literal in lexed.stringLiterals where !literal.hasInterpolation {
            #expect(scalars[literal.codeStart..<literal.codeEnd].allSatisfy { $0 == " " })
            #expect(literal.codeEnd - literal.codeStart == 2)
        }
        // The segment list is unchanged (Rule 4 and AC-M1-02 still read segments).
        #expect(lexed.literals.map(\.text) == ["x", "y", "d"])
    }

    // MARK: Helpers

    /// The brief's positive inside `func <name>() throws -> Data`, with one piece swapped.
    static func wrap(
        _ body: String? = nil,
        name: String = "inputs",
        resource: String = "\"fixtures\"",
        ext: String = "\"json\"",
        extra: String = "",
        qualifiedBundle: Bool = false
    ) -> String {
        let bundle = qualifiedBundle ? "Foundation.Bundle" : "Bundle"
        let binding = "guard let u = \(bundle).main.url(forResource: \(resource), withExtension: \(ext)\(extra)) "
            + "else { throw LoaderError.missing }"
        return """
            func \(name)() throws -> Data {
                \(binding)
                \(body ?? "return try Data(contentsOf: u)")
            }
            """
    }
}
