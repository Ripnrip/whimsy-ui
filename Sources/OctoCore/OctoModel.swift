import Foundation

public enum OctoHaptic: Hashable, Sendable { case grab, gone }

public enum OctoEvent: Equatable, Sendable {
    /// A row's tick started (announce "Completed …").
    case ticked(Int)
    /// A tap undid a tick before the grab.
    case unticked(Int)
    /// The ink grabbed the row: the row is committed from here.
    case grabbed(Int)
    /// The row collapsed out of the list.
    case gone(Int)
    /// An undone tick finished rolling back.
    case undone(Int)
    case sweepStarted(Int)
    case allDone
    case reset
    case haptic(OctoHaptic)
}

public enum OctoAnnouncement {
    public static func text(for event: OctoEvent, titles: [String]) -> String? {
        func title(_ i: Int) -> String { titles.indices.contains(i) ? titles[i] : "task" }
        switch event {
        case .ticked(let i): return "Completed \(title(i))"
        case .unticked(let i): return "\(title(i)) not completed"
        case .sweepStarted(let n): return n == 1 ? "Completing 1 task" : "Completing \(n) tasks"
        case .allDone: return "All tasks completed"
        case .reset: return "List reset"
        default: return nil
        }
    }
}

public enum OctoCatalog {
    public static let titles = ["Water the ferns", "Call the dentist back", "Fold the laundry", "Plan Saturday's picnic", "Reply to Sam's note"]
}

/// The checklist over time: one clock per row (running up toward gone, or rolling back before the
/// grab), the sweep scheduler, the list layout while rows collapse, and the events.
public struct OctoModel: Sendable {
    public struct Config: Equatable, Sendable {
        public var reduceMotion = false
        public var hapticInterval = 0.12
        /// Delay between rows when "Complete all" sweeps through the list.
        public var sweepStagger = 0.28
        /// A rolled-back tick runs this much faster than it went forward.
        public var undoRate = 2.0
        public init() {}
    }

    struct Row: Equatable, Sendable {
        var clock = 0.0
        var dir = 0
        var timing = OctoTiming.full
        var startAt: Double?
        var restoreStart: Double?
    }

    public static let restoreDuration = 0.4
    public static let collapseStiffness = 220.0
    public static let collapseDamping = 0.55
    public static let pullStiffness = 150.0
    public static let pullDamping = 0.45

    public var config: Config
    public let titles: [String]
    public private(set) var time = 0.0
    var rows: [Row]
    private var lastHaptic: [OctoHaptic: Double] = [:]
    private var pending: [OctoEvent] = []
    /// Counters for views that react to changes (`onChange`, `sensoryFeedback`) instead of draining events.
    public private(set) var grabHaptics = 0
    public private(set) var goneHaptics = 0
    public private(set) var announcementCount = 0
    public private(set) var announcement: String?

    public init(titles: [String] = OctoCatalog.titles, config: Config = Config()) {
        self.titles = titles
        self.config = config
        rows = Array(repeating: Row(), count: titles.count)
    }

    public var count: Int { titles.count }

    // MARK: State queries

    public func clock(_ i: Int) -> Double { rows[i].clock }
    public func timing(_ i: Int) -> OctoTiming { rows[i].timing }
    public func phase(_ i: Int) -> OctoPhase { rows[i].timing.phase(at: rows[i].clock) }
    public func isGone(_ i: Int) -> Bool { rows[i].dir == 0 && rows[i].clock >= rows[i].timing.total }
    /// The row's toggle value: ticked, and not rolling back.
    public func isChecked(_ i: Int) -> Bool { rows[i].dir > 0 || isGone(i) }
    public func isCommitted(_ i: Int) -> Bool { rows[i].dir > 0 && rows[i].clock >= rows[i].timing.commit }
    public var goneCount: Int { rows.indices.filter(isGone).count }
    public var isAllDone: Bool { goneCount == count }

    /// Rows "Complete all" would still send the ink through.
    func sweepTargets() -> [Int] {
        rows.indices.filter { i in
            let r = rows[i]
            if r.startAt != nil || isGone(i) { return false }
            if r.dir > 0 { return false }                       // already on its way
            return true                                         // idle, or rolling back
        }
    }
    public var canCompleteAll: Bool { !sweepTargets().isEmpty }
    /// Whether there is anything for Reset to bring back or undo.
    public var canReset: Bool { rows.contains { $0.clock > 0 || $0.startAt != nil || $0.dir != 0 } }

    public var isBusy: Bool {
        rows.contains { $0.dir != 0 || $0.startAt != nil || ($0.restoreStart.map { time - $0 < Self.restoreDuration } ?? false) }
    }
    public var isIdle: Bool { !isBusy && pending.isEmpty }

    // MARK: Input

    /// Tap a row's circle. Idle → tick. Before the grab → undo (and tap again to re-tick). After it, or
    /// once gone → ignored. Returns whether the tap did anything.
    @discardableResult
    public mutating func tap(_ i: Int, at t: Double) -> Bool {
        step(to: t)
        guard rows.indices.contains(i) else { return false }
        if rows[i].startAt != nil {
            rows[i].startAt = nil
            begin(i)
            return true
        }
        if isGone(i) { return false }
        if rows[i].dir == 0 { begin(i); return true }
        if rows[i].dir < 0 { rows[i].dir = 1; emit(.ticked(i)); return true }
        if rows[i].clock < rows[i].timing.commit {
            rows[i].dir = -1
            emit(.unticked(i))
            return true
        }
        return false
    }

    /// Sends the ink through every remaining row in turn, `sweepStagger` apart. Returns how many rows.
    @discardableResult
    public mutating func completeAll(at t: Double) -> Int {
        step(to: t)
        let targets = sweepTargets()
        guard !targets.isEmpty else { return 0 }
        for (k, i) in targets.enumerated() { rows[i].startAt = time + Double(k) * config.sweepStagger }
        emit(.sweepStarted(targets.count))
        return targets.count
    }

    /// Brings everything back: gone rows grow back in, anything mid-flight snaps to unticked.
    @discardableResult
    public mutating func reset(at t: Double) -> Bool {
        step(to: t)
        var changed = false
        for i in rows.indices {
            if isGone(i) { rows[i] = Row(restoreStart: time); changed = true }
            else if rows[i].clock > 0 || rows[i].dir != 0 || rows[i].startAt != nil { rows[i] = Row(); changed = true }
        }
        if changed { emit(.reset) }
        return changed
    }

    private mutating func emit(_ e: OctoEvent) {
        pending.append(e)
        switch e {
        case .haptic(.grab): grabHaptics += 1
        case .haptic(.gone): goneHaptics += 1
        default:
            if let text = OctoAnnouncement.text(for: e, titles: titles) { announcement = text; announcementCount += 1 }
        }
    }

    private mutating func begin(_ i: Int) {
        rows[i].timing = config.reduceMotion ? .reduced : .full
        rows[i].dir = 1
        rows[i].restoreStart = nil
        emit(.ticked(i))
    }

    // MARK: Time

    /// Moves time forward and returns what happened since the last call, in order.
    @discardableResult
    public mutating func advance(to t: Double) -> [OctoEvent] {
        step(to: t)
        let out = pending
        pending = []
        return out
    }

    private mutating func step(to t: Double) {
        let t2 = t.isFinite ? max(t, time) : time
        let prev = time
        for i in rows.indices {
            var from = prev
            if let s = rows[i].startAt, s <= t2 {
                rows[i].startAt = nil
                from = max(prev, s)
                begin(i)
            }
            guard rows[i].dir != 0 else { continue }
            let dt = t2 - from
            let old = rows[i].clock
            if rows[i].dir > 0 {
                rows[i].clock = old + dt
                if old < rows[i].timing.commit, rows[i].clock >= rows[i].timing.commit {
                    emit(.grabbed(i))
                    haptic(.grab, at: t2)
                }
                if rows[i].clock >= rows[i].timing.total {
                    rows[i].clock = rows[i].timing.total
                    rows[i].dir = 0
                    emit(.gone(i))
                    haptic(.gone, at: t2)
                    if isAllDone { emit(.allDone) }
                }
            } else {
                rows[i].clock = old - dt * config.undoRate
                if rows[i].clock <= 0 {
                    rows[i].clock = 0
                    rows[i].dir = 0
                    emit(.undone(i))
                }
            }
        }
        time = t2
    }

    private mutating func haptic(_ kind: OctoHaptic, at t: Double) {
        if t - (lastHaptic[kind] ?? -Double.infinity) >= config.hapticInterval {
            lastHaptic[kind] = t
            emit(.haptic(kind))
        }
    }

    // MARK: Frames

    /// Collapse progress for a row clock (spring for the full timeline, a plain ease when reduced).
    public static func collapse(clock: Double, timing: OctoTiming) -> Double {
        let raw = OctoTiming.progress(clock, from: timing.collapseStart, to: timing.collapseEnd)
        if timing.isReduced { return WhimsyMath.easeInOutCubic(raw) }
        let dur = timing.collapseEnd - timing.collapseStart
        let s = WhimsySpring.stepResponse(at: raw * dur, stiffness: collapseStiffness, dampingRatio: collapseDamping)
        // Blend onto exactly 1 over the last fifth so the layout lands cleanly.
        return s + (1 - s) * WhimsyMath.smoothstep(0.8, 1, raw)
    }

    /// The restore progress of a row after a reset (1 when it never went away).
    func restore(_ i: Int) -> Double {
        guard let s = rows[i].restoreStart else { return 1 }
        return WhimsyMath.easeOutCubic(OctoTiming.progress(time - s, from: 0, to: Self.restoreDuration))
    }

    public func frame(_ i: Int, top: Double = 0) -> OctoRowFrame {
        let r = rows[i], tm = r.timing, c = r.clock
        let check = WhimsyMath.easeOutCubic(OctoTiming.progress(c, from: 0, to: tm.checkEnd))
        let swell = tm.isReduced ? 0 : WhimsyMath.easeOutCubic(OctoTiming.progress(c, from: tm.checkEnd, to: tm.swellEnd))
        let grab = tm.isReduced ? 0 : WhimsyMath.easeInOutCubic(OctoTiming.progress(c, from: tm.swellEnd, to: tm.grabEnd))
        let pullP = OctoTiming.progress(c, from: tm.grabEnd, to: tm.pullEnd)
        let pullStep = tm.isReduced ? 0 : WhimsySpring.stepResponse(at: c - tm.grabEnd, stiffness: Self.pullStiffness, dampingRatio: Self.pullDamping)
        let stretch = -OctoLayout.grabSquash * sin(Double.pi * grab)
            + OctoLayout.maxStretch * pullStep * (1 - WhimsyMath.smoothstep(0.7, 1, pullP))
        let sy = 1 + stretch
        let collapse = Self.collapse(clock: c, timing: tm)
        let restore = restore(i)
        let opacity = (1 - WhimsyMath.smoothstep(tm.fadeFrom, 1, pullP)) * restore
        let phase = tm.phase(at: c)
        let ink = !tm.isReduced && swell > 0 && phase != .gone && opacity > 0.01
        return OctoRowFrame(index: i, phase: phase, check: check, swell: swell, grab: grab, pull: pullP, collapse: collapse,
                            restore: restore, offsetY: OctoLayout.pullDistance * pullStep, scaleX: 1 / sy, scaleY: sy,
                            opacity: opacity, slotHeight: OctoLayout.pitch * (restore - collapse), top: top,
                            blob: ink ? OctoInk.blob(swell: swell) : nil, showsInk: ink)
    }

    /// All rows with their tops: each slot's height shrinks as its row collapses, so the rows below rise.
    public var frames: [OctoRowFrame] {
        var out: [OctoRowFrame] = []
        var top = 0.0
        for i in rows.indices {
            let f = frame(i, top: top)
            out.append(f)
            top += f.slotHeight
        }
        return out
    }

    /// Height of the list (never negative).
    public var listHeight: Double { max(0, frames.reduce(0) { $0 + $1.slotHeight } - OctoLayout.rowGap) }
}
