import Foundation

/// A paper-doll cutout: a rounded silhouette in a generated outfit. Everything is seeded,
/// so the same seed always dresses the same crowd.
public struct FigureSpec: Equatable, Sendable, Identifiable {
    public enum Garment: Int, CaseIterable, Sendable {
        case dress, trench, suit, jumpsuit, skirtSet

        public var name: String {
            switch self {
            case .dress: return "Slip Dress"
            case .trench: return "Trench"
            case .suit: return "Suit"
            case .jumpsuit: return "Jumpsuit"
            case .skirtSet: return "Skirt Set"
            }
        }
    }

    /// Outfit colours as (name, r, g, b). Muted, boutique-ish, no two adjacent alike.
    public static let palette: [(name: String, r: Double, g: Double, b: Double)] = [
        ("Camel", 0.78, 0.60, 0.40), ("Rust", 0.72, 0.31, 0.18), ("Sage", 0.55, 0.64, 0.50),
        ("Cobalt", 0.16, 0.30, 0.78), ("Blush", 0.93, 0.68, 0.66), ("Ink", 0.10, 0.10, 0.13),
        ("Cream", 0.94, 0.90, 0.80), ("Mustard", 0.87, 0.66, 0.16), ("Plum", 0.42, 0.20, 0.36),
        ("Teal", 0.10, 0.45, 0.47), ("Poppy", 0.89, 0.22, 0.20), ("Lilac", 0.70, 0.62, 0.86),
    ]

    public static let skinTones: [(r: Double, g: Double, b: Double)] = [
        (0.98, 0.84, 0.72), (0.92, 0.72, 0.56), (0.78, 0.56, 0.40), (0.58, 0.40, 0.28), (0.40, 0.27, 0.19),
    ]

    /// Model size of a figure at scale 1, in points.
    public static let baseSize = (width: 50.0, height: 120.0)

    public var id: Int
    public var garment: Garment
    public var color: Int        // palette index
    public var accent: Int       // palette index for the bag / scarf, never the outfit colour
    public var skin: Int
    public var hairStyle: Int    // 0 short, 1 bob, 2 bun, 3 long
    public var hairShade: Double // 0 black … 1 light brown
    /// Stance: −1…1 shifts the hips and swings one arm, so the crowd isn't uniform.
    public var stance: Double
    /// Height multiplier 0.92…1.06.
    public var height: Double
    public var price: Int

    public var name: String { "\(Self.palette[color].name) \(garment.name)" }

    public static func generate(id: Int, _ rng: inout SeededRandom) -> FigureSpec {
        let garment = Garment(rawValue: min(Int(rng.uniform(0...5)), 4))!
        let color = min(Int(rng.uniform(0...12)), 11)
        var accent = min(Int(rng.uniform(0...11)), 10)
        if accent >= color { accent += 1 }
        return FigureSpec(id: id, garment: garment, color: color, accent: accent,
                          skin: min(Int(rng.uniform(0...5)), 4),
                          hairStyle: min(Int(rng.uniform(0...4)), 3),
                          hairShade: rng.uniform(0...1),
                          stance: rng.uniform(-1...1),
                          height: rng.uniform(0.92...1.06),
                          price: 120 + 5 * Int(rng.uniform(0...72)))
    }

    /// A crowd of `count` figures. Consecutive figures never share an outfit colour.
    public static func crowd(count: Int, seed: UInt64) -> [FigureSpec] {
        var rng = SeededRandom(seed: seed)
        var out: [FigureSpec] = []
        for i in 0..<max(count, 0) {
            var f = generate(id: i, &rng)
            if let prev = out.last, prev.color == f.color {
                f.color = (f.color + 5) % palette.count
                if f.accent == f.color { f.accent = (f.accent + 1) % palette.count }
            }
            out.append(f)
        }
        return out
    }
}
