import Foundation

/// Stable identity of one character in a formatted price.
///
/// Digits are keyed by place (0 is the ones). `"$99"` and `"$100"` share the tens and ones
/// glyphs; a hundreds glyph appears beside them. Grouping commas are keyed by the thousands
/// group they open, so the comma in `"$1,000"` is the same role if the price grows again.
/// The currency mark and an optional leading minus are their own roles.
public enum GlyphRole: Hashable, Sendable, Equatable {
    case sign
    case currency
    case digit(place: Int)
    case separator(group: Int)

    /// Short token shared with the golden trace and the web port (`c`, `s`, `d2`, `g1`).
    public var token: String {
        switch self {
        case .sign: "s"
        case .currency: "c"
        case .digit(let place): "d\(place)"
        case .separator(let group): "g\(group)"
        }
    }
}

/// One character of a formatted price, with the role that keeps its spring across edits.
public struct PriceGlyph: Equatable, Sendable, Identifiable {
    public var id: GlyphRole
    public var character: String

    public init(id: GlyphRole, character: String) {
        self.id = id
        self.character = character
    }
}

/// Fixed US-style price text: a leading minus when needed, then `$`, then digits with `,` groups.
///
/// `NumberFormatter` is locale-dependent, so the core builds the string itself. The same characters
/// and roles are what the web port draws.
public enum PriceGlyphs {
    public static let currencyMark = "$"

    /// Glyphs in reading order. `Int.min` is formatted (its magnitude does not fit in `Int`).
    public static func glyphs(for value: Int) -> [PriceGlyph] {
        var out: [PriceGlyph] = []
        if value < 0 { out.append(PriceGlyph(id: .sign, character: "-")) }
        out.append(PriceGlyph(id: .currency, character: currencyMark))
        let digits = decimalDigits(magnitude(of: value))
        let count = digits.count
        for (index, character) in digits.enumerated() {
            let place = count - 1 - index
            out.append(PriceGlyph(id: .digit(place: place), character: character))
            // The comma sits after a digit whose place is a positive multiple of 3
            // ("1" then "," then "000"), and the group number is place / 3.
            if place > 0, place.isMultiple(of: 3) {
                out.append(PriceGlyph(id: .separator(group: place / 3), character: ","))
            }
        }
        return out
    }

    /// The formatted price, joined from ``glyphs(for:)``.
    public static func string(for value: Int) -> String {
        glyphs(for: value).map(\.character).joined()
    }

    /// Absolute value as `UInt64`, including `Int.min`.
    static func magnitude(of value: Int) -> UInt64 {
        if value >= 0 { return UInt64(value) }
        if value == Int.min { return UInt64(Int.max) &+ 1 }
        return UInt64(-value)
    }

    static func decimalDigits(_ magnitude: UInt64) -> [String] {
        if magnitude == 0 { return ["0"] }
        var n = magnitude
        var digits: [String] = []
        let names = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        while n > 0 {
            digits.append(names[Int(n % 10)])
            n /= 10
        }
        return digits.reversed()
    }
}

/// Inclusive price grid. Legal values are `lower`, `lower + step`, … not past `upper`.
///
/// Bounds are clamped to ±1_000_000_000 and `step` to at least 1, so the grid arithmetic stays
/// inside `Int`. A `ClosedRange` already has its lower bound first.
public struct PriceSpan: Equatable, Sendable {
    public static let domain = 1_000_000_000

    public let lower: Int
    public let upper: Int
    public let step: Int

    public init(range: ClosedRange<Int>, step: Int) {
        let step = min(max(step, 1), Self.domain)
        let lo = min(max(range.lowerBound, -Self.domain), Self.domain)
        let hi = min(max(range.upperBound, -Self.domain), Self.domain)
        self.lower = min(lo, hi)
        self.upper = max(lo, hi)
        self.step = step
    }

    /// Highest value on the grid that is still ≤ ``upper``.
    public var last: Int {
        if upper <= lower { return lower }
        let stepsApart = (upper - lower) / step
        return lower + stepsApart * step
    }

    /// How many legal values the grid holds (at least one).
    public var count: Int { ((last - lower) / step) + 1 }

    public func contains(_ value: Int) -> Bool {
        value >= lower && value <= last && (value - lower).isMultiple(of: step)
    }

    /// Nearest grid value. Halfway cases round away from zero (so Swift and the web port agree;
    /// `Double.rounded()` would use banker's rounding and diverge from `Math.round`).
    public func snap(_ raw: Double) -> Int {
        guard raw.isFinite else { return lower }
        let clamped = min(max(raw, Double(lower)), Double(upper))
        let stepsFromLower = GlyphRound.halfAwayFromZero((clamped - Double(lower)) / Double(step))
        let snapped = lower + stepsFromLower * step
        if snapped < lower { return lower }
        if snapped > last { return last }
        return snapped
    }

    public func snap(_ raw: Int) -> Int { snap(Double(raw)) }

    /// Where `value` sits in 0…1 between ``lower`` and ``upper`` (the track, not just the grid).
    public func fraction(for value: Int) -> Double {
        let span = Double(upper - lower)
        guard span > 0 else { return 0 }
        return WhimsyMath.clamp01(Double(snap(value) - lower) / span)
    }

    /// Snapped value for a 0…1 position along the track.
    public func value(atFraction t: Double) -> Int {
        guard t.isFinite else { return lower }
        let raw = Double(lower) + WhimsyMath.clamp01(t) * Double(upper - lower)
        return snap(raw)
    }

    public func value(atX x: Double, width: Double) -> Int {
        guard width > 0, x.isFinite else { return lower }
        return value(atFraction: x / width)
    }

    public func x(for value: Int, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return fraction(for: value) * width
    }

    /// Grid values crossed when moving from `from` to `to`, in travel order, including `to`
    /// and excluding `from`. Both ends are snapped first. Empty when they land on the same step.
    public func steps(from: Int, to: Int) -> [Int] {
        let start = snap(from)
        let end = snap(to)
        guard start != end else { return [] }
        var value = start
        var out: [Int] = []
        if end > start {
            while value < end {
                value += step
                out.append(value)
            }
        } else {
            while value > end {
                value -= step
                out.append(value)
            }
        }
        return out
    }
}

/// Half-away-from-zero rounding that is a few arithmetic operations, so JS can copy it.
enum GlyphRound {
    /// Widest grid: `domain - (-domain)` with step 1. A step index can be `2 * domain`, so the
    /// clamp is the index, not the price. Clamping to `domain` maps a price of 123 on that grid to 0.
    static let maxIndex = PriceSpan.domain * 2

    static func halfAwayFromZero(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        let clamped = min(max(x, -Double(Self.maxIndex)), Double(Self.maxIndex))
        if clamped >= 0 { return Int(clamped + 0.5) }
        return -Int(-clamped + 0.5)
    }
}
