import Foundation

public enum ShelfRelease: Equatable, Sendable {
    /// The book never really left its slot.
    case none
    case springBack
    /// Pulled past the commit distance.
    case commitDrag
    /// Flicked up fast enough.
    case commitFlick
    public var commits: Bool { self == .commitDrag || self == .commitFlick }
}

/// Rubber-band resistance and the commit decision. `drag` is how far the finger has pulled up, in points.
public enum ShelfResistance {
    /// The book can never rise more than this fraction of its height under the finger.
    public static let maxRiseFraction = 0.7
    /// Pull this far (as a fraction of the spine's height) and let go: the book comes out.
    public static let commitFraction = 0.55
    /// ... or flick up at least this fast (points per second) after pulling at least `flickMinDrag`.
    public static let flickSpeed = 900.0
    public static let flickMinDrag = 12.0
    /// Below this visible rise (points) a release is a tap, not a pull.
    public static let tapRise = 0.5

    public static func maxRise(height: Double) -> Double { maxRiseFraction * height }
    public static func commitDistance(height: Double) -> Double { commitFraction * height }

    /// Visible rise for a pull of `drag`: `drag · R / (drag + R)`. Starts 1:1, then gives less and less,
    /// and never reaches R. Pushing down (or not-a-number) is no rise.
    public static func rise(forDrag drag: Double, height: Double) -> Double {
        guard drag.isFinite, drag > 0 else { return 0 }
        let r = maxRise(height: height)
        return drag * r / (drag + r)
    }

    /// The pull that shows `rise`; the inverse of `rise(forDrag:)`. Rises at or beyond R are clamped just under R.
    public static func drag(forRise rise: Double, height: Double) -> Double {
        guard rise.isFinite, rise > 0 else { return 0 }
        let r = maxRise(height: height)
        let x = min(rise, r * 0.999)
        return x * r / (r - x)
    }

    /// d(rise)/d(drag): 1 at the start, falling toward 0.
    public static func slope(atDrag drag: Double, height: Double) -> Double {
        let r = maxRise(height: height), d = drag.isFinite ? max(drag, 0) : 0
        return r * r / ((d + r) * (d + r))
    }

    public static func decide(drag: Double, velocity: Double, height: Double) -> ShelfRelease {
        let rise = rise(forDrag: drag, height: height)
        if rise < tapRise { return .none }
        if drag >= commitDistance(height: height) { return .commitDrag }
        if velocity.isFinite, velocity >= flickSpeed, drag >= flickMinDrag { return .commitFlick }
        return .springBack
    }
}

/// Upward speed of the last 0.1 s of the pull; a finger that stopped before lifting counts as slow.
public struct ShelfVelocityTracker: Equatable, Sendable {
    public static let window = 0.1
    public static let stale = 0.06
    private var samples: [(t: Double, y: Double)] = []

    public init() {}

    public static func == (a: ShelfVelocityTracker, b: ShelfVelocityTracker) -> Bool {
        a.samples.count == b.samples.count && zip(a.samples, b.samples).allSatisfy { $0.t == $1.t && $0.y == $1.y }
    }

    public var isEmpty: Bool { samples.isEmpty }

    public mutating func reset() { samples.removeAll() }

    public mutating func add(upward y: Double, at t: Double) {
        guard y.isFinite, t.isFinite else { return }
        if let last = samples.last, t < last.t { return }
        samples.append((t, y))
        samples.removeAll { t - $0.t > Self.window * 3 }
    }

    /// Points per second, upward positive.
    public func velocity(at now: Double) -> Double {
        guard let last = samples.last, now.isFinite, now - last.t <= Self.stale else { return 0 }
        let recent = samples.filter { last.t - $0.t <= Self.window }
        guard let first = recent.first, last.t - first.t > 0.001 else { return 0 }
        return (last.y - first.y) / (last.t - first.t)
    }
}
