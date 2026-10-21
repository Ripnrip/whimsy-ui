import Foundation

/// macOS Dock-style magnification: a raised-cosine bump centred on the finger.
public struct DockFalloff: Equatable, Sendable {
    /// Distance (pt) at which the influence reaches zero.
    public var radius: Double
    /// Scale of an item directly under the finger.
    public var maxScale: Double

    public init(radius: Double = 150, maxScale: Double = 1.5) {
        self.radius = max(radius, 1e-6)
        self.maxScale = max(maxScale, 1)
    }

    /// 1 directly under the finger, falling smoothly to 0 at `radius` (and beyond).
    public func weight(distance: Double) -> Double {
        guard distance.isFinite else { return 0 }
        let u = min(abs(distance) / radius, 1)
        return 0.5 * (1 + cos(.pi * u))
    }

    public func scale(distance: Double) -> Double {
        1 + (maxScale - 1) * weight(distance: distance)
    }
}

/// One garment's target slot on the rail.
public struct RailSlot: Equatable, Sendable {
    /// Hook x (pt, in the rail's coordinate space).
    public var centerX: Double
    public var scale: Double
    /// 0…1: how strongly the finger is over this item (drives lift, shadow and z order).
    public var emphasis: Double
}

/// Lays out `count` garments on a rail, spreading them apart around the finger.
///
/// Widths grow with each item's magnification and the row is re-anchored so the point under
/// the finger stays under the finger (exactly like the Dock): items left of it are pushed left,
/// items right of it are pushed right, and the hovered one swells in place.
public struct RailLayout: Equatable, Sendable {
    public var count: Int
    /// Base hook-to-hook spacing (pt).
    public var slotWidth: Double
    /// The rail's centre x (pt).
    public var railCenter: Double
    public var falloff: DockFalloff

    public init(count: Int, slotWidth: Double = 62, railCenter: Double = 0, falloff: DockFalloff = DockFalloff()) {
        self.count = max(count, 0)
        self.slotWidth = max(slotWidth, 1)
        self.railCenter = railCenter
        self.falloff = falloff
    }

    /// The resting row: evenly spaced and centred.
    public var baseCenters: [Double] {
        (0..<count).map { railCenter + (Double($0) - Double(count - 1) / 2) * slotWidth }
    }

    public var baseWidth: Double { Double(count) * slotWidth }

    public func slots(fingerX: Double?) -> [RailSlot] {
        let base = baseCenters
        guard let fx = fingerX, fx.isFinite, count > 0 else {
            return base.map { RailSlot(centerX: $0, scale: 1, emphasis: 0) }
        }
        let weights = base.map { falloff.weight(distance: fx - $0) }
        let widths = weights.map { slotWidth * (1 + (falloff.maxScale - 1) * $0) }
        let total = widths.reduce(0, +)
        let left0 = railCenter - baseWidth / 2
        let u = WhimsyMath.clamp01((fx - left0) / baseWidth)
        var x = left0 - u * (total - baseWidth)
        var out: [RailSlot] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            out.append(RailSlot(centerX: x + widths[i] / 2, scale: widths[i] / slotWidth, emphasis: weights[i]))
            x += widths[i]
        }
        return out
    }

    /// The item the finger is over (the most magnified one), or nil when nothing is affected.
    public func hoveredIndex(fingerX: Double?) -> Int? {
        guard let fx = fingerX, fx.isFinite, count > 0 else { return nil }
        let w = baseCenters.map { falloff.weight(distance: fx - $0) }
        guard let best = w.indices.max(by: { w[$0] < w[$1] }), w[best] > 0.5 else { return nil }
        return best
    }
}
