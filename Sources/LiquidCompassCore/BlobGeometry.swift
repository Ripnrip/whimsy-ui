import Foundation

/// The liquid blob's outline: a circle that bulges into a rounded lobe toward `angle`, draws
/// in a little on the far side, and slides its centre toward the lobe (the "lean"). The outline
/// is rescaled so its area always equals the undeformed circle's: the liquid's volume is
/// conserved however hard it stretches.
public struct BlobGeometry: Equatable, Sendable {
    /// Radius of the resting (round) blob, points.
    public var radius: Double
    /// Outline vertices (closed polygon; renderers smooth it).
    public var samples: Int
    /// Exponent on the lobe's cos-profile: higher = narrower, pointier tip.
    public var lobeSharpness: Double
    /// How much the far side pulls in, as a fraction of the stretch.
    public var backPull: Double
    /// How far the centre slides toward the lobe, as a fraction of `stretch · radius`.
    public var leanFraction: Double

    public init(radius: Double = 68, samples: Int = 120, lobeSharpness: Double = 3.0,
                backPull: Double = 0.3, leanFraction: Double = 0.22) {
        self.radius = radius
        self.samples = max(8, samples)
        self.lobeSharpness = lobeSharpness
        self.backPull = backPull
        self.leanFraction = leanFraction
    }

    public static let `default` = BlobGeometry()

    /// Unnormalised radial profile at outline angle `phi` for a lobe at `angle` (degrees).
    public func profile(phi: Double, angle: Double, stretch: Double) -> Double {
        let c = cos((phi - angle) * .pi / 180)
        let front = pow(max(c, 0), lobeSharpness)
        let back = pow(max(-c, 0), 2)
        return 1 + stretch * front - stretch * backPull * back
    }

    /// Offset of the blob's centre from the anchor, points.
    public func lean(angle: Double, stretch: Double) -> Vec2 {
        CompassMath.screenVector(degrees: angle) * (stretch * radius * leanFraction)
    }

    /// The outline for a lobe at screen angle `angle` (degrees, 0 = up, clockwise) and
    /// `stretch` (0 = round; ~0.4–0.8 typical; negative values are treated as 0), around
    /// `center`. Vertex k sits at outline angle 360·k/samples, starting straight up.
    public func outline(angle: Double, stretch: Double, center: Vec2 = .zero) -> [Vec2] {
        let s = stretch.isFinite ? max(stretch, 0) : 0
        let n = samples
        let radii = (0..<n).map { profile(phi: 360 * Double($0) / Double(n), angle: angle, stretch: s) }
        // Shoelace area of the unit-scale polygon vs. the undeformed polygon (same n), so s = 0
        // reproduces the circle exactly and any stretch keeps the same area.
        let wedge = 0.5 * sin(2 * .pi / Double(n))
        var area = 0.0
        for k in 0..<n { area += wedge * radii[k] * radii[(k + 1) % n] }
        let reference = wedge * Double(n)
        let scale = radius * (reference / area).squareRoot()
        let c = center + lean(angle: angle, stretch: s)
        return (0..<n).map { k in
            c + CompassMath.screenVector(degrees: 360 * Double(k) / Double(n)) * (radii[k] * scale)
        }
    }

    /// Shoelace area of a closed polygon (absolute value).
    public static func area(of polygon: [Vec2]) -> Double {
        guard polygon.count > 2 else { return 0 }
        var a = 0.0
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            a += p.cross(q)
        }
        return abs(a) / 2
    }

    /// Area centroid of a closed polygon.
    public static func centroid(of polygon: [Vec2]) -> Vec2 {
        guard polygon.count > 2 else { return polygon.first ?? .zero }
        var a = 0.0, cx = 0.0, cy = 0.0
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let w = p.cross(q)
            a += w; cx += (p.x + q.x) * w; cy += (p.y + q.y) * w
        }
        guard abs(a) > 1e-12 else { return polygon[0] }
        return Vec2(cx / (3 * a), cy / (3 * a))
    }
}
