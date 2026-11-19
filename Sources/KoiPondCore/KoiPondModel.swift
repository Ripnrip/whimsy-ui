import Foundation

public enum KoiPondPhase: String, Equatable, Sendable {
    case laps
    case arming
    case gathering
    case scattering
    case returning
}

public enum KoiFishMode: String, Equatable, Sendable {
    case lap
    case seeking
    case waiting
    case nibbling
    case scattering
    case returning
}

public enum KoiRippleKind: String, Equatable, Sendable {
    case gather
    case nibble
}

public struct KoiRipple: Equatable, Sendable {
    public var origin: Vec2
    public var age: Double
    public var lifetime: Double
    public var maxRadius: Double
    public var kind: KoiRippleKind
    public var reduceMotion: Bool

    public var alive: Bool { age < lifetime }

    /// Expanding ring, or a fixed disc when Reduce Motion asked for a fade instead.
    public var radius: Double {
        let life = max(lifetime, 1e-6)
        let u = min(max(age / life, 0), 1)
        if reduceMotion {
            return kind == .gather ? KoiPondTuning.reduceGatherRadius : KoiPondTuning.reduceNibbleRadius
        }
        let eased = 1 - (1 - u) * (1 - u) * (1 - u)
        return maxRadius * eased
    }

    public var opacity: Double {
        let life = max(lifetime, 1e-6)
        let u = min(max(age / life, 0), 1)
        if reduceMotion { return (1 - u) * 0.65 }
        let fadeIn = min(1, age / 0.08)
        return (1 - u) * fadeIn
    }
}

public enum KoiPondEvent: Equatable, Sendable {
    /// One peck. The view plays a light impact and calls `onNibble`.
    case nibble(Int)
    case released
    case returned
}

public struct KoiFish: Equatable, Sendable {
    public let index: Int
    public var spine: [Vec2]
    public var heading: Double
    public var mode: KoiFishMode
    public var lapAngle: Double
    public var lapOmega: Double
    public var orbitScale: Double
    public var tailPhase: Double
    public var bobSample: Double
    public var modeTime: Double
    public var nibbleHeading: Double
    public var scatterHeading: Double
    public var paletteIndex: Int

    public var head: Vec2 { spine[0] }

    public var palette: KoiPalette {
        let palettes = KoiPondTuning.palettes
        return palettes[paletteIndex % palettes.count]
    }

    /// Spine with a sine bend that grows toward the tail. Segment lengths stay `segmentLength`.
    /// The bend is a function of `time` and the constrained spine, so it does not accumulate.
    public func posedSpine(at time: Double) -> [Vec2] {
        guard spine.count >= 2, time.isFinite else { return spine }
        var out = spine
        let last = Double(spine.count - 1)
        for i in 1..<spine.count {
            let dx = spine[i].x - spine[i - 1].x
            let dy = spine[i].y - spine[i - 1].y
            let base = KoiPondMath.atan2(dy, dx)
            let envelope = Double(i) / last
            let wave = KoiPondMath.sin(
                KoiPondTuning.tailOmega * time + tailPhase - Double(i) * KoiPondTuning.tailLag
            ) * KoiPondTuning.tailAmplitude * envelope
            let angle = base + wave
            out[i] = Vec2(
                out[i - 1].x + KoiPondMath.cos(angle) * KoiPondTuning.segmentLength,
                out[i - 1].y + KoiPondMath.sin(angle) * KoiPondTuning.segmentLength
            )
        }
        return out
    }
}

/// Top-down pond. Six koi lap until a fingertip is held, then come in one after another,
/// bob, and nibble. Letting go scatters them; they drift back to the laps.
///
/// `step` integrates in fixed slices of `KoiPondTuning.fixedStep` and ignores a frame longer
/// than `maxFrame`. The same seed and the same touches produce the same pond on every platform.
public struct KoiPondModel: Equatable, Sendable {
    public private(set) var phase: KoiPondPhase
    public private(set) var fish: [KoiFish]
    public private(set) var ripples: [KoiRipple]
    public private(set) var time: Double
    public private(set) var swimTime: Double
    public private(set) var finger: Vec2
    public private(set) var armTime: Double
    public private(set) var gatherTime: Double
    public private(set) var reduceMotion: Bool
    public private(set) var arrivalOrder: [Int]
    public private(set) var nibbleCount: Int
    public let seed: UInt64

    private var scriptedRelease: Double?
    private var announcedReturn = false

    public var koiCount: Int { fish.count }
    public var holding: Bool { phase == .gathering }

    public var accessibilityLabel: String { "Pond, \(koiCount) koi" }
    public var accessibilityValue: String {
        phase == .gathering ? KoiPondTuning.nibblingValue : KoiPondTuning.swimmingValue
    }

    public init(
        koiCount: Int = KoiPondTuning.defaultCount,
        seed: UInt64 = KoiPondTuning.defaultSeed,
        reduceMotion: Bool = false
    ) {
        let count = min(max(koiCount, 1), KoiPondTuning.maxKoi)
        var rng = SeededRandom(seed: seed)
        var school: [KoiFish] = []
        school.reserveCapacity(count)
        for index in 0..<count {
            let orbit = rng.uniform(KoiPondTuning.orbitMin...KoiPondTuning.orbitMax)
            let jitter = rng.uniform(-KoiPondTuning.orbitJitter...KoiPondTuning.orbitJitter)
            let spacing = KoiPondMath.twoPi / Double(count)
            let angle = KoiPondMath.wrap((Double(index) + 0.5) * spacing + jitter)
            let omegaMag = rng.uniform(KoiPondTuning.omegaMin...KoiPondTuning.omegaMax)
            let omega = omegaMag * (rng.uniform(0...1) < 0.5 ? -1 : 1)
            let tailPhase = rng.uniform(0...KoiPondMath.twoPi)
            let heading = KoiPondMath.wrap(angle + (omega >= 0 ? KoiPondMath.halfPi : -KoiPondMath.halfPi))
            let head = KoiPondTuning.lapPoint(angle: angle, scale: orbit)
            var spine = [Vec2](repeating: head, count: KoiPondTuning.spineCount)
            for joint in 1..<KoiPondTuning.spineCount {
                spine[joint] = Vec2(
                    spine[joint - 1].x - KoiPondMath.cos(heading) * KoiPondTuning.segmentLength,
                    spine[joint - 1].y - KoiPondMath.sin(heading) * KoiPondTuning.segmentLength
                )
            }
            school.append(KoiFish(
                index: index,
                spine: spine,
                heading: heading,
                mode: .lap,
                lapAngle: angle,
                lapOmega: omega,
                orbitScale: orbit,
                tailPhase: tailPhase,
                bobSample: 0,
                modeTime: 0,
                nibbleHeading: heading,
                scatterHeading: heading,
                paletteIndex: index % KoiPondTuning.palettes.count
            ))
        }
        self.phase = .laps
        self.fish = school
        self.ripples = []
        self.time = 0
        self.swimTime = 0
        self.finger = KoiPondTuning.feedPoint
        self.armTime = 0
        self.gatherTime = 0
        self.reduceMotion = reduceMotion
        self.arrivalOrder = []
        self.nibbleCount = 0
        self.seed = seed
        self.scriptedRelease = nil
    }

    public mutating func setReduceMotion(_ on: Bool) {
        let was = reduceMotion
        reduceMotion = on
        guard on, !was else { return }
        if phase == .scattering { phase = .returning }
        for i in fish.indices where fish[i].mode == .scattering {
            fish[i].mode = .returning
            fish[i].modeTime = 0
        }
    }

    /// Pointer down. The gather commits once the press has lasted `longPress`.
    @discardableResult
    public mutating func beginTouch(at point: Vec2) -> [KoiPondEvent] {
        guard let p = finite(point) else { return [] }
        finger = KoiPondTuning.clampFinger(p)
        if phase == .arming || phase == .gathering { return [] }
        phase = .arming
        armTime = 0
        scriptedRelease = nil
        spawnRipple(at: finger, kind: .gather)
        return []
    }

    public mutating func updateTouch(at point: Vec2) {
        guard phase == .arming || phase == .gathering else { return }
        guard let p = finite(point) else { return }
        finger = KoiPondTuning.clampFinger(p)
    }

    /// Pointer up. A short press cancels. A committed hold scatters, or drifts home under Reduce Motion.
    @discardableResult
    public mutating func endTouch() -> [KoiPondEvent] {
        if phase == .arming {
            phase = .laps
            return []
        }
        if phase == .gathering { return releaseHold() }
        return []
    }

    /// VoiceOver's Feed koi. Gathers at the middle of the pond, then lets go.
    @discardableResult
    public mutating func feed() -> [KoiPondEvent] {
        if phase == .gathering { return [] }
        finger = KoiPondTuning.clampFinger(KoiPondTuning.feedPoint)
        spawnRipple(at: finger, kind: .gather)
        commitGather(scripted: true)
        return []
    }

    /// Advances the pond. Non-finite or non-positive `dt` is ignored. A frame longer than
    /// `maxFrame` is clamped, then sliced into fixed steps.
    @discardableResult
    public mutating func step(_ dt: Double) -> [KoiPondEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        var remaining = min(dt, KoiPondTuning.maxFrame)
        var events: [KoiPondEvent] = []
        while remaining > 1e-12 {
            let h = min(remaining, KoiPondTuning.fixedStep)
            events.append(contentsOf: integrate(h))
            remaining -= h
        }
        return events
    }

    // MARK: - integration

    private mutating func integrate(_ dt: Double) -> [KoiPondEvent] {
        time += dt
        let clockScale = reduceMotion ? KoiPondTuning.reduceScale : 1
        swimTime += dt * clockScale
        ageRipples(dt)

        if phase == .arming {
            armTime += dt
            if armTime >= KoiPondTuning.longPress {
                commitGather(scripted: false)
            }
        }

        var events: [KoiPondEvent] = []
        if phase == .gathering {
            gatherTime += dt
            if let release = scriptedRelease, time >= release {
                events.append(contentsOf: releaseHold())
            }
        }

        switch phase {
        case .laps, .arming:
            for i in fish.indices { lap(i, dt: dt) }
        case .gathering:
            events.append(contentsOf: gather(dt))
        case .scattering:
            scatter(dt)
            if fish.allSatisfy({ $0.mode != .scattering }) { phase = .returning }
        case .returning:
            returnHome(dt)
            if fish.allSatisfy({ $0.mode == .lap }) {
                phase = .laps
                if !announcedReturn {
                    announcedReturn = true
                    events.append(.returned)
                }
            }
        }
        return events
    }

    private mutating func commitGather(scripted: Bool) {
        phase = .gathering
        gatherTime = 0
        arrivalOrder = []
        announcedReturn = false
        scriptedRelease = scripted ? time + KoiPondTuning.feedDuration : nil
        for i in fish.indices where fish[i].mode != .lap {
            fish[i].mode = .lap
            fish[i].modeTime = 0
        }
    }

    private mutating func releaseHold() -> [KoiPondEvent] {
        scriptedRelease = nil
        let burst = !reduceMotion
        for i in fish.indices {
            fish[i].modeTime = 0
            if burst {
                fish[i].scatterHeading = scatterHeading(for: i)
                fish[i].mode = .scattering
            } else {
                fish[i].mode = .returning
            }
        }
        phase = burst ? .scattering : .returning
        announcedReturn = false
        return [.released]
    }

    private func scatterHeading(for index: Int) -> Double {
        let fish = fish[index]
        let dx = fish.head.x - finger.x
        let dy = fish.head.y - finger.y
        var away = KoiPondMath.atan2(dy, dx)
        if dx * dx + dy * dy < 1 {
            away = KoiPondMath.wrap(fish.heading + KoiPondMath.pi)
        }
        let fan = (Double(index) - Double(koiCount - 1) / 2) * KoiPondTuning.scatterFan
        return KoiPondMath.wrap(away + fan)
    }

    private mutating func lap(_ index: Int, dt: Double) {
        let scale = reduceMotion ? KoiPondTuning.reduceScale : 1
        fish[index].mode = .lap
        fish[index].lapAngle = KoiPondMath.wrap(fish[index].lapAngle + fish[index].lapOmega * dt * scale)
        let aim = lapAim(index)
        drive(index, toward: aim, speed: KoiPondTuning.lapSpeed * scale, dt: dt)
    }

    private func lapAim(_ index: Int) -> Vec2 {
        let fish = fish[index]
        let sign = fish.lapOmega >= 0 ? 1.0 : -1.0
        return KoiPondTuning.lapPoint(
            angle: fish.lapAngle + sign * KoiPondTuning.lapLookahead,
            scale: fish.orbitScale
        )
    }

    private mutating func gather(_ dt: Double) -> [KoiPondEvent] {
        let already = fish.map { $0.mode == .nibbling }
        var events: [KoiPondEvent] = []
        for i in fish.indices {
            let delay = Double(i) * KoiPondTuning.stagger
            if gatherTime + 1e-9 < delay {
                lap(i, dt: dt)
                continue
            }
            if fish[i].mode == .lap || fish[i].mode == .returning || fish[i].mode == .scattering {
                fish[i].mode = .seeking
                fish[i].modeTime = 0
            }
            let predecessor = i == 0 || already[i - 1]
            if let event = seek(i, predecessor: predecessor, dt: dt) {
                events.append(event)
            }
        }
        return events
    }

    private mutating func seek(_ index: Int, predecessor: Bool, dt: Double) -> KoiPondEvent? {
        if fish[index].mode == .nibbling {
            return nibble(index, dt: dt)
        }
        let dist = fish[index].head.distance(to: finger)
        if predecessor && dist <= KoiPondTuning.arriveRadius {
            return arrive(index, dt: dt)
        }
        if !predecessor && dist <= KoiPondTuning.holdRadius {
            fish[index].mode = .waiting
            let desired = KoiPondMath.atan2(finger.y - fish[index].head.y, finger.x - fish[index].head.x)
            fish[index].heading = KoiPondMath.turn(
                fish[index].heading,
                toward: desired,
                rate: KoiPondTuning.turnRate,
                dt: dt
            )
            fish[index].modeTime += dt
            return nil
        }
        fish[index].mode = .seeking
        let scale = reduceMotion ? KoiPondTuning.reduceScale : 1
        var speed = KoiPondTuning.seekSpeed * scale
        if dist < KoiPondTuning.arriveSlow {
            speed *= max(0.22, dist / KoiPondTuning.arriveSlow)
        }
        drive(index, toward: finger, speed: speed, dt: dt)
        fish[index].modeTime += dt
        return nil
    }

    private mutating func arrive(_ index: Int, dt: Double) -> KoiPondEvent? {
        let dx = finger.x - fish[index].head.x
        let dy = finger.y - fish[index].head.y
        fish[index].nibbleHeading = KoiPondMath.atan2(dy, dx)
        fish[index].heading = fish[index].nibbleHeading
        fish[index].mode = .nibbling
        fish[index].modeTime = 0
        fish[index].bobSample = KoiPondMath.sin(fish[index].tailPhase)
        arrivalOrder.append(index)
        return nibble(index, dt: dt)
    }

    private mutating func nibble(_ index: Int, dt: Double) -> KoiPondEvent? {
        let scale = reduceMotion ? KoiPondTuning.reduceScale : 1
        let phase = KoiPondTuning.bobOmega * fish[index].modeTime * scale + fish[index].tailPhase
        let sample = KoiPondMath.sin(phase)
        let peck = max(0, sample) * KoiPondTuning.bobAmplitude
        let ux = KoiPondMath.cos(fish[index].nibbleHeading)
        let uy = KoiPondMath.sin(fish[index].nibbleHeading)
        let gap = KoiPondTuning.nibbleGap - peck
        fish[index].heading = fish[index].nibbleHeading
        fish[index].spine[0] = KoiPondTuning.clampHead(Vec2(finger.x - ux * gap, finger.y - uy * gap))
        let heading = fish[index].heading
        KoiPondTuning.constrain(&fish[index].spine, heading: heading)

        var event: KoiPondEvent?
        if fish[index].bobSample < KoiPondTuning.nibbleThreshold && sample >= KoiPondTuning.nibbleThreshold {
            nibbleCount += 1
            spawnRipple(at: fish[index].head, kind: .nibble)
            event = .nibble(index)
        }
        fish[index].bobSample = sample
        fish[index].modeTime += dt
        return event
    }

    private mutating func scatter(_ dt: Double) {
        for i in fish.indices {
            if fish[i].mode == .scattering {
                fish[i].modeTime += dt
                if fish[i].modeTime >= KoiPondTuning.scatterDuration {
                    fish[i].mode = .returning
                    fish[i].modeTime = 0
                } else {
                    let aim = Vec2(
                        fish[i].head.x + KoiPondMath.cos(fish[i].scatterHeading) * 240,
                        fish[i].head.y + KoiPondMath.sin(fish[i].scatterHeading) * 240
                    )
                    drive(i, toward: aim, speed: KoiPondTuning.scatterSpeed, dt: dt, turnRate: KoiPondTuning.scatterTurnRate)
                }
            } else if fish[i].mode == .returning {
                returnOne(i, dt: dt)
            } else if fish[i].mode == .lap {
                lap(i, dt: dt)
            }
        }
    }

    private mutating func returnHome(_ dt: Double) {
        for i in fish.indices {
            if fish[i].mode == .lap {
                lap(i, dt: dt)
            } else {
                returnOne(i, dt: dt)
            }
        }
    }

    private mutating func returnOne(_ index: Int, dt: Double) {
        let scale = reduceMotion ? KoiPondTuning.reduceScale : 1
        fish[index].mode = .returning
        fish[index].lapAngle = KoiPondMath.wrap(fish[index].lapAngle + fish[index].lapOmega * dt * scale)
        let aim = lapAim(index)
        drive(index, toward: aim, speed: KoiPondTuning.lapSpeed * scale, dt: dt)
        fish[index].modeTime += dt
        if fish[index].head.distance(to: aim) <= KoiPondTuning.returnCatch || fish[index].modeTime >= KoiPondTuning.returnTimeout {
            fish[index].mode = .lap
            fish[index].modeTime = 0
        }
    }

    private mutating func drive(_ index: Int, toward aim: Vec2, speed: Double, dt: Double, turnRate: Double = KoiPondTuning.turnRate) {
        let desired = KoiPondMath.atan2(aim.y - fish[index].head.y, aim.x - fish[index].head.x)
        let heading = KoiPondMath.turn(fish[index].heading, toward: desired, rate: turnRate, dt: dt)
        fish[index].heading = heading
        let step = speed * dt
        let next = Vec2(
            fish[index].head.x + KoiPondMath.cos(heading) * step,
            fish[index].head.y + KoiPondMath.sin(heading) * step
        )
        fish[index].spine[0] = KoiPondTuning.clampHead(next)
        KoiPondTuning.constrain(&fish[index].spine, heading: heading)
    }

    private mutating func ageRipples(_ dt: Double) {
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age >= $0.lifetime }
    }

    private mutating func spawnRipple(at origin: Vec2, kind: KoiRippleKind) {
        let ripple = KoiRipple(
            origin: origin,
            age: 0,
            lifetime: kind == .gather ? KoiPondTuning.gatherLife : KoiPondTuning.nibbleLife,
            maxRadius: kind == .gather ? KoiPondTuning.gatherRadius : KoiPondTuning.nibbleRadius,
            kind: kind,
            reduceMotion: reduceMotion
        )
        ripples.append(ripple)
        if ripples.count > KoiPondTuning.maxRipples {
            ripples.removeFirst(ripples.count - KoiPondTuning.maxRipples)
        }
    }

    private func finite(_ point: Vec2) -> Vec2? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }
}
