import Foundation

/// A linear RGB triple (0…1 per channel, not clamped).
public struct HoloRGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public static func + (a: HoloRGB, b: HoloRGB) -> HoloRGB { HoloRGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func * (a: HoloRGB, s: Double) -> HoloRGB { HoloRGB(a.r * s, a.g * s, a.b * s) }
}

/// The holographic foil, mirrored line for line from `HoloFoil.metal` (and the web port), so the
/// colour math can be tested on Linux. Positions are card points, `size` is the card size, and
/// `tilt` is the normalised tilt (−1…1, yaw then pitch) from `HoloTilt.normalized`.
public enum HoloShading {
    // Constants: keep in sync with HoloFoil.metal (a test checks the two match).
    /// How far (card-diagonal units) the band travels from the centre at full tilt.
    public static let sweep = 0.7
    public static let yawWeight = 0.6
    public static let pitchWeight = 0.4
    /// Gaussian half-width of the diffraction band.
    public static let bandWidth = 0.16
    public static let bandStrength = 0.55
    /// Rainbow cycles across one band width, so the band shows a full spectrum.
    public static let hueSpread = 0.35
    public static let foilStrength = 0.08
    public static let glareStrength = 0.22
    public static let glareSize = 0.08
    /// Sparkle grid cell (points), the fraction of cells that hold a sparkle, and the angle window radius.
    public static let sparkleCell = 14.0
    public static let sparkleDensity = 0.5
    public static let sparkleWindow = 0.35
    public static let sparkleStrength = 0.9

    /// The axis the band sweeps along: a shallow diagonal, normalize(1, 0.6).
    public static var bandAxis: Vec2 { Vec2(1, 0.6).normalized }

    /// Band centre along `bandAxis`, relative to the card centre (0 = dead centre).
    public static func bandPosition(tilt n: Vec2) -> Double {
        sweep * (yawWeight * n.x - pitchWeight * n.y)
    }

    /// Where a pixel sits along the band axis, relative to the card centre.
    public static func axisCoordinate(_ uv: Vec2) -> Double {
        (uv - Vec2(0.5, 0.5)).dot(bandAxis)
    }

    /// Band intensity 0…1 at a given offset (in band widths) from the band centre.
    public static func bandIntensity(offset x: Double) -> Double { exp(-x * x) }

    /// The cosine rainbow palette used everywhere: hue 0 is red, cycling with period 1.
    public static func rainbow(_ hue: Double) -> HoloRGB {
        let t = 2 * Double.pi
        return HoloRGB(0.5 + 0.5 * cos(t * hue), 0.5 + 0.5 * cos(t * (hue + 0.33)), 0.5 + 0.5 * cos(t * (hue + 0.67)))
    }

    /// Centre of the soft white glare, which slides opposite the tilt.
    public static func glareCenter(tilt n: Vec2) -> Vec2 { Vec2(0.5 - 0.45 * n.x, 0.5 + 0.45 * n.y) }

    // MARK: Sparkles

    /// lowbias32, identical in Metal (uint), Swift (UInt32 wrapping) and JS (Math.imul).
    public static func hash32(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x = x &* 0x7feb_352d
        x ^= x >> 15; x = x &* 0x846c_a68b
        x ^= x >> 16
        return x
    }
    public static func unit(_ x: UInt32) -> Double { Double(x & 0xFF_FFFF) / 16_777_216 }

    public struct Sparkle: Equatable, Sendable {
        /// Sparkle centre in card points.
        public var point: Vec2
        /// The tilt (normalised) at which it shines brightest.
        public var window: Vec2
        public var radius: Double
    }

    /// The sparkle in grid cell (cx, cy), if that cell has one.
    public static func sparkle(cellX cx: Int, cellY cy: Int) -> Sparkle? {
        guard cx >= 0, cy >= 0 else { return nil }
        let base = hash32(UInt32(truncatingIfNeeded: cx) &+ hash32(UInt32(truncatingIfNeeded: cy) &+ 0x9E37))
        guard unit(base) < sparkleDensity else { return nil }
        let ox = 0.2 + 0.6 * unit(hash32(base ^ 1)), oy = 0.2 + 0.6 * unit(hash32(base ^ 2))
        let wx = 2 * unit(hash32(base ^ 3)) - 1, wy = 2 * unit(hash32(base ^ 4)) - 1
        let r = 3 + 3 * unit(hash32(base ^ 5))
        return Sparkle(point: Vec2((Double(cx) + ox) * sparkleCell, (Double(cy) + oy) * sparkleCell), window: Vec2(wx, wy), radius: r)
    }

    /// 0…1: how strongly a sparkle with this angle window lights at this tilt. It only lights inside the window.
    public static func sparkleGate(window: Vec2, tilt n: Vec2) -> Double {
        1 - WhimsyMath.smoothstep(sparkleWindow * 0.4, sparkleWindow, (n - window).length)
    }

    /// A four-pointed glint: a bright core plus horizontal and vertical arms.
    public static func glint(offset d: Vec2, radius r: Double) -> Double {
        let ax = abs(d.x), ay = abs(d.y)
        let core = exp(-(d.dot(d)) / (1.4 * 1.4))
        let arms = exp(-ay / 0.8) * max(0, 1 - ax / r) + exp(-ax / 0.8) * max(0, 1 - ay / r)
        return core + 0.6 * arms
    }

    /// Total sparkle light at a point (3×3 neighbouring cells, so glints can cross cell edges).
    public static func sparkleLight(at p: Vec2, tilt n: Vec2) -> Double {
        let cx = Int(floor(p.x / sparkleCell)), cy = Int(floor(p.y / sparkleCell))
        var total = 0.0
        for j in -1...1 {
            for i in -1...1 {
                guard let s = sparkle(cellX: cx + i, cellY: cy + j) else { continue }
                let g = sparkleGate(window: s.window, tilt: n)
                if g <= 0 { continue }
                total += g * glint(offset: p - s.point, radius: s.radius)
            }
        }
        return total
    }

    /// The light the foil adds at a pixel (before premultiplying by coverage).
    public static func foilLight(at p: Vec2, size: Vec2, tilt: Vec2) -> HoloRGB {
        let n = Vec2(max(-1, min(1, tilt.x)), max(-1, min(1, tilt.y)))
        let uv = Vec2(p.x / size.x, p.y / size.y)
        let x = (axisCoordinate(uv) - bandPosition(tilt: n)) / bandWidth
        let band = bandIntensity(offset: x)
        let hue = x * hueSpread + 0.15 * (n.x + n.y) + 0.25 * uv.y
        let foilHue = 0.6 * (uv.x + uv.y) + 0.3 * n.x - 0.2 * n.y
        let g = uv - glareCenter(tilt: n)
        let glare = glareStrength * exp(-g.dot(g) / glareSize)
        let sp = sparkleStrength * sparkleLight(at: p, tilt: n)
        return rainbow(hue) * (bandStrength * band) + rainbow(foilHue) * foilStrength
            + HoloRGB(glare, glare, glare) + HoloRGB(1, 0.97, 0.9) * sp
    }

    /// The shader: premultiplied colour in, premultiplied colour out (additive light, capped at coverage).
    public static func shade(_ color: HoloRGB, alpha a: Double, at p: Vec2, size: Vec2, tilt n: Vec2, strength: Double = 1) -> HoloRGB {
        guard a > 0 else { return color }
        let l = foilLight(at: p, size: size, tilt: n) * (strength * a)
        return HoloRGB(min(color.r + l.r, a), min(color.g + l.g, a), min(color.b + l.b, a))
    }
}
