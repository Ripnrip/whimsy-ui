import Testing
import Foundation
@testable import StarJarCore

@Suite("Stars") struct StarTests {
    @Test(arguments: [8, 20, 40, 64, 80])
    func countIsHonoured(_ n: Int) {
        #expect(StarJarModel(starCount: n).stars.count == n)
    }
    @Test(arguments: [(-5, 8), (0, 8), (3, 8), (81, 80), (1000, 80)])
    func countIsClamped(_ c: (Int, Int)) {
        #expect(StarJarModel(starCount: c.0).stars.count == c.1)
        #expect(StarJarModel.clampedCount(c.0) == c.1)
    }
    @Test(arguments: [UInt32(0), 1, 0x57A2, 0xDEADBEEF, 12345])
    func startsInsideAndAtRest(_ seed: UInt32) {
        let m = StarJarModel(seed: seed)
        #expect(m.allInside)
        #expect(m.isAtRest)
        #expect(m.phase == .asleep && m.time == 0)
    }
    @Test func startsSettledInTheBottom() {
        let m = StarJarModel()
        #expect(m.meanY > 290)
        #expect(m.stars.allSatisfy { $0.y > StarJarGeometry.bodyCenter.y })
    }
    @Test func sameSeedSameStars() {
        #expect(StarJarModel(seed: 9) == StarJarModel(seed: 9))
        #expect(StarJarModel(seed: 9) != StarJarModel(seed: 10))
    }
    @Test func starAttributesInRange() {
        for s in StarJarModel(starCount: 80).stars {
            #expect(s.radius >= 4.5 && s.radius <= 7.5)
            #expect(s.frequency >= 0.35 && s.frequency <= 1.25)
            #expect(s.phase >= 0 && s.phase < 2 * .pi && s.phase2 >= 0 && s.phase2 < 2 * .pi)
            #expect(s.wanderFrequencies.count == 4 && s.wanderPhases.count == 4)
            #expect(s.wanderFrequencies.allSatisfy { $0 >= 0.5 && $0 <= 1.8 })
            #expect(s.hue >= 0 && s.hue < 1)
        }
    }
    @Test func eachStarHasItsOwnRhythm() {
        let fs = Set(StarJarModel().stars.map(\.frequency))
        #expect(fs.count == 40)
    }
    @Test func indicesAreSequential() {
        #expect(StarJarModel().stars.map(\.index) == Array(0..<40))
    }
}

@Suite("State machine") struct StateTests {
    @Test func tapJarWakes() {
        var m = StarJarModel()
        #expect(m.tap(x: 150, y: 250) == [.waking])
        #expect(m.phase == .waking && m.isScrollLocked && m.isEngaged)
        let ev = m.run(0.7)
        #expect(phaseEvents(ev) == [.awake])
        #expect(m.phase == .awake && m.wake == 1)
    }
    @Test func tapCorkWakes() {
        var m = StarJarModel()
        #expect(m.tap(x: StarJarGeometry.cork.midX, y: StarJarGeometry.cork.midY) == [.waking])
    }
    @Test(arguments: [(5.0, 5.0), (10, 300), (290, 200), (-50, -50), (150, 339.5)])
    func tapOutsideWhileAsleepDoesNothing(_ p: (Double, Double)) {
        var m = StarJarModel()
        #expect(m.tap(x: p.0, y: p.1).isEmpty)
        #expect(m.phase == .asleep && !m.isScrollLocked)
    }
    @Test(arguments: [(5.0, 5.0), (10, 300), (290, 200), (-50, -50)])
    func tapOutsideWhileAwakeSleeps(_ p: (Double, Double)) {
        var m = awakeModel()
        #expect(m.tap(x: p.0, y: p.1) == [.settling])
        #expect(m.phase == .settling && m.isScrollLocked && !m.isEngaged)
    }
    @Test func doneChipSleeps() {
        var m = awakeModel()
        let c = StarJarGeometry.doneChip
        #expect(m.tap(x: c.midX, y: c.midY) == [.settling])
    }
    @Test func doneChipWhileAsleepDoesNothing() {
        var m = StarJarModel()
        let c = StarJarGeometry.doneChip
        #expect(m.tap(x: c.midX, y: c.midY).isEmpty)
    }
    @Test func tapJarWhileAwakeIsNoOp() {
        var m = awakeModel()
        #expect(m.tap(x: 150, y: 220).isEmpty)
        #expect(m.phase == .awake)
    }
    @Test func settleTakesAboutOneAndAHalfSeconds() {
        var m = awakeModel()
        _ = m.sleep()
        var ev = m.run(1.4)
        #expect(m.phase == .settling && m.isScrollLocked)
        ev += m.run(0.2)
        #expect(phaseEvents(ev) == [.asleep])
        #expect(m.phase == .asleep && !m.isScrollLocked)
    }
    @Test func wakeTakesWakeDuration() {
        var m = StarJarModel()
        _ = m.wakeUp()
        m.run(0.5)
        #expect(m.phase == .waking)
        m.run(0.15)
        #expect(m.phase == .awake)
    }
    @Test func wakeDuringSettleResumesFromCurrentLevel() {
        var m = awakeModel()
        _ = m.sleep()
        m.run(0.75)
        let w = m.wake
        #expect(w > 0.2 && w < 0.8)
        #expect(m.tap(x: 150, y: 250) == [.waking])
        #expect(abs(m.wake - w) < 1e-9)
        #expect(m.wakeFrom == w)
    }
    @Test func sleepDuringWakeResumesFromCurrentLevel() {
        var m = StarJarModel()
        _ = m.wakeUp()
        m.run(0.2)
        let w = m.wake
        _ = m.sleep()
        #expect(abs(m.wake - w) < 1e-9)
    }
    @Test func wakeIsMonotoneUpThenDown() {
        var m = StarJarModel()
        _ = m.wakeUp()
        var last = 0.0
        for _ in 0..<40 { m.run(1.0 / 60); #expect(m.wake >= last - 1e-12); last = m.wake }
        _ = m.sleep()
        for _ in 0..<100 { m.run(1.0 / 60); #expect(m.wake <= last + 1e-12); last = m.wake }
        #expect(m.wake == 0)
    }
    @Test func setEngagedMirrorsBinding() {
        var m = StarJarModel()
        #expect(m.setEngaged(true) == [.waking])
        #expect(m.setEngaged(true).isEmpty)
        #expect(m.setEngaged(false) == [.settling])
        #expect(m.setEngaged(false).isEmpty)
    }
    @Test func countersTrackTransitions() {
        var m = StarJarModel()
        _ = m.wakeUp(); _ = m.sleep(); _ = m.wakeUp()
        #expect(m.wakes == 2 && m.sleeps == 1)
    }
    @Test func nonFiniteTapIgnored() {
        var m = StarJarModel()
        #expect(m.tap(x: .nan, y: 100).isEmpty)
        #expect(m.tap(x: 100, y: .infinity).isEmpty)
    }
    @Test func sleepClearsTouch() {
        var m = awakeModel()
        m.touchBegan(x: 150, y: 200)
        _ = m.sleep()
        #expect(m.touch == nil)
    }
    @Test func scrollLockFollowsPhase() {
        for p in StarJarPhase.allCases {
            var m = StarJarModel()
            switch p {
            case .asleep: break
            case .waking: _ = m.wakeUp()
            case .awake: m = awakeModel()
            case .settling: m = awakeModel(); _ = m.sleep()
            }
            #expect(m.phase == p)
            #expect(m.isScrollLocked == (p != .asleep))
        }
    }
}

@Suite("Simulation") struct SimTests {
    @Test(arguments: [UInt32(1), 7, 0x57A2, 99999])
    func staysInsideThroughAFullSession(_ seed: UInt32) {
        var m = StarJarModel(seed: seed)
        _ = m.wakeUp()
        for _ in 0..<180 { m.run(1.0 / 60); #expect(m.allInside) }
        _ = swirl(&m, seconds: 2)
        #expect(m.allInside)
        _ = m.sleep()
        for _ in 0..<120 { m.run(1.0 / 60); #expect(m.allInside) }
    }
    @Test func wakingLiftsStars() {
        var m = StarJarModel()
        let rest = m.meanY
        _ = m.wakeUp()
        m.run(3)
        #expect(m.meanY < rest - 40)
        #expect(m.stars.map(\.y).min()! < StarJarGeometry.bodyCenter.y - 40)
    }
    @Test func starsKeepDriftingWhileAwake() {
        var m = awakeModel()
        m.run(3)
        let a = m.stars.map { ($0.x, $0.y) }
        m.run(1)
        let moved = zip(a, m.stars).filter { hypot($0.0.0 - $0.1.x, $0.0.1 - $0.1.y) > 5 }.count
        #expect(moved > 20)
    }
    @Test func settlingReturnsToBottomAndRests() {
        var m = awakeModel()
        m.run(2)
        _ = m.sleep()
        m.run(1.6)
        #expect(m.phase == .asleep)
        var frames = 0
        while !m.isAtRest && frames < 900 { m.run(1.0 / 60); frames += 1 }
        #expect(m.isAtRest)
        #expect(m.meanY > 290)
    }
    @Test func asleepModelStaysFrozen() {
        var m = StarJarModel()
        let before = m.stars
        m.run(2)
        #expect(m.stars == before)
        #expect(m.time > 1.99)
    }
    @Test func deterministicAcrossFrameRates() {
        // Same total time in steps that are multiples of the substep gives identical states.
        var a = StarJarModel(), b = StarJarModel()
        _ = a.wakeUp(); _ = b.wakeUp()
        for _ in 0..<120 { _ = a.step(1.0 / 60) }
        for _ in 0..<60 { _ = b.step(1.0 / 30) }
        #expect(a.stars == b.stars)
    }
    @Test func deterministicReplay() {
        func session() -> StarJarModel {
            var m = StarJarModel(seed: 4242)
            _ = m.tap(x: 150, y: 250)
            m.run(1)
            _ = swirl(&m, seconds: 1)
            _ = m.tap(x: 5, y: 5)
            m.run(1)
            return m
        }
        #expect(session() == session())
    }
    @Test func remainderCarriesOver() {
        var m = StarJarModel()
        _ = m.wakeUp()
        _ = m.step(0.004)
        #expect(m.time == 0)
        _ = m.step(0.005)
        #expect(abs(m.time - StarJarModel.substep) < 1e-12)
    }
    @Test(arguments: [-1.0, .nan, .infinity, -.infinity])
    func badStepsAreHarmless(_ dt: Double) {
        var m = awakeModel()
        let t = m.time
        _ = m.step(dt)
        #expect(m.time <= t + StarJarModel.maxStep + 1e-9)
        #expect(m.stars.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
    @Test func hugeStepIsClamped() {
        var m = awakeModel()
        let t = m.time
        _ = m.step(10)
        #expect(m.time - t <= StarJarModel.maxStep + 1e-9)
    }
    @Test func speedsAreCapped() {
        var m = awakeModel()
        m.touchBegan(x: 150, y: 212)
        for k in 0..<120 { m.touchMoved(x: 150 + (k % 2 == 0 ? 80 : -80), y: 212, at: m.time); _ = m.step(1.0 / 60) }
        #expect(m.fastest <= StarJarModel.maxSpeed + 1e-9)
        #expect(m.allInside)
    }
    @Test func starsDoNotPileIntoOnePoint() {
        var m = awakeModel()
        m.run(3)
        var close = 0
        for i in 0..<m.stars.count { for j in (i + 1)..<m.stars.count {
            if hypot(m.stars[i].x - m.stars[j].x, m.stars[i].y - m.stars[j].y) < 2 { close += 1 }
        } }
        #expect(close == 0)
    }
    @Test(arguments: [8, 80])
    func extremeCountsStayInside(_ n: Int) {
        var m = StarJarModel(starCount: n)
        #expect(m.allInside)
        _ = m.wakeUp(); m.run(3)
        #expect(m.allInside)
    }
}

@Suite("Stirring") struct StirTests {
    @Test func swirlIsTangential() {
        let a = StarJarModel.stir(x: 160, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (0, 0))
        #expect(abs(a.x) < 1e-9)
        #expect(a.y > 0)          // star to the right of the finger is pushed "down" (clockwise in screen coords)
    }
    @Test func stirFallsOffWithDistance() {
        let near = StarJarModel.stir(x: 160, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (0, 0))
        let mid = StarJarModel.stir(x: 210, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (0, 0))
        let far = StarJarModel.stir(x: 400, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (0, 0))
        #expect(hypot(near.x, near.y) > hypot(mid.x, mid.y))
        #expect(far.x == 0 && far.y == 0)
    }
    @Test func stirFollowsFingerVelocity() {
        let a = StarJarModel.stir(x: 150, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (100, 0))
        #expect(a.x > 0)
        let b = StarJarModel.stir(x: 150, y: 200, vx: 100, vy: 0, finger: (150, 200), fingerVelocity: (100, 0))
        #expect(abs(b.x) < 1e-9)
    }
    @Test func stirAtFingerIsFinite() {
        let a = StarJarModel.stir(x: 150, y: 200, vx: 0, vy: 0, finger: (150, 200), fingerVelocity: (0, 0))
        #expect(a.x.isFinite && a.y.isFinite)
    }
    @Test func swirlingSpinsStarsAround() {
        var a = awakeModel(), b = awakeModel()
        _ = swirl(&a, seconds: 1.5)
        b.run(1.5)
        #expect(a.stars.map(\.speed).reduce(0, +) > b.stars.map(\.speed).reduce(0, +) * 1.3)
    }
    @Test func touchIgnoredWhileAsleep() {
        var m = StarJarModel()
        let before = m.stars
        _ = swirl(&m, seconds: 1)
        #expect(m.stars == before)
    }
    @Test func touchVelocityIsSmoothed() {
        var m = awakeModel()
        m.touchBegan(x: 100, y: 200)
        m.touchMoved(x: 110, y: 200, at: m.time + 0.1)
        #expect(abs(m.touchVelocity.x - 50) < 1e-9)     // half of 100 pt/s
        m.touchEnded()
        #expect(m.touch == nil && m.touchVelocity.x == 0)
    }
    @Test func reduceMotionDisablesStir() {
        var a = awakeModel(reduce: true), b = awakeModel(reduce: true)
        _ = swirl(&a, seconds: 1)
        b.run(1)
        #expect(a.stars == b.stars)
    }
}

@Suite("Brush haptics") struct BrushTests {
    @Test func swirlingProducesBrushes() {
        var m = awakeModel()
        let ev = swirl(&m, seconds: 3)
        #expect(brushTimes(ev) > 3)
        #expect(m.brushes >= brushTimes(ev))
    }
    @Test func brushesAreRateLimited() {
        var m = awakeModel()
        var times: [Double] = []
        m.touchBegan(x: 200, y: 212)
        for k in 0..<360 {
            let a = Double(k) * 0.25
            m.touchMoved(x: 150 + 80 * cos(a), y: 212 + 80 * sin(a), at: m.time)
            for e in m.step(1.0 / 60) { if case .brush = e { times.append(m.time) } }
        }
        #expect(times.count > 3)
        // At most one per 80 ms (frame-time granularity: brushes inside one frame are impossible to repeat).
        #expect(times.count <= Int(6.0 / StarJarModel.brushInterval) + 1)
        for (a, b) in zip(times, times.dropFirst()) { #expect(b - a >= StarJarModel.brushInterval - 1.0 / 60 - 1e-9) }
    }
    @Test func brushSpeedsAreAboveThreshold() {
        var m = awakeModel()
        for e in swirl(&m, seconds: 3) {
            if case let .brush(star, speed) = e {
                #expect(speed > StarJarModel.brushSpeed)
                #expect(m.stars.indices.contains(star))
            }
        }
    }
    @Test func noBrushesWhileAsleepOrSettlingLate() {
        var m = awakeModel()
        _ = swirl(&m, seconds: 1)
        _ = m.sleep()
        m.run(1.0)                            // wake ≈ 0.26 < 0.3 from here
        let ev = m.run(3)
        #expect(brushTimes(ev) == 0)
    }
    @Test func noBrushesFromRestingHeap() {
        var m = StarJarModel()
        #expect(brushTimes(m.run(3)) == 0)
    }
    @Test func reduceMotionWakeIsQuiet() {
        var m = StarJarModel(reduceMotion: true)
        _ = m.wakeUp()
        #expect(brushTimes(m.run(3)) == 0)
    }
}

@Suite("Twinkle & Reduce Motion") struct TwinkleTests {
    let star = StarJarModel().stars[3]
    @Test(arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func brightnessInUnitRange(_ w: Double) {
        for k in 0..<200 {
            let b = StarJarModel.brightness(star, time: Double(k) * 0.05, wake: w, reduceMotion: false)
            #expect(b >= 0 && b <= 1)
        }
    }
    @Test func asleepIsDim() {
        for k in 0..<100 { #expect(StarJarModel.brightness(star, time: Double(k) * 0.1, wake: 0, reduceMotion: false) < 0.2) }
    }
    @Test func awakeIsBrightAndTwinkles() {
        let bs = (0..<200).map { StarJarModel.brightness(star, time: Double($0) * 0.03, wake: 1, reduceMotion: false) }
        #expect(bs.max()! > 0.8)
        #expect(bs.max()! - bs.min()! > 0.25)
    }
    @Test func starsTwinkleOutOfStep() {
        let s = StarJarModel().stars
        let at = s.map { StarJarModel.brightness($0, time: 1.7, wake: 1, reduceMotion: false) }
        #expect(Set(at.map { ($0 * 1000).rounded() }).count > 20)
    }
    @Test func reduceMotionIsSteady() {
        let bs = (0..<100).map { StarJarModel.brightness(star, time: Double($0) * 0.07, wake: 1, reduceMotion: true) }
        #expect(bs.allSatisfy { abs($0 - 0.72) < 1e-12 })
    }
    @Test func reduceMotionHasNoWander() {
        func drift(_ reduce: Bool) -> Double {
            var m = StarJarModel(reduceMotion: reduce)
            _ = m.wakeUp()
            m.run(2)
            let a = m.stars
            m.run(1)
            return zip(a, m.stars).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +)
        }
        #expect(drift(true) < drift(false) * 0.2)
    }
    @Test func reduceMotionShortensTransitions() {
        var m = StarJarModel(reduceMotion: true)
        _ = m.wakeUp(); m.run(0.35)
        #expect(m.phase == .awake)
        _ = m.sleep(); m.run(0.65)
        #expect(m.phase == .asleep)
    }
    @Test func togglingReduceMotionJumpsTransitions() {
        var m = StarJarModel()
        _ = m.wakeUp(); m.run(0.1)
        m.setReduceMotion(true)
        #expect(m.phase == .awake)
        _ = m.sleep(); m.run(0.1)
        m.setReduceMotion(false); m.setReduceMotion(true)
        #expect(m.phase == .asleep)
    }
    @Test func instanceBrightnessGuardsIndex() {
        let m = StarJarModel()
        #expect(m.brightness(-1) == 0 && m.brightness(999) == 0)
        #expect(m.brightness(0) > 0)
    }
}
