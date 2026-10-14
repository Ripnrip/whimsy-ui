import Testing
import Foundation
@testable import AliveEyesCore

@Suite("Gaze")
struct GazeTests {
    @Test func springUsesArticleDampingFormula() {
        var s = Spring2D()
        s.step(toward: Vec2(1, 0), dt: 0.01, stiffness: 400, damping: 0.5)
        // a = k·Δ − 2√k·ζ·v = 400 at rest → v = 4, x = 0.04
        #expect(abs(s.velocity.x - 4) < 1e-12 && abs(s.position.x - 0.04) < 1e-12)
    }

    @Test func followsFingerQuicklyAndSettles() {
        var g = GazeController()
        g.setTarget(Vec2(0.6, -0.5))
        for _ in 0..<24 { g.step(dt: 1.0 / 240) }               // 0.1 s
        #expect((g.gaze - Vec2(0.6, -0.5)).length < 0.3)
        for _ in 0..<240 { g.step(dt: 1.0 / 240) }
        #expect((g.gaze - Vec2(0.6, -0.5)).length < 1e-3)
    }

    @Test func targetAndOutputStayInsideTheUnitDisc() {
        var g = GazeController()
        g.setTarget(Vec2(30, 40))
        #expect(abs(g.fingerTarget!.length - 1) < 1e-12)
        var maxLength = 0.0
        for _ in 0..<480 { g.step(dt: 1.0 / 240); maxLength = max(maxLength, g.gaze.length) }
        #expect(maxLength <= 1 + 1e-12)
    }

    @Test func driftsBackToCentreSlowlyAfterRelease() {
        var g = GazeController()
        g.setTarget(Vec2(1, 0))
        for _ in 0..<480 { g.step(dt: 1.0 / 240) }
        g.setTarget(nil)
        #expect(!g.isTracking)
        for _ in 0..<24 { g.step(dt: 1.0 / 240) }               // 0.1 s: still mostly there
        #expect(g.gaze.x > 0.6)
        for _ in 0..<720 { g.step(dt: 1.0 / 240) }              // +3 s: home
        #expect(g.gaze.length < 0.01)
    }

    @Test func nudgeShiftsTheTarget() {
        var g = GazeController()
        for _ in 0..<960 { g.step(dt: 1.0 / 240, nudge: Vec2(0.05, -0.04)) }
        #expect((g.gaze - Vec2(0.05, -0.04)).length < 1e-3)
    }

    @Test(arguments: [Vec2(0, 0), Vec2(1, 0), Vec2(-0.7, 0.7), Vec2(5, -9)])
    func irisNeverLeavesTheSclera(gaze: Vec2) {
        let eye = 60.0, iris = 27.0
        let offset = EyeGeometry.irisOffset(gaze: gaze, eyeRadius: eye, irisRadius: iris)
        #expect(offset.length + iris <= eye * 0.94 + 1e-9)
    }

    @Test func fingerMapsRelativeToTheEyes() {
        let c = Vec2(200, 300)
        #expect(EyeGeometry.gazeTarget(finger: c, eyesCenter: c, reach: 100) == .zero)
        #expect(EyeGeometry.gazeTarget(finger: Vec2(250, 300), eyesCenter: c, reach: 100) == Vec2(0.5, 0))
        let far = EyeGeometry.gazeTarget(finger: Vec2(1200, -700), eyesCenter: c, reach: 100)
        #expect(abs(far.length - 1) < 1e-12 && far.x > 0 && far.y < 0)   // top-right
        #expect(EyeGeometry.gazeTarget(finger: Vec2(9, 9), eyesCenter: c, reach: 0) == .zero)
    }
}
