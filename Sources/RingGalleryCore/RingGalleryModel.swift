import Foundation

/// Where one card sits on the ring for the current rotation. Everything a renderer needs:
/// a 2D offset, a depth-driven scale/opacity/blur, a stacking order and a yaw for the 3D tilt.
public struct RingCardPlacement: Equatable, Sendable {
    public var index: Int
    /// Angle around the ring, wrapped to (-π, π]. 0 = front and centre, ±π = directly behind.
    public var angle: Double
    /// Horizontal offset from the ring's centre, points (+x right).
    public var x: Double
    /// Vertical offset, points (+y **down**). Cards further back ride higher, so the ring reads
    /// as seen from slightly above.
    public var y: Double
    /// 1 at the front → 0 directly behind: `(cos angle + 1) / 2`.
    public var depth: Double
    public var scale: Double
    public var opacity: Double
    /// Gaussian blur radius, points (0 at the front).
    public var blur: Double
    /// Stacking order; larger draws on top. Equal to `depth`.
    public var zIndex: Double
    /// Rotation about the vertical axis, degrees. Positive on the right-hand side, so side
    /// cards turn their faces outwards; it eases back to 0 behind, so no card shows its back.
    public var yawDegrees: Double
    /// True for the card nearest the front (the one a tap opens).
    public var isFront: Bool
}

/// What the ring is doing.
public enum RingMotionPhase: String, Equatable, Sendable, CaseIterable {
    /// At rest on a card.
    case idle
    /// Following a finger.
    case dragging
    /// Released with speed: spinning freely while friction bleeds the velocity off.
    case coasting
    /// Springing onto the nearest card.
    case snapping
}

/// Pure-Swift model of a 3D card ring: drag-to-rotate with momentum, friction and a spring
/// snap onto the nearest card, depth-based placement for every card, and the 12 fps film-grain
/// clock. Drive it with ``step(_:)`` once per frame.
///
/// Rotation is in radians. Card `i` sits at `i · spacing` around the ring, and the ring's
/// `rotation` is subtracted from that, so `rotation == k · spacing` brings card `k` to the front.
/// Rotation is never wrapped; ``frontIndex`` does the modular arithmetic.
public struct RingGalleryModel: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Half the ring's projected width: the x offset of a card 90° round, points.
        public var radius = 140.0
        /// How much higher the card directly behind sits than the front card, points.
        public var elevation = 46.0
        /// Scale, opacity and blur of the card directly behind (the front card is 1, 1, 0).
        public var farScale = 0.52
        public var farOpacity = 0.32
        public var maxBlur = 5.0
        /// Peak yaw of the side cards, degrees.
        public var maxYaw = 52.0
        /// Points of horizontal drag that rotate the ring by one card.
        public var dragPerCard = 120.0
        /// Exponential velocity decay while coasting, 1/s (`ω *= exp(-friction · dt)`).
        public var friction = 4.0
        /// Below this angular speed (cards/s) coasting hands over to the snap spring.
        public var snapSpeed = 1.6
        /// Fastest fling the ring accepts, cards/s.
        public var maxSpeed = 14.0
        /// The snap spring (stiffness, damping ratio).
        public var snapStiffness = 150.0
        public var snapDampingRatio = 0.86
        /// Film-grain refresh rate. Grain changes in visible steps, like projected film.
        public var grainFPS = 12.0
        public init() {}
        public static let `default` = Tuning()
    }

    /// Number of cards on the ring (at least 1).
    public let count: Int
    public let tuning: Tuning
    /// When true, releases never coast and the snap is instant; ``isSettled`` is reached on the
    /// next step. Renderers should also crossfade instead of zooming and freeze the grain.
    public var reduceMotion: Bool

    public private(set) var rotation: Double = 0
    /// Angular velocity, radians/s.
    public private(set) var angularVelocity: Double = 0
    public private(set) var phase: RingMotionPhase = .idle
    /// The rotation the snap spring is heading for (a multiple of ``spacing``).
    public private(set) var snapTarget: Double = 0
    public private(set) var time: Double = 0

    // Drag bookkeeping.
    private var dragStartRotation: Double = 0
    private var lastTranslation: Double = 0
    private var lastDragTime: Double?
    private var trackedVelocity: Double = 0 // points/s, smoothed

    public init(count: Int = 8, tuning: Tuning = .default, reduceMotion: Bool = false) {
        self.count = max(1, count)
        self.tuning = tuning
        self.reduceMotion = reduceMotion
    }

    // MARK: Geometry

    /// Angle between neighbouring cards, radians.
    public var spacing: Double { 2 * .pi / Double(count) }
    /// Radians of rotation per point of horizontal drag.
    public var dragSensitivity: Double { spacing / tuning.dragPerCard }

    /// The card currently nearest the front.
    public var frontIndex: Int { Self.wrapIndex(Int((rotation / spacing).rounded()), count) }

    /// Rotation measured in cards (2.5 = halfway between cards 2 and 3).
    public var position: Double { rotation / spacing }

    /// Placement of card `index` for the current rotation.
    public func placement(for index: Int) -> RingCardPlacement {
        Self.placement(index: index, count: count, rotation: rotation, tuning: tuning)
    }

    /// Placements for every card, in index order.
    public var placements: [RingCardPlacement] { (0..<count).map(placement(for:)) }

    /// Stateless placement maths, shared with the renderers and the tests.
    public static func placement(index: Int, count: Int, rotation: Double,
                                 tuning: Tuning = .default) -> RingCardPlacement {
        let n = max(1, count)
        let spacing = 2 * .pi / Double(n)
        let angle = wrapAngle(Double(index) * spacing - rotation)
        let c = cos(angle), s = sin(angle)
        let depth = (c + 1) / 2
        let front = wrapIndex(Int((rotation / spacing).rounded()), n)
        return RingCardPlacement(
            index: index,
            angle: angle,
            x: tuning.radius * s,
            y: -tuning.elevation * (1 - depth),
            depth: depth,
            scale: tuning.farScale + (1 - tuning.farScale) * depth,
            opacity: tuning.farOpacity + (1 - tuning.farOpacity) * pow(depth, 1.2),
            blur: tuning.maxBlur * pow(1 - depth, 1.5),
            zIndex: depth,
            yawDegrees: tuning.maxYaw * s,
            isFront: index == front)
    }

    /// Wraps an angle into (-π, π].
    public static func wrapAngle(_ a: Double) -> Double {
        guard a.isFinite else { return 0 }
        var r = a.truncatingRemainder(dividingBy: 2 * .pi)
        if r > .pi { r -= 2 * .pi }
        if r <= -.pi { r += 2 * .pi }
        return r
    }

    static func wrapIndex(_ i: Int, _ n: Int) -> Int { ((i % n) + n) % n }

    // MARK: Drag input

    /// Finger down. Catches a spinning ring dead.
    public mutating func dragBegan() {
        phase = .dragging
        angularVelocity = 0
        dragStartRotation = rotation
        lastTranslation = 0
        lastDragTime = nil
        trackedVelocity = 0
    }

    /// Finger moved. `translation` is the total horizontal travel since the drag began
    /// (points, +right); `time` is a timestamp in seconds used to estimate release speed.
    /// Dragging right turns the ring so the cards follow the finger to the right.
    public mutating func dragChanged(translation: Double, time: Double) {
        if phase != .dragging { dragBegan() }
        guard translation.isFinite else { return }
        if let last = lastDragTime, time > last {
            let v = (translation - lastTranslation) / (time - last)
            // Exponential smoothing over ~50 ms so one jittery sample can't fling the ring.
            let a = min((time - last) / 0.05, 1)
            trackedVelocity += (v - trackedVelocity) * a
        }
        lastDragTime = time
        lastTranslation = translation
        rotation = dragStartRotation - translation * dragSensitivity
    }

    /// Finger up. `velocity` is the horizontal release speed in points/s (+right), e.g.
    /// `DragGesture.Value.velocity.width`; pass `nil` to use the speed tracked from
    /// ``dragChanged(translation:time:)``.
    public mutating func dragEnded(velocity: Double? = nil) {
        let v = velocity.flatMap { $0.isFinite ? $0 : nil } ?? trackedVelocity
        let maxOmega = tuning.maxSpeed * spacing
        let omega = min(max(-v * dragSensitivity, -maxOmega), maxOmega)
        lastDragTime = nil
        if reduceMotion {
            angularVelocity = 0
            beginSnap(to: nearest(rotation))
        } else if abs(omega) > tuning.snapSpeed * spacing {
            angularVelocity = omega
            phase = .coasting
            snapTarget = projectedTarget
        } else {
            angularVelocity = omega
            beginSnap(to: nearest(rotation + omega / tuning.friction))
        }
    }

    /// Cancels a drag (e.g. the gesture was interrupted): snaps to the nearest card.
    public mutating func dragCancelled() {
        angularVelocity = 0
        beginSnap(to: nearest(rotation))
    }

    // MARK: Programmatic moves (accessibility, taps on side cards)

    /// Moves the front by `cards` positions (+1 = next card), relative to the current target
    /// so repeated calls queue up. Wraps round the ring.
    public mutating func step(by cards: Int) {
        let base = (phase == .snapping || phase == .coasting) ? snapTarget : nearest(rotation)
        angularVelocity = phase == .coasting ? 0 : angularVelocity
        beginSnap(to: base + Double(cards) * spacing)
    }

    /// Brings card `index` to the front the short way round.
    public mutating func select(_ index: Int) {
        let current = phase == .snapping ? snapTarget : nearest(rotation)
        let currentIndex = Self.wrapIndex(Int((current / spacing).rounded()), count)
        var delta = Self.wrapIndex(index - currentIndex, count)
        if delta > count / 2 { delta -= count }
        step(by: delta)
    }

    /// Where a coast that started now would come to rest, rounded onto a card: the exponential
    /// decay travels `ω / friction` in total.
    public var projectedTarget: Double { nearest(rotation + angularVelocity / tuning.friction) }

    private func nearest(_ r: Double) -> Double { (r / spacing).rounded() * spacing }

    private mutating func beginSnap(to target: Double) {
        snapTarget = target
        if reduceMotion {
            rotation = target
            angularVelocity = 0
            phase = .idle
        } else {
            phase = .snapping
        }
    }

    // MARK: Simulation

    public var isSettled: Bool { phase == .idle }

    /// Advance by `dt` seconds (clamped to 0.1 s; integrated in ≤ 1/240 s substeps).
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, 0.1)
        while remaining > 1e-12 {
            let h = min(remaining, 1.0 / 240)
            substep(h)
            remaining -= h
        }
    }

    private mutating func substep(_ h: Double) {
        time += h
        switch phase {
        case .idle, .dragging:
            break
        case .coasting:
            rotation += angularVelocity * h
            angularVelocity *= exp(-tuning.friction * h)
            if abs(angularVelocity) < tuning.snapSpeed * spacing {
                beginSnap(to: projectedTarget)
            }
        case .snapping:
            let k = tuning.snapStiffness
            let c = 2 * k.squareRoot() * tuning.snapDampingRatio
            angularVelocity += (k * (snapTarget - rotation) - c * angularVelocity) * h
            rotation += angularVelocity * h
            if abs(snapTarget - rotation) < 1e-4, abs(angularVelocity) < 1e-3 {
                rotation = snapTarget
                angularVelocity = 0
                phase = .idle
            }
        }
    }

    // MARK: Film grain clock

    /// The grain frame shown at `time` seconds: time quantised to `fps` (12 by default), so the
    /// grain pattern holds for 1/12 s and then jumps, like film. Always 0 with Reduce Motion.
    public static func grainFrame(at time: Double, fps: Double = Tuning.default.grainFPS,
                                  reduceMotion: Bool = false) -> Int {
        guard !reduceMotion, time.isFinite, fps > 0 else { return 0 }
        // +1e-9 keeps exact multiples of 1/fps (which can land a hair low) in the right frame.
        return Int((time * fps + 1e-9).rounded(.down))
    }

    /// Shader seed for a grain frame, uniformly spread over [0, 1). Neighbouring frames get
    /// unrelated seeds (SplitMix64 of the frame number), so the pattern never visibly drifts.
    public static func grainSeed(frame: Int) -> Double {
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(frame)))
        return rng.uniform(0...1) // top 53 bits / 2^53: never reaches 1
    }

    /// Shorthand: the shader seed at `time` seconds.
    public static func grainSeed(at time: Double, fps: Double = Tuning.default.grainFPS,
                                 reduceMotion: Bool = false) -> Double {
        grainSeed(frame: grainFrame(at: time, fps: fps, reduceMotion: reduceMotion))
    }
}
