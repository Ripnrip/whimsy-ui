import Foundation

/// Which side of the body a tap landed on. A left hit swings the piñata to the right.
public enum PinataSide: String, Equatable, Sendable {
    case left, right
}

public enum PinataPhase: String, Equatable, Sendable {
    case intact, bursting, spent
}

public enum PinataEvent: Equatable, Sendable {
    /// `index` is 1-based.
    case hit(Int, PinataSide)
    case burst
    case settled
}

public enum PinataParticleKind: Int, Equatable, Sendable {
    case candy = 0
    case confetti = 1
}

public struct PinataParticle: Equatable, Sendable {
    public var kind: PinataParticleKind
    public var position: Vec2
    public var velocity: Vec2
    public var rotation: Double
    public var spin: Double
    public var age: Double
    public var life: Double
    public var size: Double
    public var colorIndex: Int
    public var shape: Int

    public var opacity: Double {
        guard life > 0 else { return 0 }
        return max(0, 1 - age / life)
    }
}

/// A jagged crack in body-local space (origin at the body centre, +x right, +y down).
public struct PinataCrack: Equatable, Sendable {
    public var points: [Vec2]
    public var span: Double
}

public struct PinataHalf: Equatable, Sendable {
    public var side: PinataSide
    public var position: Vec2
    public var velocity: Vec2
    public var angle: Double
    public var angularVelocity: Double
    public var age: Double

    public var opacity: Double { max(0, 1 - age / PinataTuning.halfFade) }
}

/// The reward token that springs up when the body splits. Under Reduce Motion `scale` is the fade.
public struct PinataToken: Equatable, Sendable {
    public var present: Bool
    public var scale: Double
    public var scaleVelocity: Double
    public var offset: Double
    public var offsetVelocity: Double

    public static let hidden = PinataToken(present: false, scale: 0, scaleVelocity: 0, offset: 0, offsetVelocity: 0)
}

/// A damped spring pendulum: angle about the top peg, plus a radial spring for the ribbon.
///
/// θ = 0 hangs straight down. Positive θ swings the body to the right (positive x, y down).
/// One substep reads every acceleration from the state at the start of the step, then
/// updates both velocities, then both positions, then applies the length and angle stops.
/// The web port copies this order.
public struct PinataPendulum: Equatable, Sendable {
    public var angle: Double
    public var omega: Double
    public var length: Double
    public var radialVelocity: Double

    public init() {
        angle = 0
        omega = 0
        length = PinataTuning.restLength
        radialVelocity = 0
    }

    public var bob: Vec2 {
        Vec2(PinataTuning.anchorX + length * PinataMath.sin(angle),
             PinataTuning.anchorY + length * PinataMath.cos(angle))
    }

    /// Velocity of the body centre: radial stretch plus the tangential swing.
    public var tangentialVelocity: Vec2 {
        let s = PinataMath.sin(angle)
        let c = PinataMath.cos(angle)
        return Vec2(radialVelocity * s + omega * length * c,
                    radialVelocity * c - omega * length * s)
    }

    /// Local +y is down the body, local +x is the body's right. θ > 0 rotates the body clockwise
    /// on a y-down screen, so the top of the head stays pointed at the peg.
    public func rotate(_ local: Vec2) -> Vec2 {
        let c = PinataMath.cos(angle)
        let s = PinataMath.sin(angle)
        return Vec2(local.x * c + local.y * s, -local.x * s + local.y * c)
    }

    public func world(_ local: Vec2) -> Vec2 {
        let spun = rotate(local)
        return Vec2(bob.x + spun.x, bob.y + spun.y)
    }

    public func localPoint(_ world: Vec2) -> Vec2 {
        let c = PinataMath.cos(angle)
        let s = PinataMath.sin(angle)
        let dx = world.x - bob.x
        let dy = world.y - bob.y
        return Vec2(dx * c - dy * s, dx * s + dy * c)
    }

    public func contains(_ world: Vec2) -> Bool {
        guard world.x.isFinite, world.y.isFinite else { return false }
        let local = localPoint(world)
        let nx = local.x / (PinataTuning.bodyRadiusX * PinataTuning.hitSlop)
        let ny = local.y / (PinataTuning.bodyRadiusY * PinataTuning.hitSlop)
        return nx * nx + ny * ny <= 1
    }

    public mutating func snapToRest() {
        angle = 0
        omega = 0
        length = PinataTuning.restLength
        radialVelocity = 0
    }

    public mutating func substep(_ h: Double) {
        guard h > 0, h.isFinite else { return }
        let s = PinataMath.sin(angle)
        let radialAcc = length * omega * omega
            - PinataTuning.radialStiffness * (length - PinataTuning.restLength)
            - PinataTuning.radialDamping * radialVelocity
        let angularAcc = -(PinataTuning.gravity / length) * s
            - PinataTuning.torsion * angle
            - PinataTuning.angularDamping * omega
            - 2 * radialVelocity * omega / length
        radialVelocity += radialAcc * h
        omega += angularAcc * h
        length += radialVelocity * h
        angle += omega * h
        if length < PinataTuning.minLength {
            length = PinataTuning.minLength
            radialVelocity = 0
        } else if length > PinataTuning.maxLength {
            length = PinataTuning.maxLength
            radialVelocity = 0
        }
        if angle > PinataTuning.maxAngle {
            angle = PinataTuning.maxAngle
            omega = 0
        } else if angle < -PinataTuning.maxAngle {
            angle = -PinataTuning.maxAngle
            omega = 0
        }
    }
}

/// Hit counting, the spring pendulum, seeded candy, cracks, and the burst.
///
/// Eight taps (by default) split the body. Each tap is a larger impulse than the last,
/// aimed by which side was hit, and throws 6…10 seeded candies. Reduce Motion keeps the
/// body still, spawns nothing, and fades the token in.
public struct PinataModel: Equatable, Sendable {
    public let hitsToBreak: Int
    public let seed: UInt64
    public private(set) var reduceMotion: Bool
    public private(set) var phase: PinataPhase
    public private(set) var hits: Int
    public private(set) var pendulum: PinataPendulum
    public private(set) var glow: Double
    public private(set) var particles: [PinataParticle]
    public private(set) var cracks: [PinataCrack]
    public private(set) var halves: [PinataHalf]
    public private(set) var token: PinataToken
    public private(set) var burstAge: Double

    public init(hitsToBreak: Int = PinataTuning.defaultHits,
                seed: UInt64 = PinataTuning.defaultSeed,
                reduceMotion: Bool = false) {
        self.hitsToBreak = PinataTuning.clampedHits(hitsToBreak)
        self.seed = seed
        self.reduceMotion = reduceMotion
        phase = .intact
        hits = 0
        pendulum = PinataPendulum()
        glow = 0
        particles = []
        cracks = []
        halves = []
        token = .hidden
        burstAge = 0
    }

    public var angle: Double { pendulum.angle }
    public var omega: Double { pendulum.omega }
    public var length: Double { pendulum.length }
    public var radialVelocity: Double { pendulum.radialVelocity }
    public var bodyCenter: Vec2 { pendulum.bob }

    public var pillText: String {
        phase == .intact ? PinataTuning.keepTapping : PinataTuning.comeBack
    }

    /// VoiceOver value: "3 of 8" while it still hangs, then "Come back tomorrow".
    public var accessibilityValue: String {
        phase == .intact ? "\(hits) of \(hitsToBreak)" : PinataTuning.comeBack
    }

    public var progress: Double { Double(hits) / Double(max(hitsToBreak, 1)) }

    /// 0…1 fade used by Reduce Motion. 0 while the body is intact.
    public var reveal: Double {
        guard phase != .intact else { return 0 }
        if !reduceMotion { return phase == .spent ? 1 : min(1, burstAge / PinataTuning.burstDuration) }
        return min(1, burstAge / PinataTuning.fadeDuration)
    }

    public var isAtRest: Bool {
        if phase == .bursting { return false }
        if glow > 0.01 || !particles.isEmpty { return false }
        if halves.contains(where: { $0.opacity > 0.02 }) { return false }
        if phase == .intact {
            return abs(angle) < 1e-3 && abs(omega) < 1e-2
                && abs(length - PinataTuning.restLength) < 0.05
                && abs(radialVelocity) < 0.5
        }
        return true
    }

    /// Where the token is drawn: the resting spot of the body, plus the spring offset (y down).
    public var tokenPosition: Vec2 {
        Vec2(PinataTuning.anchorX, PinataTuning.anchorY + PinataTuning.restLength + token.offset)
    }

    // MARK: input

    /// Tap in canvas points. Misses and taps after the burst do nothing.
    public mutating func hit(at point: Vec2) -> [PinataEvent] {
        guard phase == .intact else { return [] }
        guard point.x.isFinite, point.y.isFinite, pendulum.contains(point) else { return [] }
        let local = pendulum.localPoint(point)
        let side: PinataSide = local.x < 0 ? .left : .right
        return apply(side, impact: local)
    }

    /// A scripted strike on one side of the body, through the same hit test as a tap.
    public mutating func strike(_ side: PinataSide) -> [PinataEvent] {
        let x = (side == .left ? -1.0 : 1.0) * PinataTuning.bodyRadiusX * 0.4
        return hit(at: pendulum.world(Vec2(x, 0)))
    }

    /// VoiceOver's Hit action. Sides alternate, starting on the left, so progress still moves.
    public mutating func hitForAccessibility() -> [PinataEvent] {
        strike(hits % 2 == 0 ? .left : .right)
    }

    public mutating func reset() {
        self = PinataModel(hitsToBreak: hitsToBreak, seed: seed, reduceMotion: reduceMotion)
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on {
            pendulum.snapToRest()
            particles.removeAll()
            halves.removeAll()
            token.offset = 0
            token.offsetVelocity = 0
            token.scaleVelocity = 0
            if phase != .intact {
                token.present = true
                token.scale = min(1, burstAge / PinataTuning.fadeDuration)
            }
        }
    }

    // MARK: time

    /// Advances by `dt` seconds. Non-finite or non-positive input is ignored.
    /// A stalled frame is clamped to `PinataTuning.maxFrame` and split into ≤ 1/240 s substeps.
    public mutating func step(_ dt: Double) -> [PinataEvent] {
        guard dt > 0, dt.isFinite else { return [] }
        var remaining = min(dt, PinataTuning.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, PinataTuning.substep)
            substep(h)
            remaining -= h
        }
        if phase == .bursting {
            let limit = reduceMotion ? PinataTuning.fadeDuration : PinataTuning.burstDuration
            if burstAge >= limit - 1e-9 {
                phase = .spent
                return [.settled]
            }
        }
        return []
    }

    // MARK: private

    private mutating func apply(_ side: PinataSide, impact: Vec2) -> [PinataEvent] {
        let index = hits + 1
        let scale = PinataTuning.hitScale(forHit: index)
        if !reduceMotion {
            let sign = side == .left ? 1.0 : -1.0
            pendulum.omega += sign * PinataTuning.impulse(forHit: index)
            pendulum.radialVelocity += PinataTuning.radialKick * scale
        }
        glow = 1
        hits = index
        var rng = SeededRandom(seed: PinataTuning.hitSeed(seed, index))
        if !reduceMotion {
            spawnCandy(side: side, impact: impact, scale: scale, rng: &rng)
        }
        cracks.append(makeCrack(side: side, hit: index, rng: &rng))
        var events: [PinataEvent] = [.hit(index, side)]
        if hits >= hitsToBreak {
            beginBurst(scale: scale, rng: &rng)
            events.append(.burst)
        }
        return events
    }

    private mutating func beginBurst(scale: Double, rng: inout SeededRandom) {
        phase = .bursting
        burstAge = 0
        token.present = true
        token.scale = 0
        token.scaleVelocity = 0
        if reduceMotion {
            token.offset = 0
            token.offsetVelocity = 0
            halves = []
            return
        }
        token.offset = PinataTuning.tokenDrop
        token.offsetVelocity = 0
        let bob = pendulum.bob
        let carry = pendulum.tangentialVelocity
        let outward = pendulum.rotate(Vec2(1, 0))
        let up = pendulum.rotate(Vec2(0, -1))
        halves = [makeHalf(.left, -1, bob: bob, carry: carry, outward: outward, up: up, scale: scale),
                  makeHalf(.right, 1, bob: bob, carry: carry, outward: outward, up: up, scale: scale)]
        spawnConfetti(scale: scale, rng: &rng)
    }

    private func makeHalf(_ side: PinataSide, _ sign: Double, bob: Vec2, carry: Vec2,
                          outward: Vec2, up: Vec2, scale: Double) -> PinataHalf {
        PinataHalf(side: side,
                   position: bob + outward * (sign * PinataTuning.halfGap),
                   velocity: carry + outward * (sign * PinataTuning.halfSpeed * scale) + up * (PinataTuning.halfLift * scale),
                   angle: pendulum.angle,
                   angularVelocity: sign * PinataTuning.halfSpin * scale,
                   age: 0)
    }

    private mutating func spawnCandy(side: PinataSide, impact: Vec2, scale: Double, rng: inout SeededRandom) {
        let span = PinataTuning.candyMax - PinataTuning.candyMin + 1
        let count = PinataTuning.candyMin + Int(rng.next() % UInt64(span))
        let origin = pendulum.world(impact)
        let carry = pendulum.tangentialVelocity
        let base = side == .left ? PinataMath.pi : 0
        for _ in 0..<count {
            let heading = base + rng.uniform(-PinataTuning.candySpread...PinataTuning.candySpread)
            let speed = rng.uniform(PinataTuning.candySpeedMin...PinataTuning.candySpeedMax) * scale
            let life = rng.uniform(PinataTuning.candyLifeMin...PinataTuning.candyLifeMax)
            let size = rng.uniform(PinataTuning.candySizeMin...PinataTuning.candySizeMax)
            let spin = rng.uniform(-PinataTuning.candySpin...PinataTuning.candySpin)
            let color = Int(rng.next() % UInt64(PinataTuning.candyColors))
            let shape = Int(rng.next() % 3)
            let local = Vec2(PinataMath.cos(heading) * speed, PinataMath.sin(heading) * speed)
            let velocity = pendulum.rotate(local) + carry
            particles.append(PinataParticle(kind: .candy, position: origin, velocity: velocity,
                                            rotation: 0, spin: spin, age: 0, life: life,
                                            size: size, colorIndex: color, shape: shape))
        }
    }

    private mutating func spawnConfetti(scale: Double, rng: inout SeededRandom) {
        let origin = pendulum.bob
        let count = PinataTuning.confettiCount
        for i in 0..<count {
            let ring = (Double(i) + 0.5) / Double(count) * PinataMath.twoPi
            let heading = ring + rng.uniform(-0.15...0.15)
            let speed = rng.uniform(PinataTuning.confettiSpeedMin...PinataTuning.confettiSpeedMax) * scale
            let life = rng.uniform(PinataTuning.confettiLifeMin...PinataTuning.confettiLifeMax)
            let size = rng.uniform(PinataTuning.confettiSizeMin...PinataTuning.confettiSizeMax)
            let spin = rng.uniform(-PinataTuning.confettiSpin...PinataTuning.confettiSpin)
            let color = Int(rng.next() % UInt64(PinataTuning.candyColors))
            let shape = Int(rng.next() % 3)
            let velocity = Vec2(PinataMath.cos(heading) * speed, PinataMath.sin(heading) * speed)
            particles.append(PinataParticle(kind: .confetti, position: origin, velocity: velocity,
                                            rotation: heading, spin: spin, age: 0, life: life,
                                            size: size, colorIndex: color, shape: shape))
        }
    }

    private func makeCrack(side: PinataSide, hit: Int, rng: inout SeededRandom) -> PinataCrack {
        let sign = side == .left ? -1.0 : 1.0
        let x0 = sign * rng.uniform(PinataTuning.crackXMin...PinataTuning.crackXMax) * PinataTuning.bodyRadiusX
        let y0 = rng.uniform(PinataTuning.crackYMin...PinataTuning.crackYMax) * PinataTuning.bodyRadiusY
        let heading = (side == .left ? PinataMath.pi : 0) + rng.uniform(-0.85...0.85)
        let jag = rng.uniform(-10...10)
        let span = PinataTuning.crackBase + PinataTuning.crackGrowth * Double(hit - 1)
        let dir = Vec2(PinataMath.cos(heading), PinataMath.sin(heading))
        let nrm = Vec2(-dir.y, dir.x)
        let p0 = Vec2(x0, y0)
        let p1 = p0 + dir * (span * 0.5) + nrm * jag
        let p2 = p0 + dir * span
        return PinataCrack(points: [p0, p1, p2], span: span)
    }

    private mutating func substep(_ h: Double) {
        if reduceMotion {
            pendulum.snapToRest()
            particles.removeAll()
            decayGlow(h)
            guard phase != .intact else { return }
            burstAge += h
            token.present = true
            token.offset = 0
            token.offsetVelocity = 0
            token.scaleVelocity = 0
            token.scale = min(1, burstAge / PinataTuning.fadeDuration)
            return
        }
        if phase == .intact {
            pendulum.substep(h)
        }
        decayGlow(h)
        integrateParticles(h)
        guard phase != .intact else { return }
        integrateHalves(h)
        integrateToken(h)
        burstAge += h
    }

    private mutating func decayGlow(_ h: Double) {
        guard glow > 0 else { return }
        glow *= PinataMath.exp(-PinataTuning.glowDecay * h)
        if glow < 1e-4 { glow = 0 }
    }

    private mutating func integrateParticles(_ h: Double) {
        var kept: [PinataParticle] = []
        kept.reserveCapacity(particles.count)
        for var p in particles {
            p.age += h
            if p.age >= p.life { continue }
            let drag = p.kind == .candy ? PinataTuning.candyDrag : PinataTuning.confettiDrag
            let gravity = p.kind == .candy ? PinataTuning.candyGravity : PinataTuning.confettiGravity
            let d = PinataMath.exp(-drag * h)
            p.velocity.y += gravity * h
            p.velocity.x *= d
            p.velocity.y *= d
            p.position.x += p.velocity.x * h
            p.position.y += p.velocity.y * h
            p.rotation += p.spin * h
            kept.append(p)
        }
        particles = kept
    }

    private mutating func integrateHalves(_ h: Double) {
        for i in halves.indices {
            halves[i].velocity.y += PinataTuning.halfGravity * h
            halves[i].position.x += halves[i].velocity.x * h
            halves[i].position.y += halves[i].velocity.y * h
            halves[i].angularVelocity *= PinataMath.exp(-PinataTuning.halfSpinDrag * h)
            halves[i].angle += halves[i].angularVelocity * h
            halves[i].age += h
        }
    }

    private mutating func integrateToken(_ h: Double) {
        guard token.present else { return }
        var scale = WhimsySpring(value: token.scale, velocity: token.scaleVelocity,
                                 stiffness: PinataTuning.tokenStiffness, dampingRatio: PinataTuning.tokenDamping)
        scale.substep(toward: 1, h: h)
        var offset = WhimsySpring(value: token.offset, velocity: token.offsetVelocity,
                                  stiffness: PinataTuning.tokenStiffness, dampingRatio: PinataTuning.tokenDamping)
        offset.substep(toward: 0, h: h)
        token.scale = scale.value
        token.scaleVelocity = scale.velocity
        token.offset = offset.value
        token.offsetVelocity = offset.velocity
    }
}
