// The plain-note draft (brief Definitions "Plain note"; AC-M2-10, AC-M2-23). FR-A1, UX-1, UX-3, P-4.
//
// "One draft whose title is the user's own words (trimmed), with the Q5 default fields and no inference." It is
// offered with `noModel` so nothing the person said is lost, and it is saved only by `commit(confirmed:)`.
// - Title: the whole input, trimmed of whitespace and newlines at both ends only (inner spacing is the user's).
//   The calm-words guard is not run: every word is the user's own, and the guard keeps a user's words (AC-M2-12).
// - Fields: the Q5 defaults (kind one-off, effort normal, room none, flags false, the T1 window `[now, now + 7 days)`,
//   default dayparts, all weekdays, no interval), `sourcePhrase` nil, not a duplicate, `draftID` 1.

import Foundation
import TendCore

public enum PlainNote {
    /// The plain note for `input`, or nil when the input is blank or the M1 initialiser rejects it (non-finite `now`).
    public static func draft(for input: String, now: Date, calendar: Calendar, timeZone: TimeZone) -> IngestionDraft? {
        draft(for: input, now: now, resolver: TimeResolver(calendar: calendar, timeZone: timeZone))
    }

    static func draft(for input: String, now: Date, resolver: TimeResolver) -> IngestionDraft? {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let window = resolver.resolve(nil, now: now)
        let settled = RecurrenceSettlement.settle(kind: .oneOff, resolution: window)
        let note = IngestionDraft(
            draftID: 1, title: title, kind: settled.kind, room: .none, effort: .normal, isCritical: false,
            isDeepClean: false, isWeatherDependent: false, allowedDayparts: settled.effectiveDayparts,
            allowedWeekdays: settled.effectiveWeekdays, windowStart: window.windowStart, windowEnd: window.windowEnd,
            recurrenceIntervalDays: settled.intervalDays, sourcePhrase: nil
        )
        do {
            _ = try note.task(id: DraftMapper.probeID, roomID: nil)
        } catch {
            return nil
        }
        return note
    }
}
