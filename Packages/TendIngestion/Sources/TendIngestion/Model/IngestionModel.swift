// The neutral model contract (brief Definitions "Modules": `IngestionModel` snapshots; plan WI-M2-05). FR-A1, P-1.
//
// Every model (the on-device `FoundationModels` adapter and the three cloud adapters in `TendAI`) produces the same
// neutral values: a stream of snapshots of its structured output so far. Nothing here knows which model ran. The Q5
// repairs (`DraftMapper`) turn a completed item snapshot into an `IngestionDraft`; stream assembly (WI-M2-06) decides
// when an item is complete and which events to emit.
//
// The snapshot keeps what the model actually said, before any repair: an unknown enum value is kept as
// `ModelChoice.unrecognized(text)` (it counts as a value for item completion, brief T-03 (a)), and a missing field is
// `nil`. Numbers are `Int?`: an adapter turns a JSON or model number into an `Int` with `ModelNumber.wholeNumber`, so a
// non-integer, non-finite or unrepresentable number is `nil` (plan "How the hint meets Q5", Numbers).

import Foundation
import TendCore

/// One value the model chose from a closed list: a known case, or the text it sent instead (Q5 step 2 repairs it).
public enum ModelChoice<Value>: Hashable, Sendable
where Value: RawRepresentable & Hashable & Sendable, Value.RawValue == String {
    case known(Value)
    case unrecognized(String)

    /// Exact raw-value match only (no case or whitespace folding): the schemas offer exactly these strings.
    public init(raw: String) {
        if let value = Value(rawValue: raw) {
            self = .known(value)
        } else {
            self = .unrecognized(raw)
        }
    }

    /// The known value, or nil.
    public var value: Value? {
        if case let .known(value) = self { return value }
        return nil
    }
}

/// Numbers from a model's output (plan "How the hint meets Q5", Numbers; WI-M2-12 uses this).
public enum ModelNumber {
    /// A finite whole number that fits in `Int`, as an `Int`; otherwise nil (fractional, NaN, ±∞, or too large).
    /// `Int(exactly:)` is nil for every one of those cases, so it is the whole rule.
    public static func wholeNumber(_ value: Double) -> Int? {
        Int(exactly: value)
    }
}

/// The model's structured time hint for one item, as sent (mirrors `TimeHint`, plan "The hint").
public struct TimeHintSnapshot: Hashable, Sendable {
    public var anchor: ModelChoice<TimeHint.Anchor>?
    public var daypart: ModelChoice<Daypart>?
    public var weekday: ModelChoice<Weekday>?
    public var month: Int?
    public var season: ModelChoice<TimeHint.Season>?
    public var count: Int?
    public var repeatEvery: Int?
    public var repeatUnit: ModelChoice<TimeHint.RepeatUnit>?

    public init(
        anchor: ModelChoice<TimeHint.Anchor>? = nil,
        daypart: ModelChoice<Daypart>? = nil,
        weekday: ModelChoice<Weekday>? = nil,
        month: Int? = nil,
        season: ModelChoice<TimeHint.Season>? = nil,
        count: Int? = nil,
        repeatEvery: Int? = nil,
        repeatUnit: ModelChoice<TimeHint.RepeatUnit>? = nil
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

/// One item of the model's output so far (brief Definitions "Item completion"). Every field may be missing.
/// The model never sends dates; the time fields of a draft come from `time` through the Q6 resolver.
public struct ItemSnapshot: Hashable, Sendable {
    public var title: String?
    public var kind: ModelChoice<TaskKind>?
    /// The model's room text, linked to the household by name folding (AC-M2-04).
    public var roomName: String?
    public var effort: ModelChoice<Effort>?
    public var isCritical: Bool?
    public var isDeepClean: Bool?
    public var isWeatherDependent: Bool?
    public var time: TimeHintSnapshot?
    /// The user's own words for the item, as the model quotes them (kept only if found in the input, Q5 step 8).
    public var sourcePhrase: String?

    public init(
        title: String? = nil,
        kind: ModelChoice<TaskKind>? = nil,
        roomName: String? = nil,
        effort: ModelChoice<Effort>? = nil,
        isCritical: Bool? = nil,
        isDeepClean: Bool? = nil,
        isWeatherDependent: Bool? = nil,
        time: TimeHintSnapshot? = nil,
        sourcePhrase: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.roomName = roomName
        self.effort = effort
        self.isCritical = isCritical
        self.isDeepClean = isDeepClean
        self.isWeatherDependent = isWeatherDependent
        self.time = time
        self.sourcePhrase = sourcePhrase
    }
}

/// The model's whole structured output so far: every item it has started, in output order. Each snapshot replaces the
/// previous one (as a `PartiallyGenerated` value does); the last item may still be in progress.
public struct IngestionSnapshot: Hashable, Sendable {
    public var items: [ItemSnapshot]

    public init(items: [ItemSnapshot]) {
        self.items = items
    }
}

/// What a model is asked to read: the one capture and the household's room names (ADR-0005 Decision 3 allows both).
public struct IngestionRequest: Hashable, Sendable {
    /// The finished text, or the final on-device transcript (brief Definitions "Brain-dump input").
    public var input: String
    /// The household's room names as the user wrote them (Q19).
    public var roomNames: [String]

    public init(input: String, roomNames: [String]) {
        self.input = input
        self.roomNames = roomNames
    }
}

/// A language model that reads one capture and streams snapshots of its structured output (FR-A1).
///
/// The stream ends normally when the model finishes, or throws when it fails or is cut off. Stream assembly
/// (`DraftPipeline`, WI-M2-06) turns this into the draft stream events, which never throw. Availability is not part of
/// this protocol: routing gives a `RoutedModel`, and `RoutedModel.none` carries the `OnDeviceUnavailableReason`.
///
/// **Adapter contract** (WI-M2-M2 on-device, WI-M2-M4 cloud; tested on the owner-run Mac):
/// 1. End the stream by finishing normally, or by throwing a `ModelStopReason`. Any other error is read as
///    `otherModelError`.
/// 2. Do not keep a reference to the returned `AsyncThrowingStream`. The pipeline releases its iterator when the
///    consumer cancels; a reference kept by the adapter would stop the termination handler from running.
/// 3. Cancel all model and network work in the stream's `onTermination` (the `streamResponse` loop, the URL session
///    bytes task), so nothing keeps running after the user cancels or turns cloud off (P-3, WI-M2-09).
public protocol IngestionModel: Sendable {
    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error>
}
