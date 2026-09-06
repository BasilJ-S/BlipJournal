/// SplitMix64. Deterministic for a given seed.
///
/// Used by tests, and by anything that wants a reproducible schedule. It is not
/// cryptographic and does not need to be: nothing here is secret, the only requirement
/// is that prompt times look unpredictable to the person receiving them and that the
/// same seed replays the same day.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
