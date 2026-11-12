import Foundation

/// sin, cos and exp written with plain arithmetic so the web port reproduces the pendulum
/// bit for bit. A library `sin` can differ in the last bit, and a swinging piñata amplifies that.
public enum PinataMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
    static let invTwoPi = 1 / (2 * Double.pi)
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
}
