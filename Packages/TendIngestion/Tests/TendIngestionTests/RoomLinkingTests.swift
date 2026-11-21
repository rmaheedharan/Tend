// AC-M2-04: room linking with name folding (brief S-M2-01, Definitions "Name folding", T-09). FR-A1. Plan WI-M2-04.
//
// Expected values are written from the brief:
// - a draft's room links to the existing room whose name equals it after name folding (exact, not fuzzy);
// - if several rooms fold to the same name, the room with the lowest `id.uuidString` wins;
// - if none matches, the draft carries `proposed(name)`, the model's text after the calm-words guard; if the guard
//   leaves it empty, the room is `none`;
// - a proposed room is created only on commit, and two confirmed drafts whose names fold the same create one room;
// - no room is created or renamed during parsing.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

@Suite("AC-M2-04 room linking with name folding (FR-A1)")
struct RoomLinkingTests {

    static func id(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID()
    }

    static let kitchen = Room(id: id("000000000001"), name: "Kitchen")
    static let kids = Room(id: id("000000000002"), name: "Kid\u{2019}s Room")         // typographic apostrophe
    static let cafe = Room(id: id("000000000003"), name: "Café")
    static let bathroom = Room(id: id("000000000004"), name: "Bathroom")
    static let sams = Room(id: id("000000000005"), name: "Sam's room")                 // brief Q19 example
    static let balcony = Room(id: id("000000000006"), name: "  The   Balcony ")
    static let rooms = [kitchen, kids, cafe, bathroom, sams, balcony]

    // MARK: Linking (parse time)

    @Test("AC-M2-04: a room name links to the existing room that equals it after name folding", arguments: [
        ("kitchen", kitchen.id),
        ("KITCHEN", kitchen.id),
        ("  the   Kitchen ", kitchen.id),            // trim, collapse, one leading article ("the kitchen", T-09)
        ("My kitchen", kitchen.id),
        ("our Kitchen", kitchen.id),
        ("Kid's room", kids.id),                     // ASCII apostrophe matches the typographic one
        ("kid\u{2019}s ROOM", kids.id),
        ("Cafe", cafe.id),                           // diacritic fold
        ("Cafe\u{0301}", cafe.id),                   // decomposed accent
        ("ＫＩＴＣＨＥＮ", kitchen.id),                // width fold
        ("SAM\u{2019}S ROOM", sams.id),
        ("balcony", balcony.id),                     // the stored name is folded too (both sides)
        ("the balcony", balcony.id),
    ])
    func linksByNameFolding(modelText: String, expected: UUID) {
        #expect(RoomLinker.link(modelText, in: Self.rooms) == .existing(expected))
    }

    @Test("AC-M2-04: matching is exact after folding, never fuzzy: no plural, stem, spacing or partial match", arguments: [
        "kitchens",
        "kitch",
        "kitchen 2",
        "bath room",                  // "Bathroom" is one word
        "the the kitchen",            // only one article is stripped
        "kitchen.",                   // punctuation is not folded away
        "kids room",                  // the apostrophe matters
        "Cafes",
    ])
    func noFuzzyMatch(modelText: String) {
        #expect(RoomLinker.link(modelText, in: Self.rooms) == .proposed(modelText))
    }

    @Test("AC-M2-04: no room name, or a name that folds to empty, gives no room", arguments: [nil, "", "   ", "\n\t"]
          as [String?])
    func noName(modelText: String?) {
        #expect(RoomLinker.link(modelText, in: Self.rooms) == .none)
    }

    @Test("AC-M2-04: a proposed name keeps the model's text, trimmed and collapsed", arguments: [
        ("Sun room", "Sun room"),
        ("  Sun   room ", "Sun room"),
        ("The Attic", "The Attic"),
    ])
    func proposedKeepsText(modelText: String, expected: String) {
        #expect(RoomLinker.link(modelText, in: Self.rooms) == .proposed(expected))
    }

    @Test("AC-M2-04: if several rooms fold to the same name, the lowest id.uuidString wins, in any array order")
    func tieGoesToLowestUUIDString() {
        let high = Room(id: Self.id("00000000000F"), name: "Garage")
        let low = Room(id: Self.id("00000000000A"), name: "the GARAGE")
        let lower = Room(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009") ?? UUID(), name: "garáge")
        for order in [[high, low, lower], [lower, high, low], [low, lower, high]] {
            #expect(RoomLinker.link("Garage", in: order) == .existing(lower.id))
        }
        // uuidString order is byte order of the uppercase hex string ("9" < "A" < "F").
        #expect(RoomLinker.link("garage", in: [high, low]) == .existing(low.id))
    }

    @Test("AC-M2-04: linking compares only the folded names (an empty household proposes)")
    func emptyHousehold() {
        #expect(RoomLinker.link("Kitchen", in: []) == .proposed("Kitchen"))
    }

    @Test("AC-M2-04: no room is created or renamed during parsing (linking and the guard leave the household alone)")
    func parsingCreatesNoRoom() {
        let household = Household(tasks: [], rooms: Self.rooms)
        let before = household
        for name in ["Kitchen", "Sun room", "late room", "Overdue", nil] as [String?] {
            let room = RoomLinker.link(name, in: household.rooms)
            _ = CalmWordsGuard.apply(title: "Tidy", room: room, sourcePhrase: nil, input: "tidy up")
        }
        #expect(household == before)
        #expect(household.rooms.map(\.name) == Self.rooms.map(\.name))
    }

    // MARK: Link, then guard (proposed names only)

    @Test("AC-M2-04: an unmatched name is proposed after the calm-words guard; an emptied name becomes none", arguments: [
        // (model room text, input, expected)
        ("Late room", "tidy up", DraftRoom.proposed("room")),
        ("Overdue", "tidy up", DraftRoom.none),
        ("Kitchen", "tidy up", DraftRoom.existing(kitchen.id)),          // existing: the guard does not apply
        ("Penalty box", "the penalty box needs a tidy", DraftRoom.proposed("Penalty box")),
    ])
    func linkThenGuard(modelText: String, input: String, expected: DraftRoom) {
        let linked = RoomLinker.link(modelText, in: Self.rooms)
        let decision = CalmWordsGuard.apply(title: "Tidy", room: linked, sourcePhrase: nil, input: input)
        #expect(decision == .keep(title: "Tidy", room: expected))
    }

    @Test("AC-M2-04: a household room whose own name holds a banned token still links (it is the user's label)")
    func userLabelWithBannedTokenLinks() {
        let room = Room(id: Self.id("0000000000B1"), name: "Late-night den")
        let linked = RoomLinker.link("late-night den", in: [room])
        #expect(linked == .existing(room.id))
        #expect(CalmWordsGuard.apply(title: "Tidy", room: linked, sourcePhrase: nil, input: "tidy up")
                == .keep(title: "Tidy", room: .existing(room.id)))
    }

    // MARK: Commit

    final class IDSource {
        var issued: [UUID] = []
        var next = 0
        func make() -> UUID {
            next += 1
            let id = UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", next)) ?? UUID()
            issued.append(id)
            return id
        }
    }

    @Test("AC-M2-04: two confirmed drafts proposing names that fold the same create one room")
    func oneRoomForEqualProposals() {
        let ids = IDSource()
        let plan = RoomLinker.commitPlan(for: [.proposed("Sun room"), .proposed("the SUN  room"), .proposed("Sún Room")],
                                         existing: Self.rooms, makeID: ids.make)
        #expect(plan.newRooms.count == 1)
        #expect(plan.newRooms.first?.name == "Sun room")          // the first confirmed draft's text
        #expect(ids.issued.count == 1)
        let created = ids.issued.first
        #expect(plan.roomIDs == [created, created, created])
    }

    @Test("AC-M2-04: distinct proposals create one room each, in confirmed order")
    func distinctProposals() {
        let ids = IDSource()
        let plan = RoomLinker.commitPlan(for: [.proposed("Sun room"), .none, .proposed("Attic"), .existing(Self.cafe.id)],
                                         existing: Self.rooms, makeID: ids.make)
        #expect(plan.newRooms.map(\.name) == ["Sun room", "Attic"])
        #expect(plan.newRooms.map(\.id) == ids.issued)
        #expect(plan.roomIDs == [ids.issued[0], nil, ids.issued[1], Self.cafe.id])
        #expect(plan.newRooms.allSatisfy { $0.lastTendedAt == nil })
    }

    @Test("AC-M2-04: a proposal that folds to an existing room's name creates no room and uses that room")
    func proposalMatchingExistingRoomAtCommit() {
        let ids = IDSource()
        // For example "late kitchen" guarded to "kitchen" at parse time, or a room added between parse and commit.
        let plan = RoomLinker.commitPlan(for: [.proposed("kitchen")], existing: Self.rooms, makeID: ids.make)
        #expect(plan.newRooms.isEmpty)
        #expect(ids.issued.isEmpty)
        #expect(plan.roomIDs == [Self.kitchen.id])
    }

    @Test("AC-M2-04: an existing room that is no longer in the household gives no room; nothing is created")
    func missingExistingRoom() {
        let ids = IDSource()
        let gone = Self.id("0000000000FF")
        let plan = RoomLinker.commitPlan(for: [.existing(gone), .existing(Self.kitchen.id)], existing: Self.rooms,
                                         makeID: ids.make)
        #expect(plan.newRooms.isEmpty)
        #expect(plan.roomIDs == [nil, Self.kitchen.id])
    }

    @Test("AC-M2-04: nothing confirmed, nothing created")
    func nothingConfirmed() {
        let ids = IDSource()
        let plan = RoomLinker.commitPlan(for: [], existing: Self.rooms, makeID: ids.make)
        #expect(plan.newRooms.isEmpty && plan.roomIDs.isEmpty && ids.issued.isEmpty)
    }
}

@Suite("sourcePhrase substring check (brief Definitions; Q5 step 8; FR-A1)")
struct SourcePhraseCheckTests {

    static let briefInput = CalmWordsGuardTests.briefInput

    @Test("sourcePhrase is kept when it occurs in the input as a substring after name folding", arguments: [
        "The AC needs servicing before summer",
        "the ac needs servicing",
        "  THE  AC  needs servicing ",                     // trim and collapse on the phrase side
        "dishwasher pods",
        "we\u{2019}re almost out of dishwasher pods",      // typographic apostrophe against the input's ASCII one
        "deep clean the balcony this weekend",
        "doesn\u{2019}t rain",
        "balcony",
        "the balcony",                                     // one article stripped from the phrase, then found
        "alcon",                                           // a substring, literally (not a whole-word rule)
    ])
    func kept(phrase: String) {
        #expect(SourcePhrase.checked(phrase, input: Self.briefInput) == phrase)   // returned exactly as given
    }

    @Test("sourcePhrase is nil when it does not occur in the folded input", arguments: [
        "mow the lawn",
        "dishwasher pod packs",
        "the AC needs  a service",
        "balconies",
        "summer, we're almost out of dishwasher pods, and let's deep clean the balcony this weekend if it doesn't snow",
    ])
    func dropped(phrase: String) {
        #expect(SourcePhrase.checked(phrase, input: Self.briefInput) == nil)
    }

    @Test("sourcePhrase is nil when it is nil or folds to empty", arguments: [nil, "", "   ", "\n"] as [String?])
    func empty(phrase: String?) {
        #expect(SourcePhrase.checked(phrase, input: Self.briefInput) == nil)
    }

    @Test("sourcePhrase folding applies to both sides (case, diacritics, width; a leading article in the input)")
    func bothSidesFolded() {
        #expect(SourcePhrase.checked("cafe table", input: "Wipe the CAFÉ table") == "cafe table")
        #expect(SourcePhrase.checked("ＣＡＦＥ", input: "wipe the café table") == "ＣＡＦＥ")
        #expect(SourcePhrase.checked("AC needs", input: "The AC needs servicing") == "AC needs")
        #expect(SourcePhrase.checked("x", input: "") == nil)
    }
}
