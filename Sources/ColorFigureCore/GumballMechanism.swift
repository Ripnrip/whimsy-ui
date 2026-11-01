import Foundation

public enum GumballPhase: String, Equatable, Sendable {
    /// Nothing inserted. The crank is locked.
    case ready
    /// The coin is on its way into the slot.
    case coinDropping
    /// The coin has landed and the pawl is clear; the crank is free.
    case unlocked
    /// The crank is part-way round.
    case turning
    /// One turn is done: the gumball drops, rolls out and the machine resets.
    case dispensing
}

public enum GumballHaptic: Equatable, Sendable { case coin, detent, gumball }

public enum GumballEvent: Equatable, Sendable {
    case coinInserted, coinLanded, unlocked
    case coinRefused
    case crankLocked
    case crankStarted
    case detent(Int)
    case turnComplete
    case gumballReleased
    case gumballOut
    case ready
}

/// Where the dropped gumball is at a moment of the dispense.
public struct GumballDispenseSample: Equatable, Sendable {
    public var centre: Vec3
    public var alpha: Double
    /// 0 flap shut, 1 fully open.
    public var flap: Double
    /// True while the ball is inside the chute (for the label).
    public var inChute: Bool
}

/// The machine's state machine and timelines, free of any view.
public struct GumballMechanism: Sendable {
    // Timings, in seconds
    public static let coinSlide = 0.36
    public static let coinFall = 0.45
    public static let coinTotal = coinSlide + coinFall
    public static let pawlRelease = 0.15
    public static let chuteTime = 0.9
    public static let rollTime = 0.55
    public static let dispenseTotal = 1.75
    public static let reloadStart = 0.2
    public static let reloadTime = 0.5
    public static let reducedDispenseTotal = 0.45
    public static let reducedOutTime = 0.15
    // Crank
    public static let detentCount = 8
    public static let detentStep = 2 * Double.pi / Double(detentCount)
    public static let fullTurn = 2 * Double.pi
    public static let maxCrankSpeed = 7.0
    public static let tapStep = Double.pi / 2
    public static let movingWindow = 0.25
    // Haptics
    public static let hapticGap = 0.06

    public private(set) var phase: GumballPhase = .ready
    public private(set) var time: Double = 0
    public private(set) var phaseAge: Double = 0
    public private(set) var crank: Double = 0
    public private(set) var crankTarget: Double = 0
    public private(set) var pawl: Double = 0
    public private(set) var dispensed = 0
    public private(set) var cycle = 0
    public private(set) var coinsLanded = 0
    public private(set) var coinsInserted = 0
    public private(set) var lockedAge: Double = 99
    public private(set) var sinceCrankMove: Double = 99
    public private(set) var pocketColors: [Int] = [0, 1, 2, 3]
    public private(set) var prizeColor: Int?
    public private(set) var haptics: [GumballHaptic] = []
    public var reduceMotion = false

    private var events: [GumballEvent] = []
    private var lastHaptic = -99.0
    private var hapticFired: Set<Int> = []   // event stages already emitted in this phase

    public init() {}

    // MARK: input

    /// Insert a coin. Only accepted when ready.
    @discardableResult
    public mutating func insertCoin() -> Bool {
        guard phase == .ready else { events.append(.coinRefused); return false }
        phase = .coinDropping
        phaseAge = 0
        coinsInserted += 1
        prizeColor = nil
        hapticFired = []
        events.append(.coinInserted)
        if reduceMotion { landCoin() }
        return true
    }

    /// Push the crank by turning it directly to `angle` (radians, total from the start). Only forward motion counts.
    public mutating func dragCrank(to angle: Double) {
        guard phase == .unlocked || phase == .turning else {
            if phase == .ready || phase == .coinDropping { lock() }
            return
        }
        let a = min(max(angle, crank), Self.fullTurn)
        crankTarget = a
        applyCrank(a)
    }

    /// A tap on the crank: a quarter turn, taken at crank speed.
    public mutating func tapCrank() {
        guard phase == .unlocked || phase == .turning else {
            if phase == .ready || phase == .coinDropping { lock() }
            return
        }
        crankTarget = min(Self.fullTurn, max(crankTarget, crank) + Self.tapStep)
    }

    /// Turn the crank all the way (from VoiceOver or a keyboard).
    public mutating func turnFully() {
        guard phase == .unlocked || phase == .turning else {
            if phase == .ready || phase == .coinDropping { lock() }
            return
        }
        crankTarget = Self.fullTurn
    }

    private mutating func lock() {
        lockedAge = 0
        events.append(.crankLocked)
    }

    // MARK: stepping

    public mutating func advance(by dt: Double) {
        var left = max(0, dt)
        while left > 0 {
            let h = min(left, 1.0 / 120)
            step(h)
            left -= h
        }
    }

    private mutating func step(_ h: Double) {
        time += h
        phaseAge += h
        lockedAge += h
        sinceCrankMove += h
        switch phase {
        case .ready:
            pawl = max(0, pawl - h / Self.pawlRelease)
        case .coinDropping:
            if phaseAge >= Self.coinTotal { landCoin() }
        case .unlocked, .turning:
            pawl = min(1, pawl + h / Self.pawlRelease)
            if crank < crankTarget {
                applyCrank(min(crankTarget, crank + Self.maxCrankSpeed * h))
            }
        case .dispensing:
            pawl = max(0, pawl - h / Self.pawlRelease)
            let total = reduceMotion ? Self.reducedDispenseTotal : Self.dispenseTotal
            let outAt = reduceMotion ? Self.reducedOutTime : Self.chuteTime
            if !hapticFired.contains(2) && phaseAge >= outAt {
                hapticFired.insert(2)
                dispensed += 1
                events.append(.gumballOut)
                buzz(.gumball)
            }
            if phaseAge >= total { finishDispense() }
        }
    }

    private mutating func landCoin() {
        guard phase == .coinDropping else { return }
        coinsLanded += 1
        phase = .unlocked
        phaseAge = 0
        events.append(.coinLanded)
        events.append(.unlocked)
        buzz(.coin)
        if reduceMotion { pawl = 1 }
    }

    private mutating func applyCrank(_ new: Double) {
        let old = crank
        guard new > old else { return }
        crank = new
        sinceCrankMove = 0
        if phase == .unlocked { phase = .turning; phaseAge = 0; events.append(.crankStarted) }
        let before = Int((old / Self.detentStep + 1e-9).rounded(.down))
        let after = Int((new / Self.detentStep + 1e-9).rounded(.down))
        if after > before {
            for i in (before + 1)...after {
                events.append(.detent(i))
                if i < Self.detentCount { buzz(.detent) }
            }
        }
        if new >= Self.fullTurn - 1e-9 {
            crank = Self.fullTurn
            crankTarget = Self.fullTurn
            beginDispense()
        }
    }

    private mutating func beginDispense() {
        phase = .dispensing
        phaseAge = 0
        hapticFired = []
        let station = (cycle + 2) % 4
        prizeColor = pocketColors[station]
        events.append(.turnComplete)
        events.append(.gumballReleased)
    }

    private mutating func finishDispense() {
        // The pocket now at the top gets a new gumball for next time.
        let top = (cycle + 1) % 4
        pocketColors[top] = Int(FigureNoise.hash(91, UInt32(cycle), 5) % 6)
        cycle += 1
        crank = 0
        crankTarget = 0
        phase = .ready
        phaseAge = 0
        events.append(.ready)
    }

    private mutating func buzz(_ h: GumballHaptic) {
        if time - lastHaptic < Self.hapticGap { return }
        lastHaptic = time
        haptics.append(h)
    }

    // MARK: reading state

    /// Drains and returns the events since the last call.
    public mutating func takeEvents() -> [GumballEvent] {
        defer { events = [] }
        return events
    }
    /// Drains and returns the haptics fired since the last call.
    public mutating func takeHaptics() -> [GumballHaptic] {
        defer { haptics = [] }
        return haptics
    }
    public var pendingEvents: [GumballEvent] { events }

    /// The crank as drawn: the real angle plus a wobble when someone pushes against the lock.
    public var crankDisplay: Double {
        crank + (lockedAge < 0.5 ? 0.14 * sin(lockedAge * 42) * exp(-lockedAge * 8) : 0)
    }

    /// The wheel's angle, 4 times slower than the crank and cumulative across cycles.
    public var wheelAngle: Double { Double(cycle) * Double.pi / 2 + crank / GumballLayout.gearRatio }

    public var isCrankFree: Bool { phase == .unlocked || phase == .turning }
    public var crankIsMoving: Bool { (phase == .turning || phase == .unlocked) && (sinceCrankMove < Self.movingWindow || crank < crankTarget) }

    /// Seconds into the coin's journey (nil when no coin is in flight).
    public var coinAge: Double? { phase == .coinDropping ? phaseAge : nil }

    /// The newest coin's centre while it is on its way (nil when it has landed or there is none).
    public var coinPosition: Vec3? {
        guard phase == .coinDropping else { return nil }
        let t = phaseAge
        let start = GumballLayout.coinStart
        if t < Self.coinSlide {
            let u = FigureEase.easeInOutCubic(t / Self.coinSlide)
            return Vec3(start.x + (GumballLayout.coinSlotX - start.x) * u, 0, start.z)
        }
        let u = FigureEase.clamp01((t - Self.coinSlide) / Self.coinFall)
        let z = start.z + (GumballLayout.coinRestZ - start.z) * (u * u)
        return Vec3(GumballLayout.coinSlotX, 0, z)
    }

    /// The pocket holding no gumball right now, and the one being refilled (if any).
    public var emptyPocket: Int { phase == .dispensing ? (cycle + 2) % 4 : (cycle + 1) % 4 }
    public var reloadingPocket: Int? { phase == .dispensing ? (cycle + 1) % 4 : nil }
    /// 0...1 progress of the refill ball dropping from the hopper into its pocket.
    public var reload: Double {
        guard phase == .dispensing, !reduceMotion else { return phase == .dispensing ? 1 : 0 }
        return FigureEase.clamp01((phaseAge - Self.reloadStart) / Self.reloadTime)
    }

    /// The dropped gumball and the flap at the current moment of the dispense, or nil outside one.
    public var dispense: GumballDispenseSample? { Self.sample(at: phaseAge, reduceMotion: reduceMotion, phase: phase) }

    public static func sample(at t: Double, reduceMotion: Bool, phase: GumballPhase = .dispensing) -> GumballDispenseSample? {
        guard phase == .dispensing else { return nil }
        let path = GumballLayout.ballPath
        let rest = path[path.count - 1]
        if reduceMotion {
            let a = FigureEase.clamp01((t - reducedOutTime + 0.15) / 0.15)
            return GumballDispenseSample(centre: rest, alpha: a, flap: 0, inChute: false)
        }
        let flap = flapOpenness(at: t)
        if t <= chuteTime {
            let lengths = zip(path, path.dropFirst()).map { ($1 - $0).length }
            let toFlap = lengths[0..<GumballLayout.flapIndex].reduce(0, +)
            let s = toFlap * pow(max(0, t) / chuteTime, 1.7)
            return GumballDispenseSample(centre: point(along: path, lengths: lengths, s: s), alpha: 1, flap: flap, inChute: true)
        }
        let lengths = zip(path, path.dropFirst()).map { ($1 - $0).length }
        let toFlap = lengths[0..<GumballLayout.flapIndex].reduce(0, +)
        let roll = lengths[GumballLayout.flapIndex...].reduce(0, +)
        let u = FigureEase.clamp01((t - chuteTime) / rollTime)
        let s = toFlap + roll * FigureEase.easeOutCubic(u)
        var p = point(along: path, lengths: lengths, s: s)
        p = Vec3(p.x, p.y, p.z + 1.1 * (1 - u) * abs(sin(2.5 * Double.pi * u)))
        return GumballDispenseSample(centre: p, alpha: 1, flap: flap, inChute: false)
    }

    public static func flapOpenness(at t: Double) -> Double {
        if t < 0.55 { return 0 }
        if t < 0.9 { return FigureEase.smoothstep(0.55, 0.9, t) }
        if t < 1.05 { return 1 }
        return 1 - FigureEase.smoothstep(1.05, 1.5, t)
    }

    static func point(along path: [Vec3], lengths: [Double], s: Double) -> Vec3 {
        var left = max(0, s)
        for i in 0..<lengths.count {
            if left <= lengths[i] || i == lengths.count - 1 {
                let u = lengths[i] > 0 ? min(1, left / lengths[i]) : 0
                return Vec3.lerp(path[i], path[i + 1], u)
            }
            left -= lengths[i]
        }
        return path[path.count - 1]
    }

    // MARK: labels

    /// The parts that are working right now (for the labels).
    public var activeParts: Set<String> {
        var a: Set<String> = []
        if phase == .coinDropping, phaseAge < Self.coinSlide { a.insert("coinSlot") }
        if phase == .coinDropping, phaseAge >= Self.coinSlide { a.insert("coinMech") }
        if phase == .unlocked { a.insert("coinMech") }
        if crankIsMoving, phase == .turning || (phase == .unlocked && crank < crankTarget) {
            a.formUnion(["crank", "shaft", "wheel"])
        }
        if phase == .dispensing {
            let t = phaseAge
            if t < 0.35 { a.insert("wheel") }
            if let d = dispense, d.inChute { a.insert("chute") }
            if let d = dispense, d.flap > 0.05 { a.formUnion(["flap", "spring"]) }
            if reduceMotion { a.insert("flap") }
        }
        return a
    }
}
