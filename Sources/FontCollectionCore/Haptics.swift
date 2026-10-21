import Foundation

/// Haptic moments the UI should play. The core only decides *when*; the view maps each
/// event to `sensoryFeedback` (iOS).
public enum FontHapticEvent: Equatable, Sendable {
    /// One flap of the flip board. Intensity grows as the board slows down (0…1).
    case flipTick(intensity: Double)
    /// The flip board landed on its final font.
    case settle
    /// A card arrived in its new slot after a filter change.
    case landing
    /// A filter chip was selected.
    case chip
    /// The detail view's weight slider crossed onto another weight.
    case weightStep

    /// Suggested intensity, 0…1.
    public var intensity: Double {
        switch self {
        case .flipTick(let i): min(max(i, 0), 1)
        case .settle: 1
        case .landing: 0.5
        case .chip: 0.6
        case .weightStep: 0.45
        }
    }
}

/// Rate limiter: a flurry of events closer together than `minInterval` collapses into one,
/// so taps stay crisp instead of buzzing. `.settle` always passes.
public struct HapticGate: Equatable, Sendable {
    public var minInterval: Double
    public private(set) var lastFire: Double = -.infinity

    public init(minInterval: Double = 0.04) { self.minInterval = max(minInterval, 0) }

    /// Returns true if an event at `time` should play (and records it).
    public mutating func admit(_ event: FontHapticEvent, at time: Double) -> Bool {
        guard time.isFinite else { return false }
        if event != .settle && time - lastFire < minInterval { return false }
        lastFire = time
        return true
    }

    public mutating func reset() { lastFire = -.infinity }
}
