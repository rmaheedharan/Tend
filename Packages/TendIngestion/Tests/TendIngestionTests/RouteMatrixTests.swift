// AC-M2-19: the route equals ADR-0005 Decision 1 for every combination of on-device availability, stored cloud state
// and preference (plan "Route matrix", the full expected matrix). Also the orphan-key side effects of the plan's
// matrix (AC-M2-18, T-14) and an exhaustive check over every stored state (4 selections × 8 consent sets × 8 key
// sets). P-1, P-3. Linux.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("AC-M2-19 the route matrix (ADR-0005 Decision 1; P-1, P-3)")
struct RouteMatrixTests {
    typealias R = RoutingFixtures

    @Test("AC-M2-19: the pure route rule equals the plan matrix for every availability, preference and cloud status (40 cells)")
    func pureRule() {
        let statuses: [CloudStatus] = [.off] + CloudProvider.allCases.map { .on($0) }
        var cells = 0
        for availability in R.availabilities {
            for preference in RoutePreference.allCases {
                for status in statuses {
                    let route = RouteRules.route(availability: availability, preference: preference, cloud: status)
                    #expect(route == R.planRoute(availability, preference, status),
                            "\(availability) \(preference) \(status)")
                    cells += 1
                }
            }
        }
        #expect(cells == 40)
        #expect(RoutePreference.allCases == [.onDeviceFirst, .alwaysCloud])
    }

    @Test("AC-M2-19: the named rules (on device first never goes to the cloud; always cloud with cloud off is ignored)")
    func namedRules() {
        for provider in CloudProvider.allCases {
            #expect(RouteRules.route(availability: .available, preference: .onDeviceFirst, cloud: .on(provider))
                    == .onDevice)
            #expect(RouteRules.route(availability: .available, preference: .alwaysCloud, cloud: .on(provider))
                    == .cloud(provider))
        }
        #expect(RouteRules.route(availability: .available, preference: .alwaysCloud, cloud: .off) == .onDevice)
        for reason in OnDeviceUnavailableReason.allCases {
            #expect(RouteRules.route(availability: .unavailable(reason), preference: .alwaysCloud, cloud: .off)
                    == .none)
        }
    }

    @Test("AC-M2-19: the full matrix through the router: route, side effect and cloud status for every cell (340 cells, logged)")
    func fullMatrix() async {
        var log: [String] = []
        var cells = 0
        for state in StoredState.planRows {
            for availability in R.availabilities {
                for preference in RoutePreference.allCases {
                    let (router, consents, keys, _, _) = R.router(state, availability)
                    let route = await router.route(preference: preference)
                    let expected = R.planRoute(availability, preference, state.expectedCloud)
                    #expect(route == expected, "\(state) \(availability) \(preference)")
                    #expect(await R.storedKeys(keys) == state.expectedKeysAfter, "orphan keys: \(state)")
                    #expect(await R.storedConsents(consents) == state.consents, "consents unchanged: \(state)")
                    if case let .cloud(provider) = route {
                        #expect(provider == state.selected, "cloud(Y) where Y is not selected: \(state)")
                    }
                    log.append("\(state) | \(availability) | \(preference) -> \(route)")
                    cells += 1
                }
            }
        }
        #expect(cells == 340)
        #expect(StoredState.planRows.count == 34)
        print("AC-M2-19 route matrix (\(cells) cells):")
        for line in log { print("  " + line) }
    }

    @Test("AC-M2-19: submitting a capture in every cell: the outcome carries the route, and only cloud(X) cells send exactly one request, to X with X's key (340 cells)")
    func fullMatrixThroughCapture() async {
        for state in StoredState.planRows {
            for availability in R.availabilities {
                for preference in RoutePreference.allCases {
                    let transport = RecordingTransport()
                    let (router, _, _, cloud, onDevice) = R.router(state, availability, transport: transport)
                    let events = await router.events(for: StreamFixtures.pipeline(), preference: preference)
                    let run = await collectBounded(events)
                    let expected = R.planRoute(availability, preference, state.expectedCloud)
                    #expect(events.route == expected)
                    guard case let .finished(outcome)? = run.events.last else {
                        Issue.record("no finished event: \(state)")
                        continue
                    }
                    #expect(outcome.route == expected, "\(state) \(availability) \(preference)")
                    switch expected {
                    case let .cloud(provider):
                        #expect(transport.requestCount == 1)
                        #expect(transport.requests.first?.provider == provider)
                        #expect(transport.requests.first?.key == StoredState.fixtureKey(provider))
                        #expect(transport.requests.first?.input == StreamFixtures.input)
                        #expect(cloud.askedProviders == [provider])
                        #expect(onDevice.scripted.requestCount == 0)
                        #expect(outcome == .completed(route: expected))
                    case .onDevice:
                        #expect(transport.requestCount == 0)
                        #expect(cloud.askedProviders.isEmpty)
                        #expect(onDevice.scripted.requestCount == 1)
                        #expect(outcome == .completed(route: .onDevice))
                    case .none:
                        #expect(transport.requestCount == 0)
                        #expect(cloud.askedProviders.isEmpty)
                        #expect(onDevice.scripted.requestCount == 0)
                        guard case let .unavailable(reason) = availability else {
                            Issue.record("route none with the model available")
                            continue
                        }
                        #expect(outcome.route == .none)
                        if case let .noModel(_, noModelReason, input, note) = outcome {
                            #expect(noModelReason == .onDeviceUnavailable(reason))
                            #expect(input == StreamFixtures.input)
                            #expect(note != nil)
                        } else {
                            Issue.record("expected noModel: \(outcome)")
                        }
                    }
                }
            }
        }
    }

    @Test("AC-M2-19, AC-M2-18: every stored state (256) × availability × preference: cloud is on only for the selected provider with both consent and key, orphan keys are deleted, nothing else changes (2,560 cells)")
    func everyStoredState() async {
        var cells = 0
        var cloudCells = 0
        for state in StoredState.everyState {
            // Independent oracle: written from the brief's Definitions ("Cloud model"), not from the plan rows.
            let oracleOn: CloudProvider? = state.selected.flatMap {
                state.consents.contains($0) && state.keys.contains($0) ? $0 : nil
            }
            for availability in R.availabilities {
                for preference in RoutePreference.allCases {
                    let (router, consents, keys, _, _) = R.router(state, availability)
                    let status = await router.cloudStatus()
                    #expect(status == (oracleOn.map { .on($0) } ?? .off), "\(state)")
                    let route = await router.route(preference: preference)
                    let oracleRoute: Route = switch (availability, preference, oracleOn) {
                    case (.available, .onDeviceFirst, _), (.available, .alwaysCloud, nil): .onDevice
                    case let (.available, .alwaysCloud, provider?): .cloud(provider)
                    case let (.unavailable, _, provider?): .cloud(provider)
                    case (.unavailable, _, nil): .none
                    }
                    #expect(route == oracleRoute, "\(state) \(availability) \(preference)")
                    if case .cloud = route { cloudCells += 1 }
                    #expect(await R.storedKeys(keys) == state.keys.filter { state.consents.contains($0) })
                    #expect(await R.storedConsents(consents) == state.consents)
                    #expect(await consents.selectedProvider() == state.selected)
                    cells += 1
                }
            }
        }
        #expect(cells == 2_560)
        // 3 selections × 4 consent sets containing it × 4 key sets containing it = 48 on-states; 9 cloud cells each
        // (available with always cloud, and 4 unavailable reasons × 2 preferences).
        #expect(cloudCells == 48 * 9)
        print("AC-M2-19 every stored state: \(cells) cells, \(cloudCells) cloud cells, each checked against the oracle")
    }

    @Test("AC-M2-19: the route is part of the outcome and of the routed sequence before it is read")
    func routeIsReported() async {
        let state = StoredState(selected: .gemini, consents: [.gemini], keys: [.gemini], row: "S4")
        let (router, _, _, _, _) = R.router(state, .unavailable(.deviceNotEligible))
        let events = await router.events(for: StreamFixtures.pipeline(), preference: .onDeviceFirst)
        #expect(events.route == .cloud(.gemini))
        let run = await collectBounded(events)
        #expect(run.events.last == .finished(.completed(route: .cloud(.gemini))))
    }
}

@Suite("AC-M2-10 an on-device stop never re-routes to the cloud (P-1, P-3)")
struct RouterNoModelTests {
    typealias R = RoutingFixtures

    @Test("AC-M2-10: cloud off, each on-device reason unavailable: noModel with the input and a plain note, zero requests", arguments: OnDeviceUnavailableReason.allCases)
    func cloudOffUnavailable(reason: OnDeviceUnavailableReason) async {
        for state in StoredState.planRows where state.expectedCloud == .off {
            let transport = RecordingTransport()
            let (router, _, _, cloud, onDevice) = R.router(state, .unavailable(reason), transport: transport)
            for preference in RoutePreference.allCases {
                let run = await collectBounded(await router.events(for: StreamFixtures.pipeline(),
                                                                   preference: preference))
                #expect(run.events.count == 1)
                guard case let .finished(.noModel(route, why, input, note))? = run.events.last else {
                    Issue.record("expected noModel: \(run.events)")
                    continue
                }
                #expect(route == .none)
                #expect(why == .onDeviceUnavailable(reason))
                #expect(input == StreamFixtures.input)
                #expect(note?.title == StreamFixtures.input)
            }
            #expect(transport.requestCount == 0)
            #expect(cloud.askedProviders.isEmpty)
            #expect(onDevice.scripted.requestCount == 0)
        }
    }

    @Test("AC-M2-10, AC-M2-19: on-device generation stops before the first draft, cloud on or off: noModel on route onDevice, zero cloud requests", arguments: ModelStopReason.allCases)
    func onDeviceStopNeverEscalates(reason: ModelStopReason) async {
        let states = [
            StoredState(selected: nil, consents: [], keys: [], row: "S0"),
            StoredState(selected: .openAI, consents: [.openAI], keys: [.openAI], row: "S4"),
            StoredState(selected: .anthropic, consents: [.anthropic, .gemini], keys: [.anthropic, .gemini],
                        row: "S7"),
        ]
        for state in states {
            let transport = RecordingTransport()
            let (router, _, _, cloud, onDevice) = R.router(state, .available, transport: transport,
                                                           onDeviceSteps: [.stop(reason)])
            let run = await collectBounded(await router.events(for: StreamFixtures.pipeline(),
                                                               preference: .onDeviceFirst))
            guard case let .finished(.noModel(route, why, input, note))? = run.events.last else {
                Issue.record("expected noModel: \(run.events)")
                continue
            }
            #expect(route == .onDevice)
            #expect(why == .stoppedBeforeFirstDraft(reason))
            #expect(input == StreamFixtures.input)
            #expect(note != nil)
            #expect(onDevice.scripted.requestCount == 1)
            #expect(transport.requestCount == 0, "an on-device stop called the cloud: \(state)")
            #expect(cloud.askedProviders.isEmpty)
        }
    }

    @Test("AC-M2-10 (T-25): a stop after the first draft is interrupted on route onDevice, still zero cloud requests")
    func onDeviceStopAfterDraft() async {
        let state = StoredState(selected: .openAI, consents: [.openAI], keys: [.openAI], row: "S4")
        let transport = RecordingTransport()
        let (router, _, _, cloud, _) = R.router(
            state, .available, transport: transport,
            onDeviceSteps: [.snapshot([StreamFixtures.full("Buy dishwasher pods")]), .stop(ModelStopReason.guardrail)])
        let run = await collectBounded(await router.events(for: StreamFixtures.pipeline(), preference: .onDeviceFirst))
        #expect(run.events.last == .finished(StreamFixtures.interrupted(.guardrail, discarded: nil)))
        #expect(transport.requestCount == 0)
        #expect(cloud.askedProviders.isEmpty)
    }
}
