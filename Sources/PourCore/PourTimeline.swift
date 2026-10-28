import Foundation

/// One drop at a moment in the pour.
public struct PourDrop: Equatable, Sendable {
    public var index: Int
    /// Linear 0…1 progress of this drop's own leg (0 before it starts).
    public var raw: Double
    /// The eased position progress (overshoots 1 a little).
    public var travel: Double
    public var blob: PourBlob
    /// 0…1: the option label fades in as the drop lands.
    public var labelOpacity: Double
    public var isVisible: Bool { raw > 0 }
}

/// The open/close timeline. One master clock `u` runs 0…total; drop `i` starts at `i · stagger` and
/// takes `dropDuration`. Opening runs `u` up and closing runs it back down, so the farthest drop
/// leaves first on the way up and everything reverses cleanly if you change your mind mid-pour.
public enum PourTimeline {
    public static let dropDuration = 0.5
    public static let stagger = 0.09
    /// Overshoot of the drip's ease-out-back.
    public static let overshoot = 1.2
    /// A drop starts at this fraction of its size (it stretches out of the pill) …
    public static let minScale = 0.55
    /// … and its label shows between these progress values.
    public static let labelFrom = 0.6
    public static let labelTo = 1.0

    public static func total(optionCount n: Int) -> Double { dropDuration + stagger * Double(max(n - 1, 0)) }

    public static func easeOutBack(_ x: Double) -> Double {
        let t = WhimsyMath.clamp01(x) - 1
        return 1 + (overshoot + 1) * t * t * t + overshoot * t * t
    }

    public static func rawProgress(drop i: Int, master u: Double) -> Double {
        WhimsyMath.clamp01((u - Double(i) * stagger) / dropDuration)
    }

    public static func drop(_ i: Int, master u: Double) -> PourDrop {
        let raw = rawProgress(drop: i, master: u)
        let e = easeOutBack(raw)
        let pill = PourLayout.pillCenter, rest = PourLayout.restCenter(i)
        let scale = minScale + (1 - minScale) * WhimsyMath.easeOutCubic(raw)
        let blob = PourBlob(center: Vec2(rest.x, pill.y + (rest.y - pill.y) * e),
                            halfWidth: PourLayout.dropHalfWidth * scale, radius: PourLayout.dropRadius * scale)
        return PourDrop(index: i, raw: raw, travel: e, blob: blob,
                        labelOpacity: WhimsyMath.smoothstep(labelFrom, labelTo, raw))
    }

    public static func drops(optionCount n: Int, master u: Double) -> [PourDrop] {
        (0..<max(n, 0)).map { drop($0, master: u) }
    }

    /// The necks between the pill and the visible drops, chained top to bottom: a trailing drop that
    /// hasn't yet passed the one ahead sits between it and the pill, so it bridges to both neighbours.
    public static func necks(_ drops: [PourDrop]) -> [PourNeck] {
        let blobs = ([PourLayout.pillBlob] + drops.filter(\.isVisible).map(\.blob))
            .enumerated().sorted { ($0.element.center.y, $0.offset) < ($1.element.center.y, $1.offset) }.map(\.element)
        return zip(blobs, blobs.dropFirst()).compactMap { PourLayout.neck(upper: $0, lower: $1) }
    }

    /// The lift of the pill while pouring: sin(progress · π), 0 at both ends.
    public static func lift(master u: Double, optionCount n: Int) -> Double {
        sin(WhimsyMath.clamp01(u / total(optionCount: n)) * Double.pi)
    }
}

/// How the lifted pill looks at a lift value.
public enum PourLift {
    public static let scaleGain = 0.04
    public static let shadowRadius = 16.0
    public static let shadowOffset = 8.0
    public static let shadowOpacity = 0.28
    public static let restShadowOpacity = 0.10
    public static let restShadowRadius = 3.0

    public static func scale(_ lift: Double) -> Double { 1 + scaleGain * lift }
    public static func radius(_ lift: Double) -> Double { restShadowRadius + (shadowRadius - restShadowRadius) * lift }
    public static func offsetY(_ lift: Double) -> Double { 1 + (shadowOffset - 1) * lift }
    public static func opacity(_ lift: Double) -> Double { restShadowOpacity + (shadowOpacity - restShadowOpacity) * lift }
}

/// The pill label's crossfade between the old and new option.
public enum PourLabelFade {
    public static let duration = 0.28
    public static let reducedDuration = 0.15

    /// Eased progress 0…1 after `elapsed` seconds.
    public static func progress(elapsed: Double, duration: Double = duration) -> Double {
        WhimsyMath.easeInOutCubic(duration > 0 ? elapsed / duration : 1)
    }
}
