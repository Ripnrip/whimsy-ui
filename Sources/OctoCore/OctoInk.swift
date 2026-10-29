import Foundation

/// A dot to draw, in row coordinates (origin at the row's top left).
public struct OctoDot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var r: Double
}

/// The ink blob: an ellipse.
public struct OctoBlob: Equatable, Sendable {
    public var center: Vec2
    public var rx: Double
    public var ry: Double
}

/// Where everything sits.
public enum OctoLayout {
    public static let rowWidth = 340.0
    public static let rowHeight = 56.0
    public static let rowGap = 8.0
    public static var pitch: Double { rowHeight + rowGap }
    public static let cornerRadius = 14.0
    /// How far the grabbed row is pulled down.
    public static let pullDistance = 72.0
    public static let maxStretch = 0.32
    public static let grabSquash = 0.12
}

/// The halftone ink: a fixed dot lattice whose dot size follows a radial falloff, and a tentacle.
public enum OctoInk {
    public static let spacing = 7.0
    public static let rowStep = 0.866          // hex-ish: lattice rows are spacing * 0.866 apart, odd rows shifted half a cell
    public static let maxDot = 3.3
    public static let minDot = 0.35
    public static let blobWidthFactor = 0.6
    public static let blobHeight = 62.0
    public static let blurRadius = 1.4

    /// The radial gradient: 1 at the centre, 0 at the edge (`d` is the normalised distance).
    public static func falloff(_ d: Double) -> Double { 1 - WhimsyMath.smoothstep(0, 1, d) }

    /// The blob at a swell value 0…1, rising from below the row. nil before it starts.
    public static func blob(swell: Double) -> OctoBlob? {
        guard swell > 0 else { return nil }
        let s = WhimsyMath.clamp01(swell)
        let cy = WhimsyMath.lerp(OctoLayout.rowHeight + 26, OctoLayout.rowHeight * 0.62, s)
        return OctoBlob(center: Vec2(OctoLayout.rowWidth / 2, cy), rx: OctoLayout.rowWidth * blobWidthFactor * s, ry: blobHeight * s)
    }

    public static func dotRadius(blob b: OctoBlob, x: Double, y: Double) -> Double {
        guard b.rx > 0, b.ry > 0 else { return 0 }
        let d = (((x - b.center.x) / b.rx) * ((x - b.center.x) / b.rx) + ((y - b.center.y) / b.ry) * ((y - b.center.y) / b.ry)).squareRoot()
        return d >= 1 ? 0 : maxDot * falloff(d)
    }

    /// The halftone dots for a blob. The lattice is fixed in row coordinates, so as the blob grows the
    /// dots grow in place instead of swimming.
    public static func dots(blob b: OctoBlob?) -> [OctoDot] {
        guard let b, b.rx > 0, b.ry > 0 else { return [] }
        let dy = spacing * rowStep
        let j0 = Int(((b.center.y - b.ry) / dy).rounded(.down)), j1 = Int(((b.center.y + b.ry) / dy).rounded(.up))
        let k0 = Int(((b.center.x - b.rx) / spacing).rounded(.down)) - 1, k1 = Int(((b.center.x + b.rx) / spacing).rounded(.up)) + 1
        var out: [OctoDot] = []
        for j in j0...j1 {
            let y = Double(j) * dy, shift = abs(j) % 2 == 1 ? 0.5 : 0.0
            for k in k0...k1 {
                let x = (Double(k) + shift) * spacing
                let r = dotRadius(blob: b, x: x, y: y)
                if r >= minDot { out.append(OctoDot(x: x, y: y, r: r)) }
            }
        }
        return out
    }

    // MARK: Tentacle

    public static let tentacleSamples = 44
    public static let tentacleWidth = 14.0
    /// Angles of the wrap (screen angles, y down): bottom right, up the right side, over the top, down the left.
    public static let tentacleStart = 0.9
    public static let tentacleSpan = 1.25 * Double.pi + 0.9

    /// The tentacle's centre line at u in 0…1.
    public static func tentaclePoint(_ u: Double) -> Vec2 {
        let theta = tentacleStart - u * tentacleSpan
        let curl = 1 - 0.22 * u * u
        let rx = (OctoLayout.rowWidth / 2 + 16) * curl, ry = (OctoLayout.rowHeight / 2 + 14) * curl
        return Vec2(OctoLayout.rowWidth / 2 + rx * cos(theta), OctoLayout.rowHeight / 2 + ry * sin(theta))
    }

    /// Tapered width along the tentacle.
    public static func tentacleThickness(_ u: Double) -> Double { tentacleWidth * pow(1 - WhimsyMath.clamp01(u), 0.9) + 1.5 }

    /// Dots along the first `grab` of the tentacle: three abreast, shrinking toward the tip.
    public static func tentacle(grab: Double) -> [OctoDot] {
        let g = WhimsyMath.clamp01(grab)
        guard g > 0 else { return [] }
        var out: [OctoDot] = []
        let n = tentacleSamples, last = Double(n - 1) * g
        for i in 0..<n {
            let f = Double(i)
            guard f <= last + 1e-9 else { break }
            let u = f / Double(n - 1)
            let p = tentaclePoint(u), q = tentaclePoint(min(u + 0.01, 1)), p0 = tentaclePoint(max(u - 0.01, 0))
            let tx = q.x - p0.x, ty = q.y - p0.y, len = max((tx * tx + ty * ty).squareRoot(), 1e-9)
            let nx = -ty / len, ny = tx / len
            let w = tentacleThickness(u)
            // The growing tip scales in over the last sample so the head doesn't pop.
            let tip = WhimsyMath.clamp01(last - f + 1)
            for lateral in [-1.0, 0.0, 1.0] {
                let r = (lateral == 0 ? w * 0.30 : w * 0.22) * tip
                if r >= minDot { out.append(OctoDot(x: p.x + nx * lateral * w * 0.3, y: p.y + ny * lateral * w * 0.3, r: r)) }
            }
        }
        return out
    }
}
