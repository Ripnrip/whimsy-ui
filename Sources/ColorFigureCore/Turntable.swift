import Foundation

/// The figure's yaw: dragged by hand, thrown with inertia, and gently settled onto the nearest quarter turn.
public struct Turntable: Equatable, Sendable {
    /// The resting view: front face toward the lower right.
    public static let homeYaw = -32.0
    public static let degreesPerPoint = 0.6
    public static let friction = 2.6          // velocity decay per second
    public static let snapRange = 12.0        // degrees from a rest yaw within which it settles
    public static let snapSpeed = 30.0        // deg/s below which it may settle
    public static let snapRate = 9.0
    public static let maxSpeed = 720.0

    public var yaw: Double = Turntable.homeYaw
    public private(set) var velocity: Double = 0
    public private(set) var isDragging = false
    public var reduceMotion = false
    public private(set) var turns = 0.0   // total degrees rotated since start, for tests

    public init(yaw: Double = Turntable.homeYaw) { self.yaw = yaw }

    public mutating func beginDrag() { isDragging = true; velocity = 0 }

    /// Moves by `points` of horizontal finger travel over `dt` seconds.
    public mutating func drag(by points: Double, dt: Double) {
        let d = points * Self.degreesPerPoint
        yaw += d
        turns += abs(d)
        if dt > 0 {
            let v = max(-Self.maxSpeed, min(Self.maxSpeed, d / dt))
            velocity = velocity * 0.6 + v * 0.4
        }
    }

    public mutating func endDrag() {
        isDragging = false
        if reduceMotion { velocity = 0 }
    }

    /// Throws it with a speed in degrees per second.
    public mutating func fling(_ v: Double) { velocity = reduceMotion ? 0 : max(-Self.maxSpeed, min(Self.maxSpeed, v)) }

    /// The nearest resting yaw (home plus a multiple of 90 degrees) to `yaw`.
    public static func nearestRest(to yaw: Double) -> Double {
        homeYaw + ((yaw - homeYaw) / 90).rounded() * 90
    }

    public mutating func advance(by dt: Double) {
        guard !isDragging, dt > 0 else { return }
        if abs(velocity) > 0.01 {
            let d = velocity * dt
            yaw += d
            turns += abs(d)
            velocity *= exp(-Self.friction * dt)
        }
        if abs(velocity) < Self.snapSpeed && !reduceMotion {
            let target = Self.nearestRest(to: yaw)
            if abs(target - yaw) <= Self.snapRange {
                yaw += (target - yaw) * (1 - exp(-Self.snapRate * dt))
                velocity *= exp(-Self.snapRate * dt)
                if abs(target - yaw) < 0.01 { yaw = target; velocity = 0 }
            }
        }
        if abs(velocity) < 0.01 { velocity = 0 }
    }

    /// True when nothing is moving and nothing is about to: not held, no speed, and not part-way into a settle.
    public var isSettled: Bool {
        let d = abs(Self.nearestRest(to: yaw) - yaw)
        return !isDragging && velocity == 0 && (d == 0 || d > Self.snapRange || reduceMotion)
    }

    /// Yaw wrapped into 0..<360, for display.
    public var normalizedYaw: Double {
        let m = yaw.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }
}
