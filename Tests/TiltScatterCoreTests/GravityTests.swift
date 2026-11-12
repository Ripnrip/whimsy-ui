import Testing
import Foundation
@testable import TiltScatterCore

@Suite("Gravity and tilt") struct GravityTests {
    @Test func levelTrayPullsStraightDown() {
        let g = TiltScatterGravity.acceleration(tilt: .zero)
        let expected = TiltScatterMath.sin(TiltScatterGravity.neutralPitch) * TiltScatterGravity.magnitude
        #expect(g.x == 0)
        #expect(g.y == expected)
        #expect(g.y > 0)
    }

    @Test func rollRightLeansRightAndKeepsTheSameDownComponent() {
        let right = TiltScatterGravity.acceleration(tilt: Vec2(1, 0))
        let left = TiltScatterGravity.acceleration(tilt: Vec2(-1, 0))
        let level = TiltScatterGravity.acceleration(tilt: .zero)
        #expect(right.x > 200)
        #expect(left.x < -200)
        #expect(right.x == -left.x)
        #expect(right.y == left.y)
        #expect(right.y == level.y)
    }

    @Test func pitchingBackCanSendLettersUpTheScreen() {
        let level = TiltScatterGravity.acceleration(tilt: .zero)
        let back = TiltScatterGravity.acceleration(tilt: Vec2(0, 1))
        let forward = TiltScatterGravity.acceleration(tilt: Vec2(0, -1))
        #expect(back.y < 0)
        #expect(forward.y > level.y)
    }

    @Test func tiltIsClamped() {
        let full = TiltScatterGravity.acceleration(tilt: Vec2(1, -1))
        let past = TiltScatterGravity.acceleration(tilt: Vec2(4, -9))
        #expect(full == past)
    }

    @Test func nonFiniteTiltFallsBackToLevel() {
        let level = TiltScatterGravity.acceleration(tilt: .zero)
        #expect(TiltScatterGravity.acceleration(tilt: Vec2(.nan, 0)) == level)
        #expect(TiltScatterGravity.acceleration(tilt: Vec2(0, .infinity)) == level)
    }

    @Test func polynomialSinMatchesKnownValues() {
        #expect(TiltScatterMath.sin(0) == 0)
        #expect(abs(TiltScatterMath.sin(TiltScatterMath.halfPi) - 1) < 1e-12)
        #expect(abs(TiltScatterMath.sin(.pi) ) < 1e-12)
        #expect(abs(TiltScatterMath.cos(0) - 1) < 1e-12)
        #expect(TiltScatterMath.sin(.nan) == 0)
    }

    @Test func devicePitchAboveNeutralStrengthensDown() {
        let level = TiltScatterMotionMap.tilt(pitch: TiltScatterMotionMap.neutralPitch, roll: 0)
        #expect(level == .zero)
        let downhill = TiltScatterMotionMap.tilt(pitch: TiltScatterMotionMap.neutralPitch + 0.2, roll: 0)
        #expect(downhill.y < 0)
        let uphill = TiltScatterMotionMap.tilt(pitch: TiltScatterMotionMap.neutralPitch - 0.2, roll: 0)
        #expect(uphill.y > 0)
    }

    @Test func deviceRollRightTipsRight() {
        let tip = TiltScatterMotionMap.tilt(pitch: TiltScatterMotionMap.neutralPitch, roll: 0.3)
        #expect(tip.x > 0)
        #expect(tip.y == 0)
        let clamped = TiltScatterMotionMap.tilt(pitch: 4, roll: -4)
        #expect(clamped.x == -1)
        #expect(clamped.y == -1 || clamped.y == 1)
        #expect(abs(clamped.y) == 1)
    }

    @Test func fingerOnTheRightAndBelowCentre() {
        let size = Vec2(300, 160)
        let right = TiltScatterMotionMap.tilt(fromFinger: Vec2(300, 80), in: size)
        #expect(right.x == 1)
        #expect(abs(right.y) < 1e-9)
        let below = TiltScatterMotionMap.tilt(fromFinger: Vec2(150, 160), in: size)
        #expect(below.y == -1)
        #expect(TiltScatterMotionMap.tilt(fromFinger: Vec2(.nan, 0), in: size) == .zero)
        #expect(TiltScatterMotionMap.tilt(fromFinger: Vec2(1, 1), in: Vec2(0, 0)) == .zero)
    }

    @Test func nonFiniteAttitudeIsLevel() {
        #expect(TiltScatterMotionMap.tilt(pitch: .nan, roll: 0.2) == .zero)
    }
}
