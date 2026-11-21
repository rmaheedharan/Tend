// AC-M2-02: ≥ 1,000 seeded random structured outputs (here 3 seeds × 2,000 = 6,000) are mapped. The pipeline never
// crashes and never emits an invalid task. Each item is repaired by exactly the Q5 rules, in the Q5 order, or skipped
// with a typed reason, and the result equals an independent oracle of Q5. Counts per repair rule are printed.
// FR-A1, D-016, UX-3. Plan WI-M2-05.
//
// Independence of the oracle (`Q5Oracle` below):
// - It reads the **raw** generated output (strings for every enum, `Double` for every number), not the snapshot the
//   production adapter step builds, so Q5 step 2 is computed twice, separately.
// - It re-implements every Q5 repair itself: title tidy (Character split/join), enum defaults, step 3 defaults,
//   critical + deep clean, the step 5 basis check, step 6 settlement and the R5 weekday drop (from the hint, not from
//   `weekdaysFollowRepeat`), the calm-words guard (Character.isLetter runs, Character.isPunctuation trim), the
//   `sourcePhrase` substring check (`String.contains`) and room linking (`String <` on `uuidString`).
// - It calls only two production functions, neither of them a Q5 repair: `TimeResolver.resolve` (the Q6 table, which
//   Q5 step 5 cites and which AC-M2-03 verifies against the plan's worked examples) and `TextFolding.foldName` (the
//   brief's name-folding primitive, pinned in `TextPrimitivesTests`). It never calls `DraftMapper`,
//   `RecurrenceSettlement`, `CalmWordsGuard`, `SourcePhrase`, `RoomLinker` or `BannedTokens`.
// - The generator's alphabet is ASCII letters, digits, punctuation, `é`, typographic quotes, tab, newline, CR LF and
//   NBSP. On it, Character.isLetter / isPunctuation / isWhitespace agree with the production scalar classes.

import Foundation
import Testing
import TendCore
@testable import TendIngestion

// MARK: - Raw model output (what an adapter receives) and the adapter step

struct RawHint: Sendable {
    var anchor: String?
    var daypart: String?
    var weekday: String?
    var month: Double?
    var season: String?
    var count: Double?
    var repeatEvery: Double?
    var repeatUnit: String?
}

struct RawItem: Sendable {
    var title: String?
    var kind: String?
    var room: String?
    var effort: String?
    var isCritical: Bool?
    var isDeepClean: Bool?
    var isWeatherDependent: Bool?
    var time: RawHint?
    var sourcePhrase: String?

    /// What an adapter does with a raw output: strings become `ModelChoice`, numbers go through `ModelNumber`.
    var snapshot: ItemSnapshot {
        ItemSnapshot(
            title: title,
            kind: kind.map(ModelChoice.init(raw:)),
            roomName: room,
            effort: effort.map(ModelChoice.init(raw:)),
            isCritical: isCritical,
            isDeepClean: isDeepClean,
            isWeatherDependent: isWeatherDependent,
            time: time.map { raw in
                TimeHintSnapshot(
                    anchor: raw.anchor.map(ModelChoice.init(raw:)),
                    daypart: raw.daypart.map(ModelChoice.init(raw:)),
                    weekday: raw.weekday.map(ModelChoice.init(raw:)),
                    month: raw.month.flatMap(ModelNumber.wholeNumber),
                    season: raw.season.map(ModelChoice.init(raw:)),
                    count: raw.count.flatMap(ModelNumber.wholeNumber),
                    repeatEvery: raw.repeatEvery.flatMap(ModelNumber.wholeNumber),
                    repeatUnit: raw.repeatUnit.map(ModelChoice.init(raw:))
                )
            },
            sourcePhrase: sourcePhrase
        )
    }
}

// MARK: - The oracle

/// The fields of a draft, compared field by field.
struct ExpectedDraft: Equatable, CustomStringConvertible {
    var title: String
    var kind: TaskKind
    var room: DraftRoom
    var effort: Effort
    var isCritical: Bool
    var isDeepClean: Bool
    var isWeatherDependent: Bool
    var dayparts: Set<Daypart>
    var weekdays: Set<Weekday>
    var start: Date
    var end: Date
    var interval: Int?
    var sourcePhrase: String?

    init(title: String, kind: TaskKind, room: DraftRoom, effort: Effort, isCritical: Bool, isDeepClean: Bool,
         isWeatherDependent: Bool, dayparts: Set<Daypart>, weekdays: Set<Weekday>, start: Date, end: Date,
         interval: Int?, sourcePhrase: String?) {
        self.title = title; self.kind = kind; self.room = room; self.effort = effort; self.isCritical = isCritical
        self.isDeepClean = isDeepClean; self.isWeatherDependent = isWeatherDependent; self.dayparts = dayparts
        self.weekdays = weekdays; self.start = start; self.end = end; self.interval = interval
        self.sourcePhrase = sourcePhrase
    }

    init(_ d: IngestionDraft) {
        self.init(title: d.title, kind: d.kind, room: d.room, effort: d.effort, isCritical: d.isCritical,
                  isDeepClean: d.isDeepClean, isWeatherDependent: d.isWeatherDependent, dayparts: d.allowedDayparts,
                  weekdays: d.allowedWeekdays, start: d.windowStart, end: d.windowEnd,
                  interval: d.recurrenceIntervalDays, sourcePhrase: d.sourcePhrase)
    }

    var description: String {
        "\(title)|\(kind)|\(room)|\(effort)|c\(isCritical) d\(isDeepClean) w\(isWeatherDependent)|"
            + "\(dayparts.map(\.rawValue).sorted())|\(weekdays.map(\.rawValue).sorted())|\(start)–\(end)|"
            + "\(interval.map(String.init) ?? "-")|\(sourcePhrase ?? "-")"
    }
}

enum OracleOutcome: Equatable {
    case draft(ExpectedDraft)
    case skipped(ItemSkipReason)
}

struct Q5Oracle {
    let input: String
    let rooms: [Room]
    let now: Date
    let resolver: TimeResolver

    static let banned: Set<String> = ["overdue", "late", "lateness", "missed", "failed", "behind", "penalty", "debt",
                                      "streak"]
    static let anchors = ["none", "today", "tonight", "tomorrow", "weekday", "thisWeekend", "thisWeek", "nextWeek",
                          "beforeMonth", "beforeSeason", "inDays", "inWeeks"]

    // Independent text helpers

    static func tidy(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Maximal letter runs and the text between them, in order.
    static func segments(_ text: String) -> [(text: String, isWord: Bool)] {
        var result: [(String, Bool)] = []
        for character in text {
            let isWord = character.isLetter
            if let last = result.last, last.1 == isWord {
                result[result.count - 1].0.append(character)
            } else {
                result.append((String(character), isWord))
            }
        }
        return result.map { (text: $0.0, isWord: $0.1) }
    }

    func saidBanned() -> Set<String> {
        Set(Self.segments(input).filter(\.isWord).map { TextFolding.foldName($0.text) }).intersection(Self.banned)
    }

    func calm(_ text: String) -> String {
        let said = saidBanned()
        var removed = false
        var kept = ""
        for segment in Self.segments(text) {
            if segment.isWord {
                let folded = TextFolding.foldName(segment.text)
                if Self.banned.contains(folded) && !said.contains(folded) {
                    removed = true
                    continue
                }
            }
            kept += segment.text
        }
        guard removed else { return text }
        var characters = Array(Self.tidy(kept))
        while let first = characters.first, first.isWhitespace || first.isPunctuation { characters.removeFirst() }
        while let last = characters.last, last.isWhitespace || last.isPunctuation { characters.removeLast() }
        return String(characters)
    }

    func checkedPhrase(_ phrase: String?) -> String? {
        guard let phrase else { return nil }
        let needle = TextFolding.foldName(phrase)
        guard !needle.isEmpty, TextFolding.foldName(input).contains(needle) else { return nil }
        return phrase
    }

    static func whole(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value.rounded(.towardZero) == value,
              value >= -9_223_372_036_854_775_808.0, value < 9_223_372_036_854_775_808.0 else { return nil }
        return Int(value)
    }

    func link(_ text: String?) -> (DraftRoom, defaulted: Bool) {
        guard let text else { return (.none, false) }
        let folded = TextFolding.foldName(text)
        if folded.isEmpty { return (.none, true) }
        let matches = rooms.filter { TextFolding.foldName($0.name) == folded }.sorted { $0.id.uuidString < $1.id.uuidString }
        if let first = matches.first { return (.existing(first.id), false) }
        return (.proposed(Self.tidy(text)), false)
    }

    func expect(_ raw: RawItem) -> (OracleOutcome, [ItemRepair]) {
        var repairs: [ItemRepair] = []
        // (1)
        guard let rawTitle = raw.title else { return (.skipped(.noTitle), []) }
        let title = Self.tidy(rawTitle)
        if title.isEmpty { return (.skipped(.noTitle), []) }
        if title != rawTitle { repairs.append(.titleTidied) }

        // (2)
        var kind = raw.kind.flatMap(TaskKind.init(rawValue:)) ?? .oneOff
        if raw.kind.flatMap(TaskKind.init(rawValue:)) == nil { repairs.append(.kindDefaulted) }
        let effort = raw.effort.flatMap(Effort.init(rawValue:)) ?? .normal
        if raw.effort.flatMap(Effort.init(rawValue:)) == nil { repairs.append(.effortDefaulted) }
        let linked = link(raw.room)
        var room = linked.0
        if linked.defaulted { repairs.append(.roomDefaulted) }

        var hint: TimeHint?
        if let h = raw.time {
            let anchor: TimeHint.Anchor
            if let a = h.anchor {
                if Self.anchors.contains(a), let known = TimeHint.Anchor(rawValue: a) {
                    anchor = known
                } else {
                    anchor = .unrecognized
                    repairs.append(.anchorUnrecognized)
                }
            } else {
                anchor = .none
                repairs.append(.anchorDefaulted)
            }
            let daypart = h.daypart.flatMap(Daypart.init(rawValue:))
            if h.daypart != nil && daypart == nil { repairs.append(.daypartDropped) }
            let weekday = h.weekday.flatMap(Weekday.init(rawValue:))
            if h.weekday != nil && weekday == nil { repairs.append(.weekdayDropped) }
            let season = h.season.flatMap(TimeHint.Season.init(rawValue:))
            if h.season != nil && season == nil { repairs.append(.seasonDropped) }
            let unit = h.repeatUnit.flatMap(TimeHint.RepeatUnit.init(rawValue:))
            if h.repeatUnit != nil && unit == nil { repairs.append(.repeatUnitDropped) }
            hint = TimeHint(anchor: anchor, daypart: daypart, weekday: weekday, month: Self.whole(h.month),
                            season: season, count: Self.whole(h.count), repeatEvery: Self.whole(h.repeatEvery),
                            repeatUnit: unit)
        }
        let isCritical = raw.isCritical ?? false
        var isDeepClean = raw.isDeepClean ?? false

        // (4)
        if isCritical && isDeepClean {
            isDeepClean = false
            repairs.append(.deepCleanCleared)
        }

        // (5): the Q6 function; the oracle checks the basis and the range itself.
        let resolution = resolver.resolve(hint, now: now)
        if resolution.basis != .hint { repairs.append(.windowDefaulted(resolution.basis)) }

        // (6)
        var interval = resolution.recurrenceIntervalDays
        var weekdays = resolution.allowedWeekdays
        if kind == .recurring {
            if let days = interval, days >= 1, days <= 730 {
                // kept
            } else {
                kind = .oneOff
                interval = nil
                repairs.append(.becameOneOff)
            }
        } else if interval != nil {
            interval = nil
            repairs.append(.intervalDropped)
        }
        let r5 = hint?.anchor == .weekday && resolution.basis == .hint && !weekdays.isEmpty
        if r5 && interval == nil {
            weekdays = []
            repairs.append(.repeatWeekdaysDropped)
        }

        // (3), after (5) and (6) (plan: the resolver returns ∅; WI-M2-05 fills the defaults)
        var dayparts = resolution.allowedDayparts
        if dayparts.isEmpty {
            dayparts = [.morning, .afternoon, .evening]
            repairs.append(.daypartsDefaulted)
        }
        if weekdays.isEmpty {
            weekdays = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            repairs.append(.weekdaysDefaulted)
        }

        // (7)
        var finalTitle = calm(title)
        if Self.tidy(finalTitle).isEmpty {
            let fallback = checkedPhrase(raw.sourcePhrase).map { calm(Self.tidy($0)) } ?? ""
            if Self.tidy(fallback).isEmpty { return (.skipped(.calmWords(.noTitleWordsLeft)), repairs) }
            finalTitle = fallback
            repairs.append(.titleFromSourcePhrase)
        } else if finalTitle != title {
            repairs.append(.titleCalmed)
        }
        if case let .proposed(name) = room {
            let calmed = calm(name)
            if Self.tidy(calmed).isEmpty {
                room = .none
                repairs.append(.roomNameCleared)
            } else if calmed != name {
                room = .proposed(calmed)
                repairs.append(.roomNameCalmed)
            }
        }

        // (8)
        let phrase = checkedPhrase(raw.sourcePhrase)
        if raw.sourcePhrase != nil && phrase == nil { repairs.append(.sourcePhraseDropped) }

        // (9): the oracle's claim is that every item that gets here is valid.
        return (.draft(ExpectedDraft(
            title: finalTitle, kind: kind, room: room, effort: effort, isCritical: isCritical,
            isDeepClean: isDeepClean, isWeatherDependent: raw.isWeatherDependent ?? false, dayparts: dayparts,
            weekdays: weekdays, start: resolution.windowStart, end: resolution.windowEnd, interval: interval,
            sourcePhrase: phrase)), repairs)
    }
}

// MARK: - The generator

struct OutputGenerator {
    var g: SplitMix64

    mutating func chance(_ percent: UInt64) -> Bool { g.next() % 100 < percent }
    mutating func pick<T>(_ values: [T]) -> T { values[Int(g.next() % UInt64(values.count))] }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(g.next() % UInt64(range.count)) }

    static let words = ["clean", "the", "oven", "late", "Overdue", "pods", "BEHIND", "balcony", "laté", "missed,",
                        "(debt)", "streak2", "bill", "—", "!", "penalty:", "fee", "lateness", "failed.", "kitchen",
                        "Sam’s", "room", "car", "wash", "buy", "dishwasher", "café", "“quote”", "it's", "3",
                        "bathroom", "garage", "shed"]
    static let separators = [" ", " ", " ", "  ", "\t", "\n", "\r\n", "\u{00A0}"]

    mutating func phrase(_ count: Int) -> String {
        (0..<count).map { _ in pick(Self.words) }.reduce("") { text, word in
            text.isEmpty ? word : text + pick(Self.separators) + word
        }
    }

    mutating func padded(_ text: String) -> String {
        (chance(20) ? pick(Self.separators) : "") + text + (chance(20) ? pick(Self.separators) : "")
    }

    mutating func choice(_ known: [String], unknown: [String]) -> String? {
        let roll = g.next() % 100
        if roll < 12 { return nil }
        if roll < 27 { return pick(unknown) }
        return pick(known)
    }

    mutating func number(valid: ClosedRange<Int>, odd: [Double]) -> Double? {
        let roll = g.next() % 100
        if roll < 20 { return nil }
        if roll < 40 { return pick(odd) }
        return Double(int(valid))
    }

    /// Edge hints that random draws rarely reach: windows just past the 366-day range (Q5 step 5) and R5 weekday
    /// repeats whose interval step 6 drops (PO Q-T1).
    static let edgeHints: [RawHint] = [
        RawHint(anchor: "inDays", daypart: "night", count: 366),
        RawHint(anchor: "inDays", daypart: "evening", count: 366),
        RawHint(anchor: "inWeeks", daypart: "night", count: 52),
        RawHint(anchor: "inDays", count: 366),
        RawHint(anchor: "weekday", weekday: "thursday", repeatEvery: 30, repeatUnit: "month"),
        RawHint(anchor: "weekday", weekday: "saturday", repeatEvery: 1, repeatUnit: "week"),
        RawHint(anchor: "weekday", weekday: "monday", repeatEvery: 3, repeatUnit: "year"),
        RawHint(anchor: "weekday", weekday: "friday", repeatEvery: 1, repeatUnit: "day"),
    ]

    mutating func hint() -> RawHint {
        if chance(15) { return pick(Self.edgeHints) }
        let anchor: String? = {
            let roll = g.next() % 100
            if roll < 8 { return nil }
            if roll < 18 { return pick(["someday", "unrecognized", "Tomorrow", "", "next_week"]) }
            return pick(Q5Oracle.anchors)
        }()
        let odd: [Double] = [.nan, .infinity, -.infinity, 2.5, -1, 0, 1e30, 9.3e18, 3e17, 400, 13, 800]
        return RawHint(
            anchor: anchor,
            daypart: chance(55) ? choice(Daypart.allCases.map(\.rawValue), unknown: ["brunch", "Morning", "noon"]) : nil,
            weekday: chance(50) ? choice(Weekday.allCases.map(\.rawValue), unknown: ["thurs", "Monday", "funday"]) : nil,
            month: chance(40) ? number(valid: 1...12, odd: odd) : nil,
            season: chance(35) ? choice(TimeHint.Season.allCases.map(\.rawValue), unknown: ["monsoon", "fall"]) : nil,
            count: chance(45) ? number(valid: 1...400, odd: odd) : nil,
            repeatEvery: chance(55) ? number(valid: 1...30, odd: odd + [731, 26]) : nil,
            repeatUnit: chance(55) ? choice(TimeHint.RepeatUnit.allCases.map(\.rawValue),
                                            unknown: ["fortnight", "Week", "hours"]) : nil
        )
    }

    mutating func item(input: String) -> RawItem {
        let title: String? = {
            let roll = g.next() % 100
            if roll < 5 { return nil }
            if roll < 10 { return pick(["", " ", "\n\t", "\u{00A0} "]) }
            return padded(phrase(int(1...5)))
        }()
        let room: String? = {
            let roll = g.next() % 100
            if roll < 30 { return nil }
            if roll < 35 { return pick(["", "  ", "\n"]) }
            if roll < 60 { return pick(["the kitchen", "KITCHEN", "Sam's room", "Sam’s Room", "my bathroom",
                                        "late-night den", "Garage"]) }
            if roll < 70 { return pick(["late", "Overdue!", "behind"]) }
            return padded(pick(["Driveway", "late kitchen", "Behind the shed", "garden", "Penalty box",
                                "the  attic", "café"]))
        }()
        let inputWords = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let sourcePhrase: String? = {
            let roll = g.next() % 100
            if roll < 25 || inputWords.isEmpty { return roll < 60 ? nil : phrase(int(1...3)) }
            if roll < 65 {
                let start = int(0...(inputWords.count - 1))
                let length = int(1...min(4, inputWords.count - start))
                let words = inputWords[start..<(start + length)].joined(separator: " ")
                return chance(30) ? words.uppercased() : words
            }
            if roll < 70 { return pick(["", "  "]) }
            return phrase(int(1...3))
        }()
        return RawItem(
            title: title,
            kind: choice(TaskKind.allCases.map(\.rawValue), unknown: ["chore", "OneOff", "", "recurrent"]),
            room: room,
            effort: choice(Effort.allCases.map(\.rawValue), unknown: ["huge", "Low", "medium"]),
            isCritical: chance(15) ? nil : chance(30),
            isDeepClean: chance(15) ? nil : chance(35),
            isWeatherDependent: chance(15) ? nil : chance(25),
            time: chance(80) ? hint() : nil,
            sourcePhrase: sourcePhrase
        )
    }
}

// MARK: - The property

@Suite("AC-M2-02 property: seeded random outputs against an independent Q5 oracle (FR-A1, D-016)")
struct DraftMappingPropertyTests {
    typealias F = MappingFixtures

    static let zones = ["America/New_York", "Europe/London", "America/Santiago", "Asia/Kolkata", "Pacific/Chatham",
                        "UTC"]
    static let rooms = [
        Room(id: F.id("00000000000A"), name: "Kitchen"),
        Room(id: F.id("000000000009"), name: "the kitchen"),   // folds equal to "Kitchen", lower uuidString
        Room(id: F.id("00000000000B"), name: "Bathroom"),
        Room(id: F.id("00000000000C"), name: "Sam’s room"),
        Room(id: F.id("00000000000D"), name: "Late-night den"),
        Room(id: F.id("00000000000E"), name: "Garage"),
    ]
    static let seeds: [UInt64] = [0x0A11_C0DE_5EED_0501, 0x0A11_C0DE_5EED_0502, 0x0A11_C0DE_5EED_0503]
    static let casesPerSeed = 2_000

    /// A name for counting: the case name, with the basis spelt out for window repairs.
    static func key(_ repair: ItemRepair) -> String {
        if case let .windowDefaulted(basis) = repair { return "(5) windowDefaulted(\(basis))" }
        return "(\(repair.step)) \(repair)"
    }

    @Test("AC-M2-02: 6,000 seeded outputs map without a crash or an invalid task; each equals the Q5 oracle, repairs and order included; counts per repair rule are logged", arguments: seeds)
    func property(seed: UInt64) throws {
        var generator = OutputGenerator(g: SplitMix64(seed: seed))
        var repairCounts: [String: Int] = [:]
        var skipCounts: [String: Int] = [:]
        var drafts = 0
        var mismatches = 0
        let calendar = Calendar(identifier: .gregorian)
        let base = F.utc("2026-01-01T00:00:00Z")

        for index in 0..<Self.casesPerSeed {
            let zone = F.zone(generator.pick(Self.zones))
            var sameCalendar = calendar
            sameCalendar.firstWeekday = generator.int(1...7)
            let now = base.addingTimeInterval(Double(generator.int(0...(3 * 365 * 86_400)))
                                              + Double(generator.int(0...999)) / 1_000)
            let input = generator.phrase(generator.int(0...12))
            let raw = generator.item(input: input)
            let draftID = generator.int(1...50)

            let mapper = DraftMapper(input: input, rooms: Self.rooms, now: now, calendar: sameCalendar, timeZone: zone)
            let mapping = mapper.map(raw.snapshot, draftID: draftID)
            let oracle = Q5Oracle(input: input, rooms: Self.rooms, now: now,
                                  resolver: TimeResolver(calendar: sameCalendar, timeZone: zone))
            let (expectedOutcome, expectedRepairs) = oracle.expect(raw)
            let label = "seed \(String(seed, radix: 16)) case \(index)"

            // Deterministic.
            #expect(mapper.map(raw.snapshot, draftID: draftID) == mapping, "\(label)")

            // Exactly the oracle's repairs, in the same order, and that order follows DraftMapper.stepOrder.
            #expect(mapping.repairs == expectedRepairs, "\(label): \(mapping.repairs) vs \(expectedRepairs)")
            let positions = mapping.repairs.compactMap { DraftMapper.stepOrder.firstIndex(of: $0.step) }
            #expect(positions.count == mapping.repairs.count && positions == positions.sorted(), "\(label)")

            for repair in mapping.repairs { repairCounts[Self.key(repair), default: 0] += 1 }

            switch (mapping.outcome, expectedOutcome) {
            case let (.draft(draft), .draft(expected)):
                drafts += 1
                if ExpectedDraft(draft) != expected { mismatches += 1 }
                #expect(ExpectedDraft(draft) == expected, "\(label)")
                #expect(draft.draftID == draftID && draft.duplicate == .none, "\(label)")
                // Never an invalid task: the M1 initialiser accepts every draft.
                let roomID: UUID? = if case let .existing(id) = draft.room { id } else { nil }
                #expect(throws: Never.self, "\(label)") {
                    _ = try draft.task(id: F.id("0000000000F0"), roomID: roomID)
                }
                // The Q5 step 5 range, checked here rather than trusted from the resolver.
                #expect(draft.windowStart >= now && draft.windowStart <= now.addingTimeInterval(366 * 86_400)
                        && draft.windowEnd > draft.windowStart
                        && draft.windowEnd <= draft.windowStart.addingTimeInterval(366 * 86_400), "\(label)")
                // UX-3: no banned token the user did not say.
                let said = oracle.saidBanned()
                let titleTokens = Set(Q5Oracle.segments(draft.title).filter(\.isWord)
                    .map { TextFolding.foldName($0.text) }).intersection(Q5Oracle.banned)
                #expect(titleTokens.isSubset(of: said), "\(label)")
                #expect(!draft.title.isEmpty, "\(label)")
            case let (.skipped(reason), .skipped(expected)):
                #expect(reason == expected, "\(label)")
                skipCounts["\(reason)", default: 0] += 1
            default:
                mismatches += 1
                Issue.record("\(label): outcome \(mapping.outcome) vs oracle \(expectedOutcome)")
            }
        }

        print("AC-M2-02 property: seed 0x\(String(seed, radix: 16, uppercase: true)), \(Self.casesPerSeed) outputs, "
              + "\(drafts) drafts, \(Self.casesPerSeed - drafts) skipped, \(mismatches) oracle mismatches")
        for (name, count) in skipCounts.sorted(by: { $0.key < $1.key }) {
            print("AC-M2-02 skip  \(name): \(count)")
        }
        for (name, count) in repairCounts.sorted(by: { $0.key < $1.key }) {
            print("AC-M2-02 repair \(name): \(count)")
        }

        // Coverage: every degenerate class of AC-M2-02 is exercised on every seed.
        #expect(Self.casesPerSeed >= 1_000)
        let required = ["(1) titleTidied", "(2) kindDefaulted", "(2) effortDefaulted", "(2) roomDefaulted",
                        "(2) anchorDefaulted", "(2) anchorUnrecognized", "(2) daypartDropped", "(2) weekdayDropped",
                        "(2) seasonDropped", "(2) repeatUnitDropped", "(3) daypartsDefaulted", "(3) weekdaysDefaulted",
                        "(4) deepCleanCleared", "(5) windowDefaulted(noHint)",
                        "(5) windowDefaulted(fallback(TendIngestion.TimeResolution.FallbackReason.unrecognizedAnchor))",
                        "(5) windowDefaulted(fallback(TendIngestion.TimeResolution.FallbackReason.requiredFieldAbsent))",
                        "(5) windowDefaulted(fallback(TendIngestion.TimeResolution.FallbackReason.fieldOutOfRange))",
                        "(5) windowDefaulted(fallback(TendIngestion.TimeResolution.FallbackReason.windowOutOfRange))",
                        "(6) becameOneOff", "(6) intervalDropped", "(6) repeatWeekdaysDropped", "(7) titleCalmed",
                        "(7) titleFromSourcePhrase", "(7) roomNameCalmed", "(7) roomNameCleared",
                        "(8) sourcePhraseDropped"]
        for name in required {
            #expect(repairCounts[name, default: 0] > 0, "seed \(seed): no case for \(name); keys \(repairCounts.keys)")
        }
        #expect(skipCounts["noTitle", default: 0] > 0)
        #expect(skipCounts["calmWords(TendIngestion.CalmWordsSkipReason.noTitleWordsLeft)", default: 0] > 0,
                "\(skipCounts)")
        #expect(skipCounts.keys.allSatisfy { !$0.hasPrefix("taskRejected") }, "the M1 initialiser rejected a task")
        #expect(drafts > Self.casesPerSeed / 2)
    }
}
