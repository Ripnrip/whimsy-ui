import Testing
import Foundation
@testable import ContourInkCore

private typealias T = ContourInkTimeline
private let eps = 1e-9

@Suite struct TimelineConstantsTests {
    @Test func theLoopIsTheSumOfItsPhases() {
        #expect(abs(T.drawDuration(rings: 7) - 1.22) < eps)
        #expect(abs(T.period(rings: 7) - 4.57) < eps)
        #expect(abs(T.period(rings: 7) - (T.drawDuration(rings: 7) + T.climbDuration + T.tiltDuration + T.fadeDuration + T.loopDuration)) < eps)
    }

    @Test func ringsStartAboutAHundredTwentyMillisecondsApart() {
        #expect(T.stagger == 0.12)
        #expect(T.drawDuration(rings: 6) < T.drawDuration(rings: 7))
        #expect(abs(T.drawDuration(rings: 7) - T.drawDuration(rings: 6) - 0.12) < eps)
    }

    @Test func phaseStartsAreIncreasing() {
        for n in 3...12 {
            let s = T.phaseStarts(rings: n)
            #expect(s.count == 5 && s[0] == 0)
            #expect(zip(s, s.dropFirst()).allSatisfy { $0 < $1 })
            #expect(s[4] + T.loopDuration - T.period(rings: n) < eps)
        }
    }

    @Test func theSheetTiltsAboutTwentyFiveDegrees() {
        #expect(T.tiltDegrees == 25)
        #expect(T.tiltRise < T.tiltDuration)
    }

    @Test func ringCountIsClamped() {
        #expect(T.period(rings: 1) == T.period(rings: 3))
        #expect(T.period(rings: 99) == T.period(rings: 12))
        #expect(T.frame(at: 1, rings: 0).ringTrims.count == 3)
        #expect(T.frame(at: 1, rings: 40).ringTrims.count == 12)
    }
}

@Suite struct RingTrimTests {
    @Test func ringsStartStaggered() {
        for k in 0..<7 {
            #expect(T.ringTrim(ring: k, at: Double(k) * 0.12) == 0)
            #expect(T.ringTrim(ring: k, at: Double(k) * 0.12 - 0.05) == 0)
            #expect(T.ringTrim(ring: k, at: Double(k) * 0.12 + 0.01) > 0)
        }
    }

    @Test func eachRingIsFullyDrawnWhenItCloses() {
        for k in 0..<12 {
            #expect(T.ringTrim(ring: k, at: T.closeTime(ring: k)) == 1)
            #expect(T.ringTrim(ring: k, at: T.closeTime(ring: k) - 0.01) < 1)
            #expect(T.ringTrim(ring: k, at: T.closeTime(ring: k) + 5) == 1)
        }
    }

    @Test func closeTimesAreStaggeredByTheStagger() {
        for k in 1..<7 { #expect(abs(T.closeTime(ring: k) - T.closeTime(ring: k - 1) - 0.12) < eps) }
        #expect(abs(T.closeTime(ring: 6) - T.drawDuration(rings: 7)) < eps)
    }

    @Test func drawingIsEasedInAndOut() {
        // slow at the ends, quick in the middle
        #expect(T.ringTrim(ring: 0, at: 0.25) == 0.5)
        #expect(T.ringTrim(ring: 0, at: 0.05) < 0.1 * 0.2)
        #expect(T.ringTrim(ring: 0, at: 0.45) > 0.9)
        let a = T.ringTrim(ring: 0, at: 0.20) - T.ringTrim(ring: 0, at: 0.15)
        let b = T.ringTrim(ring: 0, at: 0.05) - T.ringTrim(ring: 0, at: 0.0)
        #expect(a > 4 * b)
    }

    @Test func trimNeverGoesBackwards() {
        for k in 0..<7 {
            var prev = 0.0
            for i in 0...300 {
                let v = T.ringTrim(ring: k, at: Double(i) * 0.005)
                #expect(v >= prev && v >= 0 && v <= 1)
                prev = v
            }
        }
    }

    @Test func aRingNeverRunsAheadOfTheOneOutsideIt() {
        for i in 0...300 {
            let t = Double(i) * 0.005
            for k in 1..<7 { #expect(T.ringTrim(ring: k, at: t) <= T.ringTrim(ring: k - 1, at: t) + 1e-12) }
        }
    }
}

@Suite struct PhaseTests {
    @Test func phaseFollowsTheClock() {
        let s = T.phaseStarts(rings: 7)
        func ph(_ t: Double) -> ContourPhase { T.frame(at: t, rings: 7).phase }
        #expect(ph(0) == .draw && ph(s[1] - 0.001) == .draw)
        #expect(ph(s[1]) == .climb && ph(s[2] - 0.001) == .climb)
        #expect(ph(s[2]) == .tilt && ph(s[3] - 0.001) == .tilt)
        #expect(ph(s[3]) == .fade && ph(s[4] - 0.001) == .fade)
        #expect(ph(s[4]) == .loop && ph(T.period(rings: 7) - 0.001) == .loop)
        #expect(ph(T.period(rings: 7)) == .draw)
    }

    @Test func phaseProgressRunsFromZeroToOneInEachPhase() {
        let s = T.phaseStarts(rings: 7) + [T.period(rings: 7)]
        for (i, ph) in ContourPhase.allCases.enumerated() {
            let a = T.frame(at: s[i], rings: 7), b = T.frame(at: s[i + 1] - 1e-6, rings: 7)
            #expect(a.phase == ph && abs(a.phaseProgress) < 1e-9)
            #expect(b.phase == ph && b.phaseProgress > 0.999)
        }
    }

    @Test func theFivePhasesAreInOrder() {
        #expect(ContourPhase.allCases == [.draw, .climb, .tilt, .fade, .loop])
        var seen: [ContourPhase] = []
        for i in 0..<4570 {
            let p = T.frame(at: Double(i) * 0.001, rings: 7).phase
            if seen.last != p { seen.append(p) }
        }
        #expect(seen == [.draw, .climb, .tilt, .fade, .loop])
    }

    @Test func timeIsWrappedIntoTheLoopAndTheLoopIndexCounts() {
        let p = T.period(rings: 7)
        #expect(T.frame(at: 0.3, rings: 7).loopIndex == 0)
        #expect(T.frame(at: p + 0.3, rings: 7).loopIndex == 1)
        #expect(T.frame(at: 5 * p + 0.3, rings: 7).loopIndex == 5)
        #expect(abs(T.frame(at: 5 * p + 0.3, rings: 7).time - 0.3) < 1e-9)
    }

    @Test func eachLoopRepeatsTheSameFrames() {
        let p = T.period(rings: 7)
        for i in 0..<197 {
            let t = Double(i) * 0.0231
            var a = T.frame(at: t, rings: 7), b = T.frame(at: t + 3 * p, rings: 7)
            #expect(b.loopIndex == 3)
            a.loopIndex = 0; b.loopIndex = 0
            #expect(a.phase == b.phase)
            #expect(abs(a.tiltDegrees - b.tiltDegrees) < 1e-6 && abs(a.opacity - b.opacity) < 1e-6)
            for k in 0..<7 { #expect(abs(a.ringTrims[k] - b.ringTrims[k]) < 1e-6) }
        }
    }

    @Test func splitSurvivesRoundingAtTheBoundary() {
        let p = T.period(rings: 7)
        for j in 0..<400 {
            let r = T.split(Double(j) * p, rings: 7)
            #expect(r.loop == j && r.time < 1e-9, "j=\(j) got \(r)")
            let before = T.split(Double(j) * p - 1e-6, rings: 7)
            #expect(before.loop == max(j - 1, -1) && before.time > p - 1e-5 || j == 0)
        }
        #expect(T.split(.nan, rings: 7) == (0, 0))
        #expect(T.split(-1, rings: 7).loop == -1)
    }

    @Test func badTimesAreSafe() {
        #expect(T.frame(at: .nan, rings: 7).time == 0)
        #expect(T.frame(at: .infinity, rings: 7).time == 0)
        #expect(T.frame(at: -.infinity, rings: 7).time == 0)
        let neg = T.frame(at: -0.2, rings: 7)
        #expect(neg.loopIndex == 0)
        #expect(abs(neg.time - (T.period(rings: 7) - 0.2)) < 1e-9)
        #expect(neg.phase == .loop)
        #expect(T.wrap(-1e-300, rings: 7) < T.period(rings: 7))
    }
}

@Suite struct DrawPhaseTests {
    @Test func atTheStartNothingIsDrawnAndThereIsNoNib() {
        let f = T.frame(at: 0, rings: 7)
        #expect(f.ringTrims == Array(repeating: 0, count: 7))
        #expect(f.nib == nil && f.routeFraction == nil && f.pulse == nil)
        #expect(f.opacity == 1 && f.tiltDegrees == 0)
    }

    @Test func theFirstRingIsDrawingBeforeTheSecondStarts() {
        let f = T.frame(at: 0.1, rings: 7)
        #expect(f.ringTrims[0] > 0 && f.ringTrims[0] < 1)
        #expect(f.ringTrims[1] == 0)
        #expect(f.nib == ContourNib(ring: 0, fraction: f.ringTrims[0]))
    }

    @Test func theNibRidesTheNewestRingStillDrawing() {
        for i in 1..<122 {
            let t = Double(i) * 0.01
            let f = T.frame(at: t, rings: 7)
            guard let nib = f.nib else { continue }
            #expect(f.ringTrims[nib.ring] > 0 && f.ringTrims[nib.ring] < 1)
            #expect(nib.fraction == f.ringTrims[nib.ring])
            for k in (nib.ring + 1)..<7 where k < 7 { #expect(f.ringTrims[k] == 0 || f.ringTrims[k] == 1) }
        }
    }

    @Test func theNibIsOnTheLastRingAtTheEnd() {
        let f = T.frame(at: T.drawDuration(rings: 7) - 0.05, rings: 7)
        #expect(f.nib?.ring == 6)
        #expect(f.ringTrims[0...5].allSatisfy { $0 == 1 })
    }

    @Test func midDrawSeveralRingsOverlapInDifferentStates() {
        let f = T.frame(at: 0.7, rings: 7)
        #expect(f.ringTrims[0] == 1 && f.ringTrims[1] == 1)
        #expect(f.ringTrims.contains { $0 > 0 && $0 < 1 })
        #expect(f.ringTrims.last == 0)
    }

    @Test func nibAppearsOnlyWhileDrawing() {
        for i in 0..<460 {
            let f = T.frame(at: Double(i) * 0.01, rings: 7)
            if f.phase != .draw { #expect(f.nib == nil) }
        }
    }

    @Test func aRingIsDrawnOutwardsInFirst() {
        let f = T.frame(at: 0.7, rings: 7)
        for k in 1..<7 { #expect(f.ringTrims[k] <= f.ringTrims[k - 1]) }
    }

    @Test func routeAndTiltAreIdleWhileDrawing() {
        for i in 0..<122 {
            let f = T.frame(at: Double(i) * 0.01, rings: 7)
            #expect(f.routeFraction == nil && f.tiltDegrees == 0 && f.opacity == 1 && f.pulse == nil)
        }
    }
}

@Suite struct ClimbTiltFadeTests {
    private var s: [Double] { T.phaseStarts(rings: 7) }

    @Test func everyRingStaysDrawnFromClimbThroughFade() {
        for t in stride(from: s[1], to: s[4], by: 0.05) {
            #expect(T.frame(at: t, rings: 7).ringTrims == Array(repeating: 1, count: 7))
        }
    }

    @Test func theDotStartsAtTheOuterRingAndEndsAtThePeak() {
        #expect(T.frame(at: s[1], rings: 7).routeFraction == 0)
        #expect(abs(T.frame(at: s[2] - 1e-9, rings: 7).routeFraction! - 1) < 1e-6)
        #expect(T.frame(at: s[2], rings: 7).routeFraction == 1)
    }

    @Test func theDotClimbsMonotonicallyWithEase() {
        var prev = -1.0
        var steps: [Double] = []
        for t in stride(from: s[1], to: s[2], by: 0.01) {
            let q = T.frame(at: t, rings: 7).routeFraction!
            #expect(q >= prev)
            if prev >= 0 { steps.append(q - prev) }
            prev = q
        }
        #expect(steps[0] < steps[steps.count / 2] / 5)
        #expect(steps.last! < steps[steps.count / 2] / 5)
        #expect(abs(T.frame(at: s[1] + T.climbDuration / 2, rings: 7).routeFraction! - 0.5) < 1e-9)
    }

    @Test func theDotStaysAtThePeakThroughTiltAndFade() {
        for t in stride(from: s[2], to: s[4], by: 0.05) { #expect(T.frame(at: t, rings: 7).routeFraction == 1) }
    }

    @Test func theDotIsHiddenWhileDrawingAndDuringTheLoopGap() {
        #expect(T.frame(at: 0.5, rings: 7).routeFraction == nil)
        #expect(T.frame(at: s[4] + 0.1, rings: 7).routeFraction == nil)
    }

    @Test func theSheetIsFlatUntilTheTiltStarts() {
        for t in stride(from: 0, to: s[2], by: 0.05) { #expect(T.frame(at: t, rings: 7).tiltDegrees == 0) }
        #expect(T.frame(at: s[2], rings: 7).tiltDegrees == 0)
    }

    @Test func theSheetTiltsToTwentyFiveDegreesAndRests() {
        #expect(abs(T.frame(at: s[2] + T.tiltRise, rings: 7).tiltDegrees - 25) < 1e-9)
        #expect(abs(T.frame(at: s[2] + T.tiltRise / 2, rings: 7).tiltDegrees - 12.5) < 1e-9)
        for t in stride(from: s[2] + T.tiltRise, to: s[4], by: 0.05) { #expect(abs(T.frame(at: t, rings: 7).tiltDegrees - 25) < 1e-9) }
        var prev = 0.0
        for t in stride(from: s[2], to: s[2] + T.tiltRise, by: 0.01) {
            let d = T.frame(at: t, rings: 7).tiltDegrees
            #expect(d >= prev && d <= 25)
            prev = d
        }
    }

    @Test func tiltIsEasedInAndOut() {
        #expect(T.tilt(inPhase: 0.02) < 0.02)
        #expect(25 - T.tilt(inPhase: T.tiltRise - 0.02) < 0.02)
        #expect(T.tilt(inPhase: -1) == 0)
        #expect(T.tilt(inPhase: 99) == 25)
    }

    @Test func theSheetIsFlatAgainWhenTheLoopRestarts() {
        #expect(T.frame(at: s[4] + 0.1, rings: 7).tiltDegrees == 0)
        #expect(T.frame(at: 0.01 + T.period(rings: 7), rings: 7).tiltDegrees == 0)
    }

    @Test func rippleRunsOnlyAtTheStartOfTheTilt() {
        #expect(T.frame(at: s[2], rings: 7).pulse == 0)
        #expect(abs(T.frame(at: s[2] + 0.25, rings: 7).pulse! - 0.5) < 1e-9)
        #expect(T.frame(at: s[2] + T.pulseDuration + 0.01, rings: 7).pulse == nil)
        #expect(T.frame(at: s[1] + 0.3, rings: 7).pulse == nil)
        #expect(T.frame(at: s[3] + 0.1, rings: 7).pulse == nil)
    }

    @Test func opacityIsFullUntilTheFade() {
        for t in stride(from: 0, to: s[3], by: 0.05) { #expect(T.frame(at: t, rings: 7).opacity == 1) }
    }

    @Test func theFadeGoesFromOneToZeroSmoothly() {
        #expect(T.frame(at: s[3], rings: 7).opacity == 1)
        #expect(T.frame(at: s[3] + T.fadeDuration - 1e-6, rings: 7).opacity < 1e-6)
        #expect(abs(T.frame(at: s[3] + T.fadeDuration / 2, rings: 7).opacity - 0.5) < 1e-9)
        var prev = 1.0
        for t in stride(from: s[3], to: s[4], by: 0.01) {
            let o = T.frame(at: t, rings: 7).opacity
            #expect(o <= prev)
            prev = o
        }
    }

    @Test func theBlankSheetFadesBackInDuringTheLoopGap() {
        #expect(T.frame(at: s[4], rings: 7).opacity == 0)
        #expect(T.frame(at: T.period(rings: 7) - 1e-6, rings: 7).opacity > 0.999)
        var prev = 0.0
        for t in stride(from: s[4], to: T.period(rings: 7), by: 0.01) {
            let f = T.frame(at: t, rings: 7)
            #expect(f.opacity >= prev && f.ringTrims == Array(repeating: 0, count: 7))
            prev = f.opacity
        }
    }

    @Test func nothingJumpsWhileVisible() {
        // between neighbouring frames the sheet never changes by much while it can be seen,
        // including across the tilt reset (opacity is ~0 there) and the loop restart (the sheet is blank)
        let dt = 1.0 / 240
        var prev = T.frame(at: 0, rings: 7)
        var t = dt
        while t < 2 * T.period(rings: 7) {
            let f = T.frame(at: t, rings: 7)
            #expect(abs(f.tiltDegrees - prev.tiltDegrees) < 0.5 || min(f.opacity, prev.opacity) < 0.01)
            #expect(abs(f.opacity - prev.opacity) < 0.05)
            for k in 0..<7 { #expect(abs(f.ringTrims[k] - prev.ringTrims[k]) < 0.1 || min(f.opacity, prev.opacity) < 0.01) }
            prev = f
            t += dt
        }
    }

    @Test func staticFrameIsAFinishedFlatMapWithTheDotAtThePeak() {
        let f = T.staticFrame(rings: 7)
        #expect(f.isStatic)
        #expect(f.ringTrims == Array(repeating: 1, count: 7))
        #expect(f.routeFraction == 1 && f.nib == nil && f.pulse == nil)
        #expect(f.tiltDegrees == 0 && f.opacity == 1)
        #expect(T.staticFrame(rings: 2).ringTrims.count == 3)
        #expect(!T.frame(at: 1, rings: 7).isStatic)
    }
}

@Suite struct CloseEventTests {
    private let p = T.period(rings: 7)

    @Test func ringsCloseInOrderThenTheDotArrives() {
        let ev = T.events(from: 0, to: p, rings: 7)
        #expect(ev == [.ringClosed(0), .ringClosed(1), .ringClosed(2), .ringClosed(3), .ringClosed(4), .ringClosed(5), .ringClosed(6), .dotArrived, .looped])
    }

    @Test func everyRingClosesExactlyOncePerLoop() {
        for n in 3...12 {
            let period = T.period(rings: n)
            let ev = T.events(from: 0, to: 4 * period, rings: n)
            for k in 0..<n { #expect(ev.filter { $0 == .ringClosed(k) }.count == 4, "n=\(n) ring \(k)") }
            #expect(ev.filter { $0 == .dotArrived }.count == 4)
            #expect(ev.filter { $0 == .looped }.count == 4)
            #expect(ev.count == 4 * (n + 2))
        }
    }

    @Test func exactlyOnceHoldsHoweverTheTimeIsCut() {
        for step in [1.0 / 240, 1.0 / 120, 1.0 / 60, 1.0 / 30, 0.0173, 0.1, 0.25, 0.5, 1.7, 4.57, 9.9] {
            var t = 0.0
            var counts = [Int](repeating: 0, count: 7), arrivals = 0, loops = 0
            while t < 3 * p {
                let ev = T.events(from: t, to: min(t + step, 3 * p), rings: 7)
                for e in ev {
                    switch e {
                    case .ringClosed(let k): counts[k] += 1
                    case .dotArrived: arrivals += 1
                    case .looped: loops += 1
                    }
                }
                t += step
            }
            #expect(counts == [Int](repeating: 3, count: 7), "step \(step)")
            #expect(arrivals == 3 && loops == 3, "step \(step)")
        }
    }

    @Test func cuttingAnIntervalAnywhereGivesTheSameEvents() {
        let whole = T.events(from: 0.3, to: 17.1, rings: 7)
        var cuts: [ContourEvent] = []
        let edges = [0.3, 0.31, 1.0, 1.22, 1.221, 2.0, 2.42, 4.57, 4.5701, 9.14, 13.5, 17.1]
        for (a, b) in zip(edges, edges.dropFirst()) { cuts += T.events(from: a, to: b, rings: 7) }
        #expect(cuts == whole)
    }

    @Test func theUpperEdgeIsInclusiveAndTheLowerIsNot() {
        let c = T.closeTime(ring: 2)
        #expect(T.events(from: c - 0.01, to: c, rings: 7) == [.ringClosed(2)])
        #expect(T.events(from: c, to: c + 0.01, rings: 7).isEmpty)
        #expect(T.events(from: c - 0.01, to: c - 0.001, rings: 7).isEmpty)
    }

    @Test func theLoopEventFiresAtEachWrapButNotAtTheStart() {
        #expect(!T.events(from: -1, to: 0.001, rings: 7).contains(.looped))
        #expect(T.events(from: p - 0.01, to: p, rings: 7) == [.looped])
        #expect(T.events(from: p, to: p + 0.01, rings: 7).isEmpty)
        #expect(T.events(from: 2 * p - 0.01, to: 2 * p + 0.2, rings: 7).first == .looped)
    }

    @Test func eventsInTheLoopHappenWhenTheirPhasesDo() {
        let s = T.phaseStarts(rings: 7)
        #expect(T.events(from: s[1] - 0.001, to: s[1], rings: 7) == [.ringClosed(6)])
        #expect(T.events(from: s[2] - 0.001, to: s[2], rings: 7) == [.dotArrived])
        #expect(abs(T.arrivalTime(rings: 7) - s[2]) < eps)
    }

    @Test func degenerateIntervalsGiveNothing() {
        #expect(T.events(from: 1, to: 1, rings: 7).isEmpty)
        #expect(T.events(from: 5, to: 4, rings: 7).isEmpty)
        #expect(T.events(from: 0, to: .nan, rings: 7).isEmpty)
        #expect(T.events(from: .nan, to: 3, rings: 7).isEmpty)
        #expect(T.events(from: 0, to: .infinity, rings: 7).isEmpty)
        #expect(T.events(from: -5, to: -1, rings: 7).isEmpty)
        #expect(T.events(from: -3, to: 0.55, rings: 7) == [.ringClosed(0)])
    }

    @Test func aHugeStepCountsEveryLoop() {
        let ev = T.events(from: 0, to: 100 * p, rings: 7)
        #expect(ev.filter { $0 == .ringClosed(3) }.count == 100)
    }

    @Test func eventOrderIsChronological() {
        let ev = T.events(from: 0, to: 3 * p, rings: 7)
        func when(_ e: ContourEvent, _ j: Int) -> Double {
            switch e {
            case .ringClosed(let k): return Double(j) * p + T.closeTime(ring: k)
            case .dotArrived: return Double(j) * p + T.arrivalTime(rings: 7)
            case .looped: return Double(j) * p
            }
        }
        var j = 0
        var prev = -1.0
        for e in ev {
            if e == .looped { j += 1 }
            let w = when(e, j)
            #expect(w >= prev)
            prev = w
        }
    }

    @Test func momentsListsLoopStartRingsAndArrival() {
        let m = T.moments(rings: 7)
        #expect(m.count == 9)
        #expect(m[0].event == .looped && m[0].offset == 0)
        #expect(m.last?.event == .dotArrived)
        #expect(zip(m, m.dropFirst()).allSatisfy { $0.offset <= $1.offset })
    }
}
