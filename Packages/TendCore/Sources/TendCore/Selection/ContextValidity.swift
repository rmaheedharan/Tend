import Foundation

// "Contextually valid at `now`" (brief Definitions, Q1, Q3, Q12, Q13; AC-M1-08…12; FR-B1).
// All of: effective state is `active`, `maintenance` or `resurfaced` (a deferral whose rest is over counts as
// `active`); the window is open (half-open); `now` lies in an allowed slot; the energy matches the effort (maintenance
// counts as low); and the task is weather-safe. Internal on purpose: the only public "what to do now" API is
// `NowSelector`, which returns a `NowSelection` of at most three (UX-2).

extension EnergyLevel {
    /// Brief Q1: low → low only; normal → low + normal; high → every effort.
    func accepts(_ effort: Effort) -> Bool {
        switch self {
        case .low: effort == .low
        case .normal: effort != .high
        case .high: true
        }
    }
}

extension WeatherCondition {
    /// Brief Q3: only `clear` and `cloudy` are safe for weather-dependent tasks; `unknown` is not a guess.
    var isSafeForWeatherDependentTasks: Bool {
        switch self {
        case .clear, .cloudy: true
        case .wet, .severe, .unknown: false
        }
    }
}

extension HouseholdTask {
    /// The effort used for matching: a deep clean in `maintenance` counts as low; the stored effort is unchanged (Q1, Q5).
    var effortForMatching: Effort {
        state == .maintenance ? .low : effort
    }

    /// Effective state at `now` is one the selector may offer (Q12): `active`, `maintenance`, `resurfaced`, or a
    /// deferral whose rest is over. Completed and resting tasks never qualify.
    func isOfferable(at now: Date) -> Bool {
        switch state {
        case .active, .maintenance, .resurfaced: true
        case .deferred: isRestOver(at: now)
        case .completed: false
        }
    }

    /// The brief's "contextually valid at `now`". `slotOfNow` is the slot containing `moment.now`, computed once per
    /// selection by the caller (it depends only on the moment). The task is never changed (Q13).
    func isContextuallyValid(in moment: Moment, slotOfNow: Slot?) -> Bool {
        guard isOfferable(at: moment.now), windowIsOpen(at: moment.now) else { return false }
        guard let slot = slotOfNow, slot.isAllowed(dayparts: allowedDayparts, weekdays: allowedWeekdays) else {
            return false
        }
        guard moment.energy.accepts(effortForMatching) else { return false }
        return !isWeatherDependent || moment.weather.isSafeForWeatherDependentTasks
    }
}
