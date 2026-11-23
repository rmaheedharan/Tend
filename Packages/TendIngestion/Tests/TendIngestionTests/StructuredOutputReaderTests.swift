// The structured-output reader: a growing cloud JSON text to neutral `IngestionSnapshot`s (plan WI-M2-12; AC-M2-24,
// Linux part; AC-M2-05 through the same draft stream). FR-A1, P-3.
//
// The cloud schema's key names are `StructuredOutputKey` (WI-M2-10 writes the schema from the same names). The reader:
// - gives the latest snapshot after every chunk (incremental), for chunks cut anywhere;
// - shows only values the model finished writing: an open string, number or literal is still missing, so completion
//   rule (a) never fires on half a title (the PO WI-M2-06 ticket: "test a title that arrives last");
// - keeps an unknown enum value as `.unrecognized`, and reads a non-integer, huge or malformed number as nil;
// - maps the cloud claim fields into `sameAsItem` and `sameAsExisting(.shortlistIndex)`; `lookupQueries` stays empty;
// - reads a wrong-typed or `null` field as missing, keeps a non-object item as an empty item (positions stay), and
//   ignores unknown keys;
// - ends with a typed error for invalid JSON (`unreadableOutput`) or a cut-off text (`outputCutShort`), never a crash.
//
// Oracles: hand-written snapshots; and for the property, Foundation's `JSONDecoder` on the complete text plus a mapping
// written again here from the schema table (`ReaderOracle`).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

enum ReaderFixtures {
    /// Feeds `bytes` cut at `cuts`; returns the snapshot after each chunk and the final result.
    static func read(_ bytes: [UInt8], cuts: [Int] = [])
        -> (steps: [IngestionSnapshot], final: Result<IngestionSnapshot, PartialJSONError>) {
        var reader = StructuredOutputReader()
        var steps: [IngestionSnapshot] = []
        var start = 0
        for cut in cuts + [bytes.count] where cut >= start {
            do {
                steps.append(try reader.append(bytes: bytes[start..<cut]))
            } catch {
                return (steps, .failure(error))
            }
            start = cut
        }
        do {
            return (steps, .success(try reader.finish()))
        } catch {
            return (steps, .failure(error))
        }
    }

    static func read(_ text: String) -> Result<IngestionSnapshot, PartialJSONError> {
        read(Array(text.utf8)).final
    }

    static func items(_ text: String) throws -> [ItemSnapshot] {
        try read(text).get().items
    }

    /// A full item with every schema field, in schema order.
    static let fullItemJSON = #"{"title":"Buy dishwasher pods","kind":"restock","room":"Kitchen","effort":"low","#
        + #""isCritical":false,"isDeepClean":false,"isWeatherDependent":true,"#
        + #""time":{"anchor":"weekday","daypart":"evening","weekday":"saturday","month":6,"season":"summer","#
        + #""count":3,"repeatEvery":2,"repeatUnit":"week"},"sourcePhrase":"dishwasher pods","sameAsItem":1,"#
        + #""sameAsExisting":4}"#

    static let fullItem = ItemSnapshot(
        title: "Buy dishwasher pods", kind: .known(.restock), roomName: "Kitchen", effort: .known(.low),
        isCritical: false, isDeepClean: false, isWeatherDependent: true,
        time: TimeHintSnapshot(anchor: .known(.weekday), daypart: .known(.evening), weekday: .known(.saturday),
                               month: 6, season: .known(.summer), count: 3, repeatEvery: 2, repeatUnit: .known(.week)),
        sourcePhrase: "dishwasher pods", sameAsItem: 1, sameAsExisting: .shortlistIndex(4)
    )

    /// Each top-level member of `fullItemJSON`, as written there.
    static let fullItemMembers: [(String, String)] = [
        ("title", #""Buy dishwasher pods""#), ("kind", #""restock""#), ("room", #""Kitchen""#), ("effort", #""low""#),
        ("isCritical", "false"), ("isDeepClean", "false"), ("isWeatherDependent", "true"),
        ("time", #"{"anchor":"weekday","daypart":"evening","weekday":"saturday","month":6,"season":"summer","#
            + #""count":3,"repeatEvery":2,"repeatUnit":"week"}"#),
        ("sourcePhrase", #""dishwasher pods""#), ("sameAsItem", "1"), ("sameAsExisting", "4"),
    ]

    static func object(_ members: [(String, String)]) -> String {
        "{" + members.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
    }

    static func output(_ items: [String]) -> String { #"{"items":["# + items.joined(separator: ",") + "]}" }
}

@Suite("AC-M2-24 structured-output reader: cloud JSON to neutral snapshots (FR-A1)")
struct StructuredOutputReaderTests {
    typealias R = ReaderFixtures

    @Test("AC-M2-24: every schema field maps to its ItemSnapshot field, including the time hint and both claims")
    func fullItem() throws {
        #expect(try R.items(R.output([R.fullItemJSON])) == [R.fullItem])
        #expect(try R.read(R.output([R.fullItemJSON])).get().lookupQueries == [])
    }

    @Test("AC-M2-24: the schema key list covers every ItemSnapshot and TimeHintSnapshot field (room ↔ roomName)")
    func keyListCoversTheModel() {
        let itemFields = Mirror(reflecting: ItemSnapshot()).children.compactMap(\.label)
        let itemKeys = StructuredOutputKey.Item.allCases.map { $0 == .room ? "roomName" : $0.rawValue }
        #expect(itemKeys == itemFields)
        let timeFields = Mirror(reflecting: TimeHintSnapshot()).children.compactMap(\.label)
        #expect(StructuredOutputKey.Time.allCases.map(\.rawValue) == timeFields)
        #expect(StructuredOutputKey.items == "items")
    }

    @Test("AC-M2-24: field order does not matter (200 seeded orders of the item's and the hint's members)")
    func fieldOrder() throws {
        var rng = SplitMix64(seed: 0x0A11_C0DE_1201)
        for _ in 0..<200 {
            var members = R.fullItemMembers
            members.shuffle(using: &rng)
            let json = R.object(members)
            #expect(try R.items(R.output([json])) == [R.fullItem], "\(json)")
            let wrapped = #"{"note":"x","items":["# + json + #"],"more":[1,{"items":[]}]}"#
            #expect(try R.items(wrapped) == [R.fullItem], "\(wrapped)")
        }
        let shuffledTime = #"{"items":[{"time":{"repeatUnit":"day","count":2,"anchor":"inDays"},"title":"Mop"}]}"#
        #expect(try R.items(shuffledTime) == [ItemSnapshot(
            title: "Mop", time: TimeHintSnapshot(anchor: .known(.inDays), count: 2, repeatUnit: .known(.day)))])
    }

    @Test("AC-M2-24: unknown enum values are kept as .unrecognized (exact match only; case and spaces count)")
    func unknownEnums() throws {
        let json = R.output([#"{"title":"A","kind":"chore","effort":"High","time":{"anchor":"someday","# +
            #""daypart":"noon","weekday":"Mon","season":"fall","repeatUnit":" day"}}"#])
        #expect(try R.items(json) == [ItemSnapshot(
            title: "A", kind: .unrecognized("chore"), effort: .unrecognized("High"),
            time: TimeHintSnapshot(anchor: .unrecognized("someday"), daypart: .unrecognized("noon"),
                                   weekday: .unrecognized("Mon"), season: .unrecognized("fall"),
                                   repeatUnit: .unrecognized(" day")))])
    }

    @Test("AC-M2-24: non-integer, huge or exponent numbers are read exactly: whole numbers kept, the rest nil",
          arguments: [
            ("6", 6), ("6.0", 6), ("0.6e1", 6), ("60e-1", 6), ("1.5", nil), ("-0.5", nil), ("1e400", nil),
            ("9223372036854775808", nil), ("-9223372036854775809", nil), ("9223372036854775807", Int.max),
            ("1.0000000000000000001", nil), ("-3", -3),
          ] as [(String, Int?)])
    func numbers(_ text: String, _ expected: Int?) throws {
        let json = R.output([#"{"title":"A","time":{"month":\#(text),"count":\#(text),"repeatEvery":\#(text)},"#
            + #""sameAsItem":\#(text),"sameAsExisting":\#(text)}"#])
        let item = try #require(try R.items(json).first)
        #expect(item.time?.month == expected)
        #expect(item.time?.count == expected)
        #expect(item.time?.repeatEvery == expected)
        #expect(item.sameAsItem == expected)
        #expect(item.sameAsExisting == expected.map(ExistingTaskClaim.shortlistIndex))
    }

    @Test("AC-M2-24: the cloud claim fields map to sameAsItem and sameAsExisting(.shortlistIndex); absent claims are nil")
    func claims() throws {
        let json = R.output([#"{"title":"A"}"#, #"{"title":"B","sameAsItem":1}"#, #"{"title":"C","sameAsExisting":2}"#,
                             #"{"title":"D","sameAsItem":null,"sameAsExisting":null}"#])
        let items = try R.items(json)
        #expect(items.map(\.sameAsItem) == [nil, 1, nil, nil])
        #expect(items.map(\.sameAsExisting) == [nil, nil, .shortlistIndex(2), nil])
        #expect(items[1].duplicateClaim == DuplicateClaim(sameAsItem: 1))
        #expect(items[2].duplicateClaim == DuplicateClaim(sameAsShortlistIndex: 2))
    }

    @Test("AC-M2-24: null and wrong-typed fields are missing; unknown keys (any nesting) are ignored")
    func wrongTypes() throws {
        let json = R.output([#"{"title":5,"kind":["oneOff"],"room":null,"effort":true,"isCritical":"true","# +
            #""isDeepClean":0,"isWeatherDependent":null,"time":"tomorrow","sourcePhrase":{"a":1},"# +
            #""sameAsItem":"1","sameAsExisting":[2],"extra":{"title":"no","items":[{"title":"no"}]}}"#,
                             #"{"title":"B","time":{"anchor":3,"month":"6","count":true,"daypart":null}}"#,
                             #"{"title":"C","time":null}"#])
        #expect(try R.items(json) == [ItemSnapshot(), ItemSnapshot(title: "B", time: TimeHintSnapshot()),
                                      ItemSnapshot(title: "C")])
    }

    @Test("AC-M2-24: a non-object item is an empty item, so the positions of later items stay right")
    func nonObjectItems() throws {
        let items = try R.items(R.output(["\"Buy pods\"", "3", "null", "[]", #"{"title":"E","sameAsItem":1}"#]))
        #expect(items == [ItemSnapshot(), ItemSnapshot(), ItemSnapshot(), ItemSnapshot(),
                          ItemSnapshot(title: "E", sameAsItem: 1)])
    }

    @Test("AC-M2-24: a root that is not an object, or items that are not an array, give no items")
    func wrongRoot() throws {
        #expect(try R.items(#"[{"title":"A"}]"#) == [])
        #expect(try R.items(#""A""#) == [])
        #expect(try R.items(#"{"items":{"title":"A"}}"#) == [])
        #expect(try R.items(#"{"items":null}"#) == [])
        #expect(try R.items(#"{"Items":[{"title":"A"}]}"#) == [])
        #expect(try R.items(#"{}"#) == [])
    }

    @Test("AC-M2-24: only finished values appear: an open string, number or literal is missing until it ends")
    func onlyFinishedValues() {
        func snapshot(_ text: String) -> [ItemSnapshot]? {
            var reader = StructuredOutputReader()
            return try? reader.append(text).items
        }
        #expect(snapshot("") == [])
        #expect(snapshot(#"{"items":["#) == [])
        #expect(snapshot(#"{"items":[{"#) == [ItemSnapshot()])
        #expect(snapshot(#"{"items":[{"title":"Buy di"#) == [ItemSnapshot()])
        #expect(snapshot(#"{"items":[{"title":"Buy dish pods""#) == [ItemSnapshot(title: "Buy dish pods")])
        #expect(snapshot(#"{"items":[{"kind":"recur"#) == [ItemSnapshot()])
        #expect(snapshot(#"{"items":[{"isCritical":tru"#) == [ItemSnapshot()])
        #expect(snapshot(#"{"items":[{"isCritical":true"#) == [ItemSnapshot(isCritical: true)])
        #expect(snapshot(#"{"items":[{"sameAsItem":1"#) == [ItemSnapshot()])
        #expect(snapshot(#"{"items":[{"sameAsItem":12}"#) == [ItemSnapshot(sameAsItem: 12)])
        #expect(snapshot(#"{"items":[{"time":{"anchor":"to"#) == [ItemSnapshot(time: TimeHintSnapshot())])
        #expect(snapshot(#"{"items":[{"title":"A"},"#) == [ItemSnapshot(title: "A")])
        #expect(snapshot(#"{"items":[{"title":"A"},{"#) == [ItemSnapshot(title: "A"), ItemSnapshot()])
    }

    @Test("AC-M2-24: a title that arrives last (3-byte chunks): rule (a) fires only on the whole title; one emitted draft, never a prefix")
    func titleArrivesLast() async throws {
        var members = R.fullItemMembers.filter { $0.0 != "title" && $0.0 != "sameAsItem" && $0.0 != "sameAsExisting" }
        members.append(("title", #""Mop the kitchen floor""#))
        let bytes = Array(R.output([R.object(members)]).utf8)
        let read = R.read(bytes, cuts: Array(stride(from: 0, to: bytes.count, by: 3)))
        let final = try read.final.get()
        #expect(final.items.first?.title == "Mop the kitchen floor")
        for step in read.steps {
            #expect(step.items.allSatisfy { $0.title == nil || $0.title == "Mop the kitchen floor" })
        }
        // The steps reach completion rule (a) only when the title closes, before the end of the stream.
        let firstFull = try #require(read.steps.firstIndex { $0.items.first?.hasValueForEveryField == true })
        #expect(read.steps[firstFull].items.first?.title == "Mop the kitchen floor")
        #expect(firstFull < read.steps.count - 1)

        let steps = read.steps.map { ScriptStep.snapshot($0.items) } + [.finish]
        let events = await StreamFixtures.pipelineEvents(steps, cloud: .anthropic)
        let emitted = events.compactMap { event -> IngestionDraft? in
            if case let .emitted(draft) = event { return draft } else { return nil }
        }
        #expect(emitted.map(\.title) == ["Mop the kitchen floor"])
        #expect(!events.contains { if case .updated = $0 { true } else { false } })
        #expect(events.last == .finished(.completed(route: .cloud(.anthropic), input: nil, plainNote: nil)))
        #expect(events == StreamFixtures.assemble([.snapshot(final.items), .finish], route: .cloud(.anthropic)))
    }

    @Test("AC-M2-24: a text cut off after the first draft ends interrupted (outputCutShort); the draft stays")
    func truncatedAfterDraft() async throws {
        let text = R.output([R.fullItemJSON, #"{"title":"Mop the floor","kind":"oneOff""#])
        let bytes = Array(text.utf8.dropLast(3))
        let read = R.read(bytes, cuts: Array(stride(from: 0, to: bytes.count, by: 7)))
        #expect(read.final == .failure(.cutShort))
        let steps = read.steps.map { ScriptStep.snapshot($0.items) } + [.stop(PartialJSONError.cutShort.stopReason)]
        let events = await StreamFixtures.pipelineEvents(steps, cloud: .openAI)
        #expect(events.filter { if case .emitted = $0 { true } else { false } }.count == 1)
        #expect(events.last == .finished(StreamFixtures.interrupted(.outputCutShort, discarded: .stoppedBeforeComplete,
                                                                     route: .cloud(.openAI))))
    }

    @Test("AC-M2-24: invalid JSON before any draft ends noModel (unreadableOutput) with the plain-note offer")
    func invalidBeforeDraft() async throws {
        let bytes = Array(#"{"items":[{"title":"Buy pods","kind":restock}]}"#.utf8)
        let read = R.read(bytes, cuts: Array(stride(from: 0, to: bytes.count, by: 5)))
        guard case let .failure(.invalid(issue, offset)) = read.final else {
            Issue.record("expected invalid JSON, got \(read.final)")
            return
        }
        #expect(issue == .unexpectedByte)
        #expect(offset == 37)
        let failure = PartialJSONError.invalid(issue, byteOffset: offset)
        let steps = read.steps.map { ScriptStep.snapshot($0.items) } + [.stop(failure.stopReason)]
        let events = await StreamFixtures.pipelineEvents(steps, cloud: .gemini)
        guard case let .finished(.noModel(route, reason, input, plainNote))? = events.last else {
            Issue.record("expected noModel, got \(events)")
            return
        }
        #expect(events.count == 1)
        #expect(route == .cloud(.gemini))
        #expect(reason == .stoppedBeforeFirstDraft(.unreadableOutput))
        #expect(input == StreamFixtures.input)
        #expect(plainNote != nil)
    }

    @Test("AC-M2-24: the String API equals the byte API; after an error the reader stays closed")
    func stringAPIAndSticky() throws {
        var reader = StructuredOutputReader()
        _ = try reader.append(#"{"items":[{"title":"Caf"#)
        _ = try reader.append("\u{E9} \u{1F9FD}\"}]}")
        #expect(try reader.finish() == R.read(Array(#"{"items":[{"title":"Café 🧽"}]}"#.utf8)).final.get())

        var broken = StructuredOutputReader()
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try broken.append("{]") }
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try broken.append("}") }
        #expect(throws: PartialJSONError.invalid(.unexpectedByte, byteOffset: 1)) { try broken.finish() }
    }

    @Test("AC-M2-24: the one-shot parse equals the final incremental snapshot")
    func oneShot() throws {
        let text = R.output([R.fullItemJSON, #"{"title":"Mop"}"#])
        #expect(try StructuredOutputReader.parse(text) == R.read(Array(text.utf8), cuts: [10, 40, 41]).final.get())
        #expect(throws: PartialJSONError.cutShort) { try StructuredOutputReader.parse(#"{"items":["#) }
    }
}

// MARK: - Property: random valid outputs, random cuts, an independent oracle

/// The schema mapping written again for the oracle, over `JSONDecoder`'s value (`OracleJSON`).
enum ReaderOracle {
    static func snapshot(_ value: OracleJSON) -> IngestionSnapshot {
        guard case let .object(root) = value, case let .array(elements)? = root["items"] else {
            return IngestionSnapshot(items: [])
        }
        return IngestionSnapshot(items: elements.map(item))
    }

    static func item(_ value: OracleJSON) -> ItemSnapshot {
        guard case let .object(o) = value else { return ItemSnapshot() }
        var time: TimeHintSnapshot?
        if case let .object(t)? = o["time"] {
            time = TimeHintSnapshot(anchor: choice(t["anchor"]), daypart: choice(t["daypart"]),
                                    weekday: choice(t["weekday"]), month: number(t["month"]),
                                    season: choice(t["season"]), count: number(t["count"]),
                                    repeatEvery: number(t["repeatEvery"]), repeatUnit: choice(t["repeatUnit"]))
        }
        return ItemSnapshot(title: text(o["title"]), kind: choice(o["kind"]), roomName: text(o["room"]),
                            effort: choice(o["effort"]), isCritical: flag(o["isCritical"]),
                            isDeepClean: flag(o["isDeepClean"]), isWeatherDependent: flag(o["isWeatherDependent"]),
                            time: time, sourcePhrase: text(o["sourcePhrase"]), sameAsItem: number(o["sameAsItem"]),
                            sameAsExisting: number(o["sameAsExisting"]).map { .shortlistIndex($0) })
    }

    static func text(_ value: OracleJSON?) -> String? {
        if case let .string(text)? = value { return text }
        return nil
    }

    static func choice<V>(_ value: OracleJSON?) -> ModelChoice<V>?
        where V: RawRepresentable & Hashable & Sendable, V.RawValue == String {
        text(value).map { ModelChoice(raw: $0) }
    }

    static func flag(_ value: OracleJSON?) -> Bool? {
        if case let .bool(flag)? = value { return flag }
        return nil
    }

    static func number(_ value: OracleJSON?) -> Int? {
        if case let .number(number)? = value { return number }
        return nil
    }
}

/// A seeded writer of valid model outputs: random fields, types, enum values, numbers, escapes, whitespace and order.
struct OutputCorpus {
    var rng: SplitMix64

    static let words = ["Buy", "dish", "pods", "mop", "the", "kitchen", "AC", "caf\u{E9}", "\u{1F9FD}", "\u{6D17}\u{3046}",
                        "e\u{301}", "\"quoted\"", "back\\slash", "a/b", "tab\there", "line\nbreak", "\u{1}", "\u{7F}",
                        "\u{2028}", "\u{FEFF}", "  ", ""]
    static let enumValues: [String: [String]] = [
        "kind": TaskKind.allCases.map(\.rawValue) + ["chore", "OneOff"],
        "effort": Effort.allCases.map(\.rawValue) + ["medium"],
        "anchor": TimeHint.Anchor.allCases.map(\.rawValue) + ["someday"],
        "daypart": Daypart.allCases.map(\.rawValue) + ["noon"],
        "weekday": Weekday.allCases.map(\.rawValue) + ["Mon"],
        "season": TimeHint.Season.allCases.map(\.rawValue) + ["fall"],
        "repeatUnit": TimeHint.RepeatUnit.allCases.map(\.rawValue) + ["fortnight"],
    ]
    /// Number spellings whose `Double` reading is exact, so the oracle's Double rule and the exact rule agree.
    static let numbers = ["0", "1", "2", "3", "7", "12", "-1", "366", "3.0", "0.3e1", "30e-1", "3E0", "1.5", "2.25",
                          "-0.5", "1e30", "9223372036854775808", "-0", "1E+1"]

    mutating func chance(_ percent: Int) -> Bool { Int.random(in: 0..<100, using: &rng) < percent }
    mutating func pick<T>(_ list: [T]) -> T { list[Int.random(in: 0..<list.count, using: &rng)] }

    mutating func space() -> String {
        chance(60) ? "" : (0..<Int.random(in: 1...3, using: &rng)).map { _ in pick([" ", "\n", "\t", "\r"]) }.joined()
    }

    mutating func string(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += chance(50) ? "\\/" : "/"
            case "\n": out += chance(50) ? "\\n" : "\\u000a"
            case "\t": out += chance(50) ? "\\t" : "\\u0009"
            default:
                if scalar.value < 0x20 || (scalar.value >= 0x7F && chance(40)) {
                    out += escape(scalar)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    mutating func escape(_ scalar: Unicode.Scalar) -> String {
        let upper = chance(50)
        func hex(_ unit: UInt16) -> String {
            let digits = String(unit, radix: 16)
            let padded = String(repeating: "0", count: 4 - digits.count) + digits
            return "\\u" + (upper ? padded.uppercased() : padded)
        }
        return String(scalar).utf16.map(hex).joined()
    }

    mutating func text() -> String {
        (0..<Int.random(in: 1...4, using: &rng)).map { _ in pick(Self.words) }.joined(separator: " ")
    }

    /// Any JSON value (for unknown keys, wrong types and non-object items).
    mutating func anyValue(depth: Int = 0) -> String {
        switch Int.random(in: 0...(depth > 2 ? 3 : 5), using: &rng) {
        case 0: return "null"
        case 1: return pick(["true", "false"])
        case 2: return pick(Self.numbers)
        case 3: return string(text())
        case 4:
            return "[" + (0..<Int.random(in: 0...3, using: &rng)).map { _ in space() + anyValue(depth: depth + 1) }
                .joined(separator: ",") + space() + "]"
        default:
            let keys = ["title", "items", "x", "kind", "n"].shuffled(using: &rng).prefix(Int.random(in: 0...3, using: &rng))
            return object(keys.map { ($0, anyValue(depth: depth + 1)) })
        }
    }

    mutating func object(_ members: [(String, String)]) -> String {
        "{" + space() + members.map { string($0.0) + space() + ":" + space() + $0.1 + space() }.joined(separator: ","
            + space()) + "}"
    }

    /// A field value: usually the right type, sometimes null or a wrong type; enum fields sometimes unknown.
    mutating func field(_ kind: String) -> String? {
        if chance(12) { return nil }
        if chance(6) { return "null" }
        if chance(6) { return anyValue(depth: 2) }
        switch kind {
        case "text": return string(text())
        case "bool": return pick(["true", "false"])
        case "number": return pick(Self.numbers)
        default: return string(pick(Self.enumValues[kind] ?? ["x"]))
        }
    }

    mutating func time() -> String {
        var members: [(String, String)] = []
        for (key, kind) in [("anchor", "anchor"), ("daypart", "daypart"), ("weekday", "weekday"), ("month", "number"),
                            ("season", "season"), ("count", "number"), ("repeatEvery", "number"),
                            ("repeatUnit", "repeatUnit")] {
            if let value = field(kind) { members.append((key, value)) }
        }
        return object(members.shuffled(using: &rng))
    }

    mutating func item() -> String {
        if chance(5) { return anyValue(depth: 2) }
        var members: [(String, String)] = []
        let fields = [("title", "text"), ("kind", "kind"), ("room", "text"), ("effort", "effort"),
                      ("isCritical", "bool"), ("isDeepClean", "bool"), ("isWeatherDependent", "bool"),
                      ("sourcePhrase", "text"), ("sameAsItem", "number"), ("sameAsExisting", "number")]
        for (key, kind) in fields {
            if let value = field(kind) { members.append((key, value)) }
        }
        if !chance(15) { members.append(("time", chance(8) ? "null" : time())) }
        if chance(20) { members.append(("extra", anyValue())) }
        return object(members.shuffled(using: &rng))
    }

    mutating func output() -> [UInt8] {
        let items = (0..<Int.random(in: 0...5, using: &rng)).map { _ in space() + item() }
        var members = [("items", "[" + items.joined(separator: ",") + space() + "]")]
        if chance(20) { members.append(("note", anyValue())) }
        if chance(3) { members = [("other", anyValue())] }
        return Array((space() + object(members.shuffled(using: &rng)) + space()).utf8)
    }
}

extension ItemSnapshot {
    /// True when every field this snapshot has equals the same field of `final` (the reader shows only finished
    /// values, so a field never changes once it is there).
    func isEarlierState(of final: ItemSnapshot) -> Bool {
        func same<T: Equatable>(_ a: T?, _ b: T?) -> Bool { a == nil || a == b }
        let timeOK: Bool
        switch (time, final.time) {
        case (nil, _): timeOK = true
        case let (t?, f?):
            timeOK = same(t.anchor, f.anchor) && same(t.daypart, f.daypart) && same(t.weekday, f.weekday)
                && same(t.month, f.month) && same(t.season, f.season) && same(t.count, f.count)
                && same(t.repeatEvery, f.repeatEvery) && same(t.repeatUnit, f.repeatUnit)
        case (_?, nil): timeOK = false
        }
        return timeOK && same(title, final.title) && same(kind, final.kind) && same(roomName, final.roomName)
            && same(effort, final.effort) && same(isCritical, final.isCritical) && same(isDeepClean, final.isDeepClean)
            && same(isWeatherDependent, final.isWeatherDependent) && same(sourcePhrase, final.sourcePhrase)
            && same(sameAsItem, final.sameAsItem) && same(sameAsExisting, final.sameAsExisting)
    }
}

@Suite("AC-M2-24 reader property: random valid outputs × random cuts = one-shot parse = JSONDecoder oracle (FR-A1)")
struct StructuredOutputReaderPropertyTests {
    typealias R = ReaderFixtures

    @Test("AC-M2-24: 3 seeds × 500 outputs; one-shot, 3 random cut sets and (every 25th) byte by byte; snapshots only grow; the draft stream (first cut set) ends with the same drafts",
          arguments: [UInt64(0x0A11_C0DE_1211), 0x0A11_C0DE_1212, 0x0A11_C0DE_1213])
    func randomOutputs(seed: UInt64) async throws {
        var corpus = OutputCorpus(rng: SplitMix64(seed: seed))
        var counts = (items: 0, titles: 0, unrecognized: 0, claims: 0, cutSets: 0)
        for index in 0..<500 {
            // Long synchronous loops would hold every cooperative-pool thread and starve the time-limited
            // cancellation tests (DraftStreamTests) that run in parallel; yield once per output.
            await Task.yield()
            let bytes = corpus.output()
            let context = "seed \(seed) output \(index): \(String(decoding: bytes, as: UTF8.self))"
            let oracleValue = try #require(OracleJSON.decode(bytes), "the oracle reads it: \(context)")
            let expected = ReaderOracle.snapshot(oracleValue)
            let oneShot = try StructuredOutputReader.parse(String(decoding: bytes, as: UTF8.self))
            #expect(oneShot == expected, "\(context)")

            var cutSets: [[Int]] = []
            for _ in 0..<3 {
                cutSets.append((0..<Int.random(in: 1...12, using: &corpus.rng))
                    .map { _ in Int.random(in: 0...bytes.count, using: &corpus.rng) }.sorted())
            }
            if index % 25 == 0 { cutSets.append(Array(0...bytes.count)) }
            for (setIndex, cuts) in cutSets.enumerated() {
                counts.cutSets += 1
                let read = R.read(bytes, cuts: cuts)
                let final = try read.final.get()
                #expect(final == expected, "cuts \(cuts) \(context)")
                var previousCount = 0
                for step in read.steps {
                    #expect(step.items.count >= previousCount, "items only grow: \(context)")
                    previousCount = step.items.count
                    for (earlier, last) in zip(step.items, final.items) {
                        #expect(earlier.isEarlierState(of: last), "cuts \(cuts) \(context)")
                    }
                }
                guard setIndex == 0 else { continue }  // the draft-stream check: one cut set per output
                let incremental = read.steps.map { ScriptStep.snapshot($0.items) } + [.finish]
                var summary = DraftStreamSummary()
                for event in StreamFixtures.assemble(incremental, route: .cloud(.openAI)) { summary.apply(event) }
                var oneShotSummary = DraftStreamSummary()
                for event in StreamFixtures.assemble([.snapshot(expected.items), .finish], route: .cloud(.openAI)) {
                    oneShotSummary.apply(event)
                }
                #expect(summary.drafts == oneShotSummary.drafts, "drafts: \(context)")
            }
            counts.items += expected.items.count
            counts.titles += expected.items.filter { $0.title != nil }.count
            counts.unrecognized += expected.items.filter {
                if case .unrecognized? = $0.kind { true } else if case .unrecognized? = $0.time?.anchor { true } else { false }
            }.count
            counts.claims += expected.items.filter { $0.sameAsItem != nil || $0.sameAsExisting != nil }.count
        }
        print("AC-M2-24 reader property: seed \(String(seed, radix: 16)), 500 outputs, \(counts)")
        #expect(counts.items > 800 && counts.titles > 500 && counts.unrecognized > 50 && counts.claims > 300,
                "coverage seed \(seed): \(counts)")
    }

    @Test("AC-M2-24: 3 seeds × 400 mutated outputs never crash; the reader accepts exactly when JSONDecoder does, and then agrees",
          arguments: [UInt64(0x0A11_C0DE_1221), 0x0A11_C0DE_1222, 0x0A11_C0DE_1223])
    func mutatedOutputs(seed: UInt64) async {
        var corpus = OutputCorpus(rng: SplitMix64(seed: seed))
        var accepted = 0
        var rejected = 0
        var allowed = 0
        let alphabet = Array("{}[]\":,\\ 0-.eEtrufalsn1u".utf8) + [0x00, 0x0A, 0xC3, 0xA9, 0xFF, 0xED, 0xA0]
        for index in 0..<400 {
            await Task.yield()
            var bytes = corpus.output()
            for _ in 0..<Int.random(in: 1...3, using: &corpus.rng) where !bytes.isEmpty {
                let at = Int.random(in: 0..<bytes.count, using: &corpus.rng)
                switch Int.random(in: 0...2, using: &corpus.rng) {
                case 0: bytes.remove(at: at)
                case 1: bytes.insert(corpus.pick(alphabet), at: at)
                default: bytes[at] = corpus.pick(alphabet)
                }
            }
            let context = "seed \(seed) mutant \(index): \(bytes)"
            let cuts = (0..<Int.random(in: 0...6, using: &corpus.rng))
                .map { _ in Int.random(in: 0...bytes.count, using: &corpus.rng) }.sorted()
            let read = R.read(bytes, cuts: cuts)
            let oneShot = R.read(bytes).final
            #expect(read.final == oneShot, "\(context)")
            let oracle = OracleJSON.decode(bytes)
            switch (read.final, oracle) {
            case let (.success(snapshot), oracle?):
                accepted += 1
                #expect(snapshot == ReaderOracle.snapshot(oracle), "\(context)")
            case (.failure, nil):
                rejected += 1
            case let (.failure(error), oracle?):
                // The oracle's two leniencies (`OracleJSON`, J4): duplicate names and a trailing comma.
                allowed += 1
                #expect(error.isDuplicateKey || error.isTrailingComma(in: bytes),
                        "the reader rejects what the oracle reads: \(error) \(oracle) \(context)")
            case let (.success(snapshot), nil):
                // The oracle rejects numbers beyond Double's range, which RFC 8259 allows (J4).
                allowed += 1
                #expect(OracleJSON.hasNumberBeyondDouble(bytes),
                        "the reader reads what the oracle rejects: \(snapshot) \(context)")
            }
        }
        print("AC-M2-24 reader mutants: seed \(String(seed, radix: 16)), accepted \(accepted), rejected \(rejected), "
              + "oracle leniencies \(allowed)")
        #expect(accepted > 20 && rejected > 200 && allowed < 20,
                "coverage seed \(seed): accepted \(accepted), rejected \(rejected), oracle leniencies \(allowed)")
    }
}

extension PartialJSONError {
    var isDuplicateKey: Bool {
        if case .invalid(.duplicateKey, _) = self { return true }
        return false
    }

    func isTrailingComma(in bytes: [UInt8]) -> Bool {
        if case let .invalid(.unexpectedByte, offset) = self { return OracleJSON.isTrailingComma(bytes, at: offset) }
        return false
    }
}
