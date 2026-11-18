import Foundation

public enum GlassMorphEvent: Equatable, Sendable {
    /// Pay was accepted. The glass leaves the card.
    case paid
    /// The lights reached the two-dot mark. This is the one success haptic.
    case settled
    /// The hold ended and the half-turn started.
    case unfolding
    /// The card is back, upright.
    case returned
}

/// Card → morphing → pill → unfolding → card.
///
/// Full motion springs one unit progress from 0 to 1. The frame and both lights are
/// that progress, so they settle together. The pill then holds for one second. The
/// opening is a half-turn: progress eases back to 0 while the flip runs 0 → π.
/// Reduce Motion keeps the flip at 0 and moves progress in a straight line; the view
/// crossfades the two poses instead of travelling.
///
/// A stalled frame is clamped to `maxFrame` and split into ≤ 1/240 s substeps, the
/// same order `webports/glassmorph-core.mjs` uses. Stepping while the phase is `.card`
/// changes nothing.
public struct GlassMorphModel: Equatable, Sendable {
    public private(set) var phase: GlassMorphPhase
    public private(set) var reduceMotion: Bool
    public private(set) var progress: Double
    public private(set) var progressVelocity: Double
    public private(set) var flipAngle: Double
    public private(set) var phaseAge: Double
    public private(set) var clock: Double
    public private(set) var settledCount: Int
    /// Clock value on the substep that settled the lights. Nil until the first payment.
    public private(set) var settledClock: Double?
    /// Clock value on the substep that started the half-turn.
    public private(set) var unfoldClock: Double?

    public init(reduceMotion: Bool = false) {
        phase = .card
        self.reduceMotion = reduceMotion
        progress = 0
        progressVelocity = 0
        flipAngle = 0
        phaseAge = 0
        clock = 0
        settledCount = 0
        settledClock = nil
        unfoldClock = nil
    }

    public var frame: GlassMorphFrame { GlassMorphLayout.frame(progress: progress) }
    public var amber: GlassLight { GlassMorphLayout.light(.amber, progress: progress) }
    public var red: GlassLight { GlassMorphLayout.light(.red, progress: progress) }

    public var cardContentOpacity: Double {
        GlassMorphLayout.cardContentOpacity(phase: phase, progress: progress, flip: flipAngle, reduceMotion: reduceMotion)
    }

    public var dotOpacity: Double {
        GlassMorphLayout.dotOpacity(phase: phase, progress: progress, flip: flipAngle, reduceMotion: reduceMotion)
    }

    public var glowOpacity: Double {
        GlassMorphLayout.glowOpacity(phase: phase, progress: progress, flip: flipAngle, reduceMotion: reduceMotion)
    }

    public var edgeGlow: Double {
        GlassMorphLayout.edgeGlow(phase: phase, flip: flipAngle, reduceMotion: reduceMotion)
    }

    public var displayFlip: Double {
        GlassMorphLayout.displayFlip(flipAngle, reduceMotion: reduceMotion)
    }

    /// 0…1 blend of the resting card and the resting pill. Full motion stays at 0;
    /// the view travels one pose instead of crossfading.
    public var crossfade: Double {
        reduceMotion ? WhimsyMath.clamp01(progress) : 0
    }

    public var isAtRest: Bool {
        phase == .card && progress == 0 && flipAngle == 0 && progressVelocity == 0
    }

    public var accessibilityValue: String {
        switch phase {
        case .card: GlassMorphTuning.readyValue
        case .morphing: GlassMorphTuning.payingValue
        case .pill: GlassMorphTuning.paidValue
        case .unfolding: GlassMorphTuning.openingValue
        }
    }

    // MARK: input

    /// Starts a payment from the resting card. Ignored in every other phase.
    public mutating func pay() -> [GlassMorphEvent] {
        guard phase == .card else { return [] }
        phase = .morphing
        phaseAge = 0
        progress = 0
        progressVelocity = 0
        flipAngle = 0
        return [.paid]
    }

    /// A tap in stage points. Only the Pay button on the resting, tilted card counts.
    public mutating func pay(at point: Vec2) -> [GlassMorphEvent] {
        guard containsPay(point) else { return [] }
        return pay()
    }

    public func containsPay(_ point: Vec2) -> Bool {
        guard phase == .card else { return false }
        guard point.x.isFinite, point.y.isFinite else { return false }
        let frame = GlassMorphLayout.frame(progress: 0)
        let local = GlassMorphLayout.localPoint(point, center: frame.center, tilt: frame.tilt)
        return GlassMorphTuning.payButton.contains(local)
    }

    public mutating func reset() {
        self = GlassMorphModel(reduceMotion: reduceMotion)
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        progressVelocity = 0
        if on {
            flipAngle = 0
        } else if phase == .unfolding {
            let u = WhimsyMath.clamp01(1 - progress)
            phaseAge = u * GlassMorphTuning.unfoldDuration
            flipAngle = GlassMorphLayout.flipAngle(at: phaseAge)
        }
    }

    // MARK: time

    /// Advances by `dt` seconds. Non-finite or non-positive input is ignored.
    public mutating func step(_ dt: Double) -> [GlassMorphEvent] {
        guard dt > 0, dt.isFinite, phase != .card else { return [] }
        var remaining = min(dt, GlassMorphTuning.maxFrame)
        var events: [GlassMorphEvent] = []
        while remaining > 1e-12 {
            let h = min(remaining, GlassMorphTuning.substep)
            substep(h, events: &events)
            remaining -= h
        }
        return events
    }

    // MARK: private

    private mutating func substep(_ h: Double, events: inout [GlassMorphEvent]) {
        guard phase != .card else { return }
        clock += h
        switch phase {
        case .card:
            break
        case .morphing:
            integrateMorph(h, events: &events)
        case .pill:
            integratePill(h, events: &events)
        case .unfolding:
            integrateUnfold(h, events: &events)
        }
    }

    private mutating func integrateMorph(_ h: Double, events: inout [GlassMorphEvent]) {
        if reduceMotion {
            progress = min(1, progress + h / GlassMorphTuning.fadeDuration)
            progressVelocity = 0
            flipAngle = 0
            if progress >= 1 - 1e-12 { arrive(&events) }
            return
        }
        var spring = WhimsySpring(value: progress, velocity: progressVelocity,
                                  stiffness: GlassMorphTuning.morphStiffness,
                                  dampingRatio: GlassMorphTuning.morphDamping)
        spring.substep(toward: 1, h: h)
        progress = spring.value
        progressVelocity = spring.velocity
        if spring.isSettled(at: 1, tolerance: GlassMorphTuning.settleTolerance) {
            arrive(&events)
        }
    }

    private mutating func integratePill(_ h: Double, events: inout [GlassMorphEvent]) {
        phaseAge += h
        progress = 1
        progressVelocity = 0
        flipAngle = 0
        if phaseAge >= GlassMorphTuning.holdDuration - 1e-12 {
            beginUnfold(&events)
        }
    }

    private mutating func integrateUnfold(_ h: Double, events: inout [GlassMorphEvent]) {
        if reduceMotion {
            progress = max(0, progress - h / GlassMorphTuning.fadeDuration)
            progressVelocity = 0
            flipAngle = 0
            if progress <= 1e-12 { finish(&events) }
            return
        }
        phaseAge += h
        let u = min(1, phaseAge / GlassMorphTuning.unfoldDuration)
        let eased = GlassMorphLayout.easeInOutCubic(u)
        progress = 1 - eased
        progressVelocity = 0
        flipAngle = Double.pi * eased
        if phaseAge >= GlassMorphTuning.unfoldDuration - 1e-12 {
            finish(&events)
        }
    }

    private mutating func arrive(_ events: inout [GlassMorphEvent]) {
        progress = 1
        progressVelocity = 0
        flipAngle = 0
        phase = .pill
        phaseAge = 0
        settledCount += 1
        settledClock = clock
        events.append(.settled)
    }

    private mutating func beginUnfold(_ events: inout [GlassMorphEvent]) {
        phase = .unfolding
        phaseAge = 0
        progress = 1
        progressVelocity = 0
        flipAngle = 0
        unfoldClock = clock
        events.append(.unfolding)
    }

    private mutating func finish(_ events: inout [GlassMorphEvent]) {
        phase = .card
        progress = 0
        progressVelocity = 0
        flipAngle = 0
        phaseAge = 0
        events.append(.returned)
    }
}
