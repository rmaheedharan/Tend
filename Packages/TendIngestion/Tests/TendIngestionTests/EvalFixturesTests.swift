// The fixture formats the scorer and harness read (AC-M2-14 "Fixtures"; brief "Eval scoring rules": fixed UUIDs, stable
// keys, match groups "already keyword-folded", golden `expect` and room forms). The content is the Tester's (WI-M2-16).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-15 eval fixture formats (AC-M2-14)")
struct EvalFixturesTests {

    @Test("the self-test fixtures read with every field; the household is an M1 household with the fixed IDs")
    func reads() throws {
        let f = try EvalSelfTest.fixtures()
        #expect(f.inputs.map(\.id) == ["in01", "in02", "in03", "in04", "in05", "in06", "in07"])
        #expect(f.inputs[1].mode == .voice && f.inputNumber(of: "in05") == 5 && f.inputNumber(of: "x") == nil)
        #expect(f.rooms.map(\.key) == ["kitchen", "bathroom", "hallway"])
        let bins = try #require(f.tasks.first { $0.key == "t-bins" })
        #expect(bins.isCompleted && bins.task.recurrenceIntervalDays == 7)
        #expect(bins.task.completedAt == EvalInstant(text: "2026-11-20T09:00:00.000Z")?.date)
        let pods = try #require(f.tasks.first { $0.key == "t-pods" })
        #expect(pods.task.roomID == f.rooms[0].id && pods.matchGroups == [["dishwasher", "dish"], ["pods", "tablets"]])
        #expect(f.golden.count == 16 && f.golden[2].room == .new(name: "Balcony", alternates: ["terrace", "deck"]))
        #expect(f.golden[0].expect == .existing(seededKey: "t-ac") && f.golden[2].expect == .create)
        #expect(f.household.tasks.count == 6 && f.household.rooms.count == 3)
        #expect(f.taskKeys[pods.task.id] == "t-pods" && f.roomKeys[f.rooms[1].id] == "bathroom")
    }

    static func golden(_ items: String) -> Data { Data(#"{"schemaVersion":1,"items":[\#(items)]}"#.utf8) }
    static let item = #"{"inputID":"in01","key":"gx","matchGroups":[["oven"]],"kind":"oneOff","room":{"type":"none"},"effort":"low","isCritical":false,"isDeepClean":false,"isWeatherDependent":false,"expect":{"type":"create"}}"#

    static func readGolden(_ text: String) throws -> EvalFixtures {
        try EvalFixtures(inputs: try EvalSelfTest.selfTest("inputs.json"),
                         household: try EvalSelfTest.selfTest("household.json"), golden: golden(text))
    }

    @Test("a well-formed golden item reads; unused members are ignored")
    func goldenReads() throws {
        let f = try Self.readGolden(Self.item.replacingOccurrences(of: #""key":"gx""#, with: #""key":"gx","note":"x""#))
        #expect(f.golden.map(\.key) == ["gx"])
    }

    @Test("golden-file errors are typed", arguments: [
        (#""matchGroups":[["oven"]]"#, #""matchGroups":[["Oven"]]"#, "tokenNotKeyword"),
        (#""matchGroups":[["oven"]]"#, #""matchGroups":[["the"]]"#, "tokenNotKeyword"),
        (#""matchGroups":[["oven"]]"#, #""matchGroups":[["dish pods"]]"#, "tokenNotKeyword"),
        (#""matchGroups":[["oven"]]"#, #""matchGroups":[]"#, "emptyMatchGroups"),
        (#""matchGroups":[["oven"]]"#, #""matchGroups":[[]]"#, "emptyMatchGroups"),
        (#""inputID":"in01""#, #""inputID":"in99""#, "unknownReference"),
        (#""key":"gx""#, #""key":"t-ac""#, "keyRepeated"),
        (#""expect":{"type":"create"}"#, #""expect":{"type":"existing","seededKey":"t-nope"}"#, "unknownReference"),
        (#""room":{"type":"none"}"#, #""room":{"type":"existing","roomKey":"attic"}"#, "unknownReference"),
        (#""room":{"type":"none"}"#, #""room":{"type":"elsewhere"}"#, "unknownValue"),
        (#""kind":"oneOff""#, #""kind":"chore""#, "unknownValue"),
        (#""effort":"low""#, #""effort":1"#, "wrongType"),
        (#","isCritical":false"#, "", "missingMember"),
    ])
    func goldenErrors(find: String, replace: String, kind: String) {
        do {
            _ = try Self.readGolden(Self.item.replacingOccurrences(of: find, with: replace))
            Issue.record("accepted: \(replace)")
        } catch {
            #expect(String(describing: error).hasPrefix(kind), "\(error)")
        }
    }

    @Test("household and inputs errors are typed: version, repeated key and ID, invalid seeded task")
    func otherErrors() throws {
        let household = String(decoding: try EvalSelfTest.selfTest("household.json"), as: UTF8.self)
        let inputs = try EvalSelfTest.selfTest("inputs.json")
        let golden = try EvalSelfTest.selfTest("golden.json")
        func read(_ h: String, _ i: Data? = nil) throws -> EvalFixtures {
            try EvalFixtures(inputs: i ?? inputs, household: Data(h.utf8), golden: golden)
        }
        #expect(throws: EvalFixtureError.unsupportedVersion(file: "household.json")) {
            try read(household.replacingOccurrences(of: #""schemaVersion": 1"#, with: #""schemaVersion": 2"#))
        }
        #expect(throws: EvalFixtureError.keyRepeated(file: "household.json", key: "kitchen")) {
            try read(household.replacingOccurrences(of: #""key": "bathroom""#, with: #""key": "kitchen""#))
        }
        #expect(throws: EvalFixtureError.idRepeated(file: "household.json", id: "5E1F0000-0000-4000-8000-000000000001")) {
            try read(household.replacingOccurrences(of: "5E1F0000-0000-4000-8000-000000000011",
                                                    with: "5E1F0000-0000-4000-8000-000000000001"))
        }
        #expect(throws: EvalFixtureError.invalidSeededTask(file: "household.json", key: "t-bins",
                                                          .intervalBelowOneDay)) {
            try read(household.replacingOccurrences(of: #""recurrenceIntervalDays": 7"#,
                                                    with: #""recurrenceIntervalDays": 0"#))
        }
        #expect(throws: EvalFixtureError.keyRepeated(file: "inputs.json", key: "in01")) {
            try read(household, Data(String(decoding: inputs, as: UTF8.self)
                .replacingOccurrences(of: #""id": "in02""#, with: #""id": "in01""#).utf8))
        }
        #expect(throws: EvalFixtureError.self) { try read("{") }
    }
}
