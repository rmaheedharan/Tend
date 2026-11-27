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

/// The parse's lookups. **At most one call per capture is answered** (PO R-1 ruling, option (a)): the first call gets
/// exactly the shortlist and is recorded; every later call gets no entries and is not recorded, so the duplicate rules
/// replay exactly what the model was shown (D1). A repeat the model could only have found with a later call is still
/// marked by the word-match floor (WI-M2-07 ruling 1).
actor DuplicateLookupRecorder {
    /// The most Tool calls answered in one capture.
    static let answeredCallLimit = 1

    private var log: DuplicateLookupLog
    /// Calls after the limit (not answered, not recorded). Information for the probes and tests.
    private(set) var refusedCalls = 0

    init(household: Household) {
        log = DuplicateLookupLog(household: household)
    }

    /// One Tool call: exactly `DuplicateLookup.entries(for: query, in: household)`, recorded, while under the limit;
    /// otherwise nil.
    func lookUp(_ query: String) -> [DuplicateLookupEntry]? {
        guard log.queries.count < Self.answeredCallLimit else {
            refusedCalls += 1
            return nil
        }
        return log.lookUp(query)
    }

    /// Every query so far, in call order (`IngestionSnapshot.lookupQueries`).
    var queries: [String] { log.queries }

    /// The household the lookups read.
    var household: Household { log.household }
}

struct DuplicateLookupTool: Tool {
    let name = OnDeviceInstructions.toolName
    let description = "Finds tasks already on the person's list that match some words. Call it once, with the main "
        + "words of every chore together. Returns the title, kind and room of each."

    @Generable
    struct Arguments {
        @Guide(description: "The main words of every chore in the capture, such as dishwasher pods AC service.")
        var query: String
    }

    let recorder: DuplicateLookupRecorder

    func call(arguments: Arguments) async throws -> OnDeviceLookupResult {
        // A call after the first is answered with no entries (the one-call rule above).
        Self.result(await recorder.lookUp(arguments.query) ?? [])
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
