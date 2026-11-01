import Foundation

/// A colour, 0…1 per channel.
public struct ChannelRGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

/// The CRT channel-change look, mirrored line for line from `ChannelFlip.metal` and the web port, so the
/// pixel maths can be tested on Linux. Positions and sizes are in card points. Every function is
/// deterministic: the same seed and frame always draw the same tears.
public enum ChannelFlipShading {
    // Constants: keep in sync with ChannelFlip.metal (a test checks the two match).
    /// Rows move together in bands this tall (points).
    public static let bandHeight = 7.0
    /// The biggest sideways tear, as a fraction of the card width, at full intensity.
    public static let maxShift = 0.14
    /// Fraction of bands that tear at zero intensity, and how much more at full intensity.
    public static let bandChance = 0.3
    public static let bandChanceGain = 0.6
    /// Red goes left and blue goes right by this fraction of the width at full intensity.
    public static let split = 0.04
    /// The white flash at full intensity, and the brightness gain.
    public static let flash = 0.55
    public static let gain = 0.3
    /// Static noise: strength, and the size of its cells (points).
    public static let noise = 0.35
    public static let noiseCell = 2.0
    /// Alternate 2-point rows dim by this much at full intensity (scanlines).
    public static let scanDepth = 0.12
    public static let scanRow = 2.0
    /// The head-switch bar that rolls down the card with progress: half-height as a fraction of the height,
    /// and how much more it tears and crackles.
    public static let barHalf = 0.07
    public static let barBoost = 1.5

    /// Horizontal position wrapped into 0..<width, like a TV losing horizontal hold.
    public static func wrapX(_ x: Double, width: Double) -> Double { x - width * floor(x / width) }

    /// How inside the rolling bar a row is, 0…1.
    public static func bar(y: Double, progress: Double, height: Double) -> Double {
        1 - WhimsyMath.smoothstep(0, barHalf * height, abs(y - progress * height))
    }

    /// Sideways offset of one band (points), signed. Deterministic in (band, seed). `forced` makes it always tear.
    public static func bandOffset(band: Int, seed: Double, intensity: Double, width: Double, forced: Bool = false) -> Double {
        if !(intensity > 0) { return 0 }
        let s = ChannelHash.hash32(seedBits(seed))
        let h = ChannelHash.hash32((UInt32(truncatingIfNeeded: band) &* 0x9E37_79B1) ^ s)
        let active = forced || ChannelHash.unit(ChannelHash.hash32(h ^ 0xA511_E9B3)) < bandChance + bandChanceGain * intensity
        return active ? (2 * ChannelHash.unit(h) - 1) * maxShift * width * intensity : 0
    }

    /// A seed as the integer the hashes use (0 when not finite).
    static func seedBits(_ seed: Double) -> UInt32 { seed.isFinite && abs(seed) < 1e15 ? UInt32(truncatingIfNeeded: Int(seed)) : 0 }

    /// The red/blue separation in points at an intensity.
    public static func splitAmount(intensity: Double, width: Double) -> Double { intensity * split * width }

    /// How much white is mixed in, 0…`flash`.
    public static func flashAmount(intensity: Double) -> Double { flash * intensity * intensity }

    /// Row dimming factor for scanlines (odd rows dim).
    public static func scanFactor(row: Int, intensity: Double) -> Double { row & 1 == 1 ? 1 - scanDepth * intensity : 1 }

    /// Noise value 0…1 for a cell on one frame.
    public static func noiseValue(cellX: Int, cellY: Int, seed: Double) -> Double {
        let s = ChannelHash.hash32(seedBits(seed) &+ 0x77)
        let h = (UInt32(truncatingIfNeeded: cellX) &* 0x1F12_3BB5) ^ (UInt32(truncatingIfNeeded: cellY) &* 0x9E37_79B1) ^ s
        return ChannelHash.unit(ChannelHash.hash32(h))
    }

    /// The colour of the pixel at `p`, sampling the unaffected picture through `sample` (points in, colour out).
    public static func shade(at p: Vec2, size: Vec2, progress: Double, intensity: Double, seed: Double, noiseAmount: Double,
                             sample: (Vec2) -> ChannelRGB) -> ChannelRGB {
        let band = Int(floor(p.y / bandHeight))
        let bar = bar(y: p.y, progress: progress, height: size.y)
        let boost = 1 + barBoost * bar
        let dx = bandOffset(band: band, seed: seed, intensity: intensity, width: size.x, forced: bar > 0.5) * boost
        let sp = splitAmount(intensity: intensity, width: size.x)
        let x0 = p.x + dx
        let cr = sample(Vec2(wrapX(x0 - sp, width: size.x), p.y)).r
        let cg = sample(Vec2(wrapX(x0, width: size.x), p.y)).g
        let cb = sample(Vec2(wrapX(x0 + sp, width: size.x), p.y)).b
        var c = ChannelRGB(cr, cg, cb)
        let scan = scanFactor(row: Int(floor(p.y / scanRow)), intensity: intensity)
        let g = (1 + gain * intensity) * scan
        c = ChannelRGB(c.r * g, c.g * g, c.b * g)
        let n = noiseValue(cellX: Int(floor(p.x / noiseCell)), cellY: Int(floor(p.y / noiseCell)), seed: seed)
        let nz = (n - 0.5) * 2 * noise * noiseAmount * intensity * boost
        c = ChannelRGB(WhimsyMath.clamp01(c.r + nz), WhimsyMath.clamp01(c.g + nz), WhimsyMath.clamp01(c.b + nz))
        let f = flashAmount(intensity: intensity)
        return ChannelRGB(WhimsyMath.clamp01(c.r + (1 - c.r) * f), WhimsyMath.clamp01(c.g + (1 - c.g) * f), WhimsyMath.clamp01(c.b + (1 - c.b) * f))
    }
}
