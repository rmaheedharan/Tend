// The on-device duplicate `Tool` conformance (WI-M2-M2; AC-M2-07 Mac half: "The `Tool` returns exactly the duplicate
// shortlist for its query: at most 10 entries, only from the local household, and only title, kind and room name for
// each"). P-1, P-2.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

enum LookupHouseholds {
    static func task(_ n: UInt8, _ title: String, kind: TaskKind = .oneOff, room: UUID? = nil,
                     state: TaskState = .active) throws -> HouseholdTask {
        let start = OnDeviceFixtures.now
        return try HouseholdTask(id: OnDeviceFixtures.uuid(n), title: title, kind: kind, roomID: room,
                                 effort: .normal, windowStart: start, windowEnd: start.addingTimeInterval(86_400),
                                 recurrenceIntervalDays: kind == .recurring ? 7 : nil, state: state,
                                 completedAt: state == .completed ? start : nil)
    }

    /// Fourteen pod tasks (more than 10 match "pods"), a completed one, a room-only match and others.
    static func big() throws -> Household {
        let kitchen = OnDeviceFixtures.room("Kitchen", 200)
        let garage = OnDeviceFixtures.room("Garage", 201)
        var tasks: [HouseholdTask] = []
        for n in 1...14 {
            tasks.append(try task(UInt8(n), "Buy pods \(n)", kind: n.isMultiple(of: 3) ? .restock : .oneOff,
                                  room: n.isMultiple(of: 2) ? kitchen.id : nil))
        }
        tasks.append(try task(40, "Order dishwasher pods", kind: .restock, state: .completed))
        tasks.append(try task(41, "Sweep", room: garage.id))
        tasks.append(try task(42, "Water the plants", kind: .recurring))
        return Household(tasks: tasks, rooms: [kitchen, garage])
    }
}

@Suite("On-device duplicate Tool (WI-M2-M2; AC-M2-07)")
struct DuplicateLookupToolTests {

    static let queries = ["pods", "dishwasher pods", "the garage", "water plants", "the and of", "", "Pods 3",
                          "sweep the garage floor"]

    @Test("AC-M2-07: the Tool returns exactly the duplicate shortlist for its query, as title, kind and room name",
          arguments: queries)
    func returnsTheShortlist(query: String) async throws {
        let household = try LookupHouseholds.big()
        let tool = DuplicateLookupTool(recorder: DuplicateLookupRecorder(household: household))
        let result = try await tool.call(arguments: .init(query: query))
        let expected = DuplicateLookup.entries(for: query, in: household)
        #expect(result.tasks.count <= 10)
        #expect(result.tasks.count == expected.count)
        for (got, want) in zip(result.tasks, expected) {
            #expect(got.title == want.title)
            #expect(got.kind.rawValue == want.kind.rawValue)
            #expect(got.room == want.roomName)
        }
        // Back to the neutral entries: equal, entry for entry, in rank order.
        let back = result.tasks.map { task in
            DuplicateLookupEntry(title: task.title, kind: TaskKind(rawValue: task.kind.rawValue) ?? .oneOff,
                                 roomName: task.room)
        }
        #expect(back == expected)
    }

    @Test("More than 10 eligible tasks give the first 10; completed tasks are left out")
    func capAndCompleted() async throws {
        let household = try LookupHouseholds.big()
        let tool = DuplicateLookupTool(recorder: DuplicateLookupRecorder(household: household))
        let pods = try await tool.call(arguments: .init(query: "pods"))
        #expect(pods.tasks.count == 10)
        #expect(!pods.tasks.contains { $0.title == "Order dishwasher pods" })
        let stopWords = try await tool.call(arguments: .init(query: "the and of"))
        #expect(stopWords.tasks.isEmpty)
    }

    @Test("Each entry holds only title, kind and room; the result holds only the entries (no ID, state or date)")
    func fieldsOnly() throws {
        let entry = OnDeviceLookupTask(title: "Sweep", kind: .oneOff, room: "Garage")
        #expect(Mirror(reflecting: entry).children.map(\.label) == ["title", "kind", "room"])
        #expect(Mirror(reflecting: OnDeviceLookupResult(tasks: [entry])).children.map(\.label) == ["tasks"])
        let schema = try JSONEncoder().encode(OnDeviceLookupTask.generationSchema)
        let object = try #require(try JSONSerialization.jsonObject(with: schema) as? [String: Any])
        #expect(Set((object["properties"] as? [String: Any])?.keys.map { $0 } ?? []) == ["title", "kind", "room"])
    }

    @Test("The Tool records each query in call order, reads only its household, and never changes it (Q7)")
    func recordsQueries() async throws {
        let household = try LookupHouseholds.big()
        let recorder = DuplicateLookupRecorder(household: household)
        let tool = DuplicateLookupTool(recorder: recorder)
        _ = try await tool.call(arguments: .init(query: "pods"))
        _ = try await tool.call(arguments: .init(query: "garage"))
        #expect(await recorder.queries == ["pods", "garage"])
        #expect(await recorder.household == household)
        // Another household's tasks never appear.
        let other = DuplicateLookupTool(recorder: DuplicateLookupRecorder(household: Household(tasks: [], rooms: [])))
        #expect(try await other.call(arguments: .init(query: "pods")).tasks.isEmpty)
    }

    @Test("The Tool's name, description and argument schema hold no household data")
    func definition() throws {
        let tool = DuplicateLookupTool(recorder: DuplicateLookupRecorder(household: try LookupHouseholds.big()))
        #expect(tool.name == "findExistingTasks")
        #expect(!tool.description.contains("pods"))
        let schema = try JSONEncoder().encode(tool.parameters)
        let object = try #require(try JSONSerialization.jsonObject(with: schema) as? [String: Any])
        #expect(Set((object["properties"] as? [String: Any])?.keys.map { $0 } ?? []) == ["query"])
    }
}
