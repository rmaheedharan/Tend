import Foundation

/// One household task (AC-M1-01, FR-B1, FR-B2, UX-3).
///
/// Named `HouseholdTask` to avoid clashing with `_Concurrency.Task` (design.md naming list).
///
/// The stored fields are exactly the design naming list and nothing else (design D-2): no counter of how often or how
/// far a task moved, no original window, no history. Every instance satisfies the model invariants (AC-M1-25): the
/// only ways to make one are the throwing initialiser and `init(from:)`, which share one validation. Properties are
/// read-only outside `TendCore`; engine code inside the module keeps the invariants when it produces new values.
public struct HouseholdTask: Identifiable, Hashable, Sendable {
    public internal(set) var id: UUID
    public internal(set) var title: String
    public internal(set) var kind: TaskKind
    public internal(set) var roomID: UUID?
    /// The effort as captured. `maintenance` counts as low effort for matching, but this value is never changed.
    public internal(set) var effort: Effort
    /// A bill, food about to expire: something that comes back gently rather than moving on. Internal model flag only;
    /// the word never reaches copy (design.md).
    public internal(set) var isCritical: Bool
    public internal(set) var isDeepClean: Bool
    public internal(set) var isWeatherDependent: Bool
    public internal(set) var allowedDayparts: Set<Daypart>
    public internal(set) var allowedWeekdays: Set<Weekday>
    /// Start of the half-open window `[windowStart, windowEnd)`.
    public internal(set) var windowStart: Date
    /// End of the half-open window `[windowStart, windowEnd)`. Always after `windowStart`; both are finite (AC-M2-02).
    public internal(set) var windowEnd: Date
    /// Days between occurrences; present exactly when `kind == .recurring`, and at least 1.
    public internal(set) var recurrenceIntervalDays: Int?
    public internal(set) var state: TaskState
    /// When the task was last completed, if ever.
    public internal(set) var completedAt: Date?

    /// Creates a task, rejecting any combination the model invariants forbid (AC-M1-25).
    ///
    /// Invariants are checked in the order of `TaskInvariantViolation`'s cases; the first one broken is thrown.
    /// Defaults: no room, not critical, not a deep clean, not weather-dependent, quiet at night
    /// (`Daypart.defaultAllowed`, brief Q2), any weekday, `active`, never completed.
    public init(
        id: UUID,
        title: String,
        kind: TaskKind,
        roomID: UUID? = nil,
        effort: Effort,
        isCritical: Bool = false,
        isDeepClean: Bool = false,
        isWeatherDependent: Bool = false,
        allowedDayparts: Set<Daypart> = Daypart.defaultAllowed,
        allowedWeekdays: Set<Weekday> = Set(Weekday.allCases),
        windowStart: Date,
        windowEnd: Date,
        recurrenceIntervalDays: Int? = nil,
        state: TaskState = .active,
        completedAt: Date? = nil
    ) throws(TaskInvariantViolation) {
        self.id = id
        self.title = title
        self.kind = kind
        self.roomID = roomID
        self.effort = effort
        self.isCritical = isCritical
        self.isDeepClean = isDeepClean
        self.isWeatherDependent = isWeatherDependent
        self.allowedDayparts = allowedDayparts
        self.allowedWeekdays = allowedWeekdays
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.state = state
        self.completedAt = completedAt
        if let violation = firstInvariantViolation() {
            throw violation
        }
    }

    /// The first broken model invariant, in `TaskInvariantViolation` case order, or `nil` if the task is valid.
    /// Engine code that derives a new task inside `TendCore` can use this to check its own output.
    func firstInvariantViolation() -> TaskInvariantViolation? {
        if allowedDayparts.isEmpty { return .noAllowedDayparts }
        if allowedWeekdays.isEmpty { return .noAllowedWeekdays }
        // Before the order check: NaN makes `windowEnd > windowStart` false, which would report the wrong reason
        // (AC-M2-02 W2-F3, Q9; Designer's position, M2 design.md).
        if !windowStart.timeIntervalSinceReferenceDate.isFinite || !windowEnd.timeIntervalSinceReferenceDate.isFinite {
            return .windowDateNotFinite
        }
        if !(windowEnd > windowStart) { return .windowEndNotAfterStart }
        switch (kind, recurrenceIntervalDays) {
        case (.recurring, nil): return .recurringWithoutInterval
        case (.recurring, let days?) where days < 1: return .intervalBelowOneDay
        case (.oneOff, _?), (.restock, _?): return .intervalOnNonRecurringTask
        default: break
        }
        if isCritical && isDeepClean { return .criticalAndDeepClean }
        if state == .maintenance && !isDeepClean { return .maintenanceOnNonDeepClean }
        if state == .resurfaced && !isCritical { return .resurfacedOnNonCritical }
        return nil
    }
}

// MARK: - Effective-state helpers (brief definitions, Q12, Q13; design D-1)

extension HouseholdTask {
    /// The task is deferred and its rest has not ended yet (`until > now`). A resting task is never shown and never
    /// moved by the rescheduler, even if its window has ended (brief Q12).
    public func isResting(at now: Date) -> Bool {
        if case .deferred(let until) = state { return until > now }
        return false
    }

    /// The task is deferred and its rest is over (`until <= now`). It then behaves exactly as `active` (brief Q12).
    public func isRestOver(at now: Date) -> Bool {
        if case .deferred(let until) = state { return until <= now }
        return false
    }

    /// `windowStart <= now < windowEnd` (half-open). About the window only; the state is not considered.
    public func windowIsOpen(at now: Date) -> Bool {
        windowStart <= now && now < windowEnd
    }

    /// `windowEnd <= now`: the window has ended (`windowEnd == now` counts as ended, brief Q13). About the window only;
    /// whether the rescheduler moves the task also depends on its state (completed and resting tasks stay as they are).
    public func windowHasEnded(at now: Date) -> Bool {
        windowEnd <= now
    }
}

// MARK: - Codable (AC-M1-01; decode validates invariants, AC-M1-25)

extension HouseholdTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case roomID
        case effort
        case isCritical
        case isDeepClean
        case isWeatherDependent
        case allowedDayparts
        case allowedWeekdays
        case windowStart
        case windowEnd
        case recurrenceIntervalDays
        case state
        case completedAt
    }

    /// Decodes and validates. A file that breaks an invariant throws the `TaskInvariantViolation` itself (not a
    /// `DecodingError`), so the repository can report it as a typed error (WI-M1-02, AC-M1-06).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            kind: container.decode(TaskKind.self, forKey: .kind),
            roomID: container.decodeIfPresent(UUID.self, forKey: .roomID),
            effort: container.decode(Effort.self, forKey: .effort),
            isCritical: container.decode(Bool.self, forKey: .isCritical),
            isDeepClean: container.decode(Bool.self, forKey: .isDeepClean),
            isWeatherDependent: container.decode(Bool.self, forKey: .isWeatherDependent),
            allowedDayparts: Set(container.decode([Daypart].self, forKey: .allowedDayparts)),
            allowedWeekdays: Set(container.decode([Weekday].self, forKey: .allowedWeekdays)),
            windowStart: container.decode(Date.self, forKey: .windowStart),
            windowEnd: container.decode(Date.self, forKey: .windowEnd),
            recurrenceIntervalDays: container.decodeIfPresent(Int.self, forKey: .recurrenceIntervalDays),
            state: container.decode(TaskState.self, forKey: .state),
            completedAt: container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }

    /// Sets are written in case order, so the same task always encodes to the same JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(roomID, forKey: .roomID)
        try container.encode(effort, forKey: .effort)
        try container.encode(isCritical, forKey: .isCritical)
        try container.encode(isDeepClean, forKey: .isDeepClean)
        try container.encode(isWeatherDependent, forKey: .isWeatherDependent)
        try container.encode(Daypart.allCases.filter(allowedDayparts.contains), forKey: .allowedDayparts)
        try container.encode(Weekday.allCases.filter(allowedWeekdays.contains), forKey: .allowedWeekdays)
        try container.encode(windowStart, forKey: .windowStart)
        try container.encode(windowEnd, forKey: .windowEnd)
        try container.encodeIfPresent(recurrenceIntervalDays, forKey: .recurrenceIntervalDays)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}
