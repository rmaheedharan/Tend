// The neutral duplicate lookup that the on-device `Tool` wraps (AC-M2-07: "The `Tool` returns exactly the duplicate
// shortlist for its query: at most 10 entries, only from the local household, and only title, kind and room name for
// each"). FR-A1, P-1, P-2. Plan WI-M2-07; the `Tool` conformance itself is WI-M2-M2 (`TendAI`, owner-run Mac).
//
// The lookup reads only the household value it is given. It never changes it (Q7), and it is never given to a cloud
// model (AC-M2-24).

import Foundation
import TendCore

/// What the Tool returns for one shortlisted task: the title, kind and room name, and nothing else (no ID).
public struct DuplicateLookupEntry: Hashable, Sendable {
    public let title: String
    public let kind: TaskKind
    public let roomName: String?

    public init(title: String, kind: TaskKind, roomName: String?) {
        self.title = title
        self.kind = kind
        self.roomName = roomName
    }
}

public enum DuplicateLookup {
    /// Exactly the duplicate shortlist for `query`, in rank order, reduced to title, kind and room name.
    public static func entries(for query: String, in household: Household) -> [DuplicateLookupEntry] {
        DuplicateShortlist.entries(for: query, in: household).map(\.lookupEntry)
    }
}

extension ShortlistEntry {
    /// The fields the Tool may return.
    public var lookupEntry: DuplicateLookupEntry {
        DuplicateLookupEntry(title: title, kind: kind, roomName: roomName)
    }
}

/// The lookups the Tool made during one parse, so that a model's claim can be resolved to a task ID on the phone
/// (`DuplicateMarker`, on-device path). A value type: the `TendAI` Tool keeps one per session behind its own isolation.
public struct DuplicateLookupLog: Hashable, Sendable {
    /// The household the lookups read (unchanged, Q7).
    public let household: Household
    /// Every query, in call order.
    public private(set) var queries: [String] = []
    /// The shortlist each query returned, in call order.
    private(set) var results: [[ShortlistEntry]] = []

    public init(household: Household) {
        self.household = household
    }

    /// One Tool call: returns exactly `DuplicateLookup.entries(for: query, in: household)` and records it.
    public mutating func lookUp(_ query: String) -> [DuplicateLookupEntry] {
        let entries = DuplicateShortlist.entries(for: query, in: household)
        queries.append(query)
        results.append(entries)
        return entries.map(\.lookupEntry)
    }

    /// The task behind a title the model names: the first entry, in call order and then rank order, whose title is
    /// equal to `title` after the keyword fold (case, diacritics, width, quotes and whitespace; no article strip).
    /// Nil when no lookup returned such a title.
    public func taskID(forTitle title: String) -> HouseholdTask.ID? {
        let wanted = TextFolding.foldWithoutArticle(title)
        for entries in results {
            if let entry = entries.first(where: { TextFolding.foldWithoutArticle($0.title) == wanted }) {
                return entry.taskID
            }
        }
        return nil
    }
}
