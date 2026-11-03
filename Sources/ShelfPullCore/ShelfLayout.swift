import Foundation

/// lowbias32, the same in Swift (wrapping UInt32) and JS (Math.imul). Draws every spine's size and bands.
public enum ShelfHash {
    public static func hash32(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x = x &* 0x7feb_352d
        x ^= x >> 15; x = x &* 0x846c_a68b
        x ^= x >> 16
        return x
    }
    public static func value(_ seed: UInt32, _ salt: Int) -> UInt32 {
        hash32((UInt32(truncatingIfNeeded: salt) &* 0x9E37_79B1) ^ hash32(seed))
    }
    /// 0 ..< 1 from the low 24 bits.
    public static func unit(_ seed: UInt32, _ salt: Int) -> Double { Double(value(seed, salt) & 0xFF_FFFF) / 16_777_216 }
}

public struct ShelfRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px <= maxX && py >= y && py <= maxY }
    public static func lerp(_ a: ShelfRect, _ b: ShelfRect, _ t: Double) -> ShelfRect {
        ShelfRect(x: WhimsyMath.lerp(a.x, b.x, t), y: WhimsyMath.lerp(a.y, b.y, t),
                  width: WhimsyMath.lerp(a.width, b.width, t), height: WhimsyMath.lerp(a.height, b.height, t))
    }
}

/// One book standing on the shelf: where its spine is, how big, and where its decorative bands sit.
public struct ShelfSpine: Equatable, Sendable {
    public var index: Int
    /// Left edge on the shelf, in points (the shelf is `ShelfLayout.width` wide, y down).
    public var x: Double
    public var width: Double
    public var height: Double
    /// Band positions as fractions of the height from the top, increasing.
    public var bands: [Double]

    public var centerX: Double { x + width / 2 }
    /// The width of the front cover (the depth of the book).
    public var coverWidth: Double { height * ShelfLayout.coverAspect }
    /// The spine as a rectangle at rest, standing on the plank.
    public var restRect: ShelfRect { ShelfRect(x: x, y: ShelfLayout.plankTop - height, width: width, height: height) }
}

/// The shelf: seven spines of different heights and widths, side by side on one plank. Pure geometry.
public struct ShelfLayout: Equatable, Sendable {
    public static let width = 340.0
    public static let height = 440.0
    /// The y of the plank's top surface, where the books stand.
    public static let plankTop = 380.0
    public static let plankThickness = 16.0
    public static let plankOverhang = 12.0
    /// Where a lifted book is shown (its centre) and the size of the open card.
    public static let stage = Vec2(170, 190)
    public static let cardSize = Vec2(280, 320)
    public static let stageScale = 1.15
    public static let coverAspect = 0.7
    public static let gap = 1.5
    public static let sideMargin = 24.0
    public static let minBooks = 3
    public static let maxBooks = 9
    public static let defaultBooks = 7
    public static let defaultSeed: UInt32 = 0x5E1F
    public static let minSpineWidth = 30.0
    public static let spineWidthSpread = 14.0
    public static let minSpineHeight = 118.0
    public static let spineHeightSpread = 52.0
    /// Neighbouring heights differ by at least this much (or the next book is nudged).
    public static let minHeightStep = 8.0

    public var spines: [ShelfSpine]
    public var seed: UInt32

    public var count: Int { spines.count }

    public static func clampedCount(_ n: Int) -> Int { min(max(n, minBooks), maxBooks) }

    public static var cardRect: ShelfRect {
        ShelfRect(x: stage.x - cardSize.x / 2, y: 30, width: cardSize.x, height: cardSize.y)
    }

    public static func make(count requested: Int = defaultBooks, seed: UInt32 = defaultSeed) -> ShelfLayout {
        let n = clampedCount(requested)
        var widths: [Double] = [], heights: [Double] = []
        for i in 0..<n {
            widths.append(minSpineWidth + spineWidthSpread * ShelfHash.unit(seed, 10 + i))
            var h = minSpineHeight + spineHeightSpread * ShelfHash.unit(seed, 40 + i)
            if let prev = heights.last, abs(h - prev) < minHeightStep { h = prev + (prev > 144 ? -10 : 10) }
            heights.append(h)
        }
        let gaps = gap * Double(n - 1)
        let room = width - 2 * sideMargin - gaps
        let total = widths.reduce(0, +)
        if total > room { widths = widths.map { $0 * room / total } }
        var x = (width - widths.reduce(0, +) - gaps) / 2
        var spines: [ShelfSpine] = []
        for i in 0..<n {
            let top = 0.1 + 0.05 * ShelfHash.unit(seed, 70 + i)
            var bands = [top, top + 0.06]
            bands.append(0.84 + 0.04 * ShelfHash.unit(seed, 110 + i))
            if ShelfHash.unit(seed, 130 + i) > 0.5 { bands.append(0.92) }
            spines.append(ShelfSpine(index: i, x: x, width: widths[i], height: heights[i], bands: bands))
            x += widths[i] + gap
        }
        return ShelfLayout(spines: spines, seed: seed)
    }

    /// How far above its slot (in points) a book's centre sits when it is shown on the stage.
    public func liftedRise(_ book: Int) -> Double {
        let s = spines[min(max(book, 0), count - 1)]
        return Self.plankTop - s.height / 2 - Self.stage.y
    }

    /// The front cover as a rectangle on the stage, at the stage scale.
    public func coverRect(_ book: Int, scale: Double = ShelfLayout.stageScale) -> ShelfRect {
        let s = spines[min(max(book, 0), count - 1)]
        let w = s.coverWidth * scale, h = s.height * scale
        return ShelfRect(x: Self.stage.x - w / 2, y: Self.stage.y - h / 2, width: w, height: h)
    }

    /// Which spine, at rest, is under a point (y down).
    public func spine(atX px: Double, y py: Double) -> Int? {
        guard px.isFinite, py.isFinite else { return nil }
        for s in spines where px >= s.x - Self.gap / 2 && px <= s.x + s.width + Self.gap / 2 {
            return py >= Self.plankTop - s.height && py <= Self.plankTop ? s.index : nil
        }
        return nil
    }
}
