import Foundation

/// How much a task asks of a person (AC-M1-01, FR-B1). Matched against `EnergyLevel` by the selector (brief Q1).
public enum Effort: String, CaseIterable, Codable, Hashable, Sendable {
    case low
    case normal
    case high
}

/// How much energy the person has right now (FR-B1). An injected input to the selector; a state, never a judgement.
public enum EnergyLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case low
    case normal
    case high
}
