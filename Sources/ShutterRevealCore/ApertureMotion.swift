import Foundation
import WhimsyCore

/// SwiftUI-style spring (response / damping fraction), integrated with semi-implicit Euler.
public struct ShutterSpring: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double
    public init(response: Double, dampingFraction: Double) {
        self.response = max(response, 0.01)
        self.dampingFraction = max(dampingFraction, 0)
    }
    public var stiffness: Double { pow(2 * .pi / response, 2) }
    public var damping: Double { 4 * .pi * dampingFraction / response }

    public func step(position: inout Double, velocity: inout Double, target: Double, dt: Double) {
        velocity += (stiffness * (target - position) - damping * velocity) * dt
        position += velocity * dt
    }
}

/// Aperture progress (0 = closed, 1 = open) driven by springs: a bouncy spring with
/// overshoot for opening, a quick, nearly critically damped one for the closing snap.
public struct ApertureMotion: Equatable, Sendable {
    public static let maxSubstep: Double = 1.0 / 240.0
    public static let maxFrameDelta: Double = 0.1
    /// Progress at or below which the shutter counts as shut (fires `closeEvents`).
    public static let closedThreshold: Double = 0.01

    public private(set) var openSpring: ShutterSpring
    public private(set) var closeSpring: ShutterSpring
    private let closeResponseFactor: Double
    public private(set) var progress: Double
    public private(set) var velocity: Double = 0
    public private(set) var target: Double
    /// Incremented each time a close reaches the shut position (a haptic trigger).
    public private(set) var closeEvents = 0
    private var closeArmed = false

    /// - Parameters:
    ///   - response: opening spring response in seconds (SwiftUI semantics).
    ///   - openDamping: below 1 overshoots (≈11% at 0.58).
    ///   - closeResponseFactor: closing response = `response * factor` (snappier).
    public init(isOpen: Bool = false, response: Double = 0.45, openDamping: Double = 0.58,
                closeResponseFactor: Double = 0.55, closeDamping: Double = 0.9) {
        openSpring = ShutterSpring(response: response, dampingFraction: openDamping)
        closeSpring = ShutterSpring(response: response * closeResponseFactor, dampingFraction: closeDamping)
        self.closeResponseFactor = closeResponseFactor
        progress = isOpen ? 1 : 0
        target = progress
    }

    public var isOpening: Bool { target == 1 }
    public var isSettled: Bool { abs(progress - target) < 1e-4 && abs(velocity) < 1e-3 }

    /// Starts opening or closing. `animated == false` jumps straight to the end state.
    public mutating func setOpen(_ open: Bool, animated: Bool = true) {
        let newTarget: Double = open ? 1 : 0
        if !animated {
            progress = newTarget; velocity = 0; target = newTarget; closeArmed = false
            return
        }
        guard newTarget != target else { return }
        target = newTarget
        closeArmed = !open && progress > Self.closedThreshold
    }

    /// Changes the spring response without disturbing the current position, velocity or close count.
    public mutating func setResponse(_ response: Double) {
        openSpring.response = max(response, 0.01)
        closeSpring.response = max(response * closeResponseFactor, 0.01)
    }

    public mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, Self.maxFrameDelta)
        let spring = isOpening ? openSpring : closeSpring
        while remaining > 0 {
            let h = min(remaining, Self.maxSubstep)
            spring.step(position: &progress, velocity: &velocity, target: target, dt: h)
            remaining -= h
            if closeArmed && progress <= Self.closedThreshold {
                closeArmed = false
                closeEvents += 1
            }
        }
        if isSettled { progress = target; velocity = 0 }
    }

    /// Angular velocity of the blades (rad/s) for an iris with `twist` radians of rotation.
    public func angularVelocity(twist: Double) -> Double { velocity * twist }

    /// Progress clamped for drawing. Overshoot above 1 is kept (the blades open a little
    /// wider); below 0 is clamped (blades can't pass the centre).
    public var drawableProgress: Double { max(progress, 0) }
}

/// A faint copy of the blades at an earlier instant, used as motion blur.
public struct MotionGhost: Equatable, Sendable {
    public var progress: Double
    public var rotation: Double
    public var opacity: Double
}

public enum MotionBlur {
    /// Ghost copies trailing the motion, derived from the angular velocity. The defaults spread
    /// four ghosts over about one 60 fps frame (4 × 1/240 s), so they read as blur rather than as
    /// separate copies.
    ///
    /// Ghost `i` is where the blades were `i * exposure` seconds ago: the rotation is offset by
    /// `-ω·i·exposure` and the progress by `-v·i·exposure`. Opacity fades with `i` and scales with
    /// `|ω| / fullBlurAngularVelocity` (capped at 1). Below `minimumAngularVelocity` there are none.
    public static func ghosts(
        progress: Double,
        velocity: Double,
        geometry: IrisGeometry,
        count: Int = 4,
        exposure: Double = 1.0 / 240.0,
        maxOpacity: Double = 0.18,
        fullBlurAngularVelocity: Double = 3.0,
        minimumAngularVelocity: Double = 0.05
    ) -> [MotionGhost] {
        let omega = velocity * geometry.twist
        guard count > 0, omega.isFinite, abs(omega) >= minimumAngularVelocity else { return [] }
        let strength = min(abs(omega) / fullBlurAngularVelocity, 1)
        let baseRotation = geometry.rotation(progress: progress)
        return (1...count).map { i in
            let lag = Double(i) * exposure
            return MotionGhost(
                progress: max(progress - velocity * lag, 0),
                rotation: baseRotation - omega * lag,
                opacity: maxOpacity * strength * (1 - Double(i) / Double(count + 1))
            )
        }
    }
}
