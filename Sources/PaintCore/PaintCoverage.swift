import Foundation

/// How much of the photo has been restored: a coarse grid holding the strongest mask value
/// (soft falloff around each stroke segment) seen at each cell centre.
public struct PaintCoverage: Equatable, Sendable {
    public static let cell = 4.0

    public let columns: Int
    public let rows: Int
    public private(set) var values: [Double]

    public init(size: Vec2) {
        columns = max(1, Int((size.x / Self.cell).rounded(.up)))
        rows = max(1, Int((size.y / Self.cell).rounded(.up)))
        values = [Double](repeating: 0, count: columns * rows)
    }

    /// Mask opacity at distance `d` from a stroke's centre line: 1 inside, 0 outside, a
    /// smoothstep ramp of ±softness around the edge (0.5 exactly at the edge).
    public static func maskFalloff(distance d: Double, halfWidth h: Double, softness s: Double) -> Double {
        let s = max(s, 1e-6)
        return 1 - WhimsyMath.smoothstep(h - s, h + s, d)
    }

    /// Stamps a segment whose width varies linearly from `wa` to `wb`.
    public mutating func addSegment(_ a: Vec2, _ b: Vec2, widths wa: Double, _ wb: Double, softness: Double) {
        let reach = max(wa, wb) / 2 + softness
        let x0 = max(0, Int(floor((min(a.x, b.x) - reach) / Self.cell)))
        let x1 = min(columns - 1, Int(floor((max(a.x, b.x) + reach) / Self.cell)))
        let y0 = max(0, Int(floor((min(a.y, b.y) - reach) / Self.cell)))
        let y1 = min(rows - 1, Int(floor((max(a.y, b.y) + reach) / Self.cell)))
        guard x0 <= x1, y0 <= y1 else { return }
        let ab = b - a, l2 = ab.dot(ab)
        for y in y0...y1 {
            for x in x0...x1 {
                let p = Vec2((Double(x) + 0.5) * Self.cell, (Double(y) + 0.5) * Self.cell)
                let t = l2 > 0 ? max(0, min(1, (p - a).dot(ab) / l2)) : 0
                let d = (p - (a + ab * t)).length
                let v = Self.maskFalloff(distance: d, halfWidth: (wa + (wb - wa) * t) / 2, softness: softness)
                let i = y * columns + x
                if v > values[i] { values[i] = v }
            }
        }
    }

    public mutating func fillAll() { values = [Double](repeating: 1, count: values.count) }
    public mutating func clear() { values = [Double](repeating: 0, count: values.count) }

    /// 0…1 mean coverage.
    public var fraction: Double { values.reduce(0, +) / Double(values.count) }
}
