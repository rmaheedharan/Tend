import Foundation
import FoundationModels
import TendCore
import TendIngestion

let kitchen = Room(id: UUID(), name: "Kitchen")
let now = Date()
let pods = try HouseholdTask(id: UUID(), title: "Buy dishwasher pods", kind: .restock, roomID: kitchen.id, effort: .low,
                             windowStart: now, windowEnd: now.addingTimeInterval(86400 * 7))
let household = Household(tasks: [pods], rooms: [kitchen, Room(id: UUID(), name: "Living room")])
let prompt = #"{"capture":"We're almost out of dishwasher pods, the AC needs servicing before summer, and mop the kitchen floor tonight.","rooms":["Kitchen","Living room"]}"#

func run(_ label: String, tools: Bool) async throws {
    for r in 1...3 {
        let recorder = DuplicateLookupRecorder(household: household)
        let session = LanguageModelSession(model: .default, tools: tools ? [DuplicateLookupTool(recorder: recorder)] : [],
                                           instructions: OnDeviceInstructions.text)
        session.prewarm()
        try await Task.sleep(for: .seconds(1))
        let clock = ContinuousClock(); let start = clock.now
        var firstSnap: Duration?; var firstItem: Duration?
        for try await s in session.streamResponse(to: prompt, generating: OnDeviceOutput.self,
                                                  options: GenerationOptions(samplingMode: .greedy)) {
            if firstSnap == nil { firstSnap = start.duration(to: clock.now) }
            if firstItem == nil, (s.content.items?.count ?? 0) >= 2 || s.content.items?.first?.isWeatherDependent != nil {
                firstItem = start.duration(to: clock.now)
            }
        }
        print(label, r, "firstSnapshot", firstSnap!, "firstItemComplete", firstItem ?? .zero, "total", start.duration(to: clock.now), "queries", await recorder.queries)
    }
}
try await run("tool", tools: true)
try await run("noTool", tools: false)
