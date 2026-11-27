// The Foundation-only conformance check for `results-v1.schema.json` (AC-M2-28 "The scorer rejects a file that does not
// conform"; plan WI-M2-15; risk R-22 "A test maps every schema constraint to a check").

import Foundation
import Testing
@testable import TendIngestion

@Suite("WI-M2-15 results-v1 schema conformance check (AC-M2-28, R-22)")
struct EvalSchemaCheckTests {

    // MARK: - Fail closed on the schema

    @Test("a schema keyword outside the supported subset is refused, so no constraint is silently skipped", arguments: [
        #"{"format":"date-time"}"#, #"{"anyOf":[{}]}"#, #"{"properties":{"a":{"maxLength":3}}}"#,
        ##"{"items":{"$ref":"#"}}"##, #"{"patternProperties":{}}"#, #"{"allOf":[{}]}"#,
    ])
    func unsupportedKeyword(schema: String) {
        #expect(throws: EvalSchemaError.self) { try EvalSchemaCheck(schemaData: Data(schema.utf8)) }
    }

    @Test("a supported keyword in an unsupported form is refused", arguments: [
        #"{"additionalProperties":true}"#, #"{"additionalProperties":{"type":"string"}}"#, #"{"type":"date"}"#,
        #"{"type":[]}"#, #"{"enum":[]}"#, #"{"pattern":"("}"#, #"{"uniqueItems":false}"#, #"{"minimum":"1"}"#,
        #"{"minLength":-1}"#, #"{"required":[1]}"#, #"{"oneOf":[]}"#, #"{"properties":[]}"#, #"[]"#, #"{"title":1}"#,
    ])
    func malformedKeyword(schema: String) {
        #expect(throws: EvalSchemaError.self) { try EvalSchemaCheck(schemaData: Data(schema.utf8)) }
    }

    // MARK: - Each keyword

    static func issues(_ schema: String, _ instance: String) throws -> [EvalSchemaIssue] {
        try EvalSchemaCheck(schemaData: Data(schema.utf8)).issues(in: try EvalJSONReader.parse(Data(instance.utf8)))
    }

    @Test("each supported keyword accepts a conforming value and reports a non-conforming one", arguments: [
        (#"{"type":"string"}"#, #""x""#, #"1"#, "type"),
        (#"{"type":["integer","null"]}"#, #"null"#, #""1""#, "type"),
        (#"{"type":"number"}"#, #"3"#, #"true"#, "type"),
        (#"{"enum":["a",null]}"#, #"null"#, #""b""#, "enum"),
        (#"{"const":1}"#, #"1"#, #"2"#, "const"),
        (#"{"required":["a"]}"#, #"{"a":0}"#, #"{"b":0}"#, "required"),
        (#"{"properties":{"a":{}},"additionalProperties":false}"#, #"{"a":0}"#, #"{"a":0,"b":0}"#, "additionalProperties"),
        (#"{"properties":{"a":{"type":"string"}}}"#, #"{"a":"x"}"#, #"{"a":1}"#, "type"),
        (#"{"items":{"type":"integer"}}"#, #"[1,2]"#, #"[1,"2"]"#, "type"),
        (#"{"minItems":1}"#, #"[0]"#, #"[]"#, "minItems"),
        (#"{"uniqueItems":true}"#, #"[{"a":1},{"a":2}]"#, #"[{"a":1,"b":2},{"b":2,"a":1}]"#, "uniqueItems"),
        (#"{"minimum":0}"#, #"0"#, #"-1"#, "minimum"),
        (#"{"maximum":5}"#, #"5"#, #"6"#, "maximum"),
        (#"{"minLength":2}"#, #""é😀""#, #""é""#, "minLength"),
        (#"{"pattern":"^[0-9a-f]{2}$"}"#, #""0a""#, #""0A""#, "pattern"),
        (#"{"pattern":"b"}"#, #""abc""#, #""ac""#, "pattern"),
        (#"{"oneOf":[{"const":1},{"type":"integer"}]}"#, #"2"#, #"1"#, "oneOf"),
        (#"{"oneOf":[{"const":1},{"const":2}]}"#, #"2"#, #"3"#, "oneOf"),
    ])
    func keyword(schema: String, good: String, bad: String, keyword: String) throws {
        #expect(try Self.issues(schema, good).isEmpty)
        let found = try Self.issues(schema, bad)
        #expect(found.contains { $0.keyword == keyword }, "\(found)")
    }

    @Test("type-specific keywords apply only to values of that type (JSON Schema 2020-12)")
    func typeSpecific() throws {
        #expect(try Self.issues(#"{"minLength":3,"minimum":5,"required":["a"],"minItems":2}"#, #"true"#).isEmpty)
    }

    // MARK: - R-22: every constraint of the committed schema has a matching check

    /// One constraint of the schema: where it is and which keyword (plus the member name for `required`).
    struct Constraint: Hashable, CustomStringConvertible {
        var schemaPath: String
        var keyword: String
        var description: String { "\(schemaPath)#\(keyword)" }
    }

    static let structuralKeywords: Set<String> = ["properties", "items", "$schema", "$id", "$comment", "title",
                                                   "description"]

    /// Every constraint, walking every property, item and `oneOf` branch.
    static func constraints(_ schema: EvalJSON, at path: String) -> Set<Constraint> {
        guard case let .object(members) = schema else { return [] }
        var result: Set<Constraint> = []
        for member in members {
            switch member.key {
            case "properties":
                if case let .object(properties) = member.value {
                    for property in properties {
                        result.formUnion(constraints(property.value, at: path + "/properties/" + property.key))
                    }
                }
            case "items":
                result.formUnion(constraints(member.value, at: path + "/items"))
            case "oneOf":
                result.insert(Constraint(schemaPath: path, keyword: "oneOf"))
                if case let .array(branches) = member.value {
                    for (index, branch) in branches.enumerated() {
                        result.formUnion(constraints(branch, at: path + "/oneOf/\(index)"))
                    }
                }
            case "required":
                if case let .array(names) = member.value {
                    for case let .string(name) in names { result.insert(Constraint(schemaPath: path, keyword: "required:" + name)) }
                }
            case let keyword where !structuralKeywords.contains(keyword):
                result.insert(Constraint(schemaPath: path, keyword: keyword))
            default:
                break
            }
        }
        return result
    }

    struct Mutation {
        var constraint: Constraint
        var instancePointer: String
        var replacement: EvalJSON?
        /// Where the issue must be reported, and with which keyword.
        var expectedPath: String
        var expectedKeyword: String
    }

    static let wrongTypeCandidates: [EvalJSON] = [.bool(true), .integer(7), .string("x"), .array([]), .object([]), .null]

    /// One mutation per constraint reachable from `instance`, each breaking exactly that constraint.
    static func mutations(
        schema: EvalJSON, instance: EvalJSON, schemaPath: String, pointer: String, oneOfPointer: String?
    ) -> [Mutation] {
        var result: [Mutation] = []
        func add(_ keyword: String, _ path: String, _ replacement: EvalJSON?, issuePath: String, issueKeyword: String) {
            let reported = oneOfPointer.map { ($0, "oneOf") } ?? (issuePath, issueKeyword)
            result.append(Mutation(constraint: Constraint(schemaPath: schemaPath, keyword: keyword),
                                   instancePointer: path, replacement: replacement, expectedPath: reported.0,
                                   expectedKeyword: reported.1))
        }
        if let type = schema["type"] {
            let allowed: [String]
            switch type {
            case let .string(name): allowed = [name]
            case let .array(names): allowed = names.compactMap { if case let .string(n) = $0 { n } else { nil } }
            default: allowed = []
            }
            if let wrong = wrongTypeCandidates.first(where: { !allowed.contains($0.typeName)
                && !($0.typeName == "integer" && allowed.contains("number")) }) {
                add("type", pointer, wrong, issuePath: pointer, issueKeyword: "type")
            }
        }
        if schema["enum"] != nil, case .string = instance {
            add("enum", pointer, .string("not-a-listed-value"), issuePath: pointer, issueKeyword: "enum")
        } else if schema["enum"] != nil, instance == .null {
            add("enum", pointer, .string("not-a-listed-value"), issuePath: pointer, issueKeyword: "enum")
        }
        if let constant = schema["const"] {
            let other: EvalJSON
            switch constant {
            case let .integer(n): other = .integer(n + 1)
            case let .string(s): other = .string(s + "-other")
            default: other = .null
            }
            add("const", pointer, other, issuePath: pointer, issueKeyword: "const")
        }
        if case let .object(members) = instance {
            if case let .array(names)? = schema["required"] {
                for case let .string(name) in names {
                    add("required:" + name, pointer + "/" + name, nil, issuePath: pointer, issueKeyword: "required")
                }
            }
            if schema["additionalProperties"] == .bool(false) {
                add("additionalProperties", pointer + "/zzNotInV1", .null, issuePath: pointer + "/zzNotInV1",
                    issueKeyword: "additionalProperties")
            }
            if let properties = schema["properties"] {
                for member in members {
                    if let child = properties[member.key] {
                        result += mutations(schema: child, instance: member.value,
                                            schemaPath: schemaPath + "/properties/" + member.key,
                                            pointer: pointer + "/" + member.key, oneOfPointer: oneOfPointer)
                    }
                }
            }
        }
        if case let .array(items) = instance {
            if case let .integer(minimum)? = schema["minItems"], minimum >= 1 {
                add("minItems", pointer, .array([]), issuePath: pointer, issueKeyword: "minItems")
            }
            if schema["uniqueItems"] == .bool(true), let first = items.first {
                add("uniqueItems", pointer, .array(items + [first]), issuePath: pointer, issueKeyword: "uniqueItems")
            }
            if let itemSchema = schema["items"] {
                for (index, item) in items.enumerated() {
                    result += mutations(schema: itemSchema, instance: item, schemaPath: schemaPath + "/items",
                                        pointer: pointer + "/\(index)", oneOfPointer: oneOfPointer)
                }
            }
        }
        if case let .integer(minimum)? = schema["minimum"], case .integer = instance {
            add("minimum", pointer, .integer(minimum - 1), issuePath: pointer, issueKeyword: "minimum")
        }
        if schema["minLength"] != nil, case .string = instance {
            add("minLength", pointer, .string(""), issuePath: pointer, issueKeyword: "minLength")
        }
        if schema["pattern"] != nil, case .string = instance {
            add("pattern", pointer, .string("!"), issuePath: pointer, issueKeyword: "pattern")
        }
        if case let .array(branches)? = schema["oneOf"] {
            add("oneOf", pointer, .object([.init("type", .string("not-a-branch"))]), issuePath: pointer,
                issueKeyword: "oneOf")
            for (index, branch) in branches.enumerated() {
                var branchIssues: [EvalSchemaIssue] = []
                if let check = try? EvalSchemaCheck(schema: branch) {
                    branchIssues = check.issues(in: instance)
                    if branchIssues.isEmpty {
                        result += mutations(schema: branch, instance: instance, schemaPath: schemaPath + "/oneOf/\(index)",
                                            pointer: pointer, oneOfPointer: oneOfPointer ?? pointer)
                    }
                }
            }
        }
        return result
    }

    /// The self-test file plus one cloud request, so every schema node has a value (`cloudRequests` items included).
    static func maximalInstance() throws -> EvalJSON {
        try EvalSelfTest.resultsRoot().setting("/inputs/0/cloudRequests/0", to: .object([
            .init("arrayCounts", .array([.object([.init("count", .integer(2)), .init("path", .string("$.messages"))])])),
            .init("attempt", .integer(1)), .init("bytes", .integer(120)),
            .init("keyPaths", .array([.string("$.messages[].content"), .string("$.model")])),
            .init("userContentArrayCounts", .array([
                .object([.init("count", .integer(1)), .init("path", .string("$.rooms"))]),
            ])),
        ]))
    }

    @Test("R-22: every constraint in results-v1.schema.json is enforced (one mutation per constraint, each rejected at its path)")
    func everyConstraintEnforced() throws {
        let schemaJSON = try EvalJSONReader.parse(try EvalSelfTest.data(EvalSelfTest.schemaPath))
        let check = try EvalSchemaCheck(schema: schemaJSON)
        let instance = try Self.maximalInstance()
        #expect(check.issues(in: instance).isEmpty, "the maximal instance conforms")

        let all = Self.constraints(schemaJSON, at: "")
        let mutations = Self.mutations(schema: schemaJSON, instance: instance, schemaPath: "", pointer: "",
                                       oneOfPointer: nil)
        var exercised: Set<Constraint> = []
        var notCaught: [String] = []
        var seen: Set<Constraint> = []
        for mutation in mutations where seen.insert(mutation.constraint).inserted {
            let broken = instance.setting(mutation.instancePointer, to: mutation.replacement)
            let issues = check.issues(in: broken)
            if issues.contains(where: { $0.path == mutation.expectedPath && $0.keyword == mutation.expectedKeyword }) {
                exercised.insert(mutation.constraint)
            } else {
                notCaught.append("\(mutation.constraint) at \(mutation.instancePointer): \(issues)")
            }
        }
        print("R-22: \(all.count) constraints in the schema; \(exercised.count) exercised and rejected")
        #expect(notCaught.isEmpty, "\(notCaught)")
        let unexercised = all.subtracting(exercised).map(\.description).sorted()
        #expect(unexercised.isEmpty, "constraints with no mutation: \(unexercised)")
        #expect(all.count >= 150, "the walk found the schema's constraints (\(all.count))")
    }

    // MARK: - R27-F1: `$` is the end of the input (ECMA-262), not "before a final line terminator" (ICU)

    /// Where each `pattern` of the committed schema has a value in the maximal instance.
    static let patternLocations = [
        "/run/startedAtUTC", "/run/appCommitSHA", "/run/fixturesSHA256", "/inputs/0/drafts/0/windowStart",
        "/inputs/0/drafts/0/windowEnd", "/inputs/0/cloudRequests/0/keyPaths/0",
        "/inputs/0/cloudRequests/0/arrayCounts/0/path", "/inputs/0/cloudRequests/0/userContentArrayCounts/0/path",
    ]

    static func patternCount(_ schema: EvalJSON) -> Int {
        switch schema {
        case let .object(members):
            return members.reduce(0) { $0 + ($1.key == "pattern" ? 1 : patternCount($1.value)) }
        case let .array(items): return items.reduce(0) { $0 + patternCount($1) }
        default: return 0
        }
    }

    @Test("R27-F1: the list covers every pattern in the committed schema (8)")
    func patternListComplete() throws {
        let schemaJSON = try EvalJSONReader.parse(try EvalSelfTest.data(EvalSelfTest.schemaPath))
        #expect(Self.patternCount(schemaJSON) == Self.patternLocations.count)
    }

    @Test("R27-F1: each schema pattern refuses its valid value followed by \\n, \\r\\n or U+2028, and still accepts the value",
          arguments: patternLocations, ["\n", "\r\n", "\u{2028}", "\r", "\u{85}", "\u{2029}"])
    func patternEndOfInput(pointer: String, terminator: String) throws {
        let check = try EvalSelfTest.schema()
        let instance = try Self.maximalInstance()
        #expect(check.issues(in: instance).isEmpty)
        guard case let .string(valid)? = instance.value(at: pointer) else {
            Issue.record("no string at \(pointer)")
            return
        }
        let broken = instance.setting(pointer, to: .string(valid + terminator))
        let issues = check.issues(in: broken)
        #expect(issues == [EvalSchemaIssue(path: pointer, keyword: "pattern", detail: issues.first?.detail ?? "")],
                "\(issues)")
        #expect(issues.first?.keyword == "pattern")
    }

    @Test("R27-F1: a file with a trailing newline in a pattern field is rejected by the reader (the review's probe P2)")
    func readerRejectsTrailingNewline() throws {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        let root = try EvalSelfTest.resultsRoot().setting("/run/appCommitSHA", to: .string(sha + "\n"))
        do {
            _ = try EvalResultsFileV1.read(try EvalSelfTest.canonical(root), schema: try EvalSelfTest.schema(),
                                           fixtures: try EvalSelfTest.fixtures(),
                                           expectedFixturesSHA256: EvalSelfTest.selfTestHash)
            Issue.record("accepted a trailing newline")
        } catch let EvalRejection.schemaIssues(issues) {
            #expect(issues.map(\.path) == ["/run/appCommitSHA"])
        }
    }

    @Test("R27-F1: the ECMA-to-ICU spelling rewrites only unescaped $ outside a class", arguments: [
        ("^a$", "^a\\z"), ("^\\$(\\.[a-z]+|\\[\\])*$", "^\\$(\\.[a-z]+|\\[\\])*\\z"), ("[$]$", "[$]\\z"),
        ("a\\\\$", "a\\\\\\z"), ("^ab", "^ab"),
    ])
    func icuSpelling(ecma: String, icu: String) {
        #expect(EvalSchemaCheck.icuPattern(fromECMA: ecma) == icu)
    }

    @Test("R27-F1: $ inside the string still matches literally where the pattern escapes it; unanchored patterns stay unanchored")
    func patternSemantics() throws {
        #expect(try Self.issues(#"{"pattern":"^\\$x$"}"#, #""$x""#).isEmpty)
        #expect(!(try Self.issues(#"{"pattern":"^\\$x$"}"#, #""$x\n""#)).isEmpty)
        #expect(try Self.issues(#"{"pattern":"b"}"#, #""ab\n""#).isEmpty)
        #expect(!(try Self.issues(#"{"pattern":"a$"}"#, #""a\u2028""#)).isEmpty)
    }

    @Test("the committed schema uses only the supported subset, and it holds the v1 top level exactly")
    func committedSchemaShape() throws {
        let check = try EvalSelfTest.schema()
        #expect(check.schema["additionalProperties"] == .bool(false))
        guard case let .array(required)? = check.schema["required"] else { Issue.record("no required"); return }
        #expect(required == ["schemaVersion", "run", "coldStart", "inputs"].map { EvalJSON.string($0) })
        #expect(check.schema["properties"]?["schemaVersion"]?["const"] == .integer(1))
    }
}
