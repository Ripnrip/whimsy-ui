import Foundation

/// Hashing and the few transcendental functions the simulation needs, written with plain arithmetic
/// so the web port (and any other platform) reproduces the simulation bit for bit.
/// The star simulation is chaotic: one last-bit difference in a library `sin` would grow into a different jar.
public enum StarJarMath {
    /// lowbias32 integer hash.
    public static func hash32(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x &*= 0x7feb_352d
        x ^= x >> 15; x &*= 0x846c_a68b
        x ^= x >> 16
        return x
    }
    public static func value(_ seed: UInt32, _ salt: Int) -> UInt32 {
        hash32((UInt32(truncatingIfNeeded: salt) &* 0x9E37_79B1) ^ hash32(seed))
    }
    /// 0 ..< 1 from 24 bits of the hash.
    public static func unit(_ seed: UInt32, _ salt: Int) -> Double { Double(value(seed, salt) & 0xFF_FFFF) / 16_777_216 }

    static let twoPi = 2 * Double.pi
    static let invTwoPi = 1 / (2 * Double.pi)
    static let halfPi = Double.pi / 2
    static let ln2 = 0.6931471805599453
    static let invLn2 = 1 / 0.6931471805599453

    /// sin(x): reduced to [-π/2, π/2], then a Taylor polynomial to x¹⁷ (error under 1e-13).
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = Double.pi - r } else if r < -halfPi { r = -Double.pi - r }
        let r2 = r * r
        var p = 1.0 / 355_687_428_096_000.0
        p = -1.0 / 1_307_674_368_000.0 + r2 * p
        p = 1.0 / 6_227_020_800.0 + r2 * p
        p = -1.0 / 39_916_800.0 + r2 * p
        p = 1.0 / 362_880.0 + r2 * p
        p = -1.0 / 5040.0 + r2 * p
        p = 1.0 / 120.0 + r2 * p
        p = -1.0 / 6.0 + r2 * p
        p = 1.0 + r2 * p
        return r * p
    }
    public static func cos(_ x: Double) -> Double { sin(x + halfPi) }

    /// eˣ for x clamped to ±60: x = k·ln2 + r, a Taylor polynomial in r, times 2ᵏ by exact doubling.
    public static func exp(_ x: Double) -> Double {
        guard !x.isNaN else { return 0 }
        let xc = min(max(x, -60), 60)
        let k = (xc * invLn2 + 0.5).rounded(.down)
        let r = xc - k * ln2
        var p = 1.0 / 6_227_020_800.0
        p = 1.0 / 479_001_600.0 + r * p
        p = 1.0 / 39_916_800.0 + r * p
        p = 1.0 / 3_628_800.0 + r * p
        p = 1.0 / 362_880.0 + r * p
        p = 1.0 / 40320.0 + r * p
        p = 1.0 / 5040.0 + r * p
        p = 1.0 / 720.0 + r * p
        p = 1.0 / 120.0 + r * p
        p = 1.0 / 24.0 + r * p
        p = 1.0 / 6.0 + r * p
        p = 0.5 + r * p
        p = 1.0 + r * p
        p = 1.0 + r * p
        var n = Int(k)
        while n > 0 { p *= 2; n -= 1 }
        while n < 0 { p /= 2; n += 1 }
        return p
    }

    public static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    public static func easeOutCubic(_ t: Double) -> Double { let u = 1 - clamp01(t); return 1 - u * u * u }
    public static func easeInOutCubic(_ t: Double) -> Double {
        let t = clamp01(t)
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - u * u * u / 2
    }
}
