import Foundation

/// The card and its corner, in card-local points (origin top left, y down).
///
/// The fold maths is not repeated here: `Polygon`, `FoldLine` and `PeelState` come from `PeelCore`
/// (the same perpendicular-bisector fold the sticker uses). This file only adds what is specific to a
/// full-size card: where its corner is, how far a drag can reach in a direction, and the rules.
public enum DogEarLayout {
    public static let width = 300.0
    public static let height = 420.0
    public static let cornerRadius = 22.0
    public static let segments = 8

    public static let center = Vec2(width / 2, height / 2)

    /// The card outline, with rounded corners sampled into a polygon so it can be clipped and folded.
    public static let shape = Polygon.roundedRect(center: center, width: width, height: height,
                                                  cornerRadius: cornerRadius, segments: segments)

    /// The middle of the rounded bottom-right corner: the point the fold is measured from.
    public static let grab: Vec2 = {
        let k = cornerRadius * (1 - 0.5.squareRoot())
        return Vec2(width - k, height - k)
    }()

    /// How close to the grab point a touch has to start.
    public static let grabRadius = 64.0

    /// Unit vector from the corner toward the middle of the card: the default peel direction.
    public static var inward: Vec2 { (center - grab).normalized }

    /// How far the card reaches from `grab` along `direction`. Zero (or less) when the direction points
    /// out of the card, which is why such drags lift nothing.
    public static func extent(along direction: Vec2) -> Double {
        let n = direction.normalized
        guard n.length > 0 else { return 0 }
        return shape.points.map { ($0 - grab).dot(n) }.max() ?? 0
    }
}

/// Thresholds and tuning.
public struct DogEarRules: Equatable, Sendable {
    /// Peel progress (finger travel ÷ reach of the card along the drag) that commits to peeling off.
    public var threshold = 0.6
    /// The threshold re-arms only after dropping this far below it, so hovering on the line doesn't chatter.
    public var hysteresis = 0.03
    /// The finger can pull at most this fraction of the card's reach, so the crease stays on the card.
    public var maxPullFraction = 1.0
    /// Below this many points of pull nothing is lifted.
    public var minPull = 0.5
    public var hapticInterval = 0.12

    /// Release below the threshold: an under-damped spring on the pull. It overshoots through flat and
    /// the next swing lifts the corner a little again (the tiny bounce) before it settles.
    public var springStiffness = 380.0
    public var springDamping = 0.4
    /// Reduce Motion: critically damped, so no wobble.
    public var calmStiffness = 520.0
    public var calmDamping = 1.0

    public var sweepDuration = 0.5
    public var flyDuration = 0.55
    public var flyDistance = 200.0
    public var flyRotation = 0.16
    public var fadeDuration = 0.35
    public var returnDuration = 0.5

    public init() {}
}

/// Gradient and shadow parameters for one frame, all driven by how far the corner is peeled.
public struct DogEarShading: Equatable, Sendable {
    /// Alpha of black at the crease, fading to clear halfway along the flap.
    public var creaseDark: Double
    /// Alpha of white at the far edge of the flap.
    public var highlight: Double
    /// The flap's depth: distance from the crease to its farthest point (the gradient's length).
    public var gradientLength: Double
    /// The flap's shadow on the card: pushed along the peel direction, blurred, and faint until lifted.
    public var shadowOffset: Double
    public var shadowBlur: Double
    public var shadowOpacity: Double

    public static func make(progress: Double, flapDepth: Double) -> DogEarShading {
        let p = WhimsyMath.clamp01(progress)
        return DogEarShading(creaseDark: 0.14 + 0.22 * p, highlight: 0.10, gradientLength: max(flapDepth, 1),
                             shadowOffset: 4 + 10 * p, shadowBlur: 6 + 10 * p, shadowOpacity: 0.16 + 0.24 * p)
    }

    /// The card's own shadow on whatever is under it (the hidden note).
    public static let cardShadowRadius = 14.0
    public static let cardShadowY = 8.0
    public static let cardShadowOpacity = 0.35
}
