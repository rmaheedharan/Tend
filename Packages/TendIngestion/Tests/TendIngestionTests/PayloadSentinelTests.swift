// WI-M2-11: the payload proof (● AC-M2-20 (a) byte-level unique sentinels and (b) the structural key-path and value
// check), over ≥ 500 seeded households per provider, through the path that really sends: `ModelRouter.events(…)` →
// `DraftPipeline` → the cloud model → `CloudPayloadBuilder` → the recording mock transport (review R28-F2). The
// structural check compares concrete array indices with the committed golden request (review R28-F6). Blank room names
// are sent as written (D11, Q19). P-2, P-3, P-4.
//
// Expectations are independent of the code under test: room names are the household's, the titles are the WI-M2-07
// shortlist oracle's (`DupOracle`), and every fixed byte and value is the committed golden request's
// (`Fixtures/M2/payload/`). The selector (`CloudContextSelector`) is checked to give the same values (R28-F2 (b)).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-11 payload proof: sentinels and structure over ≥ 500 households, through the router (AC-M2-20)")
struct PayloadSentinelTests {

    static let providers = CloudProvider.allCases
    static let seed: UInt64 = 0x0A1D_2011_0001
    static let households = 520
    static let answers: [CloudTitleSharing] = [.shortlistTitles, .noTitles]

    static func hex(_ seed: UInt64) -> String { "0x" + String(seed, radix: 16) }

    /// The expected builder input for a capture: the household's room names in order, and under Q12 = yes the
    /// independent oracle's shortlist titles (none under Q12 = no).
    static func expected(_ item: SentinelCase, _ answer: CloudTitleSharing) -> (CloudPayloadInput, Set<UUID>) {
        let entries = answer == .shortlistTitles ? DupOracle.shortlist(item.capture, item.household) : []
        return (CloudPayloadInput(capture: item.capture, roomNames: item.household.rooms.map(\.name),
                                  shortlistTitles: entries.map(\.title)), Set(entries.map(\.taskID)))
    }

    // MARK: - AC-M2-20 (a)

    @Test("AC-M2-20 (a): 520 seeded households × Q12 yes/no, through the router — no task or room ID, non-shortlisted title, date (four forms), now, time-zone or calendar identifier appears in the method, host, path, query, header names, header values or body; no interval 600…729 appears as a number or digits", arguments: providers)
    func byteLevelSentinels(provider: CloudProvider) async throws {
        let harness = try await PayloadRouterHarness.make(provider)
        var gen = SentinelHouseholdGenerator(seed: Self.seed)
        var requests = 0, sentinelsChecked = 0, titlesSent = 0, cut = 0
        var labels: [String: Int] = [:]
        var intervals: Set<Int> = []
        for h in 0..<Self.households {
            let item = gen.next(index: h)
            for task in item.household.tasks { if let days = task.recurrenceIntervalDays { intervals.insert(days) } }
            for answer in Self.answers {
                let context = "seed \(Self.hex(Self.seed)) household \(h) \(answer) \(provider)"
                let (expected, sentIDs) = Self.expected(item, answer)
                let sentinels = PayloadSentinels.strings(item, sentTaskIDs: sentIDs)
                let hygiene = PayloadSentinels.hygiene(sentinels, allowed: expected)
                #expect(hygiene.isEmpty, "generator hygiene, \(context): \(hygiene.prefix(3))")
                guard let request = await harness.send(item, titleSharing: answer) else {
                    Issue.record("no request captured, \(context)")
                    continue
                }
                let found = PayloadSentinels.stringProblems(request, SentinelScanner(sentinels))
                #expect(found.isEmpty, "\(context): \(found.prefix(5))")
                let interval = PayloadSentinels.intervalProblems(request)
                #expect(interval.isEmpty, "\(context): \(interval.prefix(5))")
                requests += 1
                sentinelsChecked += sentinels.count
                for sentinel in sentinels { labels[sentinel.label, default: 0] += 1 }
                titlesSent += expected.shortlistTitles.count
                if answer == .shortlistTitles && DupOracle.ranking(item.capture, item.household).count > 10 { cut += 1 }
            }
            await Task.yield()
        }
        let summary = labels.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("WI-M2-11 (a) \(provider) seed \(Self.hex(Self.seed)): \(Self.households) households, \(requests) requests, "
              + "\(sentinelsChecked) string sentinels, \(titlesSent) titles sent, \(cut) shortlists cut at 10, "
              + "\(intervals.count) distinct intervals in 600…729; \(summary)")
        // The run is meaningful: every kind of sentinel occurs, and the shortlist is both sent and cut.
        #expect(requests == Self.households * Self.answers.count)
        for label in ["task ID", "room ID", "task room ID", "non-shortlisted title", "title token",
                      "windowStart Unix milliseconds", "windowEnd reference-date seconds", "completedAt ISO 8601 UTC",
                      "lastTendedAt Unix seconds", "deferred until ISO 8601 local", "now Unix milliseconds",
                      "time-zone identifier", "calendar identifier"] {
            #expect(labels[label, default: 0] > 0, "no \(label) sentinel was generated")
        }
        #expect(titlesSent > 0 && cut > 0)
        #expect(intervals.count >= 100, "\(intervals.count) distinct intervals")
    }

    // MARK: - AC-M2-20 (b)

    @Test("AC-M2-20 (b): 520 seeded households × Q12 yes/no, through the router — the key-path set equals the allowed list; at concrete indices every fixed value equals the golden request; the user content is exactly the capture, the room names in order and the oracle's titles with indices 1…n; the selector gives the same input; headers equal the golden", arguments: providers)
    func structuralCheck(provider: CloudProvider) async throws {
        let reference = try PayloadStructure.reference(provider)
        let harness = try await PayloadRouterHarness.make(provider)
        var gen = SentinelHouseholdGenerator(seed: Self.seed)
        var requests = 0, blankRooms = 0, repeatedRooms = 0, emptyRooms = 0, titles = 0
        for h in 0..<Self.households {
            let item = gen.next(index: h)
            for answer in Self.answers {
                let context = "seed \(Self.hex(Self.seed)) household \(h) \(answer) \(provider)"
                let (expected, _) = Self.expected(item, answer)
                // R28-F2 (b): the selector (what the AC names) equals the independent expectation …
                let selected = CloudContextSelector.input(capture: item.capture, household: item.household,
                                                          titleSharing: answer)
                #expect(selected == expected, "selector, \(context)")
                guard let request = await harness.send(item, titleSharing: answer) else {
                    Issue.record("no request captured, \(context)")
                    continue
                }
                // … and the request that was really sent carries exactly those values, and nothing else changes.
                let problems = PayloadStructure.problems(request, expected: expected, reference: reference)
                #expect(problems.isEmpty, "\(context): \(problems.prefix(5))")
                requests += 1
                titles += expected.shortlistTitles.count
            }
            let names = item.household.rooms.map(\.name)
            blankRooms += names.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            repeatedRooms += names.count - Set(names).count
            if names.isEmpty { emptyRooms += 1 }
            await Task.yield()
        }
        print("WI-M2-11 (b) \(provider) seed \(Self.hex(Self.seed)): \(Self.households) households, \(requests) requests, "
              + "\(titles) titles, \(blankRooms) blank room names, \(repeatedRooms) repeated room names, "
              + "\(emptyRooms) households with no room; \(reference.allowedPaths.count) allowed paths, "
              + "\(reference.fixedLeaves.count) fixed concrete leaves")
        #expect(requests == Self.households * Self.answers.count)
        #expect(blankRooms > 0 && repeatedRooms > 0 && emptyRooms > 0 && titles > 0)
    }

    // MARK: - The checks are real (positive and negative controls)

    @Test("AC-M2-20 (b) control: the structural check passes every committed golden request (3 households, with the selector's values)", arguments: PayloadGoldenTests.goldenCases)
    func structureAcceptsGoldens(golden: PayloadGoldenCase, provider: CloudProvider) throws {
        let reference = try PayloadStructure.reference(provider)
        let stem = PayloadGolden.stem(golden, provider)
        let body = try PayloadFixture.repositoryFile(PayloadFixture.goldenDirectory + "/" + stem + ".body.json")
        let request = PayloadStructure.replacing(try PayloadGoldenTests.goldenRequest(golden, provider), body: body)
        let expected = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                  titleSharing: .shortlistTitles)
        #expect(PayloadStructure.problems(request, expected: expected, reference: reference).isEmpty)
        // And a wrong expectation is noticed.
        let wrong = CloudPayloadInput(capture: golden.capture, roomNames: expected.roomNames + ["Attic"],
                                      shortlistTitles: expected.shortlistTitles)
        #expect(!PayloadStructure.problems(request, expected: wrong, reference: reference).isEmpty)
    }

    /// Where each provider keeps its message list and the user message's parts.
    static func layout(_ provider: CloudProvider) -> (messages: String, user: Int, parts: String) {
        switch provider {
        case .openAI: ("messages", 1, "content")
        case .anthropic: ("messages", 0, "content")
        case .gemini: ("contents", 0, "parts")
        }
    }

    static func tampered(_ request: CloudRequest, _ change: (EvalJSON) -> EvalJSON) throws -> CloudRequest {
        let body = change(try EvalJSONReader.parse(request.body))
        return PayloadStructure.replacing(request, body: try CanonicalJSONWriter.data(body.canonical))
    }

    static func appendCopy(of index: Int) -> (EvalJSON) -> EvalJSON {
        { value in
            guard case let .array(elements) = value, elements.indices.contains(index) else { return value }
            return .array(elements + [elements[index]])
        }
    }

    @Test("R28-F6: an added message, an added part or an added enum element keeps the [] key-path set but is caught at concrete indices; an added member, a changed fixed value and a changed header are caught too", arguments: providers)
    func structureCatchesTampering(provider: CloudProvider) throws {
        let reference = try PayloadStructure.reference(provider)
        let golden = PayloadGolden.g2
        let request = try PayloadGoldenTests.goldenRequest(golden, provider)
        let expected = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                  titleSharing: .shortlistTitles)
        #expect(PayloadStructure.problems(request, expected: expected, reference: reference).isEmpty)
        let (messages, user, parts) = Self.layout(provider)
        let schemaPath: [JSONStep] = switch provider {
        case .openAI: [.key("response_format"), .key("json_schema"), .key("schema")]
        case .anthropic: [.key("tools"), .index(0), .key("input_schema")]
        case .gemini: [.key("generationConfig"), .key("responseJsonSchema")]
        }
        let effortEnum = schemaPath + [.key("properties"), .key("items"), .key("items"), .key("properties"),
                                       .key("effort"), .key("enum")]
        // Same `[]` key-path set, different element count (the gap R28-F6 names).
        let sameShape: [(String, CloudRequest)] = [
            ("extra message", try Self.tampered(request) {
                PayloadStructure.modify($0, at: [.key(messages)], Self.appendCopy(of: user)) }),
            ("extra part", try Self.tampered(request) {
                PayloadStructure.modify($0, at: [.key(messages), .index(user), .key(parts)], Self.appendCopy(of: 0)) }),
            ("extra enum element", try Self.tampered(request) {
                PayloadStructure.modify($0, at: effortEnum, Self.appendCopy(of: 0)) }),
        ]
        for (name, changed) in sameShape {
            #expect(CloudRequestKeyPaths.leafPaths(ofBody: changed.body) == reference.allowedPaths,
                    "\(name): the [] path set alone does not see it")
            let problems = PayloadStructure.problems(changed, expected: expected, reference: reference)
            #expect(problems.contains { $0.hasPrefix("concrete paths") }, "\(name): \(problems)")
        }
        let addMember: (EvalJSON) -> EvalJSON = { value in
            guard case let .object(members) = value else { return value }
            return .object(members + [EvalJSON.Member("user", .string("someone"))])
        }
        let flipStream: (EvalJSON) -> EvalJSON = { value in
            switch value {
            case .bool(true): .bool(false)
            case .string: .string("text/plain")
            default: value
            }
        }
        let streamPath: [JSONStep] = provider == .gemini ? [.key("generationConfig"), .key("responseMimeType")]
            : [.key("stream")]
        var headers = request.headers
        headers.append(CloudRequestHeader(name: "X-Extra", content: .text("1")))
        var changedValue = request.headers
        changedValue[changedValue.count - 1] = CloudRequestHeader(name: changedValue[changedValue.count - 1].name,
                                                                  content: .text("text/plain"))
        let others: [(String, CloudRequest)] = [
            ("added member", try Self.tampered(request) { PayloadStructure.modify($0, at: [], addMember) }),
            ("changed fixed value", try Self.tampered(request) { PayloadStructure.modify($0, at: streamPath, flipStream) }),
            ("extra header", PayloadStructure.replacing(request, headers: headers)),
            ("changed header value", PayloadStructure.replacing(request, headers: changedValue)),
            ("changed path", PayloadStructure.replacing(request, path: request.path + "x")),
            ("added query item", PayloadStructure.replacing(request, queryItems: request.queryItems
                                                            + [CloudQueryItem(name: "key", value: "k")])),
        ]
        for (name, changed) in others {
            #expect(!PayloadStructure.problems(changed, expected: expected, reference: reference).isEmpty, "\(name)")
        }
    }

    @Test("AC-M2-20 (b): a user content with an extra room, reordered rooms, a dropped or reordered title, a wrong index or an extra slot member is caught", arguments: providers)
    func structureCatchesUserContent(provider: CloudProvider) throws {
        let reference = try PayloadStructure.reference(provider)
        let golden = PayloadGolden.g2
        let expected = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                  titleSharing: .shortlistTitles)
        let model = CloudModel.defaultModel(for: provider)
        func built(_ input: CloudPayloadInput) throws -> CloudRequest {
            try CloudPayloadBuilder.request(input, model: model, key: PayloadFixture.fakeKey)
        }
        let wrongInputs: [(String, CloudPayloadInput)] = [
            ("extra room", CloudPayloadInput(capture: expected.capture, roomNames: expected.roomNames + ["Kitchen"],
                                             shortlistTitles: expected.shortlistTitles)),
            ("rooms reordered", CloudPayloadInput(capture: expected.capture, roomNames: expected.roomNames.reversed(),
                                                  shortlistTitles: expected.shortlistTitles)),
            ("title dropped", CloudPayloadInput(capture: expected.capture, roomNames: expected.roomNames,
                                                shortlistTitles: Array(expected.shortlistTitles.dropLast()))),
            ("titles reordered", CloudPayloadInput(capture: expected.capture, roomNames: expected.roomNames,
                                                   shortlistTitles: expected.shortlistTitles.reversed())),
            ("capture changed", CloudPayloadInput(capture: expected.capture + " ", roomNames: expected.roomNames,
                                                  shortlistTitles: expected.shortlistTitles)),
        ]
        for (name, input) in wrongInputs {
            #expect(!PayloadStructure.problems(try built(input), expected: expected, reference: reference).isEmpty,
                    "\(name)")
        }
        // A hand-made user content: an index from 0, and an extra slot member.
        let at = reference.userContentAt
        let steps: [JSONStep] = at.dropFirst(2).split(separator: ".").flatMap { part -> [JSONStep] in
            let pieces = part.split(separator: "[")
            return [.key(String(pieces[0]))] + pieces.dropFirst().compactMap { Int($0.dropLast()).map(JSONStep.index) }
        }
        let good = try built(expected)
        for replacement in [#"{"capture":"x","existingTasks":[{"index":0,"title":"t"}],"rooms":[]}"#,
                            #"{"capture":"x","existingTasks":[],"household":"h","rooms":[]}"#] {
            let changed = try Self.tampered(good) { PayloadStructure.modify($0, at: steps) { _ in .string(replacement) } }
            let wanted = CloudPayloadInput(capture: "x", roomNames: [], shortlistTitles: replacement.contains("index")
                                           ? ["t"] : [])
            let problems = PayloadStructure.problems(changed, expected: wanted, reference: reference)
            #expect(problems.contains { $0.hasPrefix("user content") || $0.hasPrefix("user-content") },
                    "\(replacement): \(problems)")
        }
    }

    @Test("AC-M2-20 (a) control: a sentinel planted in the body, path, query, a header name or a header value is found; an interval planted as a number or as digits is found", arguments: providers)
    func sentinelsArePlanted(provider: CloudProvider) throws {
        let request = try PayloadGoldenTests.goldenRequest(PayloadGolden.g2, provider)
        let id = UUID(uuidString: "6E5D0A10-0000-4000-8000-00000000F00D") ?? DupFixture.zeroUUID
        let date = Date(timeIntervalSince1970: 1_800_000_123.456)
        let sentinels = PayloadSentinels.forms(id, label: "task ID")
            + PayloadSentinels.forms(date, label: "now", timeZone: .gmt)
        let scanner = SentinelScanner(sentinels)
        #expect(PayloadSentinels.stringProblems(request, scanner).isEmpty)
        #expect(PayloadSentinels.intervalProblems(request).isEmpty)
        let plants = [id.uuidString, id.uuidString.lowercased(), "1800000123456", "1800000123",
                      String(Int(date.timeIntervalSinceReferenceDate)), "2027-01-15T08:02:03"]
        #expect(PayloadSentinels.forms(date, label: "now", timeZone: .gmt).first?.text == "2027-01-15T08:02:03")
        for plant in plants {
            let inBody = try Self.tampered(request) { value in
                guard case let .object(members) = value else { return value }
                return .object(members + [EvalJSON.Member("trace", .string("m" + plant))])
            }
            #expect(!PayloadSentinels.stringProblems(inBody, scanner).isEmpty, "body: \(plant)")
            #expect(!PayloadSentinels.stringProblems(PayloadStructure.replacing(request, path: request.path + plant),
                                                     scanner).isEmpty, "path: \(plant)")
            #expect(!PayloadSentinels.stringProblems(PayloadStructure.replacing(
                request, queryItems: [CloudQueryItem(name: "q", value: plant)]), scanner).isEmpty, "query: \(plant)")
            let header = CloudRequestHeader(name: "X-" + plant, content: .text("v"))
            let value = CloudRequestHeader(name: "X-Trace", content: .text(plant))
            #expect(!PayloadSentinels.stringProblems(PayloadStructure.replacing(request, headers: request.headers + [header]),
                                                     scanner).isEmpty, "header name: \(plant)")
            #expect(!PayloadSentinels.stringProblems(PayloadStructure.replacing(request, headers: request.headers + [value]),
                                                     scanner).isEmpty, "header value: \(plant)")
        }
        // Intervals: a JSON number, digits inside a string (the user content too), the path and a header value.
        let numberKey: [JSONStep] = provider == .gemini ? [.key("generationConfig"), .key("maxOutputTokens")]
            : [.key(provider == .openAI ? "max_completion_tokens" : "max_tokens")]
        let asNumber = try Self.tampered(request) { PayloadStructure.modify($0, at: numberKey) { _ in .integer(650) } }
        #expect(PayloadSentinels.intervalProblems(asNumber).contains { $0.hasPrefix("number 650") })
        let input = CloudPayloadInput(capture: "every 16501 days", roomNames: [], shortlistTitles: [])
        let inCapture = try CloudPayloadBuilder.request(input, model: CloudModel.defaultModel(for: provider),
                                                        key: PayloadFixture.fakeKey)
        #expect(PayloadSentinels.intervalProblems(inCapture).contains { $0.hasPrefix("650") })
        #expect(!PayloadSentinels.intervalProblems(PayloadStructure.replacing(request, path: request.path + "/729")).isEmpty)
        let header = CloudRequestHeader(name: "X-Interval", content: .text("P600D"))
        #expect(!PayloadSentinels.intervalProblems(PayloadStructure.replacing(request, headers: request.headers + [header])).isEmpty)
    }

    @Test("the sentinel scanner finds needles at the start, the end, overlapping and side by side, and nothing else")
    func scanner() {
        let needles = [Sentinel(text: "abcd", label: "a"), Sentinel(text: "abcdef", label: "b"),
                       Sentinel(text: "cdef", label: "c"), Sentinel(text: "zzzz9", label: "d"),
                       Sentinel(text: "xy", label: "short")]
        let scanner = SentinelScanner(needles)
        #expect(scanner.found(in: Array("abcdef".utf8)).map(\.label).sorted() == ["a", "b", "c"])
        #expect(scanner.found(in: Array("..zzzz9".utf8)).map(\.label) == ["d"])
        #expect(scanner.found(in: Array("zzzz".utf8)).isEmpty)
        #expect(scanner.found(in: Array("abc".utf8)).isEmpty)
        #expect(scanner.found(in: Array("axyb".utf8)).map(\.label) == ["short"])
        #expect(PayloadSentinels.intervalDigits(in: "a599b730 1600x729") == [600, 729])
    }

    // MARK: - D11 (Q19): blank room names are sent as written

    @Test("D11 (Q19): empty, whitespace-only and repeated room names are sent as written and in household order, through the router, for each provider", arguments: providers)
    func blankRoomNamesAreSent(provider: CloudProvider) async throws {
        let names = ["", "  ", "Kitchen", "\t", "Kitchen", "Kids\u{2019} room", " \n "]
        let rooms = names.enumerated().map { offset, name in
            Room(id: PayloadFixture.uuid(String(format: "0000000011%02X", offset)), name: name)
        }
        let household = Household(tasks: [PayloadFixture.task("0000000011B1", "Wipe the kitchen counter",
                                                               room: rooms[2].id)], rooms: rooms)
        let capture = "wipe the counter"
        let harness = try await PayloadRouterHarness.make(provider)
        let request = try #require(await harness.send(capture: capture, household: household,
                                                      now: PayloadFixture.start,
                                                      calendar: Calendar(identifier: .gregorian), timeZone: .gmt,
                                                      titleSharing: .shortlistTitles))
        let text = try #require(PayloadOracle.value(request.body, at: PayloadOracle.userContentPath(provider)) as? String)
        let slots = try #require(PayloadOracle.slots(ofUserContent: text))
        #expect(slots.roomNames == names)
        #expect(slots.shortlistTitles == ["Wipe the kitchen counter"])
        let selected = CloudContextSelector.input(capture: capture, household: household, titleSharing: .shortlistTitles)
        #expect(selected.roomNames == names)
        let reference = try PayloadStructure.reference(provider)
        #expect(PayloadStructure.problems(request, expected: selected, reference: reference).isEmpty)
    }
}
