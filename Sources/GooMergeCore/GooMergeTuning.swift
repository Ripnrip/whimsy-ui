import Foundation

/// Shared numbers for the goo merge. The SwiftUI view, the tests and
/// `webports/goomerge-core.mjs` all read these; the web port copies the values.
public enum GooMergeTuning {
    public static let pageWidth = 390.0
    public static let pageHeight = 844.0
    /// Centre of the dashed well the drops sit around, and the point they pour into.
    public static let well = Vec2(195, 400)
    public static let ringRadius = 112.0
    public static let wellDashRadius = 36.0
    public static let minRadius = 26.0
    public static let maxRadius = 44.0
    /// The ring is drawn with four or five drops. Fewer than four uses the samples.
    public static let minDrops = 4
    public static let maxDrops = 5

    /// Critically-ish spring into the well. Slightly overdamped so a fixed step does not
    /// step back out of the well.
    public static let stiffness = 32.0
    public static let dampingRatio = 1.05
    public static let maxFrame = 0.1
    public static let substep = 1.0 / 240.0

    /// Surface gap (centre distance minus both radii) where a dragged drop starts to stretch
    /// toward its neighbour, and where the two snap into one cluster.
    public static let stretchReach = 40.0
    public static let snapGap = 8.0
    /// How far each drop's drawn centre slides toward the other at full stretch.
    public static let stretchShift = 16.0
    /// Points per second a neighbour creeps toward the finger at full stretch.
    public static let attractSpeed = 12.0

    /// A drop has reached the well once its centre is inside this radius.
    public static let arrival = 2.0
    public static let morphDuration = 0.72
    /// Reduce Motion crossfade. Positions snap; there is no stretch and no spring.
    public static let reducedFade = 0.28

    public static let bobAmplitude = 3.0
    public static let bobOmega = 1.7

    /// Polynomial smooth-min blend radius, in points, and the metaball denominator floor.
    public static let smoothK = 32.0
    public static let fieldEpsilon = 4.0
    /// A pair is connected when the smooth-min field at its midpoint is at or inside this.
    public static let connectSDF = 0.0

    /// Canvas fallback: blur, then an alpha threshold. The Metal path uses the same SDF.
    public static let gooBlur = 14.0
    public static let gooThreshold = 0.52
    public static let hitSlop = 10.0

    public static let cardWidth = 168.0
    public static let cardHeight = 216.0
    public static let cardRadius = 16.0
    public static let foldSize = 32.0

    public static let buttonCenter = Vec2(195, 712)
    public static let buttonWidth = 168.0
    public static let buttonHeight = 48.0

    public static let documentName = "Binder-01.pdf"
    public static let readyValue = "Ready to combine"
    public static let mergingValue = "Merging"
    public static let mergedValue = "Merged into Binder-01.pdf"
    public static let combineAction = "Combine"
    public static let accessibilityHint = "Combines the files into one document"
}

/// One file drop. `value` is a size in 0…1 (larger values draw a larger circle).
public struct GooDrop: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var value: Double

    public init(name: String, value: Double, id: String? = nil) {
        self.name = name
        self.value = value
        self.id = id ?? name
    }

    public static let brief = GooDrop(name: "brief.md", value: 0.62, id: "brief")
    public static let shot = GooDrop(name: "shot.png", value: 1.00, id: "shot")
    public static let notes = GooDrop(name: "notes.txt", value: 0.48, id: "notes")
    public static let reel = GooDrop(name: "reel.mov", value: 0.84, id: "reel")
    public static let deck = GooDrop(name: "deck.key", value: 0.70, id: "deck")
    public static let samples: [GooDrop] = [.brief, .shot, .notes, .reel, .deck]
}

public enum GooMergePhase: String, Equatable, Sendable {
    case ready, combining, morphing, merged
}

public enum GooMergeEvent: Equatable, Sendable {
    case combining
    case snapped(Int, Int)
    case haptic
    case morphing
    case merged(String)
}
