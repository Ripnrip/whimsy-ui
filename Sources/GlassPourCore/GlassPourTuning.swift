import Foundation

/// Shared numbers for the glass-drop menu. The SwiftUI view, the tests and
/// `webports/glasspour-core.mjs` all read these; the web port copies the values.
public enum GlassPourTuning {
    /// How long the finger must stay down on the drop before the pour starts.
    public static let longPress = 0.32
    /// Delay between one row starting to fall and the next.
    public static let stagger = 0.07
    /// Travel spring. Underdamped, so a row passes its seat and settles back.
    public static let stiffness = 170.0
    public static let dampingRatio = 0.62
    /// A second spring on the destructive row only: a small angular kick as it lands.
    public static let wobbleStiffness = 260.0
    public static let wobbleDamping = 0.16
    /// Radians per second added once, when that row's travel crosses `wobbleGate`.
    public static let wobbleKick = 2.4
    public static let wobbleGate = 0.86
    /// A row is born at this fraction of its rest size, inside the drop.
    public static let minScale = 0.42
    /// Scale is clamped so a big overshoot cannot blow the pill up.
    public static let maxScale = 1.08
    public static let minDrawnScale = 0.2
    /// The label fades in across this stretch of travel.
    public static let labelFrom = 0.62
    public static let labelTo = 0.92
    /// Reduce Motion crossfade, in seconds. No travel, no necks, no wobble.
    public static let reducedFade = 0.24
    /// A neck thinner than this has pinched off.
    public static let neckMinimum = 0.5
    public static let maxRows = 6
    /// Largest step `GlassPourModel.step` will integrate. A stalled frame is clamped.
    public static let maxFrame = 0.1
    public static let substep = 1.0 / 240.0

    public static let openedAnnouncement = "Menu opened"
    public static let closedAnnouncement = "Menu closed"
}

/// One menu row. Pure data: the view maps `symbol` to an SF Symbol.
public struct GlassDropItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var destructive: Bool

    public init(title: String, symbol: String, destructive: Bool = false, id: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.id = id ?? title
    }

    public static let share = GlassDropItem(title: "Share", symbol: "square.and.arrow.up", id: "share")
    public static let duplicate = GlassDropItem(title: "Duplicate", symbol: "plus.square.on.square", id: "duplicate")
    public static let rename = GlassDropItem(title: "Rename", symbol: "pencil", id: "rename")
    public static let delete = GlassDropItem(title: "Delete", symbol: "trash", destructive: true, id: "delete")
    public static let defaults: [GlassDropItem] = [.share, .duplicate, .rename, .delete]
}
