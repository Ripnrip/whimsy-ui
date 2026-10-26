import Foundation

/// The two small layer effects in `OilPaint.metal`, mirrored so they can be tested on Linux
/// (a test checks the constants match the shader).
public enum PaintShading {
    // paintSmear: average of `smearTaps` samples trailing behind the brush.
    /// Smear length (points) for a fully wet stroke.
    public static let smearLength = 3.0
    public static let smearTaps = 4

    // paintGloss: specular on a height field (the wet bristle layer's alpha).
    public static let heightScale = 4.0
    public static let shininess = 18.0
    public static let glossStrength = 0.85
    public static let sheen = 0.10
    public static let light = Vec3(-0.45, -0.6, 0.66)
    public static let tint = Vec3(1.0, 0.98, 0.94)

    public static func smearVector(direction: Vec2, wetness: Double) -> Vec2 {
        direction.normalized * (smearLength * WhimsyMath.clamp01(wetness))
    }

    /// Offsets the smear shader samples at (equal weights): from the pixel back along the stroke.
    public static func smearOffsets(_ smear: Vec2) -> [Vec2] {
        (0..<smearTaps).map { k in smear * (-Double(k) / Double(smearTaps - 1)) }
    }

    /// Premultiplied white-ish highlight alpha from the height (alpha) at a pixel and its four
    /// neighbours one point away (left, right, up, down).
    public static func highlight(center a: Double, left: Double, right: Double, up: Double, down: Double, strength: Double = 1) -> Double {
        let gx = (right - left) * 0.5 * heightScale
        let gy = (down - up) * 0.5 * heightScale
        let n = Vec3(-gx, -gy, 1).normalized
        let l = light.normalized
        let h = (l + Vec3(0, 0, 1)).normalized
        let flat = pow(h.z, shininess)
        let spec = max(0, min(1, (pow(max(n.dot(h), 0), shininess) - flat) / (1 - flat)))
        return max(0, min(1, (glossStrength * spec + sheen * a) * strength))
    }
}

/// Minimal 3-vector for the lighting maths.
public struct Vec3: Equatable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vec3 { let l = length; return l > 0 ? Vec3(x / l, y / l, z / l) : self }
}
