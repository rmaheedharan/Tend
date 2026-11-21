// Marking drafts as duplicates before they are emitted (brief Definitions "Draft stream events": "The duplicate marker
// is already set"; "Duplicate"; "Local duplicate re-check for cloud drafts"). FR-A1, AC-M2-07, AC-M2-08, Q7, Q12.
// Plan WI-M2-07.
//
// Stream assembly (WI-M2-06) calls `mark` once per draft, in model-output order, at the moment the draft completes.
// The model's claim reaches it as a neutral `DuplicateClaim`; which output field carries it is the adapters' and
// the payload schema's business (WI-M2-M2, WI-M2-10, WI-M2-12). Nothing here changes the household (Q7).

import Foundation
import TendCore

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

/// How a draft is checked against the existing tasks, per route and the Q12 answer.
public enum ExistingTaskCheck: Hashable, Sendable {
    /// On device: the Tool's lookups so far in this parse. `sameAsTitle` must name a title one of them returned.
    case toolLookups(DuplicateLookupLog)
    /// Cloud, Q12 = yes: the shortlist sent in the request. `sameAsShortlistIndex` must be 1…count.
    case sentShortlist([ShortlistEntry])
    /// Cloud, Q12 = no: no titles were sent; the local word-match against the household decides.
    case localWordMatch(Household)
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
        case .shortlistTitles: .sentShortlist(DuplicateShortlist.entries(for: capture, in: household))
        case .noTitles: .localWordMatch(household)
        }
    }
}

/// Marks the drafts of one parse, in model-output order.
public struct DuplicateMarker: Sendable {
    /// Each drafted position's draft ID and the marker it got.
    private var marked: [Int: (draftID: Int, duplicate: DraftDuplicate)] = [:]

    public init() {}

    /// Sets `draft.duplicate` and remembers it for later in-input claims. In order:
    /// 1. **In-input:** a valid `sameAsItem` k gives `ofDraft` of the **first** draft of that chore: k's draft ID, or
    ///    the draft k itself repeats when k is `ofDraft` (a repeat collapses into its first draft).
    /// 2. **Existing task**, by `check`: on device, a `sameAsTitle` the Tool returned; cloud Q12 = yes, a valid
    ///    `sameAsShortlistIndex`; cloud Q12 = no, the local word-match. Claims for the other paths are ignored.
    /// 3. Otherwise `none`.
    /// `position` is the item's 1-based position in the model's output, skipped items included.
    public mutating func mark(
        _ draft: IngestionDraft, position: Int, claim: DuplicateClaim, check: ExistingTaskCheck
    ) -> IngestionDraft {
        var result = draft
        result.duplicate = duplicate(for: draft, position: position, claim: claim, check: check)
        marked[position] = (draft.draftID, result.duplicate)
        return result
    }

    private func duplicate(
        for draft: IngestionDraft, position: Int, claim: DuplicateClaim, check: ExistingTaskCheck
    ) -> DraftDuplicate {
        if let k = claim.sameAsItem, k >= 1, k < position, let earlier = marked[k] {
            if case let .ofDraft(first) = earlier.duplicate { return .ofDraft(first) }
            return .ofDraft(earlier.draftID)
        }
        switch check {
        case let .toolLookups(log):
            if let title = claim.sameAsTitle, let id = log.taskID(forTitle: title) { return .ofExisting(id) }
        case let .sentShortlist(entries):
            if let n = claim.sameAsShortlistIndex, n >= 1, n <= entries.count {
                return .ofExisting(entries[n - 1].taskID)
            }
        case let .localWordMatch(household):
            if let id = LocalWordMatch.target(for: draft, in: household) { return .ofExisting(id) }
        }
        return .none
    }
}

/// The commit-time re-check (brief Definitions: "Commit checks each `ofExisting` target again. If the target is
/// missing or `completed`, the draft is treated as not a duplicate"). Commit itself is WI-M2-08.
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
