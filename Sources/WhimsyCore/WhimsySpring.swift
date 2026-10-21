import Foundation

/// A damped spring, stepped with semi-implicit Euler in fixed substeps (≤ 1/240 s), so it's
/// stable at any frame rate and reproducible on every platform. Shared by the newer cores.
public struct WhimsySpring: Equatable, Sendable {
    public var value: Double
    public var velocity: Double
    /// Spring constant k (per unit mass), 1/s².
    public var stiffness: Double
    /// ζ: < 1 overshoots, 1 is critically damped, > 1 is sluggish.
    public var dampingRatio: Double

    /// The largest substep and the largest frame the spring integrates (a stalled frame is
    /// clamped rather than exploding).
    public static let maxSubstep = 1.0 / 240
    public static let maxFrame = 0.1

    public init(value: Double = 0, velocity: Double = 0, stiffness: Double = 170, dampingRatio: Double = 0.8) {
        self.value = value
        self.velocity = velocity
        self.stiffness = max(stiffness, 0)
        self.dampingRatio = max(dampingRatio, 0)
    }

    /// The damping coefficient c = 2ζ√k.
    public var damping: Double { 2 * dampingRatio * stiffness.squareRoot() }

    /// The undamped angular frequency ω₀ = √k.
    public var naturalFrequency: Double { stiffness.squareRoot() }

    /// Advances by `dt` seconds toward `target`. Non-finite or non-positive input is ignored.
    public mutating func step(toward target: Double, dt: Double) {
        guard dt > 0, dt.isFinite, target.isFinite else { return }
        var remaining = min(dt, Self.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, Self.maxSubstep)
            substep(toward: target, h: h)
            remaining -= h
        }
    }

    /// One raw integration step of length `h` (no clamping); the building block for models
    /// that need per-substep values such as acceleration.
    public mutating func substep(toward target: Double, h: Double) {
        let acceleration = stiffness * (target - value) - damping * velocity
        velocity += acceleration * h
        value += velocity * h
    }

    public func isSettled(at target: Double, tolerance: Double = 1e-3) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }

    public mutating func snap(to target: Double) {
        value = target
        velocity = 0
    }

    /// The closed-form response at time `t` of a spring released at 0 with no velocity toward 1.
    /// Handy for staggered layouts where each item is a time-shifted copy of one spring.
    public static func stepResponse(at t: Double, stiffness: Double, dampingRatio: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t.isFinite else { return 1 }
        let w0 = max(stiffness, 0).squareRoot()
        let z = max(dampingRatio, 0)
        if w0 == 0 { return 0 }
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            return 1 - exp(-z * w0 * t) * (cos(wd * t) + z / (1 - z * z).squareRoot() * sin(wd * t))
        } else if z == 1 {
            return 1 - exp(-w0 * t) * (1 + w0 * t)
        } else {
            let s = (z * z - 1).squareRoot()
            let r1 = -w0 * (z - s), r2 = -w0 * (z + s)
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        }
    }
}

/// Two `WhimsySpring`s sharing tuning, for points.
public struct WhimsySpring2D: Equatable, Sendable {
    public var x: WhimsySpring
    public var y: WhimsySpring

    public init(value: Vec2 = .zero, stiffness: Double = 170, dampingRatio: Double = 0.8) {
        x = WhimsySpring(value: value.x, stiffness: stiffness, dampingRatio: dampingRatio)
        y = WhimsySpring(value: value.y, stiffness: stiffness, dampingRatio: dampingRatio)
    }

    public var value: Vec2 { Vec2(x.value, y.value) }
    public var velocity: Vec2 { Vec2(x.velocity, y.velocity) }

    public mutating func step(toward target: Vec2, dt: Double) {
        x.step(toward: target.x, dt: dt)
        y.step(toward: target.y, dt: dt)
    }

    public mutating func substep(toward target: Vec2, h: Double) {
        x.substep(toward: target.x, h: h)
        y.substep(toward: target.y, h: h)
    }

    public func isSettled(at target: Vec2, tolerance: Double = 1e-3) -> Bool {
        x.isSettled(at: target.x, tolerance: tolerance) && y.isSettled(at: target.y, tolerance: tolerance)
    }

    public mutating func snap(to target: Vec2) {
        x.snap(to: target.x)
        y.snap(to: target.y)
    }
}

/// Small scalar helpers shared by the cores (and mirrored exactly by the web previews).
public enum WhimsyMath {
    public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
    public static func clamp01(_ x: Double) -> Double { clamp(x, 0, 1) }
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    /// Where `x` falls between `a` and `b`, clamped to 0…1 (0 when a == b and x < a).
    public static func progress(_ x: Double, from a: Double, to b: Double) -> Double {
        if a == b { return x < a ? 0 : 1 }
        return clamp01((x - a) / (b - a))
    }
    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = progress(x, from: a, to: b)
        return t * t * (3 - 2 * t)
    }
    public static func easeInOutCubic(_ t: Double) -> Double {
        let t = clamp01(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    public static func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - clamp01(t), 3) }
}
