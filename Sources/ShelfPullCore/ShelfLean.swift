import Foundation

/// How the neighbours of a pulled book lean into the gap it leaves. Angles are in degrees, positive =
/// clockwise on screen (the top moves right), so books left of the gap are positive and books right of it negative.
public enum ShelfLean {
    public static let maxDegrees = 12.0
    /// Each book further from the gap leans this much of the one before it.
    public static let decay = 0.5
    /// The lean starts at this rise (fraction of the pulled book's height) and is full at `fullFraction`.
    public static let startFraction = 0.05
    public static let fullFraction = 0.38
    /// The nearest neighbour's top may move at most this fraction of the empty slot's width.
    public static let slotUse = 0.85
    /// After a book seats, the neighbours rock once more: amplitude (degrees), decay time and frequency.
    public static let wobbleDegrees = 1.6
    public static let wobbleDecay = 0.12
    public static let wobbleHz = 5.0

    /// 0 ... 1: how far the neighbours have leaned for a book risen `rise` points out of its slot.
    public static func progress(rise: Double, height: Double) -> Double {
        WhimsyMath.smoothstep(startFraction * height, fullFraction * height, rise.isFinite ? rise : 0)
    }

    /// The lean of every book for the book at `lifted` risen `rise` points (0 for the lifted book itself).
    /// Three rules keep it plausible: angles shrink with distance, the nearest neighbour's top never moves further
    /// than the slot is wide, and each book's top moves no further than the top of the one nearer the gap
    /// (plus the gap between books), so leaning books rest against each other and never cross.
    public static func angles(layout: ShelfLayout, lifted: Int, rise: Double) -> [Double] {
        var out = [Double](repeating: 0, count: layout.count)
        guard lifted >= 0, lifted < layout.count else { return out }
        let u = progress(rise: rise, height: layout.spines[lifted].height)
        guard u > 0 else { return out }
        for side in [-1, 1] {
            var previousShift = slotUse * layout.spines[lifted].width
            var previousAngle = maxDegrees
            var k = 1
            while true {
                let i = lifted + side * k
                if i < 0 || i >= layout.count { break }
                let h = layout.spines[i].height
                let raw = maxDegrees * pow(decay, Double(k - 1)) * u
                let shiftCap = k == 1 ? previousShift : previousShift + ShelfLayout.gap
                let cap = asin(min(1, shiftCap / h)) * 180 / Double.pi
                let angle = min(raw, cap, previousAngle)
                previousShift = h * sin(angle * Double.pi / 180)
                previousAngle = angle
                out[i] = Double(-side) * angle
                k += 1
            }
        }
        return out
    }

    /// The rock after seating, for the book `distance` (1, 2, ...) from the one that landed, `t` seconds in.
    public static func wobble(distance: Int, at t: Double) -> Double {
        guard distance >= 1, t > 0, t.isFinite else { return 0 }
        return wobbleDegrees * pow(decay, Double(distance - 1)) * exp(-t / wobbleDecay) * sin(2 * Double.pi * wobbleHz * t)
    }

    /// The corner a leaning book pivots on: the bottom corner nearest the gap (trailing for books that lean right).
    public static func pivotsOnTrailingCorner(_ lean: Double) -> Bool { lean >= 0 }
}
