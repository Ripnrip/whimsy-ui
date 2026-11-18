import Foundation

public enum OnAirEvent: Equatable, Sendable {
    /// The committed on-air state changed. The binding updates here, not when the spring lands.
    case committed(Bool)
    /// One soft click, fired when the knob reaches the stop (or the crossfade ends).
    case haptic
}

/// The on-air lamp. One spring owns the throw; dim, glow and the label are functions of
/// that progress. Reduce Motion replaces the spring with a short crossfade and holds the breath.
public struct OnAirModel: Sendable {
    public private(set) var isOn: Bool
    public private(set) var isDragging: Bool
    public private(set) var elapsed: Double
    public private(set) var reduceMotion: Bool
    public private(set) var spring: WhimsySpring

    private var progressBeforeDrag: Double
    private var fading: Bool
    private var fadeOrigin: Double
    private var fadeDestination: Double
    private var fadeElapsed: Double
    private var hapticArmed: Bool

    public init(isOn: Bool = false, reduceMotion: Bool = false) {
        self.isOn = isOn
        self.isDragging = false
        self.elapsed = 0
        self.reduceMotion = reduceMotion
        let start = isOn ? 1.0 : 0.0
        spring = WhimsySpring(
            value: start,
            velocity: 0,
            stiffness: OnAirTuning.stiffness,
            dampingRatio: OnAirTuning.dampingRatio
        )
        progressBeforeDrag = start
        fading = false
        fadeOrigin = start
        fadeDestination = start
        fadeElapsed = 0
        hapticArmed = false
    }

    public var throwProgress: Double { spring.value }

    public var dimAmount: Double { OnAirTuning.dimAmount(progress: throwProgress) }

    public var backgroundMultiply: Double { OnAirTuning.backgroundMultiply(progress: throwProgress) }

    public var glow: Double {
        OnAirTuning.glow(progress: throwProgress, elapsed: elapsed, live: isOn, reduceMotion: reduceMotion)
    }

    public var chromeOpacity: Double { OnAirTuning.chromeOpacity(progress: throwProgress) }

    public var timerText: String { OnAirClock.format(elapsed) }

    /// VoiceOver value. On air it includes the running timer, for example `On air, 01:23`.
    public var accessibilityValue: String {
        isOn ? "On air, \(timerText)" : "Off"
    }

    public var meter: [Double] { OnAirTuning.meterLevels(at: elapsed, reduceMotion: reduceMotion) }

    public var knobCenter: (x: Double, y: Double) { OnAirTuning.knobCenter(progress: throwProgress) }

    /// The timeline can sleep only when the lamp is off and the knob is sitting still.
    public var needsClock: Bool {
        if isOn || isDragging || fading || hapticArmed { return true }
        return !spring.isSettled(at: 0, tolerance: OnAirTuning.settleTolerance)
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        let destination = isOn ? 1.0 : 0.0
        if on {
            beginFade(to: destination)
            if !fading { spring.snap(to: destination) }
        } else {
            // Hand the crossfade's current position to the spring and let it finish.
            fading = false
        }
    }

    /// Commits `on` and throws the knob to that stop. Already sitting there clicks at once.
    @discardableResult
    public mutating func setOn(_ on: Bool) -> [OnAirEvent] {
        isDragging = false
        var events: [OnAirEvent] = []
        if on != isOn {
            isOn = on
            if on { elapsed = 0 }
            events.append(.committed(on))
        }
        let destination = on ? 1.0 : 0.0
        if reduceMotion {
            beginFade(to: destination)
            if fading {
                hapticArmed = true
            } else if !events.isEmpty {
                spring.snap(to: destination)
                hapticArmed = false
                events.append(.haptic)
                if !on { elapsed = 0 }
            }
            return events
        }
        if isHome(destination) {
            spring.snap(to: destination)
            hapticArmed = false
            if !events.isEmpty {
                events.append(.haptic)
                if !on { elapsed = 0 }
            }
            return events
        }
        hapticArmed = true
        return events
    }

    @discardableResult
    public mutating func toggle() -> [OnAirEvent] { setOn(!isOn) }

    /// Grabs the knob when the finger is on the pill. A miss leaves the model alone.
    @discardableResult
    public mutating func beginDrag(sceneX: Double, sceneY: Double) -> Bool {
        guard sceneX.isFinite, OnAirTuning.pillContains(y: sceneY) else { return false }
        progressBeforeDrag = spring.value
        isDragging = true
        fading = false
        hapticArmed = false
        spring.snap(to: OnAirTuning.progress(forSceneX: sceneX))
        return true
    }

    public mutating func updateDrag(sceneX: Double) {
        guard isDragging, sceneX.isFinite else { return }
        spring.snap(to: OnAirTuning.progress(forSceneX: sceneX))
    }

    /// `translation` is the horizontal travel in scene points. A short one toggles;
    /// a real drag commits on when the knob is at or past `commitThreshold`.
    @discardableResult
    public mutating func endDrag(translation: Double) -> [OnAirEvent] {
        guard isDragging else { return [] }
        if !translation.isFinite {
            spring.snap(to: progressBeforeDrag)
            return setOn(isOn)
        }
        if abs(translation) <= OnAirTuning.tapSlop {
            spring.snap(to: progressBeforeDrag)
            return setOn(!isOn)
        }
        let on = spring.value >= OnAirTuning.commitThreshold
        return setOn(on)
    }

    /// Advances motion and the on-air clock. A stalled frame is clamped to the spring's
    /// maximum, so a hitch cannot skip the click or jump the timer.
    @discardableResult
    public mutating func step(_ dt: Double) -> [OnAirEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        let frame = min(dt, WhimsySpring.maxFrame)
        if isDragging {
            if isOn { elapsed += frame }
            return []
        }
        let events = reduceMotion ? advanceFade(frame) : advanceSpring(frame)
        if isOn { elapsed += frame }
        return events
    }

    private mutating func advanceSpring(_ frame: Double) -> [OnAirEvent] {
        let destination = isOn ? 1.0 : 0.0
        var events: [OnAirEvent] = []
        if !spring.isSettled(at: destination, tolerance: OnAirTuning.settleTolerance) {
            spring.step(toward: destination, dt: frame)
        }
        if hapticArmed {
            let reached = destination >= 1 ? spring.value >= 1 : spring.value <= 0
            let seated = spring.isSettled(at: destination, tolerance: OnAirTuning.settleTolerance)
            if reached || seated {
                events.append(.haptic)
                hapticArmed = false
            }
        }
        if spring.isSettled(at: destination, tolerance: OnAirTuning.settleTolerance) {
            spring.snap(to: destination)
            if !isOn { elapsed = 0 }
        }
        return events
    }

    private mutating func advanceFade(_ frame: Double) -> [OnAirEvent] {
        let destination = isOn ? 1.0 : 0.0
        guard fading else {
            if spring.isSettled(at: destination, tolerance: OnAirTuning.settleTolerance) {
                spring.snap(to: destination)
                if !isOn { elapsed = 0 }
            }
            return []
        }
        fadeElapsed += frame
        let t = min(1, fadeElapsed / OnAirTuning.reduceDuration)
        let value = fadeOrigin + (fadeDestination - fadeOrigin) * WhimsyMath.easeInOutCubic(t)
        spring.snap(to: value)
        var events: [OnAirEvent] = []
        if t >= 1 {
            fading = false
            spring.snap(to: fadeDestination)
            if hapticArmed {
                events.append(.haptic)
                hapticArmed = false
            }
            if !isOn { elapsed = 0 }
        }
        return events
    }

    private mutating func beginFade(to destination: Double) {
        fadeOrigin = spring.value
        fadeDestination = destination
        fadeElapsed = 0
        fading = abs(spring.value - destination) > OnAirTuning.settleTolerance
        if !fading { spring.snap(to: destination) }
    }

    private func isHome(_ destination: Double) -> Bool {
        spring.isSettled(at: destination, tolerance: OnAirTuning.settleTolerance)
    }
}
