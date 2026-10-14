import Foundation

/// Pure-Swift physics for a "magnetic bead" slider. No UI framework dependencies, so it is
/// deterministic and unit-testable on any platform (including Linux).
///
/// All positions are in normalized track units (`0...1`). A thumb (the magnet) slides along
/// the track; each bead has an evenly spaced rest position and is pulled toward the thumb by
/// a Gaussian distance falloff. Each bead is a damped spring that chases its pulled target.
/// Beads far from the thumb have softer springs, so they lag and trail like a chain.

/// Tunables for the bead system.
public struct BeadConfiguration: Equatable, Sendable {
    /// Number of beads along the track.
    public var beadCount: Int
    /// Fraction (0..<1) of the distance to the thumb that a bead at distance 0 moves.
    /// Keep it below 1 so beads never pass each other.
    public var pullStrength: Double
    /// Falloff radius (track units) of the magnetic pull.
    public var pullRadius: Double
    /// Spring stiffness (1/s²) for a bead right at the thumb.
    public var stiffness: Double
    /// Stiffness multiplier for the farthest beads (0...1). Lower values make the trail longer.
    public var farStiffnessFactor: Double
    /// Damping ratio (1 = critically damped). Below 1 gives a little bounce.
    public var dampingRatio: Double
    /// Stiffness for the thumb's own release spring (1/s²).
    public var thumbStiffness: Double
    /// Damping ratio for the thumb's release spring.
    public var thumbDampingRatio: Double
    /// Stretch per unit of speed (track units / s).
    public var squashSensitivity: Double
    /// Maximum extra stretch along the motion axis (0.5 means up to 1.5x).
    public var maxStretch: Double

    public init(
        beadCount: Int = 8,
        pullStrength: Double = 0.75,
        pullRadius: Double = 0.22,
        stiffness: Double = 260,
        farStiffnessFactor: Double = 0.3,
        dampingRatio: Double = 0.62,
        thumbStiffness: Double = 320,
        thumbDampingRatio: Double = 0.78,
        squashSensitivity: Double = 0.35,
        maxStretch: Double = 0.55
    ) {
        self.beadCount = beadCount
        self.pullStrength = pullStrength
        self.pullRadius = pullRadius
        self.stiffness = stiffness
        self.farStiffnessFactor = farStiffnessFactor
        self.dampingRatio = dampingRatio
        self.thumbStiffness = thumbStiffness
        self.thumbDampingRatio = thumbDampingRatio
        self.squashSensitivity = squashSensitivity
        self.maxStretch = maxStretch
    }

    public static let `default` = BeadConfiguration()
}

/// A single bead's simulated state.
public struct Bead: Equatable, Sendable {
    /// Evenly spaced resting position on the track.
    public let restPosition: Double
    public var position: Double
    public var velocity: Double
}

/// Scale factors that squash and stretch a bead. `along * across == 1`, so the area is preserved.
public struct Squash: Equatable, Sendable {
    /// Scale along the motion (track) axis; at least 1.
    public var along: Double
    /// Scale across the motion axis; equal to `1 / along`.
    public var across: Double
    public static let identity = Squash(along: 1, across: 1)
}

/// Damped harmonic spring, integrated with semi-implicit (symplectic) Euler.
public struct DampedSpring: Equatable, Sendable {
    public var stiffness: Double
    public var dampingRatio: Double
    public init(stiffness: Double, dampingRatio: Double) {
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }
    public var damping: Double { 2 * dampingRatio * stiffness.squareRoot() }

    /// Advances `(position, velocity)` toward `target` by `dt` seconds.
    public func step(position: inout Double, velocity: inout Double, target: Double, dt: Double) {
        let acceleration = stiffness * (target - position) - damping * velocity
        velocity += acceleration * dt
        position += velocity * dt
    }
}

/// The complete slider + bead simulation.
public struct MagneticBeadSystem: Equatable, Sendable {
    /// Largest internal integration step; larger `dt`s are split into substeps for stability.
    public static let maxSubstep: Double = 1.0 / 240.0
    /// Largest `dt` accepted per call (avoids a spiral of death after app suspension).
    public static let maxFrameDelta: Double = 0.1
    static let settlePositionEpsilon = 1e-4
    static let settleVelocityEpsilon = 1e-3

    public let configuration: BeadConfiguration
    /// Number of step intervals; `0` means continuous. With `steps == 4` the values are 0, 0.25 … 1.
    public let steps: Int
    public private(set) var beads: [Bead]
    /// Where the thumb is drawn right now (it springs to `thumbTarget` after release).
    public private(set) var thumbPosition: Double
    public private(set) var thumbVelocity: Double = 0
    /// Where the thumb is heading: the finger position while dragging, or the snapped value after release.
    public private(set) var thumbTarget: Double
    public private(set) var isDragging = false

    public init(value: Double = 0, steps: Int = 0, configuration: BeadConfiguration = .default) {
        precondition(configuration.beadCount > 0, "Need at least one bead")
        self.configuration = configuration
        self.steps = max(steps, 0)
        let start = Self.snap(Self.clamp(value), steps: max(steps, 0))
        thumbPosition = start
        thumbTarget = start
        let n = configuration.beadCount
        beads = (0..<n).map { i in
            let rest = n == 1 ? 0.5 : Double(i) / Double(n - 1)
            return Bead(restPosition: rest, position: rest, velocity: 0)
        }
        settleImmediately()
    }

    // MARK: Values & steps

    static func clamp(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return min(max(x, 0), 1)
    }

    /// Snaps `x` to the nearest step (or just clamps it when `steps == 0`).
    public static func snap(_ x: Double, steps: Int) -> Double {
        let c = clamp(x)
        guard steps > 0 else { return c }
        return (c * Double(steps)).rounded() / Double(steps)
    }

    /// Nearest step index for `x`; `nil` when continuous.
    public static func stepIndex(for x: Double, steps: Int) -> Int? {
        guard steps > 0 else { return nil }
        return Int((clamp(x) * Double(steps)).rounded())
    }

    /// The slider's value: the thumb target snapped to the nearest step.
    public var value: Double { Self.snap(thumbTarget, steps: steps) }
    /// The nearest step index of the thumb target (`nil` when continuous).
    public var stepIndex: Int? { Self.stepIndex(for: thumbTarget, steps: steps) }
    /// The distance between adjacent steps (`nil` when continuous).
    public var stepSize: Double? { steps > 0 ? 1 / Double(steps) : nil }

    // MARK: Input

    /// Moves the thumb directly under the finger. Returns `true` if the nearest step changed.
    @discardableResult
    public mutating func drag(to rawValue: Double) -> Bool {
        let before = stepIndex
        isDragging = true
        thumbTarget = Self.clamp(rawValue)
        thumbPosition = thumbTarget
        thumbVelocity = 0
        return stepIndex != before
    }

    /// Ends a drag: the thumb snaps (with a spring) to the nearest step. Returns the snapped value.
    @discardableResult
    public mutating func release() -> Double {
        isDragging = false
        thumbTarget = value
        return thumbTarget
    }

    /// Sets the value programmatically (accessibility, external binding changes).
    /// Returns `true` if the step changed.
    @discardableResult
    public mutating func setValue(_ newValue: Double, animated: Bool = true) -> Bool {
        let before = stepIndex
        isDragging = false
        thumbTarget = Self.snap(newValue, steps: steps)
        if !animated { settleImmediately() }
        return stepIndex != before
    }

    // MARK: Magnetic field

    /// Gaussian pull falloff in `0...1` for a bead at `distance` from the thumb.
    public func falloff(distance: Double) -> Double {
        let r = max(configuration.pullRadius, .ulpOfOne)
        return exp(-(distance * distance) / (r * r))
    }

    /// Target position for bead `index` given the current thumb position.
    public func targetPosition(forBead index: Int) -> Double {
        targetPosition(rest: beads[index].restPosition, thumb: thumbPosition)
    }

    func targetPosition(rest: Double, thumb: Double) -> Double {
        let delta = thumb - rest
        let pull = min(max(configuration.pullStrength, 0), 0.99) * falloff(distance: abs(delta))
        return rest + delta * pull
    }

    /// Spring for bead `index`: stiff near the thumb, soft far away, so beads trail like a chain.
    public func spring(forBead index: Int) -> DampedSpring {
        let f = falloff(distance: abs(thumbPosition - beads[index].restPosition))
        let factor = configuration.farStiffnessFactor + (1 - configuration.farStiffnessFactor) * f
        return DampedSpring(stiffness: configuration.stiffness * factor, dampingRatio: configuration.dampingRatio)
    }

    // MARK: Simulation

    /// Advances the simulation by `dt` seconds (clamped to `maxFrameDelta`, then split into substeps).
    public mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, Self.maxFrameDelta)
        while remaining > 0 {
            let h = min(remaining, Self.maxSubstep)
            substep(h)
            remaining -= h
        }
        if isSettled { settleImmediately() }
    }

    private mutating func substep(_ h: Double) {
        if !isDragging {
            let thumbSpring = DampedSpring(stiffness: configuration.thumbStiffness, dampingRatio: configuration.thumbDampingRatio)
            thumbSpring.step(position: &thumbPosition, velocity: &thumbVelocity, target: thumbTarget, dt: h)
        }
        for i in beads.indices {
            let target = targetPosition(forBead: i)
            let spring = spring(forBead: i)
            var bead = beads[i]
            spring.step(position: &bead.position, velocity: &bead.velocity, target: target, dt: h)
            beads[i] = bead
        }
    }

    /// Jumps everything to its resting state (used for Reduce Motion and the final settle).
    public mutating func settleImmediately() {
        if !isDragging {
            thumbPosition = thumbTarget
        }
        thumbVelocity = 0
        for i in beads.indices {
            beads[i].position = targetPosition(forBead: i)
            beads[i].velocity = 0
        }
    }

    /// `true` when the thumb and every bead are at rest on their targets.
    public var isSettled: Bool {
        guard abs(thumbPosition - thumbTarget) < Self.settlePositionEpsilon,
              abs(thumbVelocity) < Self.settleVelocityEpsilon else { return false }
        return beads.indices.allSatisfy { i in
            abs(beads[i].position - targetPosition(forBead: i)) < Self.settlePositionEpsilon
                && abs(beads[i].velocity) < Self.settleVelocityEpsilon
        }
    }

    // MARK: Squash & stretch

    /// Squash for a given speed: stretch along the motion axis, shrink across it, same area.
    public func squash(forVelocity velocity: Double) -> Squash {
        let speed = velocity.isFinite ? abs(velocity) : 0
        let stretch = 1 + min(speed * configuration.squashSensitivity, max(configuration.maxStretch, 0))
        return Squash(along: stretch, across: 1 / stretch)
    }

    public func squash(forBead index: Int) -> Squash {
        squash(forVelocity: beads[index].velocity)
    }
}
