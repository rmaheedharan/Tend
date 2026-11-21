// Stream assembly over neutral snapshots (brief Definitions "Item completion", "Draft stream events", T-03, T-25;
// AC-M2-05, AC-M2-10, AC-M2-23; plan WI-M2-06). FR-A1, UX-3.
//
// A pure, synchronous state machine: snapshots in, events out. `DraftPipeline` drives it from a model's
// `AsyncThrowingStream`. The rules, as built:
// - **Completion.** An item is complete at the first of: (a) `ItemSnapshot.hasValueForEveryField`; (b) the snapshot
//   holds a later item; (c) the stream finishes normally. Only the last item of a snapshot can be in progress, so items
//   complete in output order. Completion is final: an item is mapped (Q5) once for emission; a skipped item stays
//   skipped, even if a later snapshot gives it a title.
// - **Emission.** A complete item that Q5 maps to a draft gets the next `draftID` (1, 2, 3 …; the counter advances only
//   for a draft, WI-M2-05 D5) and its duplicate marker from the injected check, then is `emitted`. A Q5 skip gives
//   `itemSkipped(reason)`.
// - **The duplicate hook (WI-M2-07 contract).** The check is called exactly once per draft position, in output order,
//   before that draft's `emitted` (`completeNext`). It is never called again: an update carries the marker set at
//   emission.
// - **Updates.** On each snapshot, every emitted draft whose item is still in the snapshot is mapped again with its
//   `draftID`, keeping its marker. A draft that differs from its last version gives `updated`. A re-map that Q5 would skip, or an item missing from a shorter snapshot, gives no
//   event: a draft is never withdrawn. Within one snapshot, updates (ascending `draftID`) come before new emissions.
// - **End.** A normal finish completes the remaining items (rule c), then `completed`. A stop with no emitted draft is
//   `noModel` with the input and a plain note (T-25). A stop after a draft is `interrupted`; an in-progress item is
//   discarded (`stoppedBeforeComplete`). Nothing is accepted after `finished`.

import Foundation
import TendCore

extension ItemSnapshot {
    /// Completion rule (a): every field of the output schema has a value. The schema fields are the nine fields of
    /// this type. An unknown enum value counts as a value (T-03). The time hint counts once its `anchor` is set: the
    /// other hint fields depend on the anchor and are legitimately absent for most anchors. Later changes to an
    /// emitted item arrive as `updated`.
    public var hasValueForEveryField: Bool {
        title != nil && kind != nil && roomName != nil && effort != nil && isCritical != nil && isDeepClean != nil
            && isWeatherDependent != nil && time?.anchor != nil && sourcePhrase != nil
    }
}

struct DraftStreamAssembler: Sendable {
    let mapper: DraftMapper
    let duplicateCheck: any DraftDuplicateCheck
    let route: Route

    /// The latest snapshot's items.
    private var items: [ItemSnapshot] = []
    /// How many items (from the start of the output) are complete, emitted or skipped.
    private var completedCount = 0
    /// The current version of each emitted draft; index = `draftID` - 1.
    private var drafts: [IngestionDraft] = []
    /// The item index of each emitted draft; index = `draftID` - 1.
    private var itemIndexOfDraft: [Int] = []
    private(set) var isFinished = false

    init(mapper: DraftMapper, duplicateCheck: any DraftDuplicateCheck, route: Route) {
        self.mapper = mapper
        self.duplicateCheck = duplicateCheck
        self.route = route
    }

    mutating func receive(_ snapshot: IngestionSnapshot) -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        items = snapshot.items
        var events = refreshEmitted()
        while completedCount < items.count,
              completedCount + 1 < items.count || items[completedCount].hasValueForEveryField {
            events += completeNext()
        }
        return events
    }

    mutating func finishNormally() -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        var events: [DraftStreamEvent] = []
        while completedCount < items.count { events += completeNext() }
        return events + finish(.completed(route: route))
    }

    /// The model stopped: `error` is a `ModelStopReason`, or any other error (`otherModelError`).
    mutating func stop(_ error: any Error) -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        let reason = error as? ModelStopReason ?? .otherModelError
        if drafts.isEmpty {
            return finish(.noModel(route: route, reason: .stoppedBeforeFirstDraft(reason), input: mapper.input,
                                   plainNote: plainNote()))
        }
        let discarded: DiscardedItemReason? = completedCount < items.count ? .stoppedBeforeComplete : nil
        return finish(.interrupted(route: route, reason: reason, discardedItem: discarded, input: mapper.input))
    }

    mutating func cancel() -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        return finish(.cancelled(route: route))
    }

    /// Route `none`: no model was asked.
    mutating func unavailable(_ reason: OnDeviceUnavailableReason) -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        return finish(.noModel(route: route, reason: .onDeviceUnavailable(reason), input: mapper.input,
                               plainNote: plainNote()))
    }

    // MARK: Steps

    private mutating func finish(_ outcome: DraftStreamOutcome) -> [DraftStreamEvent] {
        isFinished = true
        return [.finished(outcome)]
    }

    private func plainNote() -> IngestionDraft? {
        PlainNote.draft(for: mapper.input, now: mapper.now, resolver: mapper.resolver)
    }

    private mutating func completeNext() -> [DraftStreamEvent] {
        let index = completedCount
        completedCount += 1
        switch mapper.map(items[index], draftID: drafts.count + 1).outcome {
        case var .draft(draft):
            draft.duplicate = duplicateCheck.duplicate(of: draft, earlier: drafts)
            drafts.append(draft)
            itemIndexOfDraft.append(index)
            return [.emitted(draft)]
        case let .skipped(reason):
            return [.itemSkipped(reason)]
        }
    }

    private mutating func refreshEmitted() -> [DraftStreamEvent] {
        var events: [DraftStreamEvent] = []
        var refreshed: [IngestionDraft] = []
        refreshed.reserveCapacity(drafts.count)
        for (offset, last) in drafts.enumerated() {
            var next = last
            let index = itemIndexOfDraft[offset]
            if index < items.count, case let .draft(mapped) = mapper.map(items[index], draftID: last.draftID).outcome {
                next = mapped
            }
            next.duplicate = last.duplicate   // marked once, at emission (the WI-M2-07 hook contract)
            refreshed.append(next)
            if next != last { events.append(.updated(next)) }
        }
        drafts = refreshed
        return events
    }
}
