import Foundation

/// Maps a drag to a card tilt. `x` is yaw (degrees about the vertical axis, positive pushes the
/// right edge away), `y` is pitch (degrees about the horizontal axis, positive pushes the top away).
public enum HoloTilt {
    /// The tilt never goes past this on either axis.
    public static let maxAngle = 15.0
    /// Degrees of tilt per point of drag near the rest position.
    public static let degreesPerPoint = 0.12

    /// A soft clamp: linear (slope 1) near zero, easing into ±limit and never exceeding it.
    public static func softClamp(_ v: Double, limit: Double = maxAngle) -> Double {
        guard limit > 0, v.isFinite else { return v.isNaN ? 0 : (v > 0 ? limit : -limit) }
        return limit * tanh(v / limit)
    }

    /// Drag translation (points, y down) → tilt degrees (yaw, pitch). Dragging right pushes the right
    /// edge away; dragging up pushes the top away, like pressing the card where your finger goes.
    public static func tilt(forDrag t: Vec2) -> Vec2 {
        Vec2(softClamp(t.x * degreesPerPoint), softClamp(-t.y * degreesPerPoint))
    }

    /// Tilt in −1…1 per axis (what the shader receives).
    public static func normalized(_ tilt: Vec2) -> Vec2 {
        Vec2(max(-1, min(1, tilt.x / maxAngle)), max(-1, min(1, tilt.y / maxAngle)))
    }
}

/// Fires when the rainbow band crosses the card centre, with hysteresis and a minimum interval
/// so a band hovering near the centre doesn't buzz.
public struct CenterCrossingDetector: Equatable, Sendable {
    /// The band must get at least this far past the centre (in card-diagonal units) to count as on a side.
    public static let hysteresis = 0.04
    /// Crossings closer together than this are dropped (the side still updates).
    public static let minInterval = 0.12

    /// −1 left of centre, +1 right, 0 not yet known.
    public private(set) var side = 0
    private var sinceLast = Double.infinity

    public init() {}

    /// Feed the band position each step; returns +1/−1 for a crossing in that direction, else nil.
    public mutating func update(band: Double, dt: Double) -> Int? {
        sinceLast += max(dt, 0)
        let s = band > Self.hysteresis ? 1 : (band < -Self.hysteresis ? -1 : 0)
        guard s != 0 else { return nil }
        defer { side = s }
        guard side != 0, s != side else { return nil }
        guard sinceLast >= Self.minInterval else { return nil }
        sinceLast = 0
        return s
    }
}
