import Foundation

/// Decides when the device points "dead on" the friend, with hysteresis so a shaky hand at
/// the boundary doesn't machine-gun the haptic: you become aligned inside `enter` degrees and
/// stay aligned until you drift past `exit` degrees. Each new alignment fires one tick, at
/// most once per `cooldown` seconds.
public struct AlignmentDetector: Equatable, Sendable {
    public var enter: Double
    public var exit: Double
    public var cooldown: Double
    public private(set) var isAligned = false
    /// Increments once per tick. Bind a haptic to it.
    public private(set) var tickCount = 0
    private var lastTick: Double = -.infinity
    /// When true, the next alignment becomes `isAligned` without a tick (used when a compass
    /// starts out already facing the friend).
    private var suppressNextTick = false

    public init(enter: Double = 4, exit: Double = 8, cooldown: Double = 0.35) {
        self.enter = abs(enter)
        self.exit = max(abs(exit), abs(enter))
        self.cooldown = max(cooldown, 0)
    }

    /// Feeds a relative bearing (degrees; wrapped internally) at `time` seconds. Returns true
    /// when this update fired a tick.
    @discardableResult
    public mutating func update(relativeBearing: Double, time: Double) -> Bool {
        guard relativeBearing.isFinite, time.isFinite else { return false }
        let off = abs(CompassMath.wrap180(relativeBearing))
        if isAligned {
            if off > exit { isAligned = false }
            return false
        }
        guard off <= enter else { return false }
        isAligned = true
        if suppressNextTick {
            suppressNextTick = false
            return false
        }
        guard time - lastTick >= cooldown else { return false }
        lastTick = time
        tickCount += 1
        return true
    }

    /// Next alignment becomes true without a tick (the compass began already facing the friend).
    public mutating func suppressNextAlignmentTick() { suppressNextTick = true }

    public mutating func reset() {
        isAligned = false
        suppressNextTick = false
    }
}
