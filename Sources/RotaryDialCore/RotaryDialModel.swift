import Foundation

public enum RotaryDialFace: String, Equatable, Sendable {
    case dial, keypad, badge
}

public enum RotaryDialPhase: String, Equatable, Sendable {
    case idle, dragging, springing, shaking, morphing, keypad, unlocked
}

public enum RotaryDialEvent: Equatable, Sendable {
    /// The number that just passed the finger stop. 0 is the tenth pulse.
    case tick(Int)
    case committed(Int)
    case rejected
    case springBack
    case wrong
    case deleted
    case morphedKeypad
    case unlocked
}

public struct RotaryDialDigit: Equatable, Sendable {
    public var digit: Int
    public var startedAt: Double
    public var origin: Vec2
}

/// Four-digit rotary lock: angle, detents, the finger stop, the return spring,
/// the entry, and the shake. The SwiftUI view only draws this and plays haptics.
public struct RotaryDialModel: Equatable, Sendable {
    public let expected: [Int]
    public private(set) var reduceMotion: Bool
    public private(set) var phase: RotaryDialPhase
    public private(set) var face: RotaryDialFace
    public private(set) var morphFrom: RotaryDialFace
    public private(set) var morph: Double
    public private(set) var rotation: Double
    public private(set) var velocity: Double
    public private(set) var digits: [RotaryDialDigit]
    public private(set) var grabbed: Int?
    public private(set) var time: Double
    public private(set) var shakeTime: Double

    private var spring: WhimsySpring
    private var awaitingVerdict: Bool
    private var lastFinger: Double
    private var fingerUnwrapped: Double
    private var grabFinger: Double
    private var grabRotation: Double
    private var detent: Int

    public init(code: String = RotaryDialTuning.defaultCode, reduceMotion: Bool = false) {
        self.init(expected: RotaryDialMath.digits(parsing: code), reduceMotion: reduceMotion)
    }

    init(expected: [Int], reduceMotion: Bool) {
        self.expected = expected
        self.reduceMotion = reduceMotion
        phase = .idle
        face = .dial
        morphFrom = .dial
        morph = 1
        rotation = 0
        velocity = 0
        digits = []
        grabbed = nil
        time = 0
        shakeTime = 0
        spring = WhimsySpring(value: 0,
                              stiffness: RotaryDialTuning.springStiffness,
                              dampingRatio: RotaryDialTuning.springDamping)
        awaitingVerdict = false
        lastFinger = 0
        fingerUnwrapped = 0
        grabFinger = 0
        grabRotation = 0
        detent = 0
    }

    public var entered: [Int] { digits.map(\.digit) }

    public var isSettled: Bool {
        if awaitingVerdict { return false }
        switch phase {
        case .dragging, .springing, .shaking, .morphing:
            return false
        case .idle, .keypad, .unlocked:
            return digits.allSatisfy { dropProgress($0) >= 1 }
        }
    }

    /// The dial accepts a finger only at rest, with room left in the code.
    public var acceptsDialDrag: Bool {
        face == .dial && digits.count < RotaryDialTuning.digitCount && !awaitingVerdict
            && (phase == .idle || phase == .dragging)
    }

    public var caption: String {
        if phase == .unlocked { return RotaryDialTuning.unlockedCaption }
        if phase == .shaking { return RotaryDialTuning.wrongCaption }
        if face == .keypad { return RotaryDialTuning.keypadCaption }
        if digits.isEmpty { return RotaryDialTuning.restCaption }
        return RotaryDialTuning.enteredAnnouncement(digits.count)
    }

    public var accessibilityValue: String {
        if phase == .unlocked { return RotaryDialTuning.unlockedCaption }
        if phase == .shaking { return "Incorrect" }
        return RotaryDialTuning.enteredAnnouncement(digits.count)
    }

    public var shakeOffset: Double {
        guard phase == .shaking else { return 0 }
        return RotaryDialMath.shakeOffset(at: shakeTime, reduceMotion: reduceMotion)
    }

    /// 1 at the start of a wrong code, falling to 0. Reduce Motion uses this instead of the shiver.
    public var errorTint: Double {
        guard phase == .shaking else { return 0 }
        let duration = reduceMotion ? RotaryDialTuning.tintDuration : RotaryDialTuning.shakeDuration
        guard duration > 0 else { return 0 }
        return max(0, 1 - shakeTime / duration)
    }

    public var visualPlate: RotaryDialPlate {
        let t = RotaryDialMath.easeInOut(morph)
        return RotaryDialPlate.lerp(.shape(for: morphFrom), .shape(for: face), t)
    }

    public var dialOpacity: Double { opacity(of: .dial) }
    public var keypadOpacity: Double { opacity(of: .keypad) }
    public var badgeOpacity: Double { opacity(of: .badge) }

    public func holeCenter(_ digit: Int) -> Vec2 {
        RotaryDialMath.holeCenter(digit: digit, rotation: rotation)
    }

    public func dropProgress(slot: Int) -> Double {
        guard slot >= 0, slot < digits.count else { return 0 }
        return dropProgress(digits[slot])
    }

    public func glyphPoint(slot: Int) -> Vec2 {
        guard slot >= 0, slot < digits.count else { return RotaryDialTuning.dotCenter(0) }
        let progress = RotaryDialMath.easeOut(dropProgress(slot: slot))
        return Vec2.lerp(digits[slot].origin, RotaryDialTuning.dotCenter(slot), progress)
    }

    public func dotFilled(slot: Int) -> Bool {
        guard slot >= 0, slot < digits.count else { return false }
        return dropProgress(slot: slot) >= 1
    }

    public mutating func setReduceMotion(_ on: Bool) {
        reduceMotion = on
        guard on else { return }
        if phase == .springing {
            spring.snap(to: 0)
            rotation = 0
            velocity = 0
            phase = .idle
        }
    }

    public mutating func reset() {
        self = RotaryDialModel(expected: expected, reduceMotion: reduceMotion)
    }

    /// Grabs a hole by its digit. Used by the golden trace, so it never calls atan2.
    @discardableResult
    public mutating func beginDrag(digit: Int) -> [RotaryDialEvent] {
        guard acceptsDialDrag, phase != .dragging, (0...9).contains(digit) else { return [] }
        phase = .dragging
        grabbed = digit
        grabRotation = rotation
        grabFinger = 0
        fingerUnwrapped = 0
        lastFinger = 0
        detent = RotaryDialMath.detentIndex(rotation)
        return []
    }

    /// Clockwise finger travel in radians, accumulated from the grab. The stop clamps it.
    @discardableResult
    public mutating func drag(byClockwise delta: Double) -> [RotaryDialEvent] {
        guard phase == .dragging, let grabbed, delta.isFinite else { return [] }
        fingerUnwrapped += delta
        let limit = RotaryDialMath.travel(forDisplay: grabbed)
        let target = RotaryDialMath.clampRotation(grabRotation + (fingerUnwrapped - grabFinger), limit: limit)
        return setRotation(target)
    }

    @discardableResult
    public mutating func beginDrag(at point: Vec2) -> [RotaryDialEvent] {
        guard acceptsDialDrag, phase != .dragging else { return [] }
        guard let digit = RotaryDialMath.hitDigit(at: point, rotation: rotation) else { return [] }
        guard let angle = RotaryDialMath.fingerAngle(point) else { return [] }
        phase = .dragging
        grabbed = digit
        grabRotation = rotation
        grabFinger = angle
        fingerUnwrapped = angle
        lastFinger = angle
        detent = RotaryDialMath.detentIndex(rotation)
        return []
    }

    @discardableResult
    public mutating func updateDrag(at point: Vec2) -> [RotaryDialEvent] {
        guard phase == .dragging, let grabbed else { return [] }
        guard let angle = RotaryDialMath.fingerAngle(point) else { return [] }
        let delta = RotaryDialMath.wrapPi(angle - lastFinger)
        lastFinger = angle
        fingerUnwrapped += delta
        let limit = RotaryDialMath.travel(forDisplay: grabbed)
        let target = RotaryDialMath.clampRotation(grabRotation + (fingerUnwrapped - grabFinger), limit: limit)
        return setRotation(target)
    }

    @discardableResult
    public mutating func release() -> [RotaryDialEvent] {
        guard phase == .dragging, let grabbed else { return [] }
        let limit = RotaryDialMath.travel(forDisplay: grabbed)
        let accept = rotation + 1e-9 >= limit - RotaryDialTuning.commitSlop && rotation > 0
        var events: [RotaryDialEvent] = []
        if accept {
            append(digit: grabbed, origin: RotaryDialMath.holeCenter(digit: grabbed, rotation: rotation))
            events.append(.committed(grabbed))
        } else {
            events.append(.rejected)
        }
        if rotation > 0.01 { events.append(.springBack) }
        self.grabbed = nil
        if reduceMotion {
            spring.snap(to: 0)
            rotation = 0
            velocity = 0
            phase = .idle
            if digits.count == RotaryDialTuning.digitCount {
                events += startVerdict()
            }
        } else {
            spring = WhimsySpring(value: rotation, velocity: 0,
                                  stiffness: RotaryDialTuning.springStiffness,
                                  dampingRatio: RotaryDialTuning.springDamping)
            velocity = 0
            phase = .springing
            if digits.count == RotaryDialTuning.digitCount { awaitingVerdict = true }
        }
        return events
    }

    /// VoiceOver digit buttons, and the keypad, enter a number without a drag.
    @discardableResult
    public mutating func enterDigit(_ digit: Int) -> [RotaryDialEvent] {
        guard (0...9).contains(digit) else { return [] }
        guard digits.count < RotaryDialTuning.digitCount, !awaitingVerdict else { return [] }
        guard phase == .idle || phase == .keypad else { return [] }
        let origin = face == .keypad
            ? RotaryDialTuning.keyCenter(digit: digit)
            : RotaryDialMath.holeCenter(digit: digit, rotation: 0)
        append(digit: digit, origin: origin)
        var events: [RotaryDialEvent] = [.committed(digit)]
        if digits.count == RotaryDialTuning.digitCount {
            if reduceMotion {
                events += startVerdict()
            } else {
                awaitingVerdict = true
            }
        }
        return events
    }

    @discardableResult
    public mutating func deleteDigit() -> [RotaryDialEvent] {
        guard phase == .idle || phase == .keypad, !awaitingVerdict, !digits.isEmpty else { return [] }
        digits.removeLast()
        return [.deleted]
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [RotaryDialEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        let dt = min(dt, WhimsySpring.maxFrame)
        time += dt
        var events: [RotaryDialEvent] = []
        switch phase {
        case .springing:
            spring.step(toward: 0, dt: dt)
            rotation = spring.value
            velocity = spring.velocity
            if spring.value <= 0 || spring.isSettled(at: 0) {
                spring.snap(to: 0)
                rotation = 0
                velocity = 0
                phase = .idle
            }
            if rotation < 0 { rotation = 0 }
            events += noteDetent()
        case .shaking:
            shakeTime += dt
            let duration = reduceMotion ? RotaryDialTuning.tintDuration : RotaryDialTuning.shakeDuration
            if shakeTime >= duration {
                shakeTime = duration
                events += finishShake()
            }
        case .morphing:
            let duration = reduceMotion ? RotaryDialTuning.reduceMorphDuration : RotaryDialTuning.morphDuration
            morph += dt / duration
            if morph >= 1 {
                morph = 1
                events += finishMorph()
            }
        case .idle, .dragging, .keypad, .unlocked:
            break
        }
        if readyForVerdict() {
            events += startVerdict()
        }
        return events
    }

    // MARK: private

    private func dropProgress(_ digit: RotaryDialDigit) -> Double {
        if reduceMotion { return 1 }
        return WhimsyMath.clamp01((time - digit.startedAt) / RotaryDialTuning.dropDuration)
    }

    private func opacity(of target: RotaryDialFace) -> Double {
        let t = RotaryDialMath.easeInOut(morph)
        if face == target && morphFrom == target { return 1 }
        if face == target { return t }
        if morphFrom == target { return 1 - t }
        return 0
    }

    private mutating func append(digit: Int, origin: Vec2) {
        digits.append(RotaryDialDigit(digit: digit, startedAt: time, origin: origin))
    }

    private mutating func setRotation(_ next: Double) -> [RotaryDialEvent] {
        guard let grabbed else { return [] }
        let limit = RotaryDialMath.travel(forDisplay: grabbed)
        rotation = RotaryDialMath.clampRotation(next, limit: limit)
        velocity = 0
        return noteDetent()
    }

    /// Ticks every hole-step the wheel just reached or left, including the spring home.
    private mutating func noteDetent() -> [RotaryDialEvent] {
        let index = RotaryDialMath.detentIndex(rotation)
        guard index != detent else { return [] }
        let events = ticks(from: detent, to: index)
        detent = index
        return events
    }

    private func ticks(from old: Int, to new: Int) -> [RotaryDialEvent] {
        var events: [RotaryDialEvent] = []
        if new > old {
            for pulse in (old + 1)...new {
                events.append(.tick(RotaryDialMath.display(forPulse: pulse)))
            }
        } else if new < old {
            for pulse in stride(from: old, to: new, by: -1) {
                events.append(.tick(RotaryDialMath.display(forPulse: pulse)))
            }
        }
        return events
    }

    private func readyForVerdict() -> Bool {
        guard awaitingVerdict, digits.count == RotaryDialTuning.digitCount else { return false }
        guard phase == .idle || phase == .keypad else { return false }
        return digits.allSatisfy { dropProgress($0) >= 1 }
    }

    private mutating func startVerdict() -> [RotaryDialEvent] {
        awaitingVerdict = false
        if entered == expected {
            return beginMorph(to: .badge)
        }
        return beginShake()
    }

    private mutating func beginShake() -> [RotaryDialEvent] {
        phase = .shaking
        shakeTime = 0
        return [.wrong]
    }

    private mutating func finishShake() -> [RotaryDialEvent] {
        digits.removeAll()
        if face == .dial {
            return beginMorph(to: .keypad)
        }
        phase = .keypad
        return []
    }

    private mutating func beginMorph(to target: RotaryDialFace) -> [RotaryDialEvent] {
        if face == target {
            morph = 1
            morphFrom = target
            phase = target == .badge ? .unlocked : .keypad
            return target == .badge ? [.unlocked] : []
        }
        morphFrom = face
        face = target
        morph = 0
        phase = .morphing
        return []
    }

    private mutating func finishMorph() -> [RotaryDialEvent] {
        morph = 1
        morphFrom = face
        if face == .badge {
            phase = .unlocked
            return [.unlocked]
        }
        digits.removeAll()
        phase = .keypad
        return [.morphedKeypad]
    }
}

extension RotaryDialMath {
    /// Digit characters, left-padded with zeroes to four. Extra digits keep the first four.
    public static func digits(parsing code: String) -> [Int] {
        let raw = code.compactMap(\.wholeNumberValue).filter { (0...9).contains($0) }
        if raw.count >= RotaryDialTuning.digitCount {
            return Array(raw.prefix(RotaryDialTuning.digitCount))
        }
        return Array(repeating: 0, count: RotaryDialTuning.digitCount - raw.count) + raw
    }
}
