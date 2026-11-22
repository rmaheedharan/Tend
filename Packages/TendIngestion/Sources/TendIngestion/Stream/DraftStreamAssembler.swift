// Stream assembly over neutral snapshots (brief Definitions "Item completion", "Draft stream events", T-03, T-25;
// AC-M2-05, AC-M2-10, AC-M2-23; plan WI-M2-06). FR-A1, UX-3.
//
// A pure, synchronous state machine: snapshots in, events out. `DraftPipeline` drives it from a model's
// `AsyncThrowingStream`. The rules, as built:
// - **Completion.** An item is complete at the first of: (a) `ItemSnapshot.hasValueForEveryField`; (b) the snapshot
//   holds a later item; (c) the stream finishes normally. Only the last item of a snapshot can be in progress, so items
//   complete in output order. Completion is final: an item is mapped (Q5) once for emission; a skipped item stays
//   skipped, even if a later snapshot gives it a title.
// - **Emission.** A complete item that Q5 maps to a draft gets the next `draftID` (1, 2, 3 …; the counter
//   advances only for a draft, WI-M2-05 D5) and its duplicate marker from the injected check, then is `emitted`.
//   A Q5 skip gives `itemSkipped(reason)`.
// - **The duplicate hook (WI-M2-07 contract; PO WI-M2-06 ruling 5).** At emission, the check is called once per draft
//   position, in output order, before that draft's `emitted` (`completeNext`), with the latest lower drafts. It gets
//   each draft's item position (skipped items included), the model's claim from the last version of its item that
//   mapped to a draft (review R23-F1), and the latest snapshot's lookup queries (`DuplicateCheckEntry`; WI-M2-06/07 integration).
// - **Updates and re-marking.** On each snapshot, every emitted draft whose item is still in the snapshot is mapped
//   again with its `draftID`, and its claim is read again. If any draft's content or claim changed, the check runs
//   again in ascending `draftID` for the lowest changed draft and every later emitted draft, each against the latest
//   versions of all lower drafts (this covers `ofDraft` cascades). If the snapshot's lookup queries differ from the
//   last ones (on device, the Tool's log grew; review R22-R2-F2), it runs for every emitted draft. Each draft whose
//   content or marker changed gets exactly one `updated` (a full replacement). If nothing the check reads changed, it
//   is not called. A re-map that Q5 would skip, or an item missing
//   from a shorter snapshot, keeps the last content: a draft is never withdrawn. Within one snapshot, updates
//   (ascending `draftID`) come before new emissions, so a new draft is checked against the re-marked drafts. After
//   `finished`, each marker equals one pass of the check over the final drafts in `draftID` order, with the final
//   claims and queries (the check is pure, `DraftDuplicateCheck`).
// - **End.** A normal finish completes the remaining items (rule c), then `completed`; with no emitted draft it also
//   returns the input and a plain note (PO WI-M2-06 ruling 1). A stop with no emitted draft is
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
    /// The model's claim of each emitted draft, from the last version of its item that mapped to a draft (a version
    /// that Q5 skips, or an item missing from a shorter snapshot, keeps the last claim; R23-F1); index = `draftID` - 1.
    private var claims: [DuplicateClaim] = []
    /// The latest snapshot's lookup queries: the ones every current marker was computed with.
    private var lookupQueries: [String] = []
    private(set) var isFinished = false

    init(mapper: DraftMapper, duplicateCheck: any DraftDuplicateCheck, route: Route) {
        self.mapper = mapper
        self.duplicateCheck = duplicateCheck
        self.route = route
    }

    mutating func receive(_ snapshot: IngestionSnapshot) -> [DraftStreamEvent] {
        guard !isFinished else { return [] }
        items = snapshot.items
        let queriesChanged = snapshot.lookupQueries != lookupQueries
        lookupQueries = snapshot.lookupQueries
        var events = refreshEmitted(queriesChanged: queriesChanged)
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
        // PO WI-M2-06 ruling 1: nothing the person said is lost when no draft came out.
        if drafts.isEmpty {
            return events + finish(.completed(route: route, input: mapper.input, plainNote: plainNote()))
        }
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
            let claim = items[index].duplicateClaim
            draft.duplicate = duplicateCheck.duplicate(
                of: DuplicateCheckEntry(draft: draft, position: index + 1, claim: claim),
                earlier: entries(drafts, claims), lookupQueries: lookupQueries)
            drafts.append(draft)
            itemIndexOfDraft.append(index)
            claims.append(claim)
            return [.emitted(draft)]
        case let .skipped(reason):
            return [.itemSkipped(reason)]
        }
    }

    /// The check's view of the first `drafts.count` drafts.
    private func entries(_ drafts: [IngestionDraft], _ claims: [DuplicateClaim]) -> [DuplicateCheckEntry] {
        drafts.indices.map {
            DuplicateCheckEntry(draft: drafts[$0], position: itemIndexOfDraft[$0] + 1, claim: claims[$0])
        }
    }

    private mutating func refreshEmitted(queriesChanged: Bool) -> [DraftStreamEvent] {
        // 1. Re-map each emitted draft whose item is still present, and read its latest claim (the marker is decided
        //    in step 2). A re-map that Q5 would skip keeps the last content and claim: a draft is never withdrawn.
        var latest = drafts
        var latestClaims = claims
        for (offset, last) in drafts.enumerated() {
            let index = itemIndexOfDraft[offset]
            if index < items.count, case var .draft(mapped) = mapper.map(items[index], draftID: last.draftID).outcome {
                mapped.duplicate = last.duplicate
                latest[offset] = mapped
                latestClaims[offset] = items[index].duplicateClaim
            }
        }
        // 2. Re-mark in ascending draftID (PO WI-M2-06 ruling 5): from the lowest draft whose content or claim
        //    changed, or from draft 1 when the lookup queries changed (review R22-R2-F2: the Tool's log grew).
        let lowest = queriesChanged && !latest.isEmpty
            ? 0 : latest.indices.first { latest[$0] != drafts[$0] || latestClaims[$0] != claims[$0] }
        guard let lowest else { return [] }
        var earlier = entries(Array(latest[..<lowest]), Array(latestClaims[..<lowest]))
        for offset in lowest..<latest.count {
            let entry = DuplicateCheckEntry(draft: latest[offset], position: itemIndexOfDraft[offset] + 1,
                                            claim: latestClaims[offset])
            latest[offset].duplicate = duplicateCheck.duplicate(of: entry, earlier: earlier,
                                                                lookupQueries: lookupQueries)
            earlier.append(DuplicateCheckEntry(draft: latest[offset], position: entry.position, claim: entry.claim))
        }
        // 3. One `updated` per draft whose content or marker changed.
        let events: [DraftStreamEvent] = latest.indices.compactMap { offset in
            latest[offset] != drafts[offset] ? .updated(latest[offset]) : nil
        }
        drafts = latest
        claims = latestClaims
        return events
    }
}
