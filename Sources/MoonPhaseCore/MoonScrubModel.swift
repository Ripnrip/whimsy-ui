import Foundation

/// Scrubbing state for the moon: a horizontal drag moves the (unwrapped) phase directly, release
/// projects the flick a little forward and springs to the nearest named phase.
public struct MoonScrubModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Points of horizontal drag per full lunation (45 pt per named phase).
        public var pointsPerCycle = 360.0
        /// How far ahead (seconds) a flick's velocity is projected before snapping.
        public var projection = 0.12
        /// The snap may land at most this many steps away from where the finger let go.
        public var maxFlickSteps = 2.0
        public var snapStiffness = 160.0
        public var snapDamping = 0.62
        public init() {}
    }

    public let tuning: Tuning
    public private(set) var spring: WhimsySpring
    /// Unwrapped snap target.
    public private(set) var target: Double
    public private(set) var isDragging = false
    /// Bumps each time the moon commits to a named phase (the soft haptic's trigger).
    public private(set) var snapCount = 0
    private var dragStart = 0.0
    private var lastTranslation = 0.0
    public var reduceMotion = false {
        didSet { spring.dampingRatio = reduceMotion ? 1 : tuning.snapDamping; spring.stiffness = reduceMotion ? 260 : tuning.snapStiffness }
    }

    public init(phase: Double = MoonPhaseName.waxingCrescent.fraction, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        let p = phase.isFinite ? phase : 0
        spring = WhimsySpring(value: p, stiffness: tuning.snapStiffness, dampingRatio: tuning.snapDamping)
        target = p
    }

    /// The wrapped phase on screen, 0..1.
    public var phase: Double { MoonMath.wrap(spring.value) }
    /// The unwrapped phase (for a continuous Animatable shape).
    public var unwrappedPhase: Double { spring.value }
    /// The named phase the readout shows: nearest to what is on screen.
    public var name: MoonPhaseName { MoonPhaseName.nearest(to: spring.value) }
    public var isSettled: Bool { !isDragging && spring.isSettled(at: target, tolerance: 1e-4) }

    public mutating func beginDrag() {
        isDragging = true
        dragStart = spring.value
        lastTranslation = 0
        spring.velocity = 0
    }

    /// Follows the finger 1:1 (dragging right waxes the moon).
    public mutating func drag(translation dx: Double) {
        guard dx.isFinite else { return }
        if !isDragging { beginDrag() }
        lastTranslation = dx
        let p = dragStart + dx / tuning.pointsPerCycle
        spring.snap(to: p)
        target = p
    }

    /// Releases with the finger's horizontal velocity (pt/s) and returns the snap target.
    @discardableResult
    public mutating func endDrag(velocity vx: Double) -> Double {
        let v = vx.isFinite ? vx : 0
        isDragging = false
        let release = spring.value
        let projected = release + v * tuning.projection / tuning.pointsPerCycle
        let limit = tuning.maxFlickSteps / 8
        let clamped = min(max(projected, release - limit), release + limit)
        target = MoonPhaseName.snapTarget(near: clamped)
        spring.velocity = reduceMotion ? 0 : v / tuning.pointsPerCycle
        snapCount += 1
        return target
    }

    /// Jumps to a named phase (tap or accessibility adjust), taking the short way round.
    public mutating func select(_ name: MoonPhaseName) {
        isDragging = false
        target = MoonPhaseName.unwrapped(name, near: spring.value)
        snapCount += 1
    }

    /// Steps to the next (+1) or previous (−1) named phase from the current target.
    public mutating func advance(_ steps: Int) {
        isDragging = false
        target = MoonPhaseName.snapTarget(near: target) + Double(steps) / 8
        snapCount += 1
    }

    public mutating func step(_ dt: Double) {
        guard !isDragging else { return }
        spring.step(toward: target, dt: dt)
        // Keep the unwrapped value small; whole laps are invisible because the shape wraps.
        if abs(spring.value) > 8 {
            let k = spring.value.rounded(.down)
            spring.value -= k; target -= k
        }
    }
}
