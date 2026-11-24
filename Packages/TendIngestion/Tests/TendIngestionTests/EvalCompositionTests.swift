// WI-M2-16 composition check on the real eval fixtures (AC-M2-14; brief rubric Q3 "Composition", "Eval scoring rules";
// plan "Eval harness ID generator"; PO `po-m2-wi16.md` rulings 1–9 and F3). The checker is `EvalCompositionCheck`
// (EvalCompositionSupport.swift). Each rule passes on `Fixtures/M2/eval` as committed, and each has at least one negative
// control: a mutated in-memory copy that the rule must refuse. Nothing here writes a fixture file.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// One negative control: a mutation of the real fixtures and the violation it must produce.
struct CompositionControl: Sendable, CustomTestStringConvertible {
    var name: String
    var rule: String
    var kind: CompositionViolation.Kind
    var detail: String?
    var mutate: @Sendable (inout EvalJSONRoots) -> Void

    init(_ name: String, _ rule: String, _ kind: CompositionViolation.Kind = .rule, detail: String? = nil,
         _ mutate: @escaping @Sendable (inout EvalJSONRoots) -> Void) {
        self.name = name
        self.rule = rule
        self.kind = kind
        self.detail = detail
        self.mutate = mutate
    }

    var testDescription: String { "\(rule) \(kind.rawValue): \(name)" }
}

@Suite("WI-M2-16 composition check on the real eval fixtures (AC-M2-14, rubric Q3)")
struct EvalCompositionTests {

    static let rules = ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12", "TAG", "HH", "SUB",
                        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "READ"]

    static func realViolations() throws -> [CompositionViolation] {
        EvalCompositionCheck.violations(try EvalFixtureFiles.set())
    }

    @Test("AC-M2-14: Fixtures/M2/eval as committed passes every composition rule (C1–C12, TAG, HH, SUB, F1–F9)")
    func realFixturesPass() throws {
        let violations = try Self.realViolations()
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test("AC-M2-14: each rule, threshold and tabled value, holds on the real fixtures", arguments: rules)
    func eachRule(_ rule: String) throws {
        let violations = try Self.realViolations().filter { $0.rule == rule }
        #expect(violations.isEmpty, "\(violations.map(\.description))")
    }

    @Test("AC-M2-14: the real fixtures read with the Tester's tabled shape (N = 58, 20 inputs, 9 rooms, 19 tasks)")
    func shape() throws {
        let f = try EvalFixtures(inputs: try EvalFixtureFiles.data("inputs.json"),
                                 household: try EvalFixtureFiles.data("household.json"),
                                 golden: try EvalFixtureFiles.data("golden.json"))
        #expect(f.inputs.count == 20 && f.golden.count == 58 && f.rooms.count == 9 && f.tasks.count == 19)
        #expect(f.golden.filter { $0.expect == .create }.count == 41)
    }

    @Test("AC-M2-28 + plan ID generator: no EvalIDGenerator ID (version 8) can equal a fixture ID (version 4)")
    func generatorNeverYieldsFixtureID() throws {
        let f = try EvalFixtures(inputs: try EvalFixtureFiles.data("inputs.json"),
                                 household: try EvalFixtureFiles.data("household.json"),
                                 golden: try EvalFixtureFiles.data("golden.json"))
        let fixtureIDs = Set(f.rooms.map(\.id) + f.tasks.map(\.task.id))
        for input in 1...20 {
            for attempt in [1, 15] {
                let generator = try #require(EvalIDGenerator(inputNumber: input, attempt: attempt))
                for n in UInt64(1)...40 {
                    let id = generator.id(number: n)
                    #expect(id.uuid.6 >> 4 == 8 && !fixtureIDs.contains(id))
                }
            }
        }
    }

    // MARK: - Helpers for the controls

    static func dropRepeatTag(_ r: inout EvalJSONRoots, _ ids: [String]) {
        for id in ids { r.tags(id) { $0.removeAll { $0 == "repeat" } } }
    }

    static func setFlag(_ flag: String, _ value: Bool) -> @Sendable (EvalJSON) -> EvalJSON {
        { $0.setting("/" + flag, to: .bool(value)) }
    }

    // MARK: - Negative controls

    static let controls: [CompositionControl] = [
        // C1
        CompositionControl("in20 and its items removed", "C1") { r in
            r.inputs = EvalJSONRoots.filter(r.inputs, "inputs") { $0["id"] != .string("in20") }
            r.removeItems { $0["inputID"] == .string("in20") }
        },
        CompositionControl("in01 renamed in00", "C1", .pin) { r in
            r.input("in01", "/id", .string("in00"))
            r.eachItem { $0["inputID"] == .string("in01") ? $0.setting("/inputID", to: .string("in00")) : $0 }
        },
        // C2, C3
        CompositionControl("three voice inputs made text (7 voice)", "C2") { r in
            for id in ["in02", "in04", "in06"] { r.input(id, "/mode", .string("text")) }
        },
        CompositionControl("one voice input made text (9 voice, still ≥ 8)", "C2", .pin) { r in
            r.input("in17", "/mode", .string("text"))
        },
        CompositionControl("three text inputs made voice (7 text)", "C3") { r in
            for id in ["in01", "in03", "in05"] { r.input(id, "/mode", .string("voice")) }
        },
        CompositionControl("one text input made voice (9 text)", "C3", .pin) { r in r.input("in19", "/mode", .string("voice")) },
        // C4
        CompositionControl("in01 cut to 9 words", "C4", detail: "9 words") { r in
            r.input("in01", "/text", .string("The AC needs servicing, deep clean the balcony now"))
        },
        CompositionControl("in01 grown to 81 words", "C4", detail: "81 words") { r in
            r.inputText("in01", replacing: "rain", with: "rain" + String(repeating: " now", count: 57))
        },
        CompositionControl("one word added to in01 (25, within 10–80)", "C4", .pin) { r in
            r.inputText("in01", replacing: "rain", with: "rain today")
        },
        // C5
        CompositionControl("every restock item made one-off", "C5", detail: "no restock") { r in
            r.eachItem { $0["kind"] == .string("restock") ? $0.setting("/kind", to: .string("oneOff")) : $0 }
        },
        CompositionControl("every weather flag cleared", "C5", detail: "no weather-dependent") { r in
            r.eachItem(setFlag("isWeatherDependent", false))
        },
        CompositionControl("one recurring item made one-off", "C5", .pin) { r in
            r.item("g15-shower", "/kind", .string("oneOff"))
        },
        // C6
        CompositionControl("weather kept only in in01…in07 (3 inputs)", "C6", detail: "weather inputs, Q3") { r in
            let keep: Set<String> = ["in01", "in04", "in07"]
            r.eachItem { item in
                guard case let .string(id)? = item["inputID"], !keep.contains(id) else { return item }
                return item.setting("/isWeatherDependent", to: .bool(false))
            }
        },
        CompositionControl("weather cleared on g13-clothes (in13 keeps g13-leaves)", "C6", .pin) { r in
            r.item("g13-clothes", "/isWeatherDependent", .bool(false))
        },
        CompositionControl("weather tag removed from in01", "C6", .tag) { r in r.tags("in01") { $0.removeAll { $0 == "weather" } } },
        // C7
        CompositionControl("critical kept only in in02, in05", "C7", detail: "critical inputs, Q3") { r in
            r.eachItem { item in
                guard case let .string(id)? = item["inputID"], id != "in02", id != "in05" else { return item }
                return item.setting("/isCritical", to: .bool(false))
            }
        },
        CompositionControl("critical cleared on g18-soup (in18 keeps the tax)", "C7", .pin) { r in
            r.item("g18-soup", "/isCritical", .bool(false))
        },
        CompositionControl("critical tag added to in01", "C7", .tag) { r in r.tags("in01") { $0.append("critical") } },
        // C8
        CompositionControl("deep clean kept only in in01, in05", "C8", detail: "deep-clean inputs, Q3") { r in
            r.eachItem { item in
                guard case let .string(id)? = item["inputID"], id != "in01", id != "in05" else { return item }
                return item.setting("/isDeepClean", to: .bool(false))
            }
        },
        CompositionControl("deep clean cleared on g05-grout (in05 keeps the oven)", "C8", .pin) { r in
            r.item("g05-grout", "/isDeepClean", .bool(false))
        },
        CompositionControl("deepClean tag removed from in19", "C8", .tag) { r in r.tags("in19") { $0.removeAll { $0 == "deepClean" } } },
        // C9
        CompositionControl("every existing item made create", "C9", detail: "existing-task inputs, Q3") { r in
            r.eachItem { $0.setting("/expect", to: .object([.init("type", .string("create"))])) }
        },
        CompositionControl("g17-pods made create (in17 keeps the cat food)", "C9", .pin) { r in
            r.item("g17-pods", "/expect", .object([.init("type", .string("create"))]))
        },
        CompositionControl("existingTask tag removed from in19", "C9", .tag) { r in
            r.tags("in19") { $0.removeAll { $0 == "existingTask" } }
        },
        // C10
        CompositionControl("repeat tag removed from in03 and in06 (2 inputs)", "C10", detail: "repeat inputs, Q3") { r in
            dropRepeatTag(&r, ["in03", "in06"])
        },
        CompositionControl("repeat tag removed from in18 (3, still ≥ 3)", "C10", .pin) { r in dropRepeatTag(&r, ["in18"]) },
        CompositionControl("in03's second \"milk\" becomes \"bread\"", "C10", .tag) { r in
            r.inputText("in03", replacing: "forget the milk", with: "forget the bread")
        },
        // C11
        CompositionControl("filler tag kept on 3 inputs", "C11", detail: "filler/self-correction inputs, Q3") { r in
            for id in ["in02", "in04", "in06", "in08", "in10", "in12", "in14"] {
                r.tags(id) { $0.removeAll { $0 == "fillerOrCorrection" } }
            }
        },
        CompositionControl("filler tag removed from in17 (9, still ≥ 4)", "C11", .pin) { r in
            r.tags("in17") { $0.removeAll { $0 == "fillerOrCorrection" } }
        },
        CompositionControl("in04 loses its \"uh\" but keeps the tag", "C11", .tag) { r in
            r.inputText("in04", replacing: "So, uh, the gutters", with: "So, the gutters")
        },
        CompositionControl("in20 loses its self-correction", "C11", .pin, detail: "self-corrections") { r in
            r.inputText("in20", replacing: "the bedroom windows, no, ", with: "")
        },
        // C12
        CompositionControl("in05's items removed", "C12", detail: "in05 has no golden item") { r in
            r.removeItems { $0["inputID"] == .string("in05") }
        },
        CompositionControl("nine third items removed (N = 49)", "C12", detail: "N = 49") { r in
            let drop: Set<String> = ["g01-balcony", "g02-sink", "g04-trashbags", "g05-grout", "g06-washer", "g07-shed",
                                     "g08-card", "g09-vacuum", "g10-heater"]
            r.removeItems { if case let .string(key)? = $0["key"] { drop.contains(key) } else { false } }
        },
        CompositionControl("one item removed (N = 57)", "C12", .pin) { r in r.removeItems { $0["key"] == .string("g20-books") } },
        // TAG
        CompositionControl("unknown tag", "TAG", detail: "unknown tag") { r in r.tags("in02") { $0.append("spicy") } },
        CompositionControl("newRoom tag on an input with no new room", "TAG", .tag) { r in r.tags("in02") { $0.append("newRoom") } },
        CompositionControl("completedTaskSaidAgain tag on in02", "TAG", .tag) { r in
            r.tags("in02") { $0.append("completedTaskSaidAgain") }
        },
        // HH
        CompositionControl("t-oven made active (no maintenance target left)", "HH", .pin) { r in r.task("t-oven", "/state", .string("active")) },
        // SUB
        CompositionControl("in10 (AC-M2-11 voice) made text", "SUB", .pin) { r in r.input("in10", "/mode", .string("text")) },
        // F1
        CompositionControl("a room ID made version 8", "F1") { r in
            r.room("kitchen", "/id", .string("E7A1C0DE-0000-8000-8000-000000000101"))
        },
        CompositionControl("a task ID with a non-RFC variant", "F1") { r in
            r.task("t-pods", "/id", .string("E7A1C0DE-0000-4000-0000-000000000201"))
        },
        // F2
        CompositionControl("\"1650\" in a note (a digit run holding 650)", "F2") { r in
            r.household = r.household.setting("/note", to: .string("kept since 1650"))
        },
        CompositionControl("\"0700\" in an input's ignored member", "F2") { r in r.input("in01", "/q6Rows", .string("0700")) },
        // F3
        CompositionControl("\"late\" in the golden note", "F3") { r in
            r.golden = r.golden.setting("/note", to: .string("running late"))
        },
        CompositionControl("\"Overdue\" in a seeded title", "F3") { r in r.task("t-kettle", "/title", .string("Overdue kettle")) },
        // F4
        CompositionControl("a match-group token that is a stop word", "F4") { r in
            r.item("g01-ac", "/matchGroups", .array([.array([.string("the")])]))
        },
        CompositionControl("a match-group token not folded", "F4") { r in
            r.task("t-oven", "/matchGroups", .array([.array([.string("Oven")])]))
        },
        // F5
        CompositionControl("referencePhrase not words of the input", "F5", detail: "not words of") { r in
            r.item("g01-ac", "/referencePhrase", .string("The boiler needs servicing"))
        },
        CompositionControl("referencePhrase missing", "F5", detail: "no referencePhrase") { r in
            r.item("g01-ac", "/referencePhrase", nil)
        },
        CompositionControl("create item's phrase points at another item", "F5", detail: "g04-trashbags: best target") { r in
            r.item("g04-trashbags", "/referencePhrase", .string("mow the back garden"))
        },
        CompositionControl("existing item's phrase points at a create item", "F5", detail: "g01-pods: best target") { r in
            r.item("g01-pods", "/referencePhrase", .string("The AC needs servicing"))
        },
        // F6
        CompositionControl("t-pods retitled so no input names it", "F6", detail: "not on in01's duplicate shortlist") { r in
            r.task("t-pods", "/title", .string("Buy soap"))
        },
        CompositionControl("an existing item aimed at a completed task", "F6", detail: "is completed") { r in
            r.item("g03-milk", "/expect", .object([.init("type", .string("existing")), .init("seededKey", .string("t-milk"))]))
        },
        CompositionControl("a seeded title the word-match floor merges a create item into", "F6",
                           detail: "g16-carservice: the local word-match floor") { r in
            r.task("t-car", "/title", .string("Book the car service"))
        },
        CompositionControl("every seeded title says milk (shortlist reaches the cap)", "F6", detail: "cap of 10") { r in
            r.eachTask { task in
                guard case let .string(title)? = task["title"] else { return task }
                return task.setting("/title", to: .string(title + " milk"))
            }
        },
        // F7
        CompositionControl("an existing item's effort differs from its task", "F7") { r in
            r.item("g01-pods", "/effort", .string("normal"))
        },
        // F8
        CompositionControl("existing room not named in the input", "F8", detail: "is not named") { r in
            r.item("g02-sink", "/room", .object([.init("type", .string("existing")), .init("roomKey", .string("garage"))]))
        },
        CompositionControl("new room that is an existing room", "F8", detail: "is an existing room") { r in
            r.item("g01-balcony", "/room", .object([.init("type", .string("new")), .init("name", .string("kitchen")),
                                                     .init("alternates", .array([]))]))
        },
        CompositionControl("new room renamed (still named in the input)", "F8", .pin) { r in
            r.item("g07-shed", "/room", .object([.init("type", .string("new")), .init("name", .string("Patio")),
                                                 .init("alternates", .array([]))]))
        },
        // F9
        CompositionControl("a deep clean with normal effort", "F9", detail: "high effort") { r in
            r.item("g01-balcony", "/effort", .string("normal"))
        },
        CompositionControl("weather flag on a chore with no weather words", "F9", detail: "ties it to no weather") { r in
            r.item("g01-ac", "/isWeatherDependent", .bool(true))
        },
        CompositionControl("deep-clean flag without \"deep\"", "F9", detail: "deep clean true") { r in
            r.item("g01-ac", "/isDeepClean", .bool(true))
        },
        // READ
        CompositionControl("golden item aimed at an unknown task", "READ") { r in
            r.item("g01-pods", "/expect", .object([.init("type", .string("existing")), .init("seededKey", .string("t-none"))]))
        },
    ]

    @Test("AC-M2-14: every rule refuses its mutated copy (negative controls)", arguments: controls)
    func negativeControl(_ control: CompositionControl) throws {
        let mutated = try EvalFixtureFiles.set().mutated(control.mutate)
        let violations = EvalCompositionCheck.violations(mutated)
        let hit = violations.contains {
            $0.rule == control.rule && $0.kind == control.kind && (control.detail.map($0.detail.contains) ?? true)
        }
        let got = violations.map(\.description).joined(separator: "\n")
        #expect(hit, "expected \(control.rule) [\(control.kind.rawValue)] \(control.detail ?? ""), got:\n\(got)")
    }

    @Test("AC-M2-14: every rule has at least one negative control")
    func everyRuleHasAControl() {
        #expect(Set(Self.controls.map(\.rule)) == Set(Self.rules))
    }

    @Test("AC-M2-14: an unmutated canonical round trip passes (the controls' writer adds no violation)")
    func identityMutationPasses() throws {
        let copy = try EvalFixtureFiles.set().mutated { _ in }
        let violations = EvalCompositionCheck.violations(copy)
        #expect(violations.isEmpty, "\(violations.map(\.description))")
    }

    @Test("N-3: the digit-run rule reads substrings: 1650 and 0700 hold a sentinel; 2026, 0599 and 730 do not")
    func digitRuns() {
        #expect(EvalCompositionCheck.digitRunsHolding600to729("a 1650 b 0700") == ["1650", "0700"])
        #expect(EvalCompositionCheck.digitRunsHolding600to729("2026-11-30T14:00:00.000Z 0599 730 000000000201").isEmpty)
        #expect(EvalCompositionCheck.digitRunsHolding600to729("729") == ["729"])
    }

    @Test("UX-3: the banned-token rule is whole-token: \"plate\" and \"behindhand\" pass, \"late\" does not")
    func bannedWholeToken() throws {
        let copy = try EvalFixtureFiles.set().mutated { r in
            r.golden = r.golden.setting("/note", to: .string("plate behindhand"))
        }
        #expect(!EvalCompositionCheck.violations(copy).contains { $0.rule == "F3" })
    }
}
