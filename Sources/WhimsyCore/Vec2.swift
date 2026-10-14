import Foundation

/// Minimal 2D vector shared by every whimsy core (points, y down on screen).
/// Kept free of CoreGraphics so the cores build and test on Linux.
public struct Vec2: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { a * s }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    /// z of the 3D cross product; > 0 when `o` is counter-clockwise from `self` (math orientation).
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 {
        let l = length
        return l > 0 ? self * (1 / l) : .zero
    }
    /// Perpendicular (rotated +90° in a y-down space).
    public var perpendicular: Vec2 { Vec2(-y, x) }
    public func distance(to o: Vec2) -> Double { (self - o).length }

    /// Unit vector at `angle` radians.
    public static func unit(_ angle: Double) -> Vec2 { Vec2(cos(angle), sin(angle)) }

    /// Linear interpolation.
    public static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    /// Shortest distance from `self` to segment `a`–`b`.
    public func distance(toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let lengthSquared = ab.dot(ab)
        guard lengthSquared > 0 else { return distance(to: a) }
        let t = min(max((self - a).dot(ab) / lengthSquared, 0), 1)
        return distance(to: a + ab * t)
    }

    /// This vector scaled down (never up) so its length is at most `radius`.
    public func clamped(toRadius radius: Double) -> Vec2 {
        let l = length
        guard l > radius, l > 0 else { return self }
        return self * (radius / l)
    }
}
