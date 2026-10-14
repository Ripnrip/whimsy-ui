import Foundation
import WhimsyCore

/// Home layout: a `columns × rows` grid of equal tiles filling `width × height` with `spacing`
/// between tiles and around the edge. Indices are row-major (0 is top-left).
public struct TileLayout: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let width: Double
    public let height: Double
    public let spacing: Double

    public init(columns: Int = 4, rows: Int = 6, width: Double, height: Double, spacing: Double = 10) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.width = max(width, 0)
        self.height = max(height, 0)
        self.spacing = max(spacing, 0)
    }

    public var count: Int { columns * rows }

    public var tileWidth: Double { max((width - spacing * Double(columns + 1)) / Double(columns), 0) }
    public var tileHeight: Double { max((height - spacing * Double(rows + 1)) / Double(rows), 0) }

    /// Centre of tile `index` in its home slot.
    public func home(_ index: Int) -> Vec2 {
        let column = index % columns, row = index / columns
        return Vec2(
            spacing + tileWidth / 2 + Double(column) * (tileWidth + spacing),
            spacing + tileHeight / 2 + Double(row) * (tileHeight + spacing)
        )
    }

    public var center: Vec2 { Vec2(width / 2, height / 2) }

    /// Distance of tile `index`'s home from the grid centre.
    public func distanceFromCenter(_ index: Int) -> Double { home(index).distance(to: center) }

    /// Half the diagonal of a tile at `scale`; the farthest any corner can reach from its centre at any rotation.
    public func halfDiagonal(scale: Double = 1) -> Double {
        (tileWidth * tileWidth + tileHeight * tileHeight).squareRoot() / 2 * scale
    }
}

/// Where a tile flies to when scattered.
public struct ScatterTarget: Equatable, Sendable {
    public var position: Vec2
    /// Radians; within ±`ScatterTuning.maxTilt`.
    public var rotation: Double
    public var scale: Double
}

/// The knobs, all with sensible defaults.
public struct ScatterTuning: Equatable, Sendable {
    /// Max tilt either way (radians), ±25°.
    public var maxTilt = 25 * Double.pi / 180
    /// Scale wobble range for scattered tiles.
    public var scaleRange: ClosedRange<Double> = 0.86...1.14
    /// Base spring stiffness; each tile gets `base × stiffnessSpread` (fixed per seed).
    public var baseStiffness = 150.0
    public var stiffnessSpread: ClosedRange<Double> = 0.7...1.3
    /// Damping ratio (< 1 overshoots a little: tiles bounce into place).
    public var dampingRatio = 0.62
    /// Regroup ripple: the outermost tile starts this long after the centre ones.
    public var rippleDuration = 0.38
    /// Scatter: a little random launch jitter per tile.
    public var scatterJitter: ClosedRange<Double> = 0...0.08
    /// A regrouping tile "lands" when it first comes within this distance of home (points).
    public var landingRadius = 1.5
    public init() {}
}

public extension TileLayout {
    /// A random scatter target for one tile. The rotated, scaled tile stays fully inside the
    /// bounds, because the centre is inset by the tile's half-diagonal.
    func scatterTarget(using rng: inout SeededRandom, tuning: ScatterTuning = ScatterTuning()) -> ScatterTarget {
        let scale = rng.uniform(tuning.scaleRange)
        let inset = min(halfDiagonal(scale: scale), width / 2, height / 2)
        let x = rng.uniform(inset...max(width - inset, inset))
        let y = rng.uniform(inset...max(height - inset, inset))
        let rotation = rng.uniform(-tuning.maxTilt...tuning.maxTilt)
        return ScatterTarget(position: Vec2(x, y), rotation: rotation, scale: scale)
    }

    /// Regroup start delay per tile: proportional to its distance from the centre (a ripple).
    /// Tiles at equal distances start together.
    func rippleDelays(duration: Double) -> [Double] {
        let distances = (0..<count).map(distanceFromCenter)
        let lo = distances.min() ?? 0, hi = distances.max() ?? 0
        guard hi - lo > 1e-9 else { return Array(repeating: 0, count: count) }
        return distances.map { ($0 - lo) / (hi - lo) * duration }
    }
}
