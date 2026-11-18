import Foundation

/// Angle helpers for the dial. Screen angles are radians, 0 at 3 o'clock, clockwise
/// positive, because y grows downward. The finger stop sits at `stopAngle`. At rest,
/// digit n (1…9, and 0 as ten pulses) lies `n` steps counter-clockwise of the stop,
/// so dragging it clockwise by that many steps parks it on the stop.
public enum RotaryDialMath {
    /// Wraps to (−π, π].
    public static func wrapPi(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let tau = Double.pi * 2
        var x = angle.truncatingRemainder(dividingBy: tau)
        if x <= -Double.pi { x += tau }
        if x > Double.pi { x -= tau }
        return x
    }

    /// Taylor sine on the wrapped angle. The web port uses the same eight terms,
    /// so the shake samples match without depending on libm.
    public static func sin(_ radians: Double) -> Double {
        let x = wrapPi(radians)
        let x2 = x * x
        var term = x
        var sum = x
        var n = 1.0
        for _ in 0..<8 {
            term *= -x2 / ((2 * n) * (2 * n + 1))
            sum += term
            n += 1
        }
        return sum
    }

    public static func pulse(forDisplay digit: Int) -> Int {
        digit == 0 ? RotaryDialTuning.holeCount : digit
    }

    public static func display(forPulse pulse: Int) -> Int {
        pulse == RotaryDialTuning.holeCount ? 0 : pulse
    }

    public static func travel(forDisplay digit: Int) -> Double {
        Double(pulse(forDisplay: digit)) * RotaryDialTuning.holeStep
    }

    /// Resting screen angle of a display digit.
    public static func restAngle(forDisplay digit: Int) -> Double {
        RotaryDialTuning.stopAngle - travel(forDisplay: digit)
    }

    public static func holeCenter(digit: Int, rotation: Double) -> Vec2 {
        let angle = restAngle(forDisplay: digit) + rotation
        return Vec2(RotaryDialTuning.centerX + RotaryDialTuning.holeOrbit * cos(angle),
                    RotaryDialTuning.centerY + RotaryDialTuning.holeOrbit * sin(angle))
    }

    public static func pointOnOrbit(_ angle: Double, radius: Double) -> Vec2 {
        Vec2(RotaryDialTuning.centerX + radius * cos(angle),
             RotaryDialTuning.centerY + radius * sin(angle))
    }

    /// How many hole-steps `rotation` has reached, counting an exact step.
    public static func detentIndex(_ rotation: Double) -> Int {
        guard rotation.isFinite, rotation > 0 else { return 0 }
        let steps = rotation / RotaryDialTuning.holeStep + 1e-9
        let index = Int(steps.rounded(.down))
        return min(max(index, 0), RotaryDialTuning.holeCount)
    }

    public static func clampRotation(_ rotation: Double, limit: Double) -> Double {
        let cap = min(max(limit, 0), RotaryDialTuning.maxTravel)
        return WhimsyMath.clamp(rotation, 0, cap)
    }

    /// Nearest hole within the grab radius, or nil on the hub and the bezel.
    public static func hitDigit(at point: Vec2, rotation: Double) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let reach = RotaryDialTuning.holeRadius + RotaryDialTuning.hitSlop
        let reach2 = reach * reach
        var best: Int?
        var bestDistance = reach2
        for digit in 0..<RotaryDialTuning.holeCount {
            let center = holeCenter(digit: digit, rotation: rotation)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = dx * dx + dy * dy
            if distance <= bestDistance {
                bestDistance = distance
                best = digit
            }
        }
        return best
    }

    /// Clockwise finger angle around the dial centre. Nil on the exact centre.
    public static func fingerAngle(_ point: Vec2) -> Double? {
        let dx = point.x - RotaryDialTuning.centerX
        let dy = point.y - RotaryDialTuning.centerY
        if dx == 0, dy == 0 { return nil }
        guard dx.isFinite, dy.isFinite else { return nil }
        return atan2(dy, dx)
    }

    public static func easeInOut(_ t: Double) -> Double {
        let t = WhimsyMath.clamp01(t)
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - (u * u * u) / 2
    }

    public static func easeOut(_ t: Double) -> Double {
        let u = 1 - WhimsyMath.clamp01(t)
        return 1 - u * u * u
    }

    /// Horizontal shiver. Zero under Reduce Motion, and zero outside the shake window.
    public static func shakeOffset(at t: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        let duration = RotaryDialTuning.shakeDuration
        if t <= 0 || t >= duration { return 0 }
        let u = t / duration
        let envelope = (1 - u) * (1 - u)
        let theta = 2 * Double.pi * RotaryDialTuning.shakeCycles * u
        return RotaryDialTuning.shakeAmplitude * envelope * sin(theta)
    }
}
