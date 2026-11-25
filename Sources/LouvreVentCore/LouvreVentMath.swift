import Foundation

/// Mapping from a set point to the vent: blade angle, chamber glow, the highlight
/// on each blade, and the foreshortened face. The sine polynomial is the same one
/// the web port uses, so a gap measured here matches the canvas mask at eight decimals.
public enum LouvreVentMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
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

    /// Half away from zero, so a positive `.5` matches `Math.round`.
    public static func roundTemperature(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        if x >= 0 { return Int(x.rounded()) }
        return -Int((-x).rounded())
    }

    public static func clamp(_ temperature: Int, to range: ClosedRange<Int>) -> Int {
        min(max(temperature, range.lowerBound), range.upperBound)
    }

    /// 0 at the cool end, 1 at the hot end. A single-degree range stays at 0,
    /// which keeps the blades closed: there is nowhere for them to open.
    public static func unit(temperature: Int, range: ClosedRange<Int>) -> Double {
        let t = clamp(temperature, to: range)
        let span = range.upperBound - range.lowerBound
        if span == 0 { return 0 }
        return Double(t - range.lowerBound) / Double(span)
    }

    /// Blade angle in degrees. 0 is closed (the face fills the slot) and 70 is open.
    /// Monotonic in temperature for any range with a positive span.
    public static func angle(unit: Double) -> Double {
        WhimsyMath.lerp(LouvreVentTuning.minAngle, LouvreVentTuning.maxAngle, WhimsyMath.clamp01(unit))
    }

    public static func angle(temperature: Int, range: ClosedRange<Int>) -> Double {
        angle(unit: unit(temperature: temperature, range: range))
    }

    public static func glow(unit: Double) -> LouvreGlow {
        let u = WhimsyMath.clamp01(unit)
        return LouvreGlow(
            red: WhimsyMath.lerp(LouvreVentTuning.coolRed, LouvreVentTuning.hotRed, u),
            green: WhimsyMath.lerp(LouvreVentTuning.coolGreen, LouvreVentTuning.hotGreen, u),
            blue: WhimsyMath.lerp(LouvreVentTuning.coolBlue, LouvreVentTuning.hotBlue, u),
            intensity: WhimsyMath.lerp(LouvreVentTuning.coolIntensity, LouvreVentTuning.hotIntensity, u)
        )
    }

    public static func glow(temperature: Int, range: ClosedRange<Int>) -> LouvreGlow {
        glow(unit: unit(temperature: temperature, range: range))
    }

    /// How bright the sliding highlight is. Hotter steel catches a harder glint.
    public static func specularIntensity(unit: Double) -> Double {
        let burn = glow(unit: unit).intensity
        return LouvreVentTuning.specularFloor + LouvreVentTuning.specularGain * burn
    }

    /// Vertical scale of a blade face rotated on X. 1 when closed, about 0.34 at 70°.
    public static func faceScale(angleDegrees: Double) -> Double {
        guard angleDegrees.isFinite else { return 1 }
        let radians = angleDegrees * pi / 180
        return WhimsyMath.clamp(cos(radians), 0, 1)
    }

    /// Triangle wave in −1…1. `phase` is in cycles. Arithmetic only, so the sweep
    /// matches the web port without a library sine.
    public static func triangle(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        var x = phase - phase.rounded(.down)
        if x < 0 { x += 1 }
        if x < 0.25 { return x / 0.25 }
        if x < 0.75 { return 1 - (x - 0.25) / 0.25 }
        return (x - 0.75) / 0.25 - 1
    }

    /// Where the highlight rests on blade `blade` at this opening, 0…1 down the face.
    /// Each blade carries a small phase so the glints are not one straight line,
    /// and the whole set still moves down the face as the vent opens.
    public static func restingSpecular(blade: Int, unit: Double) -> Double {
        let u = WhimsyMath.clamp01(unit)
        let index = min(max(blade, 0), LouvreVentTuning.bladeCount - 1)
        let phase = LouvreVentTuning.specularBladePhase * Double(index)
        let raw = LouvreVentTuning.specularStart
            + LouvreVentTuning.specularTravel * u
            + phase * (1 - u) * 0.5
        return WhimsyMath.clamp(raw, 0, 1)
    }

    /// Resting highlight, plus the traveling sweep. Reduce Motion drops the sweep
    /// and returns the resting position for this angle.
    public static func specular(blade: Int, unit: Double, sweep: Double, reduceMotion: Bool) -> Double {
        let rest = restingSpecular(blade: blade, unit: unit)
        if reduceMotion || !sweep.isFinite || sweep == 0 { return rest }
        let shifted = rest + LouvreVentTuning.specularSweepAmplitude * sweep
        return WhimsyMath.clamp(shifted, 0, 1)
    }

    /// Scene Y for an integer set point. The top of the opening is the hot end.
    public static func sceneY(forTemperature temperature: Int, range: ClosedRange<Int>) -> Double {
        let hot = unit(temperature: temperature, range: range)
        return LouvreVentTuning.openingY + (1 - hot) * LouvreVentTuning.openingHeight
    }

    /// Set point under a finger at scene Y. Above the opening is the hot stop,
    /// below it is the cool stop. Non-finite Y is the cool stop.
    public static func temperature(forSceneY y: Double, range: ClosedRange<Int>) -> Int {
        let lower = range.lowerBound
        let upper = range.upperBound
        guard y.isFinite else { return lower }
        if lower == upper { return lower }
        let top = LouvreVentTuning.openingY
        let bottom = top + LouvreVentTuning.openingHeight
        let along = WhimsyMath.progress(y, from: top, to: bottom)
        let raw = Double(lower) + Double(upper - lower) * (1 - along)
        return clamp(roundTemperature(raw), to: range)
    }

    public static func slots(unit: Double, sweep: Double, reduceMotion: Bool) -> [LouvreBladeSlot] {
        let u = WhimsyMath.clamp01(unit.isFinite ? unit : 0)
        let degrees = angle(unit: u)
        let scale = faceScale(angleDegrees: degrees)
        let count = LouvreVentTuning.bladeCount
        let slotHeight = LouvreVentTuning.openingHeight / Double(count)
        let face = slotHeight * LouvreVentTuning.bladeFaceRatio
        let projected = min(slotHeight, face * scale)
        let width = LouvreVentTuning.openingWidth
        let x = LouvreVentTuning.openingX
        let centerX = x + width / 2
        return (0..<count).map { index in
            let slotTop = LouvreVentTuning.openingY + Double(index) * slotHeight
            return LouvreBladeSlot(
                index: index,
                x: x,
                slotTop: slotTop,
                width: width,
                slotHeight: slotHeight,
                faceHeight: face,
                projectedHeight: projected,
                centerX: centerX,
                centerY: slotTop + slotHeight / 2,
                specular: specular(blade: index, unit: u, sweep: sweep, reduceMotion: reduceMotion),
                angle: degrees
            )
        }
    }
}
