import Foundation

/// Where a row is in its tick-to-gone sequence.
public enum OctoPhase: Equatable, Sendable {
    case idle, check, swell, grab, pull, collapse, gone
}

/// The per-row timeline, in seconds on the row's own clock (0 = just ticked).
///
/// check → swell → grab → pull, with the collapse starting while the pull is still finishing.
/// Reduce Motion uses `reduced`: a checkmark, a fade and a plain collapse, with no ink.
public struct OctoTiming: Equatable, Sendable {
    public var checkEnd: Double
    public var swellEnd: Double
    public var grabEnd: Double
    public var pullEnd: Double
    public var collapseStart: Double
    public var collapseEnd: Double
    /// The pull progress at which the row starts to fade.
    public var fadeFrom: Double
    public var isReduced: Bool

    public static let full = OctoTiming(checkEnd: 0.25, swellEnd: 0.70, grabEnd: 1.00, pullEnd: 1.55,
                                        collapseStart: 1.30, collapseEnd: 1.80, fadeFrom: 0.30, isReduced: false)
    public static let reduced = OctoTiming(checkEnd: 0.20, swellEnd: 0.20, grabEnd: 0.20, pullEnd: 0.45,
                                           collapseStart: 0.40, collapseEnd: 0.70, fadeFrom: 0, isReduced: true)

    public var total: Double { collapseEnd }
    /// Until the grab starts a tap can still undo the tick; after it the row is committed.
    public var commit: Double { swellEnd }

    public func phase(at clock: Double) -> OctoPhase {
        if clock <= 0 { return .idle }
        if clock >= total { return .gone }
        if clock < checkEnd { return .check }
        if clock < swellEnd { return .swell }
        if clock < grabEnd { return .grab }
        if clock < collapseStart { return .pull }
        return .collapse
    }

    /// 0…1 progress of `clock` between `a` and `b` (a zero-length span is a step).
    public static func progress(_ clock: Double, from a: Double, to b: Double) -> Double {
        b <= a ? (clock >= b ? 1 : 0) : WhimsyMath.clamp01((clock - a) / (b - a))
    }
}
