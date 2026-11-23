// The eval harness's deterministic ID generator (AC-M2-28 "Its injected ID generator for committed tasks and rooms is
// deterministic (T-29) … and never yields a fixture UUID"; plan "Eval harness ID generator"). FR-A1, AC-M2-06.
//
// A plain value passed through the public commit API (`DraftCommit`, `CommitIDGenerator`), so it is not a hook into
// the pipeline (AC-M2-28 "no eval-only code paths or hooks"). For input number i (the 1-based position in
// `inputs.json`) and attempt a, the n-th ID (n = 1, 2, 3 …, restarting for every attempt) has these 16 bytes:
//
// | Bytes | Value                                        |
// |-------|----------------------------------------------|
// | 0–3   | 0x54 0x45 0x56 0x4C (ASCII "TEVL")           |
// | 4–5   | i, big-endian UInt16                         |
// | 6     | 0x80 | a (version 8, RFC 9562 custom UUID)   |
// | 7     | 0x00                                         |
// | 8     | 0x80 (RFC 9562 variant)                      |
// | 9–15  | n, big-endian 56-bit                         |
//
// Every fixture UUID is version 4 (byte 6 high nibble 4; checked by the WI-M2-16 composition check), so no generated
// ID can equal one. Commit still skips any ID in use (AC-M2-06).

import Foundation

public struct EvalIDGenerator: CommitIDGenerator, Sendable, Hashable {

    /// The plan's ranges: input number 1…65,535 (two bytes) and attempt 1…15 (the low nibble of byte 6).
    public static let inputNumbers: ClosedRange<Int> = 1...Int(UInt16.max)
    public static let attempts: ClosedRange<Int> = 1...15
    /// n fits in 7 bytes.
    public static let maximumCount: UInt64 = (1 << 56) - 1

    public let inputNumber: Int
    public let attempt: Int
    /// How many IDs have been returned so far.
    public private(set) var count: UInt64 = 0

    /// Nil when the input number or attempt is outside the plan's ranges.
    public init?(inputNumber: Int, attempt: Int) {
        guard Self.inputNumbers.contains(inputNumber), Self.attempts.contains(attempt) else { return nil }
        self.inputNumber = inputNumber
        self.attempt = attempt
    }

    /// The n-th ID of this input and attempt (n ≥ 1), without changing the generator.
    public func id(number n: UInt64) -> UUID {
        let i = UInt16(inputNumber)
        return UUID(uuid: (
            0x54, 0x45, 0x56, 0x4C,
            UInt8(i >> 8), UInt8(i & 0xFF),
            0x80 | UInt8(attempt), 0x00,
            0x80,
            UInt8((n >> 48) & 0xFF), UInt8((n >> 40) & 0xFF), UInt8((n >> 32) & 0xFF), UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)
        ))
    }

    /// The next ID: n = 1, 2, 3 …. After 2^56 − 1 IDs (never reached in an eval) it keeps returning the last one, which
    /// commit then skips as in use and reports as `idGeneratorExhausted` (no crash on a user path).
    public mutating func next() -> UUID {
        if count < Self.maximumCount { count += 1 }
        return id(number: count)
    }
}
