import Foundation

/// How lively the underlines are over time. A keystroke lifts the level from wherever it is to 1
/// over `attack` (ease-out), then it calms back to 0 (ease-in-out), reaching a flat line `calmAfter`
/// seconds after the keystroke. Typing again re-energizes it from its current level, without a jump.
public struct WaveEnvelope: Equatable, Sendable {
    public static let attack = 0.08
    public static let calmAfter = 0.5

    public private(set) var lastKeystroke: Double?
    private var startLevel = 0.0

    public init() {}

    public func level(at t: Double) -> Double {
        guard let k = lastKeystroke else { return 0 }
        let dt = t - k
        if dt < 0 { return startLevel }
        if dt < Self.attack { return startLevel + (1 - startLevel) * WhimsyMath.easeOutCubic(dt / Self.attack) }
        return 1 - WhimsyMath.easeInOutCubic((dt - Self.attack) / (Self.calmAfter - Self.attack))
    }

    public func isCalm(at t: Double) -> Bool {
        guard let k = lastKeystroke else { return true }
        return t - k >= Self.calmAfter
    }

    public mutating func energize(at t: Double) {
        startLevel = level(at: t)
        lastKeystroke = t
    }
}

/// The sine-wave underline under one matched letter. Each letter's wave is phase-shifted by its
/// index in the title and tapered to the baseline at both ends (sin πu), so a run of consecutive
/// matches joins into one continuous squiggle.
public enum WaveUnderline {
    /// Peak displacement at full energy, in points.
    public static let maxAmplitude = 2.2
    /// Points per wave cycle.
    public static let wavelength = 9.0
    /// Cycles per second of travel.
    public static let speed = 2.4
    /// Phase step per letter index, radians.
    public static let letterPhase = 0.9
    public static let samplesPerLetter = 12
    public static let lineWidth = 1.6

    /// Vertical offset from the underline's rest line at `x` (0…width) across the letter.
    public static func offset(x: Double, width: Double, amplitude: Double, time: Double, letterIndex: Int) -> Double {
        guard width > 0, amplitude != 0 else { return 0 }
        let u = WhimsyMath.clamp01(x / width)
        let phase = 2 * Double.pi * (x / wavelength + speed * time) + letterPhase * Double(letterIndex)
        return amplitude * sin(Double.pi * u) * sin(phase)
    }

    /// `count + 1` points from x = 0 to width (y relative to the rest line).
    public static func samples(width: Double, amplitude: Double, time: Double, letterIndex: Int,
                               count: Int = samplesPerLetter) -> [Vec2] {
        let n = max(count, 1)
        return (0...n).map { i in
            let x = width * Double(i) / Double(n)
            return Vec2(x, offset(x: x, width: width, amplitude: amplitude, time: time, letterIndex: letterIndex))
        }
    }
}

/// The "jiggle in" of a newly matched letter: it pops to `1 + scaleKick` and lifts by `lift`, then
/// a light, under-damped spring (closed form) settles it back with a couple of wobbles.
public enum LetterJiggle {
    public static let stiffness = 260.0
    public static let dampingRatio = 0.32
    public static let scaleKick = 0.35
    public static let lift = 5.0
    /// Delay per result row (capped at `maxStaggerRows`), so a keystroke ripples down the list.
    public static let stagger = 0.03
    public static let maxStaggerRows = 6
    /// After this long the jiggle is treated as settled (|displacement| < 0.002 well before).
    public static let settleTime = 1.0

    /// 0 before the letter starts, 1 at its start, ringing down to 0 (and crossing below it).
    public static func displacement(at t: Double) -> Double {
        guard t >= 0 else { return 0 }
        if t >= settleTime { return 0 }
        return 1 - WhimsySpring.stepResponse(at: t, stiffness: stiffness, dampingRatio: dampingRatio)
    }

    /// Scale (anchored at the baseline) and vertical offset (negative is up) `t` seconds after the start.
    public static func transform(at t: Double) -> (scale: Double, offsetY: Double) {
        let d = displacement(at: t)
        return (1 + scaleKick * d, -lift * d)
    }
}
