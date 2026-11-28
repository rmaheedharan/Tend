// AC-M2-28 "Never shipped", proved by a scan of `project.yml` (the XcodeGen spec, ADR-0003) on Linux (WI-M2-M7):
// - `TendEval` is its own app target with its own bundle ID, and a pre-build guard stops any non-Debug build.
// - No target depends on `TendEval` except its own hosted tests (`TendEvalTests`), and the `Tend` target never names it.
// - File sharing is set in the Debug configuration only (the Debug-only partial Info.plist), never in base settings.
// - The `Tend` scheme builds `Tend` only. No other scheme builds `TendEval` or `TendEvalTests`. The `TendEval` scheme
//   never builds them for archiving.
// The scan reads the spec as indented text (no YAML library: no dependency, CLAUDE.md §6). Comments are removed
// first. Negative plants check that each rule catches the change it is for.

import Foundation
import Testing

/// A minimal reader of the spec's indented blocks.
struct ProjectSpec {
    struct Line {
        let indent: Int
        let text: String
    }

    let lines: [Line]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let code = Self.removingComment(String(raw))
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return Line(indent: code.prefix { $0 == " " }.count, text: trimmed)
        }
    }

    /// A `#` that starts a line or follows a space starts a comment (YAML), outside quotes.
    static func removingComment(_ line: String) -> String {
        var result = ""
        var quote: Character?
        var previous: Character = " "
        for character in line {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous == " " {
                break
            }
            result.append(character)
            previous = character
        }
        return result
    }

    /// The child keys of the block at `path` (each a `key:` line one level in) with their lines.
    func children(of path: [String]) -> [(key: String, lines: [Line])] {
        var scope = lines[...]
        var indent = -1
        for key in path {
            guard let start = scope.firstIndex(where: { $0.text == key + ":" && $0.indent > indent }) else { return [] }
            let keyIndent = scope[start].indent
            let end = scope[(start + 1)...].firstIndex { $0.indent <= keyIndent } ?? scope.endIndex
            scope = scope[(start + 1)..<end]
            indent = keyIndent
        }
        guard let childIndent = scope.first?.indent else { return [] }
        var result: [(key: String, lines: [Line])] = []
        for (offset, line) in zip(scope.indices, scope) where line.indent == childIndent && line.text.hasSuffix(":") {
            let end = scope[(offset + 1)...].firstIndex { $0.indent <= childIndent } ?? scope.endIndex
            result.append((String(line.text.dropLast()), Array(scope[(offset + 1)..<end])))
        }
        // `key: value` children on one line.
        for line in scope where line.indent == childIndent && !line.text.hasSuffix(":") {
            if let colon = line.text.firstIndex(of: ":") { result.append((String(line.text[..<colon]), [line])) }
        }
        return result
    }

    func block(_ path: [String]) -> [Line]? {
        guard let last = path.last else { return nil }
        return children(of: Array(path.dropLast())).first { $0.key == last }?.lines
    }
}

enum ProjectSpecRules {
    static let evalTargets: Set<String> = ["TendEval", "TendEvalTests"]

    static func violations(spec text: String) -> [String] {
        let spec = ProjectSpec(text)
        var result: [String] = []
        let targets = spec.children(of: ["targets"])
        let names = targets.map(\.key)
        guard names.contains("Tend"), names.contains("TendEval") else { return ["the Tend or TendEval target is missing"] }

        // Dependencies: only TendEvalTests may depend on TendEval; the Tend target never names it.
        for (name, lines) in targets where name != "TendEvalTests" {
            if lines.contains(where: { $0.text.hasPrefix("- target:") && $0.text.contains("TendEval") }) {
                result.append("target \(name) depends on TendEval")
            }
        }
        if let tend = spec.block(["targets", "Tend"]), tend.contains(where: { $0.text.contains("TendEval") }) {
            result.append("the Tend target names TendEval")
        }

        // Own bundle ID; Debug-only guard.
        func setting(_ target: String, _ key: String) -> String? {
            spec.block(["targets", target])?.first { $0.text.hasPrefix(key + ":") }
                .map { String($0.text.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        let evalID = setting("TendEval", "PRODUCT_BUNDLE_IDENTIFIER")
        if evalID == nil || evalID == setting("Tend", "PRODUCT_BUNDLE_IDENTIFIER") {
            result.append("TendEval has no bundle ID of its own")
        }
        let scripts = spec.block(["targets", "TendEval", "preBuildScripts"]) ?? []
        let guardText = scripts.map(\.text).joined(separator: "\n")
        if !(guardText.contains("if [ \"${CONFIGURATION}\" != \"Debug\" ]; then") && guardText.contains("exit 1")) {
            result.append("TendEval has no pre-build guard that stops a non-Debug build")
        }

        // File sharing in Debug only.
        let base = spec.block(["targets", "TendEval", "settings", "base"]) ?? []
        if base.contains(where: { $0.text.contains("INFOPLIST_FILE") || $0.text.contains("UIFileSharingEnabled") }) {
            result.append("TendEval sets an Info.plist file or file sharing in base settings")
        }
        let debug = spec.block(["targets", "TendEval", "settings", "configs", "Debug"]) ?? []
        if !debug.contains(where: { $0.text == "INFOPLIST_FILE: Apps/TendEval/Support/Debug-Info.plist" }) {
            result.append("TendEval's Debug configuration does not use the Debug-only Info.plist")
        }
        let configs = spec.children(of: ["targets", "TendEval", "settings", "configs"])
        for (config, lines) in configs where config != "Debug" {
            if lines.contains(where: { $0.text.contains("INFOPLIST_FILE") || $0.text.contains("UIFileSharing") }) {
                result.append("TendEval's \(config) configuration sets file sharing")
            }
        }
        for (name, lines) in targets where !evalTargets.contains(name) {
            if lines.contains(where: { $0.text.contains("Debug-Info.plist") || $0.text.contains("UIFileSharing") }) {
                result.append("target \(name) enables file sharing")
            }
        }

        // Schemes.
        let schemes = spec.children(of: ["schemes"])
        guard let tendScheme = schemes.first(where: { $0.key == "Tend" }) else { return result + ["no Tend scheme"] }
        let tendBuilds = spec.children(of: ["schemes", "Tend", "build", "targets"]).map(\.key)
        if tendBuilds != ["Tend"] { result.append("the Tend scheme builds \(tendBuilds), not Tend only") }
        if tendScheme.lines.contains(where: { $0.text.contains("TendEval") }) {
            result.append("the Tend scheme names TendEval")
        }
        for (name, _) in schemes where name != "TendEval" {
            for built in spec.children(of: ["schemes", name, "build", "targets"]) where evalTargets.contains(built.key) {
                result.append("scheme \(name) builds \(built.key)")
            }
        }
        for built in spec.children(of: ["schemes", "TendEval", "build", "targets"]) where evalTargets.contains(built.key) {
            let value = built.lines.first?.text ?? ""
            if value.contains("all") || value.contains("archiving") || !value.contains("[") {
                result.append("the TendEval scheme builds \(built.key) for archiving (\(value))")
            }
        }
        return result
    }
}

@Suite("AC-M2-28: project.yml keeps TendEval out of every shipped product (Linux scan)")
struct ProjectSpecScanTests {
    static func spec() throws -> String {
        String(decoding: try EvalSelfTest.data("project.yml"), as: UTF8.self)
    }

    @Test("The committed project.yml passes every rule")
    func committedSpecPasses() throws {
        let text = try Self.spec()
        #expect(ProjectSpecRules.violations(spec: text) == [])
        let spec = ProjectSpec(text)
        #expect(spec.children(of: ["targets"]).map(\.key).contains("TendEvalTests"))
        print("AC-M2-28 project.yml scan: \(spec.children(of: ["targets"]).count) targets, "
              + "\(spec.children(of: ["schemes"]).count) schemes, 0 violations")
    }

    @Test("The Debug-only Info.plist turns file sharing on (and only it does)")
    func debugPlist() throws {
        let plist = String(decoding: try EvalSelfTest.data("Apps/TendEval/Support/Debug-Info.plist"), as: UTF8.self)
        #expect(plist.contains("<key>UIFileSharingEnabled</key>\n\t<true/>"))
        #expect(plist.contains("<key>TendCommit</key>\n\t<string>$(TEND_COMMIT)</string>"))
    }

    /// Each plant: a change to the committed spec and the violation it must produce.
    static let plants: [(name: String, find: String, replace: String, expected: String)] = [
        ("the Tend target depends on TendEval",
         "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.app\n",
         "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.app\n    dependencies:\n      - target: TendEval\n",
         "target Tend depends on TendEval"),
        ("the test host depends on TendEval",
         "      - path: Apps/TendAITestHost/Sources\n",
         "      - path: Apps/TendAITestHost/Sources\n    dependencies:\n      - target: TendEval\n",
         "target TendAITestHost depends on TendEval"),
        ("the Tend scheme also builds TendEval",
         "        Tend: all\n", "        Tend: all\n        TendEval: all\n",
         "the Tend scheme builds [\"Tend\", \"TendEval\"], not Tend only"),
        ("the hosted-tests scheme builds TendEval",
         "        TendAIHostedTests: [testing]\n", "        TendAIHostedTests: [testing]\n        TendEval: [testing]\n",
         "scheme TendAIHostedTests builds TendEval"),
        ("the TendEval scheme builds it for every action",
         "        TendEval: [running, testing, profiling, analyzing]\n", "        TendEval: all\n",
         "the TendEval scheme builds TendEval for archiving (TendEval: all)"),
        ("the TendEval scheme builds it for archiving",
         "        TendEval: [running, testing, profiling, analyzing]\n",
         "        TendEval: [running, testing, profiling, analyzing, archiving]\n",
         "the TendEval scheme builds TendEval for archiving (TendEval: [running, testing, profiling, analyzing, archiving])"),
        ("the Debug-only guard is removed",
         "          if [ \"${CONFIGURATION}\" != \"Debug\" ]; then\n", "          if false; then\n",
         "TendEval has no pre-build guard that stops a non-Debug build"),
        ("file sharing in base settings",
         "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.eval\n",
         "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.eval\n        INFOPLIST_FILE: Apps/TendEval/Support/Debug-Info.plist\n",
         "TendEval sets an Info.plist file or file sharing in base settings"),
        ("file sharing in a Release configuration",
         "        Debug:\n", "        Release:\n          INFOPLIST_FILE: Apps/TendEval/Support/Debug-Info.plist\n        Debug:\n",
         "TendEval's Release configuration sets file sharing"),
        ("TendEval shares the app's bundle ID",
         "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.eval\n", "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.app\n",
         "TendEval has no bundle ID of its own"),
        ("the Tend app turns file sharing on",
         "        INFOPLIST_KEY_CFBundleDisplayName: Tend\n",
         "        INFOPLIST_KEY_CFBundleDisplayName: Tend\n        INFOPLIST_KEY_UIFileSharingEnabled: YES\n",
         "target Tend enables file sharing"),
    ]

    @Test("Each negative plant is caught with its own violation", arguments: plants.indices)
    func plant(index: Int) throws {
        let plant = Self.plants[index]
        let text = try Self.spec()
        #expect(text.components(separatedBy: plant.find).count == 2, "\(plant.name): the anchor is in project.yml once")
        let planted = text.replacingOccurrences(of: plant.find, with: plant.replace)
        let found = ProjectSpecRules.violations(spec: planted)
        #expect(found.contains(plant.expected), "\(plant.name): \(found)")
    }

    @Test("A comment never counts: TendEval named only in a comment of the Tend target is not a violation")
    func commentsIgnored() throws {
        let text = try Self.spec().replacingOccurrences(
            of: "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.app\n",
            with: "        PRODUCT_BUNDLE_IDENTIFIER: com.tend.app # not TendEval\n")
        #expect(ProjectSpecRules.violations(spec: text) == [])
    }
}
