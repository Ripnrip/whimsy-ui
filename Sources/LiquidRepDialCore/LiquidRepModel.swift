import Foundation

public enum LiquidRepEvent: Equatable, Sendable {
    /// One rep was added. A jump of several reps ticks once per rep.
    case tick
    /// The count crossed the goal on the way up. Later reps do not repeat it.
    case goalReached
}

/// The rep dial. `targetFill` is reps ÷ goal. The displayed fill chases it on a
/// spring with bounce 0.4, and a tap kicks the velocity so the rim runs past the
/// new mark and settles back. Tilt shifts that pool toward the low side. The
/// leading edge carries a meniscus wobble while the liquid is moving.
///
/// Reduce Motion drops the spring, the slosh and the wobble. The fill crossfades
/// in a straight line.
public struct LiquidRepModel: Equatable, Sendable {
    public private(set) var reps: Int
    public private(set) var goal: Int
    public private(set) var reduceMotion: Bool
    public private(set) var tilt: LiquidTilt
    public private(set) var elapsed: Double
    public private(set) var meniscusEnvelope: Double

    private var spring: WhimsySpring
    private var slosh: WhimsySpring
    private var fadeFrom: Double
    private var fadeTo: Double
    private var fadeElapsed: Double
    private var fadeShown: Double
    private var meniscusPhase: Double

    public init(
        reps: Int = 0,
        goal: Int = LiquidRepTuning.defaultGoal,
        tilt: LiquidTilt = .zero,
        reduceMotion: Bool = false
    ) {
        let clampedGoal = max(LiquidRepTuning.minimumGoal, goal)
        let clampedReps = min(max(reps, 0), LiquidRepTuning.maxReps)
        self.reps = clampedReps
        self.goal = clampedGoal
        self.reduceMotion = reduceMotion
        self.tilt = LiquidTilt(
            roll: tilt.roll.isFinite ? tilt.roll : 0,
            pitch: tilt.pitch.isFinite ? tilt.pitch : 0
        )
        let fill = WhimsyMath.clamp(Double(clampedReps) / Double(clampedGoal), 0, 1)
        spring = WhimsySpring(
            value: fill,
            velocity: 0,
            stiffness: LiquidRepTuning.stiffness,
            dampingRatio: LiquidRepTuning.dampingRatio
        )
        slosh = WhimsySpring(
            value: 0,
            velocity: 0,
            stiffness: LiquidRepTuning.sloshStiffness,
            dampingRatio: LiquidRepTuning.dampingRatio
        )
        fadeFrom = fill
        fadeTo = fill
        fadeElapsed = LiquidRepTuning.crossfadeDuration
        fadeShown = fill
        meniscusEnvelope = 0
        meniscusPhase = 0
        elapsed = 0
    }

    /// Reps divided by the goal, clamped to 0…1. Past the goal the rim stays full.
    public var targetFill: Double {
        guard goal > 0 else { return 0 }
        return WhimsyMath.clamp(Double(reps) / Double(goal), 0, 1)
    }

    /// The spring's position, or the crossfade while Reduce Motion is on.
    /// This may sit past `targetFill` for a moment after a tap.
    public var displayedFill: Double { reduceMotion ? fadeShown : spring.value }

    public var fillVelocity: Double { reduceMotion ? 0 : spring.velocity }

    /// Clockwise radians from the resting arc. Zero under Reduce Motion.
    public var sloshAngle: Double { reduceMotion ? 0 : slosh.value }

    /// −1…1 wobble at the leading edge. Zero at rest and under Reduce Motion.
    public var meniscus: Double {
        if reduceMotion { return 0 }
        return meniscusEnvelope * LiquidRepMath.sin(meniscusPhase)
    }

    public var atGoal: Bool { reps >= goal }

    public var glow: Double {
        LiquidRepMath.glow(
            fill: displayedFill,
            atGoal: atGoal,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
    }

    public var rim: LiquidRim {
        LiquidRepMath.rim(fill: displayedFill, slosh: sloshAngle, meniscus: meniscus, glow: glow)
    }

    public var readout: String { String(reps) }

    public var canAddRep: Bool { reps < LiquidRepTuning.maxReps }

    public var accessibilityLabel: String { LiquidRepTuning.accessibilityLabel }

    /// For example `12 of 20 reps`.
    public var accessibilityValue: String { "\(reps) of \(goal) reps" }

    public var needsClock: Bool {
        if reduceMotion {
            return fadeFrom != fadeTo && fadeElapsed < LiquidRepTuning.crossfadeDuration
        }
        if atGoal { return true }
        if !spring.isSettled(at: targetFill, tolerance: LiquidRepTuning.settleTolerance) { return true }
        let sloshGoal = LiquidRepMath.sloshTarget(fill: targetFill, tilt: tilt)
        if !slosh.isSettled(at: sloshGoal, tolerance: LiquidRepTuning.settleTolerance) { return true }
        if meniscusEnvelope > 0.01 { return true }
        return false
    }

    /// Adds one rep. At the cap, nothing happens.
    @discardableResult
    public mutating func addRep() -> [LiquidRepEvent] {
        setReps(reps + 1)
    }

    /// Replace the count. Each rep on the way up ticks. Crossing the goal adds
    /// ``LiquidRepEvent/goalReached`` once. A count that clamps to the current
    /// value emits nothing. Going down does not tick.
    @discardableResult
    public mutating func setReps(_ raw: Int) -> [LiquidRepEvent] {
        let next = min(max(raw, 0), LiquidRepTuning.maxReps)
        if next == reps { return [] }
        let previous = reps
        reps = next
        if next > previous {
            var events: [LiquidRepEvent] = []
            let steps = next - previous
            events.reserveCapacity(steps + 1)
            for _ in 0..<steps { events.append(.tick) }
            if previous < goal && next >= goal { events.append(.goalReached) }
            retarget(kick: true)
            return events
        }
        retarget(kick: false)
        return []
    }

    /// Replace the goal. The minimum is 1. The fill retargets and does not tick,
    /// because a goal edit is not a rep.
    public mutating func setGoal(_ raw: Int) {
        let next = max(LiquidRepTuning.minimumGoal, raw)
        guard next != goal else { return }
        goal = next
        retarget(kick: false)
    }

    /// Replace the tilt. Non-finite components become 0. The pool springs toward
    /// the new low side on the next `step`. Reduce Motion stores the tilt and
    /// keeps the drawn slosh at 0.
    public mutating func setTilt(_ tilt: LiquidTilt) {
        self.tilt = LiquidTilt(
            roll: tilt.roll.isFinite ? tilt.roll : 0,
            pitch: tilt.pitch.isFinite ? tilt.pitch : 0
        )
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on {
            let shown = spring.value
            fadeFrom = shown
            fadeTo = targetFill
            fadeElapsed = 0
            fadeShown = shown
            spring.snap(to: shown)
            slosh.snap(to: 0)
            meniscusEnvelope = 0
            meniscusPhase = 0
            elapsed = 0
        } else {
            spring.snap(to: fadeShown)
        }
    }

    /// Advances the spring, the slosh and the meniscus by `dt` seconds.
    /// A stalled frame is clamped to ``WhimsySpring/maxFrame``. Non-positive and
    /// non-finite deltas are ignored. Reduce Motion only crossfades the fill.
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let frame = min(dt, WhimsySpring.maxFrame)
        if reduceMotion {
            advanceFade(frame)
            return
        }
        elapsed += frame
        spring.step(toward: targetFill, dt: frame)
        let sloshGoal = LiquidRepMath.sloshTarget(fill: targetFill, tilt: tilt)
        slosh.step(toward: sloshGoal, dt: frame)
        advanceMeniscus(frame)
    }

    // MARK: private

    private mutating func retarget(kick: Bool) {
        if reduceMotion {
            fadeFrom = displayedFill
            fadeTo = targetFill
            fadeElapsed = 0
            spring.snap(to: displayedFill)
            slosh.snap(to: 0)
            meniscusEnvelope = 0
            meniscusPhase = 0
            return
        }
        if kick { spring.velocity += LiquidRepTuning.impulse }
    }

    private mutating func advanceFade(_ dt: Double) {
        let duration = LiquidRepTuning.crossfadeDuration
        fadeElapsed = min(duration, fadeElapsed + dt)
        let t = duration > 0 ? fadeElapsed / duration : 1
        fadeShown = fadeFrom + (fadeTo - fadeFrom) * t
        spring.snap(to: fadeShown)
        slosh.snap(to: 0)
        meniscusEnvelope = 0
    }

    private mutating func advanceMeniscus(_ dt: Double) {
        let speed = abs(spring.velocity)
        let target = speed.isFinite ? WhimsyMath.clamp01(speed / LiquidRepTuning.meniscusSpeed) : 0
        let rate = target > meniscusEnvelope ? LiquidRepTuning.meniscusRise : LiquidRepTuning.meniscusFall
        let delta = target - meniscusEnvelope
        let limit = rate * dt
        if abs(delta) <= limit {
            meniscusEnvelope = target
        } else {
            meniscusEnvelope += delta > 0 ? limit : -limit
        }
        let drive = 0.35 + 0.65 * meniscusEnvelope
        meniscusPhase += LiquidRepTuning.meniscusOmega * dt * drive
    }
}

/// One scripted change in the reel the canvas port plays.
public enum LiquidRepCue: Equatable, Sendable {
    case add
    case reps(Int)
    case tilt(LiquidTilt)
    case level
}

/// A named frame of the reel, shared with the contact sheet.
public struct LiquidRepStill: Equatable, Sendable {
    public var name: String
    public var frame: Int

    public init(name: String, frame: Int) {
        self.name = name
        self.frame = frame
    }
}

/// The scripted reel: an empty dial, a first-tap overshoot, a half fill with a
/// tilt, the goal glow, then a Reduce Motion crossfade. `dt` is 1/60 s so both
/// ports share a frame.
public enum LiquidRepReel {
    public static let dt = 1.0 / 60.0
    public static let goal = 20
    public static let motionFrames = 420
    public static let reduceCueFrame = 20
    public static let reduceSpan = 76

    public static let cues: [(frame: Int, cue: LiquidRepCue)] = [
        (30, .add),
        (72, .add),
        (108, .add),
        (150, .reps(10)),
        (198, .tilt(LiquidTilt(roll: 0.15, pitch: 0.55))),
        (250, .level),
        (270, .reps(17)),
        (330, .reps(20)),
    ]

    public static let stills: [LiquidRepStill] = [
        LiquidRepStill(name: "Idle empty", frame: 12),
        LiquidRepStill(name: "First tap overshoot", frame: 38),
        LiquidRepStill(name: "Mid fill", frame: 190),
        LiquidRepStill(name: "Near goal", frame: 306),
        LiquidRepStill(name: "Goal reached glow", frame: 366),
        LiquidRepStill(name: "Tilt slosh", frame: 226),
        LiquidRepStill(name: "Reduce Motion", frame: 448),
    ]

    public static var reduceStart: Int { motionFrames }
    public static var totalFrames: Int { motionFrames + reduceSpan }
    public static var duration: Double { Double(totalFrames) * dt }

    /// Half away from zero, matching `Math.floor(t / dt + 0.5)` for a positive time.
    public static func frameCount(_ time: Double) -> Int {
        guard time.isFinite, time > 0 else { return 0 }
        return Int((time / dt + 0.5).rounded(.down))
    }

    public static func model(at time: Double) -> LiquidRepModel {
        model(atFrame: frameCount(time))
    }

    public static func model(atFrame frame: Int) -> LiquidRepModel {
        if frame >= reduceStart { return reduceModel(local: frame - reduceStart) }
        return motionModel(steps: max(0, frame))
    }

    private static func motionModel(steps: Int) -> LiquidRepModel {
        var model = LiquidRepModel(reps: 0, goal: goal, reduceMotion: false)
        for frame in 0..<max(0, steps) {
            for entry in cues where entry.frame == frame {
                apply(entry.cue, to: &model)
            }
            model.step(dt)
        }
        return model
    }

    private static func reduceModel(local: Int) -> LiquidRepModel {
        var model = LiquidRepModel(reps: 0, goal: goal, reduceMotion: true)
        for frame in 0..<max(0, local) {
            if frame == reduceCueFrame { _ = model.setReps(12) }
            model.step(dt)
        }
        return model
    }

    private static func apply(_ cue: LiquidRepCue, to model: inout LiquidRepModel) {
        switch cue {
        case .add:
            _ = model.addRep()
        case .reps(let count):
            _ = model.setReps(count)
        case .tilt(let tilt):
            model.setTilt(tilt)
        case .level:
            model.setTilt(.zero)
        }
    }
}
