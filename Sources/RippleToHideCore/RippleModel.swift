import Foundation

/// Settled or in the middle of a hide / reveal trip.
public enum RipplePhase: Equatable, Sendable {
    case shown
    case hiding
    case hidden
    case revealing
}

/// What a trip did. The view plays a soft haptic on ``haptic`` and flips `isHidden` on the swaps.
public enum RippleEvent: Equatable, Sendable {
    /// A tap (or an external hide) started an outward ripple.
    case beganHiding
    /// A tap (or an external show) started the ripple back toward the tap.
    case beganRevealing
    /// Halfway: the digits become dots.
    case swappedToMask
    /// Halfway on the way back: the digits return.
    case swappedToDigits
    /// The wavefront crossed `passRadius`. Once per trip. Not sent under Reduce Motion.
    case haptic
    case settledHidden
    case settledShown
}

/// Timing, the halfway swap, and the wavefront haptic for one balance.
///
/// A trip runs `elapsed` from 0 to the active duration. Hiding feeds `elapsed` to the shader, so
/// the front moves outward. Revealing feeds `duration - elapsed`, so the same wave runs backward.
/// The digits swap when `elapsed` crosses half the active duration. Reduce Motion keeps the same
/// halfway swap but reports amplitude 0 and a linear `maskAmount` for a crossfade, and it does
/// not emit ``RippleEvent/haptic``.
public struct RippleModel: Equatable, Sendable {
    public let rules: RippleRules
    public var reduceMotion: Bool
    public private(set) var phase: RipplePhase
    public private(set) var elapsed: Double
    public private(set) var tap: Vec2
    public private(set) var passRadius: Double
    public private(set) var showsMask: Bool
    private var hapticFired: Bool

    public init(rules: RippleRules = .standard, reduceMotion: Bool = false) {
        self.rules = rules
        self.reduceMotion = reduceMotion
        self.phase = .shown
        self.elapsed = 0
        self.tap = .zero
        self.passRadius = 0
        self.showsMask = false
        self.hapticFired = false
    }

    public var isAnimating: Bool { phase == .hiding || phase == .revealing }

    /// True once the digits have swapped to dots, including while a reveal is still on its way back.
    public var isHidden: Bool { showsMask }

    public var activeDuration: Double {
        reduceMotion ? rules.reduceMotionDuration : rules.duration
    }

    /// `time` uniform. Revealing runs the clock backward. Zero when the shader should be off.
    public var shaderTime: Double {
        guard isAnimating, !reduceMotion else { return 0 }
        if phase == .revealing { return max(rules.duration - elapsed, 0) }
        return elapsed
    }

    /// `amplitude` uniform. Zero under Reduce Motion and while settled.
    public var shaderAmplitude: Double {
        guard isAnimating, !reduceMotion else { return 0 }
        return rules.amplitude
    }

    /// 0 is the real amount, 1 is the dotted mask.
    /// Full motion swaps in one step at halfway. Reduce Motion eases across the whole trip.
    public var maskAmount: Double {
        switch phase {
        case .shown: return 0
        case .hidden: return 1
        case .hiding:
            if reduceMotion { return WhimsyMath.clamp01(elapsed / activeDuration) }
            return showsMask ? 1 : 0
        case .revealing:
            if reduceMotion { return 1 - WhimsyMath.clamp01(elapsed / activeDuration) }
            return showsMask ? 1 : 0
        }
    }

    /// Jump to a settled state. Used when the binding is already hidden at first appearance.
    public mutating func snap(hidden: Bool) {
        phase = hidden ? .hidden : .shown
        showsMask = hidden
        elapsed = 0
        hapticFired = false
    }

    /// Tap. Starts a hide from `.shown` or a reveal from `.hidden`. Ignored mid-trip.
    public mutating func toggle(at point: Vec2, passRadius: Double) -> [RippleEvent] {
        switch phase {
        case .shown: return begin(hiding: true, at: point, passRadius: passRadius)
        case .hidden: return begin(hiding: false, at: point, passRadius: passRadius)
        case .hiding, .revealing: return []
        }
    }

    /// Match an external binding. No-op when a trip is already doing that, or one is in flight.
    public mutating func setHidden(_ hidden: Bool, at point: Vec2, passRadius: Double) -> [RippleEvent] {
        if hidden {
            guard phase == .shown else { return [] }
            return begin(hiding: true, at: point, passRadius: passRadius)
        }
        guard phase == .hidden else { return [] }
        return begin(hiding: false, at: point, passRadius: passRadius)
    }

    public mutating func advance(by dt: Double) -> [RippleEvent] {
        guard isAnimating, dt > 0, dt.isFinite else { return [] }
        let before = elapsed
        let duration = activeDuration
        elapsed = min(duration, before + dt)

        // Emit in the order the moments fall inside this step, not the order the checks are written.
        var moments: [(time: Double, order: Int, event: RippleEvent)] = []
        if !reduceMotion, !hapticFired, let when = hapticElapsed, when > before, when <= elapsed {
            moments.append((when, 0, .haptic))
        }
        let half = duration * rules.swapFraction
        if before < half, elapsed >= half {
            if phase == .hiding, !showsMask {
                moments.append((half, 1, .swappedToMask))
            } else if phase == .revealing, showsMask {
                moments.append((half, 1, .swappedToDigits))
            }
        }
        if elapsed >= duration {
            let settled: RippleEvent = phase == .hiding ? .settledHidden : .settledShown
            moments.append((duration, 2, settled))
        }
        moments.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.order < rhs.order
        }

        var events: [RippleEvent] = []
        for moment in moments {
            switch moment.event {
            case .haptic:
                hapticFired = true
            case .swappedToMask:
                showsMask = true
            case .swappedToDigits:
                showsMask = false
            case .settledHidden:
                phase = .hidden
                showsMask = true
                elapsed = 0
                hapticFired = false
            case .settledShown:
                phase = .shown
                showsMask = false
                elapsed = 0
                hapticFired = false
            case .beganHiding, .beganRevealing:
                break
            }
            events.append(moment.event)
        }
        return events
    }

    /// Elapsed time at which the front crosses `passRadius`, or nil when it never does.
    private var hapticElapsed: Double? {
        guard passRadius > 0, passRadius.isFinite else { return nil }
        if phase == .revealing {
            let when = rules.duration - passRadius / rules.speed
            guard when > 0, when <= activeDuration else { return nil }
            return when
        }
        let when = passRadius / rules.speed
        guard when > 0, when <= activeDuration else { return nil }
        return when
    }

    private mutating func begin(hiding: Bool, at point: Vec2, passRadius: Double) -> [RippleEvent] {
        phase = hiding ? .hiding : .revealing
        elapsed = 0
        tap = point.x.isFinite && point.y.isFinite ? point : .zero
        self.passRadius = passRadius.isFinite ? max(passRadius, 0) : 0
        hapticFired = false
        showsMask = !hiding
        return [hiding ? .beganHiding : .beganRevealing]
    }
}
