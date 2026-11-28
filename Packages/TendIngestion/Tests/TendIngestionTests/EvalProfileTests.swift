// Scoring profiles (plan "Scoring tool and command", "Profiles"): the AC thresholds over synthetic runs, tested at each
// boundary. AC-M2-11, 15, 16, 17, 25, 26, 27; rubric Q3. The synthetic fixtures are built here (not the eval).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// A synthetic eval: n inputs with the frozen eval fixtures' modes (A-F1: in01 text, in02 voice, … in10 voice, …
/// in16 voice, in17 voice, in18 text, in19 text, in20 voice), k golden create items each, one seeded task. `flipped`
/// inverts the mode of those inputs in the fixtures and the default attempts (the wrong-mode files of A-F1).
enum Synthetic {
    static let hash = String(repeating: "a", count: 64)
    /// The voice inputs of `Fixtures/M2/eval/inputs.json` on `m2/eval-fixtures-freeze`; every other input is text.
    static let voiceInputs: Set<Int> = [2, 4, 6, 8, 10, 12, 14, 16, 17, 20]

    static func inputID(_ i: Int) -> String { "in" + (i < 10 ? "0" : "") + String(i) }
    static func token(_ i: Int, _ j: Int) -> String { "item\(i)x\(j)" }
    static func mode(_ i: Int, flipped: Set<Int> = []) -> EvalInputMode {
        voiceInputs.contains(i) != flipped.contains(i) ? .voice : .text
    }

    static func fixtures(inputs n: Int, items k: Int, flipped: Set<Int> = []) throws -> (Data, Data, Data) {
        let inputs = EvalJSON.object([.init("schemaVersion", .integer(1)), .init("inputs", .array((1...n).map { i in
            .object([.init("id", .string(inputID(i))), .init("mode", .string(mode(i, flipped: flipped).rawValue)),
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
        ttfi: Int = 300, total: Int = 1000, cloud: [EvalResultsFileV1.CloudRequestRecord] = [],
        flipped: Set<Int> = []
    ) -> EvalResultsFileV1.InputAttempt {
        var events: [EvalResultsFileV1.Event] = []
        for (index, d) in drafts.enumerated() {
            events.append(.init(type: .emitted, draftID: d.draftID, tMs: min(total, ttfi + index)))
        }
        events.append(.init(type: .finished, draftID: nil, tMs: total))
        let voice = mode(i, flipped: flipped) == .voice
        return .init(
            inputID: inputID(i), mode: mode(i, flipped: flipped), attempt: 1, retakeReason: nil,
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
    static func request(
        _ profile: EvalProfile, inputs n: Int = 20, items k: Int = 3, provider: EvalProvider? = nil,
        allowedKeyPaths: Set<String>? = nil, goldenBody: Data? = nil, flipped: Set<Int> = [], retakes: Set<Int> = [],
        edit: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 },
        firstAttempt: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt = { $1 }
    ) throws -> EvalScoringRequest {
        let route = provider.flatMap { EvalRoute(rawValue: $0.rawValue) } ?? .onDevice
        // `retakes`: those inputs get a first attempt with no draft and then the edited attempt as a retake (attempt 2).
        let attempts = (1...n).flatMap { i -> [EvalResultsFileV1.InputAttempt] in
            guard let edited = edit(i, attempt(i, drafts: rightDrafts(i, items: k), route: route, flipped: flipped))
            else { return [] }
            guard retakes.contains(i) else { return [edited] }
            var retake = edited
            retake.attempt = 2
            retake.retakeReason = "background noise"
            // `firstAttempt` edits the retaken (unscored) first attempt.
            return [firstAttempt(i, attempt(i, drafts: [], route: route, outcome: .noModel, flipped: flipped)), retake]
        }
        let (inputs, household, golden) = try fixtures(inputs: n, items: k, flipped: flipped)
        return EvalScoringRequest(
            results: try CanonicalJSONWriter.data(file(provider: provider, attempts).canonicalJSON),
            schema: try EvalSelfTest.data(EvalSelfTest.schemaPath), inputs: inputs, household: household,
            golden: golden, expectedFixturesSHA256: hash, profile: profile, allowedKeyPaths: allowedKeyPaths,
            goldenBody: goldenBody
        )
    }

    static func run(
        _ profile: EvalProfile, inputs n: Int = 20, items k: Int = 3, provider: EvalProvider? = nil,
        allowedKeyPaths: Set<String>? = nil, goldenBody: Data? = nil, flipped: Set<Int> = [], retakes: Set<Int> = [],
        edit: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 },
        firstAttempt: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt = { $1 }
    ) throws -> EvalProfileResult {
        try EvalScorer.run(try request(profile, inputs: n, items: k, provider: provider,
                                       allowedKeyPaths: allowedKeyPaths, goldenBody: goldenBody, flipped: flipped,
                                       retakes: retakes, edit: edit, firstAttempt: firstAttempt)).profileResult
    }

    /// The scoring error for a run, or nil when it is scored.
    static func rejection(
        _ profile: EvalProfile, provider: EvalProvider? = nil, flipped: Set<Int> = [], retakes: Set<Int> = [],
        edit: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 }
    ) throws -> EvalScoringError? {
        let request = try request(profile, provider: provider, flipped: flipped, retakes: retakes, edit: edit)
        do throws(EvalScoringError) {
            _ = try EvalScorer.run(request)
            return nil
        } catch {
            return error
        }
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

    /// The Anthropic golden body (`g1-outcome-empty-anthropic`) and its array counts (D-059).
    static func goldenBody() throws -> Data {
        try EvalSelfTest.data("Fixtures/M2/payload/golden/g1-outcome-empty-anthropic.body.json")
    }

    static func goldenCounts() throws -> [ArrayCount] {
        try #require(CloudRequestKeyPaths.arrayCounts(ofBody: try goldenBody()))
    }

    /// The user-content counts of a capture in the synthetic household (1 room), with `titles` shortlist titles.
    static func contentCounts(titles: Int = 2, rooms: Int = 1) -> [ArrayCount] {
        [ArrayCount(path: "$.existingTasks", count: titles), ArrayCount(path: "$.rooms", count: rooms)]
    }

    static func request(keyPaths: [String] = ["$.messages[].content", "$.model"], counts: [ArrayCount]?,
                        content: [ArrayCount]?) -> EvalResultsFileV1.CloudRequestRecord {
        .init(attempt: 1, bytes: 900, keyPaths: keyPaths, arrayCounts: counts, userContentArrayCounts: content)
    }

    static func cloudRun(
        allowed: Set<String>? = allowed, goldenBody: Data?? = nil, retakes: Set<Int> = [],
        edit: @escaping (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { $1 },
        firstAttempt: @escaping (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt = { $1 }
    ) throws -> EvalProfileResult {
        let counts = try goldenCounts()
        let body: Data? = try goldenBody ?? Self.goldenBody()
        return try Synthetic.run(.ds2Gated, provider: .anthropic, allowedKeyPaths: allowed, goldenBody: body,
                                 retakes: retakes, edit: { i, a in
            var copy = a
            copy.cloudRequests = [Self.request(counts: counts, content: Self.contentCounts())]
            return edit(i, copy)
        }, firstAttempt: firstAttempt)
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
            copy.cloudRequests = [Self.request(keyPaths: ["$.metadata.user_id", "$.model"],
                                               counts: try? Self.goldenCounts(), content: Self.contentCounts())]
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

    // MARK: ds2-gated per-array element counts (PO ruling on per-array element counts, D-059)

    static let countsName = "per-array element counts match the golden body and the seeded household (AC-M2-26, D-059)"

    /// A cloud run whose input 4 has the request `request`.
    static func countsRun(_ request: @escaping ([ArrayCount]) -> EvalResultsFileV1.CloudRequestRecord)
        throws -> EvalProfileResult {
        let counts = try goldenCounts()
        return try cloudRun { i, a in
            guard i == 4 else { return a }
            var copy = a
            copy.cloudRequests = [request(counts)]
            return copy
        }
    }

    @Test("D-059: an extra element in a fixed array, a missing array or an extra array path stops ds2-gated")
    func countsBodyMismatch() throws {
        let extra = try Self.countsRun { counts in
            var changed = counts
            if let index = changed.firstIndex(where: { $0.path == "$.messages" }) { changed[index].count += 1 }
            return Self.request(counts: changed, content: Self.contentCounts())
        }
        #expect(Synthetic.failing(extra) == [Self.countsName])
        #expect(extra.checks.first { $0.name == Self.countsName }?.detail.contains("in04 attempt 1 request 1: $.messages expected 1, seen 2") == true)
        let missing = try Self.countsRun { counts in
            Self.request(counts: Array(counts.dropLast()), content: Self.contentCounts())
        }
        #expect(Synthetic.failing(missing) == [Self.countsName])
        #expect(missing.checks.first { $0.name == Self.countsName }?.detail.contains("seen absent") == true)
        let extraPath = try Self.countsRun { counts in
            Self.request(counts: (counts + [ArrayCount(path: "$.zzz", count: 0)])
                .sorted { TextFolding.utf8Precedes($0.path, $1.path) }, content: Self.contentCounts())
        }
        #expect(Synthetic.failing(extraPath) == [Self.countsName])
        #expect(extraPath.checks.first { $0.name == Self.countsName }?.detail.contains("$.zzz expected absent, seen 0") == true)
    }

    @Test("D-059: rooms off by one, existingTasks = 11, an unexpected user-content path, or a null member stops ds2-gated")
    func countsContentMismatch() throws {
        let roomsOff = try Self.countsRun { Self.request(counts: $0, content: Self.contentCounts(rooms: 2)) }
        #expect(Synthetic.failing(roomsOff) == [Self.countsName])
        #expect(roomsOff.checks.first { $0.name == Self.countsName }?.detail.contains("$.rooms expected 1, seen 2") == true)
        let eleven = try Self.countsRun { Self.request(counts: $0, content: Self.contentCounts(titles: 11)) }
        #expect(Synthetic.failing(eleven) == [Self.countsName])
        let ten = try Self.countsRun { Self.request(counts: $0, content: Self.contentCounts(titles: 10)) }
        #expect(ten.passes)
        let unexpected = try Self.countsRun { counts in
            Self.request(counts: counts, content: [ArrayCount(path: "$.existingTasks", count: 0),
                                                   ArrayCount(path: "$.notes", count: 1),
                                                   ArrayCount(path: "$.rooms", count: 1)])
        }
        #expect(Synthetic.failing(unexpected) == [Self.countsName])
        let nullBody = try Self.countsRun { _ in Self.request(counts: nil, content: Self.contentCounts()) }
        #expect(Synthetic.failing(nullBody) == [Self.countsName])
        #expect(nullBody.checks.first { $0.name == Self.countsName }?.detail.contains("arrayCounts is null") == true)
        let nullContent = try Self.countsRun { Self.request(counts: $0, content: nil) }
        #expect(Synthetic.failing(nullContent) == [Self.countsName])
        #expect(Synthetic.failing(try Self.cloudRun(goldenBody: .some(nil))) == [Self.countsName])
    }

    // MARK: ds1-offline (AC-M2-11), ds2-offline / ds2-online (AC-M2-25), info

    /// The fixed subsets (PO ruling F3, po-m2-wi16.md; A-F1): the input numbers of each profile.
    static let ds1Subset: Set<Int> = [1, 2, 10]
    static let ds2Subset: Set<Int> = [8, 16]

    @Test("ds1-offline (AC-M2-11): in01 (text), in02 (voice), in10 (voice), each completed with every item, no extra, valid, calm, no duplicate")
    func ds1Offline() throws {
        let three: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, a in
            Self.ds1Subset.contains(i) ? a : nil
        }
        let right = try Synthetic.run(.ds1Offline, edit: three)
        #expect(right.passes, "\(Synthetic.failing(right))")
        #expect(right.checks.map(\.name).contains("inputs in01 (text), in02 (voice), in10 (voice) (AC-M2-11)"))
        let extra = try Synthetic.run(.ds1Offline) { i, a in
            guard Self.ds1Subset.contains(i) else { return nil }
            return i == 2 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3)
                + [Synthetic.draft(4, title: "Unrelated")]) : a
        }
        #expect(Synthetic.failing(extra) == ["in02: parses cleanly (AC-M2-11)"])
        let interrupted = try Synthetic.run(.ds1Offline) { i, a in
            guard Self.ds1Subset.contains(i) else { return nil }
            return i == 1 ? Synthetic.attempt(i, drafts: Synthetic.rightDrafts(i, items: 3), outcome: .interrupted) : a
        }
        #expect(Synthetic.failing(interrupted) == ["in01: parses cleanly (AC-M2-11)"])
        let four = try Synthetic.rejection(.ds1Offline) { i, a in Self.ds1Subset.contains(i) || i == 3 ? a : nil }
        guard case let .subsetMismatch(mismatch)? = four else {
            Issue.record("4 inputs under ds1-offline are not rejected: \(String(describing: four))")
            return
        }
        #expect(mismatch.found.map(\.description) == ["in01 (text)", "in02 (voice)", "in03 (text)", "in10 (voice)"])
    }

    @Test("ds2-offline (AC-M2-25): in08 (voice), in16 (voice), each noModel with nothing committed")
    func ds2Offline() throws {
        let offline: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, _ in
            Self.ds2Subset.contains(i) ? Synthetic.attempt(i, drafts: [], route: .gemini, outcome: .noModel) : nil
        }
        let right = try Synthetic.run(.ds2Offline, provider: .gemini, edit: offline)
        #expect(right.passes, "\(Synthetic.failing(right))")
        let parsed = try Synthetic.run(.ds2Offline, provider: .gemini) { i, a in Self.ds2Subset.contains(i) ? a : nil }
        #expect(Synthetic.failing(parsed) == ["in08: noModel, no task created (AC-M2-25)",
                                              "in16: noModel, no task created (AC-M2-25)"])
    }

    @Test("ds2-online (AC-M2-25): in08 (voice), in16 (voice) through the provider, each parsed cleanly; a text input is refused")
    func ds2Online() throws {
        let two: (Int, EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? = { i, a in
            Self.ds2Subset.contains(i) ? a : nil
        }
        let right = try Synthetic.run(.ds2Online, provider: .openai, edit: two)
        #expect(right.passes, "\(Synthetic.failing(right))")
        let missing = try Synthetic.run(.ds2Online, provider: .openai) { i, a in
            guard Self.ds2Subset.contains(i) else { return nil }
            return i == 16 ? Synthetic.attempt(i, drafts: Array(Synthetic.rightDrafts(i, items: 3).prefix(2)),
                                               route: .openai) : a
        }
        #expect(Synthetic.failing(missing) == ["in16: parses cleanly (AC-M2-25)"])
        let textInput = try Synthetic.rejection(.ds2Online, provider: .openai) { i, a in [1, 8].contains(i) ? a : nil }
        guard case let .subsetMismatch(mismatch)? = textInput else {
            Issue.record("a text input under ds2-online is not rejected: \(String(describing: textInput))")
            return
        }
        // Review N1: the content, not only the case.
        #expect(mismatch.found.map(\.description) == ["in01 (text)", "in08 (voice)"])
        #expect(mismatch.reason == "the inputs are not the fixed ds2-online subset (AC-M2-25, PO ruling F3): it takes "
            + "exactly in08 (voice), in16 (voice); the file has in01 (text), in08 (voice); not in the subset: "
            + "in01 (text); not in the file: in16 (voice)")
    }

    // MARK: A-F1: the subset profiles take exactly their fixed input IDs and modes (PO ruling F4)

    /// One A-F1 case: a profile, the input numbers in the file and the inputs whose mode is flipped in the fixtures.
    struct SubsetCase: Sendable, CustomTestStringConvertible {
        var profile: EvalProfile
        var inputs: Set<Int>
        var flipped: Set<Int> = []
        var label: String
        var testDescription: String { "\(profile.rawValue): \(label)" }

        var provider: EvalProvider? {
            switch profile {
            case .ds2Offline: .gemini
            case .ds2Online: .openai
            default: nil
            }
        }

        /// The attempt each kept input gets: the right one for the profile (noModel for ds2-offline).
        func edit(_ i: Int, _ a: EvalResultsFileV1.InputAttempt) -> EvalResultsFileV1.InputAttempt? {
            guard inputs.contains(i) else { return nil }
            guard profile == .ds2Offline else { return a }
            return Synthetic.attempt(i, drafts: [], route: .gemini, outcome: .noModel, flipped: flipped)
        }
    }

    static let pinned: [(EvalProfile, [String])] = [
        (.ds1Offline, ["in01 (text)", "in02 (voice)", "in10 (voice)"]),
        (.ds2Offline, ["in08 (voice)", "in16 (voice)"]),
        (.ds2Online, ["in08 (voice)", "in16 (voice)"]),
    ]

    @Test("A-F1: the subsets are pinned in the profiles (PO ruling F3); the whole-set profiles have none")
    func pinnedSubsets() {
        for (profile, inputs) in Self.pinned {
            #expect(profile.subset?.map(\.description) == inputs, "\(profile.rawValue)")
        }
        for profile in [EvalProfile.ds1Gated, .ds2Gated, .info] { #expect(profile.subset == nil) }
    }

    static let rightCases: [SubsetCase] = [
        SubsetCase(profile: .ds1Offline, inputs: ds1Subset, label: "in01, in02, in10"),
        SubsetCase(profile: .ds2Offline, inputs: ds2Subset, label: "in08, in16"),
        SubsetCase(profile: .ds2Online, inputs: ds2Subset, label: "in08, in16"),
    ]

    @Test("A-F1: the fixed subset is scored and passes", arguments: rightCases)
    func rightSubset(_ c: SubsetCase) throws {
        let result = try Synthetic.run(c.profile, provider: c.provider, edit: c.edit)
        #expect(result.passes, "\(Synthetic.failing(result))")
    }

    static let refusedCases: [SubsetCase] = [
        // Right count, right modes, wrong IDs.
        SubsetCase(profile: .ds1Offline, inputs: [1, 2, 4], label: "right count, wrong ID: in04 (voice) for in10"),
        SubsetCase(profile: .ds1Offline, inputs: [3, 2, 10], label: "right count, wrong ID: in03 (text) for in01"),
        SubsetCase(profile: .ds1Offline, inputs: [1, 8, 16], label: "right count, wrong ID: the DS-2 voice inputs"),
        SubsetCase(profile: .ds2Offline, inputs: [2, 10], label: "right count, wrong ID: the DS-1 voice inputs"),
        SubsetCase(profile: .ds2Offline, inputs: [8, 14], label: "right count, wrong ID: in14 (voice) for in16"),
        SubsetCase(profile: .ds2Online, inputs: [2, 10], label: "right count, wrong ID: the DS-1 voice inputs"),
        SubsetCase(profile: .ds2Online, inputs: [17, 16], label: "right count, wrong ID: in17 (voice) for in08"),
        // Right IDs, wrong mode (the fixtures say so too, so the file is otherwise consistent).
        SubsetCase(profile: .ds1Offline, inputs: ds1Subset, flipped: [10], label: "wrong mode: in10 (text)"),
        SubsetCase(profile: .ds1Offline, inputs: ds1Subset, flipped: [1], label: "wrong mode: in01 (voice)"),
        SubsetCase(profile: .ds2Offline, inputs: ds2Subset, flipped: [16], label: "wrong mode: in16 (text)"),
        SubsetCase(profile: .ds2Online, inputs: ds2Subset, flipped: [8], label: "wrong mode: in08 (text)"),
        // Wrong count.
        SubsetCase(profile: .ds1Offline, inputs: [1, 2], label: "too few: in10 absent"),
        SubsetCase(profile: .ds1Offline, inputs: [1, 2, 10, 4], label: "too many: in04 added"),
        SubsetCase(profile: .ds2Offline, inputs: [8], label: "too few: in16 absent"),
        SubsetCase(profile: .ds2Online, inputs: [8, 16, 2], label: "too many: in02 added"),
        SubsetCase(profile: .ds2Online, inputs: Set(1...20), label: "the whole set"),
    ]

    @Test("A-F1: any other file is refused (exit 2) with a plain reason naming the IDs and modes", arguments: refusedCases)
    func refusedSubset(_ c: SubsetCase) throws {
        let error = try Synthetic.rejection(c.profile, provider: c.provider, flipped: c.flipped, edit: c.edit)
        guard case let .subsetMismatch(mismatch)? = error else {
            Issue.record("not refused as a subset mismatch: \(String(describing: error))")
            return
        }
        let required = try #require(c.profile.subset)
        let found = c.inputs.sorted().map { EvalSubsetInput(Synthetic.inputID($0), Synthetic.mode($0, flipped: c.flipped)) }
        #expect(mismatch == EvalSubsetMismatch(profile: c.profile, required: required, found: found))
        let reason = mismatch.reason
        #expect(reason.contains(c.profile.rawValue))
        for input in required + found { #expect(reason.contains(input.description), "\(input)") }
        let words = Set(reason.lowercased().split { !$0.isLetter }.map(String.init))
        #expect(words.isDisjoint(with: ["overdue", "late", "missed", "failed", "behind", "penalty"]), "\(reason)")
    }

    @Test("A-F1 (review F1): a voice retake of in02 (attempts 1 and 2) is one input; the ds1-offline file is scored, attempt 2")
    func retakeIsOneInput() throws {
        let request = try Synthetic.request(.ds1Offline, retakes: [2]) { i, a in Self.ds1Subset.contains(i) ? a : nil }
        let report = try EvalScorer.run(request)
        #expect(report.file.inputs.filter { $0.inputID == "in02" }.map(\.attempt) == [1, 2])
        #expect(report.profileResult.passes, "\(Synthetic.failing(report.profileResult))")
        let in02 = try #require(report.score.inputs.first { $0.inputID == "in02" })
        #expect(in02.attempt == 2 && in02.attemptsInFile == 2)
        #expect(report.log.contains(
            "check PASS: inputs in01 (text), in02 (voice), in10 (voice) (AC-M2-11): file has in01 (text), in02 (voice), "
                + "in10 (voice)\n"))
        // A retake of an input outside the subset is still refused.
        let outside = try Synthetic.rejection(.ds1Offline, retakes: [4]) { i, a in [1, 2, 4].contains(i) ? a : nil }
        guard case let .subsetMismatch(mismatch)? = outside else {
            Issue.record("a retake outside the subset is not refused: \(String(describing: outside))")
            return
        }
        #expect(mismatch.found.map(\.description) == ["in01 (text)", "in02 (voice)", "in04 (voice)"])
    }

    /// Review F1: the exact reason for each note kind (not in the subset, not in the file, mode difference).
    static let exactReasons: [(SubsetCase, String)] = [
        (SubsetCase(profile: .ds1Offline, inputs: [1, 2, 4], label: "wrong ID: both notes"),
         "the inputs are not the fixed ds1-offline subset (AC-M2-11, PO ruling F3): it takes exactly in01 (text), "
            + "in02 (voice), in10 (voice); the file has in01 (text), in02 (voice), in04 (voice); not in the subset: "
            + "in04 (voice); not in the file: in10 (voice)"),
        (SubsetCase(profile: .ds1Offline, inputs: [1, 2, 10, 4], label: "too many: not in the subset only"),
         "the inputs are not the fixed ds1-offline subset (AC-M2-11, PO ruling F3): it takes exactly in01 (text), "
            + "in02 (voice), in10 (voice); the file has in01 (text), in02 (voice), in04 (voice), in10 (voice); "
            + "not in the subset: in04 (voice)"),
        (SubsetCase(profile: .ds2Offline, inputs: [8], label: "too few: not in the file only"),
         "the inputs are not the fixed ds2-offline subset (AC-M2-25, PO ruling F3): it takes exactly in08 (voice), "
            + "in16 (voice); the file has in08 (voice); not in the file: in16 (voice)"),
        (SubsetCase(profile: .ds2Online, inputs: ds2Subset, flipped: [16], label: "wrong mode: mode note only"),
         "the inputs are not the fixed ds2-online subset (AC-M2-25, PO ruling F3): it takes exactly in08 (voice), "
            + "in16 (voice); the file has in08 (voice), in16 (text); in16 is text in the file, the subset takes it "
            + "as voice"),
        (SubsetCase(profile: .ds1Offline, inputs: ds1Subset, flipped: [1], label: "wrong mode: in01 voice"),
         "the inputs are not the fixed ds1-offline subset (AC-M2-11, PO ruling F3): it takes exactly in01 (text), "
            + "in02 (voice), in10 (voice); the file has in01 (voice), in02 (voice), in10 (voice); in01 is voice in "
            + "the file, the subset takes it as text"),
    ]

    @Test("A-F1 (review F1): the exact reason text for each note kind", arguments: exactReasons)
    func exactReason(_ c: SubsetCase, reason: String) throws {
        let error = try Synthetic.rejection(c.profile, provider: c.provider, flipped: c.flipped, edit: c.edit)
        guard case let .subsetMismatch(mismatch)? = error else {
            Issue.record("not refused as a subset mismatch: \(String(describing: error))")
            return
        }
        #expect(mismatch.reason == reason)
    }

    @Test("A-F1 (review N2): only the subset profiles name an AC for the subset")
    func subsetACs() {
        #expect(EvalProfile.allCases.map(\.subsetAC) == [nil, "AC-M2-11", "AC-M2-25", "AC-M2-25", nil, nil])
    }

    @Test("A-F1: the profile check also holds the subset (second control) when the reader is bypassed")
    func profileCheckSecondControl() throws {
        let request = try Synthetic.request(.info) { i, a in [1, 2, 4].contains(i) ? a : nil }
        let report = try EvalScorer.run(request)
        let fixtures = try EvalFixtures(inputs: request.inputs, household: request.household, golden: request.golden)
        let result = EvalProfileChecks.evaluate(.ds1Offline, file: report.file, score: report.score,
                                                fixtures: fixtures, allowedKeyPaths: nil)
        #expect(Synthetic.failing(result) == ["inputs in01 (text), in02 (voice), in10 (voice) (AC-M2-11)"])
        let detail = result.checks.first { !$0.holds }?.detail
        #expect(detail == "file has in01 (text), in02 (voice), in04 (voice)")
    }

    @Test("A-F1: the scorer log prints the input IDs and modes of a subset run")
    func subsetLog() throws {
        let report = try EvalScorer.run(try Synthetic.request(.ds2Online, provider: .openai) { i, a in
            Self.ds2Subset.contains(i) ? a : nil
        })
        #expect(report.log.contains(
            "check PASS: inputs in08 (voice), in16 (voice) (AC-M2-25): file has in08 (voice), in16 (voice)\n"))
        #expect(report.log.contains("input in08: voice,") && report.log.contains("input in16: voice,"))
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

// D-059 per provider: the sent body's counts against that provider's G1 golden body.
extension EvalProfileTests {
    /// A ds2-gated run whose every request carries the counts of `body(i)`, checked against `golden`.
    static func providerCountsRun(golden: Data, body: @escaping (Int) -> Data) throws -> EvalProfileResult {
        try cloudRun(goldenBody: golden) { i, a in
            var copy = a
            copy.cloudRequests = [Self.request(counts: CloudRequestKeyPaths.arrayCounts(ofBody: body(i)),
                                               content: Self.contentCounts())]
            return copy
        }
    }

    /// The fixed top-level array of each provider's body and one more element for it.
    static let extraElement: [CloudProvider: (anchor: String, insert: String, path: String)] = [
        .openAI: (#""messages":["#, #"{"role":"user","content":[]},"#, "$.messages"),
        .anthropic: (#""messages":["#, #"{"role":"user","content":[]},"#, "$.messages"),
        .gemini: (#""contents":["#, #"{"role":"user","parts":[]},"#, "$.contents"),
    ]

    @Test("D-059: the G1, G2 and G3 bodies of each provider pass against its G1 golden body; one extra element in a fixed array stops ds2-gated",
          arguments: CloudProvider.allCases)
    func providerExtraElement(provider: CloudProvider) throws {
        let golden = try GoldenArrayCountsTests.body("g1-outcome-empty", provider)
        for name in GoldenArrayCountsTests.goldenCases {
            let same = try GoldenArrayCountsTests.body(name, provider)
            #expect(try Self.providerCountsRun(golden: golden) { _ in same }.passes, "\(name)")
        }
        let extra = try #require(Self.extraElement[provider])
        let text = String(decoding: golden, as: UTF8.self)
        #expect(text.components(separatedBy: extra.anchor).count == 2, "the anchor is in the body once")
        let mutated = Data(text.replacingOccurrences(of: extra.anchor, with: extra.anchor + extra.insert).utf8)
        let expected = try #require(CloudRequestKeyPaths.arrayCounts(ofBody: golden)?.first { $0.path == extra.path })
        let result = try Self.providerCountsRun(golden: golden) { i in i == 4 ? mutated : golden }
        #expect(Synthetic.failing(result) == [Self.countsName])
        let detail = result.checks.first { $0.name == Self.countsName }?.detail ?? ""
        #expect(detail.contains("in04 attempt 1 request 1: \(extra.path) expected \(expected.count), seen \(expected.count + 1)"),
                "\(detail)")
    }
}

// Tester D-059 re-check F1: the count and key-path checks cover every attempt, retakes included.
extension EvalProfileTests {
    static let keyPathsName = "sent key paths are a subset of the allowed list (AC-M2-26)"

    @Test("D-059 F1: only in02 attempt 1 (retaken) sends an extra message and rooms 99; ds2-gated still stops, naming input, attempt, path, expected, seen")
    func countsOnRetakenAttempt() throws {
        let golden = try Self.goldenCounts()
        let good = try Self.cloudRun(retakes: [2])
        #expect(good.passes, "a retake with a right first attempt passes")
        let result = try Self.cloudRun(retakes: [2], firstAttempt: { i, first in
            guard i == 2 else { return first }
            var bad = golden
            if let index = bad.firstIndex(where: { $0.path == "$.messages" }) { bad[index].count += 1 }
            var copy = first
            copy.cloudRequests = [Self.request(counts: bad, content: Self.contentCounts(rooms: 99))]
            return copy
        })
        #expect(!result.passes)
        #expect(Synthetic.failing(result) == [Self.countsName])
        let detail = result.checks.first { $0.name == Self.countsName }?.detail ?? ""
        #expect(detail.contains("in02 attempt 1 request 1: $.messages expected 1, seen 2"), "\(detail)")
        #expect(detail.contains("in02 attempt 1 request 1: user content $.rooms expected 1, seen 99"), "\(detail)")
        #expect(!detail.contains("in02 attempt 2"), "\(detail)")
    }

    @Test("D-059 F1: a key path outside the allowed list on a retaken first attempt stops ds2-gated, naming the attempt")
    func keyPathsOnRetakenAttempt() throws {
        let counts = try Self.goldenCounts()
        let result = try Self.cloudRun(retakes: [2], firstAttempt: { i, first in
            guard i == 2 else { return first }
            var copy = first
            copy.cloudRequests = [Self.request(keyPaths: ["$.messages[].content", "$.model", "$.secret"],
                                               counts: counts, content: Self.contentCounts())]
            return copy
        })
        #expect(Synthetic.failing(result) == [Self.keyPathsName])
        let detail = result.checks.first { $0.name == Self.keyPathsName }?.detail ?? ""
        #expect(detail == "outside: in02 attempt 1 request 1: $.secret", "\(detail)")
    }
}

// Tester D-059 re-check F3: one extra element in a nested fixed array (a content part, an enum value) stops ds2-gated.
extension EvalProfileTests {
    /// A nested insertion: after the `occurrence`-th (1-based) `anchor` in the body, `insert` adds one element to the
    /// array at `path`.
    struct NestedPlant: Sendable {
        let provider: CloudProvider
        let anchor: String
        let occurrence: Int
        let insert: String
        let path: String
    }

    static let effortEnum = #""effort":{"enum":["low","normal","high""#

    static let nestedPlants: [NestedPlant] = [
        NestedPlant(provider: .anthropic, anchor: #""content":["#, occurrence: 1,
                    insert: #"{"type":"text","text":"x"},"#, path: "$.messages[0].content"),
        NestedPlant(provider: .openAI, anchor: #""content":["#, occurrence: 2,
                    insert: #"{"type":"text","text":"x"},"#, path: "$.messages[1].content"),
        NestedPlant(provider: .gemini, anchor: #""parts":["#, occurrence: 1,
                    insert: #"{"text":"x"},"#, path: "$.contents[0].parts"),
        NestedPlant(provider: .gemini, anchor: effortEnum, occurrence: 1, insert: #","extra""#,
                    path: "$.generationConfig.responseJsonSchema.properties.items.items.properties.effort.enum"),
        NestedPlant(provider: .anthropic, anchor: effortEnum, occurrence: 1, insert: #","extra""#,
                    path: "$.tools[0].input_schema.properties.items.items.properties.effort.enum"),
        NestedPlant(provider: .openAI, anchor: effortEnum, occurrence: 1, insert: #","extra""#,
                    path: "$.response_format.json_schema.schema.properties.items.items.properties.effort.enum"),
    ]

    static func inserting(_ plant: NestedPlant, into text: String) -> String? {
        let parts = text.components(separatedBy: plant.anchor)
        guard parts.count > plant.occurrence else { return nil }
        let head = parts[..<plant.occurrence].joined(separator: plant.anchor)
        let tail = parts[plant.occurrence...].joined(separator: plant.anchor)
        return head + plant.anchor + plant.insert + tail
    }

    @Test("D-059 F3: one extra element in a nested fixed array (content part, parts, enum value) stops ds2-gated, naming the path",
          arguments: nestedPlants.indices)
    func nestedExtraElement(index: Int) throws {
        let plant = Self.nestedPlants[index]
        let golden = try GoldenArrayCountsTests.body("g1-outcome-empty", plant.provider)
        let text = String(decoding: golden, as: UTF8.self)
        let mutated = try #require(Self.inserting(plant, into: text))
        let counts = try #require(CloudRequestKeyPaths.arrayCounts(ofBody: Data(mutated.utf8)), "still strict JSON")
        let expected = try #require(CloudRequestKeyPaths.arrayCounts(ofBody: golden)?.first { $0.path == plant.path })
        #expect(counts.first { $0.path == plant.path }?.count == expected.count + 1, "the plant adds one element")
        let result = try Self.providerCountsRun(golden: golden) { i in i == 4 ? Data(mutated.utf8) : golden }
        #expect(Synthetic.failing(result) == [Self.countsName])
        let detail = result.checks.first { $0.name == Self.countsName }?.detail ?? ""
        #expect(detail.contains("in04 attempt 1 request 1: \(plant.path) expected \(expected.count), seen \(expected.count + 1)"),
                "\(detail)")
    }
}

