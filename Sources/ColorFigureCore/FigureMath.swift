import Foundation

/// A point or direction in the figure's world: x is depth (the machine's front faces +x), y is width
/// (+y runs to the viewer's left at the home view) and z is up. One unit is about a centimetre.
public struct Vec3: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    public static let zero = Vec3(0, 0, 0)
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public static func * (s: Double, a: Vec3) -> Vec3 { a * s }
    public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vec3 {
        let l = length
        return l > 0 ? self * (1 / l) : .zero
    }
    public static func lerp(_ a: Vec3, _ b: Vec3, _ t: Double) -> Vec3 { a + (b - a) * t }
    public subscript(axis: Int) -> Double {
        switch axis { case 0: return x; case 1: return y; default: return z }
    }
}

public enum Axis: Int, Sendable { case x = 0, y, z }

/// An RGB colour in 0...1.
public struct FigureColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 255) / 255
        g = Double((hex >> 8) & 255) / 255
        b = Double(hex & 255) / 255
    }
    public static func mix(_ a: FigureColor, _ b: FigureColor, _ t: Double) -> FigureColor {
        FigureColor(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
    public static let ink = FigureColor(hex: 0x2B2118)
    public static let shadowBlue = FigureColor(hex: 0x4A5C9A)
    public static let paper = FigureColor(hex: 0xF6EEDC)
}

/// Seeded hash noise: the same inputs give the same number on every platform (32-bit integer maths only),
/// which is what lets the web port draw the same wobble.
public enum FigureNoise {
    public static func hash(_ a: UInt32, _ b: UInt32, _ c: UInt32 = 0) -> UInt32 {
        var h = a &* 0x9E37_79B1
        h ^= (b &+ 0x7F4A_7C15) &* 0x85EB_CA6B
        h ^= (c &+ 0x1B87_3593) &* 0xC2B2_AE35
        h ^= h >> 15
        h = h &* 0x2C1B_3C6D
        h ^= h >> 12
        h = h &* 0x297A_2D39
        h ^= h >> 15
        return h
    }
    /// A number in [-1, 1) from the hash.
    public static func signed(_ a: UInt32, _ b: UInt32, _ c: UInt32 = 0) -> Double {
        Double(hash(a, b, c)) / 2_147_483_648.0 - 1
    }
    /// A number in [0, 1) from the hash.
    public static func unit(_ a: UInt32, _ b: UInt32, _ c: UInt32 = 0) -> Double {
        Double(hash(a, b, c)) / 4_294_967_296.0
    }
}

/// An orthographic isometric camera that turns around the vertical axis. `pitch` defaults to true
/// isometric (35.264 degrees). Everything is projected at 1 screen unit per world unit, y down; the view
/// scales it to points.
public struct FigureCamera: Equatable, Sendable {
    public static let isoPitch = atan(1 / 2.0.squareRoot()) * 180 / Double.pi

    /// Degrees. 0 looks at the machine's front (+x) square on; 90 looks from +y.
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double = FigureCamera.isoPitch) {
        self.yaw = yaw
        self.pitch = pitch
    }

    private var t: Double { yaw * Double.pi / 180 }
    private var p: Double { pitch * Double.pi / 180 }
    /// Screen right, screen up, and the direction toward the viewer, in world space.
    public var right: Vec3 { Vec3(-sin(t), cos(t), 0) }
    public var up: Vec3 { Vec3(-sin(p) * cos(t), -sin(p) * sin(t), cos(p)) }
    public var toViewer: Vec3 { Vec3(cos(p) * cos(t), cos(p) * sin(t), sin(p)) }

    public func project(_ q: Vec3) -> Vec2 { Vec2(q.dot(right), -q.dot(up)) }
    /// Bigger is nearer the viewer.
    public func depth(_ q: Vec3) -> Double { q.dot(toViewer) }
    public func faces(_ normal: Vec3) -> Bool { normal.dot(toViewer) > 1e-9 }

    /// Rotates `q` about the vertical axis through `pivot` by `angle` radians (right-handed, z up).
    public static func rotateZ(_ q: Vec3, about pivot: Vec3, by angle: Double) -> Vec3 {
        let d = q - pivot, c = cos(angle), s = sin(angle)
        return Vec3(pivot.x + d.x * c - d.y * s, pivot.y + d.x * s + d.y * c, q.z)
    }
}

public enum FigureEase {
    public static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = a == b ? (x < a ? 0 : 1) : clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
    public static func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - clamp01(t), 3) }
    public static func easeInOutCubic(_ t: Double) -> Double {
        let u = clamp01(t)
        return u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    }
}
