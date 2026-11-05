import Foundation

/// Phases of a press-and-hold fan dock.
public enum HoldToFanPhase: Int, CaseIterable, Sendable {
    /// Nothing pressed.
    case idle
    /// Finger down, waiting for the arm threshold.
    case arming
    /// Armed: tabs are springing out along the arc.
    case opening
    /// Tabs are out; the finger can aim at one.
    case open
    /// Finger up after a selection or a cancel; tabs springing home.
    case closing
}

/// What the dock did, for the view (haptics, announcements) and tests.
public enum HoldToFanEvent: Equatable, Sendable {
    /// Arm threshold reached; the fan is about to open.
    case armed
    /// The fan has settled open (or snapped open under Reduce Motion).
    case opened
    /// The finger lifted over a tab.
    case selected(Int)
    /// The finger lifted with no tab, dragged off the arc, or cancelled.
    case cancelled
    /// The fan has fully closed and come to rest.
    case seated
    /// A short pulse for a tap that never armed (optional feedback).
    case pulsed
}

/// Pure-Swift state machine for a hold-to-fan floating action button.
///
/// Press and hold past ``armThreshold`` and four (or 3…5) tabs spring out along a quarter-circle
/// above-left of the FAB. Drag toward a tab to highlight it; lift over one to select it, or lift
/// elsewhere / drag far off the arc to snap shut. Release before the threshold is a no-op tap
/// (a ``pulsed`` event). Reduce Motion snaps open and closed with no springs.
public struct HoldToFanModel: Equatable, Sendable {
    public static let minTabs = HoldToFanLayout.minTabs
    public static let maxTabs = HoldToFanLayout.maxTabs
    public static let defaultTabs = HoldToFanLayout.defaultTabs

    /// Seconds of continuous press before the fan arms.
    public static let armThreshold = 0.2
    /// Stagger between successive tabs' spring responses (seconds).
    public static let stagger = 0.045
    /// Spring that drives the master open amount (and each tab via the step response).
    public static let openStiffness = 220.0
    public static let openDamping = 0.72
    /// Closing is a touch snappier.
    public static let closeStiffness = 280.0
    public static let closeDamping = 0.85
    public static let maxStep = 0.1
    public static let substep = 1.0 / 240

    public let count: Int
    public private(set) var phase = HoldToFanPhase.idle
    public private(set) var time = 0.0
    public private(set) var phaseTime = 0.0
    /// Master open amount the spring is tracking (0 closed … 1 open).
    public private(set) var open: Double = 0
    public private(set) var openVelocity: Double = 0
    /// Seconds since the fan began opening (for staggered step responses). Reset on close start.
    public private(set) var fanTime: Double = 0
    /// Index of the tab the finger is aiming at, if any.
    public private(set) var highlighted: Int? = nil
    public private(set) var reduceMotion: Bool
    public private(set) var finger: Vec2? = nil
    public private(set) var lastSelected: Int? = nil
    public private(set) var arms = 0
    public private(set) var opens = 0
    public private(set) var selects = 0
    public private(set) var cancels = 0
    public private(set) var seats = 0
    public private(set) var pulses = 0

    private var spring: WhimsySpring
    private var pendingSelect: Int? = nil
    private var closingReason: ClosingReason = .cancel

    private enum ClosingReason: Equatable, Sendable { case select(Int), cancel }

    public init(count: Int = defaultTabs, reduceMotion: Bool = false) {
        self.count = HoldToFanLayout.clampedCount(count)
        self.reduceMotion = reduceMotion
        spring = WhimsySpring(value: 0, velocity: 0, stiffness: Self.openStiffness, dampingRatio: Self.openDamping)
    }

    // MARK: derived

    public var isExpanded: Bool { phase == .opening || phase == .open || phase == .closing }
    public var isHolding: Bool { phase == .arming || phase == .opening || phase == .open }
    public var armProgress: Double {
        guard phase == .arming else { return phase == .idle ? 0 : 1 }
        return WhimsyMath.clamp01(phaseTime / Self.armThreshold)
    }

    /// Per-tab radial progress in 0…1. Under Reduce Motion this is just `open`; otherwise each
    /// tab follows a time-shifted copy of the open spring's step response so they stagger out.
    public func tabProgress(_ index: Int) -> Double {
        let i = min(max(index, 0), count - 1)
        if reduceMotion { return open }
        switch phase {
        case .idle: return 0
        case .arming: return 0
        case .opening:
            let t = max(0, fanTime - Self.stagger * Double(i))
            return WhimsyMath.clamp01(WhimsySpring.stepResponse(at: t, stiffness: Self.openStiffness, dampingRatio: Self.openDamping))
        case .open:
            return 1
        case .closing:
            // All tabs share the master spring on the way home (no reverse stagger).
            return WhimsyMath.clamp01(open)
        }
    }

    public func tabPosition(_ index: Int) -> Vec2 {
        HoldToFanLayout.position(of: index, count: count, progress: tabProgress(index))
    }

    public func tabScale(_ index: Int) -> Double {
        let base = 0.55 + 0.45 * tabProgress(index)
        guard highlighted == index, phase == .open || phase == .opening else { return base }
        return base * 1.18
    }

    public var angles: [Double] { HoldToFanLayout.angles(count: count) }

    // MARK: input

    /// Finger down on the FAB (or anywhere — the view usually gates this to the FAB).
    public mutating func pressBegan(at point: Vec2 = HoldToFanLayout.fab) -> [HoldToFanEvent] {
        guard point.x.isFinite, point.y.isFinite else { return [] }
        // A press during close restarts arming from wherever the fan is.
        finger = point
        highlighted = nil
        pendingSelect = nil
        if phase == .closing {
            // Re-arm immediately if already past threshold visually? Spec: new press. Start arming.
            phase = .arming; phaseTime = 0
            return []
        }
        guard phase == .idle else { return [] }
        phase = .arming; phaseTime = 0
        return []
    }

    public mutating func pressMoved(to point: Vec2) {
        guard point.x.isFinite, point.y.isFinite else { return }
        guard phase == .arming || phase == .opening || phase == .open else { return }
        finger = point
        if phase == .opening || phase == .open { highlighted = nearestTab(at: point) }
    }

    /// Finger up. Selects the highlighted tab, cancels, or pulses if we never armed.
    public mutating func pressEnded() -> [HoldToFanEvent] {
        defer { finger = nil }
        switch phase {
        case .idle, .closing:
            return []
        case .arming:
            phase = .idle; phaseTime = 0; highlighted = nil
            pulses += 1
            return [.pulsed]
        case .opening, .open:
            if let i = highlighted {
                return beginClosing(selecting: i)
            }
            return beginClosing(selecting: nil)
        }
    }

    /// Cancel without a selection (e.g. a system gesture interruption).
    public mutating func cancel() -> [HoldToFanEvent] {
        finger = nil; highlighted = nil
        switch phase {
        case .idle: return []
        case .arming:
            phase = .idle; phaseTime = 0; pulses += 1; return [.pulsed]
        case .opening, .open, .closing:
            if phase == .closing { return [] }
            return beginClosing(selecting: nil)
        }
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on {
            if phase == .opening {
                spring.snap(to: 1); open = 1; openVelocity = 0
                phase = .open; phaseTime = 0
            } else if phase == .open {
                spring.snap(to: 1); open = 1; openVelocity = 0
            } else if phase == .closing {
                spring.snap(to: 0); open = 0; openVelocity = 0
            } else {
                openVelocity = 0
            }
        }
    }

    // MARK: time

    public mutating func step(_ dt: Double) -> [HoldToFanEvent] {
        let d = dt.isFinite ? min(max(dt, 0), Self.maxStep) : 0
        guard d > 0 else { return [] }
        var events: [HoldToFanEvent] = []
        var remaining = d
        while remaining > 1e-12 {
            let h = min(remaining, Self.substep)
            events += substep(h)
            remaining -= h
        }
        return events
    }

    private mutating func substep(_ h: Double) -> [HoldToFanEvent] {
        var events: [HoldToFanEvent] = []
        time += h
        phaseTime += h
        switch phase {
        case .idle:
            break
        case .arming:
            if phaseTime >= Self.armThreshold {
                events += armAndOpen()
            }
        case .opening:
            fanTime += h
            tuneSpring(opening: true)
            spring.substep(toward: 1, h: h)
            open = WhimsyMath.clamp01(spring.value); openVelocity = spring.velocity
            if reduceMotion { spring.snap(to: 1); open = 1; openVelocity = 0 }
            if open >= 0.995 && abs(openVelocity) < 0.05 || reduceMotion {
                spring.snap(to: 1); open = 1; openVelocity = 0
                phase = .open; phaseTime = 0
                opens += 1
                events.append(.opened)
            }
            if let f = finger { highlighted = nearestTab(at: f) }
        case .open:
            fanTime += h
            // Keep the spring pinned open.
            if !reduceMotion {
                tuneSpring(opening: true)
                spring.substep(toward: 1, h: h)
                open = WhimsyMath.clamp01(spring.value); openVelocity = spring.velocity
            }
            if let f = finger { highlighted = nearestTab(at: f) }
        case .closing:
            tuneSpring(opening: false)
            if reduceMotion {
                spring.snap(to: 0); open = 0; openVelocity = 0
            } else {
                spring.substep(toward: 0, h: h)
                open = WhimsyMath.clamp01(spring.value); openVelocity = spring.velocity
            }
            if (open <= 0.005 && abs(openVelocity) < 0.05) || reduceMotion {
                events += finishClose()
            }
        }
        return events
    }

    // MARK: transitions

    private mutating func armAndOpen() -> [HoldToFanEvent] {
        arms += 1
        phase = .opening; phaseTime = 0; fanTime = 0
        tuneSpring(opening: true)
        if reduceMotion {
            spring.snap(to: 1); open = 1; openVelocity = 0
        }
        if let f = finger { highlighted = nearestTab(at: f) }
        return [.armed]
    }

    private mutating func beginClosing(selecting index: Int?) -> [HoldToFanEvent] {
        var events: [HoldToFanEvent] = []
        if let i = index {
            lastSelected = i; selects += 1; pendingSelect = i
            closingReason = .select(i)
            events.append(.selected(i))
        } else {
            cancels += 1; pendingSelect = nil
            closingReason = .cancel
            events.append(.cancelled)
        }
        highlighted = nil
        phase = .closing; phaseTime = 0
        // Capture current visual open as the spring's starting point so a mid-open cancel
        // doesn't jump. Under stagger the master `open` may lag the lead tabs; pull it up.
        let visual = (0..<count).map { tabProgress($0) }.max() ?? open
        spring.value = max(open, visual)
        spring.velocity = min(openVelocity, 0)
        open = spring.value
        tuneSpring(opening: false)
        if reduceMotion {
            spring.snap(to: 0); open = 0; openVelocity = 0
        }
        return events
    }

    private mutating func finishClose() -> [HoldToFanEvent] {
        spring.snap(to: 0); open = 0; openVelocity = 0; fanTime = 0
        phase = .idle; phaseTime = 0; highlighted = nil; pendingSelect = nil
        seats += 1
        return [.seated]
    }

    private mutating func tuneSpring(opening: Bool) {
        if opening {
            spring.stiffness = Self.openStiffness
            spring.dampingRatio = Self.openDamping
        } else {
            spring.stiffness = Self.closeStiffness
            spring.dampingRatio = Self.closeDamping
        }
    }

    // MARK: hit test

    /// The tab nearest the finger by angle, if the finger is in the arc's distance band and
    /// within ``HoldToFanLayout/aimHalfAngle`` of that tab. `nil` if off the arc (a lift will cancel).
    public func nearestTab(at point: Vec2) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let d = HoldToFanLayout.distance(of: point)
        guard d >= HoldToFanLayout.aimMinDistance && d <= HoldToFanLayout.aimMaxDistance else { return nil }
        let a = HoldToFanLayout.angle(of: point)
        let angs = angles
        var best: Int? = nil
        var bestAbs = Double.infinity
        for (i, θ) in angs.enumerated() {
            let ad = abs(HoldToFanLayout.angleDelta(a, θ))
            if ad < bestAbs { bestAbs = ad; best = i }
        }
        guard let i = best, bestAbs <= HoldToFanLayout.aimHalfAngle else { return nil }
        return i
    }
}
