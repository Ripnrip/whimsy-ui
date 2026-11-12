import Foundation

public enum RubberBandPhase: Int, CaseIterable, Sendable, Equatable {
    /// Cards are in the fan. A lift spring may still be settling.
    case resting
    /// A finger is on the hand and the nearest card is lifted.
    case browsing
    /// A card is locked to the finger and fighting the rubber band.
    case dragging
    /// Springing to the centre and turning over.
    case presenting
    /// Detail is showing.
    case presented
    /// The centred card is being pulled down.
    case dismissing
    /// Springing back into its slot.
    case returning
}

public enum RubberBandEvent: Equatable, Sendable {
    /// The hover moved onto this card. One event per newly lifted card, for a light haptic.
    case lifted(Int)
    case grabbed(Int)
    /// The drag crossed the commit rise.
    case armed(Int)
    case committed(Int)
    /// The card has arrived, face up on its detail.
    case presented(Int)
    /// A centred card was asked to leave (the spring home follows).
    case dismissed(Int)
    /// The card is back in the fan.
    case restored(Int)
}

/// Everything the view needs to place one card for one frame.
public struct RubberBandPose: Equatable, Sendable {
    public var index: Int
    public var center: Vec2
    public var rotation: Double
    /// Points the card sits above its rest centre. Already baked into `center.y`.
    public var lift: Double
    public var scale: Double
    /// 0 is the picture, 1 is the detail. The view turns this into a half-revolution.
    public var flip: Double
    public var opacity: Double
    public var z: Int
}

/// The fan: hover to lift, drag up through a rubber band, flick or cross the line and the
/// card springs to centre and turns over. Let go early and it springs home.
///
/// Pure Foundation (through WhimsyCore). `step` is deterministic: fixed spring substeps, no clock.
public struct RubberBandModel: Sendable {
    public private(set) var phase = RubberBandPhase.resting
    public private(set) var focusIndex: Int?
    public private(set) var activeIndex: Int?
    public private(set) var pullUp = 0.0
    public private(set) var pullRight = 0.0
    public private(set) var isArmed = false
    public private(set) var lastRelease = RubberBandRelease.springBack
    public private(set) var reduceMotion: Bool
    public private(set) var time = 0.0
    public private(set) var phaseTime = 0.0

    public private(set) var liftEvents = 0
    public private(set) var grabs = 0
    public private(set) var commits = 0
    public private(set) var presentations = 0
    public private(set) var restores = 0

    private var lifts: [WhimsySpring]
    private var flightX = WhimsySpring()
    private var flightY = WhimsySpring()
    private var flightRot = WhimsySpring()
    private var flightFlip = WhimsySpring()
    private var flightScale = WhimsySpring()
    private var flightTarget = Vec2.zero
    private var flightTargetRot = 0.0
    private var flightTargetFlip = 0.0
    private var flightTargetScale = 1.0
    private var announceArrival = false

    private var anchor = Vec2.zero
    private var lastPoint = Vec2.zero
    private var dragFinger = Vec2.zero
    private var dragBaseLift = 0.0
    private var dismissFinger = Vec2.zero
    private var tracker = RubberBandVelocity()
    private var reportedGrab = false

    public static let maxStep = 0.25
    /// A flight that has not settled by now is snapped home, so a stalled spring cannot stick.
    public static let flightCap = 2.4

    private static let liftStiffness = 520.0
    private static let liftDamping = 0.72
    private static let presentStiffness = 190.0
    private static let presentDamping = 0.76
    private static let returnStiffness = 260.0
    private static let returnDamping = 0.86
    private static let flipStiffness = 120.0
    private static let flipDamping = 1.0

    public init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
        lifts = (0..<RubberBandLayout.count).map { _ in
            WhimsySpring(value: 0, velocity: 0, stiffness: Self.liftStiffness, dampingRatio: Self.liftDamping)
        }
    }

    // MARK: derived

    public var scrim: Double { 0.45 * openness }

    /// 0 in the hand, 1 when the detail is fully facing us.
    public var openness: Double {
        switch phase {
        case .presenting, .returning, .dismissing: return WhimsyMath.clamp01(flightFlip.value)
        case .presented: return 1
        default: return 0
        }
    }

    public var needsDisplayLink: Bool {
        if phase == .presenting || phase == .returning { return true }
        for i in 0..<RubberBandLayout.count where i != (isFlyingCard ? activeIndex : nil) {
            let target = liftTarget(i)
            if abs(lifts[i].value - target) > 0.04 || abs(lifts[i].velocity) > 0.2 { return true }
        }
        return false
    }

    private var isFlyingCard: Bool { phase == .presenting || phase == .presented || phase == .dismissing || phase == .returning }

    public func liftTarget(_ index: Int) -> Double {
        guard phase == .browsing, focusIndex == index else { return 0 }
        return RubberBandLayout.hoverLift
    }

    public func pose(_ index: Int) -> RubberBandPose {
        let i = RubberBandLayout.clamped(index)
        let rest = RubberBandLayout.restCenter(i)
        let restRot = RubberBandLayout.restRotation(i)
        let dim: Double = (activeIndex == i) ? 1 : (1 - 0.4 * openness)
        if activeIndex == i, phase == .dragging {
            let extra = max(0, RubberBandResistance.resist(pullUp))
            let up = max(0, dragBaseLift + RubberBandResistance.resist(pullUp))
            let side = RubberBandResistance.resist(pullRight)
            let straighten = WhimsyMath.smoothstep(0, RubberBandLayout.commitRise, extra)
            return RubberBandPose(
                index: i,
                center: Vec2(rest.x + side, rest.y - up),
                rotation: restRot * (1 - straighten),
                lift: up,
                scale: 1.04 + 0.06 * straighten,
                flip: 0,
                opacity: 1,
                z: 20
            )
        }
        if activeIndex == i, phase == .dismissing {
            let dx = RubberBandResistance.resist(pullRight)
            let dy = RubberBandResistance.resist(pullUp) // pullUp is negative when the finger goes down; resist keeps the sign
            // pullUp is stored as upward. During dismiss we store upward as well, so a downward
            // pull is negative and the card follows it (screen y grows).
            let center = Vec2(RubberBandLayout.stage.x + dx, RubberBandLayout.stage.y - dy)
            return RubberBandPose(
                index: i,
                center: center,
                rotation: 0,
                lift: rest.y - center.y,
                scale: RubberBandLayout.presentedScale,
                flip: 1,
                opacity: 1,
                z: 20
            )
        }
        if activeIndex == i, isFlyingCard {
            let center = Vec2(flightX.value, flightY.value)
            return RubberBandPose(
                index: i,
                center: center,
                rotation: flightRot.value,
                lift: rest.y - center.y,
                scale: max(0.4, flightScale.value),
                flip: WhimsyMath.clamp01(flightFlip.value),
                opacity: 1,
                z: 20
            )
        }
        let lift = max(0, lifts[i].value)
        let raised = WhimsyMath.clamp01(lift / RubberBandLayout.hoverLift)
        return RubberBandPose(
            index: i,
            center: Vec2(rest.x, rest.y - lift),
            rotation: restRot,
            lift: lift,
            scale: 1 + 0.04 * raised,
            flip: 0,
            opacity: dim,
            z: i
        )
    }

    public var poses: [RubberBandPose] { (0..<RubberBandLayout.count).map { pose($0) } }

    public var drawOrder: [Int] {
        (0..<RubberBandLayout.count).sorted { pose($0).z < pose($1).z }
    }

    // MARK: input

    @discardableResult
    public mutating func pointerDown(at point: Vec2, at timestamp: Double? = nil) -> [RubberBandEvent] {
        guard point.x.isFinite, point.y.isFinite else { return [] }
        let t = timestamp ?? time
        switch phase {
        case .resting, .browsing:
            anchor = point
            lastPoint = point
            pullUp = 0
            pullRight = 0
            isArmed = false
            tracker.reset()
            tracker.add(point, at: t)
            phase = .browsing
            phaseTime = 0
            return retarget(point)
        case .presented:
            anchor = point
            lastPoint = point
            pullUp = 0
            pullRight = 0
            tracker.reset()
            tracker.add(point, at: t)
            return []
        default:
            return []
        }
    }

    @discardableResult
    public mutating func pointerMoved(to point: Vec2, at timestamp: Double? = nil) -> [RubberBandEvent] {
        guard point.x.isFinite, point.y.isFinite else { return [] }
        let t = timestamp ?? time
        switch phase {
        case .browsing:
            tracker.add(point, at: t)
            let up = anchor.y - point.y
            let right = point.x - anchor.x
            if let focus = focusIndex, up > RubberBandLayout.grabSlop, up > abs(right) {
                beginDrag(index: focus)
                return applyDrag(to: point)
            }
            let events = retarget(point)
            lastPoint = point
            return events
        case .dragging:
            tracker.add(point, at: t)
            return applyDrag(to: point)
        case .presented:
            let down = point.y - anchor.y
            let right = point.x - anchor.x
            if down > RubberBandLayout.grabSlop, down > abs(right) {
                beginDismiss(finger: lastPoint)
                tracker.add(point, at: t)
                return applyDismiss(to: point)
            }
            lastPoint = point
            return []
        case .dismissing:
            tracker.add(point, at: t)
            return applyDismiss(to: point)
        default:
            return []
        }
    }

    @discardableResult
    public mutating func pointerUp(at point: Vec2, at timestamp: Double? = nil) -> [RubberBandEvent] {
        let p = (point.x.isFinite && point.y.isFinite) ? point : lastPoint
        let t = timestamp ?? time
        tracker.add(p, at: t)
        switch phase {
        case .browsing:
            focusIndex = nil
            phase = .resting
            phaseTime = 0
            if reduceMotion { snapLifts() }
            return []
        case .dragging:
            guard let i = activeIndex else { return [] }
            let v = tracker.velocity(at: t)
            let release = RubberBandResistance.decide(pullUp: pullUp, upwardVelocity: v.y)
            lastRelease = release
            isArmed = false
            if release.commits {
                commits += 1
                return [.committed(i)] + beginFlight(presenting: true, velocity: visualVelocity(v))
            }
            return beginFlight(presenting: false, velocity: visualVelocity(v))
        case .presented:
            let travel = (p - anchor).length
            if travel < 12, !RubberBandLayout.presentedContains(p), !RubberBandLayout.presentedContains(anchor) {
                return dismiss()
            }
            return []
        case .dismissing:
            guard let i = activeIndex else { return [] }
            let v = tracker.velocity(at: t)
            let down = -pullUp
            let release = RubberBandResistance.decideDismiss(pullDown: down, downwardVelocity: -v.y)
            lastRelease = release
            if release.commits {
                return [.dismissed(i)] + beginFlight(presenting: false, velocity: visualVelocity(v))
            }
            return beginFlight(presenting: true, velocity: visualVelocity(v), announce: false)
        default:
            return []
        }
    }

    @discardableResult
    public mutating func pointerCancel() -> [RubberBandEvent] {
        switch phase {
        case .browsing:
            focusIndex = nil
            phase = .resting
            phaseTime = 0
            if reduceMotion { snapLifts() }
            return []
        case .dragging:
            return beginFlight(presenting: false, velocity: .zero)
        case .dismissing:
            return beginFlight(presenting: true, velocity: .zero, announce: false)
        default:
            return []
        }
    }

    /// Opens a card without a drag. VoiceOver uses this. Refused unless the hand is at rest.
    @discardableResult
    public mutating func activate(_ index: Int) -> [RubberBandEvent] {
        guard index >= 0, index < RubberBandLayout.count else { return [] }
        guard phase == .resting else { return [] }
        focusIndex = nil
        activeIndex = index
        pullUp = 0
        pullRight = 0
        isArmed = false
        lastRelease = .commitDrag
        commits += 1
        let rest = RubberBandLayout.restCenter(index)
        flightX = WhimsySpring(value: rest.x, velocity: 0, stiffness: Self.presentStiffness, dampingRatio: Self.presentDamping)
        flightY = WhimsySpring(value: rest.y, velocity: 0, stiffness: Self.presentStiffness, dampingRatio: Self.presentDamping)
        flightRot = WhimsySpring(value: RubberBandLayout.restRotation(index), velocity: 0, stiffness: Self.returnStiffness, dampingRatio: Self.returnDamping)
        flightFlip = WhimsySpring(value: 0, velocity: 0, stiffness: Self.flipStiffness, dampingRatio: Self.flipDamping)
        flightScale = WhimsySpring(value: 1, velocity: 0, stiffness: Self.presentStiffness, dampingRatio: Self.presentDamping)
        aimFlight(presenting: true)
        if reduceMotion {
            snapPresented(announce: true)
            return [.committed(index), .presented(index)]
        }
        phase = .presenting
        phaseTime = 0
        announceArrival = true
        return [.committed(index)]
    }

    /// Puts the centred card back. Works while it is opening, open, or being pulled down.
    @discardableResult
    public mutating func dismiss() -> [RubberBandEvent] {
        guard let i = activeIndex else { return [] }
        switch phase {
        case .presenting, .presented, .dismissing:
            return [.dismissed(i)] + beginFlight(presenting: false, velocity: .zero)
        default:
            return []
        }
    }

    @discardableResult
    public mutating func setReduceMotion(_ on: Bool) -> [RubberBandEvent] {
        guard on != reduceMotion else { return [] }
        reduceMotion = on
        guard on else { return [] }
        switch phase {
        case .presenting:
            return snapPresented(announce: announceArrival)
        case .returning, .dismissing:
            return snapHome()
        default:
            snapLifts()
            return []
        }
    }

    // MARK: time

    @discardableResult
    public mutating func step(_ dt: Double) -> [RubberBandEvent] {
        let total = dt.isFinite ? min(max(dt, 0), Self.maxStep) : 0
        guard total > 0 else { return [] }
        var left = total
        var events: [RubberBandEvent] = []
        while left > 1e-12 {
            let h = min(left, WhimsySpring.maxFrame)
            time += h
            phaseTime += h
            integrate(h)
            events += finishIfNeeded()
            left -= h
        }
        return events
    }

    // MARK: private

    private mutating func retarget(_ point: Vec2) -> [RubberBandEvent] {
        let next = RubberBandLayout.nearestIndex(to: point, current: focusIndex)
        guard next != focusIndex else {
            if reduceMotion { snapLifts() }
            return []
        }
        focusIndex = next
        if reduceMotion { snapLifts() }
        guard let next else { return [] }
        liftEvents += 1
        return [.lifted(next)]
    }

    private mutating func beginDrag(index: Int) {
        activeIndex = index
        dragFinger = lastPoint
        dragBaseLift = lifts[index].value
        pullUp = 0
        pullRight = 0
        isArmed = false
        reportedGrab = false
        phase = .dragging
        phaseTime = 0
        grabs += 1
    }

    /// Pull is measured from the finger position *before* this move, so the stroke that
    /// crosses the grab slop still counts. `.grabbed` is emitted once, on that stroke.
    private mutating func applyDrag(to point: Vec2) -> [RubberBandEvent] {
        pullRight = point.x - dragFinger.x
        pullUp = dragFinger.y - point.y
        lastPoint = point
        guard let i = activeIndex else { return [] }
        var events: [RubberBandEvent] = []
        if !reportedGrab {
            reportedGrab = true
            events.append(.grabbed(i))
        }
        let crossed = RubberBandResistance.resist(pullUp) >= RubberBandLayout.commitRise
        if crossed && !isArmed {
            isArmed = true
            events.append(.armed(i))
        } else if !crossed {
            isArmed = false
        }
        return events
    }

    private mutating func beginDismiss(finger: Vec2) {
        phase = .dismissing
        phaseTime = 0
        dismissFinger = finger
        pullUp = 0
        pullRight = 0
        // The centred card is already fully flipped; keep the flight values there for scrim.
        flightFlip.snap(to: 1)
        flightX.snap(to: RubberBandLayout.stage.x)
        flightY.snap(to: RubberBandLayout.stage.y)
    }

    private mutating func applyDismiss(to point: Vec2) -> [RubberBandEvent] {
        pullRight = point.x - dismissFinger.x
        pullUp = dismissFinger.y - point.y
        lastPoint = point
        return []
    }

    private func visualVelocity(_ finger: Vec2) -> Vec2 {
        let sx = RubberBandResistance.slope(at: pullRight)
        let sy = RubberBandResistance.slope(at: pullUp)
        // finger.y is already upward-positive. Screen y grows downward.
        return Vec2(finger.x * sx, -finger.y * sy)
    }

    @discardableResult
    private mutating func beginFlight(presenting: Bool, velocity: Vec2, announce: Bool = true) -> [RubberBandEvent] {
        let current = currentFlightPose()
        let k = presenting ? Self.presentStiffness : Self.returnStiffness
        let z = presenting ? Self.presentDamping : Self.returnDamping
        flightX = WhimsySpring(value: current.center.x, velocity: velocity.x, stiffness: k, dampingRatio: z)
        flightY = WhimsySpring(value: current.center.y, velocity: velocity.y, stiffness: k, dampingRatio: z)
        flightRot = WhimsySpring(value: current.rotation, velocity: 0, stiffness: Self.returnStiffness, dampingRatio: Self.returnDamping)
        flightFlip = WhimsySpring(value: current.flip, velocity: 0, stiffness: Self.flipStiffness, dampingRatio: Self.flipDamping)
        flightScale = WhimsySpring(value: current.scale, velocity: 0, stiffness: k, dampingRatio: z)
        aimFlight(presenting: presenting)
        if let i = activeIndex { lifts[i].snap(to: 0) }
        phase = presenting ? .presenting : .returning
        phaseTime = 0
        announceArrival = presenting && announce
        reportedGrab = false
        if reduceMotion {
            if presenting { return snapPresented(announce: announce) }
            return snapHome()
        }
        return []
    }

    private mutating func aimFlight(presenting: Bool) {
        if presenting {
            flightTarget = RubberBandLayout.stage
            flightTargetRot = 0
            flightTargetFlip = 1
            flightTargetScale = RubberBandLayout.presentedScale
        } else if let i = activeIndex {
            flightTarget = RubberBandLayout.restCenter(i)
            flightTargetRot = RubberBandLayout.restRotation(i)
            flightTargetFlip = 0
            flightTargetScale = 1
        }
    }

    private func currentFlightPose() -> RubberBandPose {
        if let i = activeIndex { return pose(i) }
        return RubberBandPose(index: 0, center: .zero, rotation: 0, lift: 0, scale: 1, flip: 0, opacity: 1, z: 0)
    }

    private mutating func integrate(_ h: Double) {
        if reduceMotion {
            snapLifts()
        } else {
            for i in 0..<RubberBandLayout.count {
                lifts[i].step(toward: liftTarget(i), dt: h)
            }
        }
        guard phase == .presenting || phase == .returning else { return }
        flightX.step(toward: flightTarget.x, dt: h)
        flightY.step(toward: flightTarget.y, dt: h)
        flightRot.step(toward: flightTargetRot, dt: h)
        flightFlip.step(toward: flightTargetFlip, dt: h)
        flightScale.step(toward: flightTargetScale, dt: h)
    }

    private mutating func finishIfNeeded() -> [RubberBandEvent] {
        guard phase == .presenting || phase == .returning else { return [] }
        let timedOut = phaseTime >= Self.flightCap
        guard timedOut || flightSettled() else { return [] }
        if phase == .presenting {
            return snapPresented(announce: announceArrival)
        }
        return snapHome()
    }

    private func flightSettled() -> Bool {
        flightX.isSettled(at: flightTarget.x, tolerance: 0.4)
            && flightY.isSettled(at: flightTarget.y, tolerance: 0.4)
            && flightRot.isSettled(at: flightTargetRot, tolerance: 0.01)
            && flightFlip.isSettled(at: flightTargetFlip, tolerance: 0.02)
            && flightScale.isSettled(at: flightTargetScale, tolerance: 0.01)
    }

    @discardableResult
    private mutating func snapPresented(announce: Bool) -> [RubberBandEvent] {
        flightX.snap(to: RubberBandLayout.stage.x)
        flightY.snap(to: RubberBandLayout.stage.y)
        flightRot.snap(to: 0)
        flightFlip.snap(to: 1)
        flightScale.snap(to: RubberBandLayout.presentedScale)
        phase = .presented
        phaseTime = 0
        pullUp = 0
        pullRight = 0
        focusIndex = nil
        announceArrival = false
        reportedGrab = false
        guard announce, let i = activeIndex else { return [] }
        presentations += 1
        return [.presented(i)]
    }

    @discardableResult
    private mutating func snapHome() -> [RubberBandEvent] {
        let i = activeIndex
        if let i {
            lifts[i].snap(to: 0)
        }
        flightFlip.snap(to: 0)
        phase = .resting
        phaseTime = 0
        activeIndex = nil
        focusIndex = nil
        pullUp = 0
        pullRight = 0
        isArmed = false
        announceArrival = false
        reportedGrab = false
        guard let i else { return [] }
        restores += 1
        return [.restored(i)]
    }

    private mutating func snapLifts() {
        for i in 0..<RubberBandLayout.count {
            lifts[i].snap(to: liftTarget(i))
        }
    }
}
