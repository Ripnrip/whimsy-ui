import Foundation

/// One captured brush sample: where, when (seconds), and the brush width there (points).
public struct StrokePoint: Equatable, Sendable {
    public var position: Vec2
    public var time: Double
    public var width: Double
    public init(position: Vec2, time: Double, width: Double) {
        self.position = position; self.time = time; self.width = width
    }
}

/// Pressure-ish width from speed: slow strokes lay down a fat, loaded brush; fast flicks go thin.
public enum StrokeWidth {
    public static let maxWidth = 34.0
    public static let minWidth = 14.0
    /// At or above this speed (pt/s) the brush is at its thinnest.
    public static let fastSpeed = 1400.0
    /// Each new sample moves this fraction of the way to the target width (smooths jitter).
    public static let smoothing = 0.35

    public static func target(speed: Double) -> Double {
        maxWidth - (maxWidth - minWidth) * WhimsyMath.smoothstep(0, fastSpeed, max(speed, 0))
    }

    public static func next(previous: Double, speed: Double) -> Double {
        previous + (target(speed: speed) - previous) * smoothing
    }
}

/// Ramer–Douglas–Peucker, width-aware: a point is dropped only if it lies within `epsilon` of the
/// chord *and* its width is within `widthTolerance` of the width interpolated along the chord, so
/// the speed-driven width profile survives simplification. Times ride along with the kept points.
public enum StrokeSimplifier {
    public static let epsilon = 0.75
    public static let widthTolerance = 1.0

    public static func distance(_ p: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a, l2 = ab.dot(ab)
        guard l2 > 0 else { return (p - a).length }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return (p - (a + ab * t)).length
    }

    public static func simplify(_ pts: [StrokePoint], epsilon: Double = epsilon) -> [StrokePoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            var best = -1.0, idx = lo
            let a = pts[lo].position, ab = pts[hi].position - a, l2 = ab.dot(ab)
            for i in (lo + 1)..<hi {
                let d = distance(pts[i].position, toSegment: a, pts[hi].position)
                let t = l2 > 0 ? max(0, min(1, (pts[i].position - a).dot(ab) / l2)) : 0
                let dw = abs(pts[i].width - (pts[lo].width + (pts[hi].width - pts[lo].width) * t))
                // Scale the width error into the same units so one test covers both.
                let e = max(d, dw * epsilon / widthTolerance)
                if e > best { best = e; idx = i }
            }
            if best > epsilon {
                keep[idx] = true
                stack.append((lo, idx)); stack.append((idx, hi))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }
}

/// One bristle line inside a stroke (for the wet impasto height field). Drawn as a single
/// constant-width polyline so its alpha doesn't stack up at the joints.
public struct Bristle: Equatable, Sendable {
    public var points: [Vec2]
    public var width: Double
    public var alpha: Double
}

/// A brush stroke: samples spaced at least `minSpacing` apart, simplified when it ends.
public struct PaintStroke: Equatable, Sendable {
    public static let minSpacing = 2.0
    public static let bristleCount = 7
    /// Bristles are this fraction of the mean brush width (wide enough to overlap their neighbours).
    public static let bristleWidth = 0.26

    public let index: Int
    public private(set) var points: [StrokePoint] = []
    /// Seconds (model time) the stroke ended; nil while the finger is still down.
    public private(set) var endTime: Double?
    /// Speed (pt/s) at the last sample.
    public private(set) var speed = 0.0

    public init(index: Int) { self.index = index }

    public var isActive: Bool { endTime == nil }
    public var startTime: Double { points.first?.time ?? 0 }

    /// Adds a sample unless it's closer than `minSpacing` to the last one. Returns whether it was kept.
    @discardableResult
    public mutating func add(_ p: Vec2, at t: Double) -> Bool {
        guard isActive, p.x.isFinite, p.y.isFinite else { return false }
        guard let last = points.last else {
            points.append(StrokePoint(position: p, time: t, width: StrokeWidth.maxWidth))
            return true
        }
        let d = (p - last.position).length
        guard d >= Self.minSpacing else { return false }
        let dt = max(t - last.time, 1.0 / 240)
        speed = d / dt
        points.append(StrokePoint(position: p, time: max(t, last.time), width: StrokeWidth.next(previous: last.width, speed: speed)))
        return true
    }

    public mutating func end(at t: Double) {
        guard isActive else { return }
        endTime = max(t, points.last?.time ?? t)
        points = StrokeSimplifier.simplify(points)
    }

    /// 0 while wet (and while still being painted), 1 when dry. `instant` = Reduce Motion.
    public func dryProgress(at t: Double, duration: Double, instant: Bool = false) -> Double {
        guard let e = endTime else { return 0 }
        if instant || duration <= 0 { return 1 }
        return WhimsyMath.clamp01((t - e) / duration)
    }

    /// Unit direction of travel near the end of the stroke (over the last ~8 pt), or zero.
    public var direction: Vec2 {
        guard let last = points.last else { return .zero }
        for p in points.reversed().dropFirst() where (last.position - p.position).length >= 8 {
            return (last.position - p.position).normalized
        }
        guard let first = points.first else { return .zero }
        return (last.position - first.position).normalized
    }

    /// Unit normals per point (perpendicular to the local tangent).
    public var normals: [Vec2] {
        let n = points.count
        return (0..<n).map { i in
            let a = points[max(i - 1, 0)].position, b = points[min(i + 1, n - 1)].position
            let t = (b - a).normalized
            return t == .zero ? Vec2(0, 1) : t.perpendicular
        }
    }

    /// Seeded bristle lines spread across the brush width, each with its own paint load.
    public var bristles: [Bristle] {
        var rng = SeededRandom(seed: 0xB215 &+ UInt64(index))
        let ns = normals
        let meanWidth = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.width } / Double(points.count)
        return (0..<Self.bristleCount).map { k in
            let alpha = rng.uniform(0.35...0.75)
            let offset = ((Double(k) + 0.5) / Double(Self.bristleCount) - 0.5) * 0.86 + rng.uniform(-0.03...0.03)
            let pts = points.indices.map { i in points[i].position + ns[i] * (offset * points[i].width) }
            return Bristle(points: pts, width: meanWidth * Self.bristleWidth, alpha: alpha)
        }
    }
}
