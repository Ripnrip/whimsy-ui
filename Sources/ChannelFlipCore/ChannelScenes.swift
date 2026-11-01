import Foundation

/// One drawing step of a generated "photo". Coordinates are card points (300 x 420, y down).
public struct ChannelOp: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// A vertical gradient over the whole card, `color` at the top to `color2` at the bottom.
        case gradient
        /// A filled rectangle from `points[0]` to `points[1]`.
        case rect
        /// A filled circle at `points[0]` with radius `size`.
        case circle
        /// A filled polygon.
        case poly
        /// A line from `points[0]` to `points[1]`, `size` points wide.
        case line
        /// A glow: `color` at `alpha` in the middle (`points[0]`) fading to nothing at radius `size`.
        case radial
    }
    public var kind: Kind
    public var points: [Vec2]
    public var size: Double
    public var color: UInt32
    public var color2: UInt32
    public var alpha: Double
}

public struct ChannelScene: Equatable, Sendable {
    public var name: String
    public var ops: [ChannelOp]
}

/// The built-in photos: generated gradients and shapes, so the card works without any assets.
public enum ChannelScenes {
    public static let width = 300.0
    public static let height = 420.0
    public static let names = ["Dune Sunset", "Teal Lagoon", "Night City", "Alpine Dawn", "Neon Grid", "Paper Garden"]
    public static var count: Int { names.count }

    /// A scene by index (wrapped).
    public static func scene(_ i: Int) -> ChannelScene {
        let k = ChannelIndex.wrap(i, count: count)
        let ops: [ChannelOp]
        switch k {
        case 0: ops = dunes()
        case 1: ops = lagoon()
        case 2: ops = city()
        case 3: ops = alps()
        case 4: ops = neon()
        default: ops = garden()
        }
        return ChannelScene(name: names[k], ops: ops)
    }
    public static var all: [ChannelScene] { (0..<count).map(scene) }

    // MARK: building blocks

    /// A deterministic 0…1 value for (index, salt).
    static func rnd(_ i: Int, _ salt: UInt32) -> Double {
        ChannelHash.unit(ChannelHash.hash32((UInt32(truncatingIfNeeded: i) &* 0x9E37_79B1) ^ ChannelHash.hash32(salt)))
    }
    static func gradient(_ top: UInt32, _ bottom: UInt32) -> ChannelOp {
        ChannelOp(kind: .gradient, points: [], size: 0, color: top, color2: bottom, alpha: 1)
    }
    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: UInt32, _ a: Double = 1) -> ChannelOp {
        ChannelOp(kind: .rect, points: [Vec2(x, y), Vec2(x + w, y + h)], size: 0, color: c, color2: c, alpha: a)
    }
    static func circle(_ x: Double, _ y: Double, _ r: Double, _ c: UInt32, _ a: Double = 1) -> ChannelOp {
        ChannelOp(kind: .circle, points: [Vec2(x, y)], size: r, color: c, color2: c, alpha: a)
    }
    static func poly(_ p: [Vec2], _ c: UInt32, _ a: Double = 1) -> ChannelOp {
        ChannelOp(kind: .poly, points: p, size: 0, color: c, color2: c, alpha: a)
    }
    static func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ w: Double, _ c: UInt32, _ a: Double = 1) -> ChannelOp {
        ChannelOp(kind: .line, points: [Vec2(x0, y0), Vec2(x1, y1)], size: w, color: c, color2: c, alpha: a)
    }
    static func glow(_ x: Double, _ y: Double, _ r: Double, _ c: UInt32, _ a: Double) -> ChannelOp {
        ChannelOp(kind: .radial, points: [Vec2(x, y)], size: r, color: c, color2: c, alpha: a)
    }
    /// A wavy hill: the polygon under `base + amp * sin(freq * x + phase)`, sampled every 6 points, down to the card bottom.
    static func ridge(base: Double, amp: Double, freq: Double, phase: Double, _ c: UInt32) -> ChannelOp {
        var p: [Vec2] = [Vec2(0, height)]
        var x = 0.0
        while x < width { p.append(Vec2(x, base + amp * sin(freq * x + phase))); x += 6 }
        p.append(Vec2(width, base + amp * sin(freq * width + phase)))
        p.append(Vec2(width, height))
        return poly(p, c)
    }

    // MARK: scenes

    static func dunes() -> [ChannelOp] {
        var o: [ChannelOp] = [gradient(0x4A2C7A, 0xFF9E5E),
                              glow(150, 232, 170, 0xFFE9A8, 0.55),
                              circle(150, 232, 54, 0xFFE9A8)]
        for i in 0..<14 {
            o.append(circle(300 * rnd(i, 41), 120 * rnd(i, 42), 0.7 + 0.8 * rnd(i, 43), 0xFFFFFF, 0.3 + 0.5 * rnd(i, 44)))
        }
        for i in 0..<3 {
            let x = 70 + 70 * Double(i) + 10 * rnd(i, 45), y = 150 + 26 * rnd(i, 46)
            o.append(line(x - 7, y - 3, x, y, 1.6, 0x2A1740, 0.8))
            o.append(line(x, y, x + 7, y - 3, 1.6, 0x2A1740, 0.8))
        }
        o.append(ridge(base: 268, amp: 14, freq: 0.018, phase: 0.0, 0xD9693F))
        o.append(ridge(base: 308, amp: 18, freq: 0.013, phase: 1.7, 0xA8432F))
        for i in 0..<8 {
            let y = 322 + 8.5 * Double(i), w = 40 + 90 * rnd(i, 47), x = 300 * rnd(i, 48) - 20
            o.append(line(x, y, x + w, y, 1.4, 0xFFB98A, 0.22))
        }
        o.append(ridge(base: 356, amp: 16, freq: 0.020, phase: 3.1, 0x6E2A2E))
        return o
    }

    static func lagoon() -> [ChannelOp] {
        var o: [ChannelOp] = [gradient(0x9AD9E8, 0xE9F6F0),
                              circle(226, 84, 22, 0xFFFBE8),
                              poly([Vec2(0, 262), Vec2(70, 170), Vec2(120, 222), Vec2(190, 138), Vec2(260, 214), Vec2(300, 186), Vec2(300, 270), Vec2(0, 270)], 0x3E7C8C),
                              poly([Vec2(0, 290), Vec2(90, 226), Vec2(160, 274), Vec2(230, 210), Vec2(300, 276), Vec2(300, 310), Vec2(0, 310)], 0x2A5F6E),
                              rect(0, 270, 300, 150, 0x2C8FA6)]
        for i in 0..<9 {
            let y = 286 + Double(i) * 14
            let w = 60 + 120 * rnd(i, 11), x = 20 + (260 - w) * rnd(i, 12)
            o.append(line(x, y, x + w, y, 2, 0xFFFFFF, 0.25))
        }
        return o
    }

    static func city() -> [ChannelOp] {
        var o: [ChannelOp] = [gradient(0x0B1030, 0x3B2A6B), glow(225, 80, 90, 0xFFF3C4, 0.3), circle(225, 80, 26, 0xFFF3C4)]
        for i in 0..<36 {
            o.append(circle(300 * rnd(i, 21), 170 * rnd(i, 22), 0.8 + 0.8 * rnd(i, 23), 0xFFFFFF, 0.35 + 0.5 * rnd(i, 24)))
        }
        for col in 0..<9 {
            let x = Double(col) * 33.4 - 2
            let h = 90 + 150 * rnd(col, 31)
            let top = 420 - h
            o.append(rect(x, top, 31, h + 2, col % 2 == 0 ? 0x151A3F : 0x1E2352))
            for r in 0..<8 {
                for c in 0..<3 {
                    let k = col * 24 + r * 3 + c
                    if rnd(k, 32) < 0.45 { o.append(rect(x + 4 + Double(c) * 9, top + 8 + Double(r) * 14, 5, 7, 0xFFD36B, 0.85)) }
                }
            }
        }
        return o
    }

    static func alps() -> [ChannelOp] {
        var o: [ChannelOp] = [gradient(0x2E4A8C, 0xFFC2A8),
                              glow(95, 252, 120, 0xFFF1D0, 0.5),
                              circle(95, 252, 30, 0xFFF1D0)]
        for i in 0..<12 {
            o.append(circle(300 * rnd(i, 51), 110 * rnd(i, 52), 0.7 + 0.7 * rnd(i, 53), 0xFFFFFF, 0.25 + 0.5 * rnd(i, 54)))
        }
        for i in 0..<3 {
            let x = 40 + 100 * Double(i) + 20 * rnd(i, 55), y = 110 + 40 * rnd(i, 56)
            o.append(circle(x, y, 14, 0xFFFFFF, 0.28))
            o.append(circle(x + 16, y + 3, 11, 0xFFFFFF, 0.28))
            o.append(circle(x - 14, y + 4, 10, 0xFFFFFF, 0.28))
        }
        o.append(poly([Vec2(0, 300), Vec2(60, 200), Vec2(110, 250), Vec2(170, 150), Vec2(240, 240), Vec2(300, 190), Vec2(300, 420), Vec2(0, 420)], 0x6D7FB5))
        o.append(poly([Vec2(170, 150), Vec2(150, 186), Vec2(164, 182), Vec2(172, 196), Vec2(184, 180), Vec2(194, 186)], 0xFFFFFF, 0.9))
        o.append(poly([Vec2(60, 200), Vec2(46, 228), Vec2(58, 224), Vec2(66, 234), Vec2(76, 222)], 0xFFFFFF, 0.8))
        o.append(poly([Vec2(0, 350), Vec2(80, 262), Vec2(140, 330), Vec2(210, 250), Vec2(300, 340), Vec2(300, 420), Vec2(0, 420)], 0x3C4B7A))
        o.append(poly([Vec2(210, 250), Vec2(192, 280), Vec2(206, 276), Vec2(214, 290), Vec2(226, 274), Vec2(234, 280)], 0xFFFFFF, 0.9))
        o.append(poly([Vec2(0, 392), Vec2(300, 372), Vec2(300, 420), Vec2(0, 420)], 0x232B52))
        for i in 0..<9 {
            let x = 14 + 33 * Double(i) + 8 * rnd(i, 57), base = 394 - 2.25 * Double(i) + 6 * rnd(i, 58), h = 28 + 22 * rnd(i, 59)
            o.append(poly([Vec2(x, base - h), Vec2(x - 9, base), Vec2(x + 9, base)], 0x161C3C))
        }
        return o
    }

    static func neon() -> [ChannelOp] {
        var o: [ChannelOp] = [gradient(0x12002B, 0x4B0F6B), glow(150, 215, 150, 0xFF4FA3, 0.45), circle(150, 215, 70, 0xFF6FB5)]
        for i in 0..<6 {
            let h = 2.0 + Double(i) * 1.6
            o.append(rect(70, 232 + Double(i) * 8.5, 160, h, 0x2A0A4A))
        }
        o.append(rect(0, 262, 300, 158, 0x12002B))
        for i in 0...8 { o.append(line(150, 262, -150 + 75 * Double(i), 420, 1.2, 0x35F0FF, 0.8)) }
        for k in 1...6 {
            let t = Double(k) / 6
            o.append(line(0, 262 + 158 * t * t, 300, 262 + 158 * t * t, 1.2, 0x35F0FF, 0.8))
        }
        o.append(line(0, 262, 300, 262, 2, 0xFF6FB5, 0.9))
        return o
    }

    static func garden() -> [ChannelOp] {
        let colors: [UInt32] = [0xE4573D, 0xF0B429, 0x7CCBA2, 0x4F7FD0, 0xF2A7BC]
        var o: [ChannelOp] = [gradient(0xF6EEDC, 0xEBDDBF)]
        for i in 0..<14 {
            let x = 24 + 252 * rnd(i, 41), y = 110 + 220 * rnd(i, 42)
            o.append(line(x, y, x + 6 * (rnd(i, 43) - 0.5), 420, 2, 0x5E8F5A, 0.8))
        }
        for i in 0..<14 {
            let x = 24 + 252 * rnd(i, 41), y = 110 + 220 * rnd(i, 42)
            let r = 9 + 9 * rnd(i, 44)
            let c = colors[Int(rnd(i, 45) * 5.999) % 5]
            for p in 0..<5 {
                let a = Double(p) * 2 * Double.pi / 5 + rnd(i, 46) * 6.28
                o.append(circle(x + r * 0.95 * cos(a), y + r * 0.95 * sin(a), r * 0.62, c, 0.95))
            }
            o.append(circle(x, y, r * 0.5, 0xFFF3C4))
        }
        return o
    }
}
