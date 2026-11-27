// SP-1 timing probe (device spike, information only; never evidence for an AC). docs/milestones/M2/device-scripts/
// SP-1.md Part D3. R-1, AC-M2-16 (the number looked at, not proven here), AC-M2-07 (one Tool call per capture).
//
// Off by default: it runs only when the test process has `TEND_SP1=1` (the owner passes `TEST_RUNNER_TEND_SP1=1` to
// `xcodebuild`); in B5 it is skipped. Inputs are the Developer dev set (`devset-main.swift`, WI-M2-M2 round 2
// evidence): 8 captures `dev1`…`dev8` and a household of 8 tasks in 3 rooms, with fixed IDs. Nothing from the frozen
// eval is read, bundled or copied. No timing is asserted: the test fails only if the on-device model is unavailable or
// the probe itself breaks. Each result is one `SP1|…` line on standard output, written unbuffered.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

enum SP1DevSet {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ n: UInt8) -> UUID {
        UUID(uuid: (0x5E, 0x01, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let kitchen = Room(id: id(201), name: "Kitchen")
    static let bath = Room(id: id(202), name: "Bathroom")
    static let garden = Room(id: id(203), name: "Garden")

    static func task(_ n: UInt8, _ title: String, _ kind: TaskKind, _ room: Room?) throws -> HouseholdTask {
        try HouseholdTask(id: id(n), title: title, kind: kind, roomID: room?.id, effort: .normal, windowStart: now,
                          windowEnd: now.addingTimeInterval(7 * 86_400),
                          recurrenceIntervalDays: kind == .recurring ? 7 : nil)
    }

    static func household() throws -> Household {
        Household(tasks: [
            try task(1, "Buy dishwasher pods", .restock, kitchen), try task(2, "Descale the kettle", .oneOff, kitchen),
            try task(3, "Clean the shower glass", .recurring, bath), try task(4, "Mow the lawn", .recurring, garden),
            try task(5, "Pay the water bill", .oneOff, nil), try task(6, "Replace the smoke alarm battery", .oneOff, nil),
            try task(7, "Buy olive oil", .restock, kitchen), try task(8, "Book the boiler service", .oneOff, nil),
        ], rooms: [kitchen, bath, garden])
    }

    /// (id, input, [(keyword in the draft title, expected existing title or nil)]), as in `devset-main.swift`.
    static let cases: [(String, String, [(String, String?)])] = [
        ("dev1", "We're nearly out of dishwasher tablets and the bin needs taking out",
         [("dishwasher", "Buy dishwasher pods"), ("bin", nil)]),
        ("dev2", "Kettle needs descaling, also wipe the oven door", [("kettle", "Descale the kettle"), ("oven", nil)]),
        ("dev3", "Mow the lawn on Saturday if it's dry and trim the hedge", [("lawn", "Mow the lawn"), ("hedge", nil)]),
        ("dev4", "Pay the water bill before Friday and pay the phone bill",
         [("water", "Pay the water bill"), ("phone", nil)]),
        ("dev5", "The smoke alarm keeps chirping, change its battery, and buy more olive oil",
         [("smoke", "Replace the smoke alarm battery"), ("olive", "Buy olive oil")]),
        ("dev6", "Clean the shower glass and scrub the bathroom floor",
         [("shower", "Clean the shower glass"), ("floor", nil)]),
        ("dev7", "Book the boiler service, book a dentist appointment, and buy coffee",
         [("boiler", "Book the boiler service"), ("dentist", nil), ("coffee", nil)]),
        ("dev8", "Water the plants and wash the car", [("plants", nil), ("car", nil)]),
    ]
}

/// Unbuffered `SP1|…` lines with a running number.
final class SP1Lines: @unchecked Sendable {
    // @unchecked Sendable: `seq` is touched only under `lock`. Test target only.
    static let shared = SP1Lines()
    private let lock = NSLock()
    private var seq = 0

    func emit(_ fields: String) {
        let line = lock.withLock { () -> String in
            seq += 1
            return "SP1|seq=\(seq)|\(fields)\n"
        }
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

/// Keeps the generations a source made, so the probe can read the Tool counts (`@testable`; no new public API).
final class SP1Generations: @unchecked Sendable {
    // @unchecked Sendable: `made` is touched only under `lock`. Test target only.
    private let lock = NSLock()
    private var made: [FoundationModelsGeneration] = []
    func add(_ generation: FoundationModelsGeneration) { lock.withLock { made.append(generation) } }
    func last() -> FoundationModelsGeneration? { lock.withLock { made.last } }
}

@Suite("SP-1 timing probe (information only; runs only with TEND_SP1=1)")
struct SP1TimingProbe {

    static var isEnabled: Bool { ProcessInfo.processInfo.environment["TEND_SP1"] == "1" }

    /// The device model code (for example `iPhone16,1`); in the Simulator, the simulated model's code.
    static func machine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static func ms(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }

    struct Result {
        var ttfi: Int?
        var total: Int
        var answered: Int
        var refused: Int
        var outcome: String
        var drafts: Int
        var duplicatesCreated: Int
        var falseMerges: Int
        var timedOut: Bool
    }

    /// One capture through the real pipeline on the on-device route; 30 s limit.
    static func run(_ input: String, expectations: [(String, String?)], household: Household,
                    source: FoundationModelsOnDeviceSource, generations: SP1Generations) async -> Result {
        let pipeline = DraftPipeline(input: input, rooms: household.rooms, now: SP1DevSet.now,
                                     calendar: Calendar(identifier: .gregorian),
                                     timeZone: TimeZone(identifier: "UTC") ?? .gmt,
                                     duplicateCheck: DraftDuplicateRules.onDevice(household: household))
        let model = source.model(household: household)
        let clock = ContinuousClock()
        let start = clock.now
        let work = Task { () -> (Duration?, DraftStreamSummary, Bool) in
            var ttfi: Duration?
            var summary = DraftStreamSummary()
            var sawFinished = false
            for await event in pipeline.events(from: .onDevice(model)) {
                if case .emitted = event, ttfi == nil { ttfi = start.duration(to: clock.now) }
                if case .finished = event { sawFinished = true }
                summary.apply(event)
            }
            return (ttfi, summary, sawFinished)
        }
        let watchdog = Task {
            // Cancelled when the capture ends first; only a real 30 s timeout cancels the capture.
            guard (try? await Task.sleep(for: .seconds(30))) != nil else { return }
            work.cancel()
        }
        let (ttfi, summary, sawFinished) = await work.value
        watchdog.cancel()
        let total = start.duration(to: clock.now)
        // A timeout only when the watchdog cancelled the capture before its own `finished` (review n-1).
        // The watchdog's cancel shows as a `cancelled` outcome; any other finished outcome means the capture ended
        // first, even if the watchdog fired just after.
        let endedByItself: Bool = switch summary.outcome {
        case .completed?, .interrupted?, .noModel?: sawFinished
        case .cancelled?, nil: false
        }
        let timedOut = work.isCancelled && !endedByItself
        let recorder = generations.last()?.recorder
        let answered = await recorder?.queries.count ?? 0
        let refused = await recorder?.refusedCalls ?? 0
        var created = 0, falseMerges = 0
        for (keyword, existing) in expectations {
            guard let draft = summary.drafts.first(where: { $0.title.lowercased().contains(keyword) }) else { continue }
            let mark: String = switch draft.duplicate {
            case let .ofExisting(id): household.tasks.first { $0.id == id }?.title ?? "?"
            case .ofDraft: "ofDraft"
            case .none: "none"
            }
            if let existing { if mark != existing { created += 1 } } else if mark != "none" { falseMerges += 1 }
        }
        let outcome: String = switch summary.outcome {
        case .completed?: "completed"
        case .interrupted?: "interrupted"
        case .noModel?: "noModel"
        case .cancelled?: "cancelled"
        case nil: "none"
        }
        return Result(ttfi: ttfi.map(ms), total: ms(total), answered: answered, refused: refused,
                      outcome: timedOut ? "timeout" : outcome, drafts: summary.drafts.count,
                      duplicatesCreated: created, falseMerges: falseMerges, timedOut: timedOut)
    }

    static func fields(_ r: Result) -> String {
        "ttfi_ms=\(r.ttfi.map(String.init) ?? "none")|total_ms=\(r.total)|tool_answered=\(r.answered)"
            + "|tool_refused=\(r.refused)|outcome=\(r.outcome)|drafts=\(r.drafts)|dup_created=\(r.duplicatesCreated)"
            + "|false_merges=\(r.falseMerges)"
    }

    @Test("SP-1: cold dev1, then 3 warm rounds over dev1…dev8 (prints SP1 lines; no timing is asserted)",
          .enabled(if: SP1TimingProbe.isEnabled), .timeLimit(.minutes(15)))
    func probe() async throws {
        let out = SP1Lines.shared
        let household = try SP1DevSet.household()
        let generations = SP1Generations()
        let source = FoundationModelsOnDeviceSource(
            readAvailability: {
                let model = SystemLanguageModel.default
                return (model.availability, model.supportsLocale(Locale(identifier: "en_US")))
            },
            makeGeneration: { household in
                let generation = FoundationModelsGeneration(household: household)
                generations.add(generation)
                return generation
            })
        let availability = source.availability()
        let commit = (Bundle.main.object(forInfoDictionaryKey: "TendCommit") as? String) ?? "unknown"
        let model = switch availability {
        case .available: "available"
        case let .unavailable(reason): "unavailable(\(reason))"
        }
        out.emit("header|device=\(Self.machine())|os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
                 + "|thermal=\(Self.thermal())|lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)"
                 + "|model=\(model)|commit=\(commit)")
        guard availability == .available else {
            Issue.record("SP-1: the on-device model is not available here: \(model)")
            return
        }
        let (_, coldInput, coldExpect) = SP1DevSet.cases[0]
        let cold = await Self.run(coldInput, expectations: coldExpect, household: household, source: source,
                                  generations: generations)
        out.emit("cold|input=dev1|" + Self.fields(cold))
        var warm: [Result] = []
        for round in 1...3 {
            for (id, input, expect) in SP1DevSet.cases {
                await source.prewarm(household: household)
                try await Task.sleep(for: .seconds(1))
                let result = await Self.run(input, expectations: expect, household: household, source: source,
                                            generations: generations)
                warm.append(result)
                out.emit("warm|round=\(round)|input=\(id)|" + Self.fields(result))
            }
        }
        let ttfis = warm.compactMap(\.ttfi).sorted()
        let totals = warm.map(\.total).sorted()
        // The upper middle value for an even count (the 13th of 24; review n-2): information only.
        func median(_ values: [Int]) -> String { values.isEmpty ? "none" : String(values[values.count / 2]) }
        out.emit("summary|warm_n=\(warm.count)|ttfi_min_ms=\(ttfis.first.map(String.init) ?? "none")"
                 + "|ttfi_median_ms=\(median(ttfis))|ttfi_max_ms=\(ttfis.last.map(String.init) ?? "none")"
                 + "|ttfi_under_1500=\(ttfis.filter { $0 < 1_500 }.count)/\(warm.count)"
                 + "|total_median_ms=\(median(totals))|total_max_ms=\(totals.last.map(String.init) ?? "none")"
                 + "|total_le_5000=\(totals.filter { $0 <= 5_000 }.count)/\(warm.count)"
                 + "|tool_answered_max=\(warm.map(\.answered).max() ?? 0)|tool_refused_sum=\(warm.map(\.refused).reduce(0, +))")
        out.emit("footer|thermal=\(Self.thermal())|lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
    }
}
