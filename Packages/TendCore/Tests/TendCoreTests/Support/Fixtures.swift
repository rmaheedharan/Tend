// Deterministic fixtures for model tests (no `Date()` / `UUID()`: every input is fixed, CLAUDE.md §3).

import Foundation
import TendCore

enum Fixtures {
    /// A fixed instant (November 2025) with a sub-second part, so Codable round-trips are checked with fractional dates.
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 784_102_400.123_456)

    static func id(_ n: Int) -> UUID {
        // Deterministic UUIDs: 00000000-0000-0000-0000-<n as 12 hex digits>.
        let suffix = String(n, radix: 16)
        let padded = String(repeating: "0", count: max(0, 12 - suffix.count)) + suffix
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(padded)") else {
            preconditionFailure("fixture UUID is malformed")  // test-only; not a user path
        }
        return uuid
    }

    static let kitchenID = id(0xA1)

    /// A valid task with sensible defaults; each test overrides only what it is about.
    static func task(
        id: UUID = id(1),
        title: String = "Wipe the kitchen counters",
        kind: TaskKind = .oneOff,
        roomID: UUID? = kitchenID,
        effort: Effort = .normal,
        isCritical: Bool = false,
        isDeepClean: Bool = false,
        isWeatherDependent: Bool = false,
        allowedDayparts: Set<Daypart> = Daypart.defaultAllowed,
        allowedWeekdays: Set<Weekday> = Set(Weekday.allCases),
        windowStart: Date = referenceDate,
        windowEnd: Date = referenceDate.addingTimeInterval(3 * 24 * 3600 + 0.5),
        recurrenceIntervalDays: Int? = nil,
        state: TaskState = .active,
        completedAt: Date? = nil
    ) throws(TaskInvariantViolation) -> HouseholdTask {
        try HouseholdTask(
            id: id, title: title, kind: kind, roomID: roomID, effort: effort,
            isCritical: isCritical, isDeepClean: isDeepClean, isWeatherDependent: isWeatherDependent,
            allowedDayparts: allowedDayparts, allowedWeekdays: allowedWeekdays,
            windowStart: windowStart, windowEnd: windowEnd,
            recurrenceIntervalDays: recurrenceIntervalDays, state: state, completedAt: completedAt
        )
    }

    /// Every non-empty subset of a finite set of cases.
    static func nonEmptySubsets<T: Hashable>(of all: [T]) -> [Set<T>] {
        (1..<(1 << all.count)).map { mask in
            Set(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
        }
    }

    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Encodes `value` to a JSON object so a test can edit fields without depending on the encoded shape of each
    /// field (values are transplanted from other encoded values).
    static func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.notAnObject
        }
        return object
    }

    static func decode<T: Decodable>(
        _ type: T.Type, fromJSONObject object: [String: Any], using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try decoder.decode(type, from: data)
    }

    /// The string `nonConformingDecoder()` reads as `Double.nan` (AC-M2-02, W2-F3). No repository uses such a decoder.
    static let nonConformingNaN = "nan"

    /// A decoder that reads "+inf", "-inf" and "nan" strings as non-finite doubles, so a test can reach the model's
    /// own decode validation with a value strict JSON cannot carry (AC-M2-02, W2-F3).
    static func nonConformingDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+inf", negativeInfinity: "-inf", nan: nonConformingNaN)
        return decoder
    }

    enum FixtureError: Error { case notAnObject }
}
