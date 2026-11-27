// `PartiallyGenerated` → neutral snapshots (WI-M2-M2; AC-M2-05 on-device half; PO WI-M2-12 ruling 1, J2). FR-A1, UX-3.
// Each case builds the framework's own `PartiallyGenerated` value from a JSON prefix, the way it grows while the model
// writes.

import Foundation
import FoundationModels
import Testing
@testable import TendAI
import TendCore
import TendIngestion

@Suite("On-device snapshot mapping (WI-M2-M2; AC-M2-05)")
struct OnDeviceSnapshotMappingTests {

    private func mapped(_ json: String, isFinal: Bool = false,
                        queries: [String] = []) throws -> IngestionSnapshot {
        OnDeviceSnapshotMapping.snapshot(try OnDeviceJSON.partial(json), isFinal: isFinal, lookupQueries: queries)
    }

    @Test("A title still being written is not shown (\"Buy di\"), and is shown whole once the next property starts")
    func growingTitle() throws {
        let growing = try mapped(#"{"items":[{"title":"Buy di"#)
        #expect(growing.items.count == 1)
        #expect(growing.items[0].title == nil)
        let next = try mapped(#"{"items":[{"title":"Buy dish pods","sourcePhrase":"bu"#)
        #expect(next.items[0].title == "Buy dish pods")
        #expect(next.items[0].sourcePhrase == nil)
    }

    @Test("The prefix \"Late\" of \"Later: call the plumber\" never appears as a title")
    func latePrefix() throws {
        let prefix = try mapped(#"{"items":[{"title":"Late"#)
        #expect(prefix.items[0].title == nil)
        let whole = try mapped(#"{"items":[{"title":"Later: call the plumber","sourcePhrase":""#)
        #expect(whole.items[0].title == "Later: call the plumber")
    }

    @Test("A number still being written (the 1 of 12) is not shown until a later property starts")
    func growingNumber() throws {
        let open = try mapped(#"{"items":[{"title":"Swap filter","sourcePhrase":"","kind":"recurring","room":"","#
                              + #""effort":"low","time":{"anchor":"none","repeatEvery":1"#)
        #expect(open.items[0].effort == .known(.low))
        #expect(open.items[0].time == nil)
        let closed = try mapped(#"{"items":[{"title":"Swap filter","sourcePhrase":"","kind":"recurring","room":"","#
                                + #""effort":"low","time":{"anchor":"none","repeatEvery":12,"repeatUnit":"week"},"#
                                + #""isCritical":false"#)
        #expect(closed.items[0].time == TimeHintSnapshot(anchor: .known(.none), repeatEvery: 12,
                                                          repeatUnit: .known(.week)))
        #expect(closed.items[0].isCritical == nil)
    }

    @Test("Rule (a) fires only when the last property is written, and then every field is whole")
    func ruleAOnLastProperty() throws {
        let item = OnDeviceJSON.item(title: "Book the AC service", sourcePhrase: "AC needs servicing",
                                     kind: "oneOff", room: "Living room", effort: "low",
                                     time: #"{"anchor":"beforeSeason","season":"summer"}"#, sameAsExisting: "AC service",
                                     critical: false, deepClean: false, weather: true)
        let whole = try mapped(OnDeviceJSON.answer([item]))
        let expected = ItemSnapshot(title: "Book the AC service", kind: .known(.oneOff), roomName: "Living room",
                                    effort: .known(.low), isCritical: false, isDeepClean: false,
                                    isWeatherDependent: true,
                                    time: TimeHintSnapshot(anchor: .known(.beforeSeason), season: .known(.summer)),
                                    sourcePhrase: "AC needs servicing", sameAsExisting: .lookupTitle("AC service"))
        #expect(whole.items == [expected])
        #expect(whole.items[0].hasValueForEveryField)
        // One property earlier: isDeepClean is shown (isWeatherDependent has not started), rule (a) has not fired.
        let cut = OnDeviceJSON.answer([item]).replacingOccurrences(of: #","isWeatherDependent":true}]}"#, with: "")
        let before = try mapped(cut)
        #expect(before.items[0].isWeatherDependent == nil)
        #expect(!before.items[0].hasValueForEveryField)
    }

    @Test("An item is whole once the next item has started (rule b), and the last item is whole at the end (rule c)")
    func wholeItems() throws {
        let first = OnDeviceJSON.item(title: "Buy pods")
        let started = try mapped(#"{"items":["# + first + #",{"title":"Mop"#)
        #expect(started.items.count == 2)
        #expect(started.items[0].title == "Buy pods")
        #expect(started.items[0].hasValueForEveryField)
        #expect(started.items[1].title == nil)
        let final = try mapped(#"{"items":["# + first + #",{"title":"Mop"#, isFinal: true)
        #expect(final.items[1].title == "Mop")
    }

    @Test("Claims map to the neutral claim fields; the queries are carried as given")
    func claims() throws {
        let items = [OnDeviceJSON.item(title: "Buy pods"),
                     OnDeviceJSON.item(title: "Get pods", sameAsItem: 1, sameAsExisting: "Dishwasher pods")]
        let snapshot = try mapped(OnDeviceJSON.answer(items), queries: ["pods", "dishwasher"])
        #expect(snapshot.items[1].sameAsItem == 1)
        #expect(snapshot.items[1].sameAsExisting == .lookupTitle("Dishwasher pods"))
        #expect(snapshot.items[1].duplicateClaim == DuplicateClaim(sameAsItem: 1, sameAsTitle: "Dishwasher pods"))
        #expect(snapshot.items[0].sameAsItem == nil && snapshot.items[0].sameAsExisting == nil)
        #expect(snapshot.lookupQueries == ["pods", "dishwasher"])
    }

    @Test("Empty and itemless answers give an empty snapshot")
    func empty() throws {
        #expect(try mapped("{").items.isEmpty)
        #expect(try mapped(#"{"items":["#).items.isEmpty)
        #expect(try mapped(#"{"items":[]}"#, isFinal: true).items.isEmpty)
    }

    @Test("Every value of every closed list maps to the known neutral value", arguments: OnDeviceAnchor.allCases)
    func anchors(anchor: OnDeviceAnchor) throws {
        let item = OnDeviceJSON.item(title: "T", time: #"{"anchor":"\#(anchor.rawValue)"}"#)
        #expect(try mapped(OnDeviceJSON.answer([item])).items[0].time?.anchor
                == .known(try #require(TimeHint.Anchor(rawValue: anchor.rawValue))))
    }

    @Test("Kinds, efforts and every hint member map exactly")
    func closedValues() throws {
        for kind in OnDeviceKind.allCases {
            for effort in OnDeviceEffort.allCases {
                let item = OnDeviceJSON.item(title: "T", kind: kind.rawValue, effort: effort.rawValue)
                let snapshot = try mapped(OnDeviceJSON.answer([item])).items[0]
                #expect(snapshot.kind == .known(try #require(TaskKind(rawValue: kind.rawValue))))
                #expect(snapshot.effort == .known(try #require(Effort(rawValue: effort.rawValue))))
            }
        }
        let time = #"{"anchor":"weekday","daypart":"evening","weekday":"friday","month":3,"season":"winter","#
            + #""count":2,"repeatEvery":3,"repeatUnit":"month"}"#
        let item = try mapped(OnDeviceJSON.answer([OnDeviceJSON.item(title: "T", time: time)])).items[0]
        #expect(item.time == TimeHintSnapshot(anchor: .known(.weekday), daypart: .known(.evening),
                                              weekday: .known(.friday), month: 3, season: .known(.winter), count: 2,
                                              repeatEvery: 3, repeatUnit: .known(.month)))
    }

    @Test("A field never changes once shown, over every growing prefix of a two-item answer")
    func monotone() throws {
        let json = OnDeviceJSON.answer([
            OnDeviceJSON.item(title: "Later: call the plumber", sourcePhrase: "later call the plumber",
                              time: #"{"anchor":"inDays","count":12}"#, weather: true),
            OnDeviceJSON.item(title: "Buy dish pods", kind: "restock", sameAsItem: 1, critical: true),
        ])
        let whole = try mapped(json, isFinal: true)
        for step in [1, 2, 3, 7] {
            for partial in OnDeviceJSON.growingPartials(json, step: step) {
                let snapshot = OnDeviceSnapshotMapping.snapshot(partial, isFinal: false, lookupQueries: [])
                for (index, item) in snapshot.items.enumerated() {
                    let final = whole.items[index]
                    if let title = item.title { #expect(title == final.title) }
                    if let phrase = item.sourcePhrase { #expect(phrase == final.sourcePhrase) }
                    if let time = item.time { #expect(time == final.time) }
                    if let room = item.roomName { #expect(room == final.roomName) }
                    if let claim = item.sameAsItem { #expect(claim == final.sameAsItem) }
                }
            }
        }
    }
}
