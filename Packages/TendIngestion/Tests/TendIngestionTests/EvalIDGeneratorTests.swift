// The eval harness ID generator (AC-M2-28 "deterministic (T-29) … never yields a fixture UUID"; plan "Eval harness ID
// generator"). AC-M2-06 (commit skips IDs in use). Expected bytes are written out by hand from the plan's table.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("WI-M2-15 EvalIDGenerator (AC-M2-28, T-29)")
struct EvalIDGeneratorTests {

    @Test("the bytes follow the plan's table: TEVL, input number, version 8 + attempt, variant, n")
    func bytes() throws {
        var generator = try #require(EvalIDGenerator(inputNumber: 20, attempt: 2))
        #expect(generator.next().uuidString == "5445564C-0014-8200-8000-000000000001")
        #expect(generator.next().uuidString == "5445564C-0014-8200-8000-000000000002")
        let wide = try #require(EvalIDGenerator(inputNumber: 0x1234, attempt: 15))
        #expect(wide.id(number: 0x00AB_CDEF_0123_4567).uuidString == "5445564C-1234-8F00-80AB-CDEF01234567")
    }

    @Test("deterministic: the same input and attempt give the same IDs; another input or attempt gives others")
    func deterministic() throws {
        func ids(_ i: Int, _ a: Int) throws -> [UUID] {
            var g = try #require(EvalIDGenerator(inputNumber: i, attempt: a))
            return (0..<50).map { _ in g.next() }
        }
        #expect(try ids(3, 1) == ids(3, 1))
        #expect(Set(try ids(3, 1)).isDisjoint(with: Set(try ids(3, 2))))
        #expect(Set(try ids(3, 1)).isDisjoint(with: Set(try ids(4, 1))))
        #expect(Set(try ids(3, 1)).count == 50)
    }

    @Test("never a version-4 UUID, so never a fixture ID (every fixture UUID is version 4)")
    func neverVersion4() throws {
        for i in [1, 2, 19, 20, 65_535] {
            for a in 1...15 {
                var g = try #require(EvalIDGenerator(inputNumber: i, attempt: a))
                for _ in 0..<20 {
                    let uuid = g.next().uuid
                    #expect(uuid.6 >> 4 == 8)
                    #expect(uuid.8 & 0xC0 == 0x80)
                }
            }
        }
    }

    @Test("the input number and attempt must be in the plan's ranges", arguments: [(0, 1), (65_536, 1), (1, 0), (1, 16), (-1, 1)])
    func ranges(input: Int, attempt: Int) {
        #expect(EvalIDGenerator(inputNumber: input, attempt: attempt) == nil)
    }

    @Test("it plugs into commit through the public API: new tasks get the generator's IDs in order (AC-M2-06)")
    func commitUsesIt() throws {
        let start = Date(timeIntervalSince1970: 1_795_341_600)
        let draft = IngestionDraft(
            draftID: 1, title: "Clean the oven", kind: .oneOff, room: .proposed("Garage"), effort: .normal,
            isCritical: false, isDeepClean: false, isWeatherDependent: false, allowedDayparts: [.morning],
            allowedWeekdays: [.monday], windowStart: start, windowEnd: start.addingTimeInterval(3600),
            recurrenceIntervalDays: nil, sourcePhrase: nil
        )
        var generator = try #require(EvalIDGenerator(inputNumber: 1, attempt: 1))
        let plan = try DraftCommit.plan(confirmed: [draft], parsedWith: Household(tasks: [], rooms: []),
                                        household: Household(tasks: [], rooms: []), ids: &generator)
        // The room is needed first (it is created before the task), so it takes n = 1 and the task n = 2.
        #expect(plan.newRooms.map(\.id.uuidString) == ["5445564C-0001-8100-8000-000000000001"])
        #expect(plan.newTasks.map(\.id.uuidString) == ["5445564C-0001-8100-8000-000000000002"])
    }
}
