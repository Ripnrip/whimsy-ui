import Foundation

/// Finger velocity from the last `window` seconds of samples.
public struct VelocityTracker: Equatable, Sendable {
    public var window: Double
    public private(set) var samples: [(t: Double, p: Vec2)] = []

    public init(window: Double = 0.08) { self.window = window }

    public static func == (a: VelocityTracker, b: VelocityTracker) -> Bool {
        a.window == b.window && a.samples.map(\.t) == b.samples.map(\.t) && a.samples.map(\.p) == b.samples.map(\.p)
    }

    public mutating func reset() { samples.removeAll() }

    public mutating func add(_ p: Vec2, at t: Double) {
        if let last = samples.last, t < last.t { samples.removeAll() }
        samples.append((t, p))
        // Keep one sample older than the window so short windows still have a baseline.
        while samples.count > 2, samples[1].t < t - window { samples.removeFirst() }
    }

    /// Points per second. Zero when the finger has been still for longer than the window.
    public func velocity(at now: Double) -> Vec2 {
        guard let last = samples.last, let first = samples.first, now - last.t <= window else { return .zero }
        let dt = last.t - first.t
        guard dt > 1e-4 else { return .zero }
        return (last.p - first.p) * (1 / dt)
    }
}

public enum PeelOutcome: Equatable, Sendable { case springBack, popOff, tear }

/// When a peel snaps back, pops off or tears.
public struct PeelRules: Equatable, Sendable {
    /// Lifted fraction at which letting go pops the sticker off.
    public var popFraction = 0.5
    /// Speed along the peel direction (pt/s) that tears instead of peeling.
    public var tearSpeed = 2000.0
    /// A tear needs a little of the sticker already lifted to grip.
    public var tearMinFraction = 0.04

    public init() {}

    /// A yank tears only when it's fast *in the peel direction*; sideways flicks don't.
    public func shouldTear(fraction: Double, velocity: Vec2, peelDirection: Vec2?) -> Bool {
        guard let n = peelDirection, fraction >= tearMinFraction else { return false }
        return velocity.dot(n.normalized) >= tearSpeed
    }

    public func decide(fraction: Double, velocity: Vec2, peelDirection: Vec2?) -> PeelOutcome {
        if shouldTear(fraction: fraction, velocity: velocity, peelDirection: peelDirection) { return .tear }
        return fraction >= popFraction ? .popOff : .springBack
    }
}

/// Splits a sticker along the crease with a jagged, seeded tear. Both pieces share the
/// same jag points, so they fit back together exactly and their areas add up to the whole.
public enum TearGeometry {
    public static func pieces(of shape: Polygon, fold: FoldLine, seed: UInt64, teeth: Int = 7,
                              amplitude: ClosedRange<Double> = 2...5) -> (lifted: Polygon, stuck: Polygon)? {
        let stuck = shape.clipped { fold.signedDistance($0) }
        let lifted = shape.clipped { -fold.signedDistance($0) }
        guard !stuck.isEmpty, !lifted.isEmpty,
              let (a0, b0) = PeelState.creaseSegment(of: lifted, fold: fold) else { return nil }
        // Canonical order along the tangent, so both pieces generate the same jag.
        let t = fold.tangent
        let (a, b) = a0.dot(t) <= b0.dot(t) ? (a0, b0) : (b0, a0)
        var rng = SeededRandom(seed: seed)
        let jag: [Vec2] = (1...max(teeth, 1)).map { k in
            let base = Vec2.lerp(a, b, Double(k) / Double(teeth + 1))
            let sign: Double = k % 2 == 0 ? 1 : -1
            return base + fold.normal * (sign * rng.uniform(amplitude))
        }
        return (insert(jag, a: a, b: b, into: lifted, fold: fold), insert(jag, a: a, b: b, into: stuck, fold: fold))
    }

    private static func insert(_ jag: [Vec2], a: Vec2, b: Vec2, into poly: Polygon, fold: FoldLine) -> Polygon {
        var p = poly.points
        for i in p.indices {
            let u = p[i], v = p[(i + 1) % p.count]
            let onLine = abs(fold.signedDistance(u)) < 1e-7 && abs(fold.signedDistance(v)) < 1e-7
            guard onLine else { continue }
            if u.distance(to: a) < 1e-7, v.distance(to: b) < 1e-7 {
                p.insert(contentsOf: jag, at: i + 1); return Polygon(p)
            }
            if u.distance(to: b) < 1e-7, v.distance(to: a) < 1e-7 {
                p.insert(contentsOf: jag.reversed(), at: i + 1); return Polygon(p)
            }
        }
        return poly
    }
}
