// The on-device `IngestionModel` and source over scripted generations (WI-M2-M2; AC-M2-05, AC-M2-07, AC-M2-10 Mac
// halves; `IngestionModel` adapter contract items 1-4). FR-A1, P-1, P-3, UX-3.
// The pipeline under the adapter is the real `TendIngestion` `DraftPipeline` with the real on-device duplicate rules.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

@Suite("On-device model (WI-M2-M2; AC-M2-05, 07, 10)")
struct OnDeviceModelTests {

    private func titles(_ events: [DraftStreamEvent]) -> [String] {
        events.compactMap { if case let .emitted(draft) = $0 { draft.title } else { nil } }
    }

    private func count(_ events: [DraftStreamEvent], where test: (DraftStreamEvent) -> Bool) -> Int {
        events.filter(test).count
    }

    private static let empty = Household(tasks: [], rooms: [])

    @Test("AC-M2-05: \"Later: call the plumber\" streamed in small steps gives one emitted with the whole title, never a skip",
          arguments: [1, 2, 3, 5])
    func latePrefixEndToEnd(step: Int) async {
        let json = OnDeviceJSON.answer([
            OnDeviceJSON.item(title: "Later: call the plumber", sourcePhrase: "later call the plumber"),
            OnDeviceJSON.item(title: "Buy dish pods", kind: "restock"),
        ])
        let steps = OnDeviceJSON.growingPartials(json, step: step).map(GenerationStep.answer)
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "Later call the plumber, and buy dish pods",
                                                   household: Self.empty, model: model)
        #expect(titles(events) == ["Later: call the plumber", "Buy dish pods"])
        #expect(count(events) { if case .itemSkipped = $0 { true } else { false } } == 0)
        #expect(count(events) { if case .updated = $0 { true } else { false } } == 0)
        #expect(events.last == .finished(.completed(route: .onDevice)))
    }

    @Test("AC-M2-05: emission happens at completion: the first draft is emitted before the second item is written")
    func emittedAtCompletion() async throws {
        let first = OnDeviceJSON.item(title: "Buy pods")
        let steps: [GenerationStep] = [
            .answer(try OnDeviceJSON.partial(String(OnDeviceJSON.answer([first]).dropLast(2)))),
            .answer(try OnDeviceJSON.partial(#"{"items":["# + first + #",{"title":"Mop"#)),
            .hang,
        ]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let pipeline = DraftPipeline(input: "buy pods, mop", rooms: [], now: OnDeviceFixtures.now,
                                     calendar: OnDeviceFixtures.calendar, timeZone: OnDeviceFixtures.utc,
                                     duplicateCheck: DraftDuplicateRules.onDevice(household: Self.empty))
        var iterator = pipeline.events(from: .onDevice(model)).makeAsyncIterator()
        let event = await iterator.next()
        guard case let .emitted(draft)? = event else {
            Issue.record("expected the first emission, got \(String(describing: event))")
            return
        }
        #expect(draft.draftID == 1 && draft.title == "Buy pods")
    }

    @Test("AC-M2-05: an item in progress when the stream finishes normally is completed (rule c) and repaired (Q5)")
    func finishMidItem() async throws {
        let steps: [GenerationStep] = [.answer(try OnDeviceJSON.partial(#"{"items":[{"title":"Mop the floor","#
                                                                         + #""sourcePhrase":"mo"#))]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "mop the floor", household: Self.empty, model: model)
        #expect(titles(events) == ["Mop the floor"])
        #expect(events.last == .finished(.completed(route: .onDevice)))
    }

    @Test("AC-M2-05: at a normal finish the last answer's last string is whole (rule c), so its item is emitted")
    func finishAfterTitle() async throws {
        let steps: [GenerationStep] = [.answer(try OnDeviceJSON.partial(#"{"items":[{"title":"Mop the floor""#))]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "mop the floor", household: Self.empty, model: model)
        #expect(titles(events) == ["Mop the floor"])
        #expect(events.last == .finished(.completed(route: .onDevice)))
    }

    @Test("AC-M2-05: a throw mid-item after a draft gives interrupted; the item in progress is discarded")
    func throwMidItem() async throws {
        let first = OnDeviceJSON.item(title: "Buy pods")
        let steps: [GenerationStep] = [
            .answer(try OnDeviceJSON.partial(#"{"items":["# + first + #",{"title":"Mop the fl"#)),
            .fail(LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: ""))),
        ]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "buy pods, mop the floor", household: Self.empty,
                                                   model: model)
        #expect(titles(events) == ["Buy pods"])
        #expect(events.last == .finished(.interrupted(route: .onDevice, reason: .guardrail,
                                                      discardedItem: .stoppedBeforeComplete,
                                                      input: "buy pods, mop the floor")))
    }

    static let stops: [(String, ModelStopReason)] = [
        ("guardrail", .guardrail), ("context", .contextTooLong), ("language", .unsupportedLanguage),
        ("assets", .assetsUnavailable), ("decoding", .unreadableOutput), ("rate", .rateLimited),
        ("concurrent", .busy), ("refusal", .refusal), ("guide", .otherModelError),
    ]

    static func generationError(_ name: String) -> LanguageModelSession.GenerationError {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "")
        return switch name {
        case "guardrail": .guardrailViolation(context)
        case "context": .exceededContextWindowSize(context)
        case "language": .unsupportedLanguageOrLocale(context)
        case "assets": .assetsUnavailable(context)
        case "decoding": .decodingFailure(context)
        case "rate": .rateLimited(context)
        case "concurrent": .concurrentRequests(context)
        case "refusal": .refusal(.init(transcriptEntries: []), context)
        default: .unsupportedGuide(context)
        }
    }

    @Test("AC-M2-10: generation that throws before the first draft ends noModel, on device, with the input and a note",
          arguments: stops.map(\.0))
    func stopBeforeFirstDraft(name: String) async throws {
        let expected = try #require(Self.stops.first { $0.0 == name }?.1)
        let steps: [GenerationStep] = [.answer(try OnDeviceJSON.partial(#"{"items":[{"title":"Bu"#)),
                                       .fail(Self.generationError(name))]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "buy pods", household: Self.empty, model: model)
        #expect(events.count == 1)
        guard case let .finished(.noModel(route, reason, input, note))? = events.last else {
            Issue.record("expected noModel, got \(events)")
            return
        }
        #expect(route == .onDevice)
        #expect(reason == .stoppedBeforeFirstDraft(expected))
        #expect(input == "buy pods")
        #expect(note?.title == "buy pods")
    }

    @Test("Contract 4: every snapshot carries the Tool's queries so far, and a final snapshot carries the last ones")
    func lookupQueries() async throws {
        let household = try LookupHouseholds.big()
        let item = OnDeviceJSON.item(title: "Buy pods", kind: "restock")
        let steps: [GenerationStep] = [
            .lookup("pods"),
            .answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item]))),
            .lookup("garage"),
        ]
        let model = OnDeviceFixtures.model(household: household, steps: steps)
        let (snapshots, end) = await OnDeviceFixtures.snapshots(of: model, input: "buy pods")
        #expect(end == nil)
        // Cumulative, in call order: each snapshot carries a prefix of the final list that holds the call made before
        // its answer (the list is read when the snapshot is made, so it may already hold a later call), and the last
        // snapshot carries both calls.
        #expect(snapshots.count == 2)
        for snapshot in snapshots {
            #expect(Array(["pods", "garage"].prefix(snapshot.lookupQueries.count)) == snapshot.lookupQueries)
            #expect(snapshot.lookupQueries.first == "pods")
        }
        #expect(snapshots.last?.lookupQueries == ["pods", "garage"])
        #expect(snapshots.last?.items.first?.title == "Buy pods")
    }

    @Test("Contract 4: a Tool call after an answer with no items still reaches a snapshot before the end")
    func lookupWithoutItems() async throws {
        let model = OnDeviceFixtures.model(household: try LookupHouseholds.big(), steps: [.lookup("pods")])
        let (snapshots, end) = await OnDeviceFixtures.snapshots(of: model, input: "pods?")
        #expect(end == nil)
        #expect(snapshots == [IngestionSnapshot(items: [], lookupQueries: ["pods"])])
    }

    @Test("AC-M2-07: a title the Tool returned marks the draft ofExisting; the Tool's log equals the final queries")
    func toolClaimMarksExisting() async throws {
        let household = try LookupHouseholds.big()
        let log = GenerationLog()
        let item = OnDeviceJSON.item(title: "Get pods", kind: "restock", sameAsExisting: "Buy pods 3")
        let steps: [GenerationStep] = [.lookup("pods"), .answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item])))]
        let model = OnDeviceFixtures.model(household: household, steps: steps, log: log)
        let events = await OnDeviceFixtures.events(input: "get pods", household: household, model: model)
        let summary = DraftStreamSummary(events)
        #expect(summary.drafts.map(\.duplicate) == [.ofExisting(OnDeviceFixtures.uuid(3))])
        // The model saw exactly the shortlist (the Tool result recorded by the script).
        #expect(log.snapshot.lookupResults
                == [DuplicateLookupTool.result(DuplicateLookup.entries(for: "pods", in: household))])
    }

    @Test("AC-M2-07: a title the Tool never returned is not a claim; the word-match floor still applies")
    func unknownTitleIgnored() async throws {
        let household = try LookupHouseholds.big()
        let item = OnDeviceJSON.item(title: "Sweep the yard", sameAsExisting: "Buy pods 3")
        let model = OnDeviceFixtures.model(household: household,
                                           steps: [.answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item])))])
        let events = await OnDeviceFixtures.events(input: "sweep the yard", household: household, model: model)
        #expect(DraftStreamSummary(events).drafts.map(\.duplicate) == [DraftDuplicate.none])
    }

    @Test("A repeat within one input collapses into its first draft (sameAsItem)")
    func inInputRepeat() async throws {
        let items = [OnDeviceJSON.item(title: "Buy pods"), OnDeviceJSON.item(title: "Pick up pods", sameAsItem: 1)]
        let model = OnDeviceFixtures.model(household: Self.empty,
                                           steps: [.answer(try OnDeviceJSON.partial(OnDeviceJSON.answer(items)))])
        let events = await OnDeviceFixtures.events(input: "buy pods, pick up pods", household: Self.empty,
                                                   model: model)
        #expect(DraftStreamSummary(events).drafts.map(\.duplicate) == [.none, .ofDraft(1)])
    }

    @Test("Contract 3 and AC-M2-05: cancelling ends with cancelled and ends the model's work")
    func cancellation() async throws {
        let log = GenerationLog()
        let first = OnDeviceJSON.item(title: "Buy pods")
        let model = OnDeviceFixtures.model(household: Self.empty,
                                           steps: [.answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([first]))),
                                                   .hang],
                                           log: log)
        let pipeline = DraftPipeline(input: "buy pods", rooms: [], now: OnDeviceFixtures.now,
                                     calendar: OnDeviceFixtures.calendar, timeZone: OnDeviceFixtures.utc,
                                     duplicateCheck: DraftDuplicateRules.onDevice(household: Self.empty))
        let task = Task {
            var events: [DraftStreamEvent] = []
            for await event in pipeline.events(from: .onDevice(model)) {
                events.append(event)
                if case .emitted = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return events
        }
        let events = await task.value
        #expect(titles(events) == ["Buy pods"])
        #expect(events.last == .finished(.cancelled(route: .onDevice)))
        // The script's stream was terminated (its termination handler cancelled the model task).
        for _ in 0..<200 where log.snapshot.terminated == 0 { await Task.yield() }
        #expect(log.snapshot.terminated == 1)
    }

    @Test("Contract 3: a stream created inside a cancelled task starts no generation and finishes at once")
    func createdCancelled() async {
        let log = GenerationLog()
        let model = OnDeviceFixtures.model(household: Self.empty, steps: [.hang], log: log)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await OnDeviceFixtures.snapshots(of: model, input: "buy pods")
        }
        let (snapshots, end) = await task.value
        #expect(snapshots.isEmpty)
        #expect(end == nil)
        #expect(log.snapshot.made.isEmpty)
        #expect(log.snapshot.prompts.isEmpty)
    }

    @Test("The source gives a model whose Tool reads exactly the capture's household")
    func sourceHousehold() async throws {
        let household = try LookupHouseholds.big()
        let log = GenerationLog()
        let source = FoundationModelsOnDeviceSource(readAvailability: { (.available, true) }) { household in
            ScriptedGeneration(household: household, steps: [.lookup("pods")], log: log)
        }
        _ = await OnDeviceFixtures.snapshots(of: source.model(household: household), input: "pods")
        #expect(log.snapshot.made == [household])
        #expect(log.snapshot.lookupResults.first?.tasks.count == 10)
    }

    @Test("Prewarm prepares the next capture's session for that household only, once (Q4)")
    func prewarm() async throws {
        let household = try LookupHouseholds.big()
        let log = GenerationLog()
        let source = FoundationModelsOnDeviceSource(readAvailability: { (.available, true) }) { household in
            ScriptedGeneration(household: household, steps: [], log: log)
        }
        await source.prewarm(household: household)
        #expect(log.snapshot.prewarmed == 1)
        #expect(log.snapshot.made.count == 1)
        _ = await OnDeviceFixtures.snapshots(of: source.model(household: household), input: "a")
        #expect(log.snapshot.made.count == 1)          // the prepared session was used
        _ = await OnDeviceFixtures.snapshots(of: source.model(household: household), input: "b")
        #expect(log.snapshot.made.count == 2)          // used once only
        await source.prewarm(household: household)
        _ = await OnDeviceFixtures.snapshots(of: source.model(household: Self.empty), input: "c")
        #expect(log.snapshot.made == [household, household, household, Self.empty])
        #expect(log.snapshot.prompts.count == 3)
    }

    @Test("The prompt sent to the model is the capture and the room names as JSON")
    func promptSent() async throws {
        let log = GenerationLog()
        let household = Household(tasks: [], rooms: [OnDeviceFixtures.room("Kitchen", 9)])
        let model = OnDeviceFixtures.model(household: household, steps: [], log: log)
        _ = await OnDeviceFixtures.snapshots(of: model, input: "wipe the counters", rooms: ["Kitchen"])
        #expect(log.snapshot.prompts == [#"{"capture":"wipe the counters","rooms":["Kitchen"]}"#])
    }

    @Test("Through the router: the on-device route uses the source's model with the capture's household (P-1)")
    func router() async throws {
        let household = try LookupHouseholds.big()
        let log = GenerationLog()
        let item = OnDeviceJSON.item(title: "Buy pods")
        let partial = try OnDeviceJSON.partial(OnDeviceJSON.answer([item]))
        let source = FoundationModelsOnDeviceSource(readAvailability: { (.available, true) }) { household in
            ScriptedGeneration(household: household, steps: [.answer(partial)], log: log)
        }
        let router = ModelRouter(onDevice: source, cloudModels: NoCloud(), consents: InMemoryCloudConsentStore(),
                                 keys: InMemoryAPIKeyStore())
        let routed = await router.events(input: "buy pods", household: household, now: OnDeviceFixtures.now,
                                         calendar: OnDeviceFixtures.calendar, timeZone: OnDeviceFixtures.utc,
                                         titleSharing: .shortlistTitles, preference: .onDeviceFirst)
        #expect(routed.route == .onDevice)
        var events: [DraftStreamEvent] = []
        for await event in routed { events.append(event) }
        #expect(titles(events) == ["Buy pods"])
        #expect(log.snapshot.made == [household])
    }

    @Test("Through the router: an unavailable on-device model with cloud off ends noModel and starts no generation")
    func routerUnavailable() async throws {
        let log = GenerationLog()
        let source = FoundationModelsOnDeviceSource(readAvailability: { (.unavailable(.modelNotReady), true) }) {
            ScriptedGeneration(household: $0, steps: [], log: log)
        }
        let router = ModelRouter(onDevice: source, cloudModels: NoCloud(), consents: InMemoryCloudConsentStore(),
                                 keys: InMemoryAPIKeyStore())
        let routed = await router.events(input: "buy pods", household: Self.empty, now: OnDeviceFixtures.now,
                                         calendar: OnDeviceFixtures.calendar, timeZone: OnDeviceFixtures.utc,
                                         titleSharing: .shortlistTitles, preference: .onDeviceFirst)
        var events: [DraftStreamEvent] = []
        for await event in routed { events.append(event) }
        guard case let .finished(.noModel(route, reason, _, _))? = events.last else {
            Issue.record("expected noModel, got \(events)")
            return
        }
        #expect(route == Route.none)
        #expect(reason == .onDeviceUnavailable(.modelNotReady))
        #expect(log.snapshot.made.isEmpty)
    }
}

/// A cloud source that must never be asked (P-1).
struct NoCloud: CloudModelSource {
    func model(for provider: CloudProvider, key: APIKey) -> any IngestionModel {
        Issue.record("the cloud was asked for a model")
        return FailingModel()
    }
}

struct FailingModel: IngestionModel {
    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error> {
        AsyncThrowingStream { $0.finish(throwing: ModelStopReason.otherModelError) }
    }
}
