// Round-2 follow-ups for the on-device adapter (WI-M2-M2): review PR #41 m1 (a framework cancel the consumer did not
// ask for is a model stop, AC-M2-05 / AC-M2-10) and the PO's R-1 ruling, option (a): the duplicate-lookup Tool is
// answered at most once per capture, enforced in code. D1 (a title claim counts only if the Tool returned it) and the
// re-mark on log growth are unchanged; the word-match floor still marks repeats (AC-M2-07).

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

@Suite("On-device follow-ups (WI-M2-M2 round 2; review PR #41 m1; PO R-1 ruling (a))")
struct OnDeviceFollowUpTests {
    private static let empty = Household(tasks: [], rooms: [])

    private func titles(_ events: [DraftStreamEvent]) -> [String] {
        events.compactMap { if case let .emitted(draft) = $0 { draft.title } else { nil } }
    }

    // MARK: m1 — cancellation

    @Test("m1: a CancellationError the consumer did not ask for, after a draft, ends interrupted (AC-M2-05)")
    func unrequestedCancelAfterDraft() async throws {
        let first = OnDeviceJSON.item(title: "Buy pods")
        let steps: [GenerationStep] = [
            .answer(try OnDeviceJSON.partial(#"{"items":["# + first + #",{"title":"Mop the fl"#)),
            .fail(CancellationError()),
        ]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "buy pods, mop the floor", household: Self.empty,
                                                   model: model)
        #expect(titles(events) == ["Buy pods"])
        #expect(events.last == .finished(.interrupted(route: .onDevice, reason: .otherModelError,
                                                      discardedItem: .stoppedBeforeComplete,
                                                      input: "buy pods, mop the floor")))
    }

    @Test("m1: a CancellationError the consumer did not ask for, before any draft, ends noModel (AC-M2-10)")
    func unrequestedCancelBeforeDraft() async throws {
        let steps: [GenerationStep] = [.answer(try OnDeviceJSON.partial(#"{"items":[{"title":"Bu"#)),
                                       .fail(CancellationError())]
        let model = OnDeviceFixtures.model(household: Self.empty, steps: steps)
        let events = await OnDeviceFixtures.events(input: "buy pods", household: Self.empty, model: model)
        guard case let .finished(.noModel(route, reason, input, note))? = events.last else {
            Issue.record("expected noModel, got \(events)")
            return
        }
        #expect(route == .onDevice)
        #expect(reason == .stoppedBeforeFirstDraft(.otherModelError))
        #expect(input == "buy pods")
        #expect(note != nil)
    }

    @Test("m1: a cancel the consumer asked for still ends cancelled, even when the framework then throws CancellationError")
    func requestedCancel() async throws {
        let log = GenerationLog()
        let first = OnDeviceJSON.item(title: "Buy pods")
        let model = OnDeviceFixtures.model(household: Self.empty,
                                           steps: [.answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([first]))),
                                                   .hang],
                                           log: log, cancelBehaviour: .throwOnCancel)
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
    }

    @Test("m1: the model stream itself finishes without an error when its parse was cancelled and the framework throws")
    func requestedCancelAtTheStream() async throws {
        let model = OnDeviceFixtures.model(household: Self.empty, steps: [.hang], cancelBehaviour: .throwOnCancel)
        let task = Task { await OnDeviceFixtures.snapshots(of: model, input: "buy pods") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let (_, end) = await task.value
        #expect(end == nil)
    }

    // MARK: PO R-1 ruling (a) — one Tool call per capture

    @Test("R-1 (a): the first Tool call is answered with the shortlist; every later call gets no entries and is not recorded")
    func secondCallRefused() async throws {
        let household = try LookupHouseholds.big()
        let recorder = DuplicateLookupRecorder(household: household)
        let tool = DuplicateLookupTool(recorder: recorder)
        let first = try await tool.call(arguments: .init(query: "pods"))
        let second = try await tool.call(arguments: .init(query: "garage"))
        let third = try await tool.call(arguments: .init(query: "pods"))
        #expect(first == DuplicateLookupTool.result(DuplicateLookup.entries(for: "pods", in: household)))
        #expect(!first.tasks.isEmpty)
        #expect(second.tasks.isEmpty)
        #expect(third.tasks.isEmpty)
        #expect(await recorder.queries == ["pods"])
        #expect(await recorder.refusedCalls == 2)
    }

    @Test("R-1 (a): the snapshots carry only the one answered query, so the rules replay exactly what the model saw")
    func snapshotsCarryOneQuery() async throws {
        let household = try LookupHouseholds.big()
        let item = OnDeviceJSON.item(title: "Get pods", kind: "restock", sameAsExisting: "Buy pods 3")
        let model = OnDeviceFixtures.model(household: household, steps: [
            .lookup("pods"), .lookup("garage"), .answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item]))),
        ])
        let (snapshots, end) = await OnDeviceFixtures.snapshots(of: model, input: "get pods")
        #expect(end == nil)
        #expect(snapshots.allSatisfy { $0.lookupQueries == ["pods"] })
        let events = await OnDeviceFixtures.events(
            input: "get pods", household: household,
            model: OnDeviceFixtures.model(household: household, steps: [
                .lookup("pods"), .lookup("garage"), .answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item]))),
            ]))
        #expect(DraftStreamSummary(events).drafts.map(\.duplicate) == [.ofExisting(OnDeviceFixtures.uuid(3))])
    }

    @Test("R-1 (a): a repeat that only a refused second call would have found is still marked, by the word-match floor")
    func floorCatchesWhatTheSecondCallMissed() async throws {
        let household = try LookupHouseholds.big()
        // The first (answered) query does not shortlist "Water the plants"; the refused second one would have.
        // The model names the task anyway; D1 ignores a title the Tool did not return, and the floor marks it.
        let item = OnDeviceJSON.item(title: "Water the plants", kind: "recurring", sameAsExisting: "Water the plants")
        let steps: [GenerationStep] = [.lookup("pods"), .lookup("water plants"),
                                       .answer(try OnDeviceJSON.partial(OnDeviceJSON.answer([item])))]
        let log = GenerationLog()
        let model = OnDeviceFixtures.model(household: household, steps: steps, log: log)
        let events = await OnDeviceFixtures.events(input: "water the plants", household: household, model: model)
        #expect(DuplicateLookup.entries(for: "pods", in: household).allSatisfy { $0.title != "Water the plants" })
        #expect(log.snapshot.lookupResults.last?.tasks.isEmpty == true)
        #expect(DraftStreamSummary(events).drafts.map(\.duplicate) == [.ofExisting(OnDeviceFixtures.uuid(42))])
    }

    @Test("R-1 (a): the instructions and the Tool description ask for one call with every chore's main words")
    func oneCallWording() {
        let tool = DuplicateLookupTool(recorder: DuplicateLookupRecorder(household: Self.empty))
        #expect(OnDeviceInstructions.text.contains("once"))
        #expect(tool.description.contains("once"))
    }
}
