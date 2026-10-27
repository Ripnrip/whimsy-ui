import Foundation

/// What the search did, for the view (haptics, announcements) and tests.
public enum WiggleEvent: Equatable, Sendable {
    case queryChanged(String)
    case resultsChanged(Int)
    case lettersMatched(row: Int, indices: [Int])
    /// A light haptic: some letters became newly matched, at most once per `tickInterval`.
    case tick
    /// The underlines have calmed to a flat line.
    case calmed
}

/// The search state over time: query → ranked results, newly matched letters and their jiggle
/// start times, the wave envelope and debounced haptic events. Times are seconds on any clock that
/// only moves forward.
public struct WiggleModel: Sendable {
    public struct Config: Equatable, Sendable {
        public var tickInterval = 0.12
        public var reduceMotion = false
        public init() {}
    }

    public var config: Config
    public let rows: [SettingsRow]
    public private(set) var query = ""
    public private(set) var results: [RankedRow]
    public private(set) var time = 0.0
    public private(set) var envelope = WaveEnvelope()
    public private(set) var ticks = 0
    /// row id → title index → jiggle start time.
    public private(set) var jiggleStarts: [Int: [Int: Double]] = [:]
    private var lastTick = -Double.infinity
    private var calmEmitted = true
    private var pending: [WiggleEvent] = []

    public init(rows: [SettingsRow] = SettingsCatalog.rows, config: Config = Config()) {
        self.rows = rows
        self.config = config
        results = FuzzyMatcher.rank("", rows: rows)
    }

    public var resultCount: Int { results.count }

    /// Row id → matched title indices for the current results.
    public var matched: [Int: [Int]] {
        var d: [Int: [Int]] = [:]
        for r in results where !r.match.indices.isEmpty { d[r.row.id] = r.match.indices }
        return d
    }

    /// Current underline amplitude in points (0 under Reduce Motion: a straight line).
    public var amplitude: Double {
        config.reduceMotion ? 0 : WaveUnderline.maxAmplitude * envelope.level(at: time)
    }

    public func jiggle(row: Int, index: Int) -> (scale: Double, offsetY: Double) {
        guard !config.reduceMotion, let start = jiggleStarts[row]?[index] else { return (1, 0) }
        return LetterJiggle.transform(at: time - start)
    }

    public var isJiggling: Bool {
        !config.reduceMotion && jiggleStarts.values.contains { $0.values.contains { time - $0 < LetterJiggle.settleTime } }
    }

    /// Nothing moving and nothing to report: the view can pause its timeline.
    public var isIdle: Bool {
        (config.reduceMotion || envelope.isCalm(at: time)) && !isJiggling && pending.isEmpty && calmEmitted
    }

    public mutating func setQuery(_ q: String, at t: Double) {
        if t.isFinite { time = max(time, t) }
        guard q != query else { return }
        let before = matched, oldCount = results.count
        query = q
        results = FuzzyMatcher.rank(q, rows: rows)
        let now = matched
        pending.append(.queryChanged(q))
        if results.count != oldCount { pending.append(.resultsChanged(results.count)) }

        // Letters no longer matched forget their jiggle, so matching them again jiggles again.
        for (row, starts) in jiggleStarts {
            let keep = Set(now[row] ?? [])
            let kept = starts.filter { keep.contains($0.key) }
            jiggleStarts[row] = kept.isEmpty ? nil : kept
        }
        let fresh = MatchDiff.newlyMatched(previous: before, current: now)
        for (rank, r) in results.enumerated() {
            guard let idx = fresh[r.row.id] else { continue }
            let start = time + LetterJiggle.stagger * Double(min(rank, LetterJiggle.maxStaggerRows))
            for i in idx { jiggleStarts[r.row.id, default: [:]][i] = start }
            pending.append(.lettersMatched(row: r.row.id, indices: idx))
        }
        if !fresh.isEmpty && time - lastTick >= config.tickInterval {
            lastTick = time
            ticks += 1
            pending.append(.tick)
        }
        envelope.energize(at: time)
        calmEmitted = false
    }

    /// Moves time forward and returns everything that happened since the last call, in order.
    @discardableResult
    public mutating func advance(to t: Double) -> [WiggleEvent] {
        if t.isFinite { time = max(time, t) }
        var out = pending
        pending = []
        if !calmEmitted && envelope.isCalm(at: time) {
            calmEmitted = true
            out.append(.calmed)
        }
        return out
    }
}
