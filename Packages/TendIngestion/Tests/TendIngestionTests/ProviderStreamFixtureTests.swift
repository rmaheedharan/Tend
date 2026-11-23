// The synthetic provider stream fixtures (plan WI-M2-13; AC-M2-24 "Fixtures (T-19)", AC-M2-05). FR-A1, P-3, UX-3.
//
// Ten synthetic fixtures per provider, built from each provider's documented streaming format (OpenAI Chat
// Completions, Anthropic Messages with one forced tool, Gemini `streamGenerateContent?alt=sse`), all for the brief's
// Outcome sample sentence (no household data). They cover happy paths, out-of-order fields and noise events, split
// chunks (every fixture is also read byte by byte, one event per chunk and at seeded random cuts), a truncated stream,
// a length cut, invalid output JSON, an invalid event, schema-violating fields, unknown enum values, a refusal and an
// in-stream provider error. The real recordings (one per provider) are WI-M2-M6 on the owner-run Mac.
//
// Each fixture runs through the public `DraftPipeline` on its cloud route with a test adapter
// (`ChunkedProviderModel`), and the exact outcome, emitted titles and skips are checked. Per the PO tickets
// (`po-m2-wi12.md`, `po-q21-q22.md` PR #22 and #26): in every provider's happy path the no-room item (`"room":""`)
// completes by rule (a) before the next item starts, and the item whose title arrives last gives exactly one
// `emitted` with the whole title; and no step of any fixture ever shows part of a title.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

/// The expected result of one fixture.
struct ProviderFixtureCase: Sendable, CustomTestStringConvertible {
    enum End: Sendable, Equatable {
        case completed
        case interrupted(ModelStopReason, discarded: Bool)
        case noModel(ModelStopReason)
    }

    let provider: CloudProvider
    let name: String
    /// The reader's end: nil for a normal finish, else the typed error.
    let error: ProviderStreamError?
    let emitted: [String]
    let skipped: Int
    let end: End

    var testDescription: String { "\(ProviderFixtures.folder(provider))/\(name)" }

    static let invalidOffset = ProviderFixtures.invalidPrefix.utf8.count

    /// The fixtures every provider has, with the parts of the result that do not depend on the provider.
    static func common(_ provider: CloudProvider) -> [ProviderFixtureCase] {
        let titles = ProviderFixtures.happyTitles
        func make(_ name: String, _ error: ProviderStreamError?, _ emitted: [String], skipped: Int = 0,
                  _ end: End) -> ProviderFixtureCase {
            ProviderFixtureCase(provider: provider, name: name, error: error, emitted: emitted, skipped: skipped,
                                end: end)
        }
        let truncated: ProviderStreamError = provider == .anthropic
            ? .cutShort(.noFinish) : .cutShort(.bodyEndedInsideEvent)
        let refusal: ProviderStreamError = switch provider {
        case .openAI: .declined(.refusalText)
        case .anthropic: .declined(.refusalStop)
        case .gemini: .declined(.promptBlocked)
        }
        return [
            make("happy-path", nil, titles, .completed),
            make("out-of-order-fields", nil, titles, .completed),
            make("truncated-after-first-draft", truncated, [titles[0]], .interrupted(.outputCutShort, discarded: true)),
            make("length-limit-after-first-draft", .cutShort(.lengthLimit), [titles[0]],
                 .interrupted(.outputCutShort, discarded: true)),
            make("invalid-json-after-first-draft",
                 .unreadable(.outputNotJSON(.unexpectedByte, byteOffset: invalidOffset)), [titles[0]],
                 .interrupted(.unreadableOutput, discarded: true)),
            make("invalid-event-before-draft", .unreadable(.eventNotJSON), [], .noModel(.unreadableOutput)),
            make("schema-violating-fields", nil, ["Buy dishwasher pods", "Service the AC"], skipped: 1, .completed),
            make("unknown-enum-values", nil, ["Buy dishwasher pods", "Service the AC"], .completed),
            make("refusal-before-draft", refusal, [], .noModel(.refusal)),
            make("provider-error-after-first-draft", .providerError(.serviceUnavailable), [titles[0]],
                 .interrupted(.serviceUnavailable, discarded: false)),
        ]
    }

    static let all: [ProviderFixtureCase] = CloudProvider.allCases.flatMap(common)
}

@Suite("AC-M2-24 provider stream fixtures (synthetic): OpenAI, Anthropic, Gemini through the same draft stream (FR-A1)")
struct ProviderStreamFixtureTests {
    typealias F = ProviderFixtures

    @Test("AC-M2-24: the fixture list is exactly the table: 10 synthetic fixtures per provider, none untested")
    func fixtureList() throws {
        for provider in CloudProvider.allCases {
            let expected = ProviderFixtureCase.all.filter { $0.provider == provider }.map(\.name).sorted()
            let onDisk = try F.names(on: provider)
            print("AC-M2-24 fixtures \(F.folder(provider)): \(onDisk.count) synthetic: \(onDisk.joined(separator: ", "))")
            #expect(onDisk == expected)
        }
    }

    @Test("AC-M2-24 / AC-M2-05: each fixture gives its exact outcome, emitted titles and skips through DraftPipeline on its cloud route",
          arguments: ProviderFixtureCase.all)
    func fixtureOutcome(_ fixture: ProviderFixtureCase) async throws {
        let bytes = try F.load(fixture.provider, fixture.name)
        let read = ProviderRead.read(bytes, provider: fixture.provider)
        #expect(read.error == fixture.error)

        let events = await ProviderPipeline.events(bytes, provider: fixture.provider)
        let route = Route.cloud(fixture.provider)
        #expect(ProviderPipeline.emitted(events).map(\.title) == fixture.emitted)
        #expect(ProviderPipeline.skippedCount(events) == fixture.skipped)
        #expect(events.filter { if case .finished = $0 { true } else { false } }.count == 1)
        let outcome = try #require(ProviderPipeline.outcome(events))
        switch fixture.end {
        case .completed:
            #expect(outcome == .completed(route: route))
        case let .interrupted(reason, discarded):
            #expect(outcome == .interrupted(route: route, reason: reason,
                                            discardedItem: discarded ? .stoppedBeforeComplete : nil, input: F.input))
        case let .noModel(reason):
            guard case let .noModel(outRoute, outReason, input, plainNote) = outcome else {
                Issue.record("expected noModel, got \(outcome)")
                return
            }
            #expect(outRoute == route)
            #expect(outReason == .stoppedBeforeFirstDraft(reason))
            #expect(input == F.input)
            #expect(plainNote?.title == F.input)
            #expect(plainNote?.room == DraftRoom.none)
        }
        // The adapter throws exactly the reason the pipeline reports (adapter contract rule 1).
        if let error = fixture.error {
            switch fixture.end {
            case let .interrupted(reason, _), let .noModel(reason): #expect(error.stopReason == reason)
            case .completed: Issue.record("a completed fixture has no error")
            }
        }
    }

    @Test("AC-M2-24: every fixture gives the same result one shot, one event per chunk, byte by byte and at 40 seeded random cut sets",
          arguments: ProviderFixtureCase.all)
    func splitChunks(_ fixture: ProviderFixtureCase) async throws {
        let bytes = try F.load(fixture.provider, fixture.name)
        let oneShot = ProviderRead.read(bytes, provider: fixture.provider)
        let oneShotEvents = await ProviderPipeline.events(bytes, provider: fixture.provider)
        var rng = SplitMix64(seed: 0x13D1A1EC7 ^ UInt64(bytes.count))
        var cutSets = [ProviderRead.eventBoundaries(bytes), ProviderRead.everyByte(bytes)]
        for _ in 0..<40 {
            let count = Int.random(in: 1...40, using: &rng)
            cutSets.append((0..<count).map { _ in Int.random(in: 0...bytes.count, using: &rng) })
        }
        for (index, cuts) in cutSets.enumerated() {
            let read = ProviderRead.read(bytes, provider: fixture.provider, cuts: cuts)
            #expect(read.end == oneShot.end, "cut set \(index)")
            let events = await ProviderPipeline.events(bytes, provider: fixture.provider, cuts: cuts)
            #expect(ProviderPipeline.emitted(events).map(\.title) == ProviderPipeline.emitted(oneShotEvents).map(\.title),
                    "cut set \(index)")
            #expect(ProviderPipeline.finalDrafts(events) == ProviderPipeline.finalDrafts(oneShotEvents),
                    "cut set \(index)")
            #expect(ProviderPipeline.outcome(events) == ProviderPipeline.outcome(oneShotEvents), "cut set \(index)")
            await Task.yield()
        }
    }

    @Test("AC-M2-05 / AC-M2-24: no step of any fixture, read byte by byte, shows part of a title (only finished values)",
          arguments: ProviderFixtureCase.all)
    func neverAPartTitle(_ fixture: ProviderFixtureCase) throws {
        let bytes = try F.load(fixture.provider, fixture.name)
        let read = ProviderRead.read(bytes, provider: fixture.provider, cuts: ProviderRead.everyByte(bytes))
        let finished: Set<String> = ["Service the AC", "Buy dishwasher pods", "Deep clean the balcony"]
        for step in read.steps {
            for item in step.items {
                if let title = item.title { #expect(finished.contains(title), "part title \(title)") }
            }
        }
    }

    @Test("AC-M2-24: each provider's happy path and out-of-order fixtures join up to exactly the intended output",
          arguments: CloudProvider.allCases)
    func outputText(_ provider: CloudProvider) throws {
        let expected = try StructuredOutputReader.parse(F.happyOutput)
        #expect(expected.items.map(\.title) == F.happyTitles)
        for name in ["happy-path", "out-of-order-fields"] {
            let read = ProviderRead.read(try F.load(provider, name), provider: provider)
            #expect(try read.end.get() == expected, "\(name)")
        }
    }

    @Test("AC-M2-24 / AC-M2-04: the happy path's drafts: no room, an existing room, a proposed room; kinds and flags as sent",
          arguments: CloudProvider.allCases)
    func happyDrafts(_ provider: CloudProvider) async throws {
        let events = await ProviderPipeline.events(try F.load(provider, "happy-path"), provider: provider)
        let drafts = ProviderPipeline.finalDrafts(events)
        #expect(drafts.map(\.room) == [.none, .existing(MappingFixtures.kitchen.id), .proposed("Balcony")])
        #expect(drafts.map(\.kind) == [.oneOff, .restock, .oneOff])
        #expect(drafts.map(\.effort) == [.normal, .low, .high])
        #expect(drafts.map(\.isDeepClean) == [false, false, true])
        #expect(drafts.map(\.isWeatherDependent) == [false, false, true])
        #expect(drafts.map(\.sourcePhrase) == ["The AC needs servicing before summer", "almost out of dishwasher pods",
                                               "deep clean the balcony this weekend"])
        #expect(drafts.map(\.duplicate) == [.none, .none, .none])
    }

    /// PO WI-M2-12 ruling 2 ticket (`po-m2-wi12.md`): "a synthetic fixture per provider where a no-room item completes
    /// by (a) before the next item starts".
    @Test("AC-M2-05 / AC-M2-24: in each provider's happy path (one event per chunk) the no-room item (\"room\":\"\") is emitted by rule (a) while it is the only item, with room none",
          arguments: CloudProvider.allCases)
    func noRoomItemCompletesByRuleA(_ provider: CloudProvider) throws {
        let bytes = try F.load(provider, "happy-path")
        let read = ProviderRead.read(bytes, provider: provider, cuts: ProviderRead.eventBoundaries(bytes))
        var assembler = DraftStreamAssembler(mapper: StreamFixtures.mapper(input: F.input),
                                             duplicateCheck: NoDuplicateCheck(), route: .cloud(provider))
        var firstEmission: (step: Int, draft: IngestionDraft)?
        for (index, step) in read.steps.enumerated() {
            for event in assembler.receive(step) {
                if case let .emitted(draft) = event, firstEmission == nil { firstEmission = (index, draft) }
            }
            if firstEmission != nil { break }
        }
        let emission = try #require(firstEmission)
        #expect(emission.draft.title == "Service the AC")
        #expect(emission.draft.room == .none)
        #expect(read.steps[emission.step].items.count == 1, "the next item had already started")
        #expect(read.steps[emission.step].items[0].hasValueForEveryField)
        #expect(read.steps[emission.step].items[0].roomName == "")
    }

    /// PO tickets `po-q21-q22.md` (PR #22, PR #26) and `po-m2-wi12.md`: title arrives last, per provider.
    @Test("AC-M2-05 / AC-M2-24: in each provider's happy and out-of-order fixtures the title-last item gives exactly one emitted with the whole title, by rule (a) before the end, and no updated",
          arguments: CloudProvider.allCases, ["happy-path", "out-of-order-fields"])
    func titleArrivesLast(_ provider: CloudProvider, _ name: String) async throws {
        let bytes = try F.load(provider, name)
        for cuts in [ProviderRead.eventBoundaries(bytes), ProviderRead.everyByte(bytes)] {
            let read = ProviderRead.read(bytes, provider: provider, cuts: cuts)
            // Rule (a) is met for the third item before the stream ends.
            let full = try #require(read.steps.firstIndex { $0.items.count == 3 && $0.items[2].hasValueForEveryField })
            #expect(read.steps[full].items[2].title == "Deep clean the balcony")
            #expect(read.steps[..<full].allSatisfy { $0.items.count < 3 || $0.items[2].title == nil })
            let events = await ProviderPipeline.events(bytes, provider: provider, cuts: cuts)
            let emitted = ProviderPipeline.emitted(events).filter { $0.draftID == 3 }
            #expect(emitted.map(\.title) == ["Deep clean the balcony"])
            #expect(!events.contains { if case .updated = $0 { true } else { false } })
            #expect(!events.contains { if case .itemSkipped = $0 { true } else { false } })
        }
    }

    @Test("AC-M2-24 / AC-M2-02: schema-violating fields are repaired by Q5 (null, wrong types, a non-object item, fractions)",
          arguments: CloudProvider.allCases)
    func schemaViolatingRepairs(_ provider: CloudProvider) async throws {
        let events = await ProviderPipeline.events(try F.load(provider, "schema-violating-fields"), provider: provider)
        let drafts = ProviderPipeline.finalDrafts(events)
        try #require(drafts.count == 2)
        #expect(drafts[0].kind == .oneOff)
        #expect(drafts[0].effort == .normal)
        #expect(drafts[0].room == .none)
        #expect(drafts[0].isCritical == false && drafts[0].isWeatherDependent == false)
        #expect(drafts[0].sourcePhrase == nil)
        // "recurring" with a fractional interval: Q5 step 6 makes it a one-off with no interval.
        #expect(drafts[1].kind == .oneOff)
        #expect(drafts[1].recurrenceIntervalDays == nil)
        #expect(drafts[1].room == .none)
        #expect(events.contains(.itemSkipped(.noTitle)))
    }

    @Test("AC-M2-24 / AC-M2-02: unknown enum values become the field defaults (kind one-off, effort normal); exact match only",
          arguments: CloudProvider.allCases)
    func unknownEnumRepairs(_ provider: CloudProvider) async throws {
        let read = ProviderRead.read(try F.load(provider, "unknown-enum-values"), provider: provider)
        let items = try read.end.get().items
        #expect(items.map(\.kind) == [.unrecognized("chore"), .unrecognized("Restock")])
        #expect(items.map(\.effort) == [.unrecognized("medium"), .unrecognized("LOW")])
        #expect(items[0].time?.anchor == .unrecognized("someday"))
        let events = await ProviderPipeline.events(try F.load(provider, "unknown-enum-values"), provider: provider)
        let drafts = ProviderPipeline.finalDrafts(events)
        #expect(drafts.map(\.kind) == [.oneOff, .oneOff])
        #expect(drafts.map(\.effort) == [.normal, .normal])
        #expect(drafts.map(\.room) == [.existing(MappingFixtures.kitchen.id), .none])
    }

    @Test("AC-M2-24: the largest fixture is far below the response byte limit (1 MiB)")
    func fixturesUnderTheLimit() throws {
        var largest = 0
        for fixture in ProviderFixtureCase.all {
            largest = max(largest, try F.load(fixture.provider, fixture.name).count)
        }
        print("AC-M2-24 largest synthetic fixture: \(largest) bytes; limit \(ProviderStreamReader.defaultResponseByteLimit)")
        #expect(ProviderStreamReader.defaultResponseByteLimit == 1_048_576)
        #expect(largest * 16 < ProviderStreamReader.defaultResponseByteLimit)
    }
}
