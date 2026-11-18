import Foundation

/// Shared numbers for the reeded-glass sync hero.
/// `webports/slatsync-core.mjs` repeats this table. Change both together.
public enum SlatSyncTuning {
    public static let canvasWidth = 390.0
    public static let canvasHeight = 844.0

    public static let slatCount = 11
    /// The five slats around the middle (indices 3…7) hold the aurora at rest.
    public static let coreRadius = 2

    public static let slatWidth = 332.0
    public static let slatHeight = 26.0
    public static let slatGap = 8.0
    public static let stackTop = 176.0
    public static let cornerRadius = 4.0
    /// The lit lip along the top of every slat.
    public static let edgeThickness = 1.0

    /// How wide the resting core is, as a fraction of the slat. It grows to 1.
    public static let spreadFloor = 0.22
    public static let spreadCeil = 1.0
    /// Vertical reach, in slats from the centre, at progress 0 and at progress 1.
    public static let reachStart = 2.45
    public static let reachEnd = 6.2
    /// Width of the smooth gate that turns a slat on, in slat-steps.
    public static let reachFeather = 0.85

    /// Device attitude beyond this (radians) does not push the slats any further.
    public static let maxAttitude = 0.55
    /// Points of sideways travel at the end slats for one radian of roll, before the depth scale.
    public static let rollTravel = 40.0
    /// Degrees of extra tilt at an end slat for one radian of pitch.
    public static let pitchBow = 0.55

    public static let demoDelay = 0.35
    public static let demoRun = 3.5

    public static let title = "Halo Vault"
    public static let subtitle = "Studio library"
    public static let detail = "1,284 files · 3 devices"
    public static let syncing = "Syncing…"
    public static let synced = "All synced"

    public static let cobalt = SlatRGB(red: 47.0 / 255.0, green: 92.0 / 255.0, blue: 1)
    public static let teal = SlatRGB(red: 32.0 / 255.0, green: 214.0 / 255.0, blue: 206.0 / 255.0)
    public static let lime = SlatRGB(red: 184.0 / 255.0, green: 1, blue: 74.0 / 255.0)
    /// Where the vertical blend leaves cobalt and starts toward lime. 0 is the top slat.
    public static let tealStop = 0.42

    public static let backgroundTop = SlatRGB(red: 7.0 / 255.0, green: 6.0 / 255.0, blue: 22.0 / 255.0)
    public static let backgroundBottom = SlatRGB(red: 12.0 / 255.0, green: 8.0 / 255.0, blue: 32.0 / 255.0)
    public static let ink = SlatRGB(red: 1, green: 1, blue: 1)
    public static let muted = SlatRGB(red: 196.0 / 255.0, green: 194.0 / 255.0, blue: 210.0 / 255.0)

    /// Faint glass lip, plus the aurora's share of the 1 pt edge.
    public static let edgeBase = 0.22
    public static let edgeGain = 0.78
}

/// A colour the core can carry without SwiftUI. Components are 0…1.
public struct SlatRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static func lerp(_ a: SlatRGB, _ b: SlatRGB, _ t: Double) -> SlatRGB {
        let u = min(max(t, 0), 1)
        return SlatRGB(
            red: a.red + (b.red - a.red) * u,
            green: a.green + (b.green - a.green) * u,
            blue: a.blue + (b.blue - a.blue) * u
        )
    }
}

/// The line under the percentage.
public enum SlatSyncLabel: String, Equatable, Sendable {
    case syncing = "Syncing…"
    case synced = "All synced"
}
