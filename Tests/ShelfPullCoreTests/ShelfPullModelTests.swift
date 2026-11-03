import Testing
import Foundation
@testable import ShelfPullCore

private let dt = 1.0 / 60

/// Runs the model for `seconds`, collecting every event.
@discardableResult
private func run(_ m: inout ShelfPullModel, _ seconds: Double, step: Double = dt) -> [ShelfEvent] {
    var events: [ShelfEvent] = []
    var left = seconds
    while left > 1e-12 { let d = min(step, left); events += m.step(d); left -= d }
    return events
}

/// A slow pull of `drag` points on book `b`, then let go.
@discardableResult
private func pull(_ m: inout ShelfPullModel, _ b: Int, _ drag: Double, hold: Double = 0.2, release: Bool = true) -> [ShelfEvent] {
    var events: [ShelfEvent] = []
    m.pointerDown(book: b)
    for i in 1...10 {
        events += m.pointerMoved(upward: drag * Double(i) / 10, at: m.time)
        events += m.step(hold / 10)
    }
    // a stopped finger: stale velocity
    events += run(&m, 0.1)
    if release { events += m.pointerUp(at: m.time) }
    return events
}

private func open(_ m: inout ShelfPullModel, _ b: Int = 3) {
    pull(&m, b, 140)
    run(&m, 0.45 + 0.5 + 0.01)
}

@Suite struct ShelfPullModelBasics {
    @Test func startsAtRest() {
        let m = ShelfPullModel()
        #expect(m.phase == .resting && m.book == nil && m.seats == 0 && m.opens == 0 && m.commits == 0)
        #expect(m.layout.count == 7 && m.canGrab && !m.canClose && !m.isAnimating)
        #expect(m.frame.phase == .resting)
    }

    @Test func rejectsABadBook() {
        var m = ShelfPullModel()
        let x1 = m.pointerDown(book: -1)
        let x2 = m.pointerDown(book: 7)
        #expect(!x1 && !x2 && m.phase == .resting)
        let x3 = m.activate(book: 9)
        #expect(x3.isEmpty)
    }

    @Test func pointerDownStartsDragging() {
        var m = ShelfPullModel()
        let x4 = m.pointerDown(book: 2)
        #expect(x4)
        #expect(m.phase == .dragging && m.book == 2 && m.drag == 0 && !m.canGrab)
        let x5 = m.pointerDown(book: 4)
        #expect(!x5)
    }

    @Test func pullingMovesTheBookWithResistance() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        m.pointerMoved(upward: 50)
        let h = m.layout.spines[3].height
        #expect(abs(m.frame.spines[3].rise - ShelfResistance.rise(forDrag: 50, height: h)) < 1e-12)
        #expect(m.frame.spines[3].rise < 50)
    }

    @Test func movingDownDoesNotGoBelowTheSlot() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        m.pointerMoved(upward: -80)
        #expect(m.drag == 0 && m.frame.spines[3].rise == 0)
        m.pointerMoved(upward: 30)
        #expect(m.drag == 30)
    }

    @Test func nonFiniteMovesAreIgnored() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        m.pointerMoved(upward: 30)
        let x6 = m.pointerMoved(upward: .nan)
        let x7 = m.pointerMoved(upward: .infinity)
        #expect(x6.isEmpty && x7.isEmpty)
        #expect(m.drag == 30)
    }

    @Test func inputOutsideADragIsIgnored() {
        var m = ShelfPullModel()
        let x8 = m.pointerMoved(upward: 30)
        let x9 = m.pointerUp()
        let x10 = m.pointerCancel()
        #expect(x8.isEmpty && x9.isEmpty && x10.isEmpty)
        let x11 = m.close()
        #expect(!x11 && m.phase == .resting)
    }

    @Test func aTapGoesStraightBackWithNoSeat() {
        var m = ShelfPullModel()
        m.pointerDown(book: 1)
        m.pointerMoved(upward: 0.3)
        let x12 = m.pointerUp()
        #expect(x12.isEmpty)
        #expect(m.phase == .resting && m.book == nil && m.seats == 0 && m.lastRelease == .none)
    }

    @Test func stepIgnoresBadAndNegativeTime() {
        var m = ShelfPullModel()
        let x13 = m.step(.nan)
        let x14 = m.step(-1)
        let x15 = m.step(0)
        #expect(x13.isEmpty && x14.isEmpty && x15.isEmpty)
        #expect(m.time == 0)
        m.step(10)
        #expect(m.time == ShelfPullModel.maxStep)
    }
}

@Suite struct ShelfPullModelArming {
    @Test func armedFiresOncePerCrossing() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        let c = ShelfResistance.commitDistance(height: m.layout.spines[3].height)
        let x16 = m.pointerMoved(upward: c - 1)
        #expect(x16.isEmpty && !m.isArmed)
        let x17 = m.pointerMoved(upward: c + 1)
        #expect(x17 == [.armed(3)] && m.isArmed)
        let x18 = m.pointerMoved(upward: c + 30)
        #expect(x18.isEmpty)
        #expect(m.frame.armed)
        let x19 = m.pointerMoved(upward: c - 10)
        #expect(x19.isEmpty && !m.isArmed)
        let x20 = m.pointerMoved(upward: c + 10)
        #expect(x20 == [.armed(3)])
    }

    @Test func armedIsClearedOnRelease() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        m.pointerMoved(upward: 120)
        m.pointerUp()
        #expect(!m.isArmed)
    }
}

@Suite struct ShelfPullModelRelease {
    @Test func shortSlowPullSpringsBackAndSeatsOnce() {
        var m = ShelfPullModel()
        let ev = pull(&m, 2, 40)
        #expect(ev.isEmpty && m.phase == .returning && m.returnKind == .springBack && m.lastRelease == .springBack)
        let after = run(&m, 1)
        #expect(after == [.seated(2)] && m.seats == 1 && m.springBacks == 1 && m.commits == 0)
        #expect(m.phase == .resting && m.book == nil)
    }

    @Test func springBackRiseDecreasesToZero() {
        var m = ShelfPullModel()
        pull(&m, 2, 40)
        var prev = m.frame.spines[2].rise
        #expect(prev > 10)
        for _ in 0..<33 {
            m.step(dt)
            let r = m.frame.spines[2].rise
            #expect(r <= prev + 1e-9)
            prev = r
        }
    }

    @Test func pullPastTheThresholdCommitsAndOpens() {
        var m = ShelfPullModel()
        let ev = pull(&m, 3, 140)
        #expect(ev.contains(.armed(3)) && ev.contains(.committed(3)))
        #expect(m.phase == .lifting && m.lastRelease == .commitDrag && m.commits == 1)
        let after = run(&m, 1)
        #expect(after == [.opened(3)] && m.phase == .open && m.opens == 1)
        #expect(m.frame.card != nil && m.frame.spines[3].turn == 90)
    }

    @Test func justUnderTheThresholdSpringsBackJustOverCommits() {
        let h = ShelfPullModel().layout.spines[3].height, c = ShelfResistance.commitDistance(height: h)
        var a = ShelfPullModel(); pull(&a, 3, c - 0.5)
        var b = ShelfPullModel(); pull(&b, 3, c + 0.5)
        #expect(a.phase == .returning && b.phase == .lifting)
    }

    @Test func aFastFlickCommitsEvenWhenShort() {
        var m = ShelfPullModel()
        m.pointerDown(book: 4)
        var t = 0.0
        for i in 1...6 { t += 0.01; m.pointerMoved(upward: Double(i) * 8, at: t) }   // 800 pt/s... 8pt per 10 ms
        let x21 = m.pointerUp(at: t)
        #expect(x21.isEmpty && m.phase == .returning)   // 800 < 900: springs back
        var f = ShelfPullModel()
        f.pointerDown(book: 4)
        t = 0
        for i in 1...6 { t += 0.01; f.pointerMoved(upward: Double(i) * 12, at: t) } // 1200 pt/s
        let x22 = f.pointerUp(at: t)
        #expect(x22 == [.committed(4)] && f.lastRelease == .commitFlick && f.phase == .lifting)
    }

    @Test func aFlickThatStoppedBeforeLiftOffDoesNotCommit() {
        var m = ShelfPullModel()
        m.pointerDown(book: 4)
        var t = 0.0
        for i in 1...6 { t += 0.01; m.pointerMoved(upward: Double(i) * 12, at: t) }
        let x23 = m.pointerUp(at: t + 0.2)
        #expect(x23.isEmpty && m.phase == .returning)
    }

    @Test func aFlickBelowTwelvePointsDoesNotCommit() {
        var m = ShelfPullModel()
        m.pointerDown(book: 4)
        m.pointerMoved(upward: 0, at: 0); m.pointerMoved(upward: 6, at: 0.005); m.pointerMoved(upward: 10, at: 0.01)
        let x24 = m.pointerUp(at: 0.01)
        #expect(x24.isEmpty && m.phase == .returning)
    }

    @Test func cancelAlwaysSpringsBack() {
        var m = ShelfPullModel()
        m.pointerDown(book: 3)
        m.pointerMoved(upward: 200)
        let x25 = m.pointerCancel()
        #expect(x25.isEmpty && m.phase == .returning && m.returnKind == .springBack)
        let x26 = run(&m, 1)
        #expect(x26 == [.seated(3)])
        var t = ShelfPullModel()
        t.pointerDown(book: 3)
        t.pointerCancel()
        #expect(t.phase == .resting && t.seats == 0)
    }

    @Test func regrabbingASpringingBookContinuesFromWhereItIs() {
        var m = ShelfPullModel()
        pull(&m, 2, 40)
        run(&m, 0.15)
        let rise = m.frame.spines[2].rise
        #expect(rise > 1 && m.canGrab)
        let x27 = m.pointerDown(book: 2)
        #expect(x27 && m.phase == .dragging)
        #expect(abs(m.frame.spines[2].rise - rise) < 1e-6)
        m.pointerMoved(upward: 10)
        #expect(m.frame.spines[2].rise > rise)
        #expect(m.seats == 0)
    }

    @Test func otherBooksCannotBeGrabbedWhileOneSpringsBack() {
        var m = ShelfPullModel()
        pull(&m, 2, 40)
        let x28 = m.pointerDown(book: 5)
        #expect(!x28)
    }

    @Test func aRegrabbedBookStillSeatsExactlyOnce() {
        var m = ShelfPullModel()
        pull(&m, 2, 40)
        run(&m, 0.1)
        m.pointerDown(book: 2)
        m.pointerMoved(upward: 5)
        m.pointerUp(at: m.time + 1)
        let ev = run(&m, 2)
        #expect(ev.filter { $0 == .seated(2) }.count == 1 && m.seats == 1)
    }

    @Test func grabbingDuringSeatingIsAllowed() {
        var m = ShelfPullModel()
        pull(&m, 2, 40)
        run(&m, 0.55 + 0.05)
        #expect(m.phase == .seating)
        let x29 = m.pointerDown(book: 4)
        #expect(x29)
        #expect(m.phase == .dragging && m.book == 4)
    }
}

@Suite struct ShelfPullModelPhases {
    @Test func fullCycleVisitsEveryPhaseInOrder() {
        var m = ShelfPullModel()
        var seen: [ShelfPhase] = [m.phase]
        func note() { if seen.last != m.phase { seen.append(m.phase) } }
        m.pointerDown(book: 3); note()
        for i in 1...10 { m.pointerMoved(upward: Double(i) * 14, at: m.time); m.step(0.02) }
        m.step(0.1); m.pointerUp(at: m.time); note()
        for _ in 0..<300 { m.step(dt); note() }
        m.close(); note()
        for _ in 0..<300 { m.step(dt); note() }
        #expect(seen == [.resting, .dragging, .lifting, .turning, .open, .returning, .seating, .resting])
    }

    @Test func phaseTimesMatchTheTimeline() {
        var m = ShelfPullModel()
        pull(&m, 3, 140)
        run(&m, 0.44)
        #expect(m.phase == .lifting)
        run(&m, 0.02)
        #expect(m.phase == .turning)
        run(&m, 0.48)
        #expect(m.phase == .turning)
        run(&m, 0.02)
        #expect(m.phase == .open)
    }

    @Test func openStaysOpenForever() {
        var m = ShelfPullModel()
        open(&m)
        run(&m, 30)
        #expect(m.phase == .open && m.seats == 0 && m.canClose && m.isAnimating == false)
    }

    @Test func closeIsRefusedWhileOpening() {
        var m = ShelfPullModel()
        pull(&m, 3, 140)
        run(&m, 0.5)
        let x30 = m.close()
        #expect(!x30 && m.phase == .turning)
        run(&m, 0.46)
        let x31 = m.close()
        #expect(m.phase == .open && !m.canClose && !x31)
        run(&m, 0.5)
        #expect(m.canClose)
        let x32 = m.close()
        #expect(x32 && m.phase == .returning && m.returnKind == .card)
    }

    @Test func closingSeatsExactlyOnce() {
        var m = ShelfPullModel()
        open(&m); run(&m, 0.6)
        m.close()
        var events: [ShelfEvent] = []
        events += run(&m, 1.39)
        #expect(events.isEmpty && m.phase == .returning)
        events += run(&m, 0.02)
        #expect(events == [.seated(3)] && m.phase == .seating && m.seats == 1)
        events += run(&m, 2)
        #expect(events == [.seated(3)] && m.phase == .resting && m.seats == 1)
    }

    @Test func closeTwiceIsIgnored() {
        var m = ShelfPullModel()
        open(&m); run(&m, 0.6)
        let x33 = m.close()
        let x34 = m.close()
        #expect(x33 && !x34)
        run(&m, 3)
        #expect(m.seats == 1)
    }

    @Test func seatingTakesPointZeroFourSeconds() {
        var m = ShelfPullModel()
        open(&m); run(&m, 0.6)
        m.close()
        run(&m, 1.41)
        #expect(m.phase == .seating)
        run(&m, 0.38)
        #expect(m.phase == .seating)
        run(&m, 0.03)
        #expect(m.phase == .resting)
    }

    @Test func aBigStepCarriesLeftoverTimeAcrossPhases() {
        var a = ShelfPullModel(), b = ShelfPullModel()
        pull(&a, 3, 140); pull(&b, 3, 140)
        for _ in 0..<4 { a.step(0.25) }          // big steps
        run(&b, 1.0, step: 0.001)                // tiny steps
        #expect(a.phase == b.phase)
        #expect(abs(a.phaseTime - b.phaseTime) < 1e-6)
        #expect(a.opens == b.opens)
    }

    @Test func stepSizeDoesNotChangeTheEventCounts() {
        for stepSize in [0.001, 1.0 / 120, 1.0 / 60, 0.05, 0.25] {
            var m = ShelfPullModel()
            var events = pull(&m, 5, 150)
            events += run(&m, 2, step: stepSize)
            m.close()
            events += run(&m, 3.5, step: stepSize)
            #expect(events.filter { $0 == .seated(5) }.count == 1)
            #expect(events.filter { $0 == .opened(5) }.count == 1)
            #expect(events.filter { $0 == .committed(5) }.count == 1)
            #expect(m.phase == .resting)
        }
    }

    @Test func activateOpensWithoutAPull() {
        var m = ShelfPullModel()
        let x35 = m.activate(book: 4)
        #expect(x35 == [.committed(4)])
        #expect(m.phase == .lifting && m.book == 4 && m.commits == 1)
        run(&m, 1)
        #expect(m.phase == .open && m.opens == 1)
    }

    @Test func activateIsRefusedMidFlight() {
        var m = ShelfPullModel()
        m.activate(book: 4)
        let x36 = m.activate(book: 2)
        #expect(x36.isEmpty && m.book == 4)
        var d = ShelfPullModel(); d.pointerDown(book: 1)
        let x37 = d.activate(book: 2)
        #expect(x37.isEmpty)
    }

    @Test func nothingGrabsWhileOpenOrLifting() {
        var m = ShelfPullModel()
        pull(&m, 3, 140)
        let x38 = m.pointerDown(book: 1)
        #expect(!x38)
        run(&m, 1.1)
        let x39 = m.pointerDown(book: 1)
        #expect(!x39 && m.phase == .open)
        let x40 = m.pointerMoved(upward: 20)
        let x41 = m.pointerUp()
        #expect(x40.isEmpty && x41.isEmpty)
    }

    @Test func repeatedCyclesKeepCountsInStep() {
        var m = ShelfPullModel()
        for round in 0..<5 {
            let b = round % 7
            pull(&m, b, round % 2 == 0 ? 150 : 40)
            run(&m, 1.1)
            if m.phase == .open { run(&m, 0.6); m.close() }
            run(&m, 3)
            #expect(m.phase == .resting)
        }
        #expect(m.seats == 5 && m.commits == 3 && m.opens == 3 && m.springBacks == 2)
    }

    @Test func isAnimatingOnlyInTimedPhases() {
        var m = ShelfPullModel()
        m.pointerDown(book: 0); #expect(!m.isAnimating)
        m.pointerMoved(upward: 150); m.pointerUp(at: 99)
        #expect(m.isAnimating)
    }
}

@Suite struct ShelfPullModelReduceMotion {
    @Test func commitGoesStraightToOpenWithCrossfade() {
        var m = ShelfPullModel(reduceMotion: true)
        let ev = pull(&m, 3, 150)
        #expect(ev.suffix(2) == [.committed(3), .opened(3)])
        #expect(m.phase == .open && m.opens == 1)
        #expect(m.frame.card?.opacity == 0)
        run(&m, 0.3)
        #expect(m.frame.card?.opacity == 1 && m.frame.spines.allSatisfy { $0.turn == 0 && $0.rise == 0 })
    }

    @Test func closeFadesThenSeatsOnceWithShortSeat() {
        var m = ShelfPullModel(reduceMotion: true)
        pull(&m, 3, 150); run(&m, 0.3)
        let x42 = m.close()
        #expect(x42 && m.returnKind == .fade)
        run(&m, 0.24)
        #expect(m.phase == .returning)
        let x43 = run(&m, 0.02)
        #expect(x43 == [.seated(3)])
        run(&m, 0.1)
        #expect(m.phase == .seating)
        run(&m, 0.03)
        #expect(m.phase == .resting && m.seats == 1)
    }

    @Test func closeLockoutIsShorterUnderReduceMotion() {
        var m = ShelfPullModel(reduceMotion: true)
        pull(&m, 3, 150)
        run(&m, 0.2)
        let x44 = m.close()
        #expect(!x44)
        run(&m, 0.06)
        let x45 = m.close()
        #expect(x45)
    }

    @Test func activateOpensImmediately() {
        var m = ShelfPullModel(reduceMotion: true)
        let x46 = m.activate(book: 1)
        #expect(x46 == [.committed(1), .opened(1)] && m.phase == .open)
    }

    @Test func switchingReduceMotionOnMidFlightPutsTheBookBack() {
        var m = ShelfPullModel()
        pull(&m, 3, 150)
        run(&m, 0.2)
        m.setReduceMotion(true)
        #expect(m.phase == .resting && m.book == nil && m.reduceMotion)
        m.setReduceMotion(true)
        #expect(m.phase == .resting)
    }

    @Test func switchingWhileRestingJustChangesTheFlag() {
        var m = ShelfPullModel()
        m.pointerDown(book: 1)
        m.setReduceMotion(true)
        #expect(m.phase == .dragging && m.reduceMotion)
    }

    @Test func springBackIsUnchanged() {
        var m = ShelfPullModel(reduceMotion: true)
        pull(&m, 2, 40)
        #expect(m.returnKind == .springBack)
        let x47 = run(&m, 1)
        #expect(x47 == [.seated(2)])
    }
}

@Suite struct ShelfPullModelRobustness {
    @Test(arguments: [3, 5, 7, 9])
    func everyBookOnEveryShelfSizeOpensAndSeats(_ n: Int) {
        for b in 0..<n {
            var m = ShelfPullModel(count: n)
            m.activate(book: b)
            run(&m, 1.1)
            #expect(m.phase == .open)
            run(&m, 0.6)
            m.close()
            let ev = run(&m, 2)
            #expect(ev == [.seated(b)] && m.phase == .resting)
        }
    }

    @Test func randomisedSessionsKeepTheInvariants() {
        for seed in UInt32(1)...40 {
            var m = ShelfPullModel()
            var events: [ShelfEvent] = []
            for k in 0..<80 {
                let r = ShelfHash.value(seed, k)
                switch r % 6 {
                case 0: m.pointerDown(book: Int(r >> 8) % 7)
                case 1: events += m.pointerMoved(upward: Double(Int(r >> 8) % 260 - 40), at: m.time)
                case 2: events += m.pointerUp(at: m.time)
                case 3: m.close()
                case 4: events += m.pointerCancel()
                default: events += m.activate(book: Int(r >> 8) % 7)
                }
                events += m.step(Double(r >> 16 & 0xFF) / 255 * 0.3)
                let fr = m.frame
                for s in fr.spines {
                    #expect(s.rise >= -1e-9 && s.rise.isFinite && abs(s.lean) <= 12 + 1.6 + 1e-9 && s.turn >= 0 && s.turn <= 90 + 1e-9)
                }
                if m.phase == .resting { #expect(m.book == nil) } else { #expect(m.book != nil) }
            }
            for _ in 0..<60 { events += m.step(0.1); if m.canClose { m.close() } }
            func count(_ f: (ShelfEvent) -> Bool) -> Int { events.filter(f).count }
            #expect(count { if case .seated = $0 { return true }; return false } == m.seats)
            #expect(count { if case .opened = $0 { return true }; return false } == m.opens)
            #expect(count { if case .committed = $0 { return true }; return false } == m.commits)
            #expect(m.phase == .resting || m.phase == .dragging)
            // every open was closed, so every commit ended with its own seat; spring-backs seat too
            #expect(m.seats == m.commits + m.springBacks || m.phase == .dragging)
        }
    }

    @Test func seatsEqualReturnsNeverExceedStarts() {
        var m = ShelfPullModel()
        var events: [ShelfEvent] = []
        for b in [0, 1, 2, 3, 4, 5, 6] {
            events += pull(&m, b, b % 2 == 0 ? 160 : 30)
            events += run(&m, 1.2)
            if m.phase == .open { run(&m, 0.6); m.close() }
            events += run(&m, 2.5)
        }
        let seated = events.filter { if case .seated = $0 { return true }; return false }.count
        let committed = events.filter { if case .committed = $0 { return true }; return false }.count
        #expect(seated == 7 && committed == 4 && m.seats == 7)
    }

    @Test func modelsAreEquatableAndValueTypes() {
        var a = ShelfPullModel()
        let b = a
        a.pointerDown(book: 1)
        #expect(a != b && b.phase == .resting)
        #expect(ShelfPullModel() == ShelfPullModel())
    }
}
