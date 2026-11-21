// Mapping one completed item snapshot to a draft with the Q5 repairs (brief Q5, T-07; AC-M2-01, AC-M2-02; plan
// WI-M2-05). FR-A1, D-016, UX-3.
//
// The repairs run in the brief's order, with one placement the plan fixes: the dayparts and weekdays only exist once
// the Q6 resolver (step 5) has produced them, and step 6 can empty the weekdays again (R5's {W} is dropped with the
// interval, PO Q-T1, E26). So the step 3 defaults are applied to the resolver's sets after steps 5 and 6 (plan,
// "Notation": "WI-M2-05 applies the Q5 step-3 defaults to the resolver's empty sets after step 5"). Applying them
// before step 6 would leave an E26 item with no weekdays. The executed order is `DraftMapper.stepOrder`.
//
// Repairs happen only here; the M1 model still rejects an invalid task (step 9).

import Foundation
import TendCore

/// One repair the mapper made to an item (AC-M2-02 counts them per rule). Diagnostic only; never shown to the user.
public enum ItemRepair: Hashable, Sendable {
    // (1) Title
    /// Whitespace at the ends was trimmed, or a run inside was collapsed.
    case titleTidied
    // (2) Unknown or missing values
    /// The kind was missing or unknown: one-off.
    case kindDefaulted
    /// The effort was missing or unknown: normal.
    case effortDefaulted
    /// The model's room text folds to empty: no room.
    case roomDefaulted
    /// A time hint came without an anchor: no anchor (`TimeHint.Anchor.none`).
    case anchorDefaulted
    /// The anchor was outside the list (or the reserved `unrecognized` value): it counts as no anchor (PO Q-T2).
    case anchorUnrecognized
    /// An unknown daypart element was dropped.
    case daypartDropped
    /// An unknown weekday element was dropped.
    case weekdayDropped
    /// An unknown season was dropped.
    case seasonDropped
    /// An unknown repeat unit was dropped.
    case repeatUnitDropped
    // (3) Empty sets
    /// No daypart: `Daypart.defaultAllowed` (morning, afternoon, evening).
    case daypartsDefaulted
    /// No weekday: all seven.
    case weekdaysDefaulted
    // (4)
    /// Critical and deep clean: critical wins, deep clean is cleared.
    case deepCleanCleared
    // (5)
    /// The window is `[now, now + 7 days)` because there was no hint, or the hint's anchor was unusable (the
    /// resolver's `basis`, plan "`basis` is a diagnostic field").
    case windowDefaulted(TimeResolution.Basis)
    // (6)
    /// A recurring item with no interval, or one outside 1…730 days, became a one-off.
    case becameOneOff
    /// A one-off or restock item's interval was dropped.
    case intervalDropped
    /// R5's {W} was dropped together with the interval (PO Q-T1).
    case repeatWeekdaysDropped
    // (7) Calm-words guard
    /// A banned token the user did not say was removed from the title.
    case titleCalmed
    /// The guard left no title words, so the checked `sourcePhrase` became the title (PO ruling 1, WI-M2-04).
    case titleFromSourcePhrase
    /// A banned token the user did not say was removed from a proposed room name.
    case roomNameCalmed
    /// The guard left no words of a proposed room name: no room.
    case roomNameCleared
    /// The calmed proposed name equals an existing room's name after name folding, so the draft is linked to that room
    /// (AC-M2-04 rule, lowest `id.uuidString` on a tie; PO ruling 1 on WI-M2-05, R19-F3).
    case roomLinkedAfterCalming
    // (8)
    /// The `sourcePhrase` is not in the input after name folding: nil.
    case sourcePhraseDropped

    /// The Q5 step the repair belongs to (1…8).
    public var step: Int {
        switch self {
        case .titleTidied: 1
        case .kindDefaulted, .effortDefaulted, .roomDefaulted, .anchorDefaulted, .anchorUnrecognized, .daypartDropped,
             .weekdayDropped, .seasonDropped, .repeatUnitDropped: 2
        case .daypartsDefaulted, .weekdaysDefaulted: 3
        case .deepCleanCleared: 4
        case .windowDefaulted: 5
        case .becameOneOff, .intervalDropped, .repeatWeekdaysDropped: 6
        case .titleCalmed, .titleFromSourcePhrase, .roomNameCalmed, .roomNameCleared, .roomLinkedAfterCalming: 7
        case .sourcePhraseDropped: 8
        }
    }
}

/// Why an item was dropped (the `itemSkipped(reason)` event, brief Definitions). Calm names (AC-M2-12).
public enum ItemSkipReason: Hashable, Sendable {
    /// Q5 step 1: no title, or only whitespace.
    case noTitle
    /// Q5 step 7: the calm-words guard left nothing to call the item.
    case calmWords(CalmWordsSkipReason)
    /// Q5 step 9: the M1 initialiser rejected the task. The AC-M2-02 oracle shows that this never happens with a
    /// finite `now`.
    case taskRejected(TaskInvariantViolation)
}

/// The result of mapping one item: a draft or a typed skip, and the repairs made, in the order they ran.
public struct DraftMapping: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case draft(IngestionDraft)
        case skipped(ItemSkipReason)
    }

    public let outcome: Outcome
    public let repairs: [ItemRepair]
}

/// Maps completed item snapshots of one capture to drafts (Q5). Pure and deterministic: every date comes from the
/// injected `now`, calendar and time zone, through the Q6 resolver (AC-M2-01).
public struct DraftMapper: Sendable {
    /// The order in which the Q5 steps run (see the file header for why 3 follows 6).
    public static let stepOrder = [1, 2, 4, 5, 6, 3, 7, 8, 9]

    /// The whole input (typed text or final transcript): the calm-words guard and the `sourcePhrase` check read it.
    public let input: String
    /// The household's rooms, for linking (AC-M2-04). Parsing never creates or renames a room.
    public let rooms: [Room]
    public let now: Date
    let resolver: TimeResolver

    public init(input: String, rooms: [Room], now: Date, calendar: Calendar, timeZone: TimeZone) {
        self.input = input
        self.rooms = rooms
        self.now = now
        self.resolver = TimeResolver(calendar: calendar, timeZone: timeZone)
    }

    /// A fixed ID used only to run the M1 initialiser in step 9. Invariants do not depend on the ID.
    static let probeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Maps one completed item. `draftID` is the caller's next number in emission order; a skipped item uses none,
    /// so the caller advances its counter only for a draft.
    public func map(_ item: ItemSnapshot, draftID: Int) -> DraftMapping {
        var repairs: [ItemRepair] = []

        // (1) Title: trim and collapse whitespace; empty → skip.
        guard let rawTitle = item.title else { return DraftMapping(outcome: .skipped(.noTitle), repairs: []) }
        let title = TextFolding.collapseWhitespace(rawTitle)
        guard !title.isEmpty else { return DraftMapping(outcome: .skipped(.noTitle), repairs: []) }
        if title != rawTitle { repairs.append(.titleTidied) }

        // (2) Unknown or missing values become the field's default; unknown elements are dropped.
        let kind = item.kind?.value ?? .oneOff
        if item.kind?.value == nil { repairs.append(.kindDefaulted) }
        let effort = item.effort?.value ?? .normal
        if item.effort?.value == nil { repairs.append(.effortDefaulted) }
        var room = RoomLinker.link(item.roomName, in: rooms)  // the model's raw text (WI-M2-04 "How the pieces fit")
        if item.roomName != nil, room == .none { repairs.append(.roomDefaulted) }
        let hint = item.time.map { timeHint(from: $0, repairs: &repairs) }
        let isCritical = item.isCritical ?? false
        var isDeepClean = item.isDeepClean ?? false

        // (4) Critical + deep clean → critical.
        if isCritical && isDeepClean {
            isDeepClean = false
            repairs.append(.deepCleanCleared)
        }

        // (5) Time hint → window via Q6. The resolution comes only from `resolve` (R2-N1).
        let resolution = resolver.resolve(hint, now: now)
        if resolution.basis != .hint { repairs.append(.windowDefaulted(resolution.basis)) }

        // (6) Interval against the final kind; R5's {W} goes with a dropped interval.
        let settled = RecurrenceSettlement.settle(kind: kind, resolution: resolution)
        if kind == .recurring && settled.kind != .recurring {
            repairs.append(.becameOneOff)
        } else if kind != .recurring && resolution.recurrenceIntervalDays != nil {
            repairs.append(.intervalDropped)
        }
        if settled.allowedWeekdays.isEmpty && !resolution.allowedWeekdays.isEmpty {
            repairs.append(.repeatWeekdaysDropped)
        }

        // (3) Empty dayparts → Daypart.defaultAllowed; empty weekdays → all seven.
        if settled.allowedDayparts.isEmpty { repairs.append(.daypartsDefaulted) }
        if settled.allowedWeekdays.isEmpty { repairs.append(.weekdaysDefaulted) }

        // (7) The calm-words guard (AC-M2-12) on the title and a proposed room name.
        let guardedRoom = room
        switch CalmWordsGuard.apply(title: title, room: room, sourcePhrase: item.sourcePhrase, input: input) {
        case let .skip(reason):
            return DraftMapping(outcome: .skipped(.calmWords(reason)), repairs: repairs)
        case let .keep(keptTitle, keptRoom):
            if keptTitle != title {
                let fromPhrase = CalmWordsGuard.isBlank(CalmWordsGuard.calmed(title, input: input))
                repairs.append(fromPhrase ? .titleFromSourcePhrase : .titleCalmed)
            }
            if keptRoom != guardedRoom {
                repairs.append(keptRoom == .none ? .roomNameCleared : .roomNameCalmed)
            }
            room = keptRoom
            // R19-F3 (PO ruling 1 on WI-M2-05): a proposed name the guard changed is matched again with the AC-M2-04
            // rule, so a draft never proposes a room that equals an existing one. An unchanged proposed name already
            // failed the step 2 match. Commit keeps its own re-check (PO WI-M2-04 ruling 2b).
            if keptRoom != guardedRoom, case let .proposed(calmedName) = keptRoom,
               case let .existing(id) = RoomLinker.link(calmedName, in: rooms) {
                room = .existing(id)
                repairs.append(.roomLinkedAfterCalming)
            }
            // (8) The sourcePhrase check.
            let phrase = SourcePhrase.checked(item.sourcePhrase, input: input)
            if item.sourcePhrase != nil && phrase == nil { repairs.append(.sourcePhraseDropped) }

            let draft = IngestionDraft(
                draftID: draftID,
                title: keptTitle,
                kind: settled.kind,
                room: room,
                effort: effort,
                isCritical: isCritical,
                isDeepClean: isDeepClean,
                isWeatherDependent: item.isWeatherDependent ?? false,
                allowedDayparts: settled.effectiveDayparts,
                allowedWeekdays: settled.effectiveWeekdays,
                windowStart: resolution.windowStart,
                windowEnd: resolution.windowEnd,
                recurrenceIntervalDays: settled.intervalDays,
                sourcePhrase: phrase
            )

            // (9) The M1 initialiser.
            do {
                _ = try draft.task(id: Self.probeID, roomID: nil)
            } catch {
                return DraftMapping(outcome: .skipped(.taskRejected(error)), repairs: repairs)
            }
            return DraftMapping(outcome: .draft(draft), repairs: repairs)
        }
    }

    /// Q5 step 2 for the time hint: the neutral `TimeHint` the resolver reads.
    func timeHint(from snapshot: TimeHintSnapshot, repairs: inout [ItemRepair]) -> TimeHint {
        let anchor: TimeHint.Anchor
        switch snapshot.anchor {
        case nil:
            anchor = .none
            repairs.append(.anchorDefaulted)
        case .known(let value) where value != .unrecognized:
            anchor = value
        case .known, .unrecognized:
            anchor = .unrecognized
            repairs.append(.anchorUnrecognized)
        }
        return TimeHint(
            anchor: anchor,
            daypart: Self.element(snapshot.daypart, dropped: .daypartDropped, repairs: &repairs),
            weekday: Self.element(snapshot.weekday, dropped: .weekdayDropped, repairs: &repairs),
            month: snapshot.month,
            season: Self.element(snapshot.season, dropped: .seasonDropped, repairs: &repairs),
            count: snapshot.count,
            repeatEvery: snapshot.repeatEvery,
            repeatUnit: Self.element(snapshot.repeatUnit, dropped: .repeatUnitDropped, repairs: &repairs)
        )
    }

    static func element<Value>(
        _ choice: ModelChoice<Value>?, dropped: ItemRepair, repairs: inout [ItemRepair]
    ) -> Value? {
        switch choice {
        case nil: return nil
        case .known(let value): return value
        case .unrecognized:
            repairs.append(dropped)
            return nil
        }
    }
}
