// The structured-output reader: a cloud model's growing JSON text to neutral snapshots (plan WI-M2-12; AC-M2-24).
// FR-A1, P-3.
//
// The three provider dialects (WI-M2-13) take the output text pieces out of their events and append them here; after
// each piece the reader gives the latest `IngestionSnapshot`, which the cloud adapter yields to the draft stream
// (`IngestionModel`, the same contract as on device). The mapping, field by field (`StructuredOutputKey`):
// - root object → `items` array → one `ItemSnapshot` per element, in output order. A root that is not an object, or
//   `items` that is not an array, gives no items. An element that is not an object is an empty item, so the
//   positions that `sameAsItem` counts stay right. Unknown keys are ignored at every level.
// - `title`, `room` (→ `roomName`), `sourcePhrase`: strings. `kind`, `effort` and the hint's `anchor`, `daypart`,
//   `weekday`, `season`, `repeatUnit`: strings read with `ModelChoice(raw:)`, so an unknown value is `.unrecognized`
//   (it counts as a value for completion rule (a), brief T-03). The three flags: `true` / `false`. `time`: an object.
//   `month`, `count`, `repeatEvery`, `sameAsItem`: numbers read exactly with `ModelNumber.wholeNumber(jsonText:)`, so
//   a fraction, a huge number or an out-of-range exponent is nil. `sameAsExisting`: a number, read the same way, as
//   `.shortlistIndex(n)` (the cloud claim with Q12 = yes; the local re-check decides if it is valid, WI-M2-07).
// - `null`, a missing key and a wrong-typed value are all "missing" (nil). `lookupQueries` is always empty: a cloud
//   model has no duplicate `Tool` (AC-M2-24).
// - **Only finished values are shown.** A string, number or literal that is still being written is missing until it
//   ends. So a field never changes once it is in a snapshot (the time hint gains sub-fields, each finished, PO
//   WI-M2-06 ruling 2), completion rule (a) never fires on half a title, and no
//   draft is ever mapped from a prefix (PO WI-M2-06 ticket "title that arrives last"; dev-notes WI-M2-12, J2).
// Pure value type: no I/O, no clock, no logging.

import Foundation
import TendCore

/// The key names of the cloud output schema. WI-M2-10 writes the schema sent to the provider from these names.
public enum StructuredOutputKey {
    /// The root object's member that holds the items.
    public static let items = "items"

    /// The members of one item, in `ItemSnapshot` field order (`room` is `ItemSnapshot.roomName`).
    public enum Item: String, CaseIterable, Sendable {
        case title, kind, room, effort, isCritical, isDeepClean, isWeatherDependent, time, sourcePhrase, sameAsItem,
             sameAsExisting
    }

    /// The members of the time hint, in `TimeHintSnapshot` field order.
    public enum Time: String, CaseIterable, Sendable {
        case anchor, daypart, weekday, month, season, count, repeatEvery, repeatUnit
    }
}

/// Reads a growing structured-output text and gives the latest snapshot after each chunk; see the file header.
public struct StructuredOutputReader: Sendable {
    private var parser = PartialJSONParser()

    public init() {}

    /// Reads the next text piece and returns the snapshot so far.
    public mutating func append(_ text: String) throws(PartialJSONError) -> IngestionSnapshot {
        try append(bytes: text.utf8)
    }

    /// Reads the next byte chunk (it may end inside a UTF-8 sequence) and returns the snapshot so far.
    public mutating func append(bytes: some Sequence<UInt8>) throws(PartialJSONError) -> IngestionSnapshot {
        try parser.append(bytes)
        return Self.snapshot(of: parser.value)
    }

    /// Reads the next byte chunk without building a snapshot (`ProviderStreamReader` builds one per body chunk, not per
    /// event; review R29-N2).
    mutating func read(bytes: some Sequence<UInt8>) throws(PartialJSONError) {
        try parser.append(bytes)
    }

    /// The snapshot of the text read so far.
    var snapshot: IngestionSnapshot { Self.snapshot(of: parser.value) }

    /// Ends the text and returns the final snapshot; throws `cutShort` if the JSON is not finished.
    public mutating func finish() throws(PartialJSONError) -> IngestionSnapshot {
        Self.snapshot(of: try parser.finish())
    }

    /// Reads a whole text at once.
    public static func parse(_ text: String) throws(PartialJSONError) -> IngestionSnapshot {
        var reader = StructuredOutputReader()
        _ = try reader.append(text)
        return try reader.finish()
    }

    /// The snapshot for a value read so far (nil: nothing yet).
    public static func snapshot(of value: PartialJSONValue?) -> IngestionSnapshot {
        guard case .object? = value, case let .array(elements, _)? = value?[StructuredOutputKey.items] else {
            return IngestionSnapshot(items: [])
        }
        return IngestionSnapshot(items: elements.map(item))
    }

    private typealias Key = StructuredOutputKey.Item
    private typealias TimeKey = StructuredOutputKey.Time

    private static func item(_ value: PartialJSONValue) -> ItemSnapshot {
        guard case .object = value else { return ItemSnapshot() }
        var time: TimeHintSnapshot?
        if let hint = value[Key.time.rawValue], case .object = hint {
            time = TimeHintSnapshot(
                anchor: choice(hint[TimeKey.anchor.rawValue]), daypart: choice(hint[TimeKey.daypart.rawValue]),
                weekday: choice(hint[TimeKey.weekday.rawValue]), month: number(hint[TimeKey.month.rawValue]),
                season: choice(hint[TimeKey.season.rawValue]), count: number(hint[TimeKey.count.rawValue]),
                repeatEvery: number(hint[TimeKey.repeatEvery.rawValue]),
                repeatUnit: choice(hint[TimeKey.repeatUnit.rawValue])
            )
        }
        return ItemSnapshot(
            title: text(value[Key.title.rawValue]), kind: choice(value[Key.kind.rawValue]),
            roomName: text(value[Key.room.rawValue]), effort: choice(value[Key.effort.rawValue]),
            isCritical: flag(value[Key.isCritical.rawValue]), isDeepClean: flag(value[Key.isDeepClean.rawValue]),
            isWeatherDependent: flag(value[Key.isWeatherDependent.rawValue]), time: time,
            sourcePhrase: text(value[Key.sourcePhrase.rawValue]), sameAsItem: number(value[Key.sameAsItem.rawValue]),
            sameAsExisting: number(value[Key.sameAsExisting.rawValue]).map { .shortlistIndex($0) }
        )
    }

    /// A finished string; an open one is still missing.
    private static func text(_ value: PartialJSONValue?) -> String? {
        if case let .string(text, isComplete: true)? = value { return text }
        return nil
    }

    private static func choice<Value>(_ value: PartialJSONValue?) -> ModelChoice<Value>?
        where Value: RawRepresentable & Hashable & Sendable, Value.RawValue == String {
        text(value).map { ModelChoice(raw: $0) }
    }

    private static func flag(_ value: PartialJSONValue?) -> Bool? {
        if case let .bool(flag)? = value { return flag }
        return nil
    }

    private static func number(_ value: PartialJSONValue?) -> Int? {
        if case let .number(text)? = value { return ModelNumber.wholeNumber(jsonText: text) }
        return nil
    }
}
