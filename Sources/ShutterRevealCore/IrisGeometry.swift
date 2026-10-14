import Foundation
import WhimsyCore

/// One iris blade: the exterior wedge at aperture vertex `index`, bounded by the extension of
/// the previous aperture edge (`trailing`) and the aperture edge leaving this vertex
/// (`leading`). Because the aperture is a convex regular polygon, the N wedges tile the whole
/// plane outside the aperture exactly, with no gaps and no overlaps.
public struct Blade: Equatable, Sendable {
    public let index: Int
    /// The blade's tip: an aperture vertex. All tips meet at the centre when fully closed.
    public let apex: Vec2
    /// Unit direction of the seam with the previous blade (the previous edge, extended).
    public let trailing: Vec2
    /// Unit direction of the aperture edge (and, beyond the next vertex, the seam with the
    /// next blade).
    public let leading: Vec2
    /// Length of the visible aperture edge (apex → next vertex).
    public let edgeLength: Double
    /// Convex, counter-clockwise kite that contains the wedge out to `reach`: apex, far
    /// point on `trailing`, far point on the bisector, far point on `leading`.
    public let polygon: [Vec2]
    /// Angle of the blade's bisector (radians), handy for per-blade shading.
    public let angle: Double

    /// Strict containment (boundary points count as inside).
    public func contains(_ p: Vec2, tolerance: Double = 1e-9) -> Bool {
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if (b - a).cross(p - a) < -tolerance { return false }
        }
        return true
    }

    /// The end of the visible aperture edge.
    public var edgeEnd: Vec2 { apex + leading * edgeLength }
}

/// Geometry of an N-blade iris over a circular region (centre + radius) that must be fully
/// covered when closed and fully clear when open.
///
/// The aperture is a regular N-gon whose apothem (inscribed radius) grows linearly with
/// progress from 0 (closed, every blade tip at the centre) to `radius * openMargin`
/// (open: the inscribed circle contains the whole region). The polygon also rotates by
/// `twist` over the same range, so the blades swirl as they open.
public struct IrisGeometry: Equatable, Sendable {
    public let bladeCount: Int
    public let center: Vec2
    /// Radius of the region to cover. For a rectangle, use half its diagonal.
    public let radius: Double
    /// Open apothem as a multiple of `radius`; must be > 1 for a fully clear open state.
    public let openMargin: Double
    /// Rotation (radians) added between closed and open.
    public let twist: Double
    /// Rotation at progress 0.
    public let baseAngle: Double

    public init(bladeCount: Int = 6, center: Vec2 = .zero, radius: Double,
                openMargin: Double = 1.04, twist: Double = 0.9, baseAngle: Double = -.pi / 2) {
        self.bladeCount = max(bladeCount, 3)
        self.center = center
        self.radius = max(radius, 0)
        self.openMargin = max(openMargin, 1)
        self.twist = twist
        self.baseAngle = baseAngle
    }

    /// Convenience for a rectangle of `width` × `height` (origin top-left): covers its circumcircle.
    public init(bladeCount: Int = 6, width: Double, height: Double, twist: Double = 0.9) {
        self.init(bladeCount: bladeCount, center: Vec2(width / 2, height / 2),
                  radius: (width * width + height * height).squareRoot() / 2, twist: twist)
    }

    /// Half the exterior angle, π/N.
    var halfExterior: Double { .pi / Double(bladeCount) }

    /// Inscribed radius of the aperture. Negative progress clamps to closed; > 1 (spring overshoot) opens further.
    public func apothem(progress: Double) -> Double {
        (progress.isFinite ? max(progress, 0) : 0) * radius * openMargin
    }

    /// Circumradius of the aperture (centre → vertex).
    public func circumradius(progress: Double) -> Double {
        apothem(progress: progress) / cos(halfExterior)
    }

    /// Rotation of the aperture polygon at `progress`.
    public func rotation(progress: Double) -> Double {
        baseAngle + twist * (progress.isFinite ? progress : 0)
    }

    /// Angle of vertex `k` for a polygon rotated by `rotation`.
    func vertexAngle(_ k: Int, rotation: Double) -> Double {
        rotation + 2 * .pi * Double(k) / Double(bladeCount)
    }

    /// Unit direction of edge `k` (vertex k → k+1), computed analytically so it's defined even when closed.
    public func edgeDirection(_ k: Int, rotation: Double) -> Vec2 {
        .unit(vertexAngle(k, rotation: rotation) + .pi / 2 + halfExterior)
    }

    public func apertureVertices(progress: Double, rotation: Double? = nil) -> [Vec2] {
        let r = circumradius(progress: progress), rot = rotation ?? self.rotation(progress: progress)
        return (0..<bladeCount).map { center + .unit(vertexAngle($0, rotation: rot)) * r }
    }

    /// Whether `p` lies inside the open aperture (strictly inside every edge).
    public func isInsideAperture(_ p: Vec2, progress: Double, rotation: Double? = nil) -> Bool {
        let vertices = apertureVertices(progress: progress, rotation: rotation)
        guard apothem(progress: progress) > 0 else { return false }
        for k in vertices.indices {
            let a = vertices[k], b = vertices[(k + 1) % vertices.count]
            if (b - a).cross(p - a) <= 0 { return false }
        }
        return true
    }

    /// Blade `index` at `progress`. Pass `rotation` to override it (e.g. for motion-blur ghosts).
    public func blade(_ index: Int, progress: Double, rotation: Double? = nil) -> Blade {
        let n = bladeCount
        let j = ((index % n) + n) % n
        let rot = rotation ?? self.rotation(progress: progress)
        let r = circumradius(progress: progress)
        let apex = center + .unit(vertexAngle(j, rotation: rot)) * r
        let leading = edgeDirection(j, rotation: rot)
        let trailing = edgeDirection(j - 1, rotation: rot)
        let edgeLength = 2 * r * sin(halfExterior)
        // Far enough to reach any point of the covered disc from the apex, with margin.
        let reach = (apex.distance(to: center) + radius) * 1.1 + 1
        let exterior = 2 * halfExterior
        let bisectorAngle = atan2(trailing.y, trailing.x) + exterior / 2
        let polygon = [
            apex,
            apex + trailing * reach,
            apex + Vec2.unit(bisectorAngle) * (reach / cos(exterior / 2)),
            apex + leading * reach,
        ]
        return Blade(index: j, apex: apex, trailing: trailing, leading: leading,
                     edgeLength: edgeLength, polygon: polygon, angle: bisectorAngle)
    }

    public func blades(progress: Double, rotation: Double? = nil) -> [Blade] {
        (0..<bladeCount).map { blade($0, progress: progress, rotation: rotation) }
    }

    /// Indices of the blades containing `p` (boundaries count, so seams report two).
    public func coveringBlades(_ p: Vec2, progress: Double, rotation: Double? = nil) -> [Int] {
        blades(progress: progress, rotation: rotation).filter { $0.contains(p) }.map(\.index)
    }

    public func isCovered(_ p: Vec2, progress: Double) -> Bool {
        !coveringBlades(p, progress: progress).isEmpty
    }

    /// Fraction of a sampling grid over the covered disc that is hidden by blades.
    public func coveredFraction(progress: Double, samplesPerAxis: Int = 48) -> Double {
        let bladeList = blades(progress: progress)
        var inside = 0, covered = 0
        let n = max(samplesPerAxis, 2)
        for iy in 0..<n {
            for ix in 0..<n {
                let p = center + Vec2((Double(ix) + 0.5) / Double(n) * 2 - 1, (Double(iy) + 0.5) / Double(n) * 2 - 1) * radius
                guard p.distance(to: center) <= radius else { continue }
                inside += 1
                if bladeList.contains(where: { $0.contains(p) }) { covered += 1 }
            }
        }
        return inside == 0 ? 0 : Double(covered) / Double(inside)
    }
}
