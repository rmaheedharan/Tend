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
    /// The model's in-input claim: the 1-based position of an earlier item of this output that this item repeats
    /// (skipped items count). Optional, and not a schema field for completion rule (a): a model may say nothing.
    /// The duplicate rules decide whether it is valid (WI-M2-07); the schemas map into it (WI-M2-M2, 10, 12).
    public var sameAsItem: Int?
    /// The model's existing-task claim (on device: a title the duplicate `Tool` returned; cloud with Q12 = yes: a
    /// shortlist index). Optional, and not a schema field for completion rule (a).
    public var sameAsExisting: ExistingTaskClaim?

    public init(
        title: String? = nil,
        kind: ModelChoice<TaskKind>? = nil,
        roomName: String? = nil,
        effort: ModelChoice<Effort>? = nil,
        isCritical: Bool? = nil,
        isDeepClean: Bool? = nil,
        isWeatherDependent: Bool? = nil,
        time: TimeHintSnapshot? = nil,
        sourcePhrase: String? = nil,
        sameAsItem: Int? = nil,
        sameAsExisting: ExistingTaskClaim? = nil
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
        self.sameAsItem = sameAsItem
        self.sameAsExisting = sameAsExisting
    }

    /// The two claims as the duplicate rules read them. Which claim counts on which path is the rules' business.
    public var duplicateClaim: DuplicateClaim {
        switch sameAsExisting {
        case let .lookupTitle(title)?: DuplicateClaim(sameAsItem: sameAsItem, sameAsTitle: title)
        case let .shortlistIndex(index)?: DuplicateClaim(sameAsItem: sameAsItem, sameAsShortlistIndex: index)
        case nil: DuplicateClaim(sameAsItem: sameAsItem)
        }
    }
}

/// The model's whole structured output so far: every item it has started, in output order. Each snapshot replaces the
/// previous one (as a `PartiallyGenerated` value does); the last item may still be in progress.
public struct IngestionSnapshot: Hashable, Sendable {
    public var items: [ItemSnapshot]
    /// On device: every query the duplicate-lookup `Tool` received so far in this parse, in call order (cumulative;
    /// each snapshot carries the whole list). Empty for cloud models, which have no Tool. The duplicate rules replay
    /// these queries on the parse's fixed household to resolve title claims (`DraftDuplicateRules`, review R22-R2-F2).
    public var lookupQueries: [String]

    public init(items: [ItemSnapshot], lookupQueries: [String] = []) {
        self.items = items
        self.lookupQueries = lookupQueries
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
///    A stream that is created inside an already cancelled task (a turn-off can land just before `snapshots(for:)` is
///    called) cancels its transport at once and sends nothing (review R24-F7; WI-M2-M6).
/// 4. On device, put every duplicate-`Tool` query of this parse into `IngestionSnapshot.lookupQueries` (cumulative, in
///    call order), and yield one more snapshot after a Tool call that no snapshot has carried yet, before finishing.
///    The Tool must read the same `Household` value that `DraftDuplicateRules.onDevice(household:)` was given, so that
///    replaying the queries gives exactly the entries the model saw. Cloud adapters leave `lookupQueries` empty.
public protocol IngestionModel: Sendable {
    func snapshots(for request: IngestionRequest) -> AsyncThrowingStream<IngestionSnapshot, any Error>
}
