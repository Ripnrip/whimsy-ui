import Foundation

/// sin, cos, atan and angle wrap written with plain arithmetic so `webports/koipond-core.mjs`
/// matches this core at eight decimals. A library `sin` or `atan2` can differ in the last bit.
public enum KoiPondMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
    static let invTwoPi = 1 / (2 * Double.pi)

    /// sin(x): reduced to [-π/2, π/2], then a Taylor polynomial to x¹⁷.
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = pi - r } else if r < -halfPi { r = -pi - r }
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

    /// atan for every finite input. The series argument is reduced below tan(π/12).
    public static func atan(_ x: Double) -> Double {
        guard x.isFinite else {
            if x > 0 { return halfPi }
            if x < 0 { return -halfPi }
            return 0
        }
        let negative = x < 0
        var a = negative ? -x : x
        var complement = false
        if a > 1 {
            a = 1 / a
            complement = true
        }
        // √3 / 3. Shared as a literal with the web port.
        let tanSixth = 0.5773502691896257
        let sixth = pi / 6
        let base: Double
        if a > tanSixth {
            let t = (a - tanSixth) / (1 + a * tanSixth)
            base = sixth + atanSeries(t)
        } else {
            base = atanSeries(a)
        }
        let angle = complement ? halfPi - base : base
        return negative ? -angle : angle
    }

    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if !y.isFinite || !x.isFinite { return 0 }
        if x > 0 { return atan(y / x) }
        if x < 0 { return y >= 0 ? atan(y / x) + pi : atan(y / x) - pi }
        if y > 0 { return halfPi }
        if y < 0 { return -halfPi }
        return 0
    }

    /// Wraps to [-π, π).
    public static func wrap(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let k = ((angle + pi) * invTwoPi).rounded(.down)
        return angle - k * twoPi
    }

    /// Turns `heading` toward `desired` by at most `rate * dt` radians.
    public static func turn(_ heading: Double, toward desired: Double, rate: Double, dt: Double) -> Double {
        guard heading.isFinite, desired.isFinite, rate.isFinite, dt.isFinite, dt > 0 else { return heading }
        var delta = wrap(desired - heading)
        let maxStep = max(rate, 0) * dt
        if delta > maxStep { delta = maxStep }
        if delta < -maxStep { delta = -maxStep }
        return wrap(heading + delta)
    }

    /// Odd Taylor polynomial for atan on a small argument, through z⁴¹.
    static func atanSeries(_ z: Double) -> Double {
        let z2 = z * z
        var n = 41.0
        var acc = 1.0 / n
        while n > 1 {
            n -= 2
            acc = 1.0 / n - z2 * acc
        }
        return z * acc
    }
}
