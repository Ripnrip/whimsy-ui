import Foundation
import WhimsyCore

/// Spring constants for the heart pulse (damping is a ratio; c = 2·√k·ζ).
public struct PulseSpring: Equatable, Sendable {
    public var stiffness: Double
    public var damping: Double
    public init(stiffness: Double, damping: Double) { self.stiffness = stiffness; self.damping = damping }
}

/// Like / unlike with a solar-flare burst. Deterministic: every burst's ribbons come from a
/// `SeededRandom`, ribbons use a closed-form spring, and the pulse is stepped in fixed substeps.
public struct SolarFlareModel: Equatable, Sendable {
    public static let maxSubstep = 1.0 / 240.0
    public static let maxFrameDelta = 0.1

    public struct Tuning: Equatable, Sendable {
        public var ribbonCount: ClosedRange<Int> = 7...9
        /// Launches spread over this window, in random order.
        public var staggerWindow = 0.12
        public var lengthRange: ClosedRange<Double> = 0.75...1.25
        public var widthRange: ClosedRange<Double> = 0.10...0.16
        /// Swirl magnitude; the sign is shared by a whole burst so it reads as one twist.
        public var swirlRange: ClosedRange<Double> = 0.22...0.45
        /// Ribbons start at the heart's edge so their bright bases aren't hidden behind it.
        public var innerRadius = 0.9
        public var motion = FlareRibbon.Motion()
        /// Like pulse: hold the target here, then spring back to 1.
        public var likePeak = 1.25
        public var likePeakHold = 0.09
        public var likeSpring = PulseSpring(stiffness: 520, damping: 0.5)
        /// Unlike: a quick shrink, then back to 1.
        public var unlikeDip = 0.8
        public var unlikeDipHold = 0.05
        public var unlikeSpring = PulseSpring(stiffness: 700, damping: 0.75)
        public init() {}
    }

    public let tuning: Tuning
    public private(set) var isLiked: Bool
    public private(set) var ribbons: [FlareRibbon] = []
    /// When the current burst was spawned (model time).
    public private(set) var burstTime = 0.0
    public private(set) var burstCount = 0
    public private(set) var scale = 1.0
    public private(set) var scaleVelocity = 0.0
    public private(set) var time = 0.0
    private var pulseTarget = 1.0
    private var pulseHoldUntil = 0.0
    private var pulseIsLike = true
    private var rng: SeededRandom

    public init(isLiked: Bool = false, seed: UInt64 = 0xF1A2E, tuning: Tuning = Tuning()) {
        self.isLiked = isLiked
        self.tuning = tuning
        rng = SeededRandom(seed: seed)
    }

    public mutating func toggle(animated: Bool = true) { setLiked(!isLiked, animated: animated) }

    /// Like spawns a burst and a 1 → 1.25 → 1 pulse; unlike clears any flare and does a quick shrink.
    public mutating func setLiked(_ liked: Bool, animated: Bool = true) {
        guard liked != isLiked else { return }
        isLiked = liked
        guard animated else {
            ribbons = []
            scale = 1; scaleVelocity = 0; pulseTarget = 1; pulseHoldUntil = time
            return
        }
        if liked {
            ribbons = spawnBurst()
            burstTime = time
            burstCount += 1
            pulseTarget = tuning.likePeak
            pulseHoldUntil = time + tuning.likePeakHold
            pulseIsLike = true
        } else {
            ribbons = []
            pulseTarget = tuning.unlikeDip
            pulseHoldUntil = time + tuning.unlikeDipHold
            pulseIsLike = false
        }
    }

    private mutating func spawnBurst() -> [FlareRibbon] {
        let count = Int(rng.uniform(Double(tuning.ribbonCount.lowerBound)...(Double(tuning.ribbonCount.upperBound) + 0.999)))
        let n = min(max(count, tuning.ribbonCount.lowerBound), tuning.ribbonCount.upperBound)
        let spacing = 2 * Double.pi / Double(n)
        let base = rng.uniform(0...(2 * .pi))
        let swirlSign: Double = rng.uniform(0...1) < 0.5 ? -1 : 1
        // Random launch order spread across the stagger window.
        var order = Array(0..<n)
        for i in stride(from: n - 1, to: 0, by: -1) {
            let j = Int(rng.uniform(0...Double(i) + 0.999))
            order.swapAt(i, min(j, i))
        }
        var ribbons: [FlareRibbon] = []
        for i in 0..<n {
            let slot = Double(order[i]) / Double(max(n - 1, 1))
            ribbons.append(FlareRibbon(
                angle: base + spacing * Double(i) + rng.uniform(-0.22...0.22) * spacing,
                delay: slot * tuning.staggerWindow,
                length: rng.uniform(tuning.lengthRange),
                width: rng.uniform(tuning.widthRange),
                swirl: swirlSign * rng.uniform(tuning.swirlRange),
                innerRadius: tuning.innerRadius
            ))
        }
        return ribbons
    }

    public mutating func step(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, Self.maxFrameDelta)
        while remaining > 0 {
            let h = min(remaining, Self.maxSubstep)
            if time >= pulseHoldUntil { pulseTarget = 1 }
            let spring = pulseIsLike ? tuning.likeSpring : tuning.unlikeSpring
            let k = spring.stiffness, c = 2 * k.squareRoot() * spring.damping
            // While holding, chase the peak hard so the pulse actually reaches it.
            let kk = pulseTarget == 1 ? k : k * 4
            let cc = pulseTarget == 1 ? c : 2 * kk.squareRoot() * 0.9
            scaleVelocity += (kk * (pulseTarget - scale) - cc * scaleVelocity) * h
            scale += scaleVelocity * h
            time += h
            remaining -= h
        }
        if !ribbons.isEmpty && burstAge > ribbonsEnd { ribbons = [] }
    }

    /// Seconds since the current burst.
    public var burstAge: Double { time - burstTime }
    /// When the last ribbon of the burst has faded.
    var ribbonsEnd: Double { (ribbons.map(\.delay).max() ?? 0) + tuning.motion.lifetime }

    /// Ribbons visible now, with their state.
    public var visibleRibbons: [(ribbon: FlareRibbon, state: RibbonState)] {
        ribbons.compactMap { r in r.state(at: burstAge, motion: tuning.motion).map { (r, $0) } }
    }

    public var isSettled: Bool {
        ribbons.isEmpty && abs(scale - 1) < 1e-3 && abs(scaleVelocity) < 1e-2 && time >= pulseHoldUntil
    }
}
