import Foundation

/// The slow brightness breathing: a sine wave whose phase varies across the art.
public struct AsciiShimmer: Equatable, Sendable {
    public var amplitude = 0.14
    public var period = 5.0
    public var kx = 7.0
    public var ky = 4.5
    public init() {}

    /// Phase at the unit-square point (u, v) and time t.
    public func phase(u: Double, v: Double, t: Double) -> Double {
        2 * Double.pi * t / period + kx * u + ky * v + 1.2 * sin(2 * Double.pi * 1.5 * v)
    }
    /// Brightness offset in `-amplitude…amplitude`, scaled by `energy` (0 = still).
    public func value(u: Double, v: Double, t: Double, energy: Double) -> Double {
        amplitude * energy * sin(phase(u: u, v: v, t: t))
    }
}

public enum AsciiCellState: Equatable, Sendable {
    /// Showing its true glyph.
    case calm
    /// Showing a random glyph.
    case scrambled
    /// Just resolved: `flash` fades from 1 to 0 over `flashDuration`.
    case settled(flash: Double)
}

/// The tap's scramble → resolve timeline. Cells start scrambling a moment after the tap in a wave from
/// the tap point, hold, then resolve in a second wave from the same point, each with a little jitter.
public enum AsciiScramble {
    public static let onset = 0.15
    public static let hold = 0.30
    public static let wave = 0.85
    public static let jitter = 0.12
    public static let flashDuration = 0.18
    public static let flashGain = 0.5
    /// Random glyph changes per second.
    public static let rate = 24.0

    /// When the whole thing is over (every cell resolved and its flash faded).
    public static var total: Double { hold + wave + jitter + flashDuration }

    public static func startDelay(distance d: Double) -> Double { onset * d }
    public static func resolveTime(distance d: Double, jitter h: Double) -> Double { hold + wave * d + jitter * h }

    /// The farthest corner of the unit square from `origin`, so distance 1 is the far corner.
    public static func maxDistance(from origin: Vec2) -> Double {
        [Vec2(0, 0), Vec2(1, 0), Vec2(0, 1), Vec2(1, 1)].map { $0.distance(to: origin) }.max() ?? 1
    }

    public static func state(elapsed e: Double, distance d: Double, jitter h: Double) -> AsciiCellState {
        if e < startDelay(distance: d) { return .calm }
        let r = resolveTime(distance: d, jitter: h)
        if e < r { return .scrambled }
        let k = e - r
        return .settled(flash: k < flashDuration ? 1 - k / flashDuration : 0)
    }

    /// A seeded random index into the extended glyph set, new every `1 / rate` seconds.
    public static func randomGlyphIndex(seed: UInt32, epoch: Int, cell: Int, elapsed e: Double) -> Int {
        let step = UInt32(max(0, (e * rate).rounded(.down)))
        let key = AsciiHash.hash(seed, UInt32(truncatingIfNeeded: epoch), 7)
        return Int(AsciiHash.hash(key, UInt32(truncatingIfNeeded: cell), step) % UInt32(AsciiRamp.extended.count))
    }
}

/// Maps the vertical drag to a column count, and back to type sizes.
public enum AsciiDensity {
    public static let minColumns = 24
    public static let maxColumns = 72
    public static let defaultColumns = 48
    /// A drag this long (points) sweeps the whole range.
    public static let dragRange = 260.0
    /// Glyph font size relative to the cell.
    public static let glyphScale = 1.3
    /// The accessibility action's step.
    public static let step = 8

    public static func clamp(_ cols: Int) -> Int { min(max(cols, minColumns), maxColumns) }

    /// Dragging up (negative translation) goes finer, down goes crunchier.
    public static func columns(start: Int, translation: Double) -> Int {
        let span = Double(maxColumns - minColumns)
        let d0 = (Double(clamp(start)) - Double(minColumns)) / span
        let d = WhimsyMath.clamp01(d0 - translation / dragRange)
        return clamp(Int((Double(minColumns) + span * d).rounded()))
    }

    public static func stepped(_ cols: Int, up: Bool) -> Int { clamp(cols + (up ? step : -step)) }
    public static func cellSize(columns: Int, side: Double) -> Double { side / Double(max(columns, 1)) }
    public static func fontSize(columns: Int, side: Double) -> Double { cellSize(columns: columns, side: side) * glyphScale }

    public static func label(_ cols: Int) -> String {
        switch clamp(cols) {
        case ..<33: return "crunchy"
        case ..<53: return "medium"
        default: return "fine"
        }
    }
}
