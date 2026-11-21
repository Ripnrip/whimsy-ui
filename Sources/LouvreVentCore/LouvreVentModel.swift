import Foundation

/// A louvre vent whose set point is an integer temperature.
///
/// Hotter opens the seven blades (0° closed, 70° open) and drives the chamber
/// from deep orange to white-hot. The displayed angle and glow spring toward the
/// set point, and a highlight sweeps each blade face while they are turning.
/// Reduce Motion snaps the angle and the glow and leaves the highlight at rest.
///
/// Dragging up (a smaller scene Y) raises the temperature. Every integer degree
/// crossed emits one ``LouvreVentEvent/tick(_:)``. Setting the temperature to the
/// value it already holds, including a value that clamps to the current stop, emits nothing.
public struct LouvreVentModel: Sendable {
    public private(set) var range: ClosedRange<Int>
    public private(set) var temperature: Int
    public private(set) var reduceMotion: Bool
    public private(set) var isDragging = false
    public private(set) var sweepEnvelope = 0.0
    public private(set) var sweepPhase = 0.0

    private var spring: WhimsySpring

    public init(
        temperature: Int = 68,
        range: ClosedRange<Int> = LouvreVentTuning.defaultRange,
        reduceMotion: Bool = false
    ) {
        self.range = range
        self.temperature = LouvreVentMath.clamp(temperature, to: range)
        self.reduceMotion = reduceMotion
        let unit = LouvreVentMath.unit(temperature: self.temperature, range: range)
        spring = WhimsySpring(
            value: unit,
            velocity: 0,
            stiffness: LouvreVentTuning.stiffness,
            dampingRatio: LouvreVentTuning.dampingRatio
        )
    }

    public var targetUnit: Double {
        LouvreVentMath.unit(temperature: temperature, range: range)
    }

    /// The spring's position. Reduce Motion reports the target, so a set point
    /// change is visible before the next `step`.
    public var displayedUnit: Double {
        reduceMotion ? targetUnit : spring.value
    }

    public var displayVelocity: Double { reduceMotion ? 0 : spring.velocity }

    public var targetAngle: Double { LouvreVentMath.angle(unit: targetUnit) }
    public var displayAngle: Double { LouvreVentMath.angle(unit: displayedUnit) }

    public var targetGlow: LouvreGlow { LouvreVentMath.glow(unit: targetUnit) }
    public var glow: LouvreGlow { LouvreVentMath.glow(unit: displayedUnit) }

    /// −1…1 traveling offset. Zero when the envelope is down, and always zero
    /// under Reduce Motion.
    public var sweepSignal: Double {
        if reduceMotion || sweepEnvelope == 0 { return 0 }
        return LouvreVentMath.triangle(sweepPhase) * sweepEnvelope
    }

    public var readout: String { String(temperature) }
    public var accessibilityLabel: String { LouvreVentTuning.accessibilityLabel }
    public var accessibilityValue: String { LouvreVentTuning.accessibilityValue(temperature: temperature) }
    public var accessibilityHint: String { LouvreVentTuning.accessibilityHint }

    public var animates: Bool {
        if reduceMotion || isDragging { return isDragging && !reduceMotion }
        if sweepEnvelope > 0.001 { return true }
        return !spring.isSettled(at: targetUnit, tolerance: LouvreVentTuning.settleTolerance)
    }

    public var slots: [LouvreBladeSlot] {
        LouvreVentMath.slots(unit: displayedUnit, sweep: sweepSignal, reduceMotion: reduceMotion)
    }

    public func specularOffset(blade: Int) -> Double {
        LouvreVentMath.specular(
            blade: blade,
            unit: displayedUnit,
            sweep: sweepSignal,
            reduceMotion: reduceMotion
        )
    }

    public func specularIntensity() -> Double {
        LouvreVentMath.specularIntensity(unit: displayedUnit)
    }

    /// Replace the set point. Emits one tick per integer degree crossed, and none
    /// when the clamped result is the current temperature.
    public mutating func setTemperature(_ raw: Int) -> [LouvreVentEvent] {
        let events = apply(raw)
        if reduceMotion { snapDisplay() }
        return events
    }

    /// Move by `steps` degrees. VoiceOver's adjustable action uses ±1.
    /// Zero steps emit nothing. The result is clamped to the range.
    public mutating func adjust(by steps: Int) -> [LouvreVentEvent] {
        guard steps != 0 else { return [] }
        let (next, overflow) = temperature.addingReportingOverflow(steps)
        if overflow {
            return setTemperature(steps > 0 ? range.upperBound : range.lowerBound)
        }
        return setTemperature(next)
    }

    /// Finger down at scene Y. Non-finite Y does not start a drag.
    public mutating func beginDrag(sceneY: Double) -> [LouvreVentEvent] {
        guard sceneY.isFinite else { return [] }
        isDragging = true
        return setTemperature(LouvreVentMath.temperature(forSceneY: sceneY, range: range))
    }

    /// Finger moved. Ignored when no drag is in progress, and when Y is not finite.
    public mutating func updateDrag(sceneY: Double) -> [LouvreVentEvent] {
        guard isDragging, sceneY.isFinite else { return [] }
        return setTemperature(LouvreVentMath.temperature(forSceneY: sceneY, range: range))
    }

    public mutating func endDrag() {
        isDragging = false
    }

    /// Replace the limits. The set point is clamped into the new range, one tick
    /// per degree it moves. A range that leaves the degree where it is still
    /// retargets the blades, because that degree sits at a new place in the span.
    /// Reduce Motion snaps the angle and the glow.
    public mutating func setRange(_ newRange: ClosedRange<Int>) -> [LouvreVentEvent] {
        guard newRange != range else { return [] }
        range = newRange
        let events = apply(temperature)
        if reduceMotion { snapDisplay() }
        return events
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on { snapDisplay() }
    }

    /// Advance the spring and the highlight sweep by `dt` seconds.
    /// A stalled frame is clamped to ``WhimsySpring/maxFrame``. Non-positive and
    /// non-finite deltas are ignored. Reduce Motion stays snapped and does not sweep.
    public mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let frame = min(dt, WhimsySpring.maxFrame)
        if reduceMotion {
            snapDisplay()
            return
        }
        spring.step(toward: targetUnit, dt: frame)
        let moving = isDragging || !spring.isSettled(at: targetUnit, tolerance: LouvreVentTuning.settleTolerance)
        advanceSweep(frame, moving: moving)
    }

    // MARK: private

    private mutating func apply(_ raw: Int) -> [LouvreVentEvent] {
        let next = LouvreVentMath.clamp(raw, to: range)
        let (delta, overflow) = next.subtractingReportingOverflow(temperature)
        if overflow {
            temperature = next
            return [.tick(next)]
        }
        if delta == 0 { return [] }
        let step = delta > 0 ? 1 : -1
        var events: [LouvreVentEvent] = []
        var cursor = temperature
        while cursor != next {
            cursor += step
            events.append(.tick(cursor))
        }
        temperature = next
        return events
    }

    private mutating func snapDisplay() {
        spring.snap(to: targetUnit)
        sweepEnvelope = 0
        sweepPhase = 0
    }

    private mutating func advanceSweep(_ dt: Double, moving: Bool) {
        let target = moving ? 1.0 : 0.0
        let rate = moving ? LouvreVentTuning.sweepRise : LouvreVentTuning.sweepFall
        let delta = target - sweepEnvelope
        let limit = rate * dt
        if abs(delta) <= limit {
            sweepEnvelope = target
        } else {
            sweepEnvelope += delta > 0 ? limit : -limit
        }
        sweepPhase += LouvreVentTuning.sweepOmega * dt * sweepEnvelope
        guard sweepPhase.isFinite else {
            sweepPhase = 0
            return
        }
        sweepPhase -= sweepPhase.rounded(.down)
    }
}
