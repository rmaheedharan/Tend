import Foundation
import TendCore

/// The structured time hint the language model reports for one item (AC-M2-03, FR-A1; plan "Q6 time-phrase table").
///
/// The model never sends dates. It sends this neutral hint, and `TimeResolver` turns it into a window, dayparts,
/// weekdays and an interval with the injected `now`, calendar and time zone. The on-device `@Generable` type and the
/// cloud schemas mirror it field by field.
///
/// Unknown values are mapped before the resolver sees them (Q5 step 2): an unknown anchor becomes `.unrecognized`; an
/// unknown daypart, weekday, season or repeat unit, and any non-integer, non-finite or unrepresentable number, becomes
/// `nil`.
public struct TimeHint: Hashable, Sendable {

    /// What the phrase is anchored on (plan "The hint").
    public enum Anchor: String, CaseIterable, Hashable, Sendable {
        /// No time phrase (rows T1, T15).
        case none
        case today
        case tonight
        case tomorrow
        /// Needs `weekday`.
        case weekday
        case thisWeekend
        case thisWeek
        case nextWeek
        /// Needs `month` 1…12.
        case beforeMonth
        /// Needs `season`.
        case beforeSeason
        /// Needs `count` 1…366.
        case inDays
        /// Needs `count` 1…52.
        case inWeeks
        /// The model sent a value outside this list. The hint is unusable and resolves as no hint (T1).
        case unrecognized
    }

    /// Meteorological, northern-hemisphere seasons (Q6(c)): spring 1 Mar, summer 1 Jun, autumn 1 Sep, winter 1 Dec.
    public enum Season: String, CaseIterable, Hashable, Sendable {
        case spring
        case summer
        case autumn
        case winter

        /// The Gregorian month in which the season starts (on its first day).
        public var startMonth: Int {
            switch self {
            case .spring: 3
            case .summer: 6
            case .autumn: 9
            case .winter: 12
            }
        }
    }

    /// The unit of a repeat (rows R1–R4).
    public enum RepeatUnit: String, CaseIterable, Hashable, Sendable {
        case day
        case week
        case month
        case year

        /// Days per unit: 1 month = 30 days (Q6), 1 year = 365 days (P6).
        public var days: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }
    }

    public var anchor: Anchor
    public var daypart: Daypart?
    public var weekday: Weekday?
    public var month: Int?
    public var season: Season?
    public var count: Int?
    /// A value < 1 means no repeat.
    public var repeatEvery: Int?
    public var repeatUnit: RepeatUnit?

    public init(
        anchor: Anchor,
        daypart: Daypart? = nil,
        weekday: Weekday? = nil,
        month: Int? = nil,
        season: Season? = nil,
        count: Int? = nil,
        repeatEvery: Int? = nil,
        repeatUnit: RepeatUnit? = nil
    ) {
        self.anchor = anchor
        self.daypart = daypart
        self.weekday = weekday
        self.month = month
        self.season = season
        self.count = count
        self.repeatEvery = repeatEvery
        self.repeatUnit = repeatUnit
    }
}
