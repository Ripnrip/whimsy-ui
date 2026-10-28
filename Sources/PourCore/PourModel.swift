import Foundation

public enum PourState: Equatable, Sendable {
    case closed, opening, open, closing
}

/// What the menu did, for the view (haptics, announcements) and tests.
public enum PourEvent: Equatable, Sendable {
    case opening
    case closing
    case selected(Int)
    case labelChanged(from: Int, to: Int)
    /// The pour finished: the menu fully open, or everything back in the pill.
    case landed(open: Bool)
    /// A soft haptic for a landing, at most one per `hapticInterval`.
    case haptic
}

/// The menu's state over time: a master clock that runs up (opening) or down (closing) and can be
/// reversed at any moment, the selection, the label crossfade and the events.
public struct PourModel: Sendable {
    public struct Config: Equatable, Sendable {
        public var hapticInterval = 0.15
        /// Reduce Motion: a plain, quick fade. No goo, no lift.
        public var reduceMotion = false
        public static let reducedFadeDuration = 0.2
        public init() {}
    }

    public var config: Config
    public let options: [String]
    public private(set) var selected: Int
    public private(set) var time = 0.0
    /// The master clock, 0 (closed) … `total` (open).
    public private(set) var master = 0.0
    /// +1 opening, -1 closing, 0 at rest.
    public private(set) var direction = 0
    public private(set) var landings = 0
    private var labelFromIndex: Int
    private var labelStart: Double?
    private var lastHaptic = -Double.infinity
    private var pending: [PourEvent] = []

    public init(options: [String] = PourLayout.defaultOptions, selected: Int = 0, config: Config = Config()) {
        precondition(!options.isEmpty, "PourModel needs at least one option")
        self.options = options
        self.selected = min(max(selected, 0), options.count - 1)
        self.config = config
        labelFromIndex = self.selected
    }

    public var total: Double { PourTimeline.total(optionCount: options.count) }
    public var progress: Double { total > 0 ? master / total : 0 }

    public var state: PourState {
        if direction > 0 { return .opening }
        if direction < 0 { return .closing }
        return master >= total ? .open : .closed
    }

    /// Options can be picked while the drops are out (including mid-pour).
    public var acceptsPick: Bool { state == .opening || state == .open }
    public var isExpanded: Bool { state == .opening || state == .open }

    /// The drops. Reduce Motion keeps them at rest (the menu just fades with `menuOpacity`).
    public var drops: [PourDrop] {
        PourTimeline.drops(optionCount: options.count, master: config.reduceMotion ? total : master)
    }
    public var necks: [PourNeck] { config.reduceMotion ? [] : PourTimeline.necks(drops) }

    /// Pill lift 0…1 (always 0 under Reduce Motion).
    public var lift: Double { config.reduceMotion ? 0 : PourTimeline.lift(master: master, optionCount: options.count) }
    public var chevronAngle: Double { 180 * WhimsyMath.easeInOutCubic(progress) }

    /// Reduce Motion's plain fade of the whole menu.
    public var menuOpacity: Double { WhimsyMath.easeInOutCubic(progress) }

    // MARK: Label crossfade

    private var labelDuration: Double { config.reduceMotion ? PourLabelFade.reducedDuration : PourLabelFade.duration }

    /// 0…1 eased progress of the label crossfade (1 when none is running).
    public var labelProgress: Double {
        guard let s = labelStart else { return 1 }
        return PourLabelFade.progress(elapsed: time - s, duration: labelDuration)
    }

    public var isLabelFading: Bool {
        guard let s = labelStart else { return false }
        return time - s < labelDuration
    }

    /// The option fading out and the one fading in, with their opacities.
    public var label: (from: Int, fromOpacity: Double, to: Int, toOpacity: Double) {
        let p = labelProgress
        return (labelFromIndex, 1 - p, selected, p)
    }

    // MARK: Input

    /// Tap on the pill: closed or closing → open, open or opening → close. Mid-pour it reverses.
    public mutating func tapPill(at t: Double) {
        advance(to: t)
        if state == .closed || state == .closing {
            direction = 1
            pending.append(.opening)
        } else {
            direction = -1
            pending.append(.closing)
        }
    }

    /// Choose option `i`: the label crossfades and everything pours back up. Only while the menu is
    /// opening or open; returns whether the pick was taken.
    @discardableResult
    public mutating func pick(_ i: Int, at t: Double) -> Bool {
        advance(to: t)
        guard options.indices.contains(i), acceptsPick else { return false }
        pending.append(.selected(i))
        if i != selected {
            // A crossfade already past halfway starts from the option that was fading in.
            let from = (isLabelFading && labelProgress < 0.5) ? labelFromIndex : selected
            labelFromIndex = from
            pending.append(.labelChanged(from: selected, to: i))
            selected = i
            labelStart = time
        }
        direction = -1
        pending.append(.closing)
        return true
    }

    /// Moves time forward and returns what happened since the last call, in order.
    @discardableResult
    public mutating func advance(to t: Double) -> [PourEvent] {
        if t.isFinite, t > time {
            let dt = t - time
            time = t
            if direction != 0 {
                let rate = config.reduceMotion ? total / PourModel.Config.reducedFadeDuration : 1
                master += Double(direction) * dt * rate
                if direction > 0, master >= total { master = total; direction = 0; land(open: true) }
                else if direction < 0, master <= 0 { master = 0; direction = 0; land(open: false) }
            }
        }
        if let s = labelStart, time - s >= labelDuration { labelStart = nil; labelFromIndex = selected }
        let out = pending
        pending = []
        return out
    }

    private mutating func land(open: Bool) {
        pending.append(.landed(open: open))
        if time - lastHaptic >= config.hapticInterval {
            lastHaptic = time
            landings += 1
            pending.append(.haptic)
        }
    }

    /// Nothing moving and nothing to report.
    public var isIdle: Bool { direction == 0 && !isLabelFading && pending.isEmpty }
}
