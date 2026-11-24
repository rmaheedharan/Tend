// WI-M2-10: the 3 × 3 golden requests, the per-provider allowed key-path lists with roles (N-3; PO WI-M2-15 ruling 2),
// the key-path function, and the wiring from the router to the cloud model's request (AC-M2-20, the ○ part). P-3.
//
// The golden bytes are the requests the recording mock transport captured for the three golden households
// (`PayloadGolden`), compared byte for byte with `Fixtures/M2/payload/golden/`. The same test runs on the owner-run
// Mac in MS-2 (AC-M2-20 "Golden bytes", on Linux **and** the Mac). WI-M2-11 owns the ≥ 500-household sentinel and
// structural proof (AC-M2-20 (a), (b)).

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-10 golden requests, allowed key-path lists and wiring (AC-M2-20)")
struct PayloadGoldenTests {

    static let providers = CloudProvider.allCases

    static func goldenRequest(_ golden: PayloadGoldenCase, _ provider: CloudProvider) throws -> CloudRequest {
        let input = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                               titleSharing: .shortlistTitles)
        let built = try CloudPayloadBuilder.request(input, model: CloudModel.defaultModel(for: provider),
                                                    key: PayloadFixture.fakeKey)
        return try #require(PayloadRecordingTransport.capture(built))
    }

    /// When `TEND_PAYLOAD_GOLDEN_OUT` names a directory, also write the built files there (regeneration under a PO
    /// decision; never into the repository by itself).
    static func writeIfAsked(_ name: String, _ data: Data) {
        guard let directory = ProcessInfo.processInfo.environment["TEND_PAYLOAD_GOLDEN_OUT"], !directory.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static let goldenCases: [(PayloadGoldenCase, CloudProvider)] =
        PayloadGolden.all.flatMap { golden in CloudProvider.allCases.map { (golden, $0) } }

    @Test("AC-M2-20 golden bytes: 3 households × 3 providers, the captured request equals the committed head and body files exactly", arguments: goldenCases)
    func goldenBytes(golden: PayloadGoldenCase, provider: CloudProvider) throws {
        let request = try Self.goldenRequest(golden, provider)
        let stem = PayloadGolden.stem(golden, provider)
        let head = Data(PayloadText.head(request).utf8)
        Self.writeIfAsked("golden/" + stem + ".head.txt", head)
        Self.writeIfAsked("golden/" + stem + ".body.json", request.body)
        let committedHead = try PayloadFixture.repositoryFile(PayloadFixture.goldenDirectory + "/" + stem + ".head.txt")
        let committedBody = try PayloadFixture.repositoryFile(PayloadFixture.goldenDirectory + "/" + stem + ".body.json")
        #expect(head == committedHead, "\(stem).head.txt differs:\n\(PayloadText.string(head))")
        #expect(request.body == committedBody, "\(stem).body.json differs:\n\(PayloadText.string(request.body))")
        print("WI-M2-10 golden \(stem): head \(head.count) bytes, body \(request.body.count) bytes, "
              + "\(CloudContextSelector.input(capture: golden.capture, household: golden.household, titleSharing: .shortlistTitles).shortlistTitles.count) titles")
    }

    @Test("AC-M2-20 (a), golden households: no task or room ID, no non-shortlisted title, no date or interval of the household appears in any golden request", arguments: goldenCases)
    func goldenHoldsNoHouseholdField(golden: PayloadGoldenCase, provider: CloudProvider) throws {
        let request = try Self.goldenRequest(golden, provider)
        let all = Data(PayloadText.head(request).utf8) + request.body
        let sent = Set(CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                  titleSharing: .shortlistTitles).shortlistTitles)
        for task in golden.household.tasks {
            #expect(!PayloadOracle.contains(all, task.id.uuidString))
            #expect(!PayloadOracle.contains(all, task.id.uuidString.lowercased()))
            let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sent.contains(trimmed) {
                #expect(!PayloadOracle.contains(all, trimmed), "\(trimmed) is not on the shortlist")
            }
        }
        for room in golden.household.rooms {
            #expect(!PayloadOracle.contains(all, room.id.uuidString))
            #expect(!PayloadOracle.contains(all, room.id.uuidString.lowercased()))
        }
        for date in [PayloadFixture.start, PayloadFixture.end] {
            #expect(!PayloadOracle.contains(all, String(Int(date.timeIntervalSinceReferenceDate))))
            #expect(!PayloadOracle.contains(all, String(Int(date.timeIntervalSince1970))))
        }
    }

    @Test("the G1 golden body is the tend-payload-dump --outcome-sample body: the Outcome sentence, no rooms, no titles", arguments: providers)
    func outcomeSampleIsG1(provider: CloudProvider) throws {
        let input = CloudPayloadInput(capture: PayloadFixture.outcomeSentence, roomNames: [], shortlistTitles: [])
        let body = try CloudPayloadBuilder.body(input, model: CloudModel.defaultModel(for: provider))
        #expect(body == (try Self.goldenRequest(PayloadGolden.g1, provider)).body)
    }

    // MARK: - Key paths (results-file form, PO WI-M2-15 ruling 2)

    @Test("key paths: the leaf paths of a body in the results-file form, sorted by UTF-8 bytes and unique; containers give [] and .name; empty containers are leaves", arguments: [
        (#"{"b":1,"a":[{"x":true},{"x":null,"y":"s"}],"c":{},"d":[],"e":[[1,2]]}"#,
         ["$.a[].x", "$.a[].y", "$.b", "$.c", "$.d", "$.e[][]"]),
        (#"[]"#, ["$"]), (#"7"#, ["$"]), (#"{"A-b_9":{"Z":"z"}}"#, ["$.A-b_9.Z"]),
    ])
    func keyPathFunction(json: String, expected: [String]) {
        #expect(CloudRequestKeyPaths.leafPaths(ofBody: Data(json.utf8)) == expected)
        #expect(PayloadOracle.leafPaths(Data(json.utf8)) == expected)
    }

    @Test("key paths: a body that is not strict JSON gives nil", arguments: ["", "{", #"{"a":1.5}"#, #"{"a":1,"a":2}"#])
    func keyPathUnreadable(json: String) {
        #expect(CloudRequestKeyPaths.leafPaths(ofBody: Data(json.utf8)) == nil)
    }

    @Test("key paths of every golden body equal the independent oracle", arguments: goldenCases)
    func keyPathsMatchOracle(golden: PayloadGoldenCase, provider: CloudProvider) throws {
        let body = try Self.goldenRequest(golden, provider).body
        #expect(CloudRequestKeyPaths.leafPaths(ofBody: body) == PayloadOracle.leafPaths(body))
    }

    // MARK: - The allowed key-path lists with roles (N-3)

    static func allowedList(_ provider: CloudProvider) throws -> Data {
        try PayloadFixture.repositoryFile(PayloadFixture.payloadDirectory + "/allowed-key-paths-"
                                          + PayloadFixture.name(provider) + ".json")
    }

    @Test("N-3: each committed allowed key-path list equals the list derived from the golden requests (paths, roles, headers, user-content layout), byte for byte", arguments: providers)
    func allowedListDerived(provider: CloudProvider) throws {
        let golden = try Self.goldenRequest(PayloadGolden.g2, provider)
        let derived = try #require(try CloudAllowedKeyPaths.list(for: golden))
        Self.writeIfAsked("allowed-key-paths-" + PayloadFixture.name(provider) + ".json", derived)
        #expect(derived == (try Self.allowedList(provider)),
                "allowed-key-paths-\(PayloadFixture.name(provider)).json differs:\n\(PayloadText.string(derived))")
    }

    @Test("N-3: the allowed paths equal the key paths of all three golden bodies; exactly one path has role userContent, at the provider's user slot; every other path is fixed", arguments: providers)
    func allowedListContent(provider: CloudProvider) throws {
        let list = try EvalJSONReader.parse(try Self.allowedList(provider))
        guard case let .array(entries)? = list["keyPaths"] else {
            Issue.record("no keyPaths array")
            return
        }
        var paths: [String] = []
        var roles: [String: String] = [:]
        var userContentAt: [String] = []
        for entry in entries {
            guard case let .string(path)? = entry["path"], case let .string(role)? = entry["role"] else {
                Issue.record("entry without path and role: \(entry)")
                continue
            }
            paths.append(path)
            roles[path] = role
            if case let .string(at)? = entry["at"] { userContentAt.append(at) }
        }
        for golden in PayloadGolden.all {
            let body = try Self.goldenRequest(golden, provider).body
            #expect(PayloadOracle.leafPaths(body) == paths, "\(golden.name)")
        }
        #expect(roles.values.filter { $0 == "userContent" }.count == 1)
        #expect(Set(roles.values) == ["fixed", "userContent"])
        #expect(userContentAt == [PayloadOracle.userContentPath(provider)])
        // ds2-gated reads the same file (`--allowed-key-paths`).
        #expect(EvalProfileKeyPathsProbe.read(try Self.allowedList(provider)) == Set(paths))
        guard case let .array(headers)? = list["headers"] else {
            Issue.record("no headers array")
            return
        }
        let names = headers.compactMap { header -> String? in
            if case let .string(name)? = header["name"] { return name }
            return nil
        }
        let request = try Self.goldenRequest(PayloadGolden.g1, provider)
        #expect(Array(names.prefix(request.headerNames.count)) == request.headerNames)
        #expect(names.contains("Content-Length"), "transport-set headers are listed as derived")
    }

    @Test("GR-3, PO WI-M2-10 ruling 4 and WI-M2-16 ruling 10 (AC-M2-20, AC-M2-22 Headers): each allowed list names, in order, the auth header, the provider's headers, User-Agent and Accept-Language as fixed, then exactly Content-Length, Host, Accept, Accept-Encoding and Connection as transport-set; no other header", arguments: providers)
    func allowedListHeaders(provider: CloudProvider) throws {
        let list = try EvalJSONReader.parse(try Self.allowedList(provider))
        guard case let .array(headers)? = list["headers"] else {
            Issue.record("no headers array")
            return
        }
        var entries: [(String, String)] = []
        for header in headers {
            guard case let .string(name)? = header["name"], case let .string(role)? = header["role"] else {
                Issue.record("header without name and role: \(header)")
                continue
            }
            entries.append((name, role))
        }
        let providerHeaders: [String] = switch provider {
        case .openAI: ["Authorization", "Content-Type"]
        case .anthropic: ["x-api-key", "anthropic-version", "Content-Type"]
        case .gemini: ["x-goog-api-key", "Content-Type"]
        }
        let transportSet = ["Content-Length", "Host", "Accept", "Accept-Encoding", "Connection"]
        #expect(entries.map(\.0) == providerHeaders + ["User-Agent", "Accept-Language"] + transportSet)
        #expect(entries.map(\.1) == ["auth"] + Array(repeating: "fixed", count: providerHeaders.count + 1)
                + Array(repeating: "derivedByTransport", count: transportSet.count))
        #expect(CloudAllowedKeyPaths.transportSetHeaders == transportSet)
        // The builder sends the two fixed values itself (never the device's defaults).
        let request = try Self.goldenRequest(PayloadGolden.g1, provider)
        let values = request.headers.filter { !$0.isAuthorization }.map { ($0.name, $0.withValue { $0 }) }
        #expect(values.suffix(2).map(\.0) == ["User-Agent", "Accept-Language"])
        #expect(values.suffix(2).map(\.1) == ["Tend", "en-US"])
        #expect(Set(request.headerNames).isDisjoint(with: transportSet), "transport-set headers are not the builder's")
    }

    @Test("GR-5 (PO WI-M2-16 ruling 10; AC-M2-26 ds2-gated): no allowed key path is both a leaf and a container, so the [] form alone tells a string from a part array at every path", arguments: providers)
    func allowedPathsHaveOneShape(provider: CloudProvider) throws {
        let paths = try #require(EvalProfileKeyPathsProbe.read(try Self.allowedList(provider)))
        for path in paths {
            let containers = paths.filter { $0.hasPrefix(path + ".") || $0.hasPrefix(path + "[]") }
            #expect(containers.isEmpty, "\(path) is a leaf and the parent of \(containers.sorted().prefix(2))")
        }
    }

    @Test("GR-5 (PO WI-M2-16 ruling 10; AC-M2-26 ds2-gated): a system or user message whose content parts become a plain string sends a key path outside the allowed list, so the device subset check sees it", arguments: providers)
    func contentShapeChangeLeavesAllowedList(provider: CloudProvider) throws {
        let allowed = try #require(EvalProfileKeyPathsProbe.read(try Self.allowedList(provider)))
        let request = try Self.goldenRequest(PayloadGolden.g2, provider)
        #expect(Set(try #require(CloudRequestKeyPaths.leafPaths(ofBody: request.body))).isSubset(of: allowed))
        let flatten: (EvalJSON) -> EvalJSON = { value in
            guard case let .array(parts) = value, case let .string(text)? = parts.first?["text"] else { return value }
            return .string(text)
        }
        let slots: [(String, [JSONStep])] = switch provider {
        case .openAI: [("system", [.key("messages"), .index(0), .key("content")]),
                       ("user", [.key("messages"), .index(1), .key("content")])]
        case .anthropic: [("user", [.key("messages"), .index(0), .key("content")])]
        case .gemini: [("system", [.key("systemInstruction"), .key("parts")]),
                       ("user", [.key("contents"), .index(0), .key("parts")])]
        }
        for (name, steps) in slots {
            let body = PayloadStructure.modify(try EvalJSONReader.parse(request.body), at: steps, flatten)
            let data = try CanonicalJSONWriter.data(body.canonical)
            #expect(data != request.body, "\(name): the mutant changed nothing")
            let sent = Set(try #require(CloudRequestKeyPaths.leafPaths(ofBody: data)))
            #expect(!sent.isSubset(of: allowed), "\(name) content as a plain string is not seen: \(sent.subtracting(allowed))")
        }
    }

    @Test("PO WI-M2-15 ruling 2: every path in each allowed list, and in the user-content layout, passes the results-v1 keyPaths pattern", arguments: providers)
    func allowedListPattern(provider: CloudProvider) throws {
        let schema = try EvalJSONReader.parse(try PayloadFixture.repositoryFile(PayloadFixture.resultsSchemaPath))
        let pattern = try #require(Self.keyPathsPattern(in: schema))
        #expect(pattern == #"^\$(\.[A-Za-z0-9_-]+|\[\])*$"#)
        let regex = try #require(EvalSchemaCheck.compile(pattern))
        let list = try EvalJSONReader.parse(try Self.allowedList(provider))
        var checked = 0
        for member in ["keyPaths", "userContentKeyPaths"] {
            guard case let .array(entries)? = list[member] else {
                Issue.record("no \(member)")
                continue
            }
            for entry in entries {
                guard case let .string(path)? = entry["path"] else { continue }
                let range = NSRange(path.startIndex..., in: path)
                #expect(regex.firstMatch(in: path, range: range) != nil, "\(path)")
                checked += 1
            }
        }
        // The check is real: these are refused by the same pattern.
        for bad in ["$.a.", "$.a[0]", "a.b", "$.a b", "$.a\n", "$.x$"] {
            #expect(regex.firstMatch(in: bad, range: NSRange(bad.startIndex..., in: bad)) == nil, "\(bad)")
        }
        print("WI-M2-10 allowed list \(PayloadFixture.name(provider)): \(checked) paths pass the results-v1 pattern")
    }

    /// The `pattern` of `cloudRequests[].keyPaths[]` items in the committed results-v1 schema.
    static func keyPathsPattern(in schema: EvalJSON) -> String? {
        var found: String?
        func walk(_ value: EvalJSON) {
            guard case let .object(members) = value else {
                if case let .array(items) = value { items.forEach(walk) }
                return
            }
            for member in members {
                if member.key == "keyPaths", case let .string(p)? = member.value["items"]?["pattern"] { found = p }
                walk(member.value)
            }
        }
        walk(schema)
        return found
    }

    @Test("the user-content layout in each list names the four slot roles in the results-file form", arguments: providers)
    func userContentLayout(provider: CloudProvider) throws {
        let list = try EvalJSONReader.parse(try Self.allowedList(provider))
        guard case let .array(entries)? = list["userContentKeyPaths"] else {
            Issue.record("no userContentKeyPaths")
            return
        }
        var roles: [String: String] = [:]
        for entry in entries {
            if case let .string(path)? = entry["path"], case let .string(role)? = entry["role"] { roles[path] = role }
        }
        #expect(roles == ["$.capture": "capture", "$.rooms[]": "roomName", "$.rooms": "emptyList",
                          "$.existingTasks[].index": "shortlistIndex", "$.existingTasks[].title": "shortlistTitle",
                          "$.existingTasks": "emptyList"])
    }

    // MARK: - Wiring: the cloud model gets exactly the selector's values (brief Definitions "Cloud request")

    @Test("AC-M2-20 shortlist, through the router: a cloud capture's request carries the selector's titles (the same shortlist the duplicate marker reads); on-device requests carry none", arguments: providers)
    func routerWiring(provider: CloudProvider) async throws {
        let models = PayloadBuildingCloudModels()
        let keys = InMemoryAPIKeyStore()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)), cloudModels: models,
                                 consents: InMemoryCloudConsentStore(), keys: keys)
        _ = try await router.turnCloudOn(provider, key: PayloadFixture.fakeKey)
        for golden in PayloadGolden.all {
            let events = await router.events(input: golden.capture, household: golden.household,
                                             now: PayloadFixture.start, calendar: Calendar(identifier: .gregorian),
                                             timeZone: .gmt, titleSharing: .shortlistTitles,
                                             preference: .onDeviceFirst)
            for await _ in events {}
        }
        let requests = models.transport.requests
        #expect(requests.count == PayloadGolden.all.count)
        for (request, golden) in zip(requests, PayloadGolden.all) {
            #expect(request == (try Self.goldenRequest(golden, provider)), "\(golden.name)")
        }
    }

    @Test("wiring: the pipeline's request holds the cloud rules' shortlist titles under Q12 = yes, none under Q12 = no, none on device")
    func pipelineRequest() {
        let golden = PayloadGolden.g2
        let yes = DraftDuplicateRules.cloud(.shortlistTitles, capture: golden.capture, household: golden.household)
        let no = DraftDuplicateRules.cloud(.noTitles, capture: golden.capture, household: golden.household)
        let device = DraftDuplicateRules.onDevice(household: golden.household)
        #expect(yes.sentShortlistTitles == PayloadGolden.g2ExpectedTitles)
        #expect(no.sentShortlistTitles.isEmpty && device.sentShortlistTitles.isEmpty)
        #expect(NoDuplicateCheck().sentShortlistTitles.isEmpty)
        func request(_ rules: DraftDuplicateRules) -> IngestionRequest {
            DraftPipeline(input: golden.capture, rooms: golden.household.rooms, now: PayloadFixture.start,
                          calendar: Calendar(identifier: .gregorian), timeZone: .gmt, duplicateCheck: rules).request
        }
        #expect(request(yes) == IngestionRequest(input: golden.capture, roomNames: golden.household.rooms.map(\.name),
                                                 shortlistTitles: PayloadGolden.g2ExpectedTitles))
        #expect(request(no).shortlistTitles.isEmpty && request(device).shortlistTitles.isEmpty)
        #expect(CloudPayloadInput(request(yes)) == CloudContextSelector.input(
            capture: golden.capture, household: golden.household, titleSharing: .shortlistTitles))
        #expect(CloudPayloadInput(request(no)) == CloudContextSelector.input(
            capture: golden.capture, household: golden.household, titleSharing: .noTitles))
    }
}

/// Reads an allowed key-path list the way `tend-eval-score --allowed-key-paths` does (a JSON array of strings, or
/// `{"keyPaths": [...]}` of strings or `{"path": ...}` objects); the TendTools test checks the tool itself.
enum EvalProfileKeyPathsProbe {
    static func read(_ data: Data) -> Set<String>? {
        guard let root = try? EvalJSONReader.parse(data), case let .array(entries)? = root["keyPaths"] else {
            return nil
        }
        var result: Set<String> = []
        for entry in entries {
            guard case let .string(path)? = entry["path"] else { return nil }
            result.insert(path)
        }
        return result
    }
}
