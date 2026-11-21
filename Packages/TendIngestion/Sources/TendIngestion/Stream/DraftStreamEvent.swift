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
    /// The model's stream finished normally.
    case completed(route: Route)
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
        case let .completed(route), let .cancelled(route): route
        case let .interrupted(route, _, _, _): route
        case let .noModel(route, _, _, _): route
        }
    }

    /// The input text returned in memory (`interrupted` and `noModel`), so M3 can keep it if the user wants.
    public var input: String? {
        switch self {
        case .completed, .cancelled: nil
        case let .interrupted(_, _, _, input): input
        case let .noModel(_, _, input, _): input
        }
    }

    /// The plain-note offer (`noModel` only).
    public var plainNote: IngestionDraft? {
        if case let .noModel(_, _, _, note) = self { return note }
        return nil
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

/// The duplicate marker for a draft (brief Definitions "Duplicate"). The rules are WI-M2-07's. The stream calls the
/// check **exactly once per draft position, in output order, before that draft's `emitted`**, with the draft and every
/// draft with a lower `draftID` (latest versions, ascending). It is not called on an update: an `updated` draft keeps
/// the marker it was emitted with.
public protocol DraftDuplicateCheck: Sendable {
    func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate
}

/// A check that marks nothing (for callers with no household tasks, and for tests).
public struct NoDuplicateCheck: DraftDuplicateCheck {
    public init() {}
    public func duplicate(of draft: IngestionDraft, earlier: [IngestionDraft]) -> DraftDuplicate { .none }
}
