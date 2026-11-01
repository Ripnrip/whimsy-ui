import Foundation

/// The hand-inked look: how wobbly, how heavy the lines are, and where the light is.
public struct FigureStyle: Equatable, Sendable {
    /// 0 is ruler-straight, 1 is properly shaky.
    public var wobble: Double
    public var seed: UInt32
    /// The light in the viewer's frame (right, up, toward the viewer), so the lit side always faces the viewer.
    public var light = Vec3(0.45, 0.55, 0.70)

    public init(wobble: Double = 0.5, seed: UInt32 = 7) {
        self.wobble = FigureEase.clamp01(wobble)
        self.seed = seed
    }

    // Wobble amplitudes, in world units at wobble = 1.
    public static let vertexAmp = 0.6
    public static let edgeAmp = 0.8
    public static let ringAmp = 0.7
    // Line weights, in the same units (the view scales them with the figure).
    public static let silhouetteWidth = 0.9
    public static let creaseWidth = 0.5
    public static let hatchWidth = 0.2
    public static let lineVariation = 0.25

    /// The light as a world-space unit vector for this camera.
    public func lightDirection(_ cam: FigureCamera) -> Vec3 {
        (cam.right * light.x + cam.up * light.y + cam.toViewer * light.z).normalized
    }
}

/// Three flat tones chosen by how a face meets the light, blended over a narrow band so a face that turns
/// past a threshold while the figure rotates fades between tones rather than snapping.
public enum FigureTone {
    public static let high = 0.62
    public static let low = 0.12
    public static let band = 0.12

    public static func color(dot d: Double, palette p: FigurePalette) -> FigureColor {
        let a = FigureEase.smoothstep(high - band, high + band, d)
        let b = FigureEase.smoothstep(low - band, low + band, d)
        if a >= 1 { return p.light }
        if b <= 0 { return p.dark }
        return a > 0 ? .mix(p.mid, p.light, a) : .mix(p.dark, p.mid, b)
    }

    /// How much hatching a face gets: none when well lit, full when turned away.
    public static func hatchDensity(dot d: Double) -> Double {
        1 - FigureEase.smoothstep(-0.15, 0.55, d)
    }
}

public enum FigureHatch {
    /// Parallel hatch lines across `polygon` (screen units) at `angle` radians, `spacing` apart. Lines sit on a global grid
    /// (multiples of `spacing`), so neighbouring faces hatched with the same settings line up. Returns endpoint pairs.
    public static func segments(polygon: [Vec2], angle: Double, spacing: Double, key: UInt32 = 0, jitter: Double = 0) -> [Vec2] {
        guard polygon.count >= 3, spacing > 0 else { return [] }
        let d = Vec2(cos(angle), sin(angle))
        let nrm = Vec2(-sin(angle), cos(angle))
        let ts = polygon.map { $0.dot(nrm) }
        let us = polygon.map { $0.dot(d) }
        let tMin = ts.min()!, tMax = ts.max()!
        var out: [Vec2] = []
        var k = Int((tMin / spacing).rounded(.up))
        let kEnd = Int((tMax / spacing).rounded(.down))
        while k <= kEnd {
            let t = Double(k) * spacing
            var cuts: [Double] = []
            for i in 0..<polygon.count {
                let j = (i + 1) % polygon.count
                let ti = ts[i], tj = ts[j]
                if (ti <= t && t < tj) || (tj <= t && t < ti) {
                    cuts.append(us[i] + (us[j] - us[i]) * (t - ti) / (tj - ti))
                }
            }
            cuts.sort()
            var c = 0
            while c + 1 < cuts.count {
                var u0 = cuts[c], u1 = cuts[c + 1]
                if jitter > 0 {
                    let kk = UInt32(truncatingIfNeeded: k)
                    u0 += FigureNoise.signed(key, kk, 11) * jitter
                    u1 += FigureNoise.signed(key, kk, 12) * jitter
                }
                if u1 > u0 { out.append(nrm * t + d * u0); out.append(nrm * t + d * u1) }
                c += 2
            }
            k += 1
        }
        return out
    }
}

/// A flat cast shadow on the ground.
public enum FigureShadow {
    /// Projects world points onto the ground along a shadow direction that always falls toward the lower left of the
    /// screen, and returns the convex hull of the result as a screen polygon.
    public static func hull(of points: [Vec3], camera cam: FigureCamera) -> [Vec2] {
        let vh = Vec3(cos(cam.yaw * Double.pi / 180), sin(cam.yaw * Double.pi / 180), 0)
        let g = cam.right * -0.55 + vh * 0.3
        let pts = points.map { cam.project(Vec3($0.x + g.x * $0.z * 0.5, $0.y + g.y * $0.z * 0.5, 0)) }
        return convexHull(pts)
    }

    public static func convexHull(_ input: [Vec2]) -> [Vec2] {
        let pts = input.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard pts.count > 2 else { return pts }
        func cross(_ o: Vec2, _ a: Vec2, _ b: Vec2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for p in pts {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in pts.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    public static func contains(_ hull: [Vec2], _ p: Vec2, tolerance: Double = 1e-9) -> Bool {
        guard hull.count >= 3 else { return false }
        var sign = 0.0
        for i in 0..<hull.count {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            let c = (b - a).cross(p - a)
            if abs(c) <= tolerance { continue }
            if sign == 0 { sign = c > 0 ? 1 : -1 } else if (c > 0) != (sign > 0) { return false }
        }
        return true
    }
}
