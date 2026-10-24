import Foundation

/// A meltwater droplet sliding down the card (card coordinates).
public struct Droplet: Equatable, Sendable {
    public var position: Vec2
    public var velocity: Double
    public var radius: Double
    public var age = 0.0
    public var life: Double

    public init(position: Vec2, radius: Double, life: Double, velocity: Double = 0) {
        self.position = position; self.radius = radius; self.life = life; self.velocity = velocity
    }

    /// Water on glass: gravity against a strong drag, so it creeps to a terminal speed.
    public static let gravity = 900.0
    public static let drag = 6.0
    public static var terminalVelocity: Double { gravity / drag }
    public static let fadeIn = 0.08
    public static let fadeOut = 0.45

    public mutating func step(_ dt: Double) {
        var left = min(max(dt, 0), WhimsySpring.maxFrame)
        while left > 1e-12 {
            let h = min(left, WhimsySpring.maxSubstep)
            velocity += (Self.gravity - Self.drag * velocity) * h
            position.y += velocity * h
            age += h
            left -= h
        }
    }

    public var opacity: Double {
        WhimsyMath.clamp01(age / Self.fadeIn) * WhimsyMath.clamp01((life - age) / Self.fadeOut)
    }
    public var isFinished: Bool { age >= life }
}

/// What happened during a step.
public enum FrostEvent: Equatable, Sendable {
    /// A branch started growing.
    case spawn(Int)
    /// A branch melted away completely.
    case melted(Int)
}

/// Frost that grows while the card is held and melts back on release.
public struct FrostModel: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        /// Seconds of holding to frost over completely.
        public var growDuration = 3.0
        /// Seconds to melt from full frost.
        public var meltDuration = 1.3
        /// Haptic ticks are at least this far apart.
        public var tickInterval = 0.07
        public var maxDroplets = 36
        /// Seconds for the melt blur to come in / go out.
        public var blurIn = 0.2
        public var blurOut = 0.35
        /// Reduce Motion: no droplets and no blur.
        public var reduceMotion = false
        public init() {}
    }

    public var config: Config
    public private(set) var pattern: CrystalPattern
    public private(set) var progress = 0.0
    public private(set) var isHeld = false
    /// 0…1 melt softness (drives the blur).
    public private(set) var melt = 0.0
    public private(set) var droplets: [Droplet] = []
    /// Throttled haptic counter, and every spawn event ever emitted.
    public private(set) var ticks = 0
    public private(set) var spawns = 0
    private var sinceTick = Double.infinity
    private var meltCount = 0
    public static let dropletEvery = 4
    private var rng: SeededRandom

    public init(size: Vec2, seed: UInt64 = 0xF2057, config: Config = Config()) {
        self.config = config
        pattern = CrystalPattern(size: size, seed: seed)
        rng = SeededRandom(seed: seed ^ 0xD20F)
    }

    public var isMelting: Bool { !isHeld && progress > 0 }
    public var isIdle: Bool { !isHeld && progress == 0 && droplets.isEmpty && melt == 0 }
    /// Melt blur radius in points.
    public var blurRadius: Double { config.reduceMotion ? 0 : 3.5 * melt }

    /// Rebuilds the pattern for a new card size (only when there's no frost).
    public mutating func resize(to size: Vec2) {
        guard size != pattern.size, progress == 0, !isHeld else { return }
        pattern = CrystalPattern(size: size, seed: pattern.seed)
    }

    public mutating func press() { isHeld = true }
    public mutating func release() { isHeld = false }

    /// Advances time. Returns branches that started growing or melted away this step,
    /// in order of their birth (reversed while melting).
    @discardableResult
    public mutating func step(_ dt: Double) -> [FrostEvent] {
        let dt = min(max(dt, 0), WhimsySpring.maxFrame)
        let before = progress
        if isHeld {
            progress = min(1, progress + dt / config.growDuration)
        } else {
            progress = max(0, progress - dt / config.meltDuration)
        }
        var events: [FrostEvent] = []
        if progress > before {
            for i in pattern.spawnOrder where pattern.branches[i].birth >= before && pattern.branches[i].birth < progress {
                events.append(.spawn(i))
            }
        } else if progress < before {
            for i in pattern.spawnOrder.reversed() where pattern.branches[i].birth >= progress && pattern.branches[i].birth < before {
                events.append(.melted(i))
            }
        }

        // Haptics: one tick per step with spawns, no closer than tickInterval.
        sinceTick += dt
        let spawned = events.reduce(0) { if case .spawn = $1 { return $0 + 1 } else { return $0 } }
        spawns += spawned
        if spawned > 0, sinceTick >= config.tickInterval {
            ticks += 1
            sinceTick = 0
        }

        // Melt softness.
        let target = (!isHeld && progress > 0 && !config.reduceMotion) ? 1.0 : 0.0
        let rate = target > melt ? 1 / config.blurIn : 1 / config.blurOut
        melt = target > melt ? min(target, melt + rate * dt) : max(target, melt - rate * dt)

        // Droplets: every fourth branch to melt away leaves one where it sprouted.
        for d in droplets.indices { droplets[d].step(dt) }
        droplets.removeAll { $0.isFinished }
        if !config.reduceMotion {
            for case let .melted(i) in events {
                meltCount += 1
                guard meltCount % Self.dropletEvery == 0, droplets.count < config.maxDroplets else { continue }
                let b = pattern.branches[i]
                droplets.append(Droplet(position: b.start, radius: rng.uniform(1.6...3.4), life: rng.uniform(0.9...1.4)))
            }
        }
        return events
    }
}
