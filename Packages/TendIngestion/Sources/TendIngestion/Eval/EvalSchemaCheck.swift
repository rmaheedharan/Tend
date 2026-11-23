// The Foundation-only conformance check for `results-v1.schema.json` (AC-M2-28: "A JSON Schema for v1 is committed
// with the fixtures. The scorer rejects a file that does not conform."; plan WI-M2-15: "hand-written in Foundation for
// the schema's subset (types, required keys, enums, `additionalProperties: false`)"; risk R-22).
//
// It interprets the committed schema itself, so the check cannot drift from the file (R-22). It supports a closed
// subset of JSON Schema 2020-12 and **fails closed**: a schema that uses any other keyword, or uses a supported keyword
// in an unsupported way (for example `additionalProperties` other than `false`), is refused before any instance is
// checked. No JSON Schema library is used (no new dependency, CLAUDE.md §6).
//
// Supported keywords and their meaning (2020-12 semantics; type-specific keywords apply only to values of that type):
// - annotations, ignored: `$schema`, `$id`, `$comment`, `title`, `description`;
// - `type`: one type name or an array of names (`null`, `boolean`, `integer`, `number`, `string`, `array`, `object`);
// - `enum` (array), `const`;
// - objects: `properties`, `required`, `additionalProperties: false`;
// - arrays: `items` (one schema), `minItems`, `uniqueItems: true`;
// - integers: `minimum`, `maximum` (integers only);
// - strings: `minLength` (counted in Unicode scalars), `pattern` (unanchored search, as JSON Schema says);
// - `oneOf` (exactly one branch must hold).

import Foundation

/// One way an instance does not conform. `path` is a JSON Pointer into the instance (`""` is the root).
public struct EvalSchemaIssue: Sendable, Hashable, CustomStringConvertible {
    public var path: String
    public var keyword: String
    public var detail: String

    public var description: String { "\(path.isEmpty ? "/" : path): \(keyword) (\(detail))" }
}

/// Why a schema file cannot be used (the check fails closed).
public enum EvalSchemaError: Error, Sendable, Hashable {
    case schemaNotJSON(EvalJSONError)
    case unsupportedKeyword(schemaPath: String, keyword: String)
    case malformedKeyword(schemaPath: String, keyword: String)
}

public struct EvalSchemaCheck: Sendable {

    /// The supported keywords (the closed subset). Anything else in a schema is refused.
    public static let supportedKeywords: Set<String> = [
        "$schema", "$id", "$comment", "title", "description",
        "type", "enum", "const",
        "properties", "required", "additionalProperties",
        "items", "minItems", "uniqueItems",
        "minimum", "maximum",
        "minLength", "pattern",
        "oneOf",
    ]

    static let typeNames: Set<String> = ["null", "boolean", "integer", "number", "string", "array", "object"]

    public let schema: EvalJSON

    /// Reads and checks the schema (every keyword supported and well formed; every pattern compiles).
    public init(schemaData: Data) throws(EvalSchemaError) {
        let parsed: EvalJSON
        do throws(EvalJSONError) { parsed = try EvalJSONReader.parse(schemaData) } catch { throw .schemaNotJSON(error) }
        try self.init(schema: parsed)
    }

    public init(schema: EvalJSON) throws(EvalSchemaError) {
        try Self.checkSchema(schema, path: "")
        self.schema = schema
    }

    /// Every issue of `instance` against the schema, in document order. Empty means the instance conforms.
    public func issues(in instance: EvalJSON) -> [EvalSchemaIssue] {
        var found: [EvalSchemaIssue] = []
        validate(instance, against: schema, path: "", into: &found)
        return found
    }

    // MARK: - Schema well-formedness (fail closed)

    static func checkSchema(_ schema: EvalJSON, path: String) throws(EvalSchemaError) {
        guard case let .object(members) = schema else {
            throw .malformedKeyword(schemaPath: path, keyword: "(schema must be an object)")
        }
        for member in members {
            let keyword = member.key
            let here = path + "/" + escapePointer(keyword)
            guard supportedKeywords.contains(keyword) else {
                throw .unsupportedKeyword(schemaPath: path, keyword: keyword)
            }
            let value = member.value
            func malformed() -> EvalSchemaError { .malformedKeyword(schemaPath: path, keyword: keyword) }
            switch keyword {
            case "$schema", "$id", "$comment", "title", "description":
                guard case .string = value else { throw malformed() }
            case "type":
                switch value {
                case let .string(name):
                    guard typeNames.contains(name) else { throw malformed() }
                case let .array(names):
                    guard !names.isEmpty else { throw malformed() }
                    for name in names {
                        guard case let .string(text) = name, typeNames.contains(text) else { throw malformed() }
                    }
                default: throw malformed()
                }
            case "enum":
                guard case let .array(values) = value, !values.isEmpty else { throw malformed() }
            case "const":
                break
            case "properties":
                guard case let .object(properties) = value else { throw malformed() }
                for property in properties {
                    try checkSchema(property.value, path: here + "/" + escapePointer(property.key))
                }
            case "required":
                guard case let .array(names) = value else { throw malformed() }
                for name in names { guard case .string = name else { throw malformed() } }
            case "additionalProperties":
                guard value == .bool(false) else { throw malformed() }
            case "items":
                try checkSchema(value, path: here)
            case "minItems", "minLength":
                guard case let .integer(count) = value, count >= 0 else { throw malformed() }
            case "uniqueItems":
                guard value == .bool(true) else { throw malformed() }
            case "minimum", "maximum":
                guard case .integer = value else { throw malformed() }
            case "pattern":
                guard case let .string(pattern) = value, compile(pattern) != nil else { throw malformed() }
            case "oneOf":
                guard case let .array(branches) = value, !branches.isEmpty else { throw malformed() }
                for (index, branch) in branches.enumerated() {
                    try checkSchema(branch, path: here + "/\(index)")
                }
            default:
                throw .unsupportedKeyword(schemaPath: path, keyword: keyword)
            }
        }
    }

    // MARK: - Validation

    func validate(_ instance: EvalJSON, against schema: EvalJSON, path: String, into found: inout [EvalSchemaIssue]) {
        func issue(_ keyword: String, _ detail: String) {
            found.append(EvalSchemaIssue(path: path, keyword: keyword, detail: detail))
        }
        if let type = schema["type"] {
            let allowed: [String]
            switch type {
            case let .string(name): allowed = [name]
            case let .array(names): allowed = names.compactMap { if case let .string(n) = $0 { n } else { nil } }
            default: allowed = []
            }
            let actual = instance.typeName
            let matches = allowed.contains(actual) || (actual == "integer" && allowed.contains("number"))
            if !matches {
                issue("type", "expected \(allowed.joined(separator: " or ")), found \(actual)")
                return
            }
        }
        if case let .array(values)? = schema["enum"], !values.contains(where: { EvalJSON.jsonEqual($0, instance) }) {
            issue("enum", "value is not one of the listed values")
        }
        if let constant = schema["const"], !EvalJSON.jsonEqual(constant, instance) {
            issue("const", "value is not the required constant")
        }
        switch instance {
        case let .object(members):
            if case let .array(names)? = schema["required"] {
                for case let .string(name) in names where instance[name] == nil {
                    issue("required", "missing member \"\(name)\"")
                }
            }
            let properties = schema["properties"]
            for member in members {
                let childPath = path + "/" + Self.escapePointer(member.key)
                if let propertySchema = properties?[member.key] {
                    validate(member.value, against: propertySchema, path: childPath, into: &found)
                } else if schema["additionalProperties"] == .bool(false) {
                    found.append(EvalSchemaIssue(path: childPath, keyword: "additionalProperties",
                                                 detail: "member \"\(member.key)\" is not allowed"))
                }
            }
        case let .array(values):
            if case let .integer(minimum)? = schema["minItems"], values.count < minimum {
                issue("minItems", "\(values.count) items, at least \(minimum) needed")
            }
            if schema["uniqueItems"] == .bool(true) {
                outer: for i in values.indices {
                    for j in values.indices where j > i && EvalJSON.jsonEqual(values[i], values[j]) {
                        issue("uniqueItems", "items \(i) and \(j) are equal")
                        break outer
                    }
                }
            }
            if let itemSchema = schema["items"] {
                for (index, value) in values.enumerated() {
                    validate(value, against: itemSchema, path: path + "/\(index)", into: &found)
                }
            }
        case let .integer(number):
            if case let .integer(minimum)? = schema["minimum"], number < minimum {
                issue("minimum", "\(number) is below \(minimum)")
            }
            if case let .integer(maximum)? = schema["maximum"], number > maximum {
                issue("maximum", "\(number) is above \(maximum)")
            }
        case let .string(text):
            if case let .integer(minimum)? = schema["minLength"], text.unicodeScalars.count < minimum {
                issue("minLength", "\(text.unicodeScalars.count) characters, at least \(minimum) needed")
            }
            if case let .string(pattern)? = schema["pattern"] {
                // The pattern compiled when the schema was checked; a nil here is treated as no match (fail closed).
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if Self.compile(pattern)?.firstMatch(in: text, options: [], range: range) == nil {
                    issue("pattern", "does not match \(pattern)")
                }
            }
        case .null, .bool:
            break
        }
        if case let .array(branches)? = schema["oneOf"] {
            var holding = 0
            for branch in branches {
                var branchIssues: [EvalSchemaIssue] = []
                validate(instance, against: branch, path: path, into: &branchIssues)
                if branchIssues.isEmpty { holding += 1 }
            }
            if holding != 1 { issue("oneOf", "\(holding) branches hold, exactly 1 needed") }
        }
    }

    /// Compiles a `pattern` value (ICU syntax; the schema keeps to the part ICU and ECMA-262 read the same way).
    static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }

    /// RFC 6901 escaping of one pointer segment.
    static func escapePointer(_ segment: String) -> String {
        segment.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
}
