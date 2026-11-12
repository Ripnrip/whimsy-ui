import Foundation

/// What the picker did. The view turns `landed` into a rate-limited haptic and `selected` into speech.
public enum NeighborBounceEvent: Equatable, Sendable {
    /// The selection index changed.
    case selected(Int)
    /// The already-selected tick was chosen again. The wave still plays.
    case nudged(Int)
    /// A staggered kick was applied to this tick. Position is unchanged at this instant; velocity is not.
    case launched(Int)
    /// This tick crossed back down through the landing band fast enough, and the haptic gap allowed it.
    case landed(Int)
    /// Every spring is at rest and no kick is waiting.
    case settled
}

/// Pure-Swift segmented control.
///
/// Choosing a tick retargets the selection pill and adds an upward, outward velocity to every other
/// tick. The kick is staggered by distance and multiplied by ``NeighborBounceTuning/decay`` at each
/// step. Springs are never zeroed on a new selection, so a second tap continues from the current
/// position and velocity. Unfired kicks from the previous wave are dropped. Reduce Motion snaps the
/// pill and leaves every tick seated.
public struct NeighborBounceModel: Equatable, Sendable {
    public let count: Int
    public private(set) var selection: Int
    public private(set) var time: Double = 0
    public private(set) var reduceMotion: Bool
    public private(set) var launches = 0
    public private(set) var landings = 0
    public private(set) var suppressedLandings = 0
    public private(set) var settles = 0

    struct PendingKick: Equatable, Sendable {
        var fireAt: Double
        var index: Int
        var velocity: Vec2
    }

    var pending: [PendingKick] = []
    var indicator: WhimsySpring
    var indicatorTarget: Double
    var offsets: [WhimsySpring2D]
    var scales: [WhimsySpring]
    var airborne: [Bool]
    var wasHigh: [Bool]
    var wasMoving = false
    var lastLandingTime: Double? = nil

    public init(count: Int = NeighborBounceLayout.defaultTicks, selection: Int = 0, reduceMotion: Bool = false) {
        let n = NeighborBounceLayout.clampedCount(count)
        self.count = n
        self.reduceMotion = reduceMotion
        let s = min(max(selection, 0), n - 1)
        self.selection = s
        let target = NeighborBounceLayout.restCenter(index: s, count: n).x
        self.indicatorTarget = target
        self.indicator = WhimsySpring(
            value: target,
            velocity: 0,
            stiffness: NeighborBounceTuning.indicatorStiffness,
            dampingRatio: NeighborBounceTuning.indicatorDamping
        )
        self.offsets = (0..<n).map { _ in
            WhimsySpring2D(
                value: .zero,
                stiffness: NeighborBounceTuning.offsetStiffness,
                dampingRatio: NeighborBounceTuning.offsetDamping
            )
        }
        self.scales = (0..<n).map { i in
            WhimsySpring(
                value: i == s ? NeighborBounceTuning.selectedScale : 1,
                velocity: 0,
                stiffness: NeighborBounceTuning.scaleStiffness,
                dampingRatio: NeighborBounceTuning.scaleDamping
            )
        }
        self.airborne = Array(repeating: false, count: n)
        self.wasHigh = Array(repeating: false, count: n)
    }

    // MARK: reads

    public var indicatorX: Double { indicator.value }
    public var indicatorVelocity: Double { indicator.velocity }
    public var pendingCount: Int { pending.count }

    public func offset(_ index: Int) -> Vec2 { offsets[slot(index)].value }
    public func velocity(_ index: Int) -> Vec2 { offsets[slot(index)].velocity }
    public func scale(_ index: Int) -> Double { scales[slot(index)].value }

    public func pose(_ index: Int) -> NeighborBouncePose {
        let i = slot(index)
        let o = offsets[i].value
        let sc = scales[i].value
        let stretch = WhimsyMath.clamp(-offsets[i].y.velocity / NeighborBounceTuning.stretchDivisor,
                                        -NeighborBounceTuning.stretchLimit,
                                        NeighborBounceTuning.stretchLimit)
        return NeighborBouncePose(
            center: NeighborBounceLayout.restCenter(index: i, count: count) + o,
            scaleX: sc * (1 - NeighborBounceTuning.stretchLateral * stretch),
            scaleY: sc * (1 + stretch),
            lift: max(0, -o.y)
        )
    }

    /// VoiceOver text for the current selection. A missing title falls back to "Tick n".
    public func spokenSelection(titles: [String]) -> String {
        let title: String
        if selection >= 0, selection < titles.count, !titles[selection].isEmpty {
            title = titles[selection]
        } else {
            title = "Tick \(selection + 1)"
        }
        return "\(title), selected"
    }

    public var isResting: Bool { !isMoving }

    // MARK: inputs

    /// Select `index` (clamped). Does not change positions or velocities. Schedules a new wave,
    /// replacing any kick that has not fired yet.
    @discardableResult
    public mutating func select(_ index: Int) -> [NeighborBounceEvent] {
        let i = slot(index)
        let changed = i != selection
        selection = i
        indicatorTarget = NeighborBounceLayout.restCenter(index: i, count: count).x
        if reduceMotion {
            snapDynamics()
            return [changed ? .selected(i) : .nudged(i)]
        }
        pending.removeAll()
        for j in 0..<count where j != i {
            let distance = abs(j - i)
            let sign = j > i ? 1.0 : -1.0
            pending.append(PendingKick(
                fireAt: time + NeighborBounceTuning.stagger * Double(distance),
                index: j,
                velocity: NeighborBounceWave.impulse(distance: distance, sign: sign)
            ))
        }
        pending.sort { a, b in
            if a.fireAt != b.fireAt { return a.fireAt < b.fireAt }
            return a.index < b.index
        }
        return [changed ? .selected(i) : .nudged(i)]
    }

    /// Turning Reduce Motion on drops the wave and seats every tick. Turning it off changes nothing
    /// that is already on screen; the next selection is the one that springs.
    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        let moving = isMoving
        reduceMotion = on
        if on {
            snapDynamics()
            if moving { wasMoving = true }
        }
    }

    /// Advance by `dt` seconds. Non-finite or non-positive input is ignored. A frame longer than
    /// ``NeighborBounceTuning/maxFrame`` is clamped.
    @discardableResult
    public mutating func step(_ dt: Double) -> [NeighborBounceEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        var events: [NeighborBounceEvent] = []
        var remaining = min(dt, NeighborBounceTuning.maxFrame)
        while remaining > 1e-12 {
            let h = min(remaining, NeighborBounceTuning.substep)
            events += substep(h)
            remaining -= h
        }
        let moving = isMoving
        if wasMoving && !moving {
            settles += 1
            events.append(.settled)
        }
        wasMoving = moving
        return events
    }

    /// One line of the parity trace: hex doubles, then counters, then each tick.
    public func traceLine() -> String {
        var parts: [String] = [
            NeighborBounceMath.hex(time),
            String(selection),
            reduceMotion ? "1" : "0",
            NeighborBounceMath.hex(indicator.value),
            NeighborBounceMath.hex(indicator.velocity),
            String(pending.count),
            String(landings),
            String(suppressedLandings),
            String(launches),
        ]
        for i in 0..<count {
            parts.append(NeighborBounceMath.hex(offsets[i].x.value))
            parts.append(NeighborBounceMath.hex(offsets[i].y.value))
            parts.append(NeighborBounceMath.hex(offsets[i].x.velocity))
            parts.append(NeighborBounceMath.hex(offsets[i].y.velocity))
            parts.append(NeighborBounceMath.hex(scales[i].value))
            let drawn = pose(i)
            parts.append(NeighborBounceMath.hex(drawn.scaleX))
            parts.append(NeighborBounceMath.hex(drawn.scaleY))
            parts.append(NeighborBounceMath.hex(drawn.lift))
            parts.append(NeighborBounceMath.hex(drawn.center.x))
            parts.append(NeighborBounceMath.hex(drawn.center.y))
        }
        return parts.joined(separator: " ")
    }

    // MARK: integration

    private func slot(_ index: Int) -> Int { min(max(index, 0), count - 1) }

    private func scaleTarget(_ index: Int) -> Double {
        index == selection ? NeighborBounceTuning.selectedScale : 1
    }

    private var isMoving: Bool {
        if !pending.isEmpty { return true }
        if !indicator.isSettled(at: indicatorTarget) { return true }
        for i in 0..<count {
            if !offsets[i].isSettled(at: .zero) { return true }
            if !scales[i].isSettled(at: scaleTarget(i)) { return true }
        }
        return false
    }

    private mutating func snapDynamics() {
        pending.removeAll()
        for i in 0..<count {
            offsets[i].snap(to: .zero)
            scales[i].snap(to: scaleTarget(i))
            airborne[i] = false
            wasHigh[i] = false
        }
        indicator.snap(to: indicatorTarget)
    }

    private mutating func substep(_ h: Double) -> [NeighborBounceEvent] {
        var events: [NeighborBounceEvent] = []
        time += h
        while let kick = pending.first, kick.fireAt <= time + 1e-9 {
            pending.removeFirst()
            offsets[kick.index].x.velocity += kick.velocity.x
            offsets[kick.index].y.velocity += kick.velocity.y
            airborne[kick.index] = true
            launches += 1
            events.append(.launched(kick.index))
        }
        for i in 0..<count {
            offsets[i].substep(toward: .zero, h: h)
            scales[i].substep(toward: scaleTarget(i), h: h)
            events += landing(i)
        }
        indicator.substep(toward: indicatorTarget, h: h)
        return events
    }

    private mutating func landing(_ i: Int) -> [NeighborBounceEvent] {
        let y = offsets[i].y.value
        let vy = offsets[i].y.velocity
        let high = y < -NeighborBounceTuning.landBand
        var events: [NeighborBounceEvent] = []
        if airborne[i], wasHigh[i], !high, vy > NeighborBounceTuning.landSpeed {
            airborne[i] = false
            if let last = lastLandingTime, time - last < NeighborBounceTuning.hapticGap {
                suppressedLandings += 1
            } else {
                lastLandingTime = time
                landings += 1
                events.append(.landed(i))
            }
        }
        wasHigh[i] = high
        return events
    }
}

/// The session the web preview replays. Step counts are exact multiples of the 1/240 s substep.
public enum NeighborBounceTrace {
    public static func parityLines(stride: Int = 4) -> [String] {
        var lines: [String] = []
        for n in 5...7 {
            for i in 0..<n {
                let p = NeighborBounceLayout.restCenter(index: i, count: n)
                lines.append("L \(n) \(i) \(NeighborBounceMath.hex(p.x)) \(NeighborBounceMath.hex(p.y))")
            }
        }
        for distance in 1...6 {
            let v = NeighborBounceWave.impulse(distance: distance, sign: 1)
            lines.append("K \(distance) \(NeighborBounceMath.hex(v.x)) \(NeighborBounceMath.hex(v.y))")
        }
        let fitted = NeighborTick.fitted([])
        lines.append("F \(fitted.count) " + fitted.map(\.id).joined(separator: ","))

        var model = NeighborBounceModel(count: 6, selection: 0)
        lines.append(model.traceLine())
        func run(_ steps: Int) {
            for i in 0..<steps {
                _ = model.step(NeighborBounceTuning.substep)
                if stride > 0, (i + 1) % stride == 0 { lines.append(model.traceLine()) }
            }
        }
        run(8)
        _ = model.select(3)
        lines.append(model.traceLine())
        run(48)
        _ = model.select(1)
        lines.append(model.traceLine())
        run(16)
        _ = model.select(5)
        lines.append(model.traceLine())
        run(12)
        _ = model.select(5)
        lines.append(model.traceLine())
        run(240)
        model.setReduceMotion(true)
        lines.append(model.traceLine())
        _ = model.select(2)
        lines.append(model.traceLine())
        run(24)
        model.setReduceMotion(false)
        lines.append(model.traceLine())
        _ = model.select(0)
        lines.append(model.traceLine())
        run(200)
        lines.append(model.traceLine())
        return lines
    }
}
