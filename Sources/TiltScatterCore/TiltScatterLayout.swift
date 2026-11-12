import Foundation

/// Paper-tray geometry and the portable glyph metrics. Homes are centres of each
/// letter chip. The SwiftUI view and the web preview both read these constants;
/// nothing here asks Core Text, so Linux lays a line out the same way.
public enum TiltScatterLayout {
    public static let cardWidth = 360.0
    public static let cardHeight = 600.0

    public static let rowX = 16.0
    public static let rowWidth = 328.0
    public static let rowHeight = 48.0
    public static let rowGap = 6.0
    public static let listTop = 92.0
    public static let titleInset = 46.0
    public static let titleRightPad = 12.0
    public static let fontSize = 16.0
    public static let chipHeight = 20.0
    public static let chipMinWidth = 10.0
    public static let rowCorner = 14.0
    public static let chipCorner = 5.0
    public static let checkbox = 22.0

    public static let buttonTop = 368.0
    public static let buttonHeight = 40.0
    public static let trayTop = 420.0
    public static let trayHeight = 164.0

    /// Edges the disk *rim* may not cross. Centres stay one radius inside.
    public static let boundLeft = 22.0
    public static let boundRight = 338.0
    public static let boundTop = 80.0
    public static let boundBottom = 578.0

    public static let collisionRadius = 7.5
    /// A chip may pass through its own word until it has dropped this far.
    public static let fallenGap = 26.0

    public static func rowTop(_ index: Int) -> Double {
        listTop + Double(index) * (rowHeight + rowGap)
    }

    public static func rowCenterY(_ index: Int) -> Double {
        rowTop(index) + rowHeight / 2
    }

    public static func isGap(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty && character.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    /// Advance in ems for one scalar. Unknown scalars, including emoji, take a full em.
    public static func unitAdvance(_ scalar: Unicode.Scalar) -> Double {
        switch scalar {
        case " ", "\t", "\n": return 0.33
        case "i", "l", "I", "j", "!", "|", "'": return 0.28
        case "f", "t", "r", ".", ",", ":", ";": return 0.36
        case "m", "w", "M", "W": return 0.86
        case "J", "c", "s", "z": return 0.48
        case "A"..."Z": return 0.70
        default: return 0.56
        }
    }

    public static func unitAdvance(_ character: Character) -> Double {
        let scalars = Array(character.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first else { return 1 }
        return unitAdvance(scalar)
    }

    /// Glyph chips for one title, in reading order. Spaces advance the pen and make no chip.
    /// A line wider than the row is scaled down so the last chip stays inside the card.
    public static func glyphs(title: String, row: Int) -> [TiltScatterGlyph] {
        let maxWidth = rowWidth - titleInset - titleRightPad
        var parts: [(String, Double, Bool)] = []
        var total = 0.0
        for character in title {
            let advance = fontSize * unitAdvance(character)
            parts.append((String(character), advance, isGap(character)))
            total += advance
        }
        let scale = (total > maxWidth && total > 0) ? maxWidth / total : 1.0
        var pen = rowX + titleInset
        let y = rowCenterY(row)
        var chips: [TiltScatterGlyph] = []
        var index = 0
        for (glyph, advance, gap) in parts {
            let width = advance * scale
            if !gap {
                let chipWidth = min(width, max(chipMinWidth, width - 1.2))
                chips.append(TiltScatterGlyph(
                    row: row,
                    index: index,
                    glyph: glyph,
                    home: Vec2(pen + width * 0.5, y),
                    width: chipWidth
                ))
                index += 1
            }
            pen += width
        }
        return chips
    }

    /// Paper speckles, seeded, so the view and the web preview grain the same sheet.
    public static func grain(count: Int = 42, seed: UInt64 = 0x6A11) -> [Vec2] {
        guard count > 0 else { return [] }
        var rng = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            Vec2(rng.uniform(0...cardWidth), rng.uniform(0...cardHeight))
        }
    }
}

public struct TiltScatterGlyph: Equatable, Sendable {
    public var row: Int
    public var index: Int
    public var glyph: String
    public var home: Vec2
    public var width: Double
    public init(row: Int, index: Int, glyph: String, home: Vec2, width: Double) {
        self.row = row
        self.index = index
        self.glyph = glyph
        self.home = home
        self.width = width
    }
}

/// Ink on warm paper. Components are 0…1 so SwiftUI and the canvas port share them.
public enum TiltScatterPalette {
    public static let paper = RGB(0.965, 0.941, 0.894)
    public static let ink = RGB(0.122, 0.133, 0.165)
    public static let card = RGB(1.0, 0.988, 0.965)
    public static let wax = RGB(0.725, 0.196, 0.165)
    public static let chip = RGB(1.0, 0.976, 0.941)
    public static let tray = RGB(0.918, 0.878, 0.808)
    public static let rule = RGB(0.55, 0.48, 0.38)
}

public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}
