import Foundation

/// A small, fast, seedable random number generator (SplitMix64).
///
/// Used wherever LofiScoreKit needs randomness that tests can repeat exactly:
/// track rotation, synthetic replays, placeholder synthesis.
public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
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

    /// A uniformly distributed value in `0..<1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// A normally distributed value (Box-Muller).
    public mutating func nextGaussian(mean: Double = 0, deviation: Double = 1) -> Double {
        let u1 = max(nextUnit(), 1e-12)
        let u2 = nextUnit()
        let radius = (-2 * log(u1)).squareRoot()
        return mean + deviation * radius * cos(2 * .pi * u2)
    }
}
