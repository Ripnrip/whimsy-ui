import Foundation

/// A tiny stateless 32-bit hash, so the scramble is seeded, reproducible and identical in the web port.
public enum AsciiHash {
    public static func mix(_ x: UInt32) -> UInt32 {
        var h = x
        h ^= h >> 16; h = h &* 0x7feb352d
        h ^= h >> 15; h = h &* 0x846ca68b
        h ^= h >> 16
        return h
    }
    public static func hash(_ seed: UInt32, _ a: UInt32, _ b: UInt32) -> UInt32 {
        mix(mix(seed &+ a &* 0x9E3779B1) ^ (b &* 0x85EBCA6B))
    }
    /// 0 ≤ value < 1.
    public static func unit(_ h: UInt32) -> Double { Double(h) / 4294967296.0 }
}

/// Luminance, gamma, the character ramp and the tint.
public enum AsciiRamp {
    /// Dark to bright.
    public static let ramp: [Character] = Array(" .:-=+*#%@")
    /// The scramble draws from the ramp plus punctuation and digits.
    public static let extended: [Character] = Array(" .:-=+*#%@" + "!?/\\|<>[]{}()~^;,_01&$")
    public static let gamma = 0.8
    /// Tint floor: dim cells are brightened so their glyphs still read as their own colour.
    public static let tintFloor = 0.45
    public static let shimmerTintGain = 1.2

    public static func luminance(_ c: AsciiRGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    /// Luminance through the display gamma: what the ramp is indexed with.
    public static func tone(_ c: AsciiRGB) -> Double { pow(WhimsyMath.clamp01(luminance(c)), gamma) }

    public static func index(tone: Double) -> Int {
        let n = ramp.count
        return min(n - 1, max(0, Int((WhimsyMath.clamp01(tone) * Double(n - 1) + 0.5).rounded(.down))))
    }
    public static func glyph(tone: Double) -> Character { ramp[index(tone: tone)] }

    /// The glyph colour: the cell colour scaled so its brightest channel is at least `tintFloor`.
    public static func tint(_ c: AsciiRGB) -> AsciiRGB {
        let k = 1 / max(max(c.r, c.g, c.b), tintFloor)
        return AsciiRGB(min(c.r * k, 1), min(c.g * k, 1), min(c.b * k, 1))
    }

    public static func scaled(_ c: AsciiRGB, by s: Double) -> AsciiRGB {
        AsciiRGB(WhimsyMath.clamp01(c.r * s), WhimsyMath.clamp01(c.g * s), WhimsyMath.clamp01(c.b * s))
    }
}

/// The downsampled cover for one density: colour, tone and tint per cell.
public struct AsciiGrid: Equatable, Sendable {
    public let cols: Int
    public let colors: [AsciiRGB]
    public let tones: [Double]
    public let tints: [AsciiRGB]

    public init(source: AsciiImage, cols: Int) {
        let small = source.downsample(cols: cols, rows: cols)
        self.cols = cols
        colors = small.pixels
        tones = small.pixels.map(AsciiRamp.tone)
        tints = small.pixels.map(AsciiRamp.tint)
    }
}
