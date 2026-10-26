import Foundation

public enum PaintEvent: Equatable, Sendable {
    case strokeBegan(Int)
    case strokeEnded(Int)
    /// A light haptic tick (every `tickEvery` strokes, debounced).
    case tick
    /// A stroke finished drying.
    case dried(Int)
    case restoredAll
    case reset
}

/// Paint over a faded photo to restore it. Each stroke is wet while painted and for a moment
/// after: glossy, smeared along the stroke and soft-edged. Over `dryDuration` it goes matte and its
/// edge tightens.
public struct PaintModel: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        public var dryDuration = 2.0
        /// Mask edge softness (blur radius, points) wet → dry.
        public var wetSoftness = 6.0
        public var drySoftness = 1.5
        /// A haptic tick after every `tickEvery` finished strokes, at most one per `tickInterval` s.
        public var tickEvery = 3
        public var tickInterval = 0.3
        /// "Restore all" fades the whole photo in over this long.
        public var restoreDuration = 0.6
        /// Reduce Motion: no smear, strokes dry the moment they end, restore-all is instant.
        public var reduceMotion = false
        public init() {}
    }

    public var config: Config
    public let size: Vec2
    public private(set) var strokes: [PaintStroke] = []
    public private(set) var coverage: PaintCoverage
    public private(set) var time = 0.0
    public private(set) var ticks = 0
    public private(set) var finishedStrokes = 0
    public private(set) var restoreAllStart: Double?
    private var nextIndex = 0
    private var lastTick = -Double.infinity
    private var pending: [PaintEvent] = []
    private var driedCount = 0

    public init(size: Vec2, config: Config = Config()) {
        self.size = size
        self.config = config
        coverage = PaintCoverage(size: size)
    }

    public var activeStroke: PaintStroke? { strokes.last.flatMap { $0.isActive ? $0 : nil } }
    public var percentRestored: Double { coverage.fraction * 100 }

    public func dryProgress(_ s: PaintStroke) -> Double {
        s.dryProgress(at: time, duration: config.dryDuration, instant: config.reduceMotion)
    }
    /// 1 wet … 0 dry (eased).
    public func wetness(_ s: PaintStroke) -> Double { 1 - WhimsyMath.smoothstep(0, 1, dryProgress(s)) }
    /// Mask blur radius for a stroke: soft while wet, tight once dry.
    public func softness(_ s: PaintStroke) -> Double {
        config.drySoftness + (config.wetSoftness - config.drySoftness) * wetness(s)
    }

    /// The smear for the layer effect: along the newest stroke, scaled by how wet it is.
    public var smear: Vec2 {
        guard !config.reduceMotion, let s = strokes.last else { return .zero }
        return PaintShading.smearVector(direction: s.direction, wetness: wetness(s))
    }

    /// 0…1 opacity of the full-photo "Restore all" fill.
    public var restoreOpacity: Double {
        guard let r = restoreAllStart else { return 0 }
        if config.reduceMotion || config.restoreDuration <= 0 { return 1 }
        return WhimsyMath.easeOutCubic(WhimsyMath.clamp01((time - r) / config.restoreDuration))
    }

    public var isDrying: Bool { strokes.contains { dryProgress($0) < 1 } }
    public var isIdle: Bool { activeStroke == nil && !isDrying && (restoreAllStart == nil || restoreOpacity >= 1) && pending.isEmpty }

    // MARK: Input

    /// Finger at `p` (card points) at model time `t`; starts a stroke if none is active.
    public mutating func dragChanged(to p: Vec2, at t: Double) {
        let t = max(t, time)
        time = t
        if activeStroke == nil {
            strokes.append(PaintStroke(index: nextIndex))
            pending.append(.strokeBegan(nextIndex))
            nextIndex += 1
        }
        let i = strokes.count - 1
        let before = strokes[i].points.last
        guard strokes[i].add(p, at: t), let now = strokes[i].points.last else { return }
        let soft = config.drySoftness
        if let b = before {
            coverage.addSegment(b.position, now.position, widths: b.width, now.width, softness: soft)
        } else {
            coverage.addSegment(now.position, now.position, widths: now.width, now.width, softness: soft)
        }
    }

    public mutating func dragEnded(at t: Double) {
        guard activeStroke != nil else { return }
        let t = max(t, time)
        time = t
        let i = strokes.count - 1
        strokes[i].end(at: t)
        finishedStrokes += 1
        pending.append(.strokeEnded(strokes[i].index))
        if finishedStrokes % max(config.tickEvery, 1) == 0, t - lastTick >= config.tickInterval {
            lastTick = t
            ticks += 1
            pending.append(.tick)
        }
    }

    public mutating func restoreAll() {
        if activeStroke != nil { dragEnded(at: time) }
        coverage.fillAll()
        restoreAllStart = time
        pending.append(.restoredAll)
    }

    public mutating func reset() {
        strokes.removeAll()
        coverage.clear()
        restoreAllStart = nil
        finishedStrokes = 0
        driedCount = 0
        pending.append(.reset)
    }

    /// Advance the clock to `t` (seconds); returns everything that happened since the last call.
    @discardableResult
    public mutating func advance(to t: Double) -> [PaintEvent] {
        if t.isFinite, t > time { time = t }
        var out = pending
        pending.removeAll()
        // Strokes dry in the order they ended, so dried ones form a prefix of the finished ones.
        while driedCount < strokes.count, !strokes[driedCount].isActive, dryProgress(strokes[driedCount]) >= 1 {
            out.append(.dried(strokes[driedCount].index))
            driedCount += 1
        }
        return out
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [PaintEvent] {
        advance(to: time + (dt > 0 && dt.isFinite ? min(dt, WhimsySpring.maxFrame) : 0))
    }
}
