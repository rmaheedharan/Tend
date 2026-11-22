// AC-M2-07 (Linux half): the duplicate shortlist, the neutral duplicate-lookup function the `Tool` wraps, the in-input
// collapse, the cloud re-check (Q12 = yes), the local word-match (Q12 = no) and the word-match floor on every path
// (PO 2026-11-21, WI-M2-07 ruling 1; review R21-F1). FR-A1, Q7, Q12. Plan WI-M2-07.
//
// Every expected value below is written by hand from the brief's Definitions ("Keywords of a text", "Duplicate
// shortlist" steps 1–6, "Local duplicate re-check for cloud drafts", "Duplicate"), not computed by production code.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

private typealias F = DupFixture

// MARK: - Fixture household

private enum H {
    static let kitchen = Room(id: F.id("0000000000A1"), name: "Kitchen")
    static let bathroom = Room(id: F.id("0000000000A2"), name: "Bathroom")
    /// A room name with no keywords ("the" is a stop word): it never matches (shortlist step 3).
    static let theRoom = Room(id: F.id("0000000000A3"), name: "The")
    static let sams = Room(id: F.id("0000000000A4"), name: "Sam\u{2019}s room")

    static let pods = F.task(F.id("000000000001"), "  Buy dish pods ", kind: .restock, room: kitchen.id)
    static let counter = F.task(F.id("000000000002"), "Wipe kitchen counter", room: kitchen.id)
    static let oven = F.task(F.id("000000000003"), "Clean the oven", kind: .recurring, room: kitchen.id)
    static let milk = F.task(F.id("000000000004"), "Buy milk", kind: .restock, state: .completed)
    static let parcel = F.task(F.id("000000000005"), "Post the parcel", kind: .oneOff, state: .completed)
    static let plants = F.task(F.id("000000000006"), "Water the plants", kind: .recurring, state: .deferred)
    static let tiles = F.task(F.id("000000000007"), "Scrub bathroom tiles", room: bathroom.id, state: .maintenance)
    static let shelves = F.task(F.id("000000000008"), "Dust shelves", room: theRoom.id)
    static let toy = F.task(F.id("000000000009"), "Tidy toy box", room: sams.id, state: .resurfaced)

    static let household = Household(
        tasks: [pods, counter, oven, milk, parcel, plants, tiles, shelves, toy],
        rooms: [kitchen, bathroom, theRoom, sams]
    )
}

private func ids(_ entries: [ShortlistEntry]) -> [UUID] { entries.map(\.taskID) }

// MARK: - Shortlist

@Suite("AC-M2-07 duplicate shortlist (brief Definitions steps 1–6, T-06; FR-A1)")
struct DuplicateShortlistTests {

    @Test("AC-M2-07: a synonym query shortlists the task that shares a keyword; entries carry title as stored (trimmed), kind and room name")
    func synonymQuery() {
        // "we're almost out of dishwasher pods": keywords {dishwasher, pods}. "Buy dish pods" shares "pods" (K = 1).
        let list = DuplicateShortlist.entries(for: "we\u{2019}re almost out of dishwasher pods", in: H.household)
        #expect(list == [ShortlistEntry(index: 1, taskID: H.pods.id, title: "Buy dish pods", kind: .restock,
                                        roomName: "Kitchen")])
    }

    @Test("AC-M2-07: the entry title is trimmed of spaces, tabs and newlines at both ends; inner text is kept (review R21-F2)")
    func titleTrimmedOfNewlines() {
        let household = Household(tasks: [F.task(F.id("0000000000E1"), "\n\tBuy  dish pods \n")], rooms: [])
        #expect(DuplicateShortlist.entries(for: "pods", in: household).map(\.title) == ["Buy  dish pods"])
        #expect(DuplicateLookup.entries(for: "pods", in: household).map(\.title) == ["Buy  dish pods"])
    }

    @Test("AC-M2-07: keywords split at every character that is not a letter or a decimal digit: ½ and ² split, 3 is a keyword (review R21-F3)")
    func decimalDigitsOnly() {
        let cup = F.task(F.id("0000000000E2"), "Measure cup")
        let lemons = F.task(F.id("0000000000E3"), "Buy 3 lemons")
        let household = Household(tasks: [cup, lemons], rooms: [])
        #expect(ids(DuplicateShortlist.entries(for: "\u{00BD}cup", in: household)) == [cup.id])      // ½ (No) splits
        #expect(ids(DuplicateShortlist.entries(for: "cup\u{00B2}", in: household)) == [cup.id])      // ² (No) splits
        #expect(ids(DuplicateShortlist.entries(for: "3", in: household)) == [lemons.id])             // 3 (Nd) is kept
        #expect(DuplicateShortlist.entries(for: "\u{00BD} \u{00B2} \u{2167}", in: household).isEmpty)  // ½ ² Ⅷ
    }

    @Test("AC-M2-07: room-only matches (K = 0, R = 1) are shortlisted after keyword matches, then by folded title")
    func roomOnly() {
        // Q = "kitchen". counter: K 1, R 1. pods and oven: K 0, R 1 ("buy dish pods" < "clean the oven").
        let list = DuplicateShortlist.entries(for: "kitchen", in: H.household)
        #expect(ids(list) == [H.counter.id, H.pods.id, H.oven.id])
        #expect(list.map(\.index) == [1, 2, 3])
    }

    @Test("AC-M2-07: completed tasks are left out (step 1); every other state is a candidate")
    func completedLeftOut() {
        #expect(ids(DuplicateShortlist.entries(for: "buy", in: H.household)) == [H.pods.id])   // milk is completed
        #expect(DuplicateShortlist.entries(for: "post parcel", in: H.household).isEmpty)       // parcel is completed
        #expect(ids(DuplicateShortlist.entries(for: "plants", in: H.household)) == [H.plants.id])        // deferred
        #expect(ids(DuplicateShortlist.entries(for: "tiles", in: H.household)) == [H.tiles.id])          // maintenance
        #expect(ids(DuplicateShortlist.entries(for: "toy", in: H.household)) == [H.toy.id])              // resurfaced
    }

    @Test("AC-M2-07: a stop-word-only or empty query gives an empty shortlist", arguments: [
        "", "   ", "the", "we need to do it again, please", "um... okay so, like, wait", "a an the and or of",
    ])
    func stopWordsOnly(_ query: String) {
        #expect(DuplicateShortlist.entries(for: query, in: H.household).isEmpty)
    }

    @Test("AC-M2-07: a room name with no keywords never matches (step 3)")
    func roomWithoutKeywords() {
        // "Dust shelves" is in the room "The". Q = "the hall" has keyword {hall}: no K, and R must be 0.
        #expect(DuplicateShortlist.entries(for: "the hall", in: H.household).isEmpty)
        #expect(ids(DuplicateShortlist.entries(for: "shelves", in: H.household)) == [H.shelves.id])
    }

    @Test("AC-M2-07: R needs every keyword of the room name in the query (Sam’s room = {sam, room})")
    func roomNeedsAllKeywords() {
        #expect(DuplicateShortlist.entries(for: "room", in: H.household).isEmpty)
        #expect(ids(DuplicateShortlist.entries(for: "Sam's room", in: H.household)) == [H.toy.id])
    }

    @Test("AC-M2-07: ranking step 5a, K decides before R")
    func kBeforeR() {
        let k = Room(id: F.id("0000000000B0"), name: "Kitchen")
        let a = F.task(F.id("0000000000B1"), "dust rug", room: k.id)          // Q "dust lamp kitchen": K 1, R 1
        let b = F.task(F.id("0000000000B2"), "dust lamp")                      // K 2, R 0
        let list = DuplicateShortlist.entries(for: "dust lamp kitchen", in: Household(tasks: [a, b], rooms: [k]))
        #expect(ids(list) == [b.id, a.id])
    }

    @Test("AC-M2-07: ranking step 5b, R decides before the title (ties on K)")
    func rBeforeTitle() {
        let k = Room(id: F.id("0000000000B0"), name: "Kitchen")
        let rug = F.task(F.id("0000000000B1"), "Dust rug", room: k.id)         // K 1, R 1
        let lamp = F.task(F.id("0000000000B2"), "Dust lamp")                   // K 1, R 0; "dust lamp" < "dust rug"
        let list = DuplicateShortlist.entries(for: "dust kitchen", in: Household(tasks: [lamp, rug], rooms: [k]))
        #expect(ids(list) == [rug.id, lamp.id])
    }

    @Test("AC-M2-07: ranking step 5c, the keyword-folded title in UTF-8 byte order decides before the ID (ties on K and R)")
    func titleBeforeID() {
        let z = F.task(F.id("000000000001"), "Zest lemons")
        let a = F.task(F.id("000000000002"), "LEMONS, squeeze")                // folds to "lemons, squeeze"
        let e = F.task(F.id("000000000003"), "Éclair lemons")                  // folds to "eclair lemons"
        let list = DuplicateShortlist.entries(for: "lemons", in: Household(tasks: [z, a, e], rooms: []))
        #expect(ids(list) == [e.id, a.id, z.id])
    }

    @Test("AC-M2-07: ranking step 5d, id.uuidString in byte order breaks a full tie (same folded title)")
    func uuidLast() {
        let high = F.task(F.id("0000000000C2"), "Dust shelf")
        let low = F.task(F.id("0000000000C1"), "dust  SHELF")                  // folds to "dust shelf" too
        let other = F.task(F.id("0000000000C0"), "Dust lamp")                  // K 1 < 2
        let list = DuplicateShortlist.entries(for: "dust shelf", in: Household(tasks: [high, other, low], rooms: []))
        #expect(ids(list) == [low.id, high.id, other.id])
    }

    @Test("AC-M2-07: more than 10 eligible tasks: the first 10 in rank order, numbered 1…10")
    func capAtTen() {
        let tasks = (1...12).map { F.task(F.id(String(format: "%012d", 100 + $0)), "Buy item\($0)") }
        let list = DuplicateShortlist.entries(for: "buy", in: Household(tasks: tasks.reversed(), rooms: []))
        // UTF-8 order of the folded titles: item1, item10, item11, item12, item2 … item7; item8 and item9 are cut.
        let expected = [1, 10, 11, 12, 2, 3, 4, 5, 6, 7].map { tasks[$0 - 1].id }
        #expect(ids(list) == expected)
        #expect(list.map(\.index) == Array(1...10))
        #expect(DuplicateShortlist.limit == 10)
    }

    @Test("AC-M2-07: when two rooms share an ID, the first in household order is the task's room (R and room name)")
    func sharedRoomID() {
        let shared = F.id("0000000000D2")
        let t = F.task(F.id("0000000000D3"), "Dust lamp", room: shared)
        let household = Household(tasks: [t], rooms: [Room(id: shared, name: "Kitchen"), Room(id: shared, name: "Hall")])
        #expect(DuplicateShortlist.entries(for: "kitchen", in: household).map(\.roomName) == ["Kitchen"])
        #expect(DuplicateShortlist.entries(for: "hall", in: household).isEmpty)
    }

    @Test("AC-M2-07: a task whose room ID is not in the household has no room (no R, no room name)")
    func danglingRoom() {
        let gone = F.id("0000000000DD")
        let t = F.task(F.id("0000000000D1"), "Dust lamp", room: gone)
        let list = DuplicateShortlist.entries(for: "dust", in: Household(tasks: [t], rooms: [H.kitchen]))
        #expect(list.first?.roomName == nil)
        #expect(DuplicateShortlist.entries(for: "kitchen", in: Household(tasks: [t], rooms: [H.kitchen])).isEmpty)
    }
}

// MARK: - The neutral lookup the Tool wraps

@Suite("AC-M2-07 duplicate lookup, the neutral function the on-device Tool wraps (FR-A1, P-2)")
struct DuplicateLookupTests {

    @Test("AC-M2-07: the lookup returns exactly the shortlist for its query: at most 10, title, kind and room name only", arguments: [
        "kitchen", "buy", "we're almost out of dishwasher pods", "the", "Sam's room toy", "dust shelves bathroom tiles",
    ])
    func lookupIsShortlist(_ query: String) {
        let list = DuplicateShortlist.entries(for: query, in: H.household)
        let looked = DuplicateLookup.entries(for: query, in: H.household)
        #expect(looked == list.map { DuplicateLookupEntry(title: $0.title, kind: $0.kind, roomName: $0.roomName) })
        #expect(looked.count <= 10)
    }

    @Test("AC-M2-07: a lookup entry has exactly the fields title, kind and roomName (no ID, no other field)")
    func entryFields() {
        let entry = DuplicateLookupEntry(title: "t", kind: .oneOff, roomName: nil)
        #expect(Mirror(reflecting: entry).children.map(\.label) == ["title", "kind", "roomName"])
    }

    @Test("AC-M2-07: the lookup reads only the household it is given (local household only)")
    func localOnly() {
        let other = Household(tasks: [F.task(F.id("0000000000E1"), "Buy dish pods")], rooms: [])
        #expect(DuplicateLookup.entries(for: "pods", in: other)
                == [DuplicateLookupEntry(title: "Buy dish pods", kind: .oneOff, roomName: nil)])
        #expect(DuplicateLookup.entries(for: "pods", in: Household(tasks: [], rooms: [])).isEmpty)
    }

    @Test("AC-M2-07: the lookup log records each call and returns the same entries; Q7: the household is not changed")
    func log() {
        var log = DuplicateLookupLog(household: H.household)
        let first = log.lookUp("kitchen")
        let second = log.lookUp("pods")
        #expect(first == DuplicateLookup.entries(for: "kitchen", in: H.household))
        #expect(second == DuplicateLookup.entries(for: "pods", in: H.household))
        #expect(log.queries == ["kitchen", "pods"])
        #expect(log.household == H.household)
    }
}

// MARK: - Local word-match (Q12 = no)

@Suite("AC-M2-07 local word-match for cloud drafts when Q12 = no (brief Definitions; FR-A1)")
struct LocalWordMatchTests {

    static let kitchen = Room(id: F.id("0000000000A1"), name: "Kitchen")
    static let bathroom = Room(id: F.id("0000000000A2"), name: "Bathroom")
    static let dishPods = F.task(F.id("000000000010"), "Dish pods")                          // 2 kws, no room
    static let pods = F.task(F.id("000000000011"), "Buy dish pods", kind: .restock, room: kitchen.id)
    static let counter = F.task(F.id("000000000012"), "Wipe kitchen counter", room: kitchen.id)
    static let oven = F.task(F.id("000000000013"), "Clean oven")                            // no room
    static let milk = F.task(F.id("000000000014"), "Buy milk", kind: .restock, state: .completed)
    static let vacuum = F.task(F.id("000000000015"), "Vacuum", room: bathroom.id)
    static let mopHigh = F.task(F.id("0000000000F2"), "Mop floor")
    static let mopLow = F.task(F.id("0000000000F1"), "mop the FLOOR")
    static let toDo = F.task(F.id("000000000016"), "To do")                                 // no keywords
    static let household = Household(
        tasks: [dishPods, pods, counter, oven, milk, vacuum, mopHigh, mopLow, toDo], rooms: [kitchen, bathroom]
    )

    @Test("AC-M2-07: the word-match rule over hand-written cases", arguments: [
        // equal keyword sets, same existing room
        ("wipe the kitchen counter", DraftRoom.existing(kitchen.id), counter.id as UUID?),
        // either side has no room
        ("Wipe kitchen counter", .none, counter.id),
        ("clean the oven", .proposed("Scullery"), oven.id),
        ("clean oven", .existing(bathroom.id), oven.id),
        // different existing rooms, or a proposed room against a task with a room
        ("wipe kitchen counter", .existing(bathroom.id), nil),
        ("wipe kitchen counter", .proposed("Scullery"), nil),
        // the smaller set is a subset of the larger and has ≥ 2 keywords
        ("wipe counter", .none, counter.id),
        ("wipe kitchen counter tops", .none, counter.id),
        // a 1-keyword subset is not enough; equal 1-keyword sets are
        ("counter", .none, nil),
        ("vacuum", .none, vacuum.id),
        ("vacuum the stairs", .none, nil),
        // a completed task is not a target
        ("buy milk", .none, nil),
        // no keywords on either side
        ("the", .none, nil),
        ("to do", .none, nil),
        // most shared keywords wins (3 beats 2), even against a lower id
        ("buy dish pods", .none, pods.id),
        ("dish pods", .none, dishPods.id),
        // a tie on shared keywords goes to the lowest id.uuidString
        ("mop floor", .none, mopLow.id),
        // no stemming
        ("wipe kitchen counters", .existing(kitchen.id), nil),
        // a draft room that is not in the household counts as no room (review R21-F4)
        ("wipe kitchen counter", .existing(F.id("0000000000EE")), counter.id),
    ] as [(String, DraftRoom, UUID?)])
    func cases(_ title: String, _ room: DraftRoom, _ expected: UUID?) {
        #expect(LocalWordMatch.target(title: title, room: room, in: Self.household) == expected)
        #expect(LocalWordMatch.target(for: F.draft(1, title, room: room), in: Self.household) == expected)
    }
}

// MARK: - Marking (on-device Tool claims, cloud Q12 yes and no, in-input collapse)

@Suite("AC-M2-07 marking drafts as duplicates (FR-A1, Q7, Q12)")
struct DuplicateMarkingTests {

    static let shortlist = DuplicateShortlist.entries(for: "kitchen", in: H.household)    // counter, pods, oven

    @Test("AC-M2-07: on device, a claim naming a title the Tool returned marks ofExisting(existingID); case and spacing are folded")
    func onDeviceClaim() {
        var log = DuplicateLookupLog(household: H.household)
        _ = log.lookUp("dishwasher pods")
        var marker = DuplicateMarker()
        let marked = marker.mark(F.draft(1, "Buy dishwasher pods"), position: 1,
                                 claim: DuplicateClaim(sameAsTitle: "  buy DISH pods"), check: .toolLookups(log))
        #expect(marked.duplicate == .ofExisting(H.pods.id))
    }

    @Test("AC-M2-07: on device, a title the Tool never returned is ignored as a claim; the word-match floor decides")
    func onDeviceUnseenTitle() {
        var log = DuplicateLookupLog(household: H.household)
        _ = log.lookUp("pods")
        var marker = DuplicateMarker()
        // The claim names a task the Tool never showed; the floor finds the same task by its words (PO ruling 1).
        let unseen = marker.mark(F.draft(1, "Wipe kitchen counter"), position: 1,
                                 claim: DuplicateClaim(sameAsTitle: "Wipe kitchen counter"), check: .toolLookups(log))
        #expect(unseen.duplicate == .ofExisting(H.counter.id))
        // An unseen claim with no word match stays none: the claim alone never marks.
        let noFloor = marker.mark(F.draft(2, "Dust the lamp"), position: 2,
                                  claim: DuplicateClaim(sameAsTitle: "Wipe kitchen counter"), check: .toolLookups(log))
        #expect(noFloor.duplicate == .none)
        // An index claim does not apply on device; "Post a letter" word-matches nothing (the parcel is completed).
        let indexOnly = marker.mark(F.draft(3, "Post a letter"), position: 3,
                                    claim: DuplicateClaim(sameAsShortlistIndex: 1), check: .toolLookups(log))
        #expect(indexOnly.duplicate == .none)
    }

    @Test("AC-M2-07: on device, with no claim at all, the word-match floor marks an exact repeat")
    func onDeviceFloor() {
        let log = DuplicateLookupLog(household: H.household)                 // the model never called the Tool
        var marker = DuplicateMarker()
        let marked = marker.mark(F.draft(1, "buy dish pods", room: .existing(H.kitchen.id)), position: 1,
                                 claim: DuplicateClaim(), check: .toolLookups(log))
        #expect(marked.duplicate == .ofExisting(H.pods.id))
    }

    @Test("AC-M2-07: the model's claim wins over the floor when they disagree (device title, cloud index)")
    func claimBeatsFloor() {
        var log = DuplicateLookupLog(household: H.household)
        _ = log.lookUp("kitchen")
        var marker = DuplicateMarker()
        // The floor alone would give the counter task; the model named another task.
        #expect(LocalWordMatch.target(title: "Wipe kitchen counter", room: .none, in: H.household) == H.counter.id)
        let device = marker.mark(F.draft(1, "Wipe kitchen counter"), position: 1,
                                 claim: DuplicateClaim(sameAsTitle: "Buy dish pods"), check: .toolLookups(log))
        #expect(device.duplicate == .ofExisting(H.pods.id))
        let cloud = marker.mark(F.draft(2, "Wipe kitchen counter"), position: 2,
                                claim: DuplicateClaim(sameAsShortlistIndex: 3),
                                check: .sentShortlist(Self.shortlist, H.household))
        #expect(cloud.duplicate == .ofExisting(H.oven.id))
    }

    @Test("AC-M2-07: cloud, Q12 = yes: an exact repeat ranked 11th (outside the 10 titles sent) is marked by the floor")
    func eleventhCaughtByFloor() {
        let kitchen = Room(id: F.id("0000000000A1"), name: "Kitchen")
        // Ten tasks with K = 3 for the capture ({wipe, counter, kitchen, shelf}) outrank the target, which has K = 2.
        let shelves = (1...10).map { F.task(F.id(String(format: "%012d", 200 + $0)), "Wipe kitchen shelf \($0)") }
        let target = F.task(F.id("000000000999"), "Wipe the counter", room: kitchen.id)
        let household = Household(tasks: shelves + [target], rooms: [kitchen])
        let capture = "wipe the counter, and the kitchen shelf"
        let check = CloudTitleSharing.shortlistTitles.existingTaskCheck(capture: capture, household: household)
        guard case let .sentShortlist(sent, _) = check else {
            Issue.record("Q12 = yes must give the sent shortlist")
            return
        }
        #expect(sent.count == 10 && !sent.contains { $0.taskID == target.id })
        #expect(DupOracle.ranking(capture, household).map(\.task.id).firstIndex(of: target.id) == 10)   // 11th
        var marker = DuplicateMarker()
        let marked = marker.mark(F.draft(1, "wipe the counter"), position: 1, claim: DuplicateClaim(), check: check)
        #expect(marked.duplicate == .ofExisting(target.id))
        // An out-of-range index (the model guessing 11) is ignored, and the floor still decides.
        let guessed = marker.mark(F.draft(2, "Wipe the counter"), position: 2,
                                  claim: DuplicateClaim(sameAsShortlistIndex: 11), check: check)
        #expect(guessed.duplicate == .ofExisting(target.id))
    }

    @Test("AC-M2-07: cloud, Q12 = yes: index n becomes ofExisting(shortlist[n].id) only for 1 ≤ n ≤ count", arguments: [
        (1, H.counter.id as UUID?), (2, H.pods.id), (3, H.oven.id), (0, nil), (-1, nil), (4, nil), (11, nil),
        (Int.max, nil), (Int.min, nil),
    ] as [(Int, UUID?)])
    func cloudIndex(_ index: Int, _ expected: UUID?) {
        var marker = DuplicateMarker()
        let marked = marker.mark(F.draft(1, "x"), position: 1, claim: DuplicateClaim(sameAsShortlistIndex: index),
                                 check: .sentShortlist(Self.shortlist, H.household))
        #expect(marked.duplicate == (expected.map { DraftDuplicate.ofExisting($0) } ?? .none))
    }

    @Test("AC-M2-07: cloud, Q12 = yes: a title claim is not a claim on this path (only the index); the floor still runs")
    func cloudYesIgnoresOthers() {
        var marker = DuplicateMarker()
        let titleOnly = marker.mark(F.draft(1, "Dust the lamp"), position: 1,
                                    claim: DuplicateClaim(sameAsTitle: "Wipe kitchen counter"),
                                    check: .sentShortlist(Self.shortlist, H.household))
        #expect(titleOnly.duplicate == .none)
        let floor = marker.mark(F.draft(2, "wipe the kitchen counter"), position: 2,
                                claim: DuplicateClaim(sameAsTitle: "Buy dish pods"),
                                check: .sentShortlist(Self.shortlist, H.household))
        #expect(floor.duplicate == .ofExisting(H.counter.id))
    }

    @Test("AC-M2-07: cloud, Q12 = no: the local word-match marks without any claim, and an index claim is ignored")
    func cloudNo() {
        var marker = DuplicateMarker()
        let matched = marker.mark(F.draft(1, "wipe the kitchen counter", room: .existing(H.kitchen.id)), position: 1,
                                  claim: DuplicateClaim(), check: .localWordMatch(H.household))
        #expect(matched.duplicate == .ofExisting(H.counter.id))
        let indexOnly = marker.mark(F.draft(2, "dust lamp"), position: 2,
                                    claim: DuplicateClaim(sameAsShortlistIndex: 1), check: .localWordMatch(H.household))
        #expect(indexOnly.duplicate == .none)
    }

    @Test("AC-M2-07: the Q12 parameter picks the path: yes sends the capture's shortlist, no uses the local word-match")
    func q12Parameter() {
        let capture = "wipe the kitchen, and we're out of dishwasher pods"
        #expect(CloudTitleSharing.shortlistTitles.existingTaskCheck(capture: capture, household: H.household)
                == .sentShortlist(DuplicateShortlist.entries(for: capture, in: H.household), H.household))
        #expect(CloudTitleSharing.noTitles.existingTaskCheck(capture: capture, household: H.household)
                == .localWordMatch(H.household))
    }

    @Test("AC-M2-07: a completed one-off or restock task is not a duplicate target on any path", arguments: [
        H.milk, H.parcel,
    ])
    func completedNotTarget(_ done: HouseholdTask) {
        let title = done.title
        var log = DuplicateLookupLog(household: H.household)
        #expect(log.lookUp(title).allSatisfy { $0.title != title })
        var marker = DuplicateMarker()
        let device = marker.mark(F.draft(1, title), position: 1, claim: DuplicateClaim(sameAsTitle: title),
                                 check: .toolLookups(log))
        let sent = DuplicateShortlist.entries(for: title, in: H.household)
        let cloudYes = marker.mark(F.draft(2, title), position: 2,
                                   claim: DuplicateClaim(sameAsShortlistIndex: 1), check: .sentShortlist(sent, H.household))
        let cloudNo = marker.mark(F.draft(3, title), position: 3, claim: DuplicateClaim(),
                                  check: .localWordMatch(H.household))
        for marked in [device, cloudYes, cloudNo] {
            #expect(marked.duplicate != .ofExisting(done.id))
        }
        #expect(device.duplicate == .none && cloudNo.duplicate == .none)
    }

    @Test("AC-M2-07: a repeat within one input collapses into its first draft; positions map to draftIDs")
    func inInputCollapse() {
        var marker = DuplicateMarker()
        let check = ExistingTaskCheck.localWordMatch(Household(tasks: [], rooms: []))
        let one = marker.mark(F.draft(1, "buy bread"), position: 1, claim: DuplicateClaim(), check: check)
        // Position 2 was skipped by Q5 (no draft). Position 3 is draft 2.
        let two = marker.mark(F.draft(2, "get bread"), position: 3, claim: DuplicateClaim(sameAsItem: 1), check: check)
        let three = marker.mark(F.draft(3, "bread!"), position: 4, claim: DuplicateClaim(sameAsItem: 3), check: check)
        let toSkipped = marker.mark(F.draft(4, "milk"), position: 5, claim: DuplicateClaim(sameAsItem: 2), check: check)
        let toSelf = marker.mark(F.draft(5, "eggs"), position: 6, claim: DuplicateClaim(sameAsItem: 6), check: check)
        let toLater = marker.mark(F.draft(6, "jam"), position: 7, claim: DuplicateClaim(sameAsItem: 9), check: check)
        let toZero = marker.mark(F.draft(7, "tea"), position: 8, claim: DuplicateClaim(sameAsItem: 0), check: check)
        #expect(one.duplicate == .none)
        #expect(two.duplicate == .ofDraft(1))
        #expect(three.duplicate == .ofDraft(1))        // collapses into the first draft, not into draft 2
        #expect(toSkipped.duplicate == .none)
        #expect(toSelf.duplicate == .none)
        #expect(toLater.duplicate == .none)
        #expect(toZero.duplicate == .none)
    }

    @Test("AC-M2-07: a repeat of a draft that is itself ofExisting is ofDraft of that draft; an in-input claim wins over an existing one")
    func inInputOverExisting() {
        var marker = DuplicateMarker()
        let check = ExistingTaskCheck.sentShortlist(Self.shortlist, H.household)
        let first = marker.mark(F.draft(1, "wipe counter"), position: 1,
                                claim: DuplicateClaim(sameAsShortlistIndex: 1), check: check)
        let again = marker.mark(F.draft(2, "wipe the counter"), position: 2,
                                claim: DuplicateClaim(sameAsItem: 1, sameAsShortlistIndex: 1), check: check)
        #expect(first.duplicate == .ofExisting(H.counter.id))
        #expect(again.duplicate == .ofDraft(1))
    }

    @Test("AC-M2-07: an invalid in-input claim falls back to the existing-task check")
    func invalidItemFallsBack() {
        var marker = DuplicateMarker()
        let marked = marker.mark(F.draft(1, "wipe counter"), position: 1,
                                 claim: DuplicateClaim(sameAsItem: 1, sameAsShortlistIndex: 2),
                                 check: .sentShortlist(Self.shortlist, H.household))
        #expect(marked.duplicate == .ofExisting(H.pods.id))
    }

    @Test("AC-M2-07: marking keeps every other draft field, and replaces a marker already set")
    func keepsFields() {
        var marker = DuplicateMarker()
        var input = F.draft(4, "Wipe kitchen counter", room: .existing(H.kitchen.id), kind: .restock)
        input.duplicate = .ofDraft(99)
        let marked = marker.mark(input, position: 4, claim: DuplicateClaim(), check: .localWordMatch(H.household))
        var expected = input
        expected.duplicate = .ofExisting(H.counter.id)
        #expect(marked == expected)
    }

    @Test("AC-M2-07, Q7: checking duplicates never changes the household or the existing task")
    func householdUnchanged() {
        let before = H.household
        var log = DuplicateLookupLog(household: H.household)
        _ = log.lookUp("kitchen pods counter")
        var marker = DuplicateMarker()
        for check in [ExistingTaskCheck.toolLookups(log), .sentShortlist(Self.shortlist, H.household), .localWordMatch(H.household)] {
            _ = marker.mark(F.draft(1, "Buy dish pods"), position: 1,
                            claim: DuplicateClaim(sameAsShortlistIndex: 2, sameAsTitle: "Buy dish pods"), check: check)
        }
        #expect(H.household == before)
        #expect(log.household == before)
    }
}

// MARK: - The re-check at commit

@Suite("AC-M2-07 the ofExisting re-check at commit (brief Definitions; FR-A1)")
struct DuplicateRecheckTests {

    @Test("AC-M2-07: ofExisting stays only while its target exists and is not completed; commit then creates nothing for it")
    func recheck() {
        let live = F.task(F.id("000000000001"), "Buy dish pods", kind: .restock)
        let done = F.task(F.id("000000000002"), "Buy milk", kind: .restock, state: .completed)
        let household = Household(tasks: [live, done], rooms: [])
        #expect(DuplicateRecheck.atCommit(.ofExisting(live.id), in: household) == .ofExisting(live.id))
        #expect(DuplicateRecheck.atCommit(.ofExisting(done.id), in: household) == .none)
        #expect(DuplicateRecheck.atCommit(.ofExisting(F.id("0000000000FF")), in: household) == .none)
        #expect(DuplicateRecheck.atCommit(.ofDraft(3), in: household) == .ofDraft(3))
        #expect(DuplicateRecheck.atCommit(.none, in: household) == .none)
        #expect(DuplicateRecheck.atCommit(.ofExisting(live.id), in: household).createsTask == false)
        #expect(DuplicateRecheck.atCommit(.ofExisting(done.id), in: household).createsTask == true)
        #expect(DraftDuplicate.ofDraft(1).createsTask == false)
    }
}
