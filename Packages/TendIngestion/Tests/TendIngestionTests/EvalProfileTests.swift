// Scoring profiles (plan "Scoring tool and command", "Profiles"): the AC thresholds over synthetic runs, tested at each
// boundary. AC-M2-11, 15, 16, 17, 25, 26, 27; rubric Q3. The synthetic fixtures are built here (not the eval).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// A synthetic eval: n inputs (odd numbers voice, even text), k golden create items each, one seeded task.
enum Synthetic {
    static let hash = String(repeating: "a", count: 64)

    static func inputID(_ i: Int) -> String { "in" + (i < 10 ? "0" : "") + String(i) }
    static func token(_ i: Int, _ j: Int) -> String { "item\(i)x\(j)" }
    static func mode(_ i: Int) -> EvalInputMode { i % 2 == 1 ? .voice : .text }

    static func fixtures(inputs n: Int, items k: Int) throws -> (Data, Data, Data) {
        let inputs = EvalJSON.object([.init("schemaVersion", .integer(1)), .init("inputs", .array((1...n).map { i in
            .object([.init("id", .string(inputID(i))), .init("mode", .string(mode(i).rawValue)),
                     .init("text", .string("Say the items of input \(i)"))])
        }))])
        let household = EvalJSON.object([
            .init("schemaVersion", .integer(1)),
            .init("rooms", .array([.object([.init("key", .string("kitchen")),
                                             .init("id", .string("5E1F0000-0000-4000-8000-000000000001")),
                                             .init("name", .string("Kitchen"))])])),
            .init("tasks", .array([.object([
                .init("key", .string("t-seed")), .init("id", .string("5E1F0000-0000-4000-8000-000000000002")),
                .init("title", .string("Seeded chore")), .init("kind", .string("oneOff")), .init("roomKey", .null),
                .init("effort", .string("normal")), .init("isCritical", .bool(false)), .init("isDeepClean", .bool(false)),
                .init("isWeatherDependent", .bool(false)),
                .init("allowedDayparts", .array([.string("morning")])), .init("allowedWeekdays", .array([.string("monday")])),
                .init("windowStart", .string("2026-11-23T14:00:00.000Z")),
                .init("windowEnd", .string("2026-11-24T14:00:00.000Z")), .init("recurrenceIntervalDays", .null),
                .init("state", .string("active")),
                .init("matchGroups", .array([.array([.string("seeded")]), .array([.string("chore")])])),
            ])])),
        ])
        var items: [EvalJSON] = []
        for i in 1...n {
            for j in 1...k {
                items.append(.object([
                    .init("inputID", .string(inputID(i))), .init("key", .string("g-\(i)-\(j)")),
                    .init("matchGroups", .array([.array([.string(token(i, j))])])),
                    .init("kind", .string("oneOff")), .init("room", .object([.init("type", .string("none"))])),
                    .init("effort", .string("normal")), .init("isCritical", .bool(false)),
                    .init("isDeepClean", .bool(false)), .init("isWeatherDependent", .bool(false)),
                    .init("expect", .object([.init("type", .string("create"))])),
                ]))
            }
        }
        let golden = EvalJSON.object([.init("schemaVersion", .integer(1)), .init("items", .array(items))])
        return (try EvalSelfTest.canonical(inputs), try EvalSelfTest.canonical(household),
                try EvalSelfTest.canonical(golden))
    }

    static func draft(_ id: Int, title: String, duplicate: DraftRecord.DuplicateRecord = .none,
                      end: Int64 = 86_400_000) -> DraftRecord {
        DraftRecord(draftID: id, title: title, kind: .oneOff, room: .none, effort: .normal, isCritical: false,
                    isDeepClean: false, isWeatherDependent: false, allowedDayparts: Daypart.defaultAllowed,
                    allowedWeekdays: Set(Weekday.allCases), windowStart: EvalInstant(millisecondsSince1970: 0),
                    windowEnd: EvalInstant(millisecondsSince1970: end), recurrenceIntervalDays: nil,
                    sourcePhrase: nil, duplicate: duplicate)
    }

    /// The right drafts for input i: one per golden item.
    static func rightDrafts(_ i: Int, items k: Int) -> [DraftRecord] {
        (1...k).map { draft($0, title: "Clean " + token(i, $0)) }
    }

    static func attempt(
        _ i: Int, drafts: [DraftRecord], route: EvalRoute = .onDevice, outcome: EvalOutcome = .completed,
        ttfi: Int = 300, total: Int = 1000, cloud: [EvalResultsFileV1.CloudRequestRecord] = []
    ) -> EvalResultsFileV1.InputAttempt {
        var events: [EvalResultsFileV1.Event] = []
        for (index, d) in drafts.enumerated() {
            events.append(.init(type: .emitted, draftID: d.draftID, tMs: min(total, ttfi + index)))
        }
        events.append(.init(type: .finished, draftID: nil, tMs: total))
        let voice = mode(i) == .voice
        return .init(
            inputID: inputID(i), mode: mode(i), attempt: 1, retakeReason: nil,
            transcript: voice ? "Say the items of input \(i)" : nil, transcriber: voice ? .speechTranscriber : nil,
            route: route, outcome: outcome, ttfiMs: drafts.isEmpty ? nil : ttfi, totalMs: total, events: events,
            drafts: drafts, committed: drafts.filter { !$0.duplicate.isMarked }.map(\.draftID), cloudRequests: cloud
        )
    }

    static func file(provider: EvalProvider? = nil, _ attempts: [EvalResultsFileV1.InputAttempt]) -> EvalResultsFileV1 {
        EvalResultsFileV1(
            run: .init(operatorName: "synthetic", startedAtUTC: "2026-11-22T10:00:00Z", deviceModel: "iPhone16,1",
                       iOSBuild: "23A000", appCommitSHA: String(repeating: "0", count: 40), fixturesSHA256: hash,
                       locale: "en_US", routePreference: provider == nil ? .onDeviceFirst : .alwaysCloud,
                       provider: provider, modelID: "m", sampling: "greedy", prewarm: true,
                       network: .init(kind: "wifi", downMbps: 100, upMbps: 20, latencyMs: 12)),
            coldStart: nil, inputs: attempts
        )
    }

    /// 20 right inputs with k items each, with `edit` applied per input (nil keeps it out of the file).
    static func run(
        _ profile: EvalProfile, inputs n: Int = 20, items k: Int = 3, provider: EvalProvider? = nil,
        allowedKeyPaths: Set<String>? = nil,
        edit: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 }
    ) throws -> EvalProfileResult {
        let route = provider.flatMap { EvalRoute(rawValue: $0.rawValue) } ?? .onDevice
        let attempts = (1...n).compactMap { i in edit(i, attempt(i, drafts: rightDrafts(i, items: k), route: route)) }
        let (inputs, household, golden) = try fixtures(inputs: n, items: k)
        let request = EvalScoringRequest(
            results: try CanonicalJSONWriter.data(file(provider: provider, attempts).canonicalJSON),
            schema: try EvalSelfTest.data(EvalSelfTest.schemaPath), inputs: inputs, household: household,
            golden: golden, expectedFixturesSHA256: hash, profile: profile, allowedKeyPaths: allowedKeyPaths
        )
        return try EvalScorer.run(request).profileResult
    }

    static func failing(_ result: EvalProfileResult) -> [String] { result.checks.filter { !$0.holds }.map(\.name) }
}

@Suite("WI-M2-15 scoring profiles at their thresholds (AC-M2-11, 15, 16, 17, 25, 26, 27; Q3)")
struct EvalProfileTests {

    // MARK: ds1-gated (AC-M2-15, 16, 17)

    @Test("ds1-gated: a right 20-input run (N = 60) passes every check")
    func ds1GatedPasses() throws {
        let result = try Synthetic.run(.ds1Gated)
        #expect(result.passes, "\(Synthetic.failing(result))")
        // 1 provider + 14 Q3 and duplicate checks + 1 route + 1 timing.
        #expect(result.checks.count == 17)
    }

    @Test("ds1-gated, Q3 segmentation: 57 of 60 found passes (⌈0.95 × 60⌉ = 57); 56 does not")
    func segmentationBoundary() throws {
        func dropping(_ count: Int) throws -> EvalProfileResult {
            try Synthetic.run(.ds1Gated) { i, a in
                i > count ? a : Synthetic.attempt(i, drafts: Array(Synthetic.rightDrafts(i, items: 3).dropLast()))
            }
        }
        #expect(try dropping(3).passes)
        let four = try dropping(4)
        #expect(Synthetic.failing(four).contains("segmentation >= 95% (Q3)"))
    }

    @Test("ds1-gated, Q3 extras: 2 extra drafts pass, 3 do not")
    func extrasBoundary() throws {
        func extras(_ count: Int) throws -> EvalProfileResult {
            try Synthetic.run(.ds1Gated) { i, a in
                i > count ? a : Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3)
                    + [Synthetic.draft(4, title: "Unrelated thing \(i)")])
            }
        }
        #expect(try extras(2).passes)
        #expect(Synthetic.failing(try extras(3)) == ["extra drafts <= 2 in total (Q3)"])
    }

    @Test("ds1-gated, AC-M2-17: 1 false merge passes, 2 do not; 1 duplicate created does not")
    func duplicatesAndFalseMerges() throws {
        func merges(_ count: Int) throws -> EvalProfileResult {
            try Synthetic.run(.ds1Gated) { i, a in
                guard i <= count else { return a }
                var drafts = Synthetic.rightDrafts(i, items: 3)
                drafts[0].duplicate = .ofExisting(taskKey: "t-seed")
                return Synthetic.attempt(i, drafts: drafts)
            }
        }
        #expect(try merges(1).passes)
        #expect(Synthetic.failing(try merges(2)) == ["false merges <= 1 (AC-M2-17/26)"])
        let duplicate = try Synthetic.run(.ds1Gated) { i, a in
            i == 1 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3)
                + [Synthetic.draft(4, title: "Seeded chore")]) : a
        }
        // The extra "Seeded chore" draft is committed and its best target is t-seed → 1 duplicate (and 1 extra).
        #expect(Synthetic.failing(duplicate) == ["0 duplicates created (AC-M2-17/26)"])
    }

    @Test("ds1-gated, AC-M2-16: TTFI 1499 ms passes and 1500 ms does not; total 5000 ms passes and 5001 ms does not")
    func ds1Timing() throws {
        func timed(ttfi: Int, total: Int) throws -> EvalProfileResult {
            try Synthetic.run(.ds1Gated) { i, a in
                i == 7 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3), ttfi: ttfi, total: total) : a
            }
        }
        let name = "every input TTFI < 1500 ms and total <= 5000 ms (AC-M2-16)"
        #expect(try timed(ttfi: 1499, total: 5000).passes)
        #expect(Synthetic.failing(try timed(ttfi: 1500, total: 5000)) == [name])
        #expect(Synthetic.failing(try timed(ttfi: 1499, total: 5001)) == [name])
        // An input with no draft has no TTFI, so it does not meet AC-M2-16.
        let none = try Synthetic.run(.ds1Gated, items: 3) { i, a in
            i == 2 ? Synthetic.attempt(i, drafts: [], outcome: .noModel) : a
        }
        #expect(Synthetic.failing(none).contains(name))
    }

    @Test("ds1-gated: validity, calm words, routes, absent inputs and N < 50 each stop a pass")
    func ds1OtherChecks() throws {
        let invalid = try Synthetic.run(.ds1Gated) { i, a in
            guard i == 3 else { return a }
            var drafts = Synthetic.rightDrafts(i, items: 3)
            drafts[1] = Synthetic.draft(2, title: drafts[1].title, end: 0)
            return Synthetic.attempt(i, drafts: drafts)
        }
        #expect(Synthetic.failing(invalid) == ["validity 100% (Q3)"])
        let introduced = try Synthetic.run(.ds1Gated) { i, a in
            guard i == 4 else { return a }
            var drafts = Synthetic.rightDrafts(i, items: 3)
            drafts[0].title += " penalty"
            return Synthetic.attempt(i, drafts: drafts)
        }
        #expect(Synthetic.failing(introduced) == ["0 introduced banned tokens (Q3, UX-3)"])
        let cloudRoute = try Synthetic.run(.ds1Gated) { i, a in
            i == 5 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3), route: .none) : a
        }
        #expect(Synthetic.failing(cloudRoute) == ["route onDevice for every scored input (AC-M2-15)"])
        let absent = try Synthetic.run(.ds1Gated) { i, a in i == 20 ? nil : a }
        #expect(Synthetic.failing(absent) == ["every fixture input scored"])
        let small = try Synthetic.run(.ds1Gated, items: 2)
        #expect(Synthetic.failing(small) == ["N >= 50 golden items (AC-M2-14)"])
        let withProvider = try Synthetic.run(.ds1Gated, provider: .openai)
        #expect(Synthetic.failing(withProvider).contains("run on device, no provider (AC-M2-15)"))
    }

    // MARK: ds2-gated (AC-M2-26, 27)

    static let allowed: Set<String> = ["$.messages[].content", "$.model", "$.stream"]

    static func cloudRun(
        allowed: Set<String>? = allowed, edit: @escaping (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 }
    ) throws -> EvalProfileResult {
        try Synthetic.run(.ds2Gated, provider: .anthropic, allowedKeyPaths: allowed) { i, a in
            var copy = a
            copy.cloudRequests = [.init(attempt: 1, bytes: 900, keyPaths: ["$.messages[].content", "$.model"])]
            return edit(i, copy)
        }
    }

    @Test("ds2-gated: a right cloud run passes; TTFI 2999/3000 ms and total 10000/10001 ms are the AC-M2-27 boundaries")
    func ds2Gated() throws {
        #expect(try Self.cloudRun().passes)
        let name = "every input TTFI < 3000 ms and total <= 10000 ms (AC-M2-27)"
        func timed(_ ttfi: Int, _ total: Int) throws -> EvalProfileResult {
            try Self.cloudRun { i, a in
                guard i == 9 else { return a }
                var timedAttempt = Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3), route: .anthropic,
                                                     ttfi: ttfi, total: total)
                timedAttempt.cloudRequests = a.cloudRequests
                return timedAttempt
            }
        }
        #expect(try timed(2999, 10000).passes)
        #expect(Synthetic.failing(try timed(3000, 10000)) == [name])
        #expect(Synthetic.failing(try timed(2999, 10001)) == [name])
    }

    @Test("ds2-gated, AC-M2-26: a key path outside the allowed list, or no list, stops a pass; the route must be the provider")
    func ds2KeyPaths() throws {
        let keyName = "sent key paths are a subset of the allowed list (AC-M2-26)"
        let outside = try Self.cloudRun { i, a in
            guard i == 2 else { return a }
            var copy = a
            copy.cloudRequests = [.init(attempt: 1, bytes: 900, keyPaths: ["$.metadata.user_id", "$.model"])]
            return copy
        }
        #expect(Synthetic.failing(outside) == [keyName])
        #expect(Synthetic.failing(try Self.cloudRun(allowed: nil)) == [keyName])
        let otherRoute = try Self.cloudRun { i, a in
            guard i == 3 else { return a }
            var copy = a
            copy.route = .openai
            return copy
        }
        #expect(Synthetic.failing(otherRoute) == ["route anthropic for every scored input (AC-M2-26)"])
    }

    // MARK: ds1-offline (AC-M2-11), ds2-offline / ds2-online (AC-M2-25), info

    @Test("ds1-offline (AC-M2-11): 3 inputs, 2 voice, each completed with every item, no extra, valid, calm, no duplicate")
    func ds1Offline() throws {
        let three: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, a in i <= 3 ? a : nil }
        #expect(try Synthetic.run(.ds1Offline, edit: three).passes)
        let extra = try Synthetic.run(.ds1Offline) { i, a in
            guard i <= 3 else { return nil }
            return i == 2 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3)
                + [Synthetic.draft(4, title: "Unrelated")]) : a
        }
        #expect(Synthetic.failing(extra) == ["in02: parses cleanly (AC-M2-11)"])
        let interrupted = try Synthetic.run(.ds1Offline) { i, a in
            guard i <= 3 else { return nil }
            return i == 1 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3), outcome: .interrupted) : a
        }
        #expect(Synthetic.failing(interrupted) == ["in01: parses cleanly (AC-M2-11)"])
        let four = try Synthetic.run(.ds1Offline) { i, a in i <= 4 ? a : nil }
        #expect(Synthetic.failing(four) == ["3 inputs, 2 voice (AC-M2-11)"])
    }

    @Test("ds2-offline (AC-M2-25): 2 voice inputs, each noModel with nothing committed")
    func ds2Offline() throws {
        let offline: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, _ in
            [1, 3].contains(i) ? Synthetic.attempt(i, drafts: [], route: .gemini, outcome: .noModel) : nil
        }
        #expect(try Synthetic.run(.ds2Offline, provider: .gemini, edit: offline).passes)
        let parsed = try Synthetic.run(.ds2Offline, provider: .gemini) { i, a in [1, 3].contains(i) ? a : nil }
        #expect(Synthetic.failing(parsed) == ["in01: noModel, no task created (AC-M2-25)",
                                              "in03: noModel, no task created (AC-M2-25)"])
    }

    @Test("ds2-online (AC-M2-25): 2 voice inputs through the provider, each parsed cleanly")
    func ds2Online() throws {
        let two: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, a in [1, 3].contains(i) ? a : nil }
        #expect(try Synthetic.run(.ds2Online, provider: .openai, edit: two).passes)
        let missing = try Synthetic.run(.ds2Online, provider: .openai) { i, a in
            guard [1, 3].contains(i) else { return nil }
            return i == 3 ? Synthetic.attempt(i, drafts: Array(Synthetic.rightDrafts(i, items: 3).prefix(2)),
                                              route: .openai) : a
        }
        #expect(Synthetic.failing(missing) == ["in03: parses cleanly (AC-M2-25)"])
        let textInput = try Synthetic.run(.ds2Online, provider: .openai) { i, a in [1, 2].contains(i) ? a : nil }
        #expect(Synthetic.failing(textInput) == ["2 inputs, 2 voice (AC-M2-25)"])
    }

    @Test("info has no pass rule: even a poor run passes")
    func info() throws {
        let result = try Synthetic.run(.info, items: 1) { i, _ in Synthetic.attempt(i, drafts: [], outcome: .noModel) }
        #expect(result.checks.isEmpty && result.passes)
    }

    @Test("profile names are the plan's command-line names")
    func names() {
        #expect(EvalProfile.allCases.map(\.rawValue) == ["ds1-gated", "ds1-offline", "ds2-offline", "ds2-online",
                                                        "ds2-gated", "info"])
    }
}
