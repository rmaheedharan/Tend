// An independent oracle of the duplicate rules (AC-M2-07, AC-M2-08; T-06), written from the brief's Definitions.
// FR-A1. Plan WI-M2-07.
//
// Independence: the oracle calls **no** production code of `TendIngestion`, not even the WI-M2-04 text primitives.
// - Keywords: its own fold (typographic quotes to ASCII by a literal table, then Foundation's `folding` with the three
//   options in `en_US_POSIX`, the brief's primitive), its own split on `Character.isLetter || Character.isNumber`, and
//   its own copy of the stop-word list, pasted from the brief's text and split at ", ".
// - The keyword-folded title (shortlist step 5c): its own fold, then whitespace collapse with `Character.isWhitespace`.
// - Ranking: repeated selection of the best remaining candidate with an explicit step-by-step comparison, not a sort.
// - Word-match: a brute-force scan of every task.
// - Marking: its own position table and its own root search for the in-input collapse.
// The generators' alphabet is ASCII letters, digits, punctuation, `é`, typographic quotes, space, tab, newline and NBSP.
// On it, `Character.isLetter` / `isNumber` / `isWhitespace` agree with the production scalar classes (letters L*,
// digits Nd, Unicode White_Space).

import Foundation
import TendCore
@testable import TendIngestion

enum DupOracle {

    /// Pasted from the brief (Definitions, "Keywords of a text").
    static let stopWordText = "a, an, the, and, or, but, of, to, in, on, at, for, with, from, by, about, before, "
        + "after, this, that, these, those, it, its, is, are, be, been, was, were, we, us, our, i, me, my, you, your, "
        + "re, s, t, ll, ve, d, m, need, needs, let, lets, get, got, some, any, all, more, almost, out, up, again, also, "
        + "just, really, please, maybe, should, must, can, will, would, could, do, does, did, have, has, had, if, then, "
        + "so, too, very, no, not, wait, um, uh, like, okay, ok"
    static let stopWords = Set(stopWordText.components(separatedBy: ", "))

    static let quotes: [Character: Character] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{2032}": "'", "\u{02BC}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", "\u{2033}": "\"",
    ]

    static func fold(_ text: String) -> String {
        String(text.map { quotes[$0] ?? $0 })
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    static func keywords(_ text: String) -> Set<String> {
        var result: Set<String> = []
        var token = ""
        for character in fold(text) + " " {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else {
                if !token.isEmpty && !stopWords.contains(token) { result.insert(token) }
                token = ""
            }
        }
        return result
    }

    /// The keyword-folded title: fold, then trim and collapse whitespace.
    static func foldedTitle(_ text: String) -> String {
        fold(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func bytesBefore(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var i = 0
        while i < x.count && i < y.count {
            if x[i] != y[i] { return x[i] < y[i] }
            i += 1
        }
        return x.count < y.count
    }

    // MARK: Shortlist

    struct Candidate {
        var task: HouseholdTask
        var offset: Int
        var k: Int
        var r: Int
        var key: String
        var roomName: String?
    }

    /// Which ranking step separated two neighbours (for the coverage counts).
    enum Step: String, CaseIterable { case k, r, title, uuid, offset }

    static func room(of task: HouseholdTask, in household: Household) -> Room? {
        guard let id = task.roomID else { return nil }
        for room in household.rooms where room.id == id { return room }
        return nil
    }

    /// Candidate a ranks before b: the step that decides, or nil when b ranks before a.
    static func decides(_ a: Candidate, _ b: Candidate) -> Step? {
        if a.k != b.k { return a.k > b.k ? .k : nil }
        if a.r != b.r { return a.r > b.r ? .r : nil }
        if a.key != b.key { return bytesBefore(a.key, b.key) ? .title : nil }
        let ua = a.task.id.uuidString, ub = b.task.id.uuidString
        if ua != ub { return bytesBefore(ua, ub) ? .uuid : nil }
        return a.offset < b.offset ? .offset : nil
    }

    /// Every shortlisted candidate (no cap), in rank order.
    static func ranking(_ query: String, _ household: Household) -> [Candidate] {
        let q = keywords(query)
        var pool: [Candidate] = []
        for (offset, task) in household.tasks.enumerated() {
            if case .completed = task.state { continue }
            let k = keywords(task.title).intersection(q).count
            let room = room(of: task, in: household)
            var r = 0
            if let room {
                let rk = keywords(room.name)
                if !rk.isEmpty && rk.isSubset(of: q) { r = 1 }
            }
            if k >= 1 || r == 1 {
                pool.append(Candidate(task: task, offset: offset, k: k, r: r, key: foldedTitle(task.title),
                                      roomName: room?.name))
            }
        }
        var ranked: [Candidate] = []
        while !pool.isEmpty {
            var best = 0
            for i in pool.indices.dropFirst() where decides(pool[i], pool[best]) != nil { best = i }
            ranked.append(pool.remove(at: best))
        }
        return ranked
    }

    static func shortlist(_ query: String, _ household: Household) -> [ShortlistEntry] {
        var result: [ShortlistEntry] = []
        for candidate in ranking(query, household) {
            if result.count == 10 { break }
            result.append(ShortlistEntry(
                index: result.count + 1, taskID: candidate.task.id,
                title: candidate.task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: candidate.task.kind, roomName: candidate.roomName))
        }
        return result
    }

    // MARK: Word-match (Q12 = no)

    enum WordMatchKind: String, CaseIterable { case equalSets, subset }

    static func roomsCompatible(_ draftRoom: DraftRoom, _ task: HouseholdTask, _ household: Household) -> Bool {
        guard let taskRoom = room(of: task, in: household) else { return true }
        switch draftRoom {
        case .none: return true
        case .proposed: return false
        case let .existing(id): return id == taskRoom.id
        }
    }

    /// The qualifying tasks with their shared-keyword count and how they qualified.
    static func qualifying(_ title: String, _ draftRoom: DraftRoom, _ household: Household)
        -> [(task: HouseholdTask, shared: Int, how: WordMatchKind)] {
        let d = keywords(title)
        guard !d.isEmpty else { return [] }
        var result: [(task: HouseholdTask, shared: Int, how: WordMatchKind)] = []
        for task in household.tasks {
            if case .completed = task.state { continue }
            let t = keywords(task.title)
            if t.isEmpty { continue }
            let how: WordMatchKind
            if d == t {
                how = .equalSets
            } else if d.count < t.count, d.isSubset(of: t), d.count >= 2 {
                how = .subset
            } else if t.count < d.count, t.isSubset(of: d), t.count >= 2 {
                how = .subset
            } else {
                continue
            }
            if !roomsCompatible(draftRoom, task, household) { continue }
            result.append((task, d.intersection(t).count, how))
        }
        return result
    }

    static func wordMatch(_ title: String, _ draftRoom: DraftRoom, _ household: Household) -> UUID? {
        var best: (id: UUID, shared: Int)?
        for q in qualifying(title, draftRoom, household) {
            if let current = best {
                if q.shared > current.shared
                    || (q.shared == current.shared && bytesBefore(q.task.id.uuidString, current.id.uuidString)) {
                    best = (q.task.id, q.shared)
                }
            } else {
                best = (q.task.id, q.shared)
            }
        }
        return best?.id
    }

    // MARK: Marking

    enum Mode: String, CaseIterable, Sendable { case onDevice, cloudTitles, cloudNoTitles }

    /// One scripted model item, as the oracle sees it.
    struct Item {
        var position: Int
        var draft: IngestionDraft?
        var claim: DuplicateClaim
        /// On device: the Tool queries the mock made before this item was complete (in call order, cumulative).
        var queriesSoFar: [String]
    }

    /// The expected marker for every drafted item, in order.
    static func marks(_ items: [Item], mode: Mode, capture: String, household: Household) -> [DraftDuplicate] {
        var table: [Int: (draftID: Int, mark: DraftDuplicate)] = [:]
        var result: [DraftDuplicate] = []
        let sent = shortlist(capture, household)
        for item in items {
            guard let draft = item.draft else { continue }
            var mark: DraftDuplicate = .none
            if let k = item.claim.sameAsItem, k >= 1, k < item.position, let earlier = table[k] {
                if case let .ofDraft(root) = earlier.mark { mark = .ofDraft(root) } else { mark = .ofDraft(earlier.draftID) }
            } else {
                switch mode {
                case .onDevice:
                    if let claimed = item.claim.sameAsTitle {
                        let want = foldedTitle(claimed)
                        outer: for query in item.queriesSoFar {
                            for entry in shortlist(query, household) where foldedTitle(entry.title) == want {
                                mark = .ofExisting(entry.taskID)
                                break outer
                            }
                        }
                    }
                case .cloudTitles:
                    if let n = item.claim.sameAsShortlistIndex, n >= 1, n <= sent.count {
                        mark = .ofExisting(sent[n - 1].taskID)
                    }
                case .cloudNoTitles:
                    if let id = wordMatch(draft.title, draft.room, household) { mark = .ofExisting(id) }
                }
            }
            table[item.position] = (draft.draftID, mark)
            result.append(mark)
        }
        return result
    }
}
