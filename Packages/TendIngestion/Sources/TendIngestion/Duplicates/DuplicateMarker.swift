// Marking drafts as duplicates (brief Definitions "Draft stream events": "The duplicate marker is already set", and
// `updated` "including its duplicate marker"; "Duplicate"; "Local duplicate re-check for cloud drafts"; "Word-match
// floor"). FR-A1, AC-M2-05, AC-M2-07, AC-M2-08, Q7, Q12. Plan WI-M2-07; WI-M2-06/07 integration.
//
// Stream assembly (WI-M2-06) checks each draft at emission, in model-output order, and again after updates (PO WI-M2-06
// ruling 5): from the lowest changed draft through every later one, in ascending order. The stream's check is
// `DraftDuplicateRules`, a pure function of the draft, the lower drafts and the snapshot's lookup queries, with the
// household and the path fixed for the parse (review R22-R2-F2). `DuplicateMarker` is the same rules with a position
// table, for callers that mark one position at a time; it accepts repeat calls for a position on the same terms.
// After the model's claims, the **word-match floor** (PO 2026-11-21 WI-M2-07 ruling 1) checks every draft the model
// did not validly mark against the whole local household, on every path. It sends nothing. The model's claim reaches
// the rules as a neutral `DuplicateClaim` (from `ItemSnapshot.sameAsItem` and `sameAsExisting`); the schemas map into
// those fields (WI-M2-M2, WI-M2-10, WI-M2-12). Nothing here changes the household (Q7).

import Foundation
import TendCore

/// The model's claim that an item repeats an existing task, as a neutral value (`ItemSnapshot.sameAsExisting`).
public enum ExistingTaskClaim: Hashable, Sendable {
    /// On device: a title the duplicate `Tool` returned in this parse.
    case lookupTitle(String)
    /// Cloud, Q12 = yes: a 1-based index into the shortlist sent in the request.
    case shortlistIndex(Int)
}

/// What the model said about one item being a repeat. Every field is optional; a model may say nothing.
public struct DuplicateClaim: Hashable, Sendable {
    /// The 1-based position of an earlier item in the same output (all paths). Valid only when it is lower than the
    /// item's own position and that earlier item became a draft.
    public var sameAsItem: Int?
    /// A 1-based shortlist index from the cloud request (cloud, Q12 = yes). Valid only for 1 ≤ n ≤ the count sent.
    public var sameAsShortlistIndex: Int?
    /// A title the duplicate `Tool` returned (on device). Valid only when a lookup in this parse returned it.
    public var sameAsTitle: String?

    public init(sameAsItem: Int? = nil, sameAsShortlistIndex: Int? = nil, sameAsTitle: String? = nil) {
        self.sameAsItem = sameAsItem
        self.sameAsShortlistIndex = sameAsShortlistIndex
        self.sameAsTitle = sameAsTitle
    }
}

/// How a draft is checked against the existing tasks, per route and the Q12 answer. Every case carries the household
/// for the word-match floor.
public enum ExistingTaskCheck: Hashable, Sendable {
    /// On device: the Tool's lookups so far in this parse. `sameAsTitle` must name a title one of them returned. The
    /// floor uses the log's household.
    case toolLookups(DuplicateLookupLog)
    /// Cloud, Q12 = yes: the shortlist sent in the request (`sameAsShortlistIndex` must be 1…count) and the household
    /// for the floor.
    case sentShortlist([ShortlistEntry], Household)
    /// Cloud, Q12 = no: no titles were sent; the model makes no existing-task claim, and the floor is the only check.
    case localWordMatch(Household)
    /// On device, as the stream sees it: the Tool's queries so far in this parse (in call order), replayed on the
    /// household, which is the one the Tool read. Same resolution as `.toolLookups` with a log of those queries.
    case toolQueries([String], Household)

    /// The household the word-match floor reads.
    public var household: Household {
        switch self {
        case let .toolLookups(log): log.household
        case let .sentShortlist(_, household): household
        case let .localWordMatch(household): household
        case let .toolQueries(_, household): household
        }
    }
}

/// The Q12 answer for cloud captures (PO default: yes, owner may change it). Both paths are built; the caller passes
/// the answer in force.
public enum CloudTitleSharing: Hashable, Sendable {
    /// Q12 = yes: up to 10 shortlisted titles are sent.
    case shortlistTitles
    /// Q12 = no: only room names are sent.
    case noTitles

    /// The check for one cloud capture. With `shortlistTitles` this is the same shortlist the payload sends
    /// (`DuplicateShortlist.entries(for: capture, …)`).
    public func existingTaskCheck(capture: String, household: Household) -> ExistingTaskCheck {
        switch self {
        case .shortlistTitles: .sentShortlist(DuplicateShortlist.entries(for: capture, in: household), household)
        case .noTitles: .localWordMatch(household)
        }
    }
}

/// Marks the drafts of one parse one position at a time, remembering each position's draft ID and marker.
///
/// Repeat calls (PO WI-M2-06 ruling 5): `mark` may be called again for a position after its item was updated; the new
/// result replaces the old one. A position reads only lower positions (`sameAsItem` must be lower than its own), so a
/// repeat call never sees its own earlier entry. A caller that re-marks a position must then re-mark **every later
/// position**, in ascending order, so that `ofDraft` cascades are computed from the latest entries; the draft stream
/// does this through `DraftDuplicateRules`.
public struct DuplicateMarker: Sendable {
    /// Each drafted position's draft ID and the marker it got.
    private var marked: [Int: (draftID: Int, duplicate: DraftDuplicate)] = [:]

    public init() {}

    /// Sets `draft.duplicate` and remembers it for later in-input claims. The rules, in order, are
    /// `DuplicateMarker.duplicate(for:position:claim:check:earlierAt:)`.
    /// `position` is the item's 1-based position in the model's output, skipped items included.
    public mutating func mark(
        _ draft: IngestionDraft, position: Int, claim: DuplicateClaim, check: ExistingTaskCheck
    ) -> IngestionDraft {
        var result = draft
        let table = marked
        result.duplicate = Self.duplicate(for: draft, position: position, claim: claim, check: check) { table[$0] }
        marked[position] = (draft.draftID, result.duplicate)
        return result
    }

    /// The rules for one draft. In order:
    /// 1. **In-input:** a valid `sameAsItem` k (1 ≤ k < `position`, and k is a drafted position in `earlierAt`) gives
    ///    `ofDraft` of the **first** draft of that chore: k's draft ID, or the draft k itself repeats when k is
    ///    `ofDraft` (a repeat collapses into its first draft).
    /// 2. **The model's existing-task claim**, by `check`: on device, a `sameAsTitle` the Tool returned; cloud
    ///    Q12 = yes, a valid `sameAsShortlistIndex`. Under Q12 = no there is no such claim. Claims meant for another
    ///    path are ignored.
    /// 3. **The word-match floor** (every path): `LocalWordMatch.target` over the whole household.
    /// 4. Otherwise `none`.
    static func duplicate(
        for draft: IngestionDraft, position: Int, claim: DuplicateClaim, check: ExistingTaskCheck,
        earlierAt: (Int) -> (draftID: Int, duplicate: DraftDuplicate)?
    ) -> DraftDuplicate {
        if let k = claim.sameAsItem, k >= 1, k < position, let earlier = earlierAt(k) {
            if case let .ofDraft(first) = earlier.duplicate { return .ofDraft(first) }
            return .ofDraft(earlier.draftID)
        }
        switch check {
        case let .toolLookups(log):
            if let title = claim.sameAsTitle, let id = log.taskID(forTitle: title) { return .ofExisting(id) }
        case let .toolQueries(queries, household):
            if let title = claim.sameAsTitle,
               let id = DuplicateLookupLog.taskID(forTitle: title, replaying: queries, in: household) {
                return .ofExisting(id)
            }
        case let .sentShortlist(entries, _):
            if let n = claim.sameAsShortlistIndex, n >= 1, n <= entries.count {
                return .ofExisting(entries[n - 1].taskID)
            }
        case .localWordMatch:
            break
        }
        if let id = LocalWordMatch.target(for: draft, in: check.household) { return .ofExisting(id) }
        return .none
    }
}

/// The duplicate rules as the draft stream's check for one parse (WI-M2-06/07 integration; PO WI-M2-06 ruling 5,
/// PO WI-M2-07 ruling 1). Pure: the marker of a draft is a function of the draft, its position and claim, the lower
/// drafts (positions and latest markers) and the snapshot's lookup queries; the household and the path are fixed when
/// the value is made. So the stream may call it again for any position, as often as it re-marks.
public struct DraftDuplicateRules: DraftDuplicateCheck {
    enum Path: Hashable, Sendable {
        /// On device: title claims resolve through the replayed Tool queries.
        case onDevice(Household)
        /// Cloud: the check is fixed for the capture (Q12 = yes: the shortlist sent; Q12 = no: the word-match only).
        /// Lookup queries are ignored (a cloud model has no Tool).
        case cloud(ExistingTaskCheck)
    }

    let path: Path

    /// The on-device path. `household` must be the value the duplicate `Tool` reads during this parse.
    public static func onDevice(household: Household) -> DraftDuplicateRules {
        DraftDuplicateRules(path: .onDevice(household))
    }

    /// A cloud path under the Q12 answer in force. `capture` is the text the payload is built from, so that under
    /// Q12 = yes the shortlist is the one sent (`CloudTitleSharing.existingTaskCheck`).
    public static func cloud(_ sharing: CloudTitleSharing, capture: String, household: Household)
        -> DraftDuplicateRules {
        DraftDuplicateRules(path: .cloud(sharing.existingTaskCheck(capture: capture, household: household)))
    }

    public func duplicate(of entry: DuplicateCheckEntry, earlier: [DuplicateCheckEntry],
                          lookupQueries: [String]) -> DraftDuplicate {
        let check: ExistingTaskCheck = switch path {
        case let .onDevice(household): .toolQueries(lookupQueries, household)
        case let .cloud(check): check
        }
        return DuplicateMarker.duplicate(for: entry.draft, position: entry.position, claim: entry.claim,
                                         check: check) { k in
            earlier.first { $0.position == k }.map { ($0.draft.draftID, $0.draft.duplicate) }
        }
    }
}

/// The commit-time re-check (brief Definitions: "Commit checks each `ofExisting` target again. If the target is
/// missing or `completed`, the draft is treated as not a duplicate"). `DraftCommit` (WI-M2-08) applies it first and
/// then its own rules for a gone target (C3).
public enum DuplicateRecheck {
    public static func atCommit(_ duplicate: DraftDuplicate, in household: Household) -> DraftDuplicate {
        guard case let .ofExisting(id) = duplicate else { return duplicate }
        let live = household.tasks.contains { $0.id == id && $0.state != .completed }
        return live ? duplicate : .none
    }
}

extension DraftDuplicate {
    /// Whether commit creates a task for a confirmed draft with this (re-checked) marker: only for `none`.
    public var createsTask: Bool { self == .none }
}
