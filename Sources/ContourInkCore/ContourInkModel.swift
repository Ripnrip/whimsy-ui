import Foundation

/// The running loader: advances time, emits events, and hands the view its frame.
public struct ContourInkModel: Equatable, Sendable {
    public let rings: Int
    /// Running time in seconds; the loop is `time` wrapped to the period.
    public private(set) var time = 0.0
    public private(set) var isAnimating: Bool
    public private(set) var reduceMotion: Bool
    public private(set) var ringsClosed = 0
    public private(set) var arrivals = 0
    public private(set) var loops = 0

    /// Longest step taken at once (a stalled timeline must not skip the whole loop).
    public static let maxStep = 0.25

    public init(rings: Int = ContourInkGeometry.defaultRings, isAnimating: Bool = true, reduceMotion: Bool = false) {
        self.rings = ContourInkGeometry.clampedCount(rings)
        self.isAnimating = isAnimating
        self.reduceMotion = reduceMotion
    }

    /// Static: Reduce Motion, or not animating. Shows the finished map and does not advance.
    public var isStatic: Bool { reduceMotion || !isAnimating }

    public var period: Double { ContourInkTimeline.period(rings: rings) }

    /// Changes the two switches. Going from static to running starts the loop from the beginning.
    public mutating func update(isAnimating: Bool, reduceMotion: Bool) {
        let was = isStatic
        self.isAnimating = isAnimating
        self.reduceMotion = reduceMotion
        if was && !isStatic { restart() }
    }

    public mutating func restart() {
        time = 0; ringsClosed = 0; arrivals = 0; loops = 0
    }

    /// Advances by `dt` seconds (clamped to 0 ... `maxStep`; not-a-number counts as 0) and returns what happened.
    @discardableResult
    public mutating func step(_ dt: Double) -> [ContourEvent] {
        guard !isStatic else { return [] }
        let d = dt.isFinite ? min(max(dt, 0), Self.maxStep) : 0
        guard d > 0 else { return [] }
        let t0 = time
        time += d
        let ev = ContourInkTimeline.events(from: t0, to: time, rings: rings)
        for e in ev {
            switch e {
            case .ringClosed: ringsClosed += 1
            case .dotArrived: arrivals += 1
            case .looped: loops += 1
            }
        }
        return ev
    }

    public var frame: ContourFrame {
        isStatic ? ContourInkTimeline.staticFrame(rings: rings) : ContourInkTimeline.frame(at: time, rings: rings)
    }
}
