import Testing
import Foundation
@testable import HoldToFanCore

@Suite("State machine") struct StateTests {
    @Test func startsIdle() {
        let m = HoldToFanModel()
        #expect(m.phase == .idle && m.open == 0 && m.highlighted == nil)
        #expect(m.count == 4 && !m.isExpanded)
    }

    @Test func shortPressPulsesAndStaysClosed() {
        var m = HoldToFanModel()
        _ = m.pressBegan()
        m.run(0.1)
        #expect(m.phase == .arming && m.armProgress > 0 && m.armProgress < 1)
        let ev = m.pressEnded()
        #expect(ev == [.pulsed])
        #expect(m.phase == .idle && m.open == 0 && m.pulses == 1)
    }

    @Test func holdPastThresholdArmsAndOpens() {
        var m = HoldToFanModel()
        let ev = m.armAndOpen()
        #expect(ev.contains(.armed))
        #expect(ev.contains(.opened))
        #expect(m.phase == .open && m.open == 1)
        #expect(m.arms == 1 && m.opens == 1)
    }

    @Test func armThresholdIsAboutTwoTenths() {
        var m = HoldToFanModel()
        _ = m.pressBegan()
        m.run(0.19)
        #expect(m.phase == .arming)
        let ev = m.run(0.02)
        #expect(ev.contains(.armed))
        #expect(m.phase == .opening || m.phase == .open)
    }

    @Test func liftOverTabSelectsAndSeats() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        let target = HoldToFanLayout.openPosition(of: 1, count: 4)
        m.pressMoved(to: target)
        #expect(m.highlighted == 1)
        var ev = m.pressEnded()
        #expect(ev == [.selected(1)])
        #expect(m.phase == .closing && m.lastSelected == 1)
        ev = m.run(1.5)
        #expect(ev.contains(.seated))
        #expect(m.phase == .idle && m.open == 0 && m.seats == 1 && m.selects == 1)
    }

    @Test func liftWithNoTabCancels() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        // Finger still on the FAB: too close to aim.
        m.pressMoved(to: HoldToFanLayout.fab)
        #expect(m.highlighted == nil)
        var ev = m.pressEnded()
        #expect(ev == [.cancelled])
        ev = m.run(1.5)
        #expect(ev.contains(.seated) && m.cancels == 1 && m.selects == 0)
    }

    @Test func dragFarOffArcClearsHighlightAndCancels() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        m.pressMoved(to: HoldToFanLayout.openPosition(of: 2, count: 4))
        #expect(m.highlighted == 2)
        m.pressMoved(to: Vec2(10, 10))
        #expect(m.highlighted == nil)
        #expect(m.pressEnded() == [.cancelled])
    }

    @Test func cancelWhileArmingPulses() {
        var m = HoldToFanModel()
        _ = m.pressBegan(); m.run(0.05)
        #expect(m.cancel() == [.pulsed])
        #expect(m.phase == .idle)
    }

    @Test func cancelWhileOpenCloses() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        #expect(m.cancel() == [.cancelled])
        m.run(1.5)
        #expect(m.phase == .idle && m.seats == 1)
    }

    @Test func selectingEachTabWorks() {
        for i in 0..<4 {
            var m = HoldToFanModel()
            _ = m.armAndOpen()
            m.pressMoved(to: HoldToFanLayout.openPosition(of: i, count: 4))
            #expect(m.highlighted == i)
            #expect(m.pressEnded() == [.selected(i)])
        }
    }

    @Test func openIsMonotoneUpThenDown() {
        var m = HoldToFanModel()
        _ = m.pressBegan()
        var last = 0.0
        // Through arm + open.
        var sawOpen = false
        for _ in 0..<90 {
            _ = m.step(1.0 / 60)
            if m.phase == .opening || m.phase == .open {
                sawOpen = true
                #expect(m.open + 0.05 >= last) // underdamped spring may dip a hair
                last = max(last, m.open)
            }
        }
        #expect(sawOpen && m.phase == .open && m.open == 1)
        m.pressMoved(to: HoldToFanLayout.fab)
        _ = m.pressEnded()
        last = m.open
        for _ in 0..<90 {
            _ = m.step(1.0 / 60)
            #expect(m.open <= last + 0.05); last = min(last, m.open)
        }
        #expect(m.phase == .idle && m.open == 0)
    }

    @Test func pressDuringCloseRestartsArming() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        _ = m.pressEnded()   // cancel
        #expect(m.phase == .closing)
        _ = m.pressBegan()
        #expect(m.phase == .arming)
    }

    @Test func nonFiniteInputIgnored() {
        var m = HoldToFanModel()
        #expect(m.pressBegan(at: Vec2(.nan, 0)).isEmpty)
        _ = m.pressBegan()
        m.pressMoved(to: Vec2(.infinity, 1))
        #expect(m.finger?.x.isFinite == true)
    }
}

@Suite("Tabs & hit test") struct TabTests {
    @Test func tabsStaggerOut() {
        var m = HoldToFanModel()
        _ = m.pressBegan(); m.run(0.25)   // armed, early opening
        #expect(m.phase == .opening || m.phase == .open)
        let p = (0..<4).map { m.tabProgress($0) }
        // Lead tab ahead of the last one while opening.
        if m.phase == .opening {
            #expect(p[0] >= p[1] - 1e-9)
            #expect(p[1] >= p[2] - 1e-9)
            #expect(p[2] >= p[3] - 1e-9)
            #expect(p[0] > p[3])
        }
    }

    @Test func tabsReachTheArcWhenOpen() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        for i in 0..<4 {
            #expect(abs(m.tabProgress(i) - 1) < 1e-9)
            #expect(abs(HoldToFanLayout.distance(of: m.tabPosition(i)) - HoldToFanLayout.arcRadius) < 0.5)
        }
    }

    @Test func highlightedScalesUp() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        let base = m.tabScale(1)
        m.pressMoved(to: HoldToFanLayout.openPosition(of: 1, count: 4))
        #expect(m.tabScale(1) > base)
        #expect(m.tabScale(0) == base)
    }

    @Test func nearestPrefersClosestAngle() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        let angs = HoldToFanLayout.angles(count: 4)
        // A point on the arc between tab 0 and 1, closer to 0.
        let θ = angs[0] + HoldToFanLayout.angleDelta(angs[1], angs[0]) * 0.25
        let p = HoldToFanLayout.fab + Vec2.unit(θ) * HoldToFanLayout.arcRadius
        #expect(m.nearestTab(at: p) == 0)
    }

    @Test func nearestNilWhenTooCloseOrFar() {
        let m = HoldToFanModel()
        #expect(m.nearestTab(at: HoldToFanLayout.fab) == nil)
        #expect(m.nearestTab(at: HoldToFanLayout.fab + Vec2(0, -10)) == nil)
        #expect(m.nearestTab(at: HoldToFanLayout.fab + Vec2(0, -400)) == nil)
    }

    @Test func nearestNilWhenOffAngularWindow() {
        let m = HoldToFanModel()
        // Straight down from the FAB: outside the upper-left quarter.
        let p = HoldToFanLayout.fab + Vec2(0, HoldToFanLayout.arcRadius)
        #expect(m.nearestTab(at: p) == nil)
    }

    @Test(arguments: [3, 5])
    func worksForExtremeCounts(_ n: Int) {
        var m = HoldToFanModel(count: n)
        _ = m.armAndOpen()
        #expect(m.count == n)
        m.pressMoved(to: HoldToFanLayout.openPosition(of: n - 1, count: n))
        #expect(m.highlighted == n - 1)
        #expect(m.pressEnded() == [.selected(n - 1)])
    }
}

@Suite("Reduce Motion") struct ReduceTests {
    @Test func snapsOpenAndClosed() {
        var m = HoldToFanModel(reduceMotion: true)
        _ = m.pressBegan()
        var ev = m.run(0.21)
        #expect(ev.contains(.armed) && ev.contains(.opened))
        #expect(m.phase == .open && m.open == 1)
        // No stagger: every tab is fully out at once.
        #expect((0..<4).allSatisfy { m.tabProgress($0) == 1 })
        m.pressMoved(to: HoldToFanLayout.openPosition(of: 0, count: 4))
        ev = m.pressEnded()
        #expect(ev == [.selected(0)])
        ev = m.run(0.05)
        #expect(ev.contains(.seated))
        #expect(m.phase == .idle && m.open == 0)
    }

    @Test func togglingReduceMotionJumpsTransitions() {
        var m = HoldToFanModel()
        _ = m.pressBegan(); m.run(0.25)
        #expect(m.phase == .opening || m.phase == .open)
        m.setReduceMotion(true)
        #expect(m.phase == .open && m.open == 1)
        _ = m.pressEnded()
        m.setReduceMotion(true) // no-op
        m.run(0.02)
        // Still closing or seated; force snap by re-toggling off/on mid-close.
        if m.phase == .closing {
            m.setReduceMotion(false); m.setReduceMotion(true)
            // value snaps but finishClose needs a step
            let ev = m.step(1.0 / 60)
            #expect(ev.contains(.seated) || m.open == 0)
        }
    }
}

@Suite("Determinism & stepping") struct StepTests {
    @Test func deterministicReplay() {
        func session() -> HoldToFanModel {
            var m = HoldToFanModel(count: 4)
            _ = m.pressBegan(); m.run(0.5)
            m.pressMoved(to: HoldToFanLayout.openPosition(of: 2, count: 4))
            m.run(0.2)
            _ = m.pressEnded(); m.run(1.0)
            return m
        }
        #expect(session() == session())
    }

    @Test func badStepsAreHarmless() {
        var m = HoldToFanModel()
        _ = m.armAndOpen()
        let t = m.time
        _ = m.step(.nan); _ = m.step(-1); _ = m.step(.infinity)
        #expect(m.time <= t + HoldToFanModel.maxStep + 1e-9)
        #expect(m.phase == .open)
    }

    @Test func frameRateIndependentOpen() {
        var a = HoldToFanModel(), b = HoldToFanModel()
        _ = a.pressBegan(); _ = b.pressBegan()
        for _ in 0..<60 { _ = a.step(1.0 / 60) }
        for _ in 0..<30 { _ = b.step(1.0 / 30) }
        #expect(abs(a.open - b.open) < 1e-6)
        #expect(a.phase == b.phase)
    }
}
