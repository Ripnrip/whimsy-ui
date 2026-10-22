import Foundation

/// The eight named phases of the Moon, a 0..1 lunation apart by 1/8.
public enum MoonPhaseName: Int, CaseIterable, Sendable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous, fullMoon, waningGibbous, lastQuarter, waningCrescent

    /// Where the phase sits in the cycle: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
    public var fraction: Double { Double(rawValue) / 8 }

    public var title: String {
        switch self {
        case .newMoon: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .fullMoon: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        }
    }

    public var emoji: String { ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"][rawValue] }

    /// The named phase nearest to `phase` (any real number; it is wrapped first).
    public static func nearest(to phase: Double) -> MoonPhaseName {
        let i = Int((MoonMath.wrap(phase) * 8).rounded()) % 8
        return MoonPhaseName(rawValue: i)!
    }

    /// The unwrapped phase of the nearest named phase to an unwrapped `phase`, so a snap never
    /// takes the long way round (0.97 snaps to 1.0, not back to 0.0).
    public static func snapTarget(near phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        return (phase * 8).rounded() / 8
    }

    /// The unwrapped representative of `name` closest to an unwrapped `phase`.
    public static func unwrapped(_ name: MoonPhaseName, near phase: Double) -> Double {
        guard phase.isFinite else { return name.fraction }
        return name.fraction + ((phase - name.fraction)).rounded()
    }
}

public enum MoonMath {
    /// The synodic month in days.
    public static let synodicMonth = 29.530_588

    /// Wraps any phase into [0, 1); non-finite input gives 0.
    public static func wrap(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let r = phase - phase.rounded(.down)
        return r >= 1 ? 0 : r
    }

    /// The terminator's signed x-radius, `r·cos(2π·phase)`: r at new moon (the terminator lies on
    /// the lit limb, nothing shows), 0 at the quarters (a straight line), −r at full.
    public static func terminatorXRadius(radius r: Double, phase: Double) -> Double {
        r * cos(2 * .pi * wrap(phase))
    }

    /// Fraction of the disc that is lit, (1 − cos 2πp) / 2.
    public static func illumination(_ phase: Double) -> Double {
        (1 - cos(2 * .pi * wrap(phase))) / 2
    }

    /// True from new to full (the lit side is on the right, as seen from the northern hemisphere).
    public static func isWaxing(_ phase: Double) -> Bool { wrap(phase) < 0.5 }

    /// Faint earthshine on the dark disc: strongest at new moon and gone by the quarters.
    public static func earthshine(_ phase: Double, strength: Double = 0.32) -> Double {
        strength * pow(max(cos(2 * .pi * wrap(phase)), 0), 3)
    }

    /// Days since new moon.
    public static func age(_ phase: Double) -> Double { wrap(phase) * synodicMonth }

    /// The lit region as a closed outline centred on the origin (y down): the limb semicircle on
    /// the lit side, then back along the terminator half-ellipse. Empty at exact new moon.
    public static func litOutline(phase: Double, radius r: Double, samples: Int = 64) -> [Vec2] {
        let p = wrap(phase), n = max(samples, 4)
        let rx = terminatorXRadius(radius: r, phase: p)
        if rx >= r - 1e-9 { return [] }
        let side: Double = isWaxing(p) ? 1 : -1
        var pts: [Vec2] = []
        pts.reserveCapacity(2 * n + 2)
        // Limb: top (−r) to bottom (+r) along the lit side.
        for i in 0...n {
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(n)
            pts.append(Vec2(side * r * cos(a), r * sin(a)))
        }
        // Terminator: bottom back to top. Waxing: x = rx·cos a; waning: x = −rx·cos a.
        for i in 1..<n {
            let a = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            pts.append(Vec2(side * rx * cos(a), r * sin(a)))
        }
        return pts
    }

    /// Shoelace area (absolute value).
    public static func area(of p: [Vec2]) -> Double {
        guard p.count > 2 else { return 0 }
        var a = 0.0
        for i in p.indices { a += p[i].cross(p[(i + 1) % p.count]) }
        return abs(a) / 2
    }
}

/// Formats the readout under the moon.
public enum MoonFormatting {
    /// Whole-percent illumination, "0%"…"100%", never "100%" unless it rounds there.
    public static func percentLit(_ phase: Double) -> Int { Int((MoonMath.illumination(phase) * 100).rounded()) }
    /// "Day 7 of 29.5".
    public static func age(_ phase: Double) -> String {
        "Day \(Int(MoonMath.age(phase).rounded(.down))) of 29.5"
    }
}
