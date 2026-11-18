import Foundation
import Testing
@testable import RotaryDialCore

@Suite("Dial geometry") struct MathTests {
    @Test func wrapPiKeepsTheOpenClosedRange() {
        #expect(RotaryDialMath.wrapPi(0) == 0)
        #expect(RotaryDialMath.wrapPi(Double.pi) == Double.pi)
        #expect(RotaryDialMath.wrapPi(-Double.pi) == Double.pi)
        #expect(abs(RotaryDialMath.wrapPi(3) - 3) < 1e-12)
        #expect(abs(RotaryDialMath.wrapPi(Double.pi + 0.2) + (Double.pi - 0.2)) < 1e-9)
        #expect(RotaryDialMath.wrapPi(.nan) == 0)
    }

    @Test func zeroIsTenPulsesAndOneIsASingleStep() {
        #expect(RotaryDialMath.pulse(forDisplay: 0) == 10)
        #expect(RotaryDialMath.pulse(forDisplay: 1) == 1)
        #expect(RotaryDialMath.display(forPulse: 10) == 0)
        #expect(RotaryDialMath.display(forPulse: 7) == 7)
        #expect(abs(RotaryDialMath.travel(forDisplay: 1) - RotaryDialTuning.holeStep) < 1e-12)
        #expect(abs(RotaryDialMath.travel(forDisplay: 0) - RotaryDialTuning.maxTravel) < 1e-12)
        #expect(RotaryDialTuning.maxTravel < Double.pi * 2)
    }

    @Test func digitOneRestsOneStepCounterClockwiseOfTheStop() {
        let rest = RotaryDialMath.restAngle(forDisplay: 1)
        #expect(abs(rest - (RotaryDialTuning.stopAngle - RotaryDialTuning.holeStep)) < 1e-12)
        let parked = rest + RotaryDialMath.travel(forDisplay: 1)
        #expect(abs(parked - RotaryDialTuning.stopAngle) < 1e-12)
    }

    @Test func draggingAHoleToItsTravelParksItOnTheStop() {
        for digit in 0...9 {
            let rotation = RotaryDialMath.travel(forDisplay: digit)
            let center = RotaryDialMath.holeCenter(digit: digit, rotation: rotation)
            let stop = RotaryDialMath.pointOnOrbit(RotaryDialTuning.stopAngle, radius: RotaryDialTuning.holeOrbit)
            #expect(abs(center.x - stop.x) < 1e-9)
            #expect(abs(center.y - stop.y) < 1e-9)
        }
    }

    @Test func detentsCountExactStepsAndNothingBeforeTheFirst() {
        #expect(RotaryDialMath.detentIndex(0) == 0)
        #expect(RotaryDialMath.detentIndex(-0.2) == 0)
        #expect(RotaryDialMath.detentIndex(RotaryDialTuning.holeStep * 0.5) == 0)
        #expect(RotaryDialMath.detentIndex(RotaryDialTuning.holeStep) == 1)
        #expect(RotaryDialMath.detentIndex(RotaryDialTuning.holeStep * 5) == 5)
        #expect(RotaryDialMath.detentIndex(RotaryDialTuning.maxTravel) == 10)
        #expect(RotaryDialMath.detentIndex(RotaryDialTuning.maxTravel + 2) == 10)
    }

    @Test func theStopClampsAGrabbedHole() {
        let limit = RotaryDialMath.travel(forDisplay: 1)
        #expect(RotaryDialMath.clampRotation(limit + 1, limit: limit) == limit)
        #expect(RotaryDialMath.clampRotation(-0.4, limit: limit) == 0)
        #expect(RotaryDialMath.clampRotation(limit * 0.5, limit: limit) == limit * 0.5)
    }

    @Test func hitTestingFindsAHoleAndMissesTheHub() {
        let hole = RotaryDialMath.holeCenter(digit: 7, rotation: 0)
        #expect(RotaryDialMath.hitDigit(at: hole, rotation: 0) == 7)
        let hub = Vec2(RotaryDialTuning.centerX, RotaryDialTuning.centerY)
        #expect(RotaryDialMath.hitDigit(at: hub, rotation: 0) == nil)
        #expect(RotaryDialMath.hitDigit(at: Vec2(-40, -40), rotation: 0) == nil)
        #expect(RotaryDialMath.fingerAngle(hub) == nil)
    }

    @Test func holesDoNotOverlapTheirGrabRadii() {
        let reach = RotaryDialTuning.holeRadius + RotaryDialTuning.hitSlop
        for digit in 0..<10 {
            let a = RotaryDialMath.holeCenter(digit: digit, rotation: 0)
            let b = RotaryDialMath.holeCenter(digit: (digit + 1) % 10, rotation: 0)
            #expect(a.distance(to: b) > reach * 2)
        }
    }

    @Test func codeParsingPadsAndKeepsTheFirstFourDigits() {
        #expect(RotaryDialMath.digits(parsing: "5216") == [5, 2, 1, 6])
        #expect(RotaryDialMath.digits(parsing: "42") == [0, 0, 4, 2])
        #expect(RotaryDialMath.digits(parsing: "") == [0, 0, 0, 0])
        #expect(RotaryDialMath.digits(parsing: "12a3") == [0, 1, 2, 3])
        #expect(RotaryDialMath.digits(parsing: "12345") == [1, 2, 3, 4])
    }

    @Test func polynomialSineMatchesTheCorners() {
        #expect(abs(RotaryDialMath.sin(0)) < 1e-12)
        #expect(abs(RotaryDialMath.sin(Double.pi)) < 1e-6)
        #expect(RotaryDialMath.sin(0.3) > 0.29)
        #expect(RotaryDialMath.shakeOffset(at: 0.1, reduceMotion: true) == 0)
        #expect(RotaryDialMath.shakeOffset(at: 0, reduceMotion: false) == 0)
        #expect(RotaryDialMath.shakeOffset(at: 0.12, reduceMotion: false) != 0)
    }

    @Test func easeInOutIsIdentityAtTheEndsAndTheMiddle() {
        #expect(RotaryDialMath.easeInOut(0) == 0)
        #expect(RotaryDialMath.easeInOut(1) == 1)
        #expect(abs(RotaryDialMath.easeInOut(0.5) - 0.5) < 1e-12)
        #expect(RotaryDialMath.easeOut(0) == 0)
        #expect(RotaryDialMath.easeOut(1) == 1)
    }
}
