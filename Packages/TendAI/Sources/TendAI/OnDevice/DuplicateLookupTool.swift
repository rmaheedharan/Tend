// The on-device duplicate-lookup `Tool` (WI-M2-M2; AC-M2-07: "The `Tool` returns exactly the duplicate shortlist for
// its query: at most 10 entries, only from the local household, and only title, kind and room name for each"; brief
// Definitions "Duplicate shortlist"). FR-A1, P-1, P-2.
//
// It wraps the neutral `DuplicateLookupLog` (WI-M2-07). The log reads only the `Household` value it was made with,
// which is the value the capture's `DraftDuplicateRules.onDevice(household:)` was given (adapter contract item 4), and
// never changes it (Q7). The log lives in an actor, so the Tool is `Sendable` with no lock. A cloud model is never
// given this Tool (AC-M2-24): only `OnDeviceIngestionModel` builds it.

import Foundation
import FoundationModels
import TendCore
import TendIngestion

/// What the Tool returns to the model: the shortlist entries in rank order.
@Generable
struct OnDeviceLookupResult: Equatable {
    var tasks: [OnDeviceLookupTask]
}

/// One shortlist entry: title, kind and room name, and nothing else (no ID, state or date).
@Generable
struct OnDeviceLookupTask: Equatable {
    var title: String
    var kind: OnDeviceKind
    /// Absent when the task has no room.
    var room: String?
}

/// The parse's lookups, in call order (one per Tool call).
actor DuplicateLookupRecorder {
    private var log: DuplicateLookupLog

    init(household: Household) {
        log = DuplicateLookupLog(household: household)
    }

    /// One Tool call: exactly `DuplicateLookup.entries(for: query, in: household)`, recorded.
    func lookUp(_ query: String) -> [DuplicateLookupEntry] {
        log.lookUp(query)
    }

    /// Every query so far, in call order (`IngestionSnapshot.lookupQueries`).
    var queries: [String] { log.queries }

    /// The household the lookups read.
    var household: Household { log.household }
}

struct DuplicateLookupTool: Tool {
    let name = OnDeviceInstructions.toolName
    let description = "Finds tasks already on the person's list that match a few words. Returns the title, kind and "
        + "room of each."

    @Generable
    struct Arguments {
        @Guide(description: "The chore's main words, such as dishwasher pods.")
        var query: String
    }

    let recorder: DuplicateLookupRecorder

    func call(arguments: Arguments) async throws -> OnDeviceLookupResult {
        Self.result(await recorder.lookUp(arguments.query))
    }

    /// The model-facing form of the entries, field for field.
    static func result(_ entries: [DuplicateLookupEntry]) -> OnDeviceLookupResult {
        OnDeviceLookupResult(tasks: entries.map { entry in
            OnDeviceLookupTask(title: entry.title, kind: kind(entry.kind), room: entry.roomName)
        })
    }

    static func kind(_ kind: TaskKind) -> OnDeviceKind {
        switch kind {
        case .oneOff: .oneOff
        case .recurring: .recurring
        case .restock: .restock
        }
    }
}
