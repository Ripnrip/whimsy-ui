import WhimsyCore
/// A single eraser crumb.
public struct Crumb: Equatable, Sendable, Identifiable {
    public let id: Int
    public var position: Vec2
    public var velocity: Vec2
    public var age: Double = 0
    public let lifetime: Double
    public let size: Double
    public var rotation: Double
    public let spin: Double
    /// 0...1 shade variation, handy for colouring.
    public let shade: Double

    /// Remaining life in 0...1 (1 = just born).
    public var life: Double { lifetime > 0 ? max(1 - age / lifetime, 0) : 0 }
    /// Opacity: fully opaque for the first part of its life, then eases out.
    public var opacity: Double {
        let l = life
        return l > 0.4 ? 1 : (l / 0.4) * (l / 0.4)
    }
    public var isAlive: Bool { age < lifetime }
}

/// Emits crumbs behind the eraser and simulates them (gravity, drag, fade, lifetime).
public struct CrumbEmitter: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Crumbs per point of eraser travel.
        public var crumbsPerPoint: Double = 0.09
        public var maxCrumbs: Int = 260
        /// Gravity, points/s², y-down.
        public var gravity: Double = 900
        /// Linear air drag per second.
        public var drag: Double = 1.6
        public var lifetime: ClosedRange<Double> = 0.45...0.9
        public var size: ClosedRange<Double> = 1.6...3.6
        /// Speed thrown backwards (opposite the motion), points/s.
        public var backSpeed: ClosedRange<Double> = 40...150
        /// Upward kick, points/s (applied as negative y).
        public var lift: ClosedRange<Double> = 30...170
        public init() {}
    }

    public var configuration: Configuration
    public private(set) var crumbs: [Crumb] = []
    private var rng: SeededRandom
    private var emissionDebt = 0.0
    private var nextID = 0

    public init(seed: UInt64 = 0xC0FFEE, configuration: Configuration = .init()) {
        rng = SeededRandom(seed: seed)
        self.configuration = configuration
    }

    /// Spawns `count` crumbs behind an eraser at `position` moving along `direction`.
    /// `spread` is roughly the eraser radius. Returns how many were spawned.
    @discardableResult
    public mutating func emit(count: Int, at position: Vec2, direction: Vec2, spread: Double) -> Int {
        guard count > 0 else { return 0 }
        let forward = direction.length > 0 ? direction.normalized : Vec2(1, 0)
        let side = forward.perpendicular
        let c = configuration
        var spawned = 0
        for _ in 0..<count {
            let origin = position
                - forward * (spread * rng.double(in: 0.3...0.9))
                + side * (spread * rng.double(in: -0.8...0.8))
            let velocity = -forward * rng.double(in: c.backSpeed)
                + side * rng.double(in: -35...35)
                + Vec2(0, -rng.double(in: c.lift))
            crumbs.append(Crumb(
                id: nextID,
                position: origin,
                velocity: velocity,
                lifetime: rng.double(in: c.lifetime),
                size: rng.double(in: c.size),
                rotation: rng.double(in: 0...(2 * .pi)),
                spin: rng.double(in: -12...12),
                shade: rng.double(in: 0...1)
            ))
            nextID &+= 1
            spawned += 1
        }
        if crumbs.count > c.maxCrumbs {
            crumbs.removeFirst(crumbs.count - c.maxCrumbs) // drop the oldest
        }
        return spawned
    }

    /// Emits crumbs proportional to `distance` travelled (fractional crumbs carry over).
    @discardableResult
    public mutating func emit(forTravel distance: Double, at position: Vec2, direction: Vec2, spread: Double) -> Int {
        guard distance.isFinite, distance > 0 else { return 0 }
        emissionDebt += distance * configuration.crumbsPerPoint
        let whole = Int(emissionDebt + 1e-9) // tolerate float drift (0.45 * 100 must give 45)
        emissionDebt -= Double(whole)
        return emit(count: whole, at: position, direction: direction, spread: spread)
    }

    /// Integrates every crumb by `dt` seconds and removes dead ones.
    public mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let h = min(dt, 0.1)
        let damping = max(1 - configuration.drag * h, 0)
        for i in crumbs.indices {
            crumbs[i].velocity.y += configuration.gravity * h
            crumbs[i].velocity = crumbs[i].velocity * damping
            crumbs[i].position += crumbs[i].velocity * h
            crumbs[i].rotation += crumbs[i].spin * h
            crumbs[i].age += h
        }
        crumbs.removeAll { !$0.isAlive }
    }

    public var isIdle: Bool { crumbs.isEmpty }

    public mutating func removeAll() {
        crumbs.removeAll()
        emissionDebt = 0
    }
}
