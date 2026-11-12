import Foundation

// The tray, as a pure function of time:
// 1. Completing a row fades its title into one paper chip per glyph (spaces are gaps).
// 2. Those chips then tumble under gravity. Device tilt leans the gravity vector.
// 3. Restore springs every chip back to its own glyph, then snaps it exactly home.
// 4. Reduce Motion pins the chips in the word: no kick, no fall, no spring.

public struct TiltScatterTask: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum TiltScatterCatalog {
    public static let tasks: [TiltScatterTask] = [
        TiltScatterTask(id: "fern", title: "Water the fern"),
        TiltScatterTask(id: "ink", title: "Buy walnut ink"),
        TiltScatterTask(id: "letter", title: "Post the letter"),
        TiltScatterTask(id: "press", title: "Trim the press"),
        TiltScatterTask(id: "tea", title: "Steep the tea"),
    ]
}

public enum TiltScatterPhase: String, Equatable, Sendable {
    case idle
    case dissolving
    case tumbling
    case restoring
    case pinned
}

public enum TiltScatterHaptic: Equatable, Sendable {
    case complete
    case land
    case restore
}

public enum TiltScatterEvent: Equatable, Sendable {
    case completed(Int)
    case scattered(Int)
    case restoreBegan(Int)
    case seated(Int)
    case haptic(TiltScatterHaptic)
}

public enum TiltScatterAnnouncement {
    public static func completed(_ title: String, reduceMotion: Bool) -> String {
        reduceMotion ? "Completed \(title)" : "Completed \(title). Letters scattered"
    }
    public static func restoring(_ title: String) -> String { "Restoring \(title)" }
    public static let restoringAll = "Restoring every letter"
    public static func seated(_ title: String) -> String { "Restored \(title)" }
}

/// One letter cut out of a row. `home` never changes: Restore aims at this point.
public struct TiltScatterChip: Equatable, Sendable, Identifiable {
    public var id: String { "\(row).\(index)" }
    public let row: Int
    public let index: Int
    public let glyph: String
    public let home: Vec2
    public let width: Double
    public var position: Vec2
    public var velocity: Vec2
    public var angle: Double
    public var spin: Double
    public var scale: Double
    public var opacity: Double
    /// Asleep chips stay exactly where they settled until the tray tips enough to wake them.
    public var asleep: Bool

    public var radius: Double { TiltScatterLayout.collisionRadius }

    public var speed: Double {
        (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
    }
}

public struct TiltScatterRow: Equatable, Sendable {
    public let index: Int
    public let title: String
    public var phase: TiltScatterPhase
    public var clock: Double
    public var titleOpacity: Double
    /// The row has already ticked a land haptic for this tumble.
    public var landed: Bool
}

/// Numbers shared with the web preview. Changing one means changing the other.
public enum TiltScatterTuning {
    public static let substep = 1.0 / 120.0
    public static let maxFrame = 0.1
    public static let dissolveDuration = 0.42
    public static let reducedDissolve = 0.18
    public static let pop = 0.07
    public static let linearDrag = 1.85
    public static let spinDrag = 1.15
    public static let restitution = 0.22
    public static let friction = 0.18
    public static let frictionCap = 80.0
    public static let spinFromContact = 0.012
    public static let wallSpin = 0.002
    public static let pairIterations = 4
    public static let maxSpeed = 2200.0
    public static let sleepSpeed = 22.0
    public static let wakeSide = 120.0
    public static let supportSlop = 0.6
    public static let restoreK = 220.0
    public static let restoreZ = 0.78
    public static let restoreAngleK = 140.0
    public static let restoreAngleZ = 0.85
    public static let restoreLimit = 2.4
    public static let seatDistance = 0.4
    public static let seatAngle = 0.02
    public static let seatSpeed = 12.0
    public static let seatSpin = 0.35
    public static let fadeDistance = 28.0
    public static let kickVX = -70.0...70.0
    public static let kickVY = -150.0...(-40.0)
    public static let kickSpin = -4.5...4.5

    public static func kickSeed(base: UInt64, row: Int, index: Int) -> UInt64 {
        var x = base &+ 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(row) &* 0xBF58_476D_1CE4_E5B9
        x ^= UInt64(index) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 30
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        return x
    }

    /// A little larger while a chip is moving fast. Visual only; physics ignores it.
    public static func flightScale(speed: Double) -> Double {
        guard speed.isFinite, speed > 0 else { return 1 }
        return 1 + 0.06 * min(1, speed / 640)
    }
}

public struct TiltScatterModel: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        public var reduceMotion = false
        public init() {}
    }

    public var config: Config
    public let seed: UInt64
    public let tasks: [TiltScatterTask]
    public private(set) var rows: [TiltScatterRow]
    public private(set) var chips: [TiltScatterChip]
    public private(set) var tilt: Vec2
    public private(set) var time: Double
    public private(set) var completeHaptics = 0
    public private(set) var landHaptics = 0
    public private(set) var restoreHaptics = 0
    public private(set) var announcement: String?
    public private(set) var announcementCount = 0

    public init(tasks: [TiltScatterTask] = TiltScatterCatalog.tasks, seed: UInt64 = 0x71C75CA7, config: Config = Config()) {
        self.tasks = tasks
        self.seed = seed
        self.config = config
        self.tilt = .zero
        self.time = 0
        var rows: [TiltScatterRow] = []
        var chips: [TiltScatterChip] = []
        for (index, task) in tasks.enumerated() {
            rows.append(TiltScatterRow(index: index, title: task.title, phase: .idle, clock: 0, titleOpacity: 1, landed: false))
            for glyph in TiltScatterLayout.glyphs(title: task.title, row: index) {
                chips.append(TiltScatterChip(
                    row: glyph.row,
                    index: glyph.index,
                    glyph: glyph.glyph,
                    home: glyph.home,
                    width: glyph.width,
                    position: glyph.home,
                    velocity: .zero,
                    angle: 0,
                    spin: 0,
                    scale: 1,
                    opacity: 0,
                    asleep: false
                ))
            }
        }
        self.rows = rows
        self.chips = chips
    }

    public var gravity: Vec2 { TiltScatterGravity.acceleration(tilt: tilt) }

    public var canRestore: Bool { rows.contains { $0.phase != .idle } }

    public var needsFrame: Bool {
        if rows.contains(where: { $0.phase == .dissolving || $0.phase == .restoring }) { return true }
        for chip in chips where rows[chip.row].phase == .tumbling && !chip.asleep { return true }
        return false
    }

    public func accessibilityValue(for index: Int) -> String {
        guard rows.indices.contains(index) else { return "" }
        switch rows[index].phase {
        case .idle: return "Not completed"
        case .dissolving: return "Completing"
        case .tumbling: return "Completed, letters scattered"
        case .restoring: return "Restoring"
        case .pinned: return "Completed"
        }
    }

    public var tiltDescription: String {
        let x = tilt.x, y = tilt.y
        if abs(x) < 0.12, abs(y) < 0.12 { return "Level" }
        var parts: [String] = []
        if x >= 0.12 { parts.append("tipped right") }
        if x <= -0.12 { parts.append("tipped left") }
        if y >= 0.12 { parts.append("tipped back") }
        if y <= -0.12 { parts.append("tipped forward") }
        guard let first = parts.first else { return "Level" }
        return first.prefix(1).uppercased() + first.dropFirst() + parts.dropFirst().map { ", \($0)" }.joined()
    }

    // MARK: Input

    public mutating func setTilt(_ next: Vec2) {
        guard next.x.isFinite, next.y.isFinite else { return }
        tilt = Vec2(WhimsyMath.clamp(next.x, -1, 1), WhimsyMath.clamp(next.y, -1, 1))
    }

    /// Turning Reduce Motion on parks every in-flight chip exactly on its glyph.
    public mutating func setReduceMotion(_ on: Bool) {
        guard on != config.reduceMotion else { return }
        config.reduceMotion = on
        guard on else { return }
        for index in rows.indices where rows[index].phase != .idle {
            pin(index)
        }
    }

    @discardableResult
    public mutating func toggle(_ index: Int) -> [TiltScatterEvent] {
        guard rows.indices.contains(index) else { return [] }
        switch rows[index].phase {
        case .idle:
            return beginComplete(index)
        case .dissolving, .tumbling, .pinned:
            return beginRestore(index, announce: true)
        case .restoring:
            return []
        }
    }

    @discardableResult
    public mutating func restoreAll() -> [TiltScatterEvent] {
        var events: [TiltScatterEvent] = []
        var any = false
        for index in rows.indices where rows[index].phase != .idle && rows[index].phase != .restoring {
            let piece = beginRestore(index, announce: false)
            if !piece.isEmpty { any = true }
            events += piece
        }
        if any {
            announcement = TiltScatterAnnouncement.restoringAll
            announcementCount += 1
            restoreHaptics += 1
            events.append(.haptic(.restore))
        }
        return events
    }

    @discardableResult
    public mutating func step(dt: Double) -> [TiltScatterEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        var events: [TiltScatterEvent] = []
        var remaining = min(dt, TiltScatterTuning.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, TiltScatterTuning.substep)
            events += substep(h)
            time += h
            remaining -= h
        }
        return events
    }

    /// One line of the parity trace: hex doubles, phase letters, then each chip.
    public func traceLine() -> String {
        var parts: [String] = [TiltScatterMath.hex(time), TiltScatterMath.hex(tilt.x), TiltScatterMath.hex(tilt.y)]
        parts.append(rows.map { $0.phase.phaseLetter }.joined())
        for row in rows { parts.append(TiltScatterMath.hex(row.titleOpacity)) }
        for chip in chips {
            parts.append(TiltScatterMath.hex(chip.position.x))
            parts.append(TiltScatterMath.hex(chip.position.y))
            parts.append(TiltScatterMath.hex(chip.angle))
            parts.append(TiltScatterMath.hex(chip.velocity.x))
            parts.append(TiltScatterMath.hex(chip.velocity.y))
            parts.append(chip.asleep ? "1" : "0")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Phases

    private mutating func beginComplete(_ index: Int) -> [TiltScatterEvent] {
        rows[index].phase = .dissolving
        rows[index].clock = 0
        rows[index].landed = false
        rows[index].titleOpacity = 1
        for i in chips.indices where chips[i].row == index {
            chips[i].position = chips[i].home
            chips[i].velocity = .zero
            chips[i].angle = 0
            chips[i].spin = 0
            chips[i].scale = 1
            chips[i].opacity = 0
            chips[i].asleep = false
        }
        completeHaptics += 1
        announcement = TiltScatterAnnouncement.completed(rows[index].title, reduceMotion: config.reduceMotion)
        announcementCount += 1
        return [.completed(index), .haptic(.complete)]
    }

    private mutating func beginRestore(_ index: Int, announce: Bool) -> [TiltScatterEvent] {
        let phase = rows[index].phase
        guard phase != .idle, phase != .restoring else { return [] }
        if config.reduceMotion || phase == .pinned || phase == .dissolving {
            let title = rows[index].title
            seat(index)
            announcement = TiltScatterAnnouncement.seated(title)
            announcementCount += 1
            var events: [TiltScatterEvent] = [.seated(index)]
            if announce {
                restoreHaptics += 1
                events.append(.haptic(.restore))
            }
            return events
        }
        rows[index].phase = .restoring
        rows[index].clock = 0
        for i in chips.indices where chips[i].row == index {
            chips[i].asleep = false
            chips[i].velocity = chips[i].velocity * 0.25
            chips[i].spin *= 0.25
        }
        var events: [TiltScatterEvent] = [.restoreBegan(index)]
        if announce {
            announcement = TiltScatterAnnouncement.restoring(rows[index].title)
            announcementCount += 1
            restoreHaptics += 1
            events.append(.haptic(.restore))
        }
        return events
    }

    private mutating func pin(_ index: Int) {
        rows[index].phase = .pinned
        rows[index].clock = 0
        rows[index].titleOpacity = 0
        rows[index].landed = false
        for i in chips.indices where chips[i].row == index {
            chips[i].position = chips[i].home
            chips[i].velocity = .zero
            chips[i].angle = 0
            chips[i].spin = 0
            chips[i].scale = 1
            chips[i].opacity = 1
            chips[i].asleep = false
        }
    }

    private mutating func seat(_ index: Int) {
        rows[index].phase = .idle
        rows[index].clock = 0
        rows[index].titleOpacity = 1
        rows[index].landed = false
        for i in chips.indices where chips[i].row == index {
            chips[i].position = chips[i].home
            chips[i].velocity = .zero
            chips[i].angle = 0
            chips[i].spin = 0
            chips[i].scale = 1
            chips[i].opacity = 0
            chips[i].asleep = false
        }
    }

    // MARK: Integration

    private mutating func substep(_ h: Double) -> [TiltScatterEvent] {
        var events: [TiltScatterEvent] = []
        var tumbling: [Int] = []
        for index in rows.indices {
            switch rows[index].phase {
            case .dissolving:
                events += advanceDissolve(index, h: h)
            case .tumbling:
                tumbling.append(index)
            case .restoring:
                events += advanceRestore(index, h: h)
            case .idle, .pinned:
                break
            }
        }
        if !tumbling.isEmpty, !config.reduceMotion {
            events += integrateTumble(tumbling, h: h)
        }
        return events
    }

    private mutating func advanceDissolve(_ index: Int, h: Double) -> [TiltScatterEvent] {
        let duration = config.reduceMotion ? TiltScatterTuning.reducedDissolve : TiltScatterTuning.dissolveDuration
        rows[index].clock += h
        let u = min(1, rows[index].clock / duration)
        let eased = WhimsyMath.smoothstep(0, 1, u)
        let pop = 1 + TiltScatterTuning.pop * TiltScatterMath.sin(Double.pi * u)
        rows[index].titleOpacity = 1 - eased
        for i in chips.indices where chips[i].row == index {
            chips[i].opacity = eased
            chips[i].scale = pop
            chips[i].position = chips[i].home
            chips[i].angle = 0
            chips[i].velocity = .zero
            chips[i].spin = 0
        }
        guard rows[index].clock >= duration else { return [] }
        if config.reduceMotion {
            pin(index)
            return []
        }
        rows[index].phase = .tumbling
        rows[index].titleOpacity = 0
        applyKick(index)
        return [.scattered(index)]
    }

    private mutating func applyKick(_ index: Int) {
        for i in chips.indices where chips[i].row == index {
            var rng = SeededRandom(seed: TiltScatterTuning.kickSeed(base: seed, row: index, index: chips[i].index))
            chips[i].position = chips[i].home
            chips[i].velocity = Vec2(rng.uniform(TiltScatterTuning.kickVX), rng.uniform(TiltScatterTuning.kickVY))
            chips[i].spin = rng.uniform(TiltScatterTuning.kickSpin)
            chips[i].angle = 0
            chips[i].scale = 1
            chips[i].opacity = 1
            chips[i].asleep = false
        }
    }

    private mutating func advanceRestore(_ index: Int, h: Double) -> [TiltScatterEvent] {
        rows[index].clock += h
        let k = TiltScatterTuning.restoreK
        let c = 2 * TiltScatterTuning.restoreZ * k.squareRoot()
        let ka = TiltScatterTuning.restoreAngleK
        let ca = 2 * TiltScatterTuning.restoreAngleZ * ka.squareRoot()
        var allSeated = true
        var mean = 0.0
        var count = 0.0
        for i in chips.indices where chips[i].row == index {
            let home = chips[i].home
            let ax = k * (home.x - chips[i].position.x) - c * chips[i].velocity.x
            let ay = k * (home.y - chips[i].position.y) - c * chips[i].velocity.y
            chips[i].velocity.x += ax * h
            chips[i].velocity.y += ay * h
            chips[i].position.x += chips[i].velocity.x * h
            chips[i].position.y += chips[i].velocity.y * h
            let aa = ka * (0 - chips[i].angle) - ca * chips[i].spin
            chips[i].spin += aa * h
            chips[i].angle += chips[i].spin * h
            chips[i].scale = 1
            chips[i].asleep = false
            let dx = chips[i].position.x - home.x
            let dy = chips[i].position.y - home.y
            let dist = (dx * dx + dy * dy).squareRoot()
            let u = min(1, dist / TiltScatterTuning.fadeDistance)
            chips[i].opacity = u
            mean += u
            count += 1
            let close = dist < TiltScatterTuning.seatDistance
                && abs(chips[i].angle) < TiltScatterTuning.seatAngle
                && chips[i].speed < TiltScatterTuning.seatSpeed
                && abs(chips[i].spin) < TiltScatterTuning.seatSpin
            if !close { allSeated = false }
        }
        rows[index].titleOpacity = count > 0 ? (1 - mean / count) : 1
        if allSeated || rows[index].clock >= TiltScatterTuning.restoreLimit {
            let title = rows[index].title
            seat(index)
            announcement = TiltScatterAnnouncement.seated(title)
            announcementCount += 1
            return [.seated(index)]
        }
        return []
    }

    private mutating func integrateTumble(_ rowIndices: [Int], h: Double) -> [TiltScatterEvent] {
        let tumbling = Set(rowIndices)
        var indexes: [Int] = []
        indexes.reserveCapacity(chips.count)
        for i in chips.indices where tumbling.contains(chips[i].row) { indexes.append(i) }
        let g = gravity
        let damp = max(0, 1 - TiltScatterTuning.linearDrag * h)
        let spinDamp = max(0, 1 - TiltScatterTuning.spinDrag * h)

        let resting = supportedIndexes(among: indexes)
        for i in indexes {
            if chips[i].asleep {
                if abs(g.x) < TiltScatterTuning.wakeSide && resting.contains(i) {
                    chips[i].velocity = .zero
                    chips[i].spin = 0
                    continue
                }
                chips[i].asleep = false
            }
            chips[i].velocity.x += g.x * h
            chips[i].velocity.y += g.y * h
            chips[i].velocity = chips[i].velocity * damp
            limitSpeed(i)
            chips[i].position += chips[i].velocity * h
            chips[i].spin *= spinDamp
            chips[i].angle += chips[i].spin * h
            chips[i].opacity = 1
            chips[i].scale = 1
        }

        if indexes.count > 1 {
            for _ in 0..<TiltScatterTuning.pairIterations {
                for a in 0..<indexes.count {
                    for b in (a + 1)..<indexes.count {
                        resolvePair(indexes[a], indexes[b])
                    }
                }
            }
        }
        var events: [TiltScatterEvent] = []
        for i in indexes {
            resolveWalls(i)
            events += landIfNeeded(i)
        }
        let settled = supportedIndexes(among: indexes)
        for i in indexes {
            sleepIfSettled(i, supported: settled.contains(i), gravityX: g.x)
        }
        return events
    }

    private mutating func limitSpeed(_ i: Int) {
        let maxS = TiltScatterTuning.maxSpeed
        let sp2 = chips[i].velocity.x * chips[i].velocity.x + chips[i].velocity.y * chips[i].velocity.y
        if sp2 > maxS * maxS, sp2 > 0 {
            let k = maxS / sp2.squareRoot()
            chips[i].velocity = chips[i].velocity * k
        }
    }

    private func fallen(_ i: Int) -> Bool {
        chips[i].position.y > chips[i].home.y + TiltScatterLayout.fallenGap
    }

    private mutating func resolvePair(_ i: Int, _ j: Int) {
        if chips[i].asleep && chips[j].asleep && abs(gravity.x) < TiltScatterTuning.wakeSide { return }
        guard fallen(i), fallen(j) else { return }
        var delta = chips[j].position - chips[i].position
        var dist2 = delta.x * delta.x + delta.y * delta.y
        let minD = chips[i].radius + chips[j].radius
        if dist2 >= minD * minD, dist2 > 0 { return }
        var dist = dist2.squareRoot()
        if dist < 1e-9 {
            delta = Vec2(1, 0)
            dist = 1e-9
            dist2 = dist * dist
        }
        let nx = delta.x / dist
        let ny = delta.y / dist
        let overlap = minD - dist
        let half = overlap * 0.5
        chips[i].position.x -= nx * half
        chips[i].position.y -= ny * half
        chips[j].position.x += nx * half
        chips[j].position.y += ny * half
        let rvx = chips[j].velocity.x - chips[i].velocity.x
        let rvy = chips[j].velocity.y - chips[i].velocity.y
        let rel = rvx * nx + rvy * ny
        guard rel < 0 else { return }
        let impulse = -(1 + TiltScatterTuning.restitution) * rel * 0.5
        chips[i].velocity.x -= impulse * nx
        chips[i].velocity.y -= impulse * ny
        chips[j].velocity.x += impulse * nx
        chips[j].velocity.y += impulse * ny
        let tx = -ny
        let ty = nx
        let vt = rvx * tx + rvy * ty
        let fr = WhimsyMath.clamp(vt * TiltScatterTuning.friction, -TiltScatterTuning.frictionCap, TiltScatterTuning.frictionCap)
        chips[i].velocity.x += fr * tx * 0.5
        chips[i].velocity.y += fr * ty * 0.5
        chips[j].velocity.x -= fr * tx * 0.5
        chips[j].velocity.y -= fr * ty * 0.5
        let kick = vt * TiltScatterTuning.spinFromContact
        chips[i].spin -= kick
        chips[j].spin += kick
        chips[i].asleep = false
        chips[j].asleep = false
    }

    private mutating func resolveWalls(_ i: Int) {
        let r = chips[i].radius
        let e = TiltScatterTuning.restitution
        if chips[i].position.x < TiltScatterLayout.boundLeft + r {
            chips[i].position.x = TiltScatterLayout.boundLeft + r
            if chips[i].velocity.x < 0 {
                chips[i].velocity.x = -chips[i].velocity.x * e
                chips[i].spin += chips[i].velocity.y * TiltScatterTuning.wallSpin
            }
        } else if chips[i].position.x > TiltScatterLayout.boundRight - r {
            chips[i].position.x = TiltScatterLayout.boundRight - r
            if chips[i].velocity.x > 0 {
                chips[i].velocity.x = -chips[i].velocity.x * e
                chips[i].spin -= chips[i].velocity.y * TiltScatterTuning.wallSpin
            }
        }
        if chips[i].position.y < TiltScatterLayout.boundTop + r {
            chips[i].position.y = TiltScatterLayout.boundTop + r
            if chips[i].velocity.y < 0 { chips[i].velocity.y = -chips[i].velocity.y * e }
        } else if chips[i].position.y > TiltScatterLayout.boundBottom - r {
            chips[i].position.y = TiltScatterLayout.boundBottom - r
            if chips[i].velocity.y > 0 { chips[i].velocity.y = -chips[i].velocity.y * e }
        }
    }

    private mutating func landIfNeeded(_ i: Int) -> [TiltScatterEvent] {
        let row = chips[i].row
        guard !rows[row].landed else { return [] }
        let floor = TiltScatterLayout.boundBottom - chips[i].radius - 0.75
        guard chips[i].position.y >= floor else { return [] }
        rows[row].landed = true
        landHaptics += 1
        return [.haptic(.land)]
    }

    private func onFloor(_ i: Int) -> Bool {
        chips[i].position.y >= TiltScatterLayout.boundBottom - chips[i].radius - 0.75
    }

    private func supportedIndexes(among indexes: [Int]) -> Set<Int> {
        var supported = Set<Int>()
        let limit = TiltScatterLayout.collisionRadius * 2 + TiltScatterTuning.supportSlop
        for _ in 0..<8 {
            var changed = false
            for j in indexes where !supported.contains(j) {
                if onFloor(j) {
                    supported.insert(j)
                    changed = true
                    continue
                }
                for k in supported {
                    if chips[j].position.distance(to: chips[k].position) <= limit {
                        supported.insert(j)
                        changed = true
                        break
                    }
                }
            }
            if !changed { break }
        }
        return supported
    }

    private mutating func sleepIfSettled(_ i: Int, supported: Bool, gravityX: Double) {
        guard abs(gravityX) < TiltScatterTuning.wakeSide else {
            chips[i].asleep = false
            return
        }
        guard supported else {
            chips[i].asleep = false
            return
        }
        // A supported chip that is barely moving is asleep, whatever spin it still
        // carries. The angle stays; the spin does not, or neighbours would keep stirring it.
        if chips[i].speed < TiltScatterTuning.sleepSpeed {
            chips[i].velocity = .zero
            chips[i].spin = 0
            chips[i].asleep = true
        } else {
            chips[i].asleep = false
            if onFloor(i) {
                chips[i].velocity.x *= max(0, 1 - 6 * TiltScatterTuning.substep)
            }
        }
    }
}

private extension TiltScatterPhase {
    var phaseLetter: String {
        switch self {
        case .idle: "I"
        case .dissolving: "D"
        case .tumbling: "T"
        case .restoring: "R"
        case .pinned: "P"
        }
    }
}

/// The session the web preview's parity check replays. Step counts are exact
/// multiples of the 1/120 s substep.
public enum TiltScatterTrace {
    public static let paritySeed: UInt64 = 0x71C75CA7

    public static func parityLines(stride: Int = 6) -> [String] {
        var model = TiltScatterModel(tasks: TiltScatterCatalog.tasks, seed: paritySeed)
        var lines: [String] = [model.traceLine()]
        func run(_ steps: Int) {
            for i in 0..<steps {
                _ = model.step(dt: TiltScatterTuning.substep)
                if stride > 0, (i + 1) % stride == 0 { lines.append(model.traceLine()) }
            }
        }
        run(48)
        _ = model.toggle(0)
        lines.append(model.traceLine())
        run(66)
        _ = model.toggle(2)
        lines.append(model.traceLine())
        run(108)
        model.setTilt(Vec2(0.75, -0.15))
        lines.append(model.traceLine())
        run(96)
        model.setTilt(Vec2(-0.85, 0.55))
        lines.append(model.traceLine())
        run(96)
        model.setTilt(.zero)
        _ = model.restoreAll()
        lines.append(model.traceLine())
        run(192)
        lines.append(model.traceLine())
        return lines
    }
}
