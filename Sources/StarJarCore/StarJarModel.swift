import Foundation

/// One star. Position and velocity change; the rest is seeded once.
public struct JarStar: Equatable, Sendable {
    public let index: Int
    public var x: Double
    public var y: Double
    public var vx = 0.0
    public var vy = 0.0
    /// Collision radius in points (4.5 ... 7.5).
    public let radius: Double
    /// Twinkle: frequency in Hz (0.35 ... 1.25) and two phases.
    public let frequency: Double
    public let phase: Double
    public let phase2: Double
    /// Wander: four frequencies (rad/s) and phases for the sums of sines that push it about.
    public let wanderFrequencies: [Double]
    public let wanderPhases: [Double]
    /// 0 ... 1, a small colour variation for the view.
    public let hue: Double
    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

public enum StarJarPhase: Int, CaseIterable, Sendable {
    /// Dim stars resting in the bottom of the jar. The page scrolls.
    case asleep
    /// Brightening and lifting off (0.6 s). Scrolling is locked from here...
    case waking
    /// Twinkling and drifting like fireflies; a finger stirs them.
    case awake
    /// Sinking back to the bottom and dimming (1.5 s). ...until this ends.
    case settling
}

public enum StarJarEvent: Equatable, Sendable {
    case waking
    case awake
    case settling
    case asleep
    /// A star hit the glass faster than `brushSpeed` (at most one every `brushInterval` seconds).
    case brush(star: Int, speed: Double)
}

/// The star jar: geometry, a seeded star simulation at a fixed 120 Hz, the twinkle, the
/// asleep → waking → awake → settling machine, the scroll lock, the stir field and the brush events.
public struct StarJarModel: Equatable, Sendable {
    // MARK: constants
    public static let defaultStars = 40
    public static let minStars = 8
    public static let maxStars = 80
    public static let defaultSeed: UInt32 = 0x57A2
    public static let substep = 1.0 / 120
    public static let maxStep = 0.25
    public static let prerollSteps = 480

    public static let wakeDuration = 0.6
    public static let settleDuration = 1.5
    public static let wakeDurationReduced = 0.3
    public static let settleDurationReduced = 0.6

    public static let gravity = 260.0
    public static let sleepDrag = 2.5
    public static let awakeDrag = 1.0
    public static let wanderAccel = 80.0
    public static let buoyancy = 30.0
    public static let separation = 3000.0
    public static let separationReach = 1.15
    /// Damping of the closing speed between touching stars (a dashpot), so heaps come to rest.
    public static let contactDamping = 14.0
    public static let maxSpeed = 520.0
    public static let restitution = 0.5
    public static let wallFriction = 0.92
    public static let wakeKick = (min: 120.0, spread: 100.0, side: 70.0)

    public static let stirRadius = 70.0
    public static let stirSwirl = 700.0
    public static let stirFollow = 7.0
    public static let stirMinWake = 0.5

    public static let brushSpeed = 70.0
    public static let brushInterval = 0.08
    public static let brushMinWake = 0.3
    public static let restSpeed = 4.0

    public static func clampedCount(_ n: Int) -> Int { min(max(n, minStars), maxStars) }

    // MARK: state
    public let seed: UInt32
    public private(set) var stars: [JarStar]
    public private(set) var time = 0.0
    public private(set) var phase = StarJarPhase.asleep
    public private(set) var phaseTime = 0.0
    /// The wake level when the current phase began (a wake or a sleep can interrupt the other).
    public private(set) var wakeFrom = 0.0
    public private(set) var reduceMotion: Bool
    public private(set) var touch: (x: Double, y: Double)? = nil
    public private(set) var touchVelocity = (x: 0.0, y: 0.0)
    public private(set) var brushes = 0
    public private(set) var wakes = 0
    public private(set) var sleeps = 0
    public private(set) var lastBrushTime = -Double.infinity
    private var touchTime = 0.0
    private var accumulator = 0.0

    public static func == (a: StarJarModel, b: StarJarModel) -> Bool {
        a.seed == b.seed && a.stars == b.stars && a.time == b.time && a.phase == b.phase && a.phaseTime == b.phaseTime
            && a.wakeFrom == b.wakeFrom && a.reduceMotion == b.reduceMotion && a.touch?.x == b.touch?.x && a.touch?.y == b.touch?.y
            && a.brushes == b.brushes && a.accumulator == b.accumulator
    }

    public init(starCount: Int = defaultStars, seed: UInt32 = defaultSeed, reduceMotion: Bool = false) {
        self.seed = seed
        self.reduceMotion = reduceMotion
        stars = Self.makeStars(count: Self.clampedCount(starCount), seed: seed)
        // Let them fall into a heap before anyone looks.
        for _ in 0..<Self.prerollSteps { _ = physics(wake: 0) }
        time = 0
        for i in stars.indices { stars[i].vx = 0; stars[i].vy = 0 }
    }

    /// Seeded stars at random places inside the jar (the preroll then lets them fall).
    public static func makeStars(count: Int, seed: UInt32) -> [JarStar] {
        (0..<count).map { i in
            let u = { (salt: Int) in StarJarMath.unit(seed, salt) }
            let r = 4.5 + 3 * u(10 + i)
            var x = StarJarGeometry.bodyCenter.x, y = StarJarGeometry.bodyCenter.y
            for a in 0..<64 {
                let px = 34 + 232 * u(1000 + i * 64 + a), py = 100 + 226 * u(20_000 + i * 64 + a)
                if StarJarGeometry.distance(px, py) + r + StarJarGeometry.wall <= 0 { x = px; y = py; break }
            }
            let tau = 2 * Double.pi
            return JarStar(index: i, x: x, y: y, radius: r,
                           frequency: 0.35 + 0.9 * u(20 + i), phase: tau * u(30 + i), phase2: tau * u(40 + i),
                           wanderFrequencies: (0..<4).map { 0.5 + 1.3 * u(50 + i * 4 + $0) },
                           wanderPhases: (0..<4).map { tau * u(400 + i * 4 + $0) },
                           hue: u(800 + i))
        }
    }

    // MARK: derived

    public var wakeDuration: Double { reduceMotion ? Self.wakeDurationReduced : Self.wakeDuration }
    public var settleDuration: Double { reduceMotion ? Self.settleDurationReduced : Self.settleDuration }

    /// 0 asleep ... 1 awake: eased out while waking, eased in and out while settling.
    public var wake: Double {
        switch phase {
        case .asleep: return 0
        case .awake: return 1
        case .waking: return StarJarMath.lerp(wakeFrom, 1, StarJarMath.easeOutCubic(phaseTime / wakeDuration))
        case .settling: return StarJarMath.lerp(wakeFrom, 0, StarJarMath.easeInOutCubic(phaseTime / settleDuration))
        }
    }
    /// The surrounding scroll view is disabled from the tap that wakes the jar until the stars have settled.
    public var isScrollLocked: Bool { phase != .asleep }
    /// Waking or awake: what a `Binding<Bool>` reports.
    public var isEngaged: Bool { phase == .waking || phase == .awake }
    /// Asleep with every star still: the view can stop its timeline.
    public var isAtRest: Bool { phase == .asleep && stars.allSatisfy { $0.vx == 0 && $0.vy == 0 } }

    /// A star's brightness (0 ... 1) at a time and wake level.
    public static func brightness(_ s: JarStar, time t: Double, wake w: Double, reduceMotion: Bool) -> Double {
        let level = StarJarMath.lerp(0.16, reduceMotion ? 0.72 : 1.0, w)
        let amp = reduceMotion ? 0 : StarJarMath.lerp(0.08, 0.5, w)
        let a = 2 * Double.pi * s.frequency * t + s.phase
        let twinkle = 0.5 + 0.35 * StarJarMath.sin(a) + 0.15 * StarJarMath.sin(2.3 * a + s.phase2)
        return level * (1 - amp + amp * twinkle)
    }
    public func brightness(_ i: Int) -> Double {
        guard stars.indices.contains(i) else { return 0 }
        return Self.brightness(stars[i], time: time, wake: wake, reduceMotion: reduceMotion)
    }

    /// The acceleration the finger adds to a star at (x, y) moving at (vx, vy): a swirl round the finger
    /// plus a pull toward the finger's own velocity, both fading as exp(-d²/R²).
    public static func stir(x: Double, y: Double, vx: Double, vy: Double, finger: (x: Double, y: Double), fingerVelocity: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let dx = x - finger.x, dy = y - finger.y
        let d2 = dx * dx + dy * dy
        let f = StarJarMath.exp(-d2 / (stirRadius * stirRadius))
        guard f > 0.002 else { return (0, 0) }
        let d = d2.squareRoot() + 1e-6
        return ((-dy / d) * stirSwirl * f + (fingerVelocity.x - vx) * stirFollow * f,
                (dx / d) * stirSwirl * f + (fingerVelocity.y - vy) * stirFollow * f)
    }

    // MARK: input

    /// A tap at a point in jar coordinates. The jar (or its cork) wakes it; anywhere else, or the Done chip, puts it to sleep.
    public mutating func tap(x: Double, y: Double) -> [StarJarEvent] {
        guard x.isFinite, y.isFinite else { return [] }
        if isEngaged && StarJarGeometry.hitsDone(x, y) { return sleep() }
        if StarJarGeometry.hitsJar(x, y) { return phase == .asleep || phase == .settling ? wakeUp() : [] }
        return isEngaged ? sleep() : []
    }

    public mutating func wakeUp() -> [StarJarEvent] {
        guard phase == .asleep || phase == .settling else { return [] }
        let w0 = wake
        if !reduceMotion {
            let k = 1 - w0
            for i in stars.indices {
                stars[i].vy -= (Self.wakeKick.min + Self.wakeKick.spread * StarJarMath.unit(seed, 3000 + i)) * k
                stars[i].vx += (StarJarMath.unit(seed, 3100 + i) - 0.5) * Self.wakeKick.side * k
            }
        }
        wakeFrom = w0; phase = .waking; phaseTime = 0; wakes += 1
        return [.waking]
    }

    public mutating func sleep() -> [StarJarEvent] {
        guard isEngaged else { return [] }
        wakeFrom = wake; phase = .settling; phaseTime = 0; sleeps += 1; touch = nil
        return [.settling]
    }

    /// For a `Binding<Bool>`: true wakes, false settles.
    public mutating func setEngaged(_ on: Bool) -> [StarJarEvent] { on ? wakeUp() : sleep() }

    public mutating func touchBegan(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        touch = (x, y); touchVelocity = (0, 0); touchTime = time
    }

    /// The finger moved; its velocity is smoothed (half old, half new).
    public mutating func touchMoved(x: Double, y: Double, at timestamp: Double? = nil) {
        guard x.isFinite, y.isFinite else { return }
        guard let p = touch else { touchBegan(x: x, y: y); return }
        let t = timestamp ?? time
        let dt = max(t - touchTime, 1.0 / 240)
        touchVelocity = (0.5 * touchVelocity.x + 0.5 * (x - p.x) / dt, 0.5 * touchVelocity.y + 0.5 * (y - p.y) / dt)
        touch = (x, y); touchTime = t
    }

    public mutating func touchEnded() { touch = nil; touchVelocity = (0, 0) }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if phase == .waking { phase = .awake; phaseTime = 0 }
        if phase == .settling { phase = .asleep; phaseTime = 0 }
    }

    // MARK: time

    /// Advances by `dt` seconds (clamped to 0 ... 0.25) in fixed 1/120 s substeps; the remainder carries over.
    public mutating func step(_ dt: Double) -> [StarJarEvent] {
        let d = dt.isFinite ? min(max(dt, 0), Self.maxStep) : 0
        accumulator += d
        var events: [StarJarEvent] = []
        while accumulator >= Self.substep {
            accumulator -= Self.substep
            events += substepOnce()
        }
        return events
    }

    private mutating func substepOnce() -> [StarJarEvent] {
        var events: [StarJarEvent] = []
        time += Self.substep
        phaseTime += Self.substep
        if phase == .waking && phaseTime >= wakeDuration { phase = .awake; phaseTime = 0; events.append(.awake) }
        if phase == .settling && phaseTime >= settleDuration { phase = .asleep; phaseTime = 0; touch = nil; events.append(.asleep) }
        // Asleep and nearly still: freeze (the heap stays put and the view can pause).
        if phase == .asleep && stars.allSatisfy({ $0.speed < Self.restSpeed }) {
            for i in stars.indices { stars[i].vx = 0; stars[i].vy = 0 }
            return events
        }
        events += physics(wake: wake)
        return events
    }

    /// One 1/120 s step of the stars at wake level `w`.
    private mutating func physics(wake w: Double) -> [StarJarEvent] {
        let h = Self.substep, n = stars.count, t = time
        let g = Self.gravity * (1 - w * w)
        let damp = StarJarMath.exp(-StarJarMath.lerp(Self.sleepDrag, Self.awakeDrag, w) * h)
        let wander = reduceMotion ? 0 : Self.wanderAccel * w
        let lift = reduceMotion ? 0 : Self.buoyancy * w
        var ax = [Double](repeating: 0, count: n), ay = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let s = stars[i], f = s.wanderFrequencies, p = s.wanderPhases
            ax[i] = wander * (StarJarMath.sin(t * f[0] + p[0]) + 0.6 * StarJarMath.sin(t * f[1] + p[1]))
            ay[i] = g - lift * (s.y - StarJarGeometry.bodyCenter.y) / 60 + wander * (StarJarMath.sin(t * f[2] + p[2]) + 0.6 * StarJarMath.sin(t * f[3] + p[3]))
        }
        for i in 0..<n {
            for j in (i + 1)..<max(n, i + 1) {
                let dx = stars[j].x - stars[i].x, dy = stars[j].y - stars[i].y
                let reach = (stars[i].radius + stars[j].radius) * Self.separationReach
                let d2 = dx * dx + dy * dy
                guard d2 < reach * reach else { continue }
                let d = d2.squareRoot()
                var fx = Self.separation, fy = 0.0
                if d > 1e-6 {
                    let nx = dx / d, ny = dy / d
                    let closing = (stars[j].vx - stars[i].vx) * nx + (stars[j].vy - stars[i].vy) * ny
                    let k = Self.separation * (1 - d / reach) - Self.contactDamping * closing
                    fx = nx * k; fy = ny * k
                }
                ax[i] -= fx; ay[i] -= fy; ax[j] += fx; ay[j] += fy
            }
        }
        if let finger = touch, w > Self.stirMinWake, !reduceMotion {
            for i in 0..<n {
                let a = Self.stir(x: stars[i].x, y: stars[i].y, vx: stars[i].vx, vy: stars[i].vy, finger: finger, fingerVelocity: touchVelocity)
                ax[i] += a.x; ay[i] += a.y
            }
        }
        var events: [StarJarEvent] = []
        for i in 0..<n {
            var s = stars[i]
            s.vx = (s.vx + ax[i] * h) * damp
            s.vy = (s.vy + ay[i] * h) * damp
            let sp = s.speed
            if sp > Self.maxSpeed { s.vx = s.vx * Self.maxSpeed / sp; s.vy = s.vy * Self.maxSpeed / sp }
            s.x += s.vx * h
            s.y += s.vy * h
            for k in 0..<3 {
                let depth = StarJarGeometry.distance(s.x, s.y) + s.radius + StarJarGeometry.wall
                if depth <= 0 { break }
                let nrm = StarJarGeometry.normal(s.x, s.y)
                s.x -= nrm.x * depth; s.y -= nrm.y * depth
                let vn = s.vx * nrm.x + s.vy * nrm.y
                if vn > 0 {
                    if k == 0 && vn > Self.brushSpeed && w > Self.brushMinWake && t - lastBrushTime >= Self.brushInterval {
                        lastBrushTime = t; brushes += 1
                        events.append(.brush(star: i, speed: vn))
                    }
                    s.vx = (s.vx - (1 + Self.restitution) * vn * nrm.x) * Self.wallFriction
                    s.vy = (s.vy - (1 + Self.restitution) * vn * nrm.y) * Self.wallFriction
                }
            }
            stars[i] = s
        }
        return events
    }
}
