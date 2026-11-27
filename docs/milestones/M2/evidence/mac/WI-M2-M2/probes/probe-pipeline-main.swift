import Foundation
import TendAI
import TendCore
import TendIngestion

let kitchen = Room(id: UUID(), name: "Kitchen")
let living = Room(id: UUID(), name: "Living room")
let now = Date()
let pods = try HouseholdTask(id: UUID(), title: "Buy dishwasher pods", kind: .restock, roomID: kitchen.id, effort: .low,
                             windowStart: now, windowEnd: now.addingTimeInterval(86400 * 7))
let household = Household(tasks: [pods], rooms: [kitchen, living])
let input = "We're almost out of dishwasher pods, the AC needs servicing before summer, and mop the kitchen floor tonight."
let source = FoundationModelsOnDeviceSource(locale: Locale(identifier: "en_US"))
print("availability", source.availability())
for run in 1...4 {
    await source.prewarm(household: household)
    try await Task.sleep(for: .seconds(1))
    let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: now, calendar: .current, timeZone: .current,
                                 duplicateCheck: DraftDuplicateRules.onDevice(household: household))
    let clock = ContinuousClock()
    let start = clock.now
    var ttfi: Duration?
    for await event in pipeline.events(from: .onDevice(source.model(household: household))) {
        switch event {
        case let .emitted(d):
            if ttfi == nil { ttfi = start.duration(to: clock.now) }
            print("  emitted", d.draftID, d.title, d.kind, d.room, d.effort, "crit", d.isCritical, "dup", d.duplicate,
                  "phrase", d.sourcePhrase ?? "-")
        case let .updated(d): print("  updated", d.draftID, d.title, d.duplicate)
        case let .itemSkipped(r): print("  skipped", r)
        case let .finished(o): print("  finished", o)
        }
    }
    print("run", run, "ttfi", ttfi.map { "\($0)" } ?? "-", "total", start.duration(to: clock.now))
}
