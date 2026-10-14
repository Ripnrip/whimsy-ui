import Foundation
import WhimsyCore

/// Tiny involuntary jumps of the gaze target, as in the article: every 0.25–0.9 s, a new
/// offset within ±0.05 horizontally and ±0.04 vertically.
public struct SaccadeScheduler: Equatable, Sendable {
    public static let interval: ClosedRange<Double> = 0.25...0.9
    public static let rangeX: ClosedRange<Double> = -0.05...0.05
    public static let rangeY: ClosedRange<Double> = -0.04...0.04

    public private(set) var offset: Vec2 = .zero
    public private(set) var timeUntilNext: Double
    public private(set) var count = 0
    /// While disabled (Reduce Motion), the offset is zero and no saccades are scheduled.
    public var isEnabled = true {
        didSet { if !isEnabled { offset = .zero } }
    }

    public init(rng: inout SeededRandom) {
        timeUntilNext = rng.uniform(Self.interval)
    }

    public mutating func step(dt: Double, rng: inout SeededRandom) {
        guard isEnabled else { return }
        timeUntilNext -= dt
        while timeUntilNext <= 0 {
            offset = Vec2(rng.uniform(Self.rangeX), rng.uniform(Self.rangeY))
            count += 1
            timeUntilNext += rng.uniform(Self.interval)
        }
    }
}

/// Blink timing, as in the article: every 2.2–6.5 s, the lid closes in 70 ms and opens over
/// 100 ms, and 18% of blinks are doubles whose second blink starts 240 ms after the first.
public struct BlinkScheduler: Equatable, Sendable {
    public static let interval: ClosedRange<Double> = 2.2...6.5
    public static let closeDuration = 0.070
    public static let openDuration = 0.100
    public static let doubleBlinkChance = 0.18
    public static let doubleBlinkGap = 0.240

    /// 1 = normal; 0.5 plays blinks at half speed (Reduce Motion "gentler" blinks).
    public var speed = 1.0
    /// When false (Reduce Motion), no double blinks are scheduled.
    public var allowsDoubles = true

    public private(set) var timeUntilNext: Double
    /// Time since the current blink began, or nil between blinks.
    public private(set) var elapsed: Double?
    /// A second blink is due (double blink) after the current one.
    public private(set) var pendingSecond = false
    public private(set) var blinkCount = 0
    public private(set) var doubleCount = 0

    public init(rng: inout SeededRandom) {
        timeUntilNext = rng.uniform(Self.interval)
    }

    var blinkLength: Double { (Self.closeDuration + Self.openDuration) / speed }
    var gap: Double { Self.doubleBlinkGap / speed }

    public var isBlinking: Bool { elapsed != nil }

    /// Starts a blink now (e.g. from a test or a "tap to blink" interaction).
    public mutating func blinkNow(double: Bool = false) {
        elapsed = 0
        blinkCount += 1
        pendingSecond = double
        if double { doubleCount += 1 }
    }

    public mutating func step(dt: Double, rng: inout SeededRandom) {
        if var e = elapsed {
            e += dt
            if pendingSecond && e >= gap {
                // Second blink of a double: restart the curve where the gap ends.
                pendingSecond = false
                blinkCount += 1
                e -= gap
            }
            if !pendingSecond && e >= blinkLength {
                elapsed = nil
                timeUntilNext = rng.uniform(Self.interval) - (e - blinkLength)
            } else {
                elapsed = e
            }
            return
        }
        timeUntilNext -= dt
        if timeUntilNext <= 0 {
            let double = allowsDoubles && rng.uniform(0...1) < Self.doubleBlinkChance
            let overshoot = -timeUntilNext
            blinkNow(double: double)
            elapsed = overshoot
        }
    }

    /// Lid closure (0 open … 1 shut) `delay` seconds behind the blink's own clock, so the two
    /// lids can be slightly out of step.
    public func closure(delay: Double = 0) -> Double {
        guard let e = elapsed else { return 0 }
        return Self.closure(at: e - delay, speed: speed)
    }

    /// Blink curve: ease-in shut over 70 ms, then ease-out open over 100 ms (scaled by `speed`).
    public static func closure(at time: Double, speed: Double = 1) -> Double {
        let close = closeDuration / speed, open = openDuration / speed
        if time <= 0 || time >= close + open { return 0 }
        if time < close {
            let u = time / close
            return u * u                         // accelerates into the shut position
        }
        let u = (time - close) / open
        return 1 - u * u * (3 - 2 * u)           // smooth reopen
    }
}

/// A squint triggered by a shake: when the acceleration magnitude (g, gravity removed)
/// crosses a threshold, the level jumps to 1, holds briefly, then decays exponentially.
public struct SquintState: Equatable, Sendable {
    public var threshold = 1.4
    public var hold = 0.6
    public var decayTime = 0.45
    public private(set) var level = 0.0
    public private(set) var holdRemaining = 0.0
    public private(set) var triggerCount = 0

    public init() {}

    /// Feeds one accelerometer sample (user acceleration in g). Returns true if it triggered.
    @discardableResult
    public mutating func feed(x: Double, y: Double, z: Double) -> Bool {
        let magnitude = (x * x + y * y + z * z).squareRoot()
        guard magnitude.isFinite, magnitude >= threshold else { return false }
        trigger()
        return true
    }

    /// Fallback trigger (no accelerometer: Mac, simulator, a button, a double tap).
    public mutating func trigger() {
        level = 1
        holdRemaining = hold
        triggerCount += 1
    }

    public mutating func step(dt: Double) {
        if holdRemaining > 0 {
            let used = min(holdRemaining, dt)
            holdRemaining -= used
            let rest = dt - used
            if rest > 0 { level *= exp(-rest / decayTime) }
        } else {
            level *= exp(-dt / decayTime)
        }
        if level < 1e-3 { level = 0 }
    }
}
