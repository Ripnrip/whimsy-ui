import Testing
import Foundation
@testable import DogEarCore

private func near(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

private let grab = DogEarLayout.grab
private let diag = Vec2(-0.6, -0.8)

/// Steps a model at 60 Hz from `from` to `t`, collecting events.
@discardableResult
private func run(_ m: inout DogEarModel, from: Double = 0, to t: Double) -> [DogEarEvent] {
    var out: [DogEarEvent] = []
    var f = Int((from * 60).rounded(.up))
    while Double(f) / 60 <= t + 1e-9 { out += m.advance(to: Double(f) / 60); f += 1 }
    return out
}

/// A model with the corner held and dragged `pull` points along `dir`, at time 0.
private func held(pull: Double, dir: Vec2 = diag, reduceMotion: Bool = false) -> DogEarModel {
    var m = DogEarModel(reduceMotion: reduceMotion)
    m.begin(at: grab, time: 0)
    m.drag(to: grab + dir * pull, time: 0)
    return m
}

private func progressPull(_ progress: Double, dir: Vec2 = diag) -> Double { DogEarLayout.extent(along: dir) * progress }

@Suite("Layout and fold") struct LayoutTests {
    @Test func cardOutlineAndGrabPoint() {
        let a = DogEarLayout.shape.area
        let full = DogEarLayout.width * DogEarLayout.height
        #expect(a < full && a > full - 4 * DogEarLayout.cornerRadius * DogEarLayout.cornerRadius)
        // The grab is the middle of the rounded bottom-right corner, so it sits on the outline.
        let onOutline = DogEarLayout.shape.points.contains { $0.distance(to: grab) < 1e-9 }
        #expect(onOutline)
        #expect(grab.x < DogEarLayout.width && grab.y < DogEarLayout.height)
    }

    @Test func reachAlongADirection() {
        let inward = DogEarLayout.extent(along: DogEarLayout.inward)
        #expect(inward > 480 && inward < 520)
        #expect(DogEarLayout.extent(along: Vec2(-1, 0)) > 270 && DogEarLayout.extent(along: Vec2(-1, 0)) < DogEarLayout.width)
        // Pointing out of the card, the corner is already the farthest point.
        #expect(DogEarLayout.extent(along: Vec2(1, 1)) <= 1e-9)
        #expect(DogEarLayout.extent(along: .zero) == 0)
    }

    @Test func creaseIsThePerpendicularBisectorOfCornerAndFinger() throws {
        let finger = grab + diag * 160
        let fold = try #require(FoldLine(grab: grab, finger: finger))
        #expect(near(fold.signedDistance(grab), -80) && near(fold.signedDistance(finger), 80))
        #expect(near(fold.reflect(grab).distance(to: finger), 0))
        let f = held(pull: 160).frame
        let a = try #require(f.creaseFrom), b = try #require(f.creaseTo)
        #expect(near(fold.signedDistance(a), 0, 1e-6) && near(fold.signedDistance(b), 0, 1e-6))
    }

    @Test func foldedAndFlatAreasAddUpAndTheFlapIsTheMirrorImage() throws {
        let m = held(pull: 220)
        let f = m.frame
        let state = PeelState.peel(DogEarLayout.shape, grab: grab, finger: m.finger)
        #expect(near(f.flat.area + state.lifted.area, DogEarLayout.shape.area, 1e-6))
        #expect(near(f.flap.area, state.lifted.area, 1e-6))
        #expect(near(f.areaFraction, state.lifted.area / DogEarLayout.shape.area))
        // Reflecting the flap back gives the lifted region.
        let fold = try #require(state.fold)
        let back = Polygon(f.flap.points.map { fold.reflect($0) })
        #expect(near(back.area, state.lifted.area, 1e-6))
    }

    @Test func theCornerTipLandsOnTheFinger() throws {
        let m = held(pull: 200)
        let f = m.frame
        #expect(f.flap.points.contains { $0.distance(to: m.finger) < 1e-6 })
    }
}

@Suite("Dragging") struct DragTests {
    @Test func grabNeedsATouchNearTheCorner() {
        var m = DogEarModel()
        let r1 = m.begin(at: Vec2(40, 40), time: 0)
        #expect(!r1)
        let r2 = m.begin(at: grab + Vec2(-DogEarLayout.grabRadius - 1, 0), time: 0)
        #expect(!r2)
        let r3 = m.begin(at: grab + Vec2(-DogEarLayout.grabRadius + 1, 0), time: 0)
        #expect(r3)
        #expect(m.phase == .dragging)
        let r4 = m.advance(to: 0)
        #expect(r4.contains(.grabbed))
    }

    @Test func theCornerDoesNotJumpUnderTheFinger() {
        var m = DogEarModel()
        let touch = grab + Vec2(-30, -20)
        m.begin(at: touch, time: 0)
        m.drag(to: touch, time: 0)
        #expect(m.pull < 1e-9)
        m.drag(to: touch + diag * 90, time: 0)
        #expect(near(m.pull, 90, 1e-6))
        #expect(near(m.direction.x, diag.x) && near(m.direction.y, diag.y))
    }

    @Test func draggingOutOfTheCardLiftsNothing() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        m.drag(to: grab + Vec2(80, 60), time: 0)
        // Pointing out of the card the reach is a few points of rounded corner at most, and nothing lifts.
        #expect(m.pull < 6 && m.progress <= 1)
        #expect(near(m.frame.flat.area, DogEarLayout.shape.area) && m.frame.flap.isEmpty)
    }

    @Test func tinyPullsStayFlat() {
        let m = held(pull: 0.3)
        #expect(m.frame.flap.isEmpty && m.frame.areaFraction == 0)
    }

    @Test func theFingerCannotTearTheCreaseBeyondTheCard() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        for target in [Vec2(-900, -900), Vec2(-5000, 40), Vec2(-100, -3000), Vec2(-300, -500)] {
            m.drag(to: target, time: 0)
            #expect(m.pull <= m.reach + 1e-9)
            #expect(m.progress <= 1)
            let f = m.frame
            // The crease stays on the card, and some of the card stays down.
            #expect(f.flat.area > 1)
            for p in [f.creaseFrom, f.creaseTo].compactMap({ $0 }) {
                #expect(p.x >= -1e-6 && p.x <= DogEarLayout.width + 1e-6 && p.y >= -1e-6 && p.y <= DogEarLayout.height + 1e-6)
            }
        }
    }

    @Test func progressIsMonotonicInThePull() {
        var last = -1.0
        for k in 0...20 {
            let p = held(pull: Double(k) * 25).progress
            #expect(p >= last)
            last = p
        }
        #expect(near(held(pull: 10_000).progress, 1))
        #expect(near(held(pull: progressPull(0.5)).progress, 0.5, 1e-9))
    }

    @Test func liftedAreaGrowsWithTheDrag() {
        var last = -1.0
        for k in 0...20 {
            let a = held(pull: Double(k) * 25).frame.areaFraction
            #expect(a >= last - 1e-12)
            last = a
        }
        #expect(last > 0.2 && last < 0.6)
    }
}

@Suite("Threshold and haptics") struct ThresholdTests {
    @Test func crossingTheThresholdArmsItOnce() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        m.drag(to: grab + diag * progressPull(0.55), time: 0.1)
        #expect(!m.armed)
        m.drag(to: grab + diag * progressPull(0.61), time: 0.2)
        #expect(m.armed)
        m.drag(to: grab + diag * progressPull(0.7), time: 0.3)
        let events = m.advance(to: 0.3)
        #expect(events.filter { $0 == .thresholdCrossed(armed: true) }.count == 1)
        #expect(events.filter { $0 == .haptic(.threshold) }.count == 1)
        #expect(m.hapticCount == 1)
    }

    @Test func hysteresisKeepsItArmedJustBelowTheLine() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        m.drag(to: grab + diag * progressPull(0.62), time: 0.1)
        m.drag(to: grab + diag * progressPull(0.59), time: 0.2)
        #expect(m.armed)
        m.drag(to: grab + diag * progressPull(0.56), time: 0.3)
        #expect(!m.armed)
        let events = m.advance(to: 0.3)
        #expect(events.contains(.thresholdCrossed(armed: false)))
    }

    @Test func hapticsAreDebounced() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        let up = grab + diag * progressPull(0.7), down = grab + diag * progressPull(0.3)
        m.drag(to: up, time: 0.20)      // haptic
        m.drag(to: down, time: 0.25)    // inside 120 ms: crossing event, no haptic
        m.drag(to: up, time: 0.28)      // still inside the window
        #expect(m.hapticCount == 1)
        m.drag(to: down, time: 0.50)
        #expect(m.hapticCount == 2)
        let events = m.advance(to: 0.5)
        #expect(events.filter { $0 == .thresholdCrossed(armed: true) }.count == 2)
    }

    @Test func letGoJustBelowSpringsAndJustAbovePeels() {
        var below = held(pull: progressPull(0.58))
        below.end(time: 0)
        #expect(below.phase == .springingBack)
        var above = held(pull: progressPull(0.61))
        above.end(time: 0)
        #expect(above.phase == .peelingOff)
    }
}

@Suite("Spring back") struct SpringTests {
    /// Samples the pull every frame while the corner springs flat.
    private func springRun(reduce: Bool = false) -> (pulls: [Double], model: DogEarModel, events: [DogEarEvent]) {
        var m = held(pull: progressPull(0.4), reduceMotion: reduce)
        m.end(time: 0)
        var pulls: [Double] = [], events: [DogEarEvent] = []
        for f in 1...240 {
            events += m.advance(to: Double(f) / 60)
            pulls.append(m.pull)
        }
        return (pulls, m, events)
    }

    @Test func overshootsThroughFlatAndLiftsASmallBounce() {
        let r = springRun()
        let start = progressPull(0.4)
        let firstNegative = r.pulls.firstIndex { $0 < -0.5 }
        #expect(firstNegative != nil)
        // After going negative, the corner lifts again a little: a small, visible bounce.
        let after = r.pulls.dropFirst((firstNegative ?? 0) + 1)
        let bounce = after.drop { $0 < 0 }.max() ?? 0
        #expect(bounce > 2 && bounce < start * 0.15)
        // The overshoot below flat is bounded: an under-damped spring, not a runaway.
        #expect((r.pulls.min() ?? 0) > -start * 0.4)
    }

    @Test func settlesFlatAndAnnouncesIt() {
        let r = springRun()
        #expect(r.model.phase == .idle && r.model.pull == 0)
        #expect(r.events.contains(.springBackStarted))
        #expect(r.events.filter { $0 == .settled }.count == 1)
        #expect(r.model.isIdle)
        #expect(near(r.model.frame.flat.area, DogEarLayout.shape.area))
    }

    @Test func negativePullShowsAFlatCard() {
        var m = held(pull: progressPull(0.4))
        m.end(time: 0)
        var sawFlatWhileNegative = false
        for f in 1...120 {
            m.advance(to: Double(f) / 60)
            if m.pull < -1 { sawFlatWhileNegative = m.frame.flap.isEmpty && m.progress == 0 }
        }
        #expect(sawFlatWhileNegative)
    }

    @Test func springStartsFromTheReleasedPull() {
        var m = held(pull: 123)
        m.end(time: 0)
        #expect(near(m.pull, 123))
        m.advance(to: 1 / 60)
        #expect(m.pull < 123 && m.pull > 0)
    }

    @Test func aReleaseWithBarelyAnyPullJustSettles() {
        var m = held(pull: 0.2)
        m.end(time: 0)
        #expect(m.phase == .idle)
        let r5 = m.advance(to: 0)
        #expect(r5.contains(.settled))
    }

    @Test func grabbingAgainMidSpringCatchesTheTip() {
        var m = held(pull: progressPull(0.4))
        m.end(time: 0)
        run(&m, to: 0.1)
        let tip = m.finger
        let r6 = m.begin(at: tip + Vec2(5, 5), time: 0.1)
        #expect(r6)
        #expect(m.phase == .dragging)
        #expect(near(m.pull, tip.distance(to: grab), 1e-6))
    }

    @Test func reduceMotionSpringHasNoWobble() {
        let r = springRun(reduce: true)
        #expect((r.pulls.min() ?? 0) > -0.5)
        #expect(r.model.phase == .idle)
        // Monotonic return.
        var last = Double.infinity
        for p in r.pulls { #expect(p <= last + 1e-9); last = p }
    }
}

@Suite("Peel off") struct PeelOffTests {
    private func released(at progress: Double = 0.8) -> DogEarModel {
        var m = held(pull: progressPull(progress))
        m.end(time: 0)
        return m
    }

    @Test func theCreaseSweepsAcrossTheCard() {
        var m = released()
        #expect(m.phase == .peelingOff)
        var last = DogEarLayout.shape.area
        var lastPull = m.pull
        for f in 1...29 {
            m.advance(to: Double(f) / 60)
            let flat = m.frame.flat.area
            #expect(flat <= last + 1e-6)
            #expect(m.pull >= lastPull - 1e-9)
            last = flat; lastPull = m.pull
        }
        m.advance(to: 0.5)
        #expect(m.phase == .flying)
        // The crease has passed the far side: nothing flat, and the flap is the whole card folded over.
        #expect(m.frame.flat.isEmpty)
        #expect(near(m.frame.flap.area, DogEarLayout.shape.area, 1e-6))
    }

    @Test func theFoldedCardFliesOffWithASlightRotation() {
        var m = released()
        run(&m, to: 0.5)
        let rules = m.rules
        let c0 = m.frame.flap.centroid
        run(&m, from: 0.5, to: 0.5 + rules.flyDuration / 2)
        let mid = m.frame
        let u = (m.time - 0.5) / rules.flyDuration
        let moved = mid.flap.centroid - c0
        #expect(moved.length > 1)
        #expect(near(moved.length, rules.flyDistance * u * u, 1.5))
        #expect(moved.dot(m.direction) > 0)
        // Rotation keeps the area, and stays slight.
        #expect(near(mid.flap.area, DogEarLayout.shape.area, 1e-6))
        #expect(rules.flyRotation < 0.2)
        // Opacity fades toward the end.
        run(&m, from: 0.5 + rules.flyDuration / 2, to: 0.5 + rules.flyDuration - 1 / 60)
        #expect(m.frame.flapOpacity < mid.flapOpacity + 1e-12)
        #expect(m.frame.flapOpacity < 0.1)
    }

    @Test func theNoteIsRevealedOnceTheCardHasGone() {
        var m = held(pull: progressPull(0.8))
        m.end(time: 0.2)
        var events = m.advance(to: 0.2)
        events += run(&m, from: 0.2 + 1 / 60, to: 2)
        #expect(events.contains(.peelOffStarted))
        #expect(events.contains(.haptic(.peelOff)))
        #expect(events.filter { $0 == .noteRevealed }.count == 1)
        #expect(m.phase == .revealed && m.noteRevealed)
        #expect(m.frame.cardOpacity == 0 && m.frame.flat.isEmpty && m.frame.flap.isEmpty)
        #expect(m.announcement?.contains("Knock three times") == true)
        #expect(m.announcementCount == 1)
        #expect(m.isIdle)
    }

    @Test func revealHappensAtTheEndOfTheFlight() {
        var m = released()
        let total = m.rules.sweepDuration + m.rules.flyDuration
        run(&m, to: total - 0.05)
        #expect(m.phase == .flying)
        run(&m, from: total - 0.05 + 1 / 60, to: total + 0.05)
        #expect(m.phase == .revealed)
    }

    @Test func peelOffHapticFiresEvenAfterAThresholdTick() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        m.drag(to: grab + diag * progressPull(0.7), time: 0.1)   // threshold tick
        m.drag(to: grab + diag * progressPull(0.8), time: 0.5)   // held a while
        m.end(time: 0.5)
        let events = m.advance(to: 0.5)
        #expect(events.contains(.haptic(.peelOff)))
        #expect(m.hapticCount == 2)
    }

    @Test func aQuickCrossAndReleaseSharesOneHaptic() {
        var m = DogEarModel()
        m.begin(at: grab, time: 0)
        m.drag(to: grab + diag * progressPull(0.7), time: 0.1)
        m.end(time: 0.15)
        #expect(m.hapticCount == 1)
    }

    @Test func accessibilityPeelComesAwayFromRest() {
        var m = DogEarModel()
        m.peel(time: 0)
        #expect(m.phase == .peelingOff)
        let events = run(&m, to: 2)
        #expect(events.contains(.peelOffStarted) && events.contains(.noteRevealed))
        #expect(m.phase == .revealed)
        #expect(near(m.direction.x, DogEarLayout.inward.x) && near(m.direction.y, DogEarLayout.inward.y))
    }

    @Test func peelFromAHalfDragContinuesFromThere() {
        var m = held(pull: progressPull(0.3))
        m.peel(time: 0)
        #expect(m.phase == .peelingOff)
        #expect(near(m.pull, progressPull(0.3), 1e-6))
        m.advance(to: 1 / 60)
        #expect(m.pull > progressPull(0.3))
    }

    @Test func peelWorksInAnyDirection() {
        for dir in [Vec2(-1, 0), Vec2(0, -1), Vec2(-0.9, -0.1).normalized, Vec2(-0.1, -0.9).normalized] {
            var m = held(pull: DogEarLayout.extent(along: dir) * 0.8, dir: dir)
            m.end(time: 0)
            run(&m, to: 0.5)
            #expect(m.frame.flat.isEmpty)
            #expect(near(m.frame.flap.area, DogEarLayout.shape.area, 1e-6))
            run(&m, from: 0.5, to: 2)
            #expect(m.phase == .revealed)
        }
    }
}

@Suite("Reduce Motion") struct ReduceMotionTests {
    @Test func theCardFadesInsteadOfSweeping() {
        var m = held(pull: progressPull(0.8), reduceMotion: true)
        m.end(time: 0)
        #expect(m.phase == .fading)
        var last = 1.0
        for f in 1...20 {
            m.advance(to: Double(f) / 60)
            let fr = m.frame
            #expect(fr.flap.isEmpty && near(fr.flat.area, DogEarLayout.shape.area))
            #expect(fr.cardOpacity <= last + 1e-12)
            last = fr.cardOpacity
        }
        run(&m, from: 21.0 / 60, to: 1)
        #expect(m.phase == .revealed)
    }

    @Test func fadeHasTheSameEventsAndHaptic() {
        var m = held(pull: progressPull(0.8), reduceMotion: true)
        m.end(time: 0.2)
        var events = m.advance(to: 0.2)
        events += run(&m, from: 0.2 + 1 / 60, to: 1)
        #expect(events.contains(.peelOffStarted) && events.contains(.haptic(.peelOff)) && events.contains(.noteRevealed))
    }

    @Test func accessibilityPeelFadesToo() {
        var m = DogEarModel(reduceMotion: true)
        m.peel(time: 0)
        #expect(m.phase == .fading)
        run(&m, to: 1)
        #expect(m.phase == .revealed)
    }

    @Test func resetFadesBackWithoutScaling() {
        var m = DogEarModel(reduceMotion: true)
        m.peel(time: 0)
        run(&m, to: 1)
        m.reset(time: 1)
        run(&m, from: 1 + 1 / 60, to: 1.2)
        let f = m.frame
        #expect(f.cardScale == 1 && f.cardOpacity > 0 && f.cardOpacity < 1)
    }
}

@Suite("Shading") struct ShadingTests {
    @Test func paramsGrowWithThePeelAndStayInRange() {
        var last = DogEarShading.make(progress: 0, flapDepth: 50)
        for k in 1...10 {
            let s = DogEarShading.make(progress: Double(k) / 10, flapDepth: 50)
            #expect(s.creaseDark >= last.creaseDark && s.shadowOpacity >= last.shadowOpacity)
            #expect(s.shadowOffset >= last.shadowOffset && s.shadowBlur >= last.shadowBlur)
            #expect(s.creaseDark < 0.5 && s.shadowOpacity < 0.5)
            last = s
        }
        let clamped = DogEarShading.make(progress: 7, flapDepth: 0)
        #expect(clamped == DogEarShading.make(progress: 1, flapDepth: 1))
    }

    @Test func gradientRunsFromTheCreaseAcrossTheFlap() throws {
        let m = held(pull: 220)
        let f = m.frame
        let fold = try #require(FoldLine(grab: grab, finger: m.finger))
        #expect(near(fold.signedDistance(f.gradientFrom), 0, 1e-6))
        let depth = f.flap.points.map { fold.signedDistance($0) }.max() ?? 0
        #expect(near(fold.signedDistance(f.gradientTo), depth, 1e-6))
        #expect(near(f.shading.gradientLength, depth, 1e-6))
        // The axis is perpendicular to the crease.
        let axis = (f.gradientTo - f.gradientFrom).normalized
        #expect(near(axis.dot(fold.tangent), 0, 1e-9))
        #expect(near(f.shadowDirection.dot(fold.normal), 1, 1e-9))
    }

    @Test func theFlapFitsInsideTheGradient() throws {
        let m = held(pull: 220)
        let f = m.frame
        let fold = try #require(FoldLine(grab: grab, finger: m.finger))
        #expect(f.flap.points.allSatisfy { fold.signedDistance($0) >= -1e-6 && fold.signedDistance($0) <= f.shading.gradientLength + 1e-6 })
    }

    @Test func shadingRisesAsTheCornerLifts() {
        let a = held(pull: progressPull(0.1)).frame.shading
        let b = held(pull: progressPull(0.9)).frame.shading
        #expect(b.creaseDark > a.creaseDark && b.shadowOpacity > a.shadowOpacity && b.shadowOffset > a.shadowOffset)
    }
}

@Suite("Reset and accessibility") struct ResetTests {
    @Test func resetBringsTheCardBack() {
        var m = DogEarModel()
        m.peel(time: 0)
        run(&m, to: 2)
        let r7 = m.reset(time: 2)
        #expect(r7)
        #expect(m.phase == .returning)
        var last = 0.0
        for f in 1...29 {
            m.advance(to: 2 + Double(f) / 60)
            let fr = m.frame
            #expect(fr.cardOpacity >= last - 1e-12 && fr.cardScale <= 1 && fr.cardScale >= 0.94 - 1e-12)
            last = fr.cardOpacity
        }
        run(&m, from: 2.5, to: 3)
        #expect(m.phase == .idle && m.isIdle)
        #expect(m.frame.cardOpacity == 1 && m.frame.cardScale == 1)
        #expect(near(m.frame.flat.area, DogEarLayout.shape.area))
        #expect(m.announcement == "Card restored" && m.announcementCount == 2)
        // The card can be peeled again.
        let r8 = m.begin(at: grab, time: 3)
        #expect(r8)
    }

    @Test func resetDuringAPeelWorksAndIdleResetDoesNothing() {
        var m = DogEarModel()
        let r9 = m.reset(time: 0)
        #expect(!r9)
        m.peel(time: 0)
        run(&m, to: 0.2)
        let r10 = m.reset(time: 0.2)
        #expect(r10)
        run(&m, from: 0.2 + 1 / 60, to: 1)
        #expect(m.phase == .idle)
        let r11 = m.reset(time: 1)
        #expect(!r11)
    }

    @Test func labelsReadTheCardAndTheNote() {
        var m = DogEarModel()
        #expect(m.accessibilityLabel.contains("Midnight Masquerade") && m.accessibilityLabel.contains("Fri 31 Oct, 8 PM"))
        #expect(m.accessibilityValue == "Closed")
        m.begin(at: grab, time: 0)
        m.drag(to: grab + diag * progressPull(0.5), time: 0)
        #expect(m.accessibilityValue == "Peeling, 50 percent")
        m.drag(to: grab + diag * progressPull(0.8), time: 0.2)
        m.end(time: 0.3)
        run(&m, from: 0.3, to: 2.3)
        #expect(m.accessibilityValue == "Peeled away")
        #expect(m.content.noteLabel.contains("moonberry") && m.content.noteLabel.contains("13 Hollow Lane"))
    }

    @Test func idleOnlyWhenNothingMoves() {
        var m = DogEarModel()
        #expect(m.isIdle)
        m.begin(at: grab, time: 0)
        #expect(!m.isIdle)
        m.end(time: 0)
        _ = m.advance(to: 0)
        #expect(m.isIdle)
    }

    @Test func timeOnlyMovesForward() {
        var m = DogEarModel()
        m.peel(time: 0.5)
        let p = m.pull
        m.advance(to: 0.1)
        #expect(m.pull == p && m.time == 0.5)
    }
}
