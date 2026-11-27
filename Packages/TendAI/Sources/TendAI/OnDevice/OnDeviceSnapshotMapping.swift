// `PartiallyGenerated` snapshots of the on-device output to neutral `IngestionSnapshot`s (WI-M2-M2; AC-M2-05; brief
// Definitions "Item completion" (a); PO WI-M2-12 ruling 1). FR-A1, P-1, UX-3.
//
// **Only finished values (J2).** A `PartiallyGenerated` value shows a string, and a number, while the model is still
// writing it ("Buy di", or the "1" of "12"). A field has a value only once the model has finished writing it, so a
// snapshot never shows part of one: otherwise a late title would be skipped for good at its blank first step, and the
// prefix "Late" of "Later" would meet the calm-words guard (brief AC-M2-05). The properties are generated in
// declaration order (`OnDeviceItem`), so a property is finished when:
// - a later property of the same item has started (it is non-nil in the snapshot); or
// - the item is not the last one in the snapshot (the model has started the next item, rule (b)); or
// - the stream finished normally (`isFinal`, rule (c)).
// The last property, `isWeatherDependent`, is a `Bool`, which a snapshot shows only once it is written, so it is
// finished as soon as it appears. Rule (a) can therefore fire only when every field is whole.
//
// Pure: no clock, no I/O. The unknown-value case of `ModelChoice` cannot occur (the model's output is constrained to
// the enums), but the mapping goes through `ModelChoice(raw:)` like the cloud reader.

import Foundation
import FoundationModels
import TendCore
import TendIngestion

enum OnDeviceSnapshotMapping {
    /// The neutral snapshot for one `PartiallyGenerated` value of the whole answer.
    /// - Parameters:
    ///   - isFinal: the stream finished normally after this value (every property is finished).
    ///   - lookupQueries: every duplicate-`Tool` query of this parse so far, in call order (adapter contract item 4).
    static func snapshot(_ output: OnDeviceOutput.PartiallyGenerated, isFinal: Bool,
                         lookupQueries: [String]) -> IngestionSnapshot {
        let partials = output.items ?? []
        let items = partials.indices.map { index in
            item(partials[index], isWhole: isFinal || index < partials.count - 1)
        }
        return IngestionSnapshot(items: items, lookupQueries: lookupQueries)
    }

    /// The properties of `OnDeviceItem` in declaration (generation) order, and whether each has started.
    enum Property: Int, CaseIterable, Comparable {
        case title, sourcePhrase, kind, room, effort, time, sameAsItem, sameAsExisting, isCritical, isDeepClean,
             isWeatherDependent

        static func < (lhs: Property, rhs: Property) -> Bool { lhs.rawValue < rhs.rawValue }

        func hasStarted(in item: OnDeviceItem.PartiallyGenerated) -> Bool {
            switch self {
            case .title: item.title != nil
            case .sourcePhrase: item.sourcePhrase != nil
            case .kind: item.kind != nil
            case .room: item.room != nil
            case .effort: item.effort != nil
            case .time: item.time != nil
            case .sameAsItem: item.sameAsItem != nil
            case .sameAsExisting: item.sameAsExisting != nil
            case .isCritical: item.isCritical != nil
            case .isDeepClean: item.isDeepClean != nil
            case .isWeatherDependent: item.isWeatherDependent != nil
            }
        }
    }

    /// One item, showing only finished properties. `isWhole`: every property is finished (rules (b) and (c)).
    static func item(_ partial: OnDeviceItem.PartiallyGenerated, isWhole: Bool) -> ItemSnapshot {
        // The last property that has started; every property before it is finished.
        let lastStarted = Property.allCases.last { $0.hasStarted(in: partial) }
        func finished(_ property: Property) -> Bool {
            if isWhole { return true }
            // A `Bool` is shown only once written, so the last property is finished as soon as it starts.
            if property == .isWeatherDependent { return partial.isWeatherDependent != nil }
            guard let lastStarted else { return false }
            return property < lastStarted
        }

        var snapshot = ItemSnapshot()
        if finished(.title) { snapshot.title = partial.title }
        if finished(.sourcePhrase) { snapshot.sourcePhrase = partial.sourcePhrase }
        if finished(.kind), let kind = partial.kind { snapshot.kind = ModelChoice(raw: kind.rawValue) }
        if finished(.room) { snapshot.roomName = partial.room }
        if finished(.effort), let effort = partial.effort { snapshot.effort = ModelChoice(raw: effort.rawValue) }
        if finished(.time), let time = partial.time { snapshot.time = timeHint(time) }
        if finished(.sameAsItem) { snapshot.sameAsItem = partial.sameAsItem }
        if finished(.sameAsExisting), let title = partial.sameAsExisting {
            snapshot.sameAsExisting = .lookupTitle(title)
        }
        if finished(.isCritical) { snapshot.isCritical = partial.isCritical }
        if finished(.isDeepClean) { snapshot.isDeepClean = partial.isDeepClean }
        if finished(.isWeatherDependent) { snapshot.isWeatherDependent = partial.isWeatherDependent }
        return snapshot
    }

    /// A finished time hint (its members are finished because a later item property has started, or the item is
    /// whole).
    static func timeHint(_ time: OnDeviceTimeHint.PartiallyGenerated) -> TimeHintSnapshot {
        TimeHintSnapshot(
            anchor: time.anchor.map { ModelChoice(raw: $0.rawValue) },
            daypart: time.daypart.map { ModelChoice(raw: $0.rawValue) },
            weekday: time.weekday.map { ModelChoice(raw: $0.rawValue) },
            month: time.month,
            season: time.season.map { ModelChoice(raw: $0.rawValue) },
            count: time.count,
            repeatEvery: time.repeatEvery,
            repeatUnit: time.repeatUnit.map { ModelChoice(raw: $0.rawValue) }
        )
    }
}
