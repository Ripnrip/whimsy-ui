import Foundation

/// A latitude/longitude pair in degrees (WGS-84).
public struct GeoCoordinate: Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
}

/// Angle and bearing helpers. All angles are **degrees**. Bearings and headings are compass
/// angles: 0 = north, 90 = east, clockwise. Screen angles use the same convention with
/// 0 = straight up, 90 = right, so a relative bearing can be drawn directly.
public enum CompassMath {
    /// Wraps into [0, 360). Non-finite input gives 0.
    public static func wrap360(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let r = degrees.truncatingRemainder(dividingBy: 360)
        let w = r < 0 ? r + 360 : r
        return w == 360 ? 0 : w // -1e-15 + 360 rounds to 360
    }

    /// Wraps into (-180, 180]. Non-finite input gives 0.
    public static func wrap180(_ degrees: Double) -> Double {
        let w = wrap360(degrees)
        return w > 180 ? w - 360 : w
    }

    /// The signed shortest turn from `from` to `to`, in (-180, 180]. Positive = clockwise.
    /// An exact half turn is reported as +180.
    public static func shortestDelta(from: Double, to: Double) -> Double {
        wrap180(to - from)
    }

    /// Where the friend is relative to where the device points: 0 = dead ahead, +90 = to the
    /// right, ±180 = behind. This is also the on-screen angle of the blob's lean.
    public static func relativeBearing(heading: Double, friendBearing: Double) -> Double {
        shortestDelta(from: heading, to: friendBearing)
    }

    /// Unit vector on screen (y down) for a compass-style angle: 0 → up, 90 → right.
    public static func screenVector(degrees: Double) -> Vec2 {
        let r = degrees * .pi / 180
        return Vec2(sin(r), -cos(r))
    }

    /// Mean Earth radius (IUGG), metres.
    public static let earthRadius = 6_371_008.8

    /// Initial great-circle bearing from `a` to `b`, degrees in [0, 360).
    public static func bearing(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return wrap360(atan2(y, x) * 180 / .pi)
    }

    /// Great-circle (haversine) distance between `a` and `b`, metres.
    public static func distance(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δφ = φ2 - φ1, Δλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Words for a relative bearing, for VoiceOver: "dead ahead", "30° to your right",
    /// "behind you". Within ±`ahead` degrees counts as dead ahead; beyond ±`behind` as behind.
    public static func spokenDirection(relative: Double, ahead: Double = 4, behind: Double = 165) -> String {
        let r = wrap180(relative)
        if abs(r) <= ahead { return "dead ahead" }
        if abs(r) >= behind { return "behind you" }
        let deg = Int(abs(r).rounded())
        return "\(deg)° to your \(r > 0 ? "right" : "left")"
    }
}

/// Turns a horizontal drag into a fake heading (previews, the simulator, or devices without a
/// compass). Dragging right turns you right: the heading increases.
public struct FakeHeadingDrag: Equatable, Sendable {
    /// Degrees of heading per point of drag.
    public var sensitivity: Double
    public private(set) var startHeading: Double = 0
    public init(sensitivity: Double = 0.5) { self.sensitivity = sensitivity }

    public mutating func begin(at heading: Double) { startHeading = CompassMath.wrap360(heading) }

    /// Heading for a total horizontal translation since ``begin(at:)``, wrapped to [0, 360).
    public func heading(forTranslation dx: Double) -> Double {
        CompassMath.wrap360(startHeading + (dx.isFinite ? dx : 0) * sensitivity)
    }
}
