import Foundation

public enum DistanceUnits: String, Equatable, Sendable, CaseIterable {
    case metric, imperial
}

/// A distance split for display: the number (for `.contentTransition(.numericText(value:))`)
/// and its unit.
public struct FormattedDistance: Equatable, Sendable, CustomStringConvertible {
    /// The displayed number, already rounded (e.g. 1.2 for "1.2 km").
    public var value: Double
    /// The number as text, e.g. "1.2", "850", "1,234".
    public var number: String
    /// "m", "km", "ft" or "mi".
    public var unit: String
    /// Unit spelled out for VoiceOver ("metres", "kilometres", "feet", "miles").
    public var spokenUnit: String
    public var description: String { "\(number) \(unit)" }
    public var spoken: String { "\(number) \(spokenUnit)" }
}

/// Deterministic, locale-independent distance rounding (so the tests and the web preview agree):
///
/// | metric             | imperial                    |
/// |--------------------|-----------------------------|
/// | < 100 m: 1 m       | < 0.1 mi: feet, to 10 ft    |
/// | < 1 km: 10 m       | < 10 mi: 0.1 mi             |
/// | < 10 km: 0.1 km    | otherwise: 1 mi, "1,234 mi" |
/// | otherwise: 1 km, "1,234 km" |                    |
///
/// Values that round up to the next band are shown in that band (995 m → "1.0 km").
public enum DistanceFormatting {
    public static let metresPerMile = 1609.344
    public static let feetPerMetre = 3.280839895

    public static func format(metres: Double, units: DistanceUnits = .metric) -> FormattedDistance {
        let m = metres.isFinite ? max(metres, 0) : 0
        switch units {
        case .metric:
            if (m.rounded()) < 100 { return make(m.rounded(), 0, "m", "metres") }
            let tens = (m / 10).rounded() * 10
            if tens < 1000 { return make(tens, 0, "m", "metres") }
            let km = m / 1000
            let tenths = (km * 10).rounded() / 10
            if tenths < 10 { return make(tenths, 1, "km", "kilometres") }
            return make(km.rounded(), 0, "km", "kilometres")
        case .imperial:
            let mi = m / metresPerMile
            let tenths = (mi * 10).rounded() / 10
            if tenths < 0.1 {
                let ft = (m * feetPerMetre / 10).rounded() * 10
                if ft < 528 { return make(ft, 0, "ft", "feet") }
                return make(0.1, 1, "mi", "miles")
            }
            if tenths < 10 { return make(tenths, 1, "mi", "miles") }
            return make(mi.rounded(), 0, "mi", "miles")
        }
    }

    private static func make(_ v: Double, _ digits: Int, _ unit: String, _ spoken: String) -> FormattedDistance {
        let text: String
        if digits == 0 {
            text = grouped(Int(v))
        } else {
            let scaled = Int((v * 10).rounded())
            text = "\(grouped(scaled / 10)).\(scaled % 10)"
        }
        return FormattedDistance(value: v, number: text, unit: unit, spokenUnit: spoken)
    }

    /// "1234567" → "1,234,567".
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
