import Foundation

/// Shared numbers for the liquid rep dial. The SwiftUI view, the tests and
/// `webports/liquidrepdial-core.mjs` all read these; the web port copies the values.
public enum LiquidRepTuning {
    public static let sceneWidth = 390.0
    public static let sceneHeight = 844.0

    public static let defaultGoal = 20
    public static let minimumGoal = 1
    public static let maxReps = 999

    /// SwiftUI spring bounce. ζ = 1 − bounce, so 0.4 overshoots and comes back.
    public static let bounce = 0.4
    public static let dampingRatio = 1 - bounce
    public static let stiffness = 120.0
    /// Fill-fraction per second added when the count rises, so one rep runs past its mark.
    public static let impulse = 2.4
    public static let settleTolerance = 0.0015

    public static let sloshStiffness = 70.0
    /// Largest rotation of the pool, in radians. About 27°.
    public static let maxSlosh = 0.48
    /// Tilt magnitude (radians, after the shared sine) that saturates the slosh.
    public static let fullTilt = 0.40

    public static let meniscusOmega = 16.0
    public static let meniscusRise = 6.0
    public static let meniscusFall = 2.4
    /// Fill velocity that drives the wobble envelope to 1.
    public static let meniscusSpeed = 1.6
    /// Extra trim, as a fraction of the circle, at meniscus +1.
    public static let meniscusTrim = 0.018
    /// Extra radius, in points, at meniscus +1. The leading blob rides this far off the rim.
    public static let meniscusBulge = 7.0

    /// Reduce Motion moves the fill across this long, with no overshoot.
    public static let crossfadeDuration = 0.28

    public static let glowFloor = 0.22
    public static let glowSpan = 0.50
    public static let goalGlowFloor = 0.78
    public static let goalGlowPulse = 0.22
    public static let goalGlowSteady = 1.0
    public static let goalOmega = 5.2

    public static let wordmark = "LIQUID"
    public static let caption = "REP DIAL"
    public static let repsLabel = "REPS"
    public static let wordmarkY = 148.0
    public static let captionY = 178.0
    public static let goalY = 576.0

    public static let dialDiameter = 220.0
    public static let stroke = 16.0
    public static var ringRadius: Double { (dialDiameter - stroke) / 2 }
    public static let dialCenter = Vec2(195, 430)
    public static let numberY = 418.0
    public static let repsLabelY = 468.0
    public static let hitSlop = 18.0

    public static let backgroundTop = LiquidRGB(0.03, 0.05, 0.10)
    public static let backgroundBottom = LiquidRGB(0.05, 0.09, 0.16)
    public static let glassInner = LiquidRGB(0.05, 0.09, 0.18)
    public static let glassOuter = LiquidRGB(0.11, 0.18, 0.32)
    public static let glassEdge = LiquidRGB(0.72, 0.82, 0.92)
    public static let track = LiquidRGB(1, 1, 1)
    public static let limeDeep = LiquidRGB(0.36, 0.72, 0.18)
    public static let lime = LiquidRGB(0.64, 0.93, 0.22)
    public static let limeBright = LiquidRGB(0.88, 1.0, 0.62)
    public static let number = LiquidRGB(0.94, 0.97, 0.99)
    public static let label = LiquidRGB(0.71, 0.86, 0.46)
    public static let wordmarkColor = LiquidRGB(0.86, 0.91, 0.96)
    public static let captionColor = LiquidRGB(0.55, 0.66, 0.76)

    public static let accessibilityLabel = "Liquid rep dial"
    public static let accessibilityHint = "Adds one rep."
    public static let addRepAction = "Add rep"

    public static var goalCaption: String { "GOAL \(defaultGoal)" }

    public static func goalCaption(goal: Int) -> String { "GOAL \(goal)" }
}

/// One sRGB colour. Channels are 0…1. The canvas port copies the same triples.
public struct LiquidRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Device tilt in radians. Positive roll lowers the right side. Positive pitch
/// lowers the bottom. The core never imports CoreMotion; the view maps attitude
/// into this, and a preview can pass it directly.
public struct LiquidTilt: Equatable, Sendable {
    public var roll: Double
    public var pitch: Double

    public init(roll: Double = 0, pitch: Double = 0) {
        self.roll = roll
        self.pitch = pitch
    }

    public static let zero = LiquidTilt()
}
