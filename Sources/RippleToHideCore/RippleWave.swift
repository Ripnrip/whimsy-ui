import Foundation

/// Numbers shared by the ripple, the Metal shader, and the web port.
///
/// `RippleToHide.metal` repeats every `*Default` as a `constant float`, and
/// `webports/ripple-core.js` repeats them in `RULES`. The displacement below is the
/// same expression as `rippleDisplacement` in the shader: a travelling sine, damped in
/// time, faded with distance, and cut off past a soft wavefront.
public struct RippleRules: Equatable, Sendable {
    public static let wavelengthDefault = 44.0
    public static let speedDefault = 240.0
    public static let spatialDecayDefault = 150.0
    public static let timeDampingDefault = 0.48
    public static let frontSoftnessDefault = 20.0
    public static let durationDefault = 0.90
    public static let amplitudeDefault = 14.0
    public static let swapFractionDefault = 0.5
    public static let reduceMotionDurationDefault = 0.28

    public var wavelength: Double
    public var speed: Double
    public var spatialDecay: Double
    public var timeDamping: Double
    public var frontSoftness: Double
    public var duration: Double
    public var amplitude: Double
    public var swapFraction: Double
    public var reduceMotionDuration: Double

    public init(
        wavelength: Double = RippleRules.wavelengthDefault,
        speed: Double = RippleRules.speedDefault,
        spatialDecay: Double = RippleRules.spatialDecayDefault,
        timeDamping: Double = RippleRules.timeDampingDefault,
        frontSoftness: Double = RippleRules.frontSoftnessDefault,
        duration: Double = RippleRules.durationDefault,
        amplitude: Double = RippleRules.amplitudeDefault,
        swapFraction: Double = RippleRules.swapFractionDefault,
        reduceMotionDuration: Double = RippleRules.reduceMotionDurationDefault
    ) {
        self.wavelength = Self.clamped(wavelength, floor: 1e-3, fallback: Self.wavelengthDefault)
        self.speed = Self.clamped(speed, floor: 1e-3, fallback: Self.speedDefault)
        self.spatialDecay = Self.clamped(spatialDecay, floor: 1e-3, fallback: Self.spatialDecayDefault)
        self.timeDamping = Self.clamped(timeDamping, floor: 1e-3, fallback: Self.timeDampingDefault)
        self.frontSoftness = Self.clamped(frontSoftness, floor: 1e-3, fallback: Self.frontSoftnessDefault)
        self.duration = Self.clamped(duration, floor: 1e-3, fallback: Self.durationDefault)
        self.amplitude = amplitude.isFinite ? amplitude : Self.amplitudeDefault
        if swapFraction.isFinite {
            self.swapFraction = min(max(swapFraction, 1e-6), 1)
        } else {
            self.swapFraction = Self.swapFractionDefault
        }
        self.reduceMotionDuration = Self.clamped(reduceMotionDuration, floor: 1e-3, fallback: Self.reduceMotionDurationDefault)
    }

    private static func clamped(_ value: Double, floor: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return max(value, floor)
    }

    public static let standard = RippleRules()

    /// How far the front travels on a full-motion trip.
    public var reach: Double { speed * duration }
}

/// Axis-aligned bounds of the view the ripple covers. Y grows downward.
public struct RippleBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(minX: x, minY: y, maxX: x + width, maxY: y + height)
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
}

/// The stitchable ripple, in Double. `samplePosition` is what `rippleToHide` returns.
public struct RippleWave: Equatable, Sendable {
    public var rules: RippleRules

    public init(rules: RippleRules = .standard) {
        self.rules = rules
    }

    public var wavenumber: Double { 2 * .pi / rules.wavelength }
    public var angularFrequency: Double { wavenumber * rules.speed }

    /// 1 behind the front, 0 past it, smooth across `frontSoftness`.
    public func gate(distance d: Double, time t: Double) -> Double {
        guard t > 0, d.isFinite, t.isFinite else { return 0 }
        let front = rules.speed * t
        return 1 - WhimsyMath.smoothstep(front - rules.frontSoftness, front, max(d, 0))
    }

    /// `exp(-t / timeDamping)`. Zero at and before the start.
    public func timeDamp(time t: Double) -> Double {
        guard t > 0, t.isFinite else { return 0 }
        return exp(-t / rules.timeDamping)
    }

    /// `exp(-d / spatialDecay)`.
    public func falloff(distance d: Double) -> Double {
        guard d.isFinite else { return 0 }
        return exp(-max(d, 0) / rules.spatialDecay)
    }

    /// Distance the wavefront has travelled by `t`.
    public func front(time t: Double) -> Double {
        guard t > 0, t.isFinite else { return 0 }
        return rules.speed * t
    }

    /// Radial offset before amplitude. Positive values pull the sample toward the tap
    /// when the shader subtracts `(position - tap) / d * displacement * amplitude`.
    public func displacement(distance d: Double, time t: Double) -> Double {
        guard t > 0, d.isFinite, t.isFinite else { return 0 }
        let d = max(d, 0)
        let wave = sin(wavenumber * d - angularFrequency * t)
        return wave * gate(distance: d, time: t) * timeDamp(time: t) * falloff(distance: d)
    }

    /// Sample coordinate for an output pixel, matching `rippleToHide` in the shader.
    public func samplePosition(position: Vec2, tap: Vec2, time: Double, amplitude: Double) -> Vec2 {
        guard position.x.isFinite, position.y.isFinite, tap.x.isFinite, tap.y.isFinite,
              time.isFinite, amplitude.isFinite else {
            return position.x.isFinite && position.y.isFinite ? position : .zero
        }
        let v = position - tap
        let d = v.length
        if d < 1e-3 { return position }
        let offset = displacement(distance: d, time: time) * amplitude
        return position - v * (offset / d)
    }

    /// How far the front must travel before it has passed the whole view.
    ///
    /// The radius is the distance from `tap` to the farthest corner, capped at 92% of
    /// `reach` so a corner tap on a large card still crosses it before the trip ends.
    /// `reach` is `rules.reach` for a full-motion wave. A non-positive reach is left uncapped.
    public static func passRadius(tap: Vec2, in bounds: RippleBounds, reach: Double) -> Double {
        let corners = [
            Vec2(bounds.minX, bounds.minY),
            Vec2(bounds.maxX, bounds.minY),
            Vec2(bounds.minX, bounds.maxY),
            Vec2(bounds.maxX, bounds.maxY),
        ]
        let farthest = corners.map { tap.distance(to: $0) }.max() ?? 0
        guard farthest.isFinite else { return 0 }
        guard reach > 0, reach.isFinite else { return max(farthest, 0) }
        return min(max(farthest, 0), reach * 0.92)
    }
}

/// Digits become bullets. Everything else, including the currency mark and the separators, stays
/// so the masked string is the same length as the amount.
public enum BalanceMask {
    public static func mask(_ balance: String) -> String {
        String(balance.map { character in
            character.isASCII && character.isNumber ? "•" : character
        })
    }

    public static func display(_ balance: String, hidden: Bool) -> String {
        hidden ? mask(balance) : balance
    }
}
