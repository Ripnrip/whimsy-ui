import Foundation

/// Geometry of a five-card fan parked along the bottom of a phone-sized canvas.
///
/// Angles use the same convention as ``Vec2/unit``: 0 is right, +π/2 is down. The fan's pivot
/// sits below the canvas, so the middle card is the highest and the outer cards drop toward the
/// bottom edge. Card rotation is the angle off upright (0 for the middle card); SwiftUI's
/// `rotationEffect` is clockwise-positive, which tips the outer tops away from the centre.
public enum RubberBandLayout {
    public static let count = 5
    public static let width = 390.0
    public static let height = 700.0
    public static let cardWidth = 108.0
    public static let cardHeight = 158.0
    public static let cornerRadius = 16.0

    /// Pivot-to-centre distance of the arc, and how far the outer cards swing off vertical.
    public static let arcRadius = 292.0
    public static let halfSpan = 0.42
    /// The outer cards' axis-aligned bottoms sit this far above the canvas bottom.
    /// Rotation swings the corners lower than that, so the margin leaves them on screen.
    public static let bottomMargin = 52.0

    /// A hovered card rises this many points.
    public static let hoverLift = 20.0
    /// Resisted upward travel that commits a drag (points).
    public static let commitRise = 56.0
    /// …or a flick at least this fast (points per second, upward) after `flickMin` raw points.
    public static let flickSpeed = 900.0
    public static let flickMin = 22.0
    /// Upward travel, past this and steeper than the sideways travel, locks a card into a drag.
    public static let grabSlop = 16.0
    /// A neighbouring card has to be this many points closer in x before the hover moves.
    public static let stickiness = 14.0
    /// Resisted downward travel that puts a centred card back.
    public static let dismissRise = 48.0
    public static let dismissFlick = 800.0

    public static let presentedScale = 1.62
    /// Where a committed card springs to (upper middle of the canvas).
    public static var stage: Vec2 { Vec2(width / 2, 246) }

    public static let hitPadX = 16.0
    public static let hitPadY = 36.0

    /// Fan pivot. Derived so card 0's bottom edge lands on `height - bottomMargin`.
    public static var origin: Vec2 {
        let a = angle(0)
        let y = (height - bottomMargin) - cardHeight / 2 - sin(a) * arcRadius
        return Vec2(width / 2, y)
    }

    /// Angle of card `i` on the arc. Index 2 points straight up (−π/2).
    public static func angle(_ index: Int) -> Double {
        let i = clamped(index)
        let t = Double(i - 2) / 2.0
        return -.pi / 2 + t * halfSpan
    }

    public static func clamped(_ index: Int) -> Int { min(max(index, 0), count - 1) }

    public static func restCenter(_ index: Int) -> Vec2 {
        let a = angle(index)
        let o = origin
        return Vec2(o.x + cos(a) * arcRadius, o.y + sin(a) * arcRadius)
    }

    /// Radians, clockwise-positive, 0 upright.
    public static func restRotation(_ index: Int) -> Double { angle(index) + .pi / 2 }

    public static func restTop(_ index: Int) -> Double { restCenter(index).y - cardHeight / 2 }

    /// The finger is over the fan (including a band above the cards, where a lifted card lives).
    public static func handContains(_ point: Vec2) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let centers = (0..<count).map { restCenter($0) }
        let minX = centers.map(\.x).min()! - cardWidth / 2 - hitPadX
        let maxX = centers.map(\.x).max()! + cardWidth / 2 + hitPadX
        let minY = (0..<count).map { restTop($0) }.min()! - hoverLift - hitPadY
        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= height
    }

    /// Nearest card by horizontal distance, keeping `current` until another card is `stickiness`
    /// points closer. Nil when the point is off the hand. Ties break toward the lower index,
    /// and toward `current` when it is one of the ties.
    public static func nearestIndex(to point: Vec2, current: Int?) -> Int? {
        guard handContains(point) else { return nil }
        var best = 0
        var bestD = abs(restCenter(0).x - point.x)
        for i in 1..<count {
            let d = abs(restCenter(i).x - point.x)
            if d < bestD - 1e-9 {
                best = i
                bestD = d
            }
        }
        if let current {
            let c = clamped(current)
            let dCur = abs(restCenter(c).x - point.x)
            if dCur - bestD <= stickiness { return c }
        }
        return best
    }

    /// Axis-aligned hit rect of the centred card, in canvas points.
    public static func presentedContains(_ point: Vec2) -> Bool {
        let s = presentedScale
        let hw = cardWidth / 2 * s + 8
        let hh = cardHeight / 2 * s + 8
        let c = stage
        return abs(point.x - c.x) <= hw && abs(point.y - c.y) <= hh
    }
}
