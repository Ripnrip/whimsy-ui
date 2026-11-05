import Foundation

/// Geometry of the floating action button and the quarter-circle of tabs that fans out of it.
///
/// Angles use the same convention as ``Vec2/unit``: 0 is right, +π/2 is down (y down on screen).
/// The arc runs from straight up (−π/2) to straight left (−π), so the tabs open into the
/// upper-left quarter above the FAB.
public enum HoldToFanLayout {
    public static let minTabs = 3
    public static let maxTabs = 5
    public static let defaultTabs = 4

    /// Canvas the demo paints into (phone-content width × a short dock strip).
    public static let width = 360.0
    public static let height = 280.0

    /// FAB centre in layout coordinates (bottom-right of the strip).
    public static let fab = Vec2(300, 220)
    public static let fabRadius = 28.0

    /// Distance from the FAB centre to each tab's centre when fully open.
    public static let arcRadius = 118.0
    /// The fan spans this many radians (a quarter turn).
    public static let arcSpan = Double.pi / 2
    /// First tab (index 0) sits at this angle when open: straight up.
    public static let startAngle = -Double.pi / 2

    /// A finger closer than this is still "on the FAB", not aiming at a tab.
    public static let aimMinDistance = 36.0
    /// Past this distance the aim is considered off the arc (cancel on lift).
    public static let aimMaxDistance = 190.0
    /// Half-width of the angular hit window around a tab (radians).
    public static let aimHalfAngle = 0.38

    /// Tab pill size when fully open and not highlighted.
    public static let tabRadius = 22.0
    public static let labelGap = 8.0

    public static func clampedCount(_ n: Int) -> Int { min(max(n, minTabs), maxTabs) }

    /// Evenly spaced angles for `count` tabs along the upper-left quarter-circle.
    public static func angles(count: Int) -> [Double] {
        let n = clampedCount(count)
        if n == 1 { return [startAngle + arcSpan / 2] }
        return (0..<n).map { i in startAngle - arcSpan * Double(i) / Double(n - 1) }
    }

    /// Rest (closed) position of every tab: the FAB centre.
    public static func closedPosition(of index: Int, count: Int) -> Vec2 {
        _ = index; _ = count
        return fab
    }

    /// Fully-open position of tab `index`.
    public static func openPosition(of index: Int, count: Int) -> Vec2 {
        let θ = angles(count: count)[min(max(index, 0), clampedCount(count) - 1)]
        return fab + Vec2.unit(θ) * arcRadius
    }

    /// Position of tab `index` at radial progress `u` in 0…1 (0 = in the FAB, 1 = on the arc).
    public static func position(of index: Int, count: Int, progress u: Double) -> Vec2 {
        let t = WhimsyMath.clamp01(u)
        return Vec2.lerp(fab, openPosition(of: index, count: count), t)
    }

    /// Shortest signed difference `a − b`, in (−π, π].
    public static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d <= -.pi { d += 2 * .pi }
        return d
    }

    /// Angle of a point relative to the FAB, in (−π, π], same convention as ``angles``.
    public static func angle(of point: Vec2) -> Double {
        let d = point - fab
        return atan2(d.y, d.x)
    }

    /// Distance of a point from the FAB centre.
    public static func distance(of point: Vec2) -> Double { (point - fab).length }
}
