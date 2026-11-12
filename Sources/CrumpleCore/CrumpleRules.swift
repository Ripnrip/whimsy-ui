import Foundation

/// A rectangle in screen space. `y` grows downward, matching `Vec2`.
public struct CrumpleRect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }

    /// A zero-area rect contains nothing, so a missing bin cannot arm the zone latch.
    public func contains(_ point: Vec2) -> Bool {
        guard width > 0, height > 0 else { return false }
        return point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// One paper colour. Shade multiplies it; the mesh does not use a three-tone ink.
public struct CrumpleColor: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func scaled(_ t: Double) -> CrumpleColor {
        CrumpleColor(r * t, g * t, b * t)
    }
}

/// Thresholds shared by the core, the tests, and the HTML port.
public struct CrumpleRules: Equatable, Sendable {
    /// Release at or above this progress commits, even outside the bin.
    public var commitProgress = 0.8
    /// A shared edge creases once its fold angle reaches this many radians.
    public var creaseAngle = 0.35
    /// Quads across the card. Two triangles each, so 5 × 4 is 40 facets.
    public var columns = 5
    public var rows = 4
    /// Settled ball radius, as a fraction of the card's shorter side.
    public var ballRadiusFraction = 1.0 / 6.0
    /// How far seeded vertex height runs, in ball radii, at shape 1.
    public var buckle = 2.0
    public var seed: UInt64 = 34
    /// Light in mesh space (x right, y down, z toward the viewer), before normalizing.
    public var lightX = 0.45
    public var lightY = 0.55
    public var lightZ = 0.70
    public var paper = CrumpleColor(0.96, 0.93, 0.86)
    /// Unlit paper keeps this much of `paper`; full light keeps all of it.
    public var ambient = 0.22
    public var springStiffness = 380.0
    public var springDamping = 0.4
    public var calmStiffness = 520.0
    public var calmDamping = 1.0
    /// Full-motion flight, seconds.
    public var tossDuration = 0.5
    /// Reduce Motion commit, seconds. No arc and no lid.
    public var reduceMotionDuration = 0.35
    /// Bezier control offset, as a fraction of the toss segment.
    public var tossControl = 0.35
    /// View-side haptic coalesce. The core log does not use this to drop creases.
    public var hapticInterval = 0.12

    public init() {}

    public var vertexColumns: Int { columns + 1 }
    public var vertexRows: Int { rows + 1 }
    public var vertexCount: Int { vertexColumns * vertexRows }
    public var triangleCount: Int { columns * rows * 2 }
}
