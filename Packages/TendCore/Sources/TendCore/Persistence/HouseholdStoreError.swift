import Foundation

/// Why a household could not be read or stored (AC-M1-06, AC-M1-07, AC-M1-25; design.md naming list).
///
/// Codes only, for developers and for the M3 UI to map to calm copy (`store.error.*`, design.md). A failed load never
/// produces an empty household, and nothing here describes the person.
public enum HouseholdStoreError: Error, Hashable, Sendable {
    /// The file exists but is not a readable household: truncated, not JSON, the wrong shape, or not a file.
    case unreadableFile
    /// The file (or a household being saved) declares a schema version this build does not read.
    case unsupportedSchemaVersion(Int)
    /// A stored task breaks a model invariant; the first broken one is reported (AC-M1-25).
    case invalidTask(TaskInvariantViolation)
    /// The household could not be written. The previously stored household is unchanged (AC-M1-07).
    case writeUnsuccessful
}
