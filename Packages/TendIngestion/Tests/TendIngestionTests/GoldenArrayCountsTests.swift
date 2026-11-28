// D-059 element counts over the nine payload golden bodies (G1–G3 × OpenAI, Anthropic, Gemini). The expected lists
// are an independent oracle: computed once outside Swift (Python `json`, every array in document order, paths with
// concrete indices, sorted by UTF-8 bytes) from the committed golden bodies, then written here as literals. The fixed
// body shape is the same for G1, G2 and G3 of one provider; only the user-content counts differ.

import Foundation
import Testing
@testable import TendIngestion

@Suite("D-059: per-array element counts of the payload golden bodies")
struct GoldenArrayCountsTests {
    static let goldenCases = ["g1-outcome-empty", "g2-typical", "g3-edge"]

    /// Every array in each provider's sent body, with its element count (oracle).
    static let fixed: [CloudProvider: [(String, Int)]] = [
        .openAI: [
            ("$.messages", 2),
            ("$.messages[0].content", 1),
            ("$.messages[1].content", 1),
            ("$.response_format.json_schema.schema.properties.items.items.properties.effort.enum", 3),
            ("$.response_format.json_schema.schema.properties.items.items.properties.kind.enum", 3),
            ("$.response_format.json_schema.schema.properties.items.items.properties.sameAsExisting.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.sameAsItem.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.anchor.enum", 12),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.count.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.daypart.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.daypart.anyOf[0].enum", 4),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.month.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.repeatEvery.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.repeatUnit.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.repeatUnit.anyOf[0].enum", 4),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.season.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.season.anyOf[0].enum", 4),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.weekday.anyOf", 2),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.properties.weekday.anyOf[0].enum", 7),
            ("$.response_format.json_schema.schema.properties.items.items.properties.time.required", 8),
            ("$.response_format.json_schema.schema.properties.items.items.required", 11),
            ("$.response_format.json_schema.schema.required", 1),
        ],
        .anthropic: [
            ("$.messages", 1),
            ("$.messages[0].content", 1),
            ("$.tools", 1),
            ("$.tools[0].input_schema.properties.items.items.properties.effort.enum", 3),
            ("$.tools[0].input_schema.properties.items.items.properties.kind.enum", 3),
            ("$.tools[0].input_schema.properties.items.items.properties.sameAsExisting.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.sameAsItem.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.anchor.enum", 12),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.count.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.daypart.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.daypart.anyOf[0].enum", 4),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.month.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.repeatEvery.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.repeatUnit.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.repeatUnit.anyOf[0].enum", 4),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.season.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.season.anyOf[0].enum", 4),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.weekday.anyOf", 2),
            ("$.tools[0].input_schema.properties.items.items.properties.time.properties.weekday.anyOf[0].enum", 7),
            ("$.tools[0].input_schema.properties.items.items.properties.time.required", 8),
            ("$.tools[0].input_schema.properties.items.items.required", 11),
            ("$.tools[0].input_schema.required", 1),
        ],
        .gemini: [
            ("$.contents", 1),
            ("$.contents[0].parts", 1),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.effort.enum", 3),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.kind.enum", 3),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.sameAsExisting.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.sameAsItem.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.anchor.enum", 12),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.count.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.daypart.enum", 5),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.daypart.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.month.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.repeatEvery.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.repeatUnit.enum", 5),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.repeatUnit.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.season.enum", 5),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.season.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.weekday.enum", 8),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.properties.weekday.type", 2),
            ("$.generationConfig.responseJsonSchema.properties.items.items.properties.time.required", 8),
            ("$.generationConfig.responseJsonSchema.properties.items.items.required", 11),
            ("$.generationConfig.responseJsonSchema.required", 1),
            ("$.systemInstruction.parts", 1),
        ],
    ]

    /// Every array in the user-content object of each golden capture (oracle).
    static let content: [String: [(String, Int)]] = [
        "g1-outcome-empty": [
            ("$.existingTasks", 0),
            ("$.rooms", 0),
        ],
        "g2-typical": [
            ("$.existingTasks", 4),
            ("$.rooms", 5),
        ],
        "g3-edge": [
            ("$.existingTasks", 10),
            ("$.rooms", 5),
        ],
    ]

    static func body(_ golden: String, _ provider: CloudProvider) throws -> Data {
        try EvalSelfTest.data("Fixtures/M2/payload/golden/\(golden)-\(PayloadFixture.name(provider)).body.json")
    }

    static func counts(_ list: [(String, Int)]) -> [ArrayCount] { list.map { ArrayCount(path: $0.0, count: $0.1) } }

    @Test("each golden body's arrayCounts and userContentArrayCounts equal the oracle",
          arguments: goldenCases, CloudProvider.allCases)
    func goldenCounts(golden: String, provider: CloudProvider) throws {
        let data = try Self.body(golden, provider)
        #expect(CloudRequestKeyPaths.arrayCounts(ofBody: data) == Self.counts(try #require(Self.fixed[provider])))
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: data, provider: provider)
                == Self.counts(try #require(Self.content[golden])))
    }

    @Test("the oracle lists are sorted by UTF-8 bytes with unique paths, and every path matches the schema pattern")
    func oracleShape() throws {
        let pattern = try Regex(#"^\$(\.[A-Za-z0-9_-]+|\[(0|[1-9][0-9]*)\])*$"#)
        for list in Array(Self.fixed.values) + Array(Self.content.values) {
            let paths = list.map(\.0)
            #expect(zip(paths, paths.dropFirst()).allSatisfy { TextFolding.utf8Precedes($0, $1) })
            #expect(paths.allSatisfy { $0.wholeMatch(of: pattern) != nil })
        }
    }

    @Test("a body that is not strict JSON has null counts; a missing or non-object user content has null content counts")
    func nullCases() throws {
        let notJSON = Data("{\"messages\":[}".utf8)
        #expect(CloudRequestKeyPaths.arrayCounts(ofBody: notJSON) == nil)
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: notJSON, provider: .openAI) == nil)
        let noUserContent = Data(#"{"messages":[]}"#.utf8)
        #expect(CloudRequestKeyPaths.arrayCounts(ofBody: noUserContent) == [ArrayCount(path: "$.messages", count: 0)])
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: noUserContent, provider: .anthropic) == nil)
        let arrayContent = Data(#"{"messages":[{"content":[{"text":"[1,2]"}]}]}"#.utf8)
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: arrayContent, provider: .anthropic) == nil)
        let textContent = Data(#"{"messages":[{"content":[{"text":"hello"}]}]}"#.utf8)
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: textContent, provider: .anthropic) == nil)
        let emptyObject = Data(#"{"messages":[{"content":[{"text":"{}"}]}]}"#.utf8)
        #expect(CloudRequestKeyPaths.userContentArrayCounts(ofBody: emptyObject, provider: .anthropic) == [])
    }

    @Test("empty and nested arrays are counted, each with concrete indices of its enclosing arrays")
    func nestedAndEmpty() throws {
        let data = Data(#"{"a":[[],[1,[2,3]]],"b":{"c":[]}}"#.utf8)
        #expect(CloudRequestKeyPaths.arrayCounts(ofBody: data) == Self.counts([
            ("$.a", 2), ("$.a[0]", 0), ("$.a[1]", 2), ("$.a[1][1]", 2), ("$.b.c", 0),
        ]))
    }
}
