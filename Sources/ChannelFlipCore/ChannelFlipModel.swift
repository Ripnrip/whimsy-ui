import Foundation

/// The channel-flip state machine: which photo is wanted, which one is on screen, and the transition between.
/// The picture is swapped on the peak frame of the effect, and a light haptic fires on that same step.
public struct ChannelFlipModel: Equatable, Sendable {
    public struct Transition: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var spec: FlipSpec
        public var elapsed: Double
        public var seed: UInt32
        public var swapped: Bool
    }

    public enum Event: Equatable, Sendable {
        /// The on-screen picture changed (the peak frame).
        case swapped(from: Int, to: Int)
        case finished
    }

    /// What a view draws on one frame.
    public struct Frame: Equatable, Sendable {
        public var isActive: Bool
        /// The picture on screen now (it changes on the peak frame).
        public var shown: Int
        public var from: Int
        public var to: Int
        public var frameIndex: Int
        public var frameCount: Int
        /// Quantized progress, strictly inside (0, 1), or 0 when nothing is playing.
        public var progress: Double
        /// 0 when nothing is playing, and also 0 under Reduce Motion (no shader then).
        public var intensity: Double
        /// What the shader gets as its seed: new on every frame.
        public var seed: Double
        /// Reduce Motion only: how far the crossfade from `from` to `to` has gone, 0…1. 1 when idle.
        public var crossfade: Double
    }

    /// The channel number appears fast, stays a moment, then fades.
    public static let osdFadeIn = 0.12
    public static let osdHold = 1.6
    public static let osdFadeOut = 0.6
    /// Haptics closer together than this are dropped.
    public static let hapticGap = 0.08
    /// A longer step than this is treated as this long.
    public static let maxStep = 0.25

    public let count: Int
    /// The channel that was asked for (what the number shows).
    public private(set) var index: Int
    /// The picture on screen.
    public private(set) var shown: Int
    public private(set) var transition: Transition?
    public var reduceMotion = false
    /// Debounced count of swaps: the haptic trigger.
    public private(set) var switches = 0
    /// Count of changes asked for.
    public private(set) var flips = 0
    public private(set) var announcement: String?
    public private(set) var announcementCount = 0
    /// Seconds since the last change was asked for (large when none has been).
    public private(set) var osdAge = 99.0
    private var clock = 0.0
    private var lastHaptic = -1.0

    public init(count: Int, startAt start: Int = 0) {
        self.count = max(0, count)
        index = ChannelIndex.wrap(start, count: count)
        shown = index
    }

    /// Ask for the next or previous channel. Returns false when there is nowhere to go.
    @discardableResult
    public mutating func flip(_ direction: FlipDirection, spec: FlipSpec = ChannelFlipTiming.tap) -> Bool {
        guard count > 1 else { return false }
        // Rapid taps must still make progress: a change that hasn't swapped yet swaps now.
        if let t = transition, !t.swapped { swap(t) }
        index = direction == .next ? ChannelIndex.next(index, count: count) : ChannelIndex.previous(index, count: count)
        flips += 1
        let s = reduceMotion ? FlipSpec(duration: ChannelFlipTiming.reducedDuration, strength: spec.strength) : spec
        transition = Transition(from: shown, to: index, spec: s, elapsed: 0, seed: ChannelFlipTiming.transitionSeed(flips), swapped: false)
        osdAge = 0
        announcement = "Channel \(index + 1) of \(count)"
        announcementCount += 1
        return true
    }

    @discardableResult
    public mutating func tap() -> Bool { flip(.next, spec: ChannelFlipTiming.tap) }

    /// Act on a finished touch: a tap goes forward, a swipe goes by its direction at a length and strength set by its speed.
    @discardableResult
    public mutating func handle(_ gesture: FlipGesture) -> Bool {
        switch gesture {
        case .tap: return tap()
        case .swipe(let dir, let speed): return flip(dir, spec: FlipVelocity.spec(forSpeed: speed))
        case .none: return false
        }
    }

    private mutating func swap(_ t: Transition) {
        var t = t
        t.swapped = true
        transition = t
        let old = shown
        shown = t.to
        if clock - lastHaptic >= Self.hapticGap { switches += 1; lastHaptic = clock }
        pendingEvents.append(.swapped(from: old, to: t.to))
    }
    private var pendingEvents: [Event] = []

    /// Advance by `dt` seconds. Returns what happened, in order.
    @discardableResult
    public mutating func step(_ dt: Double) -> [Event] {
        let d = dt.isFinite ? max(0, min(dt, Self.maxStep)) : 0
        clock += d
        osdAge += d
        guard var t = transition else { return drain() }
        let before = t.elapsed
        t.elapsed += d
        transition = t
        if !t.swapped && ChannelFlipTiming.crossesSwap(from: before, to: t.elapsed, duration: t.spec.duration) { swap(t) }
        if t.elapsed >= t.spec.duration {
            transition = nil
            pendingEvents.append(.finished)
        }
        return drain()
    }

    private mutating func drain() -> [Event] { let e = pendingEvents; pendingEvents = []; return e }

    public var frame: Frame {
        guard let t = transition, let f = ChannelFlipTiming.frameIndex(elapsed: t.elapsed, duration: t.spec.duration) else {
            return Frame(isActive: false, shown: shown, from: shown, to: shown, frameIndex: 0, frameCount: 0, progress: 0, intensity: 0, seed: 0, crossfade: 1)
        }
        let n = ChannelFlipTiming.frameCount(duration: t.spec.duration)
        let p = ChannelFlipTiming.quantizedProgress(frame: f, count: n)
        return Frame(isActive: true, shown: shown, from: t.from, to: t.to, frameIndex: f, frameCount: n, progress: p,
                     intensity: reduceMotion ? 0 : ChannelFlipTiming.intensity(frame: f, count: n, strength: t.spec.strength),
                     seed: ChannelFlipTiming.frameSeed(transition: t.seed, frame: f),
                     crossfade: reduceMotion ? WhimsyMath.smoothstep(0, 1, t.elapsed / t.spec.duration) : (t.swapped ? 1 : 0))
    }

    /// The number overlay, "CH 03".
    public var channelLabel: String { ChannelIndex.label(index, count: count) }

    /// Opacity of the number overlay for a time since the last change was asked for.
    public static func osdAlpha(age: Double) -> Double {
        if !(age >= 0) { return 0 }
        let up = WhimsyMath.smoothstep(0, osdFadeIn, age)
        let down = 1 - WhimsyMath.smoothstep(osdHold, osdHold + osdFadeOut, age)
        return up * down
    }
    public var osdAlpha: Double { Self.osdAlpha(age: osdAge) }

    /// Nothing is playing and the number has faded: a view can stop its timeline.
    public var isIdle: Bool { transition == nil && osdAge >= Self.osdHold + Self.osdFadeOut }
}
