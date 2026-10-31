import Foundation

public enum DogEarPhase: Equatable, Sendable {
    /// Flat, nothing touched.
    case idle
    /// A finger is holding the corner.
    case dragging
    /// Let go below the threshold: the corner springs flat.
    case springingBack
    /// Let go past it: the crease sweeps across the card.
    case peelingOff
    /// The folded-back card flies away, spinning a little.
    case flying
    /// Reduce Motion: the card fades instead of sweeping and flying.
    case fading
    /// The card is gone and the note is showing.
    case revealed
    /// Reset: the card settles back on top.
    case returning
}

public enum DogEarHaptic: Equatable, Sendable { case threshold, peelOff }

public enum DogEarEvent: Equatable, Sendable {
    case grabbed
    /// Progress crossed the threshold (`armed` true going up, false coming back down).
    case thresholdCrossed(armed: Bool)
    case springBackStarted
    case settled
    case peelOffStarted
    case noteRevealed
    case restored
    case haptic(DogEarHaptic)
}

public enum DogEarAnnouncement {
    public static func text(for e: DogEarEvent, content: DogEarContent) -> String? {
        switch e {
        case .noteRevealed: return "Card peeled away. \(content.noteTitle). \(content.noteBody)"
        case .restored: return "Card restored"
        default: return nil
        }
    }
}

/// Everything the view draws for one moment.
public struct DogEarFrame: Sendable {
    /// The part of the card still lying on the note, as a polygon in card-local points.
    public var flat: Polygon
    /// The folded-back paper (empty when nothing is lifted). Includes the fly-away transform.
    public var flap: Polygon
    public var creaseFrom: Vec2?
    public var creaseTo: Vec2?
    /// Gradient axis, from the crease across the flap (already transformed with it).
    public var gradientFrom: Vec2
    public var gradientTo: Vec2
    /// Direction the flap's shadow is pushed on the card (unit).
    public var shadowDirection: Vec2
    public var shading: DogEarShading
    /// Share of the card's area that is lifted: the PeelCore fraction.
    public var areaFraction: Double
    public var cardOpacity: Double
    public var cardScale: Double
    public var flapOpacity: Double
}

public struct DogEarModel: Sendable {
    public var rules = DogEarRules()
    public var content = DogEarContent.halloween
    public var reduceMotion: Bool

    public private(set) var phase: DogEarPhase = .idle
    public private(set) var time = 0.0
    /// Unit vector from the corner toward the finger.
    public private(set) var direction = DogEarLayout.inward
    /// Finger travel from the corner, in points. Goes negative while the spring overshoots.
    public private(set) var pull = 0.0
    /// Latched at the threshold (with hysteresis); decides what letting go does.
    public private(set) var armed = false
    public private(set) var hapticCount = 0
    public private(set) var announcementCount = 0
    public private(set) var announcement: String?

    private var spring = WhimsySpring()
    private var offset = Vec2.zero
    private var sweepFrom = 0.0
    private var age = 0.0
    private var lastHaptic = -Double.infinity
    private var pending: [DogEarEvent] = []

    public init(reduceMotion: Bool = false) { self.reduceMotion = reduceMotion }

    // MARK: Metrics

    /// How far the card reaches along the current direction.
    public var reach: Double { DogEarLayout.extent(along: direction) }

    /// The pull that lifts nothing negative: what the fold actually sees.
    public var effectivePull: Double { max(pull, 0) }

    /// 0…1: finger travel ÷ reach of the card along the drag.
    public var progress: Double {
        let r = reach
        return r > 0 ? WhimsyMath.clamp01(effectivePull / r) : 0
    }

    /// Where the finger (the lifted corner's tip) is.
    public var finger: Vec2 { DogEarLayout.grab + direction * effectivePull }

    /// The note can be read once the card has gone.
    public var noteRevealed: Bool { phase == .revealed }

    /// Nothing is moving, so a display link can pause.
    public var isIdle: Bool { (phase == .idle || phase == .revealed) && pending.isEmpty }

    // MARK: Input

    /// Starts a drag if `point` is near the corner (or near the tip of a corner that is still springing back).
    @discardableResult
    public mutating func begin(at point: Vec2, time t: Double) -> Bool {
        sync(t)
        guard phase == .idle || phase == .springingBack else { return false }
        let tip = phase == .idle ? DogEarLayout.grab : finger
        guard tip.distance(to: point) <= DogEarLayout.grabRadius else { return false }
        offset = tip - point
        phase = .dragging
        armed = false
        age = 0
        emit(.grabbed)
        return true
    }

    /// Moves the finger. The pull is clamped to the card's reach so the crease can't leave the card.
    public mutating func drag(to point: Vec2, time t: Double) {
        sync(t)
        guard phase == .dragging else { return }
        let v = point + offset - DogEarLayout.grab
        let len = v.length
        if len > 1e-6 {
            let d = v * (1 / len)
            let r = DogEarLayout.extent(along: d)
            direction = d
            pull = r > 0 ? min(len, r * rules.maxPullFraction) : 0
        } else {
            pull = 0
        }
        let p = progress
        if !armed, p >= rules.threshold {
            armed = true
            emit(.thresholdCrossed(armed: true)); haptic(.threshold)
        } else if armed, p < rules.threshold - rules.hysteresis {
            armed = false
            emit(.thresholdCrossed(armed: false)); haptic(.threshold)
        }
    }

    /// Lets go: past the threshold the card peels off, otherwise the corner springs flat.
    public mutating func end(time t: Double) {
        sync(t)
        guard phase == .dragging else { return }
        if armed {
            startPeelOff()
        } else if pull < rules.minPull {
            pull = 0
            phase = .idle
            emit(.settled)
        } else {
            spring = WhimsySpring(value: pull, velocity: 0,
                                  stiffness: reduceMotion ? rules.calmStiffness : rules.springStiffness,
                                  dampingRatio: reduceMotion ? rules.calmDamping : rules.springDamping)
            phase = .springingBack
            emit(.springBackStarted)
        }
    }

    /// The accessibility "Peel" action: the card comes away from rest.
    public mutating func peel(time t: Double) {
        sync(t)
        guard phase == .idle || phase == .dragging || phase == .springingBack else { return }
        if phase != .dragging { direction = DogEarLayout.inward; pull = 0 }
        startPeelOff()
    }

    /// Puts the card back on top of the note.
    @discardableResult
    public mutating func reset(time t: Double) -> Bool {
        sync(t)
        guard phase != .idle, phase != .returning else { return false }
        phase = .returning
        age = 0
        pull = 0
        armed = false
        direction = DogEarLayout.inward
        emit(.restored)
        return true
    }

    @discardableResult
    public mutating func advance(to t: Double) -> [DogEarEvent] {
        sync(t)
        let out = pending
        pending = []
        return out
    }

    // MARK: Stepping

    private mutating func sync(_ t: Double) {
        guard t.isFinite, t > time else { return }
        var left = t - time
        while left > 1e-12 {
            let h = min(left, WhimsySpring.maxFrame)
            time += h
            tick(h)
            left -= h
        }
        time = t
    }

    private mutating func tick(_ h: Double) {
        switch phase {
        case .idle, .dragging, .revealed:
            break
        case .springingBack:
            spring.step(toward: 0, dt: h)
            pull = spring.value
            if spring.isSettled(at: 0, tolerance: 0.25) {
                pull = 0
                phase = .idle
                emit(.settled)
            }
        case .peelingOff:
            age += h
            let u = WhimsyMath.easeInOutCubic(age / rules.sweepDuration)
            pull = WhimsyMath.lerp(sweepFrom, fullSweepPull, u)
            if age >= rules.sweepDuration {
                pull = fullSweepPull
                age -= rules.sweepDuration
                phase = .flying
            }
        case .flying:
            age += h
            if age >= rules.flyDuration { finishReveal() }
        case .fading:
            age += h
            if age >= rules.fadeDuration { finishReveal() }
        case .returning:
            age += h
            if age >= rules.returnDuration {
                age = 0
                phase = .idle
            }
        }
    }

    /// The pull at which the crease has swept past the far side of the card.
    private var fullSweepPull: Double { 2 * reach + 4 }

    private mutating func startPeelOff() {
        armed = false
        age = 0
        sweepFrom = effectivePull
        emit(.peelOffStarted)
        haptic(.peelOff)
        phase = reduceMotion ? .fading : .peelingOff
        if reduceMotion { pull = 0 }
    }

    private mutating func finishReveal() {
        age = 0
        phase = .revealed
        emit(.noteRevealed)
    }

    private mutating func emit(_ e: DogEarEvent) {
        pending.append(e)
        if let text = DogEarAnnouncement.text(for: e, content: content) { announcement = text; announcementCount += 1 }
    }

    private mutating func haptic(_ kind: DogEarHaptic) {
        guard time - lastHaptic >= rules.hapticInterval else { return }
        lastHaptic = time
        hapticCount += 1
        emit(.haptic(kind))
    }

    // MARK: Frame

    public var frame: DogEarFrame {
        let shape = DogEarLayout.shape
        let none = Polygon([])
        func whole(opacity: Double = 1, scale: Double = 1) -> DogEarFrame {
            DogEarFrame(flat: shape, flap: none, creaseFrom: nil, creaseTo: nil, gradientFrom: .zero, gradientTo: .zero,
                        shadowDirection: direction, shading: .make(progress: 0, flapDepth: 1), areaFraction: 0,
                        cardOpacity: opacity, cardScale: scale, flapOpacity: 0)
        }
        switch phase {
        case .idle:
            return whole()
        case .fading:
            return whole(opacity: 1 - WhimsyMath.smoothstep(0, 1, age / rules.fadeDuration))
        case .returning:
            let u = age / rules.returnDuration
            return whole(opacity: reduceMotion ? WhimsyMath.clamp01(u) : WhimsyMath.easeOutCubic(u),
                         scale: reduceMotion ? 1 : 0.94 + 0.06 * WhimsyMath.easeOutCubic(u))
        case .revealed:
            var f = whole(opacity: 0); f.flat = none; return f
        case .dragging, .springingBack, .peelingOff, .flying:
            var f = peelFrame(pull: effectivePull)
            if phase == .flying { f = flown(f) }
            return f
        }
    }

    private func peelFrame(pull p: Double) -> DogEarFrame {
        let shape = DogEarLayout.shape
        let state = p >= rules.minPull
            ? PeelState.peel(shape, grab: DogEarLayout.grab, finger: DogEarLayout.grab + direction * p)
            : PeelState.flat(shape)
        guard let fold = state.fold else {
            return DogEarFrame(flat: shape, flap: Polygon([]), creaseFrom: nil, creaseTo: nil, gradientFrom: .zero, gradientTo: .zero,
                               shadowDirection: direction, shading: .make(progress: 0, flapDepth: 1), areaFraction: 0,
                               cardOpacity: 1, cardScale: 1, flapOpacity: 0)
        }
        let depth = state.flap.points.map { fold.signedDistance($0) }.max() ?? 1
        let shading = DogEarShading.make(progress: min(1, p / max(reach, 1)), flapDepth: depth)
        let mid = state.crease.map { Vec2.lerp($0.0, $0.1, 0.5) } ?? fold.point
        return DogEarFrame(flat: state.flat, flap: state.flap, creaseFrom: state.crease?.0, creaseTo: state.crease?.1,
                           gradientFrom: mid, gradientTo: mid + fold.normal * shading.gradientLength,
                           shadowDirection: fold.normal, shading: shading, areaFraction: state.fraction,
                           cardOpacity: 1, cardScale: 1, flapOpacity: 1)
    }

    /// The fly-away: slides along the peel direction while turning a little about its centre, then fades.
    private func flown(_ f: DogEarFrame) -> DogEarFrame {
        let u = WhimsyMath.clamp01(age / rules.flyDuration)
        let side: Double = direction.x >= 0 ? 1 : -1
        let angle = side * rules.flyRotation * WhimsyMath.easeOutCubic(u)
        let shift = direction * (rules.flyDistance * u * u)
        let c = f.flap.centroid
        let (s, k) = (sin(angle), cos(angle))
        func move(_ p: Vec2) -> Vec2 {
            let d = p - c
            return c + Vec2(d.x * k - d.y * s, d.x * s + d.y * k) + shift
        }
        var g = f
        g.flap = Polygon(f.flap.points.map(move))
        g.gradientFrom = move(f.gradientFrom)
        g.gradientTo = move(f.gradientTo)
        g.creaseFrom = f.creaseFrom.map(move)
        g.creaseTo = f.creaseTo.map(move)
        g.flapOpacity = 1 - WhimsyMath.smoothstep(0.3, 1, u)
        return g
    }

    // MARK: Accessibility

    public var accessibilityLabel: String { content.frontLabel }

    public var accessibilityValue: String {
        switch phase {
        case .idle, .returning: return "Closed"
        case .dragging, .springingBack: return "Peeling, \(Int((progress * 100).rounded())) percent"
        case .peelingOff, .flying, .fading, .revealed: return "Peeled away"
        }
    }
}
