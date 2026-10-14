import Foundation
import WhimsyCore

/// Where the eyes look, in normalised gaze space: the unit disc, where (1, 0) means "as far
/// right as the pupil can travel". +y is down, matching screen coordinates.
public struct GazeController: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Following a finger: fast and nearly critical (the article's 420 / 0.8).
        public var trackingStiffness = 420.0
        public var trackingDamping = 0.8
        /// After release: a slow, soft drift back to centre.
        public var driftStiffness = 38.0
        public var driftDamping = 0.95
        public init() {}
    }

    public var tuning: Tuning
    public private(set) var spring = Spring2D()
    /// Finger target (already clamped to the unit disc), or nil when no finger is down.
    public private(set) var fingerTarget: Vec2?

    public init(tuning: Tuning = Tuning()) { self.tuning = tuning }

    public var isTracking: Bool { fingerTarget != nil }

    /// Sets (or clears, with nil) the finger target. Targets are clamped to the unit disc.
    public mutating func setTarget(_ target: Vec2?) {
        fingerTarget = target.map { $0.clamped(toRadius: 1) }
    }

    /// Steps toward the finger (or the centre once released), plus the saccade `nudge`.
    public mutating func step(dt: Double, nudge: Vec2 = .zero) {
        let target = ((fingerTarget ?? .zero) + nudge).clamped(toRadius: 1)
        let (k, z) = isTracking
            ? (tuning.trackingStiffness, tuning.trackingDamping)
            : (tuning.driftStiffness, tuning.driftDamping)
        spring.step(toward: target, dt: dt, stiffness: k, damping: z)
    }

    /// The gaze to draw: the spring's position, clamped so overshoot can't leave the disc.
    public var gaze: Vec2 { spring.position.clamped(toRadius: 1) }
}

/// Maps a finger location to a gaze target, and gaze to a pupil offset that keeps the iris inside the eye.
public enum EyeGeometry {
    /// Gaze target for a finger at `finger`, relative to the point between the eyes. `reach`
    /// is the distance at which the eyes are fully turned.
    public static func gazeTarget(finger: Vec2, eyesCenter: Vec2, reach: Double) -> Vec2 {
        guard reach > 0 else { return .zero }
        return ((finger - eyesCenter) * (1 / reach)).clamped(toRadius: 1)
    }

    /// How far the iris centre may move from the eye centre so the iris stays inside the sclera.
    public static func maxTravel(eyeRadius: Double, irisRadius: Double, margin: Double = 0.06) -> Double {
        max(eyeRadius * (1 - margin) - irisRadius, 0)
    }

    /// Iris-centre offset for a gaze (gaze is clamped to the unit disc first).
    public static func irisOffset(gaze: Vec2, eyeRadius: Double, irisRadius: Double) -> Vec2 {
        gaze.clamped(toRadius: 1) * maxTravel(eyeRadius: eyeRadius, irisRadius: irisRadius)
    }
}
