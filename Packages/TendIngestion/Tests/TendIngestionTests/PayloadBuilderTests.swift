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

    static let expectedModels = PayloadExpectedModel.all

    @Test("the provider table: bare host, method, path, query, header names in order and the model ID sent, per curated model (hand-written table, PO WI-M2-10 ruling 7)", arguments: expectedModels)
    func providerTable(row: PayloadExpectedModel) throws {
        #expect(row.model.rawValue == row.id)
        #expect(row.model.provider == row.provider)
        #expect((CloudModel.defaultModel(for: row.provider) == row.model) == row.isDefault)
        let request = try Self.captured(Self.sample, row.provider)
        #expect(request.method == "POST")
        #expect(request.provider == row.provider)
        #expect(request.model == row.model && request.model.rawValue == row.id)
        #expect(request.host == row.host)
        #expect(request.path == row.path)
        #expect(request.queryItems == row.query)
        #expect(request.headerNames == row.headerNames)
        #expect(!request.host.contains("/") && !request.host.contains(":"), "a bare host, no scheme or port")
        #expect(CloudProviderTable.hosts.contains(request.host))
    }

    @Test("the curated list is closed: every model is in the hand-written table, every ID differs, each provider's default is first in its list, and every curated model has a profile that fits its provider (R28-F7)")
    func curatedModels() {
        #expect(Set(CloudModel.allCases) == Set(Self.expectedModels.map(\.model)))
        #expect(Set(CloudModel.allCases.map(\.rawValue)).count == CloudModel.allCases.count)
        #expect(Set(CloudModel.allCases.map(\.provider)) == Set(CloudProvider.allCases))
        for provider in CloudProvider.allCases {
            let curated = CloudModel.curated(for: provider)
            #expect(curated.first == CloudModel.defaultModel(for: provider))
            #expect(curated.first == PayloadExpectedModel.row(provider)?.model)
            #expect(Set(curated) == Set(CloudModel.allCases.filter { $0.provider == provider }))
            #expect(curated.count == Set(curated).count)
            for model in curated {
                #expect(model.provider == provider)
                #expect(model.requestProfile == CloudProviderTable.profile(for: model))
                #expect(model.requestProfile.fits(provider), "\(model.rawValue)")
            }
        }
        #expect(CloudProviderTable.hosts == ["api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com"])
    }

    @Test("Q18 condition 2 (ruling 7): no model ID is a moving alias", arguments: CloudModel.allCases)
    func noMovingAlias(model: CloudModel) {
        for marker in ["latest", "preview", "exp", "beta", "alpha"] {
            #expect(!model.rawValue.contains(marker), "\(model.rawValue)")
        }
        #expect(!model.rawValue.isEmpty && !model.rawValue.contains(" "))
    }

    @Test("AC-M2-20 headers: every header value except the auth header is fixed", arguments: expectedModels)
    func fixedHeaderValues(row: PayloadExpectedModel) throws {
        let request = try Self.captured(Self.sample, row.provider)
        let values = Dictionary(uniqueKeysWithValues: request.headers.filter { !$0.isAuthorization }
            .map { ($0.name, $0.withValue { $0 }) })
        #expect(values == row.fixedHeaders)
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

    @Test("AC-M2-20 opt-outs and Q18 conditions 4 and 5 (revised, PO WI-M2-10 ruling 7): each model's fixed members are exactly the hand-written table's values, and the members it must not send are absent", arguments: expectedModels)
    func requestMembers(row: PayloadExpectedModel) throws {
        for golden in PayloadGolden.all {
            let input = CloudContextSelector.input(capture: golden.capture, household: golden.household,
                                                   titleSharing: .shortlistTitles)
            let body = try Self.captured(input, row.provider).body
            for (path, expected) in row.present {
                #expect(expected.matches(PayloadOracle.value(body, at: path)), "\(row.id) \(golden.name) \(path)")
            }
            for path in row.absent {
                #expect(PayloadOracle.value(body, at: path) == nil, "\(row.id) \(golden.name): \(path) must be absent")
            }
            #expect(PayloadOracle.value(body, at: row.schemaPath) is [String: Any], "\(row.id) schema member")
        }
    }

    @Test("R28-F7: a same-provider profile changes the body with no builder change (hypothetical profiles, never shipped)")
    func profileDrivesBody() throws {
        let gemini = CloudRequestProfile(sampling: .temperatureZero, reasoning: .geminiThinkingLevel("low"),
                                         usage: .streamedByDefault, schemaDialect: .jsonSchemaNullAnyOf,
                                         schemaMember: "responseSchemaX")
        let g = try CloudPayloadBuilder.body(Self.sample, model: .geminiDefault, profile: gemini)
        #expect(PayloadOracle.value(g, at: "$.generationConfig.temperature") as? Int == 0)
        #expect(PayloadOracle.value(g, at: "$.generationConfig.thinkingConfig.thinkingLevel") as? String == "low")
        #expect(PayloadOracle.value(g, at: "$.generationConfig.responseSchemaX") is [String: Any])
        #expect(PayloadOracle.value(g, at: "$.generationConfig.responseJsonSchema") == nil)
        let budget = CloudRequestProfile(sampling: .providerDefault, reasoning: .geminiThinkingBudget(0),
                                         usage: .streamedByDefault, schemaDialect: .jsonSchemaNullTypeArray,
                                         schemaMember: "responseJsonSchema")
        let b = try CloudPayloadBuilder.body(Self.sample, model: .geminiDefault, profile: budget)
        #expect(PayloadOracle.value(b, at: "$.generationConfig.thinkingConfig.thinkingBudget") as? Int == 0)
        #expect(PayloadOracle.value(b, at: "$.generationConfig.thinkingConfig.thinkingLevel") == nil)
        let openAI = CloudRequestProfile(sampling: .temperatureZero, reasoning: .noMember, usage: .streamedByDefault,
                                         schemaDialect: .jsonSchemaNullTypeArray, schemaMember: "schema")
        let o = try CloudPayloadBuilder.body(Self.sample, model: .openAIDefault, profile: openAI)
        #expect(PayloadOracle.value(o, at: "$.temperature") as? Int == 0)
        #expect(PayloadOracle.value(o, at: "$.reasoning_effort") == nil)
        #expect(PayloadOracle.value(o, at: "$.stream_options") == nil)
        let anthropic = CloudRequestProfile(sampling: .providerDefault, reasoning: .noMember,
                                            usage: .streamedByDefault, schemaDialect: .jsonSchemaNullAnyOf,
                                            schemaMember: "input_schema")
        let a = try CloudPayloadBuilder.body(Self.sample, model: .anthropicDefault, profile: anthropic)
        #expect(PayloadOracle.value(a, at: "$.temperature") == nil)
        #expect(PayloadOracle.value(a, at: "$.tools[0].input_schema") is [String: Any])
        // A profile member with no place in the provider's body does not fit.
        #expect(gemini.fits(.gemini) && !gemini.fits(.openAI) && !gemini.fits(.anthropic))
        #expect(openAI.fits(.openAI) && anthropic.fits(.anthropic))
        #expect(!CloudRequestProfile(sampling: .providerDefault, reasoning: .openAIReasoningEffort("none"),
                                     usage: .streamedByDefault, schemaDialect: .jsonSchemaNullAnyOf,
                                     schemaMember: "schema").fits(.gemini))
        #expect(!CloudRequestProfile(sampling: .providerDefault, reasoning: .noMember,
                                     usage: .openAIStreamOptionsIncludeUsage, schemaDialect: .jsonSchemaNullAnyOf,
                                     schemaMember: "input_schema").fits(.anthropic))
    }

    // MARK: - The builder's own shortlist cap (review R28-F3; Q12; AC-M2-20 "n ≤ 10")

    @Test("R28-F3: the builder refuses more than 10 shortlist titles with a typed error, for every provider; 10 are sent with indices 1…10", arguments: providers)
    func builderTitleCap(provider: CloudProvider) throws {
        #expect(CloudPayloadInput.maximumShortlistTitles == 10)
        let titles = (1...11).map { "Fake chore \($0)" }
        let eleven = CloudPayloadInput(capture: "wipe", roomNames: [], shortlistTitles: titles)
        let model = CloudModel.defaultModel(for: provider)
        #expect(throws: CloudPayloadError.tooManyShortlistTitles(count: 11)) {
            try CloudPayloadBuilder.request(eleven, model: model, key: PayloadFixture.fakeKey)
        }
        #expect(throws: CloudPayloadError.tooManyShortlistTitles(count: 11)) {
            try CloudPayloadBuilder.body(eleven, model: model)
        }
        #expect(throws: CloudPayloadError.tooManyShortlistTitles(count: 11)) {
            try CloudPayloadBuilder.userContent(eleven)
        }
        let ten = CloudPayloadInput(capture: "wipe", roomNames: [], shortlistTitles: Array(titles.prefix(10)))
        let body = try Self.captured(ten, provider).body
        let text = try #require(PayloadOracle.value(body, at: PayloadOracle.userContentPath(provider)) as? String)
        #expect(PayloadOracle.slots(ofUserContent: text) == ten)
        #expect(!text.contains("Fake chore 11"))
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
        let row = try #require(PayloadExpectedModel.row(provider))
        return try #require(PayloadOracle.value(body, at: row.schemaPath) as? [String: Any])
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
        #expect(item["additionalProperties"] as? Bool == false)
        #expect(time["additionalProperties"] as? Bool == false)
        #expect(root["additionalProperties"] as? Bool == false)
    }

    /// Every keyword used anywhere in a schema (the member names of schema objects, not of `properties`).
    static func keywords(_ schema: Any) -> Set<String> {
        guard let object = schema as? [String: Any] else {
            return (schema as? [Any])?.reduce(into: Set<String>()) { $0.formUnion(keywords($1)) } ?? []
        }
        var found = Set(object.keys)
        for (key, value) in object {
            if key == "properties", let properties = value as? [String: Any] {
                for member in properties.values { found.formUnion(keywords(member)) }
            } else if key != "enum" && key != "required" {
                found.formUnion(keywords(value))
            }
        }
        return found
    }

    @Test("PO WI-M2-10 ruling 7: every schema uses only JSON Schema keywords; Gemini's has no nullable, format or propertyOrdering, and no upper-case type", arguments: providers)
    func schemaKeywords(provider: CloudProvider) throws {
        let root = try Self.schema(provider)
        let row = try #require(PayloadExpectedModel.row(provider))
        let allowed: Set<String> = row.nullStyle == .anyOf
            ? ["type", "properties", "required", "additionalProperties", "items", "enum", "anyOf"]
            : ["type", "properties", "required", "additionalProperties", "items", "enum"]
        #expect(Self.keywords(root).isSubset(of: allowed), "\(Self.keywords(root).subtracting(allowed))")
        for banned in ["nullable", "format", "propertyOrdering"] {
            #expect(!Self.keywords(root).contains(banned))
        }
        let text = PayloadText.string(try Self.captured(Self.sample, provider).body)
        for upper in ["\"STRING\"", "\"INTEGER\"", "\"OBJECT\"", "\"ARRAY\"", "\"BOOLEAN\""] {
            #expect(!text.contains(upper))
        }
    }

    /// The enum strings a schema property allows, and whether it allows null, in either dialect.
    static func choices(_ property: Any?, provider: CloudProvider) -> (values: [String]?, nullable: Bool, type: String?) {
        guard let property = property as? [String: Any] else { return (nil, false, nil) }
        if PayloadExpectedModel.row(provider)?.nullStyle == .typeArray, let types = property["type"] as? [String] {
            // `type: [<type>, "null"]`, and a nullable enum lists null last: `[…, null]`.
            guard types.count == 2, types[1] == "null" else { return (nil, false, nil) }
            guard let raw = property["enum"] as? [Any] else { return (nil, true, types[0]) }
            guard raw.last is NSNull else { return (nil, false, types[0]) }
            return (raw.dropLast().compactMap { $0 as? String }, true, types[0])
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
        let str = "string", int = "integer", bool = "boolean"

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
