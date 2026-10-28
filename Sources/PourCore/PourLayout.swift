import Foundation

/// One goo blob: a capsule (a rectangle with semicircular ends of `radius`) centred at `center`.
public struct PourBlob: Equatable, Sendable {
    public var center: Vec2
    public var halfWidth: Double
    public var radius: Double
    public init(center: Vec2, halfWidth: Double, radius: Double) {
        self.center = center
        self.halfWidth = halfWidth
        self.radius = radius
    }
    public var top: Double { center.y - radius }
    public var bottom: Double { center.y + radius }
}

/// The bridge of goo joining two vertically adjacent blobs: an hourglass between their centres.
public struct PourNeck: Equatable, Sendable {
    public var x: Double
    public var top: Double
    public var bottom: Double
    /// Width where it meets the blobs.
    public var width: Double
    /// Width at the middle (thinner the further the blobs have drawn apart).
    public var waist: Double

    /// The hourglass outline, clockwise from the top left.
    public var polygon: [Vec2] {
        let mid = (top + bottom) / 2
        return [Vec2(x - width / 2, top), Vec2(x - waist / 2, mid), Vec2(x - width / 2, bottom),
                Vec2(x + width / 2, bottom), Vec2(x + waist / 2, mid), Vec2(x + width / 2, top)]
    }
}

/// Where everything sits, in the component's own coordinates (origin top left, x centred).
public enum PourLayout {
    public static let defaultOptions = ["Newest", "Oldest", "Popular", "A to Z"]

    public static let width = 220.0
    public static let pillSize = Vec2(160, 44)
    public static let dropRadius = 20.0
    public static let dropHalfWidth = 74.0
    /// Empty space between neighbouring drops (and the pill and the first drop) at rest.
    public static let restGap = 14.0
    /// Distance between neighbouring drops' centres at rest.
    public static var pitch: Double { 2 * dropRadius + restGap }
    /// Extra room below the last drop for the overshoot of the pour.
    public static let bottomMargin = 12.0

    /// The goo filter: blur radius, then an alpha threshold.
    public static let gooBlur = 8.0
    public static let gooThreshold = 0.5

    /// A neck is at full width when the blobs touch and gone once they are `breakGap` apart.
    public static let maxNeck = 44.0
    public static let breakGap = 10.0
    /// How much thinner the waist gets as the gap opens.
    public static let waistThinning = 0.5

    public static var pillCenter: Vec2 { Vec2(width / 2, pillSize.y / 2) }
    public static var pillBlob: PourBlob { PourBlob(center: pillCenter, halfWidth: pillSize.x / 2, radius: pillSize.y / 2) }

    public static func height(optionCount n: Int) -> Double {
        pillSize.y + Double(max(n, 0)) * pitch + bottomMargin
    }

    public static func restCenter(_ i: Int) -> Vec2 {
        Vec2(width / 2, pillSize.y + restGap + dropRadius + Double(i) * pitch)
    }

    public static func restBlob(_ i: Int) -> PourBlob {
        PourBlob(center: restCenter(i), halfWidth: dropHalfWidth, radius: dropRadius)
    }

    /// Neck width for a vertical gap between two blobs (negative gap = overlapping).
    public static func neckWidth(gap: Double) -> Double {
        maxNeck * (1 - WhimsyMath.smoothstep(0, breakGap, gap))
    }

    /// The bridge between `upper` and `lower`, or nil once it has pinched off (under half a point wide).
    public static func neck(upper a: PourBlob, lower b: PourBlob) -> PourNeck? {
        let gap = b.top - a.bottom
        let w = neckWidth(gap: gap)
        guard w >= 0.5 else { return nil }
        let t = WhimsyMath.smoothstep(0, breakGap, gap)
        let lo = min(a.center.y, b.center.y), hi = max(a.center.y, b.center.y)
        return PourNeck(x: a.center.x, top: lo, bottom: hi, width: w, waist: w * (1 - waistThinning * t))
    }
}
