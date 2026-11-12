import Foundation

public enum RubberBandRelease: Equatable, Sendable {
    case springBack
    /// Let go past the commit rise.
    case commitDrag
    /// Flicked upward fast enough.
    case commitFlick
    public var commits: Bool { self == .commitDrag || self == .commitFlick }
}

/// Rubber-band resistance. Visible offset for a raw finger offset of `x` points:
///
///     x * 0.55 / (1 + abs(x) / 300)
///
/// The slope starts at 0.55 and falls toward 0. The curve is odd, and it never quite
/// reaches the asymptote `0.55 * 300` (165 points).
public enum RubberBandResistance {
    public static let scale = 0.55
    public static let length = 300.0
    /// The curve approaches this magnitude and never reaches it.
    public static var asymptote: Double { scale * length }

    public static func resist(_ offset: Double) -> Double {
        guard offset.isFinite else { return 0 }
        return offset * scale / (1 + abs(offset) / length)
    }

    /// d(resist)/d(offset). Starts at `scale` and is always positive.
    public static func slope(at offset: Double) -> Double {
        guard offset.isFinite else { return 0 }
        let d = 1 + abs(offset) / length
        return scale / (d * d)
    }

    /// Commit on resisted rise, or on a fast upward flick after a small pull.
    /// `pullUp` is raw points upward; `upwardVelocity` is raw points per second upward.
    public static func decide(pullUp: Double, upwardVelocity: Double) -> RubberBandRelease {
        let up = pullUp.isFinite ? pullUp : 0
        if resist(up) >= RubberBandLayout.commitRise { return .commitDrag }
        if upwardVelocity.isFinite, upwardVelocity >= RubberBandLayout.flickSpeed, up >= RubberBandLayout.flickMin {
            return .commitFlick
        }
        return .springBack
    }

    /// Same shape, for putting a centred card away: `pullDown` is raw points downward.
    public static func decideDismiss(pullDown: Double, downwardVelocity: Double) -> RubberBandRelease {
        let down = pullDown.isFinite ? pullDown : 0
        if resist(down) >= RubberBandLayout.dismissRise { return .commitDrag }
        if downwardVelocity.isFinite, downwardVelocity >= RubberBandLayout.dismissFlick, down >= RubberBandLayout.flickMin {
            return .commitFlick
        }
        return .springBack
    }
}

/// Finger velocity over the last tenth of a second. A finger that stopped counts as still.
public struct RubberBandVelocity: Equatable, Sendable {
    public static let window = 0.1
    public static let stale = 0.06

    private var samples: [(t: Double, x: Double, y: Double)] = []

    public init() {}

    public static func == (a: RubberBandVelocity, b: RubberBandVelocity) -> Bool {
        a.samples.count == b.samples.count && zip(a.samples, b.samples).allSatisfy {
            $0.t == $1.t && $0.x == $1.x && $0.y == $1.y
        }
    }

    public var isEmpty: Bool { samples.isEmpty }

    public mutating func reset() { samples.removeAll() }

    /// Screen point, y down.
    public mutating func add(_ point: Vec2, at t: Double) {
        guard point.x.isFinite, point.y.isFinite, t.isFinite else { return }
        if let last = samples.last, t < last.t { return }
        samples.append((t, point.x, point.y))
        samples.removeAll { t - $0.t > Self.window * 3 }
    }

    /// Points per second. Upward is negative screen-y. Rightward is positive x.
    public func velocity(at now: Double) -> Vec2 {
        guard let last = samples.last, now.isFinite, now - last.t <= Self.stale else { return .zero }
        let recent = samples.filter { last.t - $0.t <= Self.window }
        guard let first = recent.first, last.t - first.t > 0.001 else { return .zero }
        let dt = last.t - first.t
        return Vec2((last.x - first.x) / dt, (first.y - last.y) / dt)
    }
}
