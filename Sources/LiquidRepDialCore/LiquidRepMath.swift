import Foundation

/// Fill, slosh and the meniscus. The sine and arctangent polynomials are the ones
/// the web port copies, so a traced angle matches at eight decimals.
public enum LiquidRepMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
    public static let eighthPi = Double.pi / 8
    static let invTwoPi = 1 / (2 * Double.pi)

    /// sin(x), reduced to [-π/2, π/2], then a Taylor polynomial to x¹⁷.
    /// A library `sin` can differ in the last bit; this one does not.
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = Double.pi - r } else if r < -halfPi { r = -Double.pi - r }
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

    /// atan(z). The argument is reduced with tan(π/8) = √2 − 1, then a Taylor
    /// polynomial through x¹⁷. Both ports share the reduction, so the low side
    /// of a tilt is the same angle.
    public static func atan(_ z: Double) -> Double {
        guard z.isFinite else {
            if z > 0 { return halfPi }
            if z < 0 { return -halfPi }
            return 0
        }
        let negative = z < 0
        var x = abs(z)
        var complement = false
        if x > 1 {
            x = 1 / x
            complement = true
        }
        var add = 0.0
        let tanEighth = (2.0).squareRoot() - 1
        if x > tanEighth {
            x = (x - tanEighth) / (1 + x * tanEighth)
            add = eighthPi
        }
        var result = atanSeries(x) + add
        if complement { result = halfPi - result }
        return negative ? -result : result
    }

    /// atan2(y, x), from the positive x axis, counter-clockwise, in (−π, π].
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if !y.isFinite || !x.isFinite { return 0 }
        if x > 0 { return atan(y / x) }
        if x < 0 {
            let base = atan(y / x)
            return y >= 0 ? base + pi : base - pi
        }
        if y > 0 { return halfPi }
        if y < 0 { return -halfPi }
        return 0
    }

    /// Shortest signed angle from `start` to `end`, in (−π, π].
    public static func shortest(from start: Double, to end: Double) -> Double {
        atan2(sin(end - start), cos(end - start))
    }

    /// How much of a ring can slosh. Empty and full sit at 0. A half ring is 1.
    public static func pool(_ fill: Double) -> Double {
        let unit = fill.isFinite ? WhimsyMath.clamp01(fill) : 0
        return sin(unit * pi)
    }

    /// Signed radians, clockwise from the top, that the pool wants.
    /// Positive roll (right side down) and positive pitch (bottom down) move the
    /// arc toward that low side. A level phone, and an empty or full ring, return 0.
    public static func sloshTarget(fill: Double, tilt: LiquidTilt) -> Double {
        let unit = fill.isFinite ? WhimsyMath.clamp01(fill) : 0
        let weight = pool(unit)
        if weight == 0 { return 0 }
        let roll = tilt.roll.isFinite ? tilt.roll : 0
        let pitch = tilt.pitch.isFinite ? tilt.pitch : 0
        let gx = sin(roll)
        let gy = sin(pitch)
        let mag = (gx * gx + gy * gy).squareRoot()
        if mag < 1e-9 { return 0 }
        let strength = min(mag / LiquidRepTuning.fullTilt, 1)
        let low = atan2(gx, -gy)
        let restCenter = unit * twoPi * 0.5
        let delta = shortest(from: restCenter, to: low)
        return WhimsyMath.clamp(delta * strength * weight, -LiquidRepTuning.maxSlosh, LiquidRepTuning.maxSlosh)
    }

    /// Glow for a displayed fill. At the goal the rim breathes, unless Reduce Motion
    /// is on, which holds a steady full glow.
    public static func glow(fill: Double, atGoal: Bool, elapsed: Double, reduceMotion: Bool) -> Double {
        let f = fill.isFinite ? WhimsyMath.clamp(fill, 0, 1) : 0
        if atGoal {
            if reduceMotion || !elapsed.isFinite { return LiquidRepTuning.goalGlowSteady }
            let wave = 0.5 + 0.5 * sin(elapsed * LiquidRepTuning.goalOmega)
            return WhimsyMath.clamp(
                LiquidRepTuning.goalGlowFloor + LiquidRepTuning.goalGlowPulse * wave,
                0,
                1
            )
        }
        return WhimsyMath.clamp(LiquidRepTuning.glowFloor + LiquidRepTuning.glowSpan * f, 0, 1)
    }

    /// The drawn rim. `rotation` is the SwiftUI `rotationEffect` that puts trim 0
    /// at the top and then adds the slosh. The leading point uses the same angle.
    public static func rim(fill: Double, slosh: Double, meniscus: Double, glow: Double) -> LiquidRim {
        let clamped = fill.isFinite ? WhimsyMath.clamp(fill, 0, 1) : 0
        let wobble = meniscus.isFinite ? meniscus : 0
        let trim = WhimsyMath.clamp(clamped + wobble * LiquidRepTuning.meniscusTrim, 0, 1)
        let sloshAngle = slosh.isFinite ? slosh : 0
        let rotation = -halfPi + sloshAngle
        let angle = sloshAngle + trim * twoPi
        let bulge = wobble * LiquidRepTuning.meniscusBulge
        let radius = LiquidRepTuning.ringRadius + bulge
        let center = LiquidRepTuning.dialCenter
        let leading = Vec2(
            center.x + sin(angle) * radius,
            center.y - cos(angle) * radius
        )
        return LiquidRim(
            trim: trim,
            rotation: rotation,
            slosh: sloshAngle,
            meniscus: wobble,
            glow: glow.isFinite ? glow : 0,
            bulge: bulge,
            leading: leading,
            center: center,
            radius: LiquidRepTuning.ringRadius
        )
    }

    /// A point on the rim. Angle 0 is the top and increases clockwise, y down.
    public static func point(angle: Double, radius: Double, center: Vec2 = LiquidRepTuning.dialCenter) -> Vec2 {
        Vec2(
            center.x + sin(angle) * radius,
            center.y - cos(angle) * radius
        )
    }

    private static func atanSeries(_ x: Double) -> Double {
        let x2 = x * x
        var p = 1.0 / 17.0
        p = -1.0 / 15.0 + x2 * p
        p = 1.0 / 13.0 + x2 * p
        p = -1.0 / 11.0 + x2 * p
        p = 1.0 / 9.0 + x2 * p
        p = -1.0 / 7.0 + x2 * p
        p = 1.0 / 5.0 + x2 * p
        p = -1.0 / 3.0 + x2 * p
        p = 1.0 + x2 * p
        return x * p
    }
}

/// What the view and the canvas port draw for one frame of the rim.
public struct LiquidRim: Equatable, Sendable {
    /// 0…1 along the circle, including the meniscus stretch, clamped so the stroke cannot lap itself.
    public var trim: Double
    /// Radians for a clockwise `rotationEffect`. −π/2 parks the start at the top.
    public var rotation: Double
    public var slosh: Double
    public var meniscus: Double
    public var glow: Double
    public var bulge: Double
    public var leading: Vec2
    public var center: Vec2
    public var radius: Double

    public init(
        trim: Double,
        rotation: Double,
        slosh: Double,
        meniscus: Double,
        glow: Double,
        bulge: Double,
        leading: Vec2,
        center: Vec2,
        radius: Double
    ) {
        self.trim = trim
        self.rotation = rotation
        self.slosh = slosh
        self.meniscus = meniscus
        self.glow = glow
        self.bulge = bulge
        self.leading = leading
        self.center = center
        self.radius = radius
    }
}
