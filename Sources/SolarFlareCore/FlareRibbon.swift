import Foundation
import WhimsyCore

/// Step response of an underdamped spring from 0 to 1 (closed form, so it's exact at any frame rate).
/// `omega` is the natural frequency (rad/s) and `zeta` the damping ratio (0 < ζ < 1).
public func springResponse(_ t: Double, omega: Double, zeta: Double) -> Double {
    guard t > 0 else { return 0 }
    let z = min(max(zeta, 0.01), 0.99)
    let wd = omega * (1 - z * z).squareRoot()
    let envelope = exp(-z * omega * t)
    return 1 - envelope * (cos(wd * t) + z / (1 - z * z).squareRoot() * sin(wd * t))
}

/// One flare ribbon, in units of the heart's radius (the heart spans radius 1 around the origin).
public struct FlareRibbon: Equatable, Sendable {
    /// Direction the ribbon shoots (radians, y-down screen space).
    public var angle: Double
    /// Seconds after the tap before this ribbon launches.
    public var delay: Double
    /// Full length when extended (heart radii).
    public var length: Double
    /// Maximum half-width (heart radii).
    public var width: Double
    /// Extra rotation reached at the tip; the centreline bends by `swirl·u²`.
    public var swirl: Double
    /// Where the ribbon starts, just outside the heart.
    public var innerRadius: Double

    /// Tunables shared by every ribbon in a burst.
    public struct Motion: Equatable, Sendable {
        /// Head (tip) spring: fast with a little overshoot.
        public var omega = 22.0
        public var zeta = 0.55
        /// The tail follows the same curve this much later, so the ribbon detaches and shrinks away.
        public var tailLag = 0.16
        /// Total visible life after launch.
        public var lifetime = 0.62
        /// Opacity = (1 − age/lifetime)^fadePower.
        public var fadePower = 1.2
        public init() {}
    }

    /// Point on the centreline at distance `d` from the inner radius.
    public func centerline(_ d: Double) -> Vec2 {
        let u = length > 0 ? d / length : 0
        return Vec2.unit(angle + swirl * u * u) * (innerRadius + d)
    }

    /// Snapshot at `age` seconds after the tap (the delay is applied here).
    public func state(at age: Double, motion: Motion = Motion()) -> RibbonState? {
        let a = age - delay
        guard a >= 0, a < motion.lifetime else { return nil }
        let head = springResponse(a, omega: motion.omega, zeta: motion.zeta)
        let tail = springResponse(a - motion.tailLag, omega: motion.omega, zeta: motion.zeta)
        let opacity = pow(max(1 - a / motion.lifetime, 0), motion.fadePower)
        return RibbonState(tail: max(tail, 0) * length, head: max(head, 0) * length, opacity: opacity)
    }

    /// Closed outline (left edge out, right edge back) of the ribbon between `tail` and `head`,
    /// tapering to a point at both ends: thickest near the base, needle-sharp at the tip.
    public func outline(_ s: RibbonState, samples: Int = 18) -> [Vec2] {
        let n = max(samples, 2)
        let span = s.head - s.tail
        guard span > 1e-6 else { return [] }
        var left: [Vec2] = [], right: [Vec2] = []
        for i in 0...n {
            let u = Double(i) / Double(n)
            let d = s.tail + span * u
            let p = centerline(d)
            let ahead = centerline(min(d + 1e-3, s.tail + span + 1e-3))
            let behind = centerline(max(d - 1e-3, 0))
            let tangent = (ahead - behind).normalized
            let normal = Vec2(-tangent.y, tangent.x)
            let w = width * Self.taper(u) * min(span / (length * 0.35), 1)
            left.append(p + normal * w)
            right.append(p - normal * w)
        }
        return left + right.reversed()
    }

    /// 0 at both ends, peaking near the base (u ≈ 0.16).
    public static func taper(_ u: Double) -> Double {
        let x = min(max(u, 0), 1)
        return pow(1 - x, 0.8) * min(x * 6, 1)
    }
}

/// A ribbon's extent and opacity at one instant (distances along the ribbon, heart radii).
public struct RibbonState: Equatable, Sendable {
    public var tail: Double
    public var head: Double
    public var opacity: Double
}
