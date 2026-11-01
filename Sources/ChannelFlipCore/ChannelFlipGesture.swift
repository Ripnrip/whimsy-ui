import Foundation

/// Swipe speed to transition length and strength, and tap-or-swipe classification.
public enum FlipVelocity {
    /// Horizontal speed (points per second) at or below which a swipe is the mild, short kind…
    public static let slowSpeed = 250.0
    /// …and at or above which it is the full-strength flick.
    public static let fastSpeed = 2200.0
    public static let minDuration = 0.35
    public static let maxDuration = 0.7
    public static let minStrength = 0.45
    public static let maxStrength = 1.0

    /// 0 at `slowSpeed`, 1 at `fastSpeed`, linear between. Not-a-number and infinity are handled.
    public static func amount(forSpeed speed: Double) -> Double {
        if speed.isNaN { return 0 }
        return WhimsyMath.clamp01((abs(speed) - slowSpeed) / (fastSpeed - slowSpeed))
    }

    /// Duration and strength for a swipe at `speed` (points per second, sign ignored).
    public static func spec(forSpeed speed: Double) -> FlipSpec {
        let u = amount(forSpeed: speed)
        return FlipSpec(duration: WhimsyMath.lerp(minDuration, maxDuration, u),
                        strength: WhimsyMath.lerp(minStrength, maxStrength, u))
    }
}

public enum FlipDirection: Equatable, Sendable { case next, previous }

/// What a finished touch means.
public enum FlipGesture: Equatable, Sendable {
    case tap
    case swipe(FlipDirection, speed: Double)
    case none
}

public enum FlipGestureClassifier {
    /// Moving no further than this (points, either axis) is a tap.
    public static let tapSlop = 12.0
    /// A swipe needs at least this much horizontal travel, and more horizontal than vertical.
    public static let minSwipeDistance = 24.0

    /// Swiping left goes to the next channel and swiping right to the previous one.
    public static func classify(translation: Vec2, velocity: Vec2) -> FlipGesture {
        let ax = abs(translation.x), ay = abs(translation.y)
        if max(ax, ay) < tapSlop { return .tap }
        guard ax >= minSwipeDistance, ax >= ay else { return .none }
        return .swipe(translation.x < 0 ? .next : .previous, speed: abs(velocity.x))
    }
}

/// Channel index arithmetic.
public enum ChannelIndex {
    /// `index` wrapped into 0..<count (negative indices wrap too). 0 when there are no channels.
    public static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let r = index % count
        return r < 0 ? r + count : r
    }
    public static func next(_ index: Int, count: Int) -> Int { wrap(index + 1, count: count) }
    public static func previous(_ index: Int, count: Int) -> Int { wrap(index - 1, count: count) }
    /// The on-screen number: 1-based and two digits, like "CH 03".
    public static func label(_ index: Int, count: Int) -> String {
        let n = wrap(index, count: count) + 1
        return "CH " + (n < 10 ? "0" : "") + String(n)
    }
}
