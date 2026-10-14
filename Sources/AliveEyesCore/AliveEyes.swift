import Foundation
import WhimsyCore

/// What to draw this frame.
public struct EyesFrame: Equatable, Sendable {
    /// Gaze in the unit disc (+y down).
    public var gaze: Vec2
    /// Upper-lid closure per eye, 0 (open) … 1 (shut).
    public var leftLid: Double
    public var rightLid: Double
    /// Lower-lid rise from squinting, 0 … 1.
    public var squint: Double
    public var isBlinking: Bool
}

/// The whole "alive" brain: gaze spring, saccades, blinks and squint, stepped deterministically.
public struct AliveEyesModel: Equatable, Sendable {
    public static let maxSubstep = 1.0 / 240.0
    public static let maxFrameDelta = 0.1

    /// Resting lid droop: a touch different per eye so the face isn't mirror-perfect.
    public static let restingLid = (left: 0.07, right: 0.10)
    /// The right lid trails the left by this much during a blink.
    public static let rightLidDelay = 0.012
    /// How far a full squint lowers the upper lids.
    public static let squintLid = 0.42

    public private(set) var gazeController = GazeController()
    public private(set) var saccades: SaccadeScheduler
    public private(set) var blinks: BlinkScheduler
    public private(set) var squintState = SquintState()
    public private(set) var time = 0.0
    private var rng: SeededRandom

    /// Reduce Motion: no saccades, half-speed blinks, no double blinks.
    public var reduceMotion = false {
        didSet { applyMotionPreference() }
    }

    private mutating func applyMotionPreference() {
        saccades.isEnabled = !reduceMotion
        blinks.speed = reduceMotion ? 0.5 : 1
        blinks.allowsDoubles = !reduceMotion
    }

    public init(seed: UInt64 = 0xE7E5, reduceMotion: Bool = false) {
        var rng = SeededRandom(seed: seed)
        saccades = SaccadeScheduler(rng: &rng)
        blinks = BlinkScheduler(rng: &rng)
        self.rng = rng
        self.reduceMotion = reduceMotion   // observers don't run in init, so apply explicitly
        applyMotionPreference()
    }

    /// Finger target in gaze space (see `EyeGeometry.gazeTarget`), or nil when released.
    public mutating func setFinger(_ target: Vec2?) { gazeController.setTarget(target) }

    /// One accelerometer sample (user acceleration, g).
    public mutating func feedAcceleration(x: Double, y: Double, z: Double) {
        squintState.feed(x: x, y: y, z: z)
    }

    public mutating func squint() { squintState.trigger() }
    public mutating func blinkNow(double: Bool = false) { blinks.blinkNow(double: double) }

    public mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, Self.maxFrameDelta)
        while remaining > 0 {
            let h = min(remaining, Self.maxSubstep)
            saccades.step(dt: h, rng: &rng)
            blinks.step(dt: h, rng: &rng)
            squintState.step(dt: h)
            gazeController.step(dt: h, nudge: saccades.offset)
            time += h
            remaining -= h
        }
    }

    public var frame: EyesFrame {
        let squint = squintState.level
        let lid = { (rest: Double, blink: Double) in min(max(rest + Self.squintLid * squint, blink), 1) }
        return EyesFrame(
            gaze: gazeController.gaze,
            leftLid: lid(Self.restingLid.left, blinks.closure()),
            rightLid: lid(Self.restingLid.right, blinks.closure(delay: Self.rightLidDelay)),
            squint: squint,
            isBlinking: blinks.isBlinking
        )
    }
}
