import Foundation

/// The poster's ripple state: where the source is, how long it has been emitting, and a
/// spring-driven amplitude that follows drag speed while touched and rings down to rest after.
public struct ClothModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        public var wave = ClothWave()
        /// Amplitude (pt) while touching a still finger, plus `speedGain` per pt/s of drag speed.
        public var baseAmplitude = 3.5
        public var speedGain = 0.008
        public var maxAmplitude = 10.0
        /// Follows the drag target while touched.
        public var holdStiffness = 60.0
        public var holdDamping = 0.9
        /// Rings down after release (ζ < 1, so the cloth flaps through flat a few times).
        public var releaseStiffness = 34.0
        public var releaseDamping = 0.22
        /// Smoothing of the measured finger speed (per 1/60 s).
        public var speedSmoothing = 0.25
        /// No crest ticks below this amplitude, nor closer together than `tickInterval`.
        public var tickThreshold = 1.5
        public var tickInterval = 0.12
        public init() {}
    }

    public let tuning: Tuning
    public private(set) var touch: Vec2
    public private(set) var isTouching = false
    /// Seconds since the current ripple started emitting (the shader's `time`).
    public private(set) var emitTime = 0.0
    public private(set) var amplitude: WhimsySpring
    public private(set) var speed = 0.0
    /// Bumps once per new crest while the ripple is strong enough (the haptic trigger).
    public private(set) var tickCount = 0
    /// 0…1 strength of the latest tick, for the haptic intensity.
    public private(set) var lastTickStrength = 0.0
    private var lastCrest = 0
    private var sinceTick = Double.infinity
    private var lastTouch: Vec2?
    private var travelled = 0.0
    public var reduceMotion = false

    public init(center: Vec2 = Vec2(162, 222), tuning: Tuning = Tuning()) {
        self.tuning = tuning
        touch = center
        amplitude = WhimsySpring(value: 0, stiffness: tuning.holdStiffness, dampingRatio: tuning.holdDamping)
    }

    /// Amplitude actually applied (scaled down under Reduce Motion).
    public var effectiveAmplitude: Double { amplitude.value * (reduceMotion ? 0.3 : 1) }

    public var amplitudeTarget: Double {
        guard isTouching else { return 0 }
        return min(tuning.baseAmplitude + tuning.speedGain * speed, tuning.maxAmplitude)
    }

    public var isSettled: Bool {
        !isTouching && abs(amplitude.value) < 0.02 && abs(amplitude.velocity) < 0.2
    }

    public mutating func touchDown(at p: Vec2) {
        guard p.x.isFinite, p.y.isFinite else { return }
        // A fresh ripple only if the last one has died away; otherwise keep its waves travelling.
        if isSettled { emitTime = 0; lastCrest = 0 }
        isTouching = true
        touch = p
        lastTouch = p
        travelled = 0
        amplitude.stiffness = tuning.holdStiffness
        amplitude.dampingRatio = tuning.holdDamping
    }

    public mutating func touchMoved(to p: Vec2) {
        guard p.x.isFinite, p.y.isFinite else { return }
        if !isTouching { touchDown(at: p) }
        if let l = lastTouch { travelled += p.distance(to: l) }
        lastTouch = p
        touch = p
    }

    public mutating func touchUp() {
        guard isTouching else { return }
        isTouching = false
        lastTouch = nil
        speed = 0
        amplitude.stiffness = tuning.releaseStiffness
        amplitude.dampingRatio = reduceMotion ? 1 : tuning.releaseDamping
    }

    public mutating func step(_ dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        let dt = min(dt, WhimsySpring.maxFrame)
        if isTouching {
            let measured = travelled / dt
            travelled = 0
            let a = 1 - pow(1 - tuning.speedSmoothing, dt * 60)
            speed += (measured - speed) * a
        }
        amplitude.step(toward: amplitudeTarget, dt: dt)
        if isSettled && !isTouching { amplitude.snap(to: 0); return }
        emitTime += dt
        sinceTick += dt
        let crest = tuning.wave.crestIndex(time: emitTime)
        if crest > lastCrest {
            lastCrest = crest
            let strength = abs(amplitude.value) / tuning.maxAmplitude
            if abs(amplitude.value) >= tuning.tickThreshold && sinceTick >= tuning.tickInterval {
                tickCount += 1
                lastTickStrength = WhimsyMath.clamp01(strength)
                sinceTick = 0
            }
        }
    }

    // MARK: Field (what the shaders compute per pixel)

    /// Radial height (pt) at `p`.
    public func height(at p: Vec2) -> Double {
        tuning.wave.height(distance: p.distance(to: touch), time: emitTime) * effectiveAmplitude
    }

    /// Where the distortion shader samples from for the pixel at `p`: pulled along the radius.
    public func sourcePosition(for p: Vec2) -> Vec2 {
        let v = p - touch, d = v.length
        guard d > 1e-3 else { return p }
        return p - v * (1 / d) * height(at: p)
    }

    /// Height gradient at `p` (radial slope along the outward unit vector).
    public func gradient(at p: Vec2) -> Vec2 {
        let v = p - touch, d = v.length
        guard d > 1e-3 else { return .zero }
        return v * (1 / d) * (tuning.wave.slope(distance: d, time: emitTime) * effectiveAmplitude)
    }

    public func sheen(at p: Vec2) -> Double { ClothShading.sheen(gradient: gradient(at: p)) }
}
