import Foundation

/// What happened during a step.
public enum HoloEvent: Equatable, Sendable {
    /// The rainbow band crossed the card centre (+1 moving right, −1 moving left).
    case bandCrossedCenter(Int)
}

/// The holo card: a drag tilts it (soft-clamped to ±15°), release springs it back with a little wobble,
/// and the tilt drives the band, the sparkles and the centre-crossing haptic.
public struct HoloModel: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        /// While dragging, the tilt chases the finger through a stiff, nearly critical spring.
        public var dragStiffness = 420.0
        public var dragDamping = 0.9
        /// On release it springs back to flat, underdamped so it wobbles once or twice.
        public var releaseStiffness = 170.0
        public var releaseDamping = 0.5
        /// Reduce Motion: no wobble (critically damped return), and the view drops the 3D rotation.
        public var reduceMotion = false
        public init() {}
    }

    public var config: Config
    public private(set) var spring: WhimsySpring2D
    /// The tilt the spring is heading for (degrees, yaw then pitch).
    public private(set) var target = Vec2.zero
    public private(set) var isDragging = false
    /// Every debounced centre crossing (drives the haptic trigger).
    public private(set) var crossings = 0
    private var detector = CenterCrossingDetector()

    public init(config: Config = Config()) {
        self.config = config
        spring = WhimsySpring2D(value: .zero, stiffness: config.dragStiffness, dampingRatio: config.dragDamping)
        _ = detector.update(band: bandPosition, dt: 0)
    }

    /// Current tilt in degrees (yaw, pitch). The target is always inside ±maxAngle; the release wobble
    /// overshoots past zero but never past the clamp.
    public var tilt: Vec2 { spring.value }
    /// The tilt the view renders: hard-clamped to ±maxAngle.
    public var displayTilt: Vec2 {
        let m = HoloTilt.maxAngle
        return Vec2(max(-m, min(m, tilt.x)), max(-m, min(m, tilt.y)))
    }
    public var normalizedTilt: Vec2 { HoloTilt.normalized(tilt) }
    public var bandPosition: Double { HoloShading.bandPosition(tilt: normalizedTilt) }
    public var isSettled: Bool { spring.isSettled(at: target, tolerance: 0.01) }
    /// Nothing left to animate: not dragging and at rest.
    public var isIdle: Bool { !isDragging && isSettled }

    private var springParams: (Double, Double) {
        if isDragging { return (config.dragStiffness, config.dragDamping) }
        return config.reduceMotion ? (300, 1) : (config.releaseStiffness, config.releaseDamping)
    }

    public mutating func dragChanged(translation: Vec2) {
        isDragging = true
        target = HoloTilt.tilt(forDrag: translation)
    }

    public mutating func dragEnded() {
        isDragging = false
        target = .zero
    }

    /// VoiceOver adjustable / keyboard: hold the card at a yaw (degrees), clamped.
    public mutating func setHeldYaw(_ yaw: Double) {
        isDragging = false
        target = Vec2(HoloTilt.softClamp(yaw), 0)
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [HoloEvent] {
        guard dt > 0, dt.isFinite else { return [] }
        let (k, z) = springParams
        spring.x.stiffness = k; spring.y.stiffness = k
        spring.x.dampingRatio = z; spring.y.dampingRatio = z
        spring.step(toward: target, dt: dt)
        if isSettled { spring.snap(to: target) }
        guard let dir = detector.update(band: bandPosition, dt: dt) else { return [] }
        crossings += 1
        return [.bandCrossedCenter(dir)]
    }
}
