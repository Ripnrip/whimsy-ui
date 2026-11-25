import Foundation

/// The bolt's centreline, the weekly fraction, and the glow. Sampling is arc length
/// along the polyline, which is what a SwiftUI `trim` walks, so the head sits on the
/// bright end of the stroke. The sine polynomial is the one the web port copies.
public enum BoltStreakMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
    static let invTwoPi = 1 / (2 * Double.pi)

    /// sin(x), reduced to [-π/2, π/2], then a Taylor polynomial to x¹⁷.
    /// A library `sin` can differ in the last bit; this one does not.
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = Double.pi - r } else if r < -halfPi { r = -Double.pi - r }
        let r2 = r * r
        var p = 1.0 / 355_687_428_096_000.0
        p = -1.0 / 1_307_674_368_000.0 + r2 * p
        p = 1.0 / 6_227_020_800.0 + r2 * p
        p = -1.0 / 39_916_800.0 + r2 * p
        p = 1.0 / 362_880.0 + r2 * p
        p = -1.0 / 5040.0 + r2 * p
        p = 1.0 / 120.0 + r2 * p
        p = -1.0 / 6.0 + r2 * p
        p = 1.0 + r2 * p
        return r * p
    }

    /// Completed days over seven. Duplicates count once. Not the displayed fill:
    /// that one chases this target while a bolt is still burning.
    public static func weeklyTarget(completed: some Sequence<Weekday>) -> Double {
        let unique = Set(completed)
        return Double(unique.count) / Double(BoltStreakTuning.dayCount)
    }

    /// Glow for a burn at `progress` (0…1). Reduce Motion, and a bolt that is not
    /// the one currently igniting, hold a steady level. The pulse is a sine on
    /// `elapsed` and is zero at the start of an ignition.
    public static func glow(progress: Double, elapsed: Double, igniting: Bool, reduceMotion: Bool) -> Double {
        let p = progress.isFinite ? WhimsyMath.clamp01(progress) : 0
        if p <= 0 { return 0 }
        let base = BoltStreakTuning.glowSettled * p
        if reduceMotion || !igniting || !elapsed.isFinite { return base }
        let wave = sin(elapsed * BoltStreakTuning.glowOmega)
        return WhimsyMath.clamp(base + BoltStreakTuning.glowPulse * wave * p, 0, 1)
    }
}

/// Zigzag centreline of every bolt, in a unit box (y down) and in any scene rect.
public enum BoltPath {
    /// Normalised centreline. x is across the bolt, y runs from the shoulder to the tip.
    public static let normalizedPoints: [Vec2] = [
        Vec2(0.72, 0.06),
        Vec2(0.30, 0.34),
        Vec2(0.78, 0.44),
        Vec2(0.22, 0.70),
        Vec2(0.58, 0.78),
        Vec2(0.18, 0.94),
    ]

    public static let unitRect = BoltRect(x: 0, y: 0, width: 1, height: 1)

    public static func scenePoints(in rect: BoltRect) -> [Vec2] {
        normalizedPoints.map { point in
            Vec2(rect.x + point.x * rect.width, rect.y + point.y * rect.height)
        }
    }

    /// Polyline length. The unit-square length is `length`.
    public static func length(in rect: BoltRect) -> Double {
        let points = scenePoints(in: rect)
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for index in 1..<points.count {
            sum += points[index].distance(to: points[index - 1])
        }
        return sum
    }

    public static var length: Double { length(in: unitRect) }

    /// Point at `progress` along the centreline. 0 is the shoulder, 1 is the tip.
    /// Non-finite progress is the shoulder. Values outside 0…1 clamp.
    public static func sample(progress: Double, in rect: BoltRect) -> Vec2 {
        let points = scenePoints(in: rect)
        guard let first = points.first else { return .zero }
        guard points.count >= 2 else { return first }
        let t = progress.isFinite ? WhimsyMath.clamp01(progress) : 0
        if t == 0 { return first }
        if t == 1 { return points[points.count - 1] }
        let total = length(in: rect)
        if total <= 0 { return first }
        var remain = t * total
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let segment = end.distance(to: start)
            if remain <= segment || index == points.count - 1 {
                let u = segment > 0 ? remain / segment : 0
                return Vec2.lerp(start, end, WhimsyMath.clamp01(u))
            }
            remain -= segment
        }
        return points[points.count - 1]
    }

    public static func sample(_ progress: Double) -> Vec2 {
        sample(progress: progress, in: unitRect)
    }
}
