import Foundation

/// Axis-aligned rectangle in screen points (origin top-left).
public struct BoxRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(center c: Vec2, width: Double, height: Double) {
        self.init(x: c.x - width / 2, y: c.y - height / 2, width: width, height: height)
    }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }
    public func insetBy(_ d: Double) -> BoxRect { BoxRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
    public func intersects(_ o: BoxRect) -> Bool { minX < o.maxX && o.minX < maxX && minY < o.maxY && o.minY < maxY }
    public func contains(_ o: BoxRect) -> Bool { o.minX >= minX && o.maxX <= maxX && o.minY >= minY && o.maxY <= maxY }
}

/// Where every figure sits in each phase. Pure geometry, seeded and deterministic.
public struct BoutiqueLayout: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var figureCount: Int
    public var restCount: Int
    public var seed: UInt64

    public static let columns = 6
    public static let restScale = 1.0
    /// How much room the rest figures keep from the word and from each other.
    public static let wordMargin = 10.0
    public static let restSpacing = 72.0
    public static let restAttempts = 400

    /// The standard screen: 42 figures, 6 of them waiting around the word.
    public init(width: Double, height: Double, figureCount: Int = 42, restCount: Int = 6, seed: UInt64 = 0xB0_7140) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.figureCount = max(figureCount, 0)
        self.restCount = min(max(restCount, 0), self.figureCount)
        self.seed = seed
    }

    /// The figures stay inside this (status bar above, home indicator below).
    public var safeBounds: BoxRect { BoxRect(x: 10, y: 64, width: width - 20, height: height - 64 - 34) }

    /// The serif word's box (approximate: 30 % of the height of the type is ascenders).
    public var wordRect: BoxRect {
        let w = min(width * 0.82, 360)
        return BoxRect(center: Vec2(width / 2, height * 0.46), width: w, height: w * 0.27)
    }

    public func figureSize(scale: Double) -> (width: Double, height: Double) {
        (FigureSpec.baseSize.width * scale, FigureSpec.baseSize.height * scale)
    }

    // MARK: Rest

    /// Centres and tilts (degrees) of the figures scattered around the word. Rejection
    /// sampling: a candidate must fit the safe bounds, clear the word by `wordMargin`, and
    /// keep `restSpacing` from earlier figures. If no candidate passes, the one that comes
    /// closest (largest clearance) is used, so the count is always honoured.
    public func restPlacements() -> [(center: Vec2, tilt: Double)] {
        var rng = SeededRandom(seed: seed ^ 0x5E57)
        let size = figureSize(scale: Self.restScale)
        let bounds = safeBounds.insetBy(6)
        let word = wordRect.insetBy(-Self.wordMargin)
        var out: [(center: Vec2, tilt: Double)] = []
        for i in 0..<restCount {
            // Alternate above / below the word so the scatter frames it.
            let above = i % 2 == 0
            let bandTop = above ? bounds.minY + size.height / 2 : word.maxY + size.height / 2
            let bandBottom = above ? word.minY - size.height / 2 : bounds.maxY - size.height / 2
            var best: (Vec2, Double)? = nil
            for _ in 0..<Self.restAttempts {
                let c = Vec2(rng.uniform((bounds.minX + size.width / 2)...(bounds.maxX - size.width / 2)),
                             rng.uniform(min(bandTop, bandBottom)...max(bandTop, bandBottom)))
                let box = BoxRect(center: c, width: size.width, height: size.height)
                guard bounds.contains(box), !box.intersects(word) else { continue }
                let clearance = out.map { $0.center.distance(to: c) }.min() ?? .infinity
                if clearance >= Self.restSpacing { best = (c, clearance); break }
                if best == nil || clearance > best!.1 { best = (c, clearance) }
            }
            let c = best?.0 ?? Vec2(bounds.center.x, above ? bounds.minY + size.height / 2 : bounds.maxY - size.height / 2)
            out.append((c, rng.uniform(-8...8)))
        }
        return out
    }

    // MARK: Burst

    public var rows: Int { Int((Double(figureCount) / Double(Self.columns)).rounded(.up)) }

    /// The grid cell size of the burst.
    public var cell: (width: Double, height: Double) {
        let b = safeBounds
        return (b.width / Double(Self.columns), b.height / Double(max(rows, 1)))
    }

    /// Figures scale down to fit their cell in the burst.
    public var burstScale: Double {
        min(cell.width / FigureSpec.baseSize.width, cell.height / FigureSpec.baseSize.height) * 0.86
    }

    /// Fraction of a cell that a burst position may drift from the cell centre.
    public static let jitter = 0.16

    /// Burst centres: a jittered grid, odd rows nudged half a column for a crowd look.
    public func burstPlacements() -> [(center: Vec2, tilt: Double)] {
        var rng = SeededRandom(seed: seed ^ 0xB005_7ED)
        let b = safeBounds, c = cell
        let size = figureSize(scale: burstScale)
        let slackX = max((c.width - size.width) / 2, 0), slackY = max((c.height - size.height) / 2, 0)
        return (0..<figureCount).map { i in
            let row = i / Self.columns, col = i % Self.columns
            // Odd rows lean right, even rows left, by up to half the slack; jitter uses the rest.
            let shift = (row % 2 == 1 ? 1.0 : -1.0) * min(slackX * 0.5, c.width * 0.08)
            let jx = min(Self.jitter * c.width, slackX - abs(shift)), jy = min(Self.jitter * c.height, slackY)
            let cx = b.minX + (Double(col) + 0.5) * c.width + shift + rng.uniform(-1...1) * jx
            let cy = b.minY + (Double(row) + 0.5) * c.height + rng.uniform(-1...1) * jy
            return (Vec2(cx, cy), rng.uniform(-4...4))
        }
    }

    // MARK: Timing

    /// Seconds over which the burst ripples out from where you touched.
    public static let burstSpread = 0.45
    public static let exitSpread = 0.28
    public static let delayJitter = 0.05

    /// Per-figure delays for a ripple from `origin`: proportional to distance (the farthest
    /// figure waits `spread`), plus up to `delayJitter` of seeded noise.
    public func staggerDelays(from origin: Vec2, positions: [Vec2], spread: Double, jitter: Double = BoutiqueLayout.delayJitter) -> [Double] {
        var rng = SeededRandom(seed: seed ^ 0xDE1A)
        let d = positions.map { $0.distance(to: origin) }
        let far = max(d.max() ?? 0, 1e-9)
        return d.map { spread * $0 / far + jitter * rng.uniform(0...1) }
    }

    /// Offset that carries a figure at `position` straight away from `selected` and fully off
    /// screen. A figure exactly on the selection leaves downwards.
    public func exitOffset(for position: Vec2, awayFrom selected: Vec2) -> Vec2 {
        var dir = position - selected
        dir = dir.length < 1e-9 ? Vec2(0, 1) : dir.normalized
        let size = figureSize(scale: burstScale)
        let reach = (width * width + height * height).squareRoot() + size.height
        return dir * reach
    }

    /// Spring progress (0 → 1, overshooting) of SwiftUI's `.spring(duration:bounce:)`.
    public static func springProgress(_ t: Double, duration: Double = 0.6, bounce: Double = 0.25) -> Double {
        WhimsySpring.stepResponse(at: t, stiffness: pow(2 * .pi / duration, 2), dampingRatio: 1 - bounce)
    }
}
