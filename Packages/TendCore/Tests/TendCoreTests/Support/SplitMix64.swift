// A small, fast, seeded random number generator for property tests (WI-M1-02; reused by WI-M1-03 and WI-M1-04).
// Same seed, same sequence, on every platform: test failures print the seed so a case can be replayed exactly.

/// SplitMix64 (Steele, Lea, Flood 2014). Deterministic and platform-independent; not for cryptography.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private(set) var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `[0, 1)` with 53 random bits, used to give dates a sub-second part.
    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0  // 2^53
    }

    /// True with probability `p` (0...1).
    mutating func chance(_ p: Double) -> Bool {
        nextUnitInterval() < p
    }
}
