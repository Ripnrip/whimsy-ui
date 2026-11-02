import Testing
import Foundation
@testable import ContourInkCore

private func run(_ m: inout ContourInkModel, seconds: Double, dt: Double = 1.0 / 60) -> [ContourEvent] {
    var out: [ContourEvent] = []
    var t = 0.0
    while t < seconds - 1e-12 { out += m.step(dt); t += dt }
    return out
}

@Suite struct ModelBasicsTests {
    @Test func startsAtTheBeginningOfTheLoop() {
        let m = ContourInkModel()
        #expect(m.rings == 7 && m.time == 0)
        #expect(m.frame.phase == .draw && !m.frame.isStatic && m.frame.ringTrims.allSatisfy { $0 == 0 })
        #expect(m.ringsClosed == 0 && m.arrivals == 0 && m.loops == 0)
        #expect(abs(m.period - 4.57) < 1e-9)
    }

    @Test func ringCountIsClamped() {
        #expect(ContourInkModel(rings: 0).rings == 3)
        #expect(ContourInkModel(rings: 100).rings == 12)
        #expect(ContourInkModel(rings: 6).rings == 6)
    }

    @Test func stepAdvancesTime() {
        var m = ContourInkModel()
        m.step(0.1); m.step(0.05)
        #expect(abs(m.time - 0.15) < 1e-12)
        #expect(m.frame.phase == .draw && m.frame.ringTrims[0] > 0)
    }

    @Test func stepsAreClampedAndBadStepsAreIgnored() {
        var m = ContourInkModel()
        m.step(10)
        #expect(m.time == ContourInkModel.maxStep)
        m.step(.nan); m.step(-1); m.step(.infinity)
        #expect(m.time == ContourInkModel.maxStep)
        var n = ContourInkModel()
        #expect(n.step(.nan).isEmpty && n.step(-5).isEmpty && n.step(0).isEmpty)
        #expect(n.time == 0)
    }

    @Test func stepReturnsTheEventsOfThatStep() {
        var m = ContourInkModel()
        let first = run(&m, seconds: 0.55)
        #expect(first == [.ringClosed(0)])
        let more = run(&m, seconds: 0.35)
        #expect(more == [.ringClosed(1), .ringClosed(2), .ringClosed(3)])
        #expect(m.ringsClosed == 4)
    }

    @Test func aSingleStepCanCloseSeveralRings() {
        var m = ContourInkModel()
        m.step(0.25); m.step(0.25)
        #expect(m.ringsClosed == 1)
        let ev = m.step(0.25)
        #expect(ev == [.ringClosed(1), .ringClosed(2)])
        #expect(m.ringsClosed == 3)
    }

    @Test func countersTrackTheEvents() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 2.6)
        #expect(m.ringsClosed == 7 && m.arrivals == 1 && m.loops == 0)
        _ = run(&m, seconds: 2.1)
        #expect(m.loops == 1)
    }
}

@Suite struct ModelLoopTests {
    @Test func everyRingTicksExactlyOncePerLoopAtAnyFrameRate() {
        for dt in [1.0 / 120, 1.0 / 60, 1.0 / 30, 0.0173, 0.1, 0.25] {
            var m = ContourInkModel()
            let ev = run(&m, seconds: 3 * m.period + 0.0001, dt: dt)
            for k in 0..<7 { #expect(ev.filter { $0 == .ringClosed(k) }.count == 3, "dt \(dt) ring \(k)") }
            #expect(m.ringsClosed == 21 && m.arrivals == 3)
            #expect(m.loops >= 2 && m.loops <= 3)
        }
    }

    @Test func everyRingTicksOncePerLoopWithIrregularSteps() {
        var m = ContourInkModel(rings: 7)
        var rng = SeededRandom(seed: 42)
        var counts = [Int](repeating: 0, count: 7)
        while m.time < 5 * m.period {
            for e in m.step(rng.double(in: 0.001...0.2)) { if case .ringClosed(let k) = e { counts[k] += 1 } }
        }
        let done = Int(m.time / m.period)
        for k in 0..<7 {
            let closedThisLoop = ContourInkTimeline.closeTime(ring: k) <= m.time - Double(done) * m.period ? 1 : 0
            #expect(counts[k] == done + closedThisLoop)
        }
    }

    @Test func eachCountOfRingsTicksThatManyTimesPerLoop() {
        for n in [3, 4, 6, 7, 9, 12] {
            var m = ContourInkModel(rings: n)
            let ev = run(&m, seconds: m.period, dt: 1.0 / 60)
            #expect(ev.filter { if case .ringClosed = $0 { return true } else { return false } }.count == n)
        }
    }

    @Test func theTickComesWhenTheRingIsDrawn() {
        var m = ContourInkModel()
        var tickAt: [Double] = []
        while m.time < 1.5 {
            let ev = m.step(1.0 / 120)
            if ev.contains(where: { if case .ringClosed = $0 { return true } else { return false } }) { tickAt.append(m.time) }
        }
        #expect(tickAt.count == 7)
        for (k, t) in tickAt.enumerated() { #expect(abs(t - ContourInkTimeline.closeTime(ring: k)) <= 1.0 / 120 + 1e-9) }
    }

    @Test func theLoopRestartsAndRepeatsWithoutDrift() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 2 * m.period + 0.5, dt: 1.0 / 60)
        #expect(m.frame.loopIndex == 2)
        #expect(m.frame.phase == .draw)
        #expect(m.loops == 2)
    }

    @Test func aStalledTimelineDoesNotSkipTheLoop() {
        var m = ContourInkModel()
        var counts = 0
        for _ in 0..<40 { counts += m.step(5).filter { if case .ringClosed = $0 { return true } else { return false } }.count }
        // each 5 s gap becomes one 0.25 s step: 40 steps = 10 s of running time = just over two loops
        #expect(abs(m.time - 10) < 1e-9)
        #expect(counts == 7 * Int(10 / m.period) + ContourInkTimeline.events(from: 0, to: 10 - m.period * Double(Int(10 / m.period)), rings: 7).filter { if case .ringClosed = $0 { return true } else { return false } }.count)
    }

    @Test func twoModelsWithTheSameStepsAgree() {
        var a = ContourInkModel(), b = ContourInkModel()
        var rng = SeededRandom(seed: 7)
        for _ in 0..<800 {
            let dt = rng.double(in: 0...0.3)
            #expect(a.step(dt) == b.step(dt))
        }
        #expect(a == b)
    }
}

@Suite struct ModelStaticTests {
    @Test func reduceMotionShowsTheFinishedMapAndDoesNotRun() {
        var m = ContourInkModel(reduceMotion: true)
        #expect(m.isStatic)
        #expect(m.frame.isStatic && m.frame.routeFraction == 1 && m.frame.ringTrims.allSatisfy { $0 == 1 })
        #expect(m.step(1).isEmpty)
        #expect(m.time == 0 && m.ringsClosed == 0)
    }

    @Test func notAnimatingShowsTheFinishedMapToo() {
        var m = ContourInkModel(isAnimating: false)
        #expect(m.isStatic && m.frame.isStatic)
        #expect(m.step(0.2).isEmpty && m.time == 0)
        #expect(m.frame.tiltDegrees == 0 && m.frame.opacity == 1)
    }

    @Test func startingToAnimateRestartsTheLoop() {
        var m = ContourInkModel(isAnimating: false)
        m.update(isAnimating: true, reduceMotion: false)
        #expect(!m.isStatic && m.time == 0)
        #expect(m.frame.phase == .draw)
        _ = run(&m, seconds: 1)
        #expect(m.ringsClosed > 0)
    }

    @Test func turningReduceMotionOnFreezesAndOffRestarts() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 1)
        let t = m.time
        m.update(isAnimating: true, reduceMotion: true)
        #expect(m.isStatic && m.frame.isStatic)
        #expect(m.step(1).isEmpty && m.time == t)
        m.update(isAnimating: true, reduceMotion: false)
        #expect(m.time == 0 && m.ringsClosed == 0 && m.frame.phase == .draw)
    }

    @Test func updatingWithTheSameSwitchesChangesNothing() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 1)
        let before = m
        m.update(isAnimating: true, reduceMotion: false)
        #expect(m == before)
        var s = ContourInkModel(isAnimating: false)
        s.update(isAnimating: false, reduceMotion: false)
        #expect(s.time == 0 && s.isStatic)
    }

    @Test func restartClearsTheCounters() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 5)
        m.restart()
        #expect(m.time == 0 && m.ringsClosed == 0 && m.arrivals == 0 && m.loops == 0)
    }

    @Test func stoppingAnimationMidwayThenRunningStartsFresh() {
        var m = ContourInkModel()
        _ = run(&m, seconds: 2)
        m.update(isAnimating: false, reduceMotion: false)
        m.update(isAnimating: true, reduceMotion: false)
        #expect(m.time == 0)
    }
}
