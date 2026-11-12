import Foundation

/// sin and cos as plain polynomials, the same series StarJar uses, so a JavaScript
/// port of the tray reproduces every sample bit for bit. Library `sin` is not.
public enum TiltScatterMath {
    static let twoPi = 2 * Double.pi
    static let invTwoPi = 1 / (2 * Double.pi)
    static let halfPi = Double.pi / 2

    /// sin(x), reduced to [−π/2, π/2], then a Taylor polynomial through x¹⁷.
    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = Double.pi - r } else if r < -halfPi { r = -Double.pi - r }
        let r2 = r * r
        var p = 1.0 / 355_687_428_096_000.0
        p = -1.0 / 1_307_674_368_000.0 + r2 * p
        p = 1.0 / 6_227_020_800.0 + r2 * p
        p = -1.0 / 39_916_800.0 + r2 * p
        p = 1.0 / 362_880.0 + r2 * p
        p = -1.0 / 5040.0 + r2 * p
        p = 1.0 / 120.0 + r2 * p
        p = -1.0 / 6.0 + r2 * p
        p = 1.0 + r2 * p
        return r * p
    }

    public static func cos(_ x: Double) -> Double { sin(x + halfPi) }

    /// IEEE bit pattern, −0 folded to +0, so traces compare as text.
    public static func hex(_ d: Double) -> String {
        var x = d
        if x == 0 { x = 0 }
        return String(format: "%016llx", x.bitPattern)
    }
}
