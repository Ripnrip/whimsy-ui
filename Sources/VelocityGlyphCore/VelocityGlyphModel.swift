import Foundation

/// What the price control is doing.
public enum VelocityGlyphPhase: String, Sendable, Equatable {
    /// At rest on a snapped price. Glyphs sit on the baseline.
    case idle
    /// A finger is down. Glyphs chase a scatter pose driven by smoothed thumb speed.
    case dragging
    /// The finger is up. Each glyph springs back to the baseline and overshoots it a little.
    case settling
}

/// A step the snapped price crossed. Emitted once per crossing, in travel order, including the
/// value landed on and excluding the value left behind.
public enum VelocityGlyphEvent: Equatable, Sendable {
    case step(Int)
}

/// One glyph as the view draws it. `id` is stable across price changes that keep that place.
public struct GlyphPose: Equatable, Sendable, Identifiable {
    public var id: GlyphRole
    public var character: String
    /// Points, positive down.
    public var offsetY: Double
    /// Degrees, positive clockwise.
    public var leanDegrees: Double

    public init(id: GlyphRole, character: String, offsetY: Double, leanDegrees: Double) {
        self.id = id
        self.character = character
        self.offsetY = offsetY
        self.leanDegrees = leanDegrees
    }
}

/// Pure-Swift price slider: step snapping, per-character glyphs, smoothed thumb velocity,
/// seeded scatter and a return spring.
///
/// Drag x is in points along a track of ``VelocityGlyphTuning/trackWidth``. While the finger is
/// down, each glyph's target offset and lean are `signedAmplitude(role) * max * clamp(|speed| / fullSpeed)`.
/// On release the targets go to zero and the under-damped springs carry the glyphs past the baseline.
/// Reduce Motion keeps every offset, lean and blur at zero; the price still snaps and still emits
/// one ``VelocityGlyphEvent/step(_:)`` per grid crossing.
public struct VelocityGlyphModel: Equatable, Sendable {
    public let span: PriceSpan
    public private(set) var value: Int
    public private(set) var phase: VelocityGlyphPhase = .idle
    public private(set) var time: Double = 0
    /// Smoothed thumb velocity in points per second. Positive moves toward the high end of the track.
    public private(set) var smoothedSpeed: Double = 0
    public private(set) var reduceMotion: Bool

    private var glyphs: [GlyphBody]
    private var blurSpring: WhimsySpring
    private var pointerX: Double
    private var lastSampleX: Double

    public init(value: Int = VelocityGlyphTuning.defaultValue,
                range: ClosedRange<Int> = VelocityGlyphTuning.defaultLower...VelocityGlyphTuning.defaultUpper,
                step: Int = VelocityGlyphTuning.defaultStep,
                reduceMotion: Bool = false) {
        let span = PriceSpan(range: range, step: step)
        self.span = span
        self.value = span.snap(value)
        self.reduceMotion = reduceMotion
        self.pointerX = span.x(for: span.snap(value), width: VelocityGlyphTuning.trackWidth)
        self.lastSampleX = self.pointerX
        self.blurSpring = Self.makeSpring(value: 0)
        self.glyphs = []
        syncGlyphs()
    }

    // MARK: derived

    public var formattedPrice: String { PriceGlyphs.string(for: value) }

    /// Where the thumb is drawn: under the finger while dragging, otherwise on the snapped value.
    public var interactionX: Double {
        phase == .dragging ? pointerX : span.x(for: value, width: VelocityGlyphTuning.trackWidth)
    }

    /// Shared blur radius in points. Zero under Reduce Motion, and never negative.
    public var blurRadius: Double {
        if reduceMotion { return 0 }
        return max(0, blurSpring.value)
    }

    public var poses: [GlyphPose] {
        glyphs.map { body in
            GlyphPose(id: body.role,
                      character: body.character,
                      offsetY: reduceMotion ? 0 : body.offset.value,
                      leanDegrees: reduceMotion ? 0 : body.lean.value)
        }
    }

    public var isVisuallySettled: Bool {
        if reduceMotion { return true }
        guard blurSpring.isSettled(at: 0) else { return false }
        return glyphs.allSatisfy { $0.offset.isSettled(at: 0) && $0.lean.isSettled(at: 0) }
    }

    // MARK: input

    /// Finger down at `x` points along the track. Jumps the price and emits every step crossed.
    public mutating func beginDrag(atX x: Double) -> [VelocityGlyphEvent] {
        guard x.isFinite else { return [] }
        pointerX = clampX(x)
        lastSampleX = pointerX
        smoothedSpeed = 0
        phase = .dragging
        return apply(span.value(atX: pointerX, width: VelocityGlyphTuning.trackWidth))
    }

    /// Finger moved. The price updates immediately; velocity is sampled on the next ``step(_:)``.
    public mutating func updateDrag(atX x: Double) -> [VelocityGlyphEvent] {
        guard phase == .dragging, x.isFinite else { return [] }
        pointerX = clampX(x)
        return apply(span.value(atX: pointerX, width: VelocityGlyphTuning.trackWidth))
    }

    /// Finger up. Glyphs spring home, unless Reduce Motion (or they are already home) snaps them.
    public mutating func endDrag() {
        guard phase == .dragging else { return }
        smoothedSpeed = 0
        if reduceMotion || isVisuallySettled {
            snapVisuals()
            phase = .idle
        } else {
            phase = .settling
        }
    }

    /// Set the price from a binding or any other non-drag source. Snaps, and emits each crossing.
    public mutating func setValue(_ raw: Int) -> [VelocityGlyphEvent] {
        apply(span.snap(raw))
    }

    /// Move by `steps` grid increments (VoiceOver's adjustable action uses ±1). Clamped to the span.
    public mutating func adjust(by steps: Int) -> [VelocityGlyphEvent] {
        guard steps != 0 else { return [] }
        return apply(span.snap(shift(value, by: steps)))
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on {
            snapVisuals()
            smoothedSpeed = 0
            if phase == .settling { phase = .idle }
        }
    }

    /// Advance the velocity sample and the glyph springs by `dt` seconds.
    ///
    /// Velocity uses the real `dt` (`dx / dt`), so a long stalled frame does not look like a flick.
    /// Springs and `time` advance by at most ``VelocityGlyphTuning/maxFrame``. Non-positive and
    /// non-finite deltas are ignored.
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let frame = min(dt, VelocityGlyphTuning.maxFrame)
        if phase == .dragging {
            let raw = (pointerX - lastSampleX) / dt
            smoothedSpeed = VelocityGlyphMath.smooth(previous: smoothedSpeed, raw: raw, dt: frame)
            lastSampleX = pointerX
        }
        let offsetTargets = glyphs.map { target(for: $0.role) }
        let blurTarget = currentBlurTarget()
        if reduceMotion {
            snapVisuals()
        } else {
            for index in glyphs.indices {
                glyphs[index].offset.step(toward: offsetTargets[index].offset, dt: frame)
                glyphs[index].lean.step(toward: offsetTargets[index].lean, dt: frame)
            }
            blurSpring.step(toward: blurTarget, dt: frame)
        }
        time += frame
        if phase == .settling, isVisuallySettled {
            phase = .idle
            smoothedSpeed = 0
            snapVisuals()
        }
    }

    // MARK: private

    private struct GlyphBody: Equatable, Sendable {
        var role: GlyphRole
        var character: String
        var offset: WhimsySpring
        var lean: WhimsySpring
    }

    private static func makeSpring(value: Double) -> WhimsySpring {
        WhimsySpring(value: value, velocity: 0,
                     stiffness: VelocityGlyphTuning.springStiffness,
                     dampingRatio: VelocityGlyphTuning.springDamping)
    }

    private func clampX(_ x: Double) -> Double {
        WhimsyMath.clamp(x, 0, VelocityGlyphTuning.trackWidth)
    }

    private func target(for role: GlyphRole) -> (offset: Double, lean: Double) {
        guard phase == .dragging, !reduceMotion else { return (0, 0) }
        return VelocityGlyphMath.scatter(for: role, speed: smoothedSpeed)
    }

    private func currentBlurTarget() -> Double {
        guard phase == .dragging, !reduceMotion else { return 0 }
        return VelocityGlyphMath.blur(forSpeed: smoothedSpeed)
    }

    private func shift(_ value: Int, by steps: Int) -> Int {
        let current = span.snap(value)
        if steps > 0 {
            let room = (span.last - current) / span.step
            return current + min(steps, room) * span.step
        }
        let room = (current - span.lower) / span.step
        return current - min(-steps, room) * span.step
    }

    private mutating func apply(_ snapped: Int) -> [VelocityGlyphEvent] {
        let next = span.snap(snapped)
        let crossed = span.steps(from: value, to: next)
        guard next != value else { return [] }
        value = next
        syncGlyphs()
        return crossed.map { .step($0) }
    }

    /// Rebuilds the glyph list from the current price. Surviving roles keep their springs.
    /// A role that just appeared starts on the baseline.
    private mutating func syncGlyphs() {
        let kept = Dictionary(uniqueKeysWithValues: glyphs.map { ($0.role, $0) })
        glyphs = PriceGlyphs.glyphs(for: value).map { glyph in
            if var body = kept[glyph.id] {
                body.character = glyph.character
                return body
            }
            return GlyphBody(role: glyph.id, character: glyph.character,
                             offset: Self.makeSpring(value: 0), lean: Self.makeSpring(value: 0))
        }
    }

    private mutating func snapVisuals() {
        for index in glyphs.indices {
            glyphs[index].offset.snap(to: 0)
            glyphs[index].lean.snap(to: 0)
        }
        blurSpring.snap(to: 0)
    }
}
