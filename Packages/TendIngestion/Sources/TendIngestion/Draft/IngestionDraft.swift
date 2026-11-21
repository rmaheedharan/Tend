// The draft (brief Definitions "Draft (`IngestionDraft`), the field set", T-03). FR-A1, UX-1 (every field is
// inferred), UX-3 (a calm title).
//
// A draft is not in the household until it is committed. Only `DraftMapper` makes one, after the Q5 repairs, so every
// draft has passed the M1 initialiser once (Q5 step 9). Commit (WI-M2-08) turns it into a `HouseholdTask` with an ID
// from the injected generator and the room ID from `RoomLinker.commitPlan`.

import Foundation
import TendCore

/// Whether a draft repeats a chore that already exists (brief Definitions "Duplicate"). Set by the duplicate rules
/// (WI-M2-07) before the draft is emitted.
public enum DraftDuplicate: Hashable, Sendable {
    case none
    /// The same chore as this existing task, which is not `completed`.
    case ofExisting(HouseholdTask.ID)
    /// The same chore as the earlier draft with this `draftID` in the same input.
    case ofDraft(Int)
}

public struct IngestionDraft: Hashable, Sendable {
    /// A per-parse number (1, 2, 3 …) in emission order, given by the caller. It is not a task ID.
    public let draftID: Int
    /// Non-empty after trimming and the calm-words guard.
    public let title: String
    public let kind: TaskKind
    public let room: DraftRoom
    public let effort: Effort
    public let isCritical: Bool
    public let isDeepClean: Bool
    public let isWeatherDependent: Bool
    public let allowedDayparts: Set<Daypart>
    public let allowedWeekdays: Set<Weekday>
    public let windowStart: Date
    public let windowEnd: Date
    public let recurrenceIntervalDays: Int?
    /// The user's own words for the item, exactly as the model quoted them, kept only if they occur in the input
    /// after name folding (Q5 step 8). Otherwise nil.
    public let sourcePhrase: String?
    public internal(set) var duplicate: DraftDuplicate

    init(
        draftID: Int, title: String, kind: TaskKind, room: DraftRoom, effort: Effort, isCritical: Bool,
        isDeepClean: Bool, isWeatherDependent: Bool, allowedDayparts: Set<Daypart>, allowedWeekdays: Set<Weekday>,
        windowStart: Date, windowEnd: Date, recurrenceIntervalDays: Int?, sourcePhrase: String?,
        duplicate: DraftDuplicate = .none
    ) {
        self.draftID = draftID
        self.title = title
        self.kind = kind
        self.room = room
        self.effort = effort
        self.isCritical = isCritical
        self.isDeepClean = isDeepClean
        self.isWeatherDependent = isWeatherDependent
        self.allowedDayparts = allowedDayparts
        self.allowedWeekdays = allowedWeekdays
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.sourcePhrase = sourcePhrase
        self.duplicate = duplicate
    }

    /// The task this draft becomes on commit: `active`, never completed. The ID and the room ID come from the caller
    /// (an injected generator and the room commit plan, Q10, AC-M2-04). The M1 initialiser checks every invariant;
    /// a draft from `DraftMapper` has already passed it once, and neither argument affects an invariant.
    public func task(id: UUID, roomID: Room.ID?) throws(TaskInvariantViolation) -> HouseholdTask {
        try HouseholdTask(
            id: id,
            title: title,
            kind: kind,
            roomID: roomID,
            effort: effort,
            isCritical: isCritical,
            isDeepClean: isDeepClean,
            isWeatherDependent: isWeatherDependent,
            allowedDayparts: allowedDayparts,
            allowedWeekdays: allowedWeekdays,
            windowStart: windowStart,
            windowEnd: windowEnd,
            recurrenceIntervalDays: recurrenceIntervalDays
        )
    }
}
