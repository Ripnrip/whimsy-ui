import Foundation

public enum CrumplePhase: Equatable, Sendable {
    case idle
    case dragging
    case springing
    case tossing
    case gone
    case returning
}

public enum CrumpleEvent: Equatable, Sendable {
    case crease(Int)
    case committed
    case arrived
    case lidBump
    case restored
}

/// Drag a card toward a bin. The core records creases, the commit, and the toss. It does not draw.
public struct CrumpleModel: Equatable, Sendable {
    public var rules: CrumpleRules
    public var card: CrumpleRect
    public var bin: CrumpleRect
    public var reduceMotion: Bool
    public private(set) var phase: CrumplePhase = .idle
    public private(set) var pull: Vec2 = .zero
    /// 0 is flat. 1 is the settled ball. The snap spring may pass 1.
    public private(set) var shape: Double = 0
    public private(set) var toss: Double = 0
    public private(set) var zoneLatched = false
    public private(set) var log: [CrumpleEvent] = []

    private var pullSpring = WhimsySpring2D()
    private var shapeSpring = WhimsySpring()
    private var creases: Set<Int> = []
    private var previousAngles: [Double] = []
    private var previousProgress = 0.0
    private var tossOrigin = Vec2.zero
    private var arrived = false

    public init(card: CrumpleRect, bin: CrumpleRect, reduceMotion: Bool = false, rules: CrumpleRules = CrumpleRules()) {
        self.card = card
        self.bin = bin
        self.reduceMotion = reduceMotion
        self.rules = rules
    }

    public var progress: Double {
        let axis = bin.center - card.center
        let gap2 = axis.dot(axis)
        guard gap2 > 1e-12 else { return 0 }
        return WhimsyMath.clamp01(pull.dot(axis) / gap2)
    }

    public var center: Vec2 {
        if phase == .tossing || phase == .gone {
            return tossPoint(toss)
        }
        return card.center + pull
    }

    public var sample: CrumpleSample {
        CrumpleMesh.sample(card: card, shape: shape, pull: displayPull, rules: rules)
    }

    /// While the ball is in flight the mesh stays put in card space and the view translates `center`.
    private var displayPull: Vec2 {
        phase == .tossing || phase == .gone ? .zero : pull
    }

    public func containsTouch(_ point: Vec2) -> Bool {
        let c = card.center + pull
        let w = card.width
        let h = card.height
        return point.x >= c.x - w / 2 && point.x <= c.x + w / 2
            && point.y >= c.y - h / 2 && point.y <= c.y + h / 2
    }

    @discardableResult
    public mutating func begin(at point: Vec2) -> Bool {
        switch phase {
        case .idle, .springing:
            guard containsTouch(point) else { return false }
            phase = .dragging
            zoneLatched = false
            creases = []
            pull = point - card.center
            shape = progress
            zoneLatched = bin.contains(center)
            previousProgress = progress
            previousAngles = CrumpleMesh.foldAngles(sample)
            return true
        case .dragging, .tossing, .gone, .returning:
            return false
        }
    }

    @discardableResult
    public mutating func drag(to point: Vec2) -> [CrumpleEvent] {
        guard phase == .dragging else { return [] }
        pull = point - card.center
        shape = progress
        zoneLatched = bin.contains(center)
        var fresh: [CrumpleEvent] = []
        if progress > previousProgress + 1e-9 {
            fresh = crossedCreases()
        }
        previousProgress = progress
        previousAngles = CrumpleMesh.foldAngles(sample)
        log.append(contentsOf: fresh)
        return fresh
    }

    @discardableResult
    public mutating func end() -> [CrumpleEvent] {
        guard phase == .dragging else { return [] }
        if progress >= rules.commitProgress || zoneLatched {
            return startToss()
        }
        startSpring(toFlat: true)
        return []
    }

    @discardableResult
    public mutating func cancel() -> [CrumpleEvent] {
        guard phase == .dragging else { return [] }
        startSpring(toFlat: true)
        return []
    }

    /// VoiceOver delete, and any other commit that does not wait for the 0.8 line.
    @discardableResult
    public mutating func commit() -> [CrumpleEvent] {
        switch phase {
        case .idle, .dragging, .springing:
            return startToss()
        case .tossing, .gone, .returning:
            return []
        }
    }

    /// Puts the card back. A second call while it is already returning does nothing.
    /// A call before arrival never emits `arrived` or `lidBump`.
    @discardableResult
    public mutating func reset() -> Bool {
        switch phase {
        case .idle, .returning:
            return false
        case .dragging, .springing, .tossing, .gone:
            startSpring(toFlat: true)
            phase = .returning
            return true
        }
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [CrumpleEvent] {
        guard dt > 0, dt.isFinite else { return [] }
        var fresh: [CrumpleEvent] = []
        switch phase {
        case .springing, .returning:
            let calm = reduceMotion
            pullSpring.x.stiffness = calm ? rules.calmStiffness : rules.springStiffness
            pullSpring.y.stiffness = pullSpring.x.stiffness
            pullSpring.x.dampingRatio = calm ? rules.calmDamping : rules.springDamping
            pullSpring.y.dampingRatio = pullSpring.x.dampingRatio
            pullSpring.step(toward: .zero, dt: dt)
            pull = pullSpring.value
            shape = progress
            zoneLatched = false
            if pullSpring.isSettled(at: .zero) {
                pull = .zero
                shape = 0
                let wasReturning = phase == .returning
                phase = .idle
                if wasReturning {
                    fresh.append(.restored)
                }
            }
        case .tossing:
            if !reduceMotion {
                shapeSpring.step(toward: 1, dt: dt)
                shape = max(shapeSpring.value, 0)
            }
            let duration = reduceMotion ? rules.reduceMotionDuration : rules.tossDuration
            toss = min(1, toss + dt / max(duration, 1e-6))
            if toss >= 1, !arrived {
                arrived = true
                phase = .gone
                shape = reduceMotion ? shape : max(shape, 1)
                fresh.append(.arrived)
                if !reduceMotion {
                    fresh.append(.lidBump)
                }
            }
        case .idle, .dragging, .gone:
            break
        }
        log.append(contentsOf: fresh)
        return fresh
    }

    /// Runs `step` until the phase settles or `seconds` elapses. Tests use this.
    @discardableResult
    public mutating func run(_ seconds: Double, dt: Double = 1.0 / 60) -> [CrumpleEvent] {
        var all: [CrumpleEvent] = []
        var t = 0.0
        while t < seconds {
            all.append(contentsOf: step(dt))
            t += dt
            if phase == .idle || phase == .gone { break }
        }
        return all
    }

    private mutating func startToss() -> [CrumpleEvent] {
        tossOrigin = card.center + pull
        phase = .tossing
        toss = 0
        arrived = false
        zoneLatched = false
        shapeSpring = WhimsySpring(
            value: shape,
            velocity: 0,
            stiffness: rules.springStiffness,
            dampingRatio: rules.springDamping
        )
        let event = CrumpleEvent.committed
        log.append(event)
        return [event]
    }

    private mutating func startSpring(toFlat: Bool) {
        _ = toFlat
        pullSpring = WhimsySpring2D(
            value: pull,
            stiffness: reduceMotion ? rules.calmStiffness : rules.springStiffness,
            dampingRatio: reduceMotion ? rules.calmDamping : rules.springDamping
        )
        phase = .springing
        zoneLatched = false
    }

    private mutating func crossedCreases() -> [CrumpleEvent] {
        let angles = CrumpleMesh.foldAngles(sample)
        var fresh: [CrumpleEvent] = []
        for (index, angle) in angles.enumerated() {
            let prior = index < previousAngles.count ? previousAngles[index] : 0
            if prior < rules.creaseAngle, angle >= rules.creaseAngle, creases.insert(index).inserted {
                fresh.append(.crease(index))
            }
        }
        return fresh
    }

    private func tossPoint(_ t: Double) -> Vec2 {
        let start = tossOrigin
        let end = bin.center
        let seg = end - start
        let side = seg.length > 1e-9 ? seg.perpendicular.normalized : Vec2(0, -1)
        let control = start + seg * 0.5 + side * (seg.length * rules.tossControl)
        let u = WhimsyMath.clamp01(t)
        let a = Vec2.lerp(start, control, u)
        let b = Vec2.lerp(control, end, u)
        return Vec2.lerp(a, b, u)
    }
}
