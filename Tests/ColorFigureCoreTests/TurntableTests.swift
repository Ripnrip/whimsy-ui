import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct TurntableTests {
    @Test func dragMovesTheYawByPointsTimesRate() {
        var t = Turntable()
        let start = t.yaw
        t.beginDrag()
        t.drag(by: 50, dt: 0.016)
        #expect(abs(t.yaw - (start + 50 * Turntable.degreesPerPoint)) < 1e-9)
    }

    @Test func aDragOf600PointsTurnsTheFigureAllTheWayRound() {
        var t = Turntable()
        t.beginDrag()
        for _ in 0..<60 { t.drag(by: 10, dt: 0.016) }
        #expect(abs(t.turns - 360) < 1e-6)
        let yaw = t.yaw
        #expect(abs(yaw - (Turntable.homeYaw + 360)) < 1e-6)
    }

    @Test func letGoAtSpeedItKeepsCoasting() {
        var t = Turntable()
        t.beginDrag()
        for _ in 0..<10 { t.drag(by: 12, dt: 0.016) }
        t.endDrag()
        #expect(t.velocity > 100)
        let y0 = t.yaw
        for _ in 0..<30 { t.advance(by: 1 / 60) }
        #expect(t.yaw > y0 + 30)
    }

    @Test func inertiaDecaysAndStops() {
        var t = Turntable()
        t.fling(400)
        var last = t.velocity
        for _ in 0..<600 {
            t.advance(by: 1 / 60)
            #expect(t.velocity <= last + 1e-9)
            last = t.velocity
        }
        #expect(t.velocity == 0)
    }

    @Test func totalThrowIsAboutSpeedOverFriction() {
        var t = Turntable(yaw: Turntable.homeYaw + 45)
        t.fling(300)
        let y0 = t.yaw
        for _ in 0..<1200 { t.advance(by: 1 / 120) }
        let travel = t.yaw - y0
        // Free coast v/k = 115 degrees, then it settles onto a quarter-turn.
        #expect(travel > 90 && travel < 150)
    }

    @Test func settlesGentlyOntoTheNearestRestYaw() {
        var t = Turntable(yaw: Turntable.homeYaw + 8)
        for _ in 0..<300 { t.advance(by: 1 / 60) }
        #expect(t.yaw == Turntable.homeYaw)
        var u = Turntable(yaw: Turntable.homeYaw + 100)
        for _ in 0..<300 { u.advance(by: 1 / 60) }
        #expect(u.yaw == Turntable.homeYaw + 90)
    }

    @Test func doesNotSnapWhenFarFromARestYaw() {
        var t = Turntable(yaw: Turntable.homeYaw + 45)
        for _ in 0..<300 { t.advance(by: 1 / 60) }
        #expect(t.yaw == Turntable.homeYaw + 45)
    }

    @Test func snapIsGentleNotAJump() {
        var t = Turntable(yaw: Turntable.homeYaw + 10)
        t.advance(by: 1 / 60)
        #expect(t.yaw < Turntable.homeYaw + 10 && t.yaw > Turntable.homeYaw + 8)
    }

    @Test func nothingMovesWhileHeld() {
        var t = Turntable()
        t.fling(300)
        t.beginDrag()
        let y = t.yaw
        t.advance(by: 0.5)
        #expect(t.yaw == y && t.velocity == 0)
    }

    @Test func reduceMotionHasNoInertiaAndNoSnap() {
        var t = Turntable(yaw: Turntable.homeYaw + 8)
        t.reduceMotion = true
        t.beginDrag()
        for _ in 0..<5 { t.drag(by: 20, dt: 0.016) }
        t.endDrag()
        #expect(t.velocity == 0)
        let y = t.yaw
        t.advance(by: 1)
        #expect(t.yaw == y)
        t.fling(500)
        #expect(t.velocity == 0)
    }

    @Test func yawNormalisesForDisplay() {
        #expect(abs(Turntable(yaw: -32).normalizedYaw - 328) < 1e-9)
        #expect(abs(Turntable(yaw: 400).normalizedYaw - 40) < 1e-9)
    }

    @Test func restYawsAreQuarterTurnsFromHome() {
        #expect(Turntable.nearestRest(to: Turntable.homeYaw + 44) == Turntable.homeYaw)
        #expect(Turntable.nearestRest(to: Turntable.homeYaw + 46) == Turntable.homeYaw + 90)
        #expect(Turntable.nearestRest(to: Turntable.homeYaw - 140) == Turntable.homeYaw - 180)
    }

    @Test func flingIsCapped() {
        var t = Turntable()
        t.fling(99999)
        #expect(t.velocity == Turntable.maxSpeed)
    }
}
