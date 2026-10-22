import Foundation

/// An sRGB colour, 0…1 per channel.
public struct BlobRGB: Equatable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public static func mix(_ a: BlobRGB, _ b: BlobRGB, _ t: Double) -> BlobRGB {
        let t = WhimsyMath.clamp01(t)
        if t >= 1 { return b }
        if t <= 0 { return a }
        return BlobRGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}

/// Nine colours for a 3 × 3 mesh, row by row from the top-left.
public struct BlobPalette: Equatable, Sendable {
    public var name: String
    public var colors: [BlobRGB]
    public init(name: String, colors: [BlobRGB]) {
        precondition(colors.count == 9, "a 3 × 3 mesh needs nine colours")
        self.name = name
        self.colors = colors
    }

    public static let neon = BlobPalette(name: "Neon", colors: [
        BlobRGB(1.00, 0.30, 0.70), BlobRGB(0.62, 0.32, 1.00), BlobRGB(0.20, 0.85, 1.00),
        BlobRGB(0.78, 0.36, 0.96), BlobRGB(1.00, 0.42, 0.85), BlobRGB(0.35, 0.55, 1.00),
        BlobRGB(0.25, 0.95, 0.90), BlobRGB(1.00, 0.55, 0.78), BlobRGB(0.55, 0.40, 1.00),
    ])
    public static let sunset = BlobPalette(name: "Sunset", colors: [
        BlobRGB(1.00, 0.62, 0.25), BlobRGB(1.00, 0.36, 0.45), BlobRGB(1.00, 0.82, 0.35),
        BlobRGB(0.98, 0.42, 0.62), BlobRGB(1.00, 0.55, 0.35), BlobRGB(0.86, 0.36, 0.80),
        BlobRGB(1.00, 0.78, 0.50), BlobRGB(0.95, 0.30, 0.50), BlobRGB(1.00, 0.66, 0.42),
    ])
    public static let lagoon = BlobPalette(name: "Lagoon", colors: [
        BlobRGB(0.20, 0.80, 0.85), BlobRGB(0.25, 0.50, 1.00), BlobRGB(0.40, 0.95, 0.70),
        BlobRGB(0.30, 0.65, 1.00), BlobRGB(0.20, 0.90, 0.95), BlobRGB(0.45, 0.40, 0.95),
        BlobRGB(0.55, 1.00, 0.80), BlobRGB(0.22, 0.70, 0.95), BlobRGB(0.30, 0.85, 0.75),
    ])
    public static let orchid = BlobPalette(name: "Orchid", colors: [
        BlobRGB(0.85, 0.62, 1.00), BlobRGB(1.00, 0.68, 0.86), BlobRGB(0.70, 0.75, 1.00),
        BlobRGB(1.00, 0.60, 0.80), BlobRGB(0.80, 0.55, 0.98), BlobRGB(0.98, 0.78, 0.92),
        BlobRGB(0.66, 0.60, 1.00), BlobRGB(0.95, 0.70, 1.00), BlobRGB(1.00, 0.62, 0.74),
    ])
    public static let all: [BlobPalette] = [.neon, .sunset, .lagoon, .orchid]
}

/// A delayed follow: a critically damped *leader* chases the target and an underdamped
/// *follower* chases the leader, so the blob sets off late, glides, and lands with a little
/// overshoot instead of snapping to the finger.
public struct ChaseSpring: Equatable, Sendable {
    public var leader: WhimsySpring2D
    public var follower: WhimsySpring2D

    public init(at p: Vec2, leaderStiffness: Double = 38, followerStiffness: Double = 95, followerDamping: Double = 0.55) {
        leader = WhimsySpring2D(value: p, stiffness: leaderStiffness, dampingRatio: 1)
        follower = WhimsySpring2D(value: p, stiffness: followerStiffness, dampingRatio: followerDamping)
    }

    public var position: Vec2 { follower.value }
    public var velocity: Vec2 { follower.velocity }

    public mutating func substep(toward target: Vec2, h: Double) {
        leader.substep(toward: target, h: h)
        follower.substep(toward: leader.value, h: h)
    }

    public func isSettled(at target: Vec2, tolerance: Double = 0.05) -> Bool {
        leader.isSettled(at: target, tolerance: tolerance) && follower.isSettled(at: target, tolerance: tolerance)
    }
}

/// The blob's outline: a circle with slow travelling lobes, squashed and stretched along its
/// velocity with area preserved (×(1+s) along, ÷(1+s) across).
public struct BlobMorph: Equatable, Sendable {
    public var baseRadius: Double
    /// Speed (pt/s) at which the stretch maxes out.
    public var stretchSpeed: Double
    public var maxStretch: Double
    /// Lobe harmonics: (k, amplitude, angular speed rad/s, phase).
    public var lobes: [Lobe]

    public struct Lobe: Equatable, Sendable {
        public var k: Int, amplitude: Double, speed: Double, phase: Double
        public init(k: Int, amplitude: Double, speed: Double, phase: Double) {
            self.k = k; self.amplitude = amplitude; self.speed = speed; self.phase = phase
        }
    }

    public static let defaultLobes = [
        Lobe(k: 2, amplitude: 0.05, speed: 0.9, phase: 0),
        Lobe(k: 3, amplitude: 0.04, speed: -1.3, phase: 1.7),
        Lobe(k: 5, amplitude: 0.025, speed: 1.7, phase: 4.1),
    ]

    public init(baseRadius: Double = 130, stretchSpeed: Double = 1_400, maxStretch: Double = 0.45, lobes: [Lobe] = BlobMorph.defaultLobes) {
        self.baseRadius = max(baseRadius, 1)
        self.stretchSpeed = max(stretchSpeed, 1e-6)
        self.maxStretch = max(maxStretch, 0)
        self.lobes = lobes
    }

    /// 0 at rest, rising linearly with speed to 1 at `stretchSpeed`.
    public func speedFactor(_ velocity: Vec2) -> Double {
        let v = velocity.length
        return v.isFinite ? min(v / stretchSpeed, 1) : 0
    }

    public func stretch(for velocity: Vec2) -> Double { maxStretch * speedFactor(velocity) }

    /// Lobe gain: a gentle idle wobble that gets livelier with speed.
    public func lobeGain(for velocity: Vec2) -> Double { 0.6 + 0.8 * speedFactor(velocity) }

    /// Radius multiplier at polar angle θ (before the stretch).
    public func lobeRadius(_ theta: Double, time: Double, gain: Double) -> Double {
        var r = 1.0
        for l in lobes { r += gain * l.amplitude * sin(Double(l.k) * theta + l.speed * time + l.phase) }
        return r
    }

    /// `samples` points around the outline, relative to the blob's centre.
    public func outline(time: Double, velocity: Vec2, samples: Int = 96, wobble: Bool = true) -> [Vec2] {
        let n = max(samples, 8)
        let s = stretch(for: velocity)
        let along = velocity.length > 1e-9 ? velocity.normalized : Vec2(1, 0)
        let across = along.perpendicular
        let gain = wobble ? lobeGain(for: velocity) : 0
        return (0..<n).map { i in
            let theta = 2 * .pi * Double(i) / Double(n)
            let q = Vec2.unit(theta) * lobeRadius(theta, time: time, gain: gain)
            let a = q.dot(along), b = q.dot(across)
            return (along * (a * (1 + s)) + across * (b / (1 + s))) * baseRadius
        }
    }

    /// Shoelace area of a closed polygon.
    public static func area(of p: [Vec2]) -> Double {
        guard p.count > 2 else { return 0 }
        var a = 0.0
        for i in p.indices { a += p[i].cross(p[(i + 1) % p.count]) }
        return abs(a) / 2
    }
}

/// The 3 × 3 control points of the blob's mesh gradient, in unit space. Corners are pinned,
/// edge midpoints slide along their edges and the centre drifts (and is dragged back by speed).
public enum MeshField {
    public static func points(time t: Double, velocity: Vec2 = .zero, stretchSpeed: Double = 1_400) -> [Vec2] {
        let lag = velocity * (-0.15 / max(stretchSpeed, 1e-6))
        let cx = WhimsyMath.clamp(0.5 + 0.18 * sin(0.9 * t) + (lag.x.isFinite ? lag.x : 0), 0.15, 0.85)
        let cy = WhimsyMath.clamp(0.5 + 0.18 * cos(1.1 * t) + (lag.y.isFinite ? lag.y : 0), 0.15, 0.85)
        return [
            Vec2(0, 0), Vec2(0.5 + 0.2 * sin(0.7 * t), 0), Vec2(1, 0),
            Vec2(0, 0.5 + 0.2 * sin(0.8 * t + 1)), Vec2(cx, cy), Vec2(1, 0.5 + 0.2 * sin(0.5 * t + 3)),
            Vec2(0, 1), Vec2(0.5 + 0.2 * sin(0.6 * t + 2), 1), Vec2(1, 1),
        ]
    }
}

/// Drives the blob: follows the finger with a delayed spring, idles on a slow Lissajous orbit
/// when there's no finger, morphs with speed and crossfades between palettes.
public struct FollowBlobModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        public var leaderStiffness = 38.0
        public var followerStiffness = 95.0
        public var followerDamping = 0.55
        public var morph = BlobMorph()
        /// Idle orbit amplitude as a fraction of the canvas, and its two angular speeds (rad/s).
        public var orbitAmplitude = Vec2(0.12, 0.07)
        public var orbitSpeeds = Vec2(0.31, 0.43)
        public var paletteFade = 0.6
        public init() {}
    }

    public let tuning: Tuning
    public private(set) var size: Vec2
    /// Where the blob idles (unit space of the canvas).
    public var home: Vec2
    public private(set) var chase: ChaseSpring
    public private(set) var time = 0.0
    public private(set) var finger: Vec2?
    public private(set) var palette = 0
    public private(set) var previousPalette = 0
    public private(set) var paletteProgress = 1.0
    public var reduceMotion = false

    public init(size: Vec2, home: Vec2 = Vec2(0.68, 0.36), tuning: Tuning = Tuning()) {
        self.tuning = tuning
        self.size = size
        self.home = home
        chase = ChaseSpring(at: Vec2(home.x * size.x, home.y * size.y), leaderStiffness: tuning.leaderStiffness,
                            followerStiffness: tuning.followerStiffness, followerDamping: tuning.followerDamping)
    }

    public mutating func setSize(_ s: Vec2) {
        guard s.x.isFinite, s.y.isFinite, s.x > 0, s.y > 0, s != size else { return }
        let k = Vec2(s.x / size.x, s.y / size.y)
        size = s
        let p = chase.position
        chase = ChaseSpring(at: Vec2(p.x * k.x, p.y * k.y), leaderStiffness: tuning.leaderStiffness,
                            followerStiffness: tuning.followerStiffness, followerDamping: tuning.followerDamping)
    }

    public mutating func setFinger(_ p: Vec2?) {
        if let p, !(p.x.isFinite && p.y.isFinite) { return }
        finger = p
    }

    public mutating func setPalette(_ index: Int) {
        let i = min(max(index, 0), BlobPalette.all.count - 1)
        guard i != palette else { return }
        // Restart the fade from whatever is on screen now.
        previousPalette = paletteProgress < 0.5 ? previousPalette : palette
        palette = i
        paletteProgress = reduceMotion ? 1 : 0
    }

    /// Idle target at `time`: a slow Lissajous loop around home.
    public func orbit(at t: Double) -> Vec2 {
        if reduceMotion { return Vec2(home.x * size.x, home.y * size.y) }
        return Vec2((home.x + tuning.orbitAmplitude.x * sin(tuning.orbitSpeeds.x * t)) * size.x,
                    (home.y + tuning.orbitAmplitude.y * sin(tuning.orbitSpeeds.y * t + 1.3)) * size.y)
    }

    public var target: Vec2 { finger ?? orbit(at: time) }

    public mutating func step(_ dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        var remaining = min(dt, WhimsySpring.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, WhimsySpring.maxSubstep)
            time += h
            let goal = target
            if reduceMotion {
                // One critically damped stage: no lag-and-overshoot.
                chase.leader.snap(to: chase.follower.value)
                chase.follower.x.dampingRatio = 1; chase.follower.y.dampingRatio = 1
                chase.follower.substep(toward: goal, h: h)
            } else {
                chase.follower.x.dampingRatio = tuning.followerDamping; chase.follower.y.dampingRatio = tuning.followerDamping
                chase.substep(toward: goal, h: h)
            }
            paletteProgress = min(paletteProgress + h / max(tuning.paletteFade, 1e-6), 1)
            remaining -= h
        }
    }

    public var center: Vec2 { chase.position }
    public var velocity: Vec2 { reduceMotion ? .zero : chase.velocity }
    public var stretch: Double { tuning.morph.stretch(for: velocity) }

    public func outline(samples: Int = 96) -> [Vec2] {
        tuning.morph.outline(time: time, velocity: velocity, samples: samples, wobble: !reduceMotion)
    }

    public var meshPoints: [Vec2] {
        MeshField.points(time: reduceMotion ? 0 : time, velocity: velocity, stretchSpeed: tuning.morph.stretchSpeed)
    }

    /// The mesh colours, mid-crossfade if the palette just changed (smoothstep eased).
    public var meshColors: [BlobRGB] {
        let a = BlobPalette.all[previousPalette].colors, b = BlobPalette.all[palette].colors
        let t = WhimsyMath.smoothstep(0, 1, paletteProgress)
        return (0..<9).map { BlobRGB.mix(a[$0], b[$0], t) }
    }
}
