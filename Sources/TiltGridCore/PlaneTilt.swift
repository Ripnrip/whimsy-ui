import Foundation

/// The grid as one 3D plane that tilts and pans away from the finger on springs.
public struct PlaneTilt: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Degrees at the edge of the screen.
        public var maxPitch = 14.0
        public var maxYaw = 16.0
        /// Points of pan at the edge, opposite to the finger.
        public var maxPan = Vec2(30, 46)
        /// Extra parallax (pt) for a card at depth 1, on top of the plane's pan.
        public var parallax = 18.0
        public var stiffness = 70.0
        public var damping = 0.62
        public init() {}
    }

    public let tuning: Tuning
    /// x = yaw (positive: right edge recedes), y = pitch (positive: top edge recedes), degrees.
    public private(set) var tilt: WhimsySpring2D
    public private(set) var pan: WhimsySpring2D
    /// Normalised input, −1…1 on each axis (0 = centred); nil when nobody is touching.
    public private(set) var input: Vec2?
    public var reduceMotion = false

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
        tilt = WhimsySpring2D(stiffness: tuning.stiffness, dampingRatio: tuning.damping)
        pan = WhimsySpring2D(stiffness: tuning.stiffness, dampingRatio: tuning.damping)
    }

    /// Normalises a point in a container: −1 at the left/top edge, +1 at the right/bottom.
    public static func normalized(_ p: Vec2, in size: Vec2) -> Vec2 {
        guard size.x > 0, size.y > 0, p.x.isFinite, p.y.isFinite else { return .zero }
        return Vec2(WhimsyMath.clamp((p.x / size.x) * 2 - 1, -1, 1), WhimsyMath.clamp((p.y / size.y) * 2 - 1, -1, 1))
    }

    public mutating func setInput(_ n: Vec2?) {
        if let n, !(n.x.isFinite && n.y.isFinite) { return }
        input = n.map { Vec2(WhimsyMath.clamp($0.x, -1, 1), WhimsyMath.clamp($0.y, -1, 1)) }
    }

    /// Tilt targets: the part of the plane under the finger presses away from you.
    public var tiltTarget: Vec2 {
        guard let n = input else { return .zero }
        let k = reduceMotion ? 0.35 : 1
        return Vec2(n.x * tuning.maxYaw * k, -n.y * tuning.maxPitch * k)
    }

    /// Pan target: opposite to the finger.
    public var panTarget: Vec2 {
        guard let n = input else { return .zero }
        let k = reduceMotion ? 0.35 : 1
        return Vec2(-n.x * tuning.maxPan.x * k, -n.y * tuning.maxPan.y * k)
    }

    /// The card's extra offset for its depth: it drifts further with the pan, like it floats nearer.
    public func parallax(depth: Double) -> Vec2 {
        let d = WhimsyMath.clamp01(depth.isFinite ? depth : 0)
        let p = pan.value
        let mx = tuning.maxPan.x, my = tuning.maxPan.y
        return Vec2(mx > 0 ? p.x / mx * tuning.parallax * d : 0, my > 0 ? p.y / my * tuning.parallax * d : 0)
    }

    public var isSettled: Bool { tilt.isSettled(at: tiltTarget, tolerance: 0.01) && pan.isSettled(at: panTarget, tolerance: 0.01) }

    public mutating func step(_ dt: Double) {
        if reduceMotion {
            tilt.x.dampingRatio = 1; tilt.y.dampingRatio = 1; pan.x.dampingRatio = 1; pan.y.dampingRatio = 1
        } else {
            tilt.x.dampingRatio = tuning.damping; tilt.y.dampingRatio = tuning.damping
            pan.x.dampingRatio = tuning.damping; pan.y.dampingRatio = tuning.damping
        }
        tilt.step(toward: tiltTarget, dt: dt)
        pan.step(toward: panTarget, dt: dt)
    }
}

/// Maps device attitude to the same −1…1 input as a finger.
public enum MotionTilt {
    /// `pitch` and `roll` in radians; the phone is "neutral" held at `neutralPitch` (about 35°).
    public static func normalized(pitch: Double, roll: Double, neutralPitch: Double = 0.6, range: Double = 0.35) -> Vec2 {
        guard pitch.isFinite, roll.isFinite, range > 0 else { return .zero }
        // Tipping the top away (pitch above neutral) acts like a finger near the bottom.
        return Vec2(WhimsyMath.clamp(roll / range, -1, 1), WhimsyMath.clamp((pitch - neutralPitch) / range, -1, 1))
    }
}
