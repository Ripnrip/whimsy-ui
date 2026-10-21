import Foundation
import Testing
@testable import SweaterRailCore

private func run(_ m: inout SweaterRailModel, _ seconds: Double, _ each: (SweaterRailModel) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * 60).rounded()) { m.step(1.0 / 60); each(m) }
}

@Suite("Dock falloff and layout")
struct RailLayoutTests {
    let f = DockFalloff(radius: 150, maxScale: 1.55)

    @Test func falloffPeaksUnderFingerAndVanishesAtRadius() {
        #expect(f.weight(distance: 0) == 1)
        #expect(f.scale(distance: 0) == 1.55)
        #expect(abs(f.weight(distance: 75) - 0.5) < 1e-12)
        #expect(f.weight(distance: 150) < 1e-12 && f.weight(distance: 400) < 1e-12)
        #expect(f.weight(distance: -40) == f.weight(distance: 40))
        #expect(f.weight(distance: .nan) == 0)
        var last = 2.0
        for d in stride(from: 0.0, through: 150, by: 5) { let w = f.weight(distance: d); #expect(w <= last); last = w }
    }

    @Test func noFingerGivesAnEvenCentredRow() {
        let l = RailLayout(count: 5, slotWidth: 58, railCenter: 200)
        let s = l.slots(fingerX: nil)
        #expect(s.map(\.centerX) == [84, 142, 200, 258, 316])
        #expect(s.allSatisfy { $0.scale == 1 && $0.emphasis == 0 })
        #expect(l.hoveredIndex(fingerX: nil) == nil)
    }

    @Test func spreadPushesNeighboursAwayAndKeepsOrderWithoutOverlap() {
        let l = RailLayout(count: 5, slotWidth: 58, railCenter: 200)
        let base = l.baseCenters
        let s = l.slots(fingerX: 200)
        #expect(abs(s[2].centerX - 200) < 1e-9)           // the hovered one stays under the finger
        #expect(s[1].centerX < base[1] && s[0].centerX < base[0])
        #expect(s[3].centerX > base[3] && s[4].centerX > base[4])
        #expect(s[2].scale == 1.5)
        for i in 1..<5 {
            let gap = (s[i].centerX - s[i - 1].centerX) - 29 * (s[i].scale + s[i - 1].scale)
            #expect(abs(gap) < 1e-9)                       // edge to edge, no overlap
        }
    }

    @Test func pointUnderFingerIsAnchored() {
        let l = RailLayout(count: 5, slotWidth: 58, railCenter: 200)
        for fx in stride(from: 60.0, through: 340, by: 7) {
            let s = l.slots(fingerX: fx)
            let left = s[0].centerX - 29 * s[0].scale, right = s[4].centerX + 29 * s[4].scale
            let u = (fx - 55) / 290
            #expect(abs(left + u * (right - left) - fx) < 1e-9)
        }
        // Off the left end the row grows rightwards from its fixed left edge.
        let s = l.slots(fingerX: 20)
        #expect(abs((s[0].centerX - 29 * s[0].scale) - 55) < 1e-9)
    }

    @Test func hoveredIndexIsTheNearestAffectedItem() {
        let l = RailLayout(count: 5, slotWidth: 58, railCenter: 200)
        #expect(l.hoveredIndex(fingerX: 145) == 1)
        #expect(l.hoveredIndex(fingerX: 228) == 2)
        #expect(l.hoveredIndex(fingerX: 316) == 4)
        #expect(l.hoveredIndex(fingerX: 316 + 80) == nil)  // beyond half the radius
        #expect(RailLayout(count: 0).hoveredIndex(fingerX: 0) == nil)
        #expect(RailLayout(count: 0).slots(fingerX: 0).isEmpty)
    }
}

@Suite("Pendulum")
struct PendulumTests {
    @Test func smallAnglePeriodMatchesTheory() {
        var p = Pendulum(angle: 0.05, length: 110, gravity: 5_000, damping: 0)
        #expect(abs(p.smallAnglePeriod - 0.9318) < 1e-3)
        // Time two successive downward zero crossings.
        var crossings: [Double] = [], t = 0.0, prev = p.angle
        while crossings.count < 2 && t < 5 {
            p.step(dt: 1.0 / 240); t += 1.0 / 240
            if prev > 0 && p.angle <= 0 { crossings.append(t) }
            prev = p.angle
        }
        #expect(abs((crossings[1] - crossings[0]) - p.smallAnglePeriod) < 0.01)
    }

    @Test func dampingBringsItToRest() {
        var p = Pendulum(angle: 0.3)
        var peaks: [Double] = []
        var lastV = 0.0
        for _ in 0..<(240 * 5) {
            p.step(dt: 1.0 / 240)
            if lastV > 0 && p.angularVelocity <= 0 { peaks.append(p.angle) }
            lastV = p.angularVelocity
        }
        #expect(peaks.count >= 2 && peaks[1] < peaks[0])
        #expect(p.isAtRest)
    }

    @Test func shovingThePivotRightSwingsTheHemLeft() {
        var p = Pendulum()
        p.step(pivotAcceleration: 3_000, dt: 0.05)
        #expect(p.angle < 0)
        var q = Pendulum()
        q.step(pivotAcceleration: -3_000, dt: 0.05)
        #expect(q.angle > 0)
    }

    @Test func swingIsLimitedAndBadInputIgnored() {
        var p = Pendulum(maxAngle: 0.45)
        for _ in 0..<60 { p.step(pivotAcceleration: -1e6, dt: 1.0 / 60) }
        #expect(p.angle <= 0.45)
        let before = p
        p.step(pivotAcceleration: .nan, dt: 1 / 60); p.step(dt: .nan); p.step(dt: -1)
        #expect(p == before)
    }
}

@Suite("Rail model")
struct RailModelTests {
    @Test func startsAtRestAndSettlesToTheSpreadLayout() {
        var m = SweaterRailModel(count: 5, railCenter: 200)
        #expect(m.isSettled && m.hoveredIndex == nil)
        m.setFinger(258)
        #expect(m.hoveredIndex == 3)
        run(&m, 6)
        #expect(m.isSettled)
        let t = m.targets
        for i in 0..<5 { #expect(abs(m.pose(i).x - t[i].centerX) < 0.05) }
        #expect(abs(m.pose(3).scale - 1.5) < 1e-3 && m.pose(3).emphasis > 0.99)
    }

    @Test func spreadingKicksNeighboursIntoASwing() {
        var m = SweaterRailModel(count: 5, railCenter: 200)
        m.setFinger(200)
        var maxLeft = 0.0, maxRight = 0.0
        run(&m, 0.5) { m in maxLeft = max(maxLeft, abs(m.pose(0).swingDegrees)); maxRight = max(maxRight, abs(m.pose(4).swingDegrees)) }
        #expect(maxLeft > 1 && maxRight > 1)
        // Pushed left, the leftmost hook accelerates left first, so its hem lags to the right.
        var n = SweaterRailModel(count: 5, railCenter: 200)
        n.setFinger(200); n.step(1.0 / 60)
        #expect(n.pose(0).swingDegrees > 0 && n.pose(4).swingDegrees < 0)
    }

    @Test func reduceMotionDisablesSwingAndOvershoot() {
        var m = SweaterRailModel(count: 5, railCenter: 200)
        m.reduceMotion = true
        m.setFinger(200)
        let target = m.targets[0].centerX
        var overshoot = false
        run(&m, 2) { m in
            if m.pose(0).swingDegrees != 0 { overshoot = true }
            if m.pose(0).x < target - 1e-6 { overshoot = true }
        }
        #expect(!overshoot)
    }

    @Test func fingerLeavingReturnsHomeAndNonFiniteIsIgnored() {
        var m = SweaterRailModel(count: 5, railCenter: 200)
        m.setFinger(150); run(&m, 0.4)
        m.setFinger(.nan)
        #expect(m.fingerX == 150)
        m.setFinger(nil); run(&m, 6)
        #expect(m.isSettled)
        #expect(abs(m.pose(0).x - 76) < 0.05 && abs(m.pose(1).scale - 1) < 1e-3)
        m.setRailCenter(300)
        #expect(abs(m.pose(0).x - 176) < 0.05 && m.targets[0].centerX == 176)
    }
}

@Suite("Hero exit and marquee")
struct ExitAndMarqueeTests {
    @Test func othersLeaveAwayFromTheSelection() {
        #expect((0..<5).map { RailExit.direction(index: $0, selected: 2) } == [-1, -1, 0, 1, 1])
        #expect(RailExit.offset(index: 2, selected: 2, width: 393) == 0)
        #expect(RailExit.offset(index: 1, selected: 2, width: 393) < -290)
        #expect(RailExit.offset(index: 4, selected: 2, width: 393) > RailExit.offset(index: 3, selected: 2, width: 393))
        #expect(RailExit.delay(index: 3, selected: 2) == 0 && RailExit.delay(index: 0, selected: 2) == 0.04)
    }

    @Test func marqueeWrapsSeamlessly() {
        let m = Marquee(speed: 40, itemWidth: 200)
        #expect(m.offset(at: 0) == 0)
        #expect(m.offset(at: 1) == -40)
        #expect(m.offset(at: 5) == 0)               // one full copy later: back where it started
        #expect(abs(m.offset(at: 5.5) - -20) < 1e-9)
        for t in stride(from: -3.0, through: 30, by: 0.37) { let o = m.offset(at: t); #expect(o <= 0 && o > -200) }
        #expect(Marquee(itemWidth: 0).offset(at: 3) == 0)
        #expect(Marquee.copiesNeeded(viewport: 393, itemWidth: 200) == 3)
        #expect(Marquee.copiesNeeded(viewport: 400, itemWidth: 200) == 3)
        #expect(Marquee.copiesNeeded(viewport: 100, itemWidth: 0) == 1)
    }
}
