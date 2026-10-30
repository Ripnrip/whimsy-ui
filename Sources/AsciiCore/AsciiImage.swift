import Foundation

/// A linear-ish RGB colour, each channel 0…1.
public struct AsciiRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public static func lerp(_ a: AsciiRGB, _ b: AsciiRGB, _ t: Double) -> AsciiRGB {
        AsciiRGB(WhimsyMath.lerp(a.r, b.r, t), WhimsyMath.lerp(a.g, b.g, t), WhimsyMath.lerp(a.b, b.b, t))
    }
}

/// A small RGB raster: the source the ASCII grid is sampled from.
public struct AsciiImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [AsciiRGB]

    public init(width: Int, height: Int, pixels: [AsciiRGB]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: AsciiRGB) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    public subscript(x: Int, y: Int) -> AsciiRGB { pixels[y * width + x] }

    /// Renders `f(u, v)` (unit square, v down) sampled at pixel centres.
    public static func render(width: Int, height: Int, _ f: (Double, Double) -> AsciiRGB) -> AsciiImage {
        var px: [AsciiRGB] = []
        px.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width { px.append(f((Double(x) + 0.5) / Double(width), (Double(y) + 0.5) / Double(height))) }
        }
        return AsciiImage(width: width, height: height, pixels: px)
    }

    /// Area-weighted box filter: every destination cell averages exactly the source area it covers,
    /// including the fractional edge pixels, so any ratio (192 → 48, 192 → 72) resamples cleanly.
    public func downsample(cols: Int, rows: Int) -> AsciiImage {
        precondition(cols > 0 && rows > 0)
        var out: [AsciiRGB] = []
        out.reserveCapacity(cols * rows)
        for j in 0..<rows {
            let y0 = Double(j) * Double(height) / Double(rows), y1 = Double(j + 1) * Double(height) / Double(rows)
            for i in 0..<cols {
                let x0 = Double(i) * Double(width) / Double(cols), x1 = Double(i + 1) * Double(width) / Double(cols)
                var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
                for sy in Int(y0.rounded(.down))..<min(height, Int(y1.rounded(.up))) {
                    let wy = min(y1, Double(sy + 1)) - max(y0, Double(sy))
                    for sx in Int(x0.rounded(.down))..<min(width, Int(x1.rounded(.up))) {
                        let w = (min(x1, Double(sx + 1)) - max(x0, Double(sx))) * wy
                        let p = pixels[sy * width + sx]
                        r += p.r * w; g += p.g * w; b += p.b * w; wsum += w
                    }
                }
                out.append(AsciiRGB(r / wsum, g / wsum, b / wsum))
            }
        }
        return AsciiImage(width: cols, height: rows, pixels: out)
    }
}

/// The procedurally generated cover: a synthwave dusk with a slatted sun, stars and three hill layers.
/// Everything is a formula, so there is no source art.
public enum AsciiCover {
    public static let size = 192
    static let horizon = 0.62
    static let sunCenter = Vec2(0.5, 0.40)
    static let sunRadius = 0.24

    static let skyTop = AsciiRGB(0.10, 0.04, 0.30)
    static let skyMid = AsciiRGB(0.95, 0.25, 0.55)
    static let skyLow = AsciiRGB(1.00, 0.72, 0.25)
    static let sunTop = AsciiRGB(1.00, 0.95, 0.45)
    static let sunBottom = AsciiRGB(1.00, 0.30, 0.45)
    static let hills: [(base: Double, amp: Double, freq: Double, phase: Double, color: AsciiRGB)] = [
        (0.62, 0.035, 1.5, 0.6, AsciiRGB(0.22, 0.10, 0.45)),
        (0.72, 0.040, 2.3, 2.0, AsciiRGB(0.08, 0.28, 0.45)),
        (0.84, 0.035, 3.1, 4.0, AsciiRGB(0.01, 0.02, 0.06)),
    ]

    public static func sky(_ v: Double) -> AsciiRGB {
        let t = WhimsyMath.clamp01(v / horizon)
        return t < 0.6 ? AsciiRGB.lerp(skyTop, skyMid, t / 0.6) : AsciiRGB.lerp(skyMid, skyLow, (t - 0.6) / 0.4)
    }

    /// The cover colour at (u, v) in the unit square, v down.
    public static func color(_ u: Double, _ v: Double) -> AsciiRGB {
        for h in hills.reversed() where v > h.base + h.amp * sin(2 * Double.pi * h.freq * u + h.phase) { return h.color }
        let dx = u - sunCenter.x, dy = v - sunCenter.y
        if (dx * dx + dy * dy).squareRoot() < sunRadius {
            // Slats cut into the lower half of the sun, growing thicker toward the bottom.
            if v > sunCenter.y {
                let k = (v - sunCenter.y) / sunRadius
                let f = ((v - sunCenter.y) / 0.045).truncatingRemainder(dividingBy: 1)
                if f < k * 0.7 { return sky(v) }
            }
            return AsciiRGB.lerp(sunTop, sunBottom, WhimsyMath.clamp01((v - (sunCenter.y - sunRadius)) / (2 * sunRadius)))
        }
        if v < 0.35 {
            let sx = UInt32((u * 96).rounded(.down)), sy = UInt32((v * 96).rounded(.down))
            if AsciiHash.unit(AsciiHash.hash(7, sx, sy)) < 0.012 { return AsciiRGB(1, 1, 1) }
        }
        return sky(v)
    }

    public static func image(size n: Int = size) -> AsciiImage { AsciiImage.render(width: n, height: n, color) }
}
