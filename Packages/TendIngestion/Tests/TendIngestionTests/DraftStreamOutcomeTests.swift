// AC-M2-10 and AC-M2-23 (Linux parts): the calm typed outcomes for each neutral reason, the input text returned in
// memory, the plain-note draft, and calm case names. FR-A1, P-1, P-3, P-4, UX-3. Plan WI-M2-06.
//
// The neutral reasons are what the adapters map to (WI-M2-M2 on-device, WI-M2-M4 cloud, on the owner-run Mac). The
// brief's cases and the reason each is expected to map to:
//
// | Brief case (AC-M2-10 / AC-M2-23)              | Neutral reason                                  |
// |-----------------------------------------------|-------------------------------------------------|
// | device not eligible                           | OnDeviceUnavailableReason.deviceNotEligible     |
// | Apple Intelligence not enabled                | .appleIntelligenceNotEnabled                    |
// | model not ready                               | .modelNotReady                                  |
// | unsupported language or locale (availability) | .unsupportedLocale                              |
// | guardrail                                     | ModelStopReason.guardrail                       |
// | context too long                              | .contextTooLong                                 |
// | any other generation error                    | .otherModelError (and the other on-device ones) |
// | offline                                       | .offline                                        |
// | timeout                                       | .timedOut                                       |
// | DNS failure                                   | .hostNotFound                                   |
// | TLS failure                                   | .secureConnectionUnavailable                    |
// | 401 or 403 bad key                            | .keyNotAccepted                                 |
// | 429 rate limit                                | .rateLimited                                    |
// | 5xx                                           | .serviceUnavailable                             |
// | malformed body                                | .unreadableOutput                               |
// | provider refusal                              | .refusal                                        |

import Foundation
import Testing
import TendCore
import TendSourceScan
@testable import TendIngestion

enum OutcomeFixtures {
    typealias F = StreamFixtures

    /// The plain note for `F.input`, written out from the brief: the user's words trimmed, the Q5 defaults, no
    /// inference (T1 window `[now, now + 7 days)`).
    static func plainNote(_ title: String, now: Date = F.now) -> IngestionDraft {
        IngestionDraft(
            draftID: 1, title: title, kind: .oneOff, room: .none, effort: .normal, isCritical: false,
            isDeepClean: false, isWeatherDependent: false, allowedDayparts: [.morning, .afternoon, .evening],
            allowedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
            windowStart: now, windowEnd: now.addingTimeInterval(604_800), recurrenceIntervalDays: nil,
            sourcePhrase: nil, duplicate: .none
        )
    }

    static let onDeviceStopReasons: [ModelStopReason] = [
        .guardrail, .contextTooLong, .unsupportedLanguage, .assetsUnavailable, .busy, .rateLimited,
        .unreadableOutput, .refusal, .otherModelError,
    ]

    static let cloudStopReasons: [ModelStopReason] = [
        .offline, .timedOut, .hostNotFound, .secureConnectionUnavailable, .keyNotAccepted, .rateLimited,
        .serviceUnavailable, .unreadableOutput, .refusal, .outputCutShort,
    ]

    /// Scripts that throw before the first draft is emitted (T-25): at once, after a skipped item, and with an item
    /// in progress.
    static func beforeFirstDraft(_ reason: ModelStopReason) -> [(String, [ScriptStep])] {
        [
            ("at once", [.stop(reason)]),
            ("after an empty snapshot", [.snapshot([]), .stop(reason)]),
            ("after a skipped item", [.snapshot([ItemSnapshot(kind: .known(.oneOff)), F.titleOnly("Serv")]),
                                      .stop(reason)]),
            ("with an item in progress", [.snapshot([F.titleOnly("Buy dish")]), .stop(reason)]),
        ]
    }
}

@Suite("AC-M2-10 noModel for each neutral reason (FR-A1, P-1, P-3, UX-3)")
struct NoModelOutcomeTests {
    typealias F = StreamFixtures
    typealias O = OutcomeFixtures

    @Test("AC-M2-10: cloud off and on-device unavailable (each reason): route none, noModel, input and plain note returned, no model asked, nothing written",
          arguments: OnDeviceUnavailableReason.allCases)
    func unavailable(_ reason: OnDeviceUnavailableReason) async {
        var events: [DraftStreamEvent] = []
        for await event in F.pipeline().events(from: .none(reason)) { events.append(event) }
        let expected = DraftStreamOutcome.noModel(route: .none, reason: .onDeviceUnavailable(reason), input: F.input,
                                                  plainNote: O.plainNote(F.input))
        #expect(events == [.finished(expected)])
        #expect(events.allSatisfy { if case .emitted = $0 { false } else { true } })
        print("AC-M2-10 \(reason): \(events)")
    }

    @Test("AC-M2-10: on-device generation throws before the first draft (each reason, cloud on or off): route stays onDevice, noModel, input and plain note returned, the model is asked once",
          arguments: OutcomeFixtures.onDeviceStopReasons)
    func throwsBeforeFirstDraft(_ reason: ModelStopReason) async {
        for (label, steps) in O.beforeFirstDraft(reason) {
            let model = ScriptedModel(steps)
            var events: [DraftStreamEvent] = []
            for await event in F.pipeline().events(from: .onDevice(model)) { events.append(event) }
            let finished = DraftStreamEvent.finished(.noModel(
                route: .onDevice, reason: .stoppedBeforeFirstDraft(reason), input: F.input,
                plainNote: O.plainNote(F.input)))
            #expect(events.last == finished, "\(reason) \(label)")
            #expect(!events.contains { if case .emitted = $0 { true } else { false } }, "\(reason) \(label)")
            // The route never changes to the cloud: the pipeline holds only this one model and asks it once.
            #expect(model.requestCount == 1, "\(reason) \(label)")
            print("AC-M2-10 \(reason) \(label): \(events.map(Ev.init))")
        }
    }

    @Test("AC-M2-10 / T-25: a throw after the first draft is interrupted, not noModel, and the route stays onDevice",
          arguments: OutcomeFixtures.onDeviceStopReasons)
    func throwsAfterFirstDraft(_ reason: ModelStopReason) async {
        let events = await F.pipelineEvents([.snapshot([F.full("Buy dishwasher pods"), F.titleOnly("S")]),
                                             .stop(reason)])
        #expect(events.map(Ev.init) == [.emitted(1, "Buy dishwasher pods"),
                                        .finished(F.interrupted(reason, discarded: .stoppedBeforeComplete))])
    }

    @Test("AC-M2-10: a foreign error type thrown before the first draft is noModel(otherModelError)")
    func foreignError() async {
        let events = await F.pipelineEvents([.stop(CocoaError(.fileNoSuchFile))])
        #expect(events == [.finished(.noModel(route: .onDevice, reason: .stoppedBeforeFirstDraft(.otherModelError),
                                              input: F.input, plainNote: O.plainNote(F.input)))])
    }
}

@Suite("AC-M2-23 cloud failure outcomes and the plain note (FR-A1, P-3, P-4, UX-3)")
struct CloudOutcomeTests {
    typealias F = StreamFixtures
    typealias O = OutcomeFixtures

    struct Cell: Sendable, CustomTestStringConvertible {
        let provider: CloudProvider
        let reason: ModelStopReason
        var testDescription: String { "\(provider) \(reason)" }
    }

    static let cells: [Cell] = CloudProvider.allCases.flatMap { provider in
        OutcomeFixtures.cloudStopReasons.map { Cell(provider: provider, reason: $0) }
    }

    @Test("AC-M2-23: each cloud failure before any draft: noModel with the route, the input and a plain note; the model is asked once (no retry here, nothing queued)", arguments: cells)
    func beforeAnyDraft(_ cell: Cell) async {
        for (label, steps) in O.beforeFirstDraft(cell.reason) {
            let model = ScriptedModel(steps)
            var events: [DraftStreamEvent] = []
            for await event in F.pipeline().events(from: .cloud(cell.provider, model)) { events.append(event) }
            #expect(events.last == .finished(.noModel(
                route: .cloud(cell.provider), reason: .stoppedBeforeFirstDraft(cell.reason), input: F.input,
                plainNote: O.plainNote(F.input))), "\(cell.testDescription) \(label)")
            #expect(model.requestCount == 1)
        }
    }

    @Test("AC-M2-23: each cloud failure after a draft: interrupted with the route and the input; no plain note; the emitted draft stays", arguments: cells)
    func afterADraft(_ cell: Cell) async {
        let model = ScriptedModel([.snapshot([F.full("Buy dishwasher pods"), F.titleOnly("Serv")]),
                                   .stop(cell.reason)])
        var summary = DraftStreamSummary()
        for await event in F.pipeline().events(from: .cloud(cell.provider, model)) { summary.apply(event) }
        #expect(summary.outcome == F.interrupted(cell.reason, discarded: .stoppedBeforeComplete,
                                                 route: .cloud(cell.provider)))
        #expect(summary.outcome?.plainNote == nil)
        #expect(summary.outcome?.input == F.input)
        #expect(summary.drafts.map(\.title) == ["Buy dishwasher pods"])
        #expect(model.requestCount == 1)
    }

    @Test("AC-M2-23: the same plain-note offer exists when the route is none")
    func routeNone() async {
        var summary = DraftStreamSummary()
        for await event in F.pipeline().events(from: .none(.deviceNotEligible)) { summary.apply(event) }
        #expect(summary.outcome?.route == Route.none)
        #expect(summary.outcome?.plainNote == O.plainNote(F.input))
        #expect(summary.drafts.isEmpty)   // the plain note is an offer, not an emitted draft
    }
}

@Suite("Plain note (brief Definitions; AC-M2-10, AC-M2-23; UX-1, UX-3)")
struct PlainNoteTests {
    typealias F = StreamFixtures
    typealias O = OutcomeFixtures

    static func make(_ input: String, now: Date = F.now) -> IngestionDraft? {
        PlainNote.draft(for: input, now: now, calendar: MappingFixtures.gregorian,
                        timeZone: MappingFixtures.zone("America/New_York"))
    }

    @Test("Plain note: the user's own words, trimmed at both ends only, with the Q5 default fields and no inference",
          arguments: [
            ("  mop the kitchen floor \n", "mop the kitchen floor"),
            ("buy pods,\n\n  and   call the plumber", "buy pods,\n\n  and   call the plumber"),
            ("Bathroom: deep clean, weekly, critical!", "Bathroom: deep clean, weekly, critical!"),
          ])
    func userWords(_ input: String, _ title: String) throws {
        let note = try #require(Self.make(input))
        #expect(note == O.plainNote(title))
        #expect(note.room == .none && note.kind == .oneOff && !note.isCritical && !note.isDeepClean)
    }

    @Test("Plain note: banned tokens the user said are kept, because they are the user's words (UX-3, AC-M2-12)")
    func userBannedWordsKept() throws {
        let note = try #require(Self.make("I'm late paying the gas bill"))
        #expect(note.title == "I'm late paying the gas bill")
    }

    @Test("Plain note: a blank input gives no plain note", arguments: ["", "   ", "\n\t "])
    func blank(_ input: String) {
        #expect(Self.make(input) == nil)
    }

    @Test("Plain note: it passes the M1 initialiser and becomes an active task only through commit")
    func passesInitialiser() throws {
        let note = try #require(Self.make("water the plants"))
        let task = try note.task(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)), roomID: nil)
        #expect(task.title == "water the plants" && task.state == .active)
    }

    @Test("Plain note: a non-finite now gives no plain note instead of an invalid draft")
    func nonFiniteNow() {
        // Compared to a Bool first: describing a NaN `Date` in a failure message traps on Linux (WI-M2-05 round 2).
        let nanGivesNil = Self.make("water the plants", now: Date(timeIntervalSinceReferenceDate: .nan)) == nil
        let infinityGivesNil = Self.make("water the plants", now: Date(timeIntervalSinceReferenceDate: .infinity)) == nil
        #expect(nanGivesNil)
        #expect(infinityGivesNil)
    }

    @Test("PO WI-M2-06 ruling 1: a blank input with an empty output gives completed with the input and no plain note")
    func blankInputCompleted() async {
        let events = await F.pipelineEvents([.snapshot([]), .finish], input: "  ")
        #expect(events == [.finished(.completed(route: .onDevice, input: "  ", plainNote: nil))])
    }

    @Test("PO WI-M2-06 ruling 1: completed with no draft carries the input and plain note on every route",
          arguments: [nil] + CloudProvider.allCases.map(Optional.some))
    func completedNoDraftEveryRoute(_ provider: CloudProvider?) async {
        let route: Route = provider.map(Route.cloud) ?? .onDevice
        var summary = DraftStreamSummary()
        for event in await F.pipelineEvents([.snapshot([ItemSnapshot(isCritical: true)]), .finish], cloud: provider) {
            summary.apply(event)
        }
        #expect(summary.outcome == .completed(route: route, input: F.input, plainNote: O.plainNote(F.input)))
        #expect(summary.outcome?.input == F.input && summary.outcome?.plainNote == O.plainNote(F.input))
        #expect(summary.drafts.isEmpty && summary.skipped == [.noTitle])   // the note is an offer, not a draft
    }

    @Test("Plain note: a blank input gives noModel with no plain note, and the input is still returned")
    func blankInputOutcome() async {
        var events: [DraftStreamEvent] = []
        for await event in F.pipeline(input: "  ").events(from: .none(.modelNotReady)) { events.append(event) }
        #expect(events == [.finished(.noModel(route: .none, reason: .onDeviceUnavailable(.modelNotReady),
                                              input: "  ", plainNote: nil))])
    }
}

@Suite("Calm names and the commit order (AC-M2-10, AC-M2-12, AC-M2-23; UX-3; PO WI-M2-04 ruling 2)")
struct DraftStreamNamesTests {
    typealias F = StreamFixtures

    /// Every outcome, reason and event name, split at camelCase like the AC-M1-02 scan, has no banned token.
    static var allNames: [String] {
        let outcomes: [DraftStreamOutcome] = [
            .completed(route: .onDevice), .completed(route: .onDevice, input: "", plainNote: nil),
            .cancelled(route: .none),
            .interrupted(route: .cloud(.openAI), reason: .offline, discardedItem: .stoppedBeforeComplete, input: ""),
            .noModel(route: .none, reason: .onDeviceUnavailable(.modelNotReady), input: "", plainNote: nil),
            .noModel(route: .onDevice, reason: .stoppedBeforeFirstDraft(.guardrail), input: "", plainNote: nil),
        ]
        let events: [DraftStreamEvent] = [.itemSkipped(.noTitle), .finished(.completed(route: .onDevice))]
        var names: [String] = ModelStopReason.allCases.map { "\($0)" }
        names += OnDeviceUnavailableReason.allCases.map { "\($0)" }
        names += DiscardedItemReason.allCases.map { "\($0)" }
        names += CloudProvider.allCases.map { "\($0)" }
        names += outcomes.map { "\($0)" }
        names += events.map { "\($0)" }
        let routes: [Route] = [.onDevice, .cloud(.gemini), .none]
        names += routes.map { "\($0)" }
        return names
    }

    @Test("AC-M2-10 / AC-M2-23: no outcome, reason or event name contains a banned token")
    func calmNames() {
        let banned = Set(BannedTokens.all)
        for name in Self.allNames {
            let words = name.split { !$0.isLetter }.flatMap { SourceScanner.subTokens(of: String($0)) }
            let hits = words.map { $0.lowercased() }.filter(banned.contains)
            #expect(hits.isEmpty, "\(name): \(hits)")
        }
        print("AC-M2-10/23 names checked: \(Self.allNames.count): \(Self.allNames.joined(separator: " | "))")
    }

    @Test("AC-M2-23: the neutral reason lists are complete (every case is in a brief mapping)")
    func reasonListsComplete() {
        let listed = Set(OutcomeFixtures.onDeviceStopReasons + OutcomeFixtures.cloudStopReasons)
        #expect(listed == Set(ModelStopReason.allCases))
        #expect(OnDeviceUnavailableReason.allCases.count == 4)
        #expect(CloudProvider.allCases == [.openAI, .anthropic, .gemini])
    }

    @Test("D6 (PO WI-M2-04 ruling 2): the summary keeps the latest version of each draft, in ascending draftID")
    func summaryOrder() {
        var summary = DraftStreamSummary()
        let events = F.assemble([
            .snapshot([F.full("Buy"), F.full("Serv")]),
            .snapshot([F.full("Buy dishwasher pods"), F.full("Service the AC"), F.titleOnly("Mop")]),
            .finish,
        ])
        for event in events { summary.apply(event) }
        #expect(summary.drafts.map(\.draftID) == [1, 2, 3])
        #expect(summary.drafts.map(\.title) == ["Buy dishwasher pods", "Service the AC", "Mop"])
        #expect(summary.outcome == .completed(route: .onDevice))
        #expect(summary.skipped.isEmpty)
        // Applying an event after finished changes nothing.
        summary.apply(.emitted(OutcomeFixtures.plainNote("late")))
        #expect(summary.drafts.count == 3)
    }

    @Test("Outcome accessors: route, input and plain note per outcome")
    func accessors() {
        let note = OutcomeFixtures.plainNote("x")
        let noModel = DraftStreamOutcome.noModel(route: .none, reason: .onDeviceUnavailable(.modelNotReady),
                                                 input: "x", plainNote: note)
        #expect(noModel.route == .none && noModel.input == "x" && noModel.plainNote == note)
        let interrupted = DraftStreamOutcome.interrupted(route: .onDevice, reason: .busy, discardedItem: nil,
                                                         input: "y")
        #expect(interrupted.input == "y" && interrupted.plainNote == nil)
        #expect(DraftStreamOutcome.completed(route: .cloud(.openAI)).input == nil)
        #expect(DraftStreamOutcome.completed(route: .cloud(.openAI)).plainNote == nil)
        let completedNoDraft = DraftStreamOutcome.completed(route: .onDevice, input: "x", plainNote: note)
        #expect(completedNoDraft.input == "x" && completedNoDraft.plainNote == note
                && completedNoDraft.route == .onDevice)
        #expect(DraftStreamOutcome.cancelled(route: .onDevice).input == nil)
        #expect(DraftStreamOutcome.cancelled(route: .onDevice).route == .onDevice)
    }
}
