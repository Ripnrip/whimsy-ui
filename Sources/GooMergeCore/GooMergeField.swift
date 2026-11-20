import Foundation

/// A circle in the metaball field.
public struct GooCircle: Equatable, Sendable {
    public var center: Vec2
    public var radius: Double

    public init(center: Vec2, radius: Double) {
        self.center = center
        self.radius = radius
    }
}

/// Ring layout and the two field functions the merge is judged by.
/// `sdf` is a polynomial smooth-minimum of the circle distances.
/// `metaball` is the classic sum of radius² / (distance² + epsilon).
public enum GooMergeField {
    public static func radius(for value: Double) -> Double {
        let t = min(1, max(0, value.isFinite ? value : 0))
        return GooMergeTuning.minRadius + (GooMergeTuning.maxRadius - GooMergeTuning.minRadius) * t
    }

    /// Drop `index` on the ring. Index 0 sits at 12 o'clock; the rest step clockwise
    /// (y grows downward).
    public static func ringPoint(index: Int, count: Int) -> Vec2 {
        let n = max(count, 1)
        let angle = -Double.pi / 2 + Double(index) * (2 * Double.pi / Double(n))
        return GooMergeTuning.well + Vec2(cos(angle), sin(angle)) * GooMergeTuning.ringRadius
    }

    /// Quilez polynomial smooth minimum. `k <= 0` is a plain min.
    public static func smoothMin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        if !(k > 0) { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    public static func sdf(at point: Vec2, circles: [GooCircle]) -> Double {
        guard let first = circles.first else { return .greatestFiniteMagnitude }
        var s = point.distance(to: first.center) - first.radius
        let k = GooMergeTuning.smoothK
        for circle in circles.dropFirst() {
            let d = point.distance(to: circle.center) - circle.radius
            s = smoothMin(s, d, k)
        }
        return s
    }

    public static func metaball(at point: Vec2, circles: [GooCircle]) -> Double {
        let eps = GooMergeTuning.fieldEpsilon
        var sum = 0.0
        for circle in circles {
            let dx = point.x - circle.center.x
            let dy = point.y - circle.center.y
            sum += (circle.radius * circle.radius) / (dx * dx + dy * dy + eps)
        }
        return sum
    }

    /// 0 at the resting ring field, 1 when every circle is stacked on the well.
    public static func mergeProgress(logical: [GooCircle], restInside: Double, stackedInside: Double, restMeta: Double, stackedMeta: Double) -> Double {
        let inside = -sdf(at: GooMergeTuning.well, circles: logical)
        let meta = metaball(at: GooMergeTuning.well, circles: logical)
        let spanInside = stackedInside - restInside
        let spanMeta = stackedMeta - restMeta
        let a = spanInside == 0 ? 0 : (inside - restInside) / spanInside
        let b = spanMeta == 0 ? 0 : (meta - restMeta) / spanMeta
        return min(1, max(0, min(a, b)))
    }
}
