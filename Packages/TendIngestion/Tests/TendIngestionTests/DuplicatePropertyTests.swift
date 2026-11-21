// AC-M2-07 oracle property and the Linux marking half of AC-M2-08. FR-A1, Q12, T-06. Plan WI-M2-07.
//
// AC-M2-07: "The shortlist and the local word-match rule (Definitions) equal an independent oracle over ≥ 500 seeded
// households (T-06)". Here: 3 seeds × 200 households = 600 households, 14 queries and 14 word-match drafts each. The
// cases include ties at every ranking step, more than 10 eligible tasks, completed tasks, room-only matches and
// stop-word-only queries; a coverage check requires each class on every seed.
//
// AC-M2-08 (Linux marking half; commit is WI-M2-08): 3 seeds × 200 = 600 households and scripted draft sets with planted
// duplicates by exact title, by synonym (scripted in the mock) and within one input, plus completed-task repeats, each
// run on all three paths: on device (the mock calls the Tool), cloud Q12 = yes (the mock names a shortlist index) and
// cloud Q12 = no (the local word-match). The deterministic rule the mock scripts is: a planted draft repeats its target
// when the mock can see the target on that path, and the mock then claims it. Checked for every draft:
// - the marker equals the independent oracle (`DupOracle.marks`);
// - a planted duplicate the path can see is never left as `none` (so commit would create nothing for it);
// - `ofExisting` always names a task that exists and is not completed; `ofDraft` always names an earlier draft that is
//   not itself `ofDraft` (the collapse goes to the first draft).
// Planted duplicates the path cannot see (a target outside the shortlist; a synonym under Q12 = no, which the brief
// says the word-match misses) are counted and printed, not hidden.
//
// The seed is printed by every test and is in every failure message.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

private typealias F = DupFixture

// MARK: - Generator

struct DupHouseholdGenerator {
    var rnd: DupRandom

    static let roomNames = ["Kitchen", "Bathroom", "Sam\u{2019}s room", "the Garage", "Café", "Living room", "The",
                            "Kids' room", "Hall", "Laundry", "KITCHEN", "my office"]
    static let words = ["buy", "dish", "pods", "dishwasher", "wipe", "kitchen", "counter", "clean", "oven", "the", "a",
                        "my", "Café", "cafe", "CAFÉ", "laundry", "sheets", "water", "plants", "hall", "room", "garage",
                        "dust", "shelf", "milk", "2", "bathroom", "tiles", "of", "and", "need", "Sam\u{2019}s", "s",
                        "living", "office", "kids", "fold", "towels", "bins", "out", "Buy", "DUST"]
    static let stopOnly = ["the", "a", "and", "of", "we", "need", "to", "it", "please", "um", "ok", "again", "my"]
    static let separators = [" ", " ", " ", "  ", "\t", "\n", "\u{00A0}", ", ", " - ", "! "]

    mutating func phrase(_ count: Int, from pool: [String]) -> String {
        var text = ""
        for _ in 0..<count {
            let word = rnd.pick(pool)
            text = text.isEmpty ? word : text + rnd.pick(Self.separators) + word
        }
        return text
    }

    mutating func household() -> Household {
        var rooms: [Room] = []
        for _ in 0..<rnd.int(0...6) { rooms.append(Room(id: rnd.uuid(), name: rnd.pick(Self.roomNames))) }
        var tasks: [HouseholdTask] = []
        let count = rnd.chance(30) ? rnd.int(30...60) : rnd.int(3...30)
        // A "theme" word that many tasks share, so that > 10 eligible tasks and ties are common.
        let theme = rnd.pick(["buy", "dust", "clean", "wipe"])
        for _ in 0..<count {
            var title: String
            if !tasks.isEmpty && rnd.chance(15) {
                let earlier = rnd.pick(tasks).title
                title = rnd.chance(50) ? earlier : (rnd.chance(50) ? earlier.uppercased() : "  " + earlier + " ")
            } else if rnd.chance(4) {
                title = phrase(rnd.int(1...3), from: Self.stopOnly)
            } else {
                title = phrase(rnd.int(1...4), from: Self.words)
                if rnd.chance(35) { title = theme + " " + title }
            }
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = "dust" }
            var roomID: UUID?
            if !rooms.isEmpty && rnd.chance(60) { roomID = rnd.pick(rooms).id } else if rnd.chance(10) { roomID = rnd.uuid() }
            let state = rnd.pick([F.StateChoice.active, .active, .active, .deferred, .maintenance, .resurfaced,
                                  .completed, .completed])
            let kind = rnd.pick([TaskKind.oneOff, .recurring, .restock])
            // Sometimes give a task an ID that shares a long prefix with another, to stress the uuidString tie-break.
            let id: UUID
            if let last = tasks.last, rnd.chance(10) {
                var u = last.id.uuid
                u.15 = UInt8(truncatingIfNeeded: rnd.next())
                id = UUID(uuid: u)
            } else {
                id = rnd.uuid()
            }
            if tasks.contains(where: { $0.id == id }) { continue }
            tasks.append(F.task(id, title, kind: kind, room: roomID, state: state))
        }
        return Household(tasks: tasks, rooms: rooms)
    }

    mutating func query(_ household: Household) -> String {
        switch rnd.int(0...9) {
        case 0: return phrase(rnd.int(1...4), from: Self.stopOnly)
        case 1: return household.rooms.isEmpty ? "" : rnd.pick(household.rooms).name
        case 2: return household.tasks.isEmpty ? "" : rnd.pick(household.tasks).title
        case 3: return household.rooms.isEmpty ? "dust" : phrase(rnd.int(0...2), from: Self.words) + " "
            + rnd.pick(household.rooms).name
        case 4: return ""
        default: return phrase(rnd.int(1...6), from: Self.words + Self.stopOnly)
        }
    }

    /// A draft title and room for the word-match property: often a variant of an existing title.
    mutating func wordMatchDraft(_ household: Household) -> (String, DraftRoom) {
        var title: String
        if let task = household.tasks.isEmpty ? nil : rnd.pick(household.tasks), rnd.chance(70) {
            var words = task.title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            switch rnd.int(0...4) {
            case 0: break
            case 1: if words.count > 1 { words.remove(at: rnd.int(0...(words.count - 1))) }
            case 2: words.append(rnd.pick(Self.words))
            case 3: words.insert(rnd.pick(Self.stopOnly), at: 0)
            default: words = words.map { $0.uppercased() }
            }
            title = words.joined(separator: rnd.pick([" ", "  ", "\t"]))
        } else {
            title = phrase(rnd.int(1...4), from: Self.words + Self.stopOnly)
        }
        if title.isEmpty { title = "dust" }
        let room: DraftRoom
        switch rnd.int(0...3) {
        case 0: room = .none
        case 1: room = .proposed(rnd.pick(["Scullery", "Attic", "Porch"]))
        default:
            if household.rooms.isEmpty { room = .none } else { room = .existing(rnd.pick(household.rooms).id) }
        }
        return (title, room)
    }
}

// MARK: - AC-M2-07 property

@Suite("AC-M2-07 property: the shortlist and the local word-match equal an independent oracle (T-06, FR-A1)")
struct DuplicateOraclePropertyTests {

    static let seeds: [UInt64] = [0x0D0B_1E5E_ED00_0701, 0x0D0B_1E5E_ED00_0702, 0x0D0B_1E5E_ED00_0703]
    static let householdsPerSeed = 200
    static let queriesPerHousehold = 14
    static let draftsPerHousehold = 14

    @Test("AC-M2-07: 600 seeded households: shortlist and word-match equal the oracle; ties at every step, > 10 eligible, completed left out, room-only, stop-word-only all covered", arguments: seeds)
    func property(seed: UInt64) {
        var gen = DupHouseholdGenerator(rnd: DupRandom(seed: seed))
        var queries = 0, mismatches = 0, drafts = 0, wordMismatches = 0
        var tiesDecidedAt: [DupOracle.Step: Int] = [:]
        var overTen = 0, completedWouldMatch = 0, roomOnly = 0, stopOnlyQueries = 0, entriesTotal = 0
        var matchKinds: [String: Int] = [:]
        for h in 0..<Self.householdsPerSeed {
            let household = gen.household()
            for q in 0..<Self.queriesPerHousehold {
                let query = gen.query(household)
                queries += 1
                let actual = DuplicateShortlist.entries(for: query, in: household)
                let expected = DupOracle.shortlist(query, household)
                if actual != expected {
                    mismatches += 1
                    Issue.record("seed 0x\(String(seed, radix: 16)) household \(h) query \(q) \(query.debugDescription): \(actual) != \(expected)")
                }
                #expect(actual.count <= 10)
                #expect(DuplicateLookup.entries(for: query, in: household)
                        == expected.map { DuplicateLookupEntry(title: $0.title, kind: $0.kind, roomName: $0.roomName) },
                        "seed 0x\(String(seed, radix: 16)) household \(h) query \(q)")
                entriesTotal += actual.count
                // Coverage, from the oracle's full ranking.
                let ranking = DupOracle.ranking(query, household)
                if ranking.count > 10 { overTen += 1 }
                for pair in zip(ranking, ranking.dropFirst()).prefix(10) {
                    if let step = DupOracle.decides(pair.0, pair.1) { tiesDecidedAt[step, default: 0] += 1 }
                }
                roomOnly += expected.filter { e in ranking.contains { $0.task.id == e.taskID && $0.k == 0 && $0.r == 1 } }.count
                let qk = DupOracle.keywords(query)
                if qk.isEmpty && !query.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).isEmpty {
                    stopOnlyQueries += 1
                    #expect(actual.isEmpty, "seed 0x\(String(seed, radix: 16)): stop-word-only query \(query.debugDescription)")
                }
                completedWouldMatch += household.tasks.filter {
                    $0.state == .completed && !DupOracle.keywords($0.title).isDisjoint(with: qk)
                }.count
            }
            for d in 0..<Self.draftsPerHousehold {
                let (title, room) = gen.wordMatchDraft(household)
                drafts += 1
                let actual = LocalWordMatch.target(title: title, room: room, in: household)
                let expected = DupOracle.wordMatch(title, room, household)
                if actual != expected {
                    wordMismatches += 1
                    Issue.record("seed 0x\(String(seed, radix: 16)) household \(h) draft \(d) \(title.debugDescription) \(room): \(String(describing: actual)) != \(String(describing: expected))")
                }
                let qualifying = DupOracle.qualifying(title, room, household)
                for q in qualifying { matchKinds[q.how.rawValue, default: 0] += 1 }
                if qualifying.count > 1 { matchKinds["severalQualify", default: 0] += 1 }
                if let top = qualifying.map(\.shared).max(), qualifying.filter({ $0.shared == top }).count > 1 {
                    matchKinds["tieOnShared", default: 0] += 1
                }
                if expected == nil { matchKinds["noMatch", default: 0] += 1 }
                let kws = DupOracle.keywords(title)
                if kws.count == 1, household.tasks.contains(where: {
                    $0.state != .completed && DupOracle.keywords($0.title).count > 1 && kws.isSubset(of: DupOracle.keywords($0.title))
                }) { matchKinds["oneKeywordSubsetRejected", default: 0] += 1 }
                if household.tasks.contains(where: { $0.state == .completed && DupOracle.keywords($0.title) == kws && !kws.isEmpty }) {
                    matchKinds["completedEqualSetLeftOut", default: 0] += 1
                }
                let ignoringRooms = DupOracle.qualifying(title, .none, household).count
                if ignoringRooms > qualifying.count { matchKinds["roomIncompatible", default: 0] += 1 }
            }
        }
        let steps = DupOracle.Step.allCases.map { "\($0.rawValue) \(tiesDecidedAt[$0, default: 0])" }.joined(separator: ", ")
        print("AC-M2-07 property: seed 0x\(String(seed, radix: 16, uppercase: true)), \(Self.householdsPerSeed) households, "
              + "\(queries) queries (\(entriesTotal) entries), \(mismatches) shortlist mismatches; "
              + "neighbours decided at: \(steps); > 10 eligible: \(overTen); room-only entries: \(roomOnly); "
              + "completed tasks sharing a keyword (left out): \(completedWouldMatch); stop-word-only queries: \(stopOnlyQueries); "
              + "word-match drafts \(drafts), \(wordMismatches) mismatches, classes \(matchKinds.sorted { $0.key < $1.key })")
        #expect(mismatches == 0 && wordMismatches == 0)
        // Coverage on every seed (the brief's list, T-06).
        for step in [DupOracle.Step.k, .r, .title, .uuid] {
            #expect(tiesDecidedAt[step, default: 0] > 0, "seed 0x\(String(seed, radix: 16)): no neighbours decided at \(step)")
        }
        #expect(overTen > 0 && roomOnly > 0 && completedWouldMatch > 0 && stopOnlyQueries > 0,
                "seed 0x\(String(seed, radix: 16)): a required case class did not occur")
        for name in ["equalSets", "subset", "tieOnShared", "severalQualify", "noMatch", "oneKeywordSubsetRejected",
                     "completedEqualSetLeftOut", "roomIncompatible"] {
            #expect(matchKinds[name, default: 0] > 0, "seed 0x\(String(seed, radix: 16)): no word-match case \(name)")
        }
    }
}

// MARK: - AC-M2-08 marking property (Linux half)

@Suite("AC-M2-08 property: planted duplicates are marked on all three paths (FR-A1, Q12)")
struct DuplicateMarkingPropertyTests {

    static let seeds: [UInt64] = [0x0D0B_1E5E_ED00_0801, 0x0D0B_1E5E_ED00_0802, 0x0D0B_1E5E_ED00_0803]
    static let householdsPerSeed = 200

    enum Plant: String, CaseIterable { case fresh, exact, synonym, inInput, completedRepeat, bogusClaim, skipped }

    struct Scripted {
        var plant: Plant
        var title: String
        var room: DraftRoom
        /// The existing task the mock means (exact, synonym, completed repeat).
        var target: HouseholdTask?
        /// The earlier position the mock means (in-input).
        var earlier: Int?
    }

    static let synonymWords = ["refill", "restock", "grab", "pick up", "sort", "freshen", "scrub", "tidy"]

    /// Builds the mock's script: what it says, item by item, independent of the path.
    static func script(_ household: Household, _ rnd: inout DupRandom) -> [Scripted] {
        let live = household.tasks.filter { $0.state != .completed && !DupOracle.keywords($0.title).isEmpty }
        let done = household.tasks.filter { $0.state == .completed && !DupOracle.keywords($0.title).isEmpty }
        var items: [Scripted] = []
        for position in 1...rnd.int(4...14) {
            var plant = rnd.pick(Plant.allCases)
            if (plant == .exact || plant == .synonym) && live.isEmpty { plant = .fresh }
            if plant == .completedRepeat && done.isEmpty { plant = .fresh }
            if plant == .inInput && !items.contains(where: { $0.plant != .skipped }) { plant = .fresh }
            func roomFor(_ task: HouseholdTask) -> DraftRoom {
                guard let id = task.roomID, household.rooms.contains(where: { $0.id == id }) else { return .none }
                return rnd.chance(70) ? .existing(id) : .none
            }
            switch plant {
            case .fresh, .bogusClaim, .skipped:
                let words = ["mend", "fence", "paint", "gate", "call", "plumber", "bake", "bread", "dust", "kitchen"]
                var title = ""
                for _ in 0..<rnd.int(1...3) { title += (title.isEmpty ? "" : " ") + rnd.pick(words) }
                items.append(Scripted(plant: plant, title: title, room: .none, target: nil, earlier: nil))
            case .exact:
                let t = rnd.pick(live)
                items.append(Scripted(plant: .exact, title: t.title.trimmingCharacters(in: .whitespaces),
                                      room: roomFor(t), target: t, earlier: nil))
            case .synonym:
                let t = rnd.pick(live)
                items.append(Scripted(plant: .synonym, title: rnd.pick(synonymWords) + " " + rnd.pick(["it", "that one", "the thing"]),
                                      room: .none, target: t, earlier: nil))
            case .completedRepeat:
                let t = rnd.pick(done)
                items.append(Scripted(plant: .completedRepeat, title: t.title, room: .none, target: t, earlier: nil))
            case .inInput:
                let candidates = items.indices.filter { items[$0].plant != .skipped }
                let k = rnd.pick(candidates)
                items.append(Scripted(plant: .inInput, title: items[k].title, room: items[k].room, target: nil,
                                      earlier: k + 1))
            }
            _ = position
        }
        return items
    }

    @Test("AC-M2-08: 600 seeded households × 3 paths: planted duplicates (exact, synonym, in-input) are marked as the oracle says; nothing the path can see is left unmarked", arguments: seeds)
    func property(seed: UInt64) {
        var rnd = DupRandom(seed: seed)
        var gen = DupHouseholdGenerator(rnd: DupRandom(seed: seed ^ 0xFFFF))
        var counts: [String: Int] = [:]
        var mismatches = 0
        for h in 0..<Self.householdsPerSeed {
            let household = gen.household()
            let script = Self.script(household, &rnd)
            let capture = script.map(\.title).joined(separator: ", and ")
            for mode in DupOracle.Mode.allCases {
                let label = "seed 0x\(String(seed, radix: 16)) household \(h) \(mode.rawValue)"
                var marker = DuplicateMarker()
                var log = DuplicateLookupLog(household: household)
                let check: ExistingTaskCheck
                switch mode {
                case .onDevice: check = .toolLookups(log)
                case .cloudTitles: check = CloudTitleSharing.shortlistTitles.existingTaskCheck(capture: capture, household: household)
                case .cloudNoTitles: check = CloudTitleSharing.noTitles.existingTaskCheck(capture: capture, household: household)
                }
                let sent = DupOracle.shortlist(capture, household)
                var oracleItems: [DupOracle.Item] = []
                var marked: [IngestionDraft] = []
                var visible: [Bool] = []
                var plants: [Plant] = []
                var nextDraftID = 1
                for (offset, s) in script.enumerated() {
                    let position = offset + 1
                    var claim = DuplicateClaim()
                    var canSee = false
                    switch s.plant {
                    case .exact, .synonym, .completedRepeat:
                        guard let target = s.target else { break }
                        switch mode {
                        case .onDevice:
                            // The mock asks the Tool with its own words, then with the target's wording.
                            for query in [s.title, target.title] {
                                let entries = log.lookUp(query)
                                if let entry = entries.first(where: { DupOracle.foldedTitle($0.title) == DupOracle.foldedTitle(target.title) }) {
                                    claim.sameAsTitle = rnd.chance(50) ? entry.title : entry.title.uppercased()
                                    canSee = true
                                    break
                                }
                            }
                            if s.plant == .completedRepeat && !canSee && rnd.chance(50) { claim.sameAsTitle = target.title }
                        case .cloudTitles:
                            if let n = sent.firstIndex(where: { $0.taskID == target.id }) {
                                claim.sameAsShortlistIndex = n + 1
                                canSee = true
                            }
                        case .cloudNoTitles:
                            canSee = s.plant == .exact && DupOracle.wordMatch(s.title, s.room, household) != nil
                        }
                    case .inInput:
                        claim.sameAsItem = s.earlier
                        canSee = true
                    case .bogusClaim:
                        switch rnd.int(0...4) {
                        case 0: claim.sameAsItem = position
                        case 1: claim.sameAsItem = position + rnd.int(1...3)
                        case 2: claim.sameAsShortlistIndex = rnd.pick([0, -1, sent.count + 1, 11])
                        case 3: claim.sameAsTitle = "no such task title"
                        default: claim.sameAsItem = 0
                        }
                    case .fresh, .skipped:
                        break
                    }
                    // `check` is the evidence at the time this item completes; on device that is the log so far.
                    let evidence: ExistingTaskCheck = mode == .onDevice ? .toolLookups(log) : check
                    if s.plant == .skipped {
                        oracleItems.append(DupOracle.Item(position: position, draft: nil, claim: claim, queriesSoFar: log.queries))
                        continue
                    }
                    let draft = F.draft(nextDraftID, s.title, room: s.room)
                    nextDraftID += 1
                    marked.append(marker.mark(draft, position: position, claim: claim, check: evidence))
                    oracleItems.append(DupOracle.Item(position: position, draft: draft, claim: claim, queriesSoFar: log.queries))
                    visible.append(canSee)
                    plants.append(s.plant)
                }
                let expected = DupOracle.marks(oracleItems, mode: mode, capture: capture, household: household)
                if marked.map(\.duplicate) != expected {
                    mismatches += 1
                    Issue.record("\(label): \(marked.map(\.duplicate)) != \(expected)")
                }
                for (i, draft) in marked.enumerated() {
                    let key = "\(mode.rawValue).\(plants[i].rawValue)"
                    counts[key, default: 0] += 1
                    if visible[i] { counts[key + ".visible", default: 0] += 1 }
                    if draft.duplicate != .none { counts[key + ".marked", default: 0] += 1 }
                    if visible[i] && (plants[i] == .exact || plants[i] == .synonym || plants[i] == .inInput) {
                        #expect(draft.duplicate != .none, "\(label) draft \(draft.draftID): a visible planted duplicate was left unmarked")
                    }
                    switch draft.duplicate {
                    case let .ofExisting(id):
                        let target = household.tasks.first { $0.id == id }
                        #expect(target != nil && target?.state != .completed, "\(label) draft \(draft.draftID): bad ofExisting")
                    case let .ofDraft(root):
                        let earlier = marked.first { $0.draftID == root }
                        #expect(root < draft.draftID, "\(label) draft \(draft.draftID): ofDraft not earlier")
                        if case .ofDraft = earlier?.duplicate { Issue.record("\(label) draft \(draft.draftID): not collapsed to the first draft") }
                    case .none:
                        break
                    }
                }
            }
        }
        print("AC-M2-08 marking property: seed 0x\(String(seed, radix: 16, uppercase: true)), \(Self.householdsPerSeed) households × 3 paths, "
              + "\(mismatches) oracle mismatches; counts \(counts.sorted { $0.key < $1.key })")
        #expect(mismatches == 0)
        for mode in DupOracle.Mode.allCases {
            for plant in [Plant.exact, .inInput, .completedRepeat, .bogusClaim, .fresh] {
                #expect(counts["\(mode.rawValue).\(plant.rawValue)", default: 0] > 0, "seed 0x\(String(seed, radix: 16)): no \(mode) \(plant)")
            }
            #expect(counts["\(mode.rawValue).exact.marked", default: 0] > 0)
            #expect(counts["\(mode.rawValue).inInput.marked", default: 0] > 0)
        }
        #expect(counts["onDevice.synonym.marked", default: 0] > 0 && counts["cloudTitles.synonym.marked", default: 0] > 0)
    }
}
