import Foundation

/// A damped harmonic oscillator integrated with semi-implicit Euler in fixed substeps, so it
/// behaves the same at any frame rate. Underdamped (`dampingRatio < 1`) springs overshoot and
/// wobble; 1 is critically damped (fastest approach with no overshoot).
public struct DampedSpring: Equatable, Sendable {
    public var value: Double
    public var velocity: Double
    public var stiffness: Double
    public var dampingRatio: Double

    public init(value: Double = 0, velocity: Double = 0, stiffness: Double, dampingRatio: Double) {
        self.value = value; self.velocity = velocity
        self.stiffness = max(stiffness, 0); self.dampingRatio = max(dampingRatio, 0)
    }

    /// Damping coefficient c = 2ζ√k (unit mass).
    public var damping: Double { 2 * dampingRatio * stiffness.squareRoot() }
    /// Natural angular frequency ω₀ = √k, rad/s.
    public var naturalFrequency: Double { stiffness.squareRoot() }
    /// Fractional overshoot of a step response, e^(−πζ/√(1−ζ²)); 0 when ζ ≥ 1.
    public var theoreticalOvershoot: Double {
        dampingRatio >= 1 ? 0 : exp(-Double.pi * dampingRatio / (1 - dampingRatio * dampingRatio).squareRoot())
    }

    /// Advances `dt` seconds towards `target` (dt clamped to 0.1 s, substeps ≤ 1/240 s).
    public mutating func step(toward target: Double, dt: Double) {
        guard dt.isFinite, dt > 0, target.isFinite else { return }
        var remaining = min(dt, 0.1)
        while remaining > 1e-12 {
            let h = min(remaining, 1.0 / 240)
            let accel = stiffness * (target - value) - damping * velocity
            velocity += accel * h
            value += velocity * h
            remaining -= h
        }
    }

    /// True when within `tolerance` of `target` and (almost) still.
    public func isSettled(at target: Double, tolerance: Double = 1e-3) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }

    /// Jumps to `target` and stops.
    public mutating func snap(to target: Double) { value = target; velocity = 0 }
}
