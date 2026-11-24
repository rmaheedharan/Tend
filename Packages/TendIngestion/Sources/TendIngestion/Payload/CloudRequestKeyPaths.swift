// JSON key paths of a request body, and the per-provider allowed key-path lists with roles (brief AC-M2-20 (b),
// AC-M2-26, AC-M2-28 `cloudRequests[].keyPaths[]`; plan WI-M2-10 N-3; PO WI-M2-15 ruling 2). P-3.
//
// One key-path form everywhere (the results-file form, PO WI-M2-15 ruling 2): `$`, then `.name` for an object member
// or `[]` for an array element; no index, no value. A body's key paths are its **leaf** paths: the path of every string,
// number, Boolean and `null`, and of every empty array or object, sorted by UTF-8 bytes and unique. The eval harness
// records these for each request (AC-M2-28), `tend-eval-score --profile ds2-gated` compares them with the allowed list
// (AC-M2-26), and WI-M2-11 compares the set with the list (AC-M2-20 (b)). The builder's member names all match
// `[A-Za-z0-9_-]+`; a name outside it would be written as it is, and the results-file check would refuse it.
//
// An allowed list (`Fixtures/M2/payload/allowed-key-paths-<provider>.json`) is derived from a golden request:
// - `keyPaths`: every key path of the body with a role. `userContent` is the one path that carries the capture, the
//   room names and the titles; `at` gives its concrete path (value comparison uses concrete indices, N-3). Every other
//   path is `fixed`: its value equals the golden request's value at the same concrete path.
//   No path is both a leaf and a container (GR-5): OpenAI's system content is a text-part array like the user's, so
//   its erased path `$.messages[].content[].text` is shared by the fixed instructions (`$.messages[0]…`) and the user
//   content (`at`, `$.messages[1]…`); the concrete comparison keeps the instructions fixed.
// - `userContentKeyPaths`: the layout inside the user content, with the slot roles `capture`, `roomName`,
//   `shortlistIndex` and `shortlistTitle`, and `emptyList` for `rooms` or `existingTasks` when it has no element.
// - `headers`: the builder's headers in order (`auth` or `fixed`), then the headers the transport sets, which are
//   derived and left out of the Linux header comparison (plan WI-M2-10).
// Pure: no I/O, no clock, no logging.

import Foundation

public enum CloudRequestKeyPaths {

    /// The leaf key paths of a body, or nil when it is not strict JSON (integers only, no duplicate key).
    public static func leafPaths(ofBody body: Data) -> [String]? {
        guard let value = try? EvalJSONReader.parse(body) else { return nil }
        return leafPaths(of: value)
    }

    public static func leafPaths(of value: EvalJSON) -> [String] {
        var paths: Set<String> = []
        collect(value, path: "$", into: &paths)
        return paths.sorted { TextFolding.utf8Precedes($0, $1) }
    }

    private static func collect(_ value: EvalJSON, path: String, into paths: inout Set<String>) {
        switch value {
        case let .object(members):
            if members.isEmpty { paths.insert(path) }
            for member in members { collect(member.value, path: path + "." + member.key, into: &paths) }
        case let .array(elements):
            if elements.isEmpty { paths.insert(path) }
            for element in elements { collect(element, path: path + "[]", into: &paths) }
        case .null, .bool, .integer, .string:
            paths.insert(path)
        }
    }
}

public enum CloudAllowedKeyPaths {

    /// The concrete path of the user content in each provider's body.
    public static func userContentPath(_ provider: CloudProvider) -> String {
        switch provider {
        case .openAI: "$.messages[1].content[0].text"
        case .anthropic: "$.messages[0].content[0].text"
        case .gemini: "$.contents[0].parts[0].text"
        }
    }

    /// Headers a transport sets itself: `Content-Length` and `Host` from the body and the URL, and `Accept`,
    /// `Accept-Encoding` and `Connection`, fixed by the OS and not by the user (PO WI-M2-10 ruling 4; WI-M2-16 ruling
    /// 10, GR-3). They are not part of the builder's request and are left out of the Linux header comparison.
    public static let transportSetHeaders = ["Content-Length", "Host", "Accept", "Accept-Encoding", "Connection"]

    /// The allowed key-path list for `request`'s provider, as canonical JSON bytes; nil if the body is not readable.
    public static func list(for request: CloudRequest) throws(CanonicalJSONError) -> Data? {
        guard let paths = CloudRequestKeyPaths.leafPaths(ofBody: request.body) else { return nil }
        let at = userContentPath(request.provider)
        let userContentKeyPath = eraseIndices(at)
        let keyPaths: [CanonicalJSON] = paths.map { path in
            path == userContentKeyPath
                ? .object([.init("path", .string(path)), .init("role", .string("userContent")),
                           .init("at", .string(at))])
                : .object([.init("path", .string(path)), .init("role", .string("fixed"))])
        }
        let layout: [(String, String)] = [
            ("$.capture", "capture"), ("$.existingTasks", "emptyList"), ("$.existingTasks[].index", "shortlistIndex"),
            ("$.existingTasks[].title", "shortlistTitle"), ("$.rooms", "emptyList"), ("$.rooms[]", "roomName"),
        ]
        var headers: [CanonicalJSON] = request.headers.map { header in
            .object([.init("name", .string(header.name)),
                     .init("role", .string(header.isAuthorization ? "auth" : "fixed"))])
        }
        headers += transportSetHeaders.map {
            .object([.init("name", .string($0)), .init("role", .string("derivedByTransport"))])
        }
        return try CanonicalJSONWriter.data(.object([
            .init("schemaVersion", .integer(1)),
            .init("provider", .string(request.provider.rawValue)),
            .init("model", .string(request.model.rawValue)),
            .init("keyPaths", .array(keyPaths)),
            .init("userContentKeyPaths", .array(layout.map {
                .object([.init("path", .string($0.0)), .init("role", .string($0.1))])
            })),
            .init("headers", .array(headers)),
        ]))
    }

    /// `$.a[1].b[0]` → `$.a[].b[]`.
    static func eraseIndices(_ concrete: String) -> String {
        var result = ""
        var inIndex = false
        for character in concrete {
            if character == "[" { inIndex = true; result.append("[") }
            else if character == "]" { inIndex = false; result.append("]") }
            else if !inIndex { result.append(character) }
        }
        return result
    }
}
