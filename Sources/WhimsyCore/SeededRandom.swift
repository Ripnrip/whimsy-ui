/// SplitMix64: tiny, fast, seedable and identical on every platform. Shared by the cores
/// that need reproducible randomness (crumb particles, saccades, blinks).
public struct SeededRandom: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double via the standard library (`Double.random(in:using:)`).
    public mutating func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    /// Uniform double built from the top 53 bits. Unlike `double(in:)` this formula is fixed,
    /// so it can be reproduced bit-for-bit in other languages (the web previews do).
    public mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
