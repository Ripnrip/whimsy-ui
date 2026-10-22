import Foundation

/// A generated "photo": a gradient portrait drawn from shapes, all seeded.
public struct PortraitSpec: Equatable, Sendable {
    public var backgroundTop: Double      // hue 0…1
    public var backgroundBottom: Double   // hue 0…1
    public var skin: Int                  // index into the skin tones
    public var hairHue: Double
    public var hairStyle: Int             // 0 short, 1 bob, 2 bun, 3 long
    public var shirtHue: Double
    /// Horizontal offset of the sitter, −0.15…0.15 of the card width.
    public var lean: Double

    public static let skinTones: [(r: Double, g: Double, b: Double)] = [
        (0.98, 0.84, 0.72), (0.92, 0.72, 0.56), (0.78, 0.56, 0.40), (0.58, 0.40, 0.28), (0.40, 0.27, 0.19),
    ]

    public static func generate(_ rng: inout SeededRandom) -> PortraitSpec {
        let top = rng.uniform(0...1)
        return PortraitSpec(backgroundTop: top,
                            backgroundBottom: (top + rng.uniform(0.06...0.22)).truncatingRemainder(dividingBy: 1),
                            skin: min(Int(rng.uniform(0...5)), 4),
                            hairHue: rng.uniform(0.02...0.12),
                            hairStyle: min(Int(rng.uniform(0...4)), 3),
                            shirtHue: rng.uniform(0...1),
                            lean: rng.uniform(-0.15...0.15))
    }
}

/// One card of the masonry grid.
public struct GridCard: Equatable, Sendable {
    public var index: Int
    public var column: Int
    /// Frame in grid space (origin top-left of the grid).
    public var x: Double, y: Double, width: Double, height: Double
    /// 0…1: how far the card floats above the plane (parallax strength).
    public var depth: Double
    public var portrait: PortraitSpec
    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }
}

/// Shortest-column masonry with seeded aspect ratios and depths.
public struct MasonryGrid: Equatable, Sendable {
    public var width: Double
    public var columns: Int
    public var spacing: Double
    public var cards: [GridCard]
    public var height: Double

    public init(count: Int = 18, width: Double = 473, columns: Int = 3, spacing: Double = 10,
                aspect: ClosedRange<Double> = 1.0...1.55, seed: UInt64 = 0x7417) {
        self.width = max(width, 1)
        self.columns = max(columns, 1)
        self.spacing = max(spacing, 0)
        var rng = SeededRandom(seed: seed)
        let cw = (self.width - Double(self.columns + 1) * self.spacing) / Double(self.columns)
        var heights = Array(repeating: self.spacing, count: self.columns)
        var out: [GridCard] = []
        for i in 0..<max(count, 0) {
            let a = rng.uniform(aspect)
            let depth = rng.uniform(0...1)
            let portrait = PortraitSpec.generate(&rng)
            // Shortest column, leftmost on ties.
            var c = 0
            for k in 1..<self.columns where heights[k] < heights[c] - 1e-9 { c = k }
            let h = (cw * a).rounded()
            out.append(GridCard(index: i, column: c, x: self.spacing + Double(c) * (cw + self.spacing), y: heights[c],
                                width: cw, height: h, depth: depth, portrait: portrait))
            heights[c] += h + self.spacing
        }
        cards = out
        height = heights.max() ?? self.spacing
    }

    /// Reveal delay for each card: a ripple outwards from `origin` (grid space).
    public func revealDelay(of card: GridCard, from origin: Vec2, perPoint: Double = 0.0011) -> Double {
        card.center.distance(to: origin) * perPoint
    }
}
