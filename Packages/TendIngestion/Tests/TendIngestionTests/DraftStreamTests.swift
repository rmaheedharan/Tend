// AC-M2-05 (Linux part): stream assembly over neutral snapshots obeys the brief's "draft stream events" and "item
// completion" rules exactly. FR-A1, UX-3. Plan WI-M2-06.
//
// The oracle is a scripted list of snapshots with the exact event list expected (AC-M2-05, last bullet). Every
// scripted case runs twice: through the pure `DraftStreamAssembler` and through the public `DraftPipeline` with a mock
// `IngestionModel` that replays the same script as an `AsyncThrowingStream`. Both must give the expected list.
//
// Expected events are written by hand as (event, draftID, title) plus the outcome; the Q5 content of a draft is
// AC-M2-01/02's job, so a case compares whole drafts only where completion repairs matter (finish mid-item).

import Foundation
import Synchronization
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Shared script support

/// One step of a scripted model output.
enum ScriptStep: Sendable {
    case snapshot([ItemSnapshot])
    case finish
    case stop(any Error & Sendable)
}

/// A mock on-device or cloud model that replays a script (no clock, no I/O). Records how often it was asked.
final class ScriptedModel: IngestionModel {
    let steps: [ScriptStep]
    private let requests = Mutex<[IngestionRequest]>([])

    init(_ steps: [ScriptStep]) { self.steps = steps }

    var requestCount: Int { requests.withLock { $0.count } }
    var lastRequest: IngestionRequest? { requests.withLock { $0.last } }

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        requests.withLock { $0.append(request) }
        let steps = self.steps
        return AsyncThrowingStream { continuation in
            for step in steps {
                switch step {
                case let .snapshot(items):
                    continuation.yield(IngestionSnapshot(items: items))
                case .finish:
                    continuation.finish()
                    return
                case let .stop(error):
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
    }
}

/// A compact, hand-writable form of an event, for the oracle tables.
enum Ev: Equatable, Sendable, CustomStringConvertible {
    case emitted(Int, String, DraftDuplicate = .none)
    case updated(Int, String, DraftDuplicate = .none)
    case skipped(ItemSkipReason)
    case finished(DraftStreamOutcome)

    init(_ event: DraftStreamEvent) {
        switch event {
        case let .emitted(draft): self = .emitted(draft.draftID, draft.title, draft.duplicate)
        case let .updated(draft): self = .updated(draft.draftID, draft.title, draft.duplicate)
        case let .itemSkipped(reason): self = .skipped(reason)
        case let .finished(outcome): self = .finished(outcome)
        }
    }

    var description: String {
        switch self {
        case let .emitted(id, title, dup): "emitted(\(id), \(title), \(dup))"
        case let .updated(id, title, dup): "updated(\(id), \(title), \(dup))"
        case let .skipped(reason): "skipped(\(reason))"
        case let .finished(outcome): "finished(\(outcome))"
        }
    }
}

enum StreamFixtures {
    static let input = "we're almost out of dishwasher pods, the AC needs servicing, and mop the kitchen floor"
    static let now = MappingFixtures.newYorkNow

    static func mapper(input: String = input) -> DraftMapper {
        MappingFixtures.mapper(input: input)
    }

    static func pipeline(input: String = input, check: any DraftDuplicateCheck = NoDuplicateCheck()) -> DraftPipeline {
        DraftPipeline(input: input, rooms: MappingFixtures.rooms, now: now, calendar: MappingFixtures.gregorian,
                      timeZone: MappingFixtures.zone("America/New_York"), duplicateCheck: check)
    }

    /// An item with a value for every schema field (completion rule (a)).
    static func full(_ title: String?, room: String? = "Kitchen", sourcePhrase: String? = "dishwasher pods")
        -> ItemSnapshot {
        MappingFixtures.item(title: title, room: room, time: MappingFixtures.hint(anchor: "none"),
                             sourcePhrase: sourcePhrase)
    }

    /// An item with only a title (still in progress under rule (a)).
    static func titleOnly(_ title: String?) -> ItemSnapshot {
        ItemSnapshot(title: title)
    }

    /// Runs a script through the pure assembler.
    static func assemble(_ steps: [ScriptStep], route: Route = .onDevice, input: String = input,
                         check: any DraftDuplicateCheck = NoDuplicateCheck()) -> [DraftStreamEvent] {
        var assembler = DraftStreamAssembler(mapper: mapper(input: input), duplicateCheck: check, route: route)
        var events: [DraftStreamEvent] = []
        for step in steps {
            switch step {
            case let .snapshot(items): events += assembler.receive(IngestionSnapshot(items: items))
            case .finish: events += assembler.finishNormally(); return events
            case let .stop(error): events += assembler.stop(error); return events
            }
        }
        events += assembler.finishNormally()
        return events
    }

    /// Runs a script through the public pipeline and a scripted mock model.
    static func pipelineEvents(_ steps: [ScriptStep], cloud provider: CloudProvider? = nil, input: String = input,
                               check: any DraftDuplicateCheck = NoDuplicateCheck()) async -> [DraftStreamEvent] {
        let model = ScriptedModel(steps)
        let routed: RoutedModel = provider.map { .cloud($0, model) } ?? .onDevice(model)
        var events: [DraftStreamEvent] = []
        // No `try`: the sequence's Failure is Never (the brief: "an AsyncSequence that never throws").
        for await event in pipeline(input: input, check: check).events(from: routed) {
            events.append(event)
        }
        return events
    }

    static func interrupted(_ reason: ModelStopReason, discarded: DiscardedItemReason?, route: Route = .onDevice,
                            input: String = input) -> DraftStreamOutcome {
        .interrupted(route: route, reason: reason, discardedItem: discarded, input: input)
    }
}

/// A scripted duplicate check for the tests: a draft whose title equals an earlier draft's title is `ofDraft` of the
/// first such draft. (The real rules are WI-M2-07's; the stream only calls the injected check.)
struct SameTitleCheck: DraftDuplicateCheck {
    func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate {
        earlier.first { $0.title == draft.title }.map { .ofDraft($0.draftID) } ?? .none
    }
}

/// One call of the duplicate hook.
struct Call: Equatable, Sendable {
    let draftID: Int
    let earlier: [Int]
}

/// Records every call of the duplicate hook; marks each draft as a duplicate of the draft just before it.
final class RecordingCheck: DraftDuplicateCheck {
    private let log = Mutex<[Call]>([])
    var calls: [Call] { log.withLock { $0 } }

    func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate {
        log.withLock { $0.append(Call(draftID: draft.draftID, earlier: earlier.map(\.draftID))) }
        return earlier.last.map { .ofDraft($0.draftID) } ?? .none
    }
}

// MARK: - AC-M2-05 scripted oracle

@Suite("AC-M2-05 draft stream events over neutral snapshots (FR-A1)")
struct DraftStreamTests {
    typealias F = StreamFixtures

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let steps: [ScriptStep]
        let expected: [Ev]
        var testDescription: String { name }
    }

    static let pods = "Buy dishwasher pods"
    static let service = "Service the AC"
    static let mop = "Mop the kitchen floor"

    static let cases: [Case] = [
        Case(
            name: "fields arrive out of order; emitted once, at the snapshot where the last field arrives (rule a)",
            steps: [
                .snapshot([ItemSnapshot(kind: .known(.restock), effort: .known(.low))]),
                .snapshot([ItemSnapshot(kind: .known(.restock), roomName: "Kitchen", effort: .known(.low),
                                        sourcePhrase: "dishwasher pods")]),
                .snapshot([ItemSnapshot(title: pods, kind: .known(.restock), roomName: "Kitchen",
                                        effort: .known(.low), isCritical: false, isDeepClean: false,
                                        sourcePhrase: "dishwasher pods")]),
                .snapshot([ItemSnapshot(title: pods, kind: .known(.restock), roomName: "Kitchen",
                                        effort: .known(.low), isCritical: false, isDeepClean: false,
                                        isWeatherDependent: false, time: MappingFixtures.hint(anchor: "none"),
                                        sourcePhrase: "dishwasher pods")]),
                .finish,
            ],
            expected: [.emitted(1, pods), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "an item split across snapshots: emitted at completion, then updated with the same ID",
            steps: [
                .snapshot([F.full("Buy")]),
                .snapshot([F.full("Buy dish")]),
                .snapshot([F.full("Buy dish")]),          // no change: no event
                .snapshot([F.full(pods)]),
                .finish,
            ],
            expected: [.emitted(1, "Buy"), .updated(1, "Buy dish"), .updated(1, pods),
                       .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "the next item starting completes the previous one (rule b)",
            steps: [
                .snapshot([F.titleOnly("Buy dish")]),
                .snapshot([F.titleOnly(pods)]),
                .snapshot([F.titleOnly(pods), F.titleOnly("Serv")]),
                .snapshot([F.titleOnly(pods), F.titleOnly(service), F.titleOnly("M")]),
                .snapshot([F.titleOnly(pods), F.titleOnly(service), F.titleOnly(mop)]),
                .finish,
            ],
            expected: [.emitted(1, pods), .emitted(2, service), .emitted(3, mop),
                       .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "an item with no title is skipped with a typed reason and takes no draftID",
            steps: [
                .snapshot([ItemSnapshot(kind: .known(.oneOff))]),
                .snapshot([ItemSnapshot(kind: .known(.oneOff)), F.titleOnly(service)]),
                .snapshot([ItemSnapshot(title: "   ", kind: .known(.oneOff)), F.titleOnly(service),
                           F.titleOnly(mop)]),
                .finish,
            ],
            expected: [.skipped(.noTitle), .emitted(1, service), .emitted(2, mop),
                       .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a stream that finishes normally mid-item completes and emits that item (rule c)",
            steps: [
                .snapshot([F.full(pods), F.titleOnly("Mop the")]),
                .snapshot([F.full(pods), F.titleOnly(mop)]),
                .finish,
            ],
            expected: [.emitted(1, pods), .emitted(2, mop), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a stream that finishes normally mid-item with no title skips it",
            steps: [
                .snapshot([F.full(pods), ItemSnapshot(kind: .known(.oneOff))]),
                .finish,
            ],
            expected: [.emitted(1, pods), .skipped(.noTitle), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a stream that throws mid-item discards it; earlier drafts stay; interrupted",
            steps: [
                .snapshot([F.full(pods), F.titleOnly("Serv")]),
                .snapshot([F.full(pods), F.titleOnly(service)]),
                .stop(ModelStopReason.outputCutShort),
            ],
            expected: [.emitted(1, pods),
                       .finished(F.interrupted(.outputCutShort, discarded: .stoppedBeforeComplete))]
        ),
        Case(
            name: "a stream that throws between items: interrupted with nothing discarded",
            steps: [
                .snapshot([F.full(pods)]),
                .stop(ModelStopReason.serviceUnavailable),
            ],
            expected: [.emitted(1, pods), .finished(F.interrupted(.serviceUnavailable, discarded: nil))]
        ),
        Case(
            name: "an error that is not a neutral reason counts as otherModelError",
            steps: [
                .snapshot([F.full(pods), F.titleOnly("Se")]),
                .stop(CocoaError(.featureUnsupported)),
            ],
            expected: [.emitted(1, pods),
                       .finished(F.interrupted(.otherModelError, discarded: .stoppedBeforeComplete))]
        ),
        Case(
            name: "emission follows model-output order, not the order of sourcePhrase in the input",
            steps: [
                .snapshot([F.titleOnly(mop), F.titleOnly(pods)]),
                .finish,
            ],
            expected: [.emitted(1, mop), .emitted(2, pods), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "several items completing in one snapshot are emitted in output order",
            steps: [
                .snapshot([F.titleOnly(pods), F.titleOnly(service), F.titleOnly("Mo")]),
                .finish,
            ],
            expected: [.emitted(1, pods), .emitted(2, service), .emitted(3, "Mo"),
                       .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a draft is never withdrawn: a later blank title or a shrinking snapshot gives no event",
            steps: [
                .snapshot([F.full(pods), F.titleOnly("Serv")]),
                .snapshot([F.full("  "), F.titleOnly("Serv")]),   // the re-map would skip: the draft stays
                .snapshot([]),                                      // fewer items: nothing withdrawn
                .snapshot([F.full(pods), F.titleOnly(service)]),
                .finish,
            ],
            expected: [.emitted(1, pods), .emitted(2, service), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "updates come before new emissions within one snapshot, in draftID order",
            steps: [
                .snapshot([F.full("Buy"), F.full("Serv"), F.titleOnly("M")]),
                .snapshot([F.full(pods), F.full(service), F.titleOnly(mop), F.titleOnly("x")]),
                .finish,
            ],
            expected: [.emitted(1, "Buy"), .emitted(2, "Serv"), .updated(1, pods), .updated(2, service),
                       .emitted(3, mop), .emitted(4, "x"), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a skipped item stays skipped even if a later snapshot gives it a title",
            steps: [
                .snapshot([ItemSnapshot(kind: .known(.oneOff)), F.titleOnly("Serv")]),
                .snapshot([F.titleOnly(pods), F.titleOnly(service)]),
                .finish,
            ],
            expected: [.skipped(.noTitle), .emitted(1, service), .finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "no items at all: completed with no draft",
            steps: [.snapshot([]), .finish],
            expected: [.finished(.completed(route: .onDevice))]
        ),
        Case(
            name: "a title calmed by the guard is emitted calm; an unsaid banned token never reaches an event",
            steps: [
                .snapshot([F.full("Late mop the kitchen floor")]),
                .finish,
            ],
            expected: [.emitted(1, "mop the kitchen floor"), .finished(.completed(route: .onDevice))]
        ),
    ]

    @Test("AC-M2-05: the scripted snapshots give exactly the expected event list (pure assembler)",
          arguments: cases)
    func scriptedAssembler(_ testCase: Case) {
        let events = F.assemble(testCase.steps).map(Ev.init)
        #expect(events == testCase.expected, "\(testCase.name)")
        print("AC-M2-05 [assembler] \(testCase.name): \(events)")
    }

    @Test("AC-M2-05: the scripted snapshots give exactly the expected event list (DraftPipeline, mock model)",
          arguments: cases)
    func scriptedPipeline(_ testCase: Case) async {
        let events = await F.pipelineEvents(testCase.steps).map(Ev.init)
        #expect(events == testCase.expected, "\(testCase.name)")
        print("AC-M2-05 [pipeline] \(testCase.name): \(events)")
    }

    @Test("AC-M2-05: an item still in progress at a normal finish is completed and repaired by Q5 before emission")
    func finishRepairsInProgressItem() throws {
        // Only a title, with stray whitespace: Q5 fills every missing field (kind one-off, effort normal, room none,
        // flags false, the T1 window, default dayparts, all weekdays).
        let partial = ItemSnapshot(title: "  Mop   the kitchen floor ")
        let events = F.assemble([.snapshot([F.full(Self.pods), partial]), .finish])
        try #require(events.count == 3)
        guard case let .emitted(draft) = events[1] else {
            Issue.record("expected emitted, got \(events[1])")
            return
        }
        let expected = F.mapper().map(partial, draftID: 2)
        #expect(expected.outcome == .draft(draft))
        #expect(expected.repairs.contains(.kindDefaulted) && expected.repairs.contains(.effortDefaulted))
        #expect(draft.title == Self.mop)
        #expect(draft.kind == .oneOff && draft.effort == .normal && draft.room == .none)
        #expect(!draft.isCritical && !draft.isDeepClean && !draft.isWeatherDependent)
        #expect(draft.windowStart == F.now && draft.windowEnd == F.now.addingTimeInterval(604_800))
        #expect(draft.allowedDayparts == Daypart.defaultAllowed && draft.allowedWeekdays == Set(Weekday.allCases))
        #expect(throws: Never.self) { try draft.task(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                                                     roomID: nil) }
    }

    @Test("AC-M2-05: emitted and updated drafts are whole replacements with the same ID; finished comes once, last")
    func eventShapeRules() throws {
        let events = F.assemble([
            .snapshot([F.full("Buy")]),
            .snapshot([F.full(Self.pods, room: "garage")]),
            .snapshot([F.full(Self.pods, room: "garage"), F.titleOnly(Self.service)]),
            .finish,
        ])
        guard case let .emitted(first) = events[0], case let .updated(second) = events[1] else {
            Issue.record("unexpected shape \(events)")
            return
        }
        #expect(first.draftID == 1 && second.draftID == 1)
        #expect(first.room == .existing(MappingFixtures.kitchen.id))
        #expect(second.room == .proposed("garage"))   // full replacement: every field is the new mapping
        #expect(second.title == Self.pods)
        #expect(events.filter { if case .finished = $0 { true } else { false } }.count == 1)
        if case .finished = try #require(events.last) {} else { Issue.record("finished is not last") }
    }

    @Test("AC-M2-05: nothing follows finished; later input to the assembler is ignored")
    func nothingAfterFinished() {
        var assembler = DraftStreamAssembler(mapper: F.mapper(), duplicateCheck: NoDuplicateCheck(), route: .onDevice)
        _ = assembler.receive(IngestionSnapshot(items: [F.full(Self.pods)]))
        #expect(assembler.finishNormally().map(Ev.init) == [.finished(.completed(route: .onDevice))])
        #expect(assembler.receive(IngestionSnapshot(items: [F.full(Self.pods), F.full(Self.mop)])).isEmpty)
        #expect(assembler.finishNormally().isEmpty)
        #expect(assembler.stop(ModelStopReason.offline).isEmpty)
        #expect(assembler.isFinished)
    }

    @Test("AC-M2-05: the duplicate marker is set once, before emitted, and an update keeps it (WI-M2-07 hook contract)")
    func duplicateMarkerSetAtEmission() {
        let steps: [ScriptStep] = [
            .snapshot([F.full("Buy"), F.full(Self.pods)]),
            .snapshot([F.full(Self.pods), F.full(Self.pods)]),                   // draft 2 keeps .none
            .snapshot([F.full(Self.pods), F.full(Self.pods), F.full(Self.pods)]),
            .snapshot([F.full(Self.mop), F.full(Self.pods), F.full(Self.pods)]), // draft 3 keeps .ofDraft(1)
            .finish,
        ]
        let expected: [Ev] = [
            .emitted(1, "Buy"), .emitted(2, Self.pods),
            .updated(1, Self.pods),
            .emitted(3, Self.pods, .ofDraft(1)),
            .updated(1, Self.mop),
            .finished(.completed(route: .onDevice)),
        ]
        #expect(F.assemble(steps, check: SameTitleCheck()).map(Ev.init) == expected)
    }

    @Test("AC-M2-05: the duplicate hook is called exactly once per draft position, in output order, before emitted, with the earlier drafts")
    func duplicateHookContract() {
        let check = RecordingCheck()
        let events = F.assemble([
            .snapshot([F.full("Buy"), ItemSnapshot(kind: .known(.oneOff)), F.titleOnly("Serv")]),
            .snapshot([F.full(Self.pods), ItemSnapshot(kind: .known(.oneOff)), F.titleOnly(Self.service),
                       F.titleOnly("M")]),
            .snapshot([F.full(Self.pods), ItemSnapshot(kind: .known(.oneOff)), F.titleOnly(Self.service),
                       F.titleOnly(Self.mop)]),
            .finish,
        ], check: check)
        // Skipped items take no position; updates do not call the hook.
        #expect(check.calls == [Call(draftID: 1, earlier: []), Call(draftID: 2, earlier: [1]),
                                Call(draftID: 3, earlier: [1, 2])])
        // Each emitted draft already carries the hook's marker (the hook ran before emitted).
        let emittedMarkers = events.compactMap { if case let .emitted(d) = $0 { d.duplicate } else { nil } }
        #expect(emittedMarkers == [.none, .ofDraft(1), .ofDraft(2)])
        #expect(events.contains { if case .updated = $0 { true } else { false } })
    }

    @Test("AC-M2-05: the model is asked once, with the capture text and the household's room names")
    func modelRequest() async {
        let model = ScriptedModel([.snapshot([F.full(Self.pods)]), .finish])
        for await _ in F.pipeline().events(from: .onDevice(model)) {}
        #expect(model.requestCount == 1)
        #expect(model.lastRequest == IngestionRequest(input: F.input, roomNames: ["Kitchen", "Bathroom"]))
    }

    @Test("AC-M2-05: the sequence is lazy (no model call before iteration) and each iteration is a fresh parse")
    func lazyAndRepeatable() async {
        let model = ScriptedModel([.snapshot([F.titleOnly(Self.pods)]), .finish])
        let sequence = F.pipeline().events(from: .onDevice(model))
        #expect(model.requestCount == 0)
        var first: [Ev] = []
        for await event in sequence { first.append(Ev(event)) }
        var second: [Ev] = []
        for await event in sequence { second.append(Ev(event)) }
        #expect(first == [.emitted(1, Self.pods), .finished(.completed(route: .onDevice))])
        #expect(second == first)
        #expect(model.requestCount == 2)
    }

    @Test("AC-M2-05: after finished, the iterator returns nil")
    func iteratorEndsAfterFinished() async {
        let model = ScriptedModel([.snapshot([F.titleOnly(Self.pods)]), .finish])
        var iterator = F.pipeline().events(from: .onDevice(model)).makeAsyncIterator()
        var events: [Ev] = []
        while let event = await iterator.next() { events.append(Ev(event)) }
        #expect(events == [.emitted(1, Self.pods), .finished(.completed(route: .onDevice))])
        #expect(await iterator.next() == nil)
        #expect(await iterator.next() == nil)
    }

    @Test("AC-M2-05: every outcome carries the route (on-device and each cloud provider)",
          arguments: [nil] + CloudProvider.allCases.map(Optional.some))
    func outcomeCarriesRoute(_ provider: CloudProvider?) async {
        let route: Route = provider.map(Route.cloud) ?? .onDevice
        let completed = await F.pipelineEvents([.snapshot([F.full(Self.pods)]), .finish], cloud: provider)
        #expect(completed.last == .finished(.completed(route: route)))
        let interrupted = await F.pipelineEvents([.snapshot([F.full(Self.pods)]), .stop(ModelStopReason.timedOut)],
                                                 cloud: provider)
        #expect(interrupted.last == .finished(F.interrupted(.timedOut, discarded: nil, route: route)))
        if case let .finished(outcome) = interrupted.last { #expect(outcome.route == route) }
    }
}

// MARK: - AC-M2-05 cancellation

/// How the model's stream ended, shared between its termination handler and the test.
final class EndRecord: Sendable {
    let value = Mutex<String?>(nil)
}

/// A model whose stream the test drives by hand. The stream is handed out once and not kept, so dropping the
/// pipeline's iterator ends it; `terminations` reports how it ended (the model side of cooperative cancellation).
final class ControlledModel: IngestionModel {
    private let pending: Mutex<AsyncThrowingStream<IngestionSnapshot, any Error>?>
    let continuation: AsyncThrowingStream<IngestionSnapshot, any Error>.Continuation
    let terminations: AsyncStream<String>
    private let calls = Mutex(0)
    /// Set synchronously by the termination handler, so a test can check it while the iterator is still alive.
    private let ended: EndRecord

    init() {
        let (stream, continuation) = AsyncThrowingStream<IngestionSnapshot, any Error>.makeStream()
        let (terminations, report) = AsyncStream<String>.makeStream()
        let ended = EndRecord()
        continuation.onTermination = { termination in
            let text = switch termination {
            case .cancelled: "cancelled"
            case .finished: "finished"
            @unknown default: "unknown"
            }
            ended.value.withLock { $0 = text }
            report.yield(text)
            report.finish()
        }
        self.ended = ended
        self.pending = Mutex(stream)
        self.continuation = continuation
        self.terminations = terminations
    }

    var callCount: Int { calls.withLock { $0 } }
    var endedHow: String? { ended.value.withLock { $0 } }

    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        calls.withLock { $0 += 1 }
        return pending.withLock { slot in
            defer { slot = nil }
            return slot ?? AsyncThrowingStream { $0.finish() }
        }
    }
}

/// Runs `body` in its own task (so it can cancel itself without cancelling the test) and passes the test's own
/// cancellation on to it. A test that hits its time limit is cancelled; the consumer then ends with `cancelled` and the
/// test fails on its expectations instead of hanging.
func consumeInOwnTask<Result: Sendable>(_ body: @escaping @Sendable () async -> Result) async -> Result {
    let task = Task(operation: body)
    return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
}

/// What `cancelReleasesModelAtOnce` observed while it still held the iterator.
struct Held: Sendable {
    var events: [Ev]
    var endedWhileHeld: String?
    var afterFinished: Ev?
}

@Suite("AC-M2-05 cancellation is cooperative and ends with cancelled (FR-A1)")
struct DraftStreamCancellationTests {
    typealias F = StreamFixtures

    @Test("AC-M2-05: cancelling the consuming task while it waits for the model ends the sequence with cancelled; earlier events stay, nothing is written, the model stream is ended", .timeLimit(.minutes(1)))
    func cancelWhileWaiting() async throws {
        let model = ControlledModel()
        let (seen, seenSignal) = AsyncStream<Void>.makeStream()
        let pipeline = F.pipeline()
        let household = Household(tasks: [], rooms: MappingFixtures.rooms)
        let repository = InMemoryHouseholdRepository()
        try await repository.save(household)
        let consumer = Task {
            var events: [Ev] = []
            for await event in pipeline.events(from: .onDevice(model)) {
                events.append(Ev(event))
                seenSignal.yield()
            }
            return events
        }
        // If the time limit cancels this test, cancel the consumer too, so a broken rule fails instead of hanging.
        let stopConsumer: @Sendable () -> Void = { consumer.cancel() }
        model.continuation.yield(IngestionSnapshot(items: [F.full("Buy dishwasher pods"), F.titleOnly("Serv")]))
        var waiter = seen.makeAsyncIterator()
        _ = await withTaskCancellationHandler { await waiter.next() } onCancel: { stopConsumer() }  // emitted(1)
        consumer.cancel()
        let events = await consumer.value
        #expect(events == [.emitted(1, "Buy dishwasher pods"), .finished(.cancelled(route: .onDevice))])
        var ends = model.terminations.makeAsyncIterator()
        #expect(await ends.next() == "cancelled")
        #expect(model.callCount == 1)
        #expect(try await repository.load() == household)  // the pipeline has no write path; nothing changed
        // A snapshot sent after cancellation is never seen.
        model.continuation.yield(IngestionSnapshot(items: [F.full("Late")]))
    }

    @Test("AC-M2-05: a consumer that cancels itself mid-stream gets cancelled as the very next event; buffered events are dropped and the model stream is ended", .timeLimit(.minutes(1)))
    func cancelFromInsideTheLoop() async {
        let model = ControlledModel()
        // One snapshot completes three items at once (rule b), so two events are still buffered after the first.
        model.continuation.yield(IngestionSnapshot(items: [
            F.titleOnly("Buy dishwasher pods"), F.titleOnly("Service the AC"), F.titleOnly("Mop the kitchen floor"),
            F.titleOnly("x"),
        ]))
        let pipeline = F.pipeline()
        let events = await consumeInOwnTask {
            var events: [Ev] = []
            for await event in pipeline.events(from: .onDevice(model)) {
                events.append(Ev(event))
                if events.count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return events
        }
        #expect(events == [.emitted(1, "Buy dishwasher pods"), .finished(.cancelled(route: .onDevice))])
        var ends = model.terminations.makeAsyncIterator()
        #expect(await ends.next() == "cancelled")
    }

    @Test("AC-M2-05: the cancelled event already releases the model stream, while the consumer still holds the iterator", .timeLimit(.minutes(1)))
    func cancelReleasesModelAtOnce() async {
        let model = ControlledModel()
        model.continuation.yield(IngestionSnapshot(items: [F.titleOnly("Buy dishwasher pods"), F.titleOnly("S")]))
        let sequence = F.pipeline().events(from: .onDevice(model))
        let result = await consumeInOwnTask {
            var iterator = sequence.makeAsyncIterator()
            var events: [Ev] = []
            if let first = await iterator.next() { events.append(Ev(first)) }
            withUnsafeCurrentTask { $0?.cancel() }
            if let second = await iterator.next() { events.append(Ev(second)) }
            // The iterator is still alive here; the model's stream must already be ended.
            let endedWhileHeld = model.endedHow
            let afterFinished = await iterator.next()   // also keeps `iterator` alive until after the check
            return Held(events: events, endedWhileHeld: endedWhileHeld, afterFinished: afterFinished.map(Ev.init))
        }
        #expect(result.events == [.emitted(1, "Buy dishwasher pods"), .finished(.cancelled(route: .onDevice))])
        #expect(result.endedWhileHeld == "cancelled")
        #expect(result.afterFinished == nil)
    }

    @Test("AC-M2-05: a task cancelled before it starts gets only finished(cancelled); the model is never asked",
          arguments: [Route.onDevice, .cloud(.anthropic), .none])
    func cancelBeforeStart(_ route: Route) async {
        let model = ControlledModel()
        let routed: RoutedModel = switch route {
        case .onDevice: .onDevice(model)
        case let .cloud(provider): .cloud(provider, model)
        case .none: .none(.modelNotReady)
        }
        let pipeline = F.pipeline()
        let events = await consumeInOwnTask {
            withUnsafeCurrentTask { $0?.cancel() }
            var events: [Ev] = []
            for await event in pipeline.events(from: routed) { events.append(Ev(event)) }
            return events
        }
        #expect(events == [.finished(.cancelled(route: route))])
        #expect(model.callCount == 0)
    }

    @Test("AC-M2-05: the model stream finishing after cancellation still gives cancelled, never completed",
          .timeLimit(.minutes(1)))
    func cancelledBeatsLateFinish() async {
        let model = ControlledModel()
        model.continuation.yield(IngestionSnapshot(items: [F.full("Buy dishwasher pods")]))
        model.continuation.finish()
        let pipeline = F.pipeline()
        let events = await consumeInOwnTask {
            var events: [Ev] = []
            for await event in pipeline.events(from: .onDevice(model)) {
                events.append(Ev(event))
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return events
        }
        #expect(events == [.emitted(1, "Buy dishwasher pods"), .finished(.cancelled(route: .onDevice))])
    }

    @Test("AC-M2-05: the assembler's cancel gives cancelled with the route, and nothing after it")
    func assemblerCancel() {
        var assembler = DraftStreamAssembler(mapper: F.mapper(), duplicateCheck: NoDuplicateCheck(),
                                             route: .cloud(.gemini))
        _ = assembler.receive(IngestionSnapshot(items: [F.full("Buy dishwasher pods"), F.titleOnly("S")]))
        #expect(assembler.cancel().map(Ev.init) == [.finished(.cancelled(route: .cloud(.gemini)))])
        #expect(assembler.finishNormally().isEmpty)
        #expect(assembler.cancel().isEmpty)
    }
}
