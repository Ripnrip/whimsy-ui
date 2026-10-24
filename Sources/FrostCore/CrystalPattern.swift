import Foundation

/// One straight ice-crystal segment. It starts growing when the frost progress reaches `birth`
/// and reaches full `length` at `birth + span`.
public struct CrystalBranch: Equatable, Sendable {
    public var start: Vec2
    /// Direction in radians (y down).
    public var angle: Double
    public var length: Double
    public var width: Double
    public var generation: Int
    /// Index of the branch this one grows from (nil for an edge stem).
    public var parent: Int?
    public var birth: Double
    public var span: Double

    public var direction: Vec2 { Vec2.unit(angle) }
    public var end: Vec2 { start + direction * length }
    public var fullAt: Double { birth + span }

    /// 0…1: how much of the branch is grown at frost progress `p`.
    public func growth(at p: Double) -> Double {
        guard span > 0 else { return p >= birth ? 1 : 0 }
        return WhimsyMath.clamp01((p - birth) / span)
    }

    /// The visible tip at frost progress `p`.
    public func tip(at p: Double) -> Vec2 { start + direction * (length * growth(at: p)) }
}

/// A seeded, deterministic frost pattern for a card: stems grow in from the edges and branch at
/// about 60°, each generation shorter and thinner.
public struct CrystalPattern: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        /// Average spacing of edge stems along the perimeter (pt).
        public var stemSpacing = 48.0
        /// Stem length as a fraction of the card's shorter side.
        public var stemLength: ClosedRange<Double> = 0.22...0.34
        /// Max deviation of a stem from the inward normal (radians).
        public var stemJitter = 0.35
        public var stemWidth = 2.2
        /// Children per branch, by the parent's generation; its count is the deepest generation.
        public var children: [Int] = [3, 2, 2]
        /// Branch angle off the parent (radians), plus jitter.
        public var branchAngle = Double.pi / 3
        public var angleJitter = 0.1
        /// Child length as a fraction of the parent's.
        public var lengthRatio: ClosedRange<Double> = 0.42...0.6
        public var widthRatio = 0.62
        /// Where along the parent children sprout.
        public var sprout: ClosedRange<Double> = 0.28...0.88
        /// Latest stem start (progress).
        public var stemStagger = 0.2
        /// Growth speed in pt per unit of progress (before normalising).
        public var speed = 160.0
        /// The last branch finishes at this progress.
        public var finishAt = 0.97
        public init() {}
    }

    public let size: Vec2
    public let seed: UInt64
    public let branches: [CrystalBranch]
    /// Branch indices in the order they start growing.
    public let spawnOrder: [Int]

    public init(size: Vec2, seed: UInt64 = 0xF2057, config: Config = Config()) {
        self.size = size
        self.seed = seed
        var rng = SeededRandom(seed: seed)
        var out: [CrystalBranch] = []
        let w = size.x, h = size.y, perimeter = 2 * (w + h)
        let n = max(4, Int((perimeter / config.stemSpacing).rounded()))
        let short = min(w, h)
        for i in 0..<n {
            let u = (Double(i) + rng.uniform(0.2...0.8)) / Double(n) * perimeter
            let (p, inward) = Self.edgePoint(u, w: w, h: h)
            let angle = atan2(inward.y, inward.x) + rng.uniform(-config.stemJitter...config.stemJitter)
            let length = short * rng.uniform(config.stemLength)
            out.append(CrystalBranch(start: p, angle: angle, length: length, width: config.stemWidth, generation: 0,
                                     parent: nil, birth: rng.uniform(0...config.stemStagger), span: length / config.speed))
        }
        // Breadth-first children so generations stay grouped.
        var next = 0
        while next < out.count {
            let b = out[next]
            if b.generation < config.children.count {
                let k = config.children[b.generation]
                var side: Double = rng.next() & 1 == 0 ? 1 : -1
                for j in 0..<k {
                    // Evenly spread along the parent, jittered.
                    let lo = config.sprout.lowerBound, hi = config.sprout.upperBound
                    let slot = (hi - lo) / Double(k)
                    let t = lo + slot * (Double(j) + rng.uniform(0.15...0.85))
                    let angle = b.angle + side * (config.branchAngle + rng.uniform(-config.angleJitter...config.angleJitter))
                    let length = b.length * rng.uniform(config.lengthRatio)
                    out.append(CrystalBranch(start: b.start + b.direction * (b.length * t), angle: angle, length: length,
                                             width: b.width * config.widthRatio, generation: b.generation + 1, parent: next,
                                             birth: b.birth + b.span * t, span: length / config.speed))
                    side = -side
                }
            }
            next += 1
        }
        // Normalise timing so the whole pattern is grown at `finishAt`.
        let last = out.map(\.fullAt).max() ?? 1
        let k = last > 0 ? config.finishAt / last : 1
        for i in out.indices { out[i].birth *= k; out[i].span *= k }
        branches = out
        spawnOrder = out.indices.sorted { (out[$0].birth, $0) < (out[$1].birth, $1) }
    }

    /// A point `u` pt along the card's perimeter (clockwise from the top-left) and the inward normal there.
    public static func edgePoint(_ u: Double, w: Double, h: Double) -> (Vec2, Vec2) {
        let per = 2 * (w + h)
        var u = u.truncatingRemainder(dividingBy: per)
        if u < 0 { u += per }
        if u < w { return (Vec2(u, 0), Vec2(0, 1)) }
        u -= w
        if u < h { return (Vec2(w, u), Vec2(-1, 0)) }
        u -= h
        if u < w { return (Vec2(w - u, h), Vec2(0, -1)) }
        u -= w
        return (Vec2(0, h - u), Vec2(1, 0))
    }

    public var maxGeneration: Int { branches.map(\.generation).max() ?? 0 }

    /// How many branches have started growing at progress `p`.
    public func spawnedCount(at p: Double) -> Int { branches.reduce(0) { $0 + ($1.birth < p ? 1 : 0) } }
}
