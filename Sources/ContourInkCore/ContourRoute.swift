import Foundation

/// The red dot's route: a smooth trail from the outermost ring in to the peak, crossing every ring on the way.
public struct ContourRoute: Equatable, Sendable {
    /// Where the trail meets each ring, then the peak.
    public let waypoints: [Vec2]
    /// The smooth polyline through the waypoints (Catmull-Rom, `subdivisions` points per leg).
    public let points: [Vec2]
    public let cumulative: [Double]

    public static let subdivisions = 10
    /// The trail starts on the outermost ring at about this angle (down and to the left) ...
    public static let baseAngle = 2.35
    /// ... moving this much round each ring, with every other ring pushed on by `switchback` for hairpin turns.
    public static let angleStep = 0.28
    public static let switchback = 0.5

    public var length: Double { cumulative.last ?? 0 }
    public var start: Vec2 { points[0] }
    public var end: Vec2 { points[points.count - 1] }

    public static func make(map: ContourMap) -> ContourRoute {
        let jitter = (ContourHash.unit(map.seed, 500) - 0.5) * 0.4
        var wp: [Vec2] = []
        for (k, ring) in map.rings.enumerated() {
            let a = baseAngle + jitter + angleStep * Double(k) + (k % 2 == 1 ? switchback : 0)
            wp.append(ring.point(atAngle: a))
        }
        wp.append(map.peak)
        // Catmull-Rom through the waypoints, the ends doubled.
        var pts: [Vec2] = []
        for i in 0..<(wp.count - 1) {
            let p0 = wp[max(i - 1, 0)], p1 = wp[i], p2 = wp[i + 1], p3 = wp[min(i + 2, wp.count - 1)]
            for s in 0..<subdivisions {
                let t = Double(s) / Double(subdivisions)
                pts.append(catmullRom(p0, p1, p2, p3, t))
            }
        }
        pts.append(wp[wp.count - 1])
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + pts[i].distance(to: pts[i - 1])) }
        return ContourRoute(waypoints: wp, points: pts, cumulative: cum)
    }

    static func catmullRom(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ t: Double) -> Vec2 {
        let t2 = t * t, t3 = t2 * t
        let a = p1 * 2
        let b = (p2 - p0) * t
        let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
        let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
        return (a + b + c + d) * 0.5
    }

    /// The dot's position after `fraction` of the route by arc length.
    public func point(at fraction: Double) -> Vec2 {
        let n = points.count
        guard n > 1, length > 0 else { return points.first ?? .zero }
        let target = (fraction.isNaN ? 0 : WhimsyMath.clamp01(fraction)) * length
        var i = 0
        while i < n - 2 && cumulative[i + 1] < target { i += 1 }
        let seg = cumulative[i + 1] - cumulative[i]
        let u = seg > 0 ? WhimsyMath.clamp01((target - cumulative[i]) / seg) : 0
        return Vec2.lerp(points[i], points[i + 1], u)
    }
}
