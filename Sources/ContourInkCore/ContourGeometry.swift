import Foundation

/// lowbias32, the same in Swift (wrapping UInt32) and JS (Math.imul). Used to seed every ring.
public enum ContourHash {
    public static func hash32(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x = x &* 0x7feb_352d
        x ^= x >> 15; x = x &* 0x846c_a68b
        x ^= x >> 16
        return x
    }
    /// A hash of a seed and a salt, so every ring and harmonic draws its own numbers.
    public static func value(_ seed: UInt32, _ salt: Int) -> UInt32 {
        hash32((UInt32(truncatingIfNeeded: salt) &* 0x9E37_79B1) ^ hash32(seed))
    }
    /// 0 ..< 1 from the low 24 bits.
    public static func unit(_ x: UInt32) -> Double { Double(x & 0xFF_FFFF) / 16_777_216 }
    public static func unit(_ seed: UInt32, _ salt: Int) -> Double { unit(value(seed, salt)) }
}

/// One contour line: a sine-perturbed circle, sampled as a closed polyline in unit sheet space
/// (the sheet is the square -0.5 ... 0.5, y down).
public struct ContourRing: Equatable, Sendable {
    public var index: Int
    public var center: Vec2
    public var radius: Double
    /// The angle of `points[0]`: every ring starts its stroke somewhere else.
    public var startAngle: Double
    public var amplitudes: [Double]
    public var phases: [Double]
    /// Index contours (every few rings) are drawn thicker.
    public var isIndex: Bool
    /// `ContourInkGeometry.sampleCount` points; the path closes from the last back to the first.
    public var points: [Vec2]
    /// Arc length at each point, then the full length: `points.count + 1` values, starting at 0.
    public var cumulative: [Double]

    public var length: Double { cumulative.last ?? 0 }

    /// How much the radius wobbles at `angle`: `1 + sum(amp_h * sin(h * angle + phase_h))`.
    public func radialFactor(at angle: Double) -> Double {
        var s = 0.0
        for (j, h) in ContourInkGeometry.harmonics.enumerated() {
            s += amplitudes[j] * sin(Double(h) * angle + phases[j])
        }
        return 1 + s
    }

    /// The exact point of the curve at `angle`.
    public func point(atAngle angle: Double) -> Vec2 {
        center + Vec2.unit(angle) * (radius * radialFactor(at: angle))
    }

    /// The point a pen has reached after drawing `fraction` of the ring by arc length, the way `Shape.trim(from: 0, to:)` measures it.
    public func point(at fraction: Double) -> Vec2 {
        let n = points.count
        guard n > 1, length > 0 else { return points.first ?? .zero }
        let target = (fraction.isNaN ? 0 : WhimsyMath.clamp01(fraction)) * length
        // linear scan: 120 segments
        var i = 0
        while i < n - 1 && cumulative[i + 1] < target { i += 1 }
        let a = points[i], b = points[(i + 1) % n]
        let seg = cumulative[i + 1] - cumulative[i]
        let u = seg > 0 ? WhimsyMath.clamp01((target - cumulative[i]) / seg) : 0
        return Vec2.lerp(a, b, u)
    }

    /// Whether `p` is inside the closed polyline (even-odd rule).
    public func contains(_ p: Vec2) -> Bool {
        var inside = false
        let n = points.count
        var j = n - 1
        for i in 0..<n {
            let a = points[i], b = points[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Shortest distance from `p` to the closed polyline.
    public func distance(to p: Vec2) -> Double {
        var best = Double.infinity
        let n = points.count
        for i in 0..<n { best = min(best, p.distance(toSegment: points[i], points[(i + 1) % n])) }
        return best
    }
}

/// Ring geometry: the constants, and how a set of nested contours is made.
public enum ContourInkGeometry {
    public static let minRings = 3
    public static let maxRings = 12
    public static let defaultRings = 7
    public static let defaultSeed: UInt32 = 0x30C7
    /// Points per ring.
    public static let sampleCount = 120
    /// The wobble: harmonics of the angle, and how far each can push the radius (a fraction of it).
    public static let harmonics = [2, 3, 5]
    public static let baseAmplitudes = [0.07, 0.045, 0.025]
    /// Radius of the outermost ring, and how much of it the innermost ring gives up.
    public static let outerRadius = 0.43
    public static let innerShrink = 0.84
    /// Where the innermost ring is centred (the peak). Rings drift toward it: centre = peak * (k / (n - 1)) ^ centerEase.
    public static let peak = Vec2(0.10, -0.075)
    public static let centerEase = 1.5
    /// Rings must stay at least this far apart (unit space). The wobble is turned down until they do.
    public static let minGapFloor = 0.01
    /// The wobble scales tried, in order, until the gap is wide enough; the last (0) is plain circles.
    public static let wobbleScales = [1.0, 0.85, 0.7, 0.55, 0.4, 0.25, 0.1, 0.0]
    /// Every `indexEvery`-th ring, from the outermost, is an index contour.
    public static let indexEvery = 3
    /// Faint survey grid behind the map: this many cells across.
    public static let gridDivisions = 8

    public static func clampedCount(_ n: Int) -> Int { min(max(n, minRings), maxRings) }

    /// Ring `k` of `n`, with the wobble turned to `wobble` (0 ... 1).
    public static func ring(_ k: Int, of n: Int, seed: UInt32, wobble: Double) -> ContourRing {
        let frac = n > 1 ? Double(k) / Double(n - 1) : 0
        let radius = outerRadius * (1 - innerShrink * Double(k) / Double(n))
        let center = peak * pow(frac, centerEase)
        let start = 2 * Double.pi * ContourHash.unit(seed, 100 + k)
        var amps: [Double] = [], phases: [Double] = []
        for j in 0..<harmonics.count {
            amps.append(baseAmplitudes[j] * wobble * (0.85 + 0.3 * ContourHash.unit(seed, 200 + 10 * k + j)))
            phases.append(2 * Double.pi * ContourHash.unit(seed, 300 + j) + Double(k) * (0.22 + 0.18 * ContourHash.unit(seed, 400 + j)))
        }
        var r = ContourRing(index: k, center: center, radius: radius, startAngle: start, amplitudes: amps, phases: phases,
                            isIndex: k % indexEvery == 0, points: [], cumulative: [])
        var pts: [Vec2] = []
        pts.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            pts.append(r.point(atAngle: start + 2 * Double.pi * Double(i) / Double(sampleCount)))
        }
        var cum = [0.0]
        for i in 0..<sampleCount { cum.append(cum[i] + pts[i].distance(to: pts[(i + 1) % sampleCount])) }
        r.points = pts; r.cumulative = cum
        return r
    }

    /// The gap between an outer ring and the one inside it: the shortest distance between the two polylines,
    /// or negative if the inner one is not wholly inside the outer one (they cross, or are swapped).
    public static func gap(outer: ContourRing, inner: ContourRing) -> Double {
        var d = Double.infinity
        for p in inner.points { d = min(d, outer.distance(to: p)) }
        for p in outer.points { d = min(d, inner.distance(to: p)) }
        for p in inner.points where !outer.contains(p) { return -d }
        return d
    }
}

/// A set of nested contour rings, outermost first.
public struct ContourMap: Equatable, Sendable {
    public let seed: UInt32
    public let rings: [ContourRing]
    /// The wobble scale that was kept (1 = full wobble; smaller when rings would have come too close).
    public let wobbleScale: Double

    public var count: Int { rings.count }
    /// The peak: the centre of the innermost ring.
    public var peak: Vec2 { rings[rings.count - 1].center }

    /// Builds `rings` (clamped to 3 ... 12) nested rings. Deterministic in `seed`. If the full wobble would
    /// bring two rings closer than `ContourInkGeometry.minGapFloor`, it is turned down step by step, so the
    /// rings never touch or cross.
    public static func make(rings requested: Int = ContourInkGeometry.defaultRings, seed: UInt32 = ContourInkGeometry.defaultSeed) -> ContourMap {
        let n = ContourInkGeometry.clampedCount(requested)
        var last: [ContourRing] = []
        var kept = 0.0
        for scale in ContourInkGeometry.wobbleScales {
            let rs = (0..<n).map { ContourInkGeometry.ring($0, of: n, seed: seed, wobble: scale) }
            last = rs; kept = scale
            if minGap(of: rs) >= ContourInkGeometry.minGapFloor { break }
        }
        return ContourMap(seed: seed, rings: last, wobbleScale: kept)
    }

    /// The smallest gap between any two neighbouring rings (negative if any pair crosses).
    public static func minGap(of rings: [ContourRing]) -> Double {
        var m = Double.infinity
        for k in 0..<max(0, rings.count - 1) {
            m = min(m, ContourInkGeometry.gap(outer: rings[k], inner: rings[k + 1]))
        }
        return m
    }

    public var minGap: Double { Self.minGap(of: rings) }
}
