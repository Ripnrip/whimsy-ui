import Foundation

/// How a keyframe is approached from the one before it.
public enum KeyframeEasing: Equatable, Sendable {
    case linear, easeIn, easeOut, easeInOut
    /// Stays at the previous value, then jumps.
    case hold

    public func apply(_ t: Double) -> Double {
        let t = WhimsyMath.clamp01(t)
        switch self {
        case .linear: return t
        case .easeIn: return t * t * t
        case .easeOut: return WhimsyMath.easeOutCubic(t)
        case .easeInOut: return WhimsyMath.easeInOutCubic(t)
        case .hold: return t >= 1 ? 1 : 0
        }
    }
}

public struct Keyframe: Equatable, Sendable {
    /// Position along the track (scroll progress 0…1 here).
    public var at: Double
    public var value: Double
    public var easing: KeyframeEasing
    public init(_ at: Double, _ value: Double, _ easing: KeyframeEasing = .easeInOut) {
        self.at = at; self.value = value; self.easing = easing
    }
}

/// A scalar track: clamped before the first and after the last keyframe, eased between.
public struct KeyframeTrack: Equatable, Sendable {
    public let keyframes: [Keyframe]

    public init(_ keyframes: [Keyframe]) {
        // Stable sort, so equal positions keep their order (a step).
        self.keyframes = keyframes.filter { $0.at.isFinite && $0.value.isFinite }
            .enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }

    public func value(at p: Double) -> Double {
        guard let first = keyframes.first, let last = keyframes.last else { return 0 }
        guard p.isFinite else { return first.value }
        if p <= first.at { return first.value }
        if p >= last.at { return last.value }
        // Last segment whose start is ≤ p.
        var i = 0
        while i + 1 < keyframes.count, keyframes[i + 1].at <= p { i += 1 }
        let a = keyframes[i], b = keyframes[min(i + 1, keyframes.count - 1)]
        let span = b.at - a.at
        guard span > 0 else { return b.value }
        return a.value + (b.value - a.value) * b.easing.apply((p - a.at) / span)
    }
}
