import Foundation

/// A stadium (capsule) or a circle, when `halfWidth == radius`.
public struct GlassPourBlob: Equatable, Sendable {
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

/// The goo bridge between two blobs stacked vertically. An hourglass: wide where it
/// meets each blob, thinner at the waist, gone once the gap passes `breakGap`.
public struct GlassPourNeck: Equatable, Sendable {
    public var x: Double
    public var top: Double
    public var bottom: Double
    public var width: Double
    public var waist: Double

    /// Clockwise from the top left.
    public var polygon: [Vec2] {
        let mid = (top + bottom) / 2
        return [
            Vec2(x - width / 2, top), Vec2(x - waist / 2, mid), Vec2(x - width / 2, bottom),
            Vec2(x + width / 2, bottom), Vec2(x + waist / 2, mid), Vec2(x + width / 2, top),
        ]
    }
}

/// Where the drop and the rows sit, in the menu's own coordinates (origin top left).
public enum GlassPourLayout {
    public static let width = 228.0
    public static let dropRadius = 30.0
    public static let topInset = 6.0
    public static let pillWidth = 196.0
    public static let pillHeight = 50.0
    public static let rowGap = 14.0
    public static let bottomMargin = 18.0
    /// Extra points around the drop so a finger that lands on the highlight still hits.
    public static let hitSlop = 4.0

    /// The goo filter the view applies: blur, then an alpha threshold.
    public static let gooBlur = 9.0
    public static let gooThreshold = 0.5
    public static let maxNeck = 40.0
    public static let breakGap = 11.0
    /// How much thinner the waist is than the ends, once the gap has fully opened.
    public static let waistThinning = 0.55

    /// The web preview is one phone screen. The SwiftUI demo fills whatever it is given.
    public static let pageWidth = 390.0
    public static let pageHeight = 844.0
    public static let pageOrigin = Vec2((pageWidth - width) / 2, 300)

    public static var dropCenter: Vec2 { Vec2(width / 2, topInset + dropRadius) }
    public static var pitch: Double { pillHeight + rowGap }

    public static func restCenter(_ index: Int) -> Vec2 {
        let first = dropCenter.y + dropRadius + rowGap + pillHeight / 2
        return Vec2(width / 2, first + Double(index) * pitch)
    }

    public static func height(count: Int) -> Double {
        guard count > 0 else { return dropCenter.y + dropRadius + bottomMargin }
        return restCenter(count - 1).y + pillHeight / 2 + bottomMargin
    }

    public static func dropBlob(scale: Double) -> GlassPourBlob {
        let radius = dropRadius * scale
        return GlassPourBlob(center: dropCenter, halfWidth: radius, radius: radius)
    }

    public static func pillBlob(center: Vec2, scale: Double) -> GlassPourBlob {
        GlassPourBlob(center: center, halfWidth: pillWidth / 2 * scale, radius: pillHeight / 2 * scale)
    }

    /// 0 when the blobs overlap, 1 once they are `breakGap` apart. Drives the delete tint.
    public static func pinch(gap: Double) -> Double {
        1 - neckWidth(gap: gap) / maxNeck
    }

    public static func neckWidth(gap: Double) -> Double {
        maxNeck * (1 - WhimsyMath.smoothstep(0, breakGap, gap))
    }

    /// The bridge between `upper` and `lower`, or nil once it has pinched off.
    public static func neck(upper: GlassPourBlob, lower: GlassPourBlob) -> GlassPourNeck? {
        let gap = lower.top - upper.bottom
        let width = neckWidth(gap: gap)
        guard width >= GlassPourTuning.neckMinimum else { return nil }
        let t = WhimsyMath.smoothstep(0, breakGap, gap)
        let lo = min(upper.center.y, lower.center.y)
        let hi = max(upper.center.y, lower.center.y)
        return GlassPourNeck(x: upper.center.x, top: lo, bottom: hi, width: width, waist: width * (1 - waistThinning * t))
    }

    /// Necks between a drop and the visible rows, top to bottom. A row that has not yet
    /// passed the one above it bridges both of its neighbours.
    public static func necks(drop: GlassPourBlob, rows: [GlassPourBlob]) -> [GlassPourNeck] {
        let blobs = ([drop] + rows)
            .enumerated()
            .sorted { ($0.element.center.y, $0.offset) < ($1.element.center.y, $1.offset) }
            .map(\.element)
        return zip(blobs, blobs.dropFirst()).compactMap { neck(upper: $0, lower: $1) }
    }

    public static func containsDrop(_ point: Vec2, scale: Double) -> Bool {
        let radius = dropRadius * scale + hitSlop
        let delta = point - dropCenter
        return delta.dot(delta) <= radius * radius
    }

    /// Point-in-capsule. The pill is a rectangle with semicircular ends.
    public static func containsPill(_ point: Vec2, center: Vec2, scale: Double) -> Bool {
        let halfWidth = pillWidth * 0.5 * scale
        let halfHeight = pillHeight * 0.5 * scale
        let dx = abs(point.x - center.x)
        let dy = abs(point.y - center.y)
        if dx > halfWidth || dy > halfHeight { return false }
        let inner = halfWidth - halfHeight
        if dx <= inner { return true }
        let ex = dx - inner
        return ex * ex + dy * dy <= halfHeight * halfHeight
    }

    /// Specular dot on the drop, up and to the left of centre.
    public static func dropHighlight(scale: Double) -> (center: Vec2, radius: Double) {
        let radius = dropRadius * scale
        let center = Vec2(dropCenter.x - 0.34 * radius, dropCenter.y - 0.38 * radius)
        return (center, 0.42 * radius)
    }
}
