import Foundation

/// Every constant the pendulum, the candy, the cracks and the burst share.
/// `webports/pinata-core.mjs` repeats this table. Change both together.
public enum PinataTuning {
    public static let canvasWidth = 320.0
    public static let canvasHeight = 480.0
    public static let anchorX = 160.0
    public static let anchorY = 48.0

    /// Pivot-to-body-centre length at rest (pt). Gravity on the radius is pretensioned
    /// into this length, so a still piñata is an exact equilibrium.
    public static let restLength = 118.0
    public static let bodyRadiusX = 58.0
    public static let bodyRadiusY = 70.0
    /// Hit ellipse is a little larger than the painted body, so a tap on the fringe counts.
    public static let hitSlop = 1.12

    /// Stylised gravity for the angular equation, pt/s².
    public static let gravity = 2200.0
    /// Extra torsional spring toward hanging straight down, 1/s². This is the "spring" in
    /// the spring pendulum; gravity supplies the rest of the restoring torque.
    public static let torsion = 6.5
    /// Angular velocity damping, 1/s.
    public static let angularDamping = 1.35
    /// Radial spring about `restLength`, 1/s². Hard hits stretch the ribbon.
    public static let radialStiffness = 70.0
    public static let radialDamping = 5.8
    public static let minLength = 86.0
    public static let maxLength = 176.0
    /// Hard stop so a violent hit can't wind the ribbon over the peg, radians.
    public static let maxAngle = 1.15

    /// Angular impulse (rad/s) of hit 1. Later hits multiply by `hitScale(forHit:)`.
    public static let baseImpulse = 2.35
    /// Each hit adds this fraction of the base impulse. Hit 8 is 2.4× hit 1.
    public static let impulseGrowth = 0.2
    /// Outward speed added to the ribbon spring, pt/s, before the hit scale.
    public static let radialKick = 120.0

    public static let candyMin = 6
    public static let candyMax = 10
    public static let candySpread = 1.05
    public static let candySpeedMin = 150.0
    public static let candySpeedMax = 360.0
    public static let candyLifeMin = 0.72
    public static let candyLifeMax = 1.05
    public static let candySizeMin = 5.0
    public static let candySizeMax = 9.5
    public static let candySpin = 8.0
    public static let candyGravity = 880.0
    public static let candyDrag = 0.45
    public static let candyColors = 6

    public static let crackBase = 18.0
    public static let crackGrowth = 4.5
    public static let crackXMin = 0.10
    public static let crackXMax = 0.55
    public static let crackYMin = -0.45
    public static let crackYMax = 0.50

    public static let confettiCount = 32
    public static let confettiSpeedMin = 90.0
    public static let confettiSpeedMax = 280.0
    public static let confettiLifeMin = 1.05
    public static let confettiLifeMax = 1.45
    public static let confettiGravity = 620.0
    public static let confettiDrag = 0.55
    public static let confettiSizeMin = 4.0
    public static let confettiSizeMax = 8.0
    public static let confettiSpin = 11.0

    /// Glow flash exponential decay, 1/s.
    public static let glowDecay = 5.2

    public static let halfSpeed = 190.0
    public static let halfLift = 80.0
    public static let halfSpin = 2.4
    public static let halfGravity = 1040.0
    public static let halfSpinDrag = 0.35
    public static let halfGap = 5.0
    public static let halfFade = 1.15

    /// Full-motion burst, seconds, from the breaking hit until the phase is spent.
    public static let burstDuration = 1.35
    /// Reduce Motion fade, seconds.
    public static let fadeDuration = 0.40

    public static let tokenStiffness = 170.0
    public static let tokenDamping = 0.68
    /// Token starts this many points below its rest spot and springs up.
    public static let tokenDrop = 36.0

    public static let substep = 1.0 / 240.0
    public static let maxFrame = 0.1

    public static let defaultHits = 8
    public static let minHits = 1
    public static let maxHits = 24
    public static let defaultSeed: UInt64 = 0x00C0_FFEE_51A7

    public static let keepTapping = "Keep tapping"
    public static let comeBack = "Come back tomorrow"

    public static func clampedHits(_ n: Int) -> Int { min(max(n, minHits), maxHits) }

    /// 1 for the first hit, then `1 + impulseGrowth * (n - 1)`.
    public static func hitScale(forHit n: Int) -> Double {
        1 + impulseGrowth * Double(max(n, 1) - 1)
    }

    public static func impulse(forHit n: Int) -> Double { baseImpulse * hitScale(forHit: n) }

    /// Seed for the RNG of hit `n` (1-based). Hit streams never share state.
    public static func hitSeed(_ seed: UInt64, _ hit: Int) -> UInt64 {
        seed ^ (UInt64(truncatingIfNeeded: hit) &* 0x9E37_79B9_7F4A_7C15)
    }
}
