import Foundation

public enum BoltStreakEvent: Equatable, Sendable {
    /// `day` joined the completed set and its burn started, or snapped under Reduce Motion.
    case ignited(Weekday)
    /// One tick, fired with the ignition. A queued day ticks when it is asked, not when it later starts.
    case tick
}

/// The week's bolts. Each day is a progress in 0…1. The weekly bolt is the mean of
/// those seven, so it fills as the days burn and matches `weeklyTarget` once they settle.
/// Reduce Motion snaps a day to full, parks the head on the tip, and does not pulse.
public struct BoltStreakModel: Equatable, Sendable {
    public let today: Weekday
    public private(set) var completed: Set<Weekday>
    public private(set) var reduceMotion: Bool
    public private(set) var active: Weekday?
    public private(set) var elapsed: Double
    public private(set) var queue: [Weekday]

    private var progress: [Double]

    public init(completed: Set<Weekday> = [], today: Weekday = .monday, reduceMotion: Bool = false) {
        self.today = today
        self.completed = completed
        self.reduceMotion = reduceMotion
        self.active = nil
        self.elapsed = 0
        self.queue = []
        progress = Weekday.allCases.map { completed.contains($0) ? 1 : 0 }
    }

    public func dayProgress(_ day: Weekday) -> Double { progress[day.rawValue] }

    /// Days in the completed set, divided by seven. Jumps when a day is marked.
    public var weeklyTarget: Double { BoltStreakMath.weeklyTarget(completed: completed) }

    /// Mean of the seven displayed fills. Rises while the active bolt burns.
    public var weeklyProgress: Double {
        progress.reduce(0, +) / Double(BoltStreakTuning.dayCount)
    }

    public var needsClock: Bool { active != nil && !reduceMotion }

    public var canMarkToday: Bool { !completed.contains(today) }

    public var accessibilityLabel: String { BoltStreakTuning.accessibilityLabel }

    /// For example `3 of 7 days. Monday, Tuesday, Wednesday lit. Thursday is today.`
    public var accessibilityValue: String {
        let count = completed.count
        let lit = Weekday.allCases.filter { completed.contains($0) }
        let litText = lit.isEmpty ? "No days lit" : lit.map(\.name).joined(separator: ", ") + " lit"
        let todayText = completed.contains(today) ? "\(today.name) is lit" : "\(today.name) is today"
        return "\(count) of 7 days. \(litText). \(todayText)."
    }

    public func glow(for day: Weekday) -> Double {
        BoltStreakMath.glow(
            progress: dayProgress(day),
            elapsed: elapsed,
            igniting: active == day,
            reduceMotion: reduceMotion
        )
    }

    public var weeklyGlow: Double {
        BoltStreakMath.glow(
            progress: weeklyProgress,
            elapsed: elapsed,
            igniting: active != nil,
            reduceMotion: reduceMotion
        )
    }

    /// Head on the normalised centreline. Nil when the bolt is dark.
    /// While `day` is igniting the head rides `dayProgress`. A settled bolt parks it on the tip.
    /// Reduce Motion never rides: a lit bolt is parked on the tip immediately.
    public func head(for day: Weekday) -> Vec2? {
        let p = dayProgress(day)
        if reduceMotion {
            return completed.contains(day) ? BoltPath.sample(1) : nil
        }
        if active == day { return BoltPath.sample(p) }
        if p <= 0 { return nil }
        return BoltPath.sample(min(p, 1))
    }

    public func headTravels(for day: Weekday) -> Bool {
        !reduceMotion && active == day
    }

    public var weeklyHead: Vec2? {
        if reduceMotion {
            return weeklyProgress > 0 ? BoltPath.sample(weeklyProgress) : nil
        }
        if active != nil || weeklyProgress > 0 { return BoltPath.sample(weeklyProgress) }
        return nil
    }

    public var weeklyHeadTravels: Bool { !reduceMotion && active != nil }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        guard on else { return }
        for day in Weekday.allCases {
            progress[day.rawValue] = completed.contains(day) ? 1 : 0
        }
        active = nil
        elapsed = 0
        queue.removeAll()
    }

    /// Marks `day` and starts its burn, or snaps it when Reduce Motion is on.
    /// A day that is already lit, burning, or waiting does nothing.
    /// A second day asked during a burn waits, and the weekly target still moves now.
    @discardableResult
    public mutating func ignite(_ day: Weekday) -> [BoltStreakEvent] {
        if completed.contains(day) || active == day || queue.contains(day) { return [] }
        completed.insert(day)
        if reduceMotion {
            progress[day.rawValue] = 1
            return [.ignited(day), .tick]
        }
        if active == nil {
            active = day
            elapsed = 0
            progress[day.rawValue] = 0
        } else {
            queue.append(day)
        }
        return [.ignited(day), .tick]
    }

    @discardableResult
    public mutating func igniteToday() -> [BoltStreakEvent] { ignite(today) }

    /// Follows a binding. Removed days go dark at once. Added days ignite in weekday order.
    @discardableResult
    public mutating func setCompleted(_ days: Set<Weekday>) -> [BoltStreakEvent] {
        if days == completed { return [] }
        let removed = completed.subtracting(days)
        if !removed.isEmpty {
            for day in Weekday.allCases where removed.contains(day) {
                progress[day.rawValue] = 0
                completed.remove(day)
            }
            queue.removeAll { removed.contains($0) }
            if let day = active, removed.contains(day) {
                active = nil
                elapsed = 0
            }
            if active == nil { startNext() }
        }
        var events: [BoltStreakEvent] = []
        for day in Weekday.allCases where days.contains(day) {
            events += ignite(day)
        }
        return events
    }

    /// Advances the active burn. Frames longer than `maxFrame` are clamped.
    /// Non-finite, zero and negative steps do nothing. Reduce Motion does not travel.
    @discardableResult
    public mutating func step(_ dt: Double) -> [BoltStreakEvent] {
        guard dt.isFinite, dt > 0, !reduceMotion, let day = active else { return [] }
        let h = min(dt, BoltStreakTuning.maxFrame)
        elapsed += h
        if elapsed >= BoltStreakTuning.ignitionDuration {
            progress[day.rawValue] = 1
            elapsed = 0
            active = nil
            startNext()
            return []
        }
        progress[day.rawValue] = WhimsyMath.smoothstep(0, BoltStreakTuning.ignitionDuration, elapsed)
        return []
    }

    private mutating func startNext() {
        guard active == nil, !queue.isEmpty else { return }
        let day = queue.removeFirst()
        active = day
        elapsed = 0
        progress[day.rawValue] = 0
    }
}

/// The scripted reel the canvas port plays: idle zinc, seven burns, a hold, then a
/// Reduce Motion scene that snaps. `burnFrames` is fixed so both ports share frames.
public enum BoltStreakReel {
    public static let dt = 1.0 / 60.0
    public static let idleFrames = 30
    public static let gapFrames = 8
    public static let holdFrames = 24
    public static let reduceLead = 18
    public static let reduceMid = 24
    public static let reduceHold = 30
    public static let today: Weekday = .sunday

    public static var burnFrames: Int { BoltStreakTuning.burnFrames }

    public static func ignitionFrame(_ index: Int) -> Int {
        idleFrames + index * (burnFrames + gapFrames)
    }

    public static func ignitionIndex(at frame: Int) -> Int? {
        guard frame >= idleFrames else { return nil }
        let stride = burnFrames + gapFrames
        let delta = frame - idleFrames
        if delta % stride != 0 { return nil }
        let index = delta / stride
        guard index >= 0, index < Weekday.allCases.count else { return nil }
        return index
    }

    public static var motionFrames: Int { ignitionFrame(6) + burnFrames + holdFrames }
    public static var reduceStart: Int { motionFrames }
    public static var totalFrames: Int { reduceStart + reduceLead + reduceMid + reduceHold }
    public static var duration: Double { Double(totalFrames) * dt }

    /// Half away from zero, matching `Math.floor(t / dt + 0.5)` for a positive time.
    public static func frameCount(_ time: Double) -> Int {
        guard time.isFinite, time > 0 else { return 0 }
        return Int((time / dt + 0.5).rounded(.down))
    }

    public static func model(at time: Double) -> BoltStreakModel {
        model(atFrame: frameCount(time))
    }

    public static func model(atFrame frame: Int) -> BoltStreakModel {
        if frame >= reduceStart { return reduceModel(local: frame - reduceStart) }
        return motionModel(steps: max(0, frame))
    }

    private static func motionModel(steps: Int) -> BoltStreakModel {
        var model = BoltStreakModel(completed: [], today: today, reduceMotion: false)
        for frame in 0..<max(0, steps) {
            if let index = ignitionIndex(at: frame) {
                _ = model.ignite(Weekday.allCases[index])
            }
            _ = model.step(dt)
        }
        return model
    }

    private static func reduceModel(local: Int) -> BoltStreakModel {
        var model = BoltStreakModel(completed: [], today: today, reduceMotion: true)
        if local >= reduceLead {
            _ = model.ignite(.monday)
            _ = model.ignite(.tuesday)
            _ = model.ignite(.wednesday)
        }
        if local >= reduceLead + reduceMid {
            _ = model.ignite(.thursday)
            _ = model.ignite(.friday)
            _ = model.ignite(.saturday)
            _ = model.ignite(.sunday)
        }
        let ticks = min(max(local, 0), 3)
        for _ in 0..<ticks { _ = model.step(dt) }
        return model
    }
}
