import Foundation

/// The moment a selection is made for (FR-B1; design.md naming list). Every input is injected, so the same moment
/// always gives the same answer (CLAUDE.md §3): `TendCore` never reads the clock, the device calendar or time zone,
/// or the weather.
public struct Moment: Hashable, Sendable {
    /// The instant the selection is for.
    public let now: Date
    /// The injected calendar (Gregorian in tests), with `timeZone` applied.
    public let calendar: Calendar
    /// The injected time zone. Dayparts and weekdays are local to this zone; it wins over the calendar's own zone.
    public let timeZone: TimeZone
    /// The injected weather (`unknown` when none was supplied, brief Q3).
    public let weather: WeatherCondition
    /// The person's energy right now (brief Q1). A state, never a judgement.
    public let energy: EnergyLevel

    public init(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        weather: WeatherCondition,
        energy: EnergyLevel
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
        self.weather = weather
        self.energy = energy
    }
}
