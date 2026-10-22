import Foundation

/// A circular travelling ripple: unit-amplitude height `sin(k·d − ω·τ)`, gated behind a soft
/// wavefront moving at `speed` and fading with distance. Mirrored line-for-line in
/// ClothPoster.metal (`clothHeight`).
public struct ClothWave: Equatable, Sendable {
    public var wavelength: Double
    public var speed: Double
    public var decayLength: Double
    public var frontSoftness: Double

    public init(wavelength: Double = 52, speed: Double = 230, decayLength: Double = 240, frontSoftness: Double = 36) {
        self.wavelength = max(wavelength, 1e-3)
        self.speed = max(speed, 1e-3)
        self.decayLength = max(decayLength, 1e-3)
        self.frontSoftness = max(frontSoftness, 1e-3)
    }

    public var wavenumber: Double { 2 * .pi / wavelength }
    public var angularFrequency: Double { wavenumber * speed }
    /// Seconds between crests leaving the source.
    public var period: Double { wavelength / speed }

    /// 1 well behind the front, 0 beyond it, smooth in between.
    public func gate(distance d: Double, time t: Double) -> Double {
        let front = speed * t
        return WhimsyMath.smoothstep(front, front - frontSoftness, d)
    }

    /// Unit-amplitude height at distance `d` from the source, `t` seconds after it started.
    public func height(distance d: Double, time t: Double) -> Double {
        guard t > 0, d.isFinite, t.isFinite else { return 0 }
        let d = max(d, 0)
        return sin(wavenumber * d - angularFrequency * t) * gate(distance: d, time: t) * exp(-d / decayLength)
    }

    /// Radial slope dh/dd by a central difference of ±0.75 pt (the shader uses the same step).
    public func slope(distance d: Double, time t: Double) -> Double {
        let e = 0.75
        return (height(distance: d + e, time: t) - height(distance: max(d - e, 0), time: t)) / (d >= e ? 2 * e : d + e)
    }

    /// How many crests have left the source by time `t` (a new crest each period).
    public func crestIndex(time t: Double) -> Int {
        guard t > 0, t.isFinite else { return 0 }
        return Int((t / period).rounded(.down))
    }
}

/// Lighting for the sheen and shading: a surface z = h(x, y) lit from the upper left.
public enum ClothShading {
    /// Points towards the light (y down, so −y is up).
    public static let light: (x: Double, y: Double, z: Double) = {
        let v = (-0.45, -0.6, 0.66), n = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / n, v.1 / n, v.2 / n)
    }()
    public static let shininess = 24.0

    /// Unit surface normal for the height gradient (∂z/∂x, ∂z/∂y).
    public static func normal(gradient g: Vec2) -> (x: Double, y: Double, z: Double) {
        let n = (g.x * g.x + g.y * g.y + 1).squareRoot()
        return (-g.x / n, -g.y / n, 1 / n)
    }

    private static var halfVector: (x: Double, y: Double, z: Double) {
        let h = (light.x, light.y, light.z + 1), n = (h.0 * h.0 + h.1 * h.1 + h.2 * h.2).squareRoot()
        return (h.0 / n, h.1 / n, h.2 / n)
    }

    /// Specular sheen 0…1 above what a flat cloth shows, so a still poster has none.
    public static func sheen(gradient g: Vec2) -> Double {
        let n = normal(gradient: g), h = halfVector
        let spec = pow(max(n.x * h.x + n.y * h.y + n.z * h.z, 0), shininess)
        let flat = pow(h.z, shininess)
        return WhimsyMath.clamp01((spec - flat) / (1 - flat))
    }

    /// Diffuse change relative to flat: positive on slopes facing the light, negative away.
    public static func shade(gradient g: Vec2) -> Double {
        let n = normal(gradient: g)
        return n.x * light.x + n.y * light.y + n.z * light.z - light.z
    }
}
