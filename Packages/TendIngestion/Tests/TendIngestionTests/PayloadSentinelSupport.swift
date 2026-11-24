// Test support for WI-M2-11, the payload proof (● AC-M2-20 (a) and (b); brief Definitions "Cloud request",
// "Duplicate shortlist"; Q12, Q19; review R28-F2, R28-F6). P-2, P-3, P-4.
//
// - `SentinelHouseholdGenerator`: seeded households (SplitMix64) whose every field outside allowed content holds a
//   unique value: random task and room IDs, a unique letter token in every task title, whole-millisecond dates for
//   `windowStart`, `windowEnd`, `completedAt`, `deferred(until:)` and `lastTendedAt`, intervals in 600…729 days, and a
//   random `now`, time zone and calendar per capture. Room names never hold a sentinel (Q19): they are user labels,
//   including blank, whitespace-only and repeated names (D11).
// - `PayloadSentinels`: the string sentinels of one capture (each date in four forms) and `SentinelScanner`, a
//   multi-needle byte search (an index on the first four bytes, so ≥ 500 households stay fast).
// - `PayloadStructure`: the AC-M2-20 (b) check of one captured request against the provider's committed golden request
//   and allowed key-path list, at concrete array indices (R28-F6), plus the byte-level frame check (every byte outside
//   the user-content string equals the golden body's).
// - `PayloadRouterHarness`: sends a capture through `ModelRouter.events(…)` (the path that really sends, R28-F2) to the
//   recording mock transport and returns the captured request.
//
// What (a) covers and what still relies on (b) (review R31-F2). The scan finds each sentinel as raw bytes, without
// ASCII case, JSON-escaped (with and without `\/`, and with `\u` escapes for non-ASCII), percent- and form-encoded,
// and each date also as ISO 8601 to the minute and as the date alone. It does **not** find other transformations: other
// date layouts (compact `yyyyMMdd`, locale-formatted, days or hours since an epoch), base64 or any hash, a value split
// across fields, or a value reworded. In this harness (b) catches all of those, because it pins every byte of the
// request (the auth value included, R31-F1) against the committed golden. Reusing (a) where (b) is weaker (the real
// adapters, WI-M2-M6, or a request without a golden) needs that gap closed there.
//
// The checks return lists of problems (empty = pass) so the negative tests can show that each one is real.
// The expectations never come from the code under test: room names are the household's, titles come from the WI-M2-07
// independent shortlist oracle (`DupOracle`), and fixed values come from the committed golden files.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

// MARK: - One generated capture

/// One seeded capture with its household and the injected time inputs.
struct SentinelCase: Sendable {
    var index: Int
    var household: Household
    var capture: String
    var now: Date
    var timeZone: TimeZone
    var calendar: Calendar
    /// The calendar identifier as text, in every form checked (the CLDR form and the Swift case name).
    var calendarNames: [String]
    /// The unique letter token in each task's title, by task ID.
    var titleTokens: [UUID: String]
}

/// Seeded households for the payload proof. Every unique value is made from the generator, never fixed.
struct SentinelHouseholdGenerator {
    var rnd: DupRandom
    private var nextToken = 0

    init(seed: UInt64) { rnd = DupRandom(seed: seed) }

    /// Chore words. Letters only (no digit: the interval sentinels 600…729 must not occur in allowed content).
    static let words = ["buy", "dish", "pods", "dishwasher", "wipe", "kitchen", "counter", "clean", "oven", "laundry",
                        "sheets", "water", "plants", "hall", "garage", "dust", "shelf", "milk", "bathroom", "tiles",
                        "towels", "bins", "fold", "sweep", "porch", "fridge", "filter", "windows", "mop", "floor",
                        "rugs", "vacuum", "stairs", "gutters", "lawn", "bulbs", "soap", "sponges", "recycling",
                        "Caf\u{E9}", "balcony", "Bathroom"]
    static let fillers = ["the", "and", "we", "need", "to", "again", "please", "um", "we\u{2019}re", "low", "on",
                          "almost", "out", "of", "\u{1F9FA}", "\"quickly\"", "so"]
    static let separators = [" ", " ", " ", "  ", ", ", "\n", "\t", " - "]
    /// Room names as a user writes them (Q19). Never a sentinel; blank, whitespace-only and repeated names on purpose
    /// (D11: sent as written, in order).
    static let roomNames = ["Kitchen", "Bathroom", "Balcony", "Garage", "Hall", "Kids\u{2019} room", "Caf\u{E9}",
                            "  Hall  ", "Laundry \"nook\"", "Shed/Yard", "Loft\\attic", "", "  ", "\t", "Kitchen",
                            "Porch", "the Laundry"]
    /// Time zones the swift:6.2 Linux image and Darwin both have. None of their identifiers occurs in any fixed part
    /// or in the vocabulary (checked per capture by `PayloadSentinels.hygiene`).
    static let timeZoneIdentifiers = ["Pacific/Chatham", "Asia/Kathmandu", "America/St_Johns", "Australia/Lord_Howe",
                                      "Africa/Ouagadougou", "Atlantic/Reykjavik", "Asia/Ulaanbaatar",
                                      "Indian/Kerguelen", "America/Argentina/Ushuaia", "Pacific/Marquesas"]
    /// Calendars, with their identifier in the CLDR form and the Swift case name written out (review R31-N1:
    /// `String(describing:)` gives the CLDR form on Linux, so the case name is a literal here).
    static let calendars: [(Calendar.Identifier, String, String)] = [
        (.gregorian, "gregorian", "gregorian"), (.buddhist, "buddhist", "buddhist"), (.japanese, "japanese", "japanese"),
        (.hebrew, "hebrew", "hebrew"), (.persian, "persian", "persian"), (.coptic, "coptic", "coptic"),
        (.iso8601, "iso8601", "iso8601"), (.islamicCivil, "islamic-civil", "islamicCivil"),
        (.indian, "indian", "indian"), (.ethiopicAmeteMihret, "ethiopic", "ethiopicAmeteMihret"),
    ]

    /// A date with whole milliseconds between 2025-01-01 and 2035-01-01 (UTC), so each of the four forms is exact.
    mutating func date() -> Date {
        let low: Int64 = 1_735_689_600_000, span: Int64 = 315_619_200_000
        let ms = low + Int64(rnd.next() % UInt64(span))
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    /// A unique title token: `zq` and six letters without `z` or `q`, so a token can never occur inside another
    /// token or inside the vocabulary.
    mutating func token() -> String {
        let letters = Array("abcdefghijklmnoprstuvwxy")
        var value = nextToken
        nextToken += 1
        var text = ""
        for _ in 0..<6 {
            text.append(letters[value % letters.count])
            value /= letters.count
        }
        return "zq" + text
    }

    mutating func phrase(_ count: Int, from pool: [String]) -> String {
        var text = ""
        for _ in 0..<count {
            let word = rnd.pick(pool)
            text = text.isEmpty ? word : text + rnd.pick(Self.separators) + word
        }
        return text
    }

    mutating func someDayparts() -> Set<Daypart> {
        let set = Set(Daypart.allCases.filter { _ in rnd.chance(60) })
        return set.isEmpty ? Daypart.defaultAllowed : set
    }

    mutating func someWeekdays() -> Set<Weekday> {
        let set = Set(Weekday.allCases.filter { _ in rnd.chance(70) })
        return set.isEmpty ? [rnd.pick(Weekday.allCases)] : set
    }

    /// One household and one capture.
    mutating func next(index: Int) -> SentinelCase {
        var rooms: [Room] = []
        for _ in 0..<rnd.int(0...8) {
            rooms.append(Room(id: rnd.uuid(), name: rnd.pick(Self.roomNames), lastTendedAt: rnd.chance(70) ? date() : nil))
        }
        // A theme word many tasks share, so that more than 10 eligible tasks (the cut) is common.
        let theme = rnd.pick(Self.words)
        var tasks: [HouseholdTask] = []
        var tokens: [UUID: String] = [:]
        let count = rnd.chance(35) ? rnd.int(25...60) : rnd.int(1...24)
        while tasks.count < count {
            let token = token()
            var words = phrase(rnd.int(1...3), from: Self.words)
            if rnd.chance(40) { words = theme + " " + words }
            var title = rnd.chance(50) ? words + " " + token : token + " " + words
            if rnd.chance(15) { title = " \t" + title + " \n" }  // trimmed when sent
            let kind = rnd.pick(TaskKind.allCases)
            var state: TaskState = rnd.pick([.active, .active, .maintenance, .resurfaced, .completed, .completed])
            if rnd.chance(15) { state = .deferred(until: date()) }
            var finalKind = kind
            if state == .completed && kind == .recurring { finalKind = rnd.chance(50) ? .oneOff : .restock }
            let isCritical = state == .resurfaced || (state != .maintenance && rnd.chance(15))
            let isDeepClean = state == .maintenance || (!isCritical && rnd.chance(20))
            var roomID: UUID?
            if !rooms.isEmpty && rnd.chance(65) { roomID = rnd.pick(rooms).id } else if rnd.chance(10) { roomID = rnd.uuid() }
            let start = date()
            let end = start.addingTimeInterval(Double(rnd.int(3_600_000...34_560_000_000)) / 1000)
            let completedAt: Date? = state == .completed || rnd.chance(35) ? date() : nil
            let built = try? HouseholdTask(
                id: rnd.uuid(), title: title, kind: finalKind, roomID: roomID, effort: rnd.pick(Effort.allCases),
                isCritical: isCritical, isDeepClean: isDeepClean, isWeatherDependent: rnd.chance(30),
                allowedDayparts: someDayparts(), allowedWeekdays: someWeekdays(), windowStart: start, windowEnd: end,
                recurrenceIntervalDays: finalKind == .recurring ? rnd.int(600...729) : nil, state: state,
                completedAt: completedAt)
            guard let built, tokens[built.id] == nil else { continue }
            tasks.append(built)
            tokens[built.id] = token
        }
        // The capture: words of some titles (live and completed), sometimes a room name, and fillers. No token.
        var parts: [String] = []
        for _ in 0..<rnd.int(1...4) {
            if let task = tasks.isEmpty ? nil : rnd.pick(tasks), rnd.chance(70) {
                let titleWords = task.title.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
                    .map(String.init).filter { !$0.hasPrefix("zq") }
                if let word = titleWords.isEmpty ? nil : rnd.pick(titleWords) { parts.append(word) }
            }
            if rnd.chance(30), let room = rooms.isEmpty ? nil : rnd.pick(rooms) { parts.append(room.name) }
            if rnd.chance(40) { parts.append(theme) }
            parts.append(phrase(rnd.int(0...3), from: Self.fillers))
        }
        let capture = parts.filter { !$0.isEmpty }.joined(separator: rnd.pick(Self.separators))
        let zoneID = rnd.pick(Self.timeZoneIdentifiers)
        // Review R31-N2: a zone this platform does not have is a failure, never a silent `GMT`.
        let timeZone: TimeZone
        if let zone = TimeZone(identifier: zoneID) {
            timeZone = zone
        } else {
            Issue.record("time zone \(zoneID) is not available on this platform")
            timeZone = .gmt
        }
        let (identifier, cldr, caseName) = rnd.pick(Self.calendars)
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = timeZone
        return SentinelCase(index: index, household: Household(tasks: tasks, rooms: rooms),
                            capture: capture.isEmpty ? theme : capture, now: date(), timeZone: timeZone,
                            calendar: calendar, calendarNames: cldr == caseName ? [cldr] : [cldr, caseName],
                            titleTokens: tokens)
    }
}

// MARK: - String sentinels and the multi-needle scanner

/// One string that must not occur anywhere in a request, with what it stands for.
struct Sentinel: Sendable {
    var text: String
    var label: String
}

enum PayloadSentinels {
    /// The four forms of a date (brief AC-M2-20 (a)): ISO 8601 (to the second; any suffix, fraction or offset still
    /// contains it), Unix seconds, Unix milliseconds and reference-date seconds. The ISO form is given in UTC and in
    /// the capture's time zone, and also at minute precision and as the date alone (review R31-F2). The calendar
    /// day and minute are not unique on their own across a household, but every one of them is a household value
    /// outside allowed content, so none may appear.
    static func forms(_ date: Date, label: String, timeZone: TimeZone) -> [Sentinel] {
        var formatters = ISOFormatters()
        return forms(date, label: label, timeZone: timeZone, formatters: &formatters)
    }

    /// The same, reusing formatters across the dates of one capture (a formatter per date made the run 8× slower).
    static func forms(_ date: Date, label: String, timeZone: TimeZone,
                      formatters: inout ISOFormatters) -> [Sentinel] {
        func iso(_ zone: TimeZone, _ format: String = "yyyy-MM-dd'T'HH:mm:ss") -> String {
            formatters.string(date, zone: zone, format: format)
        }
        let unixMilliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return [
            Sentinel(text: iso(.gmt), label: label + " ISO 8601 UTC"),
            Sentinel(text: iso(timeZone), label: label + " ISO 8601 local"),
            Sentinel(text: iso(.gmt, "yyyy-MM-dd'T'HH:mm"), label: label + " ISO 8601 minute UTC"),
            Sentinel(text: iso(timeZone, "yyyy-MM-dd'T'HH:mm"), label: label + " ISO 8601 minute local"),
            Sentinel(text: iso(.gmt, "yyyy-MM-dd"), label: label + " ISO 8601 date UTC"),
            Sentinel(text: iso(timeZone, "yyyy-MM-dd"), label: label + " ISO 8601 date local"),
            Sentinel(text: String(unixMilliseconds / 1000), label: label + " Unix seconds"),
            Sentinel(text: String(unixMilliseconds), label: label + " Unix milliseconds"),
            Sentinel(text: String(Int64(date.timeIntervalSinceReferenceDate.rounded(.down))),
                     label: label + " reference-date seconds"),
        ]
    }

    /// An ID in every text form: upper and lower case, with and without hyphens.
    static func forms(_ id: UUID, label: String) -> [Sentinel] {
        let upper = id.uuidString, plain = upper.replacingOccurrences(of: "-", with: "")
        return [upper, upper.lowercased(), plain, plain.lowercased()].map { Sentinel(text: $0, label: label) }
    }

    /// Every string sentinel of one capture. `sentTaskIDs` are the tasks on the shortlist actually sent (from the
    /// independent oracle); every other task's title and title token is a sentinel.
    static func strings(_ item: SentinelCase, sentTaskIDs: Set<UUID>) -> [Sentinel] {
        var result: [Sentinel] = []
        let zone = item.timeZone
        var formatters = ISOFormatters()
        func forms(_ date: Date, label: String, timeZone: TimeZone) -> [Sentinel] {
            PayloadSentinels.forms(date, label: label, timeZone: timeZone, formatters: &formatters)
        }
        func forms(_ id: UUID, label: String) -> [Sentinel] { PayloadSentinels.forms(id, label: label) }
        for room in item.household.rooms {
            result += forms(room.id, label: "room ID")
            if let tended = room.lastTendedAt { result += forms(tended, label: "lastTendedAt", timeZone: zone) }
        }
        for task in item.household.tasks {
            result += forms(task.id, label: "task ID")
            if let roomID = task.roomID { result += forms(roomID, label: "task room ID") }
            result += forms(task.windowStart, label: "windowStart", timeZone: zone)
            result += forms(task.windowEnd, label: "windowEnd", timeZone: zone)
            if let completed = task.completedAt { result += forms(completed, label: "completedAt", timeZone: zone) }
            if case let .deferred(until) = task.state { result += forms(until, label: "deferred until", timeZone: zone) }
            if !sentTaskIDs.contains(task.id) {
                if let token = item.titleTokens[task.id] { result.append(Sentinel(text: token, label: "title token")) }
                result.append(Sentinel(text: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                       label: "non-shortlisted title"))
            }
        }
        result += forms(item.now, label: "now", timeZone: zone)
        result.append(Sentinel(text: item.timeZone.identifier, label: "time-zone identifier"))
        result += item.calendarNames.map { Sentinel(text: $0, label: "calendar identifier") }
        return result + result.flatMap(encodedVariants)
    }

    /// The encoded forms of a sentinel that differ from it (review R31-F2): JSON-escaped (with and without `\/`, and
    /// with every non-ASCII scalar as `\u` escapes) and percent-encoded (with `%20` and with `+` for a space). Case
    /// changes need no variant: the scanner compares ASCII letters without case.
    static func encodedVariants(_ sentinel: Sentinel) -> [Sentinel] {
        // Plain ASCII letters, digits and `-._~` encode to themselves in every form below.
        if sentinel.text.utf8.allSatisfy({ byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
        }) { return [] }
        func json(_ text: String, slash: Bool, ascii: Bool) -> String {
            var out = ""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\\": out += "\\\\"
                case "\"": out += "\\\""
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                case "/" where slash: out += "\\/"
                default:
                    if ascii && scalar.value > 0x7E {
                        for unit in String(scalar).utf16 { out += "\\u" + String(format: "%04x", unit) }
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let percent = sentinel.text.addingPercentEncoding(withAllowedCharacters: allowed) ?? sentinel.text
        let candidates = [
            (json(sentinel.text, slash: false, ascii: false), " JSON-escaped"),
            (json(sentinel.text, slash: true, ascii: false), " JSON-escaped with \\/"),
            (json(sentinel.text, slash: true, ascii: true), " JSON-escaped ASCII"),
            (percent, " percent-encoded"),
            (percent.replacingOccurrences(of: "%20", with: "+"), " form-encoded"),
        ]
        var seen: Set<String> = [sentinel.text.lowercased()]
        var result: [Sentinel] = []
        for (text, suffix) in candidates where seen.insert(text.lowercased()).inserted {
            result.append(Sentinel(text: text, label: sentinel.label + suffix))
        }
        return result
    }

    /// Generator hygiene: no sentinel may occur in the allowed content itself (the capture, the room names and the
    /// titles that are sent), or the absence check would prove nothing about leaks. Returns the offending sentinels.
    static func hygiene(_ sentinels: [Sentinel], allowed: CloudPayloadInput) -> [String] {
        let content = ([allowed.capture] + allowed.roomNames + allowed.shortlistTitles).map(SentinelScanner.fold)
        return sentinels.filter { sentinel in
            let needle = SentinelScanner.fold(sentinel.text)
            return content.contains { $0.contains(needle) }
        }
            .map { "\($0.label) \($0.text) occurs in allowed content" }
    }

    /// The parts of a request the string sentinels are checked in: the method, host, path, query, header names,
    /// header values (the auth value included) and body bytes.
    static func parts(_ request: CloudRequest) -> [(String, [UInt8])] {
        var parts: [(String, [UInt8])] = [("method", Array(request.method.utf8)), ("host", Array(request.host.utf8)),
                                          ("path", Array(request.path.utf8))]
        for item in request.queryItems {
            parts.append(("query name", Array(item.name.utf8)))
            parts.append(("query value", Array(item.value.utf8)))
        }
        for header in request.headers {
            parts.append(("header name", Array(header.name.utf8)))
            parts.append(("header value " + header.name, header.withValue { Array($0.utf8) }))
        }
        parts.append(("body", Array(request.body)))
        return parts
    }

    /// AC-M2-20 (a), string sentinels: every sentinel found anywhere in the request.
    static func stringProblems(_ request: CloudRequest, _ scanner: SentinelScanner) -> [String] {
        parts(request).flatMap { name, bytes in scanner.found(in: bytes).map { "\($0.label) \($0.text) in \(name)" } }
    }

    // MARK: Interval sentinels (600…729 whole days)

    static let intervalRange = 600...729

    /// Every three-digit run in `text` that is an interval sentinel ("16501" contains 650).
    static func intervalDigits(in text: String) -> [Int] {
        let digits = Array(text.utf8)
        guard digits.count >= 3 else { return [] }
        var found: [Int] = []
        for start in 0...(digits.count - 3) {
            let window = digits[start..<(start + 3)]
            guard window.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { continue }
            let value = window.reduce(0) { $0 * 10 + Int($1 - 0x30) }
            if intervalRange.contains(value) { found.append(value) }
        }
        return found
    }

    /// AC-M2-20 (a), interval sentinels: in the decoded body no JSON number equals one and no string contains one
    /// (the user-content string is decoded too); in the path, the query and the header values none appears.
    static func intervalProblems(_ request: CloudRequest) -> [String] {
        var problems: [String] = []
        func walk(_ value: EvalJSON, _ path: String) {
            switch value {
            case let .integer(number) where intervalRange.contains(number):
                problems.append("number \(number) at \(path)")
            case let .string(text):
                for found in intervalDigits(in: text) { problems.append("\(found) in the string at \(path)") }
                if path.hasSuffix(".text"), let nested = try? EvalJSONReader.parse(Data(text.utf8)) {
                    walk(nested, path + "→")
                }
            case let .array(elements):
                for (offset, element) in elements.enumerated() { walk(element, path + "[\(offset)]") }
            case let .object(members):
                for member in members { walk(member.value, path + "." + member.key) }
            case .null, .bool, .integer:
                break
            }
        }
        if let body = try? EvalJSONReader.parse(request.body) { walk(body, "$") } else {
            problems.append("the body is not strict JSON")
        }
        var texts = [("path", request.path)]
        texts += request.queryItems.flatMap { [("query name", $0.name), ("query value", $0.value)] }
        texts += request.headers.map { header in ("header value " + header.name, header.withValue { $0 }) }
        for (name, text) in texts {
            for found in intervalDigits(in: text) { problems.append("\(found) in \(name)") }
        }
        return problems
    }
}

/// `DateFormatter`s for the ISO forms, made once per zone and layout (en_US_POSIX, Gregorian).
struct ISOFormatters {
    private var cache: [String: DateFormatter] = [:]

    mutating func string(_ date: Date, zone: TimeZone, format: String) -> String {
        let key = zone.identifier + "|" + format
        if let formatter = cache[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = format
        cache[key] = formatter
        return formatter.string(from: date)
    }
}

/// Finds which of many needles occur in a byte buffer. Needles are indexed by their first four bytes, so one pass over
/// the buffer checks all of them; every candidate is then compared byte for byte. ASCII letters are compared without
/// case (review R31-F2), so an upper-case token or a mixed-case ID is found too.
struct SentinelScanner {
    private var index: [UInt32: [(bytes: [UInt8], sentinel: Sentinel)]] = [:]
    /// Needles shorter than four bytes (none in practice), compared the slow way.
    private var short: [Sentinel] = []

    init(_ sentinels: [Sentinel]) {
        for sentinel in sentinels where !sentinel.text.isEmpty {
            let bytes = Self.fold(Array(sentinel.text.utf8))
            if bytes.count < 4 { short.append(sentinel); continue }
            index[Self.key(bytes, 0), default: []].append((bytes, sentinel))
        }
    }

    private static func key(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    /// ASCII `A`…`Z` to `a`…`z`; every other byte unchanged.
    static func fold(_ bytes: [UInt8]) -> [UInt8] { bytes.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 } }
    static func fold(_ text: String) -> String { String(decoding: fold(Array(text.utf8)), as: UTF8.self) }

    func found(in original: [UInt8]) -> [Sentinel] {
        let haystack = Self.fold(original)
        var result: [Sentinel] = []
        if haystack.count >= 4 {
            for start in 0...(haystack.count - 4) {
                guard let candidates = index[Self.key(haystack, start)] else { continue }
                for candidate in candidates where start + candidate.bytes.count <= haystack.count
                    && haystack[start..<(start + candidate.bytes.count)].elementsEqual(candidate.bytes) {
                    result.append(candidate.sentinel)
                }
            }
        }
        for sentinel in short where PayloadOracle.contains(Data(haystack), Self.fold(sentinel.text)) {
            result.append(sentinel)
        }
        return result
    }
}

// MARK: - The structural check (AC-M2-20 (b))

/// One step of a concrete path.
enum JSONStep: Sendable {
    case key(String)
    case index(Int)
}

enum PayloadStructure {

    /// Every leaf of a value at its concrete path (`$.messages[1].content[0].text`): every scalar, and every empty
    /// array or object. Unlike the `[]` form, an extra array element gives extra paths (review R28-F6).
    static func concreteLeaves(_ value: EvalJSON) -> [String: EvalJSON] {
        var leaves: [String: EvalJSON] = [:]
        func walk(_ value: EvalJSON, _ path: String) {
            switch value {
            case let .object(members):
                if members.isEmpty { leaves[path] = value }
                for member in members { walk(member.value, path + "." + member.key) }
            case let .array(elements):
                if elements.isEmpty { leaves[path] = value }
                for (offset, element) in elements.enumerated() { walk(element, path + "[\(offset)]") }
            case .null, .bool, .integer, .string:
                leaves[path] = value
            }
        }
        walk(value, "$")
        return leaves
    }

    /// The committed golden request and allowed list of one provider (the reference for every capture).
    struct Reference: Sendable {
        var provider: CloudProvider
        /// G1's head lines: the request line, then `Name: value` per header.
        var headLines: [String]
        var goldenBody: Data
        /// The body bytes before and after the user-content string literal (quotes included in neither).
        var framePrefix: [UInt8]
        var frameSuffix: [UInt8]
        var fixedLeaves: [String: EvalJSON]
        var userContentAt: String
        var allowedPaths: [String]
        /// The builder's header names from the allowed list (roles `auth` and `fixed`), in order.
        var allowedHeaderNames: [String]
        var authHeaderName: String
        var userContentLayout: Set<String>
    }

    static func reference(_ provider: CloudProvider) throws -> Reference {
        let stem = PayloadGolden.stem(PayloadGolden.g1, provider)
        let head = PayloadText.string(try PayloadFixture.repositoryFile(PayloadFixture.goldenDirectory + "/" + stem
                                                                        + ".head.txt"))
        let body = try PayloadFixture.repositoryFile(PayloadFixture.goldenDirectory + "/" + stem + ".body.json")
        let frame = try #require(userContentFrame(Array(body)), "no user-content string in \(stem)")
        let list = try EvalJSONReader.parse(try PayloadFixture.repositoryFile(
            PayloadFixture.payloadDirectory + "/allowed-key-paths-" + PayloadFixture.name(provider) + ".json"))
        var allowed: [String] = []
        var at: String?
        if case let .array(entries)? = list["keyPaths"] {
            for entry in entries {
                if case let .string(path)? = entry["path"] { allowed.append(path) }
                if case let .string(value)? = entry["at"] { at = value }
            }
        }
        var headerNames: [String] = []
        var authName: String?
        if case let .array(entries)? = list["headers"] {
            for entry in entries {
                guard case let .string(name)? = entry["name"], case let .string(role)? = entry["role"] else { continue }
                if role == "auth" { authName = name }
                if role == "auth" || role == "fixed" { headerNames.append(name) }
            }
        }
        var layout: Set<String> = []
        if case let .array(entries)? = list["userContentKeyPaths"] {
            for entry in entries { if case let .string(path)? = entry["path"] { layout.insert(path) } }
        }
        let userContentAt = try #require(at)
        var fixed = concreteLeaves(try EvalJSONReader.parse(body))
        fixed[userContentAt] = nil
        return Reference(provider: provider, headLines: head.split(separator: "\n").map(String.init), goldenBody: body,
                         framePrefix: frame.prefix, frameSuffix: frame.suffix, fixedLeaves: fixed,
                         userContentAt: userContentAt, allowedPaths: allowed, allowedHeaderNames: headerNames,
                         authHeaderName: try #require(authName), userContentLayout: layout)
    }

    /// Splits a body around the first JSON string literal whose text starts `{"capture":` (the user content): the bytes
    /// before its opening quote, the literal itself, and the bytes after its closing quote.
    static func userContentFrame(_ body: [UInt8]) -> (prefix: [UInt8], literal: [UInt8], suffix: [UInt8])? {
        let marker = Array(#""{\"capture\":"#.utf8)
        guard body.count >= marker.count,
              let start = (0...(body.count - marker.count)).first(where: {
                  body[$0..<($0 + marker.count)].elementsEqual(marker)
              }) else { return nil }
        var position = start + 1
        while position < body.count {
            if body[position] == 0x5C { position += 2; continue }  // a backslash escapes the next byte
            if body[position] == 0x22 { break }                      // the closing quote
            position += 1
        }
        guard position < body.count else { return nil }
        return (Array(body[..<start]), Array(body[start...position]), Array(body[(position + 1)...]))
    }

    /// The expected leaves of the user content (brief AC-M2-20 (b)): the capture, the room names in order, the titles
    /// with indices 1…n, and an empty list where there is none.
    static func expectedUserContentLeaves(_ expected: CloudPayloadInput) -> [String: EvalJSON] {
        var leaves: [String: EvalJSON] = ["$.capture": .string(expected.capture)]
        if expected.roomNames.isEmpty { leaves["$.rooms"] = .array([]) }
        for (offset, name) in expected.roomNames.enumerated() { leaves["$.rooms[\(offset)]"] = .string(name) }
        if expected.shortlistTitles.isEmpty { leaves["$.existingTasks"] = .array([]) }
        for (offset, title) in expected.shortlistTitles.enumerated() {
            leaves["$.existingTasks[\(offset)].index"] = .integer(offset + 1)
            leaves["$.existingTasks[\(offset)].title"] = .string(title)
        }
        return leaves
    }

    /// AC-M2-20 (b) for one captured request: every problem found (empty = pass).
    static func problems(_ request: CloudRequest, expected: CloudPayloadInput, reference: Reference) -> [String] {
        var problems: [String] = []
        // Request line and headers against the golden head and the allowed list.
        var line = request.method + " " + request.host + " " + request.path
        if !request.queryItems.isEmpty {
            line += "?" + request.queryItems.map { $0.name + "=" + $0.value }.joined(separator: "&")
        }
        if line != reference.headLines.first { problems.append("request line \(line)") }
        if request.headerNames != reference.allowedHeaderNames {
            problems.append("header names \(request.headerNames) ≠ allowed list \(reference.allowedHeaderNames)")
        }
        let goldenHeaders = reference.headLines.dropFirst().map { line -> (String, String) in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? String(parts[1].dropFirst()) : "")
        }
        if request.headerNames != goldenHeaders.map(\.0) { problems.append("header names differ from the golden") }
        // Every header value equals G1's, the auth value too: this harness always uses `PayloadFixture.fakeKey`, and
        // G1's head holds exactly prefix + that key (review R31-F1). So (b) pins every byte of the request.
        for (header, golden) in zip(request.headers, goldenHeaders) where header.withValue({ $0 }) != golden.1 {
            problems.append(header.name == reference.authHeaderName
                            ? "the auth header value differs from G1's fake-key value"
                            : "header \(header.name) value differs")
        }
        if !(request.headers.first { $0.name == reference.authHeaderName }?.isAuthorization ?? false) {
            problems.append("the auth header does not hold the key")
        }
        // The key-path set (the one key-path function, D3) equals the provider's allowed list.
        guard let paths = CloudRequestKeyPaths.leafPaths(ofBody: request.body),
              let body = try? EvalJSONReader.parse(request.body) else {
            return problems + ["the body is not strict JSON"]
        }
        if paths != reference.allowedPaths {
            problems.append("key paths ≠ allowed list: extra \(Set(paths).subtracting(reference.allowedPaths).sorted()), "
                            + "missing \(Set(reference.allowedPaths).subtracting(paths).sorted())")
        }
        // Concrete indices (R28-F6): exactly the golden's leaves, with the golden's value at every fixed one.
        var leaves = concreteLeaves(body)
        guard let userContentValue = leaves.removeValue(forKey: reference.userContentAt),
              case let .string(userContent) = userContentValue else {
            return problems + ["no user-content string at \(reference.userContentAt)"]
        }
        let extra = Set(leaves.keys).subtracting(reference.fixedLeaves.keys).sorted()
        let missing = Set(reference.fixedLeaves.keys).subtracting(leaves.keys).sorted()
        if !extra.isEmpty || !missing.isEmpty { problems.append("concrete paths: extra \(extra), missing \(missing)") }
        for (path, value) in leaves {
            if let golden = reference.fixedLeaves[path], !EvalJSON.jsonEqual(golden, value) {
                problems.append("fixed value at \(path) differs")
            }
        }
        // Byte level: every byte outside the user-content string equals the golden body's.
        if let frame = userContentFrame(Array(request.body)) {
            if frame.prefix != reference.framePrefix { problems.append("body bytes before the user content differ") }
            if frame.suffix != reference.frameSuffix { problems.append("body bytes after the user content differ") }
            if (try? EvalJSONReader.parse(Data(frame.literal))) != .string(userContent) {
                problems.append("the framed literal is not the user content")
            }
        } else {
            problems.append("no user-content frame")
        }
        // The user content: exactly the expected slots, at concrete indices, in the committed layout.
        guard let slots = try? EvalJSONReader.parse(Data(userContent.utf8)) else {
            return problems + ["the user content is not strict JSON"]
        }
        let slotLeaves = concreteLeaves(slots)
        let expectedLeaves = expectedUserContentLeaves(expected)
        if Set(slotLeaves.keys) != Set(expectedLeaves.keys) {
            problems.append("user-content paths: extra \(Set(slotLeaves.keys).subtracting(expectedLeaves.keys).sorted()), "
                            + "missing \(Set(expectedLeaves.keys).subtracting(slotLeaves.keys).sorted())")
        }
        for (path, value) in expectedLeaves where !(slotLeaves[path].map { EvalJSON.jsonEqual($0, value) } ?? false) {
            problems.append("user content at \(path) ≠ the expected value")
        }
        let layoutPaths = Set(CloudRequestKeyPaths.leafPaths(of: slots))
        if !layoutPaths.isSubset(of: reference.userContentLayout) {
            problems.append("user-content paths outside the layout: \(layoutPaths.subtracting(reference.userContentLayout).sorted())")
        }
        return problems
    }

    // MARK: Tampering (negative tests only)

    /// `value` with `change` applied at `path` (an empty path changes the root).
    static func modify(_ value: EvalJSON, at path: [JSONStep], _ change: (EvalJSON) -> EvalJSON) -> EvalJSON {
        guard let step = path.first else { return change(value) }
        let rest = Array(path.dropFirst())
        switch (step, value) {
        case let (.key(key), .object(members)):
            return .object(members.map { $0.key == key ? EvalJSON.Member($0.key, modify($0.value, at: rest, change)) : $0 })
        case let (.index(index), .array(elements)):
            var copy = elements
            if copy.indices.contains(index) { copy[index] = modify(copy[index], at: rest, change) }
            return .array(copy)
        default:
            return value
        }
    }

    /// A copy of `request` with a new body, path or headers.
    static func replacing(_ request: CloudRequest, body: Data? = nil, path: String? = nil,
                          queryItems: [CloudQueryItem]? = nil, headers: [CloudRequestHeader]? = nil) -> CloudRequest {
        CloudRequest(provider: request.provider, model: request.model, method: request.method, host: request.host,
                     path: path ?? request.path, queryItems: queryItems ?? request.queryItems,
                     headers: headers ?? request.headers, body: body ?? request.body)
    }
}

// MARK: - The router path (the path that really sends, review R28-F2)

/// One router per provider with cloud on, a test cloud model that builds the request from the pipeline's request with
/// the payload builder and sends it to the recording mock transport (the shape of WI-M2-M6's adapters).
struct PayloadRouterHarness {
    let provider: CloudProvider
    let router: ModelRouter
    let models: PayloadBuildingCloudModels

    static func make(_ provider: CloudProvider) async throws -> PayloadRouterHarness {
        let models = PayloadBuildingCloudModels()
        let router = ModelRouter(onDevice: FixedOnDevice(.unavailable(.deviceNotEligible)), cloudModels: models,
                                 consents: InMemoryCloudConsentStore(), keys: InMemoryAPIKeyStore())
        _ = try await router.turnCloudOn(provider, key: PayloadFixture.fakeKey)
        return PayloadRouterHarness(provider: provider, router: router, models: models)
    }

    /// Runs one capture through `ModelRouter.events(…)` to its end and returns the one request the transport captured,
    /// or nil when the capture did not send exactly one request.
    func send(_ item: SentinelCase, titleSharing: CloudTitleSharing) async -> CloudRequest? {
        await send(capture: item.capture, household: item.household, now: item.now, calendar: item.calendar,
                   timeZone: item.timeZone, titleSharing: titleSharing)
    }

    func send(capture: String, household: Household, now: Date, calendar: Calendar, timeZone: TimeZone,
              titleSharing: CloudTitleSharing) async -> CloudRequest? {
        let before = models.transport.requests.count
        let routed = await router.events(input: capture, household: household, now: now, calendar: calendar,
                                         timeZone: timeZone, titleSharing: titleSharing, preference: .onDeviceFirst)
        guard routed.route == .cloud(provider) else { return nil }
        for await _ in routed.events {}
        let requests = models.transport.requests
        return requests.count == before + 1 ? requests.last : nil
    }
}
