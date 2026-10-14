import Testing
import Foundation
@testable import AliveEyesCore

private func trace(_ m: inout AliveEyesModel, seconds: Double, fps: Double = 60) -> [EyesFrame] {
    (0..<Int(seconds * fps)).map { _ in m.step(dt: 1 / fps); return m.frame }
}

@Suite("Model")
struct ModelTests {
    @Test func sameSeedSameFrames() {
        var a = AliveEyesModel(seed: 123), b = AliveEyesModel(seed: 123)
        #expect(trace(&a, seconds: 20) == trace(&b, seconds: 20))
    }

    @Test func differentSeedsDiverge() {
        var a = AliveEyesModel(seed: 1), b = AliveEyesModel(seed: 2)
        #expect(trace(&a, seconds: 5) != trace(&b, seconds: 5))
    }

    @Test func idleEyesAreNeverStill() {
        var m = AliveEyesModel(seed: 5)
        let frames = trace(&m, seconds: 10)
        let gazes = Set(frames.map { "\(($0.gaze.x * 1000).rounded()),\(($0.gaze.y * 1000).rounded())" })
        #expect(gazes.count > 20)
        #expect(frames.allSatisfy { $0.gaze.length < 0.08 })     // only tiny saccades
        #expect(frames.contains { $0.isBlinking })                // at least one blink in 10 s
    }

    @Test func lidsAreSlightlyAsymmetric() {
        var m = AliveEyesModel(seed: 5)
        #expect(m.frame.leftLid != m.frame.rightLid)
        m.blinkNow()
        m.step(dt: 0.06)
        #expect(m.frame.rightLid < m.frame.leftLid)              // right trails by 12 ms
        _ = trace(&m, seconds: 0.3)
        #expect(m.frame.leftLid == AliveEyesModel.restingLid.left)
    }

    @Test func blinkFullyClosesBothLids() {
        var m = AliveEyesModel(seed: 5)
        m.blinkNow()
        var maxL = 0.0, maxR = 0.0
        for _ in 0..<60 { m.step(dt: 1.0 / 240); maxL = max(maxL, m.frame.leftLid); maxR = max(maxR, m.frame.rightLid) }
        #expect(maxL > 0.99 && maxR > 0.99)
    }

    @Test func squintLowersLidsAndFades() {
        var m = AliveEyesModel(seed: 5)
        m.feedAcceleration(x: 0, y: 2, z: 0)
        m.step(dt: 1.0 / 60)
        #expect(m.frame.squint == 1)
        #expect(abs(m.frame.leftLid - (0.07 + 0.42)) < 1e-9 || m.frame.isBlinking)
        _ = trace(&m, seconds: 4)
        #expect(m.frame.squint == 0)
    }

    @Test func reduceMotionStopsSaccadesAndDoubles() {
        var m = AliveEyesModel(seed: 5, reduceMotion: true)
        let frames = trace(&m, seconds: 120)
        #expect(frames.allSatisfy { $0.gaze == .zero })
        #expect(m.blinks.doubleCount == 0 && m.blinks.blinkCount > 10 && m.blinks.speed == 0.5)
        m.reduceMotion = false
        #expect(m.saccades.isEnabled && m.blinks.speed == 1)
    }

    @Test func followsAFingerToTheTopRightThenDriftsHome() {
        var m = AliveEyesModel(seed: 5)
        m.setFinger(Vec2(0.75, -0.6))
        _ = trace(&m, seconds: 0.5)
        #expect(m.frame.gaze.x > 0.65 && m.frame.gaze.y < -0.5)
        m.setFinger(nil)
        _ = trace(&m, seconds: 4)
        #expect(m.frame.gaze.length < 0.08)
    }

    @Test func invalidAndHugeStepsAreSafe() {
        var m = AliveEyesModel(seed: 5)
        let before = m
        m.step(dt: 0); m.step(dt: -1); m.step(dt: .infinity); m.step(dt: .nan)
        #expect(m == before)
        m.step(dt: 30)
        #expect(abs(m.time - AliveEyesModel.maxFrameDelta) < 1e-9)
    }
}
