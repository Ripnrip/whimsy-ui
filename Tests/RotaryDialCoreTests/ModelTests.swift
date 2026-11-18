import Foundation
import Testing
@testable import RotaryDialCore

private extension RotaryDialModel {
    mutating func frames(_ count: Int, dt: Double = 1.0 / 60) {
        for _ in 0..<count { step(dt) }
    }
}

private func ticks(_ events: [RotaryDialEvent]) -> [Int] {
    events.compactMap { event in
        if case .tick(let digit) = event { return digit }
        return nil
    }
}

@Suite("Dial entry") struct ModelTests {
    @Test func aFullDragOfFiveTicksEachNumberOnce() {
        var model = RotaryDialModel(code: "5216")
        let slice = RotaryDialMath.travel(forDisplay: 5) / 5
        #expect(model.beginDrag(digit: 5).isEmpty)
        #expect(model.phase == .dragging)
        #expect(model.grabbed == 5)
        var heard: [Int] = []
        for _ in 0..<5 {
            heard += ticks(model.drag(byClockwise: slice))
        }
        #expect(heard == [1, 2, 3, 4, 5])
        #expect(abs(model.rotation - RotaryDialMath.travel(forDisplay: 5)) < 1e-9)
        let extra = model.drag(byClockwise: slice * 3)
        #expect(extra.isEmpty)
        #expect(abs(model.rotation - RotaryDialMath.travel(forDisplay: 5)) < 1e-9)
    }

    @Test func backingUpReticksTheBoundary() {
        var model = RotaryDialModel()
        _ = model.beginDrag(digit: 4)
        let slice = RotaryDialTuning.holeStep
        #expect(ticks(model.drag(byClockwise: slice)) == [1])
        #expect(ticks(model.drag(byClockwise: -slice * 0.5 + slice * 0.5)) == [])
        #expect(ticks(model.drag(byClockwise: slice)) == [2])
        #expect(ticks(model.drag(byClockwise: -slice)) == [2])
        #expect(ticks(model.drag(byClockwise: slice)) == [2])
    }

    @Test func theFingerStopHoldsSlackUntilTheFingerComesBack() {
        var model = RotaryDialModel()
        _ = model.beginDrag(digit: 1)
        let step = RotaryDialTuning.holeStep
        _ = model.drag(byClockwise: step * 3)
        #expect(abs(model.rotation - step) < 1e-9)
        _ = model.drag(byClockwise: -step * 0.4)
        #expect(abs(model.rotation - step) < 1e-9)
        _ = model.drag(byClockwise: -step * 2.1)
        #expect(abs(model.rotation - step * 0.5) < 1e-9)
    }

    @Test func zeroTicksAllTenNumbers() {
        var model = RotaryDialModel()
        _ = model.beginDrag(digit: 0)
        let slice = RotaryDialTuning.holeStep
        var heard: [Int] = []
        for _ in 0..<10 { heard += ticks(model.drag(byClockwise: slice)) }
        #expect(heard == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
    }

    @Test func releasingEarlySpringsHomeWithoutADigit() {
        var model = RotaryDialModel()
        _ = model.beginDrag(digit: 6)
        _ = model.drag(byClockwise: RotaryDialTuning.holeStep * 2)
        let events = model.release()
        #expect(events.contains(.rejected))
        #expect(events.contains(.springBack))
        #expect(!events.contains(.committed(6)))
        #expect(model.phase == .springing)
        #expect(model.entered.isEmpty)
        model.frames(48)
        #expect(model.phase == .idle)
        #expect(model.rotation == 0)
        #expect(model.velocity == 0)
        #expect(model.isSettled)
    }

    @Test func releasingOnTheStopDropsTheDigit() {
        var model = RotaryDialModel(code: "5216")
        _ = model.beginDrag(digit: 5)
        _ = model.drag(byClockwise: RotaryDialMath.travel(forDisplay: 5))
        let events = model.release()
        #expect(events.contains(.committed(5)))
        #expect(events.contains(.springBack))
        #expect(model.entered == [5])
        #expect(model.dropProgress(slot: 0) == 0)
        model.frames(48)
        #expect(model.phase == .idle)
        #expect(model.rotation == 0)
        #expect(model.dotFilled(slot: 0))
        #expect(model.caption == "1 of 4")
        #expect(model.accessibilityValue == "1 of 4")
    }

    @Test func theSlopBoundaryDecidesTheCommit() {
        let limit = RotaryDialMath.travel(forDisplay: 3)
        var early = RotaryDialModel()
        _ = early.beginDrag(digit: 3)
        _ = early.drag(byClockwise: limit - RotaryDialTuning.commitSlop - RotaryDialTuning.holeStep * 0.05)
        #expect(early.release().contains(.rejected))

        var late = RotaryDialModel()
        _ = late.beginDrag(digit: 3)
        _ = late.drag(byClockwise: limit - RotaryDialTuning.commitSlop + RotaryDialTuning.holeStep * 0.05)
        #expect(late.release().contains(.committed(3)))
    }

    @Test func aCorrectCodeMorphsToTheBadge() {
        var model = RotaryDialModel(code: "5216")
        for digit in [5, 2, 1] {
            _ = model.enterDigit(digit)
        }
        #expect(model.phase == .idle)
        let fourth = model.enterDigit(6)
        #expect(fourth == [.committed(6)])
        #expect(model.phase == .idle)
        model.frames(30)
        #expect(model.phase == .morphing)
        #expect(model.face == .badge)
        #expect(model.morphFrom == .dial)
        model.frames(40)
        #expect(model.phase == .unlocked)
        #expect(model.face == .badge)
        #expect(model.badgeOpacity == 1)
        #expect(model.dialOpacity == 0)
        #expect(model.caption == RotaryDialTuning.unlockedCaption)
        #expect(model.enterDigit(1).isEmpty)
    }

    @Test func aWrongCodeShakesThenBecomesTheKeypad() {
        var model = RotaryDialModel(code: "5216")
        for digit in [1, 1, 1, 1] {
            _ = model.enterDigit(digit)
        }
        model.frames(30)
        #expect(model.phase == .shaking)
        #expect(model.entered == [1, 1, 1, 1])
        #expect(model.shakeOffset != 0)
        #expect(model.errorTint > 0)
        #expect(model.caption == RotaryDialTuning.wrongCaption)
        model.frames(40)
        #expect(model.phase == .morphing)
        #expect(model.face == .keypad)
        #expect(model.entered.isEmpty)
        model.frames(40)
        #expect(model.phase == .keypad)
        #expect(model.keypadOpacity == 1)
        #expect(model.dialOpacity == 0)
        #expect(model.caption == RotaryDialTuning.keypadCaption)
    }

    @Test func theKeypadCanStillMissAndThenUnlock() {
        var model = RotaryDialModel(code: "5216")
        for digit in [9, 9, 9, 9] { _ = model.enterDigit(digit) }
        model.frames(100)
        #expect(model.phase == .keypad)
        for digit in [1, 1, 1, 1] { _ = model.enterDigit(digit) }
        model.frames(24)
        #expect(model.phase == .shaking)
        #expect(model.face == .keypad)
        model.frames(40)
        #expect(model.phase == .keypad)
        #expect(model.entered.isEmpty)
        #expect(model.face == .keypad)
        for digit in [5, 2, 1, 6] { _ = model.enterDigit(digit) }
        model.frames(80)
        #expect(model.phase == .unlocked)
        #expect(model.face == .badge)
    }

    @Test func reduceMotionSnapsAndTintsInsteadOfSpinningOrShaking() {
        var model = RotaryDialModel(code: "5216", reduceMotion: true)
        _ = model.beginDrag(digit: 5)
        _ = model.drag(byClockwise: RotaryDialMath.travel(forDisplay: 5))
        let events = model.release()
        #expect(events.contains(.committed(5)))
        #expect(model.phase == .idle)
        #expect(model.rotation == 0)
        #expect(model.dotFilled(slot: 0))
        for digit in [0, 0, 0] { _ = model.enterDigit(digit) }
        #expect(model.phase == .shaking)
        #expect(model.shakeOffset == 0)
        #expect(model.errorTint == 1)
        model.frames(30)
        #expect(model.phase == .morphing || model.phase == .keypad)
        model.frames(30)
        #expect(model.phase == .keypad)
        #expect(model.shakeOffset == 0)
    }

    @Test func deleteRemovesTheLastDigitAndResetRestoresTheDial() {
        var model = RotaryDialModel(code: "5216")
        #expect(model.deleteDigit().isEmpty)
        _ = model.enterDigit(5)
        _ = model.enterDigit(2)
        #expect(model.deleteDigit() == [.deleted])
        #expect(model.entered == [5])
        _ = model.enterDigit(2)
        _ = model.enterDigit(1)
        _ = model.enterDigit(6)
        model.frames(80)
        #expect(model.phase == .unlocked)
        model.reset()
        #expect(model.phase == .idle)
        #expect(model.face == .dial)
        #expect(model.entered.isEmpty)
        #expect(model.rotation == 0)
        #expect(model.expected == [5, 2, 1, 6])
    }

    @Test func aDragCannotStartWhileTheDialIsSpringingOrFull() {
        var model = RotaryDialModel()
        _ = model.beginDrag(digit: 4)
        _ = model.drag(byClockwise: RotaryDialTuning.holeStep)
        _ = model.release()
        #expect(model.phase == .springing)
        #expect(model.beginDrag(digit: 2).isEmpty)
        #expect(model.grabbed == nil)
        model.frames(48)
        for digit in [1, 2, 3, 4] { _ = model.enterDigit(digit) }
        #expect(model.beginDrag(digit: 8).isEmpty)
    }

    @Test func pointingAtAHoleDrivesTheSameStop() {
        var model = RotaryDialModel()
        let start = RotaryDialMath.holeCenter(digit: 2, rotation: 0)
        #expect(model.beginDrag(at: start).isEmpty)
        #expect(model.grabbed == 2)
        let travel = RotaryDialMath.travel(forDisplay: 2)
        let steps = 24
        var heard: [Int] = []
        for i in 1...steps {
            let angle = RotaryDialMath.restAngle(forDisplay: 2) + travel * Double(i) / Double(steps)
            let point = RotaryDialMath.pointOnOrbit(angle, radius: RotaryDialTuning.holeOrbit)
            heard += ticks(model.updateDrag(at: point))
        }
        #expect(heard == [1, 2])
        #expect(abs(model.rotation - travel) < 1e-6)
        #expect(model.release().contains(.committed(2)))
        let miss = Vec2(RotaryDialTuning.centerX, RotaryDialTuning.centerY)
        model.frames(48)
        #expect(model.beginDrag(at: miss).isEmpty)
        #expect(model.phase == .idle)
    }

    @Test func plateWidthTravelsFromTheDialToTheBadge() {
        let dial = RotaryDialPlate.shape(for: .dial)
        var model = RotaryDialModel(code: "1111")
        #expect(model.visualPlate == dial)
        _ = model.enterDigit(1)
        _ = model.enterDigit(1)
        _ = model.enterDigit(1)
        _ = model.enterDigit(1)
        model.frames(30)
        #expect(model.phase == .morphing)
        #expect(model.morph < 0.4)
        let mid = model.visualPlate
        model.frames(8)
        #expect(model.visualPlate.width < mid.width)
        model.frames(40)
        #expect(model.visualPlate == .shape(for: .badge))
    }
}
