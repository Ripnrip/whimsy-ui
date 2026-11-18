import Foundation

public enum GlassPourPhase: String, Equatable, Sendable {
    case closed, arming, opening, open, closing
}

public enum GlassPourEvent: Equatable, Sendable {
    case opening
    case opened
    case closing
    case closed
    case selected(Int)
    /// The finger came up before the long-press threshold. The menu stays shut.
    case pulsed
    case haptic
}

public enum GlassPourHit: Equatable, Sendable {
    case drop
    case row(Int)
    case outside
}

/// One row at this instant. `travel` is 0 in the drop and 1 at its seat (a spring may pass 1).
public struct GlassPourRow: Equatable, Sendable {
    public var index: Int
    public var travel: Double
    public var center: Vec2
    public var scale: Double
    public var opacity: Double
    public var wobble: Double
    /// 0 while this row is still fused to the shape above it, 1 once the neck has pinched off.
    public var pinch: Double
    public var destructive: Bool
    public var isVisible: Bool
    public var isInteractive: Bool
}

/// Long-press a glass drop and four rows pour out of it, one after another, tied to the drop
/// by metaball necks. Tap outside, or tap the drop again, and they suck back in. The destructive
/// row takes a small wobble as it lands. Reduce Motion fades the rows in at their seats.
public struct GlassPourModel: Sendable {
    public let items: [GlassDropItem]
    public private(set) var phase = GlassPourPhase.closed
    public private(set) var time = 0.0
    public private(set) var phaseTime = 0.0
    public private(set) var fade = 0.0
    public private(set) var reduceMotion: Bool

    private var travels: [WhimsySpring]
    private var wobbles: [WhimsySpring]
    private var wobbleKicked: [Bool]

    public init(items: [GlassDropItem] = GlassDropItem.defaults, reduceMotion: Bool = false) {
        let source = items.isEmpty ? GlassDropItem.defaults : items
        self.items = Array(source.prefix(GlassPourTuning.maxRows))
        self.reduceMotion = reduceMotion
        let rest = WhimsySpring(value: 0, stiffness: GlassPourTuning.stiffness, dampingRatio: GlassPourTuning.dampingRatio)
        let still = WhimsySpring(value: 0, stiffness: GlassPourTuning.wobbleStiffness, dampingRatio: GlassPourTuning.wobbleDamping)
        travels = Array(repeating: rest, count: self.items.count)
        wobbles = Array(repeating: still, count: self.items.count)
        wobbleKicked = Array(repeating: false, count: self.items.count)
    }

    public var count: Int { items.count }
    public var isExpanded: Bool { phase == .opening || phase == .open || phase == .closing }
    public var animates: Bool {
        switch phase {
        case .arming, .opening, .closing: return true
        case .open:
            guard !reduceMotion else { return false }
            return wobbles.contains { abs($0.value) > 0.001 || abs($0.velocity) > 0.01 }
        case .closed: return false
        }
    }

    /// The drop swells a little while the long-press is arming. Reduce Motion keeps it still.
    public var dropScale: Double {
        guard phase == .arming, !reduceMotion else { return 1 }
        let held = GlassPourTuning.longPress > 0 ? phaseTime / GlassPourTuning.longPress : 1
        return 1 + 0.07 * min(1, max(0, held))
    }

    public var dropAccessibilityLabel: String { "Menu" }
    public var dropAccessibilityHint: String {
        (phase == .closed || phase == .arming) ? "Opens the menu" : "Closes the menu"
    }
    public var dropAccessibilityValue: String {
        (phase == .closed || phase == .arming) ? "Closed" : "Open"
    }

    public var rows: [GlassPourRow] {
        items.indices.map { row($0) }
    }

    public var necks: [GlassPourNeck] {
        guard !reduceMotion else { return [] }
        let visible = rows.filter(\.isVisible).map { GlassPourLayout.pillBlob(center: $0.center, scale: $0.scale) }
        guard !visible.isEmpty else { return [] }
        return GlassPourLayout.necks(drop: GlassPourLayout.dropBlob(scale: dropScale), rows: visible)
    }

    /// Liquid while the rows are travelling. Crisp glass once they have settled, and always
    /// under Reduce Motion (the rows crossfade in place).
    public var usesGoo: Bool {
        guard !reduceMotion else { return false }
        return phase == .opening || phase == .closing
    }

    public func hitTest(_ point: Vec2) -> GlassPourHit {
        if GlassPourLayout.containsDrop(point, scale: dropScale) { return .drop }
        if phase == .opening || phase == .open {
            for row in rows.reversed() where row.isInteractive {
                if GlassPourLayout.containsPill(point, center: row.center, scale: row.scale) {
                    return .row(row.index)
                }
            }
        }
        return .outside
    }

    // MARK: input

    /// Finger down on the drop. From rest this arms a long-press. While the menu is out, it
    /// starts the suck-back. A press during the suck-back is ignored.
    @discardableResult
    public mutating func pressDrop() -> [GlassPourEvent] {
        switch phase {
        case .closed:
            phase = .arming
            phaseTime = 0
            return []
        case .arming:
            return []
        case .opening, .open:
            beginClosing()
            return [.closing]
        case .closing:
            return []
        }
    }

    /// Finger up. A release during the arming window is a short press and does not open.
    @discardableResult
    public mutating func releaseDrop() -> [GlassPourEvent] {
        guard phase == .arming else { return [] }
        phase = .closed
        phaseTime = 0
        return [.pulsed]
    }

    /// VoiceOver activates the drop as a button, so it does not have to hold.
    @discardableResult
    public mutating func activateDrop() -> [GlassPourEvent] {
        switch phase {
        case .closed, .arming, .closing:
            beginOpening()
            return [.opening]
        case .opening, .open:
            beginClosing()
            return [.closing]
        }
    }

    @discardableResult
    public mutating func pressOutside() -> [GlassPourEvent] {
        guard phase == .opening || phase == .open else { return [] }
        beginClosing()
        return [.closing]
    }

    @discardableResult
    public mutating func selectRow(_ index: Int) -> [GlassPourEvent] {
        guard items.indices.contains(index), phase == .opening || phase == .open else { return [] }
        beginClosing()
        return [.selected(index), .closing, .haptic]
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        for index in items.indices {
            wobbles[index].snap(to: 0)
            wobbleKicked[index] = false
        }
        if on {
            switch phase {
            case .opening, .open:
                for index in items.indices { travels[index].snap(to: 1) }
                if phase == .open { fade = 1 }
            case .closing:
                for index in items.indices { travels[index].snap(to: 1) }
            case .closed, .arming:
                fade = 0
                for index in items.indices { travels[index].snap(to: 0) }
            }
        }
    }

    /// Advances the clock by up to `GlassPourTuning.maxFrame` seconds.
    @discardableResult
    public mutating func step(_ dt: Double) -> [GlassPourEvent] {
        guard dt > 0, dt.isFinite else { return [] }
        let h = min(dt, GlassPourTuning.maxFrame)
        time += h
        phaseTime += h
        var events: [GlassPourEvent] = []
        if phase == .arming, phaseTime >= GlassPourTuning.longPress {
            beginOpening()
            events.append(.opening)
        }
        let targets = travelTargets()
        for index in items.indices {
            travels[index].step(toward: targets[index], dt: h)
        }
        if !reduceMotion {
            kickWobbles()
            for index in items.indices {
                wobbles[index].step(toward: 0, dt: h)
            }
            events.append(contentsOf: settleMotion())
        } else {
            events.append(contentsOf: settleFade(h))
        }
        return events
    }

    // MARK: derived rows

    private func row(_ index: Int) -> GlassPourRow {
        let travel = travels[index].value
        let rest = GlassPourLayout.restCenter(index)
        let drop = GlassPourLayout.dropCenter
        let seated = reduceMotion && (phase == .opening || phase == .open || phase == .closing || fade > 0)
        let center = seated ? rest : Vec2(rest.x, drop.y + (rest.y - drop.y) * travel)
        let scale: Double
        if reduceMotion {
            scale = 1
        } else {
            let raw = GlassPourTuning.minScale + (1 - GlassPourTuning.minScale) * travel
            scale = min(GlassPourTuning.maxScale, max(GlassPourTuning.minDrawnScale, raw))
        }
        let opacity = reduceMotion
            ? fade
            : WhimsyMath.smoothstep(GlassPourTuning.labelFrom, GlassPourTuning.labelTo, travel)
        let visible = reduceMotion ? fade > 0.02 : (travel > 0.015 || abs(travels[index].velocity) > 0.02)
        let pinch = pinchAbove(index, center: center, scale: scale, visible: visible)
        let interactive = opacity > 0.5 && (phase == .opening || phase == .open)
        return GlassPourRow(
            index: index, travel: travel, center: center, scale: scale, opacity: opacity,
            wobble: reduceMotion ? 0 : wobbles[index].value, pinch: pinch,
            destructive: items[index].destructive, isVisible: visible, isInteractive: interactive
        )
    }

    /// Gap from this row's top to the bottom of the nearest visible shape above it (the drop,
    /// if nothing else has poured out yet).
    private func pinchAbove(_ index: Int, center: Vec2, scale: Double, visible: Bool) -> Double {
        guard visible else { return 0 }
        if reduceMotion { return 1 }
        let top = center.y - GlassPourLayout.pillHeight / 2 * scale
        var aboveBottom = GlassPourLayout.dropCenter.y + GlassPourLayout.dropRadius * dropScale
        for other in items.indices where other != index {
            let candidate = rowCenter(other)
            guard candidate.y < center.y else { continue }
            let otherVisible = reduceMotion
                ? fade > 0.02
                : (travels[other].value > 0.015 || abs(travels[other].velocity) > 0.02)
            guard otherVisible else { continue }
            let otherScale = GlassPourTuning.minScale + (1 - GlassPourTuning.minScale) * travels[other].value
            let clamped = min(GlassPourTuning.maxScale, max(GlassPourTuning.minDrawnScale, otherScale))
            aboveBottom = max(aboveBottom, candidate.y + GlassPourLayout.pillHeight / 2 * clamped)
        }
        return GlassPourLayout.pinch(gap: top - aboveBottom)
    }

    private func rowCenter(_ index: Int) -> Vec2 {
        let rest = GlassPourLayout.restCenter(index)
        if reduceMotion && (phase == .opening || phase == .open || phase == .closing || fade > 0) {
            return rest
        }
        let travel = travels[index].value
        return Vec2(rest.x, GlassPourLayout.dropCenter.y + (rest.y - GlassPourLayout.dropCenter.y) * travel)
    }

    // MARK: motion

    private mutating func beginOpening() {
        let alreadyOut = travels.contains { $0.value > 0.2 }
        phase = .opening
        phaseTime = alreadyOut ? GlassPourTuning.stagger * Double(max(count - 1, 0)) : 0
        if reduceMotion {
            for index in items.indices {
                travels[index].snap(to: 1)
                wobbles[index].snap(to: 0)
                wobbleKicked[index] = false
            }
        } else {
            for index in items.indices { wobbleKicked[index] = false }
        }
    }

    private mutating func beginClosing() {
        phase = .closing
        phaseTime = 0
    }

    private func travelTargets() -> [Double] {
        if reduceMotion { return travels.map(\.value) }
        switch phase {
        case .closed, .arming:
            return Array(repeating: 0, count: count)
        case .opening, .open:
            return items.indices.map { index in
                (phase == .open || phaseTime >= Double(index) * GlassPourTuning.stagger) ? 1 : 0
            }
        case .closing:
            let last = Double(max(count - 1, 0))
            return items.indices.map { index in
                let delay = (last - Double(index)) * GlassPourTuning.stagger
                let home = travels[index].value < 0.02 && abs(travels[index].velocity) < 0.05
                return (phaseTime >= delay || home) ? 0 : 1
            }
        }
    }

    private mutating func kickWobbles() {
        guard phase == .opening || phase == .open else { return }
        for index in items.indices where items[index].destructive && !wobbleKicked[index] {
            if travels[index].value >= GlassPourTuning.wobbleGate {
                wobbles[index].velocity += GlassPourTuning.wobbleKick
                wobbleKicked[index] = true
            }
        }
    }

    private mutating func settleMotion() -> [GlassPourEvent] {
        switch phase {
        case .opening:
            let released = items.indices.allSatisfy { phaseTime >= Double($0) * GlassPourTuning.stagger }
            let seated = travels.allSatisfy { $0.isSettled(at: 1) }
            if released && seated {
                phase = .open
                phaseTime = 0
                return [.opened, .haptic]
            }
        case .closing:
            let last = Double(max(count - 1, 0))
            let released = items.indices.allSatisfy { index in
                let delay = (last - Double(index)) * GlassPourTuning.stagger
                let home = travels[index].value < 0.02 && abs(travels[index].velocity) < 0.05
                return phaseTime >= delay || home
            }
            let seated = travels.allSatisfy { $0.isSettled(at: 0) }
            if released && seated {
                finishClosed()
                return [.closed]
            }
        default:
            break
        }
        return []
    }

    private mutating func settleFade(_ h: Double) -> [GlassPourEvent] {
        let rate = GlassPourTuning.reducedFade > 0 ? h / GlassPourTuning.reducedFade : 1
        switch phase {
        case .opening:
            fade = min(1, fade + rate)
            if fade >= 1 {
                fade = 1
                phase = .open
                phaseTime = 0
                return [.opened, .haptic]
            }
        case .closing:
            fade = max(0, fade - rate)
            if fade <= 0 {
                fade = 0
                finishClosed()
                return [.closed]
            }
        default:
            break
        }
        return []
    }

    private mutating func finishClosed() {
        phase = .closed
        phaseTime = 0
        fade = 0
        for index in items.indices {
            travels[index].snap(to: 0)
            wobbles[index].snap(to: 0)
            wobbleKicked[index] = false
        }
    }
}
