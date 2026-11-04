import Foundation

/// A rectangle in jar coordinates (points, y down).
public struct JarRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px <= maxX && py >= y && py <= maxY }
}

/// The jar: a rounded body with a narrower rounded neck on top, closed by a cork.
/// The inside is the union of two rounded boxes, described by a signed distance (negative inside).
public enum StarJarGeometry {
    public static let width = 300.0
    public static let height = 340.0

    public static let bodyCenter = (x: 150.0, y: 212.0)
    public static let bodyHalf = (x: 120.0, y: 118.0)
    public static let bodyRadius = 54.0
    public static let neckCenter = (x: 150.0, y: 64.0)
    public static let neckHalf = (x: 56.0, y: 34.0)
    public static let neckRadius = 12.0
    /// The cork sits in the top of the neck; stars stop at its underside (the neck's top edge, y = 30).
    public static let cork = JarRect(x: 98, y: 6, width: 104, height: 28)
    public static let corkRadius = 6.0
    /// Thickness of the glass: a star's edge stays this far inside the outline.
    public static let wall = 4.0
    /// The "Done" chip, shown while the jar is awake.
    public static let doneChip = JarRect(x: 230, y: 8, width: 62, height: 28)
    /// Step for the numerical gradient.
    public static let normalEpsilon = 0.01

    public static var body: JarRect { JarRect(x: bodyCenter.x - bodyHalf.x, y: bodyCenter.y - bodyHalf.y, width: 2 * bodyHalf.x, height: 2 * bodyHalf.y) }
    public static var neck: JarRect { JarRect(x: neckCenter.x - neckHalf.x, y: neckCenter.y - neckHalf.y, width: 2 * neckHalf.x, height: 2 * neckHalf.y) }

    /// Signed distance from a point to a rounded box (negative inside).
    public static func roundedBox(_ px: Double, _ py: Double, cx: Double, cy: Double, hx: Double, hy: Double, r: Double) -> Double {
        let qx = abs(px - cx) - (hx - r), qy = abs(py - cy) - (hy - r)
        let ox = max(qx, 0), oy = max(qy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(qx, qy), 0) - r
    }

    /// Signed distance to the jar's inner outline: negative inside, 0 on the glass, positive outside.
    public static func distance(_ px: Double, _ py: Double) -> Double {
        let b = roundedBox(px, py, cx: bodyCenter.x, cy: bodyCenter.y, hx: bodyHalf.x, hy: bodyHalf.y, r: bodyRadius)
        let n = roundedBox(px, py, cx: neckCenter.x, cy: neckCenter.y, hx: neckHalf.x, hy: neckHalf.y, r: neckRadius)
        return min(b, n)
    }

    /// Outward unit normal (the gradient of `distance`, by central differences).
    public static func normal(_ px: Double, _ py: Double) -> (x: Double, y: Double) {
        let e = normalEpsilon
        let gx = distance(px + e, py) - distance(px - e, py)
        let gy = distance(px, py + e) - distance(px, py - e)
        let len = (gx * gx + gy * gy).squareRoot()
        guard len > 1e-12 else { return (0, 1) }
        return (gx / len, gy / len)
    }

    public static func contains(_ px: Double, _ py: Double) -> Bool { px.isFinite && py.isFinite && distance(px, py) <= 0 }
    /// A tap on the glass or the cork counts as a tap on the jar.
    public static func hitsJar(_ px: Double, _ py: Double) -> Bool { contains(px, py) || cork.contains(px, py) }
    public static func hitsDone(_ px: Double, _ py: Double) -> Bool { doneChip.contains(px, py) }
}
