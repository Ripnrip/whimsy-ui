import Foundation

/// A simple polygon in screen points (y down). Winding doesn't matter for `area`.
public struct Polygon: Equatable, Sendable {
    public var points: [Vec2]
    public init(_ points: [Vec2]) { self.points = points }

    public var isEmpty: Bool { points.count < 3 || area < 1e-9 }

    /// Absolute shoelace area.
    public var area: Double { abs(signedArea) }

    public var signedArea: Double {
        guard points.count >= 3 else { return 0 }
        var s = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            s += a.cross(b)
        }
        return s / 2
    }

    /// Area centroid (falls back to the vertex mean for degenerate polygons).
    public var centroid: Vec2 {
        let a = signedArea
        guard abs(a) > 1e-9 else {
            guard !points.isEmpty else { return .zero }
            return points.reduce(.zero, +) * (1 / Double(points.count))
        }
        var c = Vec2.zero
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count], k = p.cross(q)
            c += (p + q) * k
        }
        return c * (1 / (6 * a))
    }

    public func translated(by d: Vec2) -> Polygon { Polygon(points.map { $0 + d }) }

    /// Sutherland–Hodgman against one half-plane: keeps points where `side(p) >= 0`.
    public func clipped(keeping side: (Vec2) -> Double) -> Polygon {
        guard points.count >= 3 else { return Polygon([]) }
        var out: [Vec2] = []
        for i in points.indices {
            let cur = points[i], prev = points[(i + points.count - 1) % points.count]
            let dc = side(cur), dp = side(prev)
            if dc >= 0 {
                if dp < 0 { out.append(prev + (cur - prev) * (dp / (dp - dc))) }
                out.append(cur)
            } else if dp >= 0 {
                out.append(prev + (cur - prev) * (dp / (dp - dc)))
            }
        }
        return Polygon(out)
    }

    /// A rounded rectangle sampled into a polygon, so it can be folded and clipped.
    public static func roundedRect(center c: Vec2, width w: Double, height h: Double,
                                   cornerRadius r: Double, segments: Int = 6) -> Polygon {
        let r = max(0, min(r, w / 2, h / 2)), n = max(segments, 1)
        // Corner centres clockwise from top-right (y down), each with its starting angle.
        let corners: [(Vec2, Double)] = [
            (Vec2(c.x + w / 2 - r, c.y - h / 2 + r), -.pi / 2),
            (Vec2(c.x + w / 2 - r, c.y + h / 2 - r), 0),
            (Vec2(c.x - w / 2 + r, c.y + h / 2 - r), .pi / 2),
            (Vec2(c.x - w / 2 + r, c.y - h / 2 + r), .pi),
        ]
        var pts: [Vec2] = []
        for (cc, a0) in corners {
            for k in 0...n { pts.append(cc + Vec2.unit(a0 + Double(k) / Double(n) * .pi / 2) * r) }
        }
        return Polygon(pts)
    }
}

/// The crease: the perpendicular bisector of grab → finger. Everything on the grab side of
/// it is lifted and reflected across it, the way a sticker corner lands when you peel it.
public struct FoldLine: Equatable, Sendable {
    /// Midpoint of grab → finger.
    public var point: Vec2
    /// Unit normal pointing from the grab toward the finger (the peel direction).
    public var normal: Vec2

    public init?(grab: Vec2, finger: Vec2) {
        let d = finger - grab
        guard d.length > 1e-9 else { return nil }
        point = Vec2.lerp(grab, finger, 0.5)
        normal = d.normalized
    }

    /// Unit direction along the crease.
    public var tangent: Vec2 { normal.perpendicular }

    /// Positive on the finger side, negative on the grab (lifted) side.
    public func signedDistance(_ p: Vec2) -> Double { (p - point).dot(normal) }

    /// Mirror image across the crease.
    public func reflect(_ p: Vec2) -> Vec2 { p - normal * (2 * signedDistance(p)) }
}

/// One frame of a peel.
public struct PeelState: Equatable, Sendable {
    /// The part still stuck down (front face).
    public var flat: Polygon
    /// The lifted part in its original place, before folding (what the flap covered).
    public var lifted: Polygon
    /// The lifted part reflected across the crease: where the back face is drawn.
    public var flap: Polygon
    public var fold: FoldLine?
    /// Where the crease crosses the sticker (nil when nothing is lifted).
    public var crease: (Vec2, Vec2)? { _crease.map { ($0[0], $0[1]) } }
    /// Lifted area ÷ sticker area, 0…1.
    public var fraction: Double
    private var _crease: [Vec2]?

    public static func == (a: PeelState, b: PeelState) -> Bool {
        a.flat == b.flat && a.flap == b.flap && a.fold == b.fold && a.fraction == b.fraction
    }

    public static func flat(_ shape: Polygon) -> PeelState {
        PeelState(flat: shape, lifted: Polygon([]), flap: Polygon([]), fold: nil, fraction: 0, _crease: nil)
    }

    /// Folds `shape` for a finger that grabbed at `grab` and is now at `finger`.
    public static func peel(_ shape: Polygon, grab: Vec2, finger: Vec2) -> PeelState {
        guard let fold = FoldLine(grab: grab, finger: finger), shape.area > 0 else { return .flat(shape) }
        // Only drags that head into the sticker peel it; pulling a corner outward lifts nothing.
        guard fold.normal.dot(shape.centroid - grab) > 0 else { return .flat(shape) }
        let flat = shape.clipped { fold.signedDistance($0) }
        let lifted = shape.clipped { -fold.signedDistance($0) }
        guard !lifted.isEmpty else { return .flat(shape) }
        let flap = Polygon(lifted.points.reversed().map { fold.reflect($0) })
        let fraction = min(max(lifted.area / shape.area, 0), 1)
        return PeelState(flat: flat, lifted: lifted, flap: flap, fold: fold, fraction: fraction,
                         _crease: creaseSegment(of: lifted, fold: fold).map { [$0.0, $0.1] })
    }

    /// The longest edge of `poly` lying on the crease.
    static func creaseSegment(of poly: Polygon, fold: FoldLine) -> (Vec2, Vec2)? {
        var best: (Vec2, Vec2)? = nil, bestLen = 1e-9
        let p = poly.points
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            if abs(fold.signedDistance(a)) < 1e-7, abs(fold.signedDistance(b)) < 1e-7, a.distance(to: b) > bestLen {
                best = (a, b); bestLen = a.distance(to: b)
            }
        }
        return best
    }
}
