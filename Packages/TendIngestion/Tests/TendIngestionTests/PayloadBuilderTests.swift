// WI-M2-10: the context selector and the payload builder for the three providers (AC-M2-20, the ○ part; brief
// Definitions "Cloud request", ADR-0005 Decisions 3, 4, 5 and 6; plan WI-M2-10, Q18; PO WI-M2-12 ruling 2).
// P-3. Every request assertion is made on the request the recording mock transport captured.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-10 payload builder: input type, selector, provider table, key placement, schema (AC-M2-20)")
struct PayloadBuilderTests {

    static let providers = CloudProvider.allCases

    static func captured(_ input: CloudPayloadInput, _ provider: CloudProvider,
                         key: APIKey = PayloadFixture.fakeKey) throws -> CloudRequest {
        let request = try CloudPayloadBuilder.request(input, model: CloudModel.defaultModel(for: provider), key: key)
        return try #require(PayloadRecordingTransport.capture(request))
    }

    static let sample = CloudPayloadInput(capture: "Buy dish pods and clean the oven", roomNames: ["Kitchen", "Hall"],
                                          shortlistTitles: ["Buy dishwasher pods"])

    // MARK: - The input type (AC-M2-20 "Media")

    @Test("AC-M2-20 media: the builder's input type stores exactly capture: String, roomNames: [String], shortlistTitles: [String] (Mirror)")
    func inputTypeMirror() {
        let mirror = Mirror(reflecting: Self.sample)
        let children = mirror.children.map { ($0.label ?? "?", String(describing: type(of: $0.value))) }
        #expect(children.map(\.0) == ["capture", "roomNames", "shortlistTitles"])
        #expect(children.map(\.1) == ["String", "Array<String>", "Array<String>"])
        #expect(mirror.superclassMirror == nil)
        #expect(mirror.displayStyle == .struct)
    }

    @Test("the builder input from a pipeline request carries its three text values and nothing else")
    func inputFromRequest() {
        let request = IngestionRequest(input: "wipe the hob", roomNames: ["Kitchen"], shortlistTitles: ["Wipe hob"])
        #expect(CloudPayloadInput(request)
                == CloudPayloadInput(capture: "wipe the hob", roomNames: ["Kitchen"], shortlistTitles: ["Wipe hob"]))
        #expect(IngestionRequest(input: "x", roomNames: []).shortlistTitles.isEmpty)
    }

    // MARK: - The context selector

    @Test("AC-M2-20 shortlist: the selector gives the capture, the room names as written in household order, and the shortlist titles in rank order (G2 hand-derived)")
    func selectorG2() {
        let input = CloudContextSelector.input(capture: PayloadGolden.g2.capture, household: PayloadGolden.g2.household,
                                               titleSharing: .shortlistTitles)
        #expect(input.capture == PayloadGolden.g2.capture)
        #expect(input.roomNames == ["Kitchen", "Bathroom", "Balcony", "Kids\u{2019} room", "Garage"])
        #expect(input.shortlistTitles == PayloadGolden.g2ExpectedTitles)
    }

    @Test("AC-M2-20 shortlist: at most 10 titles; completed tasks are never sent; titles are trimmed as stored (G3)")
    func selectorG3() {
        let household = PayloadGolden.g3.household
        let input = CloudContextSelector.input(capture: PayloadGolden.g3.capture, household: household,
                                               titleSharing: .shortlistTitles)
        #expect(DupOracle.ranking(PayloadGolden.g3.capture, household).count > 10, "G3 must exercise the cap")
        #expect(input.shortlistTitles.count == 10)
        #expect(input.shortlistTitles == DupOracle.shortlist(PayloadGolden.g3.capture, household).map(\.title))
        #expect(!input.shortlistTitles.contains("Donate old towels") && !input.shortlistTitles.contains("Buy towels"))
        #expect(input.shortlistTitles.contains("Hang towels"))
        #expect(input.roomNames == household.rooms.map(\.name))
    }

    @Test("AC-M2-20 Q12 = no: no task title is selected, rooms and capture unchanged")
    func selectorQ12No() {
        for golden in PayloadGolden.all {
            let yes = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                 titleSharing: .shortlistTitles)
            let no = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                titleSharing: .noTitles)
            #expect(no.shortlistTitles.isEmpty)
            #expect(no.capture == yes.capture && no.roomNames == yes.roomNames)
        }
    }

    @Test("AC-M2-20 shortlist: 3 seeds × 200 households × 6 queries — the selector's titles equal the independent shortlist oracle, ≤ 10, in rank order", arguments: [UInt64(0x0A1D_2010_0001), 0x0A1D_2010_0002, 0x0A1D_2010_0003])
    func selectorProperty(seed: UInt64) async {
        var gen = DupHouseholdGenerator(rnd: DupRandom(seed: seed))
        var queries = 0, titles = 0, capped = 0
        for h in 0..<200 {
            let household = gen.household()
            for q in 0..<6 {
                let capture = gen.query(household)
                let input = CloudContextSelector.input(capture: capture, household: household,
                                                       titleSharing: .shortlistTitles)
                let expected = DupOracle.shortlist(capture, household).map(\.title)
                #expect(input.shortlistTitles == expected, "seed 0x\(String(seed, radix: 16)) household \(h) query \(q)")
                #expect(input.roomNames == household.rooms.map(\.name) && input.capture == capture)
                queries += 1
                titles += input.shortlistTitles.count
                if DupOracle.ranking(capture, household).count > 10 { capped += 1 }
            }
            await Task.yield()
        }
        print("WI-M2-10 selector property seed 0x\(String(seed, radix: 16)): \(queries) captures, \(titles) titles, \(capped) cut at 10")
        #expect(capped > 0)
    }

    // MARK: - The provider table (plan WI-M2-10; ADR-0005 Decision 6; Q18)

    @Test("the provider table: bare hosts, method, path, query, header names in order, and the curated pinned model per provider", arguments: providers)
    func providerTable(provider: CloudProvider) throws {
        let request = try Self.captured(Self.sample, provider)
        #expect(request.method == "POST")
        #expect(request.provider == provider)
        switch provider {
        case .openAI:
            #expect(request.host == "api.openai.com")
            #expect(request.path == "/v1/chat/completions")
            #expect(request.queryItems.isEmpty)
            #expect(request.headerNames == ["Authorization", "Content-Type"])
            #expect(request.model == .gpt41Mini && request.model.rawValue == "gpt-4.1-mini-2025-04-14")
        case .anthropic:
            #expect(request.host == "api.anthropic.com")
            #expect(request.path == "/v1/messages")
            #expect(request.queryItems.isEmpty)
            #expect(request.headerNames == ["x-api-key", "anthropic-version", "Content-Type"])
            #expect(request.model == .claudeHaiku45 && request.model.rawValue == "claude-haiku-4-5-20251001")
        case .gemini:
            #expect(request.host == "generativelanguage.googleapis.com")
            #expect(request.path == "/v1beta/models/gemini-2.5-flash:streamGenerateContent")
            #expect(request.queryItems == [CloudQueryItem(name: "alt", value: "sse")])
            #expect(request.headerNames == ["x-goog-api-key", "Content-Type"])
            #expect(request.model == .gemini25Flash && request.model.rawValue == "gemini-2.5-flash")
        }
        #expect(!request.host.contains("/") && !request.host.contains(":"), "a bare host, no scheme or port")
        #expect(CloudModel.curated(for: provider) == [CloudModel.defaultModel(for: provider)])
        #expect(CloudModel.defaultModel(for: provider).provider == provider)
        #expect(CloudProviderTable.hosts.contains(request.host))
    }

    @Test("the curated list is closed: one model per provider, every ID differs, no free-text model")
    func curatedModels() {
        #expect(CloudModel.allCases.count == 3)
        #expect(Set(CloudModel.allCases.map(\.provider)) == Set(CloudProvider.allCases))
        #expect(CloudProviderTable.hosts == ["api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com"])
    }

    @Test("AC-M2-20 headers: every header value except the auth header is fixed", arguments: providers)
    func fixedHeaderValues(provider: CloudProvider) throws {
        let request = try Self.captured(Self.sample, provider)
        let values = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name, $0.withValue { $0 }) })
        #expect(values["Content-Type"] == "application/json")
        if provider == .anthropic { #expect(values["anthropic-version"] == "2023-06-01") }
        #expect(request.headers.filter(\.isAuthorization).count == 1)
    }

    // MARK: - Key placement (AC-M2-20 "Key placement"; ADR-0005 Decision 5)

    @Test("AC-M2-20 key placement: the key appears only in the provider's auth header — never in the method, host, path, query, other headers or body; Gemini never uses key=", arguments: providers)
    func keyPlacement(provider: CloudProvider) throws {
        let key = "FAKE-KEY-placement-check-not-real"
        let request = try Self.captured(Self.sample, provider, key: APIKey(key))
        let found = request.headers.first { $0.isAuthorization }
        let auth = try #require(found)
        switch provider {
        case .openAI:
            #expect(auth.name == "Authorization" && auth.withValue { $0 } == "Bearer " + key)
        case .anthropic:
            #expect(auth.name == "x-api-key" && auth.withValue { $0 } == key)
        case .gemini:
            #expect(auth.name == "x-goog-api-key" && auth.withValue { $0 } == key)
        }
        var elsewhere = [request.method, request.host, request.path]
        elsewhere += request.queryItems.flatMap { [$0.name, $0.value] }
        elsewhere += request.headers.map(\.name)
        elsewhere += request.headers.filter { !$0.isAuthorization }.map { $0.withValue { $0 } }
        #expect(!elsewhere.contains { $0.contains(key) })
        #expect(!PayloadOracle.contains(request.body, key))
        #expect(!request.queryItems.contains { $0.name.lowercased() == "key" })
    }

    @Test("P-3: a request, its headers and its body never show the key or the body in description, debugDescription or dump", arguments: providers)
    func requestFormatting(provider: CloudProvider) throws {
        let request = try Self.captured(Self.sample, provider)
        var dumped = ""
        dump(request, to: &dumped)
        for header in request.headers { dump(header, to: &dumped) }
        let texts = [String(describing: request), String(reflecting: request), dumped]
            + request.headers.flatMap { [String(describing: $0), String(reflecting: $0)] }
        for text in texts {
            #expect(!text.contains(PayloadFixture.fakeKeyText), "\(text)")
            #expect(!text.contains("dish pods"), "the capture must not reach a description: \(text)")
            #expect(!text.contains("Kitchen"), "room names must not reach a description: \(text)")
        }
        #expect(String(describing: request).contains("\(request.body.count) bytes"))
    }

    @Test("requests with different keys differ only in the auth header value")
    func keyOnlyChangesAuth() throws {
        for provider in Self.providers {
            let a = try Self.captured(Self.sample, provider, key: APIKey("FAKE-A"))
            let b = try Self.captured(Self.sample, provider, key: APIKey("FAKE-B"))
            #expect(a != b)
            #expect(a.body == b.body && a.path == b.path && a.headerNames == b.headerNames)
        }
    }

    // MARK: - Body: canonical JSON, opt-outs, sampling (AC-M2-20 "Golden bytes", "Opt-outs"; Q18 conditions 4, 5)

    @Test("AC-M2-20: the body is canonical JSON (writing the parsed value again gives the same bytes) with no floating point", arguments: providers)
    func canonicalBody(provider: CloudProvider) throws {
        for golden in PayloadGolden.all {
            let input = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                   titleSharing: .shortlistTitles)
            let request = try Self.captured(input, provider)
            let parsed = try EvalJSONReader.parse(request.body)  // integers only: a float is refused
            #expect(try CanonicalJSONWriter.data(parsed.canonical) == request.body, "\(golden.name)")
            #expect(try CloudPayloadBuilder.body(input, model: request.model) == request.body)
        }
    }

    @Test("AC-M2-20 opt-outs and sampling: stream on, temperature 0, OpenAI store false, Gemini thinking budget 0, a fixed output cap", arguments: providers)
    func optOutsAndSampling(provider: CloudProvider) throws {
        let body = try Self.captured(Self.sample, provider).body
        func at(_ path: String) -> Any? { PayloadOracle.value(body, at: path) }
        switch provider {
        case .openAI:
            #expect(at("$.stream") as? Bool == true)
            #expect(at("$.store") as? Bool == false)
            #expect(at("$.temperature") as? Int == 0)
            #expect(at("$.max_completion_tokens") as? Int == 4096)
            #expect(at("$.model") as? String == "gpt-4.1-mini-2025-04-14")
            #expect(at("$.response_format.type") as? String == "json_schema")
            #expect(at("$.response_format.json_schema.strict") as? Bool == true)
            #expect(at("$.response_format.json_schema.name") as? String == "tend_capture")
        case .anthropic:
            #expect(at("$.stream") as? Bool == true)
            #expect(at("$.temperature") as? Int == 0)
            #expect(at("$.max_tokens") as? Int == 4096)
            #expect(at("$.model") as? String == "claude-haiku-4-5-20251001")
            #expect(at("$.tool_choice.type") as? String == "tool")
            #expect(at("$.tool_choice.name") as? String == "record_items")
            #expect(at("$.tools[0].name") as? String == "record_items")
            #expect(at("$.thinking") == nil, "no extended thinking (Q18 condition 5)")
        case .gemini:
            #expect(at("$.generationConfig.temperature") as? Int == 0)
            #expect(at("$.generationConfig.thinkingConfig.thinkingBudget") as? Int == 0)
            #expect(at("$.generationConfig.maxOutputTokens") as? Int == 4096)
            #expect(at("$.generationConfig.responseMimeType") as? String == "application/json")
            #expect(at("$.model") == nil, "the Gemini model is in the path")
        }
    }

    @Test("ADR-0005 Decision 3: the instructions are fixed, sent once in the provider's system slot, and hold no household data", arguments: providers)
    func instructionsPlacement(provider: CloudProvider) throws {
        let body = try Self.captured(Self.sample, provider).body
        #expect(PayloadOracle.value(body, at: PayloadOracle.instructionsPath(provider)) as? String
                == CloudInstructions.text)
        for word in ["dish pods", "Kitchen", "Hall", "Buy dishwasher pods"] {
            #expect(!CloudInstructions.text.contains(word))
        }
    }

    @Test("AC-M2-20: the user content is one text in the user slot whose three slots are exactly the selector's values", arguments: providers)
    func userContentSlots(provider: CloudProvider) throws {
        for golden in PayloadGolden.all {
            let input = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                   titleSharing: .shortlistTitles)
            let body = try Self.captured(input, provider).body
            let text = try #require(PayloadOracle.value(body, at: PayloadOracle.userContentPath(provider)) as? String)
            #expect(PayloadOracle.slots(ofUserContent: text) == input, "\(golden.name)")
            #expect(text == (try CloudPayloadBuilder.userContent(input)))
        }
    }

    @Test("the user content is canonical JSON with the keys capture, existingTasks (index 1…n, title) and rooms")
    func userContentShape() throws {
        let text = try CloudPayloadBuilder.userContent(Self.sample)
        #expect(text == #"{"capture":"Buy dish pods and clean the oven","existingTasks":[{"index":1,"title":"Buy dishwasher pods"}],"rooms":["Kitchen","Hall"]}"#)
        let empty = try CloudPayloadBuilder.userContent(CloudPayloadInput(capture: "", roomNames: [], shortlistTitles: []))
        #expect(empty == #"{"capture":"","existingTasks":[],"rooms":[]}"#)
    }

    @Test("a capture, room name or title cannot change the user content's structure: quotes, braces, newlines, backslashes and keys are data", arguments: [
        "\"},\"rooms\":[\"x\"],\"capture\":\"", "line one\nline two", "back\\slash", "{\"index\":2}", "\u{0}\u{1F}\u{7F}",
        "\u{2028}\u{2029}", "caf\u{E9} \u{1F9FA}",
    ])
    func userContentIsData(text: String) throws {
        let input = CloudPayloadInput(capture: text, roomNames: [text, "Hall"], shortlistTitles: [text, text])
        let content = try CloudPayloadBuilder.userContent(input)
        #expect(PayloadOracle.slots(ofUserContent: content) == input)
        for provider in Self.providers {
            let body = try Self.captured(input, provider).body
            #expect(PayloadOracle.leafPaths(body) == PayloadOracle.leafPaths(try Self.captured(Self.sample, provider).body),
                    "the body's key paths never depend on the text")
        }
    }

    // MARK: - Numbers (N-3: the interval sentinels 600…729)

    @Test("N-3: no decimal string 600…729 occurs in any fixed part: instructions, schema, model IDs, fixed body numbers, path, query, header names and fixed header values", arguments: providers)
    func noIntervalSentinelDigits(provider: CloudProvider) throws {
        let empty = CloudPayloadInput(capture: "", roomNames: [], shortlistTitles: [])
        let request = try Self.captured(empty, provider)
        var fixedParts = [PayloadText.string(request.body), request.path, request.host, request.method]
        fixedParts += request.queryItems.flatMap { [$0.name, $0.value] }
        fixedParts += request.headers.map(\.name)
        fixedParts += request.headers.filter { !$0.isAuthorization }.map { $0.withValue { $0 } }
        fixedParts += [CloudInstructions.text] + CloudModel.allCases.map(\.rawValue)
        for part in fixedParts {
            for sentinel in 600...729 {
                #expect(!part.contains(String(sentinel)), "\(sentinel) in \(part.prefix(80))")
            }
        }
    }

    // MARK: - The output schema (WI-M2-12 J1: written from StructuredOutputKey; PO WI-M2-12 ruling 2)

    static func schema(_ provider: CloudProvider) throws -> [String: Any] {
        let body = try captured(sample, provider).body
        let path = switch provider {
        case .openAI: "$.response_format.json_schema.schema"
        case .anthropic: "$.tools[0].input_schema"
        case .gemini: "$.generationConfig.responseSchema"
        }
        return try #require(PayloadOracle.value(body, at: path) as? [String: Any])
    }

    static func itemSchema(_ provider: CloudProvider) throws -> [String: Any] {
        let root = try schema(provider)
        let items = try #require((root["properties"] as? [String: Any])?["items"] as? [String: Any])
        return try #require(items["items"] as? [String: Any])
    }

    @Test("the schema's root is {items: [item]}, and the item and time-hint members are exactly StructuredOutputKey's, all required", arguments: providers)
    func schemaKeys(provider: CloudProvider) throws {
        let root = try Self.schema(provider)
        #expect(root["required"] as? [String] == ["items"])
        let item = try Self.itemSchema(provider)
        let properties = try #require(item["properties"] as? [String: Any])
        #expect(Set(properties.keys) == Set(StructuredOutputKey.Item.allCases.map(\.rawValue)))
        #expect(item["required"] as? [String] == StructuredOutputKey.Item.allCases.map(\.rawValue))
        let time = try #require(properties["time"] as? [String: Any])
        let timeProperties = try #require(time["properties"] as? [String: Any])
        #expect(Set(timeProperties.keys) == Set(StructuredOutputKey.Time.allCases.map(\.rawValue)))
        #expect(time["required"] as? [String] == StructuredOutputKey.Time.allCases.map(\.rawValue))
        if provider == .gemini {
            let sorted = StructuredOutputKey.Item.allCases.map(\.rawValue).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            #expect(item["propertyOrdering"] as? [String] == sorted, "the same member order as the canonical JSON schema")
        } else {
            #expect(item["additionalProperties"] as? Bool == false)
            #expect(time["additionalProperties"] as? Bool == false)
            #expect(root["additionalProperties"] as? Bool == false)
        }
    }

    /// The enum strings a schema property allows, and whether it allows null, in either dialect.
    static func choices(_ property: Any?, provider: CloudProvider) -> (values: [String]?, nullable: Bool, type: String?) {
        guard let property = property as? [String: Any] else { return (nil, false, nil) }
        if provider == .gemini {
            return (property["enum"] as? [String], property["nullable"] as? Bool == true, property["type"] as? String)
        }
        if let anyOf = property["anyOf"] as? [[String: Any]], anyOf.count == 2,
           anyOf[1]["type"] as? String == "null", anyOf[1].count == 1 {
            return (anyOf[0]["enum"] as? [String], true, anyOf[0]["type"] as? String)
        }
        return (property["enum"] as? [String], false, property["type"] as? String)
    }

    @Test("the enum values equal the Swift cases (anchor: the model choices, never unrecognized); rule-(a) fields are never nullable; the others are", arguments: providers)
    func schemaValues(provider: CloudProvider) throws {
        let item = try Self.itemSchema(provider)
        let p = try #require(item["properties"] as? [String: Any])
        let time = try #require((p["time"] as? [String: Any])?["properties"] as? [String: Any])
        let g = provider == .gemini
        let str = g ? "STRING" : "string", int = g ? "INTEGER" : "integer", bool = g ? "BOOLEAN" : "boolean"

        // Rule (a) fields: a finished non-null value is always possible (PO WI-M2-12 ruling 2).
        for (name, type, values) in [("title", str, nil), ("room", str, nil), ("sourcePhrase", str, nil),
                                     ("kind", str, TaskKind.allCases.map(\.rawValue)),
                                     ("effort", str, Effort.allCases.map(\.rawValue)),
                                     ("isCritical", bool, nil), ("isDeepClean", bool, nil),
                                     ("isWeatherDependent", bool, nil)] as [(String, String, [String]?)] {
            let c = Self.choices(p[name], provider: provider)
            #expect(c.type == type && c.values == values && !c.nullable, "\(name): \(c)")
        }
        let anchor = Self.choices(time["anchor"], provider: provider)
        #expect(anchor.values == TimeHint.Anchor.modelChoices.map(\.rawValue) && !anchor.nullable)
        #expect(anchor.values?.contains("none") == true && anchor.values?.contains("unrecognized") == false)

        // Not rule (a): may be null.
        for (name, type, values) in [("daypart", str, Daypart.allCases.map(\.rawValue)),
                                     ("weekday", str, Weekday.allCases.map(\.rawValue)),
                                     ("season", str, TimeHint.Season.allCases.map(\.rawValue)),
                                     ("repeatUnit", str, TimeHint.RepeatUnit.allCases.map(\.rawValue)),
                                     ("month", int, nil), ("count", int, nil), ("repeatEvery", int, nil)]
            as [(String, String, [String]?)] {
            let c = Self.choices(time[name], provider: provider)
            #expect(c.type == type && c.values == values && c.nullable, "time.\(name): \(c)")
        }
        for name in ["sameAsItem", "sameAsExisting"] {
            let c = Self.choices(p[name], provider: provider)
            #expect(c.type == int && c.values == nil && c.nullable, "\(name): \(c)")
        }
        if g {
            #expect((p["kind"] as? [String: Any])?["format"] as? String == "enum")
        }
    }

    // MARK: - PO WI-M2-12 ruling 2: no null for rule-(a) fields; blank room → none, blank sourcePhrase → nil

    /// One item as a strict-mode model writes it for "Water the plants" with no room, no phrase and no time.
    static let noRoomItem = #"{"items":[{"effort":"low","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"kind":"oneOff","room":"","sameAsExisting":null,"sameAsItem":null,"sourcePhrase":"","time":{"anchor":"none","count":null,"daypart":null,"month":null,"repeatEvery":null,"repeatUnit":null,"season":null,"weekday":null},"title":"Water the plants"}]}"#

    @Test("PO WI-M2-12 ruling 2: an item with no room, no phrase and no time meets completion rule (a) with no null in a rule-(a) field")
    func ruleAWithoutNull() throws {
        let snapshot = try StructuredOutputReader.parse(Self.noRoomItem)
        let item = try #require(snapshot.items.first)
        #expect(item.roomName == "" && item.sourcePhrase == "" && item.time?.anchor == .known(.none))
        #expect(item.hasValueForEveryField)
    }

    @Test("PO WI-M2-12 ruling 2: a blank room (\"\", spaces) maps to room none; a blank sourcePhrase maps to nil", arguments: ["", "   ", "\t \n"])
    func blankRoomAndPhrase(blank: String) throws {
        let rooms = [Room(id: PayloadFixture.uuid("0000000009A1"), name: "Kitchen")]
        let mapper = DraftMapper(input: "water the plants", rooms: rooms, now: PayloadFixture.start,
                                 calendar: Calendar(identifier: .gregorian),
                                 timeZone: TimeZone(identifier: "America/New_York") ?? .gmt)
        let item = ItemSnapshot(title: "Water the plants", kind: .known(.oneOff), roomName: blank,
                                effort: .known(.low), isCritical: false, isDeepClean: false,
                                isWeatherDependent: false, time: TimeHintSnapshot(anchor: .known(.none)),
                                sourcePhrase: blank)
        #expect(item.hasValueForEveryField)
        let mapping = mapper.map(item, draftID: 1)
        guard case let .draft(draft) = mapping.outcome else {
            Issue.record("not a draft: \(mapping.outcome)")
            return
        }
        #expect(draft.room == .none)
        #expect(draft.sourcePhrase == nil)
    }

    @Test("PO WI-M2-12 ruling 2: the instructions ask for \"\" when there is no room or phrase and \"none\" for no time, and never ask the model to invent one")
    func instructionsBlankMeaning() {
        let text = CloudInstructions.text
        #expect(text.contains(#"otherwise """#))
        #expect(text.contains(#"anchor "none""#))
        #expect(text.contains("Never invent"))
        #expect(BannedTokens.tokens(in: text).isEmpty, "UX-3: no banned token in the instructions")
    }
}
