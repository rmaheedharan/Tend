// The draft stream events and outcomes (brief Definitions "Draft stream events", T-03; AC-M2-05, AC-M2-10,
// AC-M2-23). FR-A1, UX-3.
//
// Order of drafts: `draftID`s are 1, 2, 3 … in emission order, which is the order of items in the model's output.
// Confirmed drafts are passed to commit in ascending `draftID` (PO WI-M2-04 ruling 2, WI-M2-05 D6);
// `DraftStreamSummary.drafts` is already in that order.

import Foundation

/// One event of the draft stream. The sequence never throws; `finished` comes exactly once, last.
public enum DraftStreamEvent: Hashable, Sendable {
    /// A draft, exactly once per `draftID`, at the moment its item is complete, with the duplicate marker set.
    case emitted(IngestionDraft)
    /// A full replacement of an emitted draft (same `draftID`), only after its `emitted`. A draft is never withdrawn.
    case updated(IngestionDraft)
    /// An item dropped by Q5. It has no `draftID`.
    case itemSkipped(ItemSkipReason)
    /// The end of the stream.
    case finished(DraftStreamOutcome)
}

/// Why the in-progress item was discarded when the stream stopped (AC-M2-05 "discarded with a typed reason").
public enum DiscardedItemReason: CaseIterable, Hashable, Sendable {
    /// The model stopped before the item was complete.
    case stoppedBeforeComplete
}

/// How a draft stream ended (brief Definitions). Every outcome carries the route.
public enum DraftStreamOutcome: Hashable, Sendable {
    /// The model's stream finished normally. If no draft was emitted (no items, or every item skipped), the input text
    /// is returned in memory with a plain-note offer (`nil` only for a blank input), as for `noModel` (PO WI-M2-06
    /// ruling 1). With at least one draft, both are nil.
    case completed(route: Route, input: String? = nil, plainNote: IngestionDraft? = nil)
    /// The stream stopped after at least one draft was emitted. Emitted drafts stay available for confirmation; the
    /// in-progress item, if any, is discarded (`discardedItem`). The input text is returned in memory. No plain note
    /// is offered, because a draft was emitted.
    case interrupted(route: Route, reason: ModelStopReason, discardedItem: DiscardedItemReason?, input: String)
    /// No usable model, or the model stopped before any draft. No draft was emitted. The input text is returned in
    /// memory with a plain-note offer (`nil` only when the input is blank). The plain note is saved only by commit.
    case noModel(route: Route, reason: NoModelReason, input: String, plainNote: IngestionDraft?)
    /// The consumer cancelled. Nothing is written.
    case cancelled(route: Route)

    public var route: Route {
        switch self {
        case let .completed(route, _, _): route
        case let .cancelled(route): route
        case let .interrupted(route, _, _, _): route
        case let .noModel(route, _, _, _): route
        }
    }

    /// The input text returned in memory (`interrupted`, `noModel`, and `completed` with no draft), so M3 can keep it
    /// if the user wants.
    public var input: String? {
        switch self {
        case let .completed(_, input, _): input
        case .cancelled: nil
        case let .interrupted(_, _, _, input): input
        case let .noModel(_, _, input, _): input
        }
    }

    /// The plain-note offer (`noModel`, and `completed` with no draft).
    public var plainNote: IngestionDraft? {
        switch self {
        case let .noModel(_, _, _, note), let .completed(_, _, note): note
        case .interrupted, .cancelled: nil
        }
    }
}

/// Folds a draft stream into its current state: the latest version of each draft in ascending `draftID` (the commit
/// order, D6), the skipped reasons, and the outcome. Events after `finished` are ignored.
public struct DraftStreamSummary: Hashable, Sendable {
    /// The latest version of each emitted draft, in ascending `draftID`.
    public private(set) var drafts: [IngestionDraft] = []
    public private(set) var skipped: [ItemSkipReason] = []
    public private(set) var outcome: DraftStreamOutcome?

    public init() {}

    public mutating func apply(_ event: DraftStreamEvent) {
        guard outcome == nil else { return }
        switch event {
        case let .emitted(draft):
            drafts.append(draft)
            drafts.sort { $0.draftID < $1.draftID }
        case let .updated(draft):
            if let index = drafts.firstIndex(where: { $0.draftID == draft.draftID }) { drafts[index] = draft }
        case let .itemSkipped(reason):
            skipped.append(reason)
        case let .finished(result):
            outcome = result
        }
    }
}

/// The duplicate marker for a draft (brief Definitions "Duplicate", "Draft stream events"). The rules are WI-M2-07's.
/// This is the one place the calling rule is stated (PO WI-M2-06 ruling 5):
/// - **At emission:** once per draft position, in output order, before that draft's `emitted`, with every draft with a
///   lower `draftID` (latest versions, ascending).
/// - **After updates:** when a snapshot changes the content of any emitted draft, the check runs again in ascending
///   `draftID` for the lowest changed draft and every later emitted draft, each with the latest lower drafts. Each
///   draft whose content or marker changed gets one `updated`. If no content changed, it is not called.
/// - So after `finished`, each marker equals one pass of the check over the final drafts in `draftID` order.
public protocol DraftDuplicateCheck: Sendable {
    func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate
}

/// A check that marks nothing (for callers with no household tasks, and for tests).
public struct NoDuplicateCheck: DraftDuplicateCheck {
    public init() {}
    public func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate { .none }
}
