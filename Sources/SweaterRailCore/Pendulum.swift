import Foundation

/// A damped pendulum hanging from a pivot that can be shoved sideways.
///
/// θ'' = −(g/L)·sin θ − (a/L)·cos θ − c·θ', where `a` is the pivot's horizontal acceleration:
/// shove the hook right and the garment swings back left, then rocks to rest.
/// θ is in radians, positive = the hem swings right (counter-clockwise on a y-down screen).
public struct Pendulum: Equatable, Sendable {
    public var angle: Double
    public var angularVelocity: Double
    /// Pivot-to-centre-of-mass length (pt).
    public var length: Double
    /// Gravity in pt/s² (a stylised, snappier-than-real value).
    public var gravity: Double
    /// Velocity damping (1/s).
    public var damping: Double
    /// Hard limit on the swing (rad), so a violent shove can't flip the garment over the rail.
    public var maxAngle: Double

    public init(angle: Double = 0, length: Double = 110, gravity: Double = 5_000, damping: Double = 3.2, maxAngle: Double = 0.45) {
        self.angle = angle
        self.angularVelocity = 0
        self.length = max(length, 1)
        self.gravity = max(gravity, 0)
        self.damping = max(damping, 0)
        self.maxAngle = max(maxAngle, 0)
    }

    /// 2π√(L/g): the small-swing period in seconds.
    public var smallAnglePeriod: Double { 2 * .pi * (length / max(gravity, 1e-9)).squareRoot() }

    /// One integration step of `h` seconds with the pivot accelerating at `pivotAcceleration` pt/s².
    public mutating func substep(pivotAcceleration a: Double, h: Double) {
        guard h > 0, h.isFinite, a.isFinite else { return }
        let alpha = -(gravity / length) * sin(angle) - (a / length) * cos(angle) - damping * angularVelocity
        angularVelocity += alpha * h
        angle += angularVelocity * h
        if abs(angle) > maxAngle {
            angle = angle > 0 ? maxAngle : -maxAngle
            angularVelocity = 0
        }
    }

    /// Advances `dt` (clamped to 0.1 s) in ≤ 1/240 s substeps with a constant pivot acceleration.
    public mutating func step(pivotAcceleration a: Double = 0, dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        var remaining = min(dt, WhimsySpring.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, WhimsySpring.maxSubstep)
            substep(pivotAcceleration: a, h: h)
            remaining -= h
        }
    }

    public var isAtRest: Bool { abs(angle) < 1e-3 && abs(angularVelocity) < 1e-2 }
}
