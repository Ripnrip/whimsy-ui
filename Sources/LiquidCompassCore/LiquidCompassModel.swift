import Foundation

/// The liquid-metal compass: a heading in, a springy blob out.
///
/// The blob's lean angle follows the friend's **relative bearing** (friend bearing − device
/// heading) on an underdamped spring, always taking the short way round, so a turn makes it
/// swing past and wobble back. Its stretch rides a second, bouncier spring whose target grows
/// with the swing speed: the liquid flings out while turning and jiggles as it settles.
/// An ``AlignmentDetector`` watches the raw (unsprung) bearing and ticks when you face the
/// friend. Drive it with ``step(_:)`` once per frame.
public struct LiquidCompassModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Lean-angle spring (degrees): ~27% overshoot, ~0.8 s period.
        public var angleStiffness = 70.0
        public var angleDamping = 0.38
        /// Stretch spring: bouncier, so the blob jiggles.
        public var stretchStiffness = 140.0
        public var stretchDamping = 0.28
        /// Resting stretch toward the friend, plus extra while swinging fast.
        public var baseStretch = 0.42
        public var swingStretch = 0.32
        /// Swing speed (deg/s) that earns the full `swingStretch`.
        public var swingReference = 240.0
        public var maxStretch = 0.8
        /// Glow that fades in while aligned (0…1).
        public var glowStiffness = 120.0
        public var glowDamping = 0.9
        public var geometry = BlobGeometry.default
        public var alignEnter = 4.0
        public var alignExit = 8.0
        public var tickCooldown = 0.35
        public init() {}
        public static let `default` = Tuning()
    }

    public let tuning: Tuning
    /// Reduce Motion: critically damped springs and no swing stretch, so the blob turns
    /// smoothly without overshoot or jiggle.
    public var reduceMotion: Bool {
        didSet { configureSprings() }
    }

    public private(set) var heading: Double
    public private(set) var friendBearing: Double
    public private(set) var time: Double = 0
    public private(set) var alignment: AlignmentDetector
    /// Unwrapped lean angle (degrees). Use ``leanAngle`` for display.
    public private(set) var angleSpring: DampedSpring
    public private(set) var stretchSpring: DampedSpring
    public private(set) var glowSpring: DampedSpring

    public init(heading: Double = 0, friendBearing: Double = 0, tuning: Tuning = .default,
                reduceMotion: Bool = false) {
        self.tuning = tuning
        self.reduceMotion = reduceMotion
        self.heading = CompassMath.wrap360(heading)
        self.friendBearing = CompassMath.wrap360(friendBearing)
        let rel = CompassMath.relativeBearing(heading: heading, friendBearing: friendBearing)
        angleSpring = DampedSpring(value: rel, stiffness: tuning.angleStiffness, dampingRatio: tuning.angleDamping)
        stretchSpring = DampedSpring(value: tuning.baseStretch, stiffness: tuning.stretchStiffness,
                                     dampingRatio: tuning.stretchDamping)
        glowSpring = DampedSpring(value: 0, stiffness: tuning.glowStiffness, dampingRatio: tuning.glowDamping)
        alignment = AlignmentDetector(enter: tuning.alignEnter, exit: tuning.alignExit, cooldown: tuning.tickCooldown)
        configureSprings()
        // Starting aligned is not a "moment": don't tick for it.
        if abs(rel) <= tuning.alignEnter { alignment.suppressNextAlignmentTick() }
        alignment.update(relativeBearing: rel, time: 0)
        glowSpring.value = isAligned ? 1 : 0
    }

    private mutating func configureSprings() {
        angleSpring.stiffness = reduceMotion ? 120 : tuning.angleStiffness
        angleSpring.dampingRatio = reduceMotion ? 1 : tuning.angleDamping
        stretchSpring.dampingRatio = reduceMotion ? 1 : tuning.stretchDamping
    }

    // MARK: Inputs

    /// New device heading (degrees; any range).
    public mutating func setHeading(_ degrees: Double) {
        guard degrees.isFinite else { return }
        heading = CompassMath.wrap360(degrees)
    }

    /// New bearing to the friend (degrees; any range).
    public mutating func setFriendBearing(_ degrees: Double) {
        guard degrees.isFinite else { return }
        friendBearing = CompassMath.wrap360(degrees)
    }

    // MARK: Outputs

    /// Raw relative bearing, (-180, 180]: 0 = dead ahead, + = to the right.
    public var relativeBearing: Double {
        CompassMath.relativeBearing(heading: heading, friendBearing: friendBearing)
    }
    /// The sprung lean angle on screen, (-180, 180] (0 = up, clockwise).
    public var leanAngle: Double { CompassMath.wrap180(angleSpring.value) }
    /// Lean angular speed, deg/s.
    public var swingSpeed: Double { angleSpring.velocity }
    /// Current stretch (clamped to 0…maxStretch).
    public var stretch: Double { min(max(stretchSpring.value, 0), tuning.maxStretch) }
    /// 0…1 glow while aligned.
    public var glow: Double { min(max(glowSpring.value, 0), 1) }
    public var isAligned: Bool { alignment.isAligned }
    public var tickCount: Int { alignment.tickCount }

    /// The stretch the spring is heading for right now.
    public var stretchTarget: Double {
        let swing = reduceMotion ? 0 : tuning.swingStretch * min(abs(angleSpring.velocity) / tuning.swingReference, 1)
        return min(tuning.baseStretch + swing, tuning.maxStretch)
    }

    /// Blob outline around `center` for the current state.
    public func outline(center: Vec2 = .zero) -> [Vec2] {
        tuning.geometry.outline(angle: leanAngle, stretch: stretch, center: center)
    }

    public var isSettled: Bool {
        let target = angleSpring.value + CompassMath.shortestDelta(from: angleSpring.value, to: relativeBearing)
        return angleSpring.isSettled(at: target, tolerance: 0.01)
            && stretchSpring.isSettled(at: stretchTarget, tolerance: 1e-4)
            && glowSpring.isSettled(at: isAligned ? 1 : 0, tolerance: 1e-3)
    }

    // MARK: Simulation

    /// Advance by `dt` seconds (clamped to 0.1 s; integrated in ≤ 1/240 s substeps).
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, 0.1)
        while remaining > 1e-12 {
            let h = min(remaining, 1.0 / 240)
            time += h
            // Track the target the short way round from wherever the spring is now.
            let target = angleSpring.value + CompassMath.shortestDelta(from: angleSpring.value, to: relativeBearing)
            angleSpring.step(toward: target, dt: h)
            stretchSpring.step(toward: stretchTarget, dt: h)
            alignment.update(relativeBearing: relativeBearing, time: time)
            glowSpring.step(toward: isAligned ? 1 : 0, dt: h)
            remaining -= h
        }
        // Keep the unwrapped angle bounded without disturbing the motion.
        if abs(angleSpring.value) > 720 {
            angleSpring.value = CompassMath.wrap180(angleSpring.value)
        }
    }
}
