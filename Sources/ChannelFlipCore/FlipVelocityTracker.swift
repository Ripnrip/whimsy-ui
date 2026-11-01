import Foundation

/// Estimates the horizontal speed of a drag from its last few samples, so a finger that has stopped before it lifts counts as slow.
public struct FlipVelocityTracker: Equatable, Sendable {
    /// Only samples this recent (seconds before the last one) are used.
    public static let window = 0.12
    /// Samples closer in time than this give no usable speed.
    public static let minSpan = 0.004

    private var samples: [(t: Double, x: Double)] = []

    public init() {}

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }

    /// Record the finger at horizontal position `x` (points) at time `t` (seconds).
    public mutating func add(x: Double, at t: Double) {
        guard x.isFinite, t.isFinite else { return }
        samples.append((t, x))
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
    }

    /// Signed horizontal velocity (points per second) when the finger lifts at time `end`.
    /// Zero if the last sample is older than the window, or there are too few samples.
    public func velocity(endingAt end: Double) -> Double {
        guard let last = samples.last, end - last.t <= Self.window else { return 0 }
        let recent = samples.filter { last.t - $0.t <= Self.window }
        guard let first = recent.first, last.t - first.t >= Self.minSpan else { return 0 }
        return (last.x - first.x) / (last.t - first.t)
    }

    public static func == (a: FlipVelocityTracker, b: FlipVelocityTracker) -> Bool {
        a.samples.count == b.samples.count && zip(a.samples, b.samples).allSatisfy { $0.t == $1.t && $0.x == $1.x }
    }
}
