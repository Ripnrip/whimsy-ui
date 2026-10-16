import Foundation

/// The flight phases of a ``FlyingButtonModel``.
///
/// `idle` → `thrust` (press begins, ~0.15 s crouch while the engine spools up) →
/// `airborne` (springs up to ~24 pt and hovers with a gentle bob) → `landing` (on release:
/// a soft spring down with a tiny bounce) → `idle`.
public enum FlightPhase: String, Equatable, Sendable, CaseIterable {
    case idle, thrust, airborne, landing
}

/// One puff of exhaust. Coordinates are points in the *ground* frame: the origin is the
/// centre of the capsule's bottom edge when it is resting, +x right, +y **down**.
public struct PlumeParticle: Equatable, Sendable {
    public var position: Vec2
    public var velocity: Vec2
    public var age: Double
    public var lifetime: Double
    /// Starting radius in points; see ``radius``.
    public var baseRadius: Double

    /// 0 at birth → 1 at death.
    public var progress: Double { min(max(age / lifetime, 0), 1) }
    /// Puffs swell as they cool.
    public var radius: Double { baseRadius * (1 + 1.6 * progress) }
    /// Quick fade-in (no popping), then an ease-out fade.
    public var opacity: Double { min(age / 0.05, 1) * pow(1 - progress, 1.5) }
    /// 1 = fresh ember, 0 = cold smoke. Renderers map this onto their gradient.
    public var heat: Double { pow(1 - progress, 1.4) }
}

/// A damped spring constant pair (stiffness k, damping ratio ζ).
public struct LiftSpring: Equatable, Sendable {
    public var stiffness: Double
    public var dampingRatio: Double
    public init(stiffness: Double, dampingRatio: Double) {
        self.stiffness = stiffness; self.dampingRatio = dampingRatio
    }
    var damping: Double { 2 * stiffness.squareRoot() * dampingRatio }
}

/// Pure-Swift physics for the flying button: a phase state machine, a lift spring and a
/// seeded plume particle emitter. Drive it with ``step(_:)`` once per frame.
public struct FlyingButtonModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// How long the engine spools up before liftoff.
        public var thrustDuration = 0.15
        /// Crouch depth during thrust (points, negative = squash towards the ground).
        public var crouch = -2.0
        public var hoverHeight = 24.0
        public var bobAmplitude = 1.6
        public var bobFrequency = 1.1
        /// Seconds for the bob to fade in after liftoff.
        public var bobRampIn = 0.4
        public var thrustSpring = LiftSpring(stiffness: 400, dampingRatio: 0.7)
        public var liftSpring = LiftSpring(stiffness: 120, dampingRatio: 0.5)
        public var landingSpring = LiftSpring(stiffness: 110, dampingRatio: 0.6)
        /// The landing spring aims slightly *below* the ground so the capsule meets it with
        /// some speed (like gravity) and the restitution produces a small bounce.
        public var landingAim = -4.0
        /// Fraction of downward speed returned on touchdown (the tiny bounce).
        public var restitution = 0.45
        /// Particles per second by phase. Landing only puffs for `landingPuffDuration`.
        public var thrustRate = 140.0
        public var airborneRate = 70.0
        public var landingRate = 30.0
        public var landingPuffDuration = 0.2
        /// Half-width of the nozzle along the capsule's bottom edge (points).
        public var nozzleHalfWidth = 22.0
        /// Initial downward speed range (points/s) and outward spread per point of offset.
        public var exhaustSpeed: ClosedRange<Double> = 70...120
        public var outwardSpread = 2.2
        /// Upward acceleration of warm smoke (points/s²) and linear drag (1/s).
        public var buoyancy = 90.0
        public var drag = 2.4
        /// Ground line (points below the resting capsule). Puffs that reach it skid outwards.
        public var floor = 10.0
        public var lifetimeRange: ClosedRange<Double> = 0.6...1.0
        public var radiusRange: ClosedRange<Double> = 4...7
        public var maxParticles = 220
        public init() {}
        public static let `default` = Tuning()
    }

    public private(set) var phase: FlightPhase = .idle
    /// Height above rest, points (positive = up).
    public private(set) var lift: Double = 0
    public private(set) var liftVelocity: Double = 0
    public private(set) var particles: [PlumeParticle] = []
    /// Increments once per liftoff (thrust → airborne). Handy as a haptic trigger.
    public private(set) var liftoffCount = 0
    /// Increments once per touchdown (first ground contact while landing).
    public private(set) var touchdownCount = 0
    public private(set) var phaseTime: Double = 0
    public private(set) var time: Double = 0
    public let tuning: Tuning

    private var rng: SeededRandom
    private var spawnDebt: Double = 0
    private var isPressed = false
    private var hasTouchedDown = false

    public init(seed: UInt64 = 0xF1_7E5, tuning: Tuning = .default) {
        self.rng = SeededRandom(seed: seed)
        self.tuning = tuning
    }

    // MARK: Input

    /// Finger down: start spooling up (also re-launches mid-landing).
    public mutating func pressBegan() {
        isPressed = true
        if phase == .idle || phase == .landing { enter(.thrust) }
    }

    /// Finger up: land (or abort the spool-up if we never left the ground).
    public mutating func pressEnded() {
        isPressed = false
        if phase == .thrust || phase == .airborne { enter(.landing) }
    }

    // MARK: Derived values for rendering

    /// 1 on the ground → 0.55 at hover height: the contact shadow shrinks as it lifts.
    public var shadowScale: Double { 1 - 0.45 * min(max(lift / tuning.hoverHeight, 0), 1.2) }
    public var shadowOpacity: Double { 0.28 * (1 - 0.6 * min(max(lift / tuning.hoverHeight, 0), 1)) }
    /// Vertical stretch from speed (squash on the way down, stretch on the way up).
    public var stretch: Double { 1 + min(max(liftVelocity * 0.0006, -0.06), 0.08) }
    /// Current target of the lift spring (exposed for tests and debugging).
    public var liftTarget: Double {
        switch phase {
        case .idle: 0
        case .landing: tuning.landingAim
        case .thrust: tuning.crouch
        case .airborne:
            tuning.hoverHeight + tuning.bobAmplitude * min(phaseTime / tuning.bobRampIn, 1)
                * sin(2 * .pi * tuning.bobFrequency * phaseTime)
        }
    }
    public var isSettled: Bool { phase == .idle && particles.isEmpty && abs(lift) < 0.01 }

    // MARK: Simulation

    /// Advance by `dt` seconds (clamped to 0.1 s; integrated in ≤ 1/240 s substeps).
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, 0.1)
        while remaining > 1e-12 {
            let h = min(remaining, 1.0 / 240)
            substep(h)
            remaining -= h
        }
    }

    private mutating func substep(_ h: Double) {
        time += h
        phaseTime += h

        if phase == .thrust, phaseTime >= tuning.thrustDuration {
            if isPressed { enter(.airborne); liftoffCount += 1 } else { enter(.landing) }
        }

        // Lift spring (semi-implicit Euler).
        let spring: LiftSpring = switch phase {
        case .thrust: tuning.thrustSpring
        case .airborne: tuning.liftSpring
        case .idle, .landing: tuning.landingSpring
        }
        let accel = spring.stiffness * (liftTarget - lift) - spring.damping * liftVelocity
        liftVelocity += accel * h
        lift += liftVelocity * h

        if phase == .landing {
            if lift <= 0, liftVelocity < 0 {
                lift = 0
                liftVelocity = -liftVelocity * tuning.restitution
                if !hasTouchedDown { hasTouchedDown = true; touchdownCount += 1 }
                if liftVelocity < 4 { liftVelocity = 0 }
            }
            if hasTouchedDown, lift < 0.05, abs(liftVelocity) < 1 {
                lift = 0; liftVelocity = 0
                enter(.idle)
            }
        }

        emit(h)
        advanceParticles(h)
    }

    private mutating func enter(_ next: FlightPhase) {
        phase = next
        phaseTime = 0
        if next == .landing { hasTouchedDown = false }
        // An aborted spool-up never left the ground, so "landing" from it is just a settle.
        if next == .landing, lift <= 0 { hasTouchedDown = true }
    }

    /// Spawn rate for the current phase (particles/s).
    public var spawnRate: Double {
        switch phase {
        case .idle: 0
        case .thrust: tuning.thrustRate
        case .airborne: tuning.airborneRate
        case .landing: phaseTime < tuning.landingPuffDuration ? tuning.landingRate : 0
        }
    }

    private mutating func emit(_ h: Double) {
        spawnDebt += spawnRate * h
        if spawnRate == 0 { spawnDebt = 0 }
        while spawnDebt >= 1 {
            spawnDebt -= 1
            guard particles.count < tuning.maxParticles else { continue }
            let offset = rng.uniform(-1...1) * tuning.nozzleHalfWidth
            let speed = rng.uniform(tuning.exhaustSpeed)
            let jitter = rng.uniform(-12...12)
            particles.append(PlumeParticle(
                position: Vec2(offset, -lift + 1),
                velocity: Vec2(offset * tuning.outwardSpread + jitter, speed),
                age: 0,
                lifetime: rng.uniform(tuning.lifetimeRange),
                baseRadius: rng.uniform(tuning.radiusRange)))
        }
    }

    private mutating func advanceParticles(_ h: Double) {
        let damp = exp(-tuning.drag * h)
        for i in particles.indices {
            var p = particles[i]
            p.velocity.y -= tuning.buoyancy * h
            p.velocity = p.velocity * damp
            p.position += p.velocity * h
            if p.position.y > tuning.floor {
                // Hit the ground: skid outwards instead of passing through.
                p.position.y = tuning.floor
                let side: Double = p.position.x >= 0 ? 1 : -1
                p.velocity.x += side * abs(p.velocity.y) * 0.6
                p.velocity.y = -abs(p.velocity.y) * 0.15
            }
            p.age += h
            particles[i] = p
        }
        particles.removeAll { $0.age >= $0.lifetime }
    }
}
