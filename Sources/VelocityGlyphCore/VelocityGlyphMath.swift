import Foundation

/// Constants for the price scatter. The HTML port copies these numbers and the polynomials below.
public enum VelocityGlyphTuning {
    public static let defaultLower = 40
    public static let defaultUpper = 600
    public static let defaultStep = 5
    public static let defaultValue = 180

    /// Track length in points. Drag x is measured in this space (the view scales into it).
    public static let trackWidth = 280.0

    /// Smoothing time constant, seconds. The blend is `1 - exp(-dt / tau)`.
    public static let velocityTau = 0.09

    /// Absolute thumb speed, in points per second, that saturates offset, lean and blur.
    public static let fullSpeed = 480.0

    /// Peak vertical offset at full speed, in points. The seed scales this down per glyph.
    public static let maxOffset = 18.0

    /// Peak lean at full speed, in degrees. A few degrees, not a tumble.
    public static let maxLean = 6.0

    /// Peak blur radius at full speed, in points.
    public static let maxBlur = 1.8

    /// Return spring. ζ under 1 so a glyph released off the baseline overshoots it.
    public static let springStiffness = 240.0
    public static let springDamping = 0.55

    /// Largest step the model integrates. A longer frame is clamped, matching the other cores.
    public static let maxFrame = 0.1
    public static let substep = WhimsySpring.maxSubstep
}

/// Seeded scatter, speed clamping and the velocity smoother.
///
/// `exp` is the same Taylor polynomial the star jar uses, so a web port that copies it reproduces
/// the smoother bit for bit. Seeds come from SplitMix64 (`SeededRandom.uniform`), also copied there.
public enum VelocityGlyphMath {
    /// Stable seed for a role. The salt is the ASCII-ish tag `VGLY`.
    public static func seed(for role: GlyphRole) -> UInt64 {
        switch role {
        case .sign: 0x5647_4C59_0000_0001
        case .currency: 0x5647_4C59_0000_0002
        case .digit(let place): 0x5647_4C59_1000_0000 &+ UInt64(UInt32(truncatingIfNeeded: place))
        case .separator(let group): 0x5647_4C59_2000_0000 &+ UInt64(UInt32(truncatingIfNeeded: group))
        }
    }

    /// Raw signed sample in (-1, 1). The same role always returns the same value.
    public static func signedUnit(for role: GlyphRole) -> Double {
        var rng = SeededRandom(seed: seed(for: role))
        return rng.uniform(0...1) * 2 - 1
    }

    /// Scatter weight in [-1, -0.45] ∪ [0.45, 1]. The seed still picks the sign and the ranking,
    /// and a glyph whose raw sample is near zero still takes almost half the peak.
    public static func signedAmplitude(for role: GlyphRole) -> Double {
        let unit = signedUnit(for: role)
        let direction = unit < 0 ? -1.0 : 1.0
        return direction * (0.45 + 0.55 * abs(unit))
    }

    /// 0…1 from absolute speed. Non-finite speed is 0. Speeds past ``VelocityGlyphTuning/fullSpeed`` stay at 1.
    public static func speedScale(_ speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        return WhimsyMath.clamp01(abs(speed) / VelocityGlyphTuning.fullSpeed)
    }

    /// One-pole blend of `raw` into `previous` over `dt` seconds.
    public static func smooth(previous: Double, raw: Double, dt: Double) -> Double {
        let prev = previous.isFinite ? previous : 0
        guard raw.isFinite else { return prev }
        let alpha = smoothAlpha(dt: dt)
        return prev + (raw - prev) * alpha
    }

    /// `1 - exp(-dt / tau)` for a positive `dt`, else 0. `dt` is capped at ``VelocityGlyphTuning/maxFrame``.
    public static func smoothAlpha(dt: Double) -> Double {
        guard dt.isFinite, dt > 0 else { return 0 }
        let capped = min(dt, VelocityGlyphTuning.maxFrame)
        return 1 - polyExp(-capped / VelocityGlyphTuning.velocityTau)
    }

    /// Target offset (points, +down) and lean (degrees) for this glyph at `speed`.
    public static func scatter(for role: GlyphRole, speed: Double) -> (offset: Double, lean: Double) {
        let scale = speedScale(speed)
        let amplitude = signedAmplitude(for: role)
        return (amplitude * VelocityGlyphTuning.maxOffset * scale, amplitude * VelocityGlyphTuning.maxLean * scale)
    }

    /// Blur radius in points at `speed`.
    public static func blur(forSpeed speed: Double) -> Double {
        VelocityGlyphTuning.maxBlur * speedScale(speed)
    }

    /// eˣ for x clamped to ±60. Same reduction and Taylor series as `StarJarMath.exp`.
    static func polyExp(_ x: Double) -> Double {
        guard !x.isNaN else { return 0 }
        let xc = min(max(x, -60), 60)
        let k = (xc * invLn2 + 0.5).rounded(.down)
        let r = xc - k * ln2
        var p = 1.0 / 6_227_020_800.0
        p = 1.0 / 479_001_600.0 + r * p
        p = 1.0 / 39_916_800.0 + r * p
        p = 1.0 / 3_628_800.0 + r * p
        p = 1.0 / 362_880.0 + r * p
        p = 1.0 / 40320.0 + r * p
        p = 1.0 / 5040.0 + r * p
        p = 1.0 / 720.0 + r * p
        p = 1.0 / 120.0 + r * p
        p = 1.0 / 24.0 + r * p
        p = 1.0 / 6.0 + r * p
        p = 0.5 + r * p
        p = 1.0 + r * p
        p = 1.0 + r * p
        var n = Int(k)
        while n > 0 { p *= 2; n -= 1 }
        while n < 0 { p /= 2; n += 1 }
        return p
    }

    static let ln2 = 0.6931471805599453
    static let invLn2 = 1 / 0.6931471805599453
}
