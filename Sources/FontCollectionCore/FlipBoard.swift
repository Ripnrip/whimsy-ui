import Foundation

/// Timing for the split-flap headline.
public struct FlipBoardTuning: Equatable, Sendable {
    /// Flaps per run, including the final one.
    public var flips = 14
    /// Gap after the first flap, seconds (the board starts fast)…
    public var minInterval = 0.05
    /// …and before the last one (it slows to a stop).
    public var maxInterval = 0.26
    /// Exponent of the ease-in that stretches the gaps (3 = cubic).
    public var easeExponent = 2.6
    /// How long one flap takes to fall, seconds (capped at 90% of the gap so flaps never overlap).
    public var foldDuration = 0.09
    /// The final flap falls this much slower, for a satisfying settle.
    public var finalFoldScale = 1.8
    /// Delay between neighbouring characters, seconds: a wave runs left to right.
    public var columnStagger = 0.028
    /// Flip-tick haptic intensity on the first and last flaps.
    public var tickIntensity: ClosedRange<Double> = 0.3...0.8
    public init() {}
    public static let `default` = FlipBoardTuning()
}

/// One flap on the board's base clock (column 0).
public struct FlipEvent: Equatable, Sendable {
    /// Seconds after the run starts.
    public var time: Double
    /// Font shown before this flap (index into the catalog).
    public var fromFont: Int
    /// Font revealed by this flap.
    public var toFont: Int
    /// How long this flap takes to fall, seconds.
    public var foldDuration: Double
    public var isFinal: Bool
}

/// What one character cell shows at a moment.
public struct FlipCellState: Equatable, Sendable {
    /// Font on the falling flap (the one going away).
    public var fromFont: Int
    /// Font being revealed.
    public var toFont: Int
    /// Fall progress, 0 (flap up, showing `fromFont`) … 1 (fallen, showing `toFont`).
    public var progress: Double
    /// True once this cell's final flap has fallen.
    public var isSettled: Bool

    /// The font that reads as "current" (switches halfway through the fall).
    public var visibleFont: Int { progress < 0.5 ? fromFont : toFont }
    /// Angle of the falling flap in degrees: 0 → −90 (top half folding down), then 90 → 0
    /// (bottom half landing). A renderer shows `fromFont` on the first half and `toFont` on the second.
    public var flapAngle: Double { progress < 0.5 ? -180 * progress : 180 * (1 - progress) }
}

/// A deterministic flip-board run: the headline flaps through random fonts, fast then slower
/// (an ease-in on the gaps), and settles on `target`. Characters follow column 0 with a small
/// stagger, so each flap runs across the word like a wave. All randomness comes from a seed.
public struct FlipBoardSchedule: Equatable, Sendable {
    public let fontCount: Int
    public let startFont: Int
    public let target: Int
    public let columns: Int
    public let tuning: FlipBoardTuning
    public let flips: [FlipEvent]

    /// - Parameters:
    ///   - fontCount: number of fonts to pick from (≥ 1).
    ///   - startFont: what the board shows before the first flap.
    ///   - target: where it settles.
    ///   - columns: number of character cells (≥ 1).
    ///   - reduceMotion: one instant change, no flapping.
    public init(fontCount: Int, startFont: Int = 0, target: Int, columns: Int, seed: UInt64,
                tuning: FlipBoardTuning = .default, reduceMotion: Bool = false) {
        let n = max(fontCount, 1)
        let start = Self.clampIndex(startFont, n)
        let goal = Self.clampIndex(target, n)
        self.fontCount = n
        self.startFont = start
        self.target = goal
        self.columns = max(columns, 1)
        self.tuning = tuning
        if reduceMotion {
            flips = [FlipEvent(time: 0, fromFont: start, toFont: goal, foldDuration: 0, isFinal: true)]
            return
        }
        let count = max(tuning.flips, 1)
        var rng = SeededRandom(seed: seed)
        // Font sequence: no immediate repeats, never the target until the last flap.
        var fonts: [Int] = []
        var previous = start
        for k in 0..<count {
            if k == count - 1 {
                fonts.append(goal)
            } else {
                let pool = (0..<n).filter { $0 != previous && $0 != goal }
                let pick = pool.isEmpty ? (previous == goal ? goal : previous)
                    : pool[min(Int(rng.uniform(0...1) * Double(pool.count)), pool.count - 1)]
                fonts.append(pick)
                previous = pick
            }
        }
        var out: [FlipEvent] = []
        var t = 0.0
        var from = start
        for k in 0..<count {
            let gap = Self.interval(k, count: count, tuning: tuning)
            let isFinal = k == count - 1
            let fold = isFinal ? tuning.foldDuration * tuning.finalFoldScale : min(tuning.foldDuration, gap * 0.9)
            out.append(FlipEvent(time: t, fromFont: from, toFont: fonts[k], foldDuration: fold, isFinal: isFinal))
            from = fonts[k]
            t += gap
        }
        flips = out
    }

    /// Gap after flap `k` of `count`: minInterval → maxInterval on an ease-in.
    public static func interval(_ k: Int, count: Int, tuning: FlipBoardTuning = .default) -> Double {
        guard count > 1 else { return tuning.minInterval }
        let u = min(max(Double(k) / Double(count - 1), 0), 1)
        return tuning.minInterval + (tuning.maxInterval - tuning.minInterval) * pow(u, max(tuning.easeExponent, 0))
    }

    static func clampIndex(_ i: Int, _ n: Int) -> Int { min(max(i, 0), n - 1) }

    /// When the final flap of the last column has landed.
    public var duration: Double {
        guard let last = flips.last else { return 0 }
        return last.time + Double(columns - 1) * (flips.count > 1 ? tuning.columnStagger : 0) + last.foldDuration
    }

    /// Time of column 0's final flap starting (the moment the "settle" haptic should fire is
    /// when it lands: `settleTime`).
    public var settleTime: Double {
        guard let last = flips.last else { return 0 }
        return last.time + last.foldDuration
    }

    public func isSettled(at t: Double) -> Bool { t >= duration }

    /// State of character cell `column` at `t` seconds after the run started.
    public func cell(column: Int, at t: Double) -> FlipCellState {
        let col = Self.clampIndex(column, columns)
        let offset = flips.count > 1 ? Double(col) * tuning.columnStagger : 0
        let local = t - offset
        guard let first = flips.first, local >= first.time else {
            return FlipCellState(fromFont: startFont, toFont: startFont, progress: 1, isSettled: false)
        }
        // The latest flap that has started for this column.
        var k = flips.count - 1
        while k > 0 && flips[k].time > local { k -= 1 }
        let f = flips[k]
        // Small epsilon so "exactly at the landing time" counts as landed despite rounding.
        let landed = local >= f.time + f.foldDuration - 1e-9
        let p = landed ? 1 : min(max((local - f.time) / f.foldDuration, 0), 1)
        return FlipCellState(fromFont: f.fromFont, toFont: f.toFont, progress: p, isSettled: f.isFinal && landed)
    }

    /// All cells at `t`.
    public func cells(at t: Double) -> [FlipCellState] { (0..<columns).map { cell(column: $0, at: t) } }

    /// Haptics due in the half-open window `(t0, t1]`: one tick per flap start on column 0
    /// (stronger as the board slows), and `.settle` when the final flap lands.
    public func hapticEvents(after t0: Double, through t1: Double) -> [(time: Double, event: FontHapticEvent)] {
        guard t1 > t0, flips.count > 1 else {
            // Reduce Motion: a single settle at time 0.
            if flips.count == 1, t0 < 0, t1 >= 0, t1 > t0 { return [(0, .settle)] }
            return []
        }
        var out: [(Double, FontHapticEvent)] = []
        let n = flips.count
        for (k, f) in flips.enumerated() where !f.isFinal && f.time > t0 && f.time <= t1 {
            let u = Double(k) / Double(max(n - 2, 1))
            let i = tuning.tickIntensity.lowerBound + (tuning.tickIntensity.upperBound - tuning.tickIntensity.lowerBound) * u
            out.append((f.time, .flipTick(intensity: i)))
        }
        if settleTime > t0 && settleTime <= t1 { out.append((settleTime, .settle)) }
        return out
    }
}
