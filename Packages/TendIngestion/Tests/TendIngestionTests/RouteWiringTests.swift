// Review R23-F2 (WI-M2-06/07 integration, ticket for WI-M2-09): the duplicate rules are built from the route the
// router chose, with this capture, so the rules cannot belong to another route or another capture (FR-A1, M2 gate
// "zero duplicate creation"; AC-M2-07, AC-M2-08, AC-M2-19).

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("R23-F2: the router builds each capture's duplicate rules from its route (AC-M2-07, AC-M2-19; FR-A1)")
struct RouteWiringTests {
    typealias R = RoutingFixtures

    static let task = DupFixture.task(DupFixture.id("0000000000A1"), "Buy dishwasher pods",
                                      room: MappingFixtures.kitchen.id)
    /// No room, so only the capture's own words ("AC", "servicing") can shortlist it: the shortlist depends on the
    /// capture, not only on the rooms.
    static let wordTask = DupFixture.task(DupFixture.id("0000000000A2"), "Service the AC")
    static let household = Household(tasks: [task, wordTask], rooms: MappingFixtures.rooms)

    func routedEvents(_ router: ModelRouter, _ sharing: CloudTitleSharing,
                      _ preference: RoutePreference) async -> RoutedDraftEvents {
        await router.events(input: StreamFixtures.input, household: Self.household, now: StreamFixtures.now,
                            calendar: MappingFixtures.gregorian, timeZone: MappingFixtures.zone("America/New_York"),
                            titleSharing: sharing, preference: preference)
    }

    @Test("R23-F2: in every plan cell and for both Q12 answers, the pipeline's rules are the rules of the chosen route, for this capture and household (680 cells)")
    func rulesFollowTheRoute() async throws {
        var cells = 0
        var cloudCells = 0
        for state in StoredState.planRows {
            for availability in R.availabilities {
                for preference in RoutePreference.allCases {
                    for sharing in [CloudTitleSharing.shortlistTitles, .noTitles] {
                        let (router, _, _, _, _) = R.router(state, availability)
                        let events = await routedEvents(router, sharing, preference)
                        let pipeline = events.events.pipeline
                        let rules = try #require(pipeline.duplicateCheck as? DraftDuplicateRules)
                        let expected: DraftDuplicateRules = switch events.route {
                        case .cloud: .cloud(sharing, capture: StreamFixtures.input, household: Self.household)
                        case .onDevice, .none: .onDevice(household: Self.household)
                        }
                        #expect(rules.path == expected.path, "\(state) \(availability) \(preference) \(sharing)")
                        #expect(pipeline.request.input == StreamFixtures.input)
                        #expect(pipeline.request.roomNames == MappingFixtures.rooms.map(\.name))
                        if case .cloud = events.route { cloudCells += 1 }
                        cells += 1
                    }
                }
            }
        }
        #expect(cells == 680)
        #expect(cloudCells > 0)
    }

    @Test("R23-F2: under Q12 = yes the cloud rules hold the shortlist of this capture (the one the payload sends); under Q12 = no only the word-match")
    func cloudRulesUseThisCapture() async throws {
        let state = StoredState(selected: .openAI, consents: [.openAI], keys: [.openAI], row: "S4")
        let (router, _, _, _, _) = R.router(state, .unavailable(.deviceNotEligible))
        let yes = try #require(await routedEvents(router, .shortlistTitles, .onDeviceFirst).events.pipeline
            .duplicateCheck as? DraftDuplicateRules)
        let shortlist = DuplicateShortlist.entries(for: StreamFixtures.input, in: Self.household)
        #expect(shortlist.map(\.taskID).contains(Self.wordTask.id), "the capture's words must shortlist the AC task")
        #expect(DuplicateShortlist.entries(for: "Kitchen", in: Self.household) != shortlist,
                "the fixture must make the shortlist depend on the capture")
        #expect(yes.path == .cloud(.sentShortlist(shortlist, Self.household)))
        let no = try #require(await routedEvents(router, .noTitles, .onDeviceFirst).events.pipeline
            .duplicateCheck as? DraftDuplicateRules)
        #expect(no.path == .cloud(.localWordMatch(Self.household)))
    }

    @Test("R23-F2: an on-device capture gets the on-device rules even when cloud is on")
    func onDeviceRulesWithCloudOn() async throws {
        let state = StoredState(selected: .gemini, consents: [.gemini], keys: [.gemini], row: "S4")
        let (router, _, _, _, _) = R.router(state, .available)
        let events = await routedEvents(router, .shortlistTitles, .onDeviceFirst)
        #expect(events.route == .onDevice)
        let rules = try #require(events.events.pipeline.duplicateCheck as? DraftDuplicateRules)
        #expect(rules.path == .onDevice(Self.household))
    }
}
