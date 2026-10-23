import Foundation

/// A piece flying off the card: it spins, falls under gravity and fades.
public struct TumbleBody: Equatable, Sendable {
    public var position: Vec2
    public var velocity: Vec2
    /// Radians, clockwise on screen (y down).
    public var angle = 0.0
    public var spin: Double
    public var age = 0.0

    public init(position: Vec2, velocity: Vec2, spin: Double) {
        self.position = position; self.velocity = velocity; self.spin = spin
    }
}

public struct TumblePhysics: Equatable, Sendable {
    public var gravity = 2600.0
    /// Linear air drag per second on velocity, and on spin.
    public var airDrag = 0.6
    public var spinDrag = 0.35
    public var fadeDelay = 0.35
    public var fadeDuration = 0.55
    /// Reduce Motion: pieces stay put and just fade.
    public var reduceMotion = false

    public init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    public var lifetime: Double { reduceMotion ? 0.3 : fadeDelay + fadeDuration }

    /// Launch velocity and spin for a piece leaving in `direction` with the finger's `release`
    /// velocity. Always kicks upward first, and spins the way the peel was going.
    public func launch(at position: Vec2, direction: Vec2, release: Vec2, rng: inout SeededRandom) -> TumbleBody {
        if reduceMotion { return TumbleBody(position: position, velocity: .zero, spin: 0) }
        let dir = direction.length > 1e-9 ? direction.normalized : Vec2(0, -1)
        let carried = release.clamped(toRadius: 1800) * 0.5
        let v = carried + dir * rng.uniform(380...460) + Vec2(0, -rng.uniform(560...680))
        let side: Double = dir.x >= 0 ? 1 : -1
        return TumbleBody(position: position, velocity: v, spin: side * rng.uniform(5...9))
    }

    public func step(_ b: inout TumbleBody, dt: Double) {
        var left = min(max(dt, 0), WhimsySpring.maxFrame)
        while left > 1e-12 {
            let h = min(left, WhimsySpring.maxSubstep)
            if !reduceMotion {
                b.velocity.y += gravity * h
                b.velocity = b.velocity * max(0, 1 - airDrag * h)
                b.position += b.velocity * h
                b.angle += b.spin * h
                b.spin *= max(0, 1 - spinDrag * h)
            }
            b.age += h
            left -= h
        }
    }

    public func opacity(_ b: TumbleBody) -> Double {
        if reduceMotion { return 1 - WhimsyMath.clamp01(b.age / lifetime) }
        return 1 - WhimsyMath.smoothstep(fadeDelay, fadeDelay + fadeDuration, b.age)
    }

    /// A slight lift toward the viewer as it comes away.
    public func scale(_ b: TumbleBody) -> Double {
        reduceMotion ? 1 : 1 + 0.08 * WhimsyMath.easeOutCubic(b.age / 0.25)
    }

    public func isFinished(_ b: TumbleBody) -> Bool { b.age >= lifetime }
}
