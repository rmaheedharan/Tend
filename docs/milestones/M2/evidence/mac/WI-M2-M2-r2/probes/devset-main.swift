// Developer dev set for the R-1 Tool-call change (information only; never the frozen eval). 8 captures against one
// household with 8 existing tasks. For each capture: which chores repeat an existing task (by a keyword in the draft
// title) and which are new. Counts duplicates created (a repeat left unmarked) and false merges (a new chore marked).
import Foundation
import TendAI
import TendCore
import TendIngestion

let now = Date(timeIntervalSince1970: 1_800_000_000)
let kitchen = Room(id: UUID(), name: "Kitchen"), bath = Room(id: UUID(), name: "Bathroom"),
    garden = Room(id: UUID(), name: "Garden")
func task(_ title: String, _ kind: TaskKind, _ room: Room?) throws -> HouseholdTask {
    try HouseholdTask(id: UUID(), title: title, kind: kind, roomID: room?.id, effort: .normal, windowStart: now,
                      windowEnd: now.addingTimeInterval(7 * 86_400), recurrenceIntervalDays: kind == .recurring ? 7 : nil)
}
let tasks = [try task("Buy dishwasher pods", .restock, kitchen), try task("Descale the kettle", .oneOff, kitchen),
             try task("Clean the shower glass", .recurring, bath), try task("Mow the lawn", .recurring, garden),
             try task("Pay the water bill", .oneOff, nil), try task("Replace the smoke alarm battery", .oneOff, nil),
             try task("Buy olive oil", .restock, kitchen), try task("Book the boiler service", .oneOff, nil)]
let household = Household(tasks: tasks, rooms: [kitchen, bath, garden])

/// (input, [(keyword in the draft title, expected existing title or nil)])
let cases: [(String, [(String, String?)])] = [
    ("We're nearly out of dishwasher tablets and the bin needs taking out", [("dishwasher", "Buy dishwasher pods"), ("bin", nil)]),
    ("Kettle needs descaling, also wipe the oven door", [("kettle", "Descale the kettle"), ("oven", nil)]),
    ("Mow the lawn on Saturday if it's dry and trim the hedge", [("lawn", "Mow the lawn"), ("hedge", nil)]),
    ("Pay the water bill before Friday and pay the phone bill", [("water", "Pay the water bill"), ("phone", nil)]),
    ("The smoke alarm keeps chirping, change its battery, and buy more olive oil", [("smoke", "Replace the smoke alarm battery"), ("olive", "Buy olive oil")]),
    ("Clean the shower glass and scrub the bathroom floor", [("shower", "Clean the shower glass"), ("floor", nil)]),
    ("Book the boiler service, book a dentist appointment, and buy coffee", [("boiler", "Book the boiler service"), ("dentist", nil), ("coffee", nil)]),
    ("Water the plants and wash the car", [("plants", nil), ("car", nil)]),
]

actor QueryLog { var last: [String] = []; func set(_ q: [String]) { last = q } }
/// Passes snapshots through and keeps the last Tool-query list (the Tool-call count).
struct Watched: IngestionModel {
    let inner: any IngestionModel; let log: QueryLog
    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        let inner = inner, log = log
        return AsyncThrowingStream { c in
            let t = Task {
                do { for try await s in inner.snapshots(for: request) { await log.set(s.lookupQueries); c.yield(s) }; c.finish() }
                catch { c.finish(throwing: error) }
            }
            c.onTermination = { _ in t.cancel() }
        }
    }
}
var calls: [Int] = []
let source = FoundationModelsOnDeviceSource(locale: Locale(identifier: "en_US"))
print("availability", source.availability())
var created = 0, falseMerges = 0, matched = 0, expected = 0, ttfis: [Double] = []
for (n, (input, items)) in cases.enumerated() {
    await source.prewarm(household: household)
    try await Task.sleep(for: .seconds(1))
    let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: now, calendar: .current, timeZone: .current,
                                 duplicateCheck: DraftDuplicateRules.onDevice(household: household))
    let clock = ContinuousClock(); let start = clock.now
    var ttfi: Double?
    var summary = DraftStreamSummary()
    let qlog = QueryLog()
    for await event in pipeline.events(from: .onDevice(Watched(inner: source.model(household: household), log: qlog))) {
        if case .emitted = event, ttfi == nil {
            let d = start.duration(to: clock.now); ttfi = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        summary.apply(event)
    }
    if let ttfi { ttfis.append(ttfi) }
    let queries = await qlog.last
    calls.append(queries.count)
    var line = "in\(n + 1) toolCalls \(queries.count) \(queries) ttfi \(ttfi.map { String(format: "%.2f", $0) } ?? "-") drafts \(summary.drafts.count):"
    for (keyword, existing) in items {
        expected += 1
        guard let draft = summary.drafts.first(where: { $0.title.lowercased().contains(keyword) }) else {
            line += " [\(keyword): no draft]"; continue
        }
        matched += 1
        let mark: String
        switch draft.duplicate {
        case let .ofExisting(id): mark = tasks.first { $0.id == id }?.title ?? "?"
        case .ofDraft: mark = "ofDraft"
        case .none: mark = "none"
        }
        if let existing {
            if mark != existing { created += 1 }
        } else if mark != "none" { falseMerges += 1 }
        line += " [\(keyword) → \(mark)]"
    }
    print(line)
}
let sorted = ttfis.sorted()
print("SUMMARY expected \(expected) matched \(matched) duplicatesCreated \(created) falseMerges \(falseMerges) toolCalls \(calls.reduce(0, +)) ttfiMedian \(String(format: "%.2f", sorted[sorted.count / 2])) min \(String(format: "%.2f", sorted.first ?? 0)) max \(String(format: "%.2f", sorted.last ?? 0))")
