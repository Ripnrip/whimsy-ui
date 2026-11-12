import Testing
import Foundation
@testable import RubberBandCore

@discardableResult
private func run(_ m: inout RubberBandModel, _ seconds: Double, step: Double = 1.0 / 60) -> [RubberBandEvent] {
    var events: [RubberBandEvent] = []
    var left = seconds
    while left > 1e-12 {
        let d = min(step, left)
        events += m.step(d)
        left -= d
    }
    return events
}

private func center(_ i: Int) -> Vec2 { RubberBandLayout.restCenter(i) }

/// Press on card `i`, wait for the hover lift, then pull up by `points` and optionally release.
@discardableResult
private func pull(_ m: inout RubberBandModel, _ i: Int, _ points: Double, release: Bool = true, at t0: Double = 1) -> [RubberBandEvent] {
    var events: [RubberBandEvent] = []
    let p = center(i)
    events += m.pointerDown(at: p, at: t0)
    events += run(&m, 0.45)
    let moved = Vec2(p.x, p.y - points)
    events += m.pointerMoved(to: moved, at: t0 + 0.6)
    if release { events += m.pointerUp(at: moved, at: t0 + 0.6) }
    return events
}

@Suite("Hover") struct HoverTests {
    @Test func slidingLiftsTheNearestCardByAboutTwentyPoints() {
        var m = RubberBandModel()
        let ev = m.pointerDown(at: center(1), at: 0)
        #expect(ev == [.lifted(1)])
        #expect(m.phase == .browsing && m.focusIndex == 1)
        run(&m, 0.5)
        #expect(abs(m.pose(1).lift - RubberBandLayout.hoverLift) < 0.05)
        #expect(m.pose(1).center.y < RubberBandLayout.restCenter(1).y - 19)
        #expect(m.pose(0).lift < 0.5 && m.pose(2).lift < 0.5)
    }

    @Test func reduceMotionSnapsTheLift() {
        var m = RubberBandModel(reduceMotion: true)
        _ = m.pointerDown(at: center(3), at: 0)
        #expect(m.pose(3).lift == RubberBandLayout.hoverLift)
        #expect(m.pose(3).scale > 1)
    }

    @Test func eachNewlyLiftedCardFiresOnce() {
        var m = RubberBandModel()
        var events: [RubberBandEvent] = []
        events += m.pointerDown(at: center(0), at: 0)
        // Jiggle on the same card: no second haptic.
        let j = center(0)
        events += m.pointerMoved(to: Vec2(j.x + 4, j.y), at: 0.05)
        events += m.pointerMoved(to: Vec2(j.x - 3, j.y + 2), at: 0.08)
        for i in 1..<5 {
            events += m.pointerMoved(to: center(i), at: 0.1 + Double(i) * 0.05)
        }
        let lifts = events.compactMap { if case .lifted(let i) = $0 { return i }; return nil }
        #expect(lifts == [0, 1, 2, 3, 4])
        #expect(m.liftEvents == 5)
    }

    @Test func leavingTheHandDropsTheLiftWithoutAnotherEvent() {
        var m = RubberBandModel()
        _ = m.pointerDown(at: center(2), at: 0)
        let ev = m.pointerUp(at: Vec2(195, 30), at: 0.2)
        #expect(ev.isEmpty)
        #expect(m.focusIndex == nil && m.phase == .resting)
        run(&m, 0.6)
        #expect(m.pose(2).lift < 0.05)
    }

    @Test func nonFinitePointsAreIgnored() {
        var m = RubberBandModel()
        #expect(m.pointerDown(at: Vec2(.nan, 1), at: 0).isEmpty)
        #expect(m.phase == .resting)
        _ = m.pointerDown(at: center(2), at: 0)
        #expect(m.pointerMoved(to: Vec2(.infinity, 10), at: 0.1).isEmpty)
        #expect(m.focusIndex == 2)
        #expect(m.step(.nan).isEmpty)
        #expect(m.step(-1).isEmpty)
    }
}

@Suite("Drag, commit, return") struct DragTests {
    @Test func anEarlyReleaseSpringsBackToTheSlot() {
        var m = RubberBandModel()
        let ev = pull(&m, 2, 36)
        #expect(!ev.contains(.committed(2)))
        #expect(m.lastRelease == .springBack)
        #expect(m.phase == .returning)
        let done = run(&m, 1.2)
        #expect(done.contains(.restored(2)))
        #expect(m.phase == .resting && m.activeIndex == nil)
        let back = m.pose(2)
        #expect(abs(back.center.x - center(2).x) < 1e-9)
        #expect(abs(back.center.y - center(2).y) < 1e-9)
        #expect(back.flip == 0)
        #expect(abs(back.rotation - RubberBandLayout.restRotation(2)) < 1e-9)
    }

    @Test func pullingPastTheRiseArmsAndPresents() {
        var m = RubberBandModel()
        var ev = pull(&m, 4, 180, release: false)
        #expect(ev.contains(.grabbed(4)))
        #expect(ev.contains(.armed(4)))
        #expect(m.isArmed)
        #expect(m.pose(4).lift > RubberBandLayout.hoverLift + RubberBandLayout.commitRise - 1)
        // Overpull: the card rises less than the finger travelled.
        #expect(m.pose(4).lift < 180)
        #expect(m.pose(4).lift < RubberBandLayout.hoverLift + RubberBandResistance.asymptote)
        let up = m.pointerUp(at: Vec2(center(4).x, center(4).y - 180), at: 2)
        ev += up
        #expect(up == [.committed(4)])
        #expect(m.lastRelease == .commitDrag)
        let done = run(&m, 1.2)
        #expect(done.contains(.presented(4)))
        #expect(m.phase == .presented)
        let shown = m.pose(4)
        #expect(shown.center == RubberBandLayout.stage)
        #expect(shown.flip == 1)
        #expect(abs(shown.rotation) < 1e-12)
        #expect(abs(shown.scale - RubberBandLayout.presentedScale) < 1e-12)
        #expect(m.pose(1).opacity < 0.8)
        #expect(m.drawOrder.last == 4)
    }

    @Test func aFastFlickCommitsBelowTheRise() {
        var m = RubberBandModel()
        let p = center(1)
        _ = m.pointerDown(at: p, at: 0)
        let tip = Vec2(p.x, p.y - 40)
        _ = m.pointerMoved(to: tip, at: 0.03)
        #expect(RubberBandResistance.resist(40) < RubberBandLayout.commitRise)
        let ev = m.pointerUp(at: tip, at: 0.03)
        #expect(ev == [.committed(1)])
        #expect(m.lastRelease == .commitFlick)
        #expect(m.phase == .presenting)
    }

    @Test func aSlowShortPullDoesNotFlick() {
        var m = RubberBandModel()
        let p = center(1)
        _ = m.pointerDown(at: p, at: 0)
        let tip = Vec2(p.x, p.y - 40)
        _ = m.pointerMoved(to: tip, at: 0.03)
        _ = m.pointerMoved(to: tip, at: 0.25)
        let ev = m.pointerUp(at: tip, at: 0.25)
        #expect(!ev.contains(where: { if case .committed = $0 { return true }; return false }))
        #expect(m.phase == .returning)
    }

    @Test func armingTicksOnceUntilTheFingerDropsBack() {
        var m = RubberBandModel()
        let p = center(2)
        _ = m.pointerDown(at: p, at: 0)
        run(&m, 0.3)
        func move(_ up: Double, _ t: Double) -> [RubberBandEvent] {
            m.pointerMoved(to: Vec2(p.x, p.y - up), at: t)
        }
        let first = move(180, 0.4)
        #expect(first.contains(.armed(2)))
        let held = move(220, 0.5)
        #expect(!held.contains(.armed(2)))
        let dropped = move(30, 0.7)
        #expect(!dropped.contains(.armed(2)) && !m.isArmed)
        let again = move(180, 0.9)
        #expect(again.contains(.armed(2)) && m.isArmed)
    }

    @Test func sidewaysSlidingDoesNotGrab() {
        var m = RubberBandModel()
        _ = m.pointerDown(at: center(0), at: 0)
        let ev = m.pointerMoved(to: center(4), at: 0.2)
        #expect(m.phase == .browsing && m.focusIndex == 4)
        #expect(!ev.contains(.grabbed(4)))
    }

    @Test func cancelReturnsTheCard() {
        var m = RubberBandModel()
        _ = pull(&m, 2, 40, release: false)
        #expect(m.phase == .dragging)
        #expect(m.pointerCancel().isEmpty || m.phase == .returning)
        #expect(m.phase == .returning)
        let ev = run(&m, 1.2)
        #expect(ev.contains(.restored(2)) && m.phase == .resting)
    }
}

@Suite("Detail and dismiss") struct DismissTests {
    private func present(_ i: Int = 2) -> RubberBandModel {
        var m = RubberBandModel()
        _ = pull(&m, i, 180)
        _ = run(&m, 1.2)
        #expect(m.phase == .presented)
        return m
    }

    @Test func dismissSpringsTheCardHome() {
        var m = present()
        let ev = m.dismiss()
        #expect(ev == [.dismissed(2)])
        #expect(m.phase == .returning)
        let done = run(&m, 1.2)
        #expect(done == [.restored(2)] || done.contains(.restored(2)))
        #expect(m.phase == .resting)
        #expect(abs(m.pose(2).center.x - center(2).x) < 1e-6)
        #expect(m.pose(2).flip == 0)
    }

    @Test func aTapOutsideDismissesAndATapOnTheCardDoesNot() {
        var m = present(0)
        let stage = RubberBandLayout.stage
        _ = m.pointerDown(at: stage, at: 5)
        #expect(m.pointerUp(at: stage, at: 5.05).isEmpty)
        #expect(m.phase == .presented)
        let outside = Vec2(16, 24)
        _ = m.pointerDown(at: outside, at: 6)
        let ev = m.pointerUp(at: outside, at: 6.02)
        #expect(ev == [.dismissed(0)])
        #expect(m.phase == .returning)
    }

    @Test func aShortPullDownReboundsAndALongOneReturns() {
        var m = present(3)
        let stage = RubberBandLayout.stage
        _ = m.pointerDown(at: stage, at: 5)
        let nudge = Vec2(stage.x, stage.y + 30)
        _ = m.pointerMoved(to: nudge, at: 5.1)
        #expect(m.phase == .dismissing)
        #expect(m.pose(3).center.y > stage.y)
        #expect(m.pose(3).center.y - stage.y < 30)
        _ = m.pointerUp(at: nudge, at: 5.4)
        #expect(m.phase == .presenting)
        _ = run(&m, 1.2)
        #expect(m.phase == .presented && m.presentations == 1)
        #expect(m.pose(3).center == stage)

        _ = m.pointerDown(at: stage, at: 8)
        let far = Vec2(stage.x, stage.y + 160)
        _ = m.pointerMoved(to: far, at: 8.2)
        let ev = m.pointerUp(at: far, at: 8.5)
        #expect(ev.contains(.dismissed(3)))
        _ = run(&m, 1.2)
        #expect(m.phase == .resting && m.restores == 1)
    }

    @Test func voiceOverOpensAndEscapeCloses() {
        var m = RubberBandModel()
        #expect(m.activate(9).isEmpty)
        #expect(m.activate(-1).isEmpty)
        #expect(m.dismiss().isEmpty)
        let ev = m.activate(4)
        #expect(ev == [.committed(4)])
        _ = run(&m, 1.2)
        #expect(m.phase == .presented && m.pose(4).flip == 1)
        // A second activate while open does nothing.
        #expect(m.activate(1).isEmpty)
        _ = m.dismiss()
        _ = run(&m, 1.2)
        #expect(m.phase == .resting && m.activeIndex == nil)
    }

    @Test func reduceMotionSkipsTheFlight() {
        var m = RubberBandModel(reduceMotion: true)
        let ev = m.activate(1)
        #expect(ev == [.committed(1), .presented(1)])
        #expect(m.phase == .presented)
        #expect(m.pose(1).center == RubberBandLayout.stage && m.pose(1).flip == 1)
        let back = m.dismiss()
        #expect(back.contains(.dismissed(1)) && back.contains(.restored(1)))
        #expect(m.phase == .resting)
        #expect(m.pose(1).center == center(1) && m.pose(1).flip == 0)
    }

    @Test func turningReduceMotionOnMidFlightSnaps() {
        var m = RubberBandModel()
        _ = m.activate(2)
        _ = m.step(0.05)
        #expect(m.phase == .presenting)
        let ev = m.setReduceMotion(true)
        #expect(ev.contains(.presented(2)))
        #expect(m.phase == .presented && m.pose(2).flip == 1)
        // Flight again with motion on, then snap the return.
        _ = m.setReduceMotion(false)
        _ = m.dismiss()
        #expect(m.phase == .returning)
        _ = m.step(0.05)
        let snapped = m.setReduceMotion(true)
        #expect(snapped.contains(.restored(2)) && m.phase == .resting)
    }
}

@Suite("Catalog") struct CatalogTests {
    @Test func fiveDistinctDesigns() {
        let cards = RubberBandCatalog.cards
        #expect(cards.count == 5)
        #expect(Set(cards.map(\.title)).count == 5)
        #expect(Set(cards.map(\.kicker)).count == 5)
        let papers = Set(cards.map { "\($0.paper.r),\($0.paper.g),\($0.paper.b)" })
        #expect(papers.count == 5)
        for (i, card) in cards.enumerated() {
            #expect(card.index == i)
            #expect(!card.detail.isEmpty && !card.marks.isEmpty)
        }
    }

    @Test func marksStayAboveTheTitle() {
        for card in RubberBandCatalog.cards {
            for mark in card.marks {
                let (cx, cy, halfW, halfH) = markCenter(mark)
                #expect(cx - halfW > -0.02 && cx + halfW < 1.02, "\(card.title) spills sideways")
                #expect(cy - halfH > -0.02 && cy + halfH < 0.70, "\(card.title) covers the title")
            }
        }
    }

    /// Unrotated half-extents. Capsules are thin, so rotation can't throw them onto the title band.
    private func markCenter(_ mark: RubberBandMark) -> (Double, Double, Double, Double) {
        switch mark {
        case let .ellipse(cx, cy, rx, ry, _, _):
            return (cx, cy, rx, ry)
        case let .roundRect(cx, cy, width, height, _, _, _):
            return (cx, cy, width / 2, height / 2)
        case let .capsule(cx, cy, width, height, _, _, _):
            return (cx, cy, width / 2, height / 2)
        }
    }
}
