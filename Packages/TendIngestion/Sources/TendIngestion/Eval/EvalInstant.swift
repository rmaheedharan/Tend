// A point in time as the eval files write it (AC-M2-28 results file v1; the household fixture). FR-A1.
//
// The format is fixed UTC with milliseconds, `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (years 0001…9999), for the draft window
// dates and the fixture task dates. The run's `startedAtUTC` uses the same form without milliseconds (the file-name
// timestamp is to the second, AC-M2-28). Conversion is pure civil-calendar arithmetic (proleptic Gregorian, UTC), so it
// needs no `DateFormatter`, `Calendar` or locale and gives the same answer on Linux and the Mac (AC-M2-09 Rule 1).
//
// A `Date` is recorded rounded down to the whole millisecond. The M1 window rule (`windowEnd > windowStart`) is checked
// on the recorded values, so two window ends less than 1 ms apart would read as equal (dev-notes WI-M2-15, E5).

import Foundation

/// Milliseconds since 1970-01-01T00:00:00Z.
public struct EvalInstant: Sendable, Hashable, Comparable {
    public let millisecondsSince1970: Int64

    public init(millisecondsSince1970: Int64) {
        self.millisecondsSince1970 = millisecondsSince1970
    }

    /// The instant of `date`, rounded down to the millisecond. Nil for a non-finite or out-of-range date.
    ///
    /// `Date` stores seconds since 2001-01-01, so the conversion works in that frame with the exact integer offset
    /// (978,307,200,000 ms) and never through `timeIntervalSince1970`, which adds a second rounding. `seconds * 1000`
    /// can land just below a whole millisecond, so the floor is corrected to the largest m with m / 1000 ≤ seconds,
    /// the same division `date` uses. Then `EvalInstant(i.date) == i` for every instant (tested).
    public init?(_ date: Date) {
        let seconds = date.timeIntervalSinceReferenceDate
        let milliseconds = (seconds * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= Double(Self.minimum - Self.referenceOffset),
              milliseconds <= Double(Self.maximum - Self.referenceOffset)
        else { return nil }
        var m = Int64(milliseconds)
        while Double(m) / 1000 > seconds { m -= 1 }
        while Double(m + 1) / 1000 <= seconds { m += 1 }
        self.millisecondsSince1970 = m + Self.referenceOffset
    }

    public var date: Date {
        Date(timeIntervalSinceReferenceDate: Double(millisecondsSince1970 - Self.referenceOffset) / 1000)
    }

    /// 2001-01-01T00:00:00Z in milliseconds since 1970.
    static let referenceOffset: Int64 = 978_307_200_000

    public static func < (lhs: EvalInstant, rhs: EvalInstant) -> Bool {
        lhs.millisecondsSince1970 < rhs.millisecondsSince1970
    }

    /// 0001-01-01T00:00:00.000Z and 9999-12-31T23:59:59.999Z.
    static let minimum: Int64 = daysFromCivil(year: 1, month: 1, day: 1) * 86_400_000
    static let maximum: Int64 = (daysFromCivil(year: 9999, month: 12, day: 31) + 1) * 86_400_000 - 1

    // MARK: - Text form

    /// `yyyy-MM-ddTHH:mm:ss.SSSZ`.
    public var text: String {
        let (days, inDay) = Self.floorDivide(millisecondsSince1970, 86_400_000)
        let (year, month, day) = Self.civilFromDays(days)
        let hour = inDay / 3_600_000
        let minute = inDay / 60_000 % 60
        let second = inDay / 1000 % 60
        let milli = inDay % 1000
        return Self.pad(year, 4) + "-" + Self.pad(month, 2) + "-" + Self.pad(day, 2) + "T" + Self.pad(hour, 2) + ":"
            + Self.pad(minute, 2) + ":" + Self.pad(second, 2) + "." + Self.pad(milli, 3) + "Z"
    }

    /// Reads `yyyy-MM-ddTHH:mm:ss.SSSZ`, or `yyyy-MM-ddTHH:mm:ssZ` when `milliseconds` is false. Every field must be in
    /// range (month 1…12, day within the month, hour 0…23, minute and second 0…59).
    public init?(text: String, milliseconds: Bool = true) {
        let bytes = Array(text.utf8)
        let length = milliseconds ? 24 : 20
        guard bytes.count == length else { return nil }
        func digits(_ start: Int, _ count: Int) -> Int64? {
            var value: Int64 = 0
            for byte in bytes[start..<(start + count)] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int64(byte - UInt8(ascii: "0"))
            }
            return value
        }
        let separators: [(Int, Character)] = [(4, "-"), (7, "-"), (10, "T"), (13, ":"), (16, ":")]
            + (milliseconds ? [(19, "."), (23, "Z")] : [(19, "Z")])
        for (offset, character) in separators where bytes[offset] != character.asciiValue {
            return nil
        }
        guard let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2), let hour = digits(11, 2),
              let minute = digits(14, 2), let second = digits(17, 2)
        else { return nil }
        let milli: Int64
        if milliseconds {
            guard let value = digits(20, 3) else { return nil }
            milli = value
        } else {
            milli = 0
        }
        guard year >= 1, (1...12).contains(month), day >= 1, day <= Self.daysInMonth(year: year, month: month),
              hour <= 23, minute <= 59, second <= 59
        else { return nil }
        let days = Self.daysFromCivil(year: year, month: month, day: day)
        millisecondsSince1970 = days * 86_400_000 + hour * 3_600_000 + minute * 60_000 + second * 1000 + milli
    }

    // MARK: - Civil calendar (H. Hinnant's days_from_civil / civil_from_days)

    static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = floorDivide(y, 400).quotient
        let yearOfEra = y - era * 400
        let monthIndex = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = floorDivide(z, 146_097).quotient
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func floorDivide(_ a: Int64, _ b: Int64) -> (quotient: Int64, remainder: Int64) {
        let q = a / b
        let r = a % b
        return r < 0 ? (q - 1, r + b) : (q, r)
    }

    static func pad(_ value: Int64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
